-- test/wow_shim.lua
-- Minimal stubs for the WoW global API surface that Cogworks modules touch,
-- so they can be loaded and exercised headless under stock Lua 5.1. This is a
-- TEST-ONLY shim: it implements just enough of each global to be behaviourally
-- faithful for parser-level tests, not the full Blizzard API.
--
-- Mirrored from flipqueue/test/wow_shim.lua so specs port between repos
-- without rewriting. Keep the two compatible when adding stubs.
--
-- Load this before any Cogworks module:  dofile("test/wow_shim.lua")

-- strsplit(delimiter, str[, limit]) — returns the pieces as multiple return
-- values. WoW treats every char in `delimiter` as a separator; our callers
-- only ever pass a single-char delimiter, which this handles faithfully
-- (including leading, empty, and trailing fields).
function strsplit(delim, str, limit)
    if delim == "" then return str end
    local result = {}
    local escaped = delim:gsub("(%W)", "%%%1")   -- safe inside a [..] set
    local pat = "(.-)[" .. escaped .. "]"
    local lastEnd = 1
    local s, e, cap = str:find(pat, 1)
    while s do
        table.insert(result, cap)
        lastEnd = e + 1
        s, e, cap = str:find(pat, lastEnd)
    end
    table.insert(result, str:sub(lastEnd))
    return unpack(result)
end

-- strtrim(s[, chars]) — trims leading/trailing whitespace (default) or any
-- char in `chars`. WoW's default trims " \t\r\n".
function strtrim(s, chars)
    if s == nil then return "" end
    if chars then
        local pat = "^[" .. chars:gsub("(%W)", "%%%1") .. "]*(.-)[" ..
            chars:gsub("(%W)", "%%%1") .. "]*$"
        return (s:gsub(pat, "%1"))
    end
    return (s:gsub("^%s*(.-)%s*$", "%1"))
end

-- wipe(t) — empty a table in place.
function wipe(t)
    for k in pairs(t) do t[k] = nil end
    return t
end

-- time() / date() — back onto the host os library.
time = os.time
date = os.date

-- ---------------------------------------------------------------------------
-- Frame stub
--
-- Enough of the Blizzard frame API for Cogworks UI modules to construct and be
-- driven headless. Records parentage, shown state, anchors, and scripts so a
-- spec can assert on them; Show/Hide dispatch OnShow/OnHide the way the client
-- does (including the "hiding an already-hidden frame is a no-op" rule that
-- Loading.lua's ESC path depends on).
--
-- __testFrames counts every frame ever created — that count IS the assertion
-- for pooling specs (COG-81).
-- ---------------------------------------------------------------------------

UIParent = nil          -- set below, once CreateFrame exists
UISpecialFrames = {}
__testFrames = {}

function tinsert(t, v) return table.insert(t, v) end

local function newRegion()
    local r = {}
    function r:SetAllPoints() end
    function r:SetPoint() end
    function r:SetSize(w, h) self._w, self._h = w, h end
    function r:SetWidth(w) self._w = w end
    function r:SetHeight(h) self._h = h end
    function r:GetWidth() return self._w end
    function r:GetHeight() return self._h end
    function r:SetTexture() end
    function r:SetColorTexture() end
    function r:SetVertexColor() end
    function r:SetAlpha(a) self._alpha = a end
    function r:GetAlpha() return self._alpha end
    function r:SetText(t) self._text = t end
    function r:GetText() return self._text end
    function r:SetFontObject() end
    function r:SetTextColor() end
    function r:SetJustifyH() end
    function r:SetWordWrap() end
    function r:Show() self._shown = true end
    function r:Hide() self._shown = false end
    function r:IsShown() return self._shown ~= false end
    return r
end

function CreateFrame(frameType, name, parent, template)
    local f = newRegion()
    f._type, f._name, f._parent, f._template = frameType, name, parent, template
    f._scripts, f._events, f._points = {}, {}, {}
    f._shown, f._strata, f._level = true, nil, 0
    if name then _G[name] = f end
    table.insert(__testFrames, f)

    function f:SetScript(kind, fn) self._scripts[kind] = fn end
    function f:GetScript(kind) return self._scripts[kind] end
    function f:RegisterEvent(e) self._events[e] = true end
    function f:UnregisterEvent(e) self._events[e] = nil end
    function f:UnregisterAllEvents() self._events = {} end

    function f:SetParent(p) self._parent = p end
    function f:GetParent() return self._parent end
    function f:ClearAllPoints() self._points = {} end
    function f:SetPoint(...) table.insert(self._points, { ... }) end
    function f:SetAllPoints(p) self._points = { { "ALL", p } } end
    function f:SetFrameStrata(s) self._strata = s end
    function f:GetFrameStrata() return self._strata end
    function f:SetFrameLevel(l) self._level = l end
    function f:GetFrameLevel() return self._level end
    function f:EnableMouse() end
    function f:SetBackdrop() end
    function f:SetBackdropColor() end
    function f:SetBackdropBorderColor() end
    function f:SetStatusBarTexture() end
    function f:SetStatusBarColor() end
    function f:SetMinMaxValues() end
    function f:SetValue(v) self._value = v end
    function f:GetValue() return self._value end
    function f:CreateTexture() return newRegion() end
    function f:CreateFontString() return newRegion() end

    -- Show/Hide dispatch, matching the client: a state change fires the
    -- handler, a redundant call does not.
    function f:Show()
        if self._shown then return end
        self._shown = true
        local fn = self._scripts.OnShow
        if fn then fn(self) end
    end
    function f:Hide()
        if not self._shown then return end
        self._shown = false
        local fn = self._scripts.OnHide
        if fn then fn(self) end
    end
    function f:IsShown() return self._shown end

    return f
end

UIParent = CreateFrame("Frame", "UIParent")

function __testFireEvent(frame, event, ...)
    local fn = frame._scripts and frame._scripts.OnEvent
    if fn then fn(frame, event, ...) end
end

-- Count frames created while running `fn` — the pooling assertion.
function __testCountFrames(fn)
    local before = #__testFrames
    fn()
    return #__testFrames - before
end

-- ---------------------------------------------------------------------------
-- Spec helper: load a single function out of a Cogworks module without
-- standing up LibStub and the whole library.
--
-- Cogworks module files are `local lib = LibStub("Cogworks-1.0")` followed by
-- method assignments, so a self-contained function can be lifted out by name
-- and bound to a bare table. Returns that table.
--
--   local lib = loadLibFunction("Cogworks-1.0/Items.lua", "ItemKeyToItemString")
--   lib:ItemKeyToItemString(...)
-- ---------------------------------------------------------------------------
function loadLibFunction(path, fnName, into)
    local f = assert(io.open(path), "could not open " .. path)
    local src = f:read("*a")
    f:close()

    -- Non-greedy up to a line that begins `end` at column 0 — nested blocks
    -- inside the function are indented, so this stops at the real terminator.
    local pattern = "(function lib:" .. fnName .. "%(.-\nend)"
    local body = src:match(pattern)
    assert(body, "could not locate lib:" .. fnName .. " in " .. path)

    local lib = into or {}
    assert(loadstring("local lib = ...\n" .. body))(lib)
    return lib
end
