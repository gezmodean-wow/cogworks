-- Cogworks-1.0/Realms.lua | Realm-name normalization and connected-realm matching.
--
-- Lifted from FlipQueue's Core.lua so all suite cogs share one normalization
-- and one connected-realm matcher. Two realm names spelled differently — say
-- "Confrérie du Thorium" vs "Confrerie du Thorium" — must collapse to one
-- key so cross-character / cross-realm rollups don't fragment.
--
-- Connected-realm matching consults a caller-supplied lookup table:
--   realmLookup = { [normalizedRealmName] = groupID }
-- The lookup table is caller-side state, not Cogworks-side, until the
-- cross-realm service (issue #2) lands. Callers pass nil to fall back to
-- name-only matching.

local lib = LibStub("Cogworks-1.0")
if not lib then return end

-- Module load guard. See Sections.lua for the rationale.
local MODULE_MINOR = 14
lib._modules = lib._modules or {}
if (lib._modules.Realms or 0) >= MODULE_MINOR then return end
lib._modules.Realms = MODULE_MINOR

-- ============================================================================
-- UTF-8 accent map
-- ============================================================================
-- Multi-byte UTF-8 sequences for Latin diacritics seen in EU WoW realm names
-- (French, German, Spanish, Czech, Polish, etc.). Maps each accented form to
-- its ASCII equivalent for accent-insensitive comparison.

local ACCENT_MAP = {
  -- Latin-1 Supplement (\195 prefix)
  ["\195\160"] = "a", ["\195\161"] = "a", ["\195\162"] = "a", ["\195\163"] = "a",
  ["\195\164"] = "a", ["\195\165"] = "a", -- à á â ã ä å
  ["\195\166"] = "ae",                     -- æ
  ["\195\167"] = "c",                      -- ç
  ["\195\168"] = "e", ["\195\169"] = "e", ["\195\170"] = "e", ["\195\171"] = "e", -- è é ê ë
  ["\195\172"] = "i", ["\195\173"] = "i", ["\195\174"] = "i", ["\195\175"] = "i", -- ì í î ï
  ["\195\176"] = "d",                      -- ð
  ["\195\177"] = "n",                      -- ñ
  ["\195\178"] = "o", ["\195\179"] = "o", ["\195\180"] = "o", ["\195\181"] = "o",
  ["\195\182"] = "o",                      -- ò ó ô õ ö
  ["\195\184"] = "o",                      -- ø
  ["\195\185"] = "u", ["\195\186"] = "u", ["\195\187"] = "u", ["\195\188"] = "u", -- ù ú û ü
  ["\195\189"] = "y", ["\195\190"] = "th", ["\195\191"] = "y", -- ý þ ÿ
  -- Uppercase variants (lowered)
  ["\195\128"] = "a", ["\195\129"] = "a", ["\195\130"] = "a", ["\195\131"] = "a",
  ["\195\132"] = "a", ["\195\133"] = "a", -- À Á Â Ã Ä Å
  ["\195\134"] = "ae",                     -- Æ
  ["\195\135"] = "c",                      -- Ç
  ["\195\136"] = "e", ["\195\137"] = "e", ["\195\138"] = "e", ["\195\139"] = "e", -- È É Ê Ë
  ["\195\140"] = "i", ["\195\141"] = "i", ["\195\142"] = "i", ["\195\143"] = "i", -- Ì Í Î Ï
  ["\195\144"] = "d",                      -- Ð
  ["\195\145"] = "n",                      -- Ñ
  ["\195\146"] = "o", ["\195\147"] = "o", ["\195\148"] = "o", ["\195\149"] = "o",
  ["\195\150"] = "o",                      -- Ò Ó Ô Õ Ö
  ["\195\152"] = "o",                      -- Ø
  ["\195\153"] = "u", ["\195\154"] = "u", ["\195\155"] = "u", ["\195\156"] = "u", -- Ù Ú Û Ü
  ["\195\157"] = "y", ["\195\158"] = "th", ["\195\159"] = "ss", -- Ý Þ ß
  -- Latin Extended-A (\196 / \197 prefixes)
  ["\196\128"] = "a", ["\196\129"] = "a",   -- Ā ā
  ["\196\130"] = "a", ["\196\131"] = "a",   -- Ă ă
  ["\196\132"] = "a", ["\196\133"] = "a",   -- Ą ą
  ["\196\134"] = "c", ["\196\135"] = "c",   -- Ć ć
  ["\196\140"] = "c", ["\196\141"] = "c",   -- Č č
  ["\196\142"] = "d", ["\196\143"] = "d",   -- Ď ď
  ["\196\146"] = "e", ["\196\147"] = "e",   -- Ē ē
  ["\196\152"] = "e", ["\196\153"] = "e",   -- Ę ę
  ["\196\154"] = "e", ["\196\155"] = "e",   -- Ě ě
  ["\196\168"] = "i", ["\196\169"] = "i",   -- Ĩ ĩ
  ["\196\170"] = "i", ["\196\171"] = "i",   -- Ī ī
  ["\196\185"] = "l", ["\196\186"] = "l",   -- Ĺ ĺ
  ["\196\187"] = "l", ["\196\188"] = "l",   -- Ļ ļ
  ["\197\129"] = "l", ["\197\130"] = "l",   -- Ł ł
  ["\197\131"] = "n", ["\197\132"] = "n",   -- Ń ń
  ["\197\135"] = "n", ["\197\136"] = "n",   -- Ň ň
  ["\197\140"] = "o", ["\197\141"] = "o",   -- Ō ō
  ["\197\144"] = "o", ["\197\145"] = "o",   -- Ő ő
  ["\197\146"] = "oe", ["\197\147"] = "oe", -- Œ œ
  ["\197\152"] = "r", ["\197\153"] = "r",   -- Ř ř
  ["\197\154"] = "s", ["\197\155"] = "s",   -- Ś ś
  ["\197\158"] = "s", ["\197\159"] = "s",   -- Ş ş
  ["\197\160"] = "s", ["\197\161"] = "s",   -- Š š
  ["\197\164"] = "t", ["\197\165"] = "t",   -- Ť ť
  ["\197\168"] = "u", ["\197\169"] = "u",   -- Ũ ũ
  ["\197\170"] = "u", ["\197\171"] = "u",   -- Ū ū
  ["\197\174"] = "u", ["\197\175"] = "u",   -- Ů ů
  ["\197\176"] = "u", ["\197\177"] = "u",   -- Ű ű
  ["\197\185"] = "z", ["\197\186"] = "z",   -- Ź ź
  ["\197\187"] = "z", ["\197\188"] = "z",   -- Ż ż
  ["\197\189"] = "z", ["\197\190"] = "z",   -- Ž ž
}

-- ============================================================================
-- Normalization
-- ============================================================================

-- Strip diacritics and lowercase. Idempotent on already-ASCII strings.
function lib:NormalizeAccents(str)
  if not str then return "" end
  return str:gsub("[\195-\197][\128-\191]", ACCENT_MAP):lower()
end

-- Canonical key for grouping a realm: NormalizeAccents wrapped for clarity at
-- call sites. Use this anywhere a realm name is a map key or lookup-table key.
function lib:NormalizeRealmKey(realm)
  return self:NormalizeAccents(realm or "")
end

-- ============================================================================
-- Connected-realm matching
-- ============================================================================

-- Returns true when realmName (a single realm) matches targetRealm (which may
-- be a comma-separated list of names — FlippingPal's connected-realm export
-- shape). Empty targetRealm means "any" and returns true.
--
--   realmLookup — { [normalizedRealmName] = groupID } for connected-realm
--                 group matching. Pass nil to fall back to name-only equality.
function lib:RealmMatches(targetRealm, realmName, realmLookup)
  if not targetRealm or targetRealm == "" then return true end
  if not realmName or realmName == "" then return false end

  local rNorm = self:NormalizeRealmKey(realmName)
  local rGroup = realmLookup and realmLookup[rNorm]

  for name in targetRealm:gmatch("([^,]+)") do
    name = strtrim(name)
    if #name >= 3 and not name:find("^%.+$") then
      local tNorm = self:NormalizeRealmKey(name)
      if tNorm == rNorm then return true end
      if rGroup and realmLookup then
        local tGroup = realmLookup[tNorm]
        if tGroup and tGroup == rGroup then return true end
      end
    end
  end

  return false
end

-- Returns true when realm1 and realm2 share at least one realm-name or
-- connected-realm group. Both args may be comma-separated lists.
function lib:RealmsOverlap(realm1, realm2, realmLookup)
  local r1 = realm1 or ""
  local r2 = realm2 or ""
  if r1 == "" and r2 == "" then return true end
  if r1 == "" or r2 == "" then return false end

  -- Index r2's names + groups for O(1) lookup while scanning r1
  local r2names, r2groups = {}, {}
  for name in r2:gmatch("([^,]+)") do
    name = strtrim(name)
    if #name >= 3 and not name:find("^%.+$") then
      local norm = self:NormalizeRealmKey(name)
      r2names[norm] = true
      if realmLookup then
        local gid = realmLookup[norm]
        if gid then r2groups[gid] = true end
      end
    end
  end

  for name in r1:gmatch("([^,]+)") do
    name = strtrim(name)
    if #name >= 3 and not name:find("^%.+$") then
      local norm = self:NormalizeRealmKey(name)
      if r2names[norm] then return true end
      if realmLookup then
        local gid = realmLookup[norm]
        if gid and r2groups[gid] then return true end
      end
    end
  end

  return false
end
