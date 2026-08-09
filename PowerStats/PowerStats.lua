--=====================================================================
-- PowerStats 1.0.1  (text only)
-- Up to 6 stats shown as text. Two layouts: single row or one-per-row.
-- Colored stat names, effective percentage value.
-- Static: values are held in combat (Blizzard makes combat stats secret
-- in 12.0), so the panel reads the same in and out of combat.
--=====================================================================

local ADDON = "PowerStats"

local PAD, ROW_H, CELLW = 8, 15, 130
local VPAD, WIDTH_TRIM = 4, 5
local HEADER_H, GEARW = 26, 18
local LOCKW = 28              -- lock icon larger than the gear
local MAX_SHOW = 6
local BASE_FONT = 11
local FONT_MIN, FONT_MAX = 8, 20
local FONT_PATH = "Fonts\\FRIZQT__.TTF"

--------------------------------------------------------------------
-- Defaults / SavedVariables
--------------------------------------------------------------------
local DEFAULTS = {
    point  = "CENTER", x = 0, y = 0,
    scale  = 1.0,
    locked = false,
    layout = "column",   -- "column" (one per row) | "row" (single row)
    background = true,
    fontSize = BASE_FONT,
    stats  = { haste = true, crit = true, mastery = true, versd = true },
    colors = {},
}
local db

local function Metrics()
    local fs = tonumber(db and db.fontSize) or BASE_FONT
    if fs < FONT_MIN then fs = FONT_MIN end
    if fs > FONT_MAX then fs = FONT_MAX end
    local k = fs / BASE_FONT
    return {
        fontSize = fs,
        rowH = math.max(12, math.floor(ROW_H * k + 0.5)),
        cellW = math.max(100, math.floor(CELLW * k + 0.5)),
        headerH = math.max(20, math.floor(HEADER_H * k + 0.5)),
        pad = math.max(6, math.floor(PAD * k + 0.5)),
        vpad = math.max(3, math.floor(VPAD * k + 0.5)),
        widthTrim = WIDTH_TRIM,
    }
end

--------------------------------------------------------------------
-- Secret-safe getters (12.0 Secret Values)
--------------------------------------------------------------------
local function numOK(x)
    if (issecretvalue and issecretvalue(x)) or type(x) ~= "number" then return nil end
    return x
end
local function sumOK(...)
    local total, any = 0, false
    for i = 1, select("#", ...) do
        local v = numOK((select(i, ...)))
        if v then total = total + v; any = true end
    end
    if not any then return nil end
    return total
end

local function StatVal(i) local _, eff = UnitStat("player", i); return numOK(eff) end
local function SafeSpellCrit()
    if GetSpellCritChance then
        local ok, v = pcall(GetSpellCritChance)
        if ok then local n = numOK(v); if n then return n end end
        local best = 0
        for s = 2, 7 do local o, x = pcall(GetSpellCritChance, s); if o then local n = numOK(x); if n and n > best then best = n end end end
        return best
    end
    return numOK(GetCritChance())
end
local function VersDone()
    return sumOK(GetCombatRatingBonus(CR_VERSATILITY_DAMAGE_DONE),
                 GetVersatilityBonus and GetVersatilityBonus(CR_VERSATILITY_DAMAGE_DONE) or nil)
end
local function VersTaken()
    return sumOK(GetCombatRatingBonus(CR_VERSATILITY_DAMAGE_TAKEN),
                 GetVersatilityBonus and GetVersatilityBonus(CR_VERSATILITY_DAMAGE_TAKEN) or nil)
end
local function PctPreferred(fnName, cr)
    return function()
        local fn = _G[fnName]
        if type(fn) == "function" then local ok, v = pcall(fn); if ok then local n = numOK(v); if n then return n end end end
        return numOK(GetCombatRatingBonus(cr))
    end
