-- Cogworks-1.0/Loading.lua | Theme-correct async-state overlay primitive.
--
-- `cw:ShowLoading(parent, opts)` returns a handle for a small banner that
-- sits centered on `parent` while async work runs. Two visual modes:
--   * Indeterminate (default): five gold dots that pulse in a wave.
--   * Determinate: a brass status bar with a "NN%" suffix.
-- The handle exposes :SetText / :SetProgress / :Hide; SetProgress(nil)
-- flips back to indeterminate, SetProgress(number) flips to determinate.
-- Hide is idempotent.
--
-- The banner does not block input by default; opts.dimBackground = true
-- dims the parent (matches CreatePopup) and consumes click-through so the
-- page can't be interacted with while the overlay is up.
--
-- Usage:
--
--   local handle = cw:ShowLoading(parent, {
--     text          = "Refreshing prices…",
--     -- progress   = 0,            -- pass a number for determinate
--     cancelable    = false,        -- if true, X button + onCancel + ESC closes
--     onCancel      = function() ... end,
--     dimBackground = false,        -- if true, dim parent (popup-style)
--   })
--   handle:SetProgress(0.4)          -- flips to determinate without flicker
--   handle:SetText("Refreshing prices… 240 of 600")
--   handle:Hide()                    -- caller signals work done (idempotent)
--
--   handle.banner    -- underlying frame (read-only; for re-anchoring etc.)
--   handle.dim       -- dim overlay frame, only present if dimBackground=true
--
-- ESC support requires `cancelable = true`; it uses UISpecialFrames with a
-- generated global name (CogworksLoadingOverlay_N). Multiple banners on
-- the same parent are independent.

local lib = LibStub("Cogworks-1.0")
if not lib then return end

-- Module load guard. See Sections.lua for rationale.
local MODULE_MINOR = 1
lib._modules = lib._modules or {}
if (lib._modules.Loading or 0) >= MODULE_MINOR then return end
lib._modules.Loading = MODULE_MINOR

local NUM_DOTS  = 5
local DOT_SIZE  = 8
local DOT_GAP   = 6
local BANNER_W  = 280
local BANNER_H  = 60

-- Monotonically increasing counter so each banner gets a unique global
-- name (required for UISpecialFrames ESC support).
lib._loadingCount = lib._loadingCount or 0

local function clamp01(v)
  if v < 0 then return 0 end
  if v > 1 then return 1 end
  return v
end

