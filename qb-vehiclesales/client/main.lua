local QBCore = exports['qb-core']:GetCoreObject()
local Zone = nil
local TextShown = false
local AcitveZone = {}
local CurrentVehicle = {}
local SpawnZone = {}
local EntityZones = {}
local occasionVehicles = {}

-- HÀM TRỢ GIÚP ĐÃ VIẾT LẠI: Dùng logic "mặc định là Cars"
local function getVehicleSpotType(modelName)
    if not modelName then return nil end
    -- Kiểm tra danh sách đặc biệt trước, nếu không có thì mặc định là "Cars"
    return Config.SpecialVehicleTypes[modelName:lower()] or 'Cars'
end

local function spawnOccasionsVehicles(vehicles)
    if not Zone or not vehicles then return end

    local spotConfig = Config.Zones[Zone].VehicleSpotTypes
    local spotCounters = {}
    for typeName, _ in pairs(spotConfig) do
        spotCounters[typeName] = 1
    end

    if not occasionVehicles[Zone] then occasionVehicles[Zone] = {} end

    for i = 1, #vehicles, 1 do
        local vehicle = vehicles[i]
        local spotType = getVehicleSpotType(vehicle.model)

        if spotType and spotConfig[spotType] and spotCounters[spotType] then
            local spotIndex = spotCounters[spotType]
            local spots = spotConfig[spotType].Spots

            if spotIndex <= #spots then
                local oSlot = spots[spotIndex]
                local modelHash = GetHashKey(vehicle.model)
                RequestModel(modelHash)
                while not HasModelLoaded(modelHash) do Wait(0) end

                local newVeh = CreateVehicle(modelHash, oSlot.x, oSlot.y, oSlot.z, false, false)
                occasionVehicles[Zone][i] = {
                    car   = newVeh,
                    loc   = vector3(oSlot.x, oSlot.y, oSlot.z),
                    price = vehicle.price,
                    owner = vehicle.seller,
                    model = vehicle.model,
                    plate = vehicle.plate,
                    oid   = vehicle.occasionid,
                    desc  = vehicle.description,
                    mods  = vehicle.mods,
                    spotType = spotType,
                    spotIndex = spotIndex
                }

                QBCore.Functions.SetVehicleProperties(newVeh, json.decode(vehicle.mods))
                SetModelAsNoLongerNeeded(modelHash)
                SetVehicleOnGroundProperly(newVeh)
                SetEntityInvincible(newVeh, true)
                SetEntityHeading(newVeh, oSlot.w)
                SetVehicleDoorsLocked(newVeh, 3)
                SetVehicleNumberPlateText(newVeh, vehicle.occasionid)
                FreezeEntityPosition(newVeh, true)

                if Config.UseTarget then
                    if not EntityZones then EntityZones = {} end
                    EntityZones[i] = exports['qb-target']:AddTargetEntity(newVeh, {
                        options = {{
                            type = 'client',
                            event = 'qb-vehiclesales:client:OpenContract',
                            icon = 'fas fa-car',
                            label = Lang:t('menu.view_contract'),
                            Contract = i
                        }},
                        distance = 2.0
                    })
                end
                spotCounters[spotType] = spotCounters[spotType] + 1
            end
        end
    end
end

local function despawnOccasionsVehicles()
    if not Zone then return end

    if Config.Zones[Zone] and Config.Zones[Zone].VehicleSpotTypes then
        for spotType, typeData in pairs(Config.Zones[Zone].VehicleSpotTypes) do
            for _, loc in ipairs(typeData.Spots) do
                local oldVehicle = GetClosestVehicle(loc.x, loc.y, loc.z, 1.3, 0, 70)
                if oldVehicle then
                    QBCore.Functions.DeleteVehicle(oldVehicle)
                end
            end
        end
    end

    if EntityZones then
        for i, zoneId in pairs(EntityZones) do
            if Config.UseTarget then
                exports['qb-target']:RemoveZone(zoneId)
            end
        end
    end
    EntityZones = {}
    if occasionVehicles[Zone] then
        occasionVehicles[Zone] = {}
    end
