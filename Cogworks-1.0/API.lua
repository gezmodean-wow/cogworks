-- Cogworks-1.0/API.lua | Versioned cross-cog API registry.
--
-- Lets a cog publish a typed public API surface that other cogs can call
-- synchronously. Solves what the event bus can't: events are fire-and-forget
-- and don't return values. Tally → FlipQueue research migration, FlipQueue
-- → Tally ledger reads, Tempo's reset-math contract — all the same shape.
--
-- Semantics mirror LibStub: a producer registers (name, major, minor, api);
-- a consumer requests (name, atLeast = { major, minor }); major mismatch or
-- minor consumer-ahead-of-producer returns nil. Multiple majors of the same
-- name can coexist for transition windows.
--
-- Usage:
--   -- Producer (Tally), once its API surface is built:
--   cw:RegisterAPI("Tally", {
--     major = 1, minor = 0,
--     api = { GetItemResearch = function(key) ... end, ... },
--   })
--
--   -- Consumer (FlipQueue), at any point after PLAYER_LOGIN:
--   local tally = cw:GetAPI("Tally", { atLeast = { major = 1, minor = 0 } })
--   if tally then research = tally.GetItemResearch(itemKey) end
--
--   -- Consumer that wants to be notified when a producer becomes available:
--   cw:WhenAPIReady("Tally", { atLeast = { major = 1 } }, function(api)
--     ...
--   end)

local lib = LibStub("Cogworks-1.0")
if not lib then return end

-- Ensure the APIRegistered event name exists even if lib.Events was
-- initialized by an older MINOR that didn't list it.
lib.Events = lib.Events or {}
lib.Events.APIRegistered = lib.Events.APIRegistered or "APIRegistered"

-- Registry shape: lib.apis[name][major] = { major, minor, api }
-- Multiple majors per name coexist; minor bumps replace the previous entry
-- at that major.
lib.apis = lib.apis or {}

-- ============================================================================
-- Producer
-- ============================================================================

-- Register a public API surface for `name` at `major.minor`.
-- Calling again with the same major REPLACES the previous registration at
-- that major (use this to publish a minor bump). Different majors coexist —
-- a producer in transition can register both `major = 1` and `major = 2`
-- side-by-side until consumers migrate.
--
-- Fires the APIRegistered event with (name, major, minor) so consumers that
-- registered before the producer can react.
function lib:RegisterAPI(name, info)
  assert(type(name) == "string" and name ~= "", "RegisterAPI: name required")
  assert(type(info) == "table", "RegisterAPI: info table required")
  local major = tonumber(info.major)
  local minor = tonumber(info.minor) or 0
  assert(major and major >= 0, "RegisterAPI: info.major required (non-negative number)")
  assert(type(info.api) == "table", "RegisterAPI: info.api table required")

  self.apis[name] = self.apis[name] or {}
  self.apis[name][major] = { major = major, minor = minor, api = info.api }
  self:Fire(self.Events.APIRegistered, name, major, minor)
end

-- ============================================================================
-- Consumer
-- ============================================================================

-- Find the highest-major entry in a registry table.
local function highestMajorEntry(registry)
  local bestEntry, bestMajor = nil, -1
  for major, entry in pairs(registry) do
    if major > bestMajor then
      bestMajor = major
      bestEntry = entry
    end
  end
  return bestEntry
end

-- Fetch a registered API surface.
--
--   opts.atLeast = { major = N, minor = M }
--     Selects the entry registered at major N and requires minor >= M.
--     Major mismatch → nil. Minor consumer-ahead-of-producer → nil.
--
--   opts omitted (or { atLeast = nil }):
--     Returns the API of the highest registered major. Useful for
--     diagnostics and About panels; consumers calling into the API should
--     always pin a major via opts.atLeast so a future major bump doesn't
--     silently change the contract under them.
--
-- Returns the api table directly (not the registry record), or nil.
function lib:GetAPI(name, opts)
  local registry = self.apis[name]
  if not registry then return nil end

  if not opts or not opts.atLeast then
    local entry = highestMajorEntry(registry)
    return entry and entry.api or nil
  end

  local wantMajor = tonumber(opts.atLeast.major) or 0
  local wantMinor = tonumber(opts.atLeast.minor) or 0
  local entry = registry[wantMajor]
  if not entry then return nil end
  if entry.minor < wantMinor then return nil end
  return entry.api
end

-- Run `callback(api)` as soon as an API matching (name, opts) is available.
-- Fires immediately if already registered; otherwise subscribes to
-- APIRegistered and fires on the first matching registration. Auto-cleans
-- up its callback subscription after firing.
--
-- Use this when a consumer doesn't know the load order — Cogworks only
-- guarantees event-bus ordering, not file-load ordering between cogs.
function lib:WhenAPIReady(name, opts, callback)
  assert(type(callback) == "function", "WhenAPIReady: callback required")
  local existing = self:GetAPI(name, opts)
  if existing then
    callback(existing)
    return
  end
  local handle = {}
  self.RegisterCallback(handle, self.Events.APIRegistered, function(_, registeredName)
    if registeredName ~= name then return end
    local api = self:GetAPI(name, opts)
    if api then
      self.UnregisterCallback(handle, self.Events.APIRegistered)
      callback(api)
    end
  end)
end

-- Enumerate every registered (name, major, minor) for diagnostics, About
-- panels, or `/cogworks` debug subcommands.
function lib:GetRegisteredAPIs()
  local list = {}
  for name, registry in pairs(self.apis) do
    for _, entry in pairs(registry) do
      list[#list + 1] = { name = name, major = entry.major, minor = entry.minor }
    end
  end
  table.sort(list, function(a, b)
    if a.name ~= b.name then return a.name < b.name end
    if a.major ~= b.major then return a.major < b.major end
    return a.minor < b.minor
  end)
  return list
end
