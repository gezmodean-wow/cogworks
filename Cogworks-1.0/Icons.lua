-- Cogworks-1.0/Icons.lua | Suite-wide semantic icon registry.
--
-- WoW's default fonts don't include the Unicode Geometric-Shapes block, so
-- glyphs like ▶ ▼ ✓ × render as missing-glyph boxes. Every widget that wants
-- a directional or status indicator hits this once and resolves it inline.
-- The registry hoists that resolution into Cogworks: callers ask for an icon
-- by semantic name and the library picks the known-working representation
-- (atlas, texture + texcoords, ...).
--
-- Usage:
--   local arrow = parent:CreateTexture(nil, "OVERLAY")
--   arrow:SetSize(10, 10)
--   cw:ApplyIcon(arrow, "chevron-right")
--
-- Cogs can register their own:
--   cw:RegisterIcon("fq-quality-rare", { path = "...\\Quality", l = 0, r = 0.25, t = 0, b = 1 })

local lib = LibStub("Cogworks-1.0")
if not lib then return end

lib.icons = lib.icons or {}

-- Built-in registry. Re-running this file on a MINOR bump replaces the
-- definitions, which is what we want for built-ins. Consumer overrides via
-- RegisterIcon happen after addon load, so they're not at risk from this.
lib.icons["chevron-right"] = { atlas = "friendslist-categorybutton-arrow-right" }
lib.icons["chevron-down"]  = { atlas = "friendslist-categorybutton-arrow-down" }

-- Register (or replace) a named icon.
--   def.atlas = "..."                  -- atlas form
--   def.path  = "...", l, r, t, b      -- texture + optional texCoords
function lib:RegisterIcon(name, def)
  assert(type(name) == "string" and name ~= "", "RegisterIcon: name required")
  assert(type(def) == "table" and (def.atlas or def.path), "RegisterIcon: def must have atlas or path")
  self.icons[name] = def
end

-- Apply a registered icon to a Texture region. Returns true on success,
-- false if `name` is not registered (caller can decide whether to fall back).
function lib:ApplyIcon(texture, name)
  local def = self.icons[name]
  if not def then return false end
  if def.atlas then
    texture:SetAtlas(def.atlas, false)
  else
    texture:SetTexture(def.path)
    if def.l or def.r or def.t or def.b then
      texture:SetTexCoord(def.l or 0, def.r or 1, def.t or 0, def.b or 1)
    end
  end
  return true
end

function lib:HasIcon(name)
  return self.icons[name] ~= nil
end
