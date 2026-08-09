local ADDON_NAME, ns = ...
-- AltProfLib release 1.0.1
local API = ns.API

local CHANNEL_WHISPER = "WHISPER"
local CHANNEL_GUILD = "GUILD"
local CHANNEL_SAY = "SAY"

local REPLY_MODE_EN = "en"
local REPLY_MODE_CUSTOM = "custom"
local RECENT_TARGETS_MAX = 10
local RECENT_ROW_HEIGHT = 40
local RECENT_ROW_PADDING = 2
local RECENT_SIDE_WIDTH = 210
local RECENT_DELETE_SIZE = 16
local PANEL_WIDTH = 660
local PANEL_HEIGHT = 318
local LEFT_CONTENT_RIGHT = PANEL_WIDTH - RECENT_SIDE_WIDTH - 16
local LEFT_PAD = 12

local panel
local selectedChannel = CHANNEL_WHISPER
local selectedOwner
local ownerList = {}
local currentItemID
local currentItemDisplay
local replyMode = REPLY_MODE_EN

local function GetSettings()
    local db = API.GetDB and API:GetDB()
    if not db then return nil end
    db.settings = db.settings or {}
    return db.settings
end

local function EnsureReplyLocale()
    local settings = GetSettings()
    if not settings then
        local loc = GetLocale and GetLocale() or "enUS"
        return (loc == "itIT") and "it" or "en"
    end
    if not settings.replyLocale then
        local loc = GetLocale and GetLocale() or "enUS"
        settings.replyLocale = (loc == "itIT") and "it" or "en"
    end
    return settings.replyLocale
end

local function EnsureReplyMode()
    local settings = GetSettings()
    if settings then
        if settings.replyMode ~= REPLY_MODE_EN and settings.replyMode ~= REPLY_MODE_CUSTOM then
            settings.replyMode = REPLY_MODE_EN
        end
        replyMode = settings.replyMode
    else
        replyMode = REPLY_MODE_EN
    end
    return replyMode
end

local function SetReplyMode(mode)
    if mode ~= REPLY_MODE_CUSTOM then
        mode = REPLY_MODE_EN
    end
    replyMode = mode
    local settings = GetSettings()
    if settings then
        settings.replyMode = mode
    end
end

local function L(key)
    local locale = EnsureReplyLocale()
    local pack = AltProfLibLocale and (AltProfLibLocale[locale] or AltProfLibLocale["en"])
    if type(pack) == "table" and pack[key] then
        return pack[key]
    end
    local fallback = AltProfLibLocale and AltProfLibLocale["en"]
    return (fallback and fallback[key]) or key
end

local function GetEnglishTemplate()
    local pack = AltProfLibLocale and AltProfLibLocale["en"]
    return (pack and pack.CRAFT_REPLY_TEMPLATE) or L("CRAFT_REPLY_TEMPLATE")
end

local function GetCustomTemplate()
    local settings = GetSettings()
    if not settings then return nil end
    local text = settings.customReplyTemplate
    if type(text) ~= "string" then return nil end
    text = strtrim(text)
    if text == "" then return nil end
    return text
end

local function EnsureRecentTargets()
    local settings = GetSettings()
    if not settings then return {} end
    if type(settings.recentTargets) ~= "table" then
        settings.recentTargets = {}
    end
    return settings.recentTargets
end

local function GetPlayerRealmName()
    if GetRealmName then
        local realm = GetRealmName()
        if type(realm) == "string" and realm ~= "" then
            return realm
        end
    end
    return ""
end

local function ParseTargetNameRealm(target)
    if type(target) ~= "string" then return nil, nil end
    target = strtrim(target)
    if target == "" then return nil, nil end

    local name, realm = target:match("^([^%-]+)%-(.+)$")
    if name and name ~= "" then
        return name, strtrim(realm or "")
    end
    return target, GetPlayerRealmName()
end

local function FormatRecentTargetDisplay(entry)
    if type(entry) ~= "table" or type(entry.name) ~= "string" then
        return ""
    end
    local realm = type(entry.realm) == "string" and entry.realm or ""
    local playerRealm = GetPlayerRealmName()
    if realm ~= "" and realm ~= playerRealm then
        return entry.name .. "-" .. realm
    end
    return entry.name
end

local function FormatRecentTargetEditValue(entry)
    if type(entry) ~= "table" or type(entry.name) ~= "string" then
        return ""
    end
    local realm = type(entry.realm) == "string" and entry.realm or ""
    if realm ~= "" then
        return entry.name .. "-" .. realm
    end
    return entry.name
end

local function FormatShortTimestamp(timestamp)
    timestamp = tonumber(timestamp)
    if not timestamp then return "" end
    return date("%d/%m %H:%M", timestamp)
end

local function GetClassColoredText(characterName, classFilename)
    local color = classFilename and RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFilename]
    if not color then
        return characterName
    end
    return string.format(
        "|cff%02x%02x%02x%s|r",
        color.r * 255,
        color.g * 255,
        color.b * 255,
        characterName
    )
end

local function GetClassDisplayName(classFilename)
    if type(classFilename) ~= "string" or classFilename == "" then
        return "?"
    end
    if LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[classFilename] then
        return LOCALIZED_CLASS_NAMES_MALE[classFilename]
    end
    return classFilename
end

local RefreshRecentTargetsList
local RequestWhoIfNeeded

