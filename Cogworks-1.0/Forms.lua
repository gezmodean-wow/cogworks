-- Cogworks-1.0/Forms.lua | Settings-row form helpers.
--
-- Labeled-row variants of the base UI primitives, sized for the standard
-- "settings page" layout. Each helper returns (row, consumedHeight) so callers
-- can stack rows with a simple y-cursor:
--
--   local y = 8
--   local row, h = cw:CreateSettingsCheckbox(parent, { label = "Foo", value = v, onChange = fn })
--   row:SetPoint("TOPLEFT", 0, -y); row:SetPoint("TOPRIGHT", 0, -y); y = y + h
--
-- All rows re-font and re-lay on SettingsChanged for fontScale / fontFamily.
-- A row's height can change after a font-scale event; callers that want to
-- reflow their stack should subscribe via opts.onHeightChanged or re-walk
-- their layout using row:GetConsumedHeight().

local lib = LibStub("Cogworks-1.0")
if not lib then return end

-- Module load guard. See Sections.lua for the rationale.
local MODULE_MINOR = 15
lib._modules = lib._modules or {}
if (lib._modules.Forms or 0) >= MODULE_MINOR then return end
lib._modules.Forms = MODULE_MINOR

local ROW_PAD_LEFT  = 8
local ROW_PAD_RIGHT = 8
local ROW_PAD_TOP   = 4
local ROW_PAD_BOT   = 4
local DESC_GAP      = 2   -- gap between main row and description
local CONTROL_H     = 24  -- height of the main control row (checkbox / button)
local INPUT_H       = 22  -- height of the main input row

-- Compute total row height for a label + optional description.
local function rowHeight(controlH, descFs)
  local descH = (descFs and descFs:IsShown()) and (descFs:GetStringHeight() + DESC_GAP) or 0
  return ROW_PAD_TOP + controlH + descH + ROW_PAD_BOT
end

-- Place description beneath the main row, indented under the label.
local function anchorDescription(descFs, row, indent, mainH)
  descFs:ClearAllPoints()
  descFs:SetPoint("TOPLEFT", row, "TOPLEFT",
    ROW_PAD_LEFT + indent, -(ROW_PAD_TOP + mainH + DESC_GAP))
  descFs:SetPoint("RIGHT", row, "RIGHT", -ROW_PAD_RIGHT, 0)
end

-- Subscribe `callback` to fontScale / fontFamily SettingsChanged events;
-- pin the owner table to the row so it isn't garbage-collected.
local function subscribeFontReflow(row, callback)
  local owner = {}
  lib.RegisterCallback(owner, lib.Events.SettingsChanged, function(_, key)
    if key == "fontScale" or key == "fontFamily" then
      callback()
    end
  end)
  row._fontReflowOwner = owner
end

-- ============================================================================
-- CreateSettingsCheckbox
-- ============================================================================
-- Layout:
--   [ ] Label
--       Description (dim, optional, indented under label)
--
-- opts (all but label optional):
--   label             string  — main label  (required)
--   description       string  — dim subtitle below label
--   value             bool    — initial checked state
--   onChange          fn(c)   — fires when user toggles
--   width             number  — row width; defaults to parent width
--   onHeightChanged   fn(h)   — fires after a font-scale reflow

