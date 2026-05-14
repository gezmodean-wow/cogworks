-- Cogworks-1.0/Scaling.lua | UI scaling settings block + per-frame scale registration.
--
-- Consumer-facing primitives:
--
--   cw:CreateAppearanceTab(parent, opts)
--     **Preferred entry point.** Builds the standard cogworks-managed
--     appearance controls (profile picker + per-cog override + font/UI scale
--     sliders + font family + theme dropdown + reset). Drop into a dedicated
--     tab in every cog's settings UI for suite-wide consistency. (COG-71)
--
--   cw:CreateUIScalingSettingsBlock(parent, opts)
--     Legacy name for the same primitive. Kept for back-compat; prefer
--     CreateAppearanceTab in new code.
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
-- fontFamily are scoped to `cog`; uiScale + theme stay suite-wide for the
-- v0.14.x line (per-cog theme is a planned multi-release stretch).
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
local MODULE_MINOR = 3
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
-- CreateUIScalingSettingsBlock
-- ============================================================================
-- Layout (top-down, left-aligned):
--   Description           (optional, dim)
--   Profile [dd] [+ New] [Export] [Import]
--   ☐ Override profile for this cog: [dd]   (when opts.cog)
--   Font scale [slider]            UI scale [slider]
--   Font family [dd]               Theme [dd]
--   [Reset to defaults]
--
-- opts:
--   cog              string  — when set, render the per-cog override row and
--                              wire font scale / font family edits to write
--                              into that cog's override profile if active.
--   showFontFamily   bool    — default true
--   showTheme        bool    — default true
--   description      string  — header copy above the controls

local BLOCK_PAD       = 12
local CONTROL_GAP_Y   = 32
local SLIDER_LABEL_GAP = 18

