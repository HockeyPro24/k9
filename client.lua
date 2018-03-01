--[[ Variables ]]--
    -- DO NOT CHANGE --
    local just_started = true
    local k9_name = "Default"
    local spawned_ped = nil
    local following = false
    local attacking = false
    local attacked_player = 0
    local searching = false
    local playing_animation = false

    local animations = {
        ["vehicle"] = {
            dict = "creatures@rottweiler@in_vehicle@4x4",
            getin = "get_in",
            getout = "get_out"
        }
    }
--]]

--[[ Tables ]]--
local language = {}
--]]

--[[ NUI Messages ]]--

    -- Open Menu --
    function EnableMenu()
        SetNuiFocus(true, true)
        SendNUIMessage({
            type = "open_k9_menu"
        })
    end

--]]

--[[ NUI Callbacks ]]--

    RegisterNUICallback("closemenu", function(data)
        SetNuiFocus(false, false)
    end)

    RegisterNUICallback("updatename", function(data)
        k9_name = data.name
    end)

    RegisterNUICallback("spawnk9", function(data)
        TriggerEvent("K9:ToggleK9", data.model)
    end)

    RegisterNUICallback("vehicletoggle", function(data)
        TriggerServerEvent("K9:RequestVehicleToggle")
    end)

    RegisterNUICallback("vehiclesearch", function(data)
        TriggerServerEvent("K9:RequestItems")
    end)

--]]

