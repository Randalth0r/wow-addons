local addonName, addon = ...

local PANEL_WIDTH = 225
local TITLE_HEIGHT = 28
local ROW_HEIGHT = 42
local ROW_PADDING = 4
local CONTENT_INSET = 8
local SCROLLBAR_WIDTH = 22
local PROF_ICON_SIZE = 16
local DELETE_ICON_SIZE = 16
local TEXT_MARGIN = 4

local FACTION_TEXTURES = {
	Horde = "Interface\\TargetingFrame\\UI-PVP-Horde",
	Alliance = "Interface\\TargetingFrame\\UI-PVP-Alliance",
	Neutral = "Interface\\TargetingFrame\\UI-PVP-FFA",
}

local sidePanel
local scrollFrame
local scrollChild
local characterButtons = {}

local function GetRowWidth()
	return PANEL_WIDTH - (CONTENT_INSET * 2) - SCROLLBAR_WIDTH
end

local function GetCurrentRealmName()
	local realmName = GetRealmName()
	if not realmName or realmName == "" then
		realmName = (GetNormalizedRealmName and GetNormalizedRealmName()) or "Unknown"
	end
	return realmName
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
	if not classFilename then
		return "Unknown"
	end

	if LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[classFilename] then
		return LOCALIZED_CLASS_NAMES_MALE[classFilename]
	end

	return classFilename
end

local function ResetProfessionFrame(profFrame)
	if not profFrame then
		return
	end

	profFrame.tooltipText = nil
	if profFrame.icon then
		profFrame.icon:SetTexture(nil)
	end
	profFrame:EnableMouse(false)
	if profFrame.SetMouseMotionEnabled then
		profFrame:SetMouseMotionEnabled(false)
	end
	profFrame:Hide()
end

local function ResetCharacterButton(button)
	if not button then
		return
	end

	button.characterName = nil
	button.realmName = nil
	button.dbKey = nil

	if button.nameText then
		button.nameText:SetText("")
	end
	if button.levelClassText then
		button.levelClassText:SetText("")
	end
	if button.factionIcon then
		button.factionIcon:SetTexture(nil)
		button.factionIcon:Hide()
	end
	if button.deleteButton then
		button.deleteButton:Hide()
	end

	ResetProfessionFrame(button.prof1Frame)
	ResetProfessionFrame(button.prof2Frame)

	button:Hide()
end

local function SetFactionIcon(factionIcon, button, faction)
	if not factionIcon or not button then
		return
	end

	factionIcon:ClearAllPoints()
	factionIcon:SetSize(32, 32)
	factionIcon:SetPoint("CENTER", button, "LEFT", 24, 0)

	local texturePath = FACTION_TEXTURES[faction] or FACTION_TEXTURES.Neutral
	factionIcon:SetTexture(texturePath)
	factionIcon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
	factionIcon:Show()
end

local function SetProfessionIconFrame(profFrame, icon, tooltipText)
	if not profFrame then
		return
	end

	if not icon then
		ResetProfessionFrame(profFrame)
		return
	end

	-- Store tooltip text on the frame to avoid loop/closure scope bugs.
	profFrame.tooltipText = tooltipText
	profFrame:SetSize(PROF_ICON_SIZE, PROF_ICON_SIZE)
	profFrame.icon:SetTexture(icon)
	profFrame.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	profFrame:EnableMouse(true)
	if profFrame.SetMouseMotionEnabled then
		profFrame:SetMouseMotionEnabled(true)
	end
	profFrame:Show()
	profFrame:Raise()
end

-- Anchor text right edge to the leftmost visible right-side widget.
local function ApplyDynamicTextAnchors(button)
	local nameText = button.nameText
	local levelClassText = button.levelClassText
	local factionIcon = button.factionIcon
	local prof1Shown = button.prof1Frame and button.prof1Frame:IsShown()
	local prof2Shown = button.prof2Frame and button.prof2Frame:IsShown()

	local rightAnchorFrame = button.deleteButton or button
	local rightAnchorPoint = "LEFT"

	if not button.deleteButton or not button.deleteButton:IsShown() then
		rightAnchorFrame = button
		rightAnchorPoint = "RIGHT"
	end

	if prof1Shown and prof2Shown then
		rightAnchorFrame = button.prof2Frame
		rightAnchorPoint = "LEFT"
	elseif prof2Shown then
		rightAnchorFrame = button.prof2Frame
		rightAnchorPoint = "LEFT"
	elseif prof1Shown then
		rightAnchorFrame = button.prof1Frame
		rightAnchorPoint = "LEFT"
	end

	nameText:ClearAllPoints()
	nameText:SetPoint("TOPLEFT", factionIcon, "TOPRIGHT", 4, -2)
	nameText:SetPoint("RIGHT", rightAnchorFrame, rightAnchorPoint, -TEXT_MARGIN, 0)

	levelClassText:ClearAllPoints()
	levelClassText:SetPoint("BOTTOMLEFT", factionIcon, "BOTTOMRIGHT", 4, 2)
	levelClassText:SetPoint("RIGHT", rightAnchorFrame, rightAnchorPoint, -TEXT_MARGIN, 0)
