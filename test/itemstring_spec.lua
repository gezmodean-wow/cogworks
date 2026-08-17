-- test/itemstring_spec.lua
-- Pins the WoW item-string field layout produced by lib:ItemKeyToItemString
-- (COG-83).
--
-- Run from the repo root with stock Lua 5.1:
--   lua5.1 test/itemstring_spec.lua
--
-- Why this exists: the builder laid the bonus block one field early — its
-- parts table stopped at 12 entries, omitting itemContext — so the bonus
-- COUNT landed in itemContext and the first real bonus ID landed in
-- numBonusIDs. WoW then read that bonus ID as "how many bonus IDs follow" and
-- swallowed the modifier block. Every item level, tooltip, and link derived
-- from an item key was wrong.
--
-- Ported from flipqueue/test/itemstring_spec.lua, which was written against
-- FlipQueue's temporary local override and is the acceptance test named in
-- cogworks#83. Kept in sync deliberately: when FlipQueue drops its override
-- and delegates back to the library, both specs must pass against this code.

dofile("test/wow_shim.lua")

local passed, failed = 0, 0
local function check(label, got, want)
    if got == want then
        passed = passed + 1
    else
        failed = failed + 1
        print(string.format("  FAIL %s\n       got:  %s\n       want: %s",
            label, tostring(got), tostring(want)))
    end
end

-- Items.lua pulls in more surface than this test needs; the builder is
-- self-contained, so lift just it rather than standing up the library.
local lib = loadLibFunction("Cogworks-1.0/Items.lua", "ItemKeyToItemString")

print("itemstring spec")

-- Field positions, 1-indexed, per WoW's documented layout:
--   1 item  2 itemID  3 enchant  4-7 gems  8 suffix  9 uniqueID
--   10 linkLevel  11 specID  12 modifiersMask  13 itemContext  14 numBonusIDs
local function field(s, n)
    local i = 0
    for f in (s .. ":"):gmatch("([^:]*):") do
        i = i + 1
        if i == n then return f end
    end
    return nil
end

-- The FQ-249 reporter's polearm: bonuses 6655/40/1678, modifier 9=50.
local key = "170112;6655:40:1678;9=50"
local s = lib:ItemKeyToItemString(key)

check("literal prefix",    field(s, 1),  "item")
check("itemID",            field(s, 2),  "170112")
check("itemContext empty", field(s, 13), "")
check("numBonusIDs = 3",   field(s, 14), "3")
check("bonus 1",           field(s, 15), "6655")
check("bonus 2",           field(s, 16), "40")
check("bonus 3",           field(s, 17), "1678")
check("numModifiers = 1",  field(s, 18), "1")
check("modifier type",     field(s, 19), "9")
check("modifier value",    field(s, 20), "50")

-- No bonuses: the count is still written, so numBonusIDs stays at field 14.
local plain = lib:ItemKeyToItemString("12345")
check("no-bonus itemID",       field(plain, 2),  "12345")
check("no-bonus itemContext",  field(plain, 13), "")
check("no-bonus count = 0",    field(plain, 14), "0")

-- Bonuses without modifiers: no modifier block at all.
local noMods = lib:ItemKeyToItemString("222;1663:2293")
check("no-mods count = 2", field(noMods, 14), "2")
check("no-mods bonus 1",   field(noMods, 15), "1663")
check("no-mods bonus 2",   field(noMods, 16), "2293")
check("no-mods has no modifier block", field(noMods, 17), nil)

-- Rejected inputs.
check("nil key",   lib:ItemKeyToItemString(nil),        nil)
check("empty key", lib:ItemKeyToItemString(""),         nil)
check("pet key",   lib:ItemKeyToItemString("pet:1965"), nil)
check("junk key",  lib:ItemKeyToItemString("abc"),      nil)

-- A malformed modifier must not desync the count from the pairs that follow.
-- The count is taken from the pairs that parse, not from the raw split.
local badMod = lib:ItemKeyToItemString("222;1663;9=50:garbage")
check("malformed modifier drops from count", field(badMod, 16), "1")
check("malformed modifier keeps type",       field(badMod, 17), "9")
check("malformed modifier keeps value",      field(badMod, 18), "50")

-- A modifier string where nothing parses omits the block entirely rather than
-- writing a count with no pairs behind it.
local allBadMods = lib:ItemKeyToItemString("222;1663;garbage")
check("all-malformed modifiers omit the block", field(allBadMods, 16), nil)

--------------------------
-- Round trip against real, client-authored item strings
--
-- Everything above pins the layout against a reading of the spec. These are
-- item strings WoW itself wrote, harvested from Syndicator's SavedVariables,
-- so they are the layout rather than a description of it. Each is parsed into
-- an item key and rebuilt; the bonus and modifier blocks must come back
-- byte-identical.
--
-- This is the evidence behind COG-83 (verified over 494 real strings: the
-- corrected builder 494/494, the previous one 0/494). A sample is kept here so
-- the claim stays checkable without the SavedVariables file, and so the fix
-- has a ground-truth acceptance test rather than a self-consistent one.
--------------------------

local function parseReal(link)
    local f = {}
    for part in (link .. ":"):gmatch("([^:]*):") do f[#f + 1] = part end
    local itemID = f[2]
    local nBonus = tonumber(f[14]) or 0
    local bonuses = {}
    for i = 1, nBonus do bonuses[i] = f[14 + i] end
    local modStart = 14 + nBonus + 1
    local nMod = tonumber(f[modStart]) or 0
    local mods = {}
    for i = 1, nMod do
        local t, v = f[modStart + (i - 1) * 2 + 1], f[modStart + (i - 1) * 2 + 2]
        if t and v and t ~= "" and v ~= "" then mods[#mods + 1] = t .. "=" .. v end
    end
    return itemID, table.concat(bonuses, ":"), table.concat(mods, ":")
end

-- Real strings from a live account, chosen to cover: modifiers with no
-- bonuses, bonuses with no modifiers, both together, and a long bonus run.
local REAL = {
    "item:117361::::::::81:65:::1:12380:2:9:31:28:181:::::",
    "item:120137::::::::10:1449::::1:28:46:::::",
    "item:120978::::::::90:66::105:1:737::::::",
    "item:122362::::::::14:1449:::1:582::::::",
    "item:6948::::::::15:1468::75:::::::",
}

for _, link in ipairs(REAL) do
    local itemID, bonusStr, modStr = parseReal(link)
    local key = itemID .. ";" .. bonusStr .. ";" .. modStr
    local rebuilt = lib:ItemKeyToItemString(key)
    local gotID, gotBonus, gotMod = parseReal(rebuilt or "")
    check("real/" .. itemID .. " itemID",    gotID,    itemID)
    check("real/" .. itemID .. " bonuses",   gotBonus, bonusStr)
    check("real/" .. itemID .. " modifiers", gotMod,   modStr)
end

print(string.format("\n%d passed, %d failed", passed, failed))
os.exit(failed == 0 and 0 or 1)
