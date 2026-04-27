-- Cogworks-1.0/Items.lua | Item-key parsing, canonicalization, and matching helpers.
--
-- Lifted from FlipQueue's Core.lua so all suite cogs share one canonical
-- implementation. Two consumers in mind today: FlipQueue (auction posting,
-- ledger reconciliation) and Tally (cross-source dedup of sales / inventory
-- / log entries).
--
-- Inventory coupling is parameterized — ResolveItemID and ItemsMatch take an
-- optional lookupByName(searchNameLower) callback so callers pass whatever
-- inventory shape they have on hand. Cogworks stays Syndicator-optional and
-- doesn't reach into any cog's data layer.

local lib = LibStub("Cogworks-1.0")
if not lib then return end

-- ============================================================================
-- Item key construction
-- ============================================================================
-- All suite cogs use FlippingPal's "itemID;bonusIDs;modifiers" key shape so
-- cross-cog item lookups (FlipQueue ledger ↔ Tally research ↔ Maxcraft
-- crafting reagents) compare the same identifier.

function lib:MakeItemKey(itemID, bonusIDs, modifiers)
  return string.format("%s;%s;%s", tostring(itemID), bonusIDs or "", modifiers or "")
end

-- Parse a WoW item link into (itemID, bonusIDs, modifiers) for MakeItemKey.
-- Battle pets return ("pet:<speciesID>", "q<quality>", ""). Returns nil on
-- malformed input so callers can guard.
function lib:ParseItemLink(itemLink)
  if not itemLink then return nil end

  local speciesID = itemLink:match("|Hbattlepet:(%d+)")
  if speciesID then
    local petQuality = itemLink:match("|Hbattlepet:%d+:%d+:(%d+)")
    return "pet:" .. speciesID, "q" .. (petQuality or "0"), ""
  end

  local itemString = itemLink:match("item[%-?%d:]+")
  if not itemString then return nil end

  local parts = { strsplit(":", itemString) }
  local itemID = parts[2]
  if not itemID or itemID == "" then return nil end

  local bonusIDs = ""
  local modifiers = ""

  if #parts >= 14 then
    local numBonusIDs = tonumber(parts[14]) or 0
    local bonusList = {}
    for i = 1, numBonusIDs do
      local bid = parts[14 + i]
      if bid and bid ~= "" then
        table.insert(bonusList, bid)
      end
    end
    bonusIDs = table.concat(bonusList, ":")

    local modStart = 14 + numBonusIDs + 1
    if #parts >= modStart then
      local numMods = tonumber(parts[modStart]) or 0
      local modList = {}
      for i = 1, numMods do
        local mType = parts[modStart + (i * 2) - 1]
        local mVal  = parts[modStart + (i * 2)]
        -- Modifier 9 is item level — the only one that disambiguates posting variants
        if mType and mVal and mType ~= "" and mVal ~= "" and mType == "9" then
          table.insert(modList, mType .. "=" .. mVal)
        end
      end
      modifiers = table.concat(modList, ":")
    end
  end

  return itemID, bonusIDs, modifiers
end