end
local function MoveSpeedPct()
    -- Match Movement Speed: while skyriding/gliding, GetUnitSpeed stays at 0 —
    -- use C_PlayerInfo.GetGlidingInfo() instead. Otherwise current GetUnitSpeed.
    local base = (BASE_MOVEMENT_SPEED and numOK(BASE_MOVEMENT_SPEED)) or 7
    local yards
    if C_PlayerInfo and C_PlayerInfo.GetGlidingInfo then
        local ok, isGliding, _, forwardSpeed = pcall(C_PlayerInfo.GetGlidingInfo)
        if ok and isGliding then
            yards = numOK(forwardSpeed)
        end
    end
    if yards == nil and GetUnitSpeed then
        local unit = "player"
        if UnitInVehicle and UnitInVehicle("player") then unit = "vehicle" end
        local ok, current = pcall(GetUnitSpeed, unit)
        if ok then yards = numOK(current) end
    end
    if yards == nil then return nil end
    return (yards / base) * 100
end
local function ArmorVal() local _, eff = UnitArmor("player"); return numOK(eff) end
local function APVal() local b,p,n = UnitAttackPower("player"); return sumOK(b,p,n) end
local function RAPVal() local b,p,n = UnitRangedAttackPower("player"); return sumOK(b,p,n) end
local function SpellPowerVal()
    if not GetSpellBonusDamage then return nil end
    local best = 0
    for s = 2, 7 do local ok, v = pcall(GetSpellBonusDamage, s); if ok then local n = numOK(v); if n and n > best then best = n end end end
    return best
end
local function SafeChance(fn)
    return function()
        if type(fn) ~= "function" then return nil end
        local ok, v = pcall(fn)
        return ok and numOK(v) or nil
    end
end

--------------------------------------------------------------------
-- Stat registry
--------------------------------------------------------------------
local REGISTRY = {
    { key="str",    name="Str",     cat="primary",   unit="num", r=0.90,g=0.35,b=0.35, get=function() return StatVal(1) end },
    { key="agi",    name="Agi",     cat="primary",   unit="num", r=0.45,g=0.90,b=0.45, get=function() return StatVal(2) end },
    { key="sta",    name="Sta",     cat="primary",   unit="num", r=0.95,g=0.65,b=0.30, get=function() return StatVal(3) end },
    { key="int",    name="Int",     cat="primary",   unit="num", r=0.40,g=0.70,b=1.00, get=function() return StatVal(4) end },

    { key="haste",  name="Haste",   cat="secondary", unit="pct", r=0.30,g=1.00,b=0.35, get=function() return numOK(GetHaste()) end },
    { key="crit",   name="Crit",    cat="secondary", unit="pct", r=1.00,g=0.82,b=0.20, get=function() return numOK(GetCritChance()) end },
    { key="spcrit", name="SpCrit",  cat="secondary", unit="pct", r=1.00,g=0.92,b=0.45, get=SafeSpellCrit },
    { key="mastery",name="Mastery", cat="secondary", unit="pct", r=0.78,g=0.45,b=1.00, get=function() return numOK(GetMasteryEffect()) end },
    { key="versd",  name="Vers",    cat="secondary", unit="pct", r=0.35,g=0.65,b=1.00, get=VersDone },
    { key="verst",  name="VersDR",  cat="secondary", unit="pct", r=0.30,g=0.80,b=0.85, get=VersTaken },

    { key="leech",  name="Leech",   cat="tertiary",  unit="pct", r=0.90,g=0.30,b=0.55, get=PctPreferred("GetLifesteal", CR_LIFESTEAL) },
    { key="avoid",  name="Avoid",   cat="tertiary",  unit="pct", r=0.60,g=0.70,b=0.90, get=PctPreferred("GetAvoidance", CR_AVOIDANCE) },
    { key="speed",  name="Speed",   cat="tertiary",  unit="pct", r=0.65,g=1.00,b=0.55, get=PctPreferred("GetSpeed", CR_SPEED) },
    { key="move",   name="Move",    cat="tertiary",  unit="pct", r=0.85,g=1.00,b=0.40, get=MoveSpeedPct },

    { key="dodge",  name="Dodge",   cat="defensive", unit="pct", r=0.55,g=0.85,b=0.70, get=SafeChance(GetDodgeChance) },
    { key="parry",  name="Parry",   cat="defensive", unit="pct", r=0.70,g=0.75,b=0.55, get=SafeChance(GetParryChance) },
    { key="block",  name="Block",   cat="defensive", unit="pct", r=0.75,g=0.60,b=0.45, get=SafeChance(GetBlockChance) },
    { key="armor",  name="Armor",   cat="defensive", unit="num", r=0.72,g=0.60,b=0.42, get=ArmorVal },

    { key="ap",     name="AP",      cat="power",     unit="num", r=0.95,g=0.45,b=0.30, get=APVal },
    { key="rap",    name="RAP",     cat="power",     unit="num", r=0.95,g=0.60,b=0.35, get=RAPVal },
    { key="sp",     name="SpPow",   cat="power",     unit="num", r=0.45,g=0.60,b=1.00, get=SpellPowerVal },
    { key="hp",     name="HP",      cat="power",     unit="num", r=0.50,g=0.90,b=0.50, get=function() return numOK(UnitHealthMax("player")) end },
}
local REG_BY_KEY = {}
for _, s in ipairs(REGISTRY) do REG_BY_KEY[s.key] = s end

