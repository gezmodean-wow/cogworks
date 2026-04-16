-- Cogworks-1.0 | The mainspring of the Cogworks WoW addon suite.
--
-- An embeddable LibStub library providing the primitives shared across every
-- cog: event bus, theme palette, character-key helpers, print utilities, and
-- a Syndicator capability bridge.
--
-- Design notes:
--   * No Ace3 — built on LibStub + CallbackHandler-1.0, matching the rest of
--     the suite. Both dependencies are already loaded by LibDataBroker in
--     every cog, so Cogworks adds no new library cost.
--   * Additive only. MINOR bumps on every API addition; old functions never
--     go away. A breaking change would force every cog to re-release in
--     lockstep, which is exactly what this library exists to avoid.
--   * Syndicator is a hard dependency for inventory-aware cogs (FlipQueue,
--     Ledger). They declare it in their TOC and consume it directly with no
--     fallback scanner. Character keys follow Syndicator's "Name-Realm"
--     convention so all suite data shares one keyspace.

assert(LibStub, "Cogworks-1.0 requires LibStub")
assert(LibStub:GetLibrary("CallbackHandler-1.0", true), "Cogworks-1.0 requires CallbackHandler-1.0")

local MAJOR, MINOR = "Cogworks-1.0", 2
local lib, oldminor = LibStub:NewLibrary(MAJOR, MINOR)
if not lib then return end  -- already loaded at this version or newer
oldminor = oldminor or 0

-- ============================================================================
-- Version
-- ============================================================================

lib.version      = "0.2.0"   -- human-facing semver of the Cogworks suite
lib.minorVersion = MINOR     -- LibStub minor; bumps on any API addition

-- ============================================================================
-- Event bus
-- ============================================================================
-- A single CallbackHandler-backed registry that any cog can subscribe to.
-- Event names are centralized in lib.Events so typos fail loudly instead of
-- silently registering for an event that never fires.
--
-- Usage:
--   local cw = LibStub("Cogworks-1.0")
--   cw.RegisterCallback(self, cw.Events.SaleLogged, function(event, itemKey, price, qty)
--     -- react to a sale from any other cog
--   end)
--   cw:Fire(cw.Events.SaleLogged, itemKey, price, qty, "FlipQueue")

