-- IncBGS v1.0.6
-- Quick Incoming report bar for Battlegrounds.
-- Original concept inspired by REPorter by AcidWeb.
-- Written for WoW 12.x (12.0.5) by Randalthor.

local ADDON_NAME, INC = ...
_G.IncBGS = INC

local VERSION = "1.0.6"

-- ── Upvalues ───────────────────────────────────────────────────────────────
local pairs          = _G.pairs
local print          = _G.print
local IsInInstance   = _G.IsInInstance
local GetSubZoneText = _G.GetSubZoneText
local CreateFrame    = _G.CreateFrame
local UIParent       = _G.UIParent

-- ── Forward declarations ───────────────────────────────────────────────────
local Bar     = nil
local buttons = {}
local btnLock = nil
local btnLayout = nil

-- ── Zones without meaningful subzone names ─────────────────────────────────
local ZONES_WITHOUT_SUBZONES = {
    [423]  = true,
    [417]  = true,
    [623]  = true,
    [1335] = true,
}

-- ── Saved-variable defaults ────────────────────────────────────────────────
local DEFAULTS = {
    barX       = nil,
    barY       = nil,
    horizontal = true,
    raidWarn   = false,
    alpha      = 0.9,
    minimap    = { hide = false, minimapPos = 45 },
}

-- ── Button definitions ─────────────────────────────────────────────────────
local BUTTON_DEFS = {
    { label = "1",   tooltip = "Incoming 1",   needsLoc = false,
      msg = function(loc) return "INCOMING 1"  .. (loc ~= "" and " - "..loc or "") end },
    { label = "2",   tooltip = "Incoming 2",   needsLoc = false,
      msg = function(loc) return "INCOMING 2"  .. (loc ~= "" and " - "..loc or "") end },
    { label = "3",   tooltip = "Incoming 3",   needsLoc = false,
      msg = function(loc) return "INCOMING 3"  .. (loc ~= "" and " - "..loc or "") end },
    { label = "4",   tooltip = "Incoming 4",   needsLoc = false,
      msg = function(loc) return "INCOMING 4"  .. (loc ~= "" and " - "..loc or "") end },
    { label = "5",   tooltip = "Incoming 5",   needsLoc = false,
      msg = function(loc) return "INCOMING 5"  .. (loc ~= "" and " - "..loc or "") end },
    { label = "5+",  tooltip = "Incoming 5+",  needsLoc = false,
      msg = function(loc) return "INCOMING 5+" .. (loc ~= "" and " - "..loc or "") end },
    { label = "HLP", tooltip = "Help! (need assistance at my location)", needsLoc = true,
      msg = function(loc) return "HELP - " .. loc end },
    { label = "CLR", tooltip = "Clear (location is safe)", needsLoc = true,
      msg = function(loc) return "CLEAR - " .. loc end },
}

-- ── Helpers ────────────────────────────────────────────────────────────────
local function GetLocationName()
    local _, instanceType = IsInInstance()
    if instanceType ~= "pvp" then return nil end
    local mapID = _G.C_Map.GetBestMapForUnit("player")
    if mapID and ZONES_WITHOUT_SUBZONES[mapID] then return "" end
    return GetSubZoneText() or ""
end

local function BuildMacroBody(defIndex, loc, raidWarn)
    local def = BUTTON_DEFS[defIndex]
    if def.needsLoc and (not loc or loc == "") then
        return "/run print('|cFF74D06C[IncBGS]|r No location name here.')"
    end
    local txt  = def.msg(loc or "")
    local body = "/i " .. txt
    if raidWarn then body = body .. "\n/rw " .. txt end
    return body
end

local function RefreshMacros()
    local loc      = GetLocationName()
    local raidWarn = IncBGSSettings and IncBGSSettings.raidWarn
    for i = 1, #BUTTON_DEFS do
        if buttons[i] then
            buttons[i]:SetAttribute("macrotext", BuildMacroBody(i, loc, raidWarn))
        end
    end
end

-- ── Safe toggle (checks combat lockdown) ───────────────────────────────────
-- Defined early so it can be referenced by minimap and slash commands
local function SafeToggleBar()
    if InCombatLockdown() then
        print("|cFF74D06C[IncBGS]|r Cannot show/hide bar during combat.")
        return
    end
    if Bar:IsShown() then
        Bar:Hide()
    else
        Bar:Show()
    end
end