end

local function HideSidePanel()
	if sidePanel then
		sidePanel:Hide()
	end
end

local function ClearCharacterButtons()
	for index = 1, #characterButtons do
		ResetCharacterButton(characterButtons[index])
	end
end

local function CreateProfessionIconFrame(button, xOffset)
	local profFrame = CreateFrame("Frame", nil, button)
	profFrame:SetSize(PROF_ICON_SIZE, PROF_ICON_SIZE)
	profFrame:SetPoint("RIGHT", button, "RIGHT", xOffset, 0)
	profFrame:SetFrameLevel(button:GetFrameLevel() + 10)

	-- Mouse must be enabled before registering enter/leave scripts.
	profFrame:EnableMouse(true)
	if profFrame.SetMouseMotionEnabled then
		profFrame:SetMouseMotionEnabled(true)
	end
	if profFrame.SetMouseClickEnabled then
		profFrame:SetMouseClickEnabled(false)
	end

	local icon = profFrame:CreateTexture(nil, "ARTWORK")
	icon:SetAllPoints(profFrame)
	profFrame.icon = icon

	profFrame:SetScript("OnEnter", function(self)
		if not self.tooltipText then
			return
		end

		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetText(self.tooltipText)
		GameTooltip:Show()
	end)

	profFrame:SetScript("OnLeave", function(self)
		if GameTooltip:IsOwned(self) then
			GameTooltip:Hide()
		end
	end)

	profFrame:Hide()
	return profFrame
end

local RefreshRosterList

local function CreateDeleteButton(button)
	local deleteButton = CreateFrame("Button", nil, button)
	deleteButton:SetSize(DELETE_ICON_SIZE, DELETE_ICON_SIZE)
	deleteButton:SetPoint("RIGHT", button, "RIGHT", -4, 0)
	deleteButton:SetFrameLevel(button:GetFrameLevel() + 12)
	deleteButton:EnableMouse(true)

	-- Blizzard default barred-circle (group loot Pass).
	deleteButton:SetNormalTexture("Interface\\Buttons\\UI-GroupLoot-Pass-Up")
	deleteButton:SetPushedTexture("Interface\\Buttons\\UI-GroupLoot-Pass-Down")
	deleteButton:SetHighlightTexture("Interface\\Buttons\\UI-GroupLoot-Pass-Highlight", "ADD")

	deleteButton:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetText("Remove from roster")
		GameTooltip:Show()
	end)

	deleteButton:SetScript("OnLeave", function(self)
		if GameTooltip:IsOwned(self) then
			GameTooltip:Hide()
		end
	end)

	deleteButton:SetScript("OnClick", function(self)
		local parent = self:GetParent()
		local realmName = parent and parent.realmName
		local dbKey = parent and parent.dbKey

		if not realmName or not dbKey then
			return
		end

		if RosterMailDB and RosterMailDB[realmName] then
			RosterMailDB[realmName][dbKey] = nil
		end

		RefreshRosterList()
	end)

	deleteButton:Hide()
	return deleteButton
end

