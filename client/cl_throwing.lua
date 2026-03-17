local Settings = lib.load('shared.settings')
local throwingItem, givingItem = false, false
local attachedProp, previewProp = nil, nil
local currentThrowData, currentGiveData = {}, {}
local initializingThrow = false
local droppedItems = {}

local function startItemPoint(propId, entity, netId, itemLabel)
    local coords = GetEntityCoords(entity)
    local point = lib.points.new({
        coords = coords,
        distance = 2.0,
    })

    
    local label = itemLabel or 'Weapon'

    function point:onEnter()
        lib.showTextUI(('[E] Pick Up %s'):format(label), {
            icon = 'hand-holding', 
            position = 'left-center'
        })
    end

    function point:onExit()
        lib.hideTextUI()
    end

    function point:nearby()
        if IsControlJustPressed(0, 38) then -- [E]
            TriggerEvent('LNS_ItemThrowing:clientPickupItem', propId)
        end
    end

    droppedItems[netId] = point
end

local function MakeItemThrowable(itemName, propModel, slot)
    if throwingItem or givingItem then return end
    
    initializingThrow = true
    local ped = cache.ped
    local inVehicle = IsPedInAnyVehicle(ped, false)

    GiveWeaponToPed(ped, `WEAPON_SNOWBALL`, 1, false, true)
    SetCurrentPedWeapon(ped, `WEAPON_SNOWBALL`, true)
    SetPedCurrentWeaponVisible(ped, false, false, false, false)

    CreateThread(function()
        while throwingItem do
            SetPedCurrentWeaponVisible(ped, false, false, false, false)
            local snowball = GetClosestObjectOfType(GetEntityCoords(ped), 10.0, `w_snowball`, false, false, false)
            if DoesEntityExist(snowball) then
                SetEntityVisible(snowball, false, false)
                SetEntityCollision(snowball, false, false)
            end
            Wait(0)
        end
    end)

    lib.requestModel(propModel, 5000)

    if not inVehicle then
        local bone = GetPedBoneIndex(ped, 28422)
        attachedProp = CreateObject(propModel, 0, 0, 0, true, true, true)
        AttachEntityToEntity(attachedProp, ped, bone, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, true, true, false, true, 1, true)
    end
    
    throwingItem = true
    currentThrowData = {itemName = itemName, propModel = propModel, slot = slot}

    lib.showTextUI('[X] Cancel Throw', {icon = 'hand'})

    CreateThread(function()
        for i = 1, 10 do
            Wait(50)
            if not HasPedGotWeapon(ped, `WEAPON_SNOWBALL`, false) then
                GiveWeaponToPed(ped, `WEAPON_SNOWBALL`, 1, false, true)
            end
            SetCurrentPedWeapon(ped, `WEAPON_SNOWBALL`, true)
            SetPedInfiniteAmmoClip(ped, true)
        end
        
        initializingThrow = false

        while throwingItem do
            Wait(0)

            if not HasPedGotWeapon(ped, `WEAPON_SNOWBALL`, false) then
                GiveWeaponToPed(ped, `WEAPON_SNOWBALL`, 1, false, true)
                SetCurrentPedWeapon(ped, `WEAPON_SNOWBALL`, true)
            end
            
            SetPedInfiniteAmmoClip(ped, true)

            if IsControlJustPressed(0, 73) then
                if DoesEntityExist(attachedProp) then
                    DeleteEntity(attachedProp)
                    attachedProp = nil
                end
                RemoveWeaponFromPed(ped, `WEAPON_SNOWBALL`)
                throwingItem = false
                initializingThrow = false
                currentThrowData = {}
                lib.hideTextUI()
                lib.notify({description = 'Throw cancelled', type = 'inform'})
                break
            end

            if IsPedShooting(ped) then
                local projectile = GetClosestObjectOfType(GetEntityCoords(ped), 5.0, `w_snowball`, false, false, false)
                if DoesEntityExist(projectile) then
                    SetEntityVisible(projectile, false, false)
                    DeleteEntity(projectile)
                end
                
                local camRot = GetGameplayCamRot(0)
                local pedCoords = GetEntityCoords(ped)
                local throwCoord

                if IsPedInAnyVehicle(ped, false) then
                    local veh = cache.vehicle
                    local vehCoords = GetEntityCoords(veh)
                    local forward = GetEntityForwardVector(veh)
                    throwCoord = vehCoords + (forward * 2.0) + vec3(0, 0, 0.5)
                else
                    throwCoord = pedCoords + vec3(0, 0, 1.0)
                end

                if DoesEntityExist(attachedProp) then
                    DeleteEntity(attachedProp)
                    attachedProp = nil
                end

                local flyingProp = CreateObject(propModel, throwCoord.x, throwCoord.y, throwCoord.z, true, true, true)
                NetworkRegisterEntityAsNetworked(flyingProp)
                SetNetworkIdCanMigrate(NetworkGetNetworkIdFromEntity(flyingProp), true)
                SetEntityAsMissionEntity(flyingProp, true, true)

                local force = Settings.ThrowForce
                local radRot = vec3(math.rad(camRot.x), math.rad(camRot.y), math.rad(camRot.z))
                local forceVec = vec3(-math.sin(radRot.z) * math.abs(math.cos(radRot.x)) * force, math.cos(radRot.z) * math.abs(math.cos(radRot.x)) * force, math.sin(radRot.x) * force)

                if IsPedInAnyVehicle(ped, false) then
                    local veh = cache.vehicle
                    local vehVel = GetEntityVelocity(veh)
                    forceVec = forceVec + (vehVel * 0.5)
                end
                
                ApplyForceToEntity(flyingProp, 1, forceVec.x, forceVec.y, forceVec.z, 0.0, 0.0, 0.0, 0, false, true, true, false, true)

                local netId = NetworkGetNetworkIdFromEntity(flyingProp)
                local throwData = {
                    itemName = currentThrowData.itemName,
                    slot = currentThrowData.slot,
                    amount = currentGiveData.count or 1
                }

                CreateThread(function()
                    local landed = false
                    local lastZ = GetEntityCoords(flyingProp).z
                    local stableFrames = 0

                    while not landed and DoesEntityExist(flyingProp) do
                        Wait(100)

                        local coords = GetEntityCoords(flyingProp)
                        local vel = GetEntityVelocity(flyingProp)
                        local speed = #vel

                        if speed < 0.5 and math.abs(coords.z - lastZ) < 0.1 then
                            stableFrames = stableFrames + 1
                            if stableFrames >= 3 then landed = true end
                        else
                            stableFrames = 0
                        end

                        lastZ = coords.z
                    end

                    if landed and DoesEntityExist(flyingProp) then
                        local finalCoords = GetEntityCoords(flyingProp)
                        FreezeEntityPosition(flyingProp, true)
                        SetEntityCollision(flyingProp, true, true)

                        local success = lib.callback.await('LNS_ItemThrowing:createProp', false, {
    coords = finalCoords,
    itemName = throwData.itemName,
    slot = throwData.slot,
    amount = throwData.amount,
    netId = netId
})


                        if not success and DoesEntityExist(flyingProp) then
                            DeleteEntity(flyingProp)
                            lib.notify({description = 'Failed to throw item', type = 'error'})
                        end
                    end
                end)

                RemoveWeaponFromPed(ped, `WEAPON_SNOWBALL`)
                throwingItem = false
                initializingThrow = false
                currentThrowData = {}
                lib.hideTextUI()
                break
            end
        end
    end)
