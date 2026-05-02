-- Cogworks-1.0/Slash.lua | Slash-command registry with subcommand dispatch.
--
-- Owns the SLASH_X1 / SLASH_X2 / SlashCmdList boilerplate, plus tokenizing
-- input into "subcommand args..." and dispatching to a registered handler.
-- Auto-renders a help panel for /<cmd> help / no-args / unknown subcommand.
--
-- Usage:
--
--   cw:RegisterSlashCommands("FlipQueue", {
--     globals = { "/fq", "/flipqueue" },
--     default = function() UI:Toggle() end,         -- bare /fq
--     helpStyle = "chat",                            -- "chat" | "popup" | "both"; default "chat"
--     commands = {
--       { name = "scan",    help = "Force a bag/bank scan",
--         run = function(args) ns:ForceScan() end },
--       { name = "inv",     help = "Open inventory page", args = "[char]",
--         run = function(args) UI:ShowInventory(args) end },
--       { name = "import",  help = "Import deals", aliases = { "i" },
--         run = function(args) ... end },
--     },
--   })
--
-- Each command may declare:
--   name    string  required
--   run     fn(arg) required; arg is the trimmed remainder after the subcommand
--   help    string  one-line description shown in auto-help
--   args    string  arg sketch shown in auto-help (e.g. "[char]")
--   aliases array   alternate names for this subcommand
--   hidden  bool    skip this entry in auto-help (still callable)

local lib = LibStub("Cogworks-1.0")
if not lib then return end

local MODULE_MINOR = 1
lib._modules = lib._modules or {}
if (lib._modules.Slash or 0) >= MODULE_MINOR then return end
lib._modules.Slash = MODULE_MINOR

lib._slashRegistry = lib._slashRegistry or {}  -- [addonName] = registration

local function trim(s) return (s or ""):gsub("^%s+", ""):gsub("%s+$", "") end

local function buildIndex(commands)
  local idx = {}
  for _, c in ipairs(commands) do
    if c.name then idx[c.name:lower()] = c end
    if c.aliases then
      for _, a in ipairs(c.aliases) do idx[a:lower()] = c end
    end
  end
  return idx
end

-- Render help to chat — one line per command in the order registered.
local function renderHelpChat(addonName, reg)
  lib:Print(addonName, "Commands:")
  for _, c in ipairs(reg.commands) do
    if not c.hidden then
      local syntax = "/" .. (reg.globals[1] or addonName):gsub("^/", "") .. " " .. c.name
      if c.args and c.args ~= "" then syntax = syntax .. " " .. c.args end
      DEFAULT_CHAT_FRAME:AddMessage("  |cffffd100" .. syntax .. "|r"
        .. ((c.help and c.help ~= "") and ("  — " .. c.help) or ""))
    end
  end
end

-- Render help in a Cogworks-themed popup. Reuses CreatePopup; popup body is
-- a multi-line read-only display of the same command list.
local function renderHelpPopup(addonName, reg)
  local lines = {}
  for _, c in ipairs(reg.commands) do
    if not c.hidden then
      local syntax = "/" .. (reg.globals[1] or addonName):gsub("^/", "") .. " " .. c.name
      if c.args and c.args ~= "" then syntax = syntax .. " " .. c.args end
      lines[#lines + 1] = string.format("|cffffd100%-32s|r %s",
        syntax, c.help or "")
    end
  end
  if #lines == 0 then lines[1] = "(no commands registered)" end

  local popup = lib:CreatePopup({
    title = addonName .. " — slash commands",
    width = 520, height = 320,
  })
  local fs = popup.content:CreateFontString(nil, "OVERLAY")
  fs:SetFontObject(lib:GetFont("normal"))
  fs:SetAllPoints()
  fs:SetJustifyH("LEFT"); fs:SetJustifyV("TOP")
  fs:SetWordWrap(false)
  fs:SetText(table.concat(lines, "\n"))
  fs:SetTextColor(unpack(lib.Theme.text))

  popup:SetButtons({
    { label = "Close", onClick = function() popup:Hide() end },
  })
  popup:Show()
end

local function renderHelp(addonName, reg)
  local style = reg.helpStyle or "chat"
  if style == "popup" or style == "both" then renderHelpPopup(addonName, reg) end
  if style == "chat"  or style == "both" then renderHelpChat(addonName, reg)  end
end

local function dispatch(addonName, reg, raw)
  raw = trim(raw or "")
  if raw == "" then
    if reg.default then reg.default("")
    else                 renderHelp(addonName, reg) end
    return
  end

  local sub, rest = raw:match("^(%S+)%s*(.*)$")
  sub = (sub or ""):lower()

  if sub == "help" or sub == "?" then
    renderHelp(addonName, reg)
    return
  end

  local cmd = reg.index[sub]
  if not cmd then
    lib:PrintError(addonName, "Unknown command: " .. sub .. ". Try /"
      .. (reg.globals[1] or addonName):gsub("^/", "") .. " help.")
    return
  end

  local ok, err = pcall(cmd.run, rest or "")
  if not ok then
    lib:PrintError(addonName, "Command error: " .. tostring(err))
  end
end

function lib:RegisterSlashCommands(addonName, opts)
  assert(type(addonName) == "string" and addonName ~= "", "RegisterSlashCommands: addonName required")
  assert(type(opts) == "table", "RegisterSlashCommands: opts table required")
  assert(type(opts.globals) == "table" and #opts.globals > 0, "RegisterSlashCommands: opts.globals must be a non-empty array")
  assert(type(opts.commands) == "table", "RegisterSlashCommands: opts.commands required")

  local reg = {
    addon     = addonName,
    globals   = opts.globals,
    default   = opts.default,
    commands  = opts.commands,
    helpStyle = opts.helpStyle,
    index     = buildIndex(opts.commands),
  }
  self._slashRegistry[addonName] = reg

  -- Wire SLASH_<KEY>1, SLASH_<KEY>2, ... globals so WoW recognizes the slash.
  local key = addonName:upper():gsub("[^%w_]", "")
  for i, g in ipairs(opts.globals) do
    _G["SLASH_" .. key .. i] = g
  end
  SlashCmdList[key] = function(raw) dispatch(addonName, reg, raw) end

  return reg
end

function lib:GetSlashRegistration(addonName)
  return self._slashRegistry[addonName]
end

-- Add a command to an already-registered cog (e.g. plugin-style late
-- registration). Returns true on success, false if the cog isn't registered.
function lib:AddSlashCommand(addonName, command)
  local reg = self._slashRegistry[addonName]
  if not reg then return false, "No registration for " .. addonName end
  reg.commands[#reg.commands + 1] = command
  reg.index = buildIndex(reg.commands)
  return true
end
