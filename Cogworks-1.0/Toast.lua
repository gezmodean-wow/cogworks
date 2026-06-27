-- Cogworks-1.0/Toast.lua | Transient non-modal alerts.
--
-- Toast is for short, ephemeral feedback that doesn't belong in chat:
-- "Posted 12 items", "Snapshot saved", "Sale logged: <item>". Stacks
-- vertically when several fire close together; auto-dismisses after a
-- short duration; tinted by severity from the suite theme.
--
-- Usage:
--
--   cw:Toast({
--     text     = "Posted 12 items for ~84g",
--     severity = "success",                          -- "success" | "warning" | "error" | "info"
--     duration = 4,                                  -- seconds; nil → 3
--     icon     = "Interface\\Icons\\INV_Misc_Coin_01",
--     onClick  = function() UI:Toggle() end,
--   })
--
--   cw:ClearToasts()                                 -- dismiss all live toasts
--
-- Anchor: toasts stack from the top-right of UIParent by default. Override
-- via cw:SetSetting("toastAnchor", { point = ..., relPoint = ..., x = ..., y = ... }).
--
-- Drag-to-move (COG-79): let the player place toasts directly on screen.
--   cw:EnterToastMoveMode()   -- shows a draggable ghost + a sample follower
--   cw:ExitToastMoveMode()    -- hides them
--   cw:IsToastMoveMode()      -- bool
--   cw:ResetToastAnchor()     -- clear the override → default TOPRIGHT
-- The ghost snaps to the nearest screen corner on release and persists the
-- result through cw:SetSetting("toastAnchor", ...), so live toasts and the next
-- /reload both respect it. The standard entry point is the suite Appearance tab
-- (a "Move toasts on screen" button), but the API is public for direct use too.

local lib = LibStub("Cogworks-1.0")
if not lib then return end

local MODULE_MINOR = 2
lib._modules = lib._modules or {}
if (lib._modules.Toast or 0) >= MODULE_MINOR then return end
lib._modules.Toast = MODULE_MINOR

local DEFAULT_DURATION = 3
local FADE_IN          = 0.18
local FADE_OUT         = 0.4
local TOAST_W          = 280
local TOAST_H          = 48
local TOAST_GAP        = 6

lib._toasts     = lib._toasts     or {}     -- live toast frames (top-down)
lib._toastPool  = lib._toastPool  or {}     -- recycled hidden frames

local SEVERITY_TINT = {
  success = { borderKey = "success", iconTint = "success" },
  info    = { borderKey = "arcane",  iconTint = "arcane"  },
  warning = { borderKey = "warning", iconTint = "warning" },
  error   = { borderKey = "error",   iconTint = "error"   },
}

local function getAnchor()
  local s = lib:GetSetting("toastAnchor")
  if type(s) == "table" then return s end
  return { point = "TOPRIGHT", relPoint = "TOPRIGHT", x = -16, y = -120 }
end

local function relayout()
  local anchor = getAnchor()
  local y = anchor.y or -120
  local stride = TOAST_H + TOAST_GAP
  -- Stack downward when anchored at the top; upward when anchored at the bottom.
  local goingDown = (anchor.point or "TOPRIGHT"):find("TOP") ~= nil
  for i, t in ipairs(lib._toasts) do
    t:ClearAllPoints()
    local off = (i - 1) * stride
    if goingDown then
      t:SetPoint(anchor.point, UIParent, anchor.relPoint or anchor.point,
                 anchor.x or 0, y - off)
    else
      t:SetPoint(anchor.point, UIParent, anchor.relPoint or anchor.point,
                 anchor.x or 0, y + off)
    end
  end
end