end



function StartGiveMode(itemName, slot, count)
    if givingItem or throwingItem then return end
    
    local inventory = exports.ox_inventory:GetPlayerItems()
    local slotData = inventory[slot]
    
    if not slotData or slotData.count <= 0 or slotData.count < (count or 1) then
        return lib.notify({description = 'You do not have enough of that item!', type = 'error'})
    end

    local propModel = Settings.ItemModels[itemName]
    if not propModel then
        local nearbyPlayers = lib.getNearbyPlayers(GetEntityCoords(cache.ped), Settings.MaxGiveDistance)
        if #nearbyPlayers == 0 then return lib.notify({description = 'No nearby players', type = 'error'}) end
        exports.ox_inventory:giveItemToTarget(GetPlayerServerId(nearbyPlayers[1].id), slot, count)
        return
    end
    
    givingItem = true
    currentGiveData = {itemName = itemName, slot = slot, count = count, propModel = propModel}
    lib.requestModel(propModel, 5000)
    
    previewProp = CreateObject(propModel, 0, 0, 0, false, false, false)
    SetEntityCollision(previewProp, false, false)
    SetEntityAlpha(previewProp, 200, false)
    SetEntityCompletelyDisableCollision(previewProp, false, false)

   
    SetEntityDrawOutline(previewProp, true)
    SetEntityDrawOutlineColor(255, 255, 255, 150) 
   
    local propRotation = 0.0
    lib.showTextUI('[E] Place Item | [G] Throw Item | [SCROLL] Rotate | [X] Cancel', { position = 'bottom-center', icon = 'hand-holding' })
    
    CreateThread(function()
        local ped = cache.ped
        
        while givingItem do
            Wait(0)

            local inv = exports.ox_inventory:GetPlayerItems()
            local currentSlotData = inv[currentGiveData.slot]

            if not currentSlotData or currentSlotData.count <= 0 or currentSlotData.count < (currentGiveData.count or 1) then
                if DoesEntityExist(previewProp) then DeleteEntity(previewProp) end
                givingItem = false
                lib.hideTextUI()
                lib.notify({description = 'Item is no longer available!', type = 'error'})
                break 
            end

            DisableControlAction(0, 14, true)
            DisableControlAction(0, 15, true)

            if IsDisabledControlPressed(0, 14) then propRotation = (propRotation - 2.0) % 360
            elseif IsDisabledControlPressed(0, 15) then propRotation = (propRotation + 2.0) % 360 end

            local camCoords = GetGameplayCamCoord()
            local camRot = GetGameplayCamRot(0)
            local radRot = vec3(math.rad(camRot.x), math.rad(camRot.y), math.rad(camRot.z))
            local dir = vec3(-math.sin(radRot.z) * math.abs(math.cos(radRot.x)), math.cos(radRot.z) * math.abs(math.cos(radRot.x)), math.sin(radRot.x))
            local ray = StartShapeTestRay(camCoords.x, camCoords.y, camCoords.z, camCoords.x + (dir.x * 10.0), camCoords.y + (dir.y * 10.0), camCoords.z + (dir.z * 10.0), -1, ped, 0)
            local _, hit, coords, _, hitEntity = GetShapeTestResult(ray)
            
            if hit then
                SetEntityCoords(previewProp, coords.x, coords.y, coords.z, false, false, false, false)
                SetEntityRotation(previewProp, 0.0, 0.0, propRotation, 2, true)

                local isPlayer = DoesEntityExist(hitEntity) and IsPedAPlayer(hitEntity)
                
            
                if isPlayer then
                    SetEntityDrawOutlineColor(0, 255, 0, 200) 
                else
                    SetEntityDrawOutlineColor(255, 255, 255, 150)
                end
             

                if IsControlJustPressed(0, 38) then 
                    if isPlayer then
                        local targetId = GetPlayerServerId(NetworkGetPlayerIndexFromPed(hitEntity))
                        exports.ox_inventory:giveItemToTarget(targetId, currentGiveData.slot, currentGiveData.count)
                    else
                        lib.callback.await('LNS_ItemThrowing:placeItem', false, {
                            coords = coords, rotation = vec3(0.0, 0.0, propRotation),
                            itemName = currentGiveData.itemName, slot = currentGiveData.slot,
                            amount = currentGiveData.count, propModel = currentGiveData.propModel
                        })
                    end
                    
                    if DoesEntityExist(previewProp) then DeleteEntity(previewProp) end
                    givingItem = false
                    lib.hideTextUI()
                    break
                end

                if IsControlJustPressed(0, 47) then 
                    if DoesEntityExist(previewProp) then DeleteEntity(previewProp) end
                    lib.hideTextUI()
                    local data = currentGiveData
                    givingItem = false
                    Wait(200)
                    MakeItemThrowable(data.itemName, data.propModel, data.slot)
                    break
                end
            end

            if IsControlJustPressed(0, 73) then 
                if DoesEntityExist(previewProp) then DeleteEntity(previewProp) end
                givingItem = false
                lib.hideTextUI()
                break
            end
        end
    end)
