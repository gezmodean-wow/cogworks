-- Cogworks-1.0/SegmentedControl.lua | Pill-toggle segmented control.
--
-- Horizontal row of small pill buttons sharing a "one is active" invariant.
-- Distinct from CreateTabPanel (which owns content swapping + a strip border)
-- and CreateNavButton (sidebar entry, 32px tall with a left accent bar). This
-- is the right shape for inline state-only filters: "7d / 30d / 90d / All",
-- "Saleable / Owned", "All / Sales / Purchases".
--
-- Usage:
--   local seg = cw:CreateSegmentedControl(parent, {
--     options = {
--       { key = "7d",  label = "7d"  },
--       { key = "30d", label = "30d" },
--       { key = "all", label = "All" },
--     },
--     initial  = "30d",                -- defaults to options[1].key
--     size     = "small",              -- "small" (22) | "normal" (26) | "large" (30)
--     gap      = 0,                    -- inter-button gap; default 0 (segmented strip)
--     onChange = function(key) ... end,
--   })
--   seg:SetSelected("90d")
--   seg:GetSelected() -- "90d"
--
-- Re-fits on SettingsChanged for fontScale/fontFamily so labels never clip.

local lib = LibStub("Cogworks-1.0")
if not lib then return end

-- Module load guard. See Sections.lua for rationale.
local MODULE_MINOR = 1
lib._modules = lib._modules or {}
if (lib._modules.SegmentedControl or 0) >= MODULE_MINOR then return end
lib._modules.SegmentedControl = MODULE_MINOR

local SIZES = {
  small  = { h = 22, padH = 10 },
  normal = { h = 26, padH = 12 },
  large  = { h = 30, padH = 14 },
}

local function repaint(btn, T)
  if btn._selected then
    btn.bg:SetColorTexture(T.brass[1], T.brass[2], T.brass[3], 0.55)
    btn.text:SetTextColor(unpack(T.text))
  elseif btn._hovered then
    btn.bg:SetColorTexture(1, 1, 1, 0.08)
    btn.text:SetTextColor(unpack(T.text))
  else
    btn.bg:SetColorTexture(T.bgLight[1], T.bgLight[2], T.bgLight[3], 0.6)
    btn.text:SetTextColor(unpack(T.textDim))
  end
end

local function makePill(parent, opt, sizeDef, fontObject, onClick)
  local T = lib.Theme
  local btn = CreateFrame("Button", nil, parent, "BackdropTemplate")
  btn:SetHeight(sizeDef.h)
  btn:SetBackdrop({
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    edgeSize = 8,
    insets   = { left = 1, right = 1, top = 1, bottom = 1 },
  })
  btn:SetBackdropBorderColor(T.border[1], T.border[2], T.border[3], 0.6)

  btn.bg = btn:CreateTexture(nil, "BACKGROUND")
  btn.bg:SetPoint("TOPLEFT", btn, "TOPLEFT", 1, -1)
  btn.bg:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -1, 1)

  btn.text = btn:CreateFontString(nil, "OVERLAY")
  btn.text:SetFontObject(fontObject)
  btn.text:SetPoint("CENTER")
  btn.text:SetText(opt.label or opt.key)

  btn._selected = false
  btn._hovered  = false
  btn._key      = opt.key

  btn:SetScript("OnEnter", function(b) b._hovered = true;  repaint(b, lib.Theme) end)
  btn:SetScript("OnLeave", function(b) b._hovered = false; repaint(b, lib.Theme) end)
  btn:SetScript("OnClick", function(b) onClick(b._key) end)
  repaint(btn, T)
  return btn
end

-- Auto-size each pill from its label width + horizontal padding, anchor in
-- order. Returns the total composite width.
local function layoutPills(buttons, sizeDef, gap)
  local x = 0
  for _, btn in ipairs(buttons) do
    btn.text:SetText(btn.text:GetText())  -- recompute string width after font reflow
    local w = btn.text:GetStringWidth() + sizeDef.padH * 2
    btn:SetWidth(w)
    btn:ClearAllPoints()
    btn:SetPoint("TOPLEFT", btn:GetParent(), "TOPLEFT", x, 0)
    x = x + w + gap
  end
  return x - gap
end

function lib:CreateSegmentedControl(parent, opts)
  opts = opts or {}
  assert(type(opts.options) == "table" and #opts.options > 0,
    "CreateSegmentedControl: opts.options required (at least one)")
  local sizeDef = SIZES[opts.size or "small"] or SIZES.small
  local gap     = opts.gap or 0

  local container = CreateFrame("Frame", nil, parent)
  container:SetHeight(sizeDef.h)

  local buttons   = {}
  local selected  = opts.initial or opts.options[1].key

  local function setSelected(key, fireCallback)
    selected = key
    for _, btn in ipairs(buttons) do
      btn._selected = (btn._key == key)
      repaint(btn, lib.Theme)
    end
    if fireCallback and opts.onChange then opts.onChange(key) end
  end

  for _, opt in ipairs(opts.options) do
    local btn = makePill(container, opt, sizeDef, self:GetFont("normal"), function(k)
      if k ~= selected then setSelected(k, true) end
    end)
    buttons[#buttons + 1] = btn
  end

  local function applyLayout()
    local w = layoutPills(buttons, sizeDef, gap)
    container:SetWidth(w)
  end
  applyLayout()
  setSelected(selected, false)

  -- Reflow when font scale / family changes so pills re-size to the new label widths.
  local owner = {}
  lib.RegisterCallback(owner, lib.Events.SettingsChanged, function(_, key)
    if key == "fontScale" or key == "fontFamily" then
      for _, btn in ipairs(buttons) do
        btn.text:SetFontObject(lib:GetFont("normal"))
      end
      applyLayout()
    end
  end)
  container._fontReflowOwner = owner

  function container:GetSelected() return selected end
  function container:SetSelected(key)
    for _, opt in ipairs(opts.options) do
      if opt.key == key then setSelected(key, false); return true end
    end
    return false
  end
  container.buttons = buttons
  return container
end
