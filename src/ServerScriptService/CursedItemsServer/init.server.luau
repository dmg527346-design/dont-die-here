local QuestService=require(game:GetService('ServerScriptService'):WaitForChild('QuestService'))
local QuestHttp=game:GetService('HttpService')
local function questContext(eventId,model)
 local s=game:GetService('ReplicatedStorage'):FindFirstChild('RecoveryRound')
 local map=workspace:FindFirstChild('Mansion')
 return {eventId=eventId,runId=s and s:GetAttribute('QuestRunId'),round=s and s:GetAttribute('Round'),generation=s and s:GetAttribute('QuestGeneration'),mapKind=map and map:GetAttribute('MapKind'),admin=model and (model:GetAttribute('AdminEffect')==true or model:GetAttribute('AdminSpawned')==true),lobbyToy=model and model:GetAttribute('LobbyToy')==true,itemId=model and model:GetAttribute('ItemId')}
end
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

-- Server-owned inventory, spring targets, item effects and noise. InteractServer calls PickUp.
local Players=game:GetService('Players')
local RS=game:GetService('ReplicatedStorage')
local SS=game:GetService('ServerStorage')
local Run=game:GetService('RunService')
local Debris=game:GetService('Debris')
local C=require(RS:WaitForChild('CursedCatalog'))
local Audio=require(game.ServerScriptService:WaitForChild('GameplayAudioServer'))
local map=workspace:WaitForChild('Mansion',math.huge)
while map:GetAttribute('Ready')~=true or map:GetAttribute('RuntimeReady')~=true do map:GetAttributeChangedSignal('RuntimeReady'):Wait() end
local furniture=map:FindFirstChild('Furniture') or Instance.new('Folder');furniture.Name='Furniture';furniture.Parent=map
local event=RS:FindFirstChild('CursedEvent') or Instance.new('RemoteEvent');event.Name='CursedEvent';event.Parent=RS
require(SS:WaitForChild('MoustacheMeshGeometry')).Build(SS.CursedItemKit.Moustache)
require(SS:WaitForChild('CursedBlenderHydration')).Build()
local inv: {[Player]: {Model}}={}
local states: {[any]: any}={}
local limits={}
local lobbyIds={Candy=true,SnailShell=true,Anvil=true,CoffeeMug=true,MakeupKit=true,RedPepper=true,Popsicle=true,BeehiveJar=true}
local function lobbyFolder()
 local w=workspace:FindFirstChild('LobbyWorld');local toys=w and w:FindFirstChild('Toys')
 return toys and toys:FindFirstChild('RuntimeToys')
end
local function lobbyPlayer(p)
 local s=RS:FindFirstChild('LobbyState')
 return s and s:GetAttribute('Mode')=='Menu' and p:GetAttribute('LobbyReady')==true and p:GetAttribute('MissionActive')~=true
end
local function itemAllowed(p,m)
 if m.Parent==map.Interactive then return p:GetAttribute('MissionActive')==true end
 return lobbyPlayer(p) and m.Parent==lobbyFolder() and m:GetAttribute('LobbyToy')==true and lobbyIds[m:GetAttribute('ItemId')]==true
end
local function missionRunning()
 for _,p in Players:GetPlayers()do if p:GetAttribute('MissionActive')==true then return true end end
 return false
