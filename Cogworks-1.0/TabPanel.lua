-- Cogworks-1.0/TabPanel.lua | Inline horizontal tab panel.
--
-- Tab strip on top, content area below. Pages are lazy-built on first
-- activation, so a tab whose content is expensive to construct doesn't
-- pay that cost until the user clicks it.
--
-- Distinct from CreateNavButton: nav buttons are sidebar entries that
-- pick which page to show. CreateTabPanel is the in-page horizontal
-- tab strip (settings dialogs, multi-step forms, research / inventory
-- breakdowns) — same widget shape every cog reaches for, themed once
-- here so we stop redoing it.
--
-- Usage:
--
--   local panel = cw:CreateTabPanel(parent, {
--     tabs = {
--       { key = "general",  label = "General",  build = function(c)
--           local f = CreateFrame("Frame", nil, c); f:SetAllPoints()
--           -- populate f
--           return f
--         end },
--       { key = "advanced", label = "Advanced", build = function(c) ... end },
--     },
--     initialTab  = "general",       -- defaults to first tab
--     tabHeight   = 26,              -- defaults to 26
--     onTabChange = function(key) ... end,
--   })
--   panel:SetAllPoints()             -- caller sizes the panel
--   panel:SetActiveTab("advanced")
--   local key = panel:GetActiveTab()
--   panel.content                    -- content frame; tabs build into this
--
-- Each tab's build(parent) must return a Frame anchored to parent —
-- the panel handles Show/Hide as the active tab changes.

local lib = LibStub("Cogworks-1.0")
if not lib then return end

-- Module load guard. See Sections.lua for rationale.
local MODULE_MINOR = 15
lib._modules = lib._modules or {}
if (lib._modules.TabPanel or 0) >= MODULE_MINOR then return end
lib._modules.TabPanel = MODULE_MINOR

local TAB_PAD_H          = 14   -- horizontal padding inside each tab button
local TAB_GAP            = 2    -- gap between adjacent tabs
local STRIP_PAD_LEFT     = 4    -- inset from strip's left edge
local STRIP_BORDER_HEIGHT = 1
local DEFAULT_TAB_HEIGHT = 26

-- Build a single tab button matching the suite theme. Returns the button
-- with a :SetActive(bool) method that updates its visual state. Hover and
-- active states mirror CreateNavButton's pattern (subtle bg lift on hover,
-- gold accent + brighter text on active) to keep the suite look consistent.
local function makeTabButton(parent, label, fontObject)
  local T = lib.Theme
  local btn = CreateFrame("Button", nil, parent)

  btn.bg = btn:CreateTexture(nil, "BACKGROUND")
  btn.bg:SetAllPoints()
  btn.bg:SetColorTexture(1, 1, 1, 0)

  btn.text = btn:CreateFontString(nil, "OVERLAY")
  btn.text:SetFontObject(fontObject)
  btn.text:SetPoint("CENTER")
  btn.text:SetText(label)
  btn.text:SetTextColor(unpack(T.textDim))

  -- Active accent: 2px gold line along the bottom edge (mirrors the
  -- vertical gold strip CreateNavButton uses on its left edge).
  btn.accent = btn:CreateTexture(nil, "OVERLAY")
  btn.accent:SetHeight(2)
  btn.accent:SetPoint("BOTTOMLEFT", btn, "BOTTOMLEFT", 0, 0)
  btn.accent:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", 0, 0)
  btn.accent:SetColorTexture(unpack(T.gold))
  btn.accent:Hide()

  local active = false
  local function repaint(hovered)
    if active then
      btn.bg:SetColorTexture(1, 1, 1, 0.06)
      btn.text:SetTextColor(unpack(T.text))
      btn.accent:Show()
    elseif hovered then
      btn.bg:SetColorTexture(1, 1, 1, 0.08)
      btn.text:SetTextColor(unpack(T.text))
      btn.accent:Hide()
    else
      btn.bg:SetColorTexture(1, 1, 1, 0)
      btn.text:SetTextColor(unpack(T.textDim))
      btn.accent:Hide()
    end
  end

  function btn:SetActive(v)
    active = v and true or false
    repaint(false)
  end
  btn:SetScript("OnEnter", function() repaint(true) end)
  btn:SetScript("OnLeave", function() repaint(false) end)

  repaint(false)
  return btn
end

