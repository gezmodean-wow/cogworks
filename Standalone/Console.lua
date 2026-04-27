-- Standalone/Console.lua
-- Multi-line Lua dev console for the standalone Cogworks addon.
-- NOT embedded into sibling cogs — only ships in the standalone install.
--
-- Open with /cogworks console. Paste / type Lua, hit Run (or Ctrl+Enter)
-- and the output pane shows captured `print()` calls, return values, and
-- errors. History is opt-in (toggle the "Save" checkbox before Run) and
-- browsed via the History button — arrow keys are reserved for normal
-- text navigation inside the editor.

local addonName, ns = ...
local cw = LibStub("Cogworks-1.0")
local T = cw.Theme

local FRAME_W, FRAME_H = 720, 540
local INPUT_RATIO = 0.45
local MAX_HISTORY = 50

-- 6-char RGB; appendLine prepends "|cff" (full alpha).
local COLOR_PROMPT = "d4a017"  -- gold — `>>>` input echo
local COLOR_PRINT  = "e6e6e6"  -- light gray — captured print() output
local COLOR_RETURN = "8be9c0"  -- mint — return values
local COLOR_ERROR  = "ff4040"  -- red — compile / runtime errors
local COLOR_HINT   = "888888"  -- dim gray — help text

local frame, input, output, saveCheck, historyButton, historyPopup, historyContent, historyEmpty
local copyPopup, copyEdit

local history = {}        -- session-only; oldest first. Each entry: { script, t }
local outputBuffer = {}   -- plain-text mirror of the SMF for the Copy popup
local saveEnabled = true  -- "Save to history" checkbox state

local loadFn = loadstring or load

-- ============================================================================
-- Output
-- ============================================================================

