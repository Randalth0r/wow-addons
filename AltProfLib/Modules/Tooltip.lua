local ADDON_NAME, ns = ...
local API = ns.API

-- ═══════════════════════════════════════════════════════════════════════════
-- AltProfLib Tooltip Module
-- WoW Retail 12.0.5 / 12.0.7 only
-- Only authorized API to add text to tooltips: TooltipDataProcessor.AddTooltipPostCall
-- ═══════════════════════════════════════════════════════════════════════════

local function IsKnownProfessionName(name)
    return type(name) == "string" and name ~= "" and name ~= "Unknown" and name ~= "Unknown Profession"
end

local function IsTooltipEnabled()
    local db = API.GetDB and API:GetDB()
    if not db then return false end
    db.settings = db.settings or {}
    if db.settings.tooltipEnabled == nil then db.settings.tooltipEnabled = true end
    return db.settings.tooltipEnabled == true
end

local function IsLinkDebugEnabled()
    local db = API.GetDB and API:GetDB()
    return db and db.settings and db.settings.linkDebug == true
end

local function PrintLinkDebug(source, link, parsed)
    if not IsLinkDebugEnabled() then return end
    API:Print("[LinkDebug] " .. tostring(source))
    print("- raw: " .. tostring(link or "nil"))
    if parsed then
        print("- type: " .. tostring(parsed.linkType or "unknown"))
        print("- id: " .. tostring(parsed.id or "unknown"))
    else
        print("- parsed: nil")
    end
end

local function ShortCharacterName(charKey)
    if type(charKey) ~= "string" then return tostring(charKey or "") end
    return charKey:match("^(.+)%-.+$") or charKey
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Class colors
-- ─────────────────────────────────────────────────────────────────────────────

local CLASS_COLORS = {
    WARRIOR     = "c79c6e", PALADIN     = "f58cba", HUNTER      = "abd473",
    ROGUE       = "fff569", PRIEST      = "ffffff", DEATHKNIGHT = "c41f3b",
    SHAMAN      = "0070de", MAGE        = "40c7eb", WARLOCK     = "8787ed",
    MONK        = "00ff96", DRUID       = "ff7d0a", DEMONHUNTER = "a330c9",
    EVOKER      = "33937f",
}

local GATHERING_PROFESSIONS = {
    ["Skinning"] = true, ["Herbalism"] = true, ["Mining"] = true,
    ["Fishing"]  = true, ["Cooking"]   = true, ["Archaeology"] = true,
    ["Scavenging"] = true,
}

local function GetCharacterClass(charKey)
    local db = API.GetDB and API:GetDB()
    if not db or not db.characters then return nil end
    local rec = db.characters[charKey]
    return rec and rec.class or nil
end

local function BuildOwnerLinesFromOwners(owners)
    local lines = {}
    if type(owners) ~= "table" then return lines end

    local sortedOwners = {}
    if API.GetSortedOwnersFromOwners then
        sortedOwners = API:GetSortedOwnersFromOwners(owners) or {}
    end

    for _, owner in ipairs(sortedOwners) do
        if not GATHERING_PROFESSIONS[owner.profession] then
            local name = owner.shortName or ShortCharacterName(owner.characterKey)
            local profession = IsKnownProfessionName(owner.profession) and owner.profession or nil
            local skill = tonumber(owner.skillLevel or 0) or 0
            local classFile = GetCharacterClass(owner.characterKey)
            local hex = classFile and CLASS_COLORS[classFile:upper()] or "ffffff"

            local nameColored = "|cff" .. hex .. "[" .. name .. "]|r"
            local statusText = skill > 0
                and "|cff00cc00[recipe learned]|r"
                or  "|cffcc0000[recipe not learned]|r"

            local profText = ""
            if profession then
                local icon = owner.icon
                if icon and type(icon) == "number" and icon > 0 then
                    profText = "  |T" .. tostring(icon) .. ":14:14:0:0|t  " .. profession
                else
                    profText = "  " .. profession
                end
            end

            table.insert(lines, nameColored .. profText .. "  " .. statusText)
        end
    end

    return lines
end

