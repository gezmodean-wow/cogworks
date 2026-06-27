-- Cogworks-1.0/ThemedMainFrame.lua | One-call main window chrome.
--
-- The "main window with sidebar" assembly that every cog's UI/MainFrame.lua
-- has hand-rolled until now (FlipQueue alone spent ~300 LOC on it). One
-- factory call gives you:
--
--   * BackdropTemplate frame in the suite palette
--   * Movable + clamped-to-screen + resizable with min/max bounds
--   * Title bar (title + dim version subtitle + close button)
--   * Summary bar (optional one-line status row)
--   * Sidebar with drag-to-resize handle
--   * Content area (caller populates frame.content)
--   * Diagonal-dot resize grip in the bottom-right
--   * ESC-to-close keyboard handler
--   * Persisted geometry into a caller-owned savedvars table
--   * Auto-subscription to SettingsChanged for uiScale (fires SetScale)
--
-- Usage:
--
--   local frame = cw:CreateThemedMainFrame({
--     name          = "FlipQueueMainFrame",      -- required if closeOnEscape
--     title         = "FlipQueue",
--     versionText   = "v" .. ns.VERSION,
--     defaultSize   = { w = 750, h = 550 },
--     minSize       = { w = 720, h = 450 },
--     maxSize       = { w = 1200, h = 900 },
--     saveTo        = ns.db.settings.frame,    -- mutated in place
--     closeOnEscape = true,
--     sidebar       = { defaultWidth = 130, minWidth = 80, maxWidth = 220,
--                       scrollable = true },   -- mouse-wheel nav when it overflows
--   })
--
-- sidebar.scrollable (COG-37): defaults false (nav anchors straight to the
-- sidebar, unchanged). When true the nav stack lives in an internal ScrollFrame
-- whose child grows with the item count, the mouse wheel scrolls it once the
-- stack exceeds the visible sidebar height, and SetActivePage auto-scrolls the
-- active item into view. The drag handle still resizes the sidebar width.
--
-- Note: `closeOnEscape` registers the frame with Blizzard's UISpecialFrames,
-- which requires a globally named frame — pass `opts.name` if you want ESC
-- to close. Nameless frames silently skip the bind. Do NOT roll your own
-- OnKeyDown handler; the EnableKeyboard + SetPropagateKeyboardInput pattern
-- taints the secure ToggleGameMenu path and locks the player out of the
-- game menu (root cause of COG-26 in v0.13.0).
--   frame:SetSummary("23 deals waiting | 4 expiring soon")
--   frame:AddNavItem({ key = "todo",   label = "To-do",   icon = ICONS.todo })
--   frame:AddNavItem({ key = "log",    label = "Log",     icon = ICONS.log  })
--   frame:SetActivePage("todo")
--   -- Caller anchors widgets to frame.content; pages are swapped with
--   -- frame:SetPageBuilder(key, fn) — fn(parent) returns the page frame.
--
-- Pages: callers either build their own page frames inside frame.content
-- and toggle visibility on nav-item click, OR register a builder per nav
-- key via SetPageBuilder; the lib handles lazy construction + swap.

local lib = LibStub("Cogworks-1.0")
if not lib then return end

local MODULE_MINOR = 3
lib._modules = lib._modules or {}
if (lib._modules.ThemedMainFrame or 0) >= MODULE_MINOR then return end
lib._modules.ThemedMainFrame = MODULE_MINOR

local TITLEBAR_H        = 28
local SUMMARY_H         = 20
local NAV_HEADER_GAP    = 8       -- gap between summary bar and first nav button
local NAV_BTN_H         = 32      -- matches CreateNavButton's fixed height
local DEFAULT_SIDEBAR_W = 140
local SIDEBAR_HANDLE_W  = 4

-- ============================================================================
-- Helpers
-- ============================================================================

