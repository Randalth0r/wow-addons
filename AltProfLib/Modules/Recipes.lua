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

local function AppendUniqueItemID(list, seen, itemID)
    itemID = tonumber(itemID)
    if not itemID or itemID <= 0 or seen[itemID] then return end
    seen[itemID] = true
    table.insert(list, itemID)
end

-- Quality-crafted reagents/gear expose one item ID per quality tier.
-- Chat links and tooltips often use Q2/Q3 IDs while recipeInfo.hyperlink is Q1.
local function CollectCraftedItemIDs(recipeID, recipeInfo)
    recipeID = tonumber(recipeID)
    local ids, seen = {}, {}
    if not recipeID then return ids, nil end

    if type(recipeInfo) == "table" then
        if type(recipeInfo.qualityItemIDs) == "table" then
            for _, itemID in ipairs(recipeInfo.qualityItemIDs) do
                AppendUniqueItemID(ids, seen, itemID)
            end
        end
        AppendUniqueItemID(ids, seen, recipeInfo.itemID or recipeInfo.outputItemID or recipeInfo.outputItemId or recipeInfo.productID or recipeInfo.productItemID)
        AppendUniqueItemID(ids, seen, ExtractItemIDFromLink(recipeInfo.hyperlink or recipeInfo.link or recipeInfo.itemLink or recipeInfo.outputItemLink))
    end

    if C_TradeSkillUI and C_TradeSkillUI.GetRecipeQualityItemIDs then
        local qualityItemIDs = API:SafeCall(C_TradeSkillUI.GetRecipeQualityItemIDs, recipeID)
        if type(qualityItemIDs) == "table" then
            for _, itemID in ipairs(qualityItemIDs) do
                AppendUniqueItemID(ids, seen, itemID)
            end
        end
    end

    local maxQuality = (type(recipeInfo) == "table" and tonumber(recipeInfo.maxQuality)) or 5
    if maxQuality < 1 then maxQuality = 1 end
    if maxQuality > 5 then maxQuality = 5 end

    if C_TradeSkillUI and C_TradeSkillUI.GetRecipeOutputItemData then
        for quality = 1, maxQuality do
            local outputData = API:SafeCall(C_TradeSkillUI.GetRecipeOutputItemData, recipeID, nil, nil, quality)
            if type(outputData) == "table" then
                AppendUniqueItemID(ids, seen, outputData.itemID or outputData.outputItemID or outputData.productID or outputData.productItemID)
                AppendUniqueItemID(ids, seen, ExtractItemIDFromLink(outputData.hyperlink or outputData.link or outputData.itemLink))
            end
        end

        -- Also try the unreagents/default output once (some recipes ignore overrideQualityID).
        local outputData = API:SafeCall(C_TradeSkillUI.GetRecipeOutputItemData, recipeID)
        if type(outputData) == "table" then
            AppendUniqueItemID(ids, seen, outputData.itemID or outputData.outputItemID or outputData.productID or outputData.productItemID)
            AppendUniqueItemID(ids, seen, ExtractItemIDFromLink(outputData.hyperlink or outputData.link or outputData.itemLink))
        end
    end

    if C_TradeSkillUI and C_TradeSkillUI.GetRecipeSchematic then
        local schematic = API:SafeCall(C_TradeSkillUI.GetRecipeSchematic, recipeID, false)
        if type(schematic) == "table" then
            AppendUniqueItemID(ids, seen, schematic.outputItemID or schematic.itemID or schematic.productID or schematic.productItemID)
            AppendUniqueItemID(ids, seen, ExtractItemIDFromLink(schematic.outputItemHyperlink or schematic.outputItemLink or schematic.itemLink))
            if type(schematic.outputItemData) == "table" then
                local data = schematic.outputItemData
                AppendUniqueItemID(ids, seen, data.itemID or data.outputItemID or data.productID or data.productItemID)
                AppendUniqueItemID(ids, seen, ExtractItemIDFromLink(data.hyperlink or data.link or data.itemLink))
            end
        end
    end

    if C_TradeSkillUI and C_TradeSkillUI.GetRecipeItemLink then
        AppendUniqueItemID(ids, seen, ExtractItemIDFromLink(API:SafeCall(C_TradeSkillUI.GetRecipeItemLink, recipeID)))
    end

    local source = nil
    if #ids > 0 then
        if type(recipeInfo) == "table" and type(recipeInfo.qualityItemIDs) == "table" and #recipeInfo.qualityItemIDs > 0 then
            source = "qualityItemIDs"
        elseif C_TradeSkillUI and C_TradeSkillUI.GetRecipeQualityItemIDs then
            source = "GetRecipeQualityItemIDs"
        else
            source = "resolved"
        end
    end

    return ids, source
end

local function ResolveCraftedItemID(recipeID, recipeInfo)
    local ids, source = CollectCraftedItemIDs(recipeID, recipeInfo)
    if #ids > 0 then
        return ids[1], source, ids
    end
    return nil, nil, ids
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

            local craftedItemID, craftedItemSource, craftedItemIDs = ResolveCraftedItemID(recipeID, recipeInfo)

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
                craftedItemIDs = (craftedItemIDs and #craftedItemIDs > 0) and craftedItemIDs or nil,
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
