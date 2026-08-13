local ADDON_NAME, ns = ...
-- AltProfLib release 1.0.2
local API = ns.API

local function PrintHelp()
    API:Print("commands:")
    print("  /apl help     - show commands")
    print("  /apl scan     - force profession scan and scan open profession recipes")
    print("  /apl roster   - show saved profession roster")
    print("  /apl owners   - show profession owner map")
    print("  /apl recipes  - show known recipe count for current character")
    print("  /apl recipe <RecipeID> - show which characters know a recipe")
    print("  /apl item <ItemID> - show which characters can craft an item")
    print("  /apl recipesample - show real saved RecipeIDs for testing")
    print("  /apl stats    - show account database stats")
    print("  /apl inspect <link> - parse a WoW item/spell link for debugging")
    print("  /apl draft <RecipeID> [targetName] - prepare a non-sending crafter reply in chat")
    print("  /apl draftitem <ItemID> [targetName] - prepare a non-sending item craft reply in chat")
    print("  /apl draftpreview <RecipeID> [targetName] - print the draft text without opening chat")
    print("  /apl draftitempreview <ItemID> [targetName] - print the item draft text")
    print("  /apl tooltip on|off - enable/disable AltProfLib tooltip lines")
    print("  /apl tooltipdebug - toggle ItemID tooltip debug")
    print("  /apl linkdebug - toggle hyperlink diagnostics")
    print("  Tooltip: mouseover saved craftable items to show owners")
    print("  Tooltip action: Shift-Right Click an item link to open Craft Reply")
    print("  /apl debug    - toggle debug output")
    print("  /apl version  - show addon version")
end

