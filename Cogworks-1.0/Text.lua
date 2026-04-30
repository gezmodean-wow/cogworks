-- Cogworks-1.0/Text.lua | Rich-text helpers (item-quality colors, class
-- colors, gold formatting).
--
-- Generic enough that every cog reaches for the same set: a colored item
-- name in a tooltip, a class-colored character name in a roster, a
-- formatted gold value in a heads-up. Hoisted from FlipQueue's UI/Shared.lua
-- so FlipQueue / Tally / Maxcraft / Tempo all render these the same way.

local lib = LibStub("Cogworks-1.0")
if not lib then return end

-- Module load guard. See Sections.lua for rationale.
local MODULE_MINOR = 15
lib._modules = lib._modules or {}
if (lib._modules.Text or 0) >= MODULE_MINOR then return end
lib._modules.Text = MODULE_MINOR

-- Class-color hex strings (alpha implicit at "ff"). Hand-tuned to match
-- WoW's RAID_CLASS_COLORS without depending on the WoW global being
-- populated yet — these helpers are sometimes called during early load
-- before the class-colors table is final.
local CLASS_HEX = {
  WARRIOR     = "c79c6e",
  PALADIN     = "f58cba",
  HUNTER      = "abd473",
  ROGUE       = "fff569",
  PRIEST      = "ffffff",
  DEATHKNIGHT = "c41f3b",
  SHAMAN      = "0070de",
  MAGE        = "69ccf0",
  WARLOCK     = "9482c9",
  MONK        = "00ff96",
  DRUID       = "ff7d0a",
  DEMONHUNTER = "a330c9",
  EVOKER      = "33937f",
}

-- Quality string → numeric ID for callers that hand us a name.
local QUALITY_NAME_TO_ID = {
  Poor      = 0,
  Common    = 1,
  Uncommon  = 2,
  Rare      = 3,
  Epic      = 4,
  Legendary = 5,
  Artifact  = 6,
  Heirloom  = 7,
}

local function rgbToHex(c)
  return string.format("%02x%02x%02x",
    math.floor((c[1] or 0) * 255 + 0.5),
    math.floor((c[2] or 0) * 255 + 0.5),
    math.floor((c[3] or 0) * 255 + 0.5))
end

-- ============================================================================
-- Item-quality coloring
-- ============================================================================

-- Wrap `name` in WoW color codes for the given quality. `quality` may be
-- a numeric ID (0-7+) or one of the canonical name strings ("Rare",
-- "Epic", ...). Returns the unwrapped name when quality doesn't resolve.
function lib:QualityColorName(name, quality)
  if name == nil then return "" end
  local idx
  if type(quality) == "number" then
    idx = quality
  elseif type(quality) == "string" and quality ~= "" then
    idx = QUALITY_NAME_TO_ID[quality]
  end
  local c = idx and self.Theme.quality[idx]
  if c then
    return "|cff" .. rgbToHex(c) .. tostring(name) .. "|r"
  end
  return tostring(name)
end

-- Hex color string ("rrggbb") for a quality, or nil if unknown. Useful
-- when a caller wants to colorize their own composed string (e.g.
-- "Recipe: |cff<hex><itemName>|r").
function lib:QualityColorHex(quality)
  local idx
  if type(quality) == "number" then
    idx = quality
  elseif type(quality) == "string" and quality ~= "" then
    idx = QUALITY_NAME_TO_ID[quality]
  end
  local c = idx and self.Theme.quality[idx]
  return c and rgbToHex(c) or nil
end

-- ============================================================================
-- Class coloring
-- ============================================================================

-- Hex color string ("rrggbb") for a class, or nil if unknown. Class arg
-- is case-insensitive; canonical form is upper ("WARRIOR", "DEATHKNIGHT").
function lib:ClassColor(class)
  if type(class) ~= "string" or class == "" then return nil end
  return CLASS_HEX[class:upper()]
end

-- Wrap `name` in the class's color code. Returns the unwrapped name when
-- class doesn't resolve.
function lib:ClassColorName(name, class)
  if name == nil then return "" end
  local hex = self:ClassColor(class)
  if hex then
    return "|cff" .. hex .. tostring(name) .. "|r"
  end
  return tostring(name)
end

-- ============================================================================
-- Gold formatting
-- ============================================================================

-- Format a gold value (no copper / silver) as a short readable string.
-- Mirrors FlipQueue's UI/Shared FormatGoldValue: estimates and totals
-- look noisier with fractional gold, so we round down and abbreviate
-- thousands. "" when totalGold is non-positive or nil.
function lib:FormatGoldValue(totalGold)
  if not totalGold or totalGold <= 0 then return "" end
  if totalGold >= 1000 then
    return math.floor(totalGold / 1000) .. "k gold"
  end
  return math.floor(totalGold) .. " gold"
end

-- Format a copper value (`100c = 1s`, `100s = 1g`) as "Ng Ms Kc". Returns
-- "0c" for nil / zero. Useful when the source has copper precision and
-- the caller wants the full breakdown.
function lib:FormatGSC(copper)
  if not copper or copper == 0 then return "0c" end
  copper = math.floor(copper)
  local g = math.floor(copper / 10000)
  local s = math.floor((copper % 10000) / 100)
  local c = copper % 100
  local out = {}
  if g > 0 then out[#out + 1] = g .. "g" end
  if s > 0 then out[#out + 1] = s .. "s" end
  if c > 0 or #out == 0 then out[#out + 1] = c .. "c" end
  return table.concat(out, " ")
end

-- Format a copper value as a short abbreviated gold string: "12.5k",
-- "1.2m", "13g". One decimal of precision past the suffix; bare integer
-- below 1k. Useful for tight UI cells where space is at a premium.
function lib:FormatGoldShort(copper)
  if not copper or copper <= 0 then return "0g" end
  local gold = copper / 10000
  if gold >= 1e6 then return string.format("%.1fm", gold / 1e6) end
  if gold >= 1e3 then return string.format("%.1fk", gold / 1e3) end
  return string.format("%dg", math.floor(gold))
end
