local ADDON_NAME, ns = ...
-- AltProfLib release 1.0.2
local API = ns.API

local function WipeTable(t)
    if type(t) ~= "table" then return {} end
    for k in pairs(t) do t[k] = nil end
    return t
end

local function CountTable(t)
    local count = 0
    if type(t) == "table" then
        for _ in pairs(t) do count = count + 1 end
    end
    return count
end

function API:RebuildProfessionIndex(reason)
    local db = self:GetDB()
    if not db then return 0 end

    db.professionIndex = WipeTable(db.professionIndex or {})
    local count = 0

    for charKey, rec in pairs(db.characters or {}) do
        if type(rec) == "table" and type(rec.professions) == "table" then
            for profName, info in pairs(rec.professions) do
                local professionID = tonumber(info.professionID or info.skillLine)
                if professionID then
                    db.professionIndex[professionID] = db.professionIndex[professionID] or {
                        professionID = professionID,
                        name = profName,
                        characters = {},
                    }
                    local bucket = db.professionIndex[professionID]
                    bucket.name = bucket.name or profName
                    bucket.characters[charKey] = {
                        key = charKey,
                        name = rec.name,
                        realm = rec.realm,
                        class = rec.class,
                        faction = rec.faction,
                        skillLevel = info.skillLevel,
                        maxSkillLevel = info.maxSkillLevel,
                        slot = info.slot,
                        lastSeen = info.lastSeen or rec.lastSeen,
                    }
                    count = count + 1
                end
            end
        end
    end

    self:Log("REBUILD_PROFESSION_INDEX", { reason = reason or "manual", count = count })
    return count
end

local function IsKnownProfessionName(name)
    return type(name) == "string" and name ~= "" and name ~= "Unknown" and name ~= "Unknown Profession"
end

local function FindCharacterProfessionName(db, charKey, professionID)
    local rec = db and db.characters and db.characters[charKey]
    if type(rec) ~= "table" or type(rec.professions) ~= "table" then return nil end

    professionID = tonumber(professionID)
    if not professionID or professionID <= 0 then return nil end

    for profName, info in pairs(rec.professions) do
        if type(info) == "table" then
            local id = tonumber(info.professionID or info.skillLine)
            if id == professionID then return profName end
        end
    end
    return nil
end

local function BucketHasRealProfession(bucket, charKey)
    if type(bucket) ~= "table" or type(bucket.owners) ~= "table" then return false end
    local owners = bucket.owners[charKey]
    if type(owners) ~= "table" then return false end
    for professionID, owner in pairs(owners) do
        local numericProfessionID = tonumber(professionID) or 0
        if numericProfessionID > 0 and type(owner) == "table" and IsKnownProfessionName(owner.profession) then
            return true
        end
    end
    return false
end


local function CollectPayloadCraftedItemIDs(payload)
    local ids, seen = {}, {}
    local function add(itemID)
        itemID = tonumber(itemID)
        if not itemID or itemID <= 0 or seen[itemID] then return end
        seen[itemID] = true
        table.insert(ids, itemID)
    end

    if type(payload) ~= "table" then return ids end
    if type(payload.craftedItemIDs) == "table" then
        for _, itemID in ipairs(payload.craftedItemIDs) do
            add(itemID)
        end
    end
    add(payload.craftedItemID)
    return ids
end

function API:RebuildCraftedItemIndex(reason)
    local db = self:GetDB()
    if not db then return 0 end

    db.craftedItemIndex = WipeTable(db.craftedItemIndex or {})
    local count = 0

    for recipeID, recipeEntry in pairs(db.recipeOwnerIndex or {}) do
        for charKey, byProfession in pairs(db.learnedRecipes or {}) do
            if type(byProfession) == "table" then
                for professionID, recipeBucket in pairs(byProfession) do
                    local payload = type(recipeBucket) == "table" and recipeBucket[tonumber(recipeID)] or nil
                    if type(payload) == "table" then
                        local craftedItemIDs = CollectPayloadCraftedItemIDs(payload)
                        if #craftedItemIDs > 0 then
                            local numericRecipeID = tonumber(recipeID)
                            local numericProfessionID = tonumber(professionID) or tonumber(payload.professionID) or 0
                            for _, craftedItemID in ipairs(craftedItemIDs) do
                                db.craftedItemIndex[craftedItemID] = db.craftedItemIndex[craftedItemID] or {
                                    itemID = craftedItemID,
                                    recipes = {},
                                }
                                db.craftedItemIndex[craftedItemID].recipes[numericRecipeID] = db.craftedItemIndex[craftedItemID].recipes[numericRecipeID] or {
                                    recipeID = numericRecipeID,
                                    name = recipeEntry.name or payload.name,
                                    professionID = numericProfessionID,
                                    owners = recipeEntry.owners or {},
                                }
                                local itemRecipe = db.craftedItemIndex[craftedItemID].recipes[numericRecipeID]
                                itemRecipe.name = itemRecipe.name or recipeEntry.name or payload.name
                                itemRecipe.professionID = itemRecipe.professionID or numericProfessionID
                                itemRecipe.owners = recipeEntry.owners or itemRecipe.owners or {}
                                count = count + 1
                            end
                        end
                    end
                end
            end
        end
    end

    self:Log("REBUILD_CRAFTED_ITEM_INDEX", { reason = reason or "manual", count = count })
    return count
