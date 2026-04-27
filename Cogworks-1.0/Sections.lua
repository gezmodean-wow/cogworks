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
--   section.content        : Frame for body widgets
--   section:SetCollapsed(b)
--   section:IsCollapsed()
--   section:SetContentHeight(h) — call after laying out children
--   section:GetConsumedHeight()
--
-- opts:
--   title          string (required) — header label
--   summary        string (optional) — dim subtitle to the right of the title
--   width          number (optional) — section width; defaults to parent width
--   startCollapsed bool   (optional) — initial state; default false
--   onToggle       func   (optional) — called with the new collapsed bool
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
  -- Geometric-Shapes block (▶ ▼ render as boxes), so use texture atlases.
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
  local collapsed = opts.startCollapsed and true or false
  local contentHeight = 0

  local function refreshArrow()
    arrow:SetAtlas(collapsed and "friendslist-categorybutton-arrow-right"
                              or "friendslist-categorybutton-arrow-down", false)
  end

  local function applyLayout()
    local hH = headerHeightFor(titleFs)
    header:SetHeight(hH)

    if collapsed or contentHeight <= 0 then
      content:Hide()
      section:SetHeight(hH)
    else
      content:Show()
      content:ClearAllPoints()
      content:SetPoint("TOPLEFT", header, "BOTTOMLEFT", CONTENT_INSET, -CONTENT_PAD_TOP)
      content:SetPoint("TOPRIGHT", header, "BOTTOMRIGHT", -CONTENT_INSET, -CONTENT_PAD_TOP)
      content:SetHeight(contentHeight)
      section:SetHeight(hH + CONTENT_PAD_TOP + contentHeight + CONTENT_PAD_BOT)
    end
    refreshArrow()
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
    contentHeight = math.max(0, tonumber(h) or 0)
    applyLayout()
  end

  function section:GetConsumedHeight()
    return section:GetHeight()
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