function lib:CreateTabPanel(parent, opts)
  opts = opts or {}
  assert(type(opts.tabs) == "table" and #opts.tabs > 0,
    "CreateTabPanel: opts.tabs required (at least one tab)")

  local T          = self.Theme
  local tabHeight  = opts.tabHeight or DEFAULT_TAB_HEIGHT

  local panel = CreateFrame("Frame", nil, parent)

  -- Tab strip
  local tabStrip = CreateFrame("Frame", nil, panel)
  tabStrip:SetHeight(tabHeight)
  tabStrip:SetPoint("TOPLEFT")
  tabStrip:SetPoint("TOPRIGHT")
  panel.tabStrip = tabStrip

  -- Strip border separates the tab strip from the content area.
  local stripBorder = panel:CreateTexture(nil, "BACKGROUND")
  stripBorder:SetHeight(STRIP_BORDER_HEIGHT)
  stripBorder:SetPoint("TOPLEFT", tabStrip, "BOTTOMLEFT", 0, 0)
  stripBorder:SetPoint("TOPRIGHT", tabStrip, "BOTTOMRIGHT", 0, 0)
  stripBorder:SetColorTexture(unpack(T.border))

  -- Content area below the strip.
  local content = CreateFrame("Frame", nil, panel)
  content:SetPoint("TOPLEFT", stripBorder, "BOTTOMLEFT", 0, 0)
  content:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", 0, 0)
  panel.content = content

  -- Index tabs by key for O(1) lookup.
  local tabsByKey = {}
  for _, def in ipairs(opts.tabs) do
    assert(def.key, "CreateTabPanel: each tab needs a key")
    tabsByKey[def.key] = def
  end

  local tabButtons = {}  -- key → button
  local tabPages   = {}  -- key → page frame (lazy-built)
  local activeTab

  local function pageFor(key)
    if not tabPages[key] then
      local def = tabsByKey[key]
      if def and def.build then
        local page = def.build(content)
        if page then
          tabPages[key] = page
        end
      end
    end
    return tabPages[key]
  end

  local function setActive(key)
    if not tabsByKey[key] then return end
    if activeTab == key then return end
    if activeTab then
      local prevPage = tabPages[activeTab]
      if prevPage then prevPage:Hide() end
      if tabButtons[activeTab] then tabButtons[activeTab]:SetActive(false) end
    end

    activeTab = key
    local newPage = pageFor(key)
    if newPage then newPage:Show() end
    if tabButtons[key] then tabButtons[key]:SetActive(true) end

    if opts.onTabChange then opts.onTabChange(key) end
  end

  -- Layout tab buttons left-to-right with auto-width derived from label
  -- text. Re-runs on font scale / family changes so wider labels at higher
  -- font scales push subsequent tabs along correctly.
  local function layoutTabs()
    local x = STRIP_PAD_LEFT
    local btnHeight = tabHeight - STRIP_BORDER_HEIGHT
    for _, def in ipairs(opts.tabs) do
      local btn = tabButtons[def.key]
      btn.text:SetFontObject(self:GetFont("normal") or "GameFontNormal")
      local textWidth = btn.text:GetStringWidth()
      local btnWidth = math.max(60, textWidth + TAB_PAD_H * 2)
      btn:SetSize(btnWidth, btnHeight)
      btn:ClearAllPoints()
      btn:SetPoint("TOPLEFT", tabStrip, "TOPLEFT", x, 0)
      x = x + btnWidth + TAB_GAP
    end
  end

  -- Build buttons in order.
  for _, def in ipairs(opts.tabs) do
    local btn = makeTabButton(tabStrip, def.label, self:GetFont("normal") or "GameFontNormal")
    tabButtons[def.key] = btn
    btn:SetScript("OnClick", function() setActive(def.key) end)
  end
  layoutTabs()

  -- Re-fit on font scale / family change so labels don't clip.
  local owner = {}
  self.RegisterCallback(owner, self.Events.SettingsChanged, function(_, key)
    if key == "fontScale" or key == "fontFamily" then
      layoutTabs()
    end
  end)
  panel._fontReflowOwner = owner

  function panel:SetActiveTab(key) setActive(key) end
  function panel:GetActiveTab()    return activeTab end

  -- Initial activation. Defaults to first tab.
  setActive(opts.initialTab or opts.tabs[1].key)

  return panel
end