local function BuildOwnerLines(entry)
    if type(entry) ~= "table" then return {} end
    return BuildOwnerLinesFromOwners(entry.owners)
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Append AltProfLib block to the tooltip.
-- No state flags. AddTooltipPostCall is guaranteed by Blizzard to run on a clean slate.
-- ─────────────────────────────────────────────────────────────────────────────

local function AppendAltProfLibBlock(tooltip, lines)
    if not tooltip or type(lines) ~= "table" or #lines == 0 then return end

    tooltip:AddLine(" ")
    tooltip:AddLine("|cffffd700AltProfLib|r |cff66ccff— Known by:|r")
    for i = 1, math.min(#lines, 3) do
        tooltip:AddLine(tostring(lines[i]), 1, 1, 1, true)
    end
    if #lines > 3 then
        tooltip:AddLine("|cffaaaaaa+" .. tostring(#lines - 3) .. " more...|r")
    end
    tooltip:AddLine("|cffffd700Shift-Right Click: |r|cff66ccffPrepare Whisper|r")
    tooltip:AddLine(" ")
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Lookup DB
-- ─────────────────────────────────────────────────────────────────────────────

local function GetRecipeOwnerLines(recipeID)
    recipeID = tonumber(recipeID)
    if not recipeID then return nil end
    local entry = API.GetRecipeIndexEntry and API:GetRecipeIndexEntry(recipeID)
    if not entry then return nil end
    local lines = BuildOwnerLines(entry)
    if #lines == 0 then return nil end
    return lines
end

local function GetCraftedItemOwnerLines(itemID)
    itemID = tonumber(itemID)
    if not itemID then return nil end
    local itemEntry = API.GetCraftedItemEntry and API:GetCraftedItemEntry(itemID)
    if not itemEntry or type(itemEntry.recipes) ~= "table" then return nil end
    local lines = {}
    local recipeIDs = {}
    local seen = {}
    for recipeID in pairs(itemEntry.recipes) do
        table.insert(recipeIDs, tonumber(recipeID) or recipeID)
    end
    table.sort(recipeIDs)
    for _, recipeID in ipairs(recipeIDs) do
        local recipe = itemEntry.recipes[recipeID]
        if type(recipe) == "table" and type(recipe.owners) == "table" then
            for _, line in ipairs(BuildOwnerLines(recipe)) do
                if not seen[line] then seen[line] = true; table.insert(lines, line) end
            end
        end
    end
    if #lines == 0 then return nil end
    return lines
end

-- ─────────────────────────────────────────────────────────────────────────────
-- TooltipDataProcessor — only authorized API for tooltip decoration.
-- Hooks: Enum.TooltipDataType.Item and Enum.TooltipDataType.Recipe.
-- No state flags: re-insert lines on every callback invocation.
-- ─────────────────────────────────────────────────────────────────────────────

local function InstallTooltipDataProcessor()
    if not TooltipDataProcessor then return false end
    if not TooltipDataProcessor.AddTooltipPostCall then return false end
    if not Enum or not Enum.TooltipDataType then return false end

    -- Item: crafted items (inventory, bag, loot, profession output)
    if Enum.TooltipDataType.Item then
        TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tooltip, data)
            if not IsTooltipEnabled() then return end
            if type(data) ~= "table" or not data.id then return end
            local lines = GetCraftedItemOwnerLines(data.id)
            if lines then AppendAltProfLibBlock(tooltip, lines) end
        end)
    end

    -- Recipe: recipes in the profession frame and spell book
    if Enum.TooltipDataType.Recipe then
        TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Recipe, function(tooltip, data)
            if not IsTooltipEnabled() then return end
            if type(data) ~= "table" or not data.id then return end
            local lines = GetRecipeOwnerLines(data.id)
            if lines then AppendAltProfLibBlock(tooltip, lines) end
        end)
    end

    return true
end

-- ─────────────────────────────────────────────────────────────────────────────
-- ParseLinkPayload (used by chat hover and SetHyperlink)
-- ─────────────────────────────────────────────────────────────────────────────

