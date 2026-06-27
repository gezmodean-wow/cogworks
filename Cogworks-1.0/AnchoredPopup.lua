-- Cogworks-1.0/AnchoredPopup.lua | Anchored, non-modal action popup. (COG-50)
--
-- The shape FlipQueue's BankPopup needed and none of the existing primitives
-- fit: a panel that sits *next to* another frame (the mini view / a drawer)
-- while the player keeps interacting with bags, bank, and character. Unlike
-- cw:CreatePopup it is NOT modal — no fullscreen dim, no centered placement,
-- no ESC-grab. Unlike cw:CreateDrawer it has no slide animation model; it just
-- pins itself relative to an anchor frame and optionally carries a smoothed
-- progress strip and a single-button footer band.
--
-- Usage:
--
--   local pop = cw:CreateAnchoredPopup({
--     title    = "Bank run",
--     width    = 280, height = 200,
--     anchorTo = mini, anchorMode = "right", gap = 6,   -- above | below | left | right
--     progress = { heartbeat = true, smoothing = 0.15 },-- optional progress strip
--     footer   = { button = { text = "Execute", onClick = function() ... end } },
--   })
--   -- caller populates pop.content
--   pop:SetProgress(0.4)                 -- main bar lerps smoothly toward 0.4
--   pop:SetProgressText("12 / 30")
--   pop:Heartbeat(1.5)                   -- sub-bar counts 1.5s -> 0 (inter-step wait)
--   pop:Show()
--   pop:SetAnchor(drawer, "below")       -- re-pin to a different frame / edge
--
-- The footer button is exposed as pop.footerButton; the progress strip's bars
-- as pop.progressBar / pop.heartbeatBar for callers that want direct access.

local lib = LibStub("Cogworks-1.0")
if not lib then return end

-- Module load guard. See Sections.lua for rationale.
local MODULE_MINOR = 1
lib._modules = lib._modules or {}
if (lib._modules.AnchoredPopup or 0) >= MODULE_MINOR then return end
lib._modules.AnchoredPopup = MODULE_MINOR

local TITLE_H    = 28
local MAIN_BAR_H = 16
local HB_BAR_H   = 10
local FOOTER_H   = 38
local PAD        = 6
local BAR_TEX    = "Interface\\TargetingFrame\\UI-StatusBar"

-- Re-pin the popup relative to its anchor frame for one of four edges. Kept as
-- a free function so SetAnchor / Reanchor share it.
local function applyAnchor(f, anchorTo, mode, gap)
  if not anchorTo then return end
  f:ClearAllPoints()
  gap = gap or 6
  if mode == "above" then
    f:SetPoint("BOTTOMLEFT", anchorTo, "TOPLEFT", 0, gap)
  elseif mode == "left" then
    f:SetPoint("TOPRIGHT", anchorTo, "TOPLEFT", -gap, 0)
  elseif mode == "right" then
    f:SetPoint("TOPLEFT", anchorTo, "TOPRIGHT", gap, 0)
  else -- "below" (default)
    f:SetPoint("TOPLEFT", anchorTo, "BOTTOMLEFT", 0, -gap)
  end
end