lib.Events = lib.Events or {
  -- Lifecycle
  Ready            = "Ready",            -- fired once at PLAYER_LOGIN
  AddonRegistered  = "AddonRegistered",  -- (addonName) — a new cog clicked in

  -- Character / account state
  CharacterChanged = "CharacterChanged", -- (charKey)
  GoldChanged      = "GoldChanged",      -- (charKey, newGold, delta)

  -- Inventory signals (typically bridged from Syndicator or FlipQueue's scanner)
  InventoryChanged = "InventoryChanged", -- (charKey, updates)
  MailChanged      = "MailChanged",      -- (charKey)
  AuctionsChanged  = "AuctionsChanged",  -- (charKey)

  -- Suite domain events (cross-cog signalling)
  SaleLogged       = "SaleLogged",       -- (itemKey, price, qty, source)
  CraftCompleted   = "CraftCompleted",   -- (recipeID, charKey)
  ResetDue         = "ResetDue",         -- (period)  -- "daily" / "weekly" / ...
  PriceUpdated     = "PriceUpdated",     -- (itemKey, source, price)
}

if not lib.callbacks then
  local CallbackHandler = LibStub("CallbackHandler-1.0")
  lib.callbacks = CallbackHandler:New(lib, "RegisterCallback", "UnregisterCallback", "UnregisterAllCallbacks")
end

function lib:Fire(event, ...)
  self.callbacks:Fire(event, ...)
end

-- ============================================================================
-- Registered addons (cogs)
-- ============================================================================
-- Each cog registers itself with Cogworks on load. The registry lets any cog
-- enumerate its siblings — useful for an "About" panel or for cross-promotion
-- without any hard dependency between cogs.

lib.addons = lib.addons or {}  -- [name] = { prefix, version, icon, website }

function lib:RegisterAddon(name, info)
  assert(type(name) == "string" and name ~= "", "RegisterAddon: name required")
  info = info or {}
  self.addons[name] = {
    prefix  = info.prefix  or ("|cffffd100[" .. name .. "]|r "),
    version = info.version or "unknown",
    icon    = info.icon,
    website = info.website,
  }
  self:Fire(self.Events.AddonRegistered, name)
end

function lib:GetAddon(name)
  return self.addons[name]
end

function lib:GetRegisteredAddons()
  local list = {}
  for name in pairs(self.addons) do
    list[#list + 1] = name
  end
  table.sort(list)
  return list
end

-- ============================================================================
-- Print helpers
-- ============================================================================

local function joinArgs(...)
  local n = select("#", ...)
  if n == 0 then return "" end
  local parts = {}
  for i = 1, n do
    parts[i] = tostring((select(i, ...)))
  end
  return table.concat(parts, " ")
end

function lib:Print(addonName, ...)
  local info = self.addons[addonName]
  local prefix = (info and info.prefix) or ("|cffffd100[" .. (addonName or "Cogworks") .. "]|r ")
  DEFAULT_CHAT_FRAME:AddMessage(prefix .. joinArgs(...))
end

function lib:PrintError(addonName, ...)
  self:Print(addonName, "|cffff4040" .. joinArgs(...) .. "|r")
end

-- ============================================================================
-- Theme constants
-- ============================================================================
-- The shared visual palette across the suite: dark TSM-style base, gold
-- primary accent, and a subtle arcane-purple highlight reserved for
-- "time magic" moments (reset-soon warnings, profit-surge callouts, etc.).

lib.Theme = lib.Theme or {
  -- Backgrounds
  bg        = { 0.08, 0.08, 0.12, 0.95 },   -- primary dark bg
  bgLight   = { 0.12, 0.12, 0.16, 0.95 },   -- panel bg
  bgDark    = { 0.04, 0.04, 0.07, 1.00 },   -- inset / header bg
  header    = { 0.15, 0.15, 0.20, 1.00 },   -- header / toolbar bg
  sidebar   = { 0.06, 0.06, 0.10, 1.00 },   -- sidebar bg
  border    = { 0.30, 0.30, 0.40, 1.00 },

  -- Row styling (lists / tables)
  rowAlt    = { 1.00, 1.00, 1.00, 0.03 },   -- alternating row tint
  rowHover  = { 1.00, 1.00, 1.00, 0.08 },   -- hovered row highlight

  -- Accents
  gold      = { 1.00, 0.82, 0.00, 1.00 },   -- primary accent
  arcane    = { 0.55, 0.36, 0.96, 1.00 },   -- "time magic" highlight (#8b5cf6)
  brass     = { 0.83, 0.63, 0.09, 1.00 },   -- clockwork trim

  -- Status
  success   = { 0.30, 0.85, 0.30, 1.00 },
  warning   = { 1.00, 0.78, 0.10, 1.00 },
  error     = { 1.00, 0.25, 0.25, 1.00 },

  -- Text
  text      = { 0.90, 0.90, 0.92, 1.00 },
  textDim   = { 0.60, 0.60, 0.60, 1.00 },   -- secondary / label text
  textDisabled = { 0.40, 0.40, 0.40, 1.00 },
  muted     = { 0.55, 0.55, 0.60, 1.00 },   -- kept for back-compat

  -- WoW item quality colors (for reference / shared widgets)
  quality = {
    [0] = { 0.62, 0.62, 0.62 },  -- Poor
    [1] = { 1.00, 1.00, 1.00 },  -- Common
    [2] = { 0.12, 1.00, 0.00 },  -- Uncommon
    [3] = { 0.00, 0.44, 0.87 },  -- Rare
    [4] = { 0.64, 0.21, 0.93 },  -- Epic
    [5] = { 1.00, 0.50, 0.00 },  -- Legendary
    [6] = { 0.90, 0.80, 0.50 },  -- Artifact
    [7] = { 0.00, 0.80, 1.00 },  -- Heirloom
    [8] = { 0.00, 0.80, 1.00 },  -- WoW Token
  },
}

-- ============================================================================
-- Backdrop templates
-- ============================================================================

lib.Backdrop = lib.Backdrop or {
  bgFile   = "Interface\\Tooltips\\UI-Tooltip-Background",
  edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
  edgeSize = 16,
  insets   = { left = 4, right = 4, top = 4, bottom = 4 },
}

lib.BackdropSmall = lib.BackdropSmall or {
  bgFile   = "Interface\\Tooltips\\UI-Tooltip-Background",
  edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
  edgeSize = 10,
  insets   = { left = 2, right = 2, top = 2, bottom = 2 },
}

-- ============================================================================
-- Character key utilities
-- ============================================================================
-- Canonical "Name-RealmNormalized" keys, matching Syndicator's convention
-- so Cogworks and Syndicator data can be cross-referenced without a
-- translation layer.

local function currentRealm()
  if GetNormalizedRealmName then
    local nr = GetNormalizedRealmName()
    if nr and nr ~= "" then return nr end
  end
  return GetRealmName()
end

function lib:GetCharacterKey(name, realm)
  name  = name  or UnitName("player")
  realm = realm or currentRealm()
  return name .. "-" .. realm
end

-- ============================================================================
-- Syndicator bridge
-- ============================================================================
-- Cogworks itself does not require Syndicator. Inventory-aware cogs (FlipQueue,
-- the planned Ledger) declare it as a HARD dependency in their TOC and consume
-- it directly with no fallback scanner.
--
-- This helper exists for cogs that want to OPPORTUNISTICALLY enrich their data
-- when Syndicator happens to be present, without making it a hard requirement
-- (e.g. Maxcraft showing reagent counts from alts if it can).
--
-- See docs/PLAN.md in the cogworks repo for the suite's Syndicator strategy.

function lib:HasSyndicator()
  return _G.Syndicator ~= nil
    and _G.Syndicator.API ~= nil
    and _G.Syndicator.API.IsReady ~= nil
    and _G.Syndicator.API.IsReady() == true
end

-- ============================================================================
-- UI widget factories
-- ============================================================================
-- Themed widget constructors that every cog can use instead of duplicating
-- the same dark+gold button/checkbox/header code in their own UI/Shared.lua.
-- All factories return standard WoW frames; cogs own layout and positioning.

function lib:CreateButton(parent, label, width, height, onClick)
  local T = self.Theme
  local btn = CreateFrame("Button", nil, parent, "BackdropTemplate")
  btn:SetSize(width or 100, height or 24)
  btn:SetBackdrop(self.BackdropSmall)
  btn:SetBackdropColor(0.15, 0.15, 0.2, 1)
  btn:SetBackdropBorderColor(unpack(T.border))

  btn.text = btn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  btn.text:SetPoint("CENTER")
  btn.text:SetText(label or "")

  btn:SetScript("OnEnter", function(b)
    b:SetBackdropColor(0.25, 0.25, 0.35, 1)
    b:SetBackdropBorderColor(unpack(T.gold))
  end)
  btn:SetScript("OnLeave", function(b)
    b:SetBackdropColor(0.15, 0.15, 0.2, 1)
    b:SetBackdropBorderColor(unpack(T.border))
  end)
  btn:SetScript("OnMouseDown", function(b)
    b:SetBackdropColor(0.1, 0.1, 0.15, 1)
  end)
  btn:SetScript("OnMouseUp", function(b)
    b:SetBackdropColor(0.25, 0.25, 0.35, 1)
  end)

  if onClick then btn:SetScript("OnClick", onClick) end
  return btn
end

function lib:CreateCheckbox(parent, label, description, initialValue, onChange)
  local T = self.Theme
  local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
  cb:SetSize(26, 26)

  cb.label = cb:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  cb.label:SetPoint("LEFT", cb, "RIGHT", 4, 0)
  cb.label:SetText(label or "")
  cb.label:SetTextColor(unpack(T.text))

  if description and description ~= "" then
    cb.description = cb:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    cb.description:SetPoint("TOPLEFT", cb.label, "BOTTOMLEFT", 0, -2)
    cb.description:SetPoint("RIGHT", parent, "RIGHT", -8, 0)
    cb.description:SetJustifyH("LEFT")
    cb.description:SetText(description)
    cb.description:SetTextColor(unpack(T.textDim))
    cb.description:SetWordWrap(true)
  end

  cb:SetChecked(initialValue and true or false)
  cb:SetScript("OnClick", function(c)
    local checked = c:GetChecked()
    PlaySound(checked and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON
                       or SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF)
    if onChange then onChange(checked) end
  end)
  return cb
end

function lib:CreateIconButton(parent, icon, size, tooltip, onClick)
  local btn = CreateFrame("Button", nil, parent)
  btn:SetSize(size or 16, size or 16)

  btn.tex = btn:CreateTexture(nil, "ARTWORK")
  btn.tex:SetAllPoints()
  btn.tex:SetTexture(icon)

  btn.highlight = btn:CreateTexture(nil, "HIGHLIGHT")
  btn.highlight:SetAllPoints()
  btn.highlight:SetColorTexture(1, 1, 1, 0.2)

  if onClick then btn:SetScript("OnClick", onClick) end
  if tooltip then
    btn:SetScript("OnEnter", function(b)
      GameTooltip:SetOwner(b, "ANCHOR_BOTTOM")
      GameTooltip:SetText(tooltip, 1, 1, 1)
      GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
  end
  return btn
end

function lib:CreateSectionHeader(parent, text, yOffset)
  local T = self.Theme
  local h = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  h:SetPoint("TOPLEFT", parent, "TOPLEFT", 8, yOffset or 0)
  h:SetPoint("RIGHT", parent, "RIGHT", -8, 0)
  h:SetJustifyH("LEFT")
  h:SetText((text or ""):upper())
  h:SetTextColor(unpack(T.textDim))
  return h
end

function lib:CreateProgressBar(parent, width, height)
  local T = self.Theme
  local bar = CreateFrame("Frame", nil, parent, "BackdropTemplate")
  bar:SetSize(width or 150, height or 14)
  bar:SetBackdrop({
    bgFile   = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    edgeSize = 8,
    insets   = { left = 2, right = 2, top = 2, bottom = 2 },
  })
  bar:SetBackdropColor(0.05, 0.05, 0.08, 1)
  bar:SetBackdropBorderColor(unpack(T.border))

  bar.fill = bar:CreateTexture(nil, "ARTWORK")
  bar.fill:SetPoint("TOPLEFT", bar, "TOPLEFT", 2, -2)
  bar.fill:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", 2, 2)
  bar.fill:SetColorTexture(unpack(T.success))
  bar.fill:SetWidth(0.001)

  bar.text = bar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  bar.text:SetPoint("CENTER")
  bar.text:SetTextColor(1, 1, 1, 1)
  bar.text:SetText("")

  function bar:SetProgress(current, max)
    current = current or 0
    max = max or 0
    if max <= 0 then
      self.fill:SetWidth(0.001)
      self.text:SetText("0/0")
      return
    end
    local frac = math.min(1, current / max)
    local inner = self:GetWidth() - 4
    self.fill:SetWidth(math.max(0.001, inner * frac))
    self.text:SetText(current .. "/" .. max)
  end

  function bar:SetBarColor(r, g, b)
    self.fill:SetColorTexture(r, g, b, 0.8)
  end

  return bar
end

function lib:CreateNavButton(parent, navItem, onClick)
  local T = self.Theme
  local btn = CreateFrame("Button", nil, parent)
  btn:SetSize(parent:GetWidth() or 160, 32)

  btn.bg = btn:CreateTexture(nil, "BACKGROUND")
  btn.bg:SetAllPoints()
  btn.bg:SetColorTexture(1, 1, 1, 0)

  btn.accent = btn:CreateTexture(nil, "ARTWORK")
  btn.accent:SetSize(3, 24)
  btn.accent:SetPoint("LEFT", btn, "LEFT", 0, 0)
  btn.accent:SetColorTexture(unpack(T.gold))
  btn.accent:Hide()

  if navItem.icon then
    btn.icon = btn:CreateTexture(nil, "ARTWORK")
    btn.icon:SetSize(16, 16)
    btn.icon:SetPoint("LEFT", btn, "LEFT", 12, 0)
    btn.icon:SetTexture(navItem.icon)
    btn.icon:SetDesaturated(true)
  end

  btn.label = btn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  btn.label:SetPoint("LEFT", btn, "LEFT", navItem.icon and 34 or 12, 0)
  btn.label:SetText(navItem.label or "")
  btn.label:SetTextColor(unpack(T.textDim))

  if navItem.badge then
    btn.badge = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    btn.badge:SetPoint("RIGHT", btn, "RIGHT", -8, 0)
    btn.badge:SetTextColor(unpack(T.textDim))
  end

  btn:SetScript("OnEnter", function(b)
    b.bg:SetColorTexture(1, 1, 1, 0.06)
  end)
  btn:SetScript("OnLeave", function(b)
    if not b.active then b.bg:SetColorTexture(1, 1, 1, 0) end
  end)

  if onClick then btn:SetScript("OnClick", onClick) end
  btn.active = false
  return btn
end

function lib:SetNavButtonActive(btn, isActive)
  local T = self.Theme
  btn.active = isActive
  if isActive then
    btn.accent:Show()
    btn.label:SetTextColor(unpack(T.text))
    btn.bg:SetColorTexture(1, 1, 1, 0.06)
    if btn.icon then btn.icon:SetDesaturated(false) end
  else
    btn.accent:Hide()
    btn.label:SetTextColor(unpack(T.textDim))
    btn.bg:SetColorTexture(1, 1, 1, 0)
    if btn.icon then btn.icon:SetDesaturated(true) end
  end
end

-- ============================================================================
-- Initialization hook
-- ============================================================================
-- Cogworks fires its Ready event once at PLAYER_LOGIN. Cogs that need to wait
-- for the full login sequence before touching Cogworks state can listen on it.

if not lib._readyFrame then
  lib._readyFrame = CreateFrame("Frame")
  lib._readyFrame:RegisterEvent("PLAYER_LOGIN")
  lib._readyFrame:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_LOGIN" then
      lib:Fire(lib.Events.Ready)
    end
  end)
end