local function LookupUnitClassLevel(name, realm)
    if type(name) ~= "string" or name == "" then
        return nil, nil, nil
    end

    local candidates = { name }
    local playerRealm = GetPlayerRealmName()
    if type(realm) == "string" and realm ~= "" then
        table.insert(candidates, 1, name .. "-" .. realm)
        if realm ~= playerRealm then
            table.insert(candidates, name)
        end
    end

    local classFilename, level, guid

    -- Prefer live unit data when the player is currently known to the client.
    for _, unitToken in ipairs(candidates) do
        if UnitExists and UnitExists(unitToken) and UnitClass then
            local _, unitClass = UnitClass(unitToken)
            classFilename = unitClass or classFilename
            if UnitLevel then
                local unitLevel = UnitLevel(unitToken)
                if unitLevel and unitLevel > 0 then
                    level = unitLevel
                end
            end
            if UnitGUID then
                guid = UnitGUID(unitToken) or guid
            end
            if classFilename then
                break
            end
        end
    end

    -- Fall back to chat-sender cache / last sender (GUID + class from chat events).
    if API.GetSenderInfoByName then
        local info = API:GetSenderInfoByName(name, realm)
        if type(info) == "table" then
            classFilename = classFilename or info.classFilename
            level = level or info.level
            guid = guid or info.guid
        end
    elseif type(AltProfLibLastSender) == "table" then
        local last = AltProfLibLastSender
        local lastName = last.name and (last.name:match("^([^%-]+)") or last.name)
        if lastName == name then
            classFilename = classFilename or last.classFilename
            level = level or last.level
            guid = guid or last.guid
        end
    end

    -- GUID can still resolve class even when the unit is not in range.
    if (not classFilename) and type(guid) == "string" and guid ~= "" and GetPlayerInfoByGUID then
        local _, englishClass = GetPlayerInfoByGUID(guid)
        if type(englishClass) == "string" and englishClass ~= "" then
            classFilename = englishClass
        end
    end

    return classFilename, level, guid
end

local function PushRecentTarget(target)
    local name, realm = ParseTargetNameRealm(target)
    if not name then return end

    local list = EnsureRecentTargets()
    local existingClass, existingLevel, existingGuid
    for i = #list, 1, -1 do
        local entry = list[i]
        if type(entry) == "table"
            and entry.name == name
            and (entry.realm or "") == (realm or "") then
            existingClass = entry.classFilename
            existingLevel = entry.level
            existingGuid = entry.guid
            table.remove(list, i)
        end
    end

    local classFilename, level, guid = LookupUnitClassLevel(name, realm)
    classFilename = classFilename or existingClass
    level = level or existingLevel
    guid = guid or existingGuid

    table.insert(list, 1, {
        name = name,
        realm = realm or "",
        timestamp = time(),
        classFilename = classFilename,
        level = level,
        guid = guid,
        whoRequested = false,
        whoResolved = false,
    })

    while #list > RECENT_TARGETS_MAX do
        table.remove(list)
    end

    RequestWhoIfNeeded(list[1])
end

local function RemoveRecentTargetAt(index)
    local list = EnsureRecentTargets()
    index = tonumber(index)
    if not index or index < 1 or index > #list then return end
    table.remove(list, index)
end

-- Same path Blizzard uses on Shift+Click player name: SendWho + WHO_LIST_UPDATE.
local whoQueue = {}
local whoInFlight = nil
local whoFrame = CreateFrame("Frame")

local function ClassFileFromWhoInfo(info)
    if type(info) ~= "table" then return nil end
    if type(info.filename) == "string" and info.filename ~= "" then
        return info.filename
    end
    if type(info.classFileName) == "string" and info.classFileName ~= "" then
        return info.classFileName
    end

    local localized = info.className or info.classStr
    if type(localized) ~= "string" or localized == "" then return nil end

    if LOCALIZED_CLASS_NAMES_MALE then
        for classFile, locName in pairs(LOCALIZED_CLASS_NAMES_MALE) do
            if locName == localized then return classFile end
        end
    end
    if LOCALIZED_CLASS_NAMES_FEMALE then
        for classFile, locName in pairs(LOCALIZED_CLASS_NAMES_FEMALE) do
            if locName == localized then return classFile end
        end
    end

    local upper = localized:upper():gsub("%s+", "")
    if RAID_CLASS_COLORS and RAID_CLASS_COLORS[upper] then
        return upper
    end
    return nil
end

local function ShortPlayerName(name)
    if type(name) ~= "string" then return nil end
    name = Ambiguate and Ambiguate(name, "none") or name
    return name:match("^([^%-]+)") or name
end

local function NamesMatch(a, b)
    a, b = ShortPlayerName(a), ShortPlayerName(b)
    return a and b and a == b
end

local function StripWowEscapeCodes(text)
    if type(text) ~= "string" then return "" end
    text = text:gsub("|c%x%x%x%x%x%x%x%x", "")
    text = text:gsub("|r", "")
    text = text:gsub("|T.-|t", "")
    text = text:gsub("|A.-|a", "")
    -- Keep visible [Name] from |Hplayer:...|h[Name]|h
    text = text:gsub("|H.-|[Hh]", "")
    text = text:gsub("|h", "")
    return text
end

-- Parse Blizzard who system lines such as:
-- [Beltharion]: Level 90 Kul Tiran Hunter <Guild-Realm> - Zone
local function ParseWhoSystemMessage(msg)
    if type(msg) ~= "string" or msg == "" then return nil end

    local whoName = msg:match("|h%[([^%]]+)%]|h") or msg:match("%[([^%]]+)%]")
    local plain = StripWowEscapeCodes(msg)

    if not whoName then
        whoName = plain:match("%[([^%]]+)%]")
    end
    if not whoName then return nil end

    local level, tail = plain:match("[Ll]evel%s+(%d+)%s+(.+)$")
    if not level then
        level, tail = plain:match("[Ll]ivello%s+(%d+)%s+(.+)$")
    end
    if not level then
        -- Fallback: first number after the name marker.
        level, tail = plain:match("%].-(%d%d?)%s+(.+)$")
    end
    if not level or not tail then return nil end

    local beforeGuild = tail:match("^(.-)%s*<") or tail:match("^(.-)%s*%-%s*") or tail
    beforeGuild = strtrim(beforeGuild or "")
    local classToken = beforeGuild:match("(%S+)$")

    return {
        fullName = ShortPlayerName(whoName) or whoName,
        level = tonumber(level),
        className = classToken,
        classStr = classToken,
    }