end
local registerLobby,removeLobby
local Batch=require(script:WaitForChild('CursedBatchEffects'))
local rng=Random.new(map:GetAttribute('Seed')+431)
local roomTypes={}
for _,room in ipairs(game:GetService('HttpService'):JSONDecode(map.GeneratedGraph.Value).rooms) do roomTypes[room.name]=room end
local HoldPose=require(RS:WaitForChild('HoldPose'))
local pianos={};local fallbackMusicUntil=0
do -- one haunted piano per level plays the song; every other piano stays dormant
 local all={};for _,f in ipairs(furniture:GetChildren()) do if f.Name:find('Piano') then table.insert(all,f) end end
 if #all>0 then local pick=all[rng:NextInteger(1,#all)];pianos={pick};pick:SetAttribute('HauntedPiano',true)
  local holder=pick.PrimaryPart or pick:FindFirstChildWhichIsA('BasePart',true)
  if holder then local song=Instance.new('Sound');song.Name='HauntedPianoSong';local SONGS={'rbxassetid://1847107549','rbxassetid://9046646008','rbxassetid://1842150470'};song.SoundId=SONGS[rng:NextInteger(1,#SONGS)];song:SetAttribute('Track',song.SoundId);song.Volume=.5;song.RollOffMode=Enum.RollOffMode.InverseTapered;song.RollOffMinDistance=10;song.RollOffMaxDistance=80;song.Parent=holder
   -- One song per level, picked at random (1 in 3): Chopin's Fantaisie-Impromptu, Beethoven's Moonlight Sonata (1st mvt)
   -- or Brahms' Hungarian Dance No. 5 (APM library audio).
   end end
end
local function root(p) local ch=p.Character;return ch and ch:FindFirstChild('HumanoidRootPart'),ch and ch:FindFirstChildOfClass('Humanoid') end
local function monsters() local f=workspace:FindFirstChild('RoamingCreatures');return f and f:GetChildren() or {} end
local function nearestMonster(pos)
 local best,d=nil,math.huge
 for _,m in ipairs(monsters()) do if m.PrimaryPart then local dd=(m.PrimaryPart.Position-pos).Magnitude;if dd<d then best,d=m,dd end end end
 return best,d
end
local function say(p,text) if p and p.Parent then event:FireClient(p,'notice',text) end end
local function noise(pos,radius,label,source,lobbyOnly)
 local evidence=SS:FindFirstChild('MonsterEvidence')
 if evidence and not lobbyOnly and not(source and source:GetAttribute('LobbyToy')) and missionRunning() then evidence:Fire(pos,math.clamp(radius/1.4,1,100),label,source)end
 event:FireAllClients('noise',pos,label,source)
end
local lootBounds
local touchDropPosition
local function parts(m,anchored,collide)
 local collider=m:FindFirstChild('ItemGroundCollider')
 if not collider then
  collider=Instance.new('Part');collider.Name='ItemGroundCollider';collider.Transparency=1;collider.CanQuery=false;collider.Parent=m
 end
 -- Reposition the collider before welding: changing a welded part CFrame moves the whole assembly.
 for _,joint in collider:GetChildren()do if joint:IsA('WeldConstraint')or joint:IsA('JointInstance')then joint:Destroy()end end
 collider.Anchored=true
 if lootBounds then
  local bounds=lootBounds(m,true);collider.Size=Vector3.new(math.max(.25,bounds.size.X),math.max(.25,bounds.size.Y),math.max(.25,bounds.size.Z));collider.CFrame=m:GetPivot()*CFrame.new(bounds.centre)
 else collider.Size=m.PrimaryPart.Size;collider.CFrame=m.PrimaryPart.CFrame end
 local weld=Instance.new('WeldConstraint');weld.Name='ItemGroundWeld';weld.Part0=m.PrimaryPart;weld.Part1=collider;weld.Parent=collider
 for _,p in ipairs(m:GetDescendants()) do if p:IsA('BasePart') then p.Anchored=anchored;p.Massless=p~=collider;p.CollisionGroup='Default';p.CanCollide=p==collider and collide;p.CanTouch=false end end
 m.PrimaryPart.CanQuery=true;collider.CanQuery=false
 if not anchored then pcall(function()m.PrimaryPart:SetNetworkOwner(nil) end) end
end
local function has(p,id)
 for _,m in ipairs(inv[p] or {}) do if m:GetAttribute('ItemId')==id and not m:GetAttribute('Spent') then return m end end
end
local function active(p) return inv[p] and inv[p][1] end
local function publish(p)
 local list={};for _,m in ipairs(inv[p] or {}) do if m.Parent then table.insert(list,{id=m:GetAttribute('ItemId'),model=m,name=m:GetAttribute('DisplayName')or C.Items[m:GetAttribute('ItemId')].name}) end end
 p:SetAttribute('CursedHeldCount',#list);p:SetAttribute('CursedActive',list[1] and list[1].id or nil)
 p:SetAttribute('MagicOrbHeld',has(p,'MagicOrb')~=nil)
 p:SetAttribute('BalloonHeld',has(p,'Balloon')~=nil)
 p:SetAttribute('SprintBlocked',has(p,'Anvil')~=nil or nil)
 p:SetAttribute('QuietSteps',has(p,'Shoes')~=nil)
 event:FireClient(p,'inventory',list,p:GetAttribute('Valuables') or 0)
end
local function clearHold(m)
 for _,x in ipairs(m.PrimaryPart:GetChildren()) do if x.Name:sub(1,5)=='Hold_' then x:Destroy() end end
 m:SetAttribute('HeldBy',nil)
end
-- A creature lets go of an item it stole from the cart: it becomes ordinary floor loot again.
local function monsterDrop(m)
 local weld=m.PrimaryPart:FindFirstChild('MonsterCarryWeld');if weld then weld:Destroy() end
 m:SetAttribute('MonsterCarried',nil);parts(m,false,true)
 m.PrimaryPart.AssemblyLinearVelocity=Vector3.zero;m.PrimaryPart.AssemblyAngularVelocity=Vector3.zero
 local s=states[m];if s then s.restSince=os.clock() end
end
-- Authoritative hold spring (was 65 / 160 / 45 / 100). The server owns the item's
-- real position, collisions and impacts; the holder sees a client-only visual
-- copy with its own spring (CursedItemsClient 'CursedHoldVisual').
local HOLD_RESPONSIVENESS,HOLD_MAX_VELOCITY,HOLD_TURN_RESPONSIVENESS,HOLD_MAX_TURN=100,200,75,140
local HOLD_SNAP_DISTANCE=12
local function spring(m)
 local r=m.PrimaryPart;local a=Instance.new('Attachment');a.Name='Hold_Attachment';a.Parent=r
 local pos=Instance.new('AlignPosition');pos.Name='Hold_Position';pos.Mode=Enum.PositionAlignmentMode.OneAttachment;pos.Attachment0=a;pos.ApplyAtCenterOfMass=true;pos.RigidityEnabled=false;pos.Responsiveness=HOLD_RESPONSIVENESS;pos.MaxVelocity=HOLD_MAX_VELOCITY;pos.MaxForce=math.max(15000,r.AssemblyMass*workspace.Gravity*60);pos.Position=r.Position;pos.Parent=r
 local rot=Instance.new('AlignOrientation');rot.Name='Hold_Orientation';rot.Mode=Enum.OrientationAlignmentMode.OneAttachment;rot.Attachment0=a;rot.RigidityEnabled=false;rot.Responsiveness=HOLD_TURN_RESPONSIVENESS;rot.MaxAngularVelocity=HOLD_MAX_TURN;rot.MaxTorque=math.max(40000,r.AssemblyMass*50000);rot.CFrame=r.CFrame.Rotation;rot.Parent=r
end
local function releaseFace(m)
 local s=states[m];if not s then return end
 local owner=s.faceOwner
 local joint=m.PrimaryPart:FindFirstChild('MoustacheFaceJoint');if joint then joint:Destroy()end
 m:SetAttribute('FaceOwner',nil);m:SetAttribute('MoustachePullProgress',nil);m:SetAttribute('MoustacheFallAt',nil)
 s.faceOwner=nil;s.pullStart=nil;s.fallAt=nil;s.restSince=os.clock()
 parts(m,false,true)
 if owner and owner.Parent and m:GetAttribute('ItemId')=='Moustache'then owner:SetAttribute('MoustacheFace',nil)end
end
local function faceOffset(m)
 if m:GetAttribute('ItemId')=='CoolSunglasses' then return CFrame.new(0,1.67,.68)*(m:GetAttribute('ModelPivotOffset')or CFrame.identity)end
 return CFrame.new(0,.55,.75)*CFrame.Angles(0,math.pi,0)
end
local function attachFace(p,m)
 local head=p.Character and p.Character:FindFirstChild('Head');local s=states[m]
 if not head or not s then return end
 clearHold(m)
 local oldJoint=m.PrimaryPart:FindFirstChild('MoustacheFaceJoint');if oldJoint then oldJoint:Destroy()end
 for _,part in m:GetDescendants()do if part:IsA('BasePart')then part.Anchored=true;part.Massless=true;part.CanCollide=false;part.CanTouch=false;part.CanQuery=false end end
 m:PivotTo(head.CFrame*faceOffset(m))
 s.faceOwner=p;s.pullStart=os.clock();s.fallAt=nil
 m:SetAttribute('FaceOwner',p.UserId);m:SetAttribute('HeldBy',p.UserId);m:SetAttribute('MoustacheFallAt',nil);m:SetAttribute('MoustachePullProgress',0);if m:GetAttribute('ItemId')=='Moustache'then p:SetAttribute('MoustacheFace',true)end
end

local detach
local cleanup
detach=function(p,m,throw,bypass,dropRay)
 if not m or m:GetAttribute('HeldBy')~=p.UserId then return false end
 if m:GetAttribute('ItemId')=='Coin' and not bypass then say(p,'The coin will not let go. Use near a friend or wash at a sink.');return false end
 local list=inv[p];local index=table.find(list,m);if index then table.remove(list,index) end
 if Batch.ReleaseHold(p,m)then publish(p);return true end
 if (m:GetAttribute('ItemId')=='Moustache'or m:GetAttribute('ItemId')=='CoolSunglasses') and states[m].faceOwner==p then
  local s=states[m];clearHold(m);s.pullStart=nil;s.fallAt=os.clock()+5
  m:SetAttribute('MoustachePullProgress',0);m:SetAttribute('MoustacheFallAt',workspace:GetServerTimeNow()+5)
  publish(p);return true
 end
 local placement=not throw and dropRay and touchDropPosition and touchDropPosition(p,m,dropRay)
 clearHold(m);parts(m,false,true)
 local r=root(p);if r then
  local look=(states[p] and states[p].look) or r.CFrame.LookVector
  local st=states[m];local goal=not placement and not throw and st and st.holdGoal
  if goal and (goal-r.Position).Magnitude<=HOLD_SNAP_DISTANCE then m:PivotTo(CFrame.new(goal)*m.PrimaryPart.CFrame.Rotation);m.PrimaryPart.AssemblyLinearVelocity=Vector3.zero end
  if st then st.holdGoal=nil end
  if (m.PrimaryPart.Position-r.Position).Magnitude>HOLD_SNAP_DISTANCE then m:PivotTo(r.CFrame*CFrame.new(0,0,-3)) end
  if placement then m:PivotTo(placement);st.safeDropFrame=placement end
  m.PrimaryPart.AssemblyLinearVelocity=placement and Vector3.zero or throw and look*55+Vector3.new(0,9,0) or Vector3.new(0,-1,0)
  m.PrimaryPart.AssemblyAngularVelocity=throw and Vector3.new(2,4,1) or Vector3.zero
  noise(m.PrimaryPart.Position,throw and 55 or 16,throw and 'thrown item' or 'item set down',m)
 end
 local s=states[m];s.lastOwner=p;s.restSince=os.clock();s.wind=s.wind or 0
 if m:GetAttribute('ItemId')=='Clock'then s.clockImpact=os.clock();s.impactVelocity=math.max(0,-m.PrimaryPart.AssemblyLinearVelocity.Y);s.lastPos=m.PrimaryPart.Position end
 if m:GetAttribute('ItemId')=='Bracelet' then local partner=Players:GetPlayerByUserId(p:GetAttribute('BraceletPartner') or 0);if partner then partner:SetAttribute('BraceletPartner',nil);partner:SetAttribute('BraceletPosition',nil) end;p:SetAttribute('BraceletPartner',nil);p:SetAttribute('BraceletPosition',nil) end
 if m:GetAttribute('ItemId')=='Portrait' then say(p,'Portrait: "Butterfingers. That was expensive."');event:FireAllClients('speech',m.PrimaryPart.Position,'Butterfingers. That was expensive.') end
 if m:GetAttribute('ItemId')=='Backpack' and #list>2 then for i=#list,3,-1 do detach(p,list[i],false,true) end end
 publish(p);return true
end
-- Restore the same grab after its temporary wear/use animation; do not replay Pickup.
local function restoreHold(m,p)
 local r,h=root(p)
 if not r or not h or h.Health<=0 or p:GetAttribute('PhysicalGrabActive')~=true or not m.Parent or m:GetAttribute('HeldBy')~=p.UserId or not table.find(inv[p]or {},m)then return false end
 clearHold(m);m:SetAttribute('HeldBy',p.UserId);parts(m,false,false)
 -- Resume at the current wear pose; the next hold update supplies a fresh target.
 m.PrimaryPart.AssemblyLinearVelocity=Vector3.zero;m.PrimaryPart.AssemblyAngularVelocity=Vector3.zero
 spring(m);publish(p);return true
end
Batch.Configure(detach,clearHold,parts,restoreHold)
local function questItem(p,m,hook)
 if not m or m:GetAttribute('Gear') or m:GetAttribute('LobbyToy') or m:GetAttribute('AdminEffect') or m:GetAttribute('AdminSpawned') then return end
 local ctx=questContext(nil,m);local spawnId=m:GetAttribute('LootSpawnIdentity');local guid=m:GetAttribute('LootGUID');if spawnId and ctx.runId and ctx.round then guid=tostring(ctx.runId)..':'..tostring(ctx.round)..':'..spawnId;m:SetAttribute('LootGUID',guid)end;if not guid then return end
 QuestService.Record(p,hook,1,questContext(hook..':'..guid,m))
end
local function effectSnapshot(p,m)
 local before={};for k,v in p:GetAttributes()do before['p:'..k]=v end;for k,v in m:GetAttributes()do before['m:'..k]=v end;return before
end
local function effectChanged(p,m,before)
 for k,v in p:GetAttributes()do if before['p:'..k]~=v then return true end end
 for k,v in m:GetAttributes()do if before['m:'..k]~=v then return true end end
 return false
end
local grabUse -- set below, once use() exists
local function pickup(p,m)
 local r,h=root(p)
 if p:GetAttribute('PhysicalGrabActive')~=true then return false end
 if not r or not h or h.Health<=0 or p:GetAttribute('Hiding') or typeof(m)~='Instance' or not m:IsA('Model') or not m.PrimaryPart or not m.Parent or not itemAllowed(p,m) or not states[m] or m:GetAttribute('Selling') then return false end
 if m:GetAttribute('AttachedTo') and not Batch.CanRemove(p,m)then return false end
 if m:GetAttribute('ItemWearOwner')then return false end
 if m:GetAttribute('MonsterCarried')then return false end
 if m:GetAttribute('FaceOwner') and m:GetAttribute('FaceOwner')~=p.UserId then return false end
 if m:GetAttribute('ItemId')=='Moustache' and p:GetAttribute('MoustacheFace') and m:GetAttribute('FaceOwner')~=p.UserId then return false end
 if (r.Position-m.PrimaryPart.Position).Magnitude>10 then return false end
 local candidates={m:GetAttribute('LobbyToy') and workspace.LobbyWorld or map.Collision};local camp=workspace:FindFirstChild('RecoveryCamp');if camp and not m:GetAttribute('LobbyToy')then table.insert(candidates,camp) end;for _,x in ipairs(m.Parent:GetChildren()) do if not x:GetAttribute('HeldBy') and not (m:GetAttribute('CargoStored') and (x:GetAttribute('Kind')=='cart' or x:GetAttribute('Kind')=='boat')) then table.insert(candidates,x) end end
 local params=RaycastParams.new();params.FilterType=Enum.RaycastFilterType.Include;params.FilterDescendantsInstances=candidates;params.RespectCanCollide=true
 local head=p.Character and p.Character:FindFirstChild('Head');local origin=head and head.Position or r.Position
 local hit=workspace:Raycast(origin,m.PrimaryPart.Position-origin,params)
 if hit and not hit.Instance:IsDescendantOf(m) and hit.Distance+.8<(origin-m.PrimaryPart.Position).Magnitude then return false end
 inv[p]=inv[p] or {};local cap=has(p,'Backpack') and 4 or 2
 if #inv[p]>=cap or p:GetAttribute('BothHandsBusy') then say(p,'Your hands are full.');return false end
 if m:GetAttribute('ItemId')=='Jawbone' and m:GetAttribute('Quiet') and #inv[p]>0 then return false end
 if m:GetAttribute('AttachedTo') and not Batch.RemoveAttached(p,m)then return false end
 -- Only take the item off its current holder once this player is allowed to receive it (stealing stays allowed).
 local previous=Players:GetPlayerByUserId(m:GetAttribute('HeldBy') or 0);if previous and previous~=p then detach(previous,m,false,true) end
 if m:GetAttribute('CargoStored') then local recovery=SS:FindFirstChild('RecoveryApi');if not recovery or not recovery:Invoke('takeCargo',p,m) then return false end end
 m:SetAttribute('HeldBy',p.UserId);m:SetAttribute('LastOwner',p.UserId);table.insert(inv[p],1,m);if m:GetAttribute('ItemId')=='Moustache'or m:GetAttribute('ItemId')=='CoolSunglasses' then attachFace(p,m)else parts(m,false,false);spring(m)end;local before=effectSnapshot(p,m);Batch.Pickup(p,m);if effectChanged(p,m,before)then questItem(p,m,'GrabUse')end;questItem(p,m,'ItemPickup');publish(p)
 say(p,C.Items[m:GetAttribute('ItemId')].hint)
 -- No separate use button: an item's special action happens when it is grabbed.
 task.defer(function()
  if m:GetAttribute('HeldBy')~=p.UserId then return end
  local id=m:GetAttribute('ItemId')
  if id=='Keyring' or id=='Jawbone' or id=='Doll' then
   if not(id=='Jawbone' and #(inv[p] or {})>1)then m:SetAttribute('Quiet',true)end
  elseif grabUse then grabUse(p,m) end
 end)
 return true
end
local api=Instance.new('BindableFunction');api.Name='CursedItemApi';api.OnInvoke=function(action,p,m,dropRay)
 if action=='lobbyRegister'then return registerLobby and registerLobby(m)
 elseif action=='lobbyRemove'then return removeLobby and removeLobby(m)
 elseif action=='lobbyHome'then
  if typeof(m)~='Instance' or not m:IsA('Model') or m.Parent~=lobbyFolder() or m:GetAttribute('LobbyToy')~=true or not states[m] or not m.PrimaryPart then return false end
  states[m].origin=m:GetPivot();states[m].lastPos=m.PrimaryPart.Position;return true
 end
 -- CreatureRoamServer: an item taken from the cart goes limp in a creature's grip, then back to the floor.
 if action=='monsterCarry' or action=='monsterDrop' then
  if typeof(m)~='Instance' or not m:IsA('Model') or not states[m] or not m.PrimaryPart then return false end
  if action=='monsterCarry' then m:SetAttribute('MonsterCarried',true);parts(m,false,false) else monsterDrop(m) end
  return true
 end
 if action=='pickup' then return p:GetAttribute('PhysicalGrabActive')==true and pickup(p,m)
 elseif action=='release' then
  for _,item in ipairs(table.clone(inv[p] or {})) do
   -- Super glue: the hand stays shut until the glue sets free, then it lets go if the button is no longer held.
   local glued=(item:GetAttribute('GluedUntil') or 0)-os.clock()
   if glued>0 then task.delay(glued,function() if item.Parent and item:GetAttribute('HeldBy')==p.UserId and p:GetAttribute('PhysicalGrabActive')~=true then detach(p,item,false,true) end end)
   else detach(p,item,false,true,dropRay) end
  end
  return true
 elseif action=='reset' then cleanup(p);return true
 elseif action=='dropAll' then for _,x in ipairs(table.clone(inv[p] or {})) do detach(p,x,false,true) end
 elseif action=='guard' then
  local _,h=root(p);local shield=has(p,'Teddy') or (h and h.Health<=(m or 40) and has(p,'Heart'))
  if shield then shield:SetAttribute('Spent',true);shield:SetAttribute('ProtectionUsed',true);p:SetAttribute('GrabProtectionUntil',os.clock()+4);say(p,shield:GetAttribute('ItemId')=='Teddy' and 'The teddy took the grab for you.' or 'The stone heart cracked and saved your life.');return true end
  return (p:GetAttribute('GrabProtectionUntil') or 0)>os.clock()
 end
end;api.Parent=SS
local function closestDoor(p)
 local r=root(p);local best,d=nil,11
 if not r then return end
 for _,m in ipairs(map.Interactive:GetChildren()) do if m:IsA('Model') and m.PrimaryPart and m:GetAttribute('Locked') then local dd=(m.PrimaryPart.Position-r.Position).Magnitude;if dd<d then best,d=m,dd end end end
 return best
end
local function unlock(m) if m and m.Parent then m:SetAttribute('Locked',nil);for _,p in ipairs(m:GetChildren()) do if p.Name=='Padlock' then p:Destroy() end end end end
local function nearWater(p)
 local r=root(p);if not r then return false end
 for _,m in ipairs(furniture:GetChildren()) do if m.Name:find('_Sink') and (m:GetPivot().Position-r.Position).Magnitude<10 then return true end end
 return false
end
local function valuable(p,amount) p:SetAttribute('Valuables',math.max(0,(p:GetAttribute('Valuables') or 0)+amount));publish(p) end
local function visible(a,b)
 local params=RaycastParams.new();params.FilterType=Enum.RaycastFilterType.Include;params.FilterDescendantsInstances={map.Collision}
 local delta=b-a;local hit=workspace:Raycast(a,delta,params);return not hit or hit.Distance+.6>=delta.Magnitude
end
local function closestPlayer(p,distance)
 local r=root(p);if not r then return end;local best,d=nil,distance
 for _,q in ipairs(Players:GetPlayers()) do if q~=p then local qr,qh=root(q);if qr and qh.Health>0 then local dd=(qr.Position-r.Position).Magnitude;if dd<d then best,d=q,dd end end end end
 return best
end
local BELL_UNLOCK_DELAY,BELL_FADE_TIME,BELL_LIFETIME=2.5,.45,3.2
local function ringDinnerBell(p,m,s,door)
 local rootPart=door.PrimaryPart
 local kit=SS:FindFirstChild('CursedEffectKit');local template=kit and kit:FindFirstChild('GhostButler')
 if not rootPart or not template or not template:IsA('Model')or not template.PrimaryPart then say(p,'The butler is unavailable. Try again shortly.');return end
 s.cooldown=os.clock()+30;noise(m.PrimaryPart.Position,90,'silver dinner bell',m)
 local enemy=nearestMonster(m.PrimaryPart.Position);if enemy then enemy:SetAttribute('LurePosition',m.PrimaryPart.Position);enemy:SetAttribute('LureUntil',os.clock()+20)end
 say(p,'The ghost butler is opening the door.')
 local butler=template:Clone();butler.Name='DinnerBellButler'
 local beside=rootPart.CFrame:PointToWorldSpace(Vector3.new(rootPart.Size.X*.5+2,0,1.5))
 local ray=RaycastParams.new();ray.FilterType=Enum.RaycastFilterType.Include;ray.FilterDescendantsInstances={map.Collision};ray.RespectCanCollide=true
 local floor=workspace:Raycast(beside+Vector3.new(0,6,0),Vector3.new(0,-20,0),ray)
 local point=Vector3.new(beside.X,floor and floor.Position.Y+.03 or rootPart.Position.Y-rootPart.Size.Y*.5,beside.Z)
 local look=Vector3.new(rootPart.Position.X,point.Y,rootPart.Position.Z)
 local pose=CFrame.lookAt(point,look);butler:PivotTo(pose)
 local shades={}
 for _,part in butler:GetDescendants()do if part:IsA('BasePart')then
  part.Anchored=true;part.CanCollide=false;part.CanQuery=false;part.CanTouch=false;part.CastShadow=false
  shades[part]=part.Transparency;part.Transparency=1
 end end
 butler.Parent=map;Debris:AddItem(butler,BELL_LIFETIME)
 local Tween=game:GetService('TweenService')
 for part,alpha in shades do Tween:Create(part,TweenInfo.new(BELL_FADE_TIME),{Transparency=alpha}):Play()end
 local bow=Instance.new('NumberValue');bow.Parent=butler
 local itemEnded=m.Destroying:Once(function()if butler.Parent then butler:Destroy()end end)
 local motion=bow.Changed:Connect(function(angle)if butler.Parent then butler:PivotTo(pose*CFrame.new(0,1.4,0)*CFrame.Angles(angle,0,0)*CFrame.new(0,-1.4,0))end end)
 butler.Destroying:Once(function()motion:Disconnect();itemEnded:Disconnect()end)
 task.delay(.5,function()if butler.Parent then Tween:Create(bow,TweenInfo.new(.45,Enum.EasingStyle.Sine),{Value=math.rad(18)}):Play()end end)
 task.delay(1.35,function()if butler.Parent then Tween:Create(bow,TweenInfo.new(.45,Enum.EasingStyle.Sine),{Value=0}):Play()end end)
 task.delay(BELL_UNLOCK_DELAY,function()
  if not butler.Parent then return end
  if m.Parent and states[m]==s and door.Parent then unlock(door);say(p,'The butler opened the door.')end
  for part in shades do if part.Parent then Tween:Create(part,TweenInfo.new(BELL_FADE_TIME),{Transparency=1}):Play()end end
 end)
end

local use
local performUse
performUse=function(p,m,alternate)
 if not m or m:GetAttribute('HeldBy')~=p.UserId then return end
 -- Gear shop items fire only on the use press (never on grab); GearShopServer owns their effects.
 if m:GetAttribute('Gear')then local entry=C.Items[m:GetAttribute('ItemId')];if alternate and not(entry and entry.autoUseOnGrab)then return end;local gear=SS:FindFirstChild('GearUseApi');if gear then task.spawn(function()gear:Invoke(p,m)end)end;return end
 local s=states[m];local now=os.clock();if now<(s.cooldown or 0) then return end;s.cooldown=now+.6
 local id=m:GetAttribute('ItemId');local r,h=root(p);if not r then return end
 if alternate and nearWater(p) then
  p:SetAttribute('ChatteringUntil',nil);m:SetAttribute('Quiet',false);if id=='Coin' then detach(p,m,false,true) end;s.meter=0;s.bite=now+25;s.arm=0;s.ring=now+40;s.washedUntil=now+30;Audio.Play('Wash',r);say(p,'Washed clean.');return
 end
 if alternate and id=='Shoes' then s.resistUntil=now+8;p:SetAttribute('DancingUntil',nil);say(p,'You fight the dance.');return end
 if alternate and (id=='Keyring' or id=='Jawbone' or id=='Doll') then
  if id=='Jawbone' and #(inv[p] or {})>1 then say(p,'Set down the other item to hold the jaw shut.');return end
  m:SetAttribute('Quiet',not m:GetAttribute('Quiet'));return
 end
 if id=='Whistle' then local nearest,distance=nearestMonster(r.Position);if nearest and distance<28 then nearest:SetAttribute('StunnedUntil',now+3) end;for _,n in ipairs(monsters()) do if n~=nearest then n:SetAttribute('LurePosition',r.Position);n:SetAttribute('LureUntil',now+15) end end;noise(r.Position,110,'whistle',m);s.cooldown=now+20;questItem(p,m,'GrabUse')
 elseif id=='Backpack' then if (p:GetAttribute('Valuables') or 0)>0 then valuable(p,-1);s.bite=now+35;say(p,'The backpack is satisfied.');else say(p,'It wants one valuable as a snack.') end
 elseif id=='Teddy' then s.arm=0;say(p,'You pull the teddy arms down.')
 elseif id=='Mask' then p:SetAttribute('DisguiseUntil',now+8);p:SetAttribute('BorrowedFaceActive',true);task.delay(8,function()if p.Parent and (p:GetAttribute('DisguiseUntil') or 0)<=os.clock() then p:SetAttribute('BorrowedFaceActive',false) end end);s.cooldown=now+28;noise(r.Position,15,'borrowed face',m)
 elseif id=='Balloon' then say(p,'The balloon makes you look up.')
 elseif id=='Horn' then s.extended=true;s.retractAt=math.huge;noise(r.Position+r.CFrame.LookVector*22,90,'party horn',m)
 elseif id=='Present' then
  if m:GetAttribute('Opened') then return end;m:SetAttribute('Opened',true);valuable(p,rng:NextInteger(4,9)*(has(p,'Coin') and 2 or 1));s.follow=rng:NextNumber()<.4;s.followUntil=now+30;noise(r.Position,55,s.follow and 'something crawled out' or 'present opened',m);say(p,s.follow and 'The wrapping moved. Something is following you.' or 'Treasure! The box is empty.');event:FireAllClients('present',m,s.follow,p)
  if s.follow then
   s.lastOwner=p;local follower=SS.CursedItemKit.Clown:Clone();follower.Name='GiftFollower';follower:SetAttribute('ItemId',nil);follower:SetAttribute('Kind',nil);follower:ScaleTo(.45)
   for _,part in ipairs(follower:GetDescendants()) do if part:IsA('BasePart') then part.Anchored=true;part.CanCollide=false;part.CanTouch=false;part.CanQuery=false;part.Color=(part.Name=='Clown__2' or part.Name=='Clown__3') and Color3.fromRGB(195,181,141) or Color3.fromRGB(18,14,22) end end
   follower:PivotTo(m:GetPivot());follower.Parent=map;s.follower=follower;Debris:AddItem(follower,30)
  end
 elseif id=='Cake' then valuable(p,math.max(1,math.floor(C.Items.Cake.value*(1-(s.meter or 0)/100))));detach(p,m,false,true);m:SetAttribute('Spent',true);m:Destroy();states[m]=nil;say(p,'Cake value collected.')
 elseif id=='Crown' or id=='Keyring' then
  local d=closestDoor(p);local charges=s.charges or (id=='Keyring' and 3 or 1)
  if d and charges>0 then unlock(d);questItem(p,m,'GrabUse');local doorId=d:GetAttribute('QuestDoorGUID');if not doorId then doorId=QuestHttp:GenerateGUID(false);d:SetAttribute('QuestDoorGUID',doorId)end;QuestService.Record(p,'DoorUnlocked',1,questContext('unlock:'..doorId,d));s.charges=charges-1;s.cooldown=now+3;noise(r.Position,id=='Crown' and 90 or 35,id=='Crown' and 'birthday child' or 'jailer keys',m);say(p,'The lock opens. '..s.charges..' bypasses remain.') else say(p,'Stand beside a locked door; '..charges..' bypasses remain.') end
 elseif id=='Clown' then if alternate then return end;s.wind=now+18;detach(p,m,false,true);s.destination=r.Position+r.CFrame.LookVector*18;s.owner=p;noise(m.PrimaryPart.Position,55,'wind-up clown',m)
 elseif id=='Candles' then if alternate then s.covered=not s.covered else s.darkUntil=now+2 end;say(p,s.covered and 'Candles covered.' or 'The trick candles will relight.')
 elseif id=='MusicBox' then s.wind=now+4;noise(r.Position,8,'music winding',m);questItem(p,m,'GrabUse')
 elseif id=='Candy' then if m:GetAttribute('Spent') then say(p,'Only the sticky wrapper is left, but it still sells.') else p:SetAttribute('CandyBoostUntil',now+8);p:SetAttribute('ChatteringUntil',now+60);m:SetAttribute('Spent',true) end
 elseif id=='Bracelet' then local q=closestPlayer(p,10);if q then s.partner=q;p:SetAttribute('BraceletPartner',q.UserId);q:SetAttribute('BraceletPartner',p.UserId);say(p,'Linked to '..q.DisplayName) else say(p,'Use beside a teammate to link bracelets.') end
 elseif id=='Bell' then
  local door=closestDoor(p);if not door then say(p,'Ring it beside a locked door.');return end
  ringDinnerBell(p,m,s,door);questItem(p,m,'GrabUse')
 elseif id=='Telephone' then Audio.Play('TelephoneRing',m);
  local keys={};for _,k in ipairs(map.Interactive:GetChildren()) do if k:GetAttribute('Kind')=='key' then table.insert(keys,k) end end
  local fake=rng:NextNumber()<.25;local key=#keys>0 and keys[rng:NextInteger(1,#keys)];local room=key and (key:GetAttribute('Room') or '') or '';local actual=roomTypes[room];local level=actual and tostring(actual.level);local roomType=actual and actual.type;local location=roomType and ((level=='1' and 'an upstairs ' or 'a downstairs ')..roomType:gsub('(%l)(%u)','%1 %2'):lower()) or 'one of the rooms';local text=key and ('A key waits in '..location..'.') or 'The keys have already been taken.'
  if fake then text='D-d-don\'t check the drawers. Follow the footsteps instead.' end;say(p,'Telephone: '..text);event:FireAllClients('speech',m.PrimaryPart.Position,text);s.cooldown=now+15
 elseif id=='Vacuum' then
  local gathered=0;for _,x in ipairs(map.Interactive:GetChildren()) do if x:GetAttribute('ItemId') and x~=m and not x:GetAttribute('HeldBy') and not x:GetAttribute('CargoStored') and not x:GetAttribute('AttachedTo') and not x:GetAttribute('ItemWearOwner') and not x:GetAttribute('FaceOwner') and not x:GetAttribute('MonsterCarried') and x.PrimaryPart and (x.PrimaryPart.Position-r.Position).Magnitude<14 and x.PrimaryPart.Size.Magnitude<3 and visible(r.Position,x.PrimaryPart.Position) then valuable(p,2);x:Destroy();states[x]=nil;gathered+=1 end end
  noise(r.Position,80,'vacuum motor',m);local q=closestPlayer(p,5);if q then event:FireClient(q,'shoeTug',r.Position) end;say(p,'Vacuum collected '..gathered..' small valuables.');s.cooldown=now+5
 elseif id=='Shoes' then
  local stopped=false
  for _,piano in ipairs(pianos) do if (piano:GetPivot().Position-r.Position).Magnitude<30 then piano:SetAttribute('PlayingUntil',0);local song=piano:FindFirstChild('HauntedPianoSong',true);if song then song:Stop() end;stopped=true end end
  for _,box in ipairs(map.Interactive:GetChildren()) do if box:GetAttribute('ItemId')=='MusicBox' and (box.PrimaryPart.Position-r.Position).Magnitude<12 then states[box].wind=0;box:SetAttribute('Playing',false);stopped=true end end
  if now<fallbackMusicUntil then fallbackMusicUntil=0;stopped=true end
  if stopped then p:SetAttribute('DancingUntil',nil);say(p,'You stop the haunted music.') else say(p,'Use near a haunted piano to stop it, or V to resist the dance.') end
 elseif id=='Keyring' or id=='Jawbone' or id=='Doll' then m:SetAttribute('Quiet',not m:GetAttribute('Quiet'))
 elseif id=='Lantern' then say(p,'Crouch while holding the lantern to feed it one nearby item.')
 elseif id=='Chain' then
  local pos=r.Position;local look=(states[p] and states[p].look) or r.CFrame.LookVector;local target,d=nil,25
  for _,x in ipairs(map.Interactive:GetChildren()) do if states[x] and x~=m and not x:GetAttribute('HeldBy') and not x:GetAttribute('CargoStored') then local delta=x.PrimaryPart.Position-pos;local dd=delta.Magnitude;if dd>0 and dd<d and delta.Unit:Dot(look)>.75 then target,d=x,dd end end end
  if target then local params=RaycastParams.new();params.FilterType=Enum.RaycastFilterType.Include;params.FilterDescendantsInstances={map.Collision,furniture};local hit=workspace:Raycast(pos,target.PrimaryPart.Position-pos,params);if hit and hit.Distance+.6<d then say(p,'The chain cannot reach through a wall.');return end;states[target].restSince=now;parts(target,false,true);target.PrimaryPart.AssemblyLinearVelocity=(pos-target.PrimaryPart.Position).Unit*24+Vector3.new(0,4,0);noise(pos,85,'prisoner chain',m);say(p,'The chain reels the object toward you.') else say(p,'Aim at a loose item within 25 studs.') end
 elseif id=='Clock' then s.ring=now+45;say(p,'Clock wound down.');questItem(p,m,'GrabUse')
 elseif id=='Coin' then
  local q=closestPlayer(p,9);if q then detach(p,m,false,true);m:PivotTo(select(1,root(q)).CFrame*CFrame.new(0,0,-2));if not pickup(q,m) then say(p,'Their hands are full; the coin fell between you.') end else say(p,'Use beside a teammate or wash at a sink.') end
 elseif id=='Flashlight' or id=='Candles' then s.covered=not s.covered
 
 else say(p,C.Items[id].hint) end
end
use=function(p,m,alternate)
 if not m or m:GetAttribute('HeldBy')~=p.UserId or not states[m] or os.clock()<(states[m].cooldown or 0) then return end
 local qualify=not(alternate and (nearWater(p) or m:GetAttribute('ItemId')=='Shoes' or m:GetAttribute('ItemId')=='Keyring' or m:GetAttribute('ItemId')=='Jawbone' or m:GetAttribute('ItemId')=='Doll'));local before=effectSnapshot(p,m);performUse(p,m,alternate);if qualify and effectChanged(p,m,before)then questItem(p,m,'GrabUse')end
end
event.OnServerEvent:Connect(function(p,action,value)
 if type(action)~='string' or #action>20 or (p:GetAttribute('MissionActive')~=true and not lobbyPlayer(p))then return end
 if lobbyPlayer(p) and action~='aim' and action~='carryMode' and action~='holdDistance' and action~='sync' and action~='drop' and action~='swap'then return end
 if action=='use' and typeof(value)=='CFrame' then p:SetAttribute('GearAim',value)end -- camera aim for gear guns/throws
 if not AntiCheat.Allow(p,action=='aim' and 'itemAim' or 'itemControl',action=='aim' and 90 or 20,action=='aim' and 120 or 40) then return end
 local now=os.clock();limits[p]=limits[p] or {action=0,aim=0};local gate=limits[p]
 if action=='carryMode' and typeof(value)=='boolean' then p:SetAttribute('TouchCarry',value);return end
 -- Mouse-wheel hold distance (keyboard/mouse only); clamped here so clients cannot push items through walls or past reach.
 if action=='holdDistance' and AntiCheat.Finite(value) then p:SetAttribute('HoldDistance',math.clamp(value,3.1,10));return end
  -- No item actions while the field map is out; held items keep following the aim.
  if p:GetAttribute('MapOpen') and action~='aim' and action~='sync' then return end
 if action=='aim' then
  if now-gate.aim<.014 or typeof(value)~='CFrame' then return end
  for _,n in ipairs({value:GetComponents()}) do if n~=n or math.abs(n)>1e7 then return end end
  local r,h=root(p);local head=p.Character and p.Character:FindFirstChild('Head');if not r or not h or h.Health<=0 or not head or (value.Position-head.Position).Magnitude>4 then return end
  local look=value.LookVector;if look.Magnitude<.99 or look.Magnitude>1.01 then return end
  gate.aim=now;states[p]=states[p] or {};states[p].look=look;states[p].camera=value;return
 end
 if typeof(action)~='string' or now-gate.action<.16 then return end;gate.action=now
 local r,h=root(p);if not r or not h or h.Health<=0 or p:GetAttribute('Hiding') then return end
 if action=='use' then
  for _,item in ipairs(inv[p] or {}) do if (item:GetAttribute('ItemId')=='Lantern' or item:GetAttribute('ItemId')=='Flashlight' or item:GetAttribute('ItemId')=='Candles') and item:GetAttribute('SecretLight') then
   local secrets=map:FindFirstChild('CursedSecrets');if secrets then for _,secret in ipairs(secrets:GetChildren()) do if secret:IsA('BasePart') and not secret:GetAttribute('Claimed') and (secret.Position-r.Position).Magnitude<(secret:GetAttribute('ClaimDistance') or 7) and visible(r.Position,secret.Position) then secret:SetAttribute('Claimed',true);local guid=secret:GetAttribute('QuestSecretGUID');if not guid then guid=QuestHttp:GenerateGUID(false);secret:SetAttribute('QuestSecretGUID',guid)end;QuestService.Record(p,'SecretFound',1,questContext('secret:'..guid));valuable(p,12);say(p,'Hidden treasure collected: 12 valuables.');return end end end
  end end
 end
 local m=active(p)
 if action=='sync' then publish(p)
 elseif action=='drop' then if (m and m:GetAttribute('GluedUntil') or 0)>os.clock() then say(p,'It is glued to your hand!') return end detach(p,m,false,nil,value);if m and states[m] and m:GetAttribute('ItemId')=='Clown' and m.Parent==map.Interactive and r then states[m].wind=now+18;states[m].destination=r.Position+r.CFrame.LookVector*18;states[m].owner=p;noise(m.PrimaryPart.Position,55,'wind-up clown',m) end
 -- Throwing was removed from the game; items are only dropped.
 elseif action=='use' then if m and m:GetAttribute('Gear') then use(p,m) end;return -- only gear shop items have an E use action
  elseif action=='bank' then say(p,'Put loot in the cart and sell at the van terminal.')
 elseif action=='swap' and inv[p] and #inv[p]>1 then local moved=table.remove(inv[p],1);if moved then table.insert(inv[p],moved)end;publish(p)
 elseif action=='placedUse' and typeof(value)=='Instance' and value:IsA('Model') and value.PrimaryPart and states[value] and value.Parent==map.Interactive and not value:GetAttribute('HeldBy') and (value.PrimaryPart.Position-r.Position).Magnitude<10 and value:GetAttribute('ItemId')=='Clown' then states[value].wind=now+18;states[value].destination=r.Position+r.CFrame.LookVector*18;states[value].owner=p
 end
end)
local questSpawnOrdinals={}
local function stampQuestSpawn(m,id)
 if m:GetAttribute('LootSpawnIdentity') or m:GetAttribute('LobbyToy') or m:GetAttribute('AdminEffect') or m:GetAttribute('AdminSpawned') or m.Name:sub(1,5)=='Gear_' or m.Name:sub(1,8)=='Preview_' then return end
 local p=m:GetPivot().Position
 local key=tostring(map:GetAttribute('Seed'))..':'..id..':'..tostring(math.round(p.X*100))..':'..tostring(math.round(p.Y*100))..':'..tostring(math.round(p.Z*100))
 local hash=5381;for i=1,#key do hash=(hash*33+key:byte(i))%2147483647 end
 local ordinal=(questSpawnOrdinals[key]or 0)+1;questSpawnOrdinals[key]=ordinal
 m:SetAttribute('LootSpawnIdentity',id..':'..tostring(hash)..':'..tostring(ordinal))
end
local function register(m)
 local id=m:GetAttribute('ItemId');if not C.Items[id] or not m.PrimaryPart then return end
 stampQuestSpawn(m,id)
 m:SetAttribute('Kind','pickup');m:SetAttribute('DisplayName',C.Items[id].name);m:SetAttribute('Value',rng:NextInteger(math.max(8,math.floor(C.Items[id].value*.7)),math.max(18,math.floor(C.Items[id].value*1.6))));m:SetAttribute('LootValue',m:GetAttribute('Value'))
 if id=='DiscoBall' then require(script.DiscoBallEffects).Register(m) end
 parts(m,true,false)
 states[m]={birth=os.clock(),bite=os.clock()+30,ring=os.clock()+rng:NextNumber(12,45),arm=0,meter=0,lastNoise=0,charges=id=='Keyring' and 3 or 1,origin=m:GetPivot(),lastPos=m.PrimaryPart.Position}
 local animated=id=='Compass' and {'Compass__2'} or id=='Portrait' and {'Portrait__3','Portrait__4'} or id=='Teddy' and {'Teddy__4','Teddy__6'} or {}
 for _,name in ipairs(animated) do local part=m:FindFirstChild(name);if part then for _,w in ipairs(m:GetDescendants()) do if w:IsA('WeldConstraint') and (w.Part1==part or w.Part0==part) then w:Destroy() end end;local motor=Instance.new('Motor6D');motor.Name='CurseMotion_'..name;motor.Part0=m.PrimaryPart;motor.Part1=part;motor.C0=m.PrimaryPart.CFrame:ToObjectSpace(part.CFrame);motor.Parent=m.PrimaryPart end end
 if id=='Candles' or id=='Flashlight' or id=='Lantern' then local light=Instance.new('PointLight');light.Name='CursedGlow';light.Color=Color3.fromRGB(164,218,172);light.Brightness=.3;light.Range=12;light.Shadows=true;light.Parent=m.PrimaryPart end
end
registerLobby=function(m)
 if typeof(m)~='Instance' or not m:IsA('Model') or m.Parent~=lobbyFolder() or m:GetAttribute('LobbyToy')~=true or not lobbyIds[m:GetAttribute('ItemId')] or not m.PrimaryPart then return false end
 register(m);m:SetAttribute('Value',0);m:SetAttribute('LootValue',0);return true
end
removeLobby=function(m)
 if typeof(m)~='Instance' or not states[m] or m:GetAttribute('LobbyToy')~=true then return false end
 for p,list in inv do if table.find(list,m)then detach(p,m,false,true)end end
 clearHold(m);states[m]=nil;return true
end
local adminLobbyEffects={CryingOnion=true,RedPepper=true,BeehiveJar=true,MakeupKit=true,Candy=true,SnailShell=true,Anvil=true,CoffeeMug=true,Popsicle=true}
-- Owner admin panel (AdminPowersServer checks the owner before invoking this).
local function adminSpawn(id,pos)
 if not C.Items[id] or typeof(pos)~='Vector3' or not SS.CursedItemKit:FindFirstChild(id) or not Batch.CanSpawn(id)then return nil end
 local m=SS.CursedItemKit[id]:Clone();m:PivotTo(CFrame.new(pos));m:SetAttribute('AdminSpawned',true);m.Parent=map.Interactive;register(m);return m
end
local adminApi=Instance.new('BindableFunction');adminApi.Name='CursedItemAdminApi'
adminApi.OnInvoke=function(action,p,a,b)
 if action=='catalog' then local list={};local seen={};for _,id in ipairs(C.Order)do if not seen[id] and SS.CursedItemKit:FindFirstChild(id) then seen[id]=true;table.insert(list,{id=id,name=C.Items[id].name}) end end;return list end
 if action=='effects'then
  local list={};for _,id in C.Order do if SS.CursedItemKit:FindFirstChild(id)and Batch.CanSpawn(id)and(p:GetAttribute('MissionActive')==true or adminLobbyEffects[id])then list[#list+1]={id=id,name=C.Items[id].name}end end;return list
 end
 local r=root(p);local h=p.Character and p.Character:FindFirstChildOfClass('Humanoid')
 if not r or not h or h.Health<=0 or p:GetAttribute('RoundDead')==true then return false,'Choose a living player.'end
 if action=='giveEffect'and(p:GetAttribute('MissionActive')~=true and(not lobbyPlayer(p)or not adminLobbyEffects[a]))then return false,'That effect is only available in a mission.'end
 if action=='spawn'  then
  local m=adminSpawn(a,r.Position+r.CFrame.LookVector*4+Vector3.new(0,1,0));return m~=nil,m and C.Items[a].name..' spawned.' or 'Unknown item.'
 elseif action=='give'or action=='giveEffect'then
  -- Puts the item straight into the owner's hands, so its held effect applies (no reach, sight or slot checks).
  local m
  if action=='giveEffect'and p:GetAttribute('MissionActive')~=true then
   local runtime=lobbyFolder();local template=type(a)=='string'and SS.CursedItemKit:FindFirstChild(a)
   if runtime and template and adminLobbyEffects[a]and Batch.CanSpawn(a)then
    m=template:Clone();m:SetAttribute('ItemId',a);m:SetAttribute('LobbyToy',true);m:SetAttribute('AdminEffect',true);m:PivotTo(CFrame.new(r.Position+Vector3.new(0,2,0)));m.Parent=runtime;register(m)
   end
  else m=adminSpawn(a,r.Position+Vector3.new(0,2,0))end
  if not m then return false,'Unknown or unavailable item effect.'end
  if action=='giveEffect'then m:SetAttribute('AdminEffect',true);m:SetAttribute('Value',0);m:SetAttribute('LootValue',0)end
  inv[p]=inv[p] or {};m:SetAttribute('HeldBy',p.UserId);m:SetAttribute('LastOwner',p.UserId);table.insert(inv[p],1,m)
  if a=='Moustache' or a=='CoolSunglasses' then attachFace(p,m) else parts(m,false,false);spring(m) end
  local before=effectSnapshot(p,m);Batch.Pickup(p,m);if effectChanged(p,m,before)then questItem(p,m,'GrabUse')end;questItem(p,m,'ItemPickup');publish(p)
  task.defer(function() if m:GetAttribute('HeldBy')==p.UserId and grabUse and a~='Keyring' and a~='Jawbone' and a~='Doll' then grabUse(p,m) end end)
  return true,C.Items[a].name..' effect applied.'
 elseif action=='clearEffects' then
  for _,x in ipairs(table.clone(inv[p] or {})) do detach(p,x,false,true) end;cleanup(p);return true,'Item effects cleared.'
 elseif action=='throw' then
  local m=active(p);if not m then return false,'Hold an item first.' end
  local look=(states[p] and states[p].look) or r.CFrame.LookVector
  if not detach(p,m,true,true) then return false,'Could not throw that.' end
  if m.PrimaryPart then m.PrimaryPart.AssemblyLinearVelocity=look*math.clamp(tonumber(a) or 150,20,600)+Vector3.new(0,12,0) end
  return true,'Thrown.'
 elseif action=='bring' then
  local n=0;for _,x in ipairs(map.Interactive:GetChildren()) do if states[x] and x.PrimaryPart and not x:GetAttribute('HeldBy') and not x:GetAttribute('CargoStored') and not x:GetAttribute('AttachedTo') and not x:GetAttribute('ItemWearOwner') and not x:GetAttribute('FaceOwner') and not x:GetAttribute('MonsterCarried') and (x.PrimaryPart.Position-r.Position).Magnitude<(tonumber(a) or 60) then n+=1;parts(x,false,true);x:PivotTo(CFrame.new(r.Position+r.CFrame.LookVector*4+Vector3.new(math.random()-.5,1+n*.6,math.random()-.5)));states[x].restSince=os.clock() end end
  return true,'Brought '..n..' items.'
 elseif action=='target' then
  -- a = target model, b = 'delete' | 'freeze' | 'launch' | 'grow' | 'shrink'
  local m=a;if typeof(m)~='Instance' or not m:IsA('Model') or m.Parent~=map.Interactive or not states[m] or not m.PrimaryPart then return false,'Aim at a loose item.' end
  local holder=Players:GetPlayerByUserId(m:GetAttribute('HeldBy') or 0);if holder then detach(holder,m,false,true) end
  if b=='delete' then states[m]=nil;m:Destroy();return true,'Item deleted.'
  elseif b=='freeze' then local frozen=not m:GetAttribute('AdminFrozen');m:SetAttribute('AdminFrozen',frozen);m.PrimaryPart.Anchored=frozen;return true,frozen and 'Item frozen in place.' or 'Item unfrozen.'
  elseif b=='launch' then m.PrimaryPart.Anchored=false;m:SetAttribute('AdminFrozen',nil);m.PrimaryPart.AssemblyLinearVelocity=Vector3.new(0,160,0);return true,'Launched.'
  elseif b=='grow' or b=='shrink' then local s=math.clamp(m:GetScale()*(b=='grow' and 1.5 or 1/1.5),.2,8);m:ScaleTo(s);return true,'Scale '..string.format('%.2f',s)..'x.'
  end
 end
 return false,'Unknown item action.'
end
adminApi.Parent=SS
-- Gear shop spawn (live): GearShopServer asks for a registered, grabbable, unsellable gear item.
do
 local old=SS:FindFirstChild('SpawnGearItem');if old then old:Destroy()end
 local spawnGear=Instance.new('BindableFunction');spawnGear.Name='SpawnGearItem';spawnGear.Parent=SS
 spawnGear.OnInvoke=function(id,cf,charges)
  local entry=C.Items[id];local template=SS.CursedItemKit:FindFirstChild(id)
  if not entry or not(entry.gear or entry.reward)or not template or typeof(cf)~='CFrame'then return nil end
  local m=template:Clone();m.Name=(entry.reward and 'Reward_'or 'Gear_')..id;m:PivotTo(cf);m.Parent=map.Interactive;register(m)
  if entry.reward then m:SetAttribute('Value',entry.value);m:SetAttribute('LootValue',entry.value);return m end
  m:SetAttribute('Gear',true);m:SetAttribute('Value',0);m:SetAttribute('LootValue',0);if charges then m:SetAttribute('Charges',charges)end
  return m
 end
end
-- Editor-only verification entry point. Uses the same registration and pickup/sale contracts.
if Run:IsStudio()then
 local preview=Instance.new('BindableFunction');preview.Name='PreviewCursedBatch';preview.Parent=script
 preview.OnInvoke=function(id,pos)
  if not C.Items[id]or typeof(pos)~='Vector3'or not Batch.CanSpawn(id)then return nil end
  local m=SS.CursedItemKit[id]:Clone();m.Name='Preview_'..id;m:PivotTo(CFrame.new(pos));m.Parent=map.Interactive;register(m);return m
 end
end

-- Visible bounds relative to the authored pivot (Root may be padded or off-centre).
local boundsCache=setmetatable({},{__mode='k'})
lootBounds=function(template,refresh)
 local cached=boundsCache[template];if cached and not refresh then return cached end
 local pivot=template:GetPivot();local low=Vector3.new(math.huge,math.huge,math.huge);local high=-low
 local found=false
 for _,part in template:GetDescendants()do if part:IsA('BasePart')and part.Transparency<.99 and part.Name~='ItemGroundCollider'then
  local cf=pivot:ToObjectSpace(part.CFrame);local z=part.Size
  local half=Vector3.new(math.abs(cf.RightVector.X)*z.X+math.abs(cf.UpVector.X)*z.Y+math.abs(cf.LookVector.X)*z.Z,math.abs(cf.RightVector.Y)*z.X+math.abs(cf.UpVector.Y)*z.Y+math.abs(cf.LookVector.Y)*z.Z,math.abs(cf.RightVector.Z)*z.X+math.abs(cf.UpVector.Z)*z.Y+math.abs(cf.LookVector.Z)*z.Z)*.5
  local a,b=cf.Position-half,cf.Position+half
  low=Vector3.new(math.min(low.X,a.X),math.min(low.Y,a.Y),math.min(low.Z,a.Z));high=Vector3.new(math.max(high.X,b.X),math.max(high.Y,b.Y),math.max(high.Z,b.Z));found=true
 end end
 if not found then local z=template.PrimaryPart.Size;low=-z*.5;high=z*.5 end
 cached={size=high-low,centre=(low+high)*.5,bottom=low.Y};boundsCache[template]=cached;return cached
end
-- Centre and four footprint corners must actually rest on a flat, queryable surface.
local function supportedLootPosition(template,x,z,support,top,bottom,collidable)
 local bounds=lootBounds(template);local size=bounds.size
 local params=RaycastParams.new();params.FilterType=Enum.RaycastFilterType.Include;params.RespectCanCollide=collidable==true
 if collidable then params.FilterDescendantsInstances={support}
 else
  local visible={};for _,part in support:GetDescendants()do if part:IsA('BasePart')and part.CanQuery and part.Transparency<.95 then table.insert(visible,part)end end
  params.FilterDescendantsInstances=visible
 end
 local height
 for _,off in {Vector3.zero,Vector3.new(-size.X*.48,0,-size.Z*.48),Vector3.new(size.X*.48,0,-size.Z*.48),Vector3.new(-size.X*.48,0,size.Z*.48),Vector3.new(size.X*.48,0,size.Z*.48)}do
  local hit=workspace:Raycast(Vector3.new(x+off.X,top,z+off.Z),Vector3.new(0,bottom-top,0),params)
  if not hit or hit.Normal.Y<.9 then return end
  if height and math.abs(hit.Position.Y-height)>.12 then return end
  height=height or hit.Position.Y
 end
 return Vector3.new(x-bounds.centre.X,height-bounds.bottom+.035,z-bounds.centre.Z),height,size,bounds.centre
end
local function clearLootPosition(template,pos,surface)
 local bounds=lootBounds(template);
 -- Keys intentionally have non-queryable meshes. Reserve their real visible
 -- bounds explicitly so surface loot cannot cover the normal aim target.
 local centre=pos+bounds.centre
 for _,key in ipairs(map.Interactive:GetChildren())do
  if key:IsA('Model') and key.PrimaryPart and key:GetAttribute('Kind')=='key' then
   local kb=lootBounds(key);local cf=key:GetPivot();local kc=cf:PointToWorldSpace(kb.centre)
   local h=kb.size*.5
   local kh=Vector3.new(math.abs(cf.RightVector.X)*h.X+math.abs(cf.UpVector.X)*h.Y+math.abs(cf.LookVector.X)*h.Z,math.abs(cf.RightVector.Y)*h.X+math.abs(cf.UpVector.Y)*h.Y+math.abs(cf.LookVector.Y)*h.Z,math.abs(cf.RightVector.Z)*h.X+math.abs(cf.UpVector.Z)*h.Y+math.abs(cf.LookVector.Z)*h.Z)
   local delta=centre-kc
   if math.abs(delta.X)<bounds.size.X*.5+kh.X+.6 and math.abs(delta.Z)<bounds.size.Z*.5+kh.Z+.6 and math.abs(delta.Y)<bounds.size.Y*.5+kh.Y+.15 then return false end
  end
 end
local params=OverlapParams.new();params.FilterType=Enum.RaycastFilterType.Include
 params.FilterDescendantsInstances={map.Architecture,furniture,map.Interactive,map.Collision}
 for _,hit in workspace:GetPartBoundsInBox(CFrame.new(pos+bounds.centre),Vector3.new(math.max(.05,bounds.size.X-.04),math.max(.05,bounds.size.Y-.04),math.max(.05,bounds.size.Z-.04)),params)do
  if not(surface and hit:IsDescendantOf(surface))and(hit.CanCollide or hit.Transparency<1)then return false end
 end
 return true
end

local dropPlacement=require(script:WaitForChild('TouchDropPlacement'))
touchDropPosition=function(p,m,ray)
 return dropPlacement.Find(p,m,ray,{Map=map,Rooms=roomTypes,Bounds=lootBounds,Supported=supportedLootPosition})
end

-- Initial items require real surface support, not a furniture bounding-box height.
local surfaces={}
for _,m in ipairs(furniture:GetChildren()) do if m.Name:find('_Table') or m.Name:find('_Desk') or m.Name:find('_Counter') or m.Name:find('_Nightstand') or m.Name:find('_Dresser') or m.Name:find('_Crate') then table.insert(surfaces,m) end end
local searchStart=map:GetAttribute('SpawnPosition') or workspace.SpawnLocation.Position
local function surfaceRoom(m) return m.PrimaryPart and m.PrimaryPart:GetAttribute('Room') or m.Name end
local slots={};local used={}
-- Every collectible is eligible in every map and round.
local function eligibleItems()
 local list,seen={},{}
 for _,id in ipairs(C.Order)do
  local meta=C.Items[id];local template=SS.CursedItemKit:FindFirstChild(id)
  if not seen[id]and meta and template and template:IsA('Model')and template.PrimaryPart and (not meta.coop or Batch.CanSpawn(id))then seen[id]=true;table.insert(list,id)end
 end
 return list
end
local eligible=eligibleItems()


-- Each item reserves its own size; the largest are placed first so small items
-- cannot take the only surfaces big enough for an anvil or a helium tank.
local function itemSize(id) return lootBounds(SS.CursedItemKit[id]).size end
local initialLoot=false
local function initialMissionLoot()
 if initialLoot then return end;initialLoot=true
 for i=#eligible,2,-1 do local j=rng:NextInteger(1,i);eligible[i],eligible[j]=eligible[j],eligible[i] end
 local placeOrder={};for index=1,math.min(30,#eligible*2) do table.insert(placeOrder,{id=eligible[(index-1)%#eligible+1],rank=index}) end
 table.sort(placeOrder,function(a,b) local sa,sb=itemSize(a.id),itemSize(b.id);local fa,fb=sa.X*sa.Z,sb.X*sb.Z;if math.abs(fa-fb)>1e-3 then return fa>fb end;return a.rank<b.rank end)
 for index=1,#placeOrder do local id=placeOrder[index].id;if index<=30 then
 local template=SS.CursedItemKit[id];local size=itemSize(id);local chosen,chosenSurface
 table.sort(surfaces,function(a,b) local au=used[surfaceRoom(a)] and 1 or 0;local bu=used[surfaceRoom(b)] and 1 or 0;if au~=bu then return au<bu end;local bias=index<=3 and 80 or 0;local ar=roomTypes[surfaceRoom(a)];local br=roomTypes[surfaceRoom(b)];local da=(a:GetPivot().Position-searchStart).Magnitude+(ar and ar.level or 0)*bias;local db=(b:GetPivot().Position-searchStart).Magnitude+(br and br.level or 0)*bias;if math.abs(da-db)>.01 then return da<db end;return a.Name<b.Name end)
 for _,surface in ipairs(surfaces) do
  if chosen then break end
  local cf=surface:GetPivot();local _,box=surface:GetBoundingBox()
  if (surface:GetPivot().Position-searchStart).Magnitude>22 and box.X>size.X+.8 and box.Z>size.Z+.8 then
   local centre=surface:GetBoundingBox();local top=centre.Position.Y+box.Y/2
   local offsets=box.X>size.X*3+1.2 and {Vector3.new(-box.X*.3,0,0),Vector3.zero,Vector3.new(box.X*.3,0,0)} or {Vector3.new(-box.X*.25,0,0),Vector3.new(box.X*.25,0,0)}
   -- Cruise's rounded tops support these footprints at centre, where quarter probes can miss.
   if (map:GetAttribute('MapKind')=='Cruise' or map:GetAttribute('MapKind')=='Hotel') and not table.find(offsets,Vector3.zero)then table.insert(offsets,1,Vector3.zero)end
   if map:GetAttribute('MapKind')=='Hotel' then
    for _,x in ipairs({-box.X*.25,0,box.X*.25})do for _,z in ipairs({-box.Z*.25,0,box.Z*.25})do if z~=0 then table.insert(offsets,Vector3.new(x,0,z))end end end
   end
   for _,off in ipairs(offsets) do
    local pos,height=supportedLootPosition(template,centre.Position.X+off.X,centre.Position.Z+off.Z,surface,top+.25,centre.Position.Y-box.Y*.5-.25,false)
    local good=pos~=nil
    if good then for _,a in ipairs(slots)do
     local c=pos+lootBounds(template).centre;local ac=a.p+Vector3.new(0,a.s.Y*.5,0)
     if math.abs(ac.X-c.X)<(a.s.X+size.X)/2+.2 and math.abs(ac.Z-c.Z)<(a.s.Z+size.Z)/2+.2 and math.abs(ac.Y-c.Y)<(a.s.Y+size.Y)/2+.1 then good=false end
    end end
    if good and not clearLootPosition(template,pos,surface)then good=false end
    if good then chosen=pos;chosenSurface=surface;break end
   end
  end
  if chosen then break end
 end
 if chosen then if chosenSurface then used[surfaceRoom(chosenSurface)]=true end;local m=template:Clone();m.Name='Cursed_'..id;m:PivotTo(CFrame.new(chosen));m.Parent=map.Interactive;register(m);table.insert(slots,{p=Vector3.new(chosen.X+lootBounds(template).centre.X,chosen.Y+lootBounds(template).bottom-.035,chosen.Z+lootBounds(template).centre.Z),s=size,id=id,surface=chosenSurface}) else warn('[CursedItems] No safe surface for '..id) end
end end
map:SetAttribute('LootRequested',#placeOrder);map:SetAttribute('LootPlaced',#slots)
map:SetAttribute('LootReady',true)
end
if missionRunning()then initialMissionLoot()end
local lobbyState=RS:FindFirstChild('LobbyState')
if lobbyState then lobbyState:GetAttributeChangedSignal('Mode'):Connect(function()if lobbyState:GetAttribute('Mode')=='Mission'then initialMissionLoot()end end)end
-- Fresh per-level bag: duplicates in C.Order must not give an id extra tickets.
local function shuffledLootBag(ids)
 local bag=table.clone(ids)
 for i=#bag,2,-1 do local j=rng:NextInteger(1,i);bag[i],bag[j]=bag[j],bag[i]end
 return bag
end
local function consumeLootId(bag,id)
 local at=table.find(bag,id);if at then table.remove(bag,at)end
end
-- Augmenting paths reserve scarce fitting surfaces rather than greedily stranding ids.
-- Only ids remaining in this bag participate. A new bag starts only after all were spawned.
local function matchLootBag(bag,slots,count,occupied)
 local byId,bySlot={},{}
 local function assign(index,seen)
  for _,id in ipairs(bag)do
   local size=itemSize(id);local slot=slots[index]
   if not seen[id]and size.X<=slot.s.X and size.Z<=slot.s.Z then
    seen[id]=true
    local previous=byId[id]
    if not previous or assign(previous,seen)then byId[id]=index;bySlot[index]=id;return true end
   end
  end
  return false
 end
 for i=1,count do if not occupied[i]then assign(i,{})end end
 return bySlot
end
local Budget=require(script:WaitForChild('LootBudget'))
local refreshQuestEventWorld
local function restock(round,quota)
 table.clear(questSpawnOrdinals)
 initialMissionLoot()
 Batch.ClearLevel()
 eligible=eligibleItems()
 if #eligible==0 then map:SetAttribute('AvailableLootValue',0);return 0 end
 for _,p in Players:GetPlayers()do p:SetAttribute('MoustacheFace',nil)end
 for _,p in ipairs(Players:GetPlayers()) do for _,m in ipairs(table.clone(inv[p] or {})) do detach(p,m,false,true) end end
 for m,s in pairs(states) do if typeof(m)=='Instance' and m:IsA('Model') then m:Destroy();states[m]=nil end end
 local floorArea=0;for _,r in game.HttpService:JSONDecode(map.GeneratedGraph.Value).rooms do if r.type~='Stair' and r.x1 and r.x2 and r.z1 and r.z2 then floorArea+=(r.x2-r.x1)*(r.z2-r.z1)end end
 local plan=Budget.Plan(round,quota,map:GetAttribute('MapKind'),floorArea>0 and floorArea or nil)
 local requested=#slots;local placed,boxes,values={},{},{}
 -- Distance bands by room depth from the start room: half the loot near spawn, a quarter further, a quarter farthest.
 local order={};for _,r in game.HttpService:JSONDecode(map.GeneratedGraph.Value).rooms do if r.type~='Stair' then order[#order+1]=r end end
 table.sort(order,function(a,b) return ((a.depth or -1)>=0 and a.depth or 99)<((b.depth or -1)>=0 and b.depth or 99) end)
 local bandByRoom={};for i,r in order do bandByRoom[r.name]=if i<=#order/3 then 1 elseif i<=#order*2/3 then 2 else 3 end
 local function bandOfName(name)
  if not name then return 1 end
  if bandByRoom[name] then return bandByRoom[name] end
  local best,len=1,0;for room,b in bandByRoom do if #room>len and name:sub(1,#room)==room then best,len=b,#room end end -- furniture is named <room>_<piece>
  return best
 end
 local want={math.ceil(plan.count*.5),math.ceil(plan.count*.25),0};want[3]=math.max(0,plan.count-want[1]-want[2])
 local have,bands,tries={0,0,0},{},{0,0,0}
 local onSurface={} -- at most one item per table/desk/counter per level, so loot never piles up on one surface
 local bag=shuffledLootBag(eligible);local selected={}
 while true do
  local matched=matchLootBag(bag,slots,requested,selected);local progress=0
  for i=1,requested do local id=matched[i];if id then selected[i]=id;consumeLootId(bag,id);progress+=1 end end
  if progress==0 or #bag>0 then break end
  bag=shuffledLootBag(eligible)
 end
 local function clearBoxes(id,pos)
  local b=lootBounds(SS.CursedItemKit[id]);local c=pos+b.centre
  for _,old in boxes do local d=c-old.c
   if math.abs(d.X)<(b.size.X+old.s.X)*.5+.3 and math.abs(d.Z)<(b.size.Z+old.s.Z)*.5+.3 and math.abs(d.Y)<(b.size.Y+old.s.Y)*.5+.1 then return false end
  end
  return true
 end
 local function place(id,pos,room)
  local template=SS.CursedItemKit[id];local b=lootBounds(template)
  local m=template:Clone();m.Name='Loot_'..round..'_'..(#placed+1);m:PivotTo(CFrame.new(pos));m.Parent=map.Interactive;register(m)
  if room then m:SetAttribute('Room',room)end
  placed[#placed+1]=m;boxes[#boxes+1]={c=pos+b.centre,s=b.size};values[#values+1]=Budget.Value(id,plan,rng)
  local band=bandOfName(room);bands[#placed]=band;have[band]+=1
 end
 for i=1,requested do
  if #placed>=plan.count then break end
  local slot=slots[i];local id=selected[i];if not id then continue end;local template=SS.CursedItemKit[id]
  if have[bandOfName(slot.surface and surfaceRoom(slot.surface))]>=want[bandOfName(slot.surface and surfaceRoom(slot.surface))] then table.insert(bag,id);continue end
  if slot.surface and onSurface[slot.surface] then table.insert(bag,id);continue end
  local pos=supportedLootPosition(template,slot.p.X,slot.p.Z,slot.surface,slot.p.Y+1,slot.p.Y-1,false)
  if not pos or not clearLootPosition(template,pos,slot.surface)or not clearBoxes(id,pos)then table.insert(bag,id);continue end
  place(id,pos,slot.surface and surfaceRoom(slot.surface));if slot.surface then onSurface[slot.surface]=true end
 end
 -- Extra room spots keep circulation halls, stairs, van access and interaction approaches clear.
 local rooms={};for _,room in game.HttpService:JSONDecode(map.GeneratedGraph.Value).rooms do
  if room.type~='Hall'and room.type~='Stair'and room.type~='Foyer'then rooms[#rooms+1]=room end
 end
 local roomsByBand={{},{},{}};for _,r in rooms do table.insert(roomsByBand[bandOfName(r.name)],r) end
 local keepouts={}
 for _,m in map.Interactive:GetChildren()do
  if m:IsA('Model')and m.PrimaryPart and(m:GetAttribute('Kind')=='door'or m:GetAttribute('Kind')=='key'or m:GetAttribute('Closet')or m.Name:find('Mover_'))then keepouts[#keepouts+1]=m.PrimaryPart.Position end
 end
 for _,m in map.Closets:GetChildren()do if m:IsA('Model')then keepouts[#keepouts+1]=m:GetPivot().Position end end
 local camp=workspace:FindFirstChild('RecoveryCamp');local van=camp and camp:FindFirstChild('AnomalyRecoveryVan')
 local attempts=math.min(4096,math.max(192,plan.count*24));local perRoom={}
 for attempt=1,attempts do
  if #placed>=plan.count or #rooms==0 then break end
  local need=if have[1]<want[1] then 1 elseif have[2]<want[2] then 2 else 3
  tries[need]+=1
  if tries[need]>attempts/4 and have[need]<want[need] then -- band has no more safe spots: hand its share of items onward
   local d=want[need]-have[need];want[need]=have[need];if need<3 then want[need+1]+=d end;continue
  end
  local pool=if #roomsByBand[need]>0 then roomsByBand[need] else rooms
  local room=pool[rng:NextInteger(1,#pool)]
  if(perRoom[room.name]or 0)>=16 then continue end
  if #bag==0 then bag=shuffledLootBag(eligible)end
  local id=bag[rng:NextInteger(1,#bag)];local template=SS.CursedItemKit[id];local size=lootBounds(template).size
  local ax,bx=room.x1+math.max(3,size.X*.5+1.2),room.x2-math.max(3,size.X*.5+1.2)
  local az,bz=room.z1+math.max(3,size.Z*.5+1.2),room.z2-math.max(3,size.Z*.5+1.2)
  if bx<ax or bz<az then continue end
  local x,z=rng:NextNumber(ax,bx),rng:NextNumber(az,bz)
  local pos=supportedLootPosition(template,x,z,map.Collision,room.level*16+2,room.level*16-2,true)
  local safe=pos~=nil and(not van or Vector3.new(pos.X-van:GetPivot().X,0,pos.Z-van:GetPivot().Z).Magnitude>44)
  if safe then for _,point in keepouts do if math.abs(point.Y-room.level*16)<8 and Vector3.new(x-point.X,0,z-point.Z).Magnitude<5 then safe=false;break end end end
  if safe and clearLootPosition(template,pos,nil)and clearBoxes(id,pos)then
   place(id,pos,room.name);consumeLootId(bag,id);perRoom[room.name]=(perRoom[room.name]or 0)+1
  end
 end
 -- Every locked room holds at least one item: finding its key is always worth it.
 local lockedRooms={}
 for _,m in map.Interactive:GetChildren()do
  if m:IsA('Model')and m:GetAttribute('Kind')=='door'and m:GetAttribute('Locked')and m:GetAttribute('Room')then lockedRooms[m:GetAttribute('Room')]=true end
 end
 if next(lockedRooms)then
  local hasItem={};for _,m in placed do local r=m:GetAttribute('Room');if r then hasItem[r]=true end end
  local roomByName={};for _,r in game.HttpService:JSONDecode(map.GeneratedGraph.Value).rooms do roomByName[r.name]=r end
  for name in lockedRooms do
   local room=roomByName[name]
   if room and not hasItem[name]then
    for _=1,120 do
     if #bag==0 then bag=shuffledLootBag(eligible)end
     local id=bag[rng:NextInteger(1,#bag)];local template=SS.CursedItemKit[id];local size=lootBounds(template).size
     local ax,bx=room.x1+math.max(2,size.X*.5+1),room.x2-math.max(2,size.X*.5+1)
     local az,bz=room.z1+math.max(2,size.Z*.5+1),room.z2-math.max(2,size.Z*.5+1)
     if bx>=ax and bz>=az then
      local x,z=rng:NextNumber(ax,bx),rng:NextNumber(az,bz)
      local pos=supportedLootPosition(template,x,z,map.Collision,room.level*16+2,room.level*16-2,true)
      local safe=pos~=nil
      if safe then for _,point in keepouts do if math.abs(point.Y-room.level*16)<8 and Vector3.new(x-point.X,0,z-point.Z).Magnitude<4 then safe=false;break end end end
      if safe and clearLootPosition(template,pos,nil)and clearBoxes(id,pos)then place(id,pos,name);consumeLootId(bag,id);break end
     end
    end
   end
  end
 end
 -- Capacity is finite; spread any residual shortfall across the actual safe items.
 local total=Budget.Distribute(values,bands,plan.value)
 map:SetAttribute('LootBandCounts',have[1]..'/'..have[2]..'/'..have[3])
 for i,m in placed do m:SetAttribute('Value',values[i]);m:SetAttribute('LootValue',values[i])end
 map:SetAttribute('LootRequested',plan.count);map:SetAttribute('LootPlaced',#placed)
 map:SetAttribute('LootTargetValue',plan.value);map:SetAttribute('LootTargetRatio',plan.ratio)
 map:SetAttribute('AvailableLootValue',total)
 if refreshQuestEventWorld then task.defer(refreshQuestEventWorld)end
 return total
end

local stock=Instance.new('BindableFunction');stock.Name='RecoveryLootApi';stock.OnInvoke=function(action,a,b) if action=='restock' then return restock(a,b) elseif action=='remove' and states[a] and not a:GetAttribute('HeldBy') and not a:GetAttribute('ItemWearOwner') and not a:GetAttribute('AttachedTo')then states[a]=nil;a:Destroy();return true end return false end;stock.Parent=SS
-- Secrets are optional rewards, never routes required to complete the map.
-- Plaques sit on the room's north wall near its west corner; slide along the wall past any diagonal corner cut.
local AngledCorners=require(game:GetService('ServerScriptService').MapGen:WaitForChild('AngledCorners'))
local function secretX(room)
 local x=room.x1+2
 while x<room.x2-2 and AngledCorners.Blocked(map,Vector3.new(x,room.level*16,room.z1+.75),1.2) do x+=1 end
 return x
end
local secrets=Instance.new('Folder');secrets.Name='CursedSecrets';secrets.Parent=map
local graph=game:GetService('HttpService'):JSONDecode(map.GeneratedGraph.Value)
for i=1,math.min(6,#graph.rooms) do
 local room=graph.rooms[math.max(1,math.floor(i*#graph.rooms/6))]
 local plaque=Instance.new('Part');plaque.Name='Secret_'..i;plaque.Size=Vector3.new(2,.9,.08);plaque.Anchored=true;plaque.CanCollide=false;plaque.CanQuery=false;plaque.Transparency=1;plaque.CFrame=CFrame.new(secretX(room),room.level*16+5,room.z1+.75);plaque:SetAttribute('SecretText','THE HOUSE REMEMBERS '..i..' - interact to claim treasure');plaque.Parent=secrets
end
-- Optional invisible stair-bridge: no required route or doorway depends on it.
local bridge=Instance.new('Folder');bridge.Name='HiddenBridge';bridge.Parent=map
for _,room in ipairs(graph.rooms) do
 if false and room.x2-room.x1>=14 and room.z2-room.z1>=30 then -- invisible stair-bridge removed: solid steps with no mesh read as a collision glitch
  local positions={};local good=true
  for i=1,4 do
   local pos=Vector3.new((room.x1+room.x2)/2,room.level*16+.4+i*.65,room.z1+4+i*4)
   local params=OverlapParams.new();params.FilterType=Enum.RaycastFilterType.Include;params.FilterDescendantsInstances={furniture,map.Interactive,map.Collision}
   for _,hit in ipairs(workspace:GetPartBoundsInBox(CFrame.new(pos+Vector3.new(0,1,0)),Vector3.new(3,2.5,4),params)) do if hit.CanCollide or hit.Transparency<1 then good=false end end
   table.insert(positions,pos)
  end
  if good then
   for i,pos in ipairs(positions) do local x=Instance.new('Part');x.Name='InvisibleBridge_'..i;x.Size=Vector3.new(3,.25,4);x.CFrame=CFrame.new(pos);x.Anchored=true;x.CanCollide=true;x.CanQuery=false;x.CanTouch=false;x.Transparency=1;x.Material=Enum.Material.Slate;x.Color=Color3.fromRGB(92,157,133);x.Parent=bridge end
   local treasure=Instance.new('Part');treasure.Name='BridgeTreasure';treasure.Size=Vector3.new(.8,.8,.8);treasure.CFrame=CFrame.new(positions[4]+Vector3.new(0,3,0));treasure.Anchored=true;treasure.CanCollide=false;treasure.CanQuery=false;treasure.Transparency=1;treasure:SetAttribute('ClaimDistance',2.5);treasure:SetAttribute('SecretText','HIDDEN BRIDGE TREASURE - interact to claim');treasure.Parent=secrets;break
  end
 end
end
local nextPulse=os.clock()+65;map:SetAttribute('NextDangerPulse',workspace:GetServerTimeNow()+65)
local accumulator=0
-- Repair only released physical loot: worn, carried and cart-stored items keep their own lifecycle.
local function recoverDropped(m,s,now)
 local r=m.PrimaryPart;local collider=m:FindFirstChild('ItemGroundCollider')
 if not r or r.Anchored or not collider or not collider.CanCollide or m:GetAttribute('HeldBy')or m:GetAttribute('FaceOwner')or m:GetAttribute('ItemWearOwner')or m:GetAttribute('CargoStored')then return end
 if now<(s.groundCheck or 0)then return end;s.groundCheck=now+.75
 local cf,z=collider.CFrame,collider.Size
 local half=(math.abs(cf.RightVector.Y)*z.X+math.abs(cf.UpVector.Y)*z.Y+math.abs(cf.LookVector.Y)*z.Z)*.5
 local params=RaycastParams.new();params.FilterType=Enum.RaycastFilterType.Include
 local camp=workspace:FindFirstChild('RecoveryCamp');params.FilterDescendantsInstances=camp and {map.Collision,camp}or {map.Collision};params.RespectCanCollide=true
 local hit=workspace:Raycast(cf.Position+Vector3.new(0,half+.6,0),Vector3.new(0,-(half*2+2),0),params)
 if hit and hit.Normal.Y>.8 then
  if cf.Position.Y-half<hit.Position.Y-.1 and r.AssemblyLinearVelocity.Magnitude<1 and now-(s.restSince or now)>1 then
   m:PivotTo(m:GetPivot()+Vector3.new(0,hit.Position.Y+half+.08-cf.Position.Y,0));r.AssemblyLinearVelocity=Vector3.zero;r.AssemblyAngularVelocity=Vector3.zero
  end
  s.safeDropFrame=m:GetPivot()
 elseif r.Position.Y<-8 then
  m:PivotTo(s.safeDropFrame or s.origin);r.AssemblyLinearVelocity=Vector3.zero;r.AssemblyAngularVelocity=Vector3.zero
 end
end
Run.Heartbeat:Connect(function(dt)
 if missionRunning()then
 for item,state in pairs(states)do if typeof(item)=='Instance'and item:IsA('Model')and item.PrimaryPart and item.Parent and item:GetAttribute('ItemId')=='Clock'and not item:GetAttribute('HeldBy')and state.clockImpact and os.clock()-state.clockImpact<5 then state.impactVelocity=math.max(state.impactVelocity or 0,-item.PrimaryPart.AssemblyLinearVelocity.Y)end end
 end
 local now=os.clock()
 for p,list in pairs(inv) do
  local r,h=root(p);if not r or not h or h.Health<=0 then continue end
  local look=states[p] and states[p].look or r.CFrame.LookVector
  for i,m in ipairs(list) do if m.Parent and m.PrimaryPart then
   if m:GetAttribute('FaceOwner')or m:GetAttribute('ItemWearOwner')then continue end
   -- Holding a cursed item near water washes it clean (checked twice a second).
   do local st=states[m];if not m:GetAttribute('LobbyToy') and st and now>=(st.waterCheck or 0)then st.waterCheck=now+.5;if now>=(st.washedUntil or 0)and nearWater(p)then use(p,m,true)end end end
   local head=p.Character:FindFirstChild('Head');local camera=states[p] and states[p].camera or CFrame.lookAt(head and head.Position or r.Position+Vector3.new(0,1,0),(head and head.Position or r.Position+Vector3.new(0,1,0))+look)
   local pose=p:GetAttribute('TouchCarry') and HoldPose.Item(camera,HoldPose.LeftGrip(camera),m) or camera*CFrame.new(0,-.35,-(p:GetAttribute('HoldDistance')or 6));if m:GetAttribute('ItemId')=='Mirror' and not p:GetAttribute('TouchCarry') then pose=camera*CFrame.new(0,.55,-(p:GetAttribute('HoldDistance')or 4.8))*CFrame.Angles(0,math.pi,0) end;if m:GetAttribute('ItemId')=='FearMirror' and not p:GetAttribute('TouchCarry') then pose=camera*CFrame.new(0,-.45,-2.6)*CFrame.Angles(0,math.pi,0) end;local goal=i==1 and pose.Position or r.Position-r.CFrame.RightVector*1.4+Vector3.new(0,-.3,0)
   if m:GetAttribute('ItemId')=='Balloon'then pose=CFrame.new(r.Position+Vector3.new(0,4.5,0))*r.CFrame.Rotation;goal=pose.Position end
   local params=RaycastParams.new();params.FilterType=Enum.RaycastFilterType.Include;local blockers={m:GetAttribute('LobbyToy') and workspace.LobbyWorld or map.Collision};local camp=workspace:FindFirstChild('RecoveryCamp');if camp and not m:GetAttribute('LobbyToy')then table.insert(blockers,camp)end;for _,door in ipairs(map.Interactive:GetChildren())do if door:GetAttribute('Kind')=='door'then table.insert(blockers,door)end end;params.FilterDescendantsInstances=blockers;params.RespectCanCollide=true
   local hit=workspace:Raycast(r.Position+Vector3.new(0,1,0),goal-r.Position-Vector3.new(0,1,0),params)
   if hit then goal=hit.Position-hit.Normal*.1+hit.Normal*math.max(.65,m.PrimaryPart.Size.Magnitude*.25) end
    -- Remembered so a drop lands where the holder saw the item, not where the lagging body is.
    if i==1 and states[m] then states[m].holdGoal=goal end
   local align=m.PrimaryPart:FindFirstChild('Hold_Position');local rotate=m.PrimaryPart:FindFirstChild('Hold_Orientation')
   if align then align.Position=goal end;if rotate then rotate.CFrame=pose.Rotation end
   if (m.PrimaryPart.Position-r.Position).Magnitude>HOLD_SNAP_DISTANCE then
     m:PivotTo(CFrame.new(goal));m.PrimaryPart.AssemblyLinearVelocity=Vector3.zero
    end
  end end
 end
 accumulator+=dt;if accumulator<.25 then return end;local tick=accumulator;accumulator=0
 if missionRunning() and now>=nextPulse then nextPulse=now+65;map:SetAttribute('NextDangerPulse',workspace:GetServerTimeNow()+65);for _,n in ipairs(monsters()) do n:SetAttribute('AgitatedUntil',now+12) end;for _,piano in ipairs(pianos) do piano:SetAttribute('PlayingUntil',now+10);local song=piano:FindFirstChild('HauntedPianoSong',true);if song and not song.IsPlaying then song.SoundId=song:GetAttribute('FirstTrack');song.TimePosition=0;song:Play() end end;if #pianos==0 then fallbackMusicUntil=now+10 end end
 for _,piano in ipairs(pianos) do if missionRunning() and now<(piano:GetAttribute('PlayingUntil') or 0) and now-(piano:GetAttribute('LastNoteAt') or 0)>2 then piano:SetAttribute('LastNoteAt',now);noise(piano:GetPivot().Position,12,'haunted piano music',piano) end end
 for m,s in pairs(states) do if typeof(m)=='Instance' and m:IsA('Model') then
  if not m.Parent then states[m]=nil;continue end
   if not m.PrimaryPart then continue end
  local id=m:GetAttribute('ItemId')
  -- Selected lobby toys use Batch's shared effects; skip the mission item simulation.
  if m:GetAttribute('LobbyToy') or not missionRunning()then continue end
  if m:GetAttribute('AttachedTo')then continue end
  -- Carried by a creature: inert until dropped. A creature removed mid-carry drops it where it is.
  if m:GetAttribute('MonsterCarried')then local w=m.PrimaryPart:FindFirstChild('MonsterCarryWeld');if w and w.Part0 and w.Part0.Parent then continue end;monsterDrop(m) end
  recoverDropped(m,s,now)
  if (id=='Moustache'or id=='CoolSunglasses') and s.faceOwner then
   local facePlayer=s.faceOwner;local _,faceHum=root(facePlayer)
   local faceHead=facePlayer.Character and facePlayer.Character:FindFirstChild('Head');if faceHead then m:PivotTo(faceHead.CFrame*faceOffset(m))end
   if not facePlayer.Parent or not faceHum or faceHum.Health<=0 or facePlayer:GetAttribute('MonsterJumpscareActive') then releaseFace(m)
   elseif s.pullStart and m:GetAttribute('HeldBy')==facePlayer.UserId then
    local progress=math.clamp((now-s.pullStart)/3,0,1);m:SetAttribute('MoustachePullProgress',progress)
    if progress>=1 then releaseFace(m);parts(m,false,false);spring(m)end
   elseif s.fallAt and now>=s.fallAt then releaseFace(m);local faceRoot=root(facePlayer);if faceRoot then m.PrimaryPart.AssemblyLinearVelocity=faceRoot.CFrame.LookVector*2+Vector3.new(0,-1,0)end end
  end
  local owner=Players:GetPlayerByUserId(m:GetAttribute('HeldBy') or 0);local r,h;if owner then r,h=root(owner) end
  local pos=m.PrimaryPart.Position;local enemy,distance=nearestMonster(pos)
  local function emit(radius,label,interval) if now-s.lastNoise>(interval or 4) then s.lastNoise=now;noise(pos,radius,label,m) end end
  if id=='Shadow' and r then
   if not s.ghost then
    local archived=r.Parent.Archivable;r.Parent.Archivable=true;s.ghost=r.Parent:Clone();r.Parent.Archivable=archived;s.ghost.Name='SecondShadow';for _,x in ipairs(s.ghost:GetDescendants()) do if x:IsA('LuaSourceContainer') or x:IsA('Humanoid') or x:IsA('Tool') then x:Destroy() elseif x:IsA('BasePart') then x.Anchored=true;x.CanCollide=false;x.CanQuery=false;x.CanTouch=false;x.Color=Color3.fromRGB(12,10,17);x.Material=Enum.Material.SmoothPlastic;x.Transparency=.45 end end;s.ghost.Parent=workspace;s.ghost:PivotTo(r.CFrame);s.history={}
   end
   table.insert(s.history,r.CFrame);if #s.history>10 then local cf=table.remove(s.history,1);s.ghost:PivotTo(cf);local close=nearestMonster(cf.Position);if close and (close.PrimaryPart.Position-cf.Position).Magnitude<7 then close:SetAttribute('LurePosition',r.Position);close:SetAttribute('LureUntil',now+8) end end
  elseif id=='Doll' then m:SetAttribute('Danger',math.clamp(1-distance/65,0,1));if distance<65 and not m:GetAttribute('Quiet') then emit(75,'doll crying',math.max(1, distance/15)) end
  elseif id=='Compass' then
   local target=enemy and distance<32 and enemy.PrimaryPart or nil;local best=math.huge
   if not target then for _,k in ipairs(map.Interactive:GetChildren()) do if k:GetAttribute('Kind')=='key' and k.PrimaryPart then local dd=(k.PrimaryPart.Position-pos).Magnitude;if dd<best then best=dd;target=k.PrimaryPart end end end end
   m:SetAttribute('PointerTarget',target and target.Position or pos);m:SetAttribute('NeedleShake',distance<45)
  elseif id=='Teddy' and owner then s.arm=math.min(1,s.arm+tick*.018);owner:SetAttribute('TeddyObscure',s.arm)
  elseif id=='Backpack' and owner then if now>s.bite-8 then owner:SetAttribute('CursedHint','Backpack hungry: use to feed a valuable.') end;if now>s.bite then valuable(owner,-math.min(2,owner:GetAttribute('Valuables') or 0));s.bite=now+25;emit(95,'backpack chewing',1) end
  elseif id=='Clock' then
   if not m:GetAttribute('ClockBroken') then
    if not owner and s.clockImpact and now-s.clockImpact<5 then
     local params=RaycastParams.new();params.FilterType=Enum.RaycastFilterType.Include;params.FilterDescendantsInstances={map.Collision,workspace:FindFirstChild('RecoveryCamp')};params.RespectCanCollide=true
     local hit=workspace:Raycast(s.lastPos,pos-s.lastPos+Vector3.new(0,-m.PrimaryPart.Size.Y/2-.35,0),params)
     if hit and hit.Normal.Y>.65 and (s.impactVelocity or 0)>12 then
      m:SetAttribute('ClockBroken',true);m:SetAttribute('ClockRinging',false);m:SetAttribute('DisplayName','Smashed alarm clock');s.ring=math.huge;noise(pos,45,'clock smashed',m)
      for _,sound in ipairs(m:GetDescendants())do if sound:IsA('Sound')then sound:Stop()end end
      event:FireAllClients('clockSmashed',m)
     end
     s.impactVelocity=math.max(s.impactVelocity or 0,-m.PrimaryPart.AssemblyLinearVelocity.Y)
    end
    if now>=s.ring and not s.ringingUntil then s.ringingUntil=now+rng:NextNumber(5,9);m:SetAttribute('ClockRinging',true)end
    if s.ringingUntil then
     if now<s.ringingUntil then emit(70,'alarm ringing',2)else s.ringingUntil=nil;s.ring=now+rng:NextNumber(25,65);m:SetAttribute('ClockRinging',false);event:FireAllClients('clockQuiet',m)end
    end
   end
   m:SetAttribute('SecondsToEvent',m:GetAttribute('ClockBroken')and -1 or math.max(0,math.floor(s.ring-now)))
  elseif id=='Horn' then if s.extended then emit(80,'party horn',3);m:SetAttribute('HornLength',20);if now>s.retractAt then s.extended=false end else m:SetAttribute('HornLength',0) end
  elseif id=='Present' and s.follow and now<s.followUntil and s.lastOwner then local pr=root(s.lastOwner);if pr then m:SetAttribute('FollowerTarget',pr.Position);emit(50,'gift follower',5) end
  elseif id=='Cake' and r then s.meter=math.min(100,s.meter+tick*.25+math.max(0,r.AssemblyLinearVelocity.Magnitude-12)*tick*.25);m:SetAttribute('CurseMeter',s.meter);if r.AssemblyLinearVelocity.Magnitude>6 then emit(40,'frosting trail',7);event:FireAllClients('frosting',r.Position,s.meter) end
  elseif id=='Crown' and owner then if enemy then enemy:SetAttribute('LurePosition',Vector3.new(unpack(graph.rooms[1] and {0,3,graph.rooms[1].z2} or {0,3,0})));enemy:SetAttribute('LureUntil',now+2) end;emit(80,'birthday child',10)
  elseif id=='Clown' and not owner and s.owner and not m:GetAttribute('CargoStored') then
   local pr=root(s.owner);local destination=now<(s.wind or 0) and s.destination or pr and pr.Position
   if destination then parts(m,false,true);local delta=destination-pos;if delta.Magnitude>1 then m.PrimaryPart.AssemblyLinearVelocity=Vector3.new(delta.Unit.X*5,m.PrimaryPart.AssemblyLinearVelocity.Y,delta.Unit.Z*5) end;emit(75,now<(s.wind or 0) and 'clown footsteps' or 'clown screaming',3) end
  elseif id=='MusicBox' then if now<(s.wind or 0) then for _,n in ipairs(monsters()) do if n.PrimaryPart and (n.PrimaryPart.Position-pos).Magnitude<28 then n:SetAttribute('CalmUntil',now+1) end end;m:SetAttribute('Playing',true);emit(15,'gift music',2) else m:SetAttribute('Playing',false) end
  elseif id=='Bracelet' and owner and s.partner then local pr=root(s.partner);if pr then owner:SetAttribute('BraceletPosition',pr.Position);if (pr.Position-r.Position).Magnitude>45 then emit(100,'bracelet ringing',4) end end
  elseif id=='Portrait' then m:SetAttribute('PointerTarget',enemy and enemy.PrimaryPart.Position or pos);if owner and r and r.AssemblyLinearVelocity.Magnitude<1 and (s.lastSpeed or 0)>12 then say(owner,'Portrait: "Watch where you are going."');event:FireAllClients('speech',pos,'Watch where you are going.');emit(45,'portrait criticism',3) end;s.lastSpeed=r and r.AssemblyLinearVelocity.Magnitude or 0
  elseif id=='Keyring' and r and not m:GetAttribute('Quiet') and r.AssemblyLinearVelocity.Magnitude>10 then emit(70,'keys jingling',3)
  elseif id=='Jawbone' then local secretD=math.huge;for _,x in ipairs(secrets:GetChildren()) do secretD=math.min(secretD,(x.Position-pos).Magnitude) end;m:SetAttribute('SecretNear',secretD<30);if secretD<30 and not m:GetAttribute('Quiet') then emit(65,'jawbone chatter',3) end
  elseif id=='Heart' then m:SetAttribute('Danger',math.clamp(1-distance/60,0,1));if distance<45 then emit(70,'stone heartbeat',math.max(1.3,distance/12)) end
  elseif id=='Flashlight' and owner then if now-(s.hallucination or 0)>35 and rng:NextNumber()<.05 then s.hallucination=now;event:FireClient(owner,'apparition',r.Position+r.CFrame.LookVector*6) end
  elseif id=='Candles' then m:SetAttribute('SecretLight',not s.covered and now>(s.darkUntil or 0))
  elseif id=='Lantern' then
   -- Feeding: each crouch while holding it eats exactly one nearby loose item.
   local crouching=owner~=nil and owner:GetAttribute('Crouching')==true
   if crouching and not s.crouchWas then
    local best,bd=nil,10
    for _,x in ipairs(map.Interactive:GetChildren()) do if x~=m and states[x] and x:IsA('Model') and x.PrimaryPart and not x:GetAttribute('HeldBy') and not x:GetAttribute('ItemWearOwner') and not x:GetAttribute('AttachedTo') and not x:GetAttribute('CargoStored') and not x:GetAttribute('MonsterCarried') then local d=(x.PrimaryPart.Position-pos).Magnitude;if d<bd then best,bd=x,d end end end
    if best then local info=C.Items[best:GetAttribute('ItemId')];states[best]=nil;best:Destroy();s.fedUntil=now+35;say(owner,'The lantern ate '..((info and info.name) or 'an item')..'.');noise(pos,20,'lantern chewing',m)
    else say(owner,'Nothing nearby for the lantern to eat.') end
   end
   s.crouchWas=crouching
   m:SetAttribute('SecretLight',now<(s.fedUntil or s.birth+12))
  elseif id=='Chain' and r and r.AssemblyLinearVelocity.Magnitude>8 then emit(80,'chain dragging',4)
  elseif id=='Shoes' and owner and r then
   local music=now<fallbackMusicUntil;if music then emit(12,'cursed shoe music',2) end
   for _,piano in ipairs(pianos) do if missionRunning() and now<(piano:GetAttribute('PlayingUntil') or 0) and (piano:GetPivot().Position-r.Position).Magnitude<30 then music=true end end
   for _,x in ipairs(map.Interactive:GetChildren()) do if x:GetAttribute('ItemId')=='MusicBox' and x:GetAttribute('Playing') and (x.PrimaryPart.Position-r.Position).Magnitude<30 then music=true end end
   if music and now>(s.resistUntil or 0) then owner:SetAttribute('DancingUntil',workspace:GetServerTimeNow()+1);event:FireClient(owner,'dance',true) end
  end
  if id=='Flashlight' then m:SetAttribute('SecretLight',not s.covered) end
  local light=m.PrimaryPart:FindFirstChild('CursedGlow');if light then light.Enabled=m:GetAttribute('SecretLight')==true end
  if not owner and s.ghost then s.ghost:Destroy();s.ghost=nil;s.history=nil end
  if id=='Present' and s.follower and s.follower.Parent and s.lastOwner then
   local pr=root(s.lastOwner);if pr then
    local f=s.follower;local point=f.PrimaryPart.Position;local delta=Vector3.new(pr.Position.X-point.X,0,pr.Position.Z-point.Z)
    if delta.Magnitude>2 then
     local step=delta.Unit*math.min(delta.Magnitude-2,tick*4)
     local params=RaycastParams.new();params.FilterType=Enum.RaycastFilterType.Include;params.FilterDescendantsInstances={map.Collision,furniture}
     local obstacle=workspace:Raycast(point,step+delta.Unit*.5,params)
     if not obstacle then local nextPoint=point+step;local ground=workspace:Raycast(nextPoint+Vector3.new(0,4,0),Vector3.new(0,-12,0),params);if ground then nextPoint=Vector3.new(nextPoint.X,ground.Position.Y+f.PrimaryPart.Size.Y/2+.08,nextPoint.Z) end;f:PivotTo(CFrame.lookAt(nextPoint,nextPoint+delta.Unit)) end
    end
   end
  end
  if not owner and not s.faceOwner and not m:GetAttribute('CargoStored') and not m.PrimaryPart.Anchored and not s.owner and m.PrimaryPart.AssemblyLinearVelocity.Magnitude<.5 and now-(s.restSince or now)>4 then parts(m,true,false) end
  s.lastPos=pos
  if pos.Y<-30 and not m:GetAttribute('CargoStored') then if owner then detach(owner,m,false,true) end;clearHold(m);parts(m,true,false);m:PivotTo(s.origin);s.restSince=now end
 end end
 for p,list in pairs(inv) do
  local r,h=root(p);if not r or not h then continue end
  p:SetAttribute('TeddyObscure',has(p,'Teddy') and states[has(p,'Teddy')].arm or 0)
  p:SetAttribute('BothHandsBusy',has(p,'Jawbone') and has(p,'Jawbone'):GetAttribute('Quiet') or false)
  for _,n in ipairs({'CursedLift','CursedLiftAttachment'}) do local v=r:FindFirstChild(n);if v then v:Destroy() end end
  local boost=(p:GetAttribute('CandyBoostUntil') or 0)>now;p:SetAttribute('CursedSpeedMultiplier',(boost and 1.35 or 1)*(has(p,'SnailShell') and .6 or 1)*(has(p,'Anvil') and .45 or 1))
  if (p:GetAttribute('ChatteringUntil') or 0)>now and now-((states[p] or {}).chatter or 0)>4 then states[p]=states[p] or {};states[p].chatter=now;noise(r.Position,85,'teeth chattering',nil,lobbyPlayer(p)) end
 end
end)
cleanup=function(p)
 Batch.ClearPlayer(p)
 for m,s in states do if typeof(m)=='Instance' and s.faceOwner==p and m.Parent then releaseFace(m)end end
 local r=root(p);if r then for _,name in ipairs({'CursedLift','CursedLiftAttachment'}) do local x=r:FindFirstChild(name);if x then x:Destroy() end end end
 for _,m in ipairs(table.clone(inv[p] or {})) do detach(p,m,false,true) end;inv[p]=nil;limits[p]=nil;states[p]=nil
 for _,s in pairs(states) do if s.owner==p then s.owner=nil end;if s.lastOwner==p then s.lastOwner=nil;s.follow=nil;if s.follower then s.follower:Destroy();s.follower=nil end end;if s.partner==p then s.partner=nil end end
 for _,name in ipairs({'MagicOrbHeld','BothHandsBusy','TeddyObscure','BraceletPartner','BraceletPosition','DisguiseUntil','BorrowedFaceActive','CandyBoostUntil','ChatteringUntil','CursedActive','QuietSteps','CursedSpeedMultiplier','DancingUntil'}) do p:SetAttribute(name,nil) end
end
local function added(p)
 p:SetAttribute('Valuables',p:GetAttribute('Valuables') or 0);p.CharacterRemoving:Connect(function()cleanup(p) end);p.CharacterAdded:Connect(function()inv[p]={};publish(p) end);inv[p]={};publish(p)
end
Players.PlayerAdded:Connect(added);Players.PlayerRemoving:Connect(cleanup);for _,p in ipairs(Players:GetPlayers()) do added(p) end
script:SetAttribute('Initialized',true)
grabUse=function(p,m) use(p,m,true) end



-- Halloween uses its own non-loot folder. Disabled means no instances, listeners or timers.
local eventConfig=require(game:GetService('ReplicatedStorage'):WaitForChild('EventConfig'))
local questEventGeneration=0
local function eventLive()
 local c=eventConfig.Halloween;local now=os.time()
 return c.Enabled==true and type(c.StartsAt)=='number' and type(c.EndsAt)=='number' and c.EndsAt>c.StartsAt and now>=c.StartsAt and now<c.EndsAt
end
local function eventTemplate(action)
 local kit=SS:FindFirstChild('EventKit')
 if action=='CandyCornCollected' then return kit and kit:FindFirstChild('CandyCorn') end
 if action=='PumpkinCarved' then return kit and kit:FindFirstChild('CarvingPumpkin')end
 if action=='HorsemanHeadFound' then return kit and kit:FindFirstChild('HorsemanHead')end
 if action=='EventTreasureFound' then return (kit and kit:FindFirstChild('EventTreasure'))or SS.CursedItemKit:FindFirstChild('Present')end
 return nil
end
local function eventPosition(template,source,index)
 local size=select(2,template:GetBoundingBox());local origin=source:GetPivot().Position
 local params=RaycastParams.new();params.FilterType=Enum.RaycastFilterType.Include;params.FilterDescendantsInstances={map.Collision,furniture};params.RespectCanCollide=true
 local pad=math.sqrt(size.X*size.X+size.Z*size.Z)/2+.3
 for turn=0,7 do
  local angle=(turn+index)*math.pi/4;local point=origin+Vector3.new(math.cos(angle)*2.5,12,math.sin(angle)*2.5)
  local hit=workspace:Raycast(point,Vector3.new(0,-28,0),params)
  if hit and hit.Normal.Y>.8 and not AngledCorners.Blocked(map,hit.Position,pad) then
   local cf,bounds=template:GetBoundingBox();local bottom=cf.Position.Y-bounds.Y/2;local pivot=template:GetPivot()
   return CFrame.new(hit.Position+Vector3.new(0,pivot.Position.Y-bottom+.03,0))*pivot.Rotation
  end
 end
 return nil
end
local function makeEventDrop(folder,template,cf,action,index,runId,round)
 local m=template:Clone();m.Name='Halloween_'..action..'_'..index
 for _,x in m:GetDescendants()do
  if x:IsA('Script')or x:IsA('LocalScript')or x:IsA('ProximityPrompt')then x:Destroy()
  elseif x:IsA('BasePart')then x.Anchored=true;x.CanCollide=false;x.CanTouch=false;x.CanQuery=true end
 end
 m:SetAttribute('ItemId',nil);m:SetAttribute('Kind',nil);m:SetAttribute('Value',nil);m:SetAttribute('LootValue',nil);m:SetAttribute('EventCurrency',action=='CandyCornCollected')
 m:PivotTo(cf);m.Parent=folder
 local anchor=m.PrimaryPart or m:FindFirstChildWhichIsA('BasePart',true);if not anchor then m:Destroy();return end
 local id='halloween:'..runId..':'..tostring(round)..':'..action..':'..index
 m:SetAttribute('QuestEventGUID',id);m:SetAttribute('QuestEventAction',action)
 local prompt=Instance.new('ProximityPrompt');prompt.Name='QuestEventPrompt';prompt.ObjectText='Halloween'
 prompt.ActionText=action=='PumpkinCarved' and 'Carve pumpkin' or action=='CandyCornCollected' and 'Collect Candy Corn' or action=='HorsemanHeadFound' and 'Find Horseman head' or 'Collect event treasure'
 prompt.MaxActivationDistance=8;prompt.HoldDuration=action=='PumpkinCarved' and .8 or 0;prompt.KeyboardKeyCode=Enum.KeyCode.E;prompt.GamepadKeyCode=Enum.KeyCode.ButtonX;prompt.Parent=anchor
 local taken={}
 prompt.Triggered:Connect(function(p)
  local r,h=root(p);local state=RS:FindFirstChild('RecoveryRound')
  if taken[p.UserId]or not eventLive()or not m.Parent or not r or not h or h.Health<=0 or p:GetAttribute('MissionActive')~=true or p:GetAttribute('RoundDead')==true or p:GetAttribute('LeavingRun')==true or not state or state:GetAttribute('QuestRunId')~=runId or state:GetAttribute('Round')~=round or QuestService.IsAssisted(runId,round)or (r.Position-anchor.Position).Magnitude>8 or not visible(r.Position,anchor.Position)then return end
  local ctx=questContext(id);ctx.eventEligible=true
  if QuestService.Record(p,action,1,ctx)then taken[p.UserId]=true;if action=='PumpkinCarved' then local face=m:FindFirstChild('Face',true);if face and face:IsA('BasePart')then face.Transparency=0 end end end
 end)
end
refreshQuestEventWorld=function()
 questEventGeneration+=1
 local old=map:FindFirstChild('QuestHalloweenDrops');if old then old:Destroy()end
 if not eventLive() or not missionRunning()then return end
 local state=RS:FindFirstChild('RecoveryRound');local runId=state and state:GetAttribute('QuestRunId');local round=state and state:GetAttribute('Round')
 if type(runId)~='string' or type(round)~='number' or round<1 then return end
 local sources={};for _,m in map.Interactive:GetChildren()do if m:IsA('Model')and m.PrimaryPart and m:GetAttribute('LootSpawnIdentity')and not m:GetAttribute('AdminSpawned')then table.insert(sources,m)end end
 table.sort(sources,function(a,b)return a:GetAttribute('LootSpawnIdentity')<b:GetAttribute('LootSpawnIdentity')end)
 if #sources==0 then return end
 local folder=Instance.new('Folder');folder.Name='QuestHalloweenDrops';folder.Parent=map
 local ordinal=0
 for _,row in {{'CandyCornCollected',12},{'PumpkinCarved',6},{'HorsemanHeadFound',1},{'EventTreasureFound',8}}do
  local template=eventTemplate(row[1])
  if template and template:IsA('Model')then
   for i=1,row[2]do ordinal+=1;local source=sources[(ordinal-1)%#sources+1];local cf=eventPosition(template,source,ordinal);if cf then makeEventDrop(folder,template,cf,row[1],i,runId,round)end end
  else warn('[Quests] Missing Halloween model: '..row[1])end
 end
end
if eventConfig.Halloween.Enabled then
 task.defer(refreshQuestEventWorld)
 if lobbyState then lobbyState:GetAttributeChangedSignal('Mode'):Connect(function()refreshQuestEventWorld()end)end
end
