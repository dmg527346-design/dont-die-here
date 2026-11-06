-- Item batch 6 (CursedA build 2026-10-27): FoamFinger, BobbleBuddy, WobbleJelly (first-find set), HiccupBubbleBath,
-- PopUpToaster, HomesickYoyo, HideyBox, PocketFogger, HungryLunchbox. Required exactly once by CursedBatchEffects,
-- which calls Configure / IsWorn / ReleaseHold / Pickup / ClearPlayer / ClearLevel like ItemBatch5.
-- Each child module is self-contained (own Heartbeat, own KEYS); this init only fans the owner's calls out.
-- Feedback = the shared face / screen-reaction contract (ItemBatch7 uses it too). Client half:
-- StarterPlayerScripts.CurseEffectsClient.ItemBatch6Client.
local M={}
local Feedback=require(script:WaitForChild('Feedback'))
local CHILDREN={'FirstFind','Household','ToyShop','HideyBox','Fogger','Cart'}
local mods:{[any]:any}={}
for _,name in ipairs(CHILDREN)do
 local ok,mod=pcall(require,script:WaitForChild(name))
 if ok then table.insert(mods,mod);mods[name]=mod else warn('ItemBatch6.'..name..' failed: '..tostring(mod))end
end
M.Feedback=Feedback
local function each(fn,...)
 for _,mod in ipairs(mods)do local f=mod[fn];if f then local ok,err=pcall(f,...);if not ok then warn('ItemBatch6.'..fn..': '..tostring(err))end end end
end
function M.Configure(drop,clear,parts)each('Configure',drop,clear,parts)end
function M.IsWorn(m)return mods.HideyBox~=nil and mods.HideyBox.IsWorn(m)end
function M.ReleaseHold(p,m)return mods.HideyBox~=nil and mods.HideyBox.ReleaseHold(p,m)end
function M.Pickup(p,m)each('Pickup',p,m)end
function M.ClearPlayer(p)
 each('ClearPlayer',p)
 Feedback.Clear(p)
end
function M.ClearLevel()
 for _,p in ipairs(game:GetService('Players'):GetPlayers())do M.ClearPlayer(p)end
 each('ClearLevel')
end
game:GetService('Players').PlayerRemoving:Connect(M.ClearPlayer)
return M
