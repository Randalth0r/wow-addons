local ADDON_NAME, ns = ...
local API = ns.API

local Recipes = CreateFrame("Frame")
Recipes:RegisterEvent("TRADE_SKILL_LIST_UPDATE")
Recipes:RegisterEvent("TRADE_SKILL_DATA_SOURCE_CHANGED")
Recipes:RegisterEvent("TRADE_SKILL_SHOW")

local function GetAllRecipeIDs()
    if C_TradeSkillUI and C_TradeSkillUI.GetAllRecipeIDs then
        return API:SafeCall(C_TradeSkillUI.GetAllRecipeIDs)
    end
    return nil
end

local function GetRecipeInfo(recipeID)
    if C_TradeSkillUI and C_TradeSkillUI.GetRecipeInfo then
        return API:SafeCall(C_TradeSkillUI.GetRecipeInfo, recipeID)
    end
    return nil
end

local function GetBaseProfessionInfo()
    if C_TradeSkillUI and C_TradeSkillUI.GetBaseProfessionInfo then
        return API:SafeCall(C_TradeSkillUI.GetBaseProfessionInfo)
    end
    return nil
end

local function ResolveProfessionID(recipeInfo, baseInfo)
    if recipeInfo then
        if recipeInfo.professionID then return tonumber(recipeInfo.professionID) end
        if recipeInfo.skillLineID then return tonumber(recipeInfo.skillLineID) end
        if recipeInfo.parentProfessionID then return tonumber(recipeInfo.parentProfessionID) end
    end
    if baseInfo then
        if baseInfo.professionID then return tonumber(baseInfo.professionID) end
        if baseInfo.skillLineID then return tonumber(baseInfo.skillLineID) end
    end
    return 0
end


local function ExtractItemIDFromLink(link)
    if type(link) ~= "string" then return nil end
    return tonumber(link:match("item:(%-?%d+)"))
end

local function ResolveCraftedItemID(recipeID, recipeInfo)
    recipeID = tonumber(recipeID)
    if not recipeID then return nil, nil end

    -- Midnight/modern profession APIs expose crafted output through different shapes
    -- depending on recipe type, quality support, cache state, and build. Keep this
    -- deliberately defensive: first direct item fields, then output item data, then
    -- schematic data, then hyperlinks.
    if type(recipeInfo) == "table" then
        local direct = tonumber(recipeInfo.itemID or recipeInfo.outputItemID or recipeInfo.outputItemId or recipeInfo.productID or recipeInfo.productItemID)
        if direct and direct > 0 then return direct, "recipeInfo" end
        local linkID = ExtractItemIDFromLink(recipeInfo.hyperlink or recipeInfo.link or recipeInfo.itemLink or recipeInfo.outputItemLink)
        if linkID and linkID > 0 then return linkID, "recipeInfoLink" end
    end

    if C_TradeSkillUI and C_TradeSkillUI.GetRecipeOutputItemData then
        local outputData = API:SafeCall(C_TradeSkillUI.GetRecipeOutputItemData, recipeID)
        if type(outputData) == "table" then
            local direct = tonumber(outputData.itemID or outputData.outputItemID or outputData.productID or outputData.productItemID)
            if direct and direct > 0 then return direct, "outputData" end
            local linkID = ExtractItemIDFromLink(outputData.hyperlink or outputData.link or outputData.itemLink)
            if linkID and linkID > 0 then return linkID, "outputDataLink" end
        end
    end

    if C_TradeSkillUI and C_TradeSkillUI.GetRecipeSchematic then
        local schematic = API:SafeCall(C_TradeSkillUI.GetRecipeSchematic, recipeID, false)
        if type(schematic) == "table" then
            local direct = tonumber(schematic.outputItemID or schematic.itemID or schematic.productID or schematic.productItemID)
            if direct and direct > 0 then return direct, "schematic" end
            local linkID = ExtractItemIDFromLink(schematic.outputItemHyperlink or schematic.outputItemLink or schematic.itemLink)
            if linkID and linkID > 0 then return linkID, "schematicLink" end
            if type(schematic.outputItemData) == "table" then
                local data = schematic.outputItemData
                local id = tonumber(data.itemID or data.outputItemID or data.productID or data.productItemID)
                if id and id > 0 then return id, "schematicOutputData" end
                local dataLinkID = ExtractItemIDFromLink(data.hyperlink or data.link or data.itemLink)
                if dataLinkID and dataLinkID > 0 then return dataLinkID, "schematicOutputDataLink" end
            end
        end
    end

    if C_TradeSkillUI and C_TradeSkillUI.GetRecipeItemLink then
        local itemLink = API:SafeCall(C_TradeSkillUI.GetRecipeItemLink, recipeID)
        local linkID = ExtractItemIDFromLink(itemLink)
        if linkID and linkID > 0 then return linkID, "recipeItemLink" end
    end

    return nil, nil