function lib:ShowLoading(parent, opts)
  opts = opts or {}
  parent = parent or UIParent
  local T = self.Theme

  lib._loadingCount = lib._loadingCount + 1
  local name = "CogworksLoadingOverlay_" .. lib._loadingCount

  -- ---- Dim overlay (optional, behind banner) ---------------------------
  local dim
  if opts.dimBackground then
    dim = CreateFrame("Frame", nil, parent)
    dim:SetAllPoints()
    dim:SetFrameStrata(parent:GetFrameStrata() or "DIALOG")
    dim:SetFrameLevel((parent:GetFrameLevel() or 0) + 40)
    dim:EnableMouse(true)  -- swallow clicks through to parent
    local dimTex = dim:CreateTexture(nil, "BACKGROUND")
    dimTex:SetAllPoints()
    dimTex:SetColorTexture(0, 0, 0, 0.5)
  end

  -- ---- Banner ----------------------------------------------------------
  local banner = CreateFrame("Frame", name, parent, "BackdropTemplate")
  banner:SetSize(BANNER_W, BANNER_H)
  banner:SetPoint("CENTER", parent, "CENTER", 0, 0)
  banner:SetBackdrop(self.BackdropSmall)
  banner:SetBackdropColor(unpack(T.bg))
  banner:SetBackdropBorderColor(unpack(T.border))
  banner:SetFrameStrata(parent:GetFrameStrata() or "DIALOG")
  banner:SetFrameLevel((parent:GetFrameLevel() or 0) + 50)

  -- Text label (top row)
  local textFs = banner:CreateFontString(nil, "OVERLAY")
  textFs:SetFontObject(self:GetFont("normal") or "GameFontNormal")
  textFs:SetPoint("TOPLEFT", banner, "TOPLEFT", 12, -10)
  textFs:SetPoint("TOPRIGHT", banner, "TOPRIGHT", -32, -10)
  textFs:SetJustifyH("LEFT")
  textFs:SetWordWrap(false)
  textFs:SetTextColor(unpack(T.text))
  textFs:SetText(opts.text or "Loading…")

  -- Optional close X (top-right)
  local closeBtn
  if opts.cancelable then
    closeBtn = CreateFrame("Button", nil, banner, "UIPanelCloseButton")
    closeBtn:SetSize(20, 20)
    closeBtn:SetPoint("TOPRIGHT", banner, "TOPRIGHT", -2, -2)
  end

  -- ---- Indeterminate dots (bottom row) ---------------------------------
  local dotsFrame = CreateFrame("Frame", nil, banner)
  dotsFrame:SetHeight(12)
  dotsFrame:SetPoint("BOTTOMLEFT",  banner, "BOTTOMLEFT",  12, 12)
  dotsFrame:SetPoint("BOTTOMRIGHT", banner, "BOTTOMRIGHT", -12, 12)

  local dots, dotsWidth = {}, NUM_DOTS * DOT_SIZE + (NUM_DOTS - 1) * DOT_GAP
  for i = 1, NUM_DOTS do
    local dot = dotsFrame:CreateTexture(nil, "ARTWORK")
    dot:SetSize(DOT_SIZE, DOT_SIZE)
    local x = -dotsWidth / 2 + (i - 1) * (DOT_SIZE + DOT_GAP) + DOT_SIZE / 2
    dot:SetPoint("CENTER", dotsFrame, "CENTER", x, 0)
    dot:SetColorTexture(unpack(T.gold))
    dots[i] = dot
  end

  local phase = 0
  local indetTicker = CreateFrame("Frame", nil, banner)
  indetTicker:SetScript("OnUpdate", function(_, elapsed)
    phase = (phase + elapsed * 2.5) % (math.pi * 2)
    for i, dot in ipairs(dots) do
      local p = math.sin(phase - (i - 1) * 0.5)
      dot:SetAlpha(0.30 + 0.70 * (p * 0.5 + 0.5))
    end
  end)

  -- ---- Determinate bar (bottom row, swapped in by SetProgress) ---------
  local bar = CreateFrame("StatusBar", nil, banner, "BackdropTemplate")
  bar:SetHeight(14)
  bar:SetPoint("BOTTOMLEFT",  banner, "BOTTOMLEFT",  12, 12)
  bar:SetPoint("BOTTOMRIGHT", banner, "BOTTOMRIGHT", -52, 12)
  bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
  bar:SetStatusBarColor(unpack(T.brass))
  bar:SetMinMaxValues(0, 1)
  bar:SetValue(0)
  bar:SetBackdrop({
    edgeFile = "Interface\\Buttons\\WHITE8x8",
    edgeSize = 1,
  })
  bar:SetBackdropBorderColor(unpack(T.border))
  local barBg = bar:CreateTexture(nil, "BACKGROUND")
  barBg:SetAllPoints()
  barBg:SetColorTexture(T.bgDark[1], T.bgDark[2], T.bgDark[3], 0.85)
  bar:Hide()

  local pctFs = banner:CreateFontString(nil, "OVERLAY")
  pctFs:SetFontObject(self:GetFont("small") or "GameFontDisableSmall")
  pctFs:SetPoint("LEFT", bar, "RIGHT", 6, 0)
  pctFs:SetTextColor(unpack(T.textDim))
  pctFs:SetText("")
  pctFs:Hide()

  -- ---- Mode switching --------------------------------------------------
  local mode  -- "indeterminate" | "determinate"

  local function setIndeterminate()
    if mode == "indeterminate" then return end
    mode = "indeterminate"
    bar:Hide()
    pctFs:Hide()
    dotsFrame:Show()
    indetTicker:Show()
  end

  local function setDeterminate()
    if mode == "determinate" then return end
    mode = "determinate"
    dotsFrame:Hide()
    indetTicker:Hide()
    bar:Show()
    pctFs:Show()
  end

  if type(opts.progress) == "number" then
    setDeterminate()
    local v = clamp01(opts.progress)
    bar:SetValue(v)
    pctFs:SetText(math.floor(v * 100 + 0.5) .. "%")
  else
    setIndeterminate()
  end

  -- ---- ESC support -----------------------------------------------------
  if opts.cancelable then
    tinsert(UISpecialFrames, name)
  end

  -- ---- Handle ----------------------------------------------------------
  local handle = { banner = banner, dim = dim }
  local hidden = false

  function handle:SetText(t)
    if hidden then return end
    textFs:SetText(t or "")
  end

  function handle:SetProgress(p)
    if hidden then return end
    if p == nil then
      setIndeterminate()
      return
    end
    setDeterminate()
    local v = clamp01(p)
    bar:SetValue(v)
    pctFs:SetText(math.floor(v * 100 + 0.5) .. "%")
  end

  function handle:GetProgress()
    if mode == "determinate" then return bar:GetValue() end
    return nil
  end

  function handle:IsShown() return not hidden end

  function handle:Hide()
    if hidden then return end
    hidden = true
    indetTicker:Hide()
    banner:Hide()
    if dim then dim:Hide() end
    if opts.cancelable then
      for i = #UISpecialFrames, 1, -1 do
        if UISpecialFrames[i] == name then
          table.remove(UISpecialFrames, i)
          break
        end
      end
    end
  end

  if opts.cancelable then
    closeBtn:SetScript("OnClick", function()
      if hidden then return end
      handle:Hide()
      if opts.onCancel then opts.onCancel() end
    end)
    -- ESC path: UISpecialFrames calls banner:Hide() directly. OnHide fires
    -- onCancel exactly once (the programmatic-Hide path sets `hidden`
    -- before banner:Hide so this branch is skipped).
    banner:SetScript("OnHide", function()
      if hidden then return end
      handle:Hide()
      if opts.onCancel then opts.onCancel() end
    end)
  end

  return handle
end