function API:ParseLinkPayload(text)
    if type(text) ~= "string" then return nil end
    local linkType, payload = text:match("|H([^:|]+):([^|]+)|h")
    if not linkType then linkType, payload = text:match("^([^:|]+):(.+)$") end
    if not linkType or not payload then return nil end
    local firstNumber = tonumber(payload:match("^(%-?%d+)"))
    local numbers = {}
    for n in payload:gmatch("%-?%d+") do table.insert(numbers, tonumber(n) or n) end
    return { linkType = linkType, payload = payload, id = firstNumber, numbers = numbers }
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Chat hover (OnHyperlinkEnter) — separate path from TooltipDataProcessor.
-- Required because chat hyperlinks do not pass through the DataProcessor.
-- ─────────────────────────────────────────────────────────────────────────────

local function HandleHyperlinkTooltip(tooltip, link)
    local parsed = API.ParseLinkPayload and API:ParseLinkPayload(link)
    PrintLinkDebug("SetHyperlink", link, parsed)
    if not parsed then return end
    if parsed.linkType == "spell" or parsed.linkType == "enchant" then
        local lines = GetRecipeOwnerLines(parsed.id)
        if lines then AppendAltProfLibBlock(tooltip, lines) end
    elseif parsed.linkType == "item" then
        local lines = GetCraftedItemOwnerLines(parsed.id)
        if lines then AppendAltProfLibBlock(tooltip, lines) end
    end
end

local chatHoverHooksInstalled = {}

local function ShowTooltipForChatHyperlink(frame, linkData, linkText)
    if not IsTooltipEnabled() then return end
    local link = linkData or linkText
    if type(link) ~= "string" or link == "" then return end
    local parsed = API.ParseLinkPayload and API:ParseLinkPayload(link)
    if not parsed and type(linkText) == "string" then
        link = linkText
        parsed = API.ParseLinkPayload and API:ParseLinkPayload(link)
    end
    if not parsed then return end
    if parsed.linkType ~= "item" and parsed.linkType ~= "spell" and parsed.linkType ~= "enchant" then return end
    local tooltip = GameTooltip
    if not tooltip then return end
    tooltip:SetOwner(frame or UIParent, "ANCHOR_CURSOR")
    tooltip:SetHyperlink(link)
    -- SetHyperlink triggers TooltipDataProcessor, which calls our post-call.
    -- No need to decorate manually here.
    tooltip:Show()
end

local function InstallChatHyperlinkHoverHooks()
    if not _G then return false end
    local maxWindows = tonumber(NUM_CHAT_WINDOWS) or 10
    for i = 1, maxWindows do
        local frame = _G["ChatFrame" .. tostring(i)]
        if frame and frame.HookScript and not chatHoverHooksInstalled[frame] then
            chatHoverHooksInstalled[frame] = true
            frame:HookScript("OnHyperlinkEnter", function(self, linkData, link)
                ShowTooltipForChatHyperlink(self, linkData, link)
            end)
            frame:HookScript("OnHyperlinkLeave", function(self)
                if GameTooltip and GameTooltip:IsOwned(self) then GameTooltip:Hide() end
            end)
        end
    end
    return true
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Shift-Right Click draft
-- ─────────────────────────────────────────────────────────────────────────────

local function InstallShiftRightClickDraftHook()
    if not hooksecurefunc or not SetItemRef then return false end
    hooksecurefunc("SetItemRef", function(link, text, button)
        if button ~= "RightButton" or not IsShiftKeyDown or not IsShiftKeyDown() then return end
        local parsed = API.ParseLinkPayload and API:ParseLinkPayload(link)
        if not parsed then return end
        if parsed.linkType == "item" and parsed.id and API.DraftCrafterMessageForItem then
            API:DraftCrafterMessageForItem(parsed.id)
        elseif (parsed.linkType == "spell" or parsed.linkType == "enchant") and parsed.id and API.DraftCrafterMessage then
            API:DraftCrafterMessage(parsed.id)
        end
    end)
    return true
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Profession frame: draft via Shift-Right Click on OutputIcon
-- ─────────────────────────────────────────────────────────────────────────────