local function PrintRoster()
    local db = API:GetDB()
    if not db or not db.characters then return end

    API:Print("account profession roster:")
    for charKey, rec in pairs(db.characters) do
        local parts = {}
        if rec.professions then
            for profName, info in pairs(rec.professions) do
                table.insert(parts, string.format("%s %s/%s", profName, tostring(info.skillLevel or "?"), tostring(info.maxSkillLevel or "?")))
            end
        end
        table.sort(parts)
        print("- " .. charKey .. ": " .. (#parts > 0 and table.concat(parts, ", ") or "no professions saved"))
    end
end

local function PrintOwners()
    if API.RebuildProfessionIndex then API:RebuildProfessionIndex("slash owners") end
    local index = API:GetProfessionIndex()

    API:Print("profession owners:")
    local ids = {}
    for professionID in pairs(index or {}) do table.insert(ids, professionID) end
    table.sort(ids)

    if #ids == 0 then
        print("- no profession owners saved yet")
        return
    end

    for _, professionID in ipairs(ids) do
        local bucket = index[professionID]
        print("- " .. tostring(bucket.name or "Profession") .. " [" .. tostring(professionID) .. "]")
        local chars = {}
        for charKey in pairs(bucket.characters or {}) do table.insert(chars, charKey) end
        table.sort(chars)
        for _, charKey in ipairs(chars) do
            local owner = bucket.characters[charKey]
            print("    " .. charKey .. " " .. tostring(owner.skillLevel or "?") .. "/" .. tostring(owner.maxSkillLevel or "?"))
        end
    end
end

local function PrintRecipeCounts()
    local charKey = API:GetCharacterKey()
    local recipes = API:GetKnownRecipes(charKey)
    API:Print("known recipes for " .. charKey .. ": " .. tostring(API:GetKnownRecipeCount(charKey)))

    if type(recipes) ~= "table" then return end
    local profIDs = {}
    for professionID in pairs(recipes) do table.insert(profIDs, professionID) end
    table.sort(profIDs)
    for _, professionID in ipairs(profIDs) do
        print("- professionID " .. tostring(professionID) .. ": " .. tostring(API:GetKnownRecipeCount(charKey, professionID)))
    end
end


local function IsKnownProfessionName(name)
    return type(name) == "string" and name ~= "" and name ~= "Unknown" and name ~= "Unknown Profession"
end

local function AppendKnownProfession(parts, name)
    if IsKnownProfessionName(name) then
        parts[name] = true
    end
end

local function ProfessionSetToSortedList(set)
    local out = {}
    if type(set) == "table" then
        for name in pairs(set) do table.insert(out, name) end
    end
    table.sort(out)
    return out
end

local function PrintRecipeOwners(recipeID)
    recipeID = tonumber(recipeID)
    if not recipeID then
        API:Print("usage: /apl recipe <RecipeID>")
        return
    end

    if API.RebuildRecipeOwnerIndex then API:RebuildRecipeOwnerIndex("slash recipe") end

    local entry = API:GetRecipeIndexEntry(recipeID)
    if not entry or type(entry.owners) ~= "table" then
        API:Print("recipe " .. tostring(recipeID) .. " is not known by any saved character")
        return
    end

    API:Print("recipe " .. tostring(recipeID) .. (entry.name and (" - " .. entry.name) or "") .. " known by:")
    local chars = {}
    for charKey in pairs(entry.owners) do table.insert(chars, charKey) end
    table.sort(chars)

    for _, charKey in ipairs(chars) do
        local profs = entry.owners[charKey]
        local professionSet = {}
        if type(profs) == "table" then
            for _, owner in pairs(profs) do
                if type(owner) == "table" then
                    AppendKnownProfession(professionSet, owner.profession)
                end
            end
        end
        local parts = ProfessionSetToSortedList(professionSet)
        print("- " .. charKey .. (#parts > 0 and (" (" .. table.concat(parts, ", ") .. ")") or ""))
    end
end


local function PrintCraftedItemOwners(itemID)
    itemID = tonumber(itemID)
    if not itemID then
        API:Print("usage: /apl item <ItemID>")
        return
    end

    if API.RebuildRecipeOwnerIndex then API:RebuildRecipeOwnerIndex("slash item") end
    if API.RebuildCraftedItemIndex then API:RebuildCraftedItemIndex("slash item") end

    local entry = API.GetCraftedItemEntry and API:GetCraftedItemEntry(itemID)
    if not entry or type(entry.recipes) ~= "table" then
        API:Print("item " .. tostring(itemID) .. " has no saved crafted recipe owner yet")
        return
    end

    API:Print("item " .. tostring(itemID) .. " can be crafted by:")
    local recipeIDs = {}
    for recipeID in pairs(entry.recipes) do table.insert(recipeIDs, tonumber(recipeID) or recipeID) end
    table.sort(recipeIDs)

    for _, recipeID in ipairs(recipeIDs) do
        local recipe = entry.recipes[recipeID]
        print("- recipe " .. tostring(recipeID) .. (recipe.name and (" - " .. tostring(recipe.name)) or ""))
        local chars = {}
        for charKey in pairs(recipe.owners or {}) do table.insert(chars, charKey) end
        table.sort(chars)
        for _, charKey in ipairs(chars) do
            local profSet = {}
            for _, owner in pairs(recipe.owners[charKey] or {}) do
                if type(owner) == "table" then AppendKnownProfession(profSet, owner.profession) end
            end
            local profList = ProfessionSetToSortedList(profSet)
            print("    " .. charKey .. (#profList > 0 and (" (" .. table.concat(profList, ", ") .. ")") or ""))
        end
    end
end

local function PrintRecipeSample()
    if API.RebuildRecipeOwnerIndex then API:RebuildRecipeOwnerIndex("slash recipesample") end

    local db = API:GetDB()
    local index = db and db.recipeOwnerIndex
    if type(index) ~= "table" then
        API:Print("no recipe owner index available yet")
        return
    end

    local ids = {}
    for recipeID in pairs(index) do
        table.insert(ids, tonumber(recipeID) or recipeID)
    end
    table.sort(ids)

    if #ids == 0 then
        API:Print("no saved recipes found yet. Open a profession window, then run /apl scan")
        return
    end

    API:Print("sample known recipes. Use /apl recipe <RecipeID> to inspect one:")
    local shown = 0
    for _, recipeID in ipairs(ids) do
        local entry = index[recipeID]
        if type(entry) == "table" and type(entry.owners) == "table" then
            local ownerList = {}
            for charKey, profs in pairs(entry.owners) do
                local professionSet = {}
                if type(profs) == "table" then
                    for _, owner in pairs(profs) do
                        if type(owner) == "table" then
                            AppendKnownProfession(professionSet, owner.profession)
                        end
                    end
                end
                local profList = ProfessionSetToSortedList(professionSet)
                table.insert(ownerList, charKey .. (#profList > 0 and (" (" .. table.concat(profList, ", ") .. ")") or ""))
            end
            table.sort(ownerList)
            print("- recipeID " .. tostring(recipeID) .. (entry.name and (" - " .. tostring(entry.name)) or "") .. ": " .. table.concat(ownerList, "; "))
            shown = shown + 1
            if shown >= 10 then break end
        end
    end
end

local function PrintLinkInspection(linkText)
    if type(linkText) ~= "string" or strtrim(linkText) == "" then
        API:Print("usage: /apl inspect <shift-clicked item/spell link>")
        return
    end

    local parsed = API.ParseLinkPayload and API:ParseLinkPayload(linkText)
    if not parsed then
        API:Print("could not parse link")
        return
    end

    API:Print("link inspection:")
    print("- type: " .. tostring(parsed.linkType))
    print("- id: " .. tostring(parsed.id or "unknown"))
    print("- payload: " .. tostring(parsed.payload or ""))

    if parsed.linkType == "spell" and parsed.id then
        PrintRecipeOwners(parsed.id)
    elseif parsed.linkType == "item" and parsed.id then
        PrintCraftedItemOwners(parsed.id)
    end
end

local function DraftCrafterReply(rest)
    rest = strtrim(rest or "")
    local recipeToken, targetName = rest:match("^(%S+)%s*(.-)$")
    local recipeID = tonumber(recipeToken)
    if not recipeID then
        API:Print("usage: /apl draft <RecipeID> [targetName]")
        return
    end
    if not API.DraftCrafterMessage then
        API:Print("draft system is not available")
        return
    end
    targetName = strtrim(targetName or "")
    API:DraftCrafterMessage(recipeID, nil, targetName ~= "" and targetName or nil)
end

local function PreviewCrafterReply(rest)
    rest = strtrim(rest or "")
    local recipeToken, targetName = rest:match("^(%S+)%s*(.-)$")
    local recipeID = tonumber(recipeToken)
    if not recipeID then
        API:Print("usage: /apl draftpreview <RecipeID> [targetName]")
        return
    end
    if not API.PreviewCrafterMessage then
        API:Print("draft preview system is not available")
        return
    end
    targetName = strtrim(targetName or "")
    API:PreviewCrafterMessage(recipeID, nil, targetName ~= "" and targetName or nil)
end


local function DraftItemReply(rest)
    rest = strtrim(rest or "")
    local itemToken, targetName = rest:match("^(%S+)%s*(.-)$")
    local itemID = tonumber(itemToken)
    if not itemID then
        API:Print("usage: /apl draftitem <ItemID> [targetName]")
        return
    end
    if not API.DraftCrafterMessageForItem then
        API:Print("item draft system is not available")
        return
    end
    targetName = strtrim(targetName or "")
    API:DraftCrafterMessageForItem(itemID, targetName ~= "" and targetName or nil)
end

local function PreviewItemReply(rest)
    rest = strtrim(rest or "")
    local itemToken, targetName = rest:match("^(%S+)%s*(.-)$")
    local itemID = tonumber(itemToken)
    if not itemID then
        API:Print("usage: /apl draftitempreview <ItemID> [targetName]")
        return
    end
    if not API.PreviewCrafterMessageForItem then
        API:Print("item draft preview system is not available")
        return
    end
    targetName = strtrim(targetName or "")
    API:PreviewCrafterMessageForItem(itemID, targetName ~= "" and targetName or nil)
end

local function SetTooltipEnabled(rest)
    rest = string.lower(strtrim(rest or ""))
    local db = API:GetDB()
    db.settings = db.settings or {}

    if rest == "on" or rest == "1" or rest == "true" then
        db.settings.tooltipEnabled = true
    elseif rest == "off" or rest == "0" or rest == "false" then
        db.settings.tooltipEnabled = false
    elseif rest == "" or rest == "toggle" then
        db.settings.tooltipEnabled = not db.settings.tooltipEnabled
    else
        API:Print("usage: /apl tooltip on|off")
        return
    end

    API:Print("tooltip", db.settings.tooltipEnabled and "enabled" or "disabled")
end

local function ToggleTooltipDebug()
    local db = API:GetDB()
    db.settings = db.settings or {}
    db.settings.tooltipDebug = not db.settings.tooltipDebug
    API:Print("tooltip debug", db.settings.tooltipDebug and "enabled" or "disabled")
end

local function ToggleLinkDebug()
    local db = API:GetDB()
    db.settings = db.settings or {}
    db.settings.linkDebug = not db.settings.linkDebug
    API:Print("link debug", db.settings.linkDebug and "enabled" or "disabled")
    if db.debug and db.debug.lastHoveredLink then
        API:Print("last hovered link:")
        print("- type: " .. tostring(db.debug.lastHoveredLinkType or "unknown"))
        print("- id: " .. tostring(db.debug.lastHoveredLinkID or "unknown"))
        print("- raw: " .. tostring(db.debug.lastHoveredLink))
    end
end


local function PrintStats()
    if API.RebuildProfessionIndex then API:RebuildProfessionIndex("slash stats") end
    if API.RebuildRecipeOwnerIndex then API:RebuildRecipeOwnerIndex("slash stats") end
    if API.RebuildCraftedItemIndex then API:RebuildCraftedItemIndex("slash stats") end
    local stats = API:GetAccountStats()
    API:Print("account stats:")
    print("- characters: " .. tostring(stats.characters))
    print("- profession entries: " .. tostring(stats.professionEntries))
    print("- indexed professions: " .. tostring(stats.indexedProfessions))
    print("- indexed owners: " .. tostring(stats.indexedOwners))
    print("- known recipes: " .. tostring(stats.recipes))
    print("- indexed recipes: " .. tostring(stats.indexedRecipes))
    print("- indexed recipe owners: " .. tostring(stats.indexedRecipeOwners))
    print("- crafted items: " .. tostring(stats.craftedItems))
    print("- crafted item recipes: " .. tostring(stats.craftedItemRecipes))
end

SLASH_ALTPROFLIB1 = "/apl"
SLASH_ALTPROFLIB2 = "/altproflib"
SlashCmdList.ALTPROFLIB = function(msg)
    msg = strtrim(msg or "")
    local command, rest = msg:match("^(%S*)%s*(.-)$")
    command = string.lower(command or "")

    if command == "" or command == "help" then
        PrintHelp()
    elseif command == "scan" then
        local profCount = API:ScanProfessions("slash")
        local recipeCount = API:ScanOpenTradeSkillRecipes("slash")
        if API.RebuildProfessionIndex then API:RebuildProfessionIndex("slash") end
        if API.RebuildRecipeOwnerIndex then API:RebuildRecipeOwnerIndex("slash") end
        API:Print("Profession Scan Complete! Version", API:GetVersion())
    elseif command == "roster" then
        PrintRoster()
    elseif command == "owners" then
        PrintOwners()
    elseif command == "recipes" then
        PrintRecipeCounts()
    elseif command == "stats" then
        PrintStats()
    elseif command == "inspect" or command == "link" then
        PrintLinkInspection(rest)
    elseif command == "draft" or command == "reply" then
        DraftCrafterReply(rest)
    elseif command == "draftitem" or command == "replyitem" then
        DraftItemReply(rest)
    elseif command == "draftpreview" or command == "previewdraft" then
        PreviewCrafterReply(rest)
    elseif command == "draftitempreview" or command == "previewitemdraft" then
        PreviewItemReply(rest)
    elseif command == "tooltip" then
        SetTooltipEnabled(rest)
    elseif command == "tooltipdebug" then
        ToggleTooltipDebug()
    elseif command == "linkdebug" then
        ToggleLinkDebug()
    elseif command == "recipe" then
        PrintRecipeOwners(rest)
    elseif command == "item" then
        PrintCraftedItemOwners(rest)
    elseif command == "recipesample" or command == "sample" then
        PrintRecipeSample()
    elseif command == "chardiag" then
        local db = API.GetDB and API:GetDB()
        if not db then API:Print("DB: NIL"); return end
        local charKey = API:GetCharacterKey()
        API:Print("=== chardiag: " .. tostring(charKey) .. " ===")
        local char = db.characters and db.characters[charKey]
        if char then
            print("class: " .. tostring(char.class))
            print("lastScan: " .. tostring(char.lastProfessionScan))
            for profID, bucket in pairs(db.learnedRecipes and db.learnedRecipes[charKey] or {}) do
                local n = 0; for _ in pairs(bucket) do n = n + 1 end
                print("prof " .. tostring(profID) .. ": " .. n .. " recipes")
            end
        else
            print("NO character entry found for charKey: " .. tostring(charKey))
            -- Show existing charKeys in DB for comparison
            print("Existing charKeys in DB:")
            local count = 0
            for k in pairs(db.characters or {}) do
                count = count + 1
                if count <= 5 then print("  [" .. tostring(k) .. "]") end
            end
            print("  (" .. count .. " total)")
        end
        local roiCount = 0
        for _, entry in pairs(db.recipeOwnerIndex or {}) do
            if type(entry) == "table" and type(entry.owners) == "table" then
                for ownerKey in pairs(entry.owners) do
                    if ownerKey == charKey then roiCount = roiCount + 1 end
                end
            end
        end
        print("recipeOwnerIndex entries for this char: " .. roiCount)
        local roiTotal = 0; for _ in pairs(db.recipeOwnerIndex or {}) do roiTotal = roiTotal + 1 end
        print("recipeOwnerIndex total: " .. roiTotal)
        local citTotal = 0; for _ in pairs(db.craftedItemIndex or {}) do citTotal = citTotal + 1 end
        print("craftedItemIndex total: " .. citTotal)
    elseif command == "debug" then
        local db = API:GetDB()
        db.settings.debug = not db.settings.debug
        API:Print("debug", db.settings.debug and "enabled" or "disabled")
    elseif command == "version" then
        API:Print("version", API:GetVersion())
    else
        PrintHelp()
    end
end
