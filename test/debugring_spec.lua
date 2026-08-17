-- test/debugring_spec.lua
-- Pins the Debug.lua ring-buffer semantics (COG-82).
--
-- Run from the repo root with stock Lua 5.1:
--   lua5.1 test/debugring_spec.lua
--
-- appendEntry used to append then table.remove(ring, 1), an O(ringMax) shift on
-- every call past the first 500. It is now a circular buffer with a write index,
-- which is O(1) but replaces a trivially-correct line with modular arithmetic
-- and a lazy migration path for records built by an older vendored copy. This
-- spec exists because that arithmetic is easy to get subtly wrong and the
-- symptom -- debug lines in the wrong order, or silently dropped -- would only
-- show up when someone opened the console to diagnose something else.

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

-- The ring helpers are file-locals, so lift the whole block rather than a
-- single named function. fireAppend is injected as a no-op stub.
local src = assert(io.open("Cogworks-1.0/Debug.lua")):read("*a")
local chunk = src:match("(local function ringInit%(d%).-\nlocal function appendEntry.-\nend)")
assert(chunk, "could not locate the ring-buffer block in Cogworks-1.0/Debug.lua")

local ring = assert(loadstring(
    "local fireAppend = ...\n" .. chunk ..
    "\nreturn { init = ringInit, normalize = ringNormalize, entries = ringEntries, append = appendEntry }"
))(function() end)

print("debug ring spec")

local function newCog(max)
    return { ring = {}, ringMax = max }
end

local function contents(d)
    return table.concat(ring.entries(d), ",")
end

-- Under capacity: plain append, oldest first.
local d = newCog(5)
for i = 1, 3 do ring.append(d, tostring(i)) end
check("under capacity order", contents(d), "1,2,3")
check("under capacity count", d.ringCount, 3)

-- Exactly at capacity.
for i = 4, 5 do ring.append(d, tostring(i)) end
check("at capacity order", contents(d), "1,2,3,4,5")
check("at capacity count", d.ringCount, 5)

-- One past capacity: oldest is evicted, order preserved.
ring.append(d, "6")
check("wrap once order", contents(d), "2,3,4,5,6")
check("wrap once count", d.ringCount, 5)
check("wrap once storage stays bounded", #d.ring, 5)

-- Several full laps: the ring must not drift or duplicate.
for i = 7, 20 do ring.append(d, tostring(i)) end
check("many laps order", contents(d), "16,17,18,19,20")
check("many laps storage stays bounded", #d.ring, 5)

-- A ring of one is the tightest wrap case.
local one = newCog(1)
ring.append(one, "a")
ring.append(one, "b")
check("ringMax=1 keeps newest", contents(one), "b")
check("ringMax=1 count", one.ringCount, 1)

-- Empty ring reads as empty, not nil.
local empty = newCog(4)
check("empty ring", contents(empty), "")
check("empty count", ring.init(empty).ringCount, 0)

--------------------------
-- Migration from an older vendored copy
--
-- lib._debug is guarded state: `lib._debug = lib._debug or {}`. When a sibling
-- cog ships an older Debug.lua that loads first, this copy can inherit `d`
-- records whose ring is a plain contiguous array with no ringStart/ringCount.
-- Those must keep their order and continue correctly, not restart at slot 1
-- and overwrite live entries.
--------------------------

local legacy = { ring = { "old1", "old2", "old3" }, ringMax = 5 }
check("legacy entries preserved", contents(legacy), "old1,old2,old3")
check("legacy count derived",     legacy.ringCount, 3)
check("legacy start derived",     legacy.ringStart, 1)

ring.append(legacy, "new1")
check("legacy append appends", contents(legacy), "old1,old2,old3,new1")
ring.append(legacy, "new2")
ring.append(legacy, "new3")
check("legacy wraps correctly", contents(legacy), "old2,old3,new1,new2,new3")

-- A legacy ring already at capacity wraps on the very next write.
local legacyFull = { ring = { "a", "b", "c" }, ringMax = 3 }
ring.append(legacyFull, "d")
check("legacy-full wrap", contents(legacyFull), "b,c,d")

--------------------------
-- normalize: flatten a wrapped ring back to contiguous oldest-first
--------------------------

local wrapped = newCog(4)
for i = 1, 6 do ring.append(wrapped, tostring(i)) end
check("wrapped before normalize", contents(wrapped), "3,4,5,6")
ring.normalize(wrapped)
check("normalize preserves order", contents(wrapped), "3,4,5,6")
check("normalize resets start",    wrapped.ringStart, 1)
check("normalize is contiguous",   table.concat(wrapped.ring, ","), "3,4,5,6")

-- Appending after a normalize must continue from the right slot.
ring.append(wrapped, "7")
check("append after normalize", contents(wrapped), "4,5,6,7")

print(string.format("\n%d passed, %d failed", passed, failed))
os.exit(failed == 0 and 0 or 1)
