-- SERVER-SIDE: main.lua (Tích hợp spot_id vào occasion)

local QBCore = exports['qb-core']:GetCoreObject()

-- Hàm chọn spot trống từ config
function GetAvailableOccasionSpot()
    for _, spot in pairs(Config.OccasionSpots) do
        local result = MySQL.scalar.await('SELECT COUNT(*) FROM occasion_vehicles WHERE spot_id = ?', {spot.id})
        if result == 0 then
            return spot.id
        end
    end
    return nil
end

RegisterNetEvent('qb-occasions:server:SellVehicle', function(data)
    local src = source
    local Player = QBCore.Functions.GetPlayer(src)

    if not Player then return end

    local spot_id = GetAvailableOccasionSpot()
    if not spot_id then
        TriggerClientEvent('QBCore:Notify', src, 'Không còn chỗ trưng bày!', 'error')
        return
    end

    MySQL.insert('INSERT INTO occasion_vehicles (plate, model, mods, seller, price, description, spot_id) VALUES (?, ?, ?, ?, ?, ?, ?)', {
        data.plate,
        data.model,
        json.encode(data.mods),
        Player.PlayerData.citizenid,
        data.price or 0,
        data.description or '',
        spot_id
    })

    TriggerClientEvent('QBCore:Notify', src, 'Xe đã được đưa lên sàn!', 'success')
end)

-- Khi người chơi mua xe
RegisterNetEvent('qb-occasions:server:BuyVehicle', function(plate)
    local src = source
    local Player = QBCore.Functions.GetPlayer(src)

    local result = MySQL.single.await('SELECT * FROM occasion_vehicles WHERE plate = ?', {plate})
    if not result then
        TriggerClientEvent('QBCore:Notify', src, 'Xe không tồn tại', 'error')
        return
    end

    -- Xóa khỏi occasion
    MySQL.execute('DELETE FROM occasion_vehicles WHERE plate = ?', {plate})

    -- Lưu vào player_vehicles
    MySQL.insert('INSERT INTO player_vehicles (license, citizenid, vehicle, hash, mods, plate, state, spot_id) VALUES (?, ?, ?, ?, ?, ?, ?, ?)', {
        Player.PlayerData.license,
        Player.PlayerData.citizenid,
        result.model,
        GetHashKey(result.model),
        result.mods,
        result.plate,
        0,
        nil
    })

    TriggerClientEvent('QBCore:Notify', src, 'Mua xe thành công!', 'success')
end)
