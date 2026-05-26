-- NPCClanCreatorBridge.lua
-- Neutral bridge for the legacy clan/outfit customization panel.

pcall(require, "ISUI/ISPanel")
pcall(require, "ISUI/ISLabel")
pcall(require, "ISUI/ISComboBox")

NPCClanCreatorBridge = NPCClanCreatorBridge or {}

local CustomizationUIBase = rawget(_G, "CustomizationUI")
if not CustomizationUIBase then
    CustomizationUIBase = ISPanel:derive("CustomizationUI")
end

CustomizationUI = CustomizationUIBase

function CustomizationUI:new(x, y, width, height)
    local o = ISPanel.new(self, x, y, width, height)
    setmetatable(o, self)
    self.__index = self
    o.backgroundColor = {r=0, g=0, b=0, a=0.7}
    o.borderColor = {r=1, g=1, b=1, a=1}
    o:initialise()
    return o
end

function CustomizationUI:initialise()
    ISPanel.initialise(self)
    self:createChildren()
end

function CustomizationUI:createChildren()
    print("createChildren: Start")

    local padding = 10
    local labelWidth = 120
    local controlWidth = 200
    local controlHeight = 25
    local startY = 10

    local playerObj = getPlayer()
    if not playerObj then
        print("Error: playerObj is nil")
        return
    end

    local kahluaTable = {}
    self.modelPreview = UI3DModel:new(kahluaTable)
    if not self.modelPreview then
        print("Error: modelPreview is nil after creation")
        return
    end

    self.modelPreview:setCharacter(playerObj)
    self.modelPreview:setZoom(1.0)
    self.modelPreview:setIsometric(true)
    self.modelPreview:setXOffset(0)
    self.modelPreview:setYOffset(0)

    self.modelPreviewX = padding
    self.modelPreviewY = startY

    local startX = padding + controlWidth + padding

    startY = self:addLabelAndDropdown(startX, startY, labelWidth, controlHeight, "Gender:", {"Male", "Female"}, 1, function(option)
        self.isFemale = (option == "Female")
        self:populateOutfitDropdown(self.isFemale)
    end)

    startY = startY + controlHeight + padding

    self.outfitDropdown = ISComboBox:new(startX + labelWidth, startY, 150, controlHeight, self, nil)
    if not self.outfitDropdown then
        print("Error: outfitDropdown is nil after creation")
    else
        self.outfitDropdown:initialise()
        self:addChild(self.outfitDropdown)
    end

    self:populateOutfitDropdown(false)

    print("createChildren: End")
end

function CustomizationUI:addLabelAndDropdown(x, y, labelWidth, height, labelText, options, selectedIndex, onChange)
    local label = ISLabel:new(x, y, height, labelText, 1, 1, 1, 1, UIFont.Small, true)
    self:addChild(label)
    local dropdown = ISComboBox:new(x + labelWidth, y, 150, height, self, nil)
    dropdown:initialise()
    for i, option in ipairs(options) do
        dropdown:addOption(option)
    end
    dropdown.selected = selectedIndex
    dropdown.onChange = function()
        onChange(dropdown:getSelectedText())
    end
    self:addChild(dropdown)
    return y + height + 10
end

function CustomizationUI:populateOutfitDropdown(isFemale)
    if not self.outfitDropdown then
        print("Error: outfitDropdown is nil, cannot populate")
        return
    end

    local outfits = getAllOutfits(isFemale)
    
    if not outfits or type(outfits) ~= "table" then
        print("Error: getAllOutfits returned nil or is not a table")
        return
    end
    
    self.outfitDropdown:clear()

    for i = 1, #outfits do
        local outfitName = outfits[i]
        self.outfitDropdown:addOption(outfitName)
    end

    if #outfits > 0 then
        self.outfitDropdown.selected = 1
        self:updateModelOutfit(outfits[1])
    end
end

function CustomizationUI:updateModelOutfit(outfitName)
    self.modelPreview:setOutfitName(outfitName, self.isFemale or false, false)
    self.modelPreview:render()
end

function CustomizationUI:render()
    ISPanel.render(self)

    if self.modelPreview then
        local x = self:getAbsoluteX() + self.modelPreviewX
        local y = self:getAbsoluteY() + self.modelPreviewY
        self.modelPreview:setX(x)
        self.modelPreview:setY(y)
        self.modelPreview:render()
    else
        print("Error: modelPreview is nil in render")
    end
end

function NPCClanCreatorBridge.ShowCustomizationUI()
    local ui = CustomizationUI:new(100, 100, 600, 700)
    ui:initialise()
    ui:addToUIManager()
    return ui
end

ShowCustomizationUI = NPCClanCreatorBridge.ShowCustomizationUI

return NPCClanCreatorBridge