local function release(toast)
  toast:Hide()
  for i, t in ipairs(lib._toasts) do
    if t == toast then table.remove(lib._toasts, i); break end
  end
  lib._toastPool[#lib._toastPool + 1] = toast
  relayout()
end

local function dismissAfter(toast, duration)
  -- Cancel any pending dismiss
  if toast._dismissTimer then toast._dismissTimer:Cancel() end
  toast._dismissTimer = C_Timer.NewTimer(duration, function()
    if not toast:IsShown() then return end
    -- Fade-out animation, then release.
    if toast._fadeOut then
      toast._fadeOut:Stop()
      toast._fadeOut:Play()
    else
      release(toast)
    end
  end)
end

local function buildToast()
  local T = lib.Theme
  local f = CreateFrame("Button", nil, UIParent, "BackdropTemplate")
  f:SetSize(TOAST_W, TOAST_H)
  f:SetFrameStrata("FULLSCREEN_DIALOG")
  f:SetBackdrop(lib.BackdropSmall)
  f:SetBackdropColor(T.bg[1], T.bg[2], T.bg[3], 0.95)

  f.icon = f:CreateTexture(nil, "ARTWORK")
  f.icon:SetSize(28, 28)
  f.icon:SetPoint("LEFT", f, "LEFT", 8, 0)

  f.title = f:CreateFontString(nil, "OVERLAY")
  f.title:SetFontObject(lib:GetFont("normal"))
  f.title:SetPoint("TOPLEFT",     f, "TOPLEFT",     44, -6)
  f.title:SetPoint("TOPRIGHT",    f, "TOPRIGHT",    -8, -6)
  f.title:SetJustifyH("LEFT")
  f.title:SetWordWrap(true)
  f.title:SetMaxLines(2)

  -- Fade-in / fade-out animation groups
  local fadeIn  = f:CreateAnimationGroup()
  local fi      = fadeIn:CreateAnimation("Alpha")
  fi:SetFromAlpha(0); fi:SetToAlpha(1); fi:SetDuration(FADE_IN); fi:SetSmoothing("OUT")
  fadeIn:SetScript("OnFinished", function() f:SetAlpha(1) end)
  f._fadeIn = fadeIn

  local fadeOut = f:CreateAnimationGroup()
  local fo      = fadeOut:CreateAnimation("Alpha")
  fo:SetFromAlpha(1); fo:SetToAlpha(0); fo:SetDuration(FADE_OUT); fo:SetSmoothing("IN")
  fadeOut:SetScript("OnFinished", function() release(f) end)
  f._fadeOut = fadeOut

  -- Click-to-dismiss; if onClick handler set, fire it first
  f:SetScript("OnClick", function(self, button)
    if self._onClick then self._onClick(button) end
    if self._fadeOut then self._fadeOut:Stop(); self._fadeOut:Play() end
  end)
  -- Pause auto-dismiss while hovered so users can read longer toasts
  f:SetScript("OnEnter", function(self)
    if self._dismissTimer then self._dismissTimer:Cancel(); self._dismissTimer = nil end
  end)
  f:SetScript("OnLeave", function(self) dismissAfter(self, 1.5) end)

  return f
end

local function acquireToast()
  local f = table.remove(lib._toastPool)
  if f then return f end
  return buildToast()
end

function lib:Toast(opts)
  opts = opts or {}
  assert(type(opts) == "table", "cw:Toast: opts table required")
  local T = self.Theme

  local sev = SEVERITY_TINT[opts.severity or "info"] or SEVERITY_TINT.info
  local borderColor = T[sev.borderKey] or T.border
  local tint        = T[sev.iconTint]  or T.gold

  local f = acquireToast()
  f:SetBackdropBorderColor(borderColor[1], borderColor[2], borderColor[3], 1)
  f.title:SetText(opts.text or "")
  f.title:SetTextColor(unpack(T.text))

  if opts.icon then
    f.icon:SetTexture(opts.icon)
    f.icon:SetVertexColor(1, 1, 1, 1)
  else
    f.icon:SetTexture("Interface\\COMMON\\Indicator-Yellow")
    f.icon:SetVertexColor(tint[1], tint[2], tint[3], 1)
  end

  f._onClick = opts.onClick

  -- Insert at top of stack and re-layout
  table.insert(self._toasts, 1, f)
  f:SetAlpha(0)
  f:Show()
  relayout()
  if f._fadeIn then f._fadeIn:Stop(); f._fadeIn:Play() end

  dismissAfter(f, opts.duration or DEFAULT_DURATION)
  return f
end

function lib:ClearToasts()
  for i = #self._toasts, 1, -1 do
    release(self._toasts[i])
  end
end

-- ============================================================================
-- Drag-to-move mode (COG-79)
-- ============================================================================

local function stackingDown(point)
  return (point or "TOPRIGHT"):find("TOP") ~= nil
end

-- Resolve a frame's current screen rect to an anchor {point, relPoint, x, y},
-- snapping point/relPoint to the nearest screen corner so stacking stays sane.
-- x/y are the residual offset from that UIParent corner to the frame's matching
-- corner (both share UIParent's coordinate space).
local function resolveAnchorFromFrame(frame)
  local pw, ph = UIParent:GetWidth(), UIParent:GetHeight()
  local gl, gb = frame:GetLeft() or 0, frame:GetBottom() or 0
  local gw, gh = frame:GetWidth(), frame:GetHeight()
  local isTop   = (gb + gh / 2) >= ph / 2
  local isRight = (gl + gw / 2) >= pw / 2
  local point   = (isTop and "TOP" or "BOTTOM") .. (isRight and "RIGHT" or "LEFT")
  local x = isRight and ((gl + gw) - pw) or gl
  local y = isTop   and ((gb + gh) - ph) or gb
  return { point = point, relPoint = point, x = x, y = y }
end

local function reanchor(frame, a)
  frame:ClearAllPoints()
  frame:SetPoint(a.point, UIParent, a.relPoint or a.point, a.x or 0, a.y or 0)
end

local function buildMoveGhost()
  local T = lib.Theme

  -- Sample follower toast: shows where the next toast would stack.
  local sample = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
  sample:SetSize(TOAST_W, TOAST_H)
  sample:SetFrameStrata("FULLSCREEN_DIALOG")
  sample:SetBackdrop(lib.BackdropSmall)
  sample:SetBackdropColor(T.bg[1], T.bg[2], T.bg[3], 0.75)
  sample:SetBackdropBorderColor(T.border[1], T.border[2], T.border[3], 1)
  sample.icon = sample:CreateTexture(nil, "ARTWORK")
  sample.icon:SetSize(28, 28)
  sample.icon:SetPoint("LEFT", sample, "LEFT", 8, 0)
  sample.icon:SetTexture("Interface\\COMMON\\Indicator-Yellow")
  sample.icon:SetVertexColor(T.gold[1], T.gold[2], T.gold[3], 1)
  sample.title = sample:CreateFontString(nil, "OVERLAY")
  sample.title:SetFontObject(lib:GetFont("small"))
  sample.title:SetPoint("LEFT", sample, "LEFT", 44, 0)
  sample.title:SetText("Sample toast")
  sample.title:SetTextColor(unpack(T.textDim))

  -- Draggable ghost (the thing the player grabs).
  local g = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
  g:SetSize(TOAST_W, TOAST_H)
  g:SetFrameStrata("TOOLTIP")            -- above FULLSCREEN_DIALOG toasts
  g:SetBackdrop(lib.BackdropSmall)
  g:SetBackdropColor(T.bg[1], T.bg[2], T.bg[3], 0.95)
  g:SetBackdropBorderColor(T.gold[1], T.gold[2], T.gold[3], 1)
  g:SetMovable(true); g:EnableMouse(true); g:RegisterForDrag("LeftButton")
  g:SetClampedToScreen(true)
  g._sample = sample

  g.title = g:CreateFontString(nil, "OVERLAY")
  g.title:SetFontObject(lib:GetFont("normal"))
  g.title:SetPoint("TOPLEFT",  g, "TOPLEFT",  10, -6)
  g.title:SetPoint("TOPRIGHT", g, "TOPRIGHT", -24, -6)
  g.title:SetJustifyH("LEFT")
  g.title:SetText("Drag to move toasts")
  g.title:SetTextColor(unpack(T.gold))

  g.hint = g:CreateFontString(nil, "OVERLAY")
  g.hint:SetFontObject(lib:GetFont("small"))
  g.hint:SetPoint("BOTTOMLEFT", g, "BOTTOMLEFT", 10, 6)
  g.hint:SetText("Release near a screen corner")
  g.hint:SetTextColor(unpack(T.textDim))

  local close = CreateFrame("Button", nil, g, "UIPanelCloseButton")
  close:SetSize(20, 20)
  close:SetPoint("TOPRIGHT", g, "TOPRIGHT", -2, -2)
  close:SetScript("OnClick", function() lib:ExitToastMoveMode() end)

  local function placeSample()
    local a = resolveAnchorFromFrame(g)
    sample:ClearAllPoints()
    if stackingDown(a.point) then
      sample:SetPoint("TOP", g, "BOTTOM", 0, -TOAST_GAP)
    else
      sample:SetPoint("BOTTOM", g, "TOP", 0, TOAST_GAP)
    end
  end
  g._placeSample = placeSample

  g:SetScript("OnDragStart", function(self) self._moving = true;  self:StartMoving() end)
  g:SetScript("OnUpdate",    function(self) if self._moving then placeSample() end end)
  g:SetScript("OnDragStop",  function(self)
    self._moving = false
    self:StopMovingOrSizing()
    local a = resolveAnchorFromFrame(self)
    lib:SetSetting("toastAnchor", a)   -- persists; relayout() picks it up live
    reanchor(self, a)                  -- normalize ghost to the snapped corner
    placeSample()
    relayout()
  end)

  return g
end

function lib:EnterToastMoveMode()
  self:ClearToasts()
  local g = lib._toastGhost
  if not g then g = buildMoveGhost(); lib._toastGhost = g end
  reanchor(g, getAnchor())
  g:Show()
  g._sample:Show()
  g._placeSample()
end

function lib:ExitToastMoveMode()
  local g = lib._toastGhost
  if not g then return end
  g._moving = false
  g:Hide()
  if g._sample then g._sample:Hide() end
end

function lib:IsToastMoveMode()
  return (lib._toastGhost and lib._toastGhost:IsShown()) or false
end

function lib:ResetToastAnchor()
  self:SetSetting("toastAnchor", nil)   -- clear override → default TOPRIGHT
  local g = lib._toastGhost
  if g and g:IsShown() then
    reanchor(g, getAnchor())
    g._placeSample()
  end
  relayout()
end
