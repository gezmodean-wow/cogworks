-- Cogworks-1.0/Stepper.lua | Queue-based one-at-a-time walkthrough primitive.
--
-- Wizard's sibling. Where Wizard advances a fixed N-step linear flow with a
-- validation gate and Previous/Next/Finish/Cancel chrome, Stepper walks an
-- unknown-length queue of items where the player takes a caller-defined
-- action on each item, with skip-and-keep-going semantics. The queue can
-- grow mid-traversal (FlipQueue #160 batches failed posts as the player
-- macro-spins), and Cancel returns the intact remaining queue so the caller
-- can stash it and re-show later.
--
-- Distinct from Wizard:
--   * Footer buttons are caller-defined (any actions, any labels).
--   * No per-step validate gate; the action buttons are always enabled and
--     the caller does whatever per-item check they want inside onAction.
--   * Queue is dynamic (Push during traversal), index counts visits.
--   * Skip records the item in history with action="skip" so Back can
--     revisit it.
--
-- Usage:
--
--   local stepper = cw:CreateStepper(parent, {
--     items       = { ... },                       -- initial queue
--     title       = "Repost failed listings",      -- static header title
--     -- titleFor = function(item, ctx) ... end,   -- or per-item title
--     renderItem  = function(content, item, ctx)
--       -- caller populates content for this item. ctx = {
--       --   index       1-based position of this visit (= #history + 1)
--       --   total       index + (#queue-after-current)  -- grows with Push
--       --   history     list of { item, action } for prior visits
--       --   queue       remaining queue snapshot (current at queue[1])
--       -- }
--     end,
--     actions     = {
--       { key = "skip",     label = "Skip" },
--       { key = "primary",  label = "Repost", style = "primary" },
--     },
--     onAction    = function(actionKey, item, ctx)
--       -- caller logic. By default the stepper advances after onAction
--       -- returns; return false to suppress auto-advance (caller will
--       -- later call stepper:Advance(actionKey) or stepper:Cancel()).
--     end,
--     onCancel    = function(remainingItems) ... end,
--     onComplete  = function() ... end,
--     showProgress = true,                          -- "3 / 12" in header
--     showBack    = true,                           -- Back button in footer
--   })
--   stepper:SetAllPoints()
--
--   stepper:Push(item)         -- append to queue end during traversal
--   stepper:Skip()              -- advance without firing onAction
--   stepper:Back()              -- revisit prior item; previous action is in ctx.history
--   stepper:Refresh()           -- re-render current item (e.g. caller mutated state)
--   stepper:Advance(actionKey)  -- programmatically complete the current item
--   stepper:GetRemaining()      -- queue snapshot
--   stepper:GetCurrent()        -- current item (or nil)
--   stepper:GetHistory()        -- list of { item, action } records
--
-- The stepper does not auto-hide on complete; the caller decides whether
-- to dismiss, show a "done" message, or re-Push more items.

local lib = LibStub("Cogworks-1.0")
if not lib then return end

-- Module load guard. See Sections.lua for rationale.
local MODULE_MINOR = 1
lib._modules = lib._modules or {}
if (lib._modules.Stepper or 0) >= MODULE_MINOR then return end
lib._modules.Stepper = MODULE_MINOR

local HEADER_H        = 36
local FOOTER_H        = 40
local FOOTER_BTN_W    = 96
local FOOTER_BTN_H    = 26
local FOOTER_BTN_GAP  = 8

local function shallowCopy(t)
  local out = {}
  for i = 1, #t do out[i] = t[i] end
  return out
end

function lib:CreateStepper(parent, opts)
  opts = opts or {}
  assert(type(opts.renderItem) == "function",
    "CreateStepper: opts.renderItem (function) required")
  assert(type(opts.actions) == "table" and #opts.actions > 0,
    "CreateStepper: opts.actions required (at least one action)")
  for _, a in ipairs(opts.actions) do
    assert(type(a.key) == "string" and a.key ~= "" and type(a.label) == "string",
      "CreateStepper: each action needs string key + label")
  end

  local T = self.Theme
  local showProgress = opts.showProgress ~= false
  local showBack     = opts.showBack     ~= false

  local stepper = CreateFrame("Frame", nil, parent)

  -- ---- Header (title + progress) ----------------------------------------
  local header = CreateFrame("Frame", nil, stepper)
  header:SetHeight(HEADER_H)
  header:SetPoint("TOPLEFT")
  header:SetPoint("TOPRIGHT")

  local titleFs = header:CreateFontString(nil, "OVERLAY")
  titleFs:SetFontObject(self:GetFont("large") or "GameFontNormalLarge")
  titleFs:SetPoint("LEFT", header, "LEFT", 12, 0)
  titleFs:SetPoint("RIGHT", header, "RIGHT", -120, 0)
  titleFs:SetJustifyH("LEFT")
  titleFs:SetTextColor(unpack(T.text))
  titleFs:SetWordWrap(false)

  local progressFs
  if showProgress then
    progressFs = header:CreateFontString(nil, "OVERLAY")
    progressFs:SetFontObject(self:GetFont("normal") or "GameFontNormal")
    progressFs:SetPoint("RIGHT", header, "RIGHT", -12, 0)
    progressFs:SetTextColor(unpack(T.textDim))
  end

  local headerBorder = stepper:CreateTexture(nil, "BACKGROUND")
  headerBorder:SetHeight(1)
  headerBorder:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, 0)
  headerBorder:SetPoint("TOPRIGHT", header, "BOTTOMRIGHT", 0, 0)
  headerBorder:SetColorTexture(unpack(T.border))

  -- ---- Footer (button row) ----------------------------------------------
  local footer = CreateFrame("Frame", nil, stepper)
  footer:SetHeight(FOOTER_H)
  footer:SetPoint("BOTTOMLEFT")
  footer:SetPoint("BOTTOMRIGHT")

  local footerBorder = stepper:CreateTexture(nil, "BACKGROUND")
  footerBorder:SetHeight(1)
  footerBorder:SetPoint("BOTTOMLEFT", footer, "TOPLEFT", 0, 0)
  footerBorder:SetPoint("BOTTOMRIGHT", footer, "TOPRIGHT", 0, 0)
  footerBorder:SetColorTexture(unpack(T.border))

  -- ---- Content area -----------------------------------------------------
  local content = CreateFrame("Frame", nil, stepper)
  content:SetPoint("TOPLEFT", headerBorder, "BOTTOMLEFT", 0, 0)
  content:SetPoint("BOTTOMRIGHT", footerBorder, "TOPRIGHT", 0, 0)
  stepper.content = content

  -- ---- State ------------------------------------------------------------
  local queue   = {}
  for i, v in ipairs(opts.items or {}) do queue[i] = v end
  local history = {}    -- list of { item, action }

  local function makeCtx()
    return {
      index   = #history + 1,
      total   = #history + #queue,
      history = history,
      queue   = queue,
    }
  end

  local function renderCurrent()
    local item = queue[1]
    local ctx = makeCtx()
    if item == nil then
      -- Empty state: queue has been exhausted (or never had items). Caller
      -- gets the bare content frame to draw a "done" message; the stepper
      -- doesn't auto-hide.
      ctx.index = #history
      ctx.total = #history
    end

    -- Header title (static or per-item)
    if opts.titleFor then
      titleFs:SetText(opts.titleFor(item, ctx) or "")
    else
      titleFs:SetText(opts.title or "")
    end

    -- Header progress
    if progressFs then
      if ctx.total > 0 then
        progressFs:SetText(ctx.index .. " / " .. ctx.total)
      else
        progressFs:SetText("")
      end
    end

    -- Let the caller redraw. Caller owns widget lifecycle inside `content`.
    opts.renderItem(content, item, ctx)
  end

  -- ---- Footer buttons (declared after state so handlers can close over it)
  local cancelBtn = self:CreateButton(footer, opts.cancelLabel or "Cancel",
    FOOTER_BTN_W, FOOTER_BTN_H, nil)
  cancelBtn:SetPoint("LEFT", footer, "LEFT", 12, 0)

  local backBtn
  if showBack then
    backBtn = self:CreateButton(footer, opts.backLabel or "Back",
      FOOTER_BTN_W, FOOTER_BTN_H, nil)
    backBtn:SetPoint("LEFT", cancelBtn, "RIGHT", FOOTER_BTN_GAP, 0)
  end

  -- Build action buttons right-to-left so opts.actions[#] sits at the
  -- right edge and opts.actions[1] is the leftmost action.
  local actionBtns = {}
  do
    local rightAnchor = footer
    local rightPoint  = "RIGHT"
    local xoff        = -12
    for i = #opts.actions, 1, -1 do
      local def = opts.actions[i]
      local btn = self:CreateButton(footer, def.label,
        FOOTER_BTN_W, FOOTER_BTN_H, nil)
      btn:SetPoint("RIGHT", rightAnchor, rightPoint, xoff, 0)
      if def.style == "primary" then
        btn:SetBackdropBorderColor(unpack(T.gold))
      end
      actionBtns[def.key] = btn
      rightAnchor = btn
      rightPoint  = "LEFT"
      xoff        = -FOOTER_BTN_GAP
    end
  end

  -- Track primary-style action keys so we can restore gold border on re-enable.
  local primaryKeys = {}
  for _, a in ipairs(opts.actions) do
    if a.style == "primary" then primaryKeys[a.key] = true end
  end

  -- ---- Button enable/disable based on queue + history -------------------
  local function applyButtonState()
    local hasCurrent = queue[1] ~= nil
    for key, btn in pairs(actionBtns) do
      if hasCurrent then
        btn:EnableMouse(true)
        btn.text:SetTextColor(unpack(T.text))
        btn:SetBackdropBorderColor(unpack(primaryKeys[key] and T.gold or T.border))
      else
        btn:EnableMouse(false)
        btn.text:SetTextColor(unpack(T.textDisabled))
        btn:SetBackdropBorderColor(0.2, 0.2, 0.25, 1)
      end
    end
    if backBtn then
      if #history > 0 then
        backBtn:EnableMouse(true)
        backBtn.text:SetTextColor(unpack(T.text))
        backBtn:SetBackdropBorderColor(unpack(T.border))
      else
        backBtn:EnableMouse(false)
        backBtn.text:SetTextColor(unpack(T.textDisabled))
        backBtn:SetBackdropBorderColor(0.2, 0.2, 0.25, 1)
      end
    end
  end

  -- ---- Transitions ------------------------------------------------------
  local function advance(actionKey)
    local item = queue[1]
    if item == nil then return end
    table.remove(queue, 1)
    history[#history + 1] = { item = item, action = actionKey }
    if queue[1] == nil and opts.onComplete then
      renderCurrent()
      applyButtonState()
      opts.onComplete()
      return
    end
    renderCurrent()
    applyButtonState()
  end

  -- ---- Public API -------------------------------------------------------
  function stepper:Push(item)
    queue[#queue + 1] = item
    -- Re-render so the progress count updates and an empty/complete state
    -- restarts with the newly current item (onComplete-then-Push case).
    renderCurrent()
    applyButtonState()
  end

  function stepper:Skip()
    advance("skip")
  end

  function stepper:Back()
    if #history == 0 then return end
    local last = table.remove(history)
    table.insert(queue, 1, last.item)
    renderCurrent()
    applyButtonState()
  end

  function stepper:Advance(actionKey)
    advance(actionKey or "advance")
  end

  function stepper:Refresh()
    renderCurrent()
    applyButtonState()
  end

  function stepper:Cancel()
    if opts.onCancel then opts.onCancel(shallowCopy(queue)) end
  end

  function stepper:GetRemaining() return shallowCopy(queue) end
  function stepper:GetCurrent()   return queue[1] end
  function stepper:GetHistory()
    local out = {}
    for i, h in ipairs(history) do out[i] = { item = h.item, action = h.action } end
    return out
  end

  -- ---- Wire footer handlers --------------------------------------------
  cancelBtn:SetScript("OnClick", function() stepper:Cancel() end)
  if backBtn then
    backBtn:SetScript("OnClick", function() stepper:Back() end)
  end
  for key, btn in pairs(actionBtns) do
    btn:SetScript("OnClick", function()
      local item = queue[1]
      if item == nil then return end
      local ctx = makeCtx()
      local suppress
      if opts.onAction then
        suppress = opts.onAction(key, item, ctx) == false
      end
      if not suppress then advance(key) end
    end)
  end

  -- ---- Initial paint ----------------------------------------------------
  renderCurrent()
  applyButtonState()

  return stepper
end
