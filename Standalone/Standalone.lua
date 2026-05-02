-- Standalone/Standalone.lua
-- The standalone "Cogworks" addon shell. NOT embedded into sibling cogs —
-- this file lives only in the standalone cogworks addon, not in Cogworks-1.0/.
--
-- Provides the /cogworks slash command, CogworksDB persistence for suite-wide
-- settings, and a Ready-time banner.

local addonName, ns = ...
local cw = LibStub("Cogworks-1.0")

cw:RegisterAddon("Cogworks", {
  version = cw.version,
  prefix  = "|cffd4a017[Cogworks]|r ",
  icon    = "Interface\\Icons\\INV_Misc_Gear_01",
})

-- ============================================================================
-- Settings persistence
-- ============================================================================
-- Cogworks-1.0 owns persistence via CogworksSharedDB (declared in this TOC and
-- in every consumer cog's TOC). The lib's own event frame handles ADDON_LOADED
-- and PLAYER_LOGOUT, including the one-shot migration from legacy CogworksDB.
-- The standalone addon no longer owns a parallel write path; CogworksDB stays
-- declared in the TOC for one release as a downgrade safety net.

-- ============================================================================
-- Slash command
-- ============================================================================

local function CmdMain(msg)
  msg = (msg or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")

  if msg == "" or msg == "status" then
    cw:Print("Cogworks", "Cogworks-1.0 v" .. cw.version .. " (MINOR " .. cw.minorVersion .. ") loaded.")
    local addons = cw:GetRegisteredAddons()
    cw:Print("Cogworks", "Registered cogs: " .. (#addons > 0 and table.concat(addons, ", ") or "(none)"))
    cw:Print("Cogworks", "Syndicator: " .. (cw:HasSyndicator() and "|cff30d530present|r" or "|cff888888not detected|r"))
    cw:Print("Cogworks", "Font scale: " .. cw:GetSetting("fontScale") .. "  UI scale: " .. cw:GetSetting("uiScale"))
    return
  end

  if msg == "ui" then
    ns:ToggleShowcase()
    return
  end

  if msg == "console" then
    ns:ToggleConsole()
    return
  end

  if msg == "events" then
    cw:Print("Cogworks", "Known events:")
    local names = {}
    for k in pairs(cw.Events) do names[#names + 1] = k end
    table.sort(names)
    for _, name in ipairs(names) do
      DEFAULT_CHAT_FRAME:AddMessage("  |cffffd100" .. name .. "|r")
    end
    return
  end

  if msg:sub(1, 5) == "fire " then
    local event = msg:sub(6):gsub("^%s+", ""):gsub("%s+$", "")
    local found
    for k in pairs(cw.Events) do
      if k:lower() == event then found = k; break end
    end
    if found then
      cw:Fire(found, "test")
      cw:Print("Cogworks", "Fired event: " .. found)
    else
      cw:PrintError("Cogworks", "Unknown event: " .. event .. ". Try /cogworks events.")
    end
    return
  end

  if msg == "help" then
    cw:Print("Cogworks", "Commands:")
    DEFAULT_CHAT_FRAME:AddMessage("  |cffffd100/cogworks|r              show status")
    DEFAULT_CHAT_FRAME:AddMessage("  |cffffd100/cogworks ui|r           toggle UI showcase")
    DEFAULT_CHAT_FRAME:AddMessage("  |cffffd100/cogworks console|r      toggle Lua dev console")
    DEFAULT_CHAT_FRAME:AddMessage("  |cffffd100/cogworks events|r       list known event names")
    DEFAULT_CHAT_FRAME:AddMessage("  |cffffd100/cogworks fire <ev>|r    fire an event for testing")
    DEFAULT_CHAT_FRAME:AddMessage("  |cffffd100/cogworks help|r         this message")
    return
  end

  cw:PrintError("Cogworks", "Unknown command: " .. msg .. ". Try /cogworks help.")
end

SLASH_COGWORKS1 = "/cogworks"
SlashCmdList["COGWORKS"] = CmdMain

-- Banner at Ready time so the user knows the library loaded.
local owner = {}
cw.RegisterCallback(owner, cw.Events.Ready, function()
  cw:Print("Cogworks", "Ready. Type /cogworks for status.")
end)
