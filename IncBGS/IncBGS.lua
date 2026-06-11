-- IncBGS v1.0.0
-- Quick Incoming report bar for Battlegrounds.
-- Original concept inspired by REPorter by AcidWeb.
-- Written for WoW 12.x (12.0.5) by Randalthor.

local ADDON_NAME, INC = ...
_G.IncBGS = INC

local VERSION = "1.0.0"

-- ── Upvalues ───────────────────────────────────────────────────────────────
local pairs          = _G.pairs
local print          = _G.print
local IsInInstance   = _G.IsInInstance
local GetSubZoneText = _G.GetSubZoneText
local CreateFrame    = _G.CreateFrame
local UIParent       = _G.UIParent

-- ── Forward declarations ───────────────────────────────────────────────────
local Bar        = nil
local buttons    = {}
local btnLock    = nil  -- lock/unlock micro-button
local btnLayout  = nil  -- H/V micro-button
local btnDrag    = nil  -- drag anchor micro-button

-- ── Zones without meaningful subzone names ─────────────────────────────────
local ZONES_WITHOUT_SUBZONES = {
    [423]  = true, -- Silvershard Mines
    [417]  = true, -- Temple of Kotmogu
    [623]  = true, -- Twin Peaks
    [1335] = true, -- Comp Stomp
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

-- ── Button definitions (report buttons) ───────────────────────────────────
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

-- ── Lock button helpers ────────────────────────────────────────────────────
local ICON_LOCKED   = "Interface\\Icons\\achievement_quests_completed_06"  -- padlock closed
local ICON_UNLOCKED = "Interface\\Icons\\achievement_quests_completed_07"  -- padlock open

local function UpdateLockButton()
    if not btnLock then return end
    -- Icon stays always "locked" since the bar is always locked by default
    btnLock.icon:SetTexture(ICON_LOCKED)
    btnLock.icon:SetDesaturated(false)
end

-- ── Layout button helpers ──────────────────────────────────────────────────
local function UpdateLayoutButton()
    if not btnLayout then return end
    local horiz = IncBGSSettings and IncBGSSettings.horizontal
    btnLayout:SetText(horiz and "H" or "V")
end

-- ── Bar layout ─────────────────────────────────────────────────────────────
local BUTTON_SIZE    = 32
local BUTTON_PADDING = 3
local MICRO_SIZE     = math.floor(BUTTON_SIZE / 2)  -- 16px
local NUM_REPORT     = #BUTTON_DEFS

local function SetupBarLayout()
    local sv    = IncBGSSettings
    local horiz = sv and sv.horizontal
    local p     = BUTTON_PADDING
    local s     = BUTTON_SIZE
    local m     = MICRO_SIZE

    -- Bar is always compact
    if horiz then
        Bar:SetWidth(NUM_REPORT * (s + p) + m + p)
        Bar:SetHeight(s + p * 2)
    else
        Bar:SetWidth(s + p * 2)
        Bar:SetHeight(NUM_REPORT * (s + p) + p + m + p)
    end

    -- Position report buttons
    local prev = nil
    for i = 1, NUM_REPORT do
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

    -- Position micro buttons: stacked next to CLR (last report button)
    local lastBtn = buttons[NUM_REPORT]
    if horiz then
        -- micro buttons stacked vertically to the right of CLR
        btnLock:ClearAllPoints()
        btnLock:SetPoint("TOPLEFT", lastBtn, "TOPRIGHT", p, 0)
        btnLayout:ClearAllPoints()
        btnLayout:SetPoint("TOPLEFT", btnLock, "BOTTOMLEFT", 0, -p)
    else
        -- micro buttons side by side below CLR
        btnLock:ClearAllPoints()
        btnLock:SetPoint("TOPLEFT", lastBtn, "BOTTOMLEFT", 0, -p)
        btnLayout:ClearAllPoints()
        btnLayout:SetPoint("TOPLEFT", btnLock, "TOPRIGHT", p, 0)
    end

    UpdateLockButton()   -- also calls UpdateDragButton
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

    -- Drag the bar only when SHIFT is held
    Bar:SetScript("OnDragStart", function(self)
        -- drag handled by lock button hold; background drag disabled
    end)
    Bar:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local x, y = self:GetCenter()
        IncBGSSettings.barX = x
        IncBGSSettings.barY = y
    end)

    -- ── Report buttons ────────────────────────────────────────────────────
    for i = 1, NUM_REPORT do
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

    -- ── Lock micro-button ─────────────────────────────────────────────────
    btnLock = CreateFrame("Button", "IncBGSBarLock", Bar, "UIPanelButtonTemplate")
    btnLock:SetSize(MICRO_SIZE, MICRO_SIZE)

    -- Replace text with an icon texture
    local lockIcon = btnLock:CreateTexture(nil, "ARTWORK")
    lockIcon:SetPoint("CENTER", btnLock, "CENTER", 0, 0)
    lockIcon:SetSize(MICRO_SIZE - 4, MICRO_SIZE - 4)
    lockIcon:SetTexture(ICON_LOCKED)
    btnLock.icon = lockIcon

    -- Remove default button text
    local fs = btnLock:GetFontString()
    if fs then fs:SetText("") end

    -- Hold the lock button and drag to move the bar
    btnLock:RegisterForDrag("LeftButton")
    btnLock:SetScript("OnDragStart", function()
        Bar:StartMoving()
    end)
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

    -- ── Layout micro-button ───────────────────────────────────────────────
    btnLayout = CreateFrame("Button", "IncBGSBarLayout", Bar, "UIPanelButtonTemplate")
    btnLayout:SetSize(MICRO_SIZE, MICRO_SIZE)
    btnLayout:SetText("H")
    -- Make font smaller to fit in the micro button
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
    -- ── Drag anchor ───────────────────────────────────────────────────────
    btnDrag = CreateFrame("Button", "IncBGSBarDrag", Bar)
    btnDrag:SetSize(BUTTON_SIZE, MICRO_SIZE)
    btnDrag:EnableMouse(true)
    btnDrag:RegisterForDrag("LeftButton")
    btnDrag:SetMovable(false)

    -- Background texture: a subtle highlight stripe
    local dragTex = btnDrag:CreateTexture(nil, "BACKGROUND")
    dragTex:SetAllPoints()
    dragTex:SetColorTexture(1, 1, 1, 0.15)

    -- Move icon (four arrows) centered
    local dragIcon = btnDrag:CreateTexture(nil, "ARTWORK")
    dragIcon:SetPoint("CENTER", btnDrag, "CENTER", 0, 0)
    dragIcon:SetSize(MICRO_SIZE - 2, MICRO_SIZE - 2)
    dragIcon:SetTexture("Interface\\Icons\\ability_hunter_readiness")
    dragIcon:SetAlpha(0.7)

    -- Highlight on hover
    local dragHL = btnDrag:CreateTexture(nil, "HIGHLIGHT")
    dragHL:SetAllPoints()
    dragHL:SetColorTexture(1, 1, 1, 0.25)

    btnDrag:SetScript("OnDragStart", function()
        Bar:StartMoving()
    end)
    btnDrag:SetScript("OnDragStop", function()
        Bar:StopMovingOrSizing()
        local x, y = Bar:GetCenter()
        IncBGSSettings.barX = x
        IncBGSSettings.barY = y
    end)
    btnDrag:SetScript("OnEnter", function(self)
        _G.GameTooltip:SetOwner(self, "ANCHOR_TOP")
        _G.GameTooltip:SetText("|cFFFFD700Drag|r to move the bar", 1, 1, 1, 1, true)
        _G.GameTooltip:Show()
    end)
    btnDrag:SetScript("OnLeave", function() _G.GameTooltip:Hide() end)
    -- visibility managed by UpdateDragButton() called from UpdateLockButton()
