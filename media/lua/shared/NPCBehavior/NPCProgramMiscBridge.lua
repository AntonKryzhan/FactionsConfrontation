NPCProgramMiscBridge = NPCProgramMiscBridge or {}

function NPCProgramMiscBridge.ReturnFood(bandit)
    local tasks = {}

    local container = NPCBaseClient.GetContainerOfType(bandit, "freezer")

    if not container then
        container = NPCBaseClient.GetContainerOfType(bandit, "fridge")
    end
    if not container then return tasks end
    local inventory = bandit:getInventory()

    local itemType
    local items = ArrayList.new()
    inventory:getAllEvalRecurse(NPCProgramHelpersBridge.PredicateSpoilableFood, items)
    if items:size() == 0 then return tasks end

    local square = container:getParent():getSquare()
    local asquare = AdjacentFreeTileFinder.Find(square, bandit)
    if asquare then
        local dist = NPCUtils.DistTo(bandit:getX(), bandit:getY(), asquare:getX() + 0.5, asquare:getY() + 0.5)
        if dist > 0.90 then
            -- bandit:addLineChatElement(("go put food to fridge"), 1, 1, 1)
            table.insert(tasks, NPCUtils.GetMoveTask(0, asquare:getX(), asquare:getY(), asquare:getZ(), "Walk", dist, false))
            return tasks
        else
            for i=0, items:size()-1 do
                -- bandit:addLineChatElement(("put food to fridge"), 1, 1, 1)
                local item = items:get(i)
                local itemType = item:getFullType()
                local task = {action="PutInContainer", anim="Loot", itemType=itemType, x=square:getX(), y=square:getY(), z=square:getZ()}
                table.insert(tasks, task)
            end
            return tasks
        end
    end

    return tasks
end