function lib:CreateUIScalingSettingsBlock(parent, opts)
  opts = opts or {}
  local cog            = opts.cog
  local showFontFamily = opts.showFontFamily ~= false
  local showTheme      = opts.showTheme      ~= false
  local T              = self.Theme

  local block = CreateFrame("Frame", nil, parent)
  block:SetSize(parent:GetWidth() or 480, 1)  -- height grown below

  local y = BLOCK_PAD

  -- Description -------------------------------------------------------------
  if opts.description and opts.description ~= "" then
    local desc = block:CreateFontString(nil, "OVERLAY")
    desc:SetFontObject(self:GetFont("small"))
    desc:SetTextColor(unpack(T.textDim))
    desc:SetWordWrap(true)
    desc:SetText(opts.description)
    desc:SetPoint("TOPLEFT",  block, "TOPLEFT",  BLOCK_PAD, -y)
    desc:SetPoint("TOPRIGHT", block, "TOPRIGHT", -BLOCK_PAD, -y)
    desc:SetJustifyH("LEFT")
    y = y + desc:GetStringHeight() + 8
  end

  -- Profile row -------------------------------------------------------------
  local profileDD
  local profileOptions = function()
    local list = {}
    for _, name in ipairs(lib:GetProfileNames()) do
      list[#list + 1] = { key = name, label = name }
    end
    return list
  end

  profileDD = makeDropdown(block, {
    label    = "Profile",
    width    = 160,
    optionsFn = profileOptions,
    initial  = lib:GetActiveProfile(),
    onChange = function(name) lib:SetActiveProfile(name) end,
  })
  profileDD:SetPoint("TOPLEFT", block, "TOPLEFT", BLOCK_PAD - 16, -(y + SLIDER_LABEL_GAP))

  local function refreshProfileDD()
    profileDD:RefreshOptions()
    profileDD:SetSelected(lib:GetActiveProfile())
  end

  local newBtn = self:CreateButton(block, "+ New", 60, 22, function()
    StaticPopup_Show("COGWORKS_NEW_PROFILE", nil, nil, { afterCreate = function(name)
      lib:SetActiveProfile(name)
      refreshProfileDD()
    end })
  end)
  newBtn:SetPoint("LEFT", profileDD, "RIGHT", -8, 2)

  local exportBtn = self:CreateButton(block, "Export", 64, 22, function()
    local str = lib:ExportProfile(lib:GetActiveProfile())
    if str then StaticPopup_Show("COGWORKS_EXPORT_PROFILE", nil, nil, { exportString = str }) end
  end)
  exportBtn:SetPoint("LEFT", newBtn, "RIGHT", 4, 0)

  local importBtn = self:CreateButton(block, "Import", 64, 22, function()
    StaticPopup_Show("COGWORKS_IMPORT_PROFILE", nil, nil, { afterImport = function(name)
      refreshProfileDD()
      lib:Print("Cogworks", "Imported profile: " .. name)
    end })
  end)
  importBtn:SetPoint("LEFT", exportBtn, "RIGHT", 4, 0)

  y = y + SLIDER_LABEL_GAP + 26

  -- Per-cog override -------------------------------------------------------
  local overrideCheckbox, overrideDD
  if cog then
    local row = CreateFrame("Frame", nil, block)
    row:SetPoint("TOPLEFT",  block, "TOPLEFT",  BLOCK_PAD, -y)
    row:SetPoint("TOPRIGHT", block, "TOPRIGHT", -BLOCK_PAD, -y)
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
    y = y + 28
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
  y = y + SLIDER_LABEL_GAP
  local fontSlider = makeSlider(block, {
    label   = "Font scale",
    min     = SCALE_MIN, max = SCALE_MAX, step = SCALE_STEP,
    value   = (cog and lib:GetCogSetting(cog, "fontScale")) or self:GetSetting("fontScale") or 1.0,
    width   = 160,
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
  fontSlider:SetPoint("TOPLEFT", block, "TOPLEFT", BLOCK_PAD, -y)

  local uiSlider = makeSlider(block, {
    label   = "UI scale",
    min     = SCALE_MIN, max = SCALE_MAX, step = SCALE_STEP,
    value   = self:GetSetting("uiScale") or 1.0,
    width   = 160,
    onChange = function(v) lib:SetSetting("uiScale", v) end,
  })
  uiSlider:SetPoint("TOPLEFT", fontSlider, "TOPRIGHT", 32, 0)

  y = y + 36

  -- Font family + theme dropdowns ------------------------------------------
  local familyDD, themeDD
  if showFontFamily then
    familyDD = makeDropdown(block, {
      label   = "Font family",
      width   = 160,
      optionsFn = function()
        return self:GetFontList()  -- already returns {key, label, path}
      end,
      initial = (cog and lib:GetCogSetting(cog, "fontFamily")) or self:GetSetting("fontFamily") or "default",
      onChange = function(key)
        local target = overrideTarget()
        if target then
          target.fontFamily = key
          lib:_RefreshCogFonts(cog)
        else
          lib:SetSetting("fontFamily", key)
        end
      end,
    })
    familyDD:SetPoint("TOPLEFT", block, "TOPLEFT", BLOCK_PAD - 16, -(y + SLIDER_LABEL_GAP))
    y = y + SLIDER_LABEL_GAP + 26
  end

  if showTheme then
    themeDD = makeDropdown(block, {
      label   = "Theme",
      width   = 160,
      optionsFn = function()
        local list = {}
        for _, name in ipairs(lib:GetThemeNames()) do
          list[#list + 1] = { key = name, label = name }
        end
        return list
      end,
      initial = self.activeThemeName,
      onChange = function(name) lib:SetTheme(name) end,
    })
    if familyDD then
      themeDD:SetPoint("TOPLEFT", familyDD, "TOPRIGHT", 16, 0)
    else
      themeDD:SetPoint("TOPLEFT", block, "TOPLEFT", BLOCK_PAD - 16, -(y + SLIDER_LABEL_GAP))
      y = y + SLIDER_LABEL_GAP + 26
    end
  end

  if showFontFamily and showTheme then
    -- Already accounted for one row; both share that row.
  end

  y = y + 16

  -- Reset button ------------------------------------------------------------
  local resetBtn = self:CreateButton(block, "Reset to defaults", 140, 24, function()
    local defaults = lib:GetSettingDefaults()
    for k, v in pairs(defaults) do lib:SetSetting(k, v) end
    lib:SetTheme(defaults.theme or "Cogworks")
    fontSlider:SetSliderValue(defaults.fontScale or 1.0)
    uiSlider:SetSliderValue(defaults.uiScale or 1.0)
    if familyDD then familyDD:SetSelected(defaults.fontFamily or "default") end
    if themeDD  then themeDD:SetSelected(defaults.theme or "Cogworks") end
  end)
  resetBtn:SetPoint("TOPLEFT", block, "TOPLEFT", BLOCK_PAD, -y)
  y = y + 32

  block:SetHeight(y + BLOCK_PAD)

  -- Reflect external changes (e.g. another settings page edited the same SVs).
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
    if key == "fontFamily" and familyDD then familyDD:SetSelected(effectiveFontFamily()) end
    if key == "theme"      and themeDD  then themeDD:SetSelected(lib.activeThemeName) end
    -- Profile / override changes: refresh profile dropdown and per-cog effective values.
    if key == "activeProfile" or key == "cogProfile" then
      refreshProfileDD()
      fontSlider:SetSliderValue(effectiveFontScale())
      if familyDD then familyDD:SetSelected(effectiveFontFamily()) end
    end
  end)
  block._settingsOwner = owner

  block.profileDropdown = profileDD
  block.fontSlider      = fontSlider
  block.uiSlider        = uiSlider
  block.familyDropdown  = familyDD
  block.themeDropdown   = themeDD
  block.resetButton     = resetBtn
  return block
end

-- Preferred entry point. Identical to CreateUIScalingSettingsBlock; the name
-- makes the convention from the top-of-file comment unambiguous at call sites
-- (`local appearance = cw:CreateAppearanceTab(content, { cog = "MyCog" })`).
-- See the Appearance-tab convention block above for the standard adoption
-- shape (dedicated last tab in the cog's settings TabPanel). (COG-71)
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
