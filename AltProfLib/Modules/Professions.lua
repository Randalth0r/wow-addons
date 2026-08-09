local ADDON_NAME, ns = ...
local API = ns.API

local Prof = CreateFrame("Frame")
Prof:RegisterEvent("SKILL_LINES_CHANGED")

local PROFESSION_SLOTS = {
    "profession1",
    "profession2",
    "archaeology",
    "fishing",
    "cooking",
}

local function GetProfessionIndices()
    local prof1, prof2, archaeology, fishing, cooking = GetProfessions()
    return { prof1, prof2, archaeology, fishing, cooking }
end

local function GetProfessionSlotInfo(slotName, index)
    local name, icon, skillLevel, maxSkillLevel, numAbilities, spelloffset, skillLine, skillModifier, specializationIndex, specializationOffset = GetProfessionInfo(index)
    if not name then return nil end

    return {
        slot = slotName,
        name = name,
        icon = icon,
        skillLevel = skillLevel,
        maxSkillLevel = maxSkillLevel,
        numAbilities = numAbilities,
        spelloffset = spelloffset,
        skillLine = skillLine,
        professionID = skillLine,
        skillModifier = skillModifier,
        specializationIndex = specializationIndex,
        specializationOffset = specializationOffset,
        lastSeen = time(),
    }
end

function API:BuildProfessionOwnerKey(professionName)
    if not professionName then return nil end
    return "Midnight " .. professionName
end

function API:ScanProfessions(reason)
    local db = self:GetDB()
    if not db then return 0 end

    local char, charKey = self:GetCharacterRecord()
    if not char then return 0 end

    char.professions = char.professions or {}
    local indices = GetProfessionIndices()
    local count = 0

    for slotIndex, profIndex in ipairs(indices) do
        if profIndex then
            local info = GetProfessionSlotInfo(PROFESSION_SLOTS[slotIndex], profIndex)
            if info and info.name then
                char.professions[info.name] = info

                local ownerKey = self:BuildProfessionOwnerKey(info.name)
                if ownerKey then
                    db.professionOwners[ownerKey] = charKey
                    AltProfSpecTracker = AltProfSpecTracker or {}
                    AltProfSpecTracker[ownerKey] = charKey
                end

                count = count + 1
            end
        end
    end

    char.lastProfessionScan = time()
    if self.RebuildProfessionIndex then
        self:RebuildProfessionIndex(reason or "profession scan")
    end
    self:Log("SCAN_PROFESSIONS", { reason = reason or "manual", count = count })
    self:Debug("profession scan complete", reason or "manual", count)
    return count
end

Prof:SetScript("OnEvent", function(_, event)
    if not API or not API.GetDB or not AltProfLibDB then return end
    if event == "SKILL_LINES_CHANGED" then
        API:ScanProfessions(event)
    end
end)