end



exports('startGiveMode', function(itemName, slot, count)
    StartGiveMode(itemName, slot, count)
end)

RegisterNetEvent('LNS_ItemThrowing:clientPickupItem', function(propId)
    local ped = cache.ped
    
    lib.requestAnimDict('pickup_object', 1000)
    TaskPlayAnim(ped, 'pickup_object', 'pickup_low', 8.0, -8.0, 1000, 1, 0, false, false, false)
    
    Wait(1200)
    
    local success = lib.callback.await('LNS_ItemThrowing:pickupItem', false, propId)
    if not success then
        lib.notify({description = 'Failed to pickup item', type = 'error'})
    end
    
    ClearPedTasks(ped)
end)

RegisterNetEvent('LNS_ItemThrowing:registerTarget', function(propId, netId)
    CreateThread(function()
        local timeout = GetGameTimer() + 5000
        while not NetworkDoesNetworkIdExist(netId) do
            Wait(100)
            if GetGameTimer() > timeout then return end
        end

        local entity = NetToObj(netId)
        if not DoesEntityExist(entity) then return end

        local modelHash = GetEntityModel(entity)
        local isWeapon = false
        local foundLabel = nil

        
        for itemName, propModel in pairs(Settings.ItemModels) do
            if GetHashKey(propModel) == modelHash then
                if string.find(itemName:upper(), "WEAPON_") then
                    isWeapon = true
                    
                    
                    local itemData = exports.ox_inventory:Items(itemName)
                    foundLabel = itemData and itemData.label or itemName
                    break
                end
            end
        end

        if isWeapon then
            
            startItemPoint(propId, entity, netId, foundLabel)
        else
            exports.ox_target:addLocalEntity(entity, {
                {
                    name = 'pickup_thrown_item',
                    icon = 'fas fa-hand-paper',
                    label = 'Pick Up Item',
                    distance = 2.0,
                    onSelect = function()
                        TriggerEvent('LNS_ItemThrowing:clientPickupItem', propId)
                    end
                }
            })
        end
    end)
end)