local function applyResizeBounds(f, minW, minH, maxW, maxH)
  if f.SetResizeBounds then
    f:SetResizeBounds(minW or 1, minH or 1, maxW or 4096, maxH or 4096)
  else
    -- Pre-Dragonflight clients exposed SetMinResize / SetMaxResize separately.
    if f.SetMinResize then f:SetMinResize(minW or 1, minH or 1) end
    if f.SetMaxResize then f:SetMaxResize(maxW or 4096, maxH or 4096) end
  end
end

local function persistGeometry(f, saveTo)
  if not saveTo then return end
  local x, y = f:GetLeft(), f:GetBottom()
  if x and y then saveTo.x, saveTo.y = x, y end
  saveTo.w = f:GetWidth()
  saveTo.h = f:GetHeight()
end

local function restoreGeometry(f, saveTo, defaults)
  local w = (saveTo and saveTo.w) or defaults.w
  local h = (saveTo and saveTo.h) or defaults.h
  f:SetSize(w, h)
  if saveTo and saveTo.x and saveTo.y then
    f:ClearAllPoints()
    f:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", saveTo.x, saveTo.y)
  else
    f:ClearAllPoints()
    f:SetPoint("CENTER")
  end
end

-- ============================================================================
-- CreateThemedMainFrame
-- ============================================================================