-- Convert an itemKey ("itemID;bonusIDs;modifiers") to a WoW item string
-- suitable for GameTooltip:SetHyperlink. Returns nil for pet keys (use the
-- battlepet link directly) and for malformed input.
function lib:ItemKeyToItemString(itemKey)
  if not itemKey or itemKey == "" then return nil end
  if itemKey:find("^pet:") then return nil end

  local idStr, bonusStr, modStr = strsplit(";", itemKey)
  local numID = tonumber(idStr)
  if not numID or numID <= 0 then return nil end

  -- WoW item-string layout: item:id:enchant:gem1:gem2:gem3:gem4:suffix:uniqueID:level:specID:modType:numBonuses:bonus1:...
  local parts = { "item", idStr, "", "", "", "", "", "", "", "", "", "" }

  if bonusStr and bonusStr ~= "" then
    local bonuses = { strsplit(":", bonusStr) }
    table.insert(parts, tostring(#bonuses))
    for _, b in ipairs(bonuses) do
      table.insert(parts, b)
    end
  else
    table.insert(parts, "0")
  end

  if modStr and modStr ~= "" then
    local mods = { strsplit(":", modStr) }
    table.insert(parts, tostring(#mods))
    for _, m in ipairs(mods) do
      local k, v = m:match("^(%d+)=(%d+)$")
      if k and v then
        table.insert(parts, k)
        table.insert(parts, v)
      end
    end
  end

  return table.concat(parts, ":")
end

-- ============================================================================
-- Item ID resolution and matching
-- ============================================================================

-- Resolve a queue/log item to a numeric itemID.
--
--   queueItem      — { itemID = number|string|nil, name = string|nil, ... }
--   lookupByName   — optional function(searchNameLower) → numericItemID|nil.
--                    Called only when queueItem.itemID is missing/zero.
--                    Caller decides which inventory tables to walk.
--
-- Returns numericItemID or nil.
function lib:ResolveItemID(queueItem, lookupByName)
  local numID = tonumber(queueItem.itemID)
  if numID and numID > 0 then return numID end

  if not lookupByName or not queueItem.name or queueItem.name == "" then return nil end
  return lookupByName(queueItem.name:lower())
end

-- Unified item match between a "scanned/auction" item and a "queue/log" item.
-- Returns (matched: boolean, fuzzy: boolean) — fuzzy is true for any
-- name-based match (Tier 3 or Tier 4) so callers can flag low-confidence hits.
--
--   itemKey       — scanned item's "itemID;bonusIDs;modifiers" key
--   itemName      — scanned item's name
--   queueItem     — { itemKey, itemID, name }
--   resolvedID    — pre-computed lib:ResolveItemID(queueItem, ...) value, or
--                   nil to resolve lazily here. Pass false to explicitly skip
--                   resolution (when caller has already determined no ID is
--                   available).
--   allowFuzzy    — when false, disables Tier 4 substring matching. Default true.
--   lookupByName  — forwarded to ResolveItemID when resolvedID is nil.
--
-- Tier order:
--   1. Exact key match (most precise — bonus IDs + modifiers must match)
--   2. Numeric ID match (queueItem.itemID, then resolved ID via lookupByName)
--   3. Exact name match (case-insensitive, fuzzy=true)
--   4. Substring name match (min 8 chars, recipe-aware: "Recipe: Foo" never
--      fuzzy-matches "Foo"). fuzzy=true.
function lib:ItemsMatch(itemKey, itemName, queueItem, resolvedID, allowFuzzy, lookupByName)
  -- Tier 1: exact key
  if itemKey == queueItem.itemKey then
    return true, false
  end

  -- Tier 2: numeric ID
  local scannedID = itemKey and itemKey:match("^(%d+);")
  local scannedNumID = tonumber(scannedID)
  if scannedNumID and scannedNumID > 0 then
    local queueNumID = tonumber(queueItem.itemID)
    if queueNumID and queueNumID > 0 and scannedNumID == queueNumID then
      return true, false
    end
    -- resolvedID semantics: number = use it, false = caller already checked, nil = resolve now
    local rid = resolvedID
    if rid == nil then rid = self:ResolveItemID(queueItem, lookupByName) end
    if rid and scannedNumID == rid then
      return true, false
    end
  end

  -- Tier 3 & 4: name-based
  if itemName and queueItem.name and queueItem.name ~= "" then
    local sName = itemName:lower()
    local qName = queueItem.name:lower()

    -- Tier 3: exact (case-insensitive)
    if sName == qName then
      return true, true
    end

    -- Tier 4: substring with recipe-prefix guard
    if allowFuzzy ~= false and #queueItem.name >= 8 then
      local sBase = sName:match("^%w+:%s*(.+)$") or sName
      local qBase = qName:match("^%w+:%s*(.+)$") or qName
      if sBase == qBase then
        return true, true
      end
      if sBase:find(qBase, 1, true) or qBase:find(sBase, 1, true) then
        local sHasPrefix = sName:find("^%w+:%s") ~= nil
        local qHasPrefix = qName:find("^%w+:%s") ~= nil
        -- Reject if one side has a prefix and the other doesn't (Recipe: Foo vs Foo)
        if sHasPrefix == qHasPrefix then
          return true, true
        end
      end
    end
  end

  return false, false
end
