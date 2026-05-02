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

local lib = LibStub("Cogworks-1.0")
if not lib then return end

local MODULE_MINOR = 1
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
