-- Cogworks-1.0/Tree.lua | Hierarchical tree primitive.
--
-- Expand/collapse rows for nested data (categories with sub-items, item-
-- group hierarchies, profession trees). Each visible node renders as a
-- single row: chevron (only on branches) + label + optional right-aligned
-- count. Click anywhere on the row to select; click the chevron to toggle.
--
-- Non-virtualized for v1 — every node has a row frame whether expanded or
-- collapsed (collapsed branches' children just stay :Hide()'d). If a
-- consumer hits visible-node counts in the multiple-thousands the row
-- pool can be virtualized later; in practice the FlipQueue ResearchPage
-- (the primary consumer) is well under that.
--
-- Usage:
--
--   local tree = cw:CreateTree(parent, {
--     onSelect = function(key, node) ... end,
--     indent   = 18,           -- per-depth indent in pixels (default 18)
--     rowHeight = 22,          -- (default 22)
--   })
--   tree:SetAllPoints()        -- caller sizes the tree
--   tree:SetNodes({
--     { key = "armor", label = "Armor", count = 12, children = {
--       { key = "armor.cloth",   label = "Cloth",   count = 3 },
--       { key = "armor.leather", label = "Leather", count = 4 },
--     }},
--     { key = "weapons", label = "Weapons", count = 8 },
--   })
--   tree:Expand("armor")
--   tree:GetSelected()  -- key of the selected row, or nil
--
-- Each node table is { key (string, required), label (string), count
-- (number|string, optional), children (table of nodes, optional) }.

local lib = LibStub("Cogworks-1.0")
if not lib then return end

-- Module load guard. See Sections.lua for rationale.
local MODULE_MINOR = 16
lib._modules = lib._modules or {}
if (lib._modules.Tree or 0) >= MODULE_MINOR then return end
lib._modules.Tree = MODULE_MINOR

local DEFAULT_INDENT     = 18
local DEFAULT_ROW_HEIGHT = 22
local CHEVRON_SIZE       = 10
local CHEVRON_PAD        = 4