end

local function openSellContract(bool)
    local pData = QBCore.Functions.GetPlayerData()
    SetNuiFocus(bool, bool)
    SendNUIMessage({
        action = 'sellVehicle',
        showTakeBackOption = false,
        bizName = Config.Zones[Zone].BusinessName,
        sellerData = {
            firstname = pData.charinfo.firstname,
            lastname = pData.charinfo.lastname,
            account = pData.charinfo.account,
            phone = pData.charinfo.phone
        },
        plate = QBCore.Functions.GetPlate(GetVehiclePedIsUsing(PlayerPedId()))
    })
end

local function openBuyContract(sellerData, vehicleData)
    local pData = QBCore.Functions.GetPlayerData()
    SetNuiFocus(true, true)
    SendNUIMessage({
        action = 'buyVehicle',
        showTakeBackOption = sellerData.charinfo.firstname == pData.charinfo.firstname and sellerData.charinfo.lastname == pData.charinfo.lastname,
        bizName = Config.Zones[Zone].BusinessName,
        sellerData = {
            firstname = sellerData.charinfo.firstname,
            lastname = sellerData.charinfo.lastname,
            account = sellerData.charinfo.account,
            phone = sellerData.charinfo.phone
        },
        vehicleData = {
            desc = vehicleData.desc,
            price = vehicleData.price
        },
        plate = vehicleData.plate
    })
end

local function sellVehicleWait(price)
    DoScreenFadeOut(250)
    Wait(250)
    QBCore.Functions.DeleteVehicle(GetVehiclePedIsIn(PlayerPedId()))
    Wait(1500)
    DoScreenFadeIn(250)
    QBCore.Functions.Notify(Lang:t('success.car_up_for_sale', { value = price }), 'success')
    PlaySound(-1, 'SELECT', 'HUD_FRONTEND_DEFAULT_SOUNDSET', 0, 0, 1)
end

local function SellData(data, model)
    QBCore.Functions.TriggerCallback('qb-vehiclesales:server:CheckModelName', function(DataReturning)
        local vehicleData = {}
        vehicleData.ent = GetVehiclePedIsUsing(PlayerPedId())
        vehicleData.model = DataReturning
        vehicleData.plate = model
        vehicleData.mods = QBCore.Functions.GetVehicleProperties(vehicleData.ent)
        vehicleData.desc = data.desc
        TriggerServerEvent('qb-occasions:server:sellVehicle', data.price, vehicleData)
        sellVehicleWait(data.price)
    end, model)
end

local listen = false
local function Listen4Control(spot)
    listen = true
    CreateThread(function()
        while listen do
            if IsControlJustReleased(0, 38) then -- E
                if spot then
                    local data = { Contract = spot }
                    TriggerEvent('qb-vehiclesales:client:OpenContract', data)
                else
                    if IsPedInAnyVehicle(PlayerPedId(), false) then
                        listen = false
                        TriggerEvent('qb-occasions:client:MainMenu')
                    else
                        QBCore.Functions.Notify(Lang:t('error.not_in_veh'), 'error', 4500)
                    end
                end
            end
            Wait(0)
        end
    end)
end

---- ** Main Zone Functions ** ----
local function CreateZones()
    for k, v in pairs(Config.Zones) do
        local SellSpot = PolyZone:Create(v.PolyZone, {
            name = k,
            minZ = v.MinZ,
            maxZ = v.MaxZ,
            debugPoly = false
        })

        SellSpot:onPlayerInOut(function(isPointInside)
            if isPointInside and Zone ~= k then
                Zone = k
                QBCore.Functions.TriggerCallback('qb-occasions:server:getVehicles', function(vehicles)
                    despawnOccasionsVehicles()
                    spawnOccasionsVehicles(vehicles)
                end)
            else
                if not isPointInside then
                    despawnOccasionsVehicles()
                    Zone = nil
                end
            end
        end)
        AcitveZone[k] = SellSpot
    end
end

local function DeleteZones()
    for k in pairs(AcitveZone) do
        AcitveZone[k]:destroy()
    end
    AcitveZone = {}
end