local CATS = {
    { id="primary",   label="Primary" },
    { id="secondary", label="Secondary" },
    { id="tertiary",  label="Tertiary / minor" },
    { id="defensive", label="Defensive" },
    { id="power",     label="Power / vitals" },
}

--------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------
local function GetColor(s)
    local c = db.colors[s.key]
    if c then return c.r, c.g, c.b end
    return s.r, s.g, s.b
end
local function RGBHex(r, g, b)
    return string.format("%02x%02x%02x", math.floor(r*255+0.5), math.floor(g*255+0.5), math.floor(b*255+0.5))
end
local function FormatVal(s, v)
    if s.unit == "pct" then return string.format("%.2f%%", v) end
    local n = math.floor(v + 0.5)
    return BreakUpLargeNumbers and BreakUpLargeNumbers(n) or tostring(n)
end
local function CountTrue(t) local n=0 for _,v in pairs(t) do if v then n=n+1 end end return n end
local function SafeGet(s)
    local ok, raw = pcall(s.get)
    if not ok then return nil end
    if (issecretvalue and issecretvalue(raw)) or type(raw) ~= "number" then return nil end
    return raw
end

--------------------------------------------------------------------
-- Frames
--------------------------------------------------------------------
local RebuildPanel, ToggleConfig, RefreshConfig, OpenColorPicker, ApplyBackground
local main, statPool, activeList = nil, {}, {}
local gearBtn, lockBtn, headerLabel
local held = {}
local btnBg, btnFontUp, btnFontDown, fontLabel

local function UpdateLockIcon()
    if not lockBtn or not gearBtn then return end
    if db.locked then
        lockBtn:SetNormalTexture("Interface\\Buttons\\LockButton-Locked-Up")
        gearBtn:Hide()
        lockBtn:ClearAllPoints()
        if db.layout == "row" then
            lockBtn:SetPoint("RIGHT", main, "RIGHT", -4, 0)
        else
            lockBtn:SetPoint("TOPRIGHT", -4, -1)
        end
    else
        lockBtn:SetNormalTexture("Interface\\Buttons\\LockButton-Unlocked-Up")
        gearBtn:Show()
        gearBtn:ClearAllPoints()
        lockBtn:ClearAllPoints()
        if db.layout == "row" then
            local gearS = gearBtn:GetWidth() or GEARW
            gearBtn:SetPoint("RIGHT", main, "RIGHT", -4, 0)
            lockBtn:SetPoint("RIGHT", main, "RIGHT", -(4 + gearS + 4), 0)
        else
            gearBtn:SetPoint("TOPRIGHT", -4, -4)
            lockBtn:SetPoint("TOPRIGHT", -(4 + GEARW + 4), -1)
        end
    end
end

local function ActionBar1Width()
    local b1, b12 = _G["ActionButton1"], _G["ActionButton12"]
    if b1 and b12 and b1.GetLeft and b12.GetRight then
        local l, r = b1:GetLeft(), b12:GetRight()
        if l and r and r > l + 50 then return r - l end
    end
    local mb = _G["MainMenuBar"]
    if mb and mb.GetWidth then local w = mb:GetWidth(); if w and w > 100 then return w end end
    -- Last resort when action bar / main menu bar are unavailable (e.g. hidden).
    -- Tuned to a typical retail action-bar span at default font (≈562).
    return 562
end