end

function API:RebuildRecipeOwnerIndex(reason)
    local db = self:GetDB()
    if not db then return 0 end

    db.recipeOwnerIndex = WipeTable(db.recipeOwnerIndex or {})
    local count = 0

    for charKey, byProfession in pairs(db.learnedRecipes or {}) do
        if type(byProfession) == "table" then
            for professionID, recipeBucket in pairs(byProfession) do
                local numericProfessionID = tonumber(professionID) or 0
                if type(recipeBucket) == "table" then
                    for recipeID, payload in pairs(recipeBucket) do
                        local numericRecipeID = tonumber(recipeID)
                        if numericRecipeID then
                            db.recipeOwnerIndex[numericRecipeID] = db.recipeOwnerIndex[numericRecipeID] or {
                                recipeID = numericRecipeID,
                                name = type(payload) == "table" and payload.name or nil,
                                owners = {},
                            }
                            local bucket = db.recipeOwnerIndex[numericRecipeID]
                            if type(payload) == "table" and payload.name then bucket.name = payload.name end

                            local payloadProfession = type(payload) == "table" and payload.profession or nil
                            local rosterProfession = FindCharacterProfessionName(db, charKey, numericProfessionID)
                            local professionName = IsKnownProfessionName(payloadProfession) and payloadProfession or rosterProfession

                            -- ProfessionID 0 is a fallback bucket used only when the active profession
                            -- cannot be resolved. Do not let it pollute command/tooltip output if the
                            -- same character also has the recipe indexed under a real profession.
                            if numericProfessionID > 0 or not BucketHasRealProfession(bucket, charKey) then
                                if numericProfessionID > 0 or IsKnownProfessionName(professionName) then
                                    bucket.owners[charKey] = bucket.owners[charKey] or {}
                                    bucket.owners[charKey][numericProfessionID] = {
                                        characterKey = charKey,
                                        professionID = numericProfessionID,
                                        profession = professionName,
                                        name = type(payload) == "table" and payload.name or nil,
                                        icon = type(payload) == "table" and payload.icon or nil,
                                        lastSeen = type(payload) == "table" and payload.lastSeen or nil,
                                    }
                                    count = count + 1
                                end
                            end
                        end
                    end
                end
            end
        end
    end

    self:Log("REBUILD_RECIPE_OWNER_INDEX", { reason = reason or "manual", count = count })
    return count
end

function API:GetAccountStats()
    local db = self:GetDB()
    local stats = {
        characters = 0,
        professionEntries = 0,
        indexedProfessions = 0,
        indexedOwners = 0,
        recipes = 0,
        indexedRecipes = 0,
        indexedRecipeOwners = 0,
        craftedItems = 0,
        craftedItemRecipes = 0,
    }
    if not db then return stats end

    for _, rec in pairs(db.characters or {}) do
        stats.characters = stats.characters + 1
        if type(rec) == "table" and type(rec.professions) == "table" then
            for _ in pairs(rec.professions) do
                stats.professionEntries = stats.professionEntries + 1
            end
        end
    end

    for _, bucket in pairs(db.professionIndex or {}) do
        stats.indexedProfessions = stats.indexedProfessions + 1
        if type(bucket) == "table" and type(bucket.characters) == "table" then
            for _ in pairs(bucket.characters) do
                stats.indexedOwners = stats.indexedOwners + 1
            end
        end
    end

    for _, byProfession in pairs(db.learnedRecipes or {}) do
        if type(byProfession) == "table" then
            for _, recipeBucket in pairs(byProfession) do
                if type(recipeBucket) == "table" then
                    for _ in pairs(recipeBucket) do
                        stats.recipes = stats.recipes + 1
                    end
                end
            end
        end
    end

    for _, bucket in pairs(db.recipeOwnerIndex or {}) do
        stats.indexedRecipes = stats.indexedRecipes + 1
        if type(bucket) == "table" and type(bucket.owners) == "table" then
            for _, profs in pairs(bucket.owners) do
                stats.indexedRecipeOwners = stats.indexedRecipeOwners + CountTable(profs)
            end
        end
    end

    for _, bucket in pairs(db.craftedItemIndex or {}) do
        stats.craftedItems = stats.craftedItems + 1
        if type(bucket) == "table" and type(bucket.recipes) == "table" then
            for _ in pairs(bucket.recipes) do
                stats.craftedItemRecipes = stats.craftedItemRecipes + 1
            end
        end
    end

    return stats
