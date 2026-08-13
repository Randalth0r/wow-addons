local ADDON_NAME, ns = ...
-- AltProfLib release 1.0.2
local API = ns.API

local defaults = {
    schemaVersion = ns.SCHEMA_VERSION,
    addonVersion = ns.VERSION,
    characters = {},
    professionOwners = {},
    professionIndex = {},
    recipeOwnerIndex = {},
    craftedItemIndex = {},
    learnedRecipes = {},
    settings = {
        debug = false,
        tooltipEnabled = true,
        tooltipDebug = false,
    },
    debugLog = {},
}

local function CopyDefaults(src, dst)
    if type(dst) ~= "table" then dst = {} end
    for k, v in pairs(src) do
        if type(v) == "table" then
            dst[k] = CopyDefaults(v, dst[k])
        elseif dst[k] == nil then
            dst[k] = v
        end
    end
    return dst
end

local function CopyMissingTableValues(src, dst)
    if type(src) ~= "table" then return dst end
    if type(dst) ~= "table" then dst = {} end

    for k, v in pairs(src) do
        if type(v) == "table" then
            dst[k] = CopyMissingTableValues(v, dst[k])
        elseif dst[k] == nil then
            dst[k] = v
        end
    end

    return dst
end

local function GetDisplayRealmNameSafe()
    -- Use GetRealmName() as the canonical account-visible realm key.
    -- UnitFullName("player") may return a normalized realm without spaces on connected realms,
    -- which caused duplicate character keys such as:
    -- Màtrim-Pozzo dell'Eternità and Màtrim-Pozzodell'Eternità.
    local realm = GetRealmName and GetRealmName() or nil
    if realm and realm ~= "" then return realm end

    if GetNormalizedRealmName then
        local normalized = GetNormalizedRealmName()
        if normalized and normalized ~= "" then return normalized end
    end

    local _, unitRealm = UnitFullName("player")
    if unitRealm and unitRealm ~= "" then return unitRealm end

    return "UnknownRealm"
end

local function GetUnitFullNameRealmKey()
    local name, unitRealm = UnitFullName("player")
    name = name or UnitName("player") or "Unknown"
    unitRealm = unitRealm or ""
    if unitRealm ~= "" then
        return name .. "-" .. unitRealm
    end
    return nil
end

function API:GetCharacterKey()
    local name = UnitName("player") or "Unknown"
    return name .. "-" .. GetDisplayRealmNameSafe()
end

function API:GetCharacterRealm()
    return GetDisplayRealmNameSafe()
end

function API:GetDB()
    return AltProfLibDB
end

function API:GetLegacySpecDB()
    return AltProfSpecTracker
end

function API:GetLegacyRecipeDB()
    return AltProfRecipeTrackerDB
end

function API:MigrateCurrentCharacterKeys()
    local db = self:GetDB()
    if not db then return end

    local canonicalKey = self:GetCharacterKey()
    local legacyKey = GetUnitFullNameRealmKey()

    if legacyKey and legacyKey ~= canonicalKey then
        db.characters[canonicalKey] = CopyMissingTableValues(db.characters[legacyKey], db.characters[canonicalKey])
        db.characters[legacyKey] = nil

        db.learnedRecipes[canonicalKey] = CopyMissingTableValues(db.learnedRecipes[legacyKey], db.learnedRecipes[canonicalKey])
        db.learnedRecipes[legacyKey] = nil

        if type(db.professionOwners) == "table" then
            for professionKey, ownerKey in pairs(db.professionOwners) do
                if ownerKey == legacyKey then
                    db.professionOwners[professionKey] = canonicalKey
                end
            end
        end

        AltProfSpecTracker = AltProfSpecTracker or {}
        for professionKey, ownerKey in pairs(AltProfSpecTracker) do
            if ownerKey == legacyKey then
                AltProfSpecTracker[professionKey] = canonicalKey
            end
        end

        AltProfRecipeTrackerDB = AltProfRecipeTrackerDB or {}
        AltProfRecipeTrackerDB.LearnedRecipes = AltProfRecipeTrackerDB.LearnedRecipes or {}
        AltProfRecipeTrackerDB.LearnedRecipes[canonicalKey] = CopyMissingTableValues(
            AltProfRecipeTrackerDB.LearnedRecipes[legacyKey],
            AltProfRecipeTrackerDB.LearnedRecipes[canonicalKey]
        )
        AltProfRecipeTrackerDB.LearnedRecipes[legacyKey] = nil

        self:Log("MIGRATE_CHARACTER_KEY", { from = legacyKey, to = canonicalKey })
    end
end

function API:InitDB()
    AltProfLibDB = CopyDefaults(defaults, AltProfLibDB)
    AltProfLibDB.schemaVersion = ns.SCHEMA_VERSION
    AltProfLibDB.addonVersion = ns.VERSION
    AltProfLibDB.professionIndex = AltProfLibDB.professionIndex or {}
    AltProfLibDB.recipeOwnerIndex = AltProfLibDB.recipeOwnerIndex or {}
    AltProfLibDB.craftedItemIndex = AltProfLibDB.craftedItemIndex or {}
    AltProfLibDB.settings = AltProfLibDB.settings or {}
    -- User-facing tooltip integration is enabled by default.
    -- Diagnostic modes are reset to false on load to avoid noisy chat output.
    AltProfLibDB.settings.tooltipEnabled = true
    AltProfLibDB.settings.tooltipDebug = false
    AltProfLibDB.settings.linkDebug = false
    AltProfLibDB.settings.debug = false

    AltProfSpecTracker = AltProfSpecTracker or {}
    AltProfRecipeTrackerDB = AltProfRecipeTrackerDB or {}
    AltProfRecipeTrackerDB.LearnedRecipes = AltProfRecipeTrackerDB.LearnedRecipes or {}

    self:MigrateCurrentCharacterKeys()
    self:RefreshCharacterRecord()
end

function API:RefreshCharacterRecord()
    local db = self:GetDB()
    if not db then return nil end

    local key = self:GetCharacterKey()
    db.characters[key] = db.characters[key] or {}

    local rec = db.characters[key]
    rec.key = key
    rec.name = UnitName("player") or "Unknown"
    rec.realm = GetDisplayRealmNameSafe()
    rec.class = select(2, UnitClass("player"))
    rec.faction = UnitFactionGroup("player")
    rec.level = UnitLevel("player")
    rec.lastSeen = time()
    rec.professions = rec.professions or {}

    return rec, key
end

function API:GetCharacterRecord()
    return self:RefreshCharacterRecord()
end

function API:EnsureRecipeBucket(characterKey, professionID)
    local db = self:GetDB()
    if not db then return nil end

    characterKey = characterKey or self:GetCharacterKey()
    professionID = tonumber(professionID) or 0

    db.learnedRecipes[characterKey] = db.learnedRecipes[characterKey] or {}
    db.learnedRecipes[characterKey][professionID] = db.learnedRecipes[characterKey][professionID] or {}

    AltProfRecipeTrackerDB = AltProfRecipeTrackerDB or {}
    AltProfRecipeTrackerDB.LearnedRecipes = AltProfRecipeTrackerDB.LearnedRecipes or {}
    AltProfRecipeTrackerDB.LearnedRecipes[characterKey] = AltProfRecipeTrackerDB.LearnedRecipes[characterKey] or {}
    AltProfRecipeTrackerDB.LearnedRecipes[characterKey][professionID] = AltProfRecipeTrackerDB.LearnedRecipes[characterKey][professionID] or {}

    return db.learnedRecipes[characterKey][professionID], AltProfRecipeTrackerDB.LearnedRecipes[characterKey][professionID]
end
