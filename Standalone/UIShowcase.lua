-- Standalone/UIShowcase.lua
-- Interactive widget showcase for Cogworks-1.0 UI primitives.
-- Opens with /cogworks ui — lets you poke at every shared widget in-game.

local addonName, ns = ...
local cw = LibStub("Cogworks-1.0")
local T = cw.Theme

-- ============================================================================
-- Main frame
-- ============================================================================

local FRAME_WIDTH, FRAME_HEIGHT = 680, 480
local SIDEBAR_WIDTH = 160

local showcase  -- forward ref; created lazily

local pages = {}       -- [pageKey] = builder function
local pageFrames = {}  -- [pageKey] = content frame (created on first visit)
local navButtons = {}  -- [pageKey] = nav button
local activePage       -- current page key

local function showPage(key)
  if activePage == key then return end

  -- hide old
  if activePage and pageFrames[activePage] then
    pageFrames[activePage]:Hide()
    if navButtons[activePage] then
      cw:SetNavButtonActive(navButtons[activePage], false)
    end
  end

  -- build on first visit
  if not pageFrames[key] and pages[key] then
    pageFrames[key] = pages[key](showcase.content)
  end

  -- show new
  if pageFrames[key] then
    pageFrames[key]:Show()
  end
  if navButtons[key] then
    cw:SetNavButtonActive(navButtons[key], true)
  end
  activePage = key
end

-- ============================================================================
-- Frame builder (called once on first /cogworks ui)
-- ============================================================================

local function createShowcase()
  local f = CreateFrame("Frame", "CogworksShowcase", UIParent, "BackdropTemplate")
  f:SetSize(FRAME_WIDTH, FRAME_HEIGHT)
  f:SetPoint("CENTER")
  f:SetBackdrop(cw.Backdrop)
  f:SetBackdropColor(unpack(T.bg))
  f:SetBackdropBorderColor(unpack(T.border))
  f:SetFrameStrata("DIALOG")
  f:SetMovable(true)
  f:SetResizable(true)
  f:SetResizeBounds(520, 360, 1000, 700)
  f:SetClampedToScreen(true)
  tinsert(UISpecialFrames, "CogworksShowcase")

  -- Title bar
  local titleBar = CreateFrame("Frame", nil, f)
  titleBar:SetHeight(32)
  titleBar:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
  titleBar:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, 0)
  titleBar:EnableMouse(true)
  titleBar:RegisterForDrag("LeftButton")
  titleBar:SetScript("OnDragStart", function() f:StartMoving() end)
  titleBar:SetScript("OnDragStop", function() f:StopMovingOrSizing() end)

  local titleBg = titleBar:CreateTexture(nil, "BACKGROUND")
  titleBg:SetAllPoints()
  titleBg:SetColorTexture(unpack(T.header))

  local titleText = titleBar:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  titleText:SetPoint("LEFT", titleBar, "LEFT", 12, 0)
  titleText:SetText("|cffd4a017Cogworks|r UI Showcase")
  f.titleText = titleText

  local closeBtn = cw:CreateIconButton(titleBar, "Interface\\Buttons\\UI-Panel-MinimizeButton-Up", 20, "Close", function()
    f:Hide()
  end)
  closeBtn:SetPoint("RIGHT", titleBar, "RIGHT", -6, 0)

  -- Version label
  local verText = titleBar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  verText:SetPoint("RIGHT", closeBtn, "LEFT", -8, 0)
  verText:SetText("v" .. cw.version .. " (MINOR " .. cw.minorVersion .. ")")
  verText:SetTextColor(unpack(T.textDim))

  -- Sidebar
  local sidebar = CreateFrame("Frame", nil, f)
  sidebar:SetWidth(SIDEBAR_WIDTH)
  sidebar:SetPoint("TOPLEFT", titleBar, "BOTTOMLEFT", 0, 0)
  sidebar:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 0, 0)

  local sidebarBg = sidebar:CreateTexture(nil, "BACKGROUND")
  sidebarBg:SetAllPoints()
  sidebarBg:SetColorTexture(unpack(T.sidebar))

  -- Sidebar border (right edge)
  local sidebarEdge = sidebar:CreateTexture(nil, "ARTWORK")
  sidebarEdge:SetSize(1, 1)
  sidebarEdge:SetPoint("TOPRIGHT", sidebar, "TOPRIGHT", 0, 0)
  sidebarEdge:SetPoint("BOTTOMRIGHT", sidebar, "BOTTOMRIGHT", 0, 0)
  sidebarEdge:SetColorTexture(unpack(T.border))

  -- Content area
  local content = CreateFrame("Frame", nil, f)
  content:SetPoint("TOPLEFT", sidebar, "TOPRIGHT", 0, 0)
  content:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, 0)
  f.content = content

  -- Resize grip
  local grip = CreateFrame("Button", nil, f)
  grip:SetSize(16, 16)
  grip:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -2, 2)
  grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
  grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
  grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
  grip:RegisterForDrag("LeftButton")
  grip:SetScript("OnDragStart", function() f:StartSizing("BOTTOMRIGHT") end)
  grip:SetScript("OnDragStop", function() f:StopMovingOrSizing() end)

  -- Build nav buttons
  local navDefs = {
    { key = "buttons",  label = "Buttons",     icon = "Interface\\Buttons\\UI-MicroButton-Abilities-Up" },
    { key = "controls", label = "Controls",    icon = "Interface\\Buttons\\UI-MicroButton-MainMenu-Up" },
    { key = "nav",      label = "Navigation",  icon = "Interface\\Buttons\\UI-MicroButton-EJ-Up" },
    { key = "theme",    label = "Theme",       icon = "Interface\\Buttons\\UI-MicroButton-Collections-Up" },
    { key = "layout",   label = "Layout",      icon = "Interface\\Buttons\\UI-MicroButton-Questlog-Up" },
  }

  local navHeader = cw:CreateSectionHeader(sidebar, "Pages", -12)

  local yOff = -30
  for _, def in ipairs(navDefs) do
    local btn = cw:CreateNavButton(sidebar, { label = def.label, icon = def.icon }, function()
      showPage(def.key)
    end)
    btn:SetPoint("TOPLEFT", sidebar, "TOPLEFT", 0, yOff)
    btn:SetPoint("RIGHT", sidebar, "RIGHT", -1, 0)
    navButtons[def.key] = btn
    yOff = yOff - 32
  end

  return f
