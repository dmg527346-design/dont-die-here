-- Anti-cheat boundary helpers; kept within this system's existing owner.
-- Server boundary protection. Reject requests; never ban, kick or correct movement.
local Players=game:GetService('Players')
local AntiCheat={}
local buckets={}
local counters={}
local function record(channel,reason)
 local key=channel..':'..reason
 counters[key]=math.min((counters[key] or 0)+1,1000000000)
end
function AntiCheat.Finite(n)
 return type(n)=='number' and n==n and math.abs(n)<math.huge
end
function AntiCheat.Allow(player,channel,rate,burst)
 if typeof(player)~='Instance' or not player:IsA('Player') or player.Parent~=Players then return false end
 local now=os.clock()
 local user=buckets[player]
 if not user then user={};buckets[player]=user end
 local bucket=user[channel]
 if not bucket then bucket={tokens=burst,last=now};user[channel]=bucket end
 bucket.tokens=math.min(burst,bucket.tokens+math.max(0,now-bucket.last)*rate)
 bucket.last=now
 if bucket.tokens<1 then record(channel,'rate');return false end
 bucket.tokens-=1
 return true
end
function AntiCheat.Payload(value)
 -- Lobby requests are small records. Bound work, nesting, strings and numbers.
 local remaining=64
 local bytes=0
 local seen={}
 local function valid(v,depth)
  remaining-=1
  if remaining<0 then return false end
  local t=typeof(v)
  if t=='nil' or t=='boolean' then return true end
  if t=='number' then return AntiCheat.Finite(v) end
  if t=='string' then
   bytes+=#v
   return #v<=1024 and bytes<=4096 and utf8.len(v)~=nil
  end
  if t~='table' or depth>=3 or seen[v] then return false end
  seen[v]=true
  for key,item in pairs(v) do
   if (type(key)~='string' and type(key)~='number') or not valid(key,depth+1) or not valid(item,depth+1) then return false end
  end
  seen[v]=nil
  return true
 end
 return valid(value,0)
end
function AntiCheat.Stats()
 return table.clone(counters)
end
Players.PlayerRemoving:Connect(function(player)buckets[player]=nil end)

-- Field map server: owns the replicated MapOpen attribute and the radar device
-- other players see in each character's left hand. Reading the map blocks
-- interaction (InteractServer / CursedItemsServer check MapOpen).
local Players=game:GetService('Players')
local RS=game:GetService('ReplicatedStorage')
local Device=require(RS:WaitForChild('FieldMapDevice'))
local MIN_GAP=.08
local SHOW_DELAY=.2 -- device appears once the hand is back out of the pocket
local HIDE_DELAY=.18
-- LeftHand-local grip, solved against CharacterMotionClient's map pose: the device rests
-- just above the hand in front of the chest with its screen tilted up to the eyes.
local GRIP=CFrame.new(-.178,-.227,.147)*CFrame.fromEulerAnglesXYZ(-2.577,1.253,-1.190)
local DEVICE_SCALE=.6
local event=RS:FindFirstChild('FieldMapEvent') or Instance.new('RemoteEvent')
event.Name='FieldMapEvent';event.Parent=RS
local last,token={},{}
local function setVisible(character,visible)
 local device=character and character:FindFirstChild('FieldMapDevice',true)
 if not device then return end
 for _,p in device:GetDescendants() do if p:IsA('BasePart') then p.Transparency=visible and (p:GetAttribute('ShownTransparency') or 0) or 1 end end
end
local function allowed(player)
 local character=player.Character;local hum=character and character:FindFirstChildOfClass('Humanoid')
 return player:GetAttribute('MissionActive')==true and not player:GetAttribute('RoundDead') and not player:GetAttribute('Hiding')
  and not player:GetAttribute('MonsterJumpscareActive') and hum~=nil and hum.Health>0
end
local function setOpen(player,open)
 open=open and allowed(player)
 if (player:GetAttribute('MapOpen')==true)==open then return end
 player:SetAttribute('MapOpen',open or nil)
 token[player]=(token[player] or 0)+1;local mine=token[player]
 task.delay(open and SHOW_DELAY or HIDE_DELAY,function()
  if token[player]==mine then setVisible(player.Character,open) end
 end)
end
local function giveDevice(character)
 local hand=character:WaitForChild('LeftHand',10)
 if not hand or hand:FindFirstChild('FieldMapDevice') then return end
 local model=Device.Build(DEVICE_SCALE)
 for _,p in model:GetDescendants() do if p:IsA('BasePart') then p:SetAttribute('ShownTransparency',p.Transparency);p.Transparency=1;p.Anchored=false end end
 model:PivotTo(hand.CFrame*GRIP)
 -- A Weld (not WeldConstraint) keeps the exact grip offset on every client's posed hand.
 local weld=Instance.new('Weld');weld.Name='FieldMapGrip';weld.Part0=hand;weld.Part1=model.PrimaryPart;weld.C0=GRIP;weld.Parent=model.PrimaryPart
 model.Parent=hand
end
event.OnServerEvent:Connect(function(player,open)
 if type(open)~='boolean' then return end
 -- Closing is always accepted so a rejected burst cannot leave the map open.
 if open and not AntiCheat.Allow(player,'fieldMap',10,20) then return end
 local now=os.clock()
 if open and last[player] and now-last[player]<MIN_GAP then return end
 last[player]=now
 setOpen(player,open)
end)
local function join(player)
 local function onCharacter(character)
  setOpen(player,false)
  task.spawn(giveDevice,character)
  local hum=character:WaitForChild('Humanoid',10)
  if hum then hum.Died:Connect(function() setOpen(player,false) end) end
 end
 player.CharacterAdded:Connect(onCharacter)
 if player.Character then task.spawn(onCharacter,player.Character) end
 for _,name in {'Hiding','RoundDead','MonsterJumpscareActive','MissionActive'} do
  player:GetAttributeChangedSignal(name):Connect(function() if player:GetAttribute('MapOpen') and not allowed(player) then setOpen(player,false) end end)
 end
end
Players.PlayerAdded:Connect(join)
Players.PlayerRemoving:Connect(function(player) last[player]=nil;token[player]=nil end)
for _,p in Players:GetPlayers() do join(p) end