function lib:CreateSettingsCheckbox(parent, opts)
  assert(type(opts) == "table" and opts.label, "CreateSettingsCheckbox: opts.label required")
  local T = self.Theme

  local row = CreateFrame("Frame", nil, parent)
  if opts.width then row:SetWidth(opts.width) else row:SetWidth(parent:GetWidth()) end

  local cb = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
  cb:SetSize(CONTROL_H, CONTROL_H)
  cb:SetPoint("TOPLEFT", row, "TOPLEFT", ROW_PAD_LEFT, -ROW_PAD_TOP)

  local labelFs = row:CreateFontString(nil, "OVERLAY")
  labelFs:SetFontObject(self:GetFont("normal") or "GameFontNormal")
  labelFs:SetPoint("LEFT", cb, "RIGHT", 4, 0)
  labelFs:SetPoint("RIGHT", row, "RIGHT", -ROW_PAD_RIGHT, 0)
  labelFs:SetJustifyH("LEFT")
  labelFs:SetTextColor(unpack(T.text))
  labelFs:SetText(opts.label)

  local descFs
  if opts.description and opts.description ~= "" then
    descFs = row:CreateFontString(nil, "OVERLAY")
    descFs:SetFontObject(self:GetFont("small") or "GameFontDisableSmall")
    descFs:SetJustifyH("LEFT")
    descFs:SetTextColor(unpack(T.textDim))
    descFs:SetWordWrap(true)
    descFs:SetText(opts.description)
    anchorDescription(descFs, row, CONTROL_H + 4, CONTROL_H)
  end

  cb:SetChecked(opts.value and true or false)
  cb:SetScript("OnClick", function(c)
    local checked = c:GetChecked()
    PlaySound(checked and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON
                       or SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF)
    if opts.onChange then opts.onChange(checked) end
  end)

  local function applyLayout()
    local h = rowHeight(CONTROL_H, descFs)
    row:SetHeight(h)
    return h
  end

  row.checkbox = cb
  row.label    = labelFs
  function row:GetConsumedHeight() return row:GetHeight() end
  function row:SetValue(v) cb:SetChecked(v and true or false) end
  function row:GetValue() return cb:GetChecked() end

  subscribeFontReflow(row, function()
    labelFs:SetFontObject(lib:GetFont("normal") or "GameFontNormal")
    if descFs then descFs:SetFontObject(lib:GetFont("small") or "GameFontDisableSmall") end
    local h = applyLayout()
    if opts.onHeightChanged then opts.onHeightChanged(h) end
  end)

  local h = applyLayout()
  return row, h
end

-- ============================================================================
-- CreateSettingsButton
-- ============================================================================
-- Layout:
--   Label                                          [Button]
--   Description (dim, optional)
--
-- opts:
--   label             string  — left-side label  (required)
--   description       string  — dim subtitle
--   buttonText        string  — text on the action button  (required)
--   buttonWidth       number  — default 100
--   onClick           fn()    — required
--   width             number
--   onHeightChanged   fn(h)

function lib:CreateSettingsButton(parent, opts)
  assert(type(opts) == "table" and opts.label, "CreateSettingsButton: opts.label required")
  assert(opts.buttonText, "CreateSettingsButton: opts.buttonText required")
  assert(type(opts.onClick) == "function", "CreateSettingsButton: opts.onClick required")
  local T = self.Theme

  local row = CreateFrame("Frame", nil, parent)
  if opts.width then row:SetWidth(opts.width) else row:SetWidth(parent:GetWidth()) end

  local btnW = opts.buttonWidth or 100
  local btn = self:CreateButton(row, opts.buttonText, btnW, CONTROL_H, opts.onClick)
  btn:ClearAllPoints()
  btn:SetPoint("TOPRIGHT", row, "TOPRIGHT", -ROW_PAD_RIGHT, -ROW_PAD_TOP)

  local labelFs = row:CreateFontString(nil, "OVERLAY")
  labelFs:SetFontObject(self:GetFont("normal") or "GameFontNormal")
  labelFs:SetPoint("LEFT", row, "LEFT", ROW_PAD_LEFT, 0)
  labelFs:SetPoint("RIGHT", btn, "LEFT", -8, 0)
  labelFs:SetPoint("TOP", btn, "TOP", 0, 0)
  labelFs:SetPoint("BOTTOM", btn, "BOTTOM", 0, 0)
  labelFs:SetJustifyH("LEFT")
  labelFs:SetJustifyV("MIDDLE")
  labelFs:SetTextColor(unpack(T.text))
  labelFs:SetText(opts.label)

  local descFs
  if opts.description and opts.description ~= "" then
    descFs = row:CreateFontString(nil, "OVERLAY")
    descFs:SetFontObject(self:GetFont("small") or "GameFontDisableSmall")
    descFs:SetJustifyH("LEFT")
    descFs:SetTextColor(unpack(T.textDim))
    descFs:SetWordWrap(true)
    descFs:SetText(opts.description)
    anchorDescription(descFs, row, 0, CONTROL_H)
  end

  local function applyLayout()
    local h = rowHeight(CONTROL_H, descFs)
    row:SetHeight(h)
    return h
  end

  row.button = btn
  row.label  = labelFs
  function row:GetConsumedHeight() return row:GetHeight() end

  subscribeFontReflow(row, function()
    labelFs:SetFontObject(lib:GetFont("normal") or "GameFontNormal")
    if descFs then descFs:SetFontObject(lib:GetFont("small") or "GameFontDisableSmall") end
    local h = applyLayout()
    if opts.onHeightChanged then opts.onHeightChanged(h) end
  end)

  local h = applyLayout()
  return row, h