RegisterNetEvent('LNS_ItemThrowing:createPlacedProp', function(data)
    CreateThread(function()
        lib.requestModel(data.propModel, 5000)

       
        local prop = CreateObject(data.propModel, data.coords.x, data.coords.y, data.coords.z, true, true, true)
        SetEntityAsMissionEntity(prop, true, true)
        
        if data.rotation then
            SetEntityRotation(prop, data.rotation.x, data.rotation.y, data.rotation.z, 2, true)
        end

        FreezeEntityPosition(prop, true)
        SetEntityCollision(prop, true, true)
        
       
        local netId = ObjToNet(prop)
        SetNetworkIdExistsOnAllMachines(netId, true)
        SetNetworkIdCanMigrate(netId, true)

        TriggerServerEvent('LNS_ItemThrowing:updatePlacedPropNetId', data.propId, netId)
        TriggerServerEvent('LNS_ItemThrowing:broadcastPlacedProp', data.propId, netId)
    end)
end)

RegisterNetEvent('LNS_ItemThrowing:removeProp', function(netId)
   
    if droppedItems[netId] then
        droppedItems[netId]:remove()
        droppedItems[netId] = nil
        lib.hideTextUI()
    end

    
    if NetworkDoesNetworkIdExist(netId) then
        local entity = NetToObj(netId)
        if DoesEntityExist(entity) then
            exports.ox_target:removeLocalEntity(entity)
            DeleteEntity(entity)
        end
    end
end)