end

local function NormalizeWhoInfo(info)
    if type(info) ~= "table" then return nil end
    return {
        fullName = info.fullName or info.name,
        level = tonumber(info.level),
        className = info.className or info.classStr,
        classStr = info.classStr or info.className,
        filename = info.filename or info.classFileName,
        classFileName = info.classFileName or info.filename,
    }
end

local function ApplyWhoInfoToRecentTargets(info)
    info = NormalizeWhoInfo(info)
    if not info then return false end

    local whoName = info.fullName
    local classFilename = ClassFileFromWhoInfo(info)
    local level = tonumber(info.level)
    if not whoName then return false end
    if not classFilename and not level then return false end

    local list = EnsureRecentTargets()
    local changed = false
    for _, entry in ipairs(list) do
        if type(entry) == "table" and NamesMatch(entry.name, whoName) then
            if classFilename and entry.classFilename ~= classFilename then
                entry.classFilename = classFilename
                changed = true
            elseif classFilename and not entry.classFilename then
                entry.classFilename = classFilename
                changed = true
            end
            if level and level > 0 and entry.level ~= level then
                entry.level = level
                changed = true
            end
            if entry.classFilename and entry.level and tonumber(entry.level) > 0 then
                entry.whoResolved = true
            else
                -- Keep unresolved so a retry can fill the missing level/class.
                entry.whoResolved = false
            end
        end
    end

    if changed and API.GetSenderInfoByName then
        local cached = API:GetSenderInfoByName(ShortPlayerName(whoName))
        if type(cached) == "table" then
            cached.classFilename = classFilename or cached.classFilename
            cached.level = level or cached.level
        end
    end
    if changed and type(AltProfLibLastSender) == "table" and NamesMatch(AltProfLibLastSender.name, whoName) then
        AltProfLibLastSender.classFilename = classFilename or AltProfLibLastSender.classFilename
        AltProfLibLastSender.level = level or AltProfLibLastSender.level
    end

    return changed
end

local function ProcessWhoQueue()
    if whoInFlight then return end
    local nextReq = table.remove(whoQueue, 1)
    if not nextReq then return end

    whoInFlight = nextReq
    local query = nextReq.query
    -- Keep Who results readable from GetWhoInfo (same as Shift+Click player name).
    if C_FriendList and C_FriendList.SetWhoToUi then
        pcall(C_FriendList.SetWhoToUi, true)
    end
    if C_FriendList and C_FriendList.SendWho then
        C_FriendList.SendWho(query)
    elseif SendWho then
        SendWho(query)
    else
        whoInFlight = nil
    end
end

local function EnqueueWhoLookup(name, realm)
    if type(name) ~= "string" or name == "" then return end
    local short = ShortPlayerName(name)
    if not short then return end

    local queryName = short
    if type(realm) == "string" and realm ~= "" and realm ~= GetPlayerRealmName() then
        queryName = short .. "-" .. realm
    end

    local query = string.format('n-"%s"', queryName)
    for _, pending in ipairs(whoQueue) do
        if pending.query == query then return end
    end
    if whoInFlight and whoInFlight.query == query then return end

    table.insert(whoQueue, {
        name = short,
        realm = realm or "",
        query = query,
    })
    ProcessWhoQueue()
end

RequestWhoIfNeeded = function(entry)
    if type(entry) ~= "table" or type(entry.name) ~= "string" then return end
    local needsClass = not entry.classFilename or entry.classFilename == ""
    local needsLevel = not entry.level or tonumber(entry.level) == nil or tonumber(entry.level) <= 0
    if not needsClass and not needsLevel then
        entry.whoResolved = true
        return
    end
    local now = time()
    if entry.whoRequested and not entry.whoResolved then
        local last = tonumber(entry.whoRequestTime) or 0
        if (now - last) < 15 then
            return
        end
    end
    entry.whoRequested = true
    entry.whoRequestTime = now
    EnqueueWhoLookup(entry.name, entry.realm)
end

whoFrame:RegisterEvent("WHO_LIST_UPDATE")
whoFrame:RegisterEvent("CHAT_MSG_SYSTEM")
whoFrame:SetScript("OnEvent", function(_, event, ...)
    if event == "WHO_LIST_UPDATE" then
        local pending = whoInFlight
        whoInFlight = nil

        local changed = false
        if C_FriendList and C_FriendList.GetNumWhoResults and C_FriendList.GetWhoInfo then
            local num = C_FriendList.GetNumWhoResults() or 0
            for i = 1, num do
                local info = C_FriendList.GetWhoInfo(i)
                if ApplyWhoInfoToRecentTargets(info) then
                    changed = true
                end
            end
        end

        if changed and RefreshRecentTargetsList then
            RefreshRecentTargetsList()
        end

        if #whoQueue > 0 and C_Timer and C_Timer.After then
            C_Timer.After(0.75, ProcessWhoQueue)
        elseif #whoQueue > 0 then
            ProcessWhoQueue()
        end
        return
    end

    if event == "CHAT_MSG_SYSTEM" then
        local msg = ...
        local info = ParseWhoSystemMessage(msg)
        if info and ApplyWhoInfoToRecentTargets(info) and RefreshRecentTargetsList then
            RefreshRecentTargetsList()
        end
    end
end)

