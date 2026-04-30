-- Cogworks-1.0/MiniView.lua | Heads-up mini display frame.
--
-- Draggable, resizable, persistable mini frame with the suite's standard
-- chrome (title bar with title text + pin + close, body content area,
-- bottom-right resize grip). Each consumer cog gets one or more mini
-- views — FlipQueue's pending-deals heads-up, Tempo's reset timer,
-- Tally's running net-worth, Maxcraft's profession progress — and they
-- all share one set of behaviours so users see consistent move/resize/
-- pin semantics across the suite.
--
-- Persistence: caller hands in a savedvars table; the mini view writes
-- position, size, and pinned state to it. Subsequent :Show() reads back.
-- The caller's SavedVariables-backed db owns the table; Cogworks just
-- reads / writes its keys.
--
-- Usage:
--
--   local mini = cw:CreateMiniView({
--     name      = "FlipQueueMini",            -- global frame name (unique)
--     title     = "FlipQueue",
--     width     = 220, height = 120,          -- initial defaults
--     minWidth  = 150, minHeight = 80,
--     maxWidth  = 600, maxHeight = 400,
--     savedvars = FlipQueueDB.miniView or {}, -- mutated in place
--     onClose   = function() FlipQueueDB.miniView.shown = false end,
--     onPin     = function(pinned) ... end,
--   })
--   -- populate mini.content however the cog likes
--   local fs = mini.content:CreateFontString(...)
--   ...
--   mini:Show()  -- restores position / size / pin from savedvars
--
--   mini:IsPinned()
--   mini:SetPinned(true)
--
-- The caller is responsible for hiding behaviour: nothing in the lib
-- forces the mini to appear at login. Each cog persists its own
-- "shown" boolean and decides when to restore.

local lib = LibStub("Cogworks-1.0")
if not lib then return end

-- Module load guard. See Sections.lua for rationale.
local MODULE_MINOR = 15
lib._modules = lib._modules or {}
if (lib._modules.MiniView or 0) >= MODULE_MINOR then return end
lib._modules.MiniView = MODULE_MINOR

local TITLEBAR_H     = 22
local GRIP_SIZE      = 14
local DEFAULT_W      = 220
local DEFAULT_H      = 120
local DEFAULT_MIN_W  = 120
local DEFAULT_MIN_H  = 60
local DEFAULT_MAX_W  = 1200
local DEFAULT_MAX_H  = 800

-- Persist current position + size into savedvars. Position is stored as
-- a screen-space (x, y) anchored to UIParent BOTTOMLEFT so the values
-- survive UI scale changes.
local function savePosSize(frame, savedvars)
  local x, y = frame:GetLeft(), frame:GetBottom()
  if x and y then
    savedvars.x = x
    savedvars.y = y
  end
  savedvars.width  = frame:GetWidth()
  savedvars.height = frame:GetHeight()
end

local function restorePosSize(frame, savedvars, defaults)
  local w = savedvars.width  or defaults.width
  local h = savedvars.height or defaults.height
  frame:SetSize(w, h)
  if savedvars.x and savedvars.y then
    frame:ClearAllPoints()
    frame:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", savedvars.x, savedvars.y)
  else
    frame:ClearAllPoints()
    frame:SetPoint("CENTER")
  end
end

