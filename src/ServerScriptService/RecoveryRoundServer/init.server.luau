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

local Players=game:GetService('Players');local RS=game:GetService('ReplicatedStorage');local SS=game:GetService('ServerStorage');local Run=game:GetService('RunService')
local map=workspace:WaitForChild('Mansion',math.huge);while not map:GetAttribute('RuntimeReady') do map:GetAttributeChangedSignal('RuntimeReady'):Wait() end
local Physics=game:GetService('PhysicsService')
for _,name in ipairs({'RecoveryCart','RecoveryCharacters','RecoveryLoot','RecoveryHeldCart'}) do pcall(function()Physics:RegisterCollisionGroup(name)end) end
Physics:CollisionGroupSetCollidable('RecoveryCart','RecoveryCart',false)
Physics:CollisionGroupSetCollidable('RecoveryHeldCart','RecoveryCart',false)
Physics:CollisionGroupSetCollidable('RecoveryHeldCart','RecoveryHeldCart',false)
Physics:CollisionGroupSetCollidable('RecoveryHeldCart','RecoveryCharacters',false)
for _,group in ipairs({'HorrorPhysicalArms','HorrorPlayerBodies'}) do if Physics:IsCollisionGroupRegistered(group) then Physics:CollisionGroupSetCollidable('RecoveryHeldCart',group,false) end end
Physics:CollisionGroupSetCollidable('RecoveryCart','RecoveryCharacters',true)
if Physics:IsCollisionGroupRegistered('HorrorPhysicalArms') then Physics:CollisionGroupSetCollidable('RecoveryCart','HorrorPhysicalArms',false) end
Physics:CollisionGroupSetCollidable('RecoveryLoot','RecoveryCharacters',false)
local Models=require(script:WaitForChild('RecoveryModels'))
local preview=workspace:FindFirstChild('RecoveryPreview');if preview then preview:Destroy() end
local camp=Instance.new('Model');camp.Name='RecoveryCamp';camp.Parent=workspace
local entrance=workspace.SpawnLocation.Position
local exteriorZ=entrance.Z;for _,room in ipairs(game.HttpService:JSONDecode(map.GeneratedGraph.Value).rooms) do exteriorZ=math.max(exteriorZ,room.z2) end
local van,vanCF,readouts=Models.Van(camp,entrance,exteriorZ)
-- Cart parks just outside the rear doors, facing the mansion (owner-picked spot; outside the van sale zone).
local CARTPARK_OFFSET=CFrame.new(-2.3,1.22,-29.5)*CFrame.Angles(0,math.pi,0)
local parkCF=vanCF*CARTPARK_OFFSET
local cart,cartLabel=Models.Cart(map.Interactive,parkCF)
for _,x in ipairs(cart:GetDescendants()) do if x:IsA('BasePart') then x.Anchored=false end end
for _,x in ipairs(cart:GetDescendants()) do if x:IsA('BasePart') then pcall(function()x:SetNetworkOwner(nil)end) end end
local state=Instance.new('Folder');state.Name='RecoveryRound';state.Parent=RS
local Progress=require(game.ServerScriptService.ProgressService)
local RunSaves=require(game.ServerScriptService:WaitForChild('RunSavesService'))
local runSaveContext=RunSaves.GetMissionContext()
local initialRunSave=runSaveContext and type(runSaveContext.mode)=='string'and runSaveContext.mode:lower()=='load'and runSaveContext.slot or nil
local runSaveFailed=false
-- Map variety per save: no map type repeats until this save has played every type; then a new cycle starts.
local MapProfiles=require(game.ServerScriptService:WaitForChild('MapGen'):WaitForChild('Profiles'))
local mapsSeen={}
if runSaveContext and runSaveContext.slot and type(runSaveContext.slot.mapsSeen)=='table'then
 for _,k in ipairs(runSaveContext.slot.mapsSeen)do if table.find(MapProfiles.Kinds,k)and not table.find(mapsSeen,k)then table.insert(mapsSeen,k)end end
end
local function noteMap(kind)
 if type(kind)=='string'and table.find(MapProfiles.Kinds,kind)and not table.find(mapsSeen,kind)then table.insert(mapsSeen,kind)end
