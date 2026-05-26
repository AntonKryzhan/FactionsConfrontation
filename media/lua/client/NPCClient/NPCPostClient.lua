NPCPostClient = NPCPostClient or {}

local function getGMD()
    if GetNPCModData then
        local ok, gmd = pcall(GetNPCModData)
        if ok and gmd then
            gmd.Posts = gmd.Posts or {}
            return gmd
        end
    end
    return { Posts = {} }
end

local function postId(x, y, z)
    return tostring(x) .. "-" .. tostring(y) .. "-" .. tostring(z)
end

local function sendPostCommand(player, command, args)
    if not player or not sendClientCommand then
        return false
    end
    sendClientCommand(player, "NPCCommands", command, args)
    return true
end

function NPCPostClient.GuardToggle(player, x, y, z)
    return sendPostCommand(player, "PostToggle", { x = x, y = y, z = z, type = "guard" })
end

function NPCPostClient.Update(player, post)
    if type(post) ~= "table" then
        return false
    end
    return sendPostCommand(player, "PostUpdate", post)
end

function NPCPostClient.At(character, ptype)
    if not character or not character.getX or not character.getY or not character.getZ then
        return false
    end

    local gmd = getGMD()
    local px = math.floor(character:getX())
    local py = math.floor(character:getY())
    local pz = character:getZ()

    for _, gp in pairs(gmd.Posts or {}) do
        if gp and gp.x == px and gp.y == py and gp.z == pz and (not ptype or gp.type == ptype) then
            return true
        end
    end
    return false
end

function NPCPostClient.GetAll()
    return getGMD().Posts or {}
end

local function distanceToPost(gp, x, y)
    if not gp or not gp.x or not gp.y or not x or not y then
        return nil
    end
    if NPCUtils and NPCUtils.DistTo then
        return NPCUtils.DistTo(gp.x, gp.y, x, y)
    end
    local dx = gp.x - x
    local dy = gp.y - y
    return math.sqrt(dx * dx + dy * dy)
end

function NPCPostClient.GetInRadius(character, ptype, radius)
    local nearPosts = {}
    if not character or not character.getX or not character.getY or not radius then
        return nearPosts
    end

    local px = character:getX()
    local py = character:getY()
    for id, gp in pairs(getGMD().Posts or {}) do
        local dist = distanceToPost(gp, px, py)
        if dist and dist < radius and (not ptype or gp.type == ptype) then
            nearPosts[id] = gp
        end
    end
    return nearPosts
end

local function squareHasOccupant(square)
    if not square then return true end
    if square.getZombie and square:getZombie() then return true end
    if square.getMovingObjects then
        local moving = square:getMovingObjects()
        if moving and moving.size and moving:size() > 0 then
            return true
        end
    end
    return false
end

function NPCPostClient.GetClosestFree(character, ptype, radius)
    if not character or not character.getX or not character.getY or not radius then
        return nil
    end

    local cell = getCell and getCell() or nil
    if not cell or not cell.getGridSquare then
        return nil
    end

    local px = character:getX()
    local py = character:getY()
    local bestDist = radius
    local bestPost = nil

    for _, gp in pairs(getGMD().Posts or {}) do
        if gp and (not ptype or gp.type == ptype) then
            local dist = distanceToPost(gp, px, py)
            if dist and dist <= radius and dist < bestDist then
                local square = cell:getGridSquare(gp.x, gp.y, gp.z)
                if square and not squareHasOccupant(square) then
                    bestPost = gp
                    bestDist = dist
                end
            end
        end
    end

    return bestPost
end

function NPCPostClient.Get(x, y, z, ptype)
    local post = (getGMD().Posts or {})[postId(x, y, z)]
    if post and (not ptype or post.type == ptype) then
        return post
    end
    return nil
end

function NPCPostClient.Render()
    if not ZSPosts or not getPlayer or not getCell then
        return false
    end
    local playerObj = getPlayer()
    if not playerObj then
        return false
    end
    local bo = ZSPosts:new("", "", playerObj)
    getCell():setDrag(bo, playerObj:getPlayerNum())
    return true
end

function NPCPostClient.OnKeyPressed(keynum)
    if not NPCCompatibilityBridge or not NPCCompatibilityBridge.GetGuardpostKey then
        return
    end
    if keynum == NPCCompatibilityBridge.GetGuardpostKey() then
        NPCPostClient.Render()
    end
end

function NPCPostClient.Install()
    if NPCPostClient._installed then
        return
    end
    NPCPostClient._installed = true
    if Events and Events.OnKeyPressed and Events.OnKeyPressed.Add then
        Events.OnKeyPressed.Add(NPCPostClient.OnKeyPressed)
    end
end

return NPCPostClient