function lib:CreateThemedMainFrame(opts)
  opts = opts or {}
  local T = self.Theme
  local title       = opts.title or "Cogworks"
  local versionText = opts.versionText
  local defaults    = opts.defaultSize or { w = 720, h = 480 }
  local minSize     = opts.minSize     or { w = 480, h = 320 }
  local maxSize     = opts.maxSize     or { w = 1600, h = 1000 }
  local sidebarOpts = opts.sidebar     or {}
  local sidebarW    = (opts.saveTo and opts.saveTo.sidebarW)
                   or sidebarOpts.defaultWidth or DEFAULT_SIDEBAR_W
  local sidebarMin  = sidebarOpts.minWidth or 80
  local sidebarMax  = sidebarOpts.maxWidth or 280
  local scrollable  = sidebarOpts.scrollable
  local saveTo      = opts.saveTo

  -- ---- Outer frame ------------------------------------------------------
  local f = CreateFrame("Frame", opts.name, UIParent, "BackdropTemplate")
  f:SetBackdrop(self.Backdrop)
  f:SetBackdropColor(unpack(T.bg))
  f:SetBackdropBorderColor(unpack(T.border))
  f:SetFrameStrata(opts.strata or "DIALOG")
  f:SetClampedToScreen(true)
  f:SetMovable(true); f:EnableMouse(true)
  f:SetResizable(true)
  applyResizeBounds(f, minSize.w, minSize.h, maxSize.w, maxSize.h)
  restoreGeometry(f, saveTo, defaults)
  f:Hide()

  -- ---- Title bar --------------------------------------------------------
  local titleBar = CreateFrame("Frame", nil, f)
  titleBar:SetHeight(TITLEBAR_H)
  titleBar:SetPoint("TOPLEFT",  f, "TOPLEFT",  4, -4)
  titleBar:SetPoint("TOPRIGHT", f, "TOPRIGHT", -4, -4)
  titleBar:EnableMouse(true); titleBar:RegisterForDrag("LeftButton")
  titleBar:SetScript("OnDragStart", function() f:StartMoving() end)
  titleBar:SetScript("OnDragStop",  function()
    f:StopMovingOrSizing()
    persistGeometry(f, saveTo)
  end)

  local titleBg = titleBar:CreateTexture(nil, "BACKGROUND")
  titleBg:SetAllPoints()
  titleBg:SetColorTexture(unpack(T.header))

  local titleFs = titleBar:CreateFontString(nil, "OVERLAY")
  titleFs:SetFontObject(self:GetFont("normal"))
  titleFs:SetPoint("LEFT", titleBar, "LEFT", 10, 0)
  titleFs:SetText(title)
  titleFs:SetTextColor(unpack(T.gold))

  local versionFs
  if versionText and versionText ~= "" then
    versionFs = titleBar:CreateFontString(nil, "OVERLAY")
    versionFs:SetFontObject(self:GetFont("small"))
    versionFs:SetPoint("LEFT", titleFs, "RIGHT", 6, -1)
    versionFs:SetText(versionText)
    versionFs:SetTextColor(unpack(T.textDim))
  end

  local closeBtn = CreateFrame("Button", nil, titleBar, "UIPanelCloseButton")
  closeBtn:SetSize(22, 22)
  closeBtn:SetPoint("RIGHT", titleBar, "RIGHT", -2, 0)
  closeBtn:SetScript("OnClick", function() f:Hide() end)

  -- ---- Summary bar (optional) -------------------------------------------
  local summaryBar = CreateFrame("Frame", nil, f)
  summaryBar:SetHeight(SUMMARY_H)
  summaryBar:SetPoint("TOPLEFT",  titleBar, "BOTTOMLEFT",  0, -2)
  summaryBar:SetPoint("TOPRIGHT", titleBar, "BOTTOMRIGHT", 0, -2)
  summaryBar:Hide()

  local summaryFs = summaryBar:CreateFontString(nil, "OVERLAY")
  summaryFs:SetFontObject(self:GetFont("small"))
  summaryFs:SetPoint("LEFT",  summaryBar, "LEFT",  10, 0)
  summaryFs:SetPoint("RIGHT", summaryBar, "RIGHT", -10, 0)
  summaryFs:SetJustifyH("LEFT")
  summaryFs:SetTextColor(unpack(T.textDim))

  -- ---- Sidebar ----------------------------------------------------------
  local sidebar = CreateFrame("Frame", nil, f)
  sidebar:SetWidth(sidebarW)
  -- Top of sidebar tracks summary bar visibility (re-anchored in
  -- _refreshSummaryAnchors below).
  sidebar:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 4, 4)

  local sidebarBg = sidebar:CreateTexture(nil, "BACKGROUND")
  sidebarBg:SetAllPoints()
  sidebarBg:SetColorTexture(unpack(T.sidebar))

  local sidebarEdge = sidebar:CreateTexture(nil, "ARTWORK")
  sidebarEdge:SetWidth(1)
  sidebarEdge:SetPoint("TOPRIGHT",    sidebar, "TOPRIGHT",    0, 0)
  sidebarEdge:SetPoint("BOTTOMRIGHT", sidebar, "BOTTOMRIGHT", 0, 0)
  sidebarEdge:SetColorTexture(unpack(T.border))

  -- Sidebar drag handle (resize-by-drag on the edge)
  local handle = CreateFrame("Button", nil, sidebar)
  handle:SetWidth(SIDEBAR_HANDLE_W)
  handle:SetPoint("TOPRIGHT",    sidebar, "TOPRIGHT",    0, 0)
  handle:SetPoint("BOTTOMRIGHT", sidebar, "BOTTOMRIGHT", 0, 0)
  handle:RegisterForDrag("LeftButton")
  handle:EnableMouse(true)

  -- Hover hint
  local handleTex = handle:CreateTexture(nil, "OVERLAY")
  handleTex:SetAllPoints()
  handleTex:SetColorTexture(T.gold[1], T.gold[2], T.gold[3], 0)
  handle:SetScript("OnEnter", function() handleTex:SetColorTexture(T.gold[1], T.gold[2], T.gold[3], 0.4) end)
  handle:SetScript("OnLeave", function() handleTex:SetColorTexture(T.gold[1], T.gold[2], T.gold[3], 0)   end)

  local dragging = false
  handle:SetScript("OnMouseDown", function() dragging = true end)
  handle:SetScript("OnMouseUp",   function()
    dragging = false
    sidebarW = sidebar:GetWidth()
    if saveTo then saveTo.sidebarW = sidebarW end
  end)
  handle:SetScript("OnUpdate", function()
    if not dragging then return end
    local cursorX = GetCursorPosition() / sidebar:GetEffectiveScale()
    local left    = sidebar:GetLeft() or 0
    local newW    = math.max(sidebarMin, math.min(sidebarMax, cursorX - left))
    sidebar:SetWidth(newW)
  end)

  -- ---- Content area -----------------------------------------------------
  local content = CreateFrame("Frame", nil, f)
  content:SetPoint("TOPLEFT",     sidebar, "TOPRIGHT",  1, 0)
  content:SetPoint("BOTTOMRIGHT", f,       "BOTTOMRIGHT", -4, 4)

  -- ---- Resize grip ------------------------------------------------------
  local grip = CreateFrame("Button", nil, f)
  grip:SetSize(16, 16)
  grip:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -4, 4)
  grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
  grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
  grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
  grip:RegisterForDrag("LeftButton")
  grip:SetScript("OnDragStart", function() f:StartSizing("BOTTOMRIGHT") end)
  grip:SetScript("OnDragStop",  function()
    f:StopMovingOrSizing()
    persistGeometry(f, saveTo)
  end)

  -- ---- ESC handler ------------------------------------------------------
  -- Use UISpecialFrames, NOT EnableKeyboard + SetPropagateKeyboardInput.
  -- The latter pattern taints Blizzard's ToggleGameMenu path: pressing ESC
  -- with a tainted handler in the chain blocks the secure ClearTarget call
  -- inside UIParent.lua, which surfaces as ADDON_ACTION_FORBIDDEN and locks
  -- the player out of the game menu / logout. UISpecialFrames is Blizzard's
  -- supported escape-to-close mechanism — frame must be globally named.
  if opts.closeOnEscape ~= false and opts.name then
    tinsert(UISpecialFrames, opts.name)
  end

  -- ---- uiScale subscription --------------------------------------------
  f:SetScale(self:GetSetting("uiScale") or 1.0)
  local owner = {}
  self.RegisterCallback(owner, self.Events.SettingsChanged, function(_, key, value)
    if key == "uiScale" then
      f:SetScale(value or 1.0)
    end
  end)
  f._scaleOwner = owner

  -- ============================================================================
  -- Nav management
  -- ============================================================================
  -- Each registered item gets a CreateNavButton stacked beneath the previous.
  -- Caller can either toggle their own page frames in OnClick, or pre-register
  -- builders via SetPageBuilder.

  local navItems   = {}        -- ordered list of { key, btn, def }
  local navByKey   = {}        -- key → entry
  local pages      = {}        -- key → page frame (lazy)
  local builders   = {}        -- key → fn(parent) → frame
  local activeKey

  -- Nav host. Default: nav buttons anchor straight to the sidebar (unchanged).
  -- Scrollable: buttons live inside a clipping ScrollFrame whose child grows
  -- with the item count, so overflow scrolls instead of running off-screen.
  local navHost = sidebar
  local navScroll
  if scrollable then
    navScroll = CreateFrame("ScrollFrame", nil, sidebar)
    navScroll:SetPoint("TOPLEFT",     sidebar, "TOPLEFT",     0, 0)
    navScroll:SetPoint("BOTTOMRIGHT", sidebar, "BOTTOMRIGHT", -1, 0)
    navScroll:EnableMouseWheel(true)   -- wheel only; no EnableMouse, so clicks
                                       -- pass through to nav buttons + handle
    local navContent = CreateFrame("Frame", nil, navScroll)
    navContent:SetSize(sidebarW, 1)
    navScroll:SetScrollChild(navContent)
    navScroll:SetScript("OnMouseWheel", function(sf, delta)
      local range = math.max(0, navContent:GetHeight() - sf:GetHeight())
      local cur   = sf:GetVerticalScroll()
      sf:SetVerticalScroll(math.max(0, math.min(range, cur - delta * NAV_BTN_H)))
    end)
    navScroll:SetScript("OnSizeChanged", function(_, w) navContent:SetWidth(w) end)
    navHost     = navContent
    f._navScroll = navScroll
  end

  local function relayoutNav()
    local y = 0
    for _, entry in ipairs(navItems) do
      entry.btn:ClearAllPoints()
      entry.btn:SetPoint("TOPLEFT",  navHost, "TOPLEFT",  0, -y)
      entry.btn:SetPoint("RIGHT",    navHost, "RIGHT",    -1, 0)
      y = y + NAV_BTN_H
    end
    if scrollable then
      navHost:SetWidth(navScroll:GetWidth())
      navHost:SetHeight(math.max(y, 1))
    end
  end

  -- Scroll the active nav item into the visible viewport (scrollable only).
  local function scrollNavIntoView(key)
    if not scrollable then return end
    local idx
    for i, e in ipairs(navItems) do if e.key == key then idx = i; break end end
    if not idx then return end
    local top    = (idx - 1) * NAV_BTN_H
    local bottom = top + NAV_BTN_H
    local viewH  = navScroll:GetHeight()
    local cur    = navScroll:GetVerticalScroll()
    if top < cur then
      cur = top
    elseif bottom > cur + viewH then
      cur = bottom - viewH
    end
    local range = math.max(0, navHost:GetHeight() - viewH)
    navScroll:SetVerticalScroll(math.max(0, math.min(range, cur)))
  end

  local function showPage(key)
    if activeKey == key then scrollNavIntoView(key); return end
    -- Hide previous
    if activeKey then
      local prev = navByKey[activeKey]
      if prev then lib:SetNavButtonActive(prev.btn, false) end
      if pages[activeKey] then pages[activeKey]:Hide() end
    end
    -- Lazy-build via registered builder
    if not pages[key] and builders[key] then
      pages[key] = builders[key](content)
    end
    if pages[key] then pages[key]:Show() end
    if navByKey[key] then lib:SetNavButtonActive(navByKey[key].btn, true) end
    activeKey = key
    scrollNavIntoView(key)
  end

  function f:AddNavItem(item)
    assert(type(item) == "table" and item.key,
      "ThemedMainFrame:AddNavItem requires { key, label, ... }")
    if navByKey[item.key] then return navByKey[item.key].btn end

    local btn = lib:CreateNavButton(navHost, item, function()
      showPage(item.key)
      if item.onClick then item.onClick() end
    end)
    local entry = { key = item.key, btn = btn, def = item }
    navItems[#navItems + 1] = entry
    navByKey[item.key]      = entry
    relayoutNav()
    return btn
  end

  function f:RemoveNavItem(key)
    local entry = navByKey[key]
    if not entry then return false end
    entry.btn:Hide(); entry.btn:SetParent(nil)
    navByKey[key] = nil
    if pages[key] then pages[key]:Hide(); pages[key] = nil end
    for i, e in ipairs(navItems) do
      if e.key == key then table.remove(navItems, i); break end
    end
    if activeKey == key then activeKey = nil end
    relayoutNav()
    return true
  end

  function f:SetPageBuilder(key, fn)
    assert(type(fn) == "function", "SetPageBuilder requires a function")
    builders[key] = fn
  end

  function f:SetActivePage(key) showPage(key) end
  function f:GetActivePage()    return activeKey end
  function f:GetNavItems()      return navItems end

  function f:SetSummary(text)
    if not text or text == "" then
      summaryBar:Hide()
      summaryFs:SetText("")
    else
      summaryFs:SetText(text)
      summaryBar:Show()
    end
    -- Re-anchor sidebar top to whichever bar is visible.
    sidebar:ClearAllPoints()
    sidebar:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 4, 4)
    if summaryBar:IsShown() then
      sidebar:SetPoint("TOPLEFT", summaryBar, "BOTTOMLEFT", 0, -NAV_HEADER_GAP)
    else
      sidebar:SetPoint("TOPLEFT", titleBar, "BOTTOMLEFT", 0, -NAV_HEADER_GAP)
    end
  end

  function f:GetSummary() return summaryFs:GetText() end

  -- Initial sidebar anchor (no summary by default).
  sidebar:SetPoint("TOPLEFT", titleBar, "BOTTOMLEFT", 0, -NAV_HEADER_GAP)

  -- ---- Public surface ---------------------------------------------------
  f.titleBar   = titleBar
  f.summaryBar = summaryBar
  f.sidebar    = sidebar
  f.content    = content
  f.closeBtn   = closeBtn
  f.resizeGrip = grip

  return f
end
