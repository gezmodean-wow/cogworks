-- Cogworks-1.0/Wizard.lua | Multi-step wizard primitive.
--
-- Forward-only by default, with a progress indicator, per-step validation
-- gate, and Previous / Next / Finish / Cancel footer. Each step's body is
-- built lazily on first activation; the wizard handles Show/Hide as the
-- user advances or steps back.
--
-- Consumers in the suite: onboarding flows (FlipQueue's SetupWizard),
-- one-shot config migrators, import flows that need to confirm a
-- destination, future in-game equivalents of /cog-init.
--
-- Usage:
--
--   local wizard = cw:CreateWizard(parent, {
--     steps = {
--       { key = "welcome", title = "Welcome", build = function(c) ... end },
--       { key = "config",  title = "Configuration",
--         build    = function(c) ... end,
--         validate = function() return MySettings.valid end,
--       },
--       { key = "review",  title = "Review", build = function(c) ... end },
--     },
--     onComplete = function() ... end,    -- Finish click on the last step
--     onCancel   = function() ... end,    -- Cancel click any step
--     onStepChange = function(key, idx) ... end,  -- after each navigation
--     finishLabel = "Apply",              -- defaults to "Finish"
--     cancelLabel = "Cancel",
--   })
--   wizard:SetAllPoints()
--   wizard:GetCurrentStep()  -- key
--   wizard:Next() / :Previous() / :GoTo(key)
--
-- Each step's build(parent) must return a Frame anchored to parent (the
-- wizard's content frame). The wizard owns Show/Hide; the caller owns
-- the contents.

local lib = LibStub("Cogworks-1.0")
if not lib then return end

-- Module load guard. See Sections.lua for rationale.
local MODULE_MINOR = 15
lib._modules = lib._modules or {}
if (lib._modules.Wizard or 0) >= MODULE_MINOR then return end
lib._modules.Wizard = MODULE_MINOR

local HEADER_H        = 36
local FOOTER_H        = 40
local FOOTER_BTN_W    = 96
local FOOTER_BTN_H    = 26
local FOOTER_BTN_GAP  = 8
local PROGRESS_DOT    = 8
local PROGRESS_GAP    = 6

function lib:CreateWizard(parent, opts)
  opts = opts or {}
  assert(type(opts.steps) == "table" and #opts.steps > 0,
    "CreateWizard: opts.steps required (at least one step)")
  for _, step in ipairs(opts.steps) do
    assert(step.key and step.title, "CreateWizard: each step needs key + title")
  end
  local T = self.Theme

  local wizard = CreateFrame("Frame", nil, parent)

  -- ---- Header (title + progress) ----------------------------------------
  local header = CreateFrame("Frame", nil, wizard)
  header:SetHeight(HEADER_H)
  header:SetPoint("TOPLEFT")
  header:SetPoint("TOPRIGHT")

  local titleFs = header:CreateFontString(nil, "OVERLAY")
  titleFs:SetFontObject(self:GetFont("large") or "GameFontNormalLarge")
  titleFs:SetPoint("LEFT", header, "LEFT", 12, 0)
  titleFs:SetTextColor(unpack(T.text))

  -- Progress dots: one per step, gold for completed/active, dim for
  -- upcoming. Counted right-aligned next to the title.
  local progressFrame = CreateFrame("Frame", nil, header)
  progressFrame:SetSize(#opts.steps * (PROGRESS_DOT + PROGRESS_GAP), PROGRESS_DOT + 4)
  progressFrame:SetPoint("RIGHT", header, "RIGHT", -12, 0)
  local dots = {}
  for i = 1, #opts.steps do
    local dot = progressFrame:CreateTexture(nil, "ARTWORK")
    dot:SetSize(PROGRESS_DOT, PROGRESS_DOT)
    dot:SetPoint("LEFT", progressFrame, "LEFT", (i - 1) * (PROGRESS_DOT + PROGRESS_GAP), 0)
    dots[i] = dot
  end

  local headerBorder = wizard:CreateTexture(nil, "BACKGROUND")
  headerBorder:SetHeight(1)
  headerBorder:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, 0)
  headerBorder:SetPoint("TOPRIGHT", header, "BOTTOMRIGHT", 0, 0)
  headerBorder:SetColorTexture(unpack(T.border))

  -- ---- Footer (button row) ----------------------------------------------
  local footer = CreateFrame("Frame", nil, wizard)
  footer:SetHeight(FOOTER_H)
  footer:SetPoint("BOTTOMLEFT")
  footer:SetPoint("BOTTOMRIGHT")

  local footerBorder = wizard:CreateTexture(nil, "BACKGROUND")
  footerBorder:SetHeight(1)
  footerBorder:SetPoint("BOTTOMLEFT", footer, "TOPLEFT", 0, 0)
  footerBorder:SetPoint("BOTTOMRIGHT", footer, "TOPRIGHT", 0, 0)
  footerBorder:SetColorTexture(unpack(T.border))

  -- ---- Content area -----------------------------------------------------
  local content = CreateFrame("Frame", nil, wizard)
  content:SetPoint("TOPLEFT", headerBorder, "BOTTOMLEFT", 0, 0)
  content:SetPoint("BOTTOMRIGHT", footerBorder, "TOPRIGHT", 0, 0)
  wizard.content = content

  -- ---- State + index ----------------------------------------------------
  local stepsByKey = {}
  for i, step in ipairs(opts.steps) do
    stepsByKey[step.key] = { index = i, def = step }
  end
  local stepPages = {}  -- key → page frame (lazy-built)
  local currentIndex = 1

  local function pageFor(stepKey)
    if not stepPages[stepKey] then
      local def = stepsByKey[stepKey].def
      if def.build then
        local page = def.build(content)
        if page then stepPages[stepKey] = page end
      end
    end
    return stepPages[stepKey]
  end

  -- ---- Footer buttons (declared after pageFor so Next/Finish can use it) -
  local cancelBtn = self:CreateButton(footer, opts.cancelLabel or "Cancel",
    FOOTER_BTN_W, FOOTER_BTN_H, function()
      if opts.onCancel then opts.onCancel() end
    end)
  cancelBtn:SetPoint("LEFT", footer, "LEFT", 12, 0)

  local prevBtn = self:CreateButton(footer, "Previous",
    FOOTER_BTN_W, FOOTER_BTN_H, nil)
  prevBtn:SetPoint("RIGHT", footer, "RIGHT", -(FOOTER_BTN_W + FOOTER_BTN_GAP + 12), 0)

  local nextBtn = self:CreateButton(footer, "Next",
    FOOTER_BTN_W, FOOTER_BTN_H, nil)
  nextBtn:SetPoint("RIGHT", footer, "RIGHT", -12, 0)

  -- ---- Navigation -------------------------------------------------------
  local function applyButtonState()
    -- Previous: disabled on first step
    if currentIndex == 1 then
      prevBtn:EnableMouse(false)
      prevBtn.text:SetTextColor(unpack(T.textDisabled))
      prevBtn:SetBackdropBorderColor(0.2, 0.2, 0.25, 1)
    else
      prevBtn:EnableMouse(true)
      prevBtn.text:SetTextColor(unpack(T.text))
      prevBtn:SetBackdropBorderColor(unpack(T.border))
    end

    -- Next becomes Finish on the last step.
    local isLast = currentIndex == #opts.steps
    nextBtn.text:SetText(isLast and (opts.finishLabel or "Finish") or "Next")

    -- Validation gate on Next/Finish.
    local def = opts.steps[currentIndex]
    local valid = (not def.validate) or def.validate()
    if valid then
      nextBtn:EnableMouse(true)
      nextBtn.text:SetTextColor(unpack(T.text))
      nextBtn:SetBackdropBorderColor(unpack(T.border))
    else
      nextBtn:EnableMouse(false)
      nextBtn.text:SetTextColor(unpack(T.textDisabled))
      nextBtn:SetBackdropBorderColor(0.2, 0.2, 0.25, 1)
    end
  end

  local function applyDots()
    for i, dot in ipairs(dots) do
      if i < currentIndex then
        dot:SetColorTexture(T.gold[1] * 0.7, T.gold[2] * 0.7, T.gold[3] * 0.7, 1)
      elseif i == currentIndex then
        dot:SetColorTexture(unpack(T.gold))
      else
        dot:SetColorTexture(unpack(T.textDim))
      end
    end
  end

  local function showStep(idx)
    local def = opts.steps[idx]
    if not def then return end
    -- Hide previous
    local prevDef = opts.steps[currentIndex]
    if prevDef and stepPages[prevDef.key] then stepPages[prevDef.key]:Hide() end

    currentIndex = idx
    titleFs:SetText(def.title)

    local page = pageFor(def.key)
    if page then page:Show() end

    applyDots()
    applyButtonState()

    if opts.onStepChange then opts.onStepChange(def.key, idx) end
  end

  -- Public: revalidate the Next button. Callers whose step-validate state
  -- changes (e.g. user toggles a checkbox that gates progress) should call
  -- this to update the footer enable/disable visual.
  function wizard:Refresh() applyButtonState() end

  function wizard:GetCurrentStep() return opts.steps[currentIndex].key end

  function wizard:GoTo(key)
    local entry = stepsByKey[key]
    if entry then showStep(entry.index) end
  end

  function wizard:Next()
    local def = opts.steps[currentIndex]
    if def.validate and not def.validate() then return end
    if currentIndex < #opts.steps then
      showStep(currentIndex + 1)
    elseif opts.onComplete then
      opts.onComplete()
    end
  end

  function wizard:Previous()
    if currentIndex > 1 then showStep(currentIndex - 1) end
  end

  prevBtn:SetScript("OnClick", function() wizard:Previous() end)
  nextBtn:SetScript("OnClick", function() wizard:Next() end)

  -- Initial state
  showStep(1)

  return wizard
end
