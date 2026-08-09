local ADDON_NAME, ns = ...
-- AltProfLib release 1.0.1
local API = ns.API

local function IsKnownProfessionName(name)
    return type(name) == "string" and name ~= "" and name ~= "Unknown" and name ~= "Unknown Profession"
end

local function CleanTargetName(targetName)
    if type(targetName) ~= "string" then return nil end
    targetName = strtrim(targetName)
    if targetName == "" then return nil end
    targetName = targetName:gsub("[%c\n\r]", " ")
    targetName = strtrim(targetName)
    if targetName == "" then return nil end
    return targetName
end

local function GetItemName(itemID)
    itemID = tonumber(itemID)
    if not itemID then return nil end
    if C_Item and C_Item.GetItemInfo then
        local name = C_Item.GetItemInfo(itemID)
        if name then return name end
    end
    if GetItemInfo then
        local name = GetItemInfo(itemID)
        if name then return name end
    end
    return nil
end

local function ComposeMessage(craftName, owner, targetName)
    if type(owner) ~= "table" then return nil, "no valid crafter" end
    local crafter = owner.characterKey or "my crafter"
    local profession = IsKnownProfessionName(owner.profession) and owner.profession or "the required profession"
    local greeting = CleanTargetName(targetName)
    craftName = craftName or "that item"

    if greeting then
        return string.format(
            "Hi %s, I can craft %s on %s (%s). Send me the mats and I can craft it for you.",
            greeting, craftName, crafter, profession
        )
    end

    return string.format(
        "Hi, I can craft %s on %s (%s). Send me the mats and I can craft it for you.",
        craftName, crafter, profession
    )
end

function API:BuildCrafterMessage(recipeID, characterKey, targetName)
    recipeID = tonumber(recipeID)
    if not recipeID then return nil, "missing RecipeID" end

    if self.RebuildRecipeOwnerIndex then self:RebuildRecipeOwnerIndex("build crafter message") end
    local entry = self.GetRecipeIndexEntry and self:GetRecipeIndexEntry(recipeID)
    if type(entry) ~= "table" then return nil, "recipe not known" end

    local owner
    if characterKey and type(entry.owners) == "table" and type(entry.owners[characterKey]) == "table" then
        for _, candidate in pairs(entry.owners[characterKey]) do
            if type(candidate) == "table" and IsKnownProfessionName(candidate.profession) then
                owner = candidate
                break
            end
        end
    end

    owner = owner or (self.GetPreferredRecipeOwner and self:GetPreferredRecipeOwner(recipeID))
    if type(owner) ~= "table" then return nil, "no valid recipe owner" end

    local recipeName = entry.name or owner.name or ("recipe " .. tostring(recipeID))
    local message = ComposeMessage(recipeName, owner, targetName)
    return message, owner, entry
end

function API:BuildCrafterMessageForItem(itemID, targetName)
    itemID = tonumber(itemID)
    if not itemID then return nil, "missing ItemID" end

    local owner, recipe = self.GetPreferredCraftedItemOwner and self:GetPreferredCraftedItemOwner(itemID)
    if type(owner) ~= "table" then return nil, "item not known" end

    local craftName = GetItemName(itemID) or (type(recipe) == "table" and recipe.name) or ("item " .. tostring(itemID))
    local message = ComposeMessage(craftName, owner, targetName)
    return message, owner, recipe
end

local function FindCraftedItemIDForRecipe(recipeID)
    recipeID = tonumber(recipeID)
    if not recipeID then return nil end

    local db = API.GetDB and API:GetDB()
    if not db then return nil end

    if API.RebuildCraftedItemIndex then
        API:RebuildCraftedItemIndex("craft reply recipe")
    end

    for itemID, itemEntry in pairs(db.craftedItemIndex or {}) do
        if type(itemEntry) == "table" and type(itemEntry.recipes) == "table" and itemEntry.recipes[recipeID] then
            return tonumber(itemID)
        end
    end

    for _, byProfession in pairs(db.learnedRecipes or {}) do
        if type(byProfession) == "table" then
            for _, recipeBucket in pairs(byProfession) do
                if type(recipeBucket) == "table" then
                    local payload = recipeBucket[recipeID]
                    if type(payload) == "table" and tonumber(payload.craftedItemID) then
                        return tonumber(payload.craftedItemID)
                    end
                end
            end
        end
    end

    return nil
