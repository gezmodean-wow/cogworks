-- Cogworks-1.0/Sections.lua | Collapsible section primitive.
--
-- A common settings-page idiom: a header row with a title and optional
-- summary that toggles a content frame open/closed. Caller populates the
-- `content` frame, calls SetContentHeight when its child layout is final,
-- and asks the section for GetConsumedHeight when laying out the next
-- section below.
--
-- Font scaling: the header re-fonts and recomputes its height whenever
-- Cogworks' fontScale or fontFamily settings change, so a stack of
-- sections at 1.5x scale doesn't clip.

local lib = LibStub("Cogworks-1.0")
if not lib then return end

-- Module load guard. Cogworks lib files run unconditionally per addon: when
-- a sibling cog vendors an older Cogworks copy, its module files load AFTER
-- the standalone library and would otherwise clobber methods the newer copy
-- already attached. Tracking a per-module loaded-at-MINOR on lib lets older
-- copies skip cleanly. Bump MODULE_MINOR alongside the lib MINOR whenever
-- this file's behavior changes; otherwise it can stay as-is across releases.
local MODULE_MINOR = 14
lib._modules = lib._modules or {}
if (lib._modules.Sections or 0) >= MODULE_MINOR then return end
lib._modules.Sections = MODULE_MINOR

local HEADER_PAD_VERT = 6   -- extra height above + below header text
local HEADER_PAD_LEFT = 4
local CONTENT_INSET   = 8   -- left/right inset for content frame
local CONTENT_PAD_TOP = 4   -- gap between header bottom and content top
local CONTENT_PAD_BOT = 6   -- gap below content (so stacked sections breathe)

-- Compute header height from current font.
local function headerHeightFor(titleFs)
  return math.max(titleFs:GetStringHeight() + HEADER_PAD_VERT * 2, 22)
end