end

-- ============================================================================
-- Helper: scrollable content page
-- ============================================================================

local function createPageFrame(parent)
  local scroll = CreateFrame("ScrollFrame", nil, parent, "UIPanelScrollFrameTemplate")
  scroll:SetPoint("TOPLEFT", parent, "TOPLEFT", 8, -8)
  scroll:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -28, 8)

  local child = CreateFrame("Frame", nil, scroll)
  child:SetWidth(parent:GetWidth() - 40)
  scroll:SetScrollChild(child)

  -- re-fit child width on parent resize
  parent:HookScript("OnSizeChanged", function()
    child:SetWidth(parent:GetWidth() - 40)
  end)

  scroll:SetAllPoints()
  return scroll, child
end

-- ============================================================================
-- Page: Buttons
-- ============================================================================

pages.buttons = function(parent)
  local f = CreateFrame("Frame", nil, parent)
  f:SetAllPoints()
  local scroll, c = createPageFrame(f)

  local y = 0

  -- Section: CreateButton
  cw:CreateSectionHeader(c, "CreateButton", y)
  y = y - 20

  local sizes = {
    { "Small",   80,  22 },
    { "Normal",  120, 26 },
    { "Large",   180, 32 },
    { "Wide",    260, 26 },
  }

  for _, s in ipairs(sizes) do
    local btn = cw:CreateButton(c, s[1] .. " (" .. s[2] .. "x" .. s[3] .. ")", s[2], s[3], function()
      cw:Print("Cogworks", "Clicked: " .. s[1])
    end)
    btn:SetPoint("TOPLEFT", c, "TOPLEFT", 8, y)
    y = y - (s[3] + 8)
  end

  -- Disabled-looking button demo
  y = y - 10
  cw:CreateSectionHeader(c, "Disabled State (manual)", y)
  y = y - 20

  local disBtn = cw:CreateButton(c, "Disabled", 120, 26, nil)
  disBtn:SetPoint("TOPLEFT", c, "TOPLEFT", 8, y)
  disBtn.text:SetTextColor(unpack(T.textDisabled))
  disBtn:SetBackdropBorderColor(0.2, 0.2, 0.25, 1)
  disBtn:EnableMouse(false)
  y = y - 36

  -- Section: CreateIconButton
  y = y - 10
  cw:CreateSectionHeader(c, "CreateIconButton", y)
  y = y - 20

  local icons = {
    { "Interface\\Buttons\\UI-GuildButton-PublicNote-Up", 16, "Small (16px)" },
    { "Interface\\Buttons\\UI-GuildButton-PublicNote-Up", 24, "Medium (24px)" },
    { "Interface\\Buttons\\UI-GuildButton-PublicNote-Up", 32, "Large (32px)" },
    { "Interface\\HELPFRAME\\HelpIcon-KnowledgeBase", 24, "Knowledge" },
    { "Interface\\HELPFRAME\\HelpIcon-Bug", 24, "Bug" },
    { "Interface\\HELPFRAME\\HelpIcon-CharacterStuck", 24, "Stuck" },
  }

  local xOff = 8
  for _, ic in ipairs(icons) do
    local btn = cw:CreateIconButton(c, ic[1], ic[2], ic[3], function()
      cw:Print("Cogworks", "Icon clicked: " .. ic[3])
    end)
    btn:SetPoint("TOPLEFT", c, "TOPLEFT", xOff, y)
    xOff = xOff + ic[2] + 12
    if xOff > 300 then
      xOff = 8
      y = y - 40
    end
  end

  y = y - 50
  c:SetHeight(math.abs(y) + 20)
  return f