-- ── Lock button update ─────────────────────────────────────────────────────
local ICON_LOCKED   = "Interface\\Icons\\achievement_quests_completed_06"
local ICON_UNLOCKED = "Interface\\Icons\\achievement_quests_completed_07"

local function UpdateLockButton()
    -- Lock button is now just a drag handle — icon stays locked always
    if not btnLock then return end
    btnLock.icon:SetTexture(ICON_LOCKED)
    btnLock.icon:SetDesaturated(false)
end

local function UpdateLayoutButton()
    if not btnLayout then return end
    local horiz = IncBGSSettings and IncBGSSettings.horizontal
    btnLayout:SetText(horiz and "H" or "V")
end

-- ── Bar layout ─────────────────────────────────────────────────────────────
local BUTTON_SIZE    = 32
local BUTTON_PADDING = 3
local MICRO_SIZE     = math.floor(32 / 2)
local NUM_BUTTONS    = #BUTTON_DEFS

local function SetupBarLayout()
    local horiz = IncBGSSettings and IncBGSSettings.horizontal
    local p     = BUTTON_PADDING
    local s     = BUTTON_SIZE
    local m     = MICRO_SIZE

    if horiz then
        Bar:SetWidth(NUM_BUTTONS * (s + p) + m + p)
        Bar:SetHeight(s + p * 2)
    else
        Bar:SetWidth(s + p * 2)
        Bar:SetHeight(NUM_BUTTONS * (s + p) + p + m + p)
    end

    local prev = nil
    for i = 1, NUM_BUTTONS do
        buttons[i]:ClearAllPoints()
        if not prev then
            buttons[i]:SetPoint("TOPLEFT", Bar, "TOPLEFT", p, -p)
        elseif horiz then
            buttons[i]:SetPoint("TOPLEFT", prev, "TOPRIGHT", p, 0)
        else
            buttons[i]:SetPoint("TOPLEFT", prev, "BOTTOMLEFT", 0, -p)
        end
        prev = buttons[i]
    end

    local lastBtn = buttons[NUM_BUTTONS]
    if horiz then
        btnLock:ClearAllPoints()
        btnLock:SetPoint("TOPLEFT", lastBtn, "TOPRIGHT", p, 0)
        btnLayout:ClearAllPoints()
        btnLayout:SetPoint("TOPLEFT", btnLock, "BOTTOMLEFT", 0, -p)
    else
        btnLock:ClearAllPoints()
        btnLock:SetPoint("TOPLEFT", lastBtn, "BOTTOMLEFT", 0, -p)
        btnLayout:ClearAllPoints()
        btnLayout:SetPoint("TOPLEFT", btnLock, "TOPRIGHT", p, 0)
    end

    UpdateLockButton()
    UpdateLayoutButton()
end

