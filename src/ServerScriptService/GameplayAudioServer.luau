local RS=game:GetService('ReplicatedStorage')
local event=RS:WaitForChild('GameplaySoundEvent')
local C=require(RS:WaitForChild('GameplaySoundCatalog'))
local M={}
function M.Play(key,origin,actor)
 if not C[key] then return end
 local monsterMade=typeof(origin)=='Instance' and os.clock()<(tonumber(origin:GetAttribute('MonsterOpenedUntil'))or 0)
 if typeof(origin)=='Instance' then
  if origin:IsA('Model') then origin=origin.PrimaryPart end
  origin=origin and origin:IsA('BasePart') and origin.Position or nil
 end
 local evidence=game.ServerStorage:FindFirstChild('MonsterEvidence')
 local noises={DoorOpen=20,DoorClose=24,DrawerOpen=12,DrawerClose=15,ItemDrop=35,ItemRelease=35,GlassBreak=75}
 local loudness=noises[key]
 if loudness and not monsterMade and typeof(origin)=='Vector3'and evidence then evidence:Fire(origin,loudness,key)end
 if key=='FlashlightClick'and typeof(actor)=='Instance'and actor:IsA('Player')and actor.Parent==game.Players then
  for _,listener in game.Players:GetPlayers()do event:FireClient(listener,key,if listener==actor then nil else origin)end
 else event:FireAllClients(key,origin)end
end
function M.ToPlayer(player,key)
 if player and player.Parent and C[key] then event:FireClient(player,key)end
end

-- Selected item audio channel: bounded audio on the normal audio owner/event.
function M.DraftPlay(key, model, token, duration)
 if not C[key] or type(token)~='string' or #token>80 then return end
 if typeof(model)~='Instance' or not model:IsA('Model') or model:GetAttribute('SelectedItem')~=true or not model.PrimaryPart then return end
 local itemId=model:GetAttribute('ItemId');local entry=require(game.ReplicatedStorage.CursedCatalog).Items[itemId]
 if not entry or entry.SelectedItem~=true or key~='DraftSelected_'..itemId then return end
 event:FireAllClients('ItemDraftAudio',{action='play',key=key,origin=model.PrimaryPart,token=token,duration=math.clamp(tonumber(duration)or .8,.05,key:sub(1,14)=='DraftSelected_'and 60 or 2),loop=C[key].loop==true})
end
function M.DraftStop(token)
 if type(token)=='string' and #token<=80 then
  event:FireAllClients('ItemDraftAudio',{action='stop',token=token})
 end
end
return M
