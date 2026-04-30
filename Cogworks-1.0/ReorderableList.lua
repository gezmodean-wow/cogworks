-- Cogworks-1.0/ReorderableList.lua | Vertical drag-to-reorder list.
--
-- Row-pool + drag-drop primitive. Each row is anchored at a y-cursor
-- derived from its index; on drag the held row follows the cursor and
-- the other rows shift to make room; on release the items array is
-- spliced and onReorder fires.
--
-- Caller owns row content via opts.renderRow(row, item, index): the lib
-- creates a Frame, hands it back, and the caller populates it however it
-- likes. Re-renders re-call renderRow for each row, so call SetItems /
-- Refresh after external mutation to update the display.
--
-- Usage:
--
--   local list = cw:CreateReorderableList(parent, {
--     items     = { "Foo", "Bar", "Baz" },  -- caller-side array of opaque items
--     rowHeight = 24,
--     gap       = 2,
--     renderRow = function(row, item, index)
--       row.label = row.label or row:CreateFontString(nil, "OVERLAY")
--       row.label:SetFontObject(cw.Fonts.normal)
--       row.label:SetPoint("LEFT", row, "LEFT", 8, 0)
--       row.label:SetText(index .. ". " .. tostring(item))
--     end,
--     onReorder = function(items, fromIndex, toIndex) ... end,
--   })
--   list:SetItems(newItems)
--   list:GetItems()
--   list:Refresh()                          -- re-render without changing items
--
-- The row passed to renderRow is reused across renders, so cache child
-- widgets on the row (`row.label = row.label or row:CreateFontString(...)`)
-- to avoid re-creating frames on every refresh.

local lib = LibStub("Cogworks-1.0")
if not lib then return end

-- Module load guard. See Sections.lua for rationale.
local MODULE_MINOR = 15
lib._modules = lib._modules or {}
if (lib._modules.ReorderableList or 0) >= MODULE_MINOR then return end
lib._modules.ReorderableList = MODULE_MINOR

local DEFAULT_ROW_HEIGHT = 24
local DEFAULT_GAP        = 2

function lib:CreateReorderableList(parent, opts)
  opts = opts or {}
  assert(type(opts.renderRow) == "function",
    "CreateReorderableList: opts.renderRow required")
  local T         = self.Theme
  local rowHeight = opts.rowHeight or DEFAULT_ROW_HEIGHT
  local gap       = opts.gap or DEFAULT_GAP
  local stride    = rowHeight + gap

  local list = CreateFrame("Frame", nil, parent)

  -- Scroll
  local scroll = CreateFrame("ScrollFrame", nil, list)
  scroll:SetPoint("TOPLEFT", list, "TOPLEFT", 0, 0)
  scroll:SetPoint("BOTTOMRIGHT", list, "BOTTOMRIGHT", -8, 0)

  local content = CreateFrame("Frame", nil, scroll)
  content:SetWidth(1)
  content:SetHeight(1)
  scroll:SetScrollChild(content)
  scroll:EnableMouseWheel(true)
  scroll:SetScript("OnMouseWheel", function(sf, delta)
    local range = math.max(0, content:GetHeight() - sf:GetHeight())
    local cur = sf:GetVerticalScroll()
    sf:SetVerticalScroll(math.max(0, math.min(range, cur - delta * stride)))
  end)

  -- ---- State ------------------------------------------------------------
  local items   = opts.items or {}
  local rows    = {}            -- index → row frame (slot)
  local rowPool = {}
  local dragging                -- { fromIndex, toIndex, row }

  local function acquireRow()
    local row = table.remove(rowPool)
    if row then row:Show(); return row end

    row = CreateFrame("Frame", nil, content, "BackdropTemplate")
    row:SetHeight(rowHeight)
    row:SetBackdrop(lib.BackdropSmall)
    row:SetBackdropColor(0.10, 0.10, 0.13, 0.6)
    row:SetBackdropBorderColor(unpack(T.border))

    -- Drag handle on the left edge — entire row is also draggable, but
    -- the visual hint helps users discover the gesture.
    row.handle = row:CreateTexture(nil, "OVERLAY")
    row.handle:SetSize(8, rowHeight - 6)
    row.handle:SetPoint("LEFT", row, "LEFT", 4, 0)
    row.handle:SetColorTexture(T.brass[1], T.brass[2], T.brass[3], 0.4)

    row:EnableMouse(true)
    row:RegisterForDrag("LeftButton")
    return row
  end

  local function releaseRow(row)
    row:Hide()
    row:ClearAllPoints()
    row:SetScript("OnDragStart", nil)
    row:SetScript("OnDragStop", nil)
    row:SetScript("OnUpdate", nil)
    rowPool[#rowPool + 1] = row
  end

  local function indexFromY(y)
    -- Convert a cursor-relative content-y into the nearest slot index.
    -- Items are at y = (i-1) * stride .. i * stride - gap.
    local idx = math.floor(y / stride) + 1
    if idx < 1 then return 1 end
    if idx > #items then return #items end
    return idx
  end

  -- ---- Render -----------------------------------------------------------
  local function anchorRow(row, index)
    row:ClearAllPoints()
    row:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -((index - 1) * stride))
    row:SetPoint("RIGHT", content, "RIGHT", 0, 0)
  end

  local function refresh()
    -- Release all current rows, rebuild slots in order.
    for i, r in pairs(rows) do
      releaseRow(r)
      rows[i] = nil
    end

    for i, item in ipairs(items) do
      local row = acquireRow()
      rows[i] = row
      anchorRow(row, i)
      opts.renderRow(row, item, i)

      -- Drag handlers
      row:SetScript("OnDragStart", function(r)
        dragging = { fromIndex = i, toIndex = i, row = r }
        r:SetFrameStrata("HIGH")
        r:StartMoving()
        r:SetBackdropBorderColor(unpack(T.gold))
        r:SetScript("OnUpdate", function(self)
          -- Track the cursor's content-y to drive the drop target.
          local cursorX, cursorY = GetCursorPosition()
          local scale = content:GetEffectiveScale()
          local contentTop = content:GetTop() or 0
          local relY = (contentTop - cursorY / scale)
          local target = indexFromY(relY)
          if target ~= dragging.toIndex then
            dragging.toIndex = target
            -- Re-anchor sibling rows so they shift around the dragged row.
            for j = 1, #items do
              if j ~= dragging.fromIndex then
                local visualIndex = j
                if dragging.fromIndex < dragging.toIndex then
                  if j > dragging.fromIndex and j <= dragging.toIndex then
                    visualIndex = j - 1
                  end
                else
                  if j < dragging.fromIndex and j >= dragging.toIndex then
                    visualIndex = j + 1
                  end
                end
                anchorRow(rows[j], visualIndex)
              end
            end
          end
        end)
      end)

      row:SetScript("OnDragStop", function(r)
        r:StopMovingOrSizing()
        r:SetFrameStrata("MEDIUM")
        r:SetBackdropBorderColor(unpack(T.border))
        r:SetScript("OnUpdate", nil)

        local from, to = dragging.fromIndex, dragging.toIndex
        dragging = nil
        if from ~= to then
          local moved = table.remove(items, from)
          table.insert(items, to, moved)
          if opts.onReorder then opts.onReorder(items, from, to) end
        end
        refresh()
      end)
    end

    content:SetHeight(math.max(1, #items * stride))
  end

  -- ---- Public API --------------------------------------------------------
  function list:SetItems(newItems)
    items = newItems or {}
    refresh()
  end

  function list:GetItems()
    return items
  end

  function list:Refresh()
    refresh()
  end

  refresh()
  return list
end