--[[ Main Event Handlers ]]--

    -- Updates Language Settings
    RegisterNetEvent("K9:UpdateLanguage")
    AddEventHandler("K9:UpdateLanguage", function(commands)
        language = commands
        Citizen.Trace(tostring(json.encode(language)))
    end)

    -- Opens K9 Menu
    RegisterNetEvent("K9:OpenMenu")
    AddEventHandler("K9:OpenMenu", function(pedRestriction, pedList)
        if pedRestriction then
            if CheckPedRestriction(GetLocalPed(), pedList) then
                EnableMenu()
            else
                Notification(tostring("~r~You do not have the right PED to use the K9."))
            end
        else
            EnableMenu()
        end
    end)

    -- Error for Identifier Whitelist
    RegisterNetEvent("K9:IdentifierRestricted")
    AddEventHandler("K9:IdentifierRestricted", function()
        Notification(tostring("~r~You do not match any identifiers in the whitelist."))
    end)

    -- Spawns and Deletes K9
    RegisterNetEvent("K9:ToggleK9")
    AddEventHandler("K9:ToggleK9", function(model)
        if spawned_ped == nil then
            local ped = GetHashKey(model)
            RequestModel(ped)
            while not HasModelLoaded(ped) do
                Citizen.Wait(1)
                RequestModel(ped)
            end
            local plyCoords = GetOffsetFromEntityInWorldCoords(GetLocalPed(), 0.0, 2.0, 0.0)
            local dog = CreatePed(28, ped, plyCoords.x, plyCoords.y, plyCoords.z, GetEntityHeading(GetLocalPed()), 0, 1)
            spawned_ped = dog
            SetBlockingOfNonTemporaryEvents(spawned_ped, true)
            SetPedFleeAttributes(spawned_ped, 0, 0)
            SetPedRelationshipGroupHash(spawned_ped, GetHashKey("k9"))
            local blip = AddBlipForEntity(spawned_ped)
            SetBlipAsFriendly(blip, true)
            SetBlipSprite(blip, 442)
            BeginTextCommandSetBlipName("STRING")
            AddTextComponentString(tostring("K9: ".. k9_name))
            EndTextCommandSetBlipName(blip)
            NetworkRegisterEntityAsNetworked(spawned_ped)
            while not NetworkGetEntityIsNetworked(spawned_ped) do
                NetworkRegisterEntityAsNetworked(spawned_ped)
                Citizen.Wait(1)
            end
        else
            local has_control = false
            RequestNetworkControl(function(cb)
                has_control = cb
            end)
            if has_control then
                SetEntityAsMissionEntity(spawned_ped, true, true)
                DeleteEntity(spawned_ped)
                spawned_ped = nil
                if attacking then
                    SetPedRelationshipGroupDefaultHash(target_ped, GetHashKey("CIVMALE"))
                    target_ped = nil
                    attacking = false
                end
                following = false
                searching = false
                playing_animation = false
            end
        end
    end)

    -- Toggles K9 to Follow / Heel
    RegisterNetEvent("K9:ToggleFollow")
    AddEventHandler("K9:ToggleFollow", function()
        if spawned_ped ~= nil then
            if not following then
                local has_control = false
                RequestNetworkControl(function(cb)
                    has_control = cb
                end)
                if has_control then
                    TaskFollowToOffsetOfEntity(spawned_ped, GetLocalPed(), 0.5, 0.0, 0.0, 5.0, -1, 0.0, 1)
                    SetPedKeepTask(spawned_ped, true)
                    following = true
                    attacking = false
                    Notification(tostring(k9_name .. " " .. language.follow))
                end
            else
                local has_control = false
                RequestNetworkControl(function(cb)
                    has_control = cb
                end)
                if has_control then
                    SetPedKeepTask(spawned_ped, false)
                    ClearPedTasks(spawned_ped)
                    following = false
                    attacking = false
                    Notification(tostring(k9_name .. " " .. language.stop))
                end
            end
        end
    end)

    -- Toggles K9 In and Out of Vehicles
    RegisterNetEvent("K9:ToggleVehicle")
    AddEventHandler("K9:ToggleVehicle", function(isRestricted, vehList)
        if IsPedInAnyVehicle(spawned_ped, false) then
            TaskLeaveVehicle(spawned_ped, GetVehiclePedIsIn(spawned_ped, false), 256)
            Notification(tostring(k9_name .. " " .. language.exit))
        else
            local plyCoords = GetEntityCoords(GetLocalPed(), false)
            local vehicle = GetVehicleAheadOfPlayer()
            local door = GetClosestVehicleDoor(vehicle)
            if door ~= false then
                if isRestricted then
                    if CheckVehicleRestriction(vehicle, vehList) then
                        TaskEnterVehicle(spawned_ped, vehicle, -1, door, 2.0, 1, 0)
                        Notification(tostring(k9_name .. " " .. language.enter))
                    end
                else
                    TaskEnterVehicle(spawned_ped, vehicle, -1, door, 2.0, 1, 0)
                    Notification(tostring(k9_name .. " " .. language.enter))
                end
            end
        end
    end)

    -- Triggers K9 to Attack
    RegisterNetEvent("K9:ToggleAttack")
    AddEventHandler("K9:ToggleAttack", function(target)
        if not attacking then
            if IsPedAPlayer(target) then
                local has_control = false
                RequestNetworkControl(function(cb)
                    has_control = cb
                end)
                if has_control then
                    local player = GetPlayerFromServerId(GetPlayerId(target))
                    SetCanAttackFriendly(spawned_ped, true, true)
                    TaskPutPedDirectlyIntoMelee(spawned_ped, GetPlayerPed(player), 0.0, -1.0, 0.0, 0)
                    attacked_player = player
                end
            else
                local has_control = false
                RequestNetworkControl(function(cb)
                    has_control = cb
                end)
                if has_control then
                    SetCanAttackFriendly(spawned_ped, true, true)
                    TaskPutPedDirectlyIntoMelee(spawned_ped, target, 0.0, -1.0, 0.0, 0)
                    attacked_player = 0
                end
            end
            attacking = true
            following = false
            Notification(tostring(k9_name .. " " .. language.attack))
        end
    end)

    -- Triggers K9 to Search Vehicle
    RegisterNetEvent("K9:SearchVehicle")
    AddEventHandler("K9:SearchVehicle", function(items)
        local vehicle = GetVehicleAheadOfPlayer()
        if vehicle ~= 0 then
            Citizen.Trace("Started Searching")

            local offsetOne = GetOffsetFromEntityGivenWorldCoords(vehicle, 1.0, 1.0, 0.0)
            -- Get Item
            TaskGoToCoordAnyMeans(spawned_ped, offsetOne.x, offsetOne.y, offsetOne.z, 5.0, 0, 0, 786603, 0xbf800000)

            Citizen.Wait(3000)

            local offsetTwo = GetOffsetFromEntityGivenWorldCoords(vehicle, -1.0, 1.0, 0.0)
            -- Get Item
            TaskGoToCoordAnyMeans(spawned_ped, offsetTwo.x, offsetTwo.y, offsetTwo.z, 5.0, 0, 0, 786603, 0xbf800000)

            Citizen.Wait(3000)

            local offsetThree = GetOffsetFromEntityGivenWorldCoords(vehicle, -1.0, -1.0, 0.0)
            -- Get Item
            TaskGoToCoordAnyMeans(spawned_ped, offsetThree.x, offsetThree.y, offsetThree.z, 5.0, 0, 0, 786603, 0xbf800000)

            Citizen.Wait(3000)

            local offsetFour = GetOffsetFromEntityGivenWorldCoords(vehicle, 1.0, -1.0, 0.0)
            -- Get Item
            TaskGoToCoordAnyMeans(spawned_ped, offsetFour.x, offsetFour.y, offsetFour.z, 5.0, 0, 0, 786603, 0xbf800000)

            Citizen.Wait(3000)

            Citizen.Trace("Finished Searching")
        end
    end)

--]]