local function appendLine(text, hex)
  if not output then return end
  if hex then
    output:AddMessage("|cff" .. hex .. text .. "|r")
  else
    output:AddMessage(text)
  end
  outputBuffer[#outputBuffer + 1] = text  -- plain text for Copy popup
end

local function appendBlock(text, hex)
  for line in (text .. "\n"):gmatch("([^\n]*)\n") do
    appendLine(line, hex)
  end
end

-- ============================================================================
-- Execution
-- ============================================================================

local function packResults(...)
  return select("#", ...), { ... }
end

local function executeScript(scriptText)
  if not scriptText or scriptText:match("^%s*$") then return end

  if saveEnabled then
    -- De-dup against the most recent entry to avoid spamming history when
    -- the user re-runs the same script repeatedly during iteration.
    local last = history[#history]
    if not last or last.script ~= scriptText then
      history[#history + 1] = { script = scriptText, t = time() }
      if #history > MAX_HISTORY then
        table.remove(history, 1)
      end
      if historyButton then
        historyButton:SetText("History (" .. #history .. ")")
      end
    end
  end

  local echo = scriptText:gsub("\n", "\n... ")
  appendLine(">>> " .. echo, COLOR_PROMPT)

  local captured = {}
  local realPrint = _G.print
  _G.print = function(...)
    local n = select("#", ...)
    local parts = {}
    for i = 1, n do parts[i] = tostring((select(i, ...))) end
    captured[#captured + 1] = table.concat(parts, " ")
  end

  -- Try expression form first so `1+1` evaluates and returns 2; fall back to
  -- statement form for multi-statement scripts.
  local fn, err = loadFn("return " .. scriptText, "console")
  if not fn then
    fn, err = loadFn(scriptText, "console")
  end

  if not fn then
    _G.print = realPrint
    appendBlock("compile error: " .. tostring(err), COLOR_ERROR)
    return
  end

  local n, results = packResults(pcall(fn))
  _G.print = realPrint

  for _, line in ipairs(captured) do
    appendBlock(line, COLOR_PRINT)
  end

  if not results[1] then
    appendBlock("error: " .. tostring(results[2]), COLOR_ERROR)
    return
  end

  for i = 2, n do
    appendBlock(tostring(results[i]), COLOR_RETURN)
  end
end

-- ============================================================================
-- Indent cleanup
-- ============================================================================

-- Strip leading whitespace from every line. Cheap fix for pastes from
-- terminals or chat clients that prefix continuation lines with spaces.
-- Lua doesn't care about indentation for syntax, so this is always safe.
local function stripLeadingWhitespace(text)
  return (text:gsub("\n%s+", "\n"):gsub("^%s+", ""))
end

-- ============================================================================
-- Copy popup
-- ============================================================================

local function buildCopyPopup()
  local p = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
  p:SetSize(640, 420)
  p:SetPoint("CENTER")
  p:SetFrameStrata("FULLSCREEN_DIALOG")
  p:SetBackdrop(cw.Backdrop)
  p:SetBackdropColor(unpack(T.bg))
  p:SetBackdropBorderColor(unpack(T.border))
  p:EnableMouse(true)
  p:SetMovable(true)
  p:RegisterForDrag("LeftButton")
  p:SetScript("OnDragStart", p.StartMoving)
  p:SetScript("OnDragStop", p.StopMovingOrSizing)
  p:Hide()

  local title = p:CreateFontString(nil, "OVERLAY")
  title:SetFontObject(cw:GetFont("header") or "GameFontHighlight")
  title:SetPoint("TOPLEFT", 14, -10)
  title:SetText("Copy output")
  title:SetTextColor(unpack(T.gold))

  local close = CreateFrame("Button", nil, p, "UIPanelCloseButton")
  close:SetPoint("TOPRIGHT", 2, 2)

  local hint = p:CreateFontString(nil, "OVERLAY")
  hint:SetFontObject(cw:GetFont("small") or "GameFontDisableSmall")
  hint:SetPoint("TOPLEFT", 14, -34)
  hint:SetText("Text is pre-selected — Ctrl+C to copy. Edits here aren't saved.")
  hint:SetTextColor(unpack(T.textDim))

  local editBg = CreateFrame("Frame", nil, p, "BackdropTemplate")
  editBg:SetPoint("TOPLEFT", 12, -52)
  editBg:SetPoint("BOTTOMRIGHT", -12, 48)
  editBg:SetBackdrop(cw.BackdropSmall)
  editBg:SetBackdropColor(unpack(T.bgDark))
  editBg:SetBackdropBorderColor(unpack(T.border))

  local scroll = CreateFrame("ScrollFrame", nil, editBg, "InputScrollFrameTemplate")
  scroll:SetPoint("TOPLEFT", 8, -8)
  scroll:SetPoint("BOTTOMRIGHT", -8, 8)

  copyEdit = scroll.EditBox
  copyEdit:SetMaxLetters(0)  -- unlimited; long sessions can produce a lot
  copyEdit:SetFontObject(cw:GetFont("small") or "ChatFontSmall")
  copyEdit:SetAutoFocus(false)
  copyEdit:SetMultiLine(true)
  copyEdit:SetCountInvisibleLetters(false)
  if scroll.CharCount then scroll.CharCount:Hide() end
  copyEdit:SetScript("OnEscapePressed", function() p:Hide() end)

  local closeBtn = cw:CreateButton(p, "Close", 80, 24, function() p:Hide() end)
  closeBtn:SetPoint("BOTTOMRIGHT", -12, 14)

  return p
end

local function showCopyPopup()
  if not copyPopup then copyPopup = buildCopyPopup() end
  local text = table.concat(outputBuffer, "\n")
  copyEdit:SetText(text)
  copyEdit:HighlightText()
  copyEdit:SetFocus()
  copyPopup:Show()
end

-- ============================================================================
-- History UI
-- ============================================================================

local function setInputText(text)
  input:SetText(text or "")
  input:SetCursorPosition(#(text or ""))
  input:SetFocus()
end

local function entryLabel(scriptText)
  local firstLine = scriptText:match("^%s*([^\n]+)") or scriptText
  if #firstLine > 60 then firstLine = firstLine:sub(1, 57) .. "..." end
  return firstLine
end

local function relativeAge(t)
  local d = time() - t
  if d < 60 then return d .. "s" end
  if d < 3600 then return math.floor(d / 60) .. "m" end
  if d < 86400 then return math.floor(d / 3600) .. "h" end
  return math.floor(d / 86400) .. "d"
end

local function rebuildHistoryList()
  if not historyContent then return end
  -- Wipe existing row buttons (regions like emptyState are toggled, not destroyed).
  for _, child in ipairs({ historyContent:GetChildren() }) do
    child:Hide()
    child:SetParent(nil)
  end

  if #history == 0 then
    if historyEmpty then historyEmpty:Show() end
    historyContent:SetHeight(20)
    return
  end
  if historyEmpty then historyEmpty:Hide() end

  local rowH = 18
  -- Iterate newest-first so the most recent shows at the top.
  for i = #history, 1, -1 do
    local entry = history[i]
    local row = CreateFrame("Button", nil, historyContent)
    local rowIndex = #history - i  -- 0-based from top
    row:SetSize(historyContent:GetWidth() - 8, rowH)
    row:SetPoint("TOPLEFT", 4, -(rowIndex * rowH) - 4)
    row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")

    local age = row:CreateFontString(nil, "OVERLAY")
    age:SetFontObject(cw:GetFont("small") or "GameFontNormalSmall")
    age:SetPoint("LEFT", 2, 0)
    age:SetWidth(36)
    age:SetJustifyH("LEFT")
    age:SetText(relativeAge(entry.t) .. " ago")
    age:SetTextColor(unpack(T.textDim))

    local label = row:CreateFontString(nil, "OVERLAY")
    label:SetFontObject(cw:GetFont("small") or "GameFontNormalSmall")
    label:SetPoint("LEFT", age, "RIGHT", 6, 0)
    label:SetPoint("RIGHT", -4, 0)
    label:SetJustifyH("LEFT")
    label:SetText(entryLabel(entry.script))
    label:SetTextColor(unpack(T.text))

    row:SetScript("OnClick", function()
      setInputText(entry.script)
      historyPopup:Hide()
    end)
  end

  historyContent:SetHeight(#history * rowH + 8)
end

local function buildHistoryPopup()
  local p = CreateFrame("Frame", nil, frame, "BackdropTemplate")
  p:SetSize(360, 240)
  p:SetBackdrop(cw.BackdropSmall)
  p:SetBackdropColor(unpack(T.bgDark))
  p:SetBackdropBorderColor(unpack(T.border))
  p:SetFrameStrata("FULLSCREEN_DIALOG")
  p:SetFrameLevel(frame:GetFrameLevel() + 20)
  p:Hide()

  local title = p:CreateFontString(nil, "OVERLAY")
  title:SetFontObject(cw:GetFont("small") or "GameFontNormalSmall")
  title:SetPoint("TOPLEFT", 8, -6)
  title:SetText("Recent scripts (click to load)")
  title:SetTextColor(unpack(T.textDim))

  local scroll = CreateFrame("ScrollFrame", nil, p, "UIPanelScrollFrameTemplate")
  scroll:SetPoint("TOPLEFT", 6, -22)
  scroll:SetPoint("BOTTOMRIGHT", -28, 36)

  local content = CreateFrame("Frame", nil, scroll)
  content:SetSize(scroll:GetWidth(), 1)
  scroll:SetScrollChild(content)
  historyContent = content

  historyEmpty = content:CreateFontString(nil, "OVERLAY")
  historyEmpty:SetFontObject(cw:GetFont("small") or "GameFontDisableSmall")
  historyEmpty:SetPoint("TOPLEFT", 4, -4)
  historyEmpty:SetText("(no history yet)")
  historyEmpty:SetTextColor(unpack(T.textDim))
  historyEmpty:Hide()

  local clearAll = cw:CreateButton(p, "Clear all", 90, 22, function()
    wipe(history)
    if historyButton then historyButton:SetText("History (0)") end
    rebuildHistoryList()
  end)
  clearAll:SetPoint("BOTTOMRIGHT", -8, 8)

  return p
end

local function toggleHistory()
  if not historyPopup then historyPopup = buildHistoryPopup() end
  if historyPopup:IsShown() then
    historyPopup:Hide()
  else
    historyPopup:ClearAllPoints()
    historyPopup:SetPoint("BOTTOMLEFT", historyButton, "TOPLEFT", 0, 4)
    rebuildHistoryList()
    historyPopup:Show()
  end
end

-- ============================================================================
-- Frame
-- ============================================================================

local function createConsole()
  local f = CreateFrame("Frame", "CogworksConsole", UIParent, "BackdropTemplate")
  f:SetSize(FRAME_W, FRAME_H)
  f:SetPoint("CENTER")
  f:SetFrameStrata("DIALOG")
  f:SetBackdrop(cw.Backdrop)
  f:SetBackdropColor(unpack(T.bg))
  f:SetBackdropBorderColor(unpack(T.border))
  f:EnableMouse(true)
  f:SetMovable(true)
  f:SetResizable(true)
  if f.SetResizeBounds then f:SetResizeBounds(520, 380) end
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", f.StartMoving)
  f:SetScript("OnDragStop", f.StopMovingOrSizing)
  f:Hide()

  local title = f:CreateFontString(nil, "OVERLAY")
  title:SetFontObject(cw:GetFont("header") or "GameFontHighlight")
  title:SetPoint("TOPLEFT", 14, -10)
  title:SetText("Cogworks Console")
  title:SetTextColor(unpack(T.gold))

  local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
  close:SetPoint("TOPRIGHT", 2, 2)

  -- Output
  local outputBg = CreateFrame("Frame", nil, f, "BackdropTemplate")
  outputBg:SetPoint("TOPLEFT", 12, -36)
  outputBg:SetPoint("TOPRIGHT", -12, -36)
  outputBg:SetHeight(FRAME_H * (1 - INPUT_RATIO) - 90)
  outputBg:SetBackdrop(cw.BackdropSmall)
  outputBg:SetBackdropColor(unpack(T.bgDark))
  outputBg:SetBackdropBorderColor(unpack(T.border))

  output = CreateFrame("ScrollingMessageFrame", nil, outputBg)
  output:SetPoint("TOPLEFT", 8, -8)
  output:SetPoint("BOTTOMRIGHT", -8, 8)
  output:SetFontObject(cw:GetFont("small") or "ChatFontSmall")
  output:SetJustifyH("LEFT")
  output:SetMaxLines(2000)
  output:SetFading(false)
  output:SetIndentedWordWrap(false)
  output:EnableMouseWheel(true)
  output:SetScript("OnMouseWheel", function(self, delta)
    if IsShiftKeyDown() then
      if delta > 0 then self:ScrollToTop() else self:ScrollToBottom() end
    elseif delta > 0 then
      self:ScrollUp()
    else
      self:ScrollDown()
    end
  end)

  appendLine("Cogworks Console v" .. cw.version .. ". Ctrl+Enter to run. Arrow keys edit text. Use the History button to recall scripts.", COLOR_HINT)

  -- Input (multi-line) via InputScrollFrameTemplate
  local inputBg = CreateFrame("Frame", nil, f, "BackdropTemplate")
  inputBg:SetPoint("BOTTOMLEFT", 12, 60)
  inputBg:SetPoint("BOTTOMRIGHT", -12, 60)
  inputBg:SetHeight(FRAME_H * INPUT_RATIO - 4)
  inputBg:SetBackdrop(cw.BackdropSmall)
  inputBg:SetBackdropColor(unpack(T.bgDark))
  inputBg:SetBackdropBorderColor(unpack(T.border))

  local scroll = CreateFrame("ScrollFrame", nil, inputBg, "InputScrollFrameTemplate")
  scroll:SetPoint("TOPLEFT", 8, -8)
  scroll:SetPoint("BOTTOMRIGHT", -8, 8)

  input = scroll.EditBox
  input:SetMaxLetters(20000)
  input:SetFontObject(cw:GetFont("small") or "ChatFontSmall")
  input:SetAutoFocus(false)
  input:SetMultiLine(true)
  input:SetCountInvisibleLetters(false)
  if scroll.CharCount then scroll.CharCount:Hide() end

  -- Resize grip
  local grip = CreateFrame("Button", nil, f)
  grip:SetSize(16, 16)
  grip:SetPoint("BOTTOMRIGHT", -3, 3)
  grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
  grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
  grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
  grip:SetScript("OnMouseDown", function() f:StartSizing("BOTTOMRIGHT") end)
  grip:SetScript("OnMouseUp", function() f:StopMovingOrSizing() end)

  -- Bottom button row (left side)
  local stripBtn = cw:CreateButton(f, "Strip indent", 100, 24, function()
    input:SetText(stripLeadingWhitespace(input:GetText()))
    input:SetFocus()
    input:SetCursorPosition(0)
  end)
  stripBtn:SetPoint("BOTTOMLEFT", 12, 18)

  saveCheck = cw:CreateCheckbox(f, "Save to history", nil, true, function(_, value)
    saveEnabled = value
  end)
  saveCheck:SetPoint("LEFT", stripBtn, "RIGHT", 12, 0)

  historyButton = cw:CreateButton(f, "History (0)", 110, 24, toggleHistory)
  historyButton:SetPoint("LEFT", saveCheck, "RIGHT", 130, 0)

  -- Bottom button row (right side)
  local runBtn = cw:CreateButton(f, "Run", 80, 24, function()
    executeScript(input:GetText())
  end)
  runBtn:SetPoint("BOTTOMRIGHT", -12, 18)

  local clearBtn = cw:CreateButton(f, "Clear", 70, 24, function()
    output:Clear()
    wipe(outputBuffer)
  end)
  clearBtn:SetPoint("RIGHT", runBtn, "LEFT", -8, 0)

  local copyBtn = cw:CreateButton(f, "Copy", 70, 24, showCopyPopup)
  copyBtn:SetPoint("RIGHT", clearBtn, "LEFT", -8, 0)

  -- Ctrl+Enter to run; plain Enter inserts a newline (already default for
  -- multi-line EditBox, but the OnEnterPressed handler still fires).
  input:SetScript("OnEnterPressed", function(self)
    if IsControlKeyDown() then
      executeScript(self:GetText())
    else
      self:Insert("\n")
    end
  end)

  input:SetScript("OnEscapePressed", function(self)
    self:ClearFocus()
  end)

  return f
end

-- ============================================================================
-- Public toggle
-- ============================================================================

function ns:ToggleConsole()
  if not frame then frame = createConsole() end
  if frame:IsShown() then
    frame:Hide()
  else
    frame:Show()
    input:SetFocus()
  end
end