end

local function ResolveProfessionName(recipeInfo, baseInfo)
    if recipeInfo then
        if recipeInfo.profession and recipeInfo.profession ~= "" then return recipeInfo.profession end
        if recipeInfo.parentProfessionName and recipeInfo.parentProfessionName ~= "" then return recipeInfo.parentProfessionName end
    end
    if baseInfo then
        if baseInfo.professionName and baseInfo.professionName ~= "" then return baseInfo.professionName end
        if baseInfo.name and baseInfo.name ~= "" then return baseInfo.name end
    end
    return "Unknown"
end

function API:ScanOpenTradeSkillRecipes(reason)
    if not C_TradeSkillUI then return 0 end

    local recipeIDs = GetAllRecipeIDs()
    if type(recipeIDs) ~= "table" then return 0 end

    local char, charKey = self:GetCharacterRecord()
    if not char then return 0 end

    local baseInfo = GetBaseProfessionInfo()
    local scanned = 0
    local byProfession = {}
    local byCraftedItem = 0

    for _, recipeID in ipairs(recipeIDs) do
        local recipeInfo = GetRecipeInfo(recipeID)
        if recipeInfo and recipeInfo.learned then
            local professionID = ResolveProfessionID(recipeInfo, baseInfo)
            local professionName = ResolveProfessionName(recipeInfo, baseInfo)
            local primaryBucket, legacyBucket = self:EnsureRecipeBucket(charKey, professionID)

            local craftedItemID, craftedItemSource = ResolveCraftedItemID(recipeID, recipeInfo)

            local payload = {
                recipeID = tonumber(recipeID),
                name = recipeInfo.name,
                learned = true,
                professionID = professionID,
                profession = professionName,
                skillLineAbilityID = recipeInfo.skillLineAbilityID,
                categoryID = recipeInfo.categoryID,
                icon = recipeInfo.icon,
                craftedItemID = craftedItemID,
                craftedItemSource = craftedItemSource,
                lastSeen = time(),
            }

            primaryBucket[tonumber(recipeID)] = payload
            legacyBucket[tonumber(recipeID)] = true

            byProfession[professionID] = (byProfession[professionID] or 0) + 1
            if craftedItemID then byCraftedItem = byCraftedItem + 1 end
            scanned = scanned + 1
        end
    end

    char.lastRecipeScan = time()
    if self.RebuildRecipeOwnerIndex then
        self:RebuildRecipeOwnerIndex(reason or "recipe scan")
    end
    if self.RebuildCraftedItemIndex then
        self:RebuildCraftedItemIndex(reason or "recipe scan")
    end
    self:Log("SCAN_RECIPES", { reason = reason or "manual", count = scanned, craftedItems = byCraftedItem, byProfession = byProfession })
    self:Debug("recipe scan complete", reason or "manual", scanned)
    return scanned
end

Recipes:SetScript("OnEvent", function(_, event)
    if not API or not API.GetDB or not AltProfLibDB then return end
    if event == "TRADE_SKILL_SHOW" or event == "TRADE_SKILL_LIST_UPDATE" or event == "TRADE_SKILL_DATA_SOURCE_CHANGED" then
        API:ScanProfessions(event)
        API:ScanOpenTradeSkillRecipes(event)
    end
end)
