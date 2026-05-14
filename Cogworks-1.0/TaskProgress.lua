-- Cogworks-1.0/TaskProgress.lua | Dockable long-running task progress widget.
--
-- Two factories share one row implementation:
--
--   * `cw:CreateTaskProgress(parent, opts)` — single-task dockable bar with
--     its own chrome (title bar + close X). Suited to a single long-running
--     job: Tally period synthesis, FlipQueue initial scan, Maxcraft recipe
--     evaluation.
--
--   * `cw:CreateMultiTaskProgress(parent, opts)` — stacked per-source rows
--     inside one panel with shared title + footer. Suited to multi-source
--     imports where each row has its own state / progress / ETA: Tally's
--     "Importing from siblings" controller (TSM CSV + FlipQueue +
--     Journalator) is the v1 driver.
--
-- Distinct from `cw:CreateProgressBar(parent, width, height)`, which is the
-- thin in-table progress cell (no chrome, fixed layout). That primitive
-- stays where it is for inline-in-table use; this module is for the
-- standalone "background work happening" widget. (COG-23, option 2 in the
-- naming-collision triage.)
--
-- Per-row state colours convey at-a-glance status across a multi-row stack:
--   * queued    -> textDim
--   * importing -> brass (default)
--   * done      -> success
--   * error     -> error
--   * skipped   -> textDim dim
--
-- Indeterminate mode: `:Pulse()` switches the row to a 40px-highlight loop
-- across the bar track. Calling `:SetValue(n)` flips back to determinate.
--
-- Single-task usage:
--
--   local prog = cw:CreateTaskProgress(parent, {
--     title      = "Importing TSM",         -- optional chrome title
--     label      = "Reading csvSales",
--     total      = 90128,
--     position   = "bottom-right",          -- or { x, y } anchor offset
--     cancelable = true,
--     onCancel   = function() ... end,
--     savedvars  = ns.db.taskProgressPos,   -- optional; persists x/y
--   })
--   prog:SetValue(47231)
--   prog:SetETA("~3m left")
--   prog:SetLabel("Reading csvSales (47k of 90k)")
--   prog:SetState("done", "47,000 rows imported")
--   prog:Complete()                          -- shows "Done" briefly, fades
--   prog:Hide()                              -- explicit dismiss
--
-- Multi-row usage:
--
--   local panel = cw:CreateMultiTaskProgress(parent, {
--     title = "Importing from siblings",
--     rows  = {
--       { key = "tsm",         label = "TSM Accounting" },
--       { key = "flipqueue",   label = "FlipQueue" },
--       { key = "journalator", label = "Journalator" },
--     },
--   })
--   panel:GetRow("tsm"):SetTotal(47000)
--   panel:GetRow("tsm"):SetValue(12341)
--   panel:GetRow("tsm"):SetETA("3m left")
--   panel:GetRow("flipqueue"):SetState("done", "12,043 imported")
--
-- Row dimensions stay fixed across label/ETA mutations so the stack
-- doesn't jitter mid-import.

local lib = LibStub("Cogworks-1.0")
if not lib then return end

-- Module load guard. See Sections.lua for rationale.
local MODULE_MINOR = 1
lib._modules = lib._modules or {}
if (lib._modules.TaskProgress or 0) >= MODULE_MINOR then return end
lib._modules.TaskProgress = MODULE_MINOR

local DEFAULT_W       = 320
local DEFAULT_ROW_H   = 32   -- label + bar + padding
local TITLE_H         = 22
local PAD             = 8
local BAR_H           = 8
local LABEL_LINE_H    = 14
local PULSE_W         = 40   -- sliding highlight width on indeterminate

-- Each row gets a unique global frame name so cancelable UISpecialFrames
-- registration has something to point at.
lib._taskProgressCount = lib._taskProgressCount or 0

-- ============================================================================
-- Internal: bar-row factory shared by single + multi variants
-- ============================================================================
-- Builds the label + bar + ETA cluster anchored against `host`. Returns a
-- row handle with SetLabel / SetTotal / SetValue / SetETA / SetSuffix /
-- SetState / Pulse / Complete. Does not own its outer frame — the caller
-- positions `row.frame` inside whatever container is appropriate.

local STATE_COLOURS  -- populated lazily from theme so module load doesn't
                     -- run before lib.Theme is wired up. See colourFor below.

local function colourFor(T, state)
  if not STATE_COLOURS then
    STATE_COLOURS = {
      queued    = T.textDim,
      importing = T.brass,
      done      = T.success or T.brass,
      error     = T.error   or T.textDim,
      skipped   = T.textDim,
    }
  end
  return STATE_COLOURS[state] or T.brass
end

local function createBarRow(host, opts)
  opts = opts or {}
  local T = lib.Theme

  local row = CreateFrame("Frame", nil, host)
  row:SetHeight(DEFAULT_ROW_H)

  -- Top line: label (left) + ETA / suffix (right). Width-constrained so
  -- long labels truncate rather than push the suffix off the edge.
  local label = row:CreateFontString(nil, "OVERLAY")
  label:SetFontObject(lib:GetFont("small") or "GameFontHighlightSmall")
  label:SetPoint("TOPLEFT",  row, "TOPLEFT",  0, 0)
  label:SetJustifyH("LEFT")
  label:SetWordWrap(false)
  label:SetTextColor(unpack(T.text))
  label:SetText(opts.label or "")

  local suffix = row:CreateFontString(nil, "OVERLAY")
  suffix:SetFontObject(lib:GetFont("small") or "GameFontDisableSmall")
  suffix:SetPoint("TOPRIGHT", row, "TOPRIGHT", 0, 0)
  suffix:SetJustifyH("RIGHT")
  suffix:SetWordWrap(false)
  suffix:SetTextColor(unpack(T.textDim))

  -- Right-anchor the label so it shares the row with the suffix without
  -- overlap. The suffix's actual width changes when SetETA / SetSuffix
  -- are called, so we re-anchor label's right edge on those updates.
  label:SetPoint("TOPRIGHT", suffix, "TOPLEFT", -6, 0)

  -- Bar track.
  local bar = CreateFrame("Frame", nil, row, "BackdropTemplate")
  bar:SetHeight(BAR_H)
  bar:SetPoint("BOTTOMLEFT",  row, "BOTTOMLEFT",  0, 2)
  bar:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", 0, 2)
  bar:SetBackdrop({
    bgFile   = "Interface\\Buttons\\WHITE8x8",
    edgeFile = "Interface\\Buttons\\WHITE8x8",
    edgeSize = 1,
  })
  bar:SetBackdropColor(T.bgDark and T.bgDark[1] or 0.06,
                       T.bgDark and T.bgDark[2] or 0.06,
                       T.bgDark and T.bgDark[3] or 0.08, 0.95)
  bar:SetBackdropBorderColor(T.border[1], T.border[2], T.border[3], T.border[4] or 1)

  local fill = bar:CreateTexture(nil, "ARTWORK")
  fill:SetPoint("TOPLEFT",     bar, "TOPLEFT",     1, -1)
  fill:SetPoint("BOTTOMLEFT",  bar, "BOTTOMLEFT",  1, 1)
  fill:SetColorTexture(unpack(T.brass))
  fill:SetWidth(0.001)

  -- Indeterminate-mode sliding highlight: hidden until :Pulse() turns it
  -- on. Single 40px-wide texture animates across the bar's interior.
  local pulse = bar:CreateTexture(nil, "OVERLAY")
  pulse:SetSize(PULSE_W, BAR_H - 2)
  pulse:SetColorTexture(T.brass[1], T.brass[2], T.brass[3], 0.65)
  pulse:Hide()

  local pulseTicker = CreateFrame("Frame", nil, bar)
  pulseTicker:Hide()
  local pulsePhase = 0
  pulseTicker:SetScript("OnUpdate", function(_, elapsed)
    pulsePhase = pulsePhase + elapsed
    local travel = math.max(1, bar:GetWidth() - 2 - PULSE_W)
    -- Triangle wave: 0..travel..0 over a 1.6s cycle.
    local t = (pulsePhase % 1.6) / 1.6
    local x = (t < 0.5) and (t * 2 * travel) or ((1 - (t - 0.5) * 2) * travel)
    pulse:ClearAllPoints()
    pulse:SetPoint("LEFT", bar, "LEFT", 1 + x, 0)
  end)

  -- ---- State ------------------------------------------------------------
  local total      = tonumber(opts.total) or 0
  local value      = 0
  local mode       = (total > 0) and "determinate" or "indeterminate"
  local state      = "importing"
  local stateLabel  -- override label when SetState is called with one
  local formatFn   = opts.format  -- optional caller formatter

  local function applyFill()
    if mode ~= "determinate" or total <= 0 then return end
    local frac  = math.max(0, math.min(1, value / total))
    local inner = math.max(0, bar:GetWidth() - 2)
    fill:SetWidth(math.max(0.001, inner * frac))
  end

  local function applyState()
    local rgba = colourFor(T, state)
    fill:SetColorTexture(rgba[1], rgba[2], rgba[3], 1)
    pulse:SetColorTexture(rgba[1], rgba[2], rgba[3], 0.65)
    if state == "skipped" then
      label:SetTextColor(T.textDim[1], T.textDim[2], T.textDim[3], 0.7)
      fill:SetAlpha(0.6)
    else
      label:SetTextColor(unpack(T.text))
      fill:SetAlpha(1.0)
    end
  end
  applyState()

  -- Re-apply fill width when the host width changes (multi-panel resize).
  bar:HookScript("OnSizeChanged", function() applyFill() end)

  -- ---- Handle -----------------------------------------------------------
  local h = { frame = row }

  function h:SetLabel(text)
    label:SetText(text or "")
    return h
  end

  function h:SetTotal(n)
    total = tonumber(n) or 0
    if total > 0 and mode == "indeterminate" then
      mode = "determinate"
      pulse:Hide()
      pulseTicker:Hide()
    end
    if formatFn and mode == "determinate" then
      suffix:SetText(formatFn(value, total) or "")
    end
    applyFill()
    return h
  end

  function h:SetValue(n)
    value = tonumber(n) or 0
    if mode == "indeterminate" and total > 0 then
      mode = "determinate"
      pulse:Hide()
      pulseTicker:Hide()
    end
    if formatFn and mode == "determinate" then
      suffix:SetText(formatFn(value, total) or "")
    end
    applyFill()
    return h
  end

  function h:GetValue() return value end
  function h:GetTotal() return total end

  function h:SetETA(text)
    suffix:SetText(text or "")
    return h
  end

  -- Alias: same slot, different conventional name. ETA is one specific
  -- thing to surface; suffix is the generic version (row count, etc.).
  h.SetSuffix = h.SetETA

  function h:Pulse()
    mode = "indeterminate"
    fill:SetWidth(0.001)
    pulse:Show()
    pulsePhase = 0
    pulseTicker:Show()
    return h
  end

  local function stopPulse()
    if mode == "indeterminate" then
      mode = "determinate"
    end
    pulse:Hide()
    pulseTicker:Hide()
  end

  function h:SetState(s, optLabel)
    state = s or "importing"
    stateLabel = optLabel
    applyState()
    if optLabel then label:SetText(optLabel) end
    if state == "done" or state == "error" or state == "skipped" then
      stopPulse()
      if state == "done" then
        if total > 0 then value = total end
        if total <= 0 then
          -- Terminal "done" with no defined total: show a fully-filled
          -- bar as the visual completion cue.
          local inner = math.max(0, bar:GetWidth() - 2)
          fill:SetWidth(math.max(0.001, inner))
          return h
        end
      end
      applyFill()
    elseif state == "queued" then
      stopPulse()
      fill:SetWidth(0.001)
    end
    return h
  end

  function h:GetState() return state end

  function h:Complete()
    h:SetState("done", stateLabel)
    -- The single-task wrapper handles auto-fade. For a row inside a
    -- multi-panel, completion is a visual state; the panel decides what
    -- (if anything) to do with the whole frame.
    if opts.onComplete then opts.onComplete() end
    return h
  end

  return h
end

-- ============================================================================
-- CreateTaskProgress (single-task widget)
-- ============================================================================

function lib:CreateTaskProgress(parent, opts)
  opts   = opts or {}
  parent = parent or UIParent
  local T = self.Theme

  lib._taskProgressCount = lib._taskProgressCount + 1
  local name = opts.name or ("CogworksTaskProgress_" .. lib._taskProgressCount)

  -- ---- Outer frame ------------------------------------------------------
  local f = CreateFrame("Frame", name, parent, "BackdropTemplate")
  f:SetSize(opts.width or DEFAULT_W,
            TITLE_H + DEFAULT_ROW_H + PAD * 2)
  f:SetBackdrop(self.Backdrop)
  f:SetBackdropColor(unpack(T.bg))
  f:SetBackdropBorderColor(unpack(T.border))
  f:SetFrameStrata(opts.strata or "MEDIUM")
  f:SetMovable(true)
  f:EnableMouse(true)
  f:SetClampedToScreen(true)
  f:RegisterForDrag("LeftButton")

  -- Position: caller-supplied savedvars + opts.position fallback.
  local sv = opts.savedvars
  local function applyPosition()
    f:ClearAllPoints()
    if sv and sv.x and sv.y then
      f:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", sv.x, sv.y)
      return
    end
    local pos = opts.position or "bottom-right"
    if type(pos) == "table" then
      f:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", pos.x or 0, pos.y or 0)
    elseif pos == "bottom-right" then
      f:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -20, 20)
    elseif pos == "bottom-left" then
      f:SetPoint("BOTTOMLEFT", parent, "BOTTOMLEFT", 20, 20)
    elseif pos == "top-right" then
      f:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -20, -20)
    elseif pos == "top-left" then
      f:SetPoint("TOPLEFT", parent, "TOPLEFT", 20, -20)
    else
      f:SetPoint("CENTER")
    end
  end
  applyPosition()

  f:SetScript("OnDragStart", function() f:StartMoving() end)
  f:SetScript("OnDragStop",  function()
    f:StopMovingOrSizing()
    if sv then
      sv.x = f:GetLeft()
      sv.y = f:GetBottom()
    end
  end)

  -- ---- Title bar (title + cancel X) ------------------------------------
  local titleBar = CreateFrame("Frame", nil, f)
  titleBar:SetHeight(TITLE_H)
  titleBar:SetPoint("TOPLEFT",  f, "TOPLEFT",  PAD, -PAD)
  titleBar:SetPoint("TOPRIGHT", f, "TOPRIGHT", -PAD, -PAD)

  local titleFs = titleBar:CreateFontString(nil, "OVERLAY")
  titleFs:SetFontObject(self:GetFont("normal") or "GameFontNormal")
  titleFs:SetPoint("LEFT",  titleBar, "LEFT", 0, 0)
  titleFs:SetPoint("RIGHT", titleBar, "RIGHT", -22, 0)
  titleFs:SetJustifyH("LEFT")
  titleFs:SetWordWrap(false)
  titleFs:SetTextColor(unpack(T.gold))
  titleFs:SetText(opts.title or "Progress")

  local closeBtn
  if opts.cancelable then
    closeBtn = CreateFrame("Button", nil, titleBar, "UIPanelCloseButton")
    closeBtn:SetSize(20, 20)
    closeBtn:SetPoint("RIGHT", titleBar, "RIGHT", 4, 0)
  end

  -- ---- Bar row ----------------------------------------------------------
  local row = createBarRow(f, {
    label  = opts.label,
    total  = opts.total,
    format = opts.format,
  })
  row.frame:SetPoint("TOPLEFT",  titleBar, "BOTTOMLEFT",  0, -PAD)
  row.frame:SetPoint("TOPRIGHT", titleBar, "BOTTOMRIGHT", 0, -PAD)

  -- ---- Handle wraps the row + adds Hide / Complete-with-fade -----------
  local handle = {}
  for k, v in pairs(row) do handle[k] = v end
  handle.frame   = f
  handle.barRow  = row

  -- Override row.frame so handle.frame == outer chrome frame.
  -- Methods still operate on the inner row (closures captured `row` above).

  local hidden = false
  local fader  = CreateFrame("Frame", nil, f)
  fader:Hide()
  local fadeStart, fadeDur = 0, 0
  fader:SetScript("OnUpdate", function(self, _)
    local t = (GetTime() - fadeStart) / fadeDur
    if t >= 1 then
      f:SetAlpha(1)
      f:Hide()
      hidden = true
      self:Hide()
      return
    end
    f:SetAlpha(1 - t)
  end)

  function handle:Hide()
    if hidden then return end
    hidden = true
    f:SetAlpha(1)
    f:Hide()
    fader:Hide()
  end

  function handle:Show()
    hidden = false
    f:SetAlpha(1)
    f:Show()
  end

  function handle:IsShown()
    return f:IsShown() and not hidden
  end

  -- Override Complete to add a 1.5s linger + 0.6s fade after the visual
  -- flips to the "done" state.
  function handle:Complete()
    row:Complete()
    C_Timer.After(1.5, function()
      if hidden or not f:IsShown() then return end
      fadeStart = GetTime()
      fadeDur   = 0.6
      fader:Show()
    end)
    return handle
  end

  function handle:SetTitle(text)
    titleFs:SetText(text or "")
    return handle
  end

  -- Cancel wiring.
  if opts.cancelable and closeBtn then
    closeBtn:SetScript("OnClick", function()
      if hidden then return end
      handle:Hide()
      if opts.onCancel then opts.onCancel() end
    end)
  end

  return handle
end

-- ============================================================================
-- CreateMultiTaskProgress (stacked rows)
-- ============================================================================

function lib:CreateMultiTaskProgress(parent, opts)
  opts   = opts or {}
  parent = parent or UIParent
  assert(type(opts.rows) == "table" and #opts.rows > 0,
    "CreateMultiTaskProgress: opts.rows required (at least one row)")
  local T = self.Theme

  lib._taskProgressCount = lib._taskProgressCount + 1
  local name = opts.name or ("CogworksMultiTaskProgress_" .. lib._taskProgressCount)

  local rowCount = #opts.rows
  local panelH   = TITLE_H + (rowCount * DEFAULT_ROW_H) + ((rowCount - 1) * 6) + PAD * 2

  local f = CreateFrame("Frame", name, parent, "BackdropTemplate")
  f:SetSize(opts.width or DEFAULT_W, panelH)
  f:SetBackdrop(self.Backdrop)
  f:SetBackdropColor(unpack(T.bg))
  f:SetBackdropBorderColor(unpack(T.border))
  f:SetFrameStrata(opts.strata or "MEDIUM")
  f:SetMovable(true)
  f:EnableMouse(true)
  f:SetClampedToScreen(true)
  f:RegisterForDrag("LeftButton")

  local sv = opts.savedvars
  if sv and sv.x and sv.y then
    f:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", sv.x, sv.y)
  else
    f:SetPoint("CENTER")
  end

  f:SetScript("OnDragStart", function() f:StartMoving() end)
  f:SetScript("OnDragStop",  function()
    f:StopMovingOrSizing()
    if sv then
      sv.x = f:GetLeft()
      sv.y = f:GetBottom()
    end
  end)

  -- ---- Title bar --------------------------------------------------------
  local titleBar = CreateFrame("Frame", nil, f)
  titleBar:SetHeight(TITLE_H)
  titleBar:SetPoint("TOPLEFT",  f, "TOPLEFT",  PAD, -PAD)
  titleBar:SetPoint("TOPRIGHT", f, "TOPRIGHT", -PAD, -PAD)

  local titleFs = titleBar:CreateFontString(nil, "OVERLAY")
  titleFs:SetFontObject(self:GetFont("normal") or "GameFontNormal")
  titleFs:SetPoint("LEFT",  titleBar, "LEFT", 0, 0)
  titleFs:SetPoint("RIGHT", titleBar, "RIGHT", opts.cancelable and -22 or 0, 0)
  titleFs:SetJustifyH("LEFT")
  titleFs:SetWordWrap(false)
  titleFs:SetTextColor(unpack(T.gold))
  titleFs:SetText(opts.title or "Tasks")

  if opts.cancelable then
    local closeBtn = CreateFrame("Button", nil, titleBar, "UIPanelCloseButton")
    closeBtn:SetSize(20, 20)
    closeBtn:SetPoint("RIGHT", titleBar, "RIGHT", 4, 0)
    closeBtn:SetScript("OnClick", function()
      f:Hide()
      if opts.onCancel then opts.onCancel() end
    end)
  end

  -- ---- Rows -------------------------------------------------------------
  local rowsByKey = {}
  local rowsByIndex = {}
  local prevAnchor = titleBar
  local prevOffset = -PAD
  for i, rowDef in ipairs(opts.rows) do
    assert(rowDef.key, "CreateMultiTaskProgress: row " .. i .. " missing key")
    local row = createBarRow(f, {
      label  = rowDef.label or rowDef.key,
      total  = rowDef.total,
      format = rowDef.format,
    })
    row.frame:SetPoint("TOPLEFT",  prevAnchor, "BOTTOMLEFT",  0, prevOffset)
    row.frame:SetPoint("TOPRIGHT", prevAnchor, "BOTTOMRIGHT", 0, prevOffset)
    rowsByKey[rowDef.key]  = row
    rowsByIndex[i]         = row
    prevAnchor = row.frame
    prevOffset = -6
  end

  function f:GetRow(key)        return rowsByKey[key]            end
  function f:GetRowByIndex(i)   return rowsByIndex[i]            end
  function f:GetRowCount()      return #rowsByIndex              end
  function f:SetTitle(text)     titleFs:SetText(text or "")      end

  return f
end