end

function API:DraftCrafterMessage(recipeID, characterKey, targetName)
    recipeID = tonumber(recipeID)
    if not recipeID then
        self:Print("cannot draft message for recipe: missing RecipeID")
        return false
    end
    if not self.OpenCraftReplyPanel then
        self:Print("craft reply panel is not available")
        return false
    end

    local itemID = FindCraftedItemIDForRecipe(recipeID)
    if not itemID then
        self:Print("cannot draft message for recipe " .. tostring(recipeID) .. ": no crafted item")
        return false
    end

    return self:OpenCraftReplyPanel(itemID, nil, targetName)
end

function API:DraftCrafterMessageForItem(itemID, targetName)
    itemID = tonumber(itemID)
    if not itemID then
        self:Print("cannot draft message for item: missing ItemID")
        return false
    end
    if not self.OpenCraftReplyPanel then
        self:Print("craft reply panel is not available")
        return false
    end
    return self:OpenCraftReplyPanel(itemID, nil, targetName)
end

function API:PreviewCrafterMessage(recipeID, characterKey, targetName)
    local message = self:BuildCrafterMessage(recipeID, characterKey, targetName)
    if not message then
        self:Print("cannot preview message for recipe " .. tostring(recipeID))
        return false
    end
    self:Print("draft preview:", message)
    return true
end

function API:PreviewCrafterMessageForItem(itemID, targetName)
    local message = self:BuildCrafterMessageForItem(itemID, targetName)
    if not message then
        self:Print("cannot preview message for item " .. tostring(itemID))
        return false
    end
    self:Print("draft preview:", message)
    return true
end

-- Capture requester from chat messages that contain item links.
-- Circular cache + visible ChatFrame scan; AltProfLibLastSender stays until a different sender/link wins.
local SENDER_CACHE_MAX = 10

AltProfLibSenderCache = AltProfLibSenderCache or {}

local function MessageHasItemLink(msg)
    return type(msg) == "string" and msg:find("|Hitem:", 1, true) ~= nil
end

local function NormalizeChatSender(author)
    if type(author) ~= "string" then return nil end
    author = strtrim(author)
    if author == "" then return nil end
    if Ambiguate then
        author = Ambiguate(author, "none")
    end
    return author
end

local function IsOwnChatSender(author)
    local name = NormalizeChatSender(author)
    if not name then return true end

    local me = GetUnitName and GetUnitName("player") or nil
    if not me and UnitName then
        me = UnitName("player")
    end
    if not me then return false end

    if Ambiguate then
        return Ambiguate(name, "none") == Ambiguate(me, "none")
    end
    return name == me
end

local function ChannelFromChatEvent(event)
    if event == "CHAT_MSG_GUILD" then
        return "GUILD"
    elseif event == "CHAT_MSG_SAY" then
        return "SAY"
    elseif event == "CHAT_MSG_WHISPER" or event == "CHAT_MSG_WHISPER_INFORM" then
        return "WHISPER"
    elseif event == "CHAT_MSG_CHANNEL" then
        return "GENERAL"
    elseif event == "CHAT_MSG_PARTY" or event == "CHAT_MSG_PARTY_LEADER" then
        return "WHISPER"
    end
    return "WHISPER"
end

local function ChannelFromPlayerLinkType(chatType)
    if type(chatType) ~= "string" then return nil end
    chatType = string.upper(chatType)
    if chatType == "GUILD" or chatType == "OFFICER" then
        return "GUILD"
    elseif chatType == "SAY" or chatType == "YELL" or chatType == "EMOTE" then
        return "SAY"
    elseif chatType == "WHISPER" or chatType == "WHISPER_INFORM" or chatType == "BN_WHISPER" then
        return "WHISPER"
    elseif chatType == "CHANNEL" or chatType == "GENERAL" then
        return "GENERAL"
    elseif chatType == "PARTY" or chatType == "PARTY_LEADER" or chatType == "RAID" or chatType == "RAID_LEADER" or chatType == "INSTANCE_CHAT" then
        return "WHISPER"
    end
    return nil