local function ApplyBackground()
    if not main then return end
    if db.background ~= false then
        main:SetBackdrop({
            bgFile   = "Interface\\Tooltips\\UI-Tooltip-Background",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            tile = true, tileSize = 16, edgeSize = 12,
            insets = { left = 3, right = 3, top = 3, bottom = 3 },
        })
        main:SetBackdropColor(0, 0, 0, 0.78)
        main:SetBackdropBorderColor(0.4, 0.4, 0.4, 0.9)
    else
        main:SetBackdrop(nil)
    end
end

local function CreateUI()
    main = CreateFrame("Frame", "PowerStatsFrame", UIParent, "BackdropTemplate")
    ApplyBackground()
    main:SetMovable(true); main:EnableMouse(true)
    main:RegisterForDrag("LeftButton")
    main:SetScript("OnDragStart", function(self) if not db.locked then self:StartMoving() end end)
    main:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local p, _, _, x, y = self:GetPoint()
        db.point, db.x, db.y = p, x, y
    end)
    main:SetScript("OnMouseUp", function(_, button) if button == "RightButton" then ToggleConfig() end end)

    headerLabel = main:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    headerLabel:SetText("One per Row")

    gearBtn = CreateFrame("Button", nil, main)
    gearBtn:SetSize(GEARW, GEARW)
    gearBtn:SetNormalTexture("Interface\\Buttons\\UI-OptionsButton")
    gearBtn:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
    gearBtn:SetScript("OnClick", function() ToggleConfig() end)

    lockBtn = CreateFrame("Button", nil, main)
    lockBtn:SetSize(LOCKW, LOCKW)
    lockBtn:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
    lockBtn:SetScript("OnClick", function()
        db.locked = not db.locked
        UpdateLockIcon()
    end)
    UpdateLockIcon()
end

--------------------------------------------------------------------
-- Layout
--------------------------------------------------------------------
local function BuildList()
    wipe(activeList)
    for _, s in ipairs(REGISTRY) do
        if db.stats[s.key] and #activeList < MAX_SHOW then activeList[#activeList + 1] = s end
    end
end

local RIGHTW = GEARW + LOCKW + 14   -- space reserved for gear + lock
local ROW_EXTRA = 16          -- a few px longer than Action Bar 1

local function LayoutRowSpacing()
    if db.layout ~= "row" then return end
    local n = #activeList
    if n == 0 then return end
    local m = Metrics()
    local innerL = m.pad
    local innerR = main:GetWidth() - RIGHTW - m.pad
    local avail  = innerR - innerL
    local total  = 0
    for _, s in ipairs(activeList) do total = total + (s._fs:GetStringWidth() or 0) end
    local gap = (avail - total) / (n + 1)
    if gap < 2 then gap = 2 end
    local x = innerL + gap
    for _, s in ipairs(activeList) do
        s._fs:ClearAllPoints()
        s._fs:SetPoint("LEFT", main, "LEFT", x, 0)
        x = x + (s._fs:GetStringWidth() or 0) + gap
    end
end