-- NUI Callbacks
RegisterNUICallback('sellVehicle', function(data, cb)
    local plate = QBCore.Functions.GetPlate(GetVehiclePedIsUsing(PlayerPedId()))
    SellData(data, plate)
    cb('ok')
end)

RegisterNUICallback('close', function(_, cb)
    SetNuiFocus(false, false)
    cb('ok')
end)

RegisterNUICallback('buyVehicle', function(_, cb)
    TriggerServerEvent('qb-occasions:server:buyVehicle', CurrentVehicle)
    cb('ok')
end)

RegisterNUICallback('takeVehicleBack', function(_, cb)
    TriggerServerEvent('qb-occasions:server:ReturnVehicle', CurrentVehicle)
    cb('ok')
end)

-- Events
RegisterNetEvent('qb-occasions:client:BuyFinished', function(vehdata)
    local vehmods = json.decode(vehdata.mods)
    DoScreenFadeOut(250)
    Wait(500)
    QBCore.Functions.TriggerCallback('QBCore:Server:SpawnVehicle', function(netId)
        local veh = NetToVeh(netId)
        SetVehicleNumberPlateText(veh, vehdata.plate)
        SetEntityHeading(veh, Config.Zones[Zone].BuyVehicle.w)
        TaskWarpPedIntoVehicle(PlayerPedId(), veh, -1)
        SetVehicleFuelLevel(veh, 100)
        QBCore.Functions.Notify(Lang:t('success.vehicle_bought'), 'success', 2500)
        TriggerEvent('vehiclekeys:client:SetOwner', vehdata.plate)
        SetVehicleEngineOn(veh, true, true)
        Wait(500)
        QBCore.Functions.SetVehicleProperties(veh, vehmods)
    end, vehdata.model, Config.Zones[Zone].BuyVehicle, true)
    Wait(500)
    DoScreenFadeIn(250)
    CurrentVehicle = {}
end)

RegisterNetEvent('qb-occasions:client:SellBackCar', function()
    local ped = PlayerPedId()
    if IsPedInAnyVehicle(ped, false) then
        local vehicleData = {}
        local vehicle = GetVehiclePedIsIn(ped, false)
        vehicleData.model = GetEntityModel(vehicle)
        vehicleData.plate = GetVehicleNumberPlateText(vehicle)
        QBCore.Functions.TriggerCallback('qb-occasions:server:checkVehicleOwner', function(owned, balance)
            if owned then
                if balance < 1 then
                    TriggerServerEvent('qb-occasions:server:sellVehicleBack', vehicleData)
                    QBCore.Functions.DeleteVehicle(vehicle)
                else
                    QBCore.Functions.Notify(Lang:t('error.finish_payments'), 'error', 3500)
                end
            else
                QBCore.Functions.Notify(Lang:t('error.not_your_vehicle'), 'error', 3500)
            end
        end, vehicleData.plate)
    else
        QBCore.Functions.Notify(Lang:t('error.not_in_veh'), 'error', 4500)
    end
end)

RegisterNetEvent('qb-occasions:client:ReturnOwnedVehicle', function(vehdata)
    local vehmods = json.decode(vehdata.mods)
    DoScreenFadeOut(250)
    Wait(500)
    QBCore.Functions.TriggerCallback('QBCore:Server:SpawnVehicle', function(netId)
        local veh = NetToVeh(netId)
        SetVehicleNumberPlateText(veh, vehdata.plate)
        SetEntityHeading(veh, Config.Zones[Zone].BuyVehicle.w)
        TaskWarpPedIntoVehicle(PlayerPedId(), veh, -1)
        SetVehicleFuelLevel(veh, 100)
        QBCore.Functions.Notify(Lang:t('info.vehicle_returned'))
        TriggerEvent('vehiclekeys:client:SetOwner', vehdata.plate)
        SetVehicleEngineOn(veh, true, true)
        Wait(500)
        QBCore.Functions.SetVehicleProperties(veh, vehmods)
    end, vehdata.model, Config.Zones[Zone].BuyVehicle, true)
    Wait(500)
    DoScreenFadeIn(250)
    CurrentVehicle = {}
end)