local function ShortCharacterName(charKey)
    if type(charKey) ~= "string" then return tostring(charKey or "") end
    return charKey:match("^(.+)%-.+$") or charKey
end

local function ApplyPlaceholders(template, itemDisplay, character, profession, skill)
    if type(template) ~= "string" then return "" end
    return template
        :gsub("{item}", tostring(itemDisplay or "?"))
        :gsub("{character}", tostring(character or "?"))
        :gsub("{profession}", tostring(profession or "?"))
        :gsub("{skill}", tostring(skill or 0))
end

local function ResolveItemDisplay(itemID, itemLink)
    itemID = tonumber(itemID)
    if type(itemLink) == "string" and itemLink ~= "" then
        local name = itemLink:match("%[(.-)%]")
        if name and name ~= "" then
            return itemLink, name
        end
        return itemLink, itemLink
    end

    if itemID then
        if GetItemInfo then
            local name, link = GetItemInfo(itemID)
            if type(link) == "string" and link ~= "" then
                return link, name or link
            end
            if type(name) == "string" and name ~= "" then
                return name, name
            end
        end
        if C_Item and C_Item.GetItemNameByID then
            local name = C_Item.GetItemNameByID(itemID)
            if type(name) == "string" and name ~= "" then
                return name, name
            end
        end
    end

    local fallback = "item " .. tostring(itemID or "?")
    return fallback, fallback
end

local function CollectOwnersForItem(itemID)
    itemID = tonumber(itemID)
    if not itemID then return {} end

    if API.RebuildRecipeOwnerIndex then
        API:RebuildRecipeOwnerIndex("craft reply")
    end
    if API.RebuildCraftedItemIndex then
        API:RebuildCraftedItemIndex("craft reply")
    end

    local itemEntry = API.GetCraftedItemEntry and API:GetCraftedItemEntry(itemID)
    if type(itemEntry) ~= "table" or type(itemEntry.recipes) ~= "table" then
        return {}
    end

    local merged = {}
    for _, recipe in pairs(itemEntry.recipes) do
        if type(recipe) == "table" and type(recipe.owners) == "table" then
            for charKey, profs in pairs(recipe.owners) do
                if type(profs) == "table" then
                    merged[charKey] = merged[charKey] or {}
                    for profID, owner in pairs(profs) do
                        merged[charKey][profID] = owner
                    end
                end
            end
        end
    end

    if API.GetSortedOwnersFromOwners then
        return API:GetSortedOwnersFromOwners(merged) or {}
    end
    return {}
end

local function UpdatePlaceholderVisibility()
    if not panel or not panel.placeholder then return end
    local text = panel.messageEdit and panel.messageEdit:GetText() or ""
    local show = replyMode == REPLY_MODE_CUSTOM and strtrim(text) == ""
    if show then
        panel.placeholder:Show()
    else
        panel.placeholder:Hide()
    end
end

local function UpdateSendButtonState()
    if not panel or not panel.btnSend then return end
    if selectedChannel == CHANNEL_WHISPER then
        local target = panel.targetEdit and strtrim(panel.targetEdit:GetText() or "") or ""
        panel.btnSend:SetEnabled(target ~= "")
    else
        panel.btnSend:SetEnabled(true)
    end
end

local function UpdateReplyModeButtons()
    if not panel then return end
    if panel.btnEN then
        panel.btnEN:SetEnabled(replyMode ~= REPLY_MODE_EN)
    end
    if panel.btnCustom then
        panel.btnCustom:SetEnabled(replyMode ~= REPLY_MODE_CUSTOM)
    end
end

local function RefreshMessageText()
    if not panel or not panel.messageEdit then return end

    local owner = selectedOwner
    if type(owner) ~= "table" then
        panel.messageEdit:SetText("")
        UpdatePlaceholderVisibility()
        return
    end

    local character = ShortCharacterName(owner.characterKey)
    local profession = owner.profession or "?"
    local skill = tonumber(owner.skillLevel or 0) or 0

    if replyMode == REPLY_MODE_CUSTOM then
        local custom = GetCustomTemplate()
        if custom then
            panel.messageEdit:SetText(ApplyPlaceholders(custom, currentItemDisplay, character, profession, skill))
        else
            panel.messageEdit:SetText("")
        end
    else
        panel.messageEdit:SetText(ApplyPlaceholders(GetEnglishTemplate(), currentItemDisplay, character, profession, skill))
    end

    UpdatePlaceholderVisibility()
end

local function SetChannel(channel)
    selectedChannel = channel or CHANNEL_WHISPER
    if not panel then return end

    if panel.btnWhisper then
        panel.btnWhisper:SetEnabled(selectedChannel ~= CHANNEL_WHISPER)
    end
    if panel.btnGuild then
        panel.btnGuild:SetEnabled(selectedChannel ~= CHANNEL_GUILD)
    end
    if panel.btnSay then
        panel.btnSay:SetEnabled(selectedChannel ~= CHANNEL_SAY)
    end

    local whisperMode = selectedChannel == CHANNEL_WHISPER
    if panel.targetLabel then
        if whisperMode then
            panel.targetLabel:Show()
        else
            panel.targetLabel:Hide()
        end
    end
    if panel.targetEdit then
        if whisperMode then
            panel.targetEdit:Show()
        else
            panel.targetEdit:Hide()
        end
    end

    UpdateSendButtonState()
end

local function ClosePanel()
    if not panel then return end
    if panel.messageEdit then
        panel.messageEdit:ClearFocus()
    end
    if panel.targetEdit then
        panel.targetEdit:ClearFocus()
    end
    panel:Hide()