end

-- ============================================================================
-- Page: Controls
-- ============================================================================

pages.controls = function(parent)
  local f = CreateFrame("Frame", nil, parent)
  f:SetAllPoints()
  local scroll, c = createPageFrame(f)

  local y = 0

  -- Checkboxes
  cw:CreateSectionHeader(c, "CreateCheckbox", y)
  y = y - 24

  local cb1 = cw:CreateCheckbox(c, "Basic checkbox", nil, false, function(v)
    cw:Print("Cogworks", "Basic: " .. tostring(v))
  end)
  cb1:SetPoint("TOPLEFT", c, "TOPLEFT", 8, y)
  y = y - 30

  local cb2 = cw:CreateCheckbox(c, "With description", "This checkbox has a description line below the label that word-wraps when it gets long enough.", true, function(v)
    cw:Print("Cogworks", "Described: " .. tostring(v))
  end)
  cb2:SetPoint("TOPLEFT", c, "TOPLEFT", 8, y)
  y = y - 56

  local cb3 = cw:CreateCheckbox(c, "Another option", "Short desc.", false, function(v)
    cw:Print("Cogworks", "Another: " .. tostring(v))
  end)
  cb3:SetPoint("TOPLEFT", c, "TOPLEFT", 8, y)
  y = y - 50

  -- Progress bars
  cw:CreateSectionHeader(c, "CreateProgressBar", y)
  y = y - 24

  local barData = {
    { 3, 10, "Default green",  nil },
    { 7, 10, "Gold accent",    T.gold },
    { 10, 10, "Full (success)", T.success },
    { 2, 10, "Low (warning)",  T.warning },
    { 0, 10, "Empty (error)",  T.error },
    { 5, 10, "Arcane purple",  T.arcane },
  }

  for _, bd in ipairs(barData) do
    local label = c:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    label:SetPoint("TOPLEFT", c, "TOPLEFT", 8, y)
    label:SetText(bd[3])
    label:SetTextColor(unpack(T.textDim))

    local bar = cw:CreateProgressBar(c, 200, 16)
    bar:SetPoint("TOPLEFT", c, "TOPLEFT", 140, y + 1)
    if bd[4] then bar:SetBarColor(bd[4][1], bd[4][2], bd[4][3]) end
    bar:SetProgress(bd[1], bd[2])

    y = y - 24
  end

  -- Interactive progress bar
  y = y - 10
  cw:CreateSectionHeader(c, "Interactive Progress", y)
  y = y - 24

  local interBar = cw:CreateProgressBar(c, 260, 20)
  interBar:SetPoint("TOPLEFT", c, "TOPLEFT", 8, y)
  local interVal = 0
  interBar:SetProgress(interVal, 20)

  y = y - 30
  local incBtn = cw:CreateButton(c, "+1", 60, 24, function()
    interVal = math.min(20, interVal + 1)
    interBar:SetProgress(interVal, 20)
  end)
  incBtn:SetPoint("TOPLEFT", c, "TOPLEFT", 8, y)

  local decBtn = cw:CreateButton(c, "-1", 60, 24, function()
    interVal = math.max(0, interVal - 1)
    interBar:SetProgress(interVal, 20)
  end)
  decBtn:SetPoint("TOPLEFT", c, "TOPLEFT", 78, y)

  local resetBtn = cw:CreateButton(c, "Reset", 70, 24, function()
    interVal = 0
    interBar:SetProgress(interVal, 20)
  end)
  resetBtn:SetPoint("TOPLEFT", c, "TOPLEFT", 148, y)

  local fillBtn = cw:CreateButton(c, "Fill", 60, 24, function()
    interVal = 20
    interBar:SetProgress(interVal, 20)
  end)
  fillBtn:SetPoint("TOPLEFT", c, "TOPLEFT", 228, y)

  y = y - 40
  c:SetHeight(math.abs(y) + 20)
  return f
