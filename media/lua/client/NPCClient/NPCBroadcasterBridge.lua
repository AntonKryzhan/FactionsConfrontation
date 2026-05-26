-- NPCBroadcasterBridge.lua
-- Neutral client bridge for the legacy legacy broadcaster client module.

require "NPCCore/NPCLegacyGlobalsBridge"
NPCBroadcasterBridge = NPCBroadcasterBridge or {}

NPCBroadcasterBridge.Messages = {}

NPCBroadcasterBridge.AddBroadcast = function(message)
    table.insert(NPCBroadcasterBridge.Messages, message)
end

NPCBroadcasterBridge.tick = 0

NPCBroadcasterBridge.BroadCast = function()
    if #NPCBroadcasterBridge.Messages == 0 then return end
    -- clearTvScreenSprites()

    if NPCBroadcasterBridge.tick == 0 then   
        local world = getWorld()
        local message = NPCBroadcasterBridge.Messages[1]
        for _, object in pairs(message.tvs) do
            if instanceof(object, "IsoTelevision") then
                if message.text == "END" then
                    object:setOverlaySprite(nil)
                else
                    local dd = object:getDeviceData()
                    if dd:getIsTurnedOn() and object:getX() and object:getY() and object:getZ() then
                        dd:StopPlayMedia()
                        dd:setDeviceVolume(0.01)

                        -- object:clearTvScreenSprites()
                        -- object:setOverlaySprite("appliances_television_01_20")
                        object:Say(message.text)

                        if message.sound then
                            local emitter = world:getFreeEmitter(object:getX(), object:getY(), object:getZ())
                            emitter:setVolumeAll(0.2)
                            emitter:playSound(message.sound)
                            -- dd:playSound(message.sound, 1, true)
                        end
                    end
                end
            end
        end
        table.remove(NPCBroadcasterBridge.Messages, 1)
    end

    NPCBroadcasterBridge.tick = NPCBroadcasterBridge.tick + 1

    if NPCBroadcasterBridge.tick == 3 then
        NPCBroadcasterBridge.tick = 0
    end
end


-- Events.EveryOneMinute.Add(NPCBroadcasterBridge.BroadCast)

NPCLegacyGlobalsBridge.InstallAlias("Broadcaster", NPCBroadcasterBridge, "NPCBroadcasterBridge")
