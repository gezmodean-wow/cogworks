-- Cogworks-1.0/Drawer.lua | Non-modal floating panel.
--
-- The popup-shaped-but-not-modal cousin of cw:CreatePopup. Drawers float
-- next to a main window (tool drawers, context drawers, side popups);
-- caller can drag, optionally resize, and dismiss with ESC. Geometry
-- persists into a caller-owned savedvars table.
--
-- Distinct from:
--   * CreatePopup  — modal, FULLSCREEN_DIALOG strata, dim overlay
--   * CreateMiniView — heads-up display, no main-frame coupling, minimap-style chrome
--
-- Usage:
--
--   local drawer = cw:CreateDrawer({
--     name          = "FlipQueueToolDrawer",  -- required if closeOnEscape
--     title         = "Tool drawer",
--     width         = 280,
--     height        = 480,
--     resizable     = true,
--     minSize       = { w = 240, h = 320 },
--     maxSize       = { w = 600, h = 900 },
--     anchorTo      = mainFrame,
--     anchorPoint   = "TOPLEFT",            -- self point
--     anchorRelativePoint = "TOPRIGHT",     -- relative point on anchorTo
--     anchorOffset  = { x = 4, y = 0 },
--     closeOnEscape = true,
--     saveTo        = ns.db.settings.toolDrawer,
--   })
--
-- ESC support uses Blizzard's UISpecialFrames and requires `opts.name`.
-- Nameless drawers silently skip the bind. See ThemedMainFrame.lua for why
-- a custom OnKeyDown is forbidden (COG-26 — secure-path taint).
--   drawer.content       -- frame for caller widgets
--   drawer:Show() / Hide() / Toggle()
--   drawer:SetTitle("New title")
--   drawer:SetOnClose(function() ... end)

local lib = LibStub("Cogworks-1.0")
if not lib then return end

local MODULE_MINOR = 2
lib._modules = lib._modules or {}
if (lib._modules.Drawer or 0) >= MODULE_MINOR then return end
lib._modules.Drawer = MODULE_MINOR

local TITLEBAR_H = 24
local GRIP_SIZE  = 14

local function applyResizeBounds(f, minW, minH, maxW, maxH)
  if f.SetResizeBounds then
    f:SetResizeBounds(minW or 1, minH or 1, maxW or 4096, maxH or 4096)
  else
    if f.SetMinResize then f:SetMinResize(minW or 1, minH or 1) end
    if f.SetMaxResize then f:SetMaxResize(maxW or 4096, maxH or 4096) end
  end
end