function lib:CreateAnchoredPopup(opts)
  opts = opts or {}
  local T = self.Theme
  local w = opts.width  or 280
  local h = opts.height or 200

  -- ---- Frame (non-modal; no overlay, no dim) ----------------------------
  local f = CreateFrame("Frame", opts.name, opts.parent or UIParent, "BackdropTemplate")
  f:SetSize(w, h)
  f:SetFrameStrata(opts.strata or "HIGH")
  f:SetBackdrop(self.Backdrop)
  f:SetBackdropColor(unpack(T.bg))
  f:SetBackdropBorderColor(unpack(T.border))
  f:SetClampedToScreen(true)
  f:Hide()

  f._anchorTo   = opts.anchorTo
  f._anchorMode = opts.anchorMode or "below"
  f._anchorGap  = opts.gap or 6
  applyAnchor(f, f._anchorTo, f._anchorMode, f._anchorGap)
  -- Fallback placement when no anchor was supplied.
  if not f._anchorTo then f:SetPoint("CENTER") end

  -- ---- Title bar (same chrome as CreatePopup, minus the dim) -------------
  local titleBar = CreateFrame("Frame", nil, f)
  titleBar:SetHeight(TITLE_H)
  titleBar:SetPoint("TOPLEFT"); titleBar:SetPoint("TOPRIGHT")
  titleBar:EnableMouse(true)
  titleBar:RegisterForDrag("LeftButton")
  if opts.movable ~= false then
    f:SetMovable(true)
    titleBar:SetScript("OnDragStart", function() f:StartMoving() end)
    titleBar:SetScript("OnDragStop",  function() f:StopMovingOrSizing() end)
  end

  local titleBg = titleBar:CreateTexture(nil, "BACKGROUND")
  titleBg:SetAllPoints()
  titleBg:SetColorTexture(unpack(T.header))

  local titleText = titleBar:CreateFontString(nil, "OVERLAY")
  titleText:SetFontObject(self:GetFont("normal") or "GameFontNormal")
  titleText:SetPoint("LEFT", titleBar, "LEFT", 10, 0)
  titleText:SetText(opts.title or "")
  titleText:SetTextColor(unpack(T.gold))

  if opts.closeButton ~= false then
    local closeBtn = self:CreateIconButton(titleBar,
      "Interface\\Buttons\\UI-Panel-MinimizeButton-Up", 18, "Close",
      function() f:Hide() end)
    closeBtn:SetPoint("RIGHT", titleBar, "RIGHT", -4, 0)
    f.closeButton = closeBtn
  end

  -- bottomAnchor walks up from the frame bottom as optional bands are added,
  -- so the content area always fills the gap between the title bar and the
  -- topmost band.
  local bottomAnchor = f
  local bottomPoint, bottomXOff, bottomYOff = "BOTTOM", 0, PAD

  -- ---- Footer band (optional) -------------------------------------------
  if opts.footer then
    local footer = CreateFrame("Frame", nil, f)
    footer:SetHeight(FOOTER_H)
    footer:SetPoint("BOTTOMLEFT",  f, "BOTTOMLEFT",  PAD, PAD)
    footer:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -PAD, PAD)

    local sep = footer:CreateTexture(nil, "ARTWORK")
    sep:SetHeight(1)
    sep:SetPoint("TOPLEFT",  footer, "TOPLEFT",  0, 0)
    sep:SetPoint("TOPRIGHT", footer, "TOPRIGHT", 0, 0)
    sep:SetColorTexture(T.border[1], T.border[2], T.border[3], 1)

    local btnOpts = opts.footer.button
    if btnOpts then
      local btn = self:CreateButton(footer, btnOpts.text or "OK",
        btnOpts.width or 120, btnOpts.height or 24, btnOpts.onClick)
      btn:SetPoint("BOTTOM", footer, "BOTTOM", 0, 4)
      f.footerButton = btn
    end

    f.footer = footer
    bottomAnchor, bottomPoint, bottomXOff, bottomYOff = footer, "TOP", 0, PAD
  end

  -- ---- Progress strip (optional) ----------------------------------------
  if opts.progress then
    local prog = opts.progress
    local hasHeartbeat = prog.heartbeat
    local stripH = MAIN_BAR_H + (hasHeartbeat and (HB_BAR_H + PAD) or 0) + PAD

    local strip = CreateFrame("Frame", nil, f)
    strip:SetHeight(stripH)
    strip:SetPoint("LEFT",  f, "LEFT",  PAD, 0)
    strip:SetPoint("RIGHT", f, "RIGHT", -PAD, 0)
    strip:SetPoint("BOTTOM", bottomAnchor, bottomPoint, bottomXOff, bottomYOff)

    -- Main bar + overlaid text.
    local bar = CreateFrame("StatusBar", nil, strip)
    bar:SetHeight(MAIN_BAR_H)
    bar:SetPoint("TOPLEFT",  strip, "TOPLEFT",  0, 0)
    bar:SetPoint("TOPRIGHT", strip, "TOPRIGHT", 0, 0)
    bar:SetStatusBarTexture(BAR_TEX)
    bar:SetStatusBarColor(unpack(T.brass))
    bar:SetMinMaxValues(0, 1)
    bar:SetValue(0)
    local barBg = bar:CreateTexture(nil, "BACKGROUND")
    barBg:SetAllPoints()
    barBg:SetColorTexture(T.bgDark[1], T.bgDark[2], T.bgDark[3], 0.85)
    local barText = bar:CreateFontString(nil, "OVERLAY")
    barText:SetFontObject(self:GetFont("small") or "GameFontHighlightSmall")
    barText:SetPoint("CENTER")
    barText:SetTextColor(unpack(T.text))
    f.progressBar = bar

    -- Frame-rate-independent exponential smoothing toward the target value.
    local tau = prog.smoothing or 0.15
    local display, target = 0, 0
    bar:SetScript("OnUpdate", function(_, dt)
      if math.abs(display - target) < 0.001 then
        if display ~= target then display = target; bar:SetValue(display) end
        return
      end
      local a = (tau > 0) and (1 - math.exp(-dt / tau)) or 1
      display = display + (target - display) * a
      bar:SetValue(display)
    end)

    function f:SetProgress(v)
      target = math.max(0, math.min(1, v or 0))
    end
    function f:SetProgressText(text) barText:SetText(text or "") end

    -- Heartbeat sub-bar: a self-counting countdown for the inter-step waits
    -- (the BAG_UPDATE_DELAYED gaps between ticks). Heartbeat(duration) starts
    -- it; it drains to zero on its own and shows remaining seconds.
    if hasHeartbeat then
      local hb = CreateFrame("StatusBar", nil, strip)
      hb:SetHeight(HB_BAR_H)
      hb:SetPoint("BOTTOMLEFT",  strip, "BOTTOMLEFT",  0, 0)
      hb:SetPoint("BOTTOMRIGHT", strip, "BOTTOMRIGHT", 0, 0)
      hb:SetStatusBarTexture(BAR_TEX)
      hb:SetStatusBarColor(unpack(T.gold))
      hb:SetMinMaxValues(0, 1)
      hb:SetValue(0)
      local hbBg = hb:CreateTexture(nil, "BACKGROUND")
      hbBg:SetAllPoints()
      hbBg:SetColorTexture(T.bgDark[1], T.bgDark[2], T.bgDark[3], 0.85)
      local hbText = hb:CreateFontString(nil, "OVERLAY")
      hbText:SetFontObject(self:GetFont("small") or "GameFontHighlightSmall")
      hbText:SetPoint("CENTER")
      hbText:SetTextColor(unpack(T.textDim))
      f.heartbeatBar = hb

      local hbRemaining, hbTotal, hbActive = 0, 1, false
      hb:SetScript("OnUpdate", function(_, dt)
        if not hbActive then return end
        hbRemaining = hbRemaining - dt
        if hbRemaining <= 0 then
          hbRemaining, hbActive = 0, false
          hb:SetValue(0)
          hbText:SetText("")
          return
        end
        hb:SetValue(hbRemaining / hbTotal)
        hbText:SetText(string.format("%.1fs", hbRemaining))
      end)

      function f:Heartbeat(duration)
        hbTotal     = (duration and duration > 0) and duration or 1
        hbRemaining = hbTotal
        hbActive    = true
      end
      function f:StopHeartbeat()
        hbActive = false
        hb:SetValue(0)
        hbText:SetText("")
      end
    end

    f.progressStrip = strip
    bottomAnchor, bottomPoint, bottomXOff, bottomYOff = strip, "TOP", 0, PAD
  end

  -- No-op stubs so callers can call these unconditionally even when they
  -- didn't request a progress strip.
  f.SetProgress     = f.SetProgress     or function() end
  f.SetProgressText = f.SetProgressText or function() end
  f.Heartbeat       = f.Heartbeat       or function() end
  f.StopHeartbeat   = f.StopHeartbeat   or function() end

  -- ---- Content area (fills the gap between title and topmost band) -------
  local content = CreateFrame("Frame", nil, f)
  content:SetPoint("TOPLEFT", titleBar, "BOTTOMLEFT", PAD, -PAD)
  if bottomAnchor == f then
    content:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -PAD, PAD)
  else
    -- bands (footer / progress strip) are inset PAD and anchored by their TOP,
    -- so the content's bottom-right aligns to the band's top-right with a gap.
    content:SetPoint("BOTTOMRIGHT", bottomAnchor, "TOPRIGHT", 0, PAD)
  end
  f.content = content

  -- ---- Anchor management ------------------------------------------------
  function f:SetAnchor(anchorTo, mode, gap)
    self._anchorTo   = anchorTo or self._anchorTo
    self._anchorMode = mode or self._anchorMode
    if gap ~= nil then self._anchorGap = gap end
    applyAnchor(self, self._anchorTo, self._anchorMode, self._anchorGap)
  end
  function f:Reanchor()
    applyAnchor(self, self._anchorTo, self._anchorMode, self._anchorGap)
  end

  f.titleText = titleText
  return f
end
