-- OneForAll v1.3.8
-- Compatible with WoW 12.0.5, 12.0.7 (Midnight) and Classic variants
-- Original author: Thoreex | Updated by: Randalthòr

OneForAll_Name          = "OneForAll"
OneForAll_FormalName    = C_AddOns.GetAddOnMetadata(OneForAll_Name, "Title")
OneForAll_Version       = C_AddOns.GetAddOnMetadata(OneForAll_Name, "Version")
OneForAll_ButtonPrefix  = "LibDBIcon10_"
OneForAll_Events        = {}
OneForAll_Callbacks     = {}
OneForAll_IsShown       = false
OneForAll_LibDataBroker = LibStub("LibDataBroker-1.1", true)
OneForAll_LibDBIcon     = LibStub("LibDBIcon-1.0", true)
OneForAll_Frame         = nil
OneForAll_MinimapIcon   = nil

local BUTTONS_PER_ROW = 12

OneForAll_Ignored = {
    OneForAll_ButtonPrefix..OneForAll_Name,
    "TimeManagerClockButton",
    "MiniMapBattlefieldFrame",
    "MiniMapLFGFrameIcon",
}

local OFA_FrameToID        = {}
local OFA_IDToFrame        = {}
local OFA_FpCollision      = {}
local OFA_Scanned          = {}
local OFA_Included         = {}
local OFA_Excluded         = {}
local OFA_SavedPositions   = {}
local OFA_PendingPositions = {}

setmetatable(OFA_FrameToID, { __mode = "k" })

-- ─────────────────────────────────────────────────────────────────────────────
-- Fingerprint for anonymous buttons
-- WoW 12.x: GetTexture() may return a numeric FileData ID instead of a path
-- string. That number changes between client versions, making it useless as a
-- stable identifier. We use GetDebugName() + GetAtlas() + string-only texture
-- as a multi-level stable fingerprint.
-- ─────────────────────────────────────────────────────────────────────────────

local function OFA_GetButtonTexture(button)
    local ok, normal = pcall(function() return button:GetNormalTexture() end)
    if not ok or not normal then return "" end
    local ok3, atlas = pcall(function() return normal:GetAtlas() end)
    if ok3 and atlas and type(atlas) == "string" and atlas ~= "" then
        return "atlas_" .. atlas
    end
    local ok2, rawTex = pcall(function() return normal:GetTexture() end)
    if ok2 and rawTex and type(rawTex) == "string" and rawTex ~= "" then
        return rawTex:gsub("\\", "/")
    end
    return ""
end

