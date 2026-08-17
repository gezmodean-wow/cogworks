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
--
-- ---------------------------------------------------------------------------
-- Pooling (COG-81)
-- ---------------------------------------------------------------------------
-- WoW frames cannot be destroyed. This primitive used to CreateFrame on every
-- ShowLoading call — a banner plus five child frames — and Hide() only hid
-- them, so every call leaked its whole frame tree for the session. That was
-- tolerable while ShowLoading marked rare, explicit work; it stopped being
-- tolerable when FlipQueue routed every generator filter toggle and priority
-- reorder through it, minting a frame tree per interaction.
--
-- Banners are now built once and recycled. The frame tree is constructed by
-- createBanner and configured per acquire; Hide() returns the record to
-- lib._loadingPool instead of orphaning it. The name counter still increments,
-- but only when a genuinely new frame is minted, so global names stay unique
-- and stable per pooled frame (UISpecialFrames needs a stable name).
--
-- Two hazards this has to respect, both load-bearing:
--
--   * Stale handles. Callers legitimately hold a handle across superseded runs
--     (FlipQueue's UI:GenerateTodoListWithLoading reuses one, hiding it only
--     when the whole chain finishes). If a recycled banner were driven by a
--     handle from a previous acquire, one caller would silently puppet another
--     caller's overlay. Every acquire bumps `b.gen` and each handle captures
--     the generation it was issued for; a handle whose generation no longer
--     matches is inert. Hide() therefore stays idempotent, and a late Hide()
--     from a superseded run cannot close a banner that has since been reissued.
--
--   * UISpecialFrames. A pooled frame keeps its name, so it must not be
--     registered twice across acquires — the ESC path would then remove only
--     one entry and leave a dangling name that ESC still tries to close.
--     registerEsc/unregisterEsc are presence-checked on both sides.

local lib = LibStub("Cogworks-1.0")
if not lib then return end

-- Module load guard. See Sections.lua for rationale.
local MODULE_MINOR = 2
lib._modules = lib._modules or {}
if (lib._modules.Loading or 0) >= MODULE_MINOR then return end
lib._modules.Loading = MODULE_MINOR

local NUM_DOTS  = 5
local DOT_SIZE  = 8
local DOT_GAP   = 6
local BANNER_W  = 280
local BANNER_H  = 60

-- Monotonically increasing counter so each banner gets a unique global
-- name (required for UISpecialFrames ESC support). Increments per frame
-- minted, not per ShowLoading call.
lib._loadingCount = lib._loadingCount or 0

-- Free list of banner records available for reuse. Guarded per the stateful-
-- table rule so an older vendored copy re-running this file can't drop frames
-- a newer copy already pooled.
lib._loadingPool = lib._loadingPool or {}

local function clamp01(v)
  if v < 0 then return 0 end
  if v > 1 then return 1 end
  return v
end

local function registerEsc(name)
  for i = 1, #UISpecialFrames do
    if UISpecialFrames[i] == name then return end
  end
  tinsert(UISpecialFrames, name)
end

local function unregisterEsc(name)
  for i = #UISpecialFrames, 1, -1 do
    if UISpecialFrames[i] == name then
      table.remove(UISpecialFrames, i)
      break
    end
  end
end

-- ============================================================================
-- Construction — runs once per pooled banner
-- ============================================================================

local function createBanner(self)
  lib._loadingCount = lib._loadingCount + 1
  local b = { name = "CogworksLoadingOverlay_" .. lib._loadingCount, gen = 0 }
  -- No theme colors are read here: a pooled banner can outlive a theme change,
  -- so every color is applied per-acquire in applyTheme instead.

  -- Dim overlay. Built unconditionally (unlike the pre-pool version, which
  -- only made one for dimBackground callers) so any pooled banner can serve
  -- either kind of request. Hidden unless asked for.
  b.dim = CreateFrame("Frame", nil, UIParent)
  b.dim:EnableMouse(true)  -- swallow clicks through to parent
  b.dimTex = b.dim:CreateTexture(nil, "BACKGROUND")
  b.dimTex:SetAllPoints()
  b.dimTex:SetColorTexture(0, 0, 0, 0.5)
  b.dim:Hide()

  b.banner = CreateFrame("Frame", b.name, UIParent, "BackdropTemplate")
  b.banner:SetSize(BANNER_W, BANNER_H)
  b.banner:SetBackdrop(self.BackdropSmall)

  b.textFs = b.banner:CreateFontString(nil, "OVERLAY")
  b.textFs:SetPoint("TOPLEFT", b.banner, "TOPLEFT", 12, -10)
  b.textFs:SetPoint("TOPRIGHT", b.banner, "TOPRIGHT", -32, -10)
  b.textFs:SetJustifyH("LEFT")
  b.textFs:SetWordWrap(false)

  -- Close X. Also built unconditionally; shown only for cancelable acquires.
  b.closeBtn = CreateFrame("Button", nil, b.banner, "UIPanelCloseButton")
  b.closeBtn:SetSize(20, 20)
  b.closeBtn:SetPoint("TOPRIGHT", b.banner, "TOPRIGHT", -2, -2)
  b.closeBtn:Hide()

  -- ---- Indeterminate dots ----------------------------------------------
  b.dotsFrame = CreateFrame("Frame", nil, b.banner)
  b.dotsFrame:SetHeight(12)
  b.dotsFrame:SetPoint("BOTTOMLEFT",  b.banner, "BOTTOMLEFT",  12, 12)
  b.dotsFrame:SetPoint("BOTTOMRIGHT", b.banner, "BOTTOMRIGHT", -12, 12)

  b.dots = {}
  local dotsWidth = NUM_DOTS * DOT_SIZE + (NUM_DOTS - 1) * DOT_GAP
  for i = 1, NUM_DOTS do
    local dot = b.dotsFrame:CreateTexture(nil, "ARTWORK")
    dot:SetSize(DOT_SIZE, DOT_SIZE)
    local x = -dotsWidth / 2 + (i - 1) * (DOT_SIZE + DOT_GAP) + DOT_SIZE / 2
    dot:SetPoint("CENTER", b.dotsFrame, "CENTER", x, 0)
    b.dots[i] = dot
  end

  local phase = 0
  b.indetTicker = CreateFrame("Frame", nil, b.banner)
  b.indetTicker:SetScript("OnUpdate", function(_, elapsed)
    phase = (phase + elapsed * 2.5) % (math.pi * 2)
    for i, dot in ipairs(b.dots) do
      local p = math.sin(phase - (i - 1) * 0.5)
      dot:SetAlpha(0.30 + 0.70 * (p * 0.5 + 0.5))
    end
  end)

  -- ---- Determinate bar --------------------------------------------------
  b.bar = CreateFrame("StatusBar", nil, b.banner, "BackdropTemplate")
  b.bar:SetHeight(14)
  b.bar:SetPoint("BOTTOMLEFT",  b.banner, "BOTTOMLEFT",  12, 12)
  b.bar:SetPoint("BOTTOMRIGHT", b.banner, "BOTTOMRIGHT", -52, 12)
  b.bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
  b.bar:SetMinMaxValues(0, 1)
  b.bar:SetValue(0)
  b.bar:SetBackdrop({
    edgeFile = "Interface\\Buttons\\WHITE8x8",
    edgeSize = 1,
  })
  b.barBg = b.bar:CreateTexture(nil, "BACKGROUND")
  b.barBg:SetAllPoints()
  b.bar:Hide()

  b.pctFs = b.banner:CreateFontString(nil, "OVERLAY")
  b.pctFs:SetPoint("LEFT", b.bar, "RIGHT", 6, 0)
  b.pctFs:SetText("")
  b.pctFs:Hide()

  -- Return the banner to the pool. Defined here rather than per-acquire so the
  -- scripts below can reference it unconditionally; it closes over `b` only,
  -- and `b` carries everything acquire-specific.
  function b.release()
    if b.hidden then return end
    b.hidden = true          -- set before Hide() so OnHide sees a dismissal in progress
    b.indetTicker:Hide()
    b.banner:Hide()
    b.dim:Hide()
    unregisterEsc(b.name)
    b.onCancel = nil
    b.banner:SetParent(UIParent)
    b.dim:SetParent(UIParent)
    lib._loadingPool[#lib._loadingPool + 1] = b
  end

  -- Cancel paths. Installed once and dispatched through the record, never
  -- through per-acquire upvalues — the scripts outlive any single acquire.
  b.closeBtn:SetScript("OnClick", function()
    if b.hidden then return end
    local onCancel = b.onCancel
    b.release()
    if onCancel then onCancel() end
  end)

  -- ESC path: UISpecialFrames calls banner:Hide() directly, so OnHide is the
  -- only signal. b.hidden is set before banner:Hide() on the programmatic
  -- path, so this fires onCancel exactly once and only for a real dismissal.
  b.banner:SetScript("OnHide", function()
    if b.hidden then return end
    local onCancel = b.onCancel
    b.release()
    if onCancel then onCancel() end
  end)

  return b
end

-- ============================================================================
-- Theme + per-acquire configuration
-- ============================================================================

-- Colors are re-applied on every acquire: a pooled banner can outlive a theme
-- change, and painting at construction time only would leave it stale.
local function applyTheme(self, b)
  local T = self.Theme
  b.banner:SetBackdropColor(unpack(T.bg))
  b.banner:SetBackdropBorderColor(unpack(T.border))
  b.textFs:SetFontObject(self:GetFont("normal") or "GameFontNormal")
  b.textFs:SetTextColor(unpack(T.text))
  b.pctFs:SetFontObject(self:GetFont("small") or "GameFontDisableSmall")
  b.pctFs:SetTextColor(unpack(T.textDim))
  b.bar:SetStatusBarColor(unpack(T.brass))
  b.bar:SetBackdropBorderColor(unpack(T.border))
  b.barBg:SetColorTexture(T.bgDark[1], T.bgDark[2], T.bgDark[3], 0.85)
  for _, dot in ipairs(b.dots) do
    dot:SetColorTexture(unpack(T.gold))
  end
end

local function setIndeterminate(b)
  if b.mode == "indeterminate" then return end
  b.mode = "indeterminate"
  b.bar:Hide()
  b.pctFs:Hide()
  b.dotsFrame:Show()
  b.indetTicker:Show()
end

local function setDeterminate(b)
  if b.mode == "determinate" then return end
  b.mode = "determinate"
  b.dotsFrame:Hide()
  b.indetTicker:Hide()
  b.bar:Show()
  b.pctFs:Show()
end

function lib:ShowLoading(parent, opts)
  opts = opts or {}
  parent = parent or UIParent

  local b = table.remove(lib._loadingPool) or createBanner(self)

  -- New generation: any handle issued for a previous acquire goes inert here.
  b.gen      = b.gen + 1
  b.hidden   = false
  b.mode     = nil
  b.onCancel = opts.onCancel
  b.cancelable = opts.cancelable and true or false

  applyTheme(self, b)

  -- Re-parent and re-anchor. Anchors captured at construction still reference
  -- the old parent, so they have to be cleared and re-set, not just adjusted.
  local strata = parent:GetFrameStrata() or "DIALOG"
  local level  = parent:GetFrameLevel() or 0

  b.banner:SetParent(parent)
  b.banner:ClearAllPoints()
  b.banner:SetPoint("CENTER", parent, "CENTER", 0, 0)
  b.banner:SetFrameStrata(strata)
  b.banner:SetFrameLevel(level + 50)

  b.dimUsed = opts.dimBackground and true or false
  if b.dimUsed then
    b.dim:SetParent(parent)
    b.dim:ClearAllPoints()
    b.dim:SetAllPoints(parent)
    b.dim:SetFrameStrata(strata)
    b.dim:SetFrameLevel(level + 40)
    b.dim:Show()
  else
    b.dim:Hide()
  end

  b.textFs:SetText(opts.text or "Loading…")

  if b.cancelable then
    b.closeBtn:Show()
    registerEsc(b.name)
  else
    b.closeBtn:Hide()
    unregisterEsc(b.name)
  end

  if type(opts.progress) == "number" then
    setDeterminate(b)
    local v = clamp01(opts.progress)
    b.bar:SetValue(v)
    b.pctFs:SetText(math.floor(v * 100 + 0.5) .. "%")
  else
    setIndeterminate(b)
    b.bar:SetValue(0)
    b.pctFs:SetText("")
  end

  b.banner:Show()

  -- ---- Handle ----------------------------------------------------------
  -- Fresh table per acquire (cheap — it holds no frames). `myGen` is what
  -- makes a superseded caller's handle harmless rather than dangerous.
  local myGen = b.gen
  local handle = { banner = b.banner, dim = b.dimUsed and b.dim or nil }

  local function live()
    return b.gen == myGen and not b.hidden
  end

  function handle:SetText(t)
    if not live() then return end
    b.textFs:SetText(t or "")
  end

  function handle:SetProgress(p)
    if not live() then return end
    if p == nil then
      setIndeterminate(b)
      return
    end
    setDeterminate(b)
    local v = clamp01(p)
    b.bar:SetValue(v)
    b.pctFs:SetText(math.floor(v * 100 + 0.5) .. "%")
  end

  function handle:GetProgress()
    if not live() then return nil end
    if b.mode == "determinate" then return b.bar:GetValue() end
    return nil
  end

  function handle:IsShown() return live() end

  -- Idempotent, and inert once this handle's generation has passed.
  function handle:Hide()
    if not live() then return end
    b.release()
  end

  return handle
end