end

local function MessageContainsItem(msg, itemID, itemLink)
    if type(msg) ~= "string" then return false end
    if type(itemLink) == "string" and itemLink ~= "" then
        local payload = itemLink:match("|H(item:[^|]+)|h") or itemLink
        if payload ~= "" and msg:find(payload, 1, true) then
            return true
        end
    end
    itemID = tonumber(itemID)
    if itemID and msg:find("item:" .. tostring(itemID), 1, true) then
        return true
    end
    return false
end

local function ParseSenderFromChatLine(text)
    if type(text) ~= "string" then return nil, nil end

    local body = text:match("|Hplayer:([^|]+)|h")
    if not body then return nil, nil end

    local name, lineID, chatType = body:match("^([^:]+):(%d+):([^:]+)")
    if not name then
        name = body:match("^([^:]+)")
    end
    name = NormalizeChatSender(name)
    if not name or IsOwnChatSender(name) then
        return nil, nil
    end

    local channel = ChannelFromPlayerLinkType(chatType) or "WHISPER"
    return name, channel
end

local function SetLastSender(name, channel, extra)
    name = NormalizeChatSender(name)
    if not name then return end
    extra = type(extra) == "table" and extra or {}
    AltProfLibLastSender = {
        name = name,
        channel = channel or "WHISPER",
        classFilename = extra.classFilename,
        level = extra.level,
        guid = extra.guid,
    }
end

local function ResolveClassLevelFromGuid(guid, name)
    local classFilename, level
    if type(guid) == "string" and guid ~= "" and GetPlayerInfoByGUID then
        local _, englishClass = GetPlayerInfoByGUID(guid)
        if type(englishClass) == "string" and englishClass ~= "" then
            classFilename = englishClass
        end
    end

    if type(name) == "string" and name ~= "" and UnitExists and UnitExists(name) and UnitClass then
        local _, unitClass = UnitClass(name)
        classFilename = unitClass or classFilename
        if UnitLevel then
            local unitLevel = UnitLevel(name)
            if unitLevel and unitLevel > 0 then
                level = unitLevel
            end
        end
    end

    return classFilename, level
end

local function ClassFromChatColor(text)
    if type(text) ~= "string" or not RAID_CLASS_COLORS then return nil end

    -- Prefer the color immediately before a player hyperlink; fall back to any leading color.
    local hex = text:match("|c%x%x(%x%x%x%x%x%x)|Hplayer:")
        or text:match("|cff(%x%x%x%x%x%x)|Hplayer:")
        or text:match("%[|cff(%x%x%x%x%x%x)(.-)|r%]")
    if not hex then return nil end
    hex = string.lower(hex)
    local pr = tonumber(hex:sub(1, 2), 16)
    local pg = tonumber(hex:sub(3, 4), 16)
    local pb = tonumber(hex:sub(5, 6), 16)
    if not pr then return nil end

    local bestClass, bestDist
    for classFilename, color in pairs(RAID_CLASS_COLORS) do
        local cr = math.floor(color.r * 255 + 0.5)
        local cg = math.floor(color.g * 255 + 0.5)
        local cb = math.floor(color.b * 255 + 0.5)
        local dist = (cr - pr) * (cr - pr) + (cg - pg) * (cg - pg) + (cb - pb) * (cb - pb)
        if not bestDist or dist < bestDist then
            bestDist = dist
            bestClass = classFilename
        end
    end

    -- Allow slight formatting differences from chat.
    if bestDist and bestDist <= 220 then
        return bestClass
    end
    return nil
end

local function PushSenderCache(name, channel, message, extra)
    name = NormalizeChatSender(name)
    if not name or type(message) ~= "string" then return end
    extra = type(extra) == "table" and extra or {}

    local classFilename = extra.classFilename or ClassFromChatColor(message)
    local level = extra.level
    local guid = extra.guid
    if guid and (not classFilename or not level) then
        local guidClass, guidLevel = ResolveClassLevelFromGuid(guid, name)
        classFilename = classFilename or guidClass
        level = level or guidLevel
    end

    local cache = AltProfLibSenderCache
    for i = 1, #cache do
        if cache[i].message == message or (cache[i].name == name and cache[i].guid == guid and guid) then
            local entry = table.remove(cache, i)
            entry.name = name
            entry.channel = channel or entry.channel or "WHISPER"
            entry.message = message
            entry.classFilename = classFilename or entry.classFilename
            entry.level = level or entry.level
            entry.guid = guid or entry.guid
            table.insert(cache, 1, entry)
            SetLastSender(entry.name, entry.channel, entry)
            return
        end
    end

    local entry = {
        name = name,
        channel = channel or "WHISPER",
        message = message,
        classFilename = classFilename,
        level = level,
        guid = guid,
    }
    table.insert(cache, 1, entry)
    while #cache > SENDER_CACHE_MAX do
        table.remove(cache)
    end
    SetLastSender(name, channel, entry)
end

local function FindSenderInCache(itemID, itemLink)
    local cache = AltProfLibSenderCache
    if type(cache) ~= "table" then return nil end
    for i = 1, #cache do
        local entry = cache[i]
        if type(entry) == "table" and MessageContainsItem(entry.message, itemID, itemLink) then
            return entry
        end
    end
    return nil
end

local function FindSenderInChatFrames(itemID, itemLink)
    local maxWindows = tonumber(NUM_CHAT_WINDOWS) or 10
    for frameIndex = 1, maxWindows do
        local frame = _G["ChatFrame" .. tostring(frameIndex)]
        if frame and frame.GetNumMessages and frame.GetMessageInfo then
            local okNum, numMessages = pcall(function()
                return frame:GetNumMessages()
            end)
            if okNum and type(numMessages) == "number" then
                for messageIndex = numMessages, 1, -1 do
                    local okInfo, text = pcall(function()
                        return frame:GetMessageInfo(messageIndex)
                    end)
                    if okInfo and type(text) == "string" and MessageContainsItem(text, itemID, itemLink) then
                        local name, channel = ParseSenderFromChatLine(text)
                        if name then
                            return {
                                name = name,
                                channel = channel or "WHISPER",
                                message = text,
                                classFilename = ClassFromChatColor(text),
                            }
                        end
                    end
                end
            end
        end
    end
    return nil
end

function API:ResolveCraftReplySender(itemID, itemLink)
    itemID = tonumber(itemID)

    local found = FindSenderInChatFrames(itemID, itemLink)
    if not found then
        found = FindSenderInCache(itemID, itemLink)
    end

    if found and type(found.name) == "string" then
        SetLastSender(found.name, found.channel, found)
        if type(found.message) == "string" then
            PushSenderCache(found.name, found.channel, found.message, found)
        end
        return found.name, found.channel or "WHISPER", found
    end

    if type(AltProfLibLastSender) == "table" and type(AltProfLibLastSender.name) == "string" then
        return AltProfLibLastSender.name, AltProfLibLastSender.channel or "WHISPER", AltProfLibLastSender
    end

    return nil, nil, nil
end

function API:GetSenderInfoByName(name, realm)
    name = NormalizeChatSender(name)
    if not name then return nil end
    local shortName = name:match("^([^%-]+)") or name
    local wantRealm = type(realm) == "string" and realm or ""

    local function Matches(entryName)
        entryName = NormalizeChatSender(entryName)
        if not entryName then return false end
        local entryShort = entryName:match("^([^%-]+)") or entryName
        local entryRealm = entryName:match("^[^%-]+%-(.+)$") or ""
        if entryShort ~= shortName then return false end
        if wantRealm ~= "" and entryRealm ~= "" and entryRealm ~= wantRealm then
            return false
        end
        return true
    end

    local cache = AltProfLibSenderCache
    if type(cache) == "table" then
        for i = 1, #cache do
            local entry = cache[i]
            if type(entry) == "table" and Matches(entry.name) then
                if entry.guid and not entry.classFilename then
                    local classFilename = ResolveClassLevelFromGuid(entry.guid, entry.name)
                    entry.classFilename = classFilename or entry.classFilename
                end
                return entry
            end
        end
    end

    if type(AltProfLibLastSender) == "table" and Matches(AltProfLibLastSender.name) then
        return AltProfLibLastSender
    end

    return nil
end

local function RememberChatSender(event, msg, author, guid)
    if not MessageHasItemLink(msg) then return end

    local name = NormalizeChatSender(author)
    local classFilename, level = ResolveClassLevelFromGuid(guid, name)

    local extra = {
        guid = type(guid) == "string" and guid ~= "" and guid or nil,
        classFilename = classFilename,
        level = level,
    }

    -- Outgoing whisper inform: arg2 is the whisper partner (still useful for reply target).
    if event == "CHAT_MSG_WHISPER_INFORM" then
        if not name then return end
        PushSenderCache(name, "WHISPER", msg, extra)
        return
    end

    if IsOwnChatSender(author) then return end
    if not name then return end

    PushSenderCache(name, ChannelFromChatEvent(event), msg, extra)
end

local function ChatSenderCaptureFilter(_, event, msg, author, ...)
    -- arg12 of CHAT_MSG_* is the sender GUID; after msg+author that is select(10, ...)
    local guid = select(10, ...)
    RememberChatSender(event, msg, author, guid)
    return false
end

if ChatFrame_AddMessageEventFilter then
    ChatFrame_AddMessageEventFilter("CHAT_MSG_GUILD", ChatSenderCaptureFilter)
    ChatFrame_AddMessageEventFilter("CHAT_MSG_SAY", ChatSenderCaptureFilter)
    ChatFrame_AddMessageEventFilter("CHAT_MSG_CHANNEL", ChatSenderCaptureFilter)
    ChatFrame_AddMessageEventFilter("CHAT_MSG_WHISPER", ChatSenderCaptureFilter)
    ChatFrame_AddMessageEventFilter("CHAT_MSG_WHISPER_INFORM", ChatSenderCaptureFilter)
    ChatFrame_AddMessageEventFilter("CHAT_MSG_PARTY", ChatSenderCaptureFilter)
    ChatFrame_AddMessageEventFilter("CHAT_MSG_PARTY_LEADER", ChatSenderCaptureFilter)
end

-- Keep cache warm for every chat window; filters already cover events globally,
-- but hyperlink clicks can still resolve against each frame's visible history.
local chatFrameHooks = {}
local function HookChatFrameHyperlink(frame)
    if not frame or chatFrameHooks[frame] or not frame.HookScript then return end
    if frame.HasScript and not frame:HasScript("OnHyperlinkClick") then return end
    local ok = pcall(function()
        frame:HookScript("OnHyperlinkClick", function(_, link)
            if type(link) ~= "string" or not link:find("item:", 1, true) then return end
            local itemID = tonumber(link:match("item:(%-?%d+)"))
            if API.ResolveCraftReplySender then
                API:ResolveCraftReplySender(itemID, link)
            end
        end)
    end)
    if ok then
        chatFrameHooks[frame] = true
    end
end

local function HookAllChatFrames()
    local maxWindows = tonumber(NUM_CHAT_WINDOWS) or 10
    for i = 1, maxWindows do
        HookChatFrameHyperlink(_G["ChatFrame" .. tostring(i)])
    end
end

HookAllChatFrames()
if hooksecurefunc and FCF_OpenTemporaryWindow then
    hooksecurefunc("FCF_OpenTemporaryWindow", function()
        HookAllChatFrames()
    end)
end
if C_Timer and C_Timer.After then
    C_Timer.After(0, HookAllChatFrames)
    C_Timer.After(1, HookAllChatFrames)
end
