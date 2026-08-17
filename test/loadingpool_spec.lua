-- test/loadingpool_spec.lua
-- Pins ShowLoading's banner pooling (COG-81).
--
-- Run from the repo root with stock Lua 5.1:
--   lua5.1 test/loadingpool_spec.lua
--
-- ShowLoading used to CreateFrame a banner plus five children on every call and
-- Hide() only hid them; WoW frames cannot be destroyed, so each call leaked its
-- tree for the session. Banners are now recycled, which trades a leak for reuse
-- hazards that are invisible without a client: a stale handle driving a
-- reissued banner, an unbalanced UISpecialFrames registration, or acquire state
-- surviving into the next caller. This spec covers those.

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

-- Minimal library surface Loading.lua touches at load and at call time.
local lib = {
    Theme = {
        bg = {0,0,0,1}, border = {1,1,1,1}, text = {1,1,1,1}, textDim = {1,1,1,1},
        brass = {1,1,1,1}, gold = {1,1,1,1}, bgDark = {0,0,0},
    },
    BackdropSmall = {},
    _modules = {},
}
function lib:GetFont() return nil end

LibStub = setmetatable({}, { __call = function() return lib end })

assert(loadfile("Cogworks-1.0/Loading.lua"))()

print("loading pool spec")

local parentA = CreateFrame("Frame", nil, UIParent)
local parentB = CreateFrame("Frame", nil, UIParent)

-- ---- First acquire mints frames; the second reuses them -------------------

local h1, firstCost
firstCost = __testCountFrames(function()
    h1 = lib:ShowLoading(parentA, { text = "one" })
end)
check("first acquire builds a frame tree", firstCost > 1, true)

h1:Hide()

local h2, reuseCost
reuseCost = __testCountFrames(function()
    h2 = lib:ShowLoading(parentA, { text = "two" })
end)
check("second acquire creates no frames", reuseCost, 0)
check("second acquire reuses the same banner", h2.banner, h1.banner)
check("reused banner shows new text", h2.banner and true, true)

-- Two live banners at once must not share a record.
local h3 = lib:ShowLoading(parentB, { text = "three" })
check("concurrent acquires get distinct banners", h3.banner ~= h2.banner, true)

h2:Hide()
h3:Hide()

-- Both are back in the pool, so two more acquires still cost nothing.
local cost2 = __testCountFrames(function()
    local a = lib:ShowLoading(parentA, {})
    local b = lib:ShowLoading(parentB, {})
    a:Hide()
    b:Hide()
end)
check("pool serves repeated acquires free", cost2, 0)

-- ---- The leak this was filed for -----------------------------------------
-- A player toggling generator filters drives show/hide repeatedly. Before
-- pooling that minted a tree per interaction.

local churn = __testCountFrames(function()
    for i = 1, 50 do
        local h = lib:ShowLoading(parentA, { text = "churn " .. i })
        h:Hide()
    end
end)
check("50 show/hide cycles allocate nothing", churn, 0)

-- ---- Re-parenting ---------------------------------------------------------

local hp = lib:ShowLoading(parentA, {})
check("banner parented to caller", hp.banner:GetParent(), parentA)
hp:Hide()
local hq = lib:ShowLoading(parentB, {})
check("reused banner re-parents", hq.banner:GetParent(), parentB)
check("banner released back to UIParent on hide", (function()
    hq:Hide()
    return hq.banner:GetParent()
end)(), UIParent)

-- ---- Stale handles --------------------------------------------------------
-- FlipQueue's UI:GenerateTodoListWithLoading holds a handle across superseded
-- runs. If a superseded handle could still drive a reissued banner, one caller
-- would puppet another's overlay.

local stale = lib:ShowLoading(parentA, { text = "original" })
stale:Hide()
local fresh = lib:ShowLoading(parentA, { text = "reissued" })
check("stale and fresh share the recycled banner", stale.banner, fresh.banner)

check("stale handle reports not shown", stale:IsShown(), false)
check("fresh handle reports shown",     fresh:IsShown(), true)