end

local function SplitCharacterKey(charKey)
    if type(charKey) ~= "string" then return tostring(charKey or "") end
    local name = charKey:match("^(.+)%-.+$")
    return name or charKey
end

local function GetProfessionSkillFromDB(db, charKey, professionID, professionName)
    local rec = db and db.characters and db.characters[charKey]
    if type(rec) ~= "table" or type(rec.professions) ~= "table" then return nil, nil end
    local numericProfessionID = tonumber(professionID)
    for profName, info in pairs(rec.professions) do
        if type(info) == "table" then
            local id = tonumber(info.professionID or info.skillLine)
            if (numericProfessionID and id == numericProfessionID) or (professionName and profName == professionName) then
                return tonumber(info.skillLevel) or 0, tonumber(info.maxSkillLevel) or 0
            end
        end
    end
    return nil, nil
end

local function EnrichOwnerSkill(api, owner)
    if type(owner) ~= "table" then return owner end
    local db = api:GetDB()
    local skillLevel, maxSkillLevel = GetProfessionSkillFromDB(db, owner.characterKey, owner.professionID, owner.profession)
    owner.skillLevel = skillLevel or owner.skillLevel or 0
    owner.maxSkillLevel = maxSkillLevel or owner.maxSkillLevel or 0
    owner.shortName = owner.shortName or SplitCharacterKey(owner.characterKey)
    return owner
end

function API:GetPreferredOwnerFromOwners(owners)
    if type(owners) ~= "table" then return nil end
    local best
    for charKey, profs in pairs(owners) do
        if type(profs) == "table" then
            for _, owner in pairs(profs) do
                if type(owner) == "table" and IsKnownProfessionName(owner.profession) then
                    EnrichOwnerSkill(self, owner)
                    if not best
                        or (tonumber(owner.skillLevel or 0) > tonumber(best.skillLevel or 0))
                        or (tonumber(owner.skillLevel or 0) == tonumber(best.skillLevel or 0) and tostring(owner.characterKey or charKey) < tostring(best.characterKey or "")) then
                        best = owner
                    end
                end
            end
        end
    end
    return best
end

function API:GetSortedOwnersFromOwners(owners)
    local out = {}
    if type(owners) ~= "table" then return out end
    local seen = {}
    for charKey, profs in pairs(owners) do
        if type(profs) == "table" then
            for _, owner in pairs(profs) do
                if type(owner) == "table" and IsKnownProfessionName(owner.profession) then
                    EnrichOwnerSkill(self, owner)
                    local key = tostring(owner.characterKey or charKey) .. ":" .. tostring(owner.professionID or owner.profession or "")
                    if not seen[key] then
                        seen[key] = true
                        table.insert(out, owner)
                    end
                end
            end
        end
    end
    table.sort(out, function(a, b)
        local askill, bskill = tonumber(a.skillLevel or 0), tonumber(b.skillLevel or 0)
        if askill ~= bskill then return askill > bskill end
        local aprof, bprof = tostring(a.profession or ""), tostring(b.profession or "")
        if aprof ~= bprof then return aprof < bprof end
        return tostring(a.characterKey or "") < tostring(b.characterKey or "")
    end)
    return out
end

function API:GetPreferredRecipeOwner(recipeID)
    if self.RebuildRecipeOwnerIndex then self:RebuildRecipeOwnerIndex("preferred recipe owner") end
    local entry = self.GetRecipeIndexEntry and self:GetRecipeIndexEntry(recipeID)
    if type(entry) ~= "table" then return nil, entry end
    return self:GetPreferredOwnerFromOwners(entry.owners), entry
end

function API:GetPreferredCraftedItemOwner(itemID)
    if self.RebuildRecipeOwnerIndex then self:RebuildRecipeOwnerIndex("preferred crafted item owner") end
    if self.RebuildCraftedItemIndex then self:RebuildCraftedItemIndex("preferred crafted item owner") end
    local itemEntry = self.GetCraftedItemEntry and self:GetCraftedItemEntry(itemID)
    if type(itemEntry) ~= "table" or type(itemEntry.recipes) ~= "table" then return nil, itemEntry end
    local bestOwner, bestRecipe
    for recipeID, recipe in pairs(itemEntry.recipes) do
        if type(recipe) == "table" then
            local owner = self:GetPreferredOwnerFromOwners(recipe.owners)
            if owner and (not bestOwner or tonumber(owner.skillLevel or 0) > tonumber(bestOwner.skillLevel or 0)) then
                bestOwner, bestRecipe = owner, recipe
            end
        end
    end
    return bestOwner, bestRecipe, itemEntry
end
