local ADDON_NAME, ns = ...
-- AltProfLib release 1.0.1
local API = ns.API

function API:GetAllCharacters()
    local db = self:GetDB()
    return db and db.characters or {}
end

function API:GetCharacters()
    return self:GetAllCharacters()
end

function API:GetCharacter(characterKey)
    local db = self:GetDB()
    if not db or not db.characters then return nil end
    return db.characters[characterKey or self:GetCharacterKey()]
end

function API:GetProfessions(characterKey)
    local rec = self:GetCharacter(characterKey)
    return rec and rec.professions or {}
end

function API:GetProfessionOwners()
    local db = self:GetDB()
    return db and db.professionOwners or {}
end

function API:GetProfessionIndex()
    local db = self:GetDB()
    return db and db.professionIndex or {}
end

function API:GetProfessionOwnersByID(professionID)
    local index = self:GetProfessionIndex()
    local bucket = index and index[tonumber(professionID)]
    return bucket and bucket.characters or {}
end

function API:GetKnownRecipes(characterKey, professionID)
    local db = self:GetDB()
    if not db or not db.learnedRecipes then return nil end
    if not characterKey then return db.learnedRecipes end
    if not professionID then return db.learnedRecipes[characterKey] end
    return db.learnedRecipes[characterKey] and db.learnedRecipes[characterKey][tonumber(professionID)]
end

function API:CharacterKnowsRecipe(characterKey, professionID, recipeID)
    local bucket = self:GetKnownRecipes(characterKey, professionID)
    return bucket and bucket[tonumber(recipeID)] ~= nil or false
end

function API:GetKnownRecipeCount(characterKey, professionID)
    local recipes = self:GetKnownRecipes(characterKey or self:GetCharacterKey(), professionID)
    if type(recipes) ~= "table" then return 0 end

    local count = 0
    if professionID then
        for _ in pairs(recipes) do count = count + 1 end
        return count
    end

    for _, profBucket in pairs(recipes) do
        if type(profBucket) == "table" then
            for _ in pairs(profBucket) do count = count + 1 end
        end
    end
    return count
end

function API:GetRecipeOwnerIndex()
    local db = self:GetDB()
    return db and db.recipeOwnerIndex or {}
end

function API:GetRecipeOwners(recipeID)
    local index = self:GetRecipeOwnerIndex()
    local bucket = index and index[tonumber(recipeID)]
    return bucket and bucket.owners or {}
end

function API:GetRecipeIndexEntry(recipeID)
    local index = self:GetRecipeOwnerIndex()
    return index and index[tonumber(recipeID)] or nil
end


function API:GetCraftedItemIndex()
    local db = self:GetDB()
    return db and db.craftedItemIndex or {}
end

function API:GetCraftedItemEntry(itemID)
    local index = self:GetCraftedItemIndex()
    return index and index[tonumber(itemID)] or nil
end