end

-- ============================================================================
-- Page: Navigation
-- ============================================================================

pages.nav = function(parent)
  local f = CreateFrame("Frame", nil, parent)
  f:SetAllPoints()
  local scroll, c = createPageFrame(f)

  local y = 0

  cw:CreateSectionHeader(c, "CreateNavButton + SetNavButtonActive", y)
  y = y - 20

  local desc = c:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  desc:SetPoint("TOPLEFT", c, "TOPLEFT", 8, y)
  desc:SetPoint("RIGHT", c, "RIGHT", -8, 0)
  desc:SetJustifyH("LEFT")
  desc:SetWordWrap(true)
  desc:SetText("Click any button below to toggle it active. Only one is active at a time — the same pattern used for sidebar navigation in every cog's main frame.")
  desc:SetTextColor(unpack(T.textDim))
  y = y - 40

  -- Demo nav panel
  local navPanel = CreateFrame("Frame", nil, c, "BackdropTemplate")
  navPanel:SetSize(180, 200)
  navPanel:SetPoint("TOPLEFT", c, "TOPLEFT", 8, y)
  navPanel:SetBackdrop(cw.BackdropSmall)
  navPanel:SetBackdropColor(unpack(T.sidebar))
  navPanel:SetBackdropBorderColor(unpack(T.border))

  local demoNavs = {}
  local demoItems = {
    { label = "Dashboard",  icon = "Interface\\Buttons\\UI-MicroButton-Abilities-Up" },
    { label = "Tasks",      icon = "Interface\\Buttons\\UI-MicroButton-Questlog-Up" },
    { label = "Characters", icon = "Interface\\Buttons\\UI-MicroButton-Socials-Up" },
    { label = "Settings",   icon = "Interface\\Buttons\\UI-MicroButton-MainMenu-Up" },
    { label = "About",      icon = "Interface\\Buttons\\UI-MicroButton-Help-Up" },
  }

  local navY = -8
  for _, item in ipairs(demoItems) do
    local btn = cw:CreateNavButton(navPanel, item, function()
      for _, b in ipairs(demoNavs) do
        cw:SetNavButtonActive(b, false)
      end
      cw:SetNavButtonActive(btn, true)
      cw:Print("Cogworks", "Nav: " .. item.label)
    end)
    btn:SetPoint("TOPLEFT", navPanel, "TOPLEFT", 0, navY)
    btn:SetPoint("RIGHT", navPanel, "RIGHT", 0, 0)
    demoNavs[#demoNavs + 1] = btn
    navY = navY - 32
  end

  -- Activate first by default
  cw:SetNavButtonActive(demoNavs[1], true)

  -- Badge demo
  local badgePanel = CreateFrame("Frame", nil, c, "BackdropTemplate")
  badgePanel:SetSize(180, 110)
  badgePanel:SetPoint("TOPLEFT", navPanel, "TOPRIGHT", 16, 0)
  badgePanel:SetBackdrop(cw.BackdropSmall)
  badgePanel:SetBackdropColor(unpack(T.sidebar))
  badgePanel:SetBackdropBorderColor(unpack(T.border))

  local badgeHeader = cw:CreateSectionHeader(badgePanel, "With Badges", -8)

  local badgeItems = {
    { label = "Inbox",  badge = true },
    { label = "Alerts", badge = true },
  }

  local bNavs = {}
  local bY = -28
  for _, item in ipairs(badgeItems) do
    local btn = cw:CreateNavButton(badgePanel, item, function()
      for _, b in ipairs(bNavs) do cw:SetNavButtonActive(b, false) end
      cw:SetNavButtonActive(btn, true)
    end)
    btn:SetPoint("TOPLEFT", badgePanel, "TOPLEFT", 0, bY)
    btn:SetPoint("RIGHT", badgePanel, "RIGHT", 0, 0)
    if btn.badge then
      btn.badge:SetText(item.label == "Inbox" and "3" or "!")
    end
    bNavs[#bNavs + 1] = btn
    bY = bY - 32
  end
  cw:SetNavButtonActive(bNavs[1], true)

  y = y - 220

  -- Section headers demo
  y = y - 10
  cw:CreateSectionHeader(c, "CreateSectionHeader", y)
  y = y - 20

  local headerExamples = { "General Settings", "Notifications", "Advanced", "About" }
  for _, text in ipairs(headerExamples) do
    cw:CreateSectionHeader(c, text, y)
    y = y - 20
  end

  y = y - 10
  c:SetHeight(math.abs(y) + 20)
  return f
end

-- ============================================================================
-- Page: Theme
-- ============================================================================

pages.theme = function(parent)
  local f = CreateFrame("Frame", nil, parent)
  f:SetAllPoints()
  local scroll, c = createPageFrame(f)

  local y = 0

  local function addSwatch(label, color, yPos)
    local swatch = c:CreateTexture(nil, "ARTWORK")
    swatch:SetSize(20, 20)
    swatch:SetPoint("TOPLEFT", c, "TOPLEFT", 8, yPos)
    swatch:SetColorTexture(color[1], color[2], color[3], color[4] or 1)

    -- Border around swatch
    local border = c:CreateTexture(nil, "OVERLAY")
    border:SetSize(22, 22)
    border:SetPoint("CENTER", swatch, "CENTER")
    border:SetColorTexture(unpack(T.border))
    border:SetDrawLayer("ARTWORK", -1)

    local text = c:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    text:SetPoint("LEFT", swatch, "RIGHT", 8, 0)
    text:SetText(label)
    text:SetTextColor(unpack(T.text))

    local hex = c:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    hex:SetPoint("LEFT", text, "RIGHT", 8, 0)
    local r, g, b = math.floor(color[1]*255), math.floor(color[2]*255), math.floor(color[3]*255)
    hex:SetText(string.format("|cff888888#%02x%02x%02x|r", r, g, b))
  end

  -- Backgrounds
  cw:CreateSectionHeader(c, "Backgrounds", y)
  y = y - 22
  local bgColors = {
    { "bg (primary dark)",   T.bg },
    { "bgLight (panel)",     T.bgLight },
    { "bgDark (inset)",      T.bgDark },
    { "header (toolbar)",    T.header },
    { "sidebar",             T.sidebar },
    { "border",              T.border },
    { "rowAlt",              T.rowAlt },
    { "rowHover",            T.rowHover },
  }
  for _, s in ipairs(bgColors) do
    addSwatch(s[1], s[2], y)
    y = y - 26
  end

  -- Accents
  y = y - 8
  cw:CreateSectionHeader(c, "Accents", y)
  y = y - 22
  local accentColors = {
    { "gold (primary accent)", T.gold },
    { "arcane (time magic)",   T.arcane },
    { "brass (clockwork)",     T.brass },
  }
  for _, s in ipairs(accentColors) do
    addSwatch(s[1], s[2], y)
    y = y - 26
  end

  -- Status
  y = y - 8
  cw:CreateSectionHeader(c, "Status", y)
  y = y - 22
  local statusColors = {
    { "success", T.success },
    { "warning", T.warning },
    { "error",   T.error },
  }
  for _, s in ipairs(statusColors) do
    addSwatch(s[1], s[2], y)
    y = y - 26
  end

  -- Text
  y = y - 8
  cw:CreateSectionHeader(c, "Text", y)
  y = y - 22
  local textColors = {
    { "text (primary)",      T.text },
    { "textDim (secondary)", T.textDim },
    { "textDisabled",        T.textDisabled },
    { "muted",               T.muted },
  }
  for _, s in ipairs(textColors) do
    addSwatch(s[1], s[2], y)
    y = y - 26
  end

  -- Quality colors
  y = y - 8
  cw:CreateSectionHeader(c, "Item Quality", y)
  y = y - 22
  local qualNames = { [0]="Poor", "Common", "Uncommon", "Rare", "Epic", "Legendary", "Artifact", "Heirloom", "WoW Token" }
  for i = 0, 8 do
    if T.quality[i] then
      addSwatch(qualNames[i] or ("Quality " .. i), T.quality[i], y)
      y = y - 26
    end
  end

  y = y - 10
  c:SetHeight(math.abs(y) + 20)
  return f
end

-- ============================================================================
-- Page: Layout
-- ============================================================================

pages.layout = function(parent)
  local f = CreateFrame("Frame", nil, parent)
  f:SetAllPoints()
  local scroll, c = createPageFrame(f)

  local y = 0

  -- Backdrop demos
  cw:CreateSectionHeader(c, "Backdrop Templates", y)
  y = y - 24

  local bdLabel1 = c:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  bdLabel1:SetPoint("TOPLEFT", c, "TOPLEFT", 8, y)
  bdLabel1:SetText("cw.Backdrop (16px edge)")
  bdLabel1:SetTextColor(unpack(T.text))
  y = y - 6

  local bdDemo1 = CreateFrame("Frame", nil, c, "BackdropTemplate")
  bdDemo1:SetSize(280, 60)
  bdDemo1:SetPoint("TOPLEFT", c, "TOPLEFT", 8, y)
  bdDemo1:SetBackdrop(cw.Backdrop)
  bdDemo1:SetBackdropColor(unpack(T.bg))
  bdDemo1:SetBackdropBorderColor(unpack(T.border))
  local bdText1 = bdDemo1:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  bdText1:SetPoint("CENTER")
  bdText1:SetText("Standard backdrop (panels, frames)")
  bdText1:SetTextColor(unpack(T.textDim))
  y = y - 76

  local bdLabel2 = c:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  bdLabel2:SetPoint("TOPLEFT", c, "TOPLEFT", 8, y)
  bdLabel2:SetText("cw.BackdropSmall (10px edge)")
  bdLabel2:SetTextColor(unpack(T.text))
  y = y - 6

  local bdDemo2 = CreateFrame("Frame", nil, c, "BackdropTemplate")
  bdDemo2:SetSize(280, 40)
  bdDemo2:SetPoint("TOPLEFT", c, "TOPLEFT", 8, y)
  bdDemo2:SetBackdrop(cw.BackdropSmall)
  bdDemo2:SetBackdropColor(unpack(T.header))
  bdDemo2:SetBackdropBorderColor(unpack(T.border))
  local bdText2 = bdDemo2:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  bdText2:SetPoint("CENTER")
  bdText2:SetText("Small backdrop (buttons, controls)")
  bdText2:SetTextColor(unpack(T.textDim))
  y = y - 56

  -- Nested panels
  y = y - 10
  cw:CreateSectionHeader(c, "Nested Panels", y)
  y = y - 24

  local outer = CreateFrame("Frame", nil, c, "BackdropTemplate")
  outer:SetSize(360, 140)
  outer:SetPoint("TOPLEFT", c, "TOPLEFT", 8, y)
  outer:SetBackdrop(cw.Backdrop)
  outer:SetBackdropColor(unpack(T.bg))
  outer:SetBackdropBorderColor(unpack(T.border))

  local outerTitle = outer:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  outerTitle:SetPoint("TOPLEFT", outer, "TOPLEFT", 8, -6)
  outerTitle:SetText("Outer panel (bg)")
  outerTitle:SetTextColor(unpack(T.textDim))

  local inner1 = CreateFrame("Frame", nil, outer, "BackdropTemplate")
  inner1:SetSize(160, 80)
  inner1:SetPoint("TOPLEFT", outer, "TOPLEFT", 10, -24)
  inner1:SetBackdrop(cw.BackdropSmall)
  inner1:SetBackdropColor(unpack(T.header))
  inner1:SetBackdropBorderColor(unpack(T.border))
  local i1Text = inner1:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  i1Text:SetPoint("CENTER")
  i1Text:SetText("header bg")
  i1Text:SetTextColor(unpack(T.textDim))

  local inner2 = CreateFrame("Frame", nil, outer, "BackdropTemplate")
  inner2:SetSize(160, 80)
  inner2:SetPoint("TOPLEFT", inner1, "TOPRIGHT", 10, 0)
  inner2:SetBackdrop(cw.BackdropSmall)
  inner2:SetBackdropColor(unpack(T.sidebar))
  inner2:SetBackdropBorderColor(unpack(T.border))
  local i2Text = inner2:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  i2Text:SetPoint("CENTER")
  i2Text:SetText("sidebar bg")
  i2Text:SetTextColor(unpack(T.textDim))

  y = y - 160

  -- Row styling demo
  y = y - 10
  cw:CreateSectionHeader(c, "Row Styling", y)
  y = y - 24

  local rowPanel = CreateFrame("Frame", nil, c, "BackdropTemplate")
  rowPanel:SetSize(360, 120)
  rowPanel:SetPoint("TOPLEFT", c, "TOPLEFT", 8, y)
  rowPanel:SetBackdrop(cw.BackdropSmall)
  rowPanel:SetBackdropColor(unpack(T.bg))
  rowPanel:SetBackdropBorderColor(unpack(T.border))

  for i = 1, 5 do
    local row = CreateFrame("Frame", nil, rowPanel)
    row:SetHeight(22)
    row:SetPoint("TOPLEFT", rowPanel, "TOPLEFT", 4, -4 - (i - 1) * 22)
    row:SetPoint("RIGHT", rowPanel, "RIGHT", -4, 0)

    if i % 2 == 0 then
      local altBg = row:CreateTexture(nil, "BACKGROUND")
      altBg:SetAllPoints()
      altBg:SetColorTexture(unpack(T.rowAlt))
    end

    local hoverBg = row:CreateTexture(nil, "BACKGROUND", nil, 1)
    hoverBg:SetAllPoints()
    hoverBg:SetColorTexture(unpack(T.rowHover))
    hoverBg:Hide()

    row:EnableMouse(true)
    row:SetScript("OnEnter", function() hoverBg:Show() end)
    row:SetScript("OnLeave", function() hoverBg:Hide() end)

    local rowText = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    rowText:SetPoint("LEFT", row, "LEFT", 8, 0)
    rowText:SetText("Row " .. i .. (i % 2 == 0 and " (rowAlt)" or ""))
    rowText:SetTextColor(unpack(T.text))
  end

  y = y - 140

  -- Font showcase
  y = y - 10
  cw:CreateSectionHeader(c, "Standard WoW Fonts", y)
  y = y - 22

  local fonts = {
    { "GameFontNormal",          "GameFontNormal — body text" },
    { "GameFontNormalSmall",     "GameFontNormalSmall — labels, descriptions" },
    { "GameFontNormalLarge",     "GameFontNormalLarge — page titles" },
    { "GameFontHighlight",       "GameFontHighlight — bright emphasis" },
    { "GameFontHighlightSmall",  "GameFontHighlightSmall — small emphasis" },
    { "GameFontDisable",         "GameFontDisable — disabled text" },
    { "GameFontDisableSmall",    "GameFontDisableSmall — small disabled" },
  }

  for _, fd in ipairs(fonts) do
    local fs = c:CreateFontString(nil, "OVERLAY", fd[1])
    fs:SetPoint("TOPLEFT", c, "TOPLEFT", 8, y)
    fs:SetText(fd[2])
    y = y - 20
  end

  y = y - 10
  c:SetHeight(math.abs(y) + 20)
  return f
end

-- ============================================================================
-- Public toggle
-- ============================================================================

function ns:ToggleShowcase()
  if not showcase then
    showcase = createShowcase()
    showPage("buttons")
  end

  if showcase:IsShown() then
    showcase:Hide()
  else
    showcase:Show()
  end
end