function RebuildPanel()
    BuildList()
    for _, fs in ipairs(statPool) do fs:Hide() end
    local n = #activeList
    local m = Metrics()

    if headerLabel then
        headerLabel:SetFont(FONT_PATH, math.max(9, m.fontSize - 1), "")
    end

    if db.layout == "row" then
        headerLabel:Hide()
        for i, s in ipairs(activeList) do
            local fs = statPool[i] or main:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            statPool[i] = fs
            fs:SetFont(FONT_PATH, m.fontSize, "")
            fs:SetWidth(math.max(200, m.cellW * 2))
            fs:SetJustifyH("LEFT")
            fs:Show()
            s._fs = fs
        end
        -- Scale width, height, and chrome with font so the single-row box stays proportional.
        local k = m.fontSize / BASE_FONT
        local gearS = math.max(14, math.floor(GEARW * k + 0.5))
        local lockS = math.max(18, math.floor(LOCKW * k + 0.5))
        gearBtn:SetSize(gearS, gearS)
        lockBtn:SetSize(lockS, lockS)
        gearBtn:ClearAllPoints(); gearBtn:SetPoint("RIGHT", main, "RIGHT", -4, 0)
        lockBtn:ClearAllPoints(); lockBtn:SetPoint("RIGHT", main, "RIGHT", -(4 + gearS + 4), 0)
        local rowW = ActionBar1Width() * k
        local rowH = math.max(m.rowH + 2 * m.vpad, lockS + 2)
        main:SetSize(rowW, rowH)
        LayoutRowSpacing()
    else
        gearBtn:SetSize(GEARW, GEARW)
        lockBtn:SetSize(LOCKW, LOCKW)
        headerLabel:ClearAllPoints(); headerLabel:SetPoint("TOPLEFT", m.pad, -6); headerLabel:Show()
        gearBtn:ClearAllPoints(); gearBtn:SetPoint("TOPRIGHT", -4, -4)
        lockBtn:ClearAllPoints(); lockBtn:SetPoint("TOPRIGHT", -(4 + GEARW + 4), -1)
        for i, s in ipairs(activeList) do
            local fs = statPool[i] or main:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            statPool[i] = fs
            fs:SetFont(FONT_PATH, m.fontSize, "")
            fs:ClearAllPoints()
            fs:SetPoint("TOPLEFT", m.pad, -(m.vpad + m.headerH) - (i - 1) * m.rowH)
            fs:SetWidth(m.cellW - 4)
            fs:SetJustifyH("LEFT")
            fs:Show()
            s._fs = fs
        end
        main:SetSize(m.cellW + 2 * m.pad - m.widthTrim, m.vpad + m.headerH + math.max(1, n) * m.rowH + m.vpad)
    end
    ApplyBackground()
    UpdateLockIcon()
end

--------------------------------------------------------------------
-- Values (held in combat)
--------------------------------------------------------------------
local function UpdateValues()
    for _, s in ipairs(activeList) do
        local raw = SafeGet(s)
        if raw ~= nil then held[s.key] = raw end
        local val = (raw ~= nil) and raw or held[s.key]
        local fs = s._fs
        if fs then
            if val == nil then
                fs:SetText(("|cff%s%s|r |cff888888n/a|r"):format(RGBHex(GetColor(s)), s.name))
            else
                fs:SetText(("|cff%s%s|r |cffffffff%s|r"):format(RGBHex(GetColor(s)), s.name, FormatVal(s, val)))
            end
        end
    end
    LayoutRowSpacing()
end

--------------------------------------------------------------------
-- Color picker
--------------------------------------------------------------------
function OpenColorPicker(s, swatch)
    local pr, pg, pb = GetColor(s)
    local function apply()
        local r, g, b = ColorPickerFrame:GetColorRGB()
        db.colors[s.key] = { r = r, g = g, b = b }
        if swatch then swatch:SetColorTexture(r, g, b) end
    end
    local function cancel()
        db.colors[s.key] = { r = pr, g = pg, b = pb }
        if swatch then swatch:SetColorTexture(pr, pg, pb) end
    end
    if ColorPickerFrame.SetupColorPickerAndShow then
        ColorPickerFrame:SetupColorPickerAndShow({ r=pr, g=pg, b=pb, hasOpacity=false, swatchFunc=apply, cancelFunc=cancel })
    else
        ColorPickerFrame.func=apply; ColorPickerFrame.cancelFunc=cancel; ColorPickerFrame.hasOpacity=false
        ColorPickerFrame:SetColorRGB(pr, pg, pb); ColorPickerFrame:Hide(); ColorPickerFrame:Show()
    end
end

--------------------------------------------------------------------
-- Config panel
--------------------------------------------------------------------
local config, configRows, btnRow, btnCol = nil, {}, nil, nil
local function Print(msg) print("|cff66ccffPowerStats|r: " .. msg) end

