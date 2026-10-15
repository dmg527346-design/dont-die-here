local RS=game:GetService('ReplicatedStorage')
local event=RS:WaitForChild('GameplaySoundEvent')
local C=require(RS:WaitForChild('GameplaySoundCatalog'))
local M={}
function M.Play(key,origin)
 if not C[key] then return end
 local monsterMade=typeof(origin)=='Instance' and os.clock()<(origin:GetAttribute('MonsterOpenedUntil')or 0)
 if typeof(origin)=='Instance' then
  if origin:IsA('Model') then origin=origin.PrimaryPart end
  origin=origin and origin:IsA('BasePart') and origin.Position or nil
 end
 local evidence=game.ServerStorage:FindFirstChild('MonsterEvidence')
 local noises={DoorOpen=20,DoorClose=24,DrawerOpen=12,DrawerClose=15,ItemDrop=35,ItemRelease=35,GlassBreak=75}
 local loudness=noises[key]
 if loudness and not monsterMade and typeof(origin)=='Vector3'and evidence then evidence:Fire(origin,loudness,key)end
 event:FireAllClients(key,origin)
end
function M.ToPlayer(player,key)
 if player and player.Parent and C[key] then event:FireClient(player,key)end
end
return M