local function CreateBar()
    Bar = CreateFrame("Frame", "IncBGSBar", UIParent, "BackdropTemplate")
    Bar:SetFrameStrata("MEDIUM")
    Bar:SetMovable(true)
    Bar:SetClampedToScreen(true)
    Bar:EnableMouse(true)
    Bar:RegisterForDrag("LeftButton")
    Bar:SetBackdrop({
        bgFile   = "Interface\\TutorialFrame\\TutorialFrameBackground",
        edgeFile = "Interface\\FriendsFrame\\UI-Toast-Border",
        tile     = true, tileSize = 32, edgeSize = 12,
        insets   = { left = 5, right = 5, top = 5, bottom = 5 },
    })
    Bar:SetBackdropColor(0, 0, 0, 0.6)
    Bar:SetBackdropBorderColor(0.6, 0.6, 0.6, 1)
    Bar:Hide()

    Bar:SetScript("OnDragStart", function(self)
        -- drag handled by lock button hold
    end)
    Bar:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local x, y = self:GetCenter()
        IncBGSSettings.barX = x
        IncBGSSettings.barY = y
    end)

    for i = 1, NUM_BUTTONS do
        local def = BUTTON_DEFS[i]
        local btn = CreateFrame("Button", "IncBGSBar_B" .. i, Bar,
                        "SecureActionButtonTemplate,UIPanelButtonTemplate")
        btn:SetSize(BUTTON_SIZE, BUTTON_SIZE)
        btn:SetAttribute("type", "macro")
        btn:SetAttribute("macrotext", "")
        btn:SetText(def.label)
        btn:RegisterForClicks("AnyDown")
        btn:SetScript("OnEnter", function(self)
            _G.GameTooltip:SetOwner(self, "ANCHOR_TOP")
            _G.GameTooltip:SetText("|cFF74D06C" .. def.label .. "|r  " .. def.tooltip, 1, 1, 1, 1, true)
            _G.GameTooltip:Show()
        end)
        btn:SetScript("OnLeave", function() _G.GameTooltip:Hide() end)
        buttons[i] = btn
    end

    -- Lock button (hold to drag)
    btnLock = CreateFrame("Button", "IncBGSBarLock", Bar, "UIPanelButtonTemplate")
    btnLock:SetSize(MICRO_SIZE, MICRO_SIZE)
    local lockIcon = btnLock:CreateTexture(nil, "ARTWORK")
    lockIcon:SetPoint("CENTER", btnLock, "CENTER", 0, 0)
    lockIcon:SetSize(MICRO_SIZE - 4, MICRO_SIZE - 4)
    lockIcon:SetTexture(ICON_LOCKED)
    btnLock.icon = lockIcon
    local fs = btnLock:GetFontString()
    if fs then fs:SetText("") end
    btnLock:RegisterForDrag("LeftButton")
    btnLock:SetScript("OnDragStart", function() Bar:StartMoving() end)
    btnLock:SetScript("OnDragStop", function()
        Bar:StopMovingOrSizing()
        local x, y = Bar:GetCenter()
        IncBGSSettings.barX = x
        IncBGSSettings.barY = y
    end)
    btnLock:SetScript("OnEnter", function(self)
        _G.GameTooltip:SetOwner(self, "ANCHOR_TOP")
        _G.GameTooltip:SetText("|cFFFFD700Hold & drag|r to move the bar", 1, 1, 1, 1, true)
        _G.GameTooltip:Show()
    end)
    btnLock:SetScript("OnLeave", function() _G.GameTooltip:Hide() end)

    -- Layout button
    btnLayout = CreateFrame("Button", "IncBGSBarLayout", Bar, "UIPanelButtonTemplate")
    btnLayout:SetSize(MICRO_SIZE, MICRO_SIZE)
    btnLayout:SetText("H")
    btnLayout:GetFontString():SetFont("Fonts\\FRIZQT__.TTF", 9, "OUTLINE")
    btnLayout:SetScript("OnClick", function()
        local sv = IncBGSSettings
        sv.horizontal = not sv.horizontal
        SetupBarLayout()
        print("|cFF74D06C[IncBGS]|r Bar is now " .. (sv.horizontal and "horizontal" or "vertical") .. ".")
    end)
    btnLayout:SetScript("OnEnter", function(self)
        _G.GameTooltip:SetOwner(self, "ANCHOR_TOP")
        local horiz = IncBGSSettings and IncBGSSettings.horizontal
        _G.GameTooltip:SetText("Layout: " .. (horiz and "|cFFFFD700Horizontal|r" or "|cFF74D06CVertical|r"), 1, 1, 1, 1, true)
        _G.GameTooltip:AddLine("Click to toggle H/V", 0.8, 0.8, 0.8)
        _G.GameTooltip:Show()
    end)
    btnLayout:SetScript("OnLeave", function() _G.GameTooltip:Hide() end)
end

-- ── Minimap button ─────────────────────────────────────────────────────────
local function SetupMinimapButton()
    local LDB     = _G.LibStub and _G.LibStub("LibDataBroker-1.1", true)
    local LDBIcon = _G.LibStub and _G.LibStub("LibDBIcon-1.0", true)
    if not LDB or not LDBIcon then return end

    local dataobj = LDB:NewDataObject("IncBGS", {
        type    = "launcher",
        icon    = "Interface\\Icons\\ability_warrior_battleshout",
        label   = "IncBGS",
        OnClick = function(self, btn)
            if btn == "LeftButton" then
                SafeToggleBar()
            end
        end,
        OnEnter = function(self)
            _G.GameTooltip:SetOwner(self, "ANCHOR_LEFT")
            _G.GameTooltip:SetText("|cFF74D06CInc|rBGS  v" .. VERSION, 1, 1, 1)
            _G.GameTooltip:AddLine("Left click: show/hide bar", 0.8, 0.8, 0.8)
            _G.GameTooltip:AddLine("Drag: reposition icon", 0.8, 0.8, 0.8)
            _G.GameTooltip:Show()
        end,
        OnLeave = function() _G.GameTooltip:Hide() end,
    })
    if not dataobj then return end

    LDBIcon:Register("IncBGS", dataobj, IncBGSSettings.minimap)

    local mmBtn = _G["LibDBIcon10_IncBGS"]
    if mmBtn and mmBtn.icon then
        mmBtn.icon:SetTexture("Interface\\Icons\\ability_warrior_battleshout")
    end
