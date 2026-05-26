require "NPCCore/NPCLegacyGlobalsBridge"

ZSPosts = ISBuildingObject:derive("ZSPosts")

local function zsp_getPlayer(character)
    if character then return character end
    if getPlayer then return getPlayer() end
    return nil
end

local function zsp_getFloorSprite()
    if ZSPosts.floorSprite then return ZSPosts.floorSprite end

    local sprite = IsoSprite.new()
    sprite:LoadFramesNoDirPageSimple("media/ui/FloorTileCursor.png")
    ZSPosts.floorSprite = sprite
    return sprite
end

local function zsp_squareIsUsable(square)
    if not square then return false end
    if type(square.TreatAsSolidFloor) == "function" and not square:TreatAsSolidFloor() then return false end
    if type(square.isFree) == "function" and not square:isFree(false) then return false end
    return true
end

local function zsp_postColor(postType)
    if postType == "container-to" then return 0, 0, 1 end
    if postType == "container-from" then return 0, 1, 1 end
    return 1, 1, 0
end

local function zsp_postProvider()
    return NPCPost or NPCPostClient or NPCLegacyGlobalsBridge.Get("Post")
end

function ZSPosts:create(x, y, z, north, sprite)
    local provider = zsp_postProvider()
    if not provider or type(provider.GuardToggle) ~= "function" then return end

    local player = zsp_getPlayer(self.character)
    if not player then return end

    provider.GuardToggle(player, x, y, z)
end

function ZSPosts:walkTo(x, y, z)
    return true
end

function ZSPosts:isValid(square)
    return zsp_squareIsUsable(square)
end

function ZSPosts:render(x, y, z, square)
    local player = zsp_getPlayer(self.character)
    if not player then return end

    local floorSprite = zsp_getFloorSprite()
    local canPlace = self:isValid(square)
    local existingPostAtCursor = false

    local postType
    if not isDebugEnabled() then postType = "guard" end

    local posts = {}
    local provider = zsp_postProvider()
    if provider and type(provider.GetInRadius) == "function" then
        posts = provider.GetInRadius(player, postType, 40) or {}
    end

    for id, gp in pairs(posts) do
        if gp then
            local alpha = 0.05
            if gp.z == player:getZ() then alpha = 0.8 end

            local r, g, b = zsp_postColor(gp.type)
            floorSprite:RenderGhostTileColor(gp.x, gp.y, gp.z, r, g, b, alpha)

            if gp.x == x and gp.y == y and gp.z == z then
                existingPostAtCursor = true
            end
        end
    end

    if existingPostAtCursor then
        floorSprite:RenderGhostTileColor(x, y, z, 1, 0, 0, 0.8)
    elseif canPlace then
        floorSprite:RenderGhostTileColor(x, y, z, 0, 1, 0, 0.8)
    else
        floorSprite:RenderGhostTileColor(x, y, z, 1, 0, 0, 0.8)
    end
end

function ZSPosts:new(sprite, northSprite, character)
    local o = {}
    setmetatable(o, self)
    self.__index = self

    o:init()
    o:setSprite(sprite)
    o:setNorthSprite(northSprite)
    o.character = character
    o.player = character and character:getPlayerNum() or 0
    o.noNeedHammer = true
    o.skipBuildAction = true

    return o
end