-- Returns a frame that wraps a clickable header + content area. Public surface:
--   section.content          : Frame for body widgets
--   section:SetCollapsed(b)
--   section:IsCollapsed()
--   section:SetContentHeight(h)        — static: stash a fixed height
--   section:SetContentHeightFn(fn)     — dynamic: call fn() on every layout
--                                        pass. Use this when the body is a
--                                        wrapping FontString whose
--                                        :GetStringHeight() only settles to
--                                        the wrapped value after WoW has
--                                        rendered the frame at least once.
--   section:GetConsumedHeight()
--
-- opts:
--   title            string — header label  (required)
--   summary          string — dim subtitle to the right of the title
--   width            number — section width; defaults to parent width
--   startCollapsed   bool   — initial state; default false
--   onToggle         fn(c)  — fired only when the user clicks the header
--   onLayoutChanged  fn(h)  — fired whenever the section's consumed height
--                             changes (toggle, font reflow, SetContentHeight,
--                             contentHeightFn re-read, post-show settle).
--                             Use this when the caller owns a sibling stack
--                             that needs reflowing.
--   contentHeightFn  fn()→n — convenience: same as calling
--                             SetContentHeightFn(fn) after construction.
function lib:CreateCollapsibleSection(parent, opts)
  assert(type(opts) == "table" and opts.title, "CreateCollapsibleSection: opts.title required")
  local T = self.Theme

  local section = CreateFrame("Frame", nil, parent, "BackdropTemplate")
  if opts.width then section:SetWidth(opts.width) else section:SetWidth(parent:GetWidth()) end
  section:SetHeight(24)

  -- Clickable header
  local header = CreateFrame("Button", nil, section)
  header:SetPoint("TOPLEFT")
  header:SetPoint("TOPRIGHT")

  local hover = header:CreateTexture(nil, "BACKGROUND")
  hover:SetAllPoints()
  hover:SetColorTexture(unpack(T.rowHover))
  hover:Hide()
  header:SetScript("OnEnter", function() hover:Show() end)
  header:SetScript("OnLeave", function() hover:Hide() end)

  -- Arrow indicator. WoW's default fonts don't include the Unicode
  -- Geometric-Shapes block (▶ ▼ render as boxes); the registered chevron
  -- icons resolve to working atlases.
  local arrow = header:CreateTexture(nil, "OVERLAY")
  arrow:SetSize(10, 10)
  arrow:SetPoint("LEFT", HEADER_PAD_LEFT + 2, 0)
  arrow:SetVertexColor(unpack(T.gold))

  local titleFs = header:CreateFontString(nil, "OVERLAY")
  titleFs:SetFontObject(self:GetFont("normal") or "GameFontNormal")
  titleFs:SetPoint("LEFT", arrow, "RIGHT", 4, 0)
  titleFs:SetTextColor(unpack(T.text))
  titleFs:SetText(opts.title)

  local summaryFs
  if opts.summary then
    summaryFs = header:CreateFontString(nil, "OVERLAY")
    summaryFs:SetFontObject(self:GetFont("small") or "GameFontDisableSmall")
    summaryFs:SetPoint("LEFT", titleFs, "RIGHT", 12, 0)
    summaryFs:SetPoint("RIGHT", -HEADER_PAD_LEFT, 0)
    summaryFs:SetJustifyH("LEFT")
    summaryFs:SetTextColor(unpack(T.textDim))
    summaryFs:SetText(opts.summary)
  end

  -- Content frame (caller populates)
  local content = CreateFrame("Frame", nil, section)
  content:SetPoint("TOPLEFT", header, "BOTTOMLEFT", CONTENT_INSET, 0)
  content:SetPoint("TOPRIGHT", header, "BOTTOMRIGHT", -CONTENT_INSET, 0)
  content:SetHeight(0)
  section.content = content

  -- Internal state
  local collapsed       = opts.startCollapsed and true or false
  local contentHeight   = 0                       -- static height (legacy API)
  local contentHeightFn = opts.contentHeightFn    -- dynamic height (preferred)
  local settlePending   = false

  local function refreshArrow()
    self:ApplyIcon(arrow, collapsed and "chevron-right" or "chevron-down")
  end

  -- Effective content height. When the caller has registered a heightFn we
  -- always call it fresh — this is critical for wrapping-text bodies whose
  -- :GetStringHeight() doesn't return the wrapped value until WoW has
  -- rendered the frame at least once. The static `contentHeight` remains
  -- as a fallback for callers using SetContentHeight directly.
  local function effectiveContentHeight()
    if contentHeightFn then
      local h = tonumber(contentHeightFn()) or 0
      return math.max(0, h)
    end
    return contentHeight
  end

  -- Compute the section's full consumed height from current internal state.
  -- Used both for SetHeight in applyLayout and for the public getter so
  -- callers always read the most recent value without depending on a
  -- separate layout pass to settle :GetHeight().
  local function computeConsumedHeight()
    local hH   = headerHeightFor(titleFs)
    local effH = effectiveContentHeight()
    if collapsed or effH <= 0 then
      return hH
    else
      return hH + CONTENT_PAD_TOP + effH + CONTENT_PAD_BOT
    end
  end

  -- Re-entrancy guard. onLayoutChanged callers commonly relayout siblings,
  -- which can call SetContentHeight again from inside this function. Without
  -- the guard the callback chain recurses without bound.
  local applying = false
  local function applyLayout()
    if applying then return end
    applying = true

    local hH   = headerHeightFor(titleFs)
    local effH = effectiveContentHeight()
    header:SetHeight(hH)

    if collapsed or effH <= 0 then
      content:Hide()
      section:SetHeight(hH)
    else
      content:Show()
      content:ClearAllPoints()
      content:SetPoint("TOPLEFT", header, "BOTTOMLEFT", CONTENT_INSET, -CONTENT_PAD_TOP)
      content:SetPoint("TOPRIGHT", header, "BOTTOMRIGHT", -CONTENT_INSET, -CONTENT_PAD_TOP)
      content:SetHeight(effH)
      section:SetHeight(hH + CONTENT_PAD_TOP + effH + CONTENT_PAD_BOT)
    end
    refreshArrow()

    -- Settle pass: when content has just been (or is currently) shown, WoW
    -- may not have measured wrapped FontString heights yet. Schedule a
    -- one-shot OnUpdate to re-run applyLayout on the next render tick;
    -- with contentHeightFn the re-run will pick up the settled value and
    -- resize the section accordingly. settlePending is reset AFTER the
    -- re-applyLayout to avoid scheduling a second settle from inside the
    -- first one.
    applying = false
    if not collapsed and effH > 0 and not settlePending and contentHeightFn then
      settlePending = true
      section:SetScript("OnUpdate", function(self)
        self:SetScript("OnUpdate", nil)
        applyLayout()
        settlePending = false
      end)
    end
    if opts.onLayoutChanged then opts.onLayoutChanged(computeConsumedHeight()) end
  end

  function section:SetCollapsed(b)
    b = b and true or false
    if b == collapsed then return end
    collapsed = b
    applyLayout()
    if opts.onToggle then opts.onToggle(collapsed) end
  end

  function section:IsCollapsed()
    return collapsed
  end

  function section:SetContentHeight(h)
    local newH = math.max(0, tonumber(h) or 0)
    if newH == contentHeight then return end
    contentHeight = newH
    applyLayout()
  end

  function section:SetContentHeightFn(fn)
    contentHeightFn = fn
    applyLayout()
  end

  function section:GetConsumedHeight()
    return computeConsumedHeight()
  end

  header:SetScript("OnClick", function()
    section:SetCollapsed(not collapsed)
  end)

  -- Re-font + relayout when the user changes scale / font. Arrow is a
  -- texture and doesn't need refonting; only the FontString labels do.
  local owner = {}
  self.RegisterCallback(owner, self.Events.SettingsChanged, function(_, key)
    if key == "fontScale" or key == "fontFamily" then
      titleFs:SetFontObject(self:GetFont("normal") or "GameFontNormal")
      if summaryFs then
        summaryFs:SetFontObject(self:GetFont("small") or "GameFontDisableSmall")
      end
      applyLayout()
    end
  end)

  applyLayout()
  return section
end