end
local function nextMapKind(current)
 local options={}
 for _,k in ipairs(MapProfiles.Kinds)do if k~=current and not table.find(mapsSeen,k)then table.insert(options,k)end end
 if #options==0 then -- every type seen: the cycle restarts, counting the map just played
  table.clear(mapsSeen);noteMap(current)
  for _,k in ipairs(MapProfiles.Kinds)do if k~=current then table.insert(options,k)end end
 end
 return options[Random.new():NextInteger(1,#options)]
end
local runSaveDeployMarker=false
local runSaveDeployOwnerDead=false
local runSaveDeployDeathSerial=0
local runId=game.HttpService:GenerateGUID(false);local levelStarted=workspace:GetServerTimeNow()
local cargo={}
-- Per-level recap counters (reset with levelStarted in nextRound).
local levelItems,levelDeaths,levelRevives=0,0,0
local questDeaths={};local questQuotaCredited=false
local sendRecap,WIN_HOLD -- defined with the recap event below
local round,quota,sold=0,0,0;local phase='Loading';local selling=false;local owner;local lease=0;local aim;local started;local contents={};local credited={};local lastRequests={};local transitioning=false;local generation=0;local bound={}
Players.CharacterAutoLoads=false
local function root(p) if p:GetAttribute('MissionActive')~=true or p:GetAttribute('RoundDead')==true then return nil end;local c=p.Character;local h=c and c:FindFirstChildOfClass('Humanoid');return h and h.Health>0 and c:FindFirstChild('HumanoidRootPart') end
local function inVan(p) local r=root(p);if not r then return false end;local q=vanCF:PointToObjectSpace(r.Position);return math.abs(q.X)<11 and q.Y>0 and q.Y<12 and q.Z>-24.5 and q.Z<16 end
local function cargoTotal(cartValue)
 local boat=map:GetAttribute('MapKind')=='Cruise' and map.Interactive:FindFirstChild('CruiseLaunch')
 return cartValue+(boat and boat:GetAttribute('CartValue')or 0)
end
local function publish()
 state:SetAttribute('QuestRunId',runId);state:SetAttribute('QuestGeneration',generation)
 state:SetAttribute('Round',round);state:SetAttribute('Quota',quota);state:SetAttribute('Sold',sold);state:SetAttribute('Phase',phase);state:SetAttribute('CartValue',cargoTotal(cart:GetAttribute('CartValue') or 0))
 local text=('ROUND %d\n$%d / $%d\n%s'):format(round,sold,quota,phase=='Returning' and 'QUOTA MET - ALL SURVIVORS TO VAN' or phase=='Selling' and 'SELLING - KEEP CART AT VAN' or phase=='Won' and 'LEVEL CLEARED - REVIVING TEAM' or phase=='Failed' and (state:GetAttribute('FailureReason')=='TimeExpired' and 'TIME EXPIRED' or 'TEAM WIPED')..((runSaveContext and not state:GetAttribute('RunSaveDeleted'))and(state:GetAttribute('RunSaveNew')and ' - NEW SAVE AT LEVEL 1' or ' - RETRYING THIS LEVEL') or ' - STARTING A NEW RUN') or 'RECOVER ANOMALIES')
 for _,t in ipairs(readouts) do t.Text=text end
end
local function cartCollision(held)
 for _,part in ipairs(cart:GetDescendants()) do if part:IsA('BasePart') then part.CollisionGroup=held and 'RecoveryHeldCart' or 'RecoveryCart' end end
end
local function standingOnCart(p)
 local r=root(p);if not r then return false end
 local h=p.Character:FindFirstChildOfClass('Humanoid')
 local params=RaycastParams.new();params.FilterType=Enum.RaycastFilterType.Exclude;params.FilterDescendantsInstances={p.Character};params.RespectCanCollide=true
 local hit=workspace:Raycast(r.Position,Vector3.new(0,-(h.HipHeight+r.Size.Y/2+1),0),params)
 return hit~=nil and hit.Instance:IsDescendantOf(cart)
end
-- Cart weight: lower responsiveness = more lag/inertia while pushing; release carry = how much momentum survives letting go.
-- Fully server-run cart: one simulation everyone sees (was 14 / 22 / 10 / 3.5).
local CART_PUSH_RESPONSIVENESS,CART_PUSH_MAX_SPEED=24,24
local CART_TURN_RESPONSIVENESS,CART_TURN_MAX_SPEED=16,5
-- Keeps the cart (and cargo welded into it) simulated by the server, never a nearby client.
local function serverOwnsCart()
 for _,x in ipairs(cart:GetDescendants()) do if x:IsA('BasePart') and not x.Anchored then pcall(function() if x:GetNetworkOwner()~=nil then x:SetNetworkOwner(nil) end end) end end
end
-- Start a push from its current pose, rather than switching the solver target in one frame.
local CART_ACQUIRE_SECONDS=.3
local cartAcquire
local CART_RELEASE_CARRY=.45
local function release(p)
 if owner~=p then return end;cart:SetAttribute('HeldBy',nil);owner=nil;aim=nil;cartAcquire=nil;cartCollision(false)
 for _,x in ipairs(cart.PrimaryPart:GetChildren()) do if x.Name:sub(1,9)=='CartHold_' then x:Destroy() end end
 local v=cart.PrimaryPart.AssemblyLinearVelocity;cart.PrimaryPart.AssemblyLinearVelocity=Vector3.new(v.X*CART_RELEASE_CARRY,v.Y,v.Z*CART_RELEASE_CARRY);cart.PrimaryPart.AssemblyAngularVelocity*=CART_RELEASE_CARRY
 for _,x in ipairs(cart:GetChildren()) do if x:IsA('BasePart') and x.Name=='Wheel' then x.AssemblyAngularVelocity*=CART_RELEASE_CARRY end end
end
local function cartAtVan() local q=vanCF:PointToObjectSpace(cart.PrimaryPart.Position);return math.abs(q.X)<10 and q.Y>0 and q.Y<5 and q.Z>-24 and q.Z<15 end
-- The cart owns cargo retention. Pickup removes only the selected item's joint.
-- Basket box in world space. The attributes are authored before the cart is scaled,
-- so they are scaled here to match the visible basket.
local BASKET_MARGIN,BASKET_HEADROOM=.25,1.2
local function basketFrame()
 local s=cart:GetScale()
 return cart.PrimaryPart.CFrame*CFrame.new(cart:GetAttribute('BasketOffset')*s),cart:GetAttribute('BasketSize')*s
end
local function insideBasket(m)
 if not m.PrimaryPart then return false end
 local cf,size=basketFrame();local q=cf:PointToObjectSpace(m.PrimaryPart.Position)
 return math.abs(q.X)<size.X/2+BASKET_MARGIN and q.Y>-size.Y/2-.3 and q.Y<size.Y/2+BASKET_HEADROOM and math.abs(q.Z)<size.Z/2+BASKET_MARGIN
end
local function takeCargo(p,m)
 local entry=cargo[m];local r=root(p)
 if not entry then
  local boatApi=SS:FindFirstChild('CruiseBoatApi')
  if m and m:GetAttribute('CargoCart')=='CruiseLaunch' and boatApi then return boatApi:Invoke('takeCargo',p,m)==true end
 end
 if not entry or not r or not p:GetAttribute('PhysicalGrabActive') or m:GetAttribute('Selling') or (r.Position-m.PrimaryPart.Position).Magnitude>10 then return false end
 if entry.weld.Parent then entry.weld:Destroy() end
 for part,old in pairs(entry.parts) do if part.Parent then part.Massless=old.massless;part.CanCollide=old.collide end end
 cargo[m]=nil;m:SetAttribute('CargoStored',nil);m:SetAttribute('CargoCart',nil);return true
end
-- A creature pulls exactly one stored item out of the basket; CreatureRoamServer carries it off.
-- MonsterCarried keeps the item out of the basket, the sale and player hands until it is dropped.
local function monsterTake()
 if selling or cartAtVan() then return nil end
 local list={};for m in pairs(cargo) do if m.Parent and m.PrimaryPart and not m:GetAttribute('Selling') then table.insert(list,m) end end
 if #list==0 then return nil end
 local m=list[math.random(1,#list)];local entry=cargo[m]
 if entry.weld.Parent then entry.weld:Destroy() end
 for part,old in pairs(entry.parts) do if part.Parent then part.Massless=old.massless;part.CanCollide=old.collide end end
 cargo[m]=nil;m:SetAttribute('CargoStored',nil);m:SetAttribute('CargoCart',nil);m:SetAttribute('MonsterCarried',true)
 return m
end
local function updateCargo()
 for m,entry in pairs(cargo) do if not m.Parent then if entry.weld.Parent then entry.weld:Destroy() end;cargo[m]=nil end end
 for _,m in ipairs(map.Interactive:GetChildren()) do
  if m:IsA('Model') and m.PrimaryPart and m:GetAttribute('ItemId') and not m:GetAttribute('HeldBy') and not m:GetAttribute('ItemWearOwner') and not m:GetAttribute('AttachedTo') and not m:GetAttribute('MonsterCarried') and not m:GetAttribute('Selling') and not cargo[m] and insideBasket(m) then
   local size=m.PrimaryPart.Size;local _,basket=basketFrame()
   -- Long items lie along the basket; nothing is ever refused for its size.
   local turn=size.X>basket.X-.16 and size.Z<size.X
   if turn then size=Vector3.new(size.Z,size.Y,size.X) end
   local halfX=math.max(0,basket.X/2-size.X/2-.08);local halfZ=math.max(0,basket.Z/2-size.Z/2-.08)
   local original=cart.PrimaryPart.CFrame:PointToObjectSpace(m.PrimaryPart.Position);local floor=cart.BasketFloor;local base=cart.PrimaryPart.CFrame:PointToObjectSpace(floor.Position).Y+floor.Size.Y/2+.04
   local function clear(x,z)
    for item in pairs(cargo) do if item.Parent then local q=cart.PrimaryPart.CFrame:PointToObjectSpace(item.PrimaryPart.Position);local other=item.PrimaryPart.Size;if math.abs(x-q.X)<(size.X+other.X)/2+.06 and math.abs(z-q.Z)<(size.Z+other.Z)/2+.06 then return false end end end
    return true
   end
   local x,z=math.clamp(original.X,-halfX,halfX),math.clamp(original.Z,-halfZ,halfZ);local found=clear(x,z)
   if not found then for px=-halfX,halfX,.35 do for pz=-halfZ,halfZ,.35 do if clear(px,pz) then x,z,found=px,pz,true;break end end;if found then break end end end
   if not found then
    local topItem;local top=base
    for item in pairs(cargo) do if item.Parent then local q=cart.PrimaryPart.CFrame:PointToObjectSpace(item.PrimaryPart.Position);local height=q.Y+item.PrimaryPart.Size.Y/2+.05;if height>top then top=height;topItem=q end end end
    base=top;if topItem then x,z=math.clamp(topItem.X,-halfX,halfX),math.clamp(topItem.Z,-halfZ,halfZ) end
   end
   m:PivotTo(cart.PrimaryPart.CFrame*CFrame.new(x,base+size.Y/2,z)*(turn and CFrame.Angles(0,math.pi/2,0) or CFrame.identity))
   local entry={parts={}}
   for _,part in ipairs(m:GetDescendants()) do if part:IsA('BasePart') then entry.parts[part]={massless=part.Massless,collide=part.CanCollide};part.Anchored=false;part.CanCollide=false;part.Massless=true end end
   m.PrimaryPart.AssemblyLinearVelocity=cart.PrimaryPart.AssemblyLinearVelocity;m.PrimaryPart.AssemblyAngularVelocity=Vector3.zero
   local w=Instance.new('WeldConstraint');w.Name='CargoRetention';w.Part0=cart.PrimaryPart;w.Part1=m.PrimaryPart;w.Parent=m.PrimaryPart;entry.weld=w;cargo[m]=entry
   m:SetAttribute('CargoStored',true);m:SetAttribute('CargoCart',cart.Name)
  end
 end
end
local function snapshot()
 local t={};local value=0;local cf,size=basketFrame()
 for _,m in ipairs(map.Interactive:GetChildren()) do if m:IsA('Model') and m.PrimaryPart and m:GetAttribute('ItemId') and not m:GetAttribute('Gear') and not m:GetAttribute('HeldBy') and not m:GetAttribute('ItemWearOwner') and not m:GetAttribute('AttachedTo') and not m:GetAttribute('MonsterCarried') and not credited[m] then local p=cf:PointToObjectSpace(m.PrimaryPart.Position);if cargo[m] or (math.abs(p.X)<size.X/2 and math.abs(p.Y)<size.Y/2+.3 and math.abs(p.Z)<size.Z/2) then table.insert(t,m);value+=m:GetAttribute('LootValue') or m:GetAttribute('Value') or 0 end end end
 return t,value
end
-- Grabbing the cart during a sale cancels it (the player decided not to sell yet).
local saleToken=0
local function sell(p,carrier)
 local atSale,saleSnapshot=cartAtVan,snapshot
 if carrier then
  local boatApi=SS:FindFirstChild('CruiseBoatApi')
  if map:GetAttribute('MapKind')~='Cruise' or carrier~=map.Interactive:FindFirstChild('CruiseLaunch') or not boatApi then return false end
  atSale=function()return boatApi.Parent and boatApi:Invoke('saleReady',carrier)==true end
  saleSnapshot=function()if not boatApi.Parent then return {},0 end;return boatApi:Invoke('snapshot',carrier)end
 end
 if selling or (phase~='Searching' and phase~='Returning') or not atSale() then return false end
 saleToken+=1;local mySale=saleToken
 local batch,value=saleSnapshot();if #batch==0 then return false end
 local saleGeneration=generation;selling=true;phase='Selling';release(owner);state:SetAttribute('SaleEnds',workspace:GetServerTimeNow()+5)
 for _,m in ipairs(batch) do m:SetAttribute('Selling',true) end;publish()
 task.spawn(function()
  local finish=os.clock()+5;local valid=true
  while os.clock()<finish do if saleGeneration~=generation then return end;if not atSale() or saleToken~=mySale then valid=false;break end;task.wait(.1) end
  if saleGeneration~=generation then return end
  local nowItems={};for _,m in ipairs(saleSnapshot()) do nowItems[m]=true end
  if valid then local api=SS:FindFirstChild('RecoveryLootApi');for _,m in ipairs(batch) do
   local worth=m:GetAttribute('LootValue') or m:GetAttribute('Value') or 0
   local spawnId=m:GetAttribute('LootSpawnIdentity');if spawnId then m:SetAttribute('LootGUID',runId..':'..tostring(round)..':'..spawnId)end;local ctx=questContext('sale:'..tostring(m:GetAttribute('LootGUID')),m);ctx.value=worth;ctx.money=worth;ctx.items=1;ctx.amount=1
   local eligible=m:GetAttribute('LootGUID') and not m:GetAttribute('AdminEffect') and not m:GetAttribute('AdminSpawned') and not m:GetAttribute('LobbyToy')
   if m.Parent and nowItems[m] and api and api:Invoke('remove',m) then
    credited[m]=true;sold+=worth;levelItems+=1
    if eligible then local roster={};for _,member in Players:GetPlayers()do if member:GetAttribute('MissionActive')==true and not member:GetAttribute('ReturnedToLobby')then table.insert(roster,member)end end;QuestService.RecordParty(roster,'ItemSold',1,ctx)end
   end
  end
  if sold>=quota and not questQuotaCredited then questQuotaCredited=true;local roster={};for _,member in Players:GetPlayers()do if member:GetAttribute('MissionActive')==true then table.insert(roster,member)end end;QuestService.RecordParty(roster,'QuotaMet',1,{eventId='quota:'..runId..':'..round,runId=runId,round=round,mapKind=map:GetAttribute('MapKind')})end
 end
  for _,m in ipairs(batch) do if m.Parent then m:SetAttribute('Selling',nil) end end
  selling=false;state:SetAttribute('SaleEnds',nil);phase=sold>=quota and 'Returning' or 'Searching';publish()
 end);return true
end
local giftRevive,giftReviveIdentity
local winLevel -- defined beside the Heartbeat; shared by the normal extraction and the Instant Win product
local api=Instance.new('BindableFunction');api.Name='RecoveryApi';api.Parent=SS
api.OnInvoke=function(action,p,m,operationId,identity)
 if action=='GiftReviveIdentity'then return giftReviveIdentity and giftReviveIdentity(p,m)or nil end
 if action=='GiftRevive'then if giftRevive then return giftRevive(p,m,operationId,identity)end;return false end
 if action=='shopAllowed'then return not transitioning and (phase=='Searching'or phase=='Selling'or phase=='Returning')and inVan(p)end
 if action=='monsterTake' then return monsterTake() end
 -- Instant Win (MonetizeServer spends the buyer's saved charge first and refunds it when this returns false).
 if action=='canInstantWin' or action=='instantWin' then
  local playing=not transitioning and (phase=='Searching' or phase=='Selling' or phase=='Returning') and round>=1
  if not playing then return false,'Instant Win can only be used while a level is being played.' end
  if action=='canInstantWin' then return true end
  state:SetAttribute('QuestAssisted',true);QuestService.MarkAssisted(runId,round)
  -- Cancel a running sale so its loop cannot rewrite the phase after the win.
  if selling then saleToken+=1;generation+=1;selling=false;state:SetAttribute('SaleEnds',nil);for _,item in ipairs(map.Interactive:GetChildren()) do if item:GetAttribute('Selling') then item:SetAttribute('Selling',nil) end end end
  release(owner);started=nil
  winLevel()
  return true
 end
 if action=='sellBoat' then return sell(nil,m) end
 if action=='takeCargo' then return takeCargo(p,m) elseif action=='sell' then return sell(p) elseif action=='release' then release(p);return true elseif action=='pickup' then
  -- One pusher at a time: no stealing a cart someone is actively pushing.
   if owner and owner~=p and root(owner) and os.clock()-lease<.85 then return false end
   local r=root(p);if m~=cart or not r or not p:GetAttribute('PhysicalGrabActive') or phase=='Won' or standingOnCart(p) or (r.Position-cart.PrimaryPart.Position).Magnitude>11 then return false end
  local head=p.Character:FindFirstChild('Head');local origin=head and head.Position or r.Position;local delta=cart.PrimaryPart.Position-origin
  local sight=RaycastParams.new();sight.FilterType=Enum.RaycastFilterType.Include;sight.FilterDescendantsInstances={map.Collision,camp};sight.RespectCanCollide=true
  local obstruction=workspace:Raycast(origin,delta,sight);if obstruction and obstruction.Distance+.5<delta.Magnitude then return false end
  if selling then saleToken+=1 end -- cancels the running sale; its loop restores the phase
   release(owner);owner=p;lease=os.clock();aim=nil;cartAcquire={started=lease,position=cart.PrimaryPart.Position,rotation=cart.PrimaryPart.CFrame.Rotation};cart:SetAttribute('HeldBy',p.UserId);cartCollision(true)
  serverOwnsCart()
  local a=Instance.new('Attachment');a.Name='CartHold_Attachment';a.Parent=cart.PrimaryPart
  local pos=Instance.new('AlignPosition');pos.Name='CartHold_Position';pos.Mode=Enum.PositionAlignmentMode.OneAttachment;pos.Attachment0=a;pos.ApplyAtCenterOfMass=true;pos.Responsiveness=CART_PUSH_RESPONSIVENESS;pos.MaxForce=math.max(16000,cart.PrimaryPart.AssemblyMass*1800);pos.MaxVelocity=CART_PUSH_MAX_SPEED;pos.Position=cart.PrimaryPart.Position;pos.Parent=cart.PrimaryPart
  local rot=Instance.new('AlignOrientation');rot.Name='CartHold_Orientation';rot.Mode=Enum.OrientationAlignmentMode.OneAttachment;rot.Attachment0=a;rot.Responsiveness=CART_TURN_RESPONSIVENESS;rot.MaxTorque=160000;rot.MaxAngularVelocity=CART_TURN_MAX_SPEED;rot.CFrame=cart.PrimaryPart.CFrame.Rotation;rot.Parent=cart.PrimaryPart;return true
 end;return false
end
local ev=Instance.new('RemoteEvent');ev.Name='RecoveryEvent';ev.Parent=RS
local TeleportService=game:GetService('TeleportService')
local leavingRun={}
local pendingWipe
local function leaveReply(p,ok,message)
 if p.Parent==Players then ev:FireClient(p,'leaveRun',ok,message)end
end
local function returnInPlace(p,attempt)
 if leavingRun[p]~=attempt or p.Parent~=Players then return false end
 local lobby=game.ServerScriptService:FindFirstChild('LobbyServer');local api=lobby and lobby:FindFirstChild('ReturnToLobby')
 local ok,returned,remaining=pcall(function()if api and api:IsA('BindableFunction')then return api:Invoke(p)end;return false end)
 if ok and returned then
  leavingRun[p]=nil
  if remaining==0 then
   generation+=1;phase='Ended';transitioning=false;pendingWipe=nil;selling=false;started=nil
   state:SetAttribute('WipeRevivable',nil);state:SetAttribute('TransitionEnds',nil);state:SetAttribute('Phase','Ended')
   local creatures=workspace:FindFirstChild('RoamingCreatures');if creatures then creatures:ClearAllChildren()end
  end
  leaveReply(p,true,'Returned to the lobby.');return true
 end
 leavingRun[p]=nil;p:SetAttribute('LeavingRun',nil);leaveReply(p,false,'Could not return to the lobby. Please try again.');return false
end
local function leaveRun(p)
 local h=p.Character and p.Character:FindFirstChildOfClass('Humanoid')
 if p:GetAttribute('MissionActive')~=true or p:GetAttribute('RoundDead')~=true or p:GetAttribute('Reviving')==true or h and h.Health>0 or phase=='Deploying' or phase=='Won' then
  leaveReply(p,false,'You can leave here while spectating.');return false
 end
 if leavingRun[p]then return false end
 if not AntiCheat.Allow(p,'leaveRun',.2,1)then leaveReply(p,false,'Please wait a moment before trying again.');return false end
 -- A public-server teleport uses the normal departure save and reward owners.
 -- Keep mission/death attributes intact until PlayerRemoving; teammates keep their run.
 local attempt={options=Instance.new('TeleportOptions'),token=game:GetService('HttpService'):GenerateGUID(false)}
 attempt.options:SetTeleportData({lobbyReturn=attempt.token})
 leavingRun[p]=attempt;p:SetAttribute('LeavingRun',true)
 leaveReply(p,true,'Returning to the lobby...')
 task.delay(30,function()if leavingRun[p]==attempt and p.Parent==Players then returnInPlace(p,attempt)end end)
 if Run:IsStudio()then return returnInPlace(p,attempt)end
 local ok=pcall(function()TeleportService:TeleportAsync(game.PlaceId,{p},attempt.options)end)
 if not ok and leavingRun[p]==attempt then return returnInPlace(p,attempt)end
 return ok
end
TeleportService.TeleportInitFailed:Connect(function(p,_,_,placeId,options)
 if placeId~=game.PlaceId or not leavingRun[p] or not options then return end
 local data=options:GetTeleportData()
 if type(data)~='table' or data.lobbyReturn~=leavingRun[p].token then return end
 returnInPlace(p,leavingRun[p])
end)
Players.PlayerRemoving:Connect(function(p)leavingRun[p]=nil end)
ev.OnServerEvent:Connect(function(p,action,cf)
 if action=='leaveRun'then leaveRun(p);return end
 if action=='spawnReady' then
  local c=p.Character;local r=c and c:FindFirstChild('HumanoidRootPart')
  if c and r and cf==c:GetAttribute('RecoverySpawnRevision') and not c:GetAttribute('RecoverySpawnReady') then
   local placement=c:GetAttribute('RecoverySpawnCFrame');c:PivotTo(placement)
   for _,part in ipairs(c:GetDescendants()) do if part:IsA('BasePart') then part.AssemblyLinearVelocity=Vector3.zero;part.AssemblyAngularVelocity=Vector3.zero end end
   c:SetAttribute('RecoverySpawnReady',true);r.Anchored=false;pcall(function()r:SetNetworkOwner(p)end)
  end
  return
 end
 if action~='aim' or owner~=p or typeof(cf)~='CFrame' then return end
 if not AntiCheat.Allow(p,'cartAim',90,120) then return end
 for _,n in ipairs({cf:GetComponents()}) do if n~=n or math.abs(n)>1e6 then return end end
 local r=root(p);if not r or (cf.Position-r.Position).Magnitude>6 then return end;aim=cf;lease=os.clock()
end)
local function assignCharacter(c)
 if c:GetAttribute('RecoveryGroupAssigned') then return end;c:SetAttribute('RecoveryGroupAssigned',true)
 local function set(x) if x:IsA('BasePart') then x.CollisionGroup='RecoveryCharacters' end end
 for _,x in ipairs(c:GetDescendants()) do set(x) end;c.DescendantAdded:Connect(set)
end
local function assignLoot(m) if m:GetAttribute('ItemId') then for _,x in ipairs(m:GetDescendants()) do if x:IsA('BasePart') then x.CollisionGroup='RecoveryLoot' end end end end
for _,m in ipairs(map.Interactive:GetChildren()) do assignLoot(m) end;map.Interactive.ChildAdded:Connect(function(m)task.defer(assignLoot,m)end)
local function positionCharacter(p,c)
 assignCharacter(c)
 local r=c:WaitForChild('HumanoidRootPart',12);if not r then return end
 local h=c:WaitForChild('Humanoid',12);if not h or p.Character~=c then return end
 local index=table.find(Players:GetPlayers(),p) or 1
 local height=.25+h.HipHeight+r.Size.Y/2+1.5
 c:SetAttribute('RecoverySpawnReady',false);r.Anchored=true
 c:PivotTo(vanCF*CFrame.new(2+((index-1)%3)*2.5,height,-15+math.floor((index-1)/3)*3))
 for _,part in ipairs(c:GetDescendants()) do if part:IsA('BasePart') then part.AssemblyLinearVelocity=Vector3.zero;part.AssemblyAngularVelocity=Vector3.zero end end
 h.PlatformStand=false;h.Sit=false;h:ChangeState(Enum.HumanoidStateType.Running)
 c:SetAttribute('RecoverySpawnCFrame',r.CFrame);c:SetAttribute('RecoveryFacing',Vector3.new(0,0,-1));c:SetAttribute('RecoverySpawnRevision',(c:GetAttribute('RecoverySpawnRevision') or 0)+1)
 -- The client acknowledges placement before physics is released.
end

local reviving={}
-- A team wipe stays undoable while the monster-win cutscene plays: a revive in that window resumes the level.
-- {from=phase before the wipe, saved=save-tag attributes before the preview, id=generation of the wipe}
local resumeFromWipe
local deathSerial={}
local giftOperations={}
local failedFrom='Searching'
local reviveEvent=RS:FindFirstChild('ReviveEvent')or Instance.new('RemoteEvent');reviveEvent.Name='ReviveEvent';reviveEvent.Parent=RS
local function reviveReply(p,ok,message)if p.Parent then reviveEvent:FireClient(p,ok,message)end end
-- Server-only paid gift route: receipt owner grants one saved token first.
-- Both recipient and mission identity are checked before every yielding stage.
local function giftParticipants(buyer,target)
 return typeof(buyer)=='Instance'and buyer:IsA('Player')and buyer.Parent==Players
  and typeof(target)=='Instance'and target:IsA('Player')and target.Parent==Players
  and buyer~=target and target:GetAttribute('LeavingRun')~=true and buyer:GetAttribute('MissionActive')==true and target:GetAttribute('MissionActive')==true
end
local function giftPhase()
 return not transitioning and(phase=='Searching'or phase=='Returning'or phase=='Selling')
end
giftReviveIdentity=function(buyer,target)
 if not giftParticipants(buyer,target)or not giftPhase()or target:GetAttribute('RoundDead')~=true or reviving[target]then return nil end
 return {runId=runId,round=round,generation=generation,targetUserId=target.UserId,deathSerial=deathSerial[target]or 0,expiresAt=workspace:GetServerTimeNow()+60}
end
local function giftIdentityMatches(buyer,target,identity)
 return giftParticipants(buyer,target)and giftPhase()and type(identity)=='table'
  and identity.runId==runId and identity.round==round and identity.generation==generation
  and identity.targetUserId==target.UserId and identity.deathSerial==(deathSerial[target]or 0)
  and type(identity.expiresAt)=='number'and identity.expiresAt==identity.expiresAt
  and identity.expiresAt>=workspace:GetServerTimeNow()and identity.expiresAt<=workspace:GetServerTimeNow()+60
end
local function settleGift(buyer,id,method)
 local ok,result=pcall(method,buyer,id)
 if ok and result then return true end
 -- The durable consumed/used/refunded operation prevents another receipt attempt spending twice.
 task.spawn(function()
  for attempt=1,10 do
   task.wait(5)
   local retryOk,settled=pcall(method,buyer,id)
   if retryOk and settled then return end
  end
 end)
 return false
end
giftRevive=function(buyer,target,id,identity)
 if type(id)~='string'or #id<1 or #id>160 or not giftIdentityMatches(buyer,target,identity)then return false,'Gift target unavailable; your saved revive token remains.'end
 local operationKey=tostring(buyer.UserId)..':'..id
 if giftOperations[operationKey]then return giftOperations[operationKey]=='done','Gift operation already handled.'end
 if reviving[target]or target:GetAttribute('RoundDead')~=true then return false,'Gift target unavailable; your saved revive token remains.'end
 giftOperations[operationKey]='running';reviving[target]=true;target:SetAttribute('Reviving',true)
 local oldCharacter=target.Character
 local consumeOk,consumed,message=pcall(Progress.ConsumeRevive,buyer,id)
 if not consumeOk or not consumed then
  if not consumeOk then settleGift(buyer,id,Progress.RefundRevive)end
  giftOperations[operationKey]='failed';reviving[target]=nil
  if target.Parent==Players then target:SetAttribute('Reviving',nil)end
  return false,consumeOk and message or 'Revive token consumption failed.'
 end
 local loaded=false
 if giftIdentityMatches(buyer,target,identity)and target:GetAttribute('RoundDead')==true then loaded=pcall(function()target:LoadCharacterAsync()end)end
 local c=target.Character;local h=c and c:FindFirstChildOfClass('Humanoid')
 local refunded=false
 local success=loaded and c~=oldCharacter and h and h.Health>0 and giftIdentityMatches(buyer,target,identity)and target:GetAttribute('RoundDead')==true
 if success then
  h.Health=h.MaxHealth;target:SetAttribute('RoundDead',false);levelRevives+=1
  giftOperations[operationKey]='done';settleGift(buyer,id,Progress.ConfirmRevive);QuestService.Record(buyer,'TeammateRevived',1,{eventId='gift:'..id,runId=runId,round=round,generation=generation,targetUserId=target.UserId})
  reviveReply(target,true,buyer.DisplayName..' used a revive token for you.')
 else
  giftOperations[operationKey]='failed';refunded=settleGift(buyer,id,Progress.RefundRevive)
  -- A failed load must not leave an uncredited living ghost in this same level.
  if c and c~=oldCharacter and target.Parent==Players and target.Character==c and target:GetAttribute('RoundDead')==true and identity.runId==runId and identity.round==round and identity.generation==generation then target.Character=nil;c:Destroy()end
 end
 reviving[target]=nil;if target.Parent==Players then target:SetAttribute('Reviving',nil)end
 return success and true or false,success and 'Teammate revived.'or(refunded and 'Respawn unavailable; your saved revive token was restored.'or 'Respawn unavailable; token restoration is retrying.')
end
resumeFromWipe=function()
 local w=pendingWipe;pendingWipe=nil;state:SetAttribute('WipeRevivable',nil)
 -- back to the level as it was; a cart that was mid-sale just sells again at the van
 phase=w.from=='Selling'and 'Searching'or w.from
 state:SetAttribute('FailureReason',nil);state:SetAttribute('TransitionEnds',nil)
 state:SetAttribute('RunSaveChances',w.saved.chances);state:SetAttribute('RunSaveNew',w.saved.new);state:SetAttribute('RunSaveDeleted',w.saved.deleted)
 publish()
end
local function revivePlayer(p,admin)
 if reviving[p]or(not admin and not AntiCheat.Allow(p,'revive',2,4))then return false,'Reviving is already in progress.'end
 if p:GetAttribute('LeavingRun')==true or p:GetAttribute('MissionActive')~=true or p:GetAttribute('RoundDead')~=true or transitioning or(phase~='Searching'and phase~='Returning'and phase~='Selling'and not(phase=='Failed'and pendingWipe))then reviveReply(p,false,'Reviving is unavailable right now.');return false,'Reviving is unavailable right now.'end
 reviving[p]=true;p:SetAttribute('Reviving',true)
 local free=not admin and p:GetAttribute('Pass_free_revive')==true and p:GetAttribute('FreeReviveUsed')~=true
 local id=game.HttpService:GenerateGUID(false)
 local paid=false
 local oldRound,oldGeneration,oldCharacter=round,generation,p.Character
 if not admin and not free then
  local ok,msg=Progress.ConsumeRevive(p,id)
  if not ok then reviving[p]=nil;p:SetAttribute('Reviving',nil);reviveReply(p,false,msg);return end
  paid=true
 end
 if not p.Parent or transitioning or (round~=oldRound or generation~=oldGeneration)or phase=='Won'or phase=='Deploying'or(phase=='Failed'and not pendingWipe)then
  if paid then Progress.RefundRevive(p,id)end
  reviving[p]=nil;if p.Parent then p:SetAttribute('Reviving',nil);reviveReply(p,false,'The level is changing. Your token was restored.')end;return
 end
 local ok=pcall(function()p:LoadCharacterAsync()end)
 local h=p.Character and p.Character:FindFirstChildOfClass('Humanoid')
 local restored=ok and h and h.Health>0 and p.Parent==Players and p.Character~=oldCharacter and p:GetAttribute('MissionActive')==true and round==oldRound and generation==oldGeneration and not transitioning and(phase=='Searching'or phase=='Returning'or phase=='Selling'or phase=='Failed'and pendingWipe~=nil)
 if restored then
  h.Health=h.MaxHealth;p:SetAttribute('RoundDead',false);levelRevives+=1
  if free then p:SetAttribute('FreeReviveUsed',true)
  elseif paid then task.spawn(function()for attempt=1,10 do if Progress.ConfirmRevive(p,id)then return end;task.wait(5)end end)end
  if phase=='Failed'and pendingWipe then resumeFromWipe()end
  if admin then state:SetAttribute('QuestAssisted',true);QuestService.MarkAssisted(runId,round);end;reviveReply(p,true,admin and'An admin revived you.'or free and'Your free revive was used.'or'Revive token used.')
 else
  if paid then local refunded=Progress.RefundRevive(p,id);if not refunded then task.spawn(function()for attempt=1,10 do if Progress.RefundRevive(p,id)then return end;task.wait(5)end end)end end
  reviveReply(p,false,'Respawn failed. Your revive was restored.')
 end
 reviving[p]=nil;if p.Parent then p:SetAttribute('Reviving',nil)end
 return restored==true,restored and'Revived.'or'Respawn failed.'
end
reviveEvent.OnServerEvent:Connect(function(p)revivePlayer(p,false)end)

-- This state belongs to the connected player only, never to a run save/DataStore.
local SESSION_HEALTH='RecoverySessionHealth'
local function rememberSessionHealth(p)
 local h=p.Character and p.Character:FindFirstChildOfClass('Humanoid')
 if h then p:SetAttribute(SESSION_HEALTH,h.Health)end
end
local function watchCharacter(p,c)
 if p:GetAttribute('MissionActive')~=true then return end
 local h=c:WaitForChild('Humanoid',12);if not h or p.Character~=c or p:GetAttribute('MissionActive')~=true then return end
 h.Died:Once(function()
  if p.Character~=c or p:GetAttribute('MissionActive')~=true then return end
  deathSerial[p]=(deathSerial[p]or 0)+1
  p:SetAttribute('RoundDead',true);p:SetAttribute('PhysicalGrabActive',nil);levelDeaths+=1;questDeaths[tostring(p.UserId)]=true;QuestService.Record(p,'Death',1,{eventId='death:'..runId..':'..round..':'..tostring(deathSerial[p]),runId=runId,round=round})
  release(p)
  local items=SS:FindFirstChild('CursedItemApi');if items then items:Invoke('release',p)end
  -- Spectating uses player state; a dead physical character must not remain in the map.
  for _,part in c:GetDescendants()do if part:IsA('BasePart')then part.CanCollide=false;part.CanTouch=false;part.CanQuery=false;part.Transparency=1 end end
  task.defer(function()if p.Character==c and p:GetAttribute('RoundDead')==true then p.Character=nil;c:Destroy()end end)
 end)
 positionCharacter(p,c)
end
local function added(p)
 if p:GetAttribute('MissionActive')~=true then
  task.spawn(function()while p.Parent and p:GetAttribute('MissionActive')~=true do task.wait(.05)end;if p.Parent then added(p)end end);return
 end
 if bound[p]then return end;bound[p]=true
 p:SetAttribute('RoundDead',false)
 p.CharacterAdded:Connect(function(c)task.defer(watchCharacter,p,c)end)
 if p.Character then task.defer(watchCharacter,p,p.Character)
 elseif round>0 then task.spawn(function()if p.Parent then p:LoadCharacterAsync()end end)end
end
-- One run-save writer lives in RunSavesService; Recovery supplies only an authoritative snapshot.
local function runSaveOwner()
 return runSaveContext and Players:GetPlayerByUserId(runSaveContext.ownerUserId)or nil
end
local function genuineRunOwnerDead(p)
 if not p then return false end
 local h=p.Character and p.Character:FindFirstChildOfClass('Humanoid')
 if h and h.Health<=0 then return true end
 -- rebuildWorld marks healthy characters RoundDead while deploying: that is not a death.
 if runSaveDeployMarker then return runSaveDeployOwnerDead or(deathSerial[p]or 0)~=runSaveDeployDeathSerial end
 return p:GetAttribute('RoundDead')==true
end
local function runSaveSnapshot()
 local members={}
 for _,q in ipairs(Players:GetPlayers())do if q:GetAttribute('MissionActive')==true then local h=q.Character and q.Character:FindFirstChildOfClass('Humanoid');table.insert(members,{userId=q.UserId,displayName=q.DisplayName,health=h and h.Health or q:GetAttribute('RecoverySessionHealth'),maxHealth=h and h.MaxHealth or 100})end end
 if RunSaves.CaptureMembers then members=RunSaves.CaptureMembers()end
 -- Gear shop: team bank and unused gear ride along in the run save.
 local gearApi=SS:FindFirstChild('GearShopApi');local gearOk,gearState=false,nil
 if gearApi then gearOk,gearState=pcall(function()return gearApi:Invoke('snapshot')end)end
 if not gearOk or type(gearState)~='table'then gearState={}end
 return {round=round,quota=quota,sold=sold,runId=runId,mapKind=map:GetAttribute('MapKind'),mapSeed=map:GetAttribute('Seed'),members=members,bank=gearState.bank,gear=gearState.gear,mapsSeen=table.clone(mapsSeen)}
end
local function captureRunSave(p)
 if not runSaveContext or typeof(p)~='Instance'or not p:IsA('Player')or p.UserId~=runSaveContext.ownerUserId then return nil end
 if genuineRunOwnerDead(p)then return {delete=true}end
 if transitioning or runSaveFailed or phase=='Failed'or phase=='Loading'or phase=='Deploying'or p.Parent~=Players or p:GetAttribute('MissionActive')~=true or not root(p)or round<1 then return nil end
 return runSaveSnapshot()
end
-- Show what a failure will cost (chances left / NEW SAVE) without writing it yet; returns the old values.
local function previewRunSaveFailure()
 local saved={chances=state:GetAttribute('RunSaveChances'),new=state:GetAttribute('RunSaveNew'),deleted=state:GetAttribute('RunSaveDeleted')}
 if runSaveContext and not runSaveFailed then
  local left=math.max(0,(state:GetAttribute('RunSaveChances')or 3)-1)
  if left<=0 then state:SetAttribute('RunSaveChances',3);state:SetAttribute('RunSaveNew',true);state:SetAttribute('RunSaveDeleted',false);table.clear(mapsSeen)
  else state:SetAttribute('RunSaveChances',left);state:SetAttribute('RunSaveDeleted',false) end
 end
 return saved
end
local function markRunSaveFailed(previewDone)
 -- Sticky for this mission: an automatic restart must not recreate a deleted failed run.
 local first=not runSaveFailed
 runSaveFailed=true
 RunSaves.BlockHealthCache()
 if not first then return end
 -- Show the cost on the round-end card right away; the storage write runs in the background.
 if runSaveContext and not previewDone then
  local left=math.max(0,(state:GetAttribute('RunSaveChances')or 3)-1)
  -- out of chances: the save starts over as a new save at level 1 (RunSaveNew drives the tag and recap card)
  if left<=0 then state:SetAttribute('RunSaveChances',3);state:SetAttribute('RunSaveNew',true);state:SetAttribute('RunSaveDeleted',false);table.clear(mapsSeen)
  else state:SetAttribute('RunSaveChances',left);state:SetAttribute('RunSaveDeleted',false) end
 end
 task.spawn(function()
 -- Any failed run (team wipe or timer) costs the save one chance; the third failure deletes it.
 do
  local ok,result,left,reset=pcall(RunSaves.FailChance,runId..':'..round..':'..generation)
  if not ok or result==false then state:SetAttribute('RunSaveDeleteError',tostring(ok and(left or 'Chance update pending')or result))
  elseif type(left)=='number'then state:SetAttribute('RunSaveChances',left);if reset then state:SetAttribute('RunSaveNew',true)end end
 end
 end)
end
-- The save this mission plays on, for the in-game tag and the round-end card.
if runSaveContext and runSaveContext.slot then
 -- Built from the slot number, never from stored text: older saves may hold a client-sent name that was never filtered.
 state:SetAttribute('RunSaveName',type(runSaveContext.slotIndex)=='number'and('Run '..runSaveContext.slotIndex)or 'Run')
 state:SetAttribute('RunSaveChances',runSaveContext.slot.chances or 3)
 state:SetAttribute('RunSaveDeleted',false)
end
RunSaves.RegisterSnapshot(captureRunSave)
Players.PlayerAdded:Connect(added)
Players.PlayerRemoving:Connect(function(p)release(p);lastRequests[p]=nil;bound[p]=nil;deathSerial[p]=nil end)
workspace.SpawnLocation.CFrame=vanCF*CFrame.new(5,.6,-12);workspace.SpawnLocation.Transparency=1;workspace.SpawnLocation.CanCollide=false
for _,p in ipairs(Players:GetPlayers()) do added(p) end
local stock=SS:WaitForChild('RecoveryLootApi',30);assert(stock,'Recovery loot failed to initialize')
local function rebuildWorld()
 -- Preserve damage before RoundDead is temporarily used as a deployment flag.
 for _,p in Players:GetPlayers()do if p:GetAttribute('MissionActive')then rememberSessionHealth(p)end end
 local reboot={'CursedItemsServer','KeyDoorServer','InteractServer','CreatureRoamServer','GameplaySoundServer','MonsterMimic'}
 local items=SS:FindFirstChild('CursedItemApi')
 for _,p in Players:GetPlayers()do if p:GetAttribute('MissionActive')then
  if items then items:Invoke('reset',p)end
  for _,name in {'FreeReviveUsed','Reviving','Hiding','ClosetState','ClosetProtectedUntil','MonsterJumpscareActive','GrabProtectionUntil','MoustacheFace','DiscoSmileForced'}do p:SetAttribute(name,nil)end
  p:SetAttribute('Valuables',0);p:SetAttribute('RoundDead',true)
  if p.Character then p.Character:SetAttribute('RecoverySpawnReady',false)end
 end end
 for _,name in reboot do game.ServerScriptService[name].Enabled=false end
 for _,name in {'CursedItemApi','RecoveryLootApi','KeyDoorApi','MonsterMimicApi','CursedItemAdminApi','CreatureAdminApi'}do local old=SS:FindFirstChild(name);if old then old:Destroy()end end
 for _,child in game.ServerScriptService.InteractServer:GetChildren()do if child.Name=='MonsterDoorApi'or child.Name=='MonsterClosetApi'then child:Destroy()end end
 for _,child in game.ServerScriptService.CursedItemsServer:GetChildren()do if child.Name=='PreviewCursedBatch'then child:Destroy()end end
 for _,graph in RS:GetChildren()do if graph.Name:match('^MimicVoice_')then graph:Destroy()end end
 local creatures=workspace:FindFirstChild('RoamingCreatures');if creatures then creatures:ClearAllChildren()end
 local cosmetics=workspace:FindFirstChild('CursedLevelCosmetics');if cosmetics then cosmetics:ClearAllChildren()end
 local spit=workspace:FindFirstChild('SpitTrails');if spit then spit:ClearAllChildren()end
 for _,object in workspace:GetChildren()do if object.Name=='SecondShadow'then object:Destroy()end end
 camp:Destroy()
 map:SetAttribute('Ready',false);map:SetAttribute('RuntimeReady',false)
 for _,p in Players:GetPlayers()do if p:GetAttribute('MissionActive')==true then RS.LobbyEvent:FireClient(p,'restart',{})end end
 local success,info=game.ServerScriptService.MapGen:WaitForChild('RegenerateMissionMap'):Invoke(nextMapKind(map:GetAttribute('MapKind')))
 entrance=workspace.SpawnLocation.Position;exteriorZ=entrance.Z
 for _,room in game.HttpService:JSONDecode(map.GeneratedGraph.Value).rooms do exteriorZ=math.max(exteriorZ,room.z2)end
 camp=Instance.new('Model');camp.Name='RecoveryCamp';camp.Parent=workspace
 van,vanCF,readouts=Models.Van(camp,entrance,exteriorZ);parkCF=vanCF*CARTPARK_OFFSET
 cart,cartLabel=Models.Cart(map.Interactive,parkCF)
 for _,part in cart:GetDescendants()do if part:IsA('BasePart')then part.Anchored=false;pcall(function()part:SetNetworkOwner(nil)end)end end
 workspace.SpawnLocation.CFrame=vanCF*CFrame.new(5,.6,-12)
 game.ServerScriptService.CursedItemsServer:SetAttribute('Initialized',nil)
 for _,name in reboot do game.ServerScriptService[name].Enabled=true end
 stock=SS:WaitForChild('RecoveryLootApi',30);assert(stock,'Restart loot did not initialize')
 if not success then error(info)end
 state:SetAttribute('MapKind',map:GetAttribute('MapKind'));state:SetAttribute('MapSeed',map:GetAttribute('Seed'))
 state:SetAttribute('RunRevision',(state:GetAttribute('RunRevision')or 0)+1)
end
local forceRebuild:any=false -- RestartMission: the previous run's map is spent
local function nextRound(restart)
 if transitioning then return end
 local saveOwner=runSaveOwner();runSaveDeployOwnerDead=genuineRunOwnerDead(saveOwner);runSaveDeployDeathSerial=saveOwner and(deathSerial[saveOwner]or 0)or 0;runSaveDeployMarker=true
 transitioning=true;generation+=1
 -- a retry, or a fresh level 1 on a just-renewed save, saves again; clearing a level ends the NEW SAVE label
 if restart=='retry' or (restart==true and state:GetAttribute('RunSaveNew')) then runSaveFailed=false end
 if not restart then state:SetAttribute('RunSaveNew',nil) end
 phase='Deploying';selling=false;started=nil;state:SetAttribute('ExtractionSeconds',nil);state:SetAttribute('SaleEnds',nil);state:SetAttribute('TransitionEnds',nil)
 release(owner)
 local resume=round==0 and not restart and initialRunSave or nil;initialRunSave=nil
 if resume and type(resume.round)=='number'and resume.round==math.floor(resume.round)and resume.round>=1 and resume.round<math.huge and type(resume.quota)=='number'and resume.quota>=1 and resume.quota<math.huge and type(resume.runId)=='string'and #resume.runId>0 then
  round=resume.round;quota=resume.quota;runId=resume.runId
 else
  if restart==true then runId=game.HttpService:GenerateGUID(false);for _,p in Players:GetPlayers()do if p:GetAttribute('MissionActive')then local h=p.Character and p.Character:FindFirstChildOfClass('Humanoid');p:SetAttribute('RecoverySessionHealth',h and h.MaxHealth or 100);if h and h.Health>0 then h.Health=h.MaxHealth end end end end
  if restart~='retry' then round=restart and 1 or round+1 end;quota=math.floor(180*1.3^(round-1))
 end
 -- Resume the start of this level: historical sold is metadata, fresh level loot starts at zero.
 sold=0;table.clear(credited)
 for _,p in Players:GetPlayers()do if p:GetAttribute('MissionActive')==true then local items=SS:FindFirstChild('CursedItemApi');if items then items:Invoke('release',p)end end end
 table.clear(cargo)
 -- A resumed level-1 save that already saw the startup map's type gets a fresh, unseen map first.
 local staleMap=table.find(mapsSeen,map:GetAttribute('MapKind'))~=nil and #mapsSeen<#MapProfiles.Kinds
 if restart or round>1 or staleMap or forceRebuild then
  local ok,err=pcall(rebuildWorld)
  if not ok then
   -- RestartMission: a failed rebuild must not cost the new save a chance or auto-retry; the caller rolls back.
   if forceRebuild=='restart' then transitioning=false;phase='Ended';generation+=1;runSaveDeployMarker=false;state:SetAttribute('RestartError',tostring(err));return end
   transitioning=false;phase='Failed';markRunSaveFailed();state:SetAttribute('RestartError',tostring(err));state:SetAttribute('TransitionEnds',workspace:GetServerTimeNow()+5);publish()
   task.delay(5,function()if phase=='Failed'and not transitioning then nextRound(true)end end)
   return
  end
  forceRebuild=false;state:SetAttribute('RestartError',nil)
 end
 cart:PivotTo(parkCF);cart.PrimaryPart.AssemblyLinearVelocity=Vector3.zero;cart.PrimaryPart.AssemblyAngularVelocity=Vector3.zero
 noteMap(map:GetAttribute('MapKind'))
 stock:Invoke('restock',round,quota);publish()
 for _,p in Players:GetPlayers()do if p:GetAttribute('MissionActive')==true then
  local h=p.Character and p.Character:FindFirstChildOfClass('Humanoid')
  if not h or h.Health<=0 or p:GetAttribute('RoundDead')then
   local ok,err=pcall(function()p:LoadCharacterAsync()end)
   if not ok and p.Parent then warn('[RecoveryRound] Revival failed: '..tostring(err))end
  end
  if p.Character then
   local hum=p.Character:FindFirstChildOfClass('Humanoid')
   if hum and hum.Health>0 then local saved=p:GetAttribute(SESSION_HEALTH);if type(saved)=='number'and saved>0 then hum.Health=math.min(hum.MaxHealth,saved)end;positionCharacter(p,p.Character);p:SetAttribute('RoundDead',false);rememberSessionHealth(p)end
  end
 end end
 levelStarted=workspace:GetServerTimeNow();levelItems,levelDeaths,levelRevives=0,0,0;table.clear(questDeaths);questQuotaCredited=false;state:SetAttribute("QuestAssisted",nil)
 local roam=game.ServerScriptService:FindFirstChild('CreatureRoamServer');local aided=state:GetAttribute('QuestAssistedRunId')==runId or roam and roam:GetAttribute('AdminNoMonsters')==true
 for _,member in Players:GetPlayers()do if member:GetAttribute('MissionActive')==true and (member:GetAttribute('AdminGod')==true or member:GetAttribute('AdminWalkSpeed')~=nil or member:GetAttribute('AdminJumpHeight')~=nil)then aided=true;break end end
 if aided then state:SetAttribute('QuestAssisted',true);QuestService.MarkAssisted(runId,round)end
 local duration=script:GetAttribute('LevelDurationSeconds');if type(duration)~='number' or duration~=duration then duration=600 end
 -- Level 1 is the gentle first impression: five extra minutes on the clock.
 if round==1 then duration+=300 end
 state:SetAttribute('LevelEnds',levelStarted+math.clamp(duration,30,3600));state:SetAttribute('FailureReason',nil)
 runSaveDeployMarker=false
 phase='Searching';transitioning=false;publish()
 -- Save the level you reached right away, not only when the owner leaves.
 if runSaveContext and not runSaveFailed and not state:GetAttribute('RunSaveDeleted') then
  local snap=runSaveSnapshot()
  task.spawn(function()
   local ok,saved,msg=pcall(RunSaves.Checkpoint,snap)
   state:SetAttribute('RunSaveCheckpoint',ok and saved and round or nil)
   if not ok or not saved then state:SetAttribute('RunSaveCheckpointError',tostring(ok and msg or saved)) else state:SetAttribute('RunSaveCheckpointError',nil) end
  end)
 end
end
nextRound()
-- Same-session restart after every player returned to the lobby (phase Ended).
-- MissionRuntime calls this after RunSaves.BeginMission acquired the next save and set MissionActive.
local restartApi=Instance.new('BindableFunction');restartApi.Name='RestartMission';restartApi.Parent=script
restartApi.OnInvoke=function(ownerUserId)
 if phase~='Ended'or transitioning or pendingWipe then return false,'Recovery round is still running.'end
 for _,q in Players:GetPlayers()do if leavingRun[q]then return false,'A lobby return is still in progress.'end end
 local context=RunSaves.GetMissionContext()
 if not context or type(context.ownerUserId)~='number'then return false,'No run-save context for the new mission.'end
 if ownerUserId~=nil and ownerUserId~=context.ownerUserId then return false,'Restart owner does not match the run save.'end
 local saveOwner=Players:GetPlayerByUserId(context.ownerUserId)
 if not saveOwner or saveOwner:GetAttribute('MissionActive')~=true then return false,'The run-save owner is not in the mission.'end
 runSaveContext=context
 initialRunSave=type(context.mode)=='string'and context.mode:lower()=='load'and context.slot or nil
 table.clear(mapsSeen)
 if context.slot and type(context.slot.mapsSeen)=='table'then for _,k in ipairs(context.slot.mapsSeen)do noteMap(k)end end
 -- terminal / wipe / deployment state from the previous run
 runSaveFailed=false;failedFrom='Searching';table.clear(reviving)
 runSaveDeployMarker=false;runSaveDeployOwnerDead=false;runSaveDeployDeathSerial=0
 round,quota,sold=0,0,0;selling=false;started=nil;release(owner);aim=nil;table.clear(credited);table.clear(cargo);table.clear(contents)
 runId=game.HttpService:GenerateGUID(false)
 for _,name in {'WipeRevivable','TransitionEnds','FailureReason','RunSaveNew','RunSaveDeleteError','RunSaveCheckpoint','RunSaveCheckpointError','RestartError','QuestAssisted','ExtractionSeconds','SaleEnds'}do state:SetAttribute(name,nil)end
 state:SetAttribute('RunSaveName',type(context.slotIndex)=='number'and('Run '..context.slotIndex)or 'Run')
 state:SetAttribute('RunSaveChances',context.slot and context.slot.chances or 3)
 state:SetAttribute('RunSaveDeleted',false)
 local restartGeneration=generation
 phase='Loading';forceRebuild='restart'
 -- LOAD: round 0 + not restart takes the resume path; NEW: restart==true starts level 1 with full health.
 local ok,err=pcall(nextRound,initialRunSave==nil or nil)
 forceRebuild=false
 if not ok then transitioning=false;phase='Ended';generation+=1;runSaveDeployMarker=false;return false,tostring(err)end
 if generation==restartGeneration or phase~='Searching'then return false,tostring(state:GetAttribute('RestartError')or'Restart did not reach Searching.')end
 return true
end
-- Owner admin panel (AdminPowersServer checks the owner). Skips never record clears, badges or tokens.
local adminApi=Instance.new('BindableFunction');adminApi.Name='RecoveryAdminApi'
adminApi.OnInvoke=function(action,value)
 if action=='status' then return {round=round,phase=phase,quota=quota,sold=sold,levelEnds=state:GetAttribute('LevelEnds')}end
 if action=='revive'then
  if typeof(value)~='Instance'or not value:IsA('Player')or value.Parent~=Players then return false,'Player left.'end
  return revivePlayer(value,true)
 end
 if transitioning then return false,'A level is already loading.' end
 if action=='restart' then state:SetAttribute('QuestAssisted',true);QuestService.MarkAssisted(runId,round);task.spawn(nextRound,true);return true,'Restarting from level 1.'
 elseif action=='next' then state:SetAttribute('QuestAssisted',true);QuestService.MarkAssisted(runId,round);task.spawn(nextRound,false);return true,'Starting the next level.'
 elseif action=='end' then
  if phase~='Searching' and phase~='Returning' and phase~='Selling' then return false,'No level is running.' end
  state:SetAttribute('QuestAssisted',true);QuestService.MarkAssisted(runId,round);state:SetAttribute('LevelEnds',workspace:GetServerTimeNow());return true,'Ending the level.'
 elseif action=='addTime' then
  local ends=state:GetAttribute('LevelEnds');if type(ends)~='number' then return false,'No level timer.' end
  state:SetAttribute('QuestAssisted',true);QuestService.MarkAssisted(runId,round);state:SetAttribute('LevelEnds',ends+math.clamp(tonumber(value) or 60,-3600,3600));return true,'Timer changed.'
 elseif action=='quota' then
  state:SetAttribute('QuestAssisted',true);QuestService.MarkAssisted(runId,round);sold=quota;phase='Returning';publish();return true,'Quota met. Return to the van to clear.'
 end
 return false,'Unknown round action.'
end
adminApi.Parent=SS
local acc=0
local ownershipCheck=0
-- Round recap: only numbers the server actually records, sent to every mission
-- participant (dead and spectating included). Clients dedupe by id. Tokens are
-- confirmed separately by ProgressService once the save succeeds.
local recapEvent=RS:FindFirstChild('RoundRecap') or Instance.new('RemoteEvent');recapEvent.Name='RoundRecap';recapEvent.Parent=RS
local Shop=require(RS:WaitForChild('LobbyShopCatalog'))
WIN_HOLD=10 -- seconds the clear stays on screen (was 7) so the recap can be read
sendRecap=function(outcome)
 local id=runId..':'..round..':'..outcome
 local roster,survivors={},0
 for _,p in Players:GetPlayers() do if p:GetAttribute('MissionActive')==true then table.insert(roster,p);if p:GetAttribute('RoundDead')~=true then survivors+=1 end end end
 local base={id=id,outcome=outcome,reason=outcome=='Failed' and state:GetAttribute('FailureReason') or nil,level=round,quota=quota,sold=sold,
  items=levelItems,deaths=levelDeaths,revives=levelRevives,seconds=math.max(0,math.floor(workspace:GetServerTimeNow()-levelStarted)),
  survivors=survivors,team=#roster,nextQuota=math.floor(180*1.3^round),runLevels=Shop.RunLevels}
 for _,p in roster do
  local mine=table.clone(base)
  mine.survived=p:GetAttribute('RoundDead')~=true
  mine.tokensExpected=outcome=='Won' and round%Shop.RunLevels==0 and Shop.TokensPerRun*(p:GetAttribute('Pass_double_tokens') and 2 or 1) or 0
  recapEvent:FireClient(p,'recap',mine)
 end
 state:SetAttribute('LastRecapId',id)
end
-- Level cleared: record it, show the recap, then move on to the next level.
winLevel=function()
 phase='Won'
 local roster={};for _,player in Players:GetPlayers()do if player:GetAttribute('MissionActive')==true then table.insert(roster,player)end end
 Progress.RecordClear(roster,runId,round,sold,math.max(1,math.round((workspace:GetServerTimeNow()-levelStarted)*1000)),{items=levelItems,mapKind=map:GetAttribute('MapKind'),teamSize=#roster,deathsByUser=table.clone(questDeaths),assisted=state:GetAttribute('QuestAssisted')==true,round=round,generation=generation,noPartyDeath=levelDeaths==0,timeLeft=math.max(0,(state:GetAttribute('LevelEnds')or 0)-workspace:GetServerTimeNow())});QuestService.FlushParty(roster)
 publish();state:SetAttribute('ExtractionSeconds',nil);state:SetAttribute('TransitionEnds',workspace:GetServerTimeNow()+WIN_HOLD);sendRecap('Won')
 task.delay(WIN_HOLD,function()if phase=='Won'then nextRound(false)end end)
end
local CART_PUSH_DISTANCE=9.3 -- studs ahead of the pusher (was 6.2; 1.5x reach)
Run.Heartbeat:Connect(function(dt)
 if transitioning or not cart or not cart.PrimaryPart then return end
 ownershipCheck+=dt;if ownershipCheck>=1 then ownershipCheck=0;serverOwnsCart() end
 if owner then local r=root(owner);if not r or os.clock()-lease>.85 or (r.Position-cart.PrimaryPart.Position).Magnitude>18 then release(owner) else
  local cf=aim or r.CFrame;local look=Vector3.new(cf.LookVector.X,0,cf.LookVector.Z);if look.Magnitude>.01 then look=look.Unit else look=r.CFrame.LookVector end
  local params=RaycastParams.new();params.FilterType=Enum.RaycastFilterType.Exclude;params.FilterDescendantsInstances={cart,owner.Character,map.Interactive};params.RespectCanCollide=true;params.CollisionGroup='RecoveryCart'
  local target=r.Position+look*CART_PUSH_DISTANCE;local hit=workspace:Raycast(target+Vector3.new(0,5,0),Vector3.new(0,-20,0),params);target=Vector3.new(target.X,hit and hit.Position.Y+cart:GetAttribute('GroundOffset') or r.Position.Y-1.8,target.Z)
  local rotation=CFrame.lookAt(Vector3.zero,look).Rotation*CFrame.Angles(0,math.pi,0)
  if cartAcquire then
   local t=math.clamp((os.clock()-cartAcquire.started)/CART_ACQUIRE_SECONDS,0,1)
   local blend=t*t*(3-2*t)
   target=cartAcquire.position:Lerp(target,blend);rotation=cartAcquire.rotation:Lerp(rotation,blend)
   if t>=1 then cartAcquire=nil end
  end
  local a=cart.PrimaryPart:FindFirstChild('CartHold_Position');local b=cart.PrimaryPart:FindFirstChild('CartHold_Orientation');if a then a.Position=target end;if b then b.CFrame=rotation end
 end end
 if not owner then
  local nearBody=false
  for _,p in ipairs(Players:GetPlayers()) do local r=root(p);if r and (r.Position-cart.PrimaryPart.Position).Magnitude<8 then nearBody=true;break end end
  local decay=math.exp(-(nearBody and 1.5 or 12)*dt);local v=cart.PrimaryPart.AssemblyLinearVelocity;cart.PrimaryPart.AssemblyLinearVelocity=Vector3.new(v.X*decay,v.Y,v.Z*decay);cart.PrimaryPart.AssemblyAngularVelocity*=decay
  for _,x in ipairs(cart:GetChildren()) do if x:IsA('BasePart') and x.Name=='Wheel' then x.AssemblyAngularVelocity*=decay end end
 end
 if transitioning then return end
 acc+=dt;if acc<.1 then return end;acc=0
 updateCargo()
 local cartValue;contents,cartValue=snapshot();cart:SetAttribute('CartValue',cartValue);cartLabel.Text='$'..cartValue;state:SetAttribute('CartValue',cargoTotal(cartValue))
 if cart.PrimaryPart.Position.Y<-30 then release(owner);cart:PivotTo(parkCF);cart.PrimaryPart.AssemblyLinearVelocity=Vector3.zero end
 if cartAtVan() and cartValue>0 and not selling and not owner then sell(nil) end -- only sells once nobody is pushing
 local alive,inside,participants=0,0,0;for _,p in ipairs(Players:GetPlayers()) do if p:GetAttribute('MissionActive')==true then participants+=1 end;if root(p) then alive+=1;if inVan(p) then inside+=1 end end end
 state:SetAttribute('Alive',alive);state:SetAttribute('InVan',inside)
 local timedOut=workspace:GetServerTimeNow()>=(state:GetAttribute('LevelEnds')or math.huge)
 if participants>0 and (alive==0 or timedOut) and (phase=='Searching'or phase=='Returning'or phase=='Selling')then
  state:SetAttribute('FailureReason',timedOut and 'TimeExpired'or 'TeamWipe')
  failedFrom=phase;phase='Failed';generation+=1
  if timedOut then markRunSaveFailed() else pendingWipe={from=failedFrom,saved=previewRunSaveFailure(),id=generation};state:SetAttribute('WipeRevivable',true) end
  local wipeId=generation;selling=false;started=nil;state:SetAttribute('SaleEnds',nil);state:SetAttribute('ExtractionSeconds',nil)
   -- A team wipe leaves room for the monster victory cutscene (MonsterWinCutscene client).
   local hold=timedOut and 7 or 13
   state:SetAttribute('TransitionEnds',workspace:GetServerTimeNow()+hold);publish();sendRecap('Failed')
  task.delay(7,function()
   if hold>7 then task.wait(hold-7) end
    while next(reviving)and phase=='Failed'do task.wait(.1)end
    -- nobody revived in time: now the failure (and its chance) is final
    if phase=='Failed'and pendingWipe and pendingWipe.id==wipeId then pendingWipe=nil;state:SetAttribute('WipeRevivable',nil);markRunSaveFailed(true)end
   if phase=='Failed'and generation==wipeId then nextRound((runSaveContext and not state:GetAttribute('RunSaveDeleted')and not state:GetAttribute('RunSaveNew'))and 'retry' or true)end
  end)
 elseif phase=='Returning' then
  if alive>0 and alive==inside and cartAtVan() then started=started or os.clock();local left=math.max(0,7-(os.clock()-started));state:SetAttribute('ExtractionSeconds',left)
   if left<=0 then winLevel() end
  else started=nil;state:SetAttribute('ExtractionSeconds',nil) end
 end
end)

