-- Item batch 7 (CursedA build 2026-10-27): companions (DustBunnyBot, PeekabooSock), rare treasures (GildedIdol,
-- MansionCrown) and map-only items (FoodCourtPager on Mall, HallPass on School). Required exactly once by
-- CursedBatchEffects, which calls Configure / IsWorn / ReleaseHold / AdoptCompanion / Pickup / ClearPlayer / ClearLevel.
-- Children are self-contained (own Heartbeat); this init only fans the calls out. Faces and screen pops use
-- ItemBatch6.Feedback. Client half: StarterPlayerScripts.CurseEffectsClient.ItemBatch7Client.
local M={}
local CHILDREN={'Companion','Treasure','Maps'}
local mods:{[any]:any}={}
for _,name in ipairs(CHILDREN)do
 local ok,mod=pcall(require,script:WaitForChild(name))
 if ok then table.insert(mods,mod);mods[name]=mod else warn('ItemBatch7.'..name..' failed: '..tostring(mod))end
end
local function each(fn,...)
 for _,mod in ipairs(mods)do local f=mod[fn];if f then local ok,err=pcall(f,...);if not ok then warn('ItemBatch7.'..fn..': '..tostring(err))end end end
end
function M.Configure(drop,clear,parts)each('Configure',drop,clear,parts)end
function M.IsWorn(m)return mods.Treasure~=nil and mods.Treasure.IsWorn(m)end
function M.ReleaseHold(p,m)return mods.Treasure~=nil and mods.Treasure.ReleaseHold(p,m)end
-- CursedItemsServer use() chain: true = the grabbed companion item is spent (the caller detaches and destroys it).
function M.AdoptCompanion(p,m)return mods.Companion~=nil and mods.Companion.Adopt(p,m)==true end
function M.Pickup(p,m)each('Pickup',p,m)end
function M.ClearPlayer(p)each('ClearPlayer',p)end
function M.ClearLevel()each('ClearLevel')end
return M