function lib:CreateTree(parent, opts)
  opts = opts or {}
  local T          = self.Theme
  local indent     = opts.indent    or DEFAULT_INDENT
  local rowHeight  = opts.rowHeight or DEFAULT_ROW_HEIGHT

  local tree = CreateFrame("Frame", nil, parent)

  -- Scroll area
  local scroll = CreateFrame("ScrollFrame", nil, tree)
  scroll:SetPoint("TOPLEFT", tree, "TOPLEFT", 0, 0)
  scroll:SetPoint("BOTTOMRIGHT", tree, "BOTTOMRIGHT", -8, 0)

  local content = CreateFrame("Frame", nil, scroll)
  content:SetWidth(1)
  content:SetHeight(1)
  scroll:SetScrollChild(content)

  -- Keep the scroll child's width pinned to the viewport. Without this the
  -- content frame stays at width=1 and rows anchored TOPRIGHT to content
  -- collapse to 1px wide — invisible backdrop, no clickable area.
  scroll:HookScript("OnSizeChanged", function(sf, w, h)
    content:SetWidth(math.max(1, w))
  end)

  scroll:EnableMouseWheel(true)
  scroll:SetScript("OnMouseWheel", function(sf, delta)
    local range = math.max(0, content:GetHeight() - sf:GetHeight())
    local cur = sf:GetVerticalScroll()
    sf:SetVerticalScroll(math.max(0, math.min(range, cur - delta * 30)))
  end)

  -- ---- State ------------------------------------------------------------
  local nodesByKey = {}  -- key → node ref
  local rowsByKey  = {}  -- key → row frame
  local rowPool    = {}  -- pool of row frames
  local rootNodes  = {}
  local expanded   = {}  -- key → true if expanded
  local selected            -- key of selected row

  -- Index every node so callers can address by key in any order.
  local function indexNodes(nodes)
    for _, n in ipairs(nodes) do
      assert(n.key, "CreateTree: each node needs a key")
      nodesByKey[n.key] = n
      if n.children then indexNodes(n.children) end
    end
  end

  local function clearIndex()
    for k in pairs(nodesByKey) do nodesByKey[k] = nil end
    for k in pairs(rowsByKey)  do rowsByKey[k]  = nil end
  end

  -- ---- Row construction --------------------------------------------------
  local function acquireRow()
    local row = table.remove(rowPool)
    if row then row:Show(); return row end

    row = CreateFrame("Button", nil, content)
    row:SetHeight(rowHeight)

    row.bg = row:CreateTexture(nil, "BACKGROUND")
    row.bg:SetAllPoints()
    row.bg:SetColorTexture(1, 1, 1, 0)

    row.chevron = row:CreateTexture(nil, "OVERLAY")
    row.chevron:SetSize(CHEVRON_SIZE, CHEVRON_SIZE)
    row.chevron:SetVertexColor(unpack(T.gold))

    row.label = row:CreateFontString(nil, "OVERLAY")
    row.label:SetFontObject(lib.Fonts.normal)
    row.label:SetTextColor(unpack(T.text))
    row.label:SetJustifyH("LEFT")

    row.count = row:CreateFontString(nil, "OVERLAY")
    row.count:SetFontObject(lib.Fonts.small)
    row.count:SetTextColor(unpack(T.textDim))
    row.count:SetJustifyH("RIGHT")

    return row
  end

  local function releaseRow(row)
    row:Hide()
    row:ClearAllPoints()
    row:SetScript("OnEnter", nil)
    row:SetScript("OnLeave", nil)
    row:SetScript("OnClick", nil)
    table.insert(rowPool, row)
  end

  local function paintRow(row, isSelected)
    if isSelected then
      row.bg:SetColorTexture(T.gold[1], T.gold[2], T.gold[3], 0.18)
      row.label:SetTextColor(unpack(T.text))
    else
      row.bg:SetColorTexture(1, 1, 1, 0)
      row.label:SetTextColor(unpack(T.text))
    end
  end

  -- ---- Layout / render ---------------------------------------------------
  local function setSelected(key)
    if selected == key then return end
    if selected and rowsByKey[selected] then
      paintRow(rowsByKey[selected], false)
    end
    selected = key
    if selected and rowsByKey[selected] then
      paintRow(rowsByKey[selected], true)
    end
    if opts.onSelect then opts.onSelect(key, nodesByKey[key]) end
  end

  -- forward declaration so render can be referenced before definition
  local render

  local function renderNode(node, depth, y)
    local row = acquireRow()
    rowsByKey[node.key] = row

    row:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -y)
    row:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, -y)

    local hasChildren = node.children and #node.children > 0
    local xOff = depth * indent + CHEVRON_PAD

    -- Chevron only when there are children to expand
    if hasChildren then
      row.chevron:Show()
      row.chevron:ClearAllPoints()
      row.chevron:SetPoint("LEFT", row, "LEFT", xOff, 0)
      lib:ApplyIcon(row.chevron, expanded[node.key] and "chevron-down" or "chevron-right")
    else
      row.chevron:Hide()
    end

    row.label:ClearAllPoints()
    row.label:SetPoint("LEFT", row, "LEFT", xOff + CHEVRON_SIZE + 4, 0)
    row.label:SetPoint("RIGHT", row.count, "LEFT", -8, 0)
    row.label:SetText(node.label or node.key)

    row.count:ClearAllPoints()
    row.count:SetPoint("RIGHT", row, "RIGHT", -8, 0)
    if node.count ~= nil then
      row.count:SetText(tostring(node.count))
      row.count:Show()
    else
      row.count:Hide()
    end

    paintRow(row, selected == node.key)

    row:SetScript("OnEnter", function(r)
      if selected ~= node.key then r.bg:SetColorTexture(unpack(T.rowHover)) end
    end)
    row:SetScript("OnLeave", function(r)
      paintRow(r, selected == node.key)
    end)
    row:SetScript("OnClick", function(_, button)
      -- Toggle when clicking the chevron half of the row; select otherwise.
      -- Approximation: clicks within `chevronZone` pixels of the left edge
      -- of the chevron toggle expansion; everything else selects.
      local mouseX = GetCursorPosition()
      local rowLeft = row:GetLeft() or 0
      local effectiveScale = row:GetEffectiveScale()
      local relX = (mouseX / effectiveScale) - rowLeft
      local chevronZone = xOff + CHEVRON_SIZE + 4
      if hasChildren and relX <= chevronZone then
        if expanded[node.key] then
          expanded[node.key] = nil
        else
          expanded[node.key] = true
        end
        render()
      else
        setSelected(node.key)
      end
    end)

    y = y + rowHeight
    if hasChildren and expanded[node.key] then
      for _, child in ipairs(node.children) do
        y = renderNode(child, depth + 1, y)
      end
    end
    return y
  end

  -- Hide all currently-visible rows back to the pool, then render the
  -- visible subtree fresh. Cheap as long as visible-row count stays
  -- under a few hundred — the row pool keeps allocation flat.
  render = function()
    for _, row in pairs(rowsByKey) do
      releaseRow(row)
    end
    for k in pairs(rowsByKey) do rowsByKey[k] = nil end

    local y = 0
    for _, n in ipairs(rootNodes) do
      y = renderNode(n, 0, y)
    end
    content:SetHeight(math.max(1, y))
  end

  -- ---- Public API --------------------------------------------------------
  function tree:SetNodes(nodes)
    clearIndex()
    rootNodes = nodes or {}
    indexNodes(rootNodes)
    render()
  end

  function tree:GetNodes()
    return rootNodes
  end

  function tree:Expand(key)
    if not nodesByKey[key] then return end
    if expanded[key] then return end
    expanded[key] = true
    render()
  end

  function tree:Collapse(key)
    if not expanded[key] then return end
    expanded[key] = nil
    render()
  end

  function tree:Toggle(key)
    if expanded[key] then expanded[key] = nil else expanded[key] = true end
    render()
  end

  function tree:IsExpanded(key)
    return expanded[key] and true or false
  end

  function tree:ExpandAll()
    for k, n in pairs(nodesByKey) do
      if n.children and #n.children > 0 then expanded[k] = true end
    end
    render()
  end

  function tree:CollapseAll()
    for k in pairs(expanded) do expanded[k] = nil end
    render()
  end

  function tree:SetSelected(key) setSelected(key) end
  function tree:GetSelected()    return selected end

  -- Initial render with whatever was passed in opts.
  if opts.rootNodes then tree:SetNodes(opts.rootNodes) end

  return tree
end