function RefreshConfig()
    if not config then return end
    local full = CountTrue(db.stats) >= MAX_SHOW
    for _, row in ipairs(configRows) do
        local on = db.stats[row.s.key] and true or false
        row.cb:SetChecked(on)
        local enable = on or (not full)
        if row.cb.SetEnabled then row.cb:SetEnabled(enable) else if enable then row.cb:Enable() else row.cb:Disable() end end
        row.cb:SetAlpha(enable and 1 or 0.3)
    end
    if btnRow and btnCol then
        btnRow:SetAlpha(db.layout == "row" and 0.55 or 1)
        btnCol:SetAlpha(db.layout == "column" and 0.55 or 1)
    end
    if btnBg then
        btnBg:SetText(db.background ~= false and "BG: On" or "BG: Off")
    end
    if fontLabel then
        fontLabel:SetText(tostring(db.fontSize or BASE_FONT))
    end
    if btnFontDown then
        local fs = db.fontSize or BASE_FONT
        if btnFontDown.SetEnabled then btnFontDown:SetEnabled(fs > FONT_MIN) else
            if fs > FONT_MIN then btnFontDown:Enable() else btnFontDown:Disable() end
        end
    end
    if btnFontUp then
        local fs = db.fontSize or BASE_FONT
        if btnFontUp.SetEnabled then btnFontUp:SetEnabled(fs < FONT_MAX) else
            if fs < FONT_MAX then btnFontUp:Enable() else btnFontUp:Disable() end
        end
    end
end

local function SetFontSize(nextSize)
    nextSize = math.floor(tonumber(nextSize) or BASE_FONT)
    if nextSize < FONT_MIN then nextSize = FONT_MIN end
    if nextSize > FONT_MAX then nextSize = FONT_MAX end
    db.fontSize = nextSize
    RebuildPanel()
    UpdateValues()
    RefreshConfig()
end