local function AcquireCharacterButton(index)
	local button = characterButtons[index]
	if button then
		ResetCharacterButton(button)
		button:SetHeight(ROW_HEIGHT)
		button:SetWidth(GetRowWidth())
		return button
	end

	button = CreateFrame("Button", nil, scrollChild)
	button:SetHeight(ROW_HEIGHT)
	button:SetWidth(GetRowWidth())

	local background = button:CreateTexture(nil, "BACKGROUND")
	background:SetAllPoints()
	background:SetColorTexture(0.12, 0.12, 0.12, 0.85)
	button.background = background

	local highlight = button:CreateTexture(nil, "HIGHLIGHT")
	highlight:SetAllPoints()
	highlight:SetColorTexture(1, 1, 1, 0.12)

	local factionIcon = button:CreateTexture(nil, "ARTWORK")
	factionIcon:ClearAllPoints()
	factionIcon:SetSize(32, 32)
	factionIcon:SetPoint("CENTER", button, "LEFT", 24, 0)
	factionIcon:Hide()
	button.factionIcon = factionIcon

	button.deleteButton = CreateDeleteButton(button)

	-- Profession icons sit left of the delete button.
	local deleteReserve = 4 + DELETE_ICON_SIZE + TEXT_MARGIN
	button.prof1Frame = CreateProfessionIconFrame(button, -(deleteReserve))
	button.prof2Frame = CreateProfessionIconFrame(button, -(deleteReserve + PROF_ICON_SIZE + TEXT_MARGIN))

	local nameText = button:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	nameText:SetJustifyH("LEFT")
	nameText:SetWordWrap(false)
	button.nameText = nameText

	local levelClassText = button:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	levelClassText:SetJustifyH("LEFT")
	levelClassText:SetWordWrap(false)
	button.levelClassText = levelClassText

	button:SetScript("OnEnter", function(self)
		self.background:SetColorTexture(0.22, 0.22, 0.22, 0.95)
	end)

	button:SetScript("OnLeave", function(self)
		self.background:SetColorTexture(0.12, 0.12, 0.12, 0.85)
	end)

	button:SetScript("OnClick", function(self)
		local characterName = self.characterName
		if characterName and SendMailNameEditBox then
			SendMailNameEditBox:SetText(characterName)
			SendMailNameEditBox:SetFocus()
		end
	end)

	characterButtons[index] = button
	ResetCharacterButton(button)
	return button
end

RefreshRosterList = function()
	-- Hide existing rows first to avoid visual leftovers while redrawing.
	for index = 1, #characterButtons do
		characterButtons[index]:Hide()
	end

	if not scrollChild then
		return
	end

	local realmName = GetCurrentRealmName()
	local playerName = UnitName("player")
	local realmCharacters = RosterMailDB and RosterMailDB[realmName]
	local visibleCount = 0
	local rowWidth = GetRowWidth()

	scrollChild:SetWidth(rowWidth)

	if realmCharacters then
		for characterName, data in pairs(realmCharacters) do
			if characterName ~= playerName then
				visibleCount = visibleCount + 1

				local button = AcquireCharacterButton(visibleCount)
				local displayName = data.name or characterName
				local level = data.level or "?"
				local classFilename = data.classFilename
				local classDisplayName = GetClassDisplayName(classFilename)
				local faction = data.faction
				local prof1_icon = data.prof1_icon
				local prof1_name = data.prof1_name
				local prof2_icon = data.prof2_icon
				local prof2_name = data.prof2_name

				button:SetWidth(rowWidth)
				button.characterName = displayName
				button.realmName = realmName
				button.dbKey = characterName

				SetFactionIcon(button.factionIcon, button, faction)
				SetProfessionIconFrame(button.prof1Frame, prof1_icon, prof1_name)
				SetProfessionIconFrame(button.prof2Frame, prof2_icon, prof2_name)

				button.deleteButton:Show()
				button.deleteButton:Raise()

				button.nameText:SetText(GetClassColoredText(displayName, classFilename))
				button.levelClassText:SetText(string.format("Level %s  %s", tostring(level), classDisplayName))
				ApplyDynamicTextAnchors(button)

				button:ClearAllPoints()
				button:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 0, -((visibleCount - 1) * (ROW_HEIGHT + ROW_PADDING)))
				button:SetPoint("TOPRIGHT", scrollChild, "TOPRIGHT", 0, -((visibleCount - 1) * (ROW_HEIGHT + ROW_PADDING)))
				button:Show()
			end
		end
	end

	if visibleCount == 0 then
		visibleCount = 1
		local emptyButton = AcquireCharacterButton(1)
		emptyButton.characterName = nil
		emptyButton.realmName = nil
		emptyButton.dbKey = nil
		emptyButton:SetWidth(rowWidth)

		if emptyButton.deleteButton then
			emptyButton.deleteButton:Hide()
		end

		emptyButton.nameText:ClearAllPoints()
		emptyButton.nameText:SetPoint("TOPLEFT", emptyButton, "TOPLEFT", 8, -6)
		emptyButton.nameText:SetPoint("TOPRIGHT", emptyButton, "TOPRIGHT", -8, -6)
		emptyButton.levelClassText:ClearAllPoints()
		emptyButton.levelClassText:SetPoint("BOTTOMLEFT", emptyButton, "BOTTOMLEFT", 8, 6)
		emptyButton.levelClassText:SetPoint("BOTTOMRIGHT", emptyButton, "BOTTOMRIGHT", -8, 6)
		emptyButton.nameText:SetText("|cffaaaaaaNo alts saved.|r")
		emptyButton.levelClassText:SetText("Log in on other characters to build the roster.")

		emptyButton:ClearAllPoints()
		emptyButton:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 0, 0)
		emptyButton:SetPoint("TOPRIGHT", scrollChild, "TOPRIGHT", 0, 0)
		emptyButton:Show()
	end

	local contentHeight = (visibleCount * ROW_HEIGHT) + (math.max(visibleCount - 1, 0) * ROW_PADDING)
	scrollChild:SetHeight(math.max(contentHeight, 1))