RegisterNetEvent('qb-occasion:client:refreshVehicles', function()
    if Zone then
        QBCore.Functions.TriggerCallback('qb-occasions:server:getVehicles', function(vehicles)
            despawnOccasionsVehicles()
            spawnOccasionsVehicles(vehicles)
        end)
    end
end)

RegisterNetEvent('qb-vehiclesales:client:SellVehicle', function()
    local ped = PlayerPedId()
    local vehicle = GetVehiclePedIsIn(ped, false)
    local vehicleModelHash = GetEntityModel(vehicle)
    local vehicleModelName = nil

    for k, v in pairs(QBCore.Shared.Vehicles) do
        if v.hash == vehicleModelHash then
            vehicleModelName = k
            break
        end
    end

    if not vehicleModelName then
        QBCore.Functions.Notify("Không thể xác định model của xe này.", "error")
        return
    end

    local spotType = getVehicleSpotType(vehicleModelName)
    if not spotType then
        QBCore.Functions.Notify("Loại xe này không được phép bán ở đây.", "error")
        return
    end

    if not Config.Zones[Zone].VehicleSpotTypes[spotType] then
        QBCore.Functions.Notify("Không có khu vực trưng bày nào được cấu hình cho loại xe này.", "error")
        return
    end

    QBCore.Functions.TriggerCallback('qb-occasions:server:checkVehicleOwner', function(owned, balance)
        if owned then
            if balance < 1 then
                QBCore.Functions.TriggerCallback('qb-vehiclesales:server:getSpotAvailability', function(availability)
                    if availability[spotType] and availability[spotType] > 0 then
                        openSellContract(true)
                    else
                        QBCore.Functions.Notify(Lang:t('error.no_space_on_lot'), 'error', 3500)
                    end
                end, Zone)
            else
                QBCore.Functions.Notify(Lang:t('error.finish_payments'), 'error', 3500)
            end
        else
            QBCore.Functions.Notify(Lang:t('error.not_your_vehicle'), 'error', 3500)
        end
    end, QBCore.Functions.GetPlate(vehicle))
end)

RegisterNetEvent('qb-vehiclesales:client:OpenContract', function(data)
    if not occasionVehicles[Zone] or not occasionVehicles[Zone][data.Contract] then return end
    CurrentVehicle = occasionVehicles[Zone][data.Contract]
    if CurrentVehicle then
        QBCore.Functions.TriggerCallback('qb-occasions:server:getSellerInformation', function(info)
            if info then
                info.charinfo = json.decode(info.charinfo)
            else
                info = {}
                info.charinfo = {
                    firstname = Lang:t('charinfo.firstname'),
                    lastname = Lang:t('charinfo.lastname'),
                    account = Lang:t('charinfo.account'),
                    phone = Lang:t('charinfo.phone')
                }
            end
            openBuyContract(info, CurrentVehicle)
        end, CurrentVehicle.owner)
    else
        QBCore.Functions.Notify(Lang:t('error.not_for_sale'), 'error', 7500)
    end
end)

RegisterNetEvent('qb-occasions:client:MainMenu', function()
    local MainMenu = {
        { isMenuHeader = true, header = Config.Zones[Zone].BusinessName },
        { header = Lang:t('menu.sell_vehicle'), txt = Lang:t('menu.sell_vehicle_help'), params = { event = 'qb-vehiclesales:client:SellVehicle' }},
        { header = Lang:t('menu.sell_back'), txt = Lang:t('menu.sell_back_help'), params = { event = 'qb-occasions:client:SellBackCar' }}
    }
    exports['qb-menu']:openMenu(MainMenu)
end)

-- Threads
CreateThread(function()
    for _, cars in pairs(Config.Zones) do
        local OccasionBlip = AddBlipForCoord(cars.SellVehicle.x, cars.SellVehicle.y, cars.SellVehicle.z)
        SetBlipSprite(OccasionBlip, 326)
        SetBlipDisplay(OccasionBlip, 4)
        SetBlipScale(OccasionBlip, 0.75)
        SetBlipAsShortRange(OccasionBlip, true)
        SetBlipColour(OccasionBlip, 3)
        BeginTextCommandSetBlipName('STRING')
        AddTextComponentSubstringPlayerName(Lang:t('info.used_vehicle_lot'))
        EndTextCommandSetBlipName(OccasionBlip)
    end
end)

