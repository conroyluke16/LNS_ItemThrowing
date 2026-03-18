local Settings = lib.load('shared.settings')
local activeProps = {}
local cooldowns = {}

local itemFilter = {}
for itemName, _ in pairs(Settings.ItemModels) do
    itemFilter[itemName] = true
end

local function onCooldown(src)
    local last = cooldowns[src]
    return last and (GetGameTimer() - last) < Settings.CooldownTime
end

local function destroyProp(propId)
    local prop = activeProps[propId]
    if not prop then return end

    if prop.netId then
        TriggerClientEvent('LNS_ItemThrowing:removeProp', -1, prop.netId)
    end

    activeProps[propId] = nil
end

local function validateAmount(source, slot, amount)
    amount = tonumber(amount) or 1
    if amount < 1 then return false end

    local item = exports.ox_inventory:GetSlot(source, slot)
    if not item or item.count < amount then
        return false
    end

    return amount
end

lib.callback.register('LNS_ItemThrowing:createProp', function(source, data)
    if not data or not data.itemName or not data.coords or not data.slot or not data.netId then
        return false
    end

    if onCooldown(source) then
        lib.notify(source, { type = 'error', description = 'Please wait before throwing again' })
        return false
    end

    local amount = validateAmount(source, data.slot, data.amount)
    if not amount then
        lib.notify(source, { type = 'error', description = 'Invalid item amount' })
        return false
    end

    local ped = GetPlayerPed(source)
    local pedCoords = GetEntityCoords(ped)

    if #(pedCoords - data.coords) > Settings.MaxThrowDistance then
        lib.notify(source, { type = 'error', description = 'Invalid throw distance' })
        return false
    end

    if not Settings.ItemModels[data.itemName] then
        lib.notify(source, { type = 'error', description = 'This item cannot be thrown' })
        return false
    end

    if not exports.ox_inventory:RemoveItem(source, data.itemName, amount, nil, data.slot) then
        lib.notify(source, { type = 'error', description = 'Failed to throw item' })
        return false
    end

    cooldowns[source] = GetGameTimer()

    local propId = ('thrown_%d_%d'):format(math.random(100000, 999999), os.time())
    activeProps[propId] = {
        netId = data.netId,
        itemName = data.itemName,
        coords = data.coords,
        amount = amount,
        metadata = data.metadata
    }

    TriggerClientEvent('LNS_ItemThrowing:registerTarget', -1, propId, data.netId)

    SetTimeout(Settings.PropLifetime, function()
        destroyProp(propId)
    end)

    return true, propId
end)

lib.callback.register('LNS_ItemThrowing:placeItem', function(source, data)
    if not data or not data.itemName or not data.coords or not data.slot or not data.propModel then
        return false
    end

    if onCooldown(source) then
        lib.notify(source, { type = 'error', description = 'Please wait before placing again' })
        return false
    end

    local amount = validateAmount(source, data.slot, data.amount)
    if not amount then
        lib.notify(source, { type = 'error', description = 'Invalid item amount' })
        return false
    end

    local ped = GetPlayerPed(source)
    local pedCoords = GetEntityCoords(ped)

    if #(pedCoords - data.coords) > Settings.MaxPlaceDistance then
        lib.notify(source, { type = 'error', description = 'Invalid placement distance' })
        return false
    end

    if Settings.ItemModels[data.itemName] ~= data.propModel then
        lib.notify(source, { type = 'error', description = 'Invalid item model' })
        return false
    end

    if not exports.ox_inventory:RemoveItem(source, data.itemName, amount, nil, data.slot) then
        lib.notify(source, { type = 'error', description = 'Failed to place item' })
        return false
    end

    cooldowns[source] = GetGameTimer()

    local propId = ('placed_%d_%d'):format(math.random(100000, 999999), os.time())
    activeProps[propId] = {
        netId = nil,
        itemName = data.itemName,
        coords = data.coords,
        amount = amount,
        metadata = data.metadata
    }

    TriggerClientEvent('LNS_ItemThrowing:createPlacedProp', source, {
        propId = propId,
        coords = data.coords,
        rotation = data.rotation,
        itemName = data.itemName,
        propModel = data.propModel
    })

    SetTimeout(Settings.PropLifetime, function()
        destroyProp(propId)
    end)

    return true, propId
end)

lib.callback.register('LNS_ItemThrowing:pickupItem', function(source, propId)
    local prop = activeProps[propId]
    if not prop then
        lib.notify(source, { type = 'error', description = 'Item no longer available' })
        return false
    end

    local ped = GetPlayerPed(source)
    local pedCoords = GetEntityCoords(ped)

    if #(pedCoords - prop.coords) > Settings.PickupDistance then
        lib.notify(source, { type = 'error', description = 'Too far from item' })
        return false
    end

    if exports.ox_inventory:AddItem(source, prop.itemName, prop.amount or 1, prop.metadata) then 
    lib.notify(source, { type = 'success', description = 'Item picked up' })
    destroyProp(propId)
    return true
end

    lib.notify(source, { type = 'error', description = 'Inventory full' })
    return false
end)

RegisterNetEvent('LNS_ItemThrowing:updatePlacedPropNetId', function(propId, netId)
    if activeProps[propId] then
        activeProps[propId].netId = netId
    end
end)

RegisterNetEvent('LNS_ItemThrowing:broadcastPlacedProp', function(propId, netId)
    TriggerClientEvent('LNS_ItemThrowing:registerTarget', -1, propId, netId)
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    for propId in pairs(activeProps) do
        destroyProp(propId)
    end
end)

AddEventHandler('playerDropped', function()
    cooldowns[source] = nil
end)


CreateThread(function()
    local resource = GetCurrentResourceName()
    local currentVersion = GetResourceMetadata(resource, 'version', 0) or '1.0.0'
    
    PerformHttpRequest('https://raw.githubusercontent.com/LumaNodeStudios/LNS_ItemThrowing/main/fxmanifest.lua', function(status, response, headers)
        if status ~= 200 then
            print('^3[' .. resource .. '] ^7Unable to check for updates (Status: ' .. status .. ')^0')
            return
        end
        
        local latestVersion = response:match("version%s+'([%d%.]+)'") or response:match('version%s+"([%d%.]+)"')
        
        if not latestVersion then
            print('^3[' .. resource .. '] ^7Unable to parse version from GitHub^0')
            return
        end
        
        if currentVersion ~= latestVersion then
            print('^0====================================^0')
            print('^3[' .. resource .. '] ^1Update Available!^0')
            print('^7Current Version: ^3' .. currentVersion .. '^0')
            print('^7Latest Version: ^2' .. latestVersion .. '^0')
            print('^7Download: ^5https://github.com/LumaNodeStudios/LNS_ItemThrowing^0')
            print('^0====================================^0')
        else
            print('^2[' .. resource .. '] ^7You are running the latest version (^2' .. currentVersion .. '^7)^0')
        end
    end, 'GET')
end)

exports.ox_inventory:registerHook('swapItems', function(payload)
    local item = payload.fromSlot
    local propModel = Settings.ItemModels[item.name]

    if payload.toInventory ~= 'newdrop' or not propModel then return end

    local items = { { item.name, payload.count, item.metadata } }
    local coords = GetEntityCoords(GetPlayerPed(payload.source))
    
    local dropId = exports.ox_inventory:CustomDrop(item.label, items, coords, 5, 3000, nil, propModel)

    if not dropId then return end

    CreateThread(function()
        exports.ox_inventory:RemoveItem(payload.source, item.name, payload.count, nil, item.slot)
        Wait(0)
        exports.ox_inventory:forceOpenInventory(payload.source, 'drop', dropId)
    end)

    return false
end, {
    itemFilter = itemFilter,
    typeFilter = { player = true }
})
