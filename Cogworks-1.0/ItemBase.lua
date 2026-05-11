-- Cogworks-1.0/ItemBase.lua | Bundled name -> itemID + metadata cache.
--
-- Closes the gap left by C_Item.GetItemInfo when the live WoW client has never
-- cached an item the player is trying to import (FlippingPal exports, TSM
-- group dumps, PBS lists, etc.). The static cache is regenerated from
-- Blizzard's Game Data API per major-patch cycle by tools/generate-item-base.py
-- and shipped as Data/ItemBase-Generated-<locale>.lua.
--
-- Loading strategy:
--   * The data file is a ~3 MB Lua table. We do NOT parse it at addon load —
--     none of the cogs should pay that cost unless they actually call into
--     this module. First call to ResolveName / GetItem / Load triggers a
--     one-shot LoadAddOn / require-style eval; subsequent calls are O(1).
--   * In-memory after the first parse. No on-demand re-reads.
--   * All methods are nil/false safe when the data file is absent (nolib
--     path, partial install, locale fallback miss). Consumers can call them
--     unguarded and just check the return.
--
-- Usage:
--   local cw = LibStub("Cogworks-1.0", true)
--   if not cw or not cw.ItemBase then return end
--
--   local itemID, meta = cw.ItemBase:ResolveName("Crimson Combatant's Necklace")
--   local meta         = cw.ItemBase:GetItem(12345)
--   local resolutions  = cw.ItemBase:ResolveNames({ "Item A", "Item B" })
--
--   if cw.ItemBase:IsAvailable() then ... end
--   cw.ItemBase:OnReady(function() refreshUI() end)

local lib = LibStub("Cogworks-1.0")
if not lib then return end

-- Module load guard. See Sections.lua for the rationale; bump MODULE_MINOR
-- alongside the lib MINOR whenever this file's behavior changes.
local MODULE_MINOR = 1
lib._modules = lib._modules or {}
if (lib._modules.ItemBase or 0) >= MODULE_MINOR then return end
lib._modules.ItemBase = MODULE_MINOR

-- Per-module state. Guard with `or` so re-runs on the same lib don't clobber
-- an already-warm parse.
lib._itemBase = lib._itemBase or {
  loaded      = false,    -- has the lazy parse completed?
  available   = nil,      -- bool cache for IsAvailable; nil until first probe
  data        = nil,      -- the full table from the data file
  readyCbs    = {},       -- pending OnReady callbacks
}

-- Public namespace. `lib.ItemBase` is what consumers reach for.
lib.ItemBase = lib.ItemBase or {}
local ItemBase = lib.ItemBase

-- ----------------------------------------------------------------------------
-- Internal: locate + parse the data file
-- ----------------------------------------------------------------------------

-- The data file (Data/ItemBase-Generated-<locale>.lua) is sourced from the
-- XML manifest right before this loader. WoW's XML script loader doesn't
-- surface a chunk's `return` value, so the data file assigns its table to
-- the well-known global CogworksItemBaseData_<locale>. We probe for the
-- live-locale global first, then fall back to enUS for clients on locales
-- the suite hasn't shipped yet.
--
-- TODO(COG-28): once per-locale data files ship (deDE/frFR/...), extend the
-- manifest to source each one and update DATA_GLOBALS to enumerate them.
-- For the scaffold we ship enUS only.

local function localeGlobals()
  local current = (GetLocale and GetLocale()) or "enUS"
  if current == "enUS" then
    return { "CogworksItemBaseData_enUS" }
  end
  return {
    "CogworksItemBaseData_" .. current,
    "CogworksItemBaseData_enUS",
  }
end

local function locateDataTable()
  for _, name in ipairs(localeGlobals()) do
    local t = _G[name]
    if type(t) == "table" then
      return t
    end
  end
  return nil
end

-- Probe whether the data file shipped (regardless of whether we've parsed it
-- yet). We treat the placeholder file (which sets `version = "placeholder"`)
-- as "not really available" so consumers don't show a stale "item base ready"
-- toast against an empty table.
local function probeAvailable()
  local t = locateDataTable()
  if not t then return false end
  if t.version == "placeholder" then return false end
  if type(t.items) ~= "table" then return false end
  return true
end

local function fireReady()
  local cbs = lib._itemBase.readyCbs
  lib._itemBase.readyCbs = {}
  for _, fn in ipairs(cbs) do
    -- Defensive: a consumer's callback erroring shouldn't strand later ones.
    pcall(fn)
  end
end