end

-- ── Saved-variable helpers ─────────────────────────────────────────────────
local function InitSavedVars()
    if not IncBGSSettings then IncBGSSettings = {} end
    for k, v in pairs(DEFAULTS) do
        if IncBGSSettings[k] == nil then
            if type(v) == "table" then
                IncBGSSettings[k] = {}
                for k2, v2 in pairs(v) do IncBGSSettings[k][k2] = v2 end
            else
                IncBGSSettings[k] = v
            end
        end
    end
end

local function RestorePosition()
    Bar:ClearAllPoints()
    if IncBGSSettings.barX and IncBGSSettings.barY then
        Bar:SetPoint("CENTER", UIParent, "BOTTOMLEFT",
            IncBGSSettings.barX, IncBGSSettings.barY)
    else
        Bar:SetPoint("CENTER", UIParent, "CENTER")
    end
end

-- ── Slash commands ─────────────────────────────────────────────────────────
_G.SLASH_INCBGS1 = "/incbgs"
_G.SlashCmdList["INCBGS"] = function(msg)
    msg = msg:lower():gsub("^%s+",""):gsub("%s+$","")
    local sv = IncBGSSettings
    if msg == "" then
        SafeToggleBar()
    elseif msg == "horiz" then
        sv.horizontal = not sv.horizontal
        SetupBarLayout()
        print("|cFF74D06C[IncBGS]|r Bar is now " .. (sv.horizontal and "horizontal" or "vertical") .. ".")
    elseif msg == "raidwarn" then
        sv.raidWarn = not sv.raidWarn
        RefreshMacros()
        print("|cFF74D06C[IncBGS]|r Raid warning echo " .. (sv.raidWarn and "ON" or "OFF") .. ".")
    elseif msg == "reset" then
        sv.barX, sv.barY = nil, nil
        RestorePosition()
        print("|cFF74D06C[IncBGS]|r Bar position reset.")
    elseif msg == "minimap" then
        local LDBIcon = _G.LibStub and _G.LibStub("LibDBIcon-1.0", true)
        if LDBIcon then
            sv.minimap.hide = not sv.minimap.hide
            if sv.minimap.hide then
                LDBIcon:Hide("IncBGS")
                print("|cFF74D06C[IncBGS]|r Minimap icon hidden.")
            else
                LDBIcon:Show("IncBGS")
                print("|cFF74D06C[IncBGS]|r Minimap icon shown.")
            end
        end
    elseif msg == "version" then
        print("|cFF74D06C[IncBGS]|r Version " .. VERSION)
    else
        print("|cFF74D06C[IncBGS]|r v" .. VERSION)
        print("  |cFFFFD700/incbgs|r          — show/hide bar")
        print("  |cFFFFD700/incbgs horiz|r    — toggle horizontal/vertical")
        print("  |cFFFFD700/incbgs raidwarn|r — toggle raid warning echo")
        print("  |cFFFFD700/incbgs minimap|r  — show/hide minimap icon")
        print("  |cFFFFD700/incbgs reset|r    — move bar to screen center")
    end
end

-- ── Bootstrap ─────────────────────────────────────────────────────────────
CreateBar()

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
eventFrame:RegisterEvent("ZONE_CHANGED")

eventFrame:SetScript("OnEvent", function(_, event, arg1)
    if event == "ADDON_LOADED" and arg1 == ADDON_NAME then
        InitSavedVars()
        RestorePosition()
        SetupBarLayout()
        Bar:SetAlpha(IncBGSSettings.alpha)
        SetupMinimapButton()
        print("|cFF74D06C[IncBGS]|r v" .. VERSION .. " loaded. Type |cFFFFD700/incbgs help|r for commands.")

    elseif event == "PLAYER_ENTERING_WORLD"
        or event == "ZONE_CHANGED_NEW_AREA"
        or event == "ZONE_CHANGED" then
        local _, instanceType = IsInInstance()
        local inBG = (instanceType == "pvp")
        if inBG then RefreshMacros() end
        -- Defer visibility change until out of combat
        local function applyVisibility()
            if InCombatLockdown() then
                C_Timer.After(1, applyVisibility)
            else
                if inBG then Bar:Show() else Bar:Hide() end
            end
        end
        applyVisibility()
    end
end)