local function BuildConfig()
    config = CreateFrame("Frame", "PowerStatsConfig", UIParent, "BackdropTemplate")
    config:SetSize(250, 470)
    config:SetPoint("LEFT", main, "RIGHT", 8, 0)
    config:SetBackdrop({
        bgFile   = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    config:SetBackdropColor(0, 0, 0, 0.9)
    config:SetMovable(true); config:EnableMouse(true)
    config:RegisterForDrag("LeftButton")
    config:SetScript("OnDragStart", config.StartMoving)
    config:SetScript("OnDragStop", config.StopMovingOrSizing)
    config:Hide()

    local ct = config:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    ct:SetPoint("TOP", 0, -8); ct:SetText("PowerStats  (max "..MAX_SHOW..")")

    local close = CreateFrame("Button", nil, config, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", 2, 2)

    btnCol = CreateFrame("Button", nil, config, "UIPanelButtonTemplate")
    btnCol:SetSize(105, 20); btnCol:SetPoint("TOPLEFT", 14, -28); btnCol:SetText("One per Row")
    btnCol:SetScript("OnClick", function() db.layout = "column"; RebuildPanel(); RefreshConfig() end)
    btnRow = CreateFrame("Button", nil, config, "UIPanelButtonTemplate")
    btnRow:SetSize(105, 20); btnRow:SetPoint("TOPRIGHT", -14, -28); btnRow:SetText("Single Row")
    btnRow:SetScript("OnClick", function() db.layout = "row"; RebuildPanel(); RefreshConfig() end)

    btnBg = CreateFrame("Button", nil, config, "UIPanelButtonTemplate")
    btnBg:SetSize(105, 20)
    btnBg:SetPoint("TOPLEFT", 14, -52)
    btnBg:SetScript("OnClick", function()
        db.background = not (db.background ~= false)
        ApplyBackground()
        RefreshConfig()
    end)

    -- Same footprint as the Single Row button above.
    local fontBar = CreateFrame("Frame", nil, config)
    fontBar:SetSize(105, 20)
    fontBar:SetPoint("TOPRIGHT", -14, -52)

    local fontHint = fontBar:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    fontHint:SetPoint("LEFT", fontBar, "LEFT", 0, 0)
    fontHint:SetText("|cffffd200Font|r")

    -- Same height/chrome as BG: On (UIPanelButtonTemplate @ 20).
    btnFontDown = CreateFrame("Button", nil, fontBar, "UIPanelButtonTemplate")
    btnFontDown:SetSize(20, 20)
    btnFontDown:SetPoint("LEFT", fontHint, "RIGHT", 4, 0)
    btnFontDown:SetText("-")
    if btnFontDown.GetFontString and btnFontDown:GetFontString() then
        btnFontDown:GetFontString():SetFontObject(GameFontHighlightSmall)
    end
    btnFontDown:SetScript("OnClick", function() SetFontSize((db.fontSize or BASE_FONT) - 1) end)

    fontLabel = fontBar:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    fontLabel:SetPoint("LEFT", btnFontDown, "RIGHT", 2, 0)
    fontLabel:SetWidth(22)
    fontLabel:SetJustifyH("CENTER")

    btnFontUp = CreateFrame("Button", nil, fontBar, "UIPanelButtonTemplate")
    btnFontUp:SetSize(20, 20)
    btnFontUp:SetPoint("LEFT", fontLabel, "RIGHT", 2, 0)
    btnFontUp:SetText("+")
    if btnFontUp.GetFontString and btnFontUp:GetFontString() then
        btnFontUp:GetFontString():SetFontObject(GameFontHighlightSmall)
    end
    btnFontUp:SetScript("OnClick", function() SetFontSize((db.fontSize or BASE_FONT) + 1) end)

    local scroll = CreateFrame("ScrollFrame", "PowerStatsScroll", config, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 10, -78)
    scroll:SetPoint("BOTTOMRIGHT", -30, 10)
    local content = CreateFrame("Frame", nil, scroll)
    content:SetWidth(200)
    scroll:SetScrollChild(content)

    local y = -2
    for _, catDef in ipairs(CATS) do
        local hdr = content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        hdr:SetPoint("TOPLEFT", 2, y); hdr:SetText("|cffffd200"..catDef.label.."|r")
        y = y - 18
        for _, s in ipairs(REGISTRY) do
            if s.cat == catDef.id then
                local key = s.key
                local cb = CreateFrame("CheckButton", nil, content)
                cb:SetSize(18, 18); cb:SetPoint("TOPLEFT", 8, y + 2)
                cb:SetNormalTexture("Interface\\Buttons\\UI-CheckBox-Up")
                cb:SetPushedTexture("Interface\\Buttons\\UI-CheckBox-Down")
                cb:SetHighlightTexture("Interface\\Buttons\\UI-CheckBox-Highlight", "ADD")
                cb:SetCheckedTexture("Interface\\Buttons\\UI-CheckBox-Check")
                cb:SetScript("OnClick", function(self)
                    if self:GetChecked() then
                        if CountTrue(db.stats) >= MAX_SHOW then self:SetChecked(false); Print("Max "..MAX_SHOW.." stats."); return end
                        db.stats[key] = true
                    else db.stats[key] = nil end
                    RebuildPanel(); RefreshConfig()
                end)

                local swatch = CreateFrame("Button", nil, content)
                swatch:SetSize(12, 12); swatch:SetPoint("TOPLEFT", 32, y + 1)
                local tex = swatch:CreateTexture(nil, "ARTWORK"); tex:SetAllPoints(); tex:SetColorTexture(GetColor(s))
                swatch:SetScript("OnClick", function() OpenColorPicker(s, tex) end)

                local lbl = content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                lbl:SetPoint("TOPLEFT", 52, y - 1); lbl:SetJustifyH("LEFT"); lbl:SetWidth(130)

                configRows[#configRows + 1] = { s = s, cb = cb, swatch = tex, lbl = lbl }
                y = y - 22
            end
        end
        y = y - 4
    end
    content:SetHeight(-y + 8)
end

function ToggleConfig()
    if not config then BuildConfig() end
    if config:IsShown() then config:Hide() else config:Show(); RefreshConfig() end
end

local function UpdateConfigValues()
    if not config or not config:IsShown() then return end
    for _, row in ipairs(configRows) do
        local s = row.s
        local v = SafeGet(s)
        if v == nil then v = held[s.key] end
        local shown = (v == nil) and "|cff888888n/a|r" or FormatVal(s, v)
        row.lbl:SetText(("%s  |cffaaaaaa%s|r"):format(s.name, shown))
        row.swatch:SetColorTexture(GetColor(s))
    end
end

--------------------------------------------------------------------
-- Loop / slash
--------------------------------------------------------------------
local function ApplyBase()
    main:ClearAllPoints()
    main:SetPoint(db.point, UIParent, db.point, db.x, db.y)
    main:SetScale(db.scale)
end

local accum, cfgAccum = 0, 0
local function OnUpdate(_, dt)
    accum = accum + dt; cfgAccum = cfgAccum + dt
    if accum < 0.2 then return end
    accum = 0
    UpdateValues()
    if cfgAccum >= 0.3 then cfgAccum = 0; UpdateConfigValues() end
end

local function HandleSlash(msg)
    msg = (msg or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
    local cmd = msg:match("^(%S*)")
    if cmd == "" or cmd == "toggle" then
        if main:IsShown() then main:Hide() else main:Show() end
    elseif cmd == "config" or cmd == "cfg" then
        ToggleConfig()
    elseif cmd == "row" then
        db.layout = "row"; RebuildPanel(); RefreshConfig(); Print("layout: single row")
    elseif cmd == "column" or cmd == "col" then
        db.layout = "column"; RebuildPanel(); RefreshConfig(); Print("layout: one per row")
    elseif cmd == "lock" then
        db.locked = not db.locked; UpdateLockIcon(); Print(db.locked and "locked." or "unlocked.")
    elseif cmd == "scale" then
        local n = tonumber(msg:match("^%S*%s+(%S+)"))
        if n and n >= 0.5 and n <= 2.5 then db.scale = n; main:SetScale(n); Print("scale: "..n)
        else Print("usage: /ps scale <0.5-2.5>") end
    elseif REG_BY_KEY[cmd] then
        if db.stats[cmd] then db.stats[cmd] = nil
        elseif CountTrue(db.stats) < MAX_SHOW then db.stats[cmd] = true
        else Print("Max "..MAX_SHOW.." stats."); return end
        RebuildPanel(); RefreshConfig(); Print(cmd..": "..(db.stats[cmd] and "ON" or "OFF"))
    elseif cmd == "reset" then
        wipe(db)
        for k, v in pairs(DEFAULTS) do
            if type(v) == "table" then db[k] = {}; for kk, vv in pairs(v) do db[k][kk] = vv end
            else db[k] = v end
        end
        ApplyBase(); RebuildPanel(); RefreshConfig(); main:Show(); Print("defaults restored.")
    else
        Print("commands:")
        print("  /ps            show/hide   (right-click panel = config)")
        print("  /ps config     stat selection panel")
        print("  /ps row | /ps column     layout")
        print("  /ps lock       lock/unlock move")
        print("  /ps scale N    0.5-2.5")
        print("  /ps <key>      toggle a stat (e.g. /ps haste)")
        print("  /ps reset")
    end
end

--------------------------------------------------------------------
-- Bootstrap
--------------------------------------------------------------------
local boot = CreateFrame("Frame")
boot:RegisterEvent("ADDON_LOADED")
boot:RegisterEvent("PLAYER_LOGIN")
boot:RegisterEvent("PLAYER_ENTERING_WORLD")
boot:SetScript("OnEvent", function(_, event, arg1)
    if event ~= "ADDON_LOADED" then
        -- action bars are laid out by now: recompute (fixes first-login row width)
        if main then
            RebuildPanel()
            if C_Timer and C_Timer.After then C_Timer.After(1, function() if main then RebuildPanel() end end) end
        end
        return
    end
    if arg1 ~= ADDON then return end
    PowerStatsDB = PowerStatsDB or {}
    db = PowerStatsDB

    for k, v in pairs(DEFAULTS) do
        if db[k] == nil then
            if type(v) == "table" then db[k] = {}; for kk, vv in pairs(v) do db[k][kk] = vv end
            else db[k] = v end
        end
    end
    db.colors = db.colors or {}
    if type(db.stats) ~= "table" then
        db.stats = {}
        for k, v in pairs(DEFAULTS.stats) do db.stats[k] = v end
    end
    if db.layout ~= "row" and db.layout ~= "column" then db.layout = "column" end
    if db.background == nil then db.background = true end
    db.fontSize = tonumber(db.fontSize) or BASE_FONT
    if db.fontSize < FONT_MIN then db.fontSize = FONT_MIN end
    if db.fontSize > FONT_MAX then db.fontSize = FONT_MAX end

    CreateUI()
    ApplyBase()
    RebuildPanel()
    UpdateValues()
    main:SetScript("OnUpdate", OnUpdate)
    main:Show()

    SLASH_POWERSTATS1 = "/ps"
    SLASH_POWERSTATS2 = "/powerstats"
    SlashCmdList["POWERSTATS"] = HandleSlash
    Print("loaded. Right-click the panel or /ps config.")
end)