-- Force the lazy parse. Idempotent: subsequent calls just return the cached
-- result. Returns true if a usable data table is now resident; false if the
-- data file is absent or only the placeholder shipped.
function ItemBase:Load()
  local state = lib._itemBase
  if state.loaded then
    return state.data ~= nil
  end

  local t = locateDataTable()
  if not t or t.version == "placeholder" or type(t.items) ~= "table" then
    state.loaded    = true
    state.available = false
    state.data      = nil
    return false
  end

  state.data      = t
  state.available = true
  state.loaded    = true
  fireReady()
  return true
end

-- ----------------------------------------------------------------------------
-- Public API
-- ----------------------------------------------------------------------------

-- ResolveName: live client cache wins, static cache fallback.
-- Returns (itemID, meta) or (nil, nil) when neither resolves the name.
function ItemBase:ResolveName(name)
  if type(name) ~= "string" or name == "" then return nil, nil end

  -- Live cache first. C_Item.GetItemInfo accepts a name and returns the
  -- itemID via its second-to-last return on modern clients; older clients
  -- expose the same data via GetItemInfoInstant. We try the modern path
  -- and fall back gracefully.
  if GetItemInfoInstant then
    local liveID = select(1, GetItemInfoInstant(name))
    if type(liveID) == "number" and liveID > 0 then
      local meta = self:GetItem(liveID)
      return liveID, meta
    end
  end

  -- Static cache.
  if not self:Load() then return nil, nil end
  local data = lib._itemBase.data
  local byName = data and data.byName
  if type(byName) ~= "table" then return nil, nil end
  local id = byName[string.lower(name)]
  if not id then return nil, nil end
  return id, data.items and data.items[id] or nil
end

-- GetItem: itemID -> metadata. Static cache only; does not consult the live
-- client cache (callers that already have an itemID are usually after the
-- canonical bundled metadata, not whatever the live cache happened to have
-- warmed up).
function ItemBase:GetItem(itemID)
  if type(itemID) ~= "number" then return nil end
  if not self:Load() then return nil end
  local data = lib._itemBase.data
  if not data or type(data.items) ~= "table" then return nil end
  return data.items[itemID]
end

-- ResolveNames: bulk variant of ResolveName for import flows. Returns a
-- parallel array of { itemID, meta } entries, or `false` for unresolved
-- positions (using `false` instead of nil keeps array length stable for
-- consumers that iterate with ipairs).
function ItemBase:ResolveNames(names)
  if type(names) ~= "table" then return {} end
  local out = {}
  for i = 1, #names do
    local id, meta = self:ResolveName(names[i])
    if id then
      out[i] = { itemID = id, meta = meta }
    else
      out[i] = false
    end
  end
  return out
end

-- IsAvailable: does a non-placeholder data file exist? Cheap probe; safe to
-- call before Load(). Cogs use this to decide whether to surface "Item base
-- ready" UI affordances.
function ItemBase:IsAvailable()
  local state = lib._itemBase
  if state.available == nil then
    state.available = probeAvailable()
  end
  return state.available
end

-- IsLoaded: has the lazy parse already happened? (Distinct from IsAvailable,
-- which just checks file presence.)
function ItemBase:IsLoaded()
  return lib._itemBase.loaded == true
end

-- Version: WoW build + ISO-8601 generation timestamp from the data file, or
-- nil when the data file is absent. Cogs surface this on About panels.
function ItemBase:Version()
  if not self:Load() then return nil, nil end
  local data = lib._itemBase.data
  if not data then return nil, nil end
  return data.version, data.generatedAt
end

-- Stats: { items = N, byName = N, locale = "enUS" } for diagnostic surfaces.
-- Returns nil when the data file is absent so callers can branch cleanly.
function ItemBase:Stats()
  if not self:Load() then return nil end
  local data = lib._itemBase.data
  if not data then return nil end
  local nItems, nByName = 0, 0
  if type(data.items) == "table" then
    for _ in pairs(data.items) do nItems = nItems + 1 end
  end
  if type(data.byName) == "table" then
    for _ in pairs(data.byName) do nByName = nByName + 1 end
  end
  return {
    items  = nItems,
    byName = nByName,
    locale = data.locale,
  }
end

-- OnReady: fire `cb` once the lazy parse completes successfully. If the data
-- file is already loaded (or already known absent), the callback fires right
-- away — synchronously when loaded, never when absent (we don't fire failure
-- callbacks; consumers should pair OnReady with IsAvailable for that signal).
function ItemBase:OnReady(cb)
  if type(cb) ~= "function" then return end
  if lib._itemBase.loaded then
    if lib._itemBase.data then
      pcall(cb)
    end
    return
  end
  table.insert(lib._itemBase.readyCbs, cb)
end