CreateThread(function()
    for k, cars in pairs(Config.Zones) do
        SpawnZone[k] = CircleZone:Create(vector3(cars.SellVehicle.x, cars.SellVehicle.y, cars.SellVehicle.z), 3.0, {
            name = 'OCSell' .. k,
            debugPoly = false,
        })

        SpawnZone[k]:onPlayerInOut(function(isPointInside)
            if isPointInside and IsPedInAnyVehicle(PlayerPedId(), false) then
                exports['qb-core']:DrawText(Lang:t('menu.interaction'), 'left')
                TextShown = true
                Listen4Control()
            else
                listen = false
                if TextShown then
                    TextShown = false
                    exports['qb-core']:HideText()
                end
            end
        end)
        
        if not Config.UseTarget then
            for typeName, typeData in pairs(cars.VehicleSpotTypes) do
                for spotIndex, spotData in ipairs(typeData.Spots) do
                    local VehicleZones = BoxZone:Create(vector3(spotData.x, spotData.y, spotData.z), 4.3, 3.6, {
                        name = 'VehicleSpot' .. k .. typeName .. spotIndex,
                        debugPoly = false,
                        minZ = spotData.z - 2,
                        maxZ = spotData.z + 2,
                    })

                    VehicleZones:onPlayerInOut(function(isPointInside)
                        local wasListening = listen
                        listen = false
                        if isPointInside then
                            if occasionVehicles[k] then
                                for i, vehData in pairs(occasionVehicles[k]) do
                                    if vehData.spotType == typeName and vehData.spotIndex == spotIndex then
                                        exports['qb-core']:DrawText(Lang:t('menu.view_contract_int'), 'left')
                                        TextShown = true
                                        Listen4Control(i)
                                        return
                                    end
                                end
                            end
                        end
                        if wasListening and TextShown then
                            TextShown = false
                            exports['qb-core']:HideText()
                        end
                    end)
                end
            end
        end
    end
end)

---- ** Resource Events ** ----
RegisterNetEvent('QBCore:Client:OnPlayerLoaded', function()
    CreateZones()
end)

RegisterNetEvent('QBCore:Client:OnPlayerUnload', function()
    DeleteZones()
end)

AddEventHandler('onResourceStart', function(resourceName)
    if GetCurrentResourceName() == resourceName then
        CreateZones()
    end
end)

AddEventHandler('onResourceStop', function(resourceName)
    if GetCurrentResourceName() == resourceName then
        DeleteZones()
        despawnOccasionsVehicles()
    end
end)
-- THÊM VÀO CUỐI TỆP client/main.lua
CreateThread(function()
    while true do
        Wait(0)
        -- Lặp qua tất cả các khu vực bán xe đã cấu hình
        for _, zoneData in pairs(Config.Zones) do
            local sellCoords = zoneData.SellVehicle
            local distance = #(GetEntityCoords(PlayerPedId()) - sellCoords.xyz)

            -- Chỉ vẽ marker khi người chơi ở gần để tiết kiệm tài nguyên
            if distance < 100.0 then
                DrawMarker(
                    1, -- Loại marker (1 là hình trụ đứng)
                    sellCoords.x, sellCoords.y, sellCoords.z - 0.98, -- Tọa độ (hạ thấp một chút cho đẹp)
                    0.0, 0.0, 0.0, -- Hướng
                    0.0, 0.0, 0.0, -- Góc xoay
                    3.0, 3.0, 1.0, -- Kích thước (rộng, dài, cao)
                    185, 230, 185, 255, -- Màu sắc (Vàng, trong suốt)
                    false, -- Hiệu ứng nhấp nháy lên xuống
                    false, -- Không xoay theo camera
                    2,
                    false,
                    nil, nil,
                    false
                )
            end
        end
    end
end)