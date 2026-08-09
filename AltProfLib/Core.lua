local ADDON_NAME, ns = ...
-- AltProfLib release 1.0.1

AltProfLib = AltProfLib or {}
ns.API = AltProfLib
ns.ADDON_NAME = ADDON_NAME
ns.VERSION = "1.0.1"
ns.SCHEMA_VERSION = 4
ns.IS_BETA = false

local API = ns.API
local frame = CreateFrame("Frame")

function API:GetVersion()
    return ns.VERSION
end

function API:IsBeta()
    return ns.IS_BETA == true
end

function API:Print(...)
    print("|cff66ccffAltProfLib:|r", ...)
end

function API:Debug(...)
    local db = self.GetDB and self:GetDB()
    if not db or not db.settings or not db.settings.debug then return end
    self:Print(...)
end

function API:SafeCall(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, a, b, c, d, e, f, g = pcall(fn, ...)
    if ok then return a, b, c, d, e, f, g end
    return nil
end

function API:Log(event, payload)
    local db = self.GetDB and self:GetDB()
    if not db then return end
    db.debugLog = db.debugLog or {}
    table.insert(db.debugLog, 1, {
        time = time(),
        event = event,
        payload = payload,
    })
    while #db.debugLog > 200 do
        table.remove(db.debugLog)
    end
end

frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGIN")
frame:SetScript("OnEvent", function(_, event, arg1)
    if event == "ADDON_LOADED" and arg1 == ADDON_NAME then
        if API.InitDB then
            API:InitDB()
        end
        API:Log("ADDON_LOADED", ADDON_NAME)
    elseif event == "PLAYER_LOGIN" then
        if API.RefreshCharacterRecord then
            API:RefreshCharacterRecord()
        end
        if API.ScanProfessions then
            API:ScanProfessions("PLAYER_LOGIN")
        end
        if API.RebuildProfessionIndex then
            API:RebuildProfessionIndex("PLAYER_LOGIN")
        end
        if API.RebuildRecipeOwnerIndex then
            API:RebuildRecipeOwnerIndex("PLAYER_LOGIN")
        end
        if API.RebuildCraftedItemIndex then
            API:RebuildCraftedItemIndex("PLAYER_LOGIN")
        end
        API:Print("|cffffd700AltProfLib|r " .. ns.VERSION .. " loaded.")
        API:Print("Profession Scan Complete! Version", ns.VERSION)
    end
end)