function lib:CreateDrawer(opts)
  opts = opts or {}
  local T = self.Theme

  local defW = opts.width  or 280
  local defH = opts.height or 360
  local minSize = opts.minSize or { w = 200, h = 160 }
  local maxSize = opts.maxSize or { w = 1200, h = 900 }

  local f = CreateFrame("Frame", opts.name, UIParent, "BackdropTemplate")
  f:SetSize((opts.saveTo and opts.saveTo.w) or defW,
            (opts.saveTo and opts.saveTo.h) or defH)
  f:SetBackdrop(self.Backdrop)
  f:SetBackdropColor(unpack(T.bg))
  f:SetBackdropBorderColor(unpack(T.border))
  f:SetFrameStrata(opts.strata or "DIALOG")
  f:SetClampedToScreen(true)
  f:SetMovable(true); f:EnableMouse(true)
  if opts.resizable then
    f:SetResizable(true)
    applyResizeBounds(f, minSize.w, minSize.h, maxSize.w, maxSize.h)
  end
  f:Hide()

  -- ---- Title bar -------------------------------------------------------
  local titleBar = CreateFrame("Frame", nil, f)
  titleBar:SetHeight(TITLEBAR_H)
  titleBar:SetPoint("TOPLEFT",  4, -4)
  titleBar:SetPoint("TOPRIGHT", -4, -4)
  titleBar:EnableMouse(true)
  titleBar:RegisterForDrag("LeftButton")
  titleBar:SetScript("OnDragStart", function() f:StartMoving() end)
  titleBar:SetScript("OnDragStop", function()
    f:StopMovingOrSizing()
    if opts.saveTo then
      opts.saveTo.x, opts.saveTo.y = f:GetLeft(), f:GetBottom()
    end
  end)

  local titleBg = titleBar:CreateTexture(nil, "BACKGROUND")
  titleBg:SetAllPoints(); titleBg:SetColorTexture(unpack(T.header))

  local titleFs = titleBar:CreateFontString(nil, "OVERLAY")
  titleFs:SetFontObject(self:GetFont("normal"))
  titleFs:SetPoint("LEFT", 8, 0)
  titleFs:SetTextColor(unpack(T.gold))
  titleFs:SetText(opts.title or "")

  local closeBtn = CreateFrame("Button", nil, titleBar, "UIPanelCloseButton")
  closeBtn:SetSize(20, 20); closeBtn:SetPoint("RIGHT", -2, 0)
  local onCloseCb
  closeBtn:SetScript("OnClick", function()
    f:Hide()
    if onCloseCb then onCloseCb() end
  end)

  -- ---- Content ---------------------------------------------------------
  local content = CreateFrame("Frame", nil, f)
  content:SetPoint("TOPLEFT",     titleBar, "BOTTOMLEFT",  0, -2)
  content:SetPoint("BOTTOMRIGHT", f,        "BOTTOMRIGHT", -4, 4)
  f.content = content

  -- ---- Resize grip (optional) -----------------------------------------
  if opts.resizable then
    local grip = CreateFrame("Button", nil, f)
    grip:SetSize(GRIP_SIZE, GRIP_SIZE)
    grip:SetPoint("BOTTOMRIGHT", -4, 4)
    grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
    grip:RegisterForDrag("LeftButton")
    grip:SetScript("OnDragStart", function() f:StartSizing("BOTTOMRIGHT") end)
    grip:SetScript("OnDragStop", function()
      f:StopMovingOrSizing()
      if opts.saveTo then
        opts.saveTo.w = f:GetWidth()
        opts.saveTo.h = f:GetHeight()
      end
    end)
  end

  -- ---- ESC handler -----------------------------------------------------
  -- See ThemedMainFrame.lua for why we use UISpecialFrames instead of
  -- EnableKeyboard + SetPropagateKeyboardInput. ESC support requires a
  -- globally named frame; callers without opts.name silently skip the bind.
  if opts.closeOnEscape ~= false and opts.name then
    tinsert(UISpecialFrames, opts.name)
  end

  -- ---- Anchor / show wiring -------------------------------------------
  local function applyShowAnchor()
    -- Persisted position wins. Otherwise anchor to opts.anchorTo if given;
    -- otherwise center on screen.
    local sv = opts.saveTo
    if sv and sv.x and sv.y then
      f:ClearAllPoints()
      f:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", sv.x, sv.y)
    elseif opts.anchorTo then
      f:ClearAllPoints()
      local off = opts.anchorOffset or { x = 4, y = 0 }
      f:SetPoint(opts.anchorPoint or "TOPLEFT",
                 opts.anchorTo,
                 opts.anchorRelativePoint or "TOPRIGHT",
                 off.x or 0, off.y or 0)
    else
      f:ClearAllPoints()
      f:SetPoint("CENTER")
    end
  end

  hooksecurefunc(f, "Show", applyShowAnchor)
  applyShowAnchor()  -- initial

  -- ---- Public surface --------------------------------------------------
  function f:Toggle()
    if self:IsShown() then self:Hide() else self:Show() end
  end
  function f:SetTitle(text)   titleFs:SetText(text or "") end
  function f:GetTitle()       return titleFs:GetText() end
  function f:SetOnClose(fn)   onCloseCb = fn end
  function f:SetAnchorTo(target, point, relPoint, offset)
    opts.anchorTo            = target
    opts.anchorPoint         = point
    opts.anchorRelativePoint = relPoint
    opts.anchorOffset        = offset
    if self:IsShown() then applyShowAnchor() end
  end

  f.titleBar = titleBar
  f.closeBtn = closeBtn
  return f
end