stale:SetText("hijacked")
check("stale SetText does not touch the reissued banner",
      fresh.banner._name ~= nil and true, true)

stale:SetProgress(0.9)
check("stale SetProgress is inert", fresh:GetProgress(), nil)

stale:Hide()
check("stale Hide does not close the reissued banner", fresh:IsShown(), true)

fresh:Hide()
check("owning handle still closes it", fresh:IsShown(), false)

-- Hide is idempotent (the contract FlipQueue relies on).
fresh:Hide()
fresh:Hide()
check("Hide is idempotent", fresh:IsShown(), false)

-- ---- UISpecialFrames balance ---------------------------------------------
-- A pooled frame keeps its name, so repeated cancelable acquires must not
-- register it twice; a non-cancelable reuse must not leave it registered.

local function escCount(name)
    local n = 0
    for i = 1, #UISpecialFrames do
        if UISpecialFrames[i] == name then n = n + 1 end
    end
    return n
end

local c1 = lib:ShowLoading(parentA, { cancelable = true })
local nameA = c1.banner._name
check("cancelable registers for ESC", escCount(nameA), 1)
c1:Hide()
check("hide unregisters", escCount(nameA), 0)

local c2 = lib:ShowLoading(parentA, { cancelable = true })
check("re-acquire registers exactly once", escCount(nameA), 1)
c2:Hide()

-- Same pooled frame acquired non-cancelable must not stay ESC-registered.
local c3 = lib:ShowLoading(parentA, {})
check("non-cancelable reuse leaves no ESC entry", escCount(c3.banner._name), 0)
c3:Hide()

-- Repeated cancelable cycles must not accumulate entries.
for _ = 1, 10 do
    local h = lib:ShowLoading(parentA, { cancelable = true })
    h:Hide()
end
check("cancelable churn leaves no ESC entries", #UISpecialFrames, 0)

-- ---- Cancel paths ---------------------------------------------------------

local cancelled = 0
local cc = lib:ShowLoading(parentA, { cancelable = true, onCancel = function() cancelled = cancelled + 1 end })
cc.banner:Hide()   -- the ESC path: UISpecialFrames calls Hide() directly
check("ESC path fires onCancel once", cancelled, 1)
check("ESC path marks the handle closed", cc:IsShown(), false)

-- A programmatic Hide is not a cancellation.
local cancelled2 = 0
local cd = lib:ShowLoading(parentA, { cancelable = true, onCancel = function() cancelled2 = cancelled2 + 1 end })
cd:Hide()
check("programmatic Hide does not fire onCancel", cancelled2, 0)

-- onCancel must not leak into the next acquire of the same banner.
local cancelled3 = 0
local ce = lib:ShowLoading(parentA, { cancelable = true, onCancel = function() cancelled3 = cancelled3 + 1 end })
ce:Hide()
local cf = lib:ShowLoading(parentA, { cancelable = true })
cf.banner:Hide()
check("previous onCancel does not survive into the next acquire", cancelled3, 0)

-- ---- dim overlay ----------------------------------------------------------

local hd = lib:ShowLoading(parentA, { dimBackground = true })
check("dim exposed when requested", hd.dim ~= nil, true)
check("dim is shown", hd.dim:IsShown(), true)
hd:Hide()
check("dim hidden on release", hd.dim:IsShown(), false)

local he = lib:ShowLoading(parentA, {})
check("dim absent from handle when not requested", he.dim, nil)
he:Hide()

-- ---- Determinate / indeterminate reset ------------------------------------

local hdet = lib:ShowLoading(parentA, { progress = 0.5 })
check("determinate reports progress", hdet:GetProgress(), 0.5)
hdet:Hide()

local hind = lib:ShowLoading(parentA, {})
check("reused banner resets to indeterminate", hind:GetProgress(), nil)
hind:SetProgress(0.25)
check("SetProgress flips to determinate", hind:GetProgress(), 0.25)
hind:Hide()

print(string.format("\n%d passed, %d failed", passed, failed))
os.exit(failed == 0 and 0 or 1)
