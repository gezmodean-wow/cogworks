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
--
-- Optional edge-reveal animation (COG-38). Pass opts.animate to slide the
-- drawer out from its anchor edge over a short duration:
--
--   cw:CreateDrawer({
--     ...
--     animate = {
--       direction = "right",   -- "right" | "left" | "up" | "down"
--                              -- the axis the drawer slides along; right means
--                              -- it slides rightward into place (typical for
--                              -- a drawer anchored to the right of mainFrame)
--       duration  = 0.15,      -- seconds; default 0.15
--       easing    = "out",     -- "in" | "out" | "inout"; default "out"
--       distance  = 24,        -- px translation distance; default 24
--     },
--   })
--
-- nil opts.animate preserves the original instant-show / instant-hide
-- behavior bit-exact. Toggle / Hide / Show during an in-flight animation
-- reverse cleanly. ESC during a Show animation cancels Show and plays the
-- Hide reverse.

local lib = LibStub("Cogworks-1.0")
if not lib then return end

local MODULE_MINOR = 3
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

  -- ---- Edge-reveal animation (optional; COG-38) ------------------------
  -- When opts.animate is set, Show fades + slides the drawer in from the
  -- chosen direction; Hide reverses then calls the raw Hide. Show/Hide/
  -- Toggle during an in-flight animation reverse cleanly. nil opts.animate
  -- preserves the original instant-show / instant-hide behavior bit-exact.
  if opts.animate then
    local anim = {
      state     = "hidden",                            -- hidden | showing | shown | hiding
      progress  = 0,                                   -- 0..1
      duration  = opts.animate.duration or 0.15,
      direction = opts.animate.direction or "right",
      easing    = opts.animate.easing    or "out",
      distance  = opts.animate.distance  or 24,
    }

    local function ease(t)
      if anim.easing == "in" then
        return t * t
      elseif anim.easing == "inout" then
        if t < 0.5 then return 2 * t * t end
        local u = 1 - t
        return 1 - 2 * u * u
      end
      -- default: "out"
      local u = 1 - t
      return 1 - u * u
    end

    -- Resolve the final (shown) anchor exactly like applyShowAnchor does,
    -- then apply a translation derived from current animation progress.
    local function applyVisual()
      local e = ease(anim.progress)
      f:SetAlpha(e)

      local sv = opts.saveTo
      local point, relTo, relPoint, fx, fy
      if sv and sv.x and sv.y then
        point, relTo, relPoint = "BOTTOMLEFT", UIParent, "BOTTOMLEFT"
        fx, fy = sv.x, sv.y
      elseif opts.anchorTo then
        point    = opts.anchorPoint or "TOPLEFT"
        relTo    = opts.anchorTo
        relPoint = opts.anchorRelativePoint or "TOPRIGHT"
        local aoff = opts.anchorOffset or { x = 4, y = 0 }
        fx, fy = aoff.x or 0, aoff.y or 0
      else
        point, relTo, relPoint = "CENTER", UIParent, "CENTER"
        fx, fy = 0, 0
      end

      local off = (1 - e) * anim.distance
      local dx, dy = 0, 0
      if     anim.direction == "right" then dx = -off  -- start to the left, slide right
      elseif anim.direction == "left"  then dx =  off
      elseif anim.direction == "up"    then dy = -off
      elseif anim.direction == "down"  then dy =  off
      end

      f:ClearAllPoints()
      f:SetPoint(point, relTo, relPoint, fx + dx, fy + dy)
    end

    -- Per-frame ticker driving the state machine.
    local rawHide = f.Hide
    local ticker = CreateFrame("Frame", nil, f)
    ticker:Hide()
    ticker:SetScript("OnUpdate", function(_, elapsed)
      if anim.state == "showing" then
        anim.progress = anim.progress + elapsed / anim.duration
        if anim.progress >= 1 then
          anim.progress = 1
          anim.state    = "shown"
          applyVisual()
          ticker:Hide()
          return
        end
        applyVisual()
      elseif anim.state == "hiding" then
        anim.progress = anim.progress - elapsed / anim.duration
        if anim.progress <= 0 then
          anim.progress = 0
          anim.state    = "hidden"
          applyVisual()
          ticker:Hide()
          rawHide(f)
          return
        end
        applyVisual()
      end
    end)

    -- Hook Show: applyShowAnchor (above) sets the final anchor; we then
    -- override with the hidden-state visual and start the show animation.
    -- Repeat Show calls when already showing / shown are no-ops.
    hooksecurefunc(f, "Show", function()
      if anim.state == "shown" or anim.state == "showing" then return end
      if anim.state == "hiding" then
        -- Mid-flight reversal: keep progress, flip direction.
        anim.state = "showing"
        ticker:Show()
        return
      end
      -- state == "hidden"
      anim.state    = "showing"
      anim.progress = 0
      applyVisual()
      ticker:Show()
    end)

    -- Wrap Hide. UISpecialFrames ESC handling calls f:Hide() directly, so
    -- the wrapper handles the secure dismissal path too.
    function f:Hide(...)
      if anim.state == "hidden" then
        rawHide(self)
        return
      end
      if anim.state == "hiding" then return end
      if anim.state == "showing" then
        anim.state = "hiding"
        ticker:Show()
        return
      end
      -- state == "shown"
      anim.state    = "hiding"
      anim.progress = 1
      ticker:Show()
    end

    -- Toggle uses anim.state so a click during the hiding animation flips
    -- back to showing (IsShown() would still return true during hiding).
    function f:Toggle()
      if anim.state == "shown" or anim.state == "showing" then
        self:Hide()
      else
        self:Show()
      end
    end

    f._anim = anim  -- exposed for tests / introspection
  else
    function f:Toggle()
      if self:IsShown() then self:Hide() else self:Show() end
    end
  end

  -- ---- Public surface --------------------------------------------------
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