end

local function SyncPanelHeight()
	if not sidePanel or not MailFrame then
		return
	end

	sidePanel:SetHeight(MailFrame:GetHeight())
end

local function CreateSidePanel()
	if sidePanel then
		return sidePanel
	end

	if not MailFrame then
		return nil
	end

	-- Parent to MailFrame so visibility (including ESC close) is inherited.
	sidePanel = CreateFrame("Frame", "RosterMailSidePanel", MailFrame, "BackdropTemplate")
	sidePanel:SetParent(MailFrame)
	sidePanel:SetWidth(PANEL_WIDTH)
	sidePanel:SetFrameStrata(MailFrame:GetFrameStrata())
	sidePanel:SetFrameLevel(MailFrame:GetFrameLevel() + 1)
	sidePanel:SetClampedToScreen(true)
	sidePanel:EnableMouse(true)
	sidePanel:Hide()

	sidePanel:SetBackdrop({
		bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
		edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
		tile = true,
		tileSize = 16,
		edgeSize = 12,
		insets = { left = 3, right = 3, top = 3, bottom = 3 },
	})
	sidePanel:SetBackdropColor(0, 0, 0, 0.95)
	sidePanel:SetBackdropBorderColor(0.6, 0.6, 0.6, 1)

	local title = sidePanel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	title:SetPoint("TOP", 0, -10)
	title:SetText("RosterMail")
	sidePanel.title = title

	scrollFrame = CreateFrame("ScrollFrame", "RosterMailSidePanelScrollFrame", sidePanel, "UIPanelScrollFrameTemplate")
	scrollFrame:SetPoint("TOPLEFT", CONTENT_INSET, -(TITLE_HEIGHT + 4))
	scrollFrame:SetPoint("BOTTOMRIGHT", -(CONTENT_INSET + SCROLLBAR_WIDTH), CONTENT_INSET)

	scrollChild = CreateFrame("Frame", "RosterMailSidePanelScrollChild", scrollFrame)
	scrollChild:SetWidth(GetRowWidth())
	scrollChild:SetHeight(1)
	scrollFrame:SetScrollChild(scrollChild)

	sidePanel:SetScript("OnShow", function()
		SyncPanelHeight()
		RefreshRosterList()
	end)

	return sidePanel
end

local function ShowSidePanel()
	if not MailFrame then
		return
	end

	CreateSidePanel()
	if not sidePanel then
		return
	end

	-- Keep parenting explicit in case the panel was created earlier.
	sidePanel:SetParent(MailFrame)
	sidePanel:SetWidth(PANEL_WIDTH)
	SyncPanelHeight()

	sidePanel:ClearAllPoints()
	sidePanel:SetPoint("TOPLEFT", MailFrame, "TOPRIGHT", 2, 0)
	sidePanel:Show()
	RefreshRosterList()
end

local eventFrame = CreateFrame("Frame")
eventFrame:Hide()
eventFrame:RegisterEvent("MAIL_SHOW")
eventFrame:RegisterEvent("MAIL_CLOSED")

eventFrame:SetScript("OnEvent", function(self, event)
	if event == "MAIL_SHOW" then
		ShowSidePanel()
	elseif event == "MAIL_CLOSED" then
		-- Explicit hide as redundancy for ESC / parent-hide edge cases.
		HideSidePanel()
	end
end)