function lib:CreateMiniView(opts)
  opts = opts or {}
  assert(opts.name, "CreateMiniView: opts.name required (unique global frame name)")
  assert(type(opts.savedvars) == "table", "CreateMiniView: opts.savedvars table required")
  local T = self.Theme
  local sv = opts.savedvars

  local minW = opts.minWidth  or DEFAULT_MIN_W
  local minH = opts.minHeight or DEFAULT_MIN_H
  local maxW = opts.maxWidth  or DEFAULT_MAX_W
  local maxH = opts.maxHeight or DEFAULT_MAX_H
  local defaults = {
    width  = opts.width  or DEFAULT_W,
    height = opts.height or DEFAULT_H,
  }

  local frame = CreateFrame("Frame", opts.name, UIParent, "BackdropTemplate")
  frame:SetBackdrop(self.Backdrop)
  frame:SetBackdropColor(unpack(T.bg))
  frame:SetBackdropBorderColor(unpack(T.border))
  frame:SetFrameStrata("MEDIUM")
  frame:SetClampedToScreen(true)
  frame:SetMovable(true)
  frame:SetResizable(true)
  if frame.SetResizeBounds then
    frame:SetResizeBounds(minW, minH, maxW, maxH)
  end
  frame:Hide()

  -- ---- Title bar ---------------------------------------------------------
  local titleBar = CreateFrame("Frame", nil, frame)
  titleBar:SetHeight(TITLEBAR_H)
  titleBar:SetPoint("TOPLEFT")
  titleBar:SetPoint("TOPRIGHT")
  titleBar:EnableMouse(true)
  titleBar:RegisterForDrag("LeftButton")

  local titleBg = titleBar:CreateTexture(nil, "BACKGROUND")
  titleBg:SetAllPoints()
  titleBg:SetColorTexture(unpack(T.header))

  local titleText = titleBar:CreateFontString(nil, "OVERLAY")
  titleText:SetFontObject(self:GetFont("normal") or "GameFontNormal")
  titleText:SetPoint("LEFT", titleBar, "LEFT", 8, 0)
  titleText:SetText(opts.title or opts.name)
  titleText:SetTextColor(unpack(T.text))

  local closeBtn = self:CreateIconButton(
    titleBar,
    "Interface\\Buttons\\UI-Panel-MinimizeButton-Up",
    16, "Close", function()
      frame:Hide()
      if opts.onClose then opts.onClose() end
    end)
  closeBtn:SetPoint("RIGHT", titleBar, "RIGHT", -4, 0)

  -- Pin toggle: lock position + hide drag affordance + hide grip.
  local pinBtn = CreateFrame("Button", nil, titleBar)
  pinBtn:SetSize(16, 16)
  pinBtn:SetPoint("RIGHT", closeBtn, "LEFT", -4, 0)

  pinBtn.tex = pinBtn:CreateTexture(nil, "ARTWORK")
  pinBtn.tex:SetAllPoints()
  pinBtn.tex:SetTexture("Interface\\Minimap\\Tracking\\WorldMap")
  pinBtn.highlight = pinBtn:CreateTexture(nil, "HIGHLIGHT")
  pinBtn.highlight:SetAllPoints()
  pinBtn.highlight:SetColorTexture(1, 1, 1, 0.2)

  -- ---- Resize grip (bottom-right) ---------------------------------------
  local grip = CreateFrame("Button", nil, frame)
  grip:SetSize(GRIP_SIZE, GRIP_SIZE)
  grip:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -2, 2)
  grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
  grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
  grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
  grip:RegisterForDrag("LeftButton")
  grip:SetScript("OnDragStart", function() frame:StartSizing("BOTTOMRIGHT") end)
  grip:SetScript("OnDragStop", function()
    frame:StopMovingOrSizing()
    savePosSize(frame, sv)
  end)

  -- ---- Content area ------------------------------------------------------
  local content = CreateFrame("Frame", nil, frame)
  content:SetPoint("TOPLEFT", titleBar, "BOTTOMLEFT", 4, -2)
  content:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -4, 4)
  frame.content = content

  -- ---- Pin behaviour -----------------------------------------------------
  local pinned = sv.pinned and true or false

  local function applyPinVisual()
    if pinned then
      pinBtn.tex:SetVertexColor(unpack(T.gold))
      grip:Hide()
      titleBar:RegisterForDrag()  -- empty list disables drag
    else
      pinBtn.tex:SetVertexColor(unpack(T.textDim))
      grip:Show()
      titleBar:RegisterForDrag("LeftButton")
    end
  end

  function frame:SetPinned(b)
    pinned = b and true or false
    sv.pinned = pinned
    applyPinVisual()
    if opts.onPin then opts.onPin(pinned) end
  end
  function frame:IsPinned() return pinned end

  pinBtn:SetScript("OnClick", function() frame:SetPinned(not pinned) end)
  pinBtn:SetScript("OnEnter", function(b)
    GameTooltip:SetOwner(b, "ANCHOR_BOTTOM")
    GameTooltip:SetText(pinned and "Unpin (allow move/resize)" or "Pin (lock position)", 1, 1, 1)
    GameTooltip:Show()
  end)
  pinBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
  applyPinVisual()

  -- ---- Drag ---------------------------------------------------------------
  titleBar:SetScript("OnDragStart", function() if not pinned then frame:StartMoving() end end)
  titleBar:SetScript("OnDragStop", function()
    frame:StopMovingOrSizing()
    savePosSize(frame, sv)
  end)

  -- ---- UI scale awareness ------------------------------------------------
  local function applyUiScale()
    frame:SetScale(self:GetSetting("uiScale") or 1.0)
  end
  applyUiScale()
  local owner = {}
  self.RegisterCallback(owner, self.Events.SettingsChanged, function(_, key)
    if key == "uiScale" then applyUiScale()
    elseif key == "fontScale" or key == "fontFamily" then
      titleText:SetFontObject(self:GetFont("normal") or "GameFontNormal")
    end
  end)
  frame._reflowOwner = owner

  -- Wrap Show to restore persisted state every time. Hide writes nothing
  -- extra (drag and resize handlers already saved on stop), so consumer
  -- cogs that want to remember "was visible at logout" must persist that
  -- bit themselves.
  hooksecurefunc(frame, "Show", function()
    -- Show is hooked, not overridden — original behaviour runs first.
    -- restorePosSize is a no-op the second time (anchors stay) but harmless.
    restorePosSize(frame, sv, defaults)
  end)
  -- Initial restore so first Show by the caller honours saved geometry.
  restorePosSize(frame, sv, defaults)

  return frame
end
