NPCProgramHelpersBridge = NPCProgramHelpersBridge or {}

function NPCProgramHelpersBridge.PredicateAll(item)
    -- item:getType()
	return true
end

function NPCProgramHelpersBridge.PredicateSpoilableFood(item)
    local category = item:getDisplayCategory()
    if category == "Food" then
        local canSpoil = item:getOffAgeMax() < 1000
        if canSpoil then
            return true
        end
    end
    return false
end

function NPCProgramHelpersBridge.GetItem(bandit, itemTypeTab, cnt)
    local task
    local obj
    local itemType
    for _, it in pairs(itemTypeTab) do
        local o = NPCBaseClient.GetContainerWithItem(bandit, it, cnt)
        if o then 
            obj = o
            itemType = it
            break
        end
    end

    if not obj then return end

    local square = obj
    if not instanceof(obj, "IsoGridSquare") then square = obj:getParent():getSquare() end

    local asquare = AdjacentFreeTileFinder.Find(square, bandit)
    if not asquare then return end

    local dist = NPCUtils.DistTo(bandit:getX(), bandit:getY(), asquare:getX() + 0.5, asquare:getY() + 0.5)
    if dist > 0.90 then
        -- bandit:addLineChatElement(("go collect: " .. itemType), 1, 1, 1)
        task = NPCUtils.GetMoveTask(0, asquare:getX(), asquare:getY(), asquare:getZ(), "Walk", dist, false)
    else
        if instanceof(obj, "IsoGridSquare") then
            -- bandit:addLineChatElement(("pickup " .. itemType), 1, 1, 1)
            task = {action="PickUp", anim="LootLow", itemType=itemType, x=square:getX(), y=square:getY(), z=square:getZ(), cnt=cnt}
        else
            -- bandit:addLineChatElement(("take from container: " .. itemType), 1, 1, 1)
            task = {action="TakeFromContainer", anim="Loot", itemType=itemType, x=square:getX(), y=square:getY(), z=square:getZ(), cnt=cnt}
        end
    end
    return task
end