local function OFA_MakeFingerprint(button)
    local debugName = ""
    local ok, dn = pcall(function() return button:GetDebugName() end)
    if ok and dn and type(dn) == "string" and dn ~= "" then
        debugName = dn:match("^([%w_]+)") or ""
    end
    local tex = OFA_GetButtonTexture(button)
    local w   = math.floor((button:GetWidth()  or 0) + 0.5)
    local h   = math.floor((button:GetHeight() or 0) + 0.5)
    local base = "OFA_fp_" .. debugName .. "_" .. tex .. "_" .. w .. "x" .. h
    if not OFA_FpCollision[base] then
        OFA_FpCollision[base] = 1
        return base
    end
    local existing = OFA_FrameToID[button]
    if existing and existing:sub(1, #base) == base then return existing end
    OFA_FpCollision[base] = OFA_FpCollision[base] + 1
    return base .. "_" .. OFA_FpCollision[base]
end

local function OFA_GetOrCreateID(button)
    local name = button:GetName()
    if name and name ~= "" then return name end
    if OFA_FrameToID[button] then return OFA_FrameToID[button] end
    local id = OFA_MakeFingerprint(button)
    OFA_FrameToID[button] = id
    OFA_IDToFrame[id]     = button
    return id
end

local function OFA_GetFrame(id)
    return _G[id] or OFA_IDToFrame[id]
end

local function OFA_IsLibDBIconButton(id)
    local libName = id:match("^" .. OneForAll_ButtonPrefix .. "(.+)$")
    return libName, libName and OneForAll_LibDBIcon and OneForAll_LibDBIcon:IsRegistered(libName)
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Set helpers
-- ─────────────────────────────────────────────────────────────────────────────

local function OFA_IsScanned(id)  return OFA_Scanned[id] == true end

local function OFA_IsIgnored(id)
    if not id then return true end
    for _, n in ipairs(OneForAll_Ignored) do
        if n == id then return true end
    end
    return false
end

local function OFA_IsExcluded(id)
    for _, v in ipairs(OFA_Excluded) do if v == id then return true end end
    return false
end

local function OFA_GetIncludedPos(id)
    for i, v in ipairs(OFA_Included) do if v == id then return i end end
    return 0
end

local function OFA_GetExcludedPos(id)
    for i, v in ipairs(OFA_Excluded) do if v == id then return i end end
    return 0
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Core lifecycle
-- ─────────────────────────────────────────────────────────────────────────────

function OneForAll_OnLoad()
    OneForAll_Frame = CreateFrame("Frame")
    for event, _ in pairs(OneForAll_Events) do
        OneForAll_Frame:RegisterEvent(event)
    end
    OneForAll_Frame:SetScript("OnEvent", OneForAll_OnEvent)
    for callback, _ in pairs(OneForAll_Callbacks) do
        OneForAll_LibDBIcon.RegisterCallback(OneForAll_Frame, callback, OneForAll_OnCallback)
    end
end

function OneForAll_OnEvent(self, event, ...)
    if OneForAll_Events[event] then OneForAll_Events[event](self, ...) end
end

function OneForAll_OnCallback(callback, ...)
    if OneForAll_Callbacks[callback] then OneForAll_Callbacks[callback](callback, ...) end
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Minimap icon
-- ─────────────────────────────────────────────────────────────────────────────

function OneForAll_OnClick(self, button)
    OneForAll_ToggleButtons()
    OneForAll_PositionButtons()
end

function OneForAll_OnTooltipShow(tooltip)
    if not tooltip or not tooltip.AddLine then return end
    tooltip:AddLine(OneForAll_FormalName .. " v" .. OneForAll_Version)
    tooltip:AddLine("|cFFffffffClick to show/hide icons|r")
    tooltip:AddLine("|cFFffffffDrag and drop here to include/exclude icons|r")
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Minimap position helpers
-- ─────────────────────────────────────────────────────────────────────────────

local function OFA_GetMinimapPos(button)
    if button.db then
        if button.db.minimapPos ~= nil then return button.db.minimapPos end
        if button.db.minimap and button.db.minimap.minimapPos ~= nil then
            return button.db.minimap.minimapPos
        end
    end
    return button.minimapPos
end

local function OFA_SetMinimapPos(button, pos)
    if pos == nil then return end
    if button.db then
        if button.db.minimapPos ~= nil then button.db.minimapPos = pos; return end
        if button.db.minimap and button.db.minimap.minimapPos ~= nil then
            button.db.minimap.minimapPos = pos; return
        end
        button.db.minimapPos = pos
    else
        button.minimapPos = pos
    end
end

local function OFA_SavePoint(button)
    if not button.GetPoint then return end
    local p, rt, rp, ox, oy = button:GetPoint(1)
    if not p then p, rt, rp, ox, oy = button:GetPoint() end
    return p, rt, rp, ox, oy
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Include
-- ─────────────────────────────────────────────────────────────────────────────

local function OFA_SortIncluded()
    table.sort(OFA_Included, function(a, b) return a:upper() < b:upper() end)
end

function OneForAll_IncludeButton(button)
    local id = OFA_GetOrCreateID(button)

    if button.OFA_PositionLocked then
        button.OFA_PositionLocked = false
        if button.OFA_OrigSetPoint    then button.SetPoint       = button.OFA_OrigSetPoint    end
        if button.OFA_OrigClearPoints then button.ClearAllPoints = button.OFA_OrigClearPoints end
        button.OFA_OrigSetPoint    = nil
        button.OFA_OrigClearPoints = nil
    end

    table.insert(OFA_Included, id)
    local ep = OFA_GetExcludedPos(id)
    if ep > 0 then table.remove(OFA_Excluded, ep) end
    OFA_SortIncluded()

    button.HiddenVisibility      = button:IsVisible()
    button.HiddenShow            = button.Show
    button.HiddenHide            = button.Hide
    button.HiddenClearAllPoints  = button.ClearAllPoints
    button.HiddenSetPoint        = button.SetPoint
    button.HiddenOnDragStart     = button:GetScript("OnDragStart")
    button.HiddenOnDragStop      = button:GetScript("OnDragStop")

    if button.HiddenMinimapPos == nil then
        button.HiddenMinimapPos = OFA_GetMinimapPos(button)
    end
    if button.HiddenPoint == nil then
        button.HiddenPoint,
        button.HiddenRelativeTo,
        button.HiddenRelativePoint,
        button.HiddenOffsetX,
        button.HiddenOffsetY = OFA_SavePoint(button)
    end

    button.Show = function()
        button.HiddenVisibility = true
        if OneForAll_IsShown then
            button:HiddenShow()
            OneForAll_PositionButtons()
        end
    end
    button.Hide = function()
        button.HiddenVisibility = false
        if OneForAll_IsShown then
            button:HiddenHide()
            OneForAll_PositionButtons()
        end
    end
    button.ClearAllPoints = function() end
    button.SetPoint       = function() end

    button:SetScript("OnDragStart", function(btn)
        btn:SetScript("OnUpdate", function(b)
            local x, y  = GetCursorPosition()
            local r     = b:GetWidth() / 2
            local scale = b:GetEffectiveScale()
            b:HiddenSetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", (x-r)/scale, (y-r)/scale)
        end)
    end)
    button:SetScript("OnDragStop", function(btn)
        btn:SetScript("OnUpdate", nil)
        local x, y  = GetCursorPosition()
        local r     = btn:GetWidth() / 2
        local scale = btn:GetEffectiveScale()
        local cx    = (x - r) / scale
        local cy    = (y - r) / scale
        if OneForAll_IsCursorColliding(OneForAll_MinimapIcon) then
            btn.HiddenPoint         = "BOTTOMLEFT"
            btn.HiddenRelativeTo    = UIParent
            btn.HiddenRelativePoint = "BOTTOMLEFT"
            btn.HiddenOffsetX       = cx
            btn.HiddenOffsetY       = cy
            if not OneForAll_IsShown then OneForAll_ToggleButtons() end
            OneForAll_ExcludeButton(btn)
        end
        OneForAll_PositionButtons()
    end)

    if not OneForAll_IsShown then button:HiddenHide() end
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Exclude
-- ─────────────────────────────────────────────────────────────────────────────

function OneForAll_ExcludeButton(button)
    local id = OFA_GetOrCreateID(button)

    table.insert(OFA_Excluded, id)
    local ip = OFA_GetIncludedPos(id)
    if ip > 0 then table.remove(OFA_Included, ip) end
    OFA_SortIncluded()

    button.Show           = button.HiddenShow
    button.Hide           = button.HiddenHide
    button.ClearAllPoints = button.HiddenClearAllPoints
    button.SetPoint       = button.HiddenSetPoint
    button:SetScript("OnDragStart", button.HiddenOnDragStart)
    button:SetScript("OnDragStop",  button.HiddenOnDragStop)

    if button.HiddenMinimapPos ~= nil then
        OFA_SetMinimapPos(button, button.HiddenMinimapPos)
    end

    local libName, isLib = OFA_IsLibDBIconButton(id)
    if isLib then
        OneForAll_LibDBIcon:Refresh(libName)
    else
        button:ClearAllPoints()
        local sp = OFA_SavedPositions[id]
        if sp then
            local relTo = (sp[2] == "UIParent") and UIParent or _G[sp[2]] or UIParent
            button:SetPoint(sp[1], relTo, sp[3], sp[4], sp[5])
        elseif button.HiddenPoint ~= nil then
            button:SetPoint(button.HiddenPoint,
                            button.HiddenRelativeTo,
                            button.HiddenRelativePoint,
                            button.HiddenOffsetX,
                            button.HiddenOffsetY)
            local relName = (button.HiddenRelativeTo == UIParent) and "UIParent"
                         or (button.HiddenRelativeTo and button.HiddenRelativeTo:GetName())
                         or "UIParent"
            OFA_SavedPositions[id] = {
                button.HiddenPoint, relName,
                button.HiddenRelativePoint,
                button.HiddenOffsetX, button.HiddenOffsetY
            }
        else
            local p, rt, rp, ox, oy = OFA_SavePoint(OneForAll_MinimapIcon)
            if p then button:SetPoint(p, rt, rp, ox, oy) end
        end
    end

    button.HiddenVisibility    = nil
    button.HiddenMinimapPos    = nil
    button.HiddenPoint         = nil
    button.HiddenRelativeTo    = nil
    button.HiddenRelativePoint = nil
    button.HiddenOffsetX       = nil
    button.HiddenOffsetY       = nil
    button.HiddenShow          = nil
    button.HiddenHide          = nil
    button.HiddenClearAllPoints= nil
    button.HiddenSetPoint      = nil
    button.HiddenOnDragStart   = nil
    button.HiddenOnDragStop    = nil

    if not OneForAll_IsShown then button:Show() end
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Drag & Drop for excluded buttons (re-include or reposition)
-- ─────────────────────────────────────────────────────────────────────────────

function OneForAll_SetupDragAndDropButton(button)
    button:HookScript("OnDragStart", function(btn)
        btn.HiddenMinimapPos = OFA_GetMinimapPos(btn)
        btn.HiddenPoint,
        btn.HiddenRelativeTo,
        btn.HiddenRelativePoint,
        btn.HiddenOffsetX,
        btn.HiddenOffsetY = OFA_SavePoint(btn)
    end)
    button:HookScript("OnDragStop", function(btn)
        if OneForAll_IsCursorColliding(OneForAll_MinimapIcon) then
            if btn.HiddenMinimapPos ~= nil then
                OFA_SetMinimapPos(btn, btn.HiddenMinimapPos)
            end
            local btnID = OFA_GetOrCreateID(btn)
            local libName, isLib = OFA_IsLibDBIconButton(btnID)
            if isLib then
                OneForAll_LibDBIcon:Refresh(libName)
            elseif btn.HiddenPoint ~= nil then
                btn:SetPoint(btn.HiddenPoint, btn.HiddenRelativeTo,
                             btn.HiddenRelativePoint, btn.HiddenOffsetX, btn.HiddenOffsetY)
            end
            if not OneForAll_IsShown then OneForAll_ToggleButtons() end
            OneForAll_IncludeButton(btn)
        else
            -- Update saved position when user repositions an excluded button
            local btnID = OFA_GetOrCreateID(btn)
            if OFA_IsExcluded(btnID) then
                local libName, isLib = OFA_IsLibDBIconButton(btnID)
                if isLib then
                    -- For LibDBIcon buttons: save the minimap angle, not screen coords
                    -- LibDBIcon:Refresh() will use minimapPos to place on circumference
                    -- (minimapPos is already updated by LibDBIcon's own OnDragStop)
                    OFA_SavedPositions[btnID] = nil  -- no pixel coords needed
                else
                    -- For non-LibDBIcon buttons: save screen coords as before
                    local x, y  = GetCursorPosition()
                    local r     = btn:GetWidth() / 2
                    local scale = btn:GetEffectiveScale()
                    OFA_SavedPositions[btnID] = {
                        "BOTTOMLEFT", "UIParent", "BOTTOMLEFT",
                        (x - r) / scale, (y - r) / scale
                    }
                end
            end
        end
        OneForAll_PositionButtons()
    end)
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Toggle + Multi-row layout
-- ─────────────────────────────────────────────────────────────────────────────

function OneForAll_ToggleButtons()
    OneForAll_IsShown = not OneForAll_IsShown
    for _, id in ipairs(OFA_Included) do
        local btn = OFA_GetFrame(id)
        if btn then
            if OneForAll_IsShown then
                if btn.HiddenVisibility then btn:HiddenShow() end
            else
                if btn.HiddenVisibility then btn:HiddenHide() end
            end
        end
    end
end

function OneForAll_PositionButtons()
    if not OneForAll_MinimapIcon then return end
    local iconW  = OneForAll_MinimapIcon:GetWidth()
    local iconH  = OneForAll_MinimapIcon:GetHeight()
    local column = 0
    local row    = 0
    for _, id in ipairs(OFA_Included) do
        local btn = OFA_GetFrame(id)
        if btn and btn.HiddenVisibility and btn.HiddenClearAllPoints then
            btn:HiddenClearAllPoints()
            btn:HiddenSetPoint("CENTER", OneForAll_MinimapIcon, "CENTER",
                (column + 1) * iconW * -1, row * iconH)
            column = column + 1
            if column >= BUTTONS_PER_ROW then column = 0; row = row + 1 end
        end
    end
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Helpers
-- ─────────────────────────────────────────────────────────────────────────────

function OneForAll_IsCursorColliding(button)
    if not button then return false end
    local x, y  = GetCursorPosition()
    local scale = button:GetEffectiveScale()
    x = x / scale; y = y / scale
    return x >= button:GetLeft() and x <= button:GetRight()
       and y >= button:GetBottom() and y <= button:GetTop()
end

local function OFA_IsMinimapButton(object)
    if not object then return false end
    if not object.IsObjectType then return false end
    if not (object:IsObjectType("Button") or object:IsObjectType("button")) then return false end
    local hasClick = object:GetScript("OnClick")  ~= nil
    local hasEnter = object:GetScript("OnEnter")  ~= nil
    local hasLeave = object:GetScript("OnLeave")  ~= nil
    local ok, movable = pcall(function() return object:IsMovable() end)
    local hasDrag = object:GetScript("OnDragStart") ~= nil or (ok and movable)
    return hasClick and hasEnter and hasLeave and hasDrag
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Scanning
-- ─────────────────────────────────────────────────────────────────────────────

local function OFA_SetupButton(button)
    local id = OFA_GetOrCreateID(button)
    OFA_Scanned[id] = true
    OneForAll_SetupDragAndDropButton(button)
    if not OFA_IsExcluded(id) then
        OneForAll_IncludeButton(button)
    else
        local libName, isLib = OFA_IsLibDBIconButton(id)
        if isLib then
            -- LibDBIcon buttons: just let LibDBIcon place them on the circumference
            -- using their saved minimapPos. No position locking needed.
            table.insert(OFA_PendingPositions, id)
        else
            -- Non-LibDBIcon buttons: lock position and restore from savedPositions
            local sp = OFA_SavedPositions[id]
            if sp then
                local btn = OFA_GetFrame(id)
                if btn then
                    btn.OFA_PositionLocked  = true
                    btn.OFA_OrigSetPoint    = btn.SetPoint
                    btn.OFA_OrigClearPoints = btn.ClearAllPoints
                    btn.SetPoint = function(self, ...)
                        if self.OFA_PositionLocked then return end
                        self.OFA_OrigSetPoint(self, ...)
                    end
                    btn.ClearAllPoints = function(self)
                        if self.OFA_PositionLocked then return end
                        self.OFA_OrigClearPoints(self)
                    end
                end
                table.insert(OFA_PendingPositions, id)
            end
        end
    end
end

function OneForAll_ScanLibraryButtons()
    if not OneForAll_LibDBIcon then return end
    local buttons = OneForAll_LibDBIcon:GetButtonList()
    if not buttons then return end
    for _, name in ipairs(buttons) do
        local button = OneForAll_LibDBIcon:GetMinimapButton(name)
        local id     = OneForAll_ButtonPrefix .. name
        if button and not OFA_IsScanned(id) and not OFA_IsIgnored(id) then
            OFA_FrameToID[button] = id
            OFA_IDToFrame[id]     = button
            OFA_SetupButton(button)
        end
    end
end

function OneForAll_ScanNonLibraryButtons()
    local children = { Minimap:GetChildren() }
    for _, child in ipairs(children) do
        local id = OFA_GetOrCreateID(child)
        if not OFA_IsScanned(id) and not OFA_IsIgnored(id) and OFA_IsMinimapButton(child) then
            OFA_SetupButton(child)
        end
    end
end

function OneForAll_ScanButtons()
    OneForAll_ScanLibraryButtons()
    OneForAll_ScanNonLibraryButtons()
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Saved Variables
-- ─────────────────────────────────────────────────────────────────────────────

function OneForAll_LoadDatabase()
    OneForAll_Database  = OneForAll_Database or {}
    OFA_Excluded        = OneForAll_Database["excludedButtons"] or {}
    OFA_SavedPositions  = OneForAll_Database["savedPositions"]  or {}
end

function OneForAll_SaveDatabase()
    OneForAll_Database["excludedButtons"] = OFA_Excluded
    OneForAll_Database["savedPositions"]  = OFA_SavedPositions
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Events
-- ─────────────────────────────────────────────────────────────────────────────

function OneForAll_Events:ADDON_LOADED(addonName)
    if addonName ~= OneForAll_Name then return end
    OneForAll_LoadDatabase()
    local minimapIcon = OneForAll_LibDataBroker:NewDataObject(OneForAll_Name, {
        type          = "data source",
        text          = "One For All",
        icon          = "Interface\\AddOns\\OneForAll\\OneForAll.png",
        OnClick       = OneForAll_OnClick,
        OnTooltipShow = OneForAll_OnTooltipShow,
    })
    OneForAll_LibDBIcon:Register(OneForAll_Name, minimapIcon, OneForAll_Database)
    OneForAll_MinimapIcon = OneForAll_LibDBIcon:GetMinimapButton(OneForAll_Name)
end

function OneForAll_Events:PLAYER_LOGIN()
    OneForAll_ScanButtons()
end

function OneForAll_Events:PLAYER_ENTERING_WORLD()
    if not OFA_PendingPositions or #OFA_PendingPositions == 0 then return end
    for _, id in ipairs(OFA_PendingPositions) do
        local libName, isLib = OFA_IsLibDBIconButton(id)
        if isLib then
            -- LibDBIcon buttons: use Refresh() to place on minimap circumference
            OneForAll_LibDBIcon:Refresh(libName)
            -- Unlock position if it was locked
            local btn = OFA_GetFrame(id)
            if btn and btn.OFA_PositionLocked then
                btn.OFA_PositionLocked = false
                if btn.OFA_OrigSetPoint    then btn.SetPoint       = btn.OFA_OrigSetPoint    end
                if btn.OFA_OrigClearPoints then btn.ClearAllPoints = btn.OFA_OrigClearPoints end
                btn.OFA_OrigSetPoint    = nil
                btn.OFA_OrigClearPoints = nil
            end
        else
            -- Non-LibDBIcon buttons: restore from saved pixel coordinates
            local btn = OFA_GetFrame(id)
            local sp  = OFA_SavedPositions[id]
            if btn and sp then
                local relTo = (sp[2] == "UIParent") and UIParent or _G[sp[2]] or UIParent
                if btn.OFA_OrigClearPoints then btn.OFA_OrigClearPoints(btn) end
                if btn.OFA_OrigSetPoint then
                    btn.OFA_OrigSetPoint(btn, sp[1], relTo, sp[3], sp[4], sp[5])
                end
            end
        end
    end
    OFA_PendingPositions = {}
end

function OneForAll_Events:PLAYER_LOGOUT()
    OneForAll_SaveDatabase()
end

-- ─────────────────────────────────────────────────────────────────────────────
-- LibDBIcon callback
-- ─────────────────────────────────────────────────────────────────────────────

function OneForAll_Callbacks:LibDBIcon_IconCreated(button, name)
    local id = OneForAll_ButtonPrefix .. name
    if not OFA_IsScanned(id) and not OFA_IsIgnored(id) then
        OFA_FrameToID[button] = id
        OFA_IDToFrame[id]     = button
        OFA_SetupButton(button)
    end
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Bootstrap
-- ─────────────────────────────────────────────────────────────────────────────

OneForAll_OnLoad()