end

-- ============================================================================
-- CreateSettingsInput
-- ============================================================================
-- Layout:
--   Label                                          [input] suffix
--   Description (dim, optional)
--
-- opts:
--   label             string   — required
--   description       string   — dim subtitle
--   value             string|number — initial value (tostring'd into the box)
--   numeric           bool     — restrict input to numbers; commits as number
--   inputWidth        number   — default 100
--   maxLetters        number   — character cap
--   placeholder       string   — placeholder shown when empty (advisory only;
--                                most callers use description instead)
--   suffix            string   — dim label rendered to the right of the input
--                                ("hours", "%"). Use Get/SetSuffix to mutate
--                                later. The input is auto-shrunk to leave
--                                room for the suffix.
--   validate          fn(v)→ok,err — called on commit. If ok is false, the
--                                input reverts to the last committed value,
--                                row:Flash(err) plays a red border flash, and
--                                onChange does NOT fire. Use this for client-
--                                side range / format checks.
--   onChange          fn(v)    — fires on Enter / focus loss with the
--                                validated value (string or number depending
--                                on `numeric`).
--   width             number
--   onHeightChanged   fn(h)
--
-- Returned row also exposes:
--   row:Flash(errMsg?) — plays the red border flash. Optional message is
--                        printed via lib:PrintError. Useful when a backend
--                        rejects a value that passed local validate.
--   row:GetSuffix() / row:SetSuffix(text) — get or change the suffix label;
--                        passing nil/"" hides it and reclaims the input width.

function lib:CreateSettingsInput(parent, opts)
  assert(type(opts) == "table" and opts.label, "CreateSettingsInput: opts.label required")
  local T = self.Theme

  local row = CreateFrame("Frame", nil, parent)
  if opts.width then row:SetWidth(opts.width) else row:SetWidth(parent:GetWidth()) end

  local inputW = opts.inputWidth or 100
  local edit = CreateFrame("EditBox", nil, row, "InputBoxTemplate")
  edit:SetSize(inputW, INPUT_H)
  edit:SetAutoFocus(false)
  edit:SetFontObject(self:GetFont("normal") or "GameFontNormal")
  if opts.maxLetters then edit:SetMaxLetters(opts.maxLetters) end
  if opts.numeric then edit:SetNumeric(true) end
  if opts.value ~= nil then edit:SetText(tostring(opts.value)) end

  -- Suffix label (dim) anchored at row TOPRIGHT. Hidden until SetSuffix gives
  -- it text. Edit's right anchor below switches between row and suffix based
  -- on whether the suffix is visible.
  local suffixFs = row:CreateFontString(nil, "OVERLAY")
  suffixFs:SetFontObject(self:GetFont("small") or "GameFontDisableSmall")
  suffixFs:SetTextColor(unpack(T.textDim))
  suffixFs:SetPoint("TOPRIGHT", row, "TOPRIGHT", -ROW_PAD_RIGHT, -(ROW_PAD_TOP + 4))
  suffixFs:Hide()

  local function suffixVisible()
    return suffixFs:IsShown() and suffixFs:GetText() and suffixFs:GetText() ~= ""
  end

  local function reanchorEdit()
    edit:ClearAllPoints()
    edit:SetSize(inputW, INPUT_H)
    if suffixVisible() then
      edit:SetPoint("TOPRIGHT", suffixFs, "TOPLEFT", -4, 2)
    else
      -- InputBoxTemplate has internal left padding from its own border
      -- textures — offset right by 4 so the visible right edge aligns with
      -- other rows.
      edit:SetPoint("TOPRIGHT", row, "TOPRIGHT", -ROW_PAD_RIGHT - 4, -(ROW_PAD_TOP + 1))
    end
  end

  if opts.suffix and opts.suffix ~= "" then
    suffixFs:SetText(opts.suffix)
    suffixFs:Show()
  end
  reanchorEdit()

  -- Red flash overlay used by row:Flash and the validate-failure path. We
  -- layer a 1px tooltip-style border around the edit and play an alpha
  -- fade-out so the indicator is visible but transient.
  local flashOverlay = CreateFrame("Frame", nil, row, "BackdropTemplate")
  flashOverlay:SetPoint("TOPLEFT",     edit, "TOPLEFT",     -2,  2)
  flashOverlay:SetPoint("BOTTOMRIGHT", edit, "BOTTOMRIGHT",  2, -2)
  flashOverlay:SetBackdrop({
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    edgeSize = 8,
  })
  flashOverlay:SetBackdropBorderColor(1, 0.25, 0.25, 1)
  flashOverlay:SetFrameLevel(edit:GetFrameLevel() + 1)
  flashOverlay:Hide()

  local flashAnim  = flashOverlay:CreateAnimationGroup()
  local flashAlpha = flashAnim:CreateAnimation("Alpha")
  flashAlpha:SetFromAlpha(1)
  flashAlpha:SetToAlpha(0)
  flashAlpha:SetDuration(0.6)
  flashAnim:SetScript("OnFinished", function() flashOverlay:Hide() end)

  local function flashError(msg)
    flashOverlay:Show()
    flashOverlay:SetAlpha(1)
    flashAnim:Stop()
    flashAnim:Play()
    if msg and msg ~= "" then
      lib:PrintError("Cogworks", msg)
    end
  end

  local lastCommitted = opts.value
  local function commit()
    local raw = edit:GetText()
    local val = opts.numeric and tonumber(raw) or raw

    if opts.validate then
      local ok, err = opts.validate(val)
      if not ok then
        edit:SetText(tostring(lastCommitted or ""))
        edit:ClearFocus()
        flashError(err)
        return
      end
    end

    edit:ClearFocus()
    if val ~= lastCommitted then
      lastCommitted = val
      if opts.onChange then opts.onChange(val) end
    end
  end
  edit:SetScript("OnEnterPressed", commit)
  edit:SetScript("OnEscapePressed", function()
    edit:SetText(tostring(lastCommitted or ""))
    edit:ClearFocus()
  end)
  edit:SetScript("OnEditFocusLost", commit)

  local labelFs = row:CreateFontString(nil, "OVERLAY")
  labelFs:SetFontObject(self:GetFont("normal") or "GameFontNormal")
  labelFs:SetPoint("LEFT", row, "LEFT", ROW_PAD_LEFT, 0)
  labelFs:SetPoint("RIGHT", edit, "LEFT", -8, 0)
  labelFs:SetPoint("TOP", edit, "TOP", 0, 0)
  labelFs:SetPoint("BOTTOM", edit, "BOTTOM", 0, 0)
  labelFs:SetJustifyH("LEFT")
  labelFs:SetJustifyV("MIDDLE")
  labelFs:SetTextColor(unpack(T.text))
  labelFs:SetText(opts.label)

  local descFs
  if opts.description and opts.description ~= "" then
    descFs = row:CreateFontString(nil, "OVERLAY")
    descFs:SetFontObject(self:GetFont("small") or "GameFontDisableSmall")
    descFs:SetJustifyH("LEFT")
    descFs:SetTextColor(unpack(T.textDim))
    descFs:SetWordWrap(true)
    descFs:SetText(opts.description)
    anchorDescription(descFs, row, 0, INPUT_H + 2)
  end

  local function applyLayout()
    local h = rowHeight(INPUT_H + 2, descFs)
    row:SetHeight(h)
    return h
  end

  row.input  = edit
  row.label  = labelFs
  row.suffix = suffixFs
  function row:GetConsumedHeight() return row:GetHeight() end
  function row:GetValue()
    local raw = edit:GetText()
    return opts.numeric and tonumber(raw) or raw
  end
  function row:SetValue(v)
    lastCommitted = v
    edit:SetText(tostring(v or ""))
  end
  function row:Flash(errMsg) flashError(errMsg) end
  function row:GetSuffix()
    return suffixFs:IsShown() and suffixFs:GetText() or nil
  end
  function row:SetSuffix(text)
    if not text or text == "" then
      suffixFs:Hide()
    else
      suffixFs:SetText(text)
      suffixFs:Show()
    end
    reanchorEdit()
  end

  subscribeFontReflow(row, function()
    labelFs:SetFontObject(lib:GetFont("normal") or "GameFontNormal")
    edit:SetFontObject(lib:GetFont("normal") or "GameFontNormal")
    suffixFs:SetFontObject(lib:GetFont("small") or "GameFontDisableSmall")
    if descFs then descFs:SetFontObject(lib:GetFont("small") or "GameFontDisableSmall") end
    reanchorEdit()
    local h = applyLayout()
    if opts.onHeightChanged then opts.onHeightChanged(h) end
  end)

  local h = applyLayout()
  return row, h
end