end

local function FormatCrafterShareName(owner)
    if type(owner) ~= "table" then return nil end
    local key = owner.characterKey
    if type(key) ~= "string" or key == "" then return nil end

    local name, realm = key:match("^(.+)%-(.+)$")
    if not name then
        return key
    end

    local playerRealm = GetPlayerRealmName()
    if realm == "" or realm == playerRealm then
        return name
    end
    return name .. "-" .. realm
end

local function ShareCrafterName()
    local crafterName = FormatCrafterShareName(selectedOwner)
    if not crafterName then
        API:Print("no crafter selected to share")
        return
    end

    local channel = selectedChannel or CHANNEL_WHISPER
    local target
    if channel == CHANNEL_WHISPER then
        target = panel and panel.targetEdit and strtrim(panel.targetEdit:GetText() or "") or ""
        if target == "" then
            API:Print("whisper target is required to share crafter")
            return
        end
    end

    SendChatMessage("Crafter: " .. crafterName, channel, nil, target)
end

local function SendPanelMessage()
    if not panel or not panel.messageEdit then return end

    local text = panel.messageEdit:GetText()
    if type(text) ~= "string" then text = "" end
    text = strtrim(text)
    if text == "" then
        API:Print("craft reply message is empty")
        return
    end

    local channel = selectedChannel or CHANNEL_WHISPER
    local target
    if channel == CHANNEL_WHISPER then
        target = panel.targetEdit and strtrim(panel.targetEdit:GetText() or "") or ""
        if target == "" then
            API:Print("whisper target is required")
            return
        end
    end

    SendChatMessage(text, channel, nil, target)
    if type(target) == "string" and strtrim(target) ~= "" then
        PushRecentTarget(target)
        RefreshRecentTargetsList()
    end

    -- Keep the panel open; only clear the target field.
    if panel.targetEdit then
        panel.targetEdit:ClearFocus()
        panel.targetEdit:SetText("")
    end
    UpdateSendButtonState()
end

local function SaveCustomTemplate()
    if not panel or not panel.messageEdit then return end
    local settings = GetSettings()
    if not settings then
        API:Print("cannot save custom template: database unavailable")
        return
    end

    local text = panel.messageEdit:GetText()
    if type(text) ~= "string" then text = "" end
    settings.customReplyTemplate = text
    SetReplyMode(REPLY_MODE_CUSTOM)
    UpdateReplyModeButtons()
    UpdatePlaceholderVisibility()
    API:Print("custom reply template saved")
end

local function OwnerDropdown_Initialize(dropdown, level)
    if not UIDropDownMenu_AddButton then return end

    for _, owner in ipairs(ownerList) do
        if type(owner) == "table" then
            local info = UIDropDownMenu_CreateInfo()
            local name = ShortCharacterName(owner.characterKey)
            local profession = owner.profession or "?"
            local skill = tonumber(owner.skillLevel or 0) or 0
            info.text = string.format("%s — %s Sk:%s", name, profession, tostring(skill))
            info.checked = selectedOwner == owner
            info.func = function()
                selectedOwner = owner
                UIDropDownMenu_SetText(dropdown, info.text)
                RefreshMessageText()
            end
            UIDropDownMenu_AddButton(info, level)
        end
    end
end

