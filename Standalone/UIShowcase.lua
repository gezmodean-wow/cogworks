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
  f:SetResizeBounds(420, 300, 1200, 900)
  f:SetClampedToScreen(true)
  f:SetScale(cw:GetSetting("uiScale") or 1.0)
  tinsert(UISpecialFrames, "CogworksShowcase")

  -- Respond to settings changes (UI scale, theme, fonts)
  local settingsOwner = {}
  cw.RegisterCallback(settingsOwner, cw.Events.SettingsChanged, function(_, key, value)
    if key == "uiScale" then
      f:SetScale(value)
    elseif key == "theme" or key == "themeColor" then
      -- Re-apply frame-level colors
      local TT = cw.Theme
      f:SetBackdropColor(unpack(TT.bg))
      f:SetBackdropBorderColor(unpack(TT.border))
      if f._sidebarBg then f._sidebarBg:SetColorTexture(unpack(TT.sidebar)) end
      if f._sidebarEdge then f._sidebarEdge:SetColorTexture(unpack(TT.border)) end
      if f._titleBg then f._titleBg:SetColorTexture(unpack(TT.header)) end
      -- Re-apply nav button states
      for k, nb in pairs(navButtons) do
        cw:SetNavButtonActive(nb, k == activePage)
      end
      -- Full preset switch: rebuild all pages
      if key == "theme" then
        for k, pf in pairs(pageFrames) do
          pf:Hide()
          pf:SetParent(nil)
          pageFrames[k] = nil
        end
        local cur = activePage
        activePage = nil
        showPage(cur or "gears")
      end
    end
  end)

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
  f._titleBg = titleBg

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
  f._sidebarBg = sidebarBg

  -- Sidebar border (right edge)
  local sidebarEdge = sidebar:CreateTexture(nil, "ARTWORK")
  sidebarEdge:SetSize(1, 1)
  sidebarEdge:SetPoint("TOPRIGHT", sidebar, "TOPRIGHT", 0, 0)
  sidebarEdge:SetPoint("BOTTOMRIGHT", sidebar, "BOTTOMRIGHT", 0, 0)
  sidebarEdge:SetColorTexture(unpack(T.border))
  f._sidebarEdge = sidebarEdge

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
    { key = "gears",    label = "Gears",       icon = "Interface\\Icons\\INV_Misc_Gear_01" },
    { key = "settings", label = "Settings",    icon = "Interface\\Buttons\\UI-MicroButton-MainMenu-Up" },
    { key = "sections", label = "Sections",    icon = "Interface\\Buttons\\UI-MicroButton-Spellbook-Up" },
    { key = "tabs",     label = "Tabs",        icon = "Interface\\Buttons\\UI-MicroButton-Talents-Up" },
    { key = "mini",     label = "MiniView",    icon = "Interface\\Buttons\\UI-MicroButton-Inventory-Up" },
    { key = "text",     label = "Text",        icon = "Interface\\Buttons\\UI-MicroButton-Achievement-Up" },
    { key = "wizard",   label = "Wizard",      icon = "Interface\\Buttons\\UI-MicroButton-Mounts-Up" },
    { key = "tree",     label = "Tree",        icon = "Interface\\Buttons\\UI-MicroButton-LFG-Up" },
    { key = "reorder",  label = "Reorderable", icon = "Interface\\Buttons\\UI-MicroButton-Encounter-Journal-Up" },
    { key = "tables",   label = "Tables",      icon = "Interface\\Buttons\\UI-MicroButton-Questlog-Up" },
    { key = "popups",   label = "Popups",      icon = "Interface\\Buttons\\UI-MicroButton-Help-Up" },
    { key = "buttons",  label = "Buttons",     icon = "Interface\\Buttons\\UI-MicroButton-Abilities-Up" },
    { key = "controls", label = "Controls",    icon = "Interface\\Buttons\\UI-MicroButton-EJ-Up" },
    { key = "nav",      label = "Navigation",  icon = "Interface\\Buttons\\UI-MicroButton-Socials-Up" },
    { key = "theme",    label = "Theme",       icon = "Interface\\Buttons\\UI-MicroButton-Collections-Up" },
    { key = "layout",   label = "Layout",      icon = "Interface\\Icons\\Trade_Engineering" },
    { key = "debug",    label = "Debug",       icon = "Interface\\Buttons\\UI-OptionsButton" },
    { key = "mainframe",label = "MainFrame",   icon = "Interface\\Buttons\\UI-MicroButton-MainMenu-Up" },
    { key = "drawer",   label = "Drawer",      icon = "Interface\\Buttons\\UI-MicroButton-Inventory-Up" },
    { key = "toast",    label = "Toast",       icon = "Interface\\COMMON\\Indicator-Yellow" },
    { key = "slash",    label = "Slash",       icon = "Interface\\Buttons\\UI-MicroButton-Help-Up" },
  }

  local navHeader = cw:CreateSectionHeader(sidebar, "Pages", -12)

  -- Nav buttons live inside a ScrollFrame so they don't overflow the sidebar
  -- when the page count or fontScale-driven button height pushes the stack
  -- past the visible region. (16 buttons × 32px exceeds the ~448px sidebar
  -- on a default-size frame even at 1.0x scale.)
  local NAV_HEADER_H = 30
  local NAV_ROW_STRIDE = 32

  local navScroll = CreateFrame("ScrollFrame", nil, sidebar)
  navScroll:SetPoint("TOPLEFT",     sidebar, "TOPLEFT",     0, -NAV_HEADER_H)
  navScroll:SetPoint("BOTTOMRIGHT", sidebar, "BOTTOMRIGHT", 0, 0)
  navScroll:EnableMouseWheel(true)

  local navContent = CreateFrame("Frame", nil, navScroll)
  navContent:SetWidth(SIDEBAR_WIDTH)
  navContent:SetHeight(#navDefs * NAV_ROW_STRIDE)
  navScroll:SetScrollChild(navContent)

  -- Thin themed scroll-indicator track on the right inside edge of the
  -- sidebar (overlay-only, no mouse interaction so clicks pass through to
  -- the nav buttons beneath). Mirrors the pattern in createPageFrame.
  local navTrack = CreateFrame("Frame", nil, sidebar)
  navTrack:SetWidth(4)
  navTrack:SetPoint("TOPRIGHT",    navScroll, "TOPRIGHT",    -3, -2)
  navTrack:SetPoint("BOTTOMRIGHT", navScroll, "BOTTOMRIGHT", -3, 2)
  navTrack:SetFrameLevel(navScroll:GetFrameLevel() + 5)
  local navTrackBg = navTrack:CreateTexture(nil, "BACKGROUND")
  navTrackBg:SetAllPoints()
  navTrackBg:SetColorTexture(T.border[1], T.border[2], T.border[3], 0.15)

  local navThumb = CreateFrame("Frame", nil, navTrack)
  navThumb:SetWidth(4)
  navThumb:SetHeight(20)
  navThumb:SetPoint("TOP", navTrack, "TOP", 0, 0)
  local navThumbTex = navThumb:CreateTexture(nil, "ARTWORK")
  navThumbTex:SetAllPoints()
  navThumbTex:SetColorTexture(T.brass[1], T.brass[2], T.brass[3], 0.7)
  navTrack:Hide()

  local function updateNavThumb()
    local contentH = navContent:GetHeight()
    local viewH    = navScroll:GetHeight()
    local range    = math.max(0, contentH - viewH)
    if range <= 0.5 then navTrack:Hide(); return end
    navTrack:Show()
    local trackH = navTrack:GetHeight()
    local thumbH = math.max(16, trackH * (viewH / contentH))
    navThumb:SetHeight(thumbH)
    local cur  = navScroll:GetVerticalScroll()
    local frac = range > 0 and (cur / range) or 0
    navThumb:ClearAllPoints()
    navThumb:SetPoint("TOP", navTrack, "TOP", 0, -frac * (trackH - thumbH))
  end

  navScroll:SetScript("OnMouseWheel", function(sf, delta)
    local range = math.max(0, navContent:GetHeight() - sf:GetHeight())
    if range <= 0 then return end
    local cur = sf:GetVerticalScroll()
    sf:SetVerticalScroll(math.max(0, math.min(range, cur - delta * NAV_ROW_STRIDE)))
    updateNavThumb()
  end)
  navScroll:HookScript("OnSizeChanged", updateNavThumb)
  -- The first measurement is unreliable until WoW has rendered a frame, so
  -- defer the initial paint by one tick.
  navScroll:SetScript("OnShow", function() C_Timer.After(0, updateNavThumb) end)

  local yOff = 0
  for _, def in ipairs(navDefs) do
    local btn = cw:CreateNavButton(navContent, { label = def.label, icon = def.icon }, function()
      showPage(def.key)
    end)
    btn:SetPoint("TOPLEFT", navContent, "TOPLEFT", 0, -yOff)
    btn:SetPoint("RIGHT",   navContent, "RIGHT",  -1, 0)
    navButtons[def.key] = btn
    yOff = yOff + NAV_ROW_STRIDE
  end

  C_Timer.After(0, updateNavThumb)

  return f
end

-- ============================================================================
-- Helper: scrollable content page
-- ============================================================================

local function createPageFrame(parent)
  local scroll = CreateFrame("ScrollFrame", nil, parent)
  scroll:SetPoint("TOPLEFT", parent, "TOPLEFT", 8, -8)
  scroll:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -14, 8)

  local child = CreateFrame("Frame", nil, scroll)
  child:SetWidth(scroll:GetWidth())
  scroll:SetScrollChild(child)

  -- Thin themed scrollbar
  local track = CreateFrame("Frame", nil, parent)
  track:SetWidth(4)
  track:SetPoint("TOPLEFT", scroll, "TOPRIGHT", 2, 0)
  track:SetPoint("BOTTOMLEFT", scroll, "BOTTOMRIGHT", 2, 0)
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
    local contentH = child:GetHeight()
    local viewH = scroll:GetHeight()
    local range = math.max(0, contentH - viewH)
    if range <= 0.5 then track:Hide(); return end
    track:Show()
    local trackH = track:GetHeight()
    local thumbH = math.max(16, trackH * (viewH / contentH))
    thumb:SetHeight(thumbH)
    local cur = scroll:GetVerticalScroll()
    local frac = range > 0 and (cur / range) or 0
    thumb:ClearAllPoints()
    thumb:SetPoint("TOP", track, "TOP", 0, -frac * (trackH - thumbH))
  end

  scroll:EnableMouseWheel(true)
  scroll:SetScript("OnMouseWheel", function(sf, delta)
    local contentH = child:GetHeight()
    local viewH = sf:GetHeight()
    local range = math.max(0, contentH - viewH)
    local step = 40
    local newVal = math.max(0, math.min(range, sf:GetVerticalScroll() - delta * step))
    sf:SetVerticalScroll(newVal)
    updateThumb()
  end)

  local function refreshLayout()
    local w = scroll:GetWidth()
    if w and w > 1 then
      child:SetWidth(w)
      updateThumb()
    end
  end

  parent:HookScript("OnSizeChanged", refreshLayout)
  parent:HookScript("OnShow", refreshLayout)

  scroll.updateThumb = updateThumb

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
    local btn = cw:CreateNavButton(navPanel, item, nil)
    btn:SetPoint("TOPLEFT", navPanel, "TOPLEFT", 0, navY)
    btn:SetPoint("RIGHT", navPanel, "RIGHT", 0, 0)
    demoNavs[#demoNavs + 1] = btn
    -- Set click handler after btn is assigned so the closure captures it
    btn:SetScript("OnClick", function()
      for _, b in ipairs(demoNavs) do
        cw:SetNavButtonActive(b, false)
      end
      cw:SetNavButtonActive(btn, true)
      cw:Print("Cogworks", "Nav: " .. item.label)
    end)
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
    local btn = cw:CreateNavButton(badgePanel, item, nil)
    btn:SetPoint("TOPLEFT", badgePanel, "TOPLEFT", 0, bY)
    btn:SetPoint("RIGHT", badgePanel, "RIGHT", 0, 0)
    btn:SetScript("OnClick", function()
      for _, b in ipairs(bNavs) do cw:SetNavButtonActive(b, false) end
      cw:SetNavButtonActive(btn, true)
    end)
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

  local PREVIEW_HEIGHT = 130
  local swatches = {}
  local previewWidgets = {}

  local function refreshPreview()
    local TT = cw.Theme
    for _, pw in ipairs(previewWidgets) do
      if pw.type == "backdrop" then
        pw.frame:SetBackdropColor(unpack(TT[pw.bgKey] or TT.bg))
        pw.frame:SetBackdropBorderColor(unpack(TT.border))
      elseif pw.type == "texture" then
        local c = TT[pw.colorKey]
        if c then pw.tex:SetColorTexture(c[1], c[2], c[3], c[4] or 1) end
      elseif pw.type == "text" then
        local c = TT[pw.colorKey]
        if c then pw.fs:SetTextColor(c[1], c[2], c[3], c[4] or 1) end
      elseif pw.type == "button" then
        pw.frame:SetBackdropColor(unpack(TT.header))
        pw.frame:SetBackdropBorderColor(unpack(TT.border))
      elseif pw.type == "bar" then
        local c = TT[pw.colorKey]
        if c then pw.tex:SetColorTexture(c[1], c[2], c[3], 0.8) end
      end
    end
  end

  -- Live preview panel (fixed, does not scroll)
  cw:CreateSectionHeader(f, "Live Preview", -4)

  local previewOuter = CreateFrame("Frame", nil, f, "BackdropTemplate")
  previewOuter:SetSize(460, 110)
  previewOuter:SetPoint("TOPLEFT", f, "TOPLEFT", 16, -22)
  previewOuter:SetBackdrop(cw.Backdrop)
  previewOuter:SetBackdropColor(unpack(T.bg))
  previewOuter:SetBackdropBorderColor(unpack(T.border))
  previewWidgets[#previewWidgets+1] = { type="backdrop", frame=previewOuter, bgKey="bg" }

  -- Mini sidebar
  local pvSidebar = CreateFrame("Frame", nil, previewOuter)
  pvSidebar:SetWidth(80)
  pvSidebar:SetPoint("TOPLEFT", previewOuter, "TOPLEFT", 4, -4)
  pvSidebar:SetPoint("BOTTOMLEFT", previewOuter, "BOTTOMLEFT", 4, 4)
  local pvSidebarBg = pvSidebar:CreateTexture(nil, "BACKGROUND")
  pvSidebarBg:SetAllPoints()
  pvSidebarBg:SetColorTexture(unpack(T.sidebar))
  previewWidgets[#previewWidgets+1] = { type="texture", tex=pvSidebarBg, colorKey="sidebar" }

  -- Sidebar nav items
  local pvNavLabels = { "Dashboard", "Tasks", "Settings" }
  for i, lbl in ipairs(pvNavLabels) do
    local pvNav = pvSidebar:CreateFontString(nil, "OVERLAY")
    pvNav:SetFontObject(cw.Fonts.small)
    pvNav:SetPoint("TOPLEFT", pvSidebar, "TOPLEFT", 6, -6 - (i-1) * 18)
    pvNav:SetText(lbl)
    local ck = i == 1 and "text" or "textDim"
    pvNav:SetTextColor(unpack(T[ck]))
    previewWidgets[#previewWidgets+1] = { type="text", fs=pvNav, colorKey=ck }
    if i == 1 then
      local accent = pvSidebar:CreateTexture(nil, "ARTWORK")
      accent:SetSize(2, 14)
      accent:SetPoint("LEFT", pvSidebar, "LEFT", 0, 0)
      accent:SetPoint("TOP", pvNav, "TOP", 0, 0)
      accent:SetColorTexture(unpack(T.gold))
      previewWidgets[#previewWidgets+1] = { type="texture", tex=accent, colorKey="gold" }
    end
  end

  -- Mini header
  local pvHeader = CreateFrame("Frame", nil, previewOuter)
  pvHeader:SetHeight(20)
  pvHeader:SetPoint("TOPLEFT", pvSidebar, "TOPRIGHT", 2, 0)
  pvHeader:SetPoint("RIGHT", previewOuter, "RIGHT", -4, 0)
  local pvHeaderBg = pvHeader:CreateTexture(nil, "BACKGROUND")
  pvHeaderBg:SetAllPoints()
  pvHeaderBg:SetColorTexture(unpack(T.header))
  previewWidgets[#previewWidgets+1] = { type="texture", tex=pvHeaderBg, colorKey="header" }

  local pvTitle = pvHeader:CreateFontString(nil, "OVERLAY")
  pvTitle:SetFontObject(cw.Fonts.small)
  pvTitle:SetPoint("LEFT", pvHeader, "LEFT", 6, 0)
  pvTitle:SetText("Sample Panel")
  pvTitle:SetTextColor(unpack(T.gold))
  previewWidgets[#previewWidgets+1] = { type="text", fs=pvTitle, colorKey="gold" }

  -- Content area with sample widgets
  local pvContent = CreateFrame("Frame", nil, previewOuter)
  pvContent:SetPoint("TOPLEFT", pvHeader, "BOTTOMLEFT", 0, -2)
  pvContent:SetPoint("BOTTOMRIGHT", previewOuter, "BOTTOMRIGHT", -4, 4)

  -- Sample button
  local pvBtn = CreateFrame("Frame", nil, pvContent, "BackdropTemplate")
  pvBtn:SetSize(80, 20)
  pvBtn:SetPoint("TOPLEFT", pvContent, "TOPLEFT", 6, -6)
  pvBtn:SetBackdrop(cw.BackdropSmall)
  pvBtn:SetBackdropColor(unpack(T.header))
  pvBtn:SetBackdropBorderColor(unpack(T.border))
  previewWidgets[#previewWidgets+1] = { type="button", frame=pvBtn }
  local pvBtnText = pvBtn:CreateFontString(nil, "OVERLAY")
  pvBtnText:SetFontObject(cw.Fonts.small)
  pvBtnText:SetPoint("CENTER")
  pvBtnText:SetText("Button")
  pvBtnText:SetTextColor(unpack(T.text))
  previewWidgets[#previewWidgets+1] = { type="text", fs=pvBtnText, colorKey="text" }

  -- Sample progress bar
  local pvBarBg = CreateFrame("Frame", nil, pvContent, "BackdropTemplate")
  pvBarBg:SetSize(140, 12)
  pvBarBg:SetPoint("LEFT", pvBtn, "RIGHT", 8, 0)
  pvBarBg:SetBackdrop({ bgFile="Interface\\Tooltips\\UI-Tooltip-Background", edgeFile="Interface\\Tooltips\\UI-Tooltip-Border", edgeSize=8, insets={left=2,right=2,top=2,bottom=2} })
  pvBarBg:SetBackdropColor(0.05, 0.05, 0.08, 1)
  pvBarBg:SetBackdropBorderColor(unpack(T.border))
  local pvBarFill = pvBarBg:CreateTexture(nil, "ARTWORK")
  pvBarFill:SetPoint("TOPLEFT", pvBarBg, "TOPLEFT", 2, -2)
  pvBarFill:SetPoint("BOTTOMLEFT", pvBarBg, "BOTTOMLEFT", 2, 2)
  pvBarFill:SetWidth(90)
  pvBarFill:SetColorTexture(T.success[1], T.success[2], T.success[3], 0.8)
  previewWidgets[#previewWidgets+1] = { type="bar", tex=pvBarFill, colorKey="success" }

  -- Sample text
  local pvTexts = {
    { "Normal text", "text", 0, -32 },
    { "Dimmed label", "textDim", 0, -46 },
    { "Disabled", "textDisabled", 80, -46 },
    { "Success", "success", 0, -60 },
    { "Warning", "warning", 60, -60 },
    { "Error", "error", 120, -60 },
  }
  for _, td in ipairs(pvTexts) do
    local fs = pvContent:CreateFontString(nil, "OVERLAY")
    fs:SetFontObject(cw.Fonts.small)
    fs:SetPoint("TOPLEFT", pvContent, "TOPLEFT", 6 + td[3], td[4])
    fs:SetText(td[1])
    fs:SetTextColor(unpack(T[td[2]]))
    previewWidgets[#previewWidgets+1] = { type="text", fs=fs, colorKey=td[2] }
  end

  -- Arcane accent sample
  local pvArcane = pvContent:CreateFontString(nil, "OVERLAY")
  pvArcane:SetFontObject(cw.Fonts.small)
  pvArcane:SetPoint("TOPLEFT", pvContent, "TOPLEFT", 160, -32)
  pvArcane:SetText("Arcane glow")
  pvArcane:SetTextColor(unpack(T.arcane))
  previewWidgets[#previewWidgets+1] = { type="text", fs=pvArcane, colorKey="arcane" }

  local pvBrass = pvContent:CreateFontString(nil, "OVERLAY")
  pvBrass:SetFontObject(cw.Fonts.small)
  pvBrass:SetPoint("TOPLEFT", pvArcane, "BOTTOMLEFT", 0, -4)
  pvBrass:SetText("Brass trim")
  pvBrass:SetTextColor(unpack(T.brass))
  previewWidgets[#previewWidgets+1] = { type="text", fs=pvBrass, colorKey="brass" }

  -- Scrollable area below the fixed preview
  local scrollArea = CreateFrame("Frame", nil, f)
  scrollArea:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -(PREVIEW_HEIGHT + 4))
  scrollArea:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, 0)
  local scroll, c = createPageFrame(scrollArea)

  local y = 0

  local function refreshSwatches()
    for _, sw in ipairs(swatches) do
      local color = cw.Theme[sw.key]
      if color then
        sw.tex:SetColorTexture(color[1], color[2], color[3], color[4] or 1)
        local r, g, b = math.floor(color[1]*255), math.floor(color[2]*255), math.floor(color[3]*255)
        sw.hex:SetText(string.format("|cff888888#%02x%02x%02x|r", r, g, b))
      end
    end
    refreshPreview()
  end

  local function addEditableSwatch(key, label, yPos)
    local color = cw.Theme[key]
    if not color then return yPos end

    local btn = CreateFrame("Button", nil, c)
    btn:SetSize(20, 20)
    btn:SetPoint("TOPLEFT", c, "TOPLEFT", 8, yPos)

    local tex = btn:CreateTexture(nil, "ARTWORK")
    tex:SetAllPoints()
    tex:SetColorTexture(color[1], color[2], color[3], color[4] or 1)

    local borderTex = c:CreateTexture(nil, "ARTWORK", nil, -1)
    borderTex:SetSize(22, 22)
    borderTex:SetPoint("CENTER", btn, "CENTER")
    borderTex:SetColorTexture(0.5, 0.5, 0.5, 0.5)

    local text = c:CreateFontString(nil, "OVERLAY")
    text:SetFontObject(cw.Fonts.normal)
    text:SetPoint("LEFT", btn, "RIGHT", 8, 0)
    text:SetText(label)
    text:SetTextColor(unpack(T.text))

    local hex = c:CreateFontString(nil, "OVERLAY")
    hex:SetFontObject(cw.Fonts.small)
    hex:SetPoint("LEFT", text, "RIGHT", 8, 0)
    local r, g, b = math.floor(color[1]*255), math.floor(color[2]*255), math.floor(color[3]*255)
    hex:SetText(string.format("|cff888888#%02x%02x%02x|r", r, g, b))

    swatches[#swatches + 1] = { key = key, tex = tex, hex = hex }

    btn:SetScript("OnClick", function()
      local cur = cw.Theme[key]
      local info = {
        r = cur[1], g = cur[2], b = cur[3],
        hasOpacity = true, opacity = cur[4] or 1,
        swatchFunc = function()
          local nr, ng, nb = ColorPickerFrame:GetColorRGB()
          local na = (ColorPickerFrame.GetColorAlpha and ColorPickerFrame:GetColorAlpha()) or 1
          cw:SetThemeColor(key, nr, ng, nb, na)
          refreshSwatches()
        end,
        cancelFunc = function(prev)
          cw:SetThemeColor(key, prev.r, prev.g, prev.b, prev.a or 1)
          refreshSwatches()
        end,
      }
      ColorPickerFrame:SetupColorPickerAndShow(info)
    end)

    return yPos - 24
  end

  -- Theme preset selector
  cw:CreateSectionHeader(c, "Theme Presets", y)
  y = y - 22

  local themeLabel = c:CreateFontString(nil, "OVERLAY")
  themeLabel:SetFontObject(cw.Fonts.normal)
  themeLabel:SetPoint("TOPLEFT", c, "TOPLEFT", 8, y)
  themeLabel:SetText("Active: |cffd4a017" .. cw.activeThemeName .. "|r")
  y = y - 26

  local presetNames = { "Cogworks", "Midnight", "Forge", "Frost", "Classic" }
  local xOff = 8
  for _, name in ipairs(presetNames) do
    local btn = cw:CreateButton(c, name, 90, 24, function()
      cw:SetTheme(name)
      cw.settings.theme = name
      themeLabel:SetText("Active: |cffd4a017" .. name .. "|r")
      refreshSwatches()
    end)
    btn:SetPoint("TOPLEFT", c, "TOPLEFT", xOff, y)
    xOff = xOff + 98
    if xOff > 400 then xOff = 8; y = y - 32 end
  end
  y = y - 36

  -- Custom theme names
  local customNames = {}
  for name in pairs(cw.CustomThemes) do customNames[#customNames + 1] = name end
  if #customNames > 0 then
    table.sort(customNames)
    cw:CreateSectionHeader(c, "Custom Themes", y)
    y = y - 22
    xOff = 8
    for _, name in ipairs(customNames) do
      local btn = cw:CreateButton(c, name, 110, 24, function()
        cw:SetTheme(name)
        cw.settings.theme = name
        themeLabel:SetText("Active: |cffd4a017" .. name .. "|r")
        refreshSwatches()
      end)
      btn:SetPoint("TOPLEFT", c, "TOPLEFT", xOff, y)
      xOff = xOff + 118
      if xOff > 400 then xOff = 8; y = y - 32 end
    end
    y = y - 36
  end

  -- Editable color swatches (click to open color picker)
  cw:CreateSectionHeader(c, "Colors (click swatch to edit)", y)
  y = y - 22

  local colorDefs = {
    { "Backgrounds", { {"bg","bg"}, {"bgLight","bgLight"}, {"bgDark","bgDark"},
      {"header","header"}, {"sidebar","sidebar"}, {"border","border"} } },
    { "Rows", { {"rowAlt","rowAlt"}, {"rowHover","rowHover"} } },
    { "Accents", { {"gold","gold"}, {"arcane","arcane"}, {"brass","brass"} } },
    { "Status", { {"success","success"}, {"warning","warning"}, {"error","error"} } },
    { "Text", { {"text","text"}, {"textDim","textDim"}, {"textDisabled","textDisabled"} } },
  }

  for _, group in ipairs(colorDefs) do
    local groupLabel = c:CreateFontString(nil, "OVERLAY")
    groupLabel:SetFontObject(cw.Fonts.small)
    groupLabel:SetPoint("TOPLEFT", c, "TOPLEFT", 8, y)
    groupLabel:SetText("|cffd4a017" .. group[1] .. "|r")
    y = y - 18
    for _, pair in ipairs(group[2]) do
      y = addEditableSwatch(pair[1], pair[2], y)
    end
    y = y - 6
  end

  -- Save / Export / Import
  y = y - 4
  cw:CreateSectionHeader(c, "Save & Share", y)
  y = y - 22

  local saveBtn = cw:CreateButton(c, "Save as Custom", 140, 26, function()
    local popup = cw:CreatePopup({ title = "Save Theme", width = 360, height = 140 })
    local nameBox = CreateFrame("EditBox", nil, popup.content, "InputBoxTemplate")
    nameBox:SetSize(280, 22)
    nameBox:SetPoint("TOPLEFT", popup.content, "TOPLEFT", 8, -8)
    nameBox:SetAutoFocus(true)
    nameBox:SetText("My Theme")
    nameBox:SetFontObject(cw.Fonts.normal)
    popup:SetButtons({
      { label = "Save", onClick = function()
        local n = nameBox:GetText():gsub("^%s+",""):gsub("%s+$","")
        if n ~= "" then
          cw:SaveCustomTheme(n)
          cw.activeThemeName = n
          cw.settings.theme = n
          themeLabel:SetText("Active: |cffd4a017" .. n .. "|r")
          cw:Print("Cogworks", "Theme saved: " .. n)
        end
      end },
      { label = "Cancel" },
    })
    popup:Show()
  end)
  saveBtn:SetPoint("TOPLEFT", c, "TOPLEFT", 8, y)

  local exportBtn = cw:CreateButton(c, "Export", 80, 26, function()
    local str = cw:ExportTheme()
    local popup = cw:CreatePopup({ title = "Export Theme", width = 480, height = 160 })
    local box = CreateFrame("EditBox", nil, popup.content, "InputBoxTemplate")
    box:SetSize(420, 22)
    box:SetPoint("TOPLEFT", popup.content, "TOPLEFT", 8, -8)
    box:SetText(str)
    box:SetFontObject(cw.Fonts.small)
    box:SetAutoFocus(true)
    box:HighlightText()
    local hint = popup.content:CreateFontString(nil, "OVERLAY")
    hint:SetFontObject(cw.Fonts.small)
    hint:SetPoint("TOPLEFT", box, "BOTTOMLEFT", 0, -6)
    hint:SetText("Ctrl+C to copy, share on Discord")
    hint:SetTextColor(unpack(T.textDim))
    popup:SetButtons({ { label = "Close" } })
    popup:Show()
  end)
  exportBtn:SetPoint("LEFT", saveBtn, "RIGHT", 8, 0)

  local importBtn = cw:CreateButton(c, "Import", 80, 26, function()
    local popup = cw:CreatePopup({ title = "Import Theme", width = 480, height = 160 })
    local box = CreateFrame("EditBox", nil, popup.content, "InputBoxTemplate")
    box:SetSize(420, 22)
    box:SetPoint("TOPLEFT", popup.content, "TOPLEFT", 8, -8)
    box:SetFontObject(cw.Fonts.small)
    box:SetAutoFocus(true)
    local hint = popup.content:CreateFontString(nil, "OVERLAY")
    hint:SetFontObject(cw.Fonts.small)
    hint:SetPoint("TOPLEFT", box, "BOTTOMLEFT", 0, -6)
    hint:SetText("Paste a CogworksTheme: string and click Import")
    hint:SetTextColor(unpack(T.textDim))
    popup:SetButtons({
      { label = "Import", onClick = function()
        local name, err = cw:ImportTheme(box:GetText())
        if name then
          cw:SetTheme(name)
          cw.settings.theme = name
          themeLabel:SetText("Active: |cffd4a017" .. name .. "|r")
          refreshSwatches()
          cw:Print("Cogworks", "Theme imported: " .. name)
        else
          cw:PrintError("Cogworks", "Import failed: " .. (err or "unknown"))
        end
      end },
      { label = "Cancel" },
    })
    popup:Show()
  end)
  importBtn:SetPoint("LEFT", exportBtn, "RIGHT", 8, 0)

  y = y - 40
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

  -- Same y-stack pattern as pages.sections — each section participates in
  -- a single relayout walk so toggling and font-scale changes never leave
  -- siblings in stale positions.
  local items = {}
  local function add(frame, heightFn, gapAfter)
    items[#items + 1] = { f = frame, h = heightFn, gap = gapAfter or 8 }
  end

  local function relayout()
    local y = 0
    for _, it in ipairs(items) do
      it.f:ClearAllPoints()
      it.f:SetPoint("TOPLEFT", c, "TOPLEFT", 8, -y)
      it.f:SetPoint("TOPRIGHT", c, "TOPRIGHT", -8, -y)
      y = y + it.h() + it.gap
    end
    c:SetHeight(y + 20)
  end

  -- Build a section, add it to the stack, return both the section and a
  -- handle to its content frame so the caller can populate it.
  local function makeSection(opts)
    local section = cw:CreateCollapsibleSection(c, opts)
    return section, section.content
  end

  -- ---- Backdrop Templates ------------------------------------------------
  local bdSection, bdContent = makeSection({
    title           = "Backdrop Templates",
    summary         = "cw.Backdrop and cw.BackdropSmall, themed",
    onLayoutChanged = function() relayout() end,
  })

  local bdLabel1 = bdContent:CreateFontString(nil, "OVERLAY")
  bdLabel1:SetFontObject(cw:GetFont("normal"))
  bdLabel1:SetPoint("TOPLEFT", bdContent, "TOPLEFT", 0, 0)
  bdLabel1:SetText("cw.Backdrop (16px edge)")
  bdLabel1:SetTextColor(unpack(T.text))

  local bdDemo1 = CreateFrame("Frame", nil, bdContent, "BackdropTemplate")
  bdDemo1:SetSize(280, 60)
  bdDemo1:SetPoint("TOPLEFT", bdLabel1, "BOTTOMLEFT", 0, -4)
  bdDemo1:SetBackdrop(cw.Backdrop)
  bdDemo1:SetBackdropColor(unpack(T.bg))
  bdDemo1:SetBackdropBorderColor(unpack(T.border))
  local bdText1 = bdDemo1:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  bdText1:SetPoint("CENTER")
  bdText1:SetText("Standard backdrop (panels, frames)")
  bdText1:SetTextColor(unpack(T.textDim))

  local bdLabel2 = bdContent:CreateFontString(nil, "OVERLAY")
  bdLabel2:SetFontObject(cw:GetFont("normal"))
  bdLabel2:SetPoint("TOPLEFT", bdDemo1, "BOTTOMLEFT", 0, -10)
  bdLabel2:SetText("cw.BackdropSmall (10px edge)")
  bdLabel2:SetTextColor(unpack(T.text))

  local bdDemo2 = CreateFrame("Frame", nil, bdContent, "BackdropTemplate")
  bdDemo2:SetSize(280, 40)
  bdDemo2:SetPoint("TOPLEFT", bdLabel2, "BOTTOMLEFT", 0, -4)
  bdDemo2:SetBackdrop(cw.BackdropSmall)
  bdDemo2:SetBackdropColor(unpack(T.header))
  bdDemo2:SetBackdropBorderColor(unpack(T.border))
  local bdText2 = bdDemo2:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  bdText2:SetPoint("CENTER")
  bdText2:SetText("Small backdrop (buttons, controls)")
  bdText2:SetTextColor(unpack(T.textDim))

  add(bdSection, function()
    bdSection:SetContentHeight(bdLabel1:GetStringHeight() + 4 + 60 + 10
                            + bdLabel2:GetStringHeight() + 4 + 40)
    return bdSection:GetConsumedHeight()
  end, 8)

  -- ---- Nested Panels -----------------------------------------------------
  local nestedSection, nestedContent = makeSection({
    title           = "Nested Panels",
    summary         = "outer + inner with theme bg variants",
    onLayoutChanged = function() relayout() end,
  })

  local outer = CreateFrame("Frame", nil, nestedContent, "BackdropTemplate")
  outer:SetSize(360, 140)
  outer:SetPoint("TOPLEFT", nestedContent, "TOPLEFT", 0, 0)
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

  nestedSection:SetContentHeight(140)
  add(nestedSection, function() return nestedSection:GetConsumedHeight() end, 8)

  -- ---- Row Styling -------------------------------------------------------
  local rowSection, rowContent = makeSection({
    title           = "Row Styling",
    summary         = "alt rows + hover highlight",
    onLayoutChanged = function() relayout() end,
  })

  local rowPanel = CreateFrame("Frame", nil, rowContent, "BackdropTemplate")
  rowPanel:SetSize(360, 120)
  rowPanel:SetPoint("TOPLEFT", rowContent, "TOPLEFT", 0, 0)
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

  rowSection:SetContentHeight(120)
  add(rowSection, function() return rowSection:GetConsumedHeight() end, 8)

  -- ---- Standard WoW Fonts ------------------------------------------------
  local fontSection, fontContent = makeSection({
    title           = "Standard WoW Fonts",
    summary         = "reference for fixed game fonts (do not respect cw.fontScale)",
    onLayoutChanged = function() relayout() end,
  })

  local fonts = {
    { "GameFontNormal",          "GameFontNormal — body text" },
    { "GameFontNormalSmall",     "GameFontNormalSmall — labels, descriptions" },
    { "GameFontNormalLarge",     "GameFontNormalLarge — page titles" },
    { "GameFontHighlight",       "GameFontHighlight — bright emphasis" },
    { "GameFontHighlightSmall",  "GameFontHighlightSmall — small emphasis" },
    { "GameFontDisable",         "GameFontDisable — disabled text" },
    { "GameFontDisableSmall",    "GameFontDisableSmall — small disabled" },
  }

  local fontFs = {}
  local prev = fontContent
  for i, fd in ipairs(fonts) do
    local fs = fontContent:CreateFontString(nil, "OVERLAY", fd[1])
    if i == 1 then
      fs:SetPoint("TOPLEFT", prev, "TOPLEFT", 0, 0)
    else
      fs:SetPoint("TOPLEFT", prev, "BOTTOMLEFT", 0, -2)
    end
    -- Bound the right edge so long sample labels (especially the Large
    -- fonts) wrap inside the section instead of extending past the page.
    fs:SetPoint("RIGHT", fontContent, "RIGHT", 0, 0)
    fs:SetJustifyH("LEFT")
    fs:SetWordWrap(true)
    fs:SetText(fd[2])
    fontFs[i] = fs
    prev = fs
  end

  add(fontSection, function()
    local h = 0
    for _, fs in ipairs(fontFs) do h = h + fs:GetStringHeight() + 2 end
    fontSection:SetContentHeight(h)
    return fontSection:GetConsumedHeight()
  end, 16)

  relayout()
  -- Settle pass — see pages.sections for rationale.
  f:SetScript("OnUpdate", function(self)
    self:SetScript("OnUpdate", nil)
    relayout()
  end)
  return f
end

-- ============================================================================
-- Page: Gear Assembly
-- ============================================================================

pages.gears = function(parent)
  local f = CreateFrame("Frame", nil, parent)
  f:SetAllPoints()
  local scroll, c = createPageFrame(f)

  local y = 0

  cw:CreateSectionHeader(c, "Suite Gear Assembly — Cluster", y)
  y = y - 20

  local desc = c:CreateFontString(nil, "OVERLAY")
  desc:SetFontObject(cw.Fonts.small)
  desc:SetPoint("TOPLEFT", c, "TOPLEFT", 8, y)
  desc:SetPoint("RIGHT", c, "RIGHT", -8, 0)
  desc:SetJustifyH("LEFT")
  desc:SetWordWrap(true)
  desc:SetText("Cogworks at the hub with FlipQueue and Tempo mesh-engaged on either side; the hub spins clockwise and the meshed pair counter-rotates. Maxcraft and Tally sit above as triangle apexes — visually a separate layer from the core trio, reflecting that they're naturally less coupled. Embed via cw:CreateGearAssembly(parent, { layout = \"cluster\" }).")
  desc:SetTextColor(unpack(T.textDim))
  y = y - 64

  local cluster = cw:CreateGearAssembly(c, { layout = "cluster" })
  cluster:SetPoint("TOP", c, "TOP", 0, y)
  y = y - (cluster:GetHeight() + 24)

  -- Linear/independent variant
  cw:CreateSectionHeader(c, "Linear (independent, with labels)", y)
  y = y - 20

  local row = cw:CreateGearAssembly(c, { layout = "row", showLabels = true })
  row:SetPoint("TOPLEFT", c, "TOPLEFT", 8, y)
  y = y - (row:GetHeight() + 20)

  -- Simulated states
  cw:CreateSectionHeader(c, "Registry Info", y)
  y = y - 22

  local registered = cw:GetRegisteredAddons()
  for _, name in ipairs(registered) do
    local info = cw:GetAddon(name)
    local line = c:CreateFontString(nil, "OVERLAY")
    line:SetFontObject(cw.Fonts.normal)
    line:SetPoint("TOPLEFT", c, "TOPLEFT", 8, y)
    line:SetText("|cffd4a017" .. name .. "|r  v" .. (info.version or "?") .. "  |cff30d530installed|r")
    y = y - 18
  end

  -- Show missing cogs
  for _, entry in ipairs(cw.SuiteRoster) do
    if not entry.central and not cw:GetAddon(entry.name) then
      local line = c:CreateFontString(nil, "OVERLAY")
      line:SetFontObject(cw.Fonts.normal)
      line:SetPoint("TOPLEFT", c, "TOPLEFT", 8, y)
      if entry.planned then
        line:SetText("|cff888888" .. entry.name .. "|r  |cff8b5cf6planned|r")
      else
        line:SetText("|cffccaa00" .. entry.name .. "|r  |cffff4040not installed|r")
      end
      y = y - 18
    end
  end

  y = y - 10
  c:SetHeight(math.abs(y) + 20)
  return f
end

-- ============================================================================
-- Page: Tables
-- ============================================================================

pages.tables = function(parent)
  local f = CreateFrame("Frame", nil, parent)
  f:SetAllPoints()

  local y = 0

  local header = cw:CreateSectionHeader(f, "CreateScrollTable — sortable, resizable columns", -8)

  -- Table container
  local tableFrame = CreateFrame("Frame", nil, f)
  tableFrame:SetPoint("TOPLEFT", f, "TOPLEFT", 8, -28)
  tableFrame:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -8, 40)

  local columns = {
    { key = "name",    label = "Character",  width = 120, sortable = true },
    { key = "realm",   label = "Realm",      width = 100, sortable = true },
    { key = "class",   label = "Class",      width = 90,  sortable = true },
    { key = "level",   label = "Level",      width = 50,  sortable = true, align = "RIGHT" },
    { key = "gold",    label = "Gold",       width = 80,  sortable = true, align = "RIGHT",
      format = function(v) return string.format("%s|cffffd100g|r", v or 0) end },
    { key = "status",  label = "Status",     width = 80,  sortable = true },
  }

  local tbl = cw:CreateScrollTable(tableFrame, columns)
  tbl:SetSort("name", true)

  -- Generate fake data
  local names = { "Gezmodean", "Chronosmith", "Brasswind", "Ticktock", "Springcoil",
    "Gearheart", "Tempora", "Auricog", "Ironpawl", "Escapement",
    "Mainspring", "Ratchetjaw", "Pendulum", "Oscillar", "Tourbillon",
    "Fusee", "Detent", "Arbor", "Pinion", "Verge" }
  local realms = { "Stormrage", "Illidan", "Area 52", "Tichondrius", "Sargeras" }
  local classes = { "Warrior", "Paladin", "Hunter", "Rogue", "Priest", "Mage",
    "Warlock", "Monk", "Druid", "Evoker", "Death Knight", "Demon Hunter", "Shaman" }
  local statuses = { "Active", "Inactive", "Alt", "Bank" }

  local fakeData = {}
  for i, name in ipairs(names) do
    fakeData[i] = {
      name   = name,
      realm  = realms[(i - 1) % #realms + 1],
      class  = classes[(i - 1) % #classes + 1],
      level  = 60 + (i * 3) % 21,
      gold   = math.floor(math.random() * 500000),
      status = statuses[(i - 1) % #statuses + 1],
      _tooltipText = name .. " — click for details",
      _tooltipExtra = "Last login: " .. (i * 7 % 30 + 1) .. " days ago",
    }
  end

  tbl:SetData(fakeData)
  tbl:SetOnRowClick(function(data, button, idx)
    cw:Print("Cogworks", "Clicked row " .. idx .. ": " .. data.name .. " (" .. button .. ")")
  end)

  -- Bottom info bar
  local info = f:CreateFontString(nil, "OVERLAY")
  info:SetFontObject(cw.Fonts.small)
  info:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 12, 12)
  info:SetText("|cffd4a017" .. #fakeData .. " rows|r — click column headers to sort, drag borders to resize")
  info:SetTextColor(unpack(T.textDim))

  return f
end

-- ============================================================================
-- Page: Popups
-- ============================================================================

pages.popups = function(parent)
  local f = CreateFrame("Frame", nil, parent)
  f:SetAllPoints()
  local scroll, c = createPageFrame(f)

  local y = 0

  cw:CreateSectionHeader(c, "CreatePopup — modal dialog", y)
  y = y - 22

  local desc = c:CreateFontString(nil, "OVERLAY")
  desc:SetFontObject(cw.Fonts.small)
  desc:SetPoint("TOPLEFT", c, "TOPLEFT", 8, y)
  desc:SetPoint("RIGHT", c, "RIGHT", -8, 0)
  desc:SetJustifyH("LEFT"); desc:SetWordWrap(true)
  desc:SetText("Popups are modal dialogs with a dark overlay, draggable title bar, content area, and action buttons. ESC to dismiss. Use ShowConfirmDialog for yes/no prompts.")
  desc:SetTextColor(unpack(T.textDim))
  y = y - 40

  -- Basic popup
  local basicBtn = cw:CreateButton(c, "Open Basic Popup", 180, 28, function()
    local popup = cw:CreatePopup({
      title = "Basic Popup", width = 400, height = 200,
    })
    local msg = popup.content:CreateFontString(nil, "OVERLAY")
    msg:SetFontObject(cw.Fonts.normal)
    msg:SetAllPoints()
    msg:SetJustifyH("LEFT"); msg:SetJustifyV("TOP"); msg:SetWordWrap(true)
    msg:SetText("This is a basic popup with a content area and action buttons. You can put any widgets in the content area — forms, lists, whatever the cog needs.\n\nDrag the title bar to move it. Press ESC or click the X to close.")
    msg:SetTextColor(unpack(T.text))
    popup:SetButtons({
      { label = "Got It" },
    })
    popup:Show()
  end)
  basicBtn:SetPoint("TOPLEFT", c, "TOPLEFT", 8, y)
  y = y - 36

  -- Confirm dialog
  local confirmBtn = cw:CreateButton(c, "Show Confirm Dialog", 180, 28, function()
    cw:ShowConfirmDialog(
      "Delete Character Data?",
      "This will permanently delete all saved data for Gezmodean-Stormrage. This action cannot be undone.",
      function() cw:Print("Cogworks", "Confirmed!") end,
      function() cw:Print("Cogworks", "Cancelled.") end
    )
  end)
  confirmBtn:SetPoint("TOPLEFT", c, "TOPLEFT", 8, y)
  y = y - 36

  -- Multi-button popup
  local multiBtn = cw:CreateButton(c, "Multi-Button Popup", 180, 28, function()
    local popup = cw:CreatePopup({
      title = "Export Options", width = 420, height = 180,
    })
    local msg = popup.content:CreateFontString(nil, "OVERLAY")
    msg:SetFontObject(cw.Fonts.normal)
    msg:SetAllPoints()
    msg:SetJustifyH("LEFT"); msg:SetJustifyV("TOP"); msg:SetWordWrap(true)
    msg:SetText("Choose an export format for your data.")
    msg:SetTextColor(unpack(T.text))
    popup:SetButtons({
      { label = "CSV", width = 70, onClick = function() cw:Print("Cogworks", "Exported as CSV") end },
      { label = "JSON", width = 70, onClick = function() cw:Print("Cogworks", "Exported as JSON") end },
      { label = "Cancel", width = 70 },
    })
    popup:Show()
  end)
  multiBtn:SetPoint("TOPLEFT", c, "TOPLEFT", 8, y)
  y = y - 50

  cw:CreateSectionHeader(c, "Usage", y)
  y = y - 22

  local usage = c:CreateFontString(nil, "OVERLAY")
  usage:SetFontObject(cw.Fonts.small)
  usage:SetPoint("TOPLEFT", c, "TOPLEFT", 8, y)
  usage:SetPoint("RIGHT", c, "RIGHT", -8, 0)
  usage:SetJustifyH("LEFT"); usage:SetWordWrap(true)
  usage:SetText("local popup = cw:CreatePopup({ title=\"...\", width=400, height=200 })\n-- Add widgets to popup.content\npopup:SetButtons({ {label=\"OK\", onClick=fn}, {label=\"Cancel\"} })\npopup:Show()\n\n-- Shortcut:\ncw:ShowConfirmDialog(\"Title\", \"Message\", onConfirm, onCancel)")
  usage:SetTextColor(unpack(T.textDim))

  y = y - 100
  c:SetHeight(math.abs(y) + 20)
  return f
end

-- ============================================================================
-- Page: Settings
-- ============================================================================

pages.settings = function(parent)
  local f = CreateFrame("Frame", nil, parent)
  f:SetAllPoints()
  local scroll, c = createPageFrame(f)

  local y = 0

  -- Font Family
  local fontSource = cw:HasSharedMedia() and "LibSharedMedia" or "Built-in"
  cw:CreateSectionHeader(c, "Font Family (" .. fontSource .. ")", y)
  y = y - 24

  local fontList = cw:GetFontList()
  local fontItems = {}
  for _, fi in ipairs(fontList) do
    fontItems[#fontItems + 1] = { key = fi.key, label = fi.label, fontPath = fi.path }
  end

  local fontDD = cw:CreateDropdown(c, fontItems, cw:GetSetting("fontFamily") or "default", function(key, label)
    cw:SetSetting("fontFamily", key)
  end)
  fontDD:SetSize(240, 26)
  fontDD:SetPoint("TOPLEFT", c, "TOPLEFT", 8, y)
  y = y - 40

  -- Font Scale
  cw:CreateSectionHeader(c, "Font Scale", y)
  y = y - 22

  local fontValText = c:CreateFontString(nil, "OVERLAY")
  fontValText:SetFontObject(cw.Fonts.normal)
  fontValText:SetPoint("TOPLEFT", c, "TOPLEFT", 8, y)
  fontValText:SetText("Current: " .. string.format("%.0f%%", cw:GetSetting("fontScale") * 100))
  fontValText:SetTextColor(unpack(T.text))
  y = y - 28

  local scales = { 0.8, 0.9, 1.0, 1.1, 1.2, 1.3, 1.4 }
  xOff = 8
  for _, s in ipairs(scales) do
    local label = string.format("%.0f%%", s * 100)
    local btn = cw:CreateButton(c, label, 52, 24, function()
      cw:SetSetting("fontScale", s)
      fontValText:SetText("Current: " .. label)
    end)
    btn:SetPoint("TOPLEFT", c, "TOPLEFT", xOff, y)
    xOff = xOff + 58
  end
  y = y - 40

  -- Font preview
  cw:CreateSectionHeader(c, "Font Preview", y)
  y = y - 22

  local previewFonts = {
    { key = "large",  label = "cw.Fonts.large — Page Titles" },
    { key = "normal", label = "cw.Fonts.normal — Body Text" },
    { key = "small",  label = "cw.Fonts.small — Labels & Descriptions" },
    { key = "header", label = "cw.Fonts.header — SECTION HEADERS" },
  }
  for _, pf in ipairs(previewFonts) do
    local fs = c:CreateFontString(nil, "OVERLAY")
    fs:SetFontObject(cw:GetFont(pf.key))
    fs:SetPoint("TOPLEFT", c, "TOPLEFT", 8, y)
    fs:SetText(pf.label)
    fs:SetTextColor(unpack(T.text))
    y = y - 22
  end
  y = y - 16

  -- UI Scale
  cw:CreateSectionHeader(c, "UI Scale", y)
  y = y - 22

  local uiValText = c:CreateFontString(nil, "OVERLAY")
  uiValText:SetFontObject(cw.Fonts.normal)
  uiValText:SetPoint("TOPLEFT", c, "TOPLEFT", 8, y)
  uiValText:SetText("Current: " .. string.format("%.0f%%", cw:GetSetting("uiScale") * 100))
  uiValText:SetTextColor(unpack(T.text))
  y = y - 28

  xOff = 8
  for _, s in ipairs(scales) do
    local label = string.format("%.0f%%", s * 100)
    local btn = cw:CreateButton(c, label, 52, 24, function()
      cw:SetSetting("uiScale", s)
      uiValText:SetText("Current: " .. label)
      if showcase then showcase:SetScale(s) end
    end)
    btn:SetPoint("TOPLEFT", c, "TOPLEFT", xOff, y)
    xOff = xOff + 58
  end
  y = y - 40

  -- Reset
  cw:CreateSectionHeader(c, "Reset", y)
  y = y - 22

  local resetBtn = cw:CreateButton(c, "Reset All to Defaults", 180, 28, function()
    local defaults = cw:GetSettingDefaults()
    for k, v in pairs(defaults) do cw:SetSetting(k, v) end
    fontValText:SetText("Current: 100%")
    uiValText:SetText("Current: 100%")
    familyLabel:SetText("Current: Friz Quadrata")
    if showcase then showcase:SetScale(1.0) end
    cw:Print("Cogworks", "Settings reset to defaults.")
  end)
  resetBtn:SetPoint("TOPLEFT", c, "TOPLEFT", 8, y)
  y = y - 50

  -- Live preview
  cw:CreateSectionHeader(c, "Live Widget Preview", y)
  y = y - 22

  local demoBtn = cw:CreateButton(c, "Sample Button", 140, 28, nil)
  demoBtn:SetPoint("TOPLEFT", c, "TOPLEFT", 8, y)
  y = y - 36

  local demoCb = cw:CreateCheckbox(c, "Sample checkbox", "Description text scales with font settings.", false, nil)
  demoCb:SetPoint("TOPLEFT", c, "TOPLEFT", 8, y)
  y = y - 50

  local demoBar = cw:CreateProgressBar(c, 250, 18)
  demoBar:SetPoint("TOPLEFT", c, "TOPLEFT", 8, y)
  demoBar:SetProgress(7, 10)
  y = y - 30

  c:SetHeight(math.abs(y) + 20)
  return f
end

-- ============================================================================
-- Page: Tree (CreateTree demo)
-- ============================================================================

pages.tree = function(parent)
  local f = CreateFrame("Frame", nil, parent)
  f:SetAllPoints()

  local intro = f:CreateFontString(nil, "OVERLAY")
  intro:SetFontObject(cw.Fonts.small)
  intro:SetPoint("TOPLEFT", f, "TOPLEFT", 12, -12)
  intro:SetPoint("RIGHT", f, "RIGHT", -12, 0)
  intro:SetJustifyH("LEFT")
  intro:SetWordWrap(true)
  intro:SetTextColor(unpack(T.textDim))
  intro:SetText("Click chevrons (or the row near the chevron) to expand / collapse. "
              .. "Click anywhere else on a row to select. The print line below logs each select event.")

  local sel = f:CreateFontString(nil, "OVERLAY")
  sel:SetFontObject(cw.Fonts.small)
  sel:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 12, 8)
  sel:SetTextColor(unpack(T.textDim))
  sel:SetText("selected: <none>")

  local tree = cw:CreateTree(f, {
    onSelect = function(key, node)
      sel:SetText("selected: " .. key .. "  (label: " .. (node.label or "?") .. ")")
    end,
  })
  tree:SetPoint("TOPLEFT", intro, "BOTTOMLEFT", 0, -12)
  tree:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -8, 28)

  tree:SetNodes({
    { key = "armor", label = "Armor", count = 12, children = {
      { key = "armor.cloth",   label = "Cloth",   count = 3 },
      { key = "armor.leather", label = "Leather", count = 4 },
      { key = "armor.mail",    label = "Mail",    count = 2 },
      { key = "armor.plate",   label = "Plate",   count = 3 },
    }},
    { key = "weapons", label = "Weapons", count = 8, children = {
      { key = "weapons.1h", label = "One-handed", count = 5, children = {
        { key = "weapons.1h.swords", label = "Swords", count = 2 },
        { key = "weapons.1h.maces",  label = "Maces",  count = 2 },
        { key = "weapons.1h.daggers", label = "Daggers", count = 1 },
      }},
      { key = "weapons.2h", label = "Two-handed", count = 3 },
    }},
    { key = "consumables", label = "Consumables", count = 24, children = {
      { key = "cons.flask",  label = "Flasks",  count = 6 },
      { key = "cons.potion", label = "Potions", count = 12 },
      { key = "cons.food",   label = "Food",    count = 6 },
    }},
    { key = "misc", label = "Miscellaneous (no children)" },
  })
  tree:Expand("armor")

  return f
end

-- ============================================================================
-- Page: ReorderableList (CreateReorderableList demo)
-- ============================================================================

pages.reorder = function(parent)
  local f = CreateFrame("Frame", nil, parent)
  f:SetAllPoints()

  local intro = f:CreateFontString(nil, "OVERLAY")
  intro:SetFontObject(cw.Fonts.small)
  intro:SetPoint("TOPLEFT", f, "TOPLEFT", 12, -12)
  intro:SetPoint("RIGHT", f, "RIGHT", -12, 0)
  intro:SetJustifyH("LEFT")
  intro:SetWordWrap(true)
  intro:SetTextColor(unpack(T.textDim))
  intro:SetText("Drag rows by the brass handle (or any non-text part of the row) to reorder. "
              .. "Caller-supplied renderRow populates each row's contents; the list re-orders the items "
              .. "array on drop and fires onReorder.")

  local order = f:CreateFontString(nil, "OVERLAY")
  order:SetFontObject(cw.Fonts.small)
  order:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 12, 8)
  order:SetPoint("RIGHT", f, "RIGHT", -12, 0)
  order:SetJustifyH("LEFT")
  order:SetTextColor(unpack(T.textDim))

  local items = { "Mythic Plus", "Raid Night", "Auction House", "Profession Cooldowns",
                  "Daily Reset", "Weekly Reset", "Mailbox", "Bank Run" }

  -- Distinct dim background per row so the user can track which row went
  -- where after a drag — without colors a pool-recycled row that lands in a
  -- different slot looks identical to its old position.
  local ROW_TINTS = {
    { 0.22, 0.10, 0.12, 0.75 },  -- crimson
    { 0.22, 0.14, 0.06, 0.75 },  -- amber
    { 0.18, 0.18, 0.06, 0.75 },  -- ochre
    { 0.10, 0.20, 0.10, 0.75 },  -- forest
    { 0.06, 0.16, 0.20, 0.75 },  -- teal
    { 0.10, 0.12, 0.22, 0.75 },  -- indigo
    { 0.18, 0.10, 0.22, 0.75 },  -- violet
    { 0.20, 0.10, 0.16, 0.75 },  -- magenta
  }

  local list = cw:CreateReorderableList(f, {
    items     = items,
    rowHeight = 26,
    renderRow = function(row, item, index)
      row.label = row.label or row:CreateFontString(nil, "OVERLAY")
      row.label:SetFontObject(cw.Fonts.normal)
      row.label:SetPoint("LEFT", row, "LEFT", 24, 0)
      row.label:SetTextColor(unpack(T.text))
      row.label:SetText(string.format("%d. %s", index, item))

      -- Color the row by its label (the *content*), not its position. That
      -- way each task keeps its tint as it gets dragged around — making
      -- before/after order much easier to read.
      local function hashColor(str)
        local h = 0
        for i = 1, #str do h = (h * 31 + str:byte(i)) % 1000003 end
        return ROW_TINTS[(h % #ROW_TINTS) + 1]
      end
      row:SetBackdropColor(unpack(hashColor(item)))
    end,
    onReorder = function(items_, from, to)
      cw:Print("Cogworks", "reordered: " .. from .. " -> " .. to)
      local parts = {}
      for i, v in ipairs(items_) do parts[i] = v end
      order:SetText("order: " .. table.concat(parts, " | "))
    end,
  })
  list:SetPoint("TOPLEFT", intro, "BOTTOMLEFT", 0, -12)
  list:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -8, 32)

  -- Initial order display
  local parts = {}
  for i, v in ipairs(items) do parts[i] = v end
  order:SetText("order: " .. table.concat(parts, " | "))

  return f
end

-- ============================================================================
-- Page: Wizard (CreateWizard demo)
-- ============================================================================

pages.wizard = function(parent)
  local f = CreateFrame("Frame", nil, parent)
  f:SetAllPoints()

  local wizardState = { agreed = false, name = "" }
  local nameRow
  -- Forward-declare so the build/onChange closures inside the table arg below
  -- can see the upvalue. Otherwise `local wizard = cw:CreateWizard(...)` only
  -- introduces the local AFTER the table evaluates, and the closures resolve
  -- `wizard` as a (nil) global.
  local wizard
  wizard = cw:CreateWizard(f, {
    onComplete = function()
      cw:Print("Cogworks", "wizard finished — name = " .. (wizardState.name or "<empty>"))
    end,
    onCancel = function()
      cw:Print("Cogworks", "wizard cancelled")
    end,
    onStepChange = function(key, idx)
      cw:Print("Cogworks", "wizard step " .. idx .. " (" .. key .. ")")
    end,
    steps = {
      { key = "welcome", title = "Welcome",
        build = function(c)
          local p = CreateFrame("Frame", nil, c); p:SetAllPoints()
          local fs = p:CreateFontString(nil, "OVERLAY")
          fs:SetFontObject(cw.Fonts.normal)
          fs:SetPoint("TOPLEFT", p, "TOPLEFT", 16, -16)
          fs:SetPoint("RIGHT", p, "RIGHT", -16, 0)
          fs:SetJustifyH("LEFT")
          fs:SetWordWrap(true)
          fs:SetTextColor(unpack(T.text))
          fs:SetText("Welcome step. The 'Previous' button is disabled here because we're "
                  .. "on the first step. Click 'Next' to advance — no validation gate on "
                  .. "this step, so the Next button is always enabled.")
          return p
        end },

      { key = "agree", title = "Agree",
        build = function(c)
          local p = CreateFrame("Frame", nil, c); p:SetAllPoints()
          local fs = p:CreateFontString(nil, "OVERLAY")
          fs:SetFontObject(cw.Fonts.normal)
          fs:SetPoint("TOPLEFT", p, "TOPLEFT", 16, -16)
          fs:SetPoint("RIGHT", p, "RIGHT", -16, 0)
          fs:SetJustifyH("LEFT")
          fs:SetWordWrap(true)
          fs:SetTextColor(unpack(T.text))
          fs:SetText("Validation-gate step. The 'Next' button stays disabled until you "
                  .. "tick the checkbox below — toggling the checkbox calls "
                  .. "wizard:Refresh() so the footer state updates immediately.")

          local row = cw:CreateSettingsCheckbox(p, {
            label    = "I agree to the demo",
            description = "Required to advance.",
            value    = wizardState.agreed,
            onChange = function(v)
              wizardState.agreed = v
              wizard:Refresh()
            end,
          })
          row:SetPoint("TOPLEFT", fs, "BOTTOMLEFT", 0, -16)
          row:SetPoint("TOPRIGHT", fs, "BOTTOMRIGHT", 0, -16)

          return p
        end,
        validate = function() return wizardState.agreed end,
      },

      { key = "name", title = "Name",
        build = function(c)
          local p = CreateFrame("Frame", nil, c); p:SetAllPoints()
          local fs = p:CreateFontString(nil, "OVERLAY")
          fs:SetFontObject(cw.Fonts.normal)
          fs:SetPoint("TOPLEFT", p, "TOPLEFT", 16, -16)
          fs:SetPoint("RIGHT", p, "RIGHT", -16, 0)
          fs:SetJustifyH("LEFT")
          fs:SetWordWrap(true)
          fs:SetTextColor(unpack(T.text))
          fs:SetText("CreateSettingsInput inside a wizard step. Validation requires a "
                  .. "non-empty name. Press Enter or tab away from the input to commit "
                  .. "before clicking Next.")

          nameRow = cw:CreateSettingsInput(p, {
            label       = "Display name",
            value       = wizardState.name,
            inputWidth  = 200,
            onChange    = function(v)
              wizardState.name = v
              wizard:Refresh()
            end,
          })
          nameRow:SetPoint("TOPLEFT", fs, "BOTTOMLEFT", 0, -16)
          nameRow:SetPoint("TOPRIGHT", fs, "BOTTOMRIGHT", 0, -16)

          return p
        end,
        validate = function() return wizardState.name and wizardState.name ~= "" end,
      },

      { key = "review", title = "Review",
        build = function(c)
          local p = CreateFrame("Frame", nil, c); p:SetAllPoints()
          local fs = p:CreateFontString(nil, "OVERLAY")
          fs:SetFontObject(cw.Fonts.normal)
          fs:SetPoint("TOPLEFT", p, "TOPLEFT", 16, -16)
          fs:SetPoint("RIGHT", p, "RIGHT", -16, 0)
          fs:SetJustifyH("LEFT")
          fs:SetWordWrap(true)
          fs:SetTextColor(unpack(T.text))
          -- Re-text on Show so the latest wizardState shows. This is a
          -- showcase-only quirk — real wizards would persist immediately
          -- on the previous step's onChange, not lazily at review time.
          local function refresh()
            fs:SetText("Final step. The Next button is now labeled 'Finish'.\n\n"
                    .. "Agreed: " .. tostring(wizardState.agreed) .. "\n"
                    .. "Name:   " .. (wizardState.name ~= "" and wizardState.name or "<empty>"))
          end
          refresh()
          p:SetScript("OnShow", refresh)
          return p
        end,
      },
    },
  })
  wizard:SetPoint("TOPLEFT", f, "TOPLEFT", 8, -8)
  wizard:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -8, 8)

  return f
end

-- ============================================================================
-- Page: MiniView (CreateMiniView demo)
-- ============================================================================

-- Backed by a transient table local to the showcase — a real cog would
-- pass its persistent SavedVariables sub-table here.
local _showcaseMiniSV = {}
local _showcaseMini

pages.mini = function(parent)
  local f = CreateFrame("Frame", nil, parent)
  f:SetAllPoints()

  local intro = f:CreateFontString(nil, "OVERLAY")
  intro:SetFontObject(cw.Fonts.normal)
  intro:SetPoint("TOPLEFT", f, "TOPLEFT", 12, -12)
  intro:SetPoint("RIGHT", f, "RIGHT", -12, 0)
  intro:SetJustifyH("LEFT")
  intro:SetWordWrap(true)
  intro:SetTextColor(unpack(T.text))
  intro:SetText("CreateMiniView opens a draggable, resizable, persistable heads-up frame "
              .. "with the suite's standard chrome (title bar, pin, close, resize grip). "
              .. "Position, size, and pinned state are written to the savedvars table the "
              .. "caller passes in — for the showcase, that's a transient Lua table local "
              .. "to this page, so geometry is forgotten on /reload.")

  local btn = cw:CreateButton(f, "Open demo MiniView", 200, 28, function()
    if not _showcaseMini then
      _showcaseMini = cw:CreateMiniView({
        name      = "CogworksShowcaseMini",
        title     = "Demo Mini",
        width     = 240, height = 140,
        savedvars = _showcaseMiniSV,
        onClose   = function() cw:Print("Cogworks", "demo mini hidden") end,
        onPin     = function(p) cw:Print("Cogworks", "demo mini " .. (p and "pinned" or "unpinned")) end,
      })
      local body = _showcaseMini.content:CreateFontString(nil, "OVERLAY")
      body:SetFontObject(cw.Fonts.normal)
      body:SetPoint("TOPLEFT", _showcaseMini.content, "TOPLEFT", 4, -4)
      body:SetPoint("RIGHT", _showcaseMini.content, "RIGHT", -4, 0)
      body:SetJustifyH("LEFT")
      body:SetWordWrap(true)
      body:SetTextColor(unpack(T.text))
      body:SetText("Drag the title bar to move. Drag the bottom-right corner to resize. "
                .. "Click the pin to lock; click again to unlock. Close hides the frame.")
    end
    if _showcaseMini:IsShown() then _showcaseMini:Hide() else _showcaseMini:Show() end
  end)
  btn:SetPoint("TOPLEFT", intro, "BOTTOMLEFT", 0, -16)

  return f
end

-- ============================================================================
-- Page: Text helpers (QualityColorName, ClassColorName, FormatGoldValue, FormatGSC)
-- ============================================================================

pages.text = function(parent)
  local f = CreateFrame("Frame", nil, parent)
  f:SetAllPoints()

  local y = 0
  local function addLine(text)
    local fs = f:CreateFontString(nil, "OVERLAY")
    fs:SetFontObject(cw.Fonts.normal)
    fs:SetPoint("TOPLEFT", f, "TOPLEFT", 12, -12 + y)
    fs:SetPoint("RIGHT", f, "RIGHT", -12, 0)
    fs:SetJustifyH("LEFT")
    fs:SetWordWrap(true)
    fs:SetTextColor(unpack(T.text))
    fs:SetText(text)
    -- Wrapped text takes more vertical space than a single line. Use the
    -- string's actual height plus a small gap so successive lines never
    -- overlap at higher fontScale.
    y = y - math.max(22, fs:GetStringHeight() + 4)
  end

  local function addHeader(text)
    y = y - 6
    local h = f:CreateFontString(nil, "OVERLAY")
    h:SetFontObject(cw.Fonts.header)
    h:SetPoint("TOPLEFT", f, "TOPLEFT", 12, -12 + y)
    h:SetPoint("RIGHT", f, "RIGHT", -12, 0)
    h:SetJustifyH("LEFT")
    h:SetText(text:upper())
    h:SetTextColor(unpack(T.textDim))
    y = y - math.max(22, h:GetStringHeight() + 4)
  end

  addHeader("QualityColorName")
  addLine("Numeric: " .. cw:QualityColorName("Common item", 1)
       .. "  " .. cw:QualityColorName("Uncommon item", 2)
       .. "  " .. cw:QualityColorName("Rare item", 3))
  addLine("More: " .. cw:QualityColorName("Epic item", 4)
       .. "  " .. cw:QualityColorName("Legendary item", 5)
       .. "  " .. cw:QualityColorName("Heirloom item", 7))
  addLine("Named: " .. cw:QualityColorName("Rare", "Rare")
       .. " / " .. cw:QualityColorName("Legendary", "Legendary"))

  addHeader("ClassColorName")
  addLine(cw:ClassColorName("Warrior", "WARRIOR")
       .. "  " .. cw:ClassColorName("Paladin", "PALADIN")
       .. "  " .. cw:ClassColorName("Hunter", "HUNTER")
       .. "  " .. cw:ClassColorName("Rogue", "ROGUE")
       .. "  " .. cw:ClassColorName("Priest", "PRIEST"))
  addLine(cw:ClassColorName("Death Knight", "DEATHKNIGHT")
       .. "  " .. cw:ClassColorName("Shaman", "SHAMAN")
       .. "  " .. cw:ClassColorName("Mage", "MAGE")
       .. "  " .. cw:ClassColorName("Warlock", "WARLOCK"))
  addLine(cw:ClassColorName("Monk", "MONK")
       .. "  " .. cw:ClassColorName("Druid", "DRUID")
       .. "  " .. cw:ClassColorName("Demon Hunter", "DEMONHUNTER")
       .. "  " .. cw:ClassColorName("Evoker", "EVOKER"))

  addHeader("FormatGoldValue")
  addLine("Below 1k:  150 gold = " .. cw:FormatGoldValue(150))
  addLine("Above 1k:  4250 gold = " .. cw:FormatGoldValue(4250))
  addLine("Above 100k: 250000 gold = " .. cw:FormatGoldValue(250000))

  addHeader("FormatGSC (copper input)")
  addLine("12g 34s 56c = " .. cw:FormatGSC(123456))
  addLine("0g 5s 0c    = " .. cw:FormatGSC(500))
  addLine("just copper = " .. cw:FormatGSC(75))
  addLine("zero        = " .. cw:FormatGSC(0))

  addHeader("FormatGoldShort (copper input)")
  addLine("13g       = " .. cw:FormatGoldShort(133456))
  addLine("12.3k     = " .. cw:FormatGoldShort(123456789))
  addLine("1.2m      = " .. cw:FormatGoldShort(12345678901))

  return f
end

-- ============================================================================
-- Page: Tabs (CreateTabPanel demo)
-- ============================================================================

pages.tabs = function(parent)
  local f = CreateFrame("Frame", nil, parent)
  f:SetAllPoints()

  local activeLabel = f:CreateFontString(nil, "OVERLAY")
  activeLabel:SetFontObject(cw.Fonts.small)
  activeLabel:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 8, 8)
  activeLabel:SetTextColor(unpack(T.textDim))

  local function buildTextPage(text)
    return function(c)
      local p = CreateFrame("Frame", nil, c)
      p:SetAllPoints()
      local fs = p:CreateFontString(nil, "OVERLAY")
      fs:SetFontObject(cw.Fonts.normal)
      fs:SetPoint("TOPLEFT", p, "TOPLEFT", 12, -12)
      fs:SetPoint("RIGHT", p, "RIGHT", -12, 0)
      fs:SetJustifyH("LEFT")
      fs:SetWordWrap(true)
      fs:SetTextColor(unpack(T.text))
      fs:SetText(text)
      return p
    end
  end

  local panel = cw:CreateTabPanel(f, {
    initialTab = "general",
    onTabChange = function(key)
      activeLabel:SetText("active tab: " .. key)
      cw:Print("Cogworks", "tab switched: " .. key)
    end,
    tabs = {
      { key = "general",  label = "General",
        build = buildTextPage("General-tab content. Tab pages are lazy-built — this Frame was created the first time you navigated to this tab. Switching to another tab Hides this one; coming back Shows it without re-running build.") },
      { key = "advanced", label = "Advanced",
        build = buildTextPage("Advanced-tab content. Note the gold accent line under the active tab and the slight bg lift on hover — both pulled from the same theme constants the rest of the suite uses.") },
      { key = "research", label = "Research / Notes",
        build = buildTextPage("Tabs auto-size to their label width with a 60 px floor. Switching font scale on the Settings page reflows the strip without clipping. The strip border below the tabs is one continuous line at theme.border; the active accent rides over it on the bottom edge of the active tab.") },
      { key = "about",    label = "About",
        build = buildTextPage("CreateTabPanel — Cogworks-1.0 MINOR 15. Each tab is { key, label, build = function(parent) ... return frame end }. Caller owns the page frames; the panel only handles Show/Hide on switch.") },
    },
  })
  panel:SetPoint("TOPLEFT", f, "TOPLEFT", 8, -8)
  panel:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -8, 24)

  return f
end

-- ============================================================================
-- Page: Sections (collapsible sections + settings form helpers + dropdown auto-width)
-- ============================================================================

pages.sections = function(parent)
  local f = CreateFrame("Frame", nil, parent)
  f:SetAllPoints()
  local scroll, c = createPageFrame(f)

  -- Page-level y-stack: each item is { frame, heightFn, gapAfter, fullWidth }.
  -- relayout() re-walks the stack so a collapsible section toggling open or
  -- closed pushes the items below it down/up instead of overlapping them.
  local items = {}
  local function add(frame, heightFn, gapAfter, fullWidth)
    items[#items + 1] = {
      f          = frame,
      h          = heightFn,
      gap        = gapAfter or 4,
      fullWidth  = fullWidth ~= false,  -- default true
    }
  end

  local function relayout()
    local y = 0
    for _, it in ipairs(items) do
      it.f:ClearAllPoints()
      it.f:SetPoint("TOPLEFT", c, "TOPLEFT", 8, -y)
      if it.fullWidth then
        it.f:SetPoint("TOPRIGHT", c, "TOPRIGHT", -8, -y)
      end
      y = y + it.h() + it.gap
    end
    c:SetHeight(y + 20)
  end

  -- Helper: a section header that participates in the y-stack.
  local function addSectionHeader(text, gapAfter)
    local h = c:CreateFontString(nil, "OVERLAY")
    h:SetFontObject(cw.Fonts.header)
    h:SetJustifyH("LEFT")
    h:SetText(text:upper())
    h:SetTextColor(unpack(T.textDim))
    add(h, function() return 16 end, gapAfter or 6)
    return h
  end

  -- ---- CreateCollapsibleSection demos ------------------------------------
  addSectionHeader("CreateCollapsibleSection")

  -- Build a section with a wrapping body FontString. SetContentHeightFn
  -- means applyLayout reads body:GetStringHeight() fresh on every layout
  -- pass — so the post-show settle pass inside Sections.lua picks up the
  -- wrapped height once WoW has rendered the frame, without us having to
  -- overwrite a previously-correct stored height with a stale single-line
  -- value (which is what the SetContentHeight pattern did when the body
  -- was hidden mid-collapse).
  local function makeTextSection(opts, text)
    local section = cw:CreateCollapsibleSection(c, opts)
    local body = section.content:CreateFontString(nil, "OVERLAY")
    body:SetFontObject(cw:GetFont("normal"))
    body:SetPoint("TOPLEFT", section.content, "TOPLEFT", 0, 0)
    body:SetPoint("RIGHT", section.content, "RIGHT", 0, 0)
    body:SetJustifyH("LEFT")
    body:SetWordWrap(true)
    body:SetTextColor(unpack(T.text))
    body:SetText(text)
    section:SetContentHeightFn(function() return body:GetStringHeight() + 4 end)
    return section, function() return section:GetConsumedHeight() end
  end

  local sec1, sec1H = makeTextSection({
    title           = "Section A",
    summary         = "open by default; toggling reflows the page below",
    onLayoutChanged = function() relayout() end,
  }, "Section bodies render whatever you put into section.content. Width is fixed at construction; height comes from SetContentHeight, which the section uses to size itself plus its chrome.")
  add(sec1, sec1H, 4)

  local sec2, sec2H = makeTextSection({
    title           = "Section B",
    summary         = "starts collapsed; click to expand",
    startCollapsed  = true,
    onLayoutChanged = function() relayout() end,
  }, "The chevron is the suite-wide icon registry's chevron-right / chevron-down (issue #9) — WoW's default fonts don't ship Unicode Geometric Shapes, so registered atlases stand in.")
  add(sec2, sec2H, 16)

  -- ---- Settings form helpers (live-stacked with y-cursor) ----------------
  addSectionHeader("Settings Form Helpers")

  local formSection = cw:CreateCollapsibleSection(c, {
    title           = "Form rows (CreateSettingsCheckbox / Button / Input)",
    summary         = "y-cursor stack; reflows on font change and on toggle",
    onLayoutChanged = function() relayout() end,
  })

  local demoState = { foo = true, bar = false, queueSize = 50, label = "Hello" }
  local rowYs = {}

  -- Anchor each row at its current y-cursor position. Row heights drive the
  -- y-cursor — Forms.lua's row:GetConsumedHeight() returns row:GetHeight()
  -- which is set by the row's own applyLayout pass.
  local function anchorFormRows()
    local fy = 4
    for _, r in ipairs(rowYs) do
      r.row:ClearAllPoints()
      r.row:SetPoint("TOPLEFT", formSection.content, "TOPLEFT", 0, -fy)
      r.row:SetPoint("TOPRIGHT", formSection.content, "TOPRIGHT", 0, -fy)
      fy = fy + r.row:GetConsumedHeight()
    end
    return fy + 4
  end

  -- Section-level height = anchored row stack height. Returned fresh each
  -- pass so the post-show settle inside Sections.lua picks up wrapped
  -- description heights once they've measured.
  formSection:SetContentHeightFn(anchorFormRows)

  local function relayoutFormRows()
    -- Triggers formSection's applyLayout, which calls anchorFormRows via
    -- the contentHeightFn — that re-anchors rows AND updates the section
    -- height in one pass. Then bubble up to the page-level stack.
    formSection:SetContentHeightFn(anchorFormRows)
    relayout()
  end

  local function pushRow(row)
    rowYs[#rowYs + 1] = { row = row }
  end

  local cbRow = cw:CreateSettingsCheckbox(formSection.content, {
    label       = "Enable foo",
    description = "Toggles the foo subsystem. The description wraps when the row gets narrow.",
    value       = demoState.foo,
    onChange    = function(v) demoState.foo = v; cw:Print("Cogworks", "foo: " .. tostring(v)) end,
    onHeightChanged = relayoutFormRows,
  })
  pushRow(cbRow)

  local cbRow2 = cw:CreateSettingsCheckbox(formSection.content, {
    label    = "Enable bar (no description)",
    value    = demoState.bar,
    onChange = function(v) demoState.bar = v; cw:Print("Cogworks", "bar: " .. tostring(v)) end,
    onHeightChanged = relayoutFormRows,
  })
  pushRow(cbRow2)

  local btnRow = cw:CreateSettingsButton(formSection.content, {
    label       = "Reset demo state",
    description = "Restores the demo defaults shown on this page.",
    buttonText  = "Reset",
    buttonWidth = 100,
    onClick     = function()
      demoState.foo, demoState.bar, demoState.queueSize, demoState.label = true, false, 50, "Hello"
      cbRow:SetValue(true)
      cbRow2:SetValue(false)
      cw:Print("Cogworks", "demo state reset")
    end,
    onHeightChanged = relayoutFormRows,
  })
  pushRow(btnRow)

  local inputRow = cw:CreateSettingsInput(formSection.content, {
    label       = "Max queue size",
    description = "Numeric input — commits on Enter or focus loss.",
    value       = demoState.queueSize,
    numeric     = true,
    inputWidth  = 80,
    maxLetters  = 5,
    onChange    = function(v) demoState.queueSize = v; cw:Print("Cogworks", "queue size: " .. tostring(v)) end,
    onHeightChanged = relayoutFormRows,
  })
  pushRow(inputRow)

  local inputRow2 = cw:CreateSettingsInput(formSection.content, {
    label       = "Free-form label",
    description = "Text input.",
    value       = demoState.label,
    inputWidth  = 160,
    onChange    = function(v) demoState.label = v; cw:Print("Cogworks", "label: " .. tostring(v)) end,
    onHeightChanged = relayoutFormRows,
  })
  pushRow(inputRow2)

  relayoutFormRows()
  add(formSection, function() return formSection:GetConsumedHeight() end, 16)

  -- ---- CreateDropdown autoWidth comparison -------------------------------
  addSectionHeader("CreateDropdown — autoWidth")

  local ddItems = {
    { key = "s",   label = "Short" },
    { key = "m",   label = "Medium-length entry" },
    { key = "l",   label = "A much longer label that would clip a fixed dropdown" },
    { key = "xl",  label = "An even longer label demonstrating the upper-clamp behavior" },
    { key = "tn",  label = "tn" },
  }

  -- Wrap each dropdown in a row frame so the y-stack can manage it cleanly.
  local fixedRow = CreateFrame("Frame", nil, c)
  fixedRow:SetHeight(28)
  local fixedDD = cw:CreateDropdown(fixedRow, ddItems, "s",
    function(k) cw:Print("Cogworks", "fixed: " .. k) end)
  fixedDD:SetPoint("LEFT", fixedRow, "LEFT", 0, 0)
  local fixedLabel = fixedRow:CreateFontString(nil, "OVERLAY")
  fixedLabel:SetFontObject(cw:GetFont("small"))
  fixedLabel:SetPoint("LEFT", fixedDD, "RIGHT", 12, 0)
  fixedLabel:SetTextColor(unpack(T.textDim))
  fixedLabel:SetText("fixed 200px (legacy 4-arg signature)")
  add(fixedRow, function() return 28 end, 8, false)

  local autoRow = CreateFrame("Frame", nil, c)
  autoRow:SetHeight(28)
  local autoDD = cw:CreateDropdown(autoRow, ddItems, "s",
    function(k) cw:Print("Cogworks", "auto: " .. k) end,
    { autoWidth = true, minWidth = 120, maxWidth = 360 })
  autoDD:SetPoint("LEFT", autoRow, "LEFT", 0, 0)
  local autoLabel = autoRow:CreateFontString(nil, "OVERLAY")
  autoLabel:SetFontObject(cw:GetFont("small"))
  autoLabel:SetPoint("LEFT", autoDD, "RIGHT", 12, 0)
  autoLabel:SetTextColor(unpack(T.textDim))
  autoLabel:SetText("autoWidth (clamped 120 — 360px); refits on font change")
  add(autoRow, function() return 28 end, 24, false)

  -- Subscribe at the page level so font-scale / family changes trigger an
  -- immediate relayout — picks up the new body GetStringHeight values that
  -- each section's heightFn recomputes when called.
  local fontReflowOwner = {}
  cw.RegisterCallback(fontReflowOwner, cw.Events.SettingsChanged, function(_, key)
    if key == "fontScale" or key == "fontFamily" then
      relayoutFormRows()  -- bubbles up into relayout()
    end
  end)
  f._fontReflowOwner = fontReflowOwner

  relayout()
  return f
end

-- ============================================================================
-- Page: Debug toolkit (CreateDebugConsole + logger + inspector + profiler)
-- ============================================================================

pages.debug = function(parent)
  local f = CreateFrame("Frame", nil, parent)
  f:SetAllPoints()

  -- Lazy-create a logger + register a few inspectors/actions on first visit
  -- so the showcase has interesting demo content the moment the user clicks.
  local DEMO_COG = "Cogworks"
  if not f._wired then
    f._wired = true
    cw:RegisterDebugLogger(DEMO_COG, { ringMax = 200 })
    cw:RegisterDebugInspector(DEMO_COG, "Suite roster", function() return cw.SuiteRoster end)
    cw:RegisterDebugInspector(DEMO_COG, "Settings",     function() return cw.settings    end)
    cw:RegisterDebugInspector(DEMO_COG, "Registered addons", function() return cw:GetRegisteredAddons() end)
    cw:RegisterDebugAction(DEMO_COG, "Emit test debug log", function()
      for i = 1, 5 do cw:DebugPrint(DEMO_COG, "test line " .. i) end
    end)
    cw:RegisterDebugAction(DEMO_COG, "Profile a sleep loop", function()
      cw:SetDebugEnabled(DEMO_COG, true)
      for _ = 1, 50 do
        cw:Profile(DEMO_COG, "Math.sqrt-loop", function()
          local s = 0
          for i = 1, 5000 do s = s + math.sqrt(i) end
          return s
        end)
      end
      cw:DebugPrint(DEMO_COG, "Profile sample done — see Profile tab")
    end)
    cw:RegisterDebugAction(DEMO_COG, "Fire a LibDebug bridge event", function()
      cw:_LibDebugPrint("hello from the lib bridge", "Showcase")
    end)
  end

  local intro = f:CreateFontString(nil, "OVERLAY")
  intro:SetFontObject(cw.Fonts.small)
  intro:SetPoint("TOPLEFT",  f, "TOPLEFT",  12, -12)
  intro:SetPoint("RIGHT",    f, "RIGHT",    -12, 0)
  intro:SetJustifyH("LEFT")
  intro:SetWordWrap(true)
  intro:SetTextColor(unpack(T.textDim))
  intro:SetText("Per-cog debug toolkit. Click below to open a CreateDebugConsole instance pointed at the standalone Cogworks logger. "
              .. "Pre-registered actions, inspectors, and a sample profile loop are ready to poke at; the LibDebug bridge demo shows "
              .. "lib-side events landing in the cog's own ring buffer.")

  local openBtn = cw:CreateButton(f, "Open debug console", 200, 28, function()
    if not f._console then
      f._console = cw:CreateDebugConsole({ cog = DEMO_COG })
    end
    if f._console:IsShown() then f._console:Hide() else f._console:Show() end
  end)
  openBtn:SetPoint("TOPLEFT", intro, "BOTTOMLEFT", 0, -16)

  local emitBtn = cw:CreateButton(f, "Emit 1 debug line", 160, 24, function()
    cw:DebugPrint(DEMO_COG, "Showcase emit @ " .. date("%H:%M:%S"))
  end)
  emitBtn:SetPoint("TOPLEFT", openBtn, "BOTTOMLEFT", 0, -8)

  local dumpBtn = cw:CreateButton(f, "Open state dump dialog", 200, 24, function()
    cw:CreateCopyDialog(cw:DumpDebugState(DEMO_COG),
      "Full state dump for " .. DEMO_COG .. "  —  Ctrl+A then Ctrl+C"):Show()
  end)
  dumpBtn:SetPoint("TOPLEFT", emitBtn, "BOTTOMLEFT", 0, -8)

  return f
end

-- ============================================================================
-- Page: ThemedMainFrame demo
-- ============================================================================

pages.mainframe = function(parent)
  local f = CreateFrame("Frame", nil, parent)
  f:SetAllPoints()

  local intro = f:CreateFontString(nil, "OVERLAY")
  intro:SetFontObject(cw.Fonts.small)
  intro:SetPoint("TOPLEFT",  f, "TOPLEFT",  12, -12)
  intro:SetPoint("RIGHT",    f, "RIGHT",    -12, 0)
  intro:SetJustifyH("LEFT")
  intro:SetWordWrap(true)
  intro:SetTextColor(unpack(T.textDim))
  intro:SetText("CreateThemedMainFrame is the one-call main-window chrome. Title bar, optional summary row, sidebar with drag-to-resize handle, "
              .. "content area, resize grip, ESC-to-close, persisted geometry. The button below opens a sample frame with three pre-registered nav items.")

  cw:CreateButton(f, "Open ThemedMainFrame demo", 240, 28, function()
    if not f._demo then
      local demo = cw:CreateThemedMainFrame({
        name          = "CogworksShowcaseDemoFrame",
        title         = "ThemedMainFrame demo",
        versionText   = "v" .. cw.version,
        defaultSize   = { w = 620, h = 420 },
        minSize       = { w = 480, h = 320 },
        sidebar       = { defaultWidth = 130 },
        closeOnEscape = true,
      })
      demo:SetSummary("Sample summary text — frame:SetSummary(text)")
      local function makePage(label, color)
        return function(p)
          local pf = CreateFrame("Frame", nil, p)
          pf:SetAllPoints()
          local fs = pf:CreateFontString(nil, "OVERLAY")
          fs:SetFontObject(cw.Fonts.large)
          fs:SetPoint("CENTER")
          fs:SetText(label)
          fs:SetTextColor(unpack(color))
          return pf
        end
      end
      demo:SetPageBuilder("alpha", makePage("Page Alpha",   T.gold))
      demo:SetPageBuilder("beta",  makePage("Page Beta",    T.arcane))
      demo:SetPageBuilder("gamma", makePage("Page Gamma",   T.success))
      demo:AddNavItem({ key = "alpha", label = "Alpha", icon = "Interface\\Icons\\Spell_Holy_FistOfJustice" })
      demo:AddNavItem({ key = "beta",  label = "Beta",  icon = "Interface\\Icons\\Spell_Frost_FrostBolt02"  })
      demo:AddNavItem({ key = "gamma", label = "Gamma", icon = "Interface\\Icons\\Spell_Nature_LightningBolt" })
      demo:SetActivePage("alpha")
      f._demo = demo
    end
    if f._demo:IsShown() then f._demo:Hide() else f._demo:Show() end
  end):SetPoint("TOPLEFT", intro, "BOTTOMLEFT", 0, -16)

  return f
end

-- ============================================================================
-- Page: Drawer demo
-- ============================================================================

pages.drawer = function(parent)
  local f = CreateFrame("Frame", nil, parent)
  f:SetAllPoints()

  local intro = f:CreateFontString(nil, "OVERLAY")
  intro:SetFontObject(cw.Fonts.small)
  intro:SetPoint("TOPLEFT", f, "TOPLEFT", 12, -12)
  intro:SetPoint("RIGHT",   f, "RIGHT",   -12, 0)
  intro:SetJustifyH("LEFT")
  intro:SetWordWrap(true)
  intro:SetTextColor(unpack(T.textDim))
  intro:SetText("Non-modal floating panel that anchors next to a parent (the showcase, in this demo). Drag the title to move; ESC closes; geometry persists.")

  cw:CreateButton(f, "Toggle drawer", 200, 28, function()
    if not f._drawer then
      f._drawer = cw:CreateDrawer({
        name        = "CogworksShowcaseSampleDrawer",
        title       = "Sample drawer",
        width       = 260,
        height      = 320,
        resizable   = true,
        anchorTo    = showcase,
        anchorPoint = "TOPLEFT",
        anchorRelativePoint = "TOPRIGHT",
        anchorOffset = { x = 6, y = 0 },
      })
      local body = f._drawer.content:CreateFontString(nil, "OVERLAY")
      body:SetFontObject(cw.Fonts.small)
      body:SetPoint("TOPLEFT", 8, -8)
      body:SetPoint("RIGHT", -8, 0)
      body:SetJustifyH("LEFT")
      body:SetWordWrap(true)
      body:SetTextColor(unpack(T.text))
      body:SetText("This is drawer.content. Caller anchors widgets here. The drawer auto-anchors to the showcase frame on Show, and persists position once you drag it.")
    end
    f._drawer:Toggle()
  end):SetPoint("TOPLEFT", intro, "BOTTOMLEFT", 0, -16)

  return f
end

-- ============================================================================
-- Page: Toast demo
-- ============================================================================

pages.toast = function(parent)
  local f = CreateFrame("Frame", nil, parent)
  f:SetAllPoints()

  local intro = f:CreateFontString(nil, "OVERLAY")
  intro:SetFontObject(cw.Fonts.small)
  intro:SetPoint("TOPLEFT", f, "TOPLEFT", 12, -12)
  intro:SetPoint("RIGHT",   f, "RIGHT",   -12, 0)
  intro:SetJustifyH("LEFT")
  intro:SetWordWrap(true)
  intro:SetTextColor(unpack(T.textDim))
  intro:SetText("Click each severity to fire a toast. Multiple firings stack vertically from the top-right of the screen. "
              .. "Hover a toast to pause its auto-dismiss; click anywhere on it to dismiss immediately.")

  local sevs = {
    { label = "Toast: success", severity = "success", text = "Posted 12 items for ~84g",
      icon  = "Interface\\Icons\\INV_Misc_Coin_01" },
    { label = "Toast: info",    severity = "info",    text = "Snapshot saved at 14:02" },
    { label = "Toast: warning", severity = "warning", text = "4 deals expire in <30 minutes",
      icon  = "Interface\\Icons\\INV_Misc_Bell_01" },
    { label = "Toast: error",   severity = "error",   text = "Auction post failed: not enough money",
      icon  = "Interface\\Icons\\Ability_DualWield" },
  }

  local prev = intro
  for i, def in ipairs(sevs) do
    local b = cw:CreateButton(f, def.label, 180, 24, function()
      cw:Toast({ text = def.text, severity = def.severity, icon = def.icon, duration = 4 })
    end)
    b:SetPoint("TOPLEFT", prev, "BOTTOMLEFT", (i == 1) and 0 or 0, (i == 1) and -16 or -6)
    prev = b
  end

  local clearBtn = cw:CreateButton(f, "Clear all toasts", 180, 24, function()
    cw:ClearToasts()
  end)
  clearBtn:SetPoint("TOPLEFT", prev, "BOTTOMLEFT", 0, -16)

  return f
end

-- ============================================================================
-- Page: Slash registry — docs + example
-- ============================================================================

pages.slash = function(parent)
  local f = CreateFrame("Frame", nil, parent)
  f:SetAllPoints()

  local intro = f:CreateFontString(nil, "OVERLAY")
  intro:SetFontObject(cw.Fonts.small)
  intro:SetPoint("TOPLEFT", f, "TOPLEFT", 12, -12)
  intro:SetPoint("RIGHT",   f, "RIGHT",   -12, 0)
  intro:SetJustifyH("LEFT")
  intro:SetWordWrap(true)
  intro:SetTextColor(unpack(T.textDim))
  intro:SetText("RegisterSlashCommands wires SLASH_X1/X2 + SlashCmdList + tokenizing + auto-help. The button below registers a sample "
              .. "/cogdemo command at runtime so you can try it in chat (try /cogdemo, /cogdemo help, /cogdemo greet world).")

  local registered = false
  cw:CreateButton(f, "Register /cogdemo", 200, 28, function()
    if registered then
      cw:Print("Cogworks", "/cogdemo already registered — try it in chat.")
      return
    end
    cw:RegisterSlashCommands("CogworksDemo", {
      globals   = { "/cogdemo" },
      helpStyle = "popup",
      default   = function() cw:Print("Cogworks", "Try /cogdemo help") end,
      commands  = {
        { name = "greet", help = "Print a greeting", args = "<name>",
          run = function(args) cw:Print("Cogworks", "hello, " .. (args ~= "" and args or "world") .. "!") end },
        { name = "toast", help = "Fire a sample toast",
          run = function() cw:Toast({ text = "Triggered by /cogdemo toast", severity = "success" }) end },
      },
    })
    registered = true
    cw:Print("Cogworks", "/cogdemo registered. Try /cogdemo, /cogdemo help, /cogdemo greet world, /cogdemo toast.")
  end):SetPoint("TOPLEFT", intro, "BOTTOMLEFT", 0, -16)

  return f
end

-- ============================================================================
-- Public toggle
-- ============================================================================

function ns:ToggleShowcase()
  if not showcase then
    showcase = createShowcase()
    showcase:Hide()
    showPage("gears")
  end

  if showcase:IsShown() then
    showcase:Hide()
  else
    showcase:Show()
  end
end