end

-- ── Saved-variable helpers ─────────────────────────────────────────────────
local function InitSavedVars()
    if not IncBGSSettings then IncBGSSettings = {} end
    for k, v in pairs(DEFAULTS) do
        if IncBGSSettings[k] == nil then
            if type(v) == "table" then
                IncBGSSettings[k] = {}
                for k2, v2 in pairs(v) do
                    IncBGSSettings[k][k2] = v2
                end
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
        if Bar:IsShown() then Bar:Hide() else Bar:Show() end
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
        sv.minimap.hide = not sv.minimap.hide
        local LDBIcon = _G.LibStub and _G.LibStub("LibDBIcon-1.0", true)
        if LDBIcon then
            if sv.minimap.hide then LDBIcon:Hide("IncBGS") else LDBIcon:Show("IncBGS") end
        end
        print("|cFF74D06C[IncBGS]|r Minimap icon " .. (sv.minimap.hide and "hidden" or "shown") .. ".")
    else
        print("|cFF74D06C[IncBGS]|r v" .. VERSION)
        print("  |cFFFFD700/incbgs|r          — show/hide bar")
        print("  |cFFFFD700/incbgs horiz|r    — toggle horizontal/vertical")
        print("  |cFFFFD700/incbgs raidwarn|r — toggle raid warning echo")
        print("  |cFFFFD700/incbgs reset|r    — move bar to screen center")
        print("  |cFFFFD700/incbgs minimap|r  — show/hide minimap icon")
    end
end

-- ── Minimap button (uses LibDBIcon only if already loaded by another addon) ──
local function SetupMinimapButton()
    -- We never load LibDBIcon ourselves — we only use it if already in memory
    -- from another addon (e.g. One For All, DBM, WeakAuras, etc.)
    local LDBIcon = _G.LibStub and _G.LibStub("LibDBIcon-1.0", true)
    if not LDBIcon then return end  -- silently skip if not available

    local LDB = _G.LibStub("LibDataBroker-1.1", true)
    if not LDB then return end

    local dataobj = LDB:NewDataObject("IncBGS", {
        type  = "launcher",
        icon  = "Interface\\Icons\\ability_warrior_battleshout",
        label = "IncBGS",
    })
    if not dataobj then return end

    LDBIcon:Register("IncBGS", dataobj, IncBGSSettings.minimap)

    -- Force icon texture directly on the button after registration
    -- LibDBIcon always names buttons "LibDBIcon10_<name>"
    local mmBtn = _G["LibDBIcon10_IncBGS"]
    if mmBtn and mmBtn.icon then
        mmBtn.icon:SetTexture("Interface\\Icons\\ability_warrior_battleshout")
    end

    dataobj.OnClick = function(self, btn)
        if btn == "LeftButton" then
            if Bar:IsShown() then Bar:Hide() else Bar:Show() end
        end
    end
    dataobj.OnEnter = function(self)
        _G.GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        _G.GameTooltip:SetText("|cFF74D06CInc|rBGS  v" .. VERSION, 1, 1, 1)
        _G.GameTooltip:AddLine("Left click: show/hide bar", 0.8, 0.8, 0.8)
        _G.GameTooltip:AddLine("Drag: reposition icon", 0.8, 0.8, 0.8)
        _G.GameTooltip:Show()
    end
    dataobj.OnLeave = function()
        _G.GameTooltip:Hide()
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
        if instanceType == "pvp" then
            Bar:Show()
            RefreshMacros()
        else
            Bar:Hide()
        end
    end
end)
