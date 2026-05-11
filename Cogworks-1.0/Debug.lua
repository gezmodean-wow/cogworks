-- Cogworks-1.0/Debug.lua | Per-cog debug toolkit.
--
-- Surfaces (all keyed by cogName so each cog gets its own state):
--   * Logger      — ring buffer + PrintDebug + chat echo gated by enabled flag
--   * Inspectors  — caller-registered named state accessors
--   * Profiler    — Profile(label, fn) timing accumulator
--   * Actions     — button registry consumed by the dashboard widget
--   * Console     — the dashboard widget (status + actions + log + inspector + profile)
--   * CopyDialog  — modal popup with a ctrl+a/c-friendly EditBox for state dumps
--   * LibDebug bridge — lib-side internal debug events route into every cog's
--                       logger so a single console shows both cog + lib activity
--
-- Usage (typical):
--   local logger = cw:RegisterDebugLogger("FlipQueue", { enabled = ns.db.settings.debugMessages })
--   logger:PrintDebug("AutoScan: bucket=" .. tostring(bucket))
--
--   cw:RegisterDebugInspector("FlipQueue", "Tasks", function() return ns.db.todoLists.active.tasks end)
--   cw:RegisterDebugAction("FlipQueue", "Bank popup ×6", function() UI:ShowBankPopup(...) end)
--
--   cw:Profile("FlipQueue", "AuctionPost.PostItem", function() ... end)
--
--   local console = cw:CreateDebugConsole({ cog = "FlipQueue" })
--   console:Show()
--
-- Design note: per-cog state is required because the suite has multiple cogs
-- with overlapping concerns; sharing one ring buffer would mean cog A's noise
-- buries cog B's signal. Lib-side debug events still bridge into every logger
-- so a "what fired across the suite" view falls out naturally.

local lib = LibStub("Cogworks-1.0")
if not lib then return end

local MODULE_MINOR = 2
lib._modules = lib._modules or {}
if (lib._modules.Debug or 0) >= MODULE_MINOR then return end
lib._modules.Debug = MODULE_MINOR

-- ============================================================================
-- Per-cog registry
-- ============================================================================

lib._debug = lib._debug or {}  -- [cogName] = { ring, ringMax, enabled, appendCbs, inspectors, actions, profile, _loggerObj }

local function ensureCog(cogName)
  assert(type(cogName) == "string" and cogName ~= "", "Debug: cogName required")
  local d = lib._debug[cogName]
  if not d then
    d = {
      cog        = cogName,
      ring       = {},
      ringMax    = 500,
      enabled    = false,
      appendCbs  = {},
      inspectors = {},
      actions    = {},
      profile    = {},
    }
    lib._debug[cogName] = d
  end
  return d
end

local function joinArgs(...)
  local n = select("#", ...)
  if n == 0 then return "" end
  local parts = {}
  for i = 1, n do parts[i] = tostring((select(i, ...))) end
  return table.concat(parts, " ")
end

local function fireAppend(d)
  for _, cb in ipairs(d.appendCbs) do
    local ok, err = pcall(cb)
    if not ok and geterrorhandler then geterrorhandler()(err) end
  end
end

local function appendEntry(d, line)
  d.ring[#d.ring + 1] = line
  if #d.ring > d.ringMax then table.remove(d.ring, 1) end
  fireAppend(d)
end

-- ============================================================================
-- Logger
-- ============================================================================

function lib:RegisterDebugLogger(cogName, opts)
  opts = opts or {}
  local d = ensureCog(cogName)
  if opts.ringMax  then d.ringMax  = opts.ringMax end
  if opts.enabled ~= nil then d.enabled = opts.enabled and true or false end

  if d._loggerObj then return d._loggerObj end

  local logger = {}
  logger.cog = cogName
  function logger:PrintDebug(...)  return lib:DebugPrint(cogName, ...) end
  function logger:GetEntries()     return d.ring end
  function logger:Clear()          return lib:ClearDebugLog(cogName) end
  function logger:OnAppend(cb)
    if type(cb) == "function" then d.appendCbs[#d.appendCbs + 1] = cb end
  end
  function logger:SetEnabled(b)    d.enabled = b and true or false end
  function logger:IsEnabled()      return d.enabled end
  d._loggerObj = logger
  return logger
end

-- Bare entrypoints — useful for cogs that don't want to thread a logger ref
-- through every module.
function lib:DebugPrint(cogName, ...)
  local d   = ensureCog(cogName)
  local ts  = date("%H:%M:%S")
  local msg = joinArgs(...)
  appendEntry(d, ts .. "  " .. msg)
  if d.enabled then
    DEFAULT_CHAT_FRAME:AddMessage("|cffaaaaaa[" .. cogName .. " debug]|r " .. msg)
  end
end

function lib:ClearDebugLog(cogName)
  local d = ensureCog(cogName)
  for i = #d.ring, 1, -1 do d.ring[i] = nil end
  fireAppend(d)
end

function lib:GetDebugEntries(cogName) return ensureCog(cogName).ring end
function lib:SetDebugEnabled(cogName, b) ensureCog(cogName).enabled = b and true or false end
function lib:IsDebugEnabled(cogName) return ensureCog(cogName).enabled end

-- ============================================================================
-- LibDebug bridge
-- ============================================================================
-- Lib-side internals call lib:_LibDebugPrint(msg, scope?) which fires the
-- LibDebug event. Every registered cog logger picks it up and tags the entry
-- "[Cogworks-1.0/<scope>]" in its ring buffer. Cogs see lib activity in their
-- own console without any wiring on their end.

function lib:_LibDebugPrint(msg, scope)
  self:Fire(self.Events.LibDebug, msg, scope)
end

if not lib._debugLibBridgeOwner then
  lib._debugLibBridgeOwner = {}
  lib.RegisterCallback(lib._debugLibBridgeOwner, lib.Events.LibDebug, function(_, msg, scope)
    local prefix = scope and ("[Cogworks-1.0/" .. tostring(scope) .. "] ")
                          or  "[Cogworks-1.0] "
    local ts    = date("%H:%M:%S")
    local entry = ts .. "  " .. prefix .. tostring(msg)
    for _, d in pairs(lib._debug) do
      appendEntry(d, entry)
    end
  end)
end

-- ============================================================================
-- Inspectors
-- ============================================================================

function lib:RegisterDebugInspector(cogName, name, fn)
  assert(type(name) == "string" and name ~= "", "Debug: inspector name required")
  assert(type(fn) == "function",                  "Debug: inspector fn required")
  local d = ensureCog(cogName)
  d.inspectors[#d.inspectors + 1] = { name = name, fn = fn }
end

function lib:GetDebugInspectors(cogName) return ensureCog(cogName).inspectors end

-- ============================================================================
-- Actions
-- ============================================================================

function lib:RegisterDebugAction(cogName, label, fn)
  assert(type(label) == "string" and label ~= "", "Debug: action label required")
  assert(type(fn) == "function",                    "Debug: action fn required")
  local d = ensureCog(cogName)
  d.actions[#d.actions + 1] = { label = label, fn = fn }
end

function lib:GetDebugActions(cogName) return ensureCog(cogName).actions end

-- ============================================================================
-- Profiler
-- ============================================================================
-- Wraps a function call with debugprofilestop() timing; per-label counters
-- live in lib._debug[cog].profile. When the cog's debug is disabled, calls
-- bypass timing entirely (zero overhead in production).

function lib:Profile(cogName, label, fn, ...)
  local d = ensureCog(cogName)
  if not d.enabled or type(fn) ~= "function" then
    if type(fn) == "function" then return fn(...) end
    return
  end
  local t0 = debugprofilestop()
  local r1, r2, r3, r4, r5 = fn(...)
  local dt = debugprofilestop() - t0

  local p = d.profile[label]
  if not p then
    p = { count = 0, total = 0, last = 0, max = 0 }
    d.profile[label] = p
  end
  p.count = p.count + 1
  p.total = p.total + dt
  p.last  = dt
  if dt > p.max then p.max = dt end

  return r1, r2, r3, r4, r5
end

function lib:GetProfileStats(cogName) return ensureCog(cogName).profile end

function lib:ResetProfileStats(cogName)
  local d = ensureCog(cogName)
  for k in pairs(d.profile) do d.profile[k] = nil end
end

-- ============================================================================
-- Serialize
-- ============================================================================
-- Pretty-printer biased toward readability for copy-paste in defect reports.
-- Cycles short-circuit with "<cycle>"; userdata + functions print as
-- "<userdata>" / "<function>" so the output stays text-only.

local function indentStr(n) return string.rep("  ", n) end

local function serializeValue(v, depth, seen, maxDepth)
  if v == nil               then return "nil"            end
  local t = type(v)
  if t == "string"          then return string.format("%q", v) end
  if t == "number"          then return tostring(v)      end
  if t == "boolean"         then return tostring(v)      end
  if t == "function"        then return "<function>"     end
  if t == "userdata"        then return "<userdata>"     end
  if t == "thread"          then return "<thread>"       end
  if t ~= "table"           then return "<" .. t .. ">"  end

  if seen[v]                then return "<cycle>"        end
  if depth >= maxDepth      then return "<...>"          end
  seen[v] = true

  if next(v) == nil then seen[v] = nil; return "{}" end

  -- Array vs map detection: pure-numeric-key tables print as arrays for compactness.
  local arrLen = 0
  local isArray = true
  for k in pairs(v) do
    if type(k) ~= "number" or k ~= math.floor(k) or k < 1 then
      isArray = false
      break
    end
    if k > arrLen then arrLen = k end
  end

  local lines = { "{" }
  if isArray and arrLen > 0 then
    for i = 1, arrLen do
      lines[#lines + 1] = indentStr(depth + 1) .. serializeValue(v[i], depth + 1, seen, maxDepth) .. ","
    end
  else
    local keys = {}
    for k in pairs(v) do keys[#keys + 1] = k end
    table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
    for _, k in ipairs(keys) do
      local ks
      if type(k) == "string" and k:match("^[_%a][_%w]*$") then
        ks = k
      else
        ks = "[" .. serializeValue(k, depth + 1, seen, maxDepth) .. "]"
      end
      local vs = serializeValue(v[k], depth + 1, seen, maxDepth)
      lines[#lines + 1] = indentStr(depth + 1) .. ks .. " = " .. vs .. ","
    end
  end
  lines[#lines + 1] = indentStr(depth) .. "}"

  seen[v] = nil
  return table.concat(lines, "\n")
end

function lib:SerializeDebugValue(v, opts)
  opts = opts or {}
  return serializeValue(v, 0, {}, opts.maxDepth or 6)
end

function lib:DumpDebugState(cogName)
  local d = ensureCog(cogName)
  local parts = {
    "=== " .. cogName .. " — debug state dump ===",
    "Generated: " .. date("%Y-%m-%d %H:%M:%S"),
    "Cogworks-1.0 v" .. lib.version .. " (MINOR " .. lib.minorVersion .. ")",
    "",
    "[Suite settings]",
    self:SerializeDebugValue(lib.settings),
    "",
  }

  for _, ins in ipairs(d.inspectors) do
    parts[#parts + 1] = "[" .. ins.name .. "]"
    local ok, val = pcall(ins.fn)
    if ok then
      parts[#parts + 1] = self:SerializeDebugValue(val)
    else
      parts[#parts + 1] = "<error: " .. tostring(val) .. ">"
    end
    parts[#parts + 1] = ""
  end

  if next(d.profile) then
    parts[#parts + 1] = "[Profile]"
    local labels = {}
    for k in pairs(d.profile) do labels[#labels + 1] = k end
    table.sort(labels)
    for _, lbl in ipairs(labels) do
      local p = d.profile[lbl]
      local avg = (p.count > 0) and (p.total / p.count) or 0
      parts[#parts + 1] = string.format("  %-40s  count=%d  total=%.2fms  last=%.2fms  max=%.2fms  avg=%.2fms",
        lbl, p.count, p.total, p.last, p.max, avg)
    end
    parts[#parts + 1] = ""
  end

  parts[#parts + 1] = "[Recent debug log (" .. #d.ring .. " of " .. d.ringMax .. ")]"
  for _, line in ipairs(d.ring) do parts[#parts + 1] = line end

  return table.concat(parts, "\n")
end

-- ============================================================================
-- CreateCopyDialog
-- ============================================================================
-- Modal-style frame with a read-only multi-line EditBox preloaded with text.
-- Caller dismisses via Close button or Escape. Designed for "copy this state
-- dump to your bug report" workflows.
--
-- Returns the frame; populated copy text via :SetCopyText(t) or the initial
-- `text` arg. The dialog auto-highlights so users can immediately ctrl+C.

function lib:CreateCopyDialog(text, hint)
  local T = self.Theme
  local f = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
  f:SetSize(560, 420)
  f:SetPoint("CENTER")
  f:SetFrameStrata("FULLSCREEN_DIALOG")
  f:SetBackdrop(self.Backdrop)
  f:SetBackdropColor(unpack(T.bg))
  f:SetBackdropBorderColor(unpack(T.gold))
  f:SetMovable(true); f:EnableMouse(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", f.StartMoving)
  f:SetScript("OnDragStop",  f.StopMovingOrSizing)
  f:SetClampedToScreen(true)
  f:SetResizable(true)
  if f.SetResizeBounds then f:SetResizeBounds(360, 240, 1200, 900) end

  local titleBar = CreateFrame("Frame", nil, f)
  titleBar:SetHeight(24)
  titleBar:SetPoint("TOPLEFT", 4, -4)
  titleBar:SetPoint("TOPRIGHT", -4, -4)
  local titleBg = titleBar:CreateTexture(nil, "BACKGROUND")
  titleBg:SetAllPoints()
  titleBg:SetColorTexture(unpack(T.header))
  local title = titleBar:CreateFontString(nil, "OVERLAY")
  title:SetFontObject(self:GetFont("normal"))
  title:SetPoint("LEFT", 8, 0)
  title:SetText("Copy text")
  title:SetTextColor(unpack(T.gold))

  local closeBtn = CreateFrame("Button", nil, titleBar, "UIPanelCloseButton")
  closeBtn:SetSize(20, 20)
  closeBtn:SetPoint("RIGHT", -2, 0)
  closeBtn:SetScript("OnClick", function() f:Hide() end)

  local hintFs
  if hint and hint ~= "" then
    hintFs = f:CreateFontString(nil, "OVERLAY")
    hintFs:SetFontObject(self:GetFont("small"))
    hintFs:SetTextColor(unpack(T.textDim))
    hintFs:SetPoint("TOPLEFT",  titleBar, "BOTTOMLEFT",  4, -4)
    hintFs:SetPoint("TOPRIGHT", titleBar, "BOTTOMRIGHT", -4, -4)
    hintFs:SetJustifyH("LEFT")
    hintFs:SetText(hint)
  end

  local scroll = CreateFrame("ScrollFrame", nil, f, "UIPanelScrollFrameTemplate")
  scroll:SetPoint("TOPLEFT",     hintFs or titleBar, "BOTTOMLEFT",  0, -6)
  scroll:SetPoint("BOTTOMRIGHT", f,                  "BOTTOMRIGHT", -28, 12)

  local edit = CreateFrame("EditBox", nil, scroll)
  edit:SetMultiLine(true)
  edit:SetAutoFocus(true)
  edit:SetFontObject(ChatFontNormal)
  edit:SetWidth(scroll:GetWidth())
  edit:SetText(text or "")
  edit:HighlightText()
  edit:SetScript("OnEscapePressed", function() f:Hide() end)
  scroll:SetScrollChild(edit)
  scroll:HookScript("OnSizeChanged", function(sf, w, h)
    edit:SetWidth(math.max(1, w))
  end)

  -- Resize grip so users can grow the dialog for long dumps.
  local grip = CreateFrame("Button", nil, f)
  grip:SetSize(14, 14)
  grip:SetPoint("BOTTOMRIGHT", -4, 4)
  grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
  grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
  grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
  grip:RegisterForDrag("LeftButton")
  grip:SetScript("OnDragStart", function() f:StartSizing("BOTTOMRIGHT") end)
  grip:SetScript("OnDragStop",  function() f:StopMovingOrSizing() end)

  function f:SetCopyText(t)
    edit:SetText(t or "")
    edit:HighlightText()
    edit:SetCursorPosition(0)
  end
  function f:GetCopyText() return edit:GetText() end
  return f
end

-- ============================================================================
-- CreateDebugConsole
-- ============================================================================
-- Dashboard frame for one cog. Uses CreateTabPanel for multiple surfaces:
--   Actions   — registered debug action buttons (2-col grid)
--   Inspectors— picker dropdown + View / Copy / Dump All buttons
--   Profile   — sortable list of profile labels
--   Log       — live-updated scrollable text view
--
-- opts:
--   cog       string  — cog name (required)
--   width     number  — default 580
--   height    number  — default 460
--   savedvars table   — optional; persists position/size/pinned
--
-- Returns the frame. Movable + resizable; reuses CreateMiniView's chrome
-- conventions (title bar, close, resize grip).

function lib:CreateDebugConsole(opts)
  opts = opts or {}
  local cog = opts.cog
  assert(type(cog) == "string" and cog ~= "", "CreateDebugConsole: opts.cog required")
  local T = self.Theme
  local d = ensureCog(cog)

  local f = CreateFrame("Frame", "CogworksDebugConsole_" .. cog, UIParent, "BackdropTemplate")
  f:SetSize(opts.width or 580, opts.height or 460)
  f:SetPoint("CENTER")
  f:SetFrameStrata("DIALOG")
  f:SetBackdrop(self.Backdrop)
  f:SetBackdropColor(unpack(T.bg))
  f:SetBackdropBorderColor(unpack(T.border))
  f:SetClampedToScreen(true)
  f:SetMovable(true); f:EnableMouse(true)
  f:SetResizable(true)
  if f.SetResizeBounds then f:SetResizeBounds(420, 320, 1200, 900) end
  f:Hide()

  -- ---- Title bar -------------------------------------------------------
  local titleBar = CreateFrame("Frame", nil, f)
  titleBar:SetHeight(24)
  titleBar:SetPoint("TOPLEFT", 4, -4)
  titleBar:SetPoint("TOPRIGHT", -4, -4)
  titleBar:EnableMouse(true); titleBar:RegisterForDrag("LeftButton")
  titleBar:SetScript("OnDragStart", function() f:StartMoving() end)
  titleBar:SetScript("OnDragStop",  function() f:StopMovingOrSizing() end)

  local titleBg = titleBar:CreateTexture(nil, "BACKGROUND")
  titleBg:SetAllPoints(); titleBg:SetColorTexture(unpack(T.header))

  local title = titleBar:CreateFontString(nil, "OVERLAY")
  title:SetFontObject(self:GetFont("normal"))
  title:SetPoint("LEFT", 8, 0)
  title:SetText(cog .. " — Debug")
  title:SetTextColor(unpack(T.gold))

  local closeBtn = CreateFrame("Button", nil, titleBar, "UIPanelCloseButton")
  closeBtn:SetSize(20, 20); closeBtn:SetPoint("RIGHT", -2, 0)
  closeBtn:SetScript("OnClick", function() f:Hide() end)

  -- ---- Status row ------------------------------------------------------
  local statusRow = CreateFrame("Frame", nil, f)
  statusRow:SetHeight(22)
  statusRow:SetPoint("TOPLEFT",  titleBar, "BOTTOMLEFT",  0, -4)
  statusRow:SetPoint("TOPRIGHT", titleBar, "BOTTOMRIGHT", 0, -4)

  local statusFs = statusRow:CreateFontString(nil, "OVERLAY")
  statusFs:SetFontObject(self:GetFont("small"))
  statusFs:SetPoint("LEFT", 8, 0)
  statusFs:SetTextColor(unpack(T.textDim))

  local toggleBtn = self:CreateButton(statusRow, "Toggle debug", 110, 18, function()
    self:SetDebugEnabled(cog, not self:IsDebugEnabled(cog))
    f._refreshStatus()
  end)
  toggleBtn:SetPoint("RIGHT", -8, 0)

  function f._refreshStatus()
    local on = lib:IsDebugEnabled(cog)
    local on_label = on and ("|cff30d530ON|r")
                       or ("|cffaa3030OFF|r")
    statusFs:SetText(string.format("Debug echo: %s   |cff888888• %d log entries  • %d profile labels  • %d inspectors  • %d actions|r",
      on_label, #d.ring, (function() local n=0; for _ in pairs(d.profile) do n=n+1 end; return n end)(),
      #d.inspectors, #d.actions))
  end
  f._refreshStatus()

  -- ---- Tab panel -------------------------------------------------------
  local tabHost = CreateFrame("Frame", nil, f)
  tabHost:SetPoint("TOPLEFT",     statusRow, "BOTTOMLEFT",  0, -2)
  tabHost:SetPoint("BOTTOMRIGHT", f,         "BOTTOMRIGHT", -4, 14)

  -- The tab build closures reference f._buildActions / f._buildInspectors /
  -- f._buildProfile / f._buildLog — all defined further down in this function.
  -- TabPanel's eager initial activation would fire those closures before the
  -- methods exist, so we pass lazy=true here and explicitly activate the
  -- starting tab at the bottom of CreateDebugConsole once everything is wired.
  local panel = self:CreateTabPanel(tabHost, {
    lazy = true,
    tabs = {
      { key = "actions",    label = "Actions",    build = function(p) f._buildActions(p)    end },
      { key = "inspectors", label = "Inspectors", build = function(p) f._buildInspectors(p) end },
      { key = "profile",    label = "Profile",    build = function(p) f._buildProfile(p)    end },
      { key = "log",        label = "Log",        build = function(p) f._buildLog(p)        end },
    },
    onActivate = function(key)
      if key == "log"     and f._refreshLog     then f._refreshLog()     end
      if key == "profile" and f._refreshProfile then f._refreshProfile() end
    end,
  })
  panel:SetAllPoints(tabHost)

  -- ---- Resize grip -----------------------------------------------------
  local grip = CreateFrame("Button", nil, f)
  grip:SetSize(14, 14); grip:SetPoint("BOTTOMRIGHT", -4, 4)
  grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
  grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
  grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
  grip:RegisterForDrag("LeftButton")
  grip:SetScript("OnDragStart", function() f:StartSizing("BOTTOMRIGHT") end)
  grip:SetScript("OnDragStop",  function() f:StopMovingOrSizing() end)

  -- ---- Optional persistence ------------------------------------------
  if opts.savedvars then
    local sv = opts.savedvars
    if sv.x and sv.y then
      f:ClearAllPoints()
      f:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", sv.x, sv.y)
    end
    if sv.w and sv.h then f:SetSize(sv.w, sv.h) end
    f:HookScript("OnHide", function()
      sv.x = f:GetLeft(); sv.y = f:GetBottom()
      sv.w = f:GetWidth(); sv.h = f:GetHeight()
    end)
  end

  -- ---- Log live-update subscription ------------------------------------
  d.appendCbs[#d.appendCbs + 1] = function()
    if f:IsShown() and f._refreshLog then f._refreshLog() end
    f._refreshStatus()
  end

  -- ============================================================================
  -- Tab builders
  -- ============================================================================

  function f._buildActions(parent)
    local pad = 8
    local btnW, btnH, gap = 240, 24, 6

    local scroll = CreateFrame("ScrollFrame", nil, parent)
    scroll:SetPoint("TOPLEFT",     parent, "TOPLEFT",     pad, -pad)
    scroll:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -pad - 4, pad)
    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(1, 1)
    scroll:SetScrollChild(content)
    scroll:EnableMouseWheel(true)
    scroll:SetScript("OnMouseWheel", function(sf, delta)
      local range = math.max(0, content:GetHeight() - sf:GetHeight())
      sf:SetVerticalScroll(math.max(0, math.min(range, sf:GetVerticalScroll() - delta * (btnH + gap))))
    end)

    local cols = 2
    local function rebuild()
      -- Tear down old buttons
      if content._btns then
        for _, b in ipairs(content._btns) do b:Hide(); b:SetParent(nil) end
      end
      content._btns = {}
      local actions = lib:GetDebugActions(cog)
      for i, a in ipairs(actions) do
        local b = lib:CreateButton(content, a.label, btnW, btnH, function()
          local ok, err = pcall(a.fn)
          if not ok then lib:PrintError(cog, "action error: " .. tostring(err)) end
          f._refreshStatus()
        end)
        local col = (i - 1) % cols
        local row = math.floor((i - 1) / cols)
        b:ClearAllPoints()
        b:SetPoint("TOPLEFT", content, "TOPLEFT", col * (btnW + gap), -row * (btnH + gap))
        content._btns[i] = b
      end
      local rowCount = math.ceil(math.max(1, #actions) / cols)
      content:SetHeight(math.max(1, rowCount * (btnH + gap)))
      content:SetWidth(scroll:GetWidth())
    end
    rebuild()
    content._rebuild = rebuild
    f._actionsTab = content

    -- Empty-state hint
    if #lib:GetDebugActions(cog) == 0 then
      local empty = content:CreateFontString(nil, "OVERLAY")
      empty:SetFontObject(lib:GetFont("small"))
      empty:SetTextColor(unpack(T.textDim))
      empty:SetPoint("TOPLEFT", 0, -4)
      empty:SetText("No actions registered. Use cw:RegisterDebugAction(\"" .. cog .. "\", label, fn) to add one.")
    end
  end

  function f._buildInspectors(parent)
    local pad = 8

    local row = CreateFrame("Frame", nil, parent)
    row:SetHeight(28)
    row:SetPoint("TOPLEFT",  parent, "TOPLEFT",  pad, -pad)
    row:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -pad, -pad)

    local function inspectorOptions()
      local list = {}
      for _, ins in ipairs(lib:GetDebugInspectors(cog)) do
        list[#list + 1] = { key = ins.name, label = ins.name }
      end
      return list
    end

    local inspectors = lib:GetDebugInspectors(cog)
    local selectedKey = inspectors[1] and inspectors[1].name

    local dd = lib:CreateDropdown(row, inspectorOptions(), selectedKey, function(key)
      selectedKey = key
    end, { autoWidth = true, minWidth = 140, maxWidth = 280 })
    dd:SetPoint("LEFT", 0, 0)

    local function showSelected()
      if not selectedKey then return end
      for _, ins in ipairs(lib:GetDebugInspectors(cog)) do
        if ins.name == selectedKey then
          local ok, val = pcall(ins.fn)
          local body
          if ok then
            body = lib:SerializeDebugValue(val)
          else
            body = "<inspector error: " .. tostring(val) .. ">"
          end
          local dlg = lib:CreateCopyDialog(body, "Inspector: " .. selectedKey .. "  —  Ctrl+A to select all, Ctrl+C to copy")
          dlg:Show()
          return
        end
      end
    end

    local viewBtn = lib:CreateButton(row, "View", 60, 22, showSelected)
    viewBtn:SetPoint("LEFT", dd, "RIGHT", 8, 0)

    local dumpBtn = lib:CreateButton(row, "Dump all", 80, 22, function()
      local dlg = lib:CreateCopyDialog(lib:DumpDebugState(cog),
        "Full state dump for " .. cog .. "  —  paste this into a defect report")
      dlg:Show()
    end)
    dumpBtn:SetPoint("LEFT", viewBtn, "RIGHT", 4, 0)

    -- Inspector summary list below the row
    local listScroll = CreateFrame("ScrollFrame", nil, parent)
    listScroll:SetPoint("TOPLEFT",     row, "BOTTOMLEFT",  0, -8)
    listScroll:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -pad - 4, pad)
    local listContent = CreateFrame("Frame", nil, listScroll)
    listContent:SetSize(1, 1)
    listScroll:SetScrollChild(listContent)
    listScroll:EnableMouseWheel(true)
    listScroll:SetScript("OnMouseWheel", function(sf, delta)
      local range = math.max(0, listContent:GetHeight() - sf:GetHeight())
      sf:SetVerticalScroll(math.max(0, math.min(range, sf:GetVerticalScroll() - delta * 22)))
    end)

    local listFs = listContent:CreateFontString(nil, "OVERLAY")
    listFs:SetFontObject(lib:GetFont("small"))
    listFs:SetTextColor(unpack(T.textDim))
    listFs:SetPoint("TOPLEFT", 4, -4)
    listFs:SetJustifyH("LEFT")
    listFs:SetWordWrap(true)

    local function rebuildList()
      local lines = {}
      local list = lib:GetDebugInspectors(cog)
      if #list == 0 then
        lines[1] = "No inspectors registered. Use cw:RegisterDebugInspector(\"" .. cog .. "\", name, fn)."
      else
        lines[1] = #list .. " inspector(s):"
        for _, ins in ipairs(list) do
          lines[#lines + 1] = "  • " .. ins.name
        end
      end
      listFs:SetText(table.concat(lines, "\n"))
      listContent:SetHeight(math.max(1, listFs:GetStringHeight() + 8))
      listContent:SetWidth(listScroll:GetWidth())
    end
    rebuildList()
  end

  function f._buildProfile(parent)
    local pad = 8

    local row = CreateFrame("Frame", nil, parent)
    row:SetHeight(28)
    row:SetPoint("TOPLEFT",  parent, "TOPLEFT",  pad, -pad)
    row:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -pad, -pad)

    local resetBtn = lib:CreateButton(row, "Reset", 70, 22, function()
      lib:ResetProfileStats(cog)
      f._refreshProfile()
      f._refreshStatus()
    end)
    resetBtn:SetPoint("LEFT", 0, 0)

    local hint = row:CreateFontString(nil, "OVERLAY")
    hint:SetFontObject(lib:GetFont("small"))
    hint:SetTextColor(unpack(T.textDim))
    hint:SetPoint("LEFT", resetBtn, "RIGHT", 12, 0)
    hint:SetText("Wrap calls with cw:Profile(cog, label, fn, ...) — only timed when debug is enabled")

    local scroll = CreateFrame("ScrollFrame", nil, parent)
    scroll:SetPoint("TOPLEFT",     row, "BOTTOMLEFT", 0, -6)
    scroll:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -pad - 4, pad)
    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(1, 1)
    scroll:SetScrollChild(content)
    scroll:EnableMouseWheel(true)
    scroll:SetScript("OnMouseWheel", function(sf, delta)
      local range = math.max(0, content:GetHeight() - sf:GetHeight())
      sf:SetVerticalScroll(math.max(0, math.min(range, sf:GetVerticalScroll() - delta * 18)))
    end)

    local fs = content:CreateFontString(nil, "OVERLAY")
    fs:SetFontObject(lib:GetFont("small"))
    fs:SetPoint("TOPLEFT", 4, -4)
    fs:SetJustifyH("LEFT")
    fs:SetWordWrap(false)
    fs:SetTextColor(unpack(T.text))

    function f._refreshProfile()
      local stats = lib:GetProfileStats(cog)
      local labels = {}
      for k in pairs(stats) do labels[#labels + 1] = k end
      table.sort(labels, function(a, b) return (stats[a].total or 0) > (stats[b].total or 0) end)
      local lines = { string.format("%-40s  %8s  %10s  %9s  %9s  %9s", "label", "count", "total ms", "last ms", "max ms", "avg ms") }
      lines[#lines + 1] = string.rep("-", 92)
      if #labels == 0 then
        lines[#lines + 1] = "(no profile samples yet)"
      else
        for _, lbl in ipairs(labels) do
          local p = stats[lbl]
          local avg = (p.count > 0) and (p.total / p.count) or 0
          lines[#lines + 1] = string.format("%-40s  %8d  %10.2f  %9.2f  %9.2f  %9.2f",
            lbl:sub(1, 40), p.count, p.total, p.last, p.max, avg)
        end
      end
      fs:SetText(table.concat(lines, "\n"))
      content:SetHeight(math.max(1, fs:GetStringHeight() + 8))
      content:SetWidth(scroll:GetWidth())
    end
    f._refreshProfile()
  end

  function f._buildLog(parent)
    local pad = 8

    local row = CreateFrame("Frame", nil, parent)
    row:SetHeight(28)
    row:SetPoint("TOPLEFT",  parent, "TOPLEFT",  pad, -pad)
    row:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -pad, -pad)

    local copyBtn = lib:CreateButton(row, "Copy log", 90, 22, function()
      local dlg = lib:CreateCopyDialog(table.concat(d.ring, "\n"),
        "#" .. #d.ring .. " entries  —  Ctrl+A then Ctrl+C")
      dlg:Show()
    end)
    copyBtn:SetPoint("LEFT", 0, 0)

    local clearBtn = lib:CreateButton(row, "Clear", 70, 22, function()
      lib:ClearDebugLog(cog)
      f._refreshLog()
      f._refreshStatus()
    end)
    clearBtn:SetPoint("LEFT", copyBtn, "RIGHT", 4, 0)

    local autoScroll = true
    local autoBtn = lib:CreateButton(row, "Auto-scroll: ON", 130, 22, function() end)
    autoBtn:SetPoint("LEFT", clearBtn, "RIGHT", 4, 0)
    autoBtn:SetScript("OnClick", function()
      autoScroll = not autoScroll
      autoBtn.text:SetText("Auto-scroll: " .. (autoScroll and "ON" or "OFF"))
    end)

    local scroll = CreateFrame("ScrollFrame", nil, parent, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT",     row, "BOTTOMLEFT", 0, -6)
    scroll:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -pad - 22, pad)
    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(1, 1)
    scroll:SetScrollChild(content)

    local fs = content:CreateFontString(nil, "OVERLAY")
    fs:SetFontObject(lib:GetFont("small"))
    fs:SetPoint("TOPLEFT", 2, -2)
    fs:SetPoint("TOPRIGHT", -2, -2)
    fs:SetJustifyH("LEFT")
    fs:SetWordWrap(false)
    fs:SetTextColor(unpack(T.text))

    function f._refreshLog()
      -- Show the last N lines that fit comfortably (cap to avoid huge font work)
      local maxLines = 400
      local startIdx = math.max(1, #d.ring - maxLines + 1)
      local lines = {}
      for i = startIdx, #d.ring do lines[#lines + 1] = d.ring[i] end
      fs:SetText(table.concat(lines, "\n"))
      content:SetHeight(math.max(1, fs:GetStringHeight() + 4))
      content:SetWidth(scroll:GetWidth())
      if autoScroll then
        local maxScroll = scroll:GetVerticalScrollRange()
        scroll:SetVerticalScroll(maxScroll)
      end
    end
    f._refreshLog()
  end

  function f:RebuildActions()
    if f._actionsTab and f._actionsTab._rebuild then f._actionsTab._rebuild() end
    f._refreshStatus()
  end

  -- Activate the starting tab now that every f._build* method is defined.
  -- Honours opts.initialTab if the caller picked a specific landing tab.
  panel:SetActiveTab(opts.initialTab or "actions")

  return f
end