local function GetSelectedProfessionRecipeID()
    local pf = _G and _G.ProfessionsFrame
    local sf = pf and pf.CraftingPage and pf.CraftingPage.SchematicForm
    local sch = sf and sf.recipeSchematic
    return sch and tonumber(sch.recipeID) or nil
end

local function GetSelectedProfessionOutputItemID()
    local pf = _G and _G.ProfessionsFrame
    local sf = pf and pf.CraftingPage and pf.CraftingPage.SchematicForm
    if not sf then return nil end
    local outputIcon = sf.OutputIcon
    if outputIcon then
        if outputIcon.GetItemLink then
            local ok, link = pcall(function() return outputIcon:GetItemLink() end)
            if ok and type(link) == "string" then
                local parsed = API.ParseLinkPayload and API:ParseLinkPayload(link)
                if parsed and parsed.linkType == "item" and parsed.id then return parsed.id end
            end
        end
        if outputIcon.GetItem then
            local ok, _, link = pcall(function() return outputIcon:GetItem() end)
            if ok and type(link) == "string" then
                local parsed = API.ParseLinkPayload and API:ParseLinkPayload(link)
                if parsed and parsed.linkType == "item" and parsed.id then return parsed.id end
            end
        end
    end
    return nil
end

local function DraftFromSelectedProfessionRecipeOrItem()
    local recipeID = GetSelectedProfessionRecipeID()
    if recipeID and API.DraftCrafterMessage then
        API:DraftCrafterMessage(recipeID); return true
    end
    local itemID = GetSelectedProfessionOutputItemID()
    if itemID and API.DraftCrafterMessageForItem then
        API:DraftCrafterMessageForItem(itemID); return true
    end
    return false
end

local function IsShiftRightButton(button)
    return button == "RightButton" and IsShiftKeyDown and IsShiftKeyDown()
end

local function SafeHookScript(frame, scriptName, handler)
    if not frame or not frame.HookScript then return false end
    if frame.HasScript and not frame:HasScript(scriptName) then return false end
    local ok = pcall(function() frame:HookScript(scriptName, handler) end)
    return ok
end

local function HookProfessionOutputButton(button)
    if not button or button.__AltProfLibDraftHooked then return false end
    if not button.HookScript then return false end
    button.__AltProfLibDraftHooked = true
    SafeHookScript(button, "OnMouseUp", function(_, mouseButton)
        if IsShiftRightButton(mouseButton) then DraftFromSelectedProfessionRecipeOrItem() end
    end)
    SafeHookScript(button, "OnClick", function(_, mouseButton)
        if IsShiftRightButton(mouseButton) then DraftFromSelectedProfessionRecipeOrItem() end
    end)
    return true
end

local function InstallProfessionOutputDraftHooks()
    local pf = _G and _G.ProfessionsFrame
    local sf = pf and pf.CraftingPage and pf.CraftingPage.SchematicForm
    if not sf then return false end
    HookProfessionOutputButton(sf.OutputIcon)
    HookProfessionOutputButton(sf.OutputButton)
    HookProfessionOutputButton(sf.RecipeIcon)
    return true
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Boot
-- ─────────────────────────────────────────────────────────────────────────────

InstallTooltipDataProcessor()
InstallShiftRightClickDraftHook()
InstallProfessionOutputDraftHooks()
InstallChatHyperlinkHoverHooks()

if C_Timer and C_Timer.After then
    C_Timer.After(1, function()
        InstallProfessionOutputDraftHooks()
        InstallChatHyperlinkHoverHooks()
    end)
end

local profEventFrame = CreateFrame and CreateFrame("Frame")
if profEventFrame then
    profEventFrame:RegisterEvent("TRADE_SKILL_SHOW")
    profEventFrame:RegisterEvent("TRADE_SKILL_LIST_UPDATE")
    profEventFrame:RegisterEvent("TRADE_SKILL_DATA_SOURCE_CHANGED")
    profEventFrame:SetScript("OnEvent", function()
        InstallProfessionOutputDraftHooks()
    end)
end

if hooksecurefunc and FCF_OpenTemporaryWindow then
    hooksecurefunc("FCF_OpenTemporaryWindow", function()
        InstallChatHyperlinkHoverHooks()
    end)
end
