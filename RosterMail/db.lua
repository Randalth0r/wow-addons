local addonName, addon = ...

-- Allowed primary professions only (English names + skillLine IDs for locale-safe matching).
local PRIMARY_PROFESSION_LOOKUP = {
	Skinning = true,
	Herbalism = true,
	Mining = true,
	Leatherworking = true,
	Jewelcrafting = true,
	Tailoring = true,
	Enchanting = true,
	Alchemy = true,
	Engineering = true,
	Blacksmithing = true,
	Inscription = true,
	[393] = true, -- Skinning
	[182] = true, -- Herbalism
	[186] = true, -- Mining
	[165] = true, -- Leatherworking
	[755] = true, -- Jewelcrafting
	[197] = true, -- Tailoring
	[333] = true, -- Enchanting
	[171] = true, -- Alchemy
	[202] = true, -- Engineering
	[164] = true, -- Blacksmithing
	[773] = true, -- Inscription
}

local function ResolveProfessionData(professionIndex)
	if not professionIndex then
		return nil, nil
	end

	local name, icon, _, _, _, _, skillLine = GetProfessionInfo(professionIndex)
	if not icon then
		return nil, nil
	end

	if PRIMARY_PROFESSION_LOOKUP[name] or PRIMARY_PROFESSION_LOOKUP[skillLine] then
		return icon, name
	end

	return nil, nil
end

local eventFrame = CreateFrame("Frame")
eventFrame:Hide()
eventFrame:RegisterEvent("PLAYER_LOGIN")

eventFrame:SetScript("OnEvent", function(self, event)
	if event ~= "PLAYER_LOGIN" then
		return
	end

	if RosterMailDB == nil then
		RosterMailDB = {}
	end

	local characterName = UnitName("player")
	local realmName = GetRealmName()
	if not realmName or realmName == "" then
		realmName = (GetNormalizedRealmName and GetNormalizedRealmName()) or "Unknown"
	end

	local classFilename = UnitClassBase("player")
	local level = UnitLevel("player")
	local faction = UnitFactionGroup("player")

	local prof1, prof2 = GetProfessions()
	local prof1_icon, prof1_name = ResolveProfessionData(prof1)
	local prof2_icon, prof2_name = ResolveProfessionData(prof2)

	if not RosterMailDB[realmName] then
		RosterMailDB[realmName] = {}
	end

	RosterMailDB[realmName][characterName] = {
		name = characterName,
		realm = realmName,
		classFilename = classFilename,
		level = level,
		faction = faction,
		prof1_icon = prof1_icon,
		prof1_name = prof1_name,
		prof2_icon = prof2_icon,
		prof2_name = prof2_name,
	}

	self:UnregisterEvent("PLAYER_LOGIN")
end)