RefreshRecentTargetsList = function()
    if not panel or not panel.recentRows then return end

    local list = EnsureRecentTargets()
    local count = math.min(#list, RECENT_TARGETS_MAX)
    local rowWidth = RECENT_SIDE_WIDTH - 34

    for i = 1, RECENT_TARGETS_MAX do
        local row = panel.recentRows[i]
        local entry = list[i]
        if entry and i <= count then
            -- Refresh class/level if the unit/chat cache knows this player.
            local classFilename, level, guid = LookupUnitClassLevel(entry.name, entry.realm)
            if classFilename then
                entry.classFilename = classFilename
            elseif entry.guid and GetPlayerInfoByGUID then
                local _, englishClass = GetPlayerInfoByGUID(entry.guid)
                if type(englishClass) == "string" and englishClass ~= "" then
                    entry.classFilename = englishClass
                end
            end
            if level and level > 0 then
                entry.level = level
            end
            if guid then
                entry.guid = guid
            end

            RequestWhoIfNeeded(entry)

            row.entryIndex = i
            row.nameText:SetText(GetClassColoredText(FormatRecentTargetDisplay(entry), entry.classFilename))
            row.metaText:SetText(string.format(
                "Level %s  %s",
                tostring(entry.level or "?"),
                GetClassDisplayName(entry.classFilename)
            ))
            row.timeText:SetText(FormatShortTimestamp(entry.timestamp))
            row:SetWidth(rowWidth)
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", panel.recentContent, "TOPLEFT", 0, -((i - 1) * (RECENT_ROW_HEIGHT + RECENT_ROW_PADDING)))
            row:SetPoint("TOPRIGHT", panel.recentContent, "TOPRIGHT", 0, -((i - 1) * (RECENT_ROW_HEIGHT + RECENT_ROW_PADDING)))
            row:Show()
        else
            row.entryIndex = nil
            row:Hide()
        end
    end

    local contentHeight = (count * RECENT_ROW_HEIGHT) + (math.max(count - 1, 0) * RECENT_ROW_PADDING)
    if panel.recentContent then
        panel.recentContent:SetWidth(rowWidth)
        panel.recentContent:SetHeight(math.max(contentHeight, 1))
    end
    if panel.recentScroll then
        panel.recentScroll:SetVerticalScroll(0)
    end
end

local function EnsurePanel()
    if panel then return panel end

    panel = CreateFrame("Frame", "AltProfLibCraftReplyPanel", UIParent, "BasicFrameTemplateWithInset")
    panel:SetSize(PANEL_WIDTH, PANEL_HEIGHT)
    panel:SetPoint("CENTER")
    panel:SetFrameStrata("DIALOG")
    panel:SetToplevel(true)
    panel:SetMovable(true)
    panel:EnableMouse(true)
    panel:RegisterForDrag("LeftButton")
    panel:SetScript("OnDragStart", panel.StartMoving)
    panel:SetScript("OnDragStop", panel.StopMovingOrSizing)
    panel:SetScript("OnHide", function(self)
        if self.messageEdit then self.messageEdit:ClearFocus() end
        if self.targetEdit then self.targetEdit:ClearFocus() end
    end)
    panel:Hide()

    local alreadyListed
    for i = 1, #UISpecialFrames do
        if UISpecialFrames[i] == "AltProfLibCraftReplyPanel" then
            alreadyListed = true
            break
        end
    end
    if not alreadyListed then
        tinsert(UISpecialFrames, "AltProfLibCraftReplyPanel")
    end

    if panel.TitleText then
        panel.TitleText:SetText(L("PANEL_TITLE"))
    end

    panel.charLabel = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    panel.charLabel:SetPoint("TOPLEFT", LEFT_PAD, -28)
    panel.charLabel:SetText("Character")

    panel.btnShare = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    panel.btnShare:SetSize(54, 20)
    panel.btnShare:SetPoint("TOPRIGHT", panel, "TOPLEFT", LEFT_CONTENT_RIGHT, -44)
    panel.btnShare:SetText("Share")
    panel.btnShare:SetScript("OnClick", ShareCrafterName)

    panel.charDropDown = CreateFrame("Frame", "AltProfLibCraftReplyCharDropDown", panel, "UIDropDownMenuTemplate")
    panel.charDropDown:SetPoint("TOPLEFT", panel.charLabel, "BOTTOMLEFT", -16, -1)
    panel.charDropDown:SetPoint("RIGHT", panel.btnShare, "LEFT", -4, 0)
    UIDropDownMenu_SetWidth(panel.charDropDown, LEFT_CONTENT_RIGHT - LEFT_PAD - 70)
    UIDropDownMenu_Initialize(panel.charDropDown, OwnerDropdown_Initialize)

    panel.btnEN = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    panel.btnEN:SetSize(54, 20)
    panel.btnEN:SetPoint("TOPLEFT", LEFT_PAD, -74)
    panel.btnEN:SetScript("OnClick", function()
        SetReplyMode(REPLY_MODE_EN)
        UpdateReplyModeButtons()
        RefreshMessageText()
    end)

    panel.btnCustom = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    panel.btnCustom:SetSize(72, 20)
    panel.btnCustom:SetPoint("LEFT", panel.btnEN, "RIGHT", 6, 0)
    panel.btnCustom:SetScript("OnClick", function()
        SetReplyMode(REPLY_MODE_CUSTOM)
        UpdateReplyModeButtons()
        RefreshMessageText()
    end)

    panel.btnSaveCustom = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    panel.btnSaveCustom:SetSize(100, 20)
    panel.btnSaveCustom:SetPoint("LEFT", panel.btnCustom, "RIGHT", 6, 0)
    panel.btnSaveCustom:SetScript("OnClick", SaveCustomTemplate)

    panel.messageLabel = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    panel.messageLabel:SetPoint("TOPLEFT", LEFT_PAD, -98)
    panel.messageLabel:SetText("Message")

    local messageBackdrop = CreateFrame("Frame", nil, panel, "BackdropTemplate")
    messageBackdrop:SetPoint("TOPLEFT", panel.messageLabel, "BOTTOMLEFT", 0, -2)
    messageBackdrop:SetWidth(LEFT_CONTENT_RIGHT - LEFT_PAD)
    messageBackdrop:SetHeight(78)
    messageBackdrop:SetBackdrop({
        bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true,
        tileSize = 16,
        edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    messageBackdrop:SetBackdropColor(0, 0, 0, 0.6)
    panel.messageBackdrop = messageBackdrop

    panel.placeholder = messageBackdrop:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    panel.placeholder:SetPoint("TOPLEFT", 6, -6)
    panel.placeholder:SetPoint("TOPRIGHT", -6, -6)
    panel.placeholder:SetJustifyH("LEFT")
    panel.placeholder:SetText(L("CUSTOM_PLACEHOLDER"))
    panel.placeholder:Hide()

    panel.messageEdit = CreateFrame("EditBox", nil, messageBackdrop)
    panel.messageEdit:SetMultiLine(true)
    panel.messageEdit:SetAutoFocus(false)
    panel.messageEdit:SetFontObject(ChatFontNormal)
    panel.messageEdit:SetPoint("TOPLEFT", 5, -5)
    panel.messageEdit:SetPoint("BOTTOMRIGHT", -5, 5)
    panel.messageEdit:SetScript("OnEscapePressed", function(self)
        self:ClearFocus()
    end)
    panel.messageEdit:SetScript("OnTextChanged", function()
        UpdatePlaceholderVisibility()
    end)
    panel.messageEdit:SetScript("OnEditFocusGained", function()
        UpdatePlaceholderVisibility()
    end)
    panel.messageEdit:SetScript("OnEditFocusLost", function()
        UpdatePlaceholderVisibility()
    end)

    panel.btnWhisper = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    panel.btnWhisper:SetSize(80, 20)
    panel.btnWhisper:SetPoint("TOPLEFT", messageBackdrop, "BOTTOMLEFT", 0, -8)
    panel.btnWhisper:SetScript("OnClick", function()
        SetChannel(CHANNEL_WHISPER)
    end)

    panel.btnGuild = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    panel.btnGuild:SetSize(80, 20)
    panel.btnGuild:SetPoint("LEFT", panel.btnWhisper, "RIGHT", 6, 0)
    panel.btnGuild:SetScript("OnClick", function()
        SetChannel(CHANNEL_GUILD)
    end)

    panel.btnSay = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    panel.btnSay:SetSize(80, 20)
    panel.btnSay:SetPoint("LEFT", panel.btnGuild, "RIGHT", 6, 0)
    panel.btnSay:SetScript("OnClick", function()
        SetChannel(CHANNEL_SAY)
    end)

    panel.targetLabel = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    panel.targetLabel:SetPoint("TOPLEFT", panel.btnWhisper, "BOTTOMLEFT", 0, -10)
    panel.targetLabel:SetText("Target")

    panel.targetEdit = CreateFrame("EditBox", nil, panel, "InputBoxTemplate")
    panel.targetEdit:SetSize(240, 18)
    panel.targetEdit:SetPoint("LEFT", panel.targetLabel, "RIGHT", 8, 0)
    panel.targetEdit:SetAutoFocus(false)
    panel.targetEdit:SetScript("OnEscapePressed", function(self)
        self:ClearFocus()
    end)
    panel.targetEdit:SetScript("OnTextChanged", function()
        UpdateSendButtonState()
    end)

    -- Compact vertical recent-targets column (photo layout).
    local recentColumn = CreateFrame("Frame", nil, panel, "BackdropTemplate")
    recentColumn:SetWidth(RECENT_SIDE_WIDTH)
    recentColumn:SetPoint("TOPRIGHT", -10, -26)
    recentColumn:SetPoint("BOTTOMRIGHT", -10, 12)
    recentColumn:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true,
        tileSize = 16,
        edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    recentColumn:SetBackdropColor(0, 0, 0, 0.95)
    recentColumn:SetBackdropBorderColor(0.6, 0.6, 0.6, 1)
    panel.recentColumn = recentColumn

    panel.recentLabel = recentColumn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    panel.recentLabel:SetPoint("TOP", 0, -8)
    panel.recentLabel:SetText("Recent Targets")

    panel.recentScroll = CreateFrame("ScrollFrame", "AltProfLibCraftReplyRecentScroll", recentColumn, "UIPanelScrollFrameTemplate")
    panel.recentScroll:SetPoint("TOPLEFT", 6, -26)
    panel.recentScroll:SetPoint("BOTTOMRIGHT", -26, 6)

    panel.recentContent = CreateFrame("Frame", nil, panel.recentScroll)
    panel.recentContent:SetSize(RECENT_SIDE_WIDTH - 34, 1)
    panel.recentScroll:SetScrollChild(panel.recentContent)

    panel.recentRows = {}
    for i = 1, RECENT_TARGETS_MAX do
        local row = CreateFrame("Button", nil, panel.recentContent)
        row:SetHeight(RECENT_ROW_HEIGHT)
        row:SetWidth(RECENT_SIDE_WIDTH - 34)

        local background = row:CreateTexture(nil, "BACKGROUND")
        background:SetAllPoints()
        background:SetColorTexture(0.12, 0.12, 0.12, 0.85)
        row.background = background

        local highlight = row:CreateTexture(nil, "HIGHLIGHT")
        highlight:SetAllPoints()
        highlight:SetColorTexture(1, 1, 1, 0.12)

        local deleteButton = CreateFrame("Button", nil, row)
        deleteButton:SetSize(RECENT_DELETE_SIZE, RECENT_DELETE_SIZE)
        deleteButton:SetPoint("RIGHT", -2, 0)
        deleteButton:SetFrameLevel(row:GetFrameLevel() + 5)
        deleteButton:SetNormalTexture("Interface\\Buttons\\UI-GroupLoot-Pass-Up")
        deleteButton:SetPushedTexture("Interface\\Buttons\\UI-GroupLoot-Pass-Down")
        deleteButton:SetHighlightTexture("Interface\\Buttons\\UI-GroupLoot-Pass-Highlight", "ADD")
        deleteButton:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText("Remove from recent targets")
            GameTooltip:Show()
        end)
        deleteButton:SetScript("OnLeave", function(self)
            if GameTooltip:IsOwned(self) then
                GameTooltip:Hide()
            end
        end)
        deleteButton:SetScript("OnClick", function()
            if not row.entryIndex then return end
            RemoveRecentTargetAt(row.entryIndex)
            RefreshRecentTargetsList()
        end)
        row.deleteButton = deleteButton

        local nameText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        nameText:SetJustifyH("LEFT")
        nameText:SetWordWrap(false)
        nameText:SetPoint("TOPLEFT", 6, -3)
        nameText:SetPoint("RIGHT", deleteButton, "LEFT", -4, 0)
        row.nameText = nameText

        local metaText = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        metaText:SetJustifyH("LEFT")
        metaText:SetWordWrap(false)
        metaText:SetPoint("TOPLEFT", nameText, "BOTTOMLEFT", 0, 0)
        metaText:SetPoint("RIGHT", deleteButton, "LEFT", -4, 0)
        row.metaText = metaText

        local timeText = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        timeText:SetJustifyH("LEFT")
        timeText:SetWordWrap(false)
        timeText:SetPoint("BOTTOMLEFT", 6, 3)
        timeText:SetPoint("RIGHT", deleteButton, "LEFT", -4, 0)
        row.timeText = timeText

        row:SetScript("OnEnter", function(self)
            self.background:SetColorTexture(0.22, 0.22, 0.22, 0.95)
        end)
        row:SetScript("OnLeave", function(self)
            self.background:SetColorTexture(0.12, 0.12, 0.12, 0.85)
        end)
        row:SetScript("OnClick", function()
            local list = EnsureRecentTargets()
            local entry = list[row.entryIndex]
            if not entry then return end
            SetChannel(CHANNEL_WHISPER)
            if panel.targetEdit then
                panel.targetEdit:SetText(FormatRecentTargetEditValue(entry))
                panel.targetEdit:SetFocus()
            end
            UpdateSendButtonState()
        end)

        row:Hide()
        panel.recentRows[i] = row
    end

    panel.btnSend = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    panel.btnSend:SetSize(90, 22)
    panel.btnSend:SetPoint("BOTTOMLEFT", LEFT_CONTENT_RIGHT - 90, 12)
    panel.btnSend:SetScript("OnClick", SendPanelMessage)

    panel.btnCancel = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    panel.btnCancel:SetSize(90, 22)
    panel.btnCancel:SetPoint("RIGHT", panel.btnSend, "LEFT", -6, 0)
    panel.btnCancel:SetScript("OnClick", ClosePanel)

    return panel
end

local function ApplyLocalizedLabels()
    if not panel then return end
    if panel.TitleText then
        panel.TitleText:SetText(L("PANEL_TITLE"))
    end
    if panel.btnEN then panel.btnEN:SetText(L("BTN_EN")) end
    if panel.btnCustom then panel.btnCustom:SetText(L("BTN_CUSTOM")) end
    if panel.btnSaveCustom then panel.btnSaveCustom:SetText(L("BTN_SAVE_CUSTOM")) end
    if panel.placeholder then panel.placeholder:SetText(L("CUSTOM_PLACEHOLDER")) end
    panel.btnWhisper:SetText(L("BTN_WHISPER"))
    panel.btnGuild:SetText(L("BTN_GUILD"))
    panel.btnSay:SetText(L("BTN_SAY"))
    panel.btnSend:SetText(L("BTN_SEND"))
    panel.btnCancel:SetText(L("BTN_CANCEL"))
end

local function MapStoredChannelToPanel(storedChannel)
    if storedChannel == "GUILD" then
        return CHANNEL_GUILD
    elseif storedChannel == "SAY" or storedChannel == "GENERAL" then
        return CHANNEL_SAY
    end
    return CHANNEL_WHISPER
end

local function ResetAndPopulatePanel(resolvedTarget, resolvedChannel)
    EnsurePanel()
    EnsureReplyMode()
    ApplyLocalizedLabels()

    -- Always reload fresh state on every open (fixes stale/locked reopen).
    if panel.messageEdit then
        panel.messageEdit:ClearFocus()
        panel.messageEdit:SetText("")
    end
    if panel.targetEdit then
        panel.targetEdit:ClearFocus()
        panel.targetEdit:SetText(type(resolvedTarget) == "string" and resolvedTarget or "")
    end

    SetChannel(resolvedChannel)
    UpdateReplyModeButtons()
    RefreshMessageText()
    RefreshRecentTargetsList()
    UpdateSendButtonState()

    local firstLabel = string.format(
        "%s — %s Sk:%s",
        ShortCharacterName(selectedOwner.characterKey),
        tostring(selectedOwner.profession or "?"),
        tostring(tonumber(selectedOwner.skillLevel or 0) or 0)
    )
    UIDropDownMenu_Initialize(panel.charDropDown, OwnerDropdown_Initialize)
    UIDropDownMenu_SetText(panel.charDropDown, firstLabel)

    panel:SetParent(UIParent)
    panel:ClearAllPoints()
    panel:SetPoint("CENTER")
    panel:SetFrameStrata("DIALOG")
    panel:SetToplevel(true)
    panel:EnableMouse(true)
    panel:Show()
    panel:Raise()
end

function API:OpenCraftReplyPanel(itemID, itemLink, targetPlayer)
    itemID = tonumber(itemID)
    if not itemID then
        self:Print("craft reply requires an ItemID")
        return false
    end

    EnsureReplyLocale()
    ownerList = CollectOwnersForItem(itemID)
    if #ownerList == 0 then
        self:Print("no saved crafter for item " .. tostring(itemID))
        return false
    end

    local resolvedTarget = targetPlayer
    local resolvedChannel = CHANNEL_WHISPER

    -- Resolve from visible chat / sender cache. Do not clear AltProfLibLastSender:
    -- the same chat line must still work on a second Shift+Click.
    if self.ResolveCraftReplySender then
        local name, channel = self:ResolveCraftReplySender(itemID, itemLink)
        if (type(resolvedTarget) ~= "string" or strtrim(resolvedTarget) == "") and type(name) == "string" then
            resolvedTarget = name
        end
        if type(channel) == "string" then
            resolvedChannel = MapStoredChannelToPanel(channel)
        end
    elseif type(AltProfLibLastSender) == "table" then
        local lastSender = AltProfLibLastSender
        if (type(resolvedTarget) ~= "string" or strtrim(resolvedTarget) == "") and type(lastSender.name) == "string" then
            resolvedTarget = lastSender.name
        end
        if type(lastSender.channel) == "string" then
            resolvedChannel = MapStoredChannelToPanel(lastSender.channel)
        end
    end

    currentItemID = itemID
    currentItemDisplay = ResolveItemDisplay(itemID, itemLink)
    selectedOwner = ownerList[1]

    ResetAndPopulatePanel(resolvedTarget, resolvedChannel)
    return true
end
local boot = CreateFrame("Frame")
boot:RegisterEvent("PLAYER_LOGIN")
boot:SetScript("OnEvent", function()
    EnsureReplyLocale()
    EnsureReplyMode()
    EnsureRecentTargets()
end)