--[[ Threads ]]

    -- Controls Menu
    Citizen.CreateThread(function()
        while true do
            Citizen.Wait(0)

            -- Trigger Opens Menu
            if IsControlPressed(1, 19) and IsControlJustPressed(1, 213) then
                TriggerServerEvent("K9:RequestOpenMenu")
            end

            -- Trigger Attack
            if IsControlJustPressed(1, 47) and IsPlayerFreeAiming(PlayerId()) then
                local bool, target = GetEntityPlayerIsFreeAimingAt(PlayerId())

                if bool then
                    if IsEntityAPed(target) then
                        TriggerEvent("K9:ToggleAttack", target)
                    end
                end
            end

            -- Trigger Follow
            if IsControlJustPressed(1, 47) and not IsPlayerFreeAiming(PlayerId()) then
                TriggerEvent("K9:ToggleFollow")
            end

        end
    end)

    -- DO NOT TOUCH (CLEANER)
    Citizen.CreateThread(function()
        while true do
            Citizen.Wait(0)

            -- Setting K9 Settings
            if just_started then
                Citizen.Wait(1000)
                local resource = GetCurrentResourceName()
                SendNUIMessage({
                    type = "update_resource_name",
                    name = resource
                })
                just_started = false
                SetNuiFocus(false, false)
                TriggerServerEvent("K9:SendLanguage")
            end

            -- Deletes K9 when you die
            if spawned_ped ~= nil and IsEntityDead(GetLocalPed()) then
                TriggerEvent("K9:ToggleK9")
            end
        end
    end)

--]]

--[[ EXTRA FUNCTIONS ]]--

-- Gets Local Ped
function GetLocalPed()
    return GetPlayerPed(PlayerId())
end

-- Gets Control Of Ped
function RequestNetworkControl(callback)
    local netId = NetworkGetNetworkIdFromEntity(spawned_ped)
    local timer = 0
    NetworkRequestControlOfNetworkId(netId)
    while not NetworkHasControlOfNetworkId(netId) do
        Citizen.Wait(1)
        NetworkRequestControlOfNetworkId(netId)
        timer = timer + 1
        if timer == 5000 then
            Citizen.Trace("Control failed")
            callback(false)
        end
    end
    callback(true)
end

-- Gets Players
function GetPlayers()
    local players = {}
    for i = 0, 32 do
        if NetworkIsPlayerActive(i) then
            table.insert(players, i)
        end
    end
    return players
end

function ChooseItem(items)
    local number = math.random(1, 100)

    if number > 70 and number < 95 then
        local randomItem = math.random(1, #items)
        return items[randomItem]
    else
        return false
    end
end

-- Gets Player ID
function GetPlayerId(target_ped)
    local players = GetPlayers()
    for a = 1, #players do
        local ped = GetPlayerPed(players[a])
        local server_id = GetPlayerServerId(players[a])
        if target_ped == ped then
            return server_id
        end
    end
    return 0
end

-- Checks Ped Restriction
function CheckPedRestriction(ped, PedList)
	for i = 1, #PedList do
		if GetHashKey(PedList[i]) == GetEntityModel(ped) then
			return true
		end
	end
	return false
end

-- Checks Vehicle Restriction
function CheckVehicleRestriction(vehicle, VehicleList)
	for i = 1, #VehicleList do
		if GetHashKey(VehicleList[i]) == GetEntityModel(vehicle) then
			return true
		end
	end
	return false
end

-- Gets Vehicle Ahead Of Player
function GetVehicleAheadOfPlayer()
    local lPed = GetLocalPed()
    local lPedCoords = GetEntityCoords(lPed, alive)
    local lPedOffset = GetOffsetFromEntityInWorldCoords(lPed, 0.0, 3.0, 0.0)
    local rayHandle = StartShapeTestCapsule(lPedCoords.x, lPedCoords.y, lPedCoords.z, lPedOffset.x, lPedOffset.y, lPedOffset.z, 1.2, 10, lPed, 7)
    local returnValue, hit, endcoords, surface, vehicle = GetShapeTestResult(rayHandle)

    if hit then
        return vehicle
    else
        return false
    end
end

-- Gets Closest Door To Player
function GetClosestVehicleDoor(vehicle)
    local plyCoords = GetEntityCoords(GetLocalPed(), false)
	local backleft = GetWorldPositionOfEntityBone(vehicle, GetEntityBoneIndexByName(vehicle, "door_dside_r"))
	local backright = GetWorldPositionOfEntityBone(vehicle, GetEntityBoneIndexByName(vehicle, "door_pside_r"))
	local bldistance = GetDistanceBetweenCoords(backleft['x'], backleft['y'], backleft['z'], plyCoords.x, plyCoords.y, plyCoords.z, 1)
    local brdistance = GetDistanceBetweenCoords(backright['x'], backright['y'], backright['z'], plyCoords.x, plyCoords.y, plyCoords.z, 1)

    local found_door = false

    if (bldistance < brdistance) then
        found_door = 1
    elseif(brdistance < bldistance) then
        found_door = 2
    end

    return found_door
end

-- Displays Notification
function Notification(message)
	SetNotificationTextEntry("STRING")
	AddTextComponentString(message)
	DrawNotification(0, 1)
end
--]]