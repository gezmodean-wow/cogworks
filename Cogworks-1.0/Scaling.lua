-- Cogworks-1.0/Scaling.lua | Appearance editor + per-frame scale registration.
--
-- Consumer-facing primitives:
--
--   cw:CreateAppearanceTab(parent, opts)
--     **Preferred entry point.** Builds the full cogworks Appearance editor —
--     a single scrolling page with a live preview panel, profile picker,
--     per-cog override, font/UI scale sliders, font family + font preview,
--     theme picker, editable color swatches, and theme save/share. Returns a
--     ScrollFrame already anchored to fill `parent`, so it drops straight into
--     a settings tab with no follow-up SetPoint. (COG-71 / COG-73)
--
--   cw:CreateUIScalingSettingsBlock(parent, opts)
--     The editor itself; CreateAppearanceTab is a thin alias. Kept under this
--     name for back-compat. As of MINOR 30 it returns a self-anchored
--     ScrollFrame (was an unanchored Frame) — direct callers that positioned
--     the result themselves should ClearAllPoints first if they still want to.
--
--   cw:RegisterScalingFrame(frame, opts)
--     Subscribes a frame to SettingsChanged for uiScale so SetScale fires
--     automatically. Optionally persists frame geometry into a caller-owned SV
--     table.
--
-- ============================================================================
-- Appearance-tab convention (COG-71)
-- ============================================================================
-- Every cog should expose cogworks-managed appearance settings in a dedicated
-- tab inside its own settings UI. The convention:
--
--   * Tab label:     "Appearance"
--   * Tab position:  last tab in the cog's settings TabPanel
--   * Tab body:      a single call to cw:CreateAppearanceTab(parent, { cog = "MyCog" })
--   * Cog-specific:  toggles / picker rows / debug knobs go in OTHER tabs.
--                    The Appearance tab is reserved for the standard primitive
--                    so suite-wide UX improvements (color editors, new
--                    overrides, etc.) reach every cog the day they ship.
--
-- Persistence: all writes flow through cogworks into CogworksSharedDB
-- (account-wide, shared by every cog). Per-cog overrides for fontScale +
-- fontFamily are scoped to `cog`; uiScale + theme (including color edits) stay
-- suite-wide for the v0.14.x line (per-cog theme is a planned multi-release
-- stretch — see cogworks #74).
--
-- Adoption example (in a cog's main settings TabPanel):
--
--   local panel = cw:CreateTabPanel(parent, {
--     tabs = {
--       { key = "general",    label = "General",    build = function(c) ... end },
--       { key = "scanner",    label = "Scanner",    build = function(c) ... end },
--       -- ... cog-specific tabs ...
--       { key = "appearance", label = "Appearance",
--         build = function(c)
--           return cw:CreateAppearanceTab(c, { cog = "MyCog" })
--         end },
--     },
--   })
--
-- See Standalone/UIShowcase.lua -> "Appearance" page for a runnable demo.

local lib = LibStub("Cogworks-1.0")
if not lib then return end

-- Module load guard. See Sections.lua for rationale.
local MODULE_MINOR = 5
lib._modules = lib._modules or {}
if (lib._modules.Scaling or 0) >= MODULE_MINOR then return end
lib._modules.Scaling = MODULE_MINOR

local SCALE_MIN, SCALE_MAX, SCALE_STEP = 0.8, 1.4, 0.05

-- ============================================================================
-- Slider helper
-- ============================================================================
-- Wraps OptionsSliderTemplate so we get the standard knob and groove, but with
-- our own header label + live value display in theme colors.

local _sliderId = 0
local function makeSlider(parent, opts)
  _sliderId = _sliderId + 1
  local T = lib.Theme
  local sliderName = "CogworksScaleSlider" .. _sliderId
  local s = CreateFrame("Slider", sliderName, parent, "OptionsSliderTemplate")
  s:SetMinMaxValues(opts.min, opts.max)
  s:SetValueStep(opts.step)
  s:SetObeyStepOnDrag(true)
  s:SetWidth(opts.width or 160)
  s:SetValue(opts.value or opts.min)

  -- Hide the template's built-in label (we render our own header above).
  local lo, hi, mid = _G[sliderName .. "Low"], _G[sliderName .. "High"], _G[sliderName .. "Text"]
  if lo  then lo:Hide()  end
  if hi  then hi:Hide()  end
  if mid then mid:Hide() end

  s.title = parent:CreateFontString(nil, "OVERLAY")
  s.title:SetFontObject(lib:GetFont("normal"))
  s.title:SetPoint("BOTTOMLEFT", s, "TOPLEFT", 0, 4)
  s.title:SetTextColor(unpack(T.text))
  s.title:SetText(opts.label or "")

  s.valueText = parent:CreateFontString(nil, "OVERLAY")
  s.valueText:SetFontObject(lib:GetFont("normal"))
  s.valueText:SetPoint("BOTTOMRIGHT", s, "TOPRIGHT", 0, 4)
  s.valueText:SetTextColor(unpack(T.gold))

  local fmt = opts.format or "%.2fx"
  local function setValueText(v) s.valueText:SetText(fmt:format(v)) end
  setValueText(opts.value or opts.min)

  s:SetScript("OnValueChanged", function(self, val)
    -- Snap to opts.step (slider hardware sometimes overshoots by epsilon).
    val = math.floor((val - opts.min) / opts.step + 0.5) * opts.step + opts.min
    setValueText(val)
    if opts.onChange then opts.onChange(val) end
  end)

  function s:SetSliderValue(v)
    self:SetValue(v)
    setValueText(v)
  end
  return s
end

-- ============================================================================
-- Dropdown helper
-- ============================================================================
-- Thin wrapper around UIDropDownMenuTemplate so the settings block can stamp
-- out theme/profile/font-family selectors without each one re-doing the
-- Initialize boilerplate.

local _ddId = 0
local function makeDropdown(parent, opts)
  _ddId = _ddId + 1
  local T  = lib.Theme
  local dd = CreateFrame("Frame", "CogworksScaleDropdown" .. _ddId, parent, "UIDropDownMenuTemplate")
  UIDropDownMenu_SetWidth(dd, opts.width or 140)

  dd.title = parent:CreateFontString(nil, "OVERLAY")
  dd.title:SetFontObject(lib:GetFont("normal"))
  -- The template adds ~16px of internal padding on its left edge; offset our
  -- label so it sits flush with the visible left edge of the dropdown chrome.
  dd.title:SetPoint("BOTTOMLEFT", dd, "TOPLEFT", 22, 0)
  dd.title:SetTextColor(unpack(T.text))
  dd.title:SetText(opts.label or "")

  local function rebuildOptions(selectedKey)
    UIDropDownMenu_Initialize(dd, function(self, level)
      local options = opts.optionsFn and opts.optionsFn() or opts.options or {}
      for _, o in ipairs(options) do
        local info = UIDropDownMenu_CreateInfo()
        info.text         = o.label or o.key
        info.value        = o.key
        info.checked      = (o.key == selectedKey)
        info.func         = function(_, value)
          UIDropDownMenu_SetSelectedValue(dd, value)
          UIDropDownMenu_SetText(dd, o.label or value)
          if opts.onChange then opts.onChange(value) end
        end
        UIDropDownMenu_AddButton(info, level)
      end
    end)
  end

  function dd:SetSelected(key, labelOverride)
    UIDropDownMenu_SetSelectedValue(dd, key)
    rebuildOptions(key)
    -- Look up label for display.
    local options = opts.optionsFn and opts.optionsFn() or opts.options or {}
    local label   = labelOverride or key
    for _, o in ipairs(options) do
      if o.key == key then label = o.label or o.key; break end
    end
    UIDropDownMenu_SetText(dd, label)
  end

  function dd:RefreshOptions()
    rebuildOptions(UIDropDownMenu_GetSelectedValue(dd))
  end

  rebuildOptions(opts.initial)
  if opts.initial then dd:SetSelected(opts.initial) end
  return dd
end

-- ============================================================================
-- Profile-action popups
-- ============================================================================
-- StaticPopupDialogs reused across blocks. Per-key assignment is the safe
-- pattern; rebinding the global itself (StaticPopupDialogs = StaticPopupDialogs
-- or {}) taints the table from insecure context and causes ADDON_ACTION_FORBIDDEN
-- on any protected call that consults the popup table — most visibly
-- UseContainerItem on knowledge tomes / consumables (COG-30 / flipqueue#156).

StaticPopupDialogs["COGWORKS_NEW_PROFILE"] = StaticPopupDialogs["COGWORKS_NEW_PROFILE"] or {
  text         = "Name for the new profile:",
  button1      = "Create",
  button2      = "Cancel",
  hasEditBox   = true,
  maxLetters   = 32,
  timeout      = 0,
  whileDead    = true,
  hideOnEscape = true,
  OnAccept = function(self, data)
    local name = self.editBox and self.editBox:GetText() or ""
    if name == "" then return end
    local ok, err = lib:CreateProfile(name, lib:GetActiveProfile())
    if ok and data and data.afterCreate then data.afterCreate(name) end
    if not ok and err then lib:PrintError("Cogworks", err) end
  end,
  EditBoxOnEnterPressed = function(self) self:GetParent().button1:Click() end,
}

StaticPopupDialogs["COGWORKS_IMPORT_PROFILE"] = StaticPopupDialogs["COGWORKS_IMPORT_PROFILE"] or {
  text         = "Paste profile string:",
  button1      = "Import",
  button2      = "Cancel",
  hasEditBox   = true,
  maxLetters   = 999,
  editBoxWidth = 260,
  timeout      = 0,
  whileDead    = true,
  hideOnEscape = true,
  OnAccept = function(self, data)
    local str = self.editBox and self.editBox:GetText() or ""
    local name, err = lib:ImportProfile(str)
    if name and data and data.afterImport then data.afterImport(name) end
    if not name and err then lib:PrintError("Cogworks", err) end
  end,
}

StaticPopupDialogs["COGWORKS_EXPORT_PROFILE"] = StaticPopupDialogs["COGWORKS_EXPORT_PROFILE"] or {
  text         = "Copy this string to share the profile:",
  button1      = "Close",
  hasEditBox   = true,
  editBoxWidth = 260,
  timeout      = 0,
  whileDead    = true,
  hideOnEscape = true,
  OnShow = function(self, data)
    if self.editBox and data and data.exportString then
      self.editBox:SetText(data.exportString)
      self.editBox:HighlightText()
      self.editBox:SetFocus()
    end
  end,
}

-- ============================================================================
-- Scroll-frame helper
-- ============================================================================
-- A ScrollFrame that fills `parent`, with a content scroll-child and a thin
-- themed scrollbar. The editor builds top-down inside `content` and calls
-- content:SetHeight(...) when done.

local function makeScroller(parent)
  local scroll = CreateFrame("ScrollFrame", nil, parent)
  scroll:SetPoint("TOPLEFT",     parent, "TOPLEFT",     0,  0)
  scroll:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -6, 0)

  local content = CreateFrame("Frame", nil, scroll)
  content:SetWidth(math.max(1, (parent:GetWidth() or 480) - 6))
  content:SetHeight(1)
  scroll:SetScrollChild(content)

  -- Thin themed scrollbar track + thumb.
  local T = lib.Theme
  local track = CreateFrame("Frame", nil, parent)
  track:SetWidth(4)
  track:SetPoint("TOPRIGHT",    parent, "TOPRIGHT",    0,  0)
  track:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", 0,  0)
  local trackBg = track:CreateTexture(nil, "BACKGROUND")
  trackBg:SetAllPoints()
  trackBg:SetColorTexture(T.border[1], T.border[2], T.border[3], 0.1)

  local thumb = CreateFrame("Frame", nil, track)
  thumb:SetWidth(4); thumb:SetHeight(40)
  thumb:SetPoint("TOP", track, "TOP", 0, 0)
  local thumbTex = thumb:CreateTexture(nil, "ARTWORK")
  thumbTex:SetAllPoints()
  thumbTex:SetColorTexture(T.brass[1], T.brass[2], T.brass[3], 0.4)
  track:Hide()

  local function updateThumb()
    local contentH = content:GetHeight()
    local viewH    = scroll:GetHeight()
    local range    = math.max(0, contentH - viewH)
    if range <= 0.5 then track:Hide(); return end
    track:Show()
    local trackH = track:GetHeight()
    local thumbH = math.max(16, trackH * (viewH / contentH))
    thumb:SetHeight(thumbH)
    local frac = range > 0 and (scroll:GetVerticalScroll() / range) or 0
    thumb:ClearAllPoints()
    thumb:SetPoint("TOP", track, "TOP", 0, -frac * (trackH - thumbH))
  end

  scroll:EnableMouseWheel(true)
  scroll:SetScript("OnMouseWheel", function(sf, delta)
    local range  = math.max(0, content:GetHeight() - sf:GetHeight())
    local newVal = math.max(0, math.min(range, sf:GetVerticalScroll() - delta * 40))
    sf:SetVerticalScroll(newVal)
    updateThumb()
  end)

  local function refreshLayout()
    local w = scroll:GetWidth()
    if w and w > 1 then content:SetWidth(w) end
    updateThumb()
  end
  parent:HookScript("OnSizeChanged", refreshLayout)
  parent:HookScript("OnShow", refreshLayout)

  scroll.content     = content
  scroll.updateThumb = updateThumb
  scroll.track       = track
  scroll.thumbTex    = thumbTex
  scroll.trackBg     = trackBg
  return scroll, content
end

-- ============================================================================
-- Live preview panel
-- ============================================================================
-- A miniature sample UI (sidebar + header + button + progress bar + colored
-- text) that repaints from cw.Theme on every theme / color edit. Returns the
-- outer frame, its height, and a repaint() closure.

local function buildPreviewPanel(parent, width)
  local T  = lib.Theme
  local widgets = {}  -- { type=..., ... } entries repainted by repaint()

  local outer = CreateFrame("Frame", nil, parent, "BackdropTemplate")
  outer:SetSize(width, 110)
  outer:SetBackdrop(lib.Backdrop)
  outer:SetBackdropColor(unpack(T.bg))
  outer:SetBackdropBorderColor(unpack(T.border))
  widgets[#widgets+1] = { type = "backdrop", frame = outer }

  -- Mini sidebar.
  local sidebar = CreateFrame("Frame", nil, outer)
  sidebar:SetWidth(80)
  sidebar:SetPoint("TOPLEFT",    outer, "TOPLEFT",    4, -4)
  sidebar:SetPoint("BOTTOMLEFT", outer, "BOTTOMLEFT", 4,  4)
  local sidebarBg = sidebar:CreateTexture(nil, "BACKGROUND")
  sidebarBg:SetAllPoints()
  sidebarBg:SetColorTexture(unpack(T.sidebar))
  widgets[#widgets+1] = { type = "texture", tex = sidebarBg, key = "sidebar" }

  for i, lbl in ipairs({ "Dashboard", "Tasks", "Settings" }) do
    local nav = sidebar:CreateFontString(nil, "OVERLAY")
    nav:SetFontObject(lib.Fonts.small)
    nav:SetPoint("TOPLEFT", sidebar, "TOPLEFT", 6, -6 - (i - 1) * 18)
    nav:SetText(lbl)
    local ck = (i == 1) and "text" or "textDim"
    nav:SetTextColor(unpack(T[ck]))
    widgets[#widgets+1] = { type = "text", fs = nav, key = ck }
    if i == 1 then
      local accent = sidebar:CreateTexture(nil, "ARTWORK")
      accent:SetSize(2, 14)
      accent:SetPoint("LEFT", sidebar, "LEFT", 0, 0)
      accent:SetPoint("TOP",  nav,     "TOP",  0, 0)
      accent:SetColorTexture(unpack(T.gold))
      widgets[#widgets+1] = { type = "texture", tex = accent, key = "gold" }
    end
  end

  -- Mini header.
  local header = CreateFrame("Frame", nil, outer)
  header:SetHeight(20)
  header:SetPoint("TOPLEFT", sidebar, "TOPRIGHT", 2, 0)
  header:SetPoint("RIGHT",   outer,   "RIGHT",   -4, 0)
  local headerBg = header:CreateTexture(nil, "BACKGROUND")
  headerBg:SetAllPoints()
  headerBg:SetColorTexture(unpack(T.header))
  widgets[#widgets+1] = { type = "texture", tex = headerBg, key = "header" }

  local title = header:CreateFontString(nil, "OVERLAY")
  title:SetFontObject(lib.Fonts.small)
  title:SetPoint("LEFT", header, "LEFT", 6, 0)
  title:SetText("Sample Panel")
  title:SetTextColor(unpack(T.gold))
  widgets[#widgets+1] = { type = "text", fs = title, key = "gold" }

  -- Content area.
  local body = CreateFrame("Frame", nil, outer)
  body:SetPoint("TOPLEFT",     header, "BOTTOMLEFT",  0, -2)
  body:SetPoint("BOTTOMRIGHT", outer,  "BOTTOMRIGHT", -4, 4)

  -- Sample button.
  local btn = CreateFrame("Frame", nil, body, "BackdropTemplate")
  btn:SetSize(80, 20)
  btn:SetPoint("TOPLEFT", body, "TOPLEFT", 6, -6)
  btn:SetBackdrop(lib.BackdropSmall)
  btn:SetBackdropColor(unpack(T.header))
  btn:SetBackdropBorderColor(unpack(T.border))
  widgets[#widgets+1] = { type = "button", frame = btn }
  local btnText = btn:CreateFontString(nil, "OVERLAY")
  btnText:SetFontObject(lib.Fonts.small)
  btnText:SetPoint("CENTER")
  btnText:SetText("Button")
  btnText:SetTextColor(unpack(T.text))
  widgets[#widgets+1] = { type = "text", fs = btnText, key = "text" }

  -- Sample progress bar.
  local barBg = CreateFrame("Frame", nil, body, "BackdropTemplate")
  barBg:SetSize(140, 12)
  barBg:SetPoint("LEFT", btn, "RIGHT", 8, 0)
  barBg:SetBackdrop({
    bgFile   = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    edgeSize = 8,
    insets   = { left = 2, right = 2, top = 2, bottom = 2 },
  })
  barBg:SetBackdropColor(0.05, 0.05, 0.08, 1)
  barBg:SetBackdropBorderColor(unpack(T.border))
  local barFill = barBg:CreateTexture(nil, "ARTWORK")
  barFill:SetPoint("TOPLEFT",    barBg, "TOPLEFT",    2, -2)
  barFill:SetPoint("BOTTOMLEFT", barBg, "BOTTOMLEFT", 2,  2)
  barFill:SetWidth(90)
  barFill:SetColorTexture(T.success[1], T.success[2], T.success[3], 0.8)
  widgets[#widgets+1] = { type = "bar", tex = barFill, key = "success" }

  -- Sample colored text.
  local texts = {
    { "Normal text",   "text",         0,   -32 },
    { "Dimmed label",  "textDim",      0,   -46 },
    { "Disabled",      "textDisabled", 80,  -46 },
    { "Success",       "success",      0,   -60 },
    { "Warning",       "warning",      60,  -60 },
    { "Error",         "error",        120, -60 },
    { "Arcane glow",   "arcane",       160, -32 },
    { "Brass trim",    "brass",        160, -46 },
  }
  for _, td in ipairs(texts) do
    local fs = body:CreateFontString(nil, "OVERLAY")
    fs:SetFontObject(lib.Fonts.small)
    fs:SetPoint("TOPLEFT", body, "TOPLEFT", 6 + td[3], td[4])
    fs:SetText(td[1])
    fs:SetTextColor(unpack(T[td[2]]))
    widgets[#widgets+1] = { type = "text", fs = fs, key = td[2] }
  end

  local function repaint()
    local TT = lib.Theme
    for _, w in ipairs(widgets) do
      if w.type == "backdrop" then
        w.frame:SetBackdropColor(unpack(TT.bg))
        w.frame:SetBackdropBorderColor(unpack(TT.border))
      elseif w.type == "button" then
        w.frame:SetBackdropColor(unpack(TT.header))
        w.frame:SetBackdropBorderColor(unpack(TT.border))
      elseif w.type == "texture" then
        local c = TT[w.key]
        if c then w.tex:SetColorTexture(c[1], c[2], c[3], c[4] or 1) end
      elseif w.type == "bar" then
        local c = TT[w.key]
        if c then w.tex:SetColorTexture(c[1], c[2], c[3], 0.8) end
      elseif w.type == "text" then
        local c = TT[w.key]
        if c then w.fs:SetTextColor(c[1], c[2], c[3], c[4] or 1) end
      end
    end
  end

  return outer, 110, repaint
end

-- ============================================================================
-- CreateUIScalingSettingsBlock — the Appearance editor
-- ============================================================================
-- A full scrolling theme / font editor. Returns a ScrollFrame that fills
-- `parent`; the caller drops it straight into a settings tab.
--
-- Content, top-down:
--   Description (optional)
--   Live preview panel  — repaints on every theme / color edit.
--   Profile row         — profile dropdown + New / Export / Import
--   Per-cog override    — checkbox + dropdown (only when opts.cog)
--   Font scale + UI scale sliders
--   Font family dropdown
--   Font preview rows   — sample text in each font key
--   Theme dropdown
--   Colors              — grouped editable swatches (click -> ColorPickerFrame)
--   Save as Custom / Export Theme / Import Theme
--   Reset to defaults
--
-- opts:
--   cog              string — render the per-cog override row; font scale /
--                             font family edits target that cog's override
--                             profile when one is active.
--   showFontFamily   bool   — default true
--   showTheme        bool   — default true (also gates the color editor)
--   description      string — header copy above the controls
--
-- Color editing targets the suite-wide active theme (cw.Theme), not a single
-- cog — per-cog theme is a planned stretch (cogworks #74). The Colors header
-- carries a one-line note so users aren't surprised.

local PAD       = 12          -- left edge for labels / buttons / swatches
local DD_INDENT = PAD - 16    -- dropdown frames sit ~16px right of their chrome
local ROW       = 24          -- swatch row pitch
local LABEL_GAP = 18          -- header-to-control gap

-- Grouped color keys for the swatch editor. Each entry: { groupLabel, {keys} }.
local COLOR_GROUPS = {
  { "Backgrounds", { "bg", "bgLight", "bgDark", "header", "sidebar", "border" } },
  { "Rows",        { "rowAlt", "rowHover" } },
  { "Accents",     { "gold", "arcane", "brass" } },
  { "Status",      { "success", "warning", "error" } },
  { "Text",        { "text", "textDim", "textDisabled" } },
}

function lib:CreateUIScalingSettingsBlock(parent, opts)
  opts = opts or {}
  local cog            = opts.cog
  local showFontFamily = opts.showFontFamily ~= false
  local showTheme      = opts.showTheme      ~= false
  local T              = self.Theme

  local scroll, content = makeScroller(parent)
  local cw = self

  -- Collected for refreshAll(): swatch repaints + the preview repaint.
  local swatches      = {}      -- { key, tex, hex }
  local previewRepaint            -- set once preview is built
  local fontPreviewRows = {}    -- fontstrings to re-skin on font change

  local function refreshAll()
    for _, sw in ipairs(swatches) do
      local color = cw.Theme[sw.key]
      if color then
        sw.tex:SetColorTexture(color[1], color[2], color[3], color[4] or 1)
        local r, g, b = math.floor(color[1] * 255 + 0.5),
                        math.floor(color[2] * 255 + 0.5),
                        math.floor(color[3] * 255 + 0.5)
        sw.hex:SetText(string.format("|cff888888#%02x%02x%02x|r", r, g, b))
      end
    end
    if previewRepaint then previewRepaint() end
  end

  local y = PAD

  -- Section-header helper -- advances the y-cursor past a header.
  local function section(text, extraGap)
    y = y + (extraGap or 14)
    cw:CreateSectionHeader(content, text, -y)
    y = y + 20
  end

  -- Description -------------------------------------------------------------
  if opts.description and opts.description ~= "" then
    local desc = content:CreateFontString(nil, "OVERLAY")
    desc:SetFontObject(self:GetFont("small"))
    desc:SetTextColor(unpack(T.textDim))
    desc:SetWordWrap(true)
    desc:SetText(opts.description)
    desc:SetPoint("TOPLEFT",  content, "TOPLEFT",  PAD, -y)
    desc:SetPoint("TOPRIGHT", content, "TOPRIGHT", -PAD, -y)
    desc:SetJustifyH("LEFT")
    y = y + math.max(desc:GetStringHeight(), 14) + 8
  end

  -- Live preview ------------------------------------------------------------
  section("Live Preview", 0)
  do
    local pvWidth = math.max(200, (content:GetWidth() or 460) - PAD * 2)
    local pv, pvH, repaint = buildPreviewPanel(content, pvWidth)
    pv:SetPoint("TOPLEFT",  content, "TOPLEFT",  PAD, -y)
    pv:SetPoint("TOPRIGHT", content, "TOPRIGHT", -PAD, -y)
    previewRepaint = repaint
    y = y + pvH + 6
  end

  -- Profile row -------------------------------------------------------------
  section("Profile")
  local profileOptions = function()
    local list = {}
    for _, name in ipairs(lib:GetProfileNames()) do
      list[#list + 1] = { key = name, label = name }
    end
    return list
  end

  local profileDD = makeDropdown(content, {
    label     = "Profile",
    width     = 160,
    optionsFn = profileOptions,
    initial   = lib:GetActiveProfile(),
    onChange  = function(name) lib:SetActiveProfile(name) end,
  })
  profileDD:SetPoint("TOPLEFT", content, "TOPLEFT", DD_INDENT, -(y + LABEL_GAP))

  local function refreshProfileDD()
    profileDD:RefreshOptions()
    profileDD:SetSelected(lib:GetActiveProfile())
  end

  local newBtn = self:CreateButton(content, "+ New", 60, 22, function()
    StaticPopup_Show("COGWORKS_NEW_PROFILE", nil, nil, { afterCreate = function(name)
      lib:SetActiveProfile(name)
      refreshProfileDD()
    end })
  end)
  newBtn:SetPoint("LEFT", profileDD, "RIGHT", -8, 2)

  local pExportBtn = self:CreateButton(content, "Export", 64, 22, function()
    local str = lib:ExportProfile(lib:GetActiveProfile())
    if str then StaticPopup_Show("COGWORKS_EXPORT_PROFILE", nil, nil, { exportString = str }) end
  end)
  pExportBtn:SetPoint("LEFT", newBtn, "RIGHT", 4, 0)

  local pImportBtn = self:CreateButton(content, "Import", 64, 22, function()
    StaticPopup_Show("COGWORKS_IMPORT_PROFILE", nil, nil, { afterImport = function(name)
      refreshProfileDD()
      lib:Print("Cogworks", "Imported profile: " .. name)
    end })
  end)
  pImportBtn:SetPoint("LEFT", pExportBtn, "RIGHT", 4, 0)

  y = y + LABEL_GAP + 26

  -- Per-cog override --------------------------------------------------------
  local overrideCheckbox, overrideDD
  if cog then
    local row = CreateFrame("Frame", nil, content)
    row:SetPoint("TOPLEFT",  content, "TOPLEFT",  PAD, -y)
    row:SetPoint("TOPRIGHT", content, "TOPRIGHT", -PAD, -y)
    row:SetHeight(28)

    overrideCheckbox = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
    overrideCheckbox:SetSize(24, 24)
    overrideCheckbox:SetPoint("LEFT", row, "LEFT", 0, 0)

    local label = row:CreateFontString(nil, "OVERLAY")
    label:SetFontObject(self:GetFont("normal"))
    label:SetTextColor(unpack(T.text))
    label:SetText("Override profile for " .. cog)
    label:SetPoint("LEFT", overrideCheckbox, "RIGHT", 4, 0)

    overrideDD = makeDropdown(row, {
      label     = "",
      width     = 130,
      optionsFn = profileOptions,
      onChange  = function(name) lib:SetCogProfile(cog, name) end,
    })
    overrideDD:SetPoint("LEFT", label, "RIGHT", 8, -2)

    local function applyOverrideState()
      local override = (function()
        local db = _G.CogworksSharedDB
        return db and db.cogOverrides and db.cogOverrides[cog]
      end)()
      overrideCheckbox:SetChecked(override ~= nil)
      if override then
        overrideDD:SetSelected(override)
        UIDropDownMenu_EnableDropDown(overrideDD)
      else
        UIDropDownMenu_SetText(overrideDD, "(suite default)")
        UIDropDownMenu_DisableDropDown(overrideDD)
      end
    end

    overrideCheckbox:SetScript("OnClick", function(c)
      if c:GetChecked() then
        lib:SetCogProfile(cog, lib:GetActiveProfile())
      else
        lib:SetCogProfile(cog, nil)
      end
      applyOverrideState()
    end)
    applyOverrideState()
    y = y + 30
  end

  -- Resolve where an override-eligible setting should be written. Returns the
  -- override profile table if cog has an active override, else nil (meaning
  -- "write to suite-active via SetSetting").
  local function overrideTarget()
    if not cog then return nil end
    local db = _G.CogworksSharedDB
    local pName = db and db.cogOverrides and db.cogOverrides[cog]
    if not pName or not db.profiles or not db.profiles[pName] then return nil end
    return db.profiles[pName]
  end

  -- Font scale + UI scale sliders ------------------------------------------
  section("Scale")
  y = y + LABEL_GAP
  local fontSlider = makeSlider(content, {
    label    = "Font scale",
    min      = SCALE_MIN, max = SCALE_MAX, step = SCALE_STEP,
    value    = (cog and lib:GetCogSetting(cog, "fontScale")) or self:GetSetting("fontScale") or 1.0,
    width    = 160,
    onChange = function(v)
      local target = overrideTarget()
      if target then
        target.fontScale = v
        lib:_RefreshCogFonts(cog)
      else
        lib:SetSetting("fontScale", v)
      end
    end,
  })
  fontSlider:SetPoint("TOPLEFT", content, "TOPLEFT", PAD, -y)

  local uiSlider = makeSlider(content, {
    label    = "UI scale",
    min      = SCALE_MIN, max = SCALE_MAX, step = SCALE_STEP,
    value    = self:GetSetting("uiScale") or 1.0,
    width    = 160,
    onChange = function(v) lib:SetSetting("uiScale", v) end,
  })
  uiSlider:SetPoint("TOPLEFT", fontSlider, "TOPRIGHT", 32, 0)

  y = y + 36

  -- Font family dropdown ----------------------------------------------------
  local familyDD
  if showFontFamily then
    section("Font")
    familyDD = makeDropdown(content, {
      label     = "Font family",
      width     = 200,
      optionsFn = function() return self:GetFontList() end,  -- {key,label,path}
      initial   = (cog and lib:GetCogSetting(cog, "fontFamily")) or self:GetSetting("fontFamily") or "default",
      onChange  = function(key)
        local target = overrideTarget()
        if target then
          target.fontFamily = key
          lib:_RefreshCogFonts(cog)
        else
          lib:SetSetting("fontFamily", key)
        end
      end,
    })
    familyDD:SetPoint("TOPLEFT", content, "TOPLEFT", DD_INDENT, -(y + LABEL_GAP))
    y = y + LABEL_GAP + 30

    -- Font preview rows -- one sample line per font key.
    for _, pf in ipairs({
      { "large",  "cw.Fonts.large - Page Titles" },
      { "normal", "cw.Fonts.normal - Body Text" },
      { "small",  "cw.Fonts.small - Labels & Descriptions" },
      { "header", "cw.Fonts.header - SECTION HEADERS" },
    }) do
      local fs = content:CreateFontString(nil, "OVERLAY")
      fs:SetFontObject(self:GetFont(pf[1]))
      fs:SetPoint("TOPLEFT", content, "TOPLEFT", PAD, -y)
      fs:SetText(pf[2])
      fs:SetTextColor(unpack(T.text))
      fontPreviewRows[#fontPreviewRows + 1] = { fs = fs, key = pf[1] }
      y = y + 22
    end
  end

  -- Theme dropdown ----------------------------------------------------------
  local themeDD
  if showTheme then
    section("Theme")
    themeDD = makeDropdown(content, {
      label     = "Theme",
      width     = 200,
      optionsFn = function()
        local list = {}
        for _, name in ipairs(lib:GetThemeNames()) do
          list[#list + 1] = { key = name, label = name }
        end
        return list
      end,
      initial   = self.activeThemeName,
      onChange  = function(name)
        lib:SetTheme(name)
        refreshAll()
      end,
    })
    themeDD:SetPoint("TOPLEFT", content, "TOPLEFT", DD_INDENT, -(y + LABEL_GAP))
    y = y + LABEL_GAP + 30
  end

  -- Editable color swatches -------------------------------------------------
  local function addSwatch(key, yPos)
    local color = cw.Theme[key]
    if not color then return yPos end

    local btn = CreateFrame("Button", nil, content)
    btn:SetSize(20, 20)
    btn:SetPoint("TOPLEFT", content, "TOPLEFT", PAD, -yPos)

    -- Border sits one layer behind the swatch fill.
    local borderTex = content:CreateTexture(nil, "ARTWORK", nil, -1)
    borderTex:SetSize(22, 22)
    borderTex:SetPoint("CENTER", btn, "CENTER")
    borderTex:SetColorTexture(0.5, 0.5, 0.5, 0.5)

    local tex = btn:CreateTexture(nil, "ARTWORK")
    tex:SetAllPoints()
    tex:SetColorTexture(color[1], color[2], color[3], color[4] or 1)

    local text = content:CreateFontString(nil, "OVERLAY")
    text:SetFontObject(cw.Fonts.normal)
    text:SetPoint("LEFT", btn, "RIGHT", 8, 0)
    text:SetText(key)
    text:SetTextColor(unpack(T.text))

    local hex = content:CreateFontString(nil, "OVERLAY")
    hex:SetFontObject(cw.Fonts.small)
    hex:SetPoint("LEFT", text, "RIGHT", 8, 0)
    local r, g, b = math.floor(color[1] * 255 + 0.5),
                    math.floor(color[2] * 255 + 0.5),
                    math.floor(color[3] * 255 + 0.5)
    hex:SetText(string.format("|cff888888#%02x%02x%02x|r", r, g, b))

    swatches[#swatches + 1] = { key = key, tex = tex, hex = hex }

    btn:SetScript("OnClick", function()
      local cur = cw.Theme[key]
      ColorPickerFrame:SetupColorPickerAndShow({
        r = cur[1], g = cur[2], b = cur[3],
        hasOpacity = true, opacity = cur[4] or 1,
        swatchFunc = function()
          local nr, ng, nb = ColorPickerFrame:GetColorRGB()
          local na = (ColorPickerFrame.GetColorAlpha and ColorPickerFrame:GetColorAlpha()) or 1
          cw:SetThemeColor(key, nr, ng, nb, na)
          refreshAll()
        end,
        cancelFunc = function(prev)
          if prev then
            cw:SetThemeColor(key, prev.r, prev.g, prev.b, prev.a or 1)
            refreshAll()
          end
        end,
      })
    end)

    return yPos + ROW
  end

  if showTheme then
    section("Colors")
    local note = content:CreateFontString(nil, "OVERLAY")
    note:SetFontObject(self:GetFont("small"))
    note:SetTextColor(unpack(T.textDim))
    note:SetWordWrap(true)
    note:SetText("Click a swatch to edit. Color edits apply to the active theme "
               .. "suite-wide (shared by every cog).")
    note:SetPoint("TOPLEFT",  content, "TOPLEFT",  PAD, -y)
    note:SetPoint("TOPRIGHT", content, "TOPRIGHT", -PAD, -y)
    note:SetJustifyH("LEFT")
    y = y + math.max(note:GetStringHeight(), 14) + 8

    for _, group in ipairs(COLOR_GROUPS) do
      local groupLabel = content:CreateFontString(nil, "OVERLAY")
      groupLabel:SetFontObject(cw.Fonts.small)
      groupLabel:SetPoint("TOPLEFT", content, "TOPLEFT", PAD, -y)
      groupLabel:SetText("|cffd4a017" .. group[1] .. "|r")
      y = y + 18
      for _, key in ipairs(group[2]) do
        y = addSwatch(key, y)
      end
      y = y + 6
    end

    -- Save / Export / Import theme ------------------------------------------
    section("Save & Share", 4)
    local saveBtn = self:CreateButton(content, "Save as Custom", 140, 26, function()
      local popup = cw:CreatePopup({ title = "Save Theme", width = 360, height = 140 })
      local nameBox = CreateFrame("EditBox", nil, popup.content, "InputBoxTemplate")
      nameBox:SetSize(280, 22)
      nameBox:SetPoint("TOPLEFT", popup.content, "TOPLEFT", 8, -8)
      nameBox:SetAutoFocus(true)
      nameBox:SetText("My Theme")
      nameBox:SetFontObject(cw.Fonts.normal)
      popup:SetButtons({
        { label = "Save", onClick = function()
          local n = nameBox:GetText():gsub("^%s+", ""):gsub("%s+$", "")
          if n ~= "" then
            cw:SaveCustomTheme(n)
            cw:SetTheme(n)
            if themeDD then themeDD:RefreshOptions(); themeDD:SetSelected(n) end
            refreshAll()
            cw:Print("Cogworks", "Theme saved: " .. n)
          end
        end },
        { label = "Cancel" },
      })
      popup:Show()
    end)
    saveBtn:SetPoint("TOPLEFT", content, "TOPLEFT", PAD, -y)

    local exportBtn = self:CreateButton(content, "Export Theme", 110, 26, function()
      local str = cw:ExportTheme()
      local popup = cw:CreatePopup({ title = "Export Theme", width = 480, height = 160 })
      local box = CreateFrame("EditBox", nil, popup.content, "InputBoxTemplate")
      box:SetSize(420, 22)
      box:SetPoint("TOPLEFT", popup.content, "TOPLEFT", 8, -8)
      box:SetText(str or "")
      box:SetFontObject(cw.Fonts.small)
      box:SetAutoFocus(true)
      box:HighlightText()
      local hint = popup.content:CreateFontString(nil, "OVERLAY")
      hint:SetFontObject(cw.Fonts.small)
      hint:SetPoint("TOPLEFT", box, "BOTTOMLEFT", 0, -6)
      hint:SetText("Ctrl+C to copy, then share the string.")
      hint:SetTextColor(unpack(T.textDim))
      popup:SetButtons({ { label = "Close" } })
      popup:Show()
    end)
    exportBtn:SetPoint("LEFT", saveBtn, "RIGHT", 6, 0)

    local importBtn = self:CreateButton(content, "Import Theme", 110, 26, function()
      local popup = cw:CreatePopup({ title = "Import Theme", width = 480, height = 160 })
      local box = CreateFrame("EditBox", nil, popup.content, "InputBoxTemplate")
      box:SetSize(420, 22)
      box:SetPoint("TOPLEFT", popup.content, "TOPLEFT", 8, -8)
      box:SetFontObject(cw.Fonts.small)
      box:SetAutoFocus(true)
      local hint = popup.content:CreateFontString(nil, "OVERLAY")
      hint:SetFontObject(cw.Fonts.small)
      hint:SetPoint("TOPLEFT", box, "BOTTOMLEFT", 0, -6)
      hint:SetText("Paste a CogworksTheme: string and click Import.")
      hint:SetTextColor(unpack(T.textDim))
      popup:SetButtons({
        { label = "Import", onClick = function()
          local name, err = cw:ImportTheme(box:GetText())
          if name then
            cw:SetTheme(name)
            if themeDD then themeDD:RefreshOptions(); themeDD:SetSelected(name) end
            refreshAll()
            cw:Print("Cogworks", "Theme imported: " .. name)
          else
            cw:PrintError("Cogworks", "Import failed: " .. (err or "unknown"))
          end
        end },
        { label = "Cancel" },
      })
      popup:Show()
    end)
    importBtn:SetPoint("LEFT", exportBtn, "RIGHT", 6, 0)

    y = y + 34
  end

  -- Reset button ------------------------------------------------------------
  y = y + 8
  local resetBtn = self:CreateButton(content, "Reset to defaults", 140, 24, function()
    local defaults = lib:GetSettingDefaults()
    for k, v in pairs(defaults) do lib:SetSetting(k, v) end
    lib:SetTheme(defaults.theme or "Cogworks")
    fontSlider:SetSliderValue(defaults.fontScale or 1.0)
    uiSlider:SetSliderValue(defaults.uiScale or 1.0)
    if familyDD then familyDD:SetSelected(defaults.fontFamily or "default") end
    if themeDD  then themeDD:SetSelected(defaults.theme or "Cogworks") end
    refreshAll()
  end)
  resetBtn:SetPoint("TOPLEFT", content, "TOPLEFT", PAD, -y)
  y = y + 32

  content:SetHeight(y + PAD)
  scroll:updateThumb()
  refreshAll()

  -- Reflect external changes (another settings page editing the same SVs, a
  -- theme preset switch, a color edit elsewhere).
  local function effectiveFontScale()
    return (cog and lib:GetCogSetting(cog, "fontScale")) or lib:GetSetting("fontScale") or 1.0
  end
  local function effectiveFontFamily()
    return (cog and lib:GetCogSetting(cog, "fontFamily")) or lib:GetSetting("fontFamily") or "default"
  end

  local owner = {}
  self.RegisterCallback(owner, self.Events.SettingsChanged, function(_, key)
    if key == "fontScale"  then fontSlider:SetSliderValue(effectiveFontScale()) end
    if key == "uiScale"    then uiSlider:SetSliderValue(lib:GetSetting("uiScale") or 1.0) end
    if key == "fontFamily" and familyDD then
      familyDD:SetSelected(effectiveFontFamily())
      for _, row in ipairs(fontPreviewRows) do row.fs:SetFontObject(lib:GetFont(row.key)) end
    end
    if key == "theme" then
      if themeDD then themeDD:SetSelected(lib.activeThemeName) end
      refreshAll()
    end
    if key == "themeColor" then refreshAll() end
    -- Profile / override changes: refresh profile dropdown and effective values.
    if key == "activeProfile" or key == "cogProfile" then
      refreshProfileDD()
      fontSlider:SetSliderValue(effectiveFontScale())
      if familyDD then familyDD:SetSelected(effectiveFontFamily()) end
    end
  end)
  scroll._settingsOwner = owner

  -- Public handles (back-compat with the pre-MINOR-30 block).
  scroll.profileDropdown = profileDD
  scroll.fontSlider      = fontSlider
  scroll.uiSlider        = uiSlider
  scroll.familyDropdown  = familyDD
  scroll.themeDropdown   = themeDD
  scroll.resetButton     = resetBtn
  scroll.Refresh         = refreshAll
  return scroll
end

-- Preferred entry point for the Appearance-tab convention. CreateUIScaling-
-- SettingsBlock already returns a ScrollFrame anchored to fill `parent`, so
-- this is a pure pass-through alias — kept as a distinct, well-named entry
-- point per the convention (see the header block above). (COG-71)
function lib:CreateAppearanceTab(parent, opts)
  return self:CreateUIScalingSettingsBlock(parent, opts)
end

-- ============================================================================
-- RegisterScalingFrame
-- ============================================================================
-- Subscribes a frame to uiScale changes and (optionally) persists its
-- geometry to a caller-owned SV table.
--
-- opts:
--   cog              string  — owning cog (forward-compat for per-cog scale)
--   saveTo           table   — where to read/write {x, y, w, h}
--   scaleOverrideKey string  — read scale from a specific lib.settings key
--                              instead of "uiScale" (rare; use sparingly)
--
-- Side effects:
--   • frame:SetScale called immediately, and on every uiScale change.
--   • If saveTo provided and saveTo.x/y exist, frame is repositioned on first
--     show; OnDragStop / OnSizeChanged hooks persist subsequent changes.

function lib:RegisterScalingFrame(frame, opts)
  opts = opts or {}
  local saveTo  = opts.saveTo
  local scaleKey = opts.scaleOverrideKey or "uiScale"

  local function applyScale()
    local s = self:GetSetting(scaleKey) or 1.0
    frame:SetScale(s)
  end
  applyScale()

  if saveTo then
    -- Restore persisted geometry on first show.
    if saveTo.x and saveTo.y then
      frame:ClearAllPoints()
      frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", saveTo.x, saveTo.y)
    end
    if saveTo.w and saveTo.h then
      frame:SetSize(saveTo.w, saveTo.h)
    end
    -- Persist on move (caller is responsible for setting the frame movable
    -- and wiring OnDragStart → StartMovingOrSizing on the appropriate region).
    frame:HookScript("OnDragStop", function(f)
      saveTo.x, saveTo.y = f:GetLeft(), f:GetBottom()
    end)
    frame:HookScript("OnSizeChanged", function(_, w, h)
      saveTo.w, saveTo.h = w, h
    end)
  end

  local owner = {}
  self.RegisterCallback(owner, self.Events.SettingsChanged, function(_, key)
    if key == scaleKey then applyScale() end
  end)
  frame._scalingOwner = owner

  return frame
end
