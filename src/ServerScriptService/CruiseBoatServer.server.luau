local QuestService=require(game:GetService('ServerScriptService'):WaitForChild('QuestService'))
local QuestHttp=game:GetService('HttpService')
local function questContext(eventId,model)
 local s=game:GetService('ReplicatedStorage'):FindFirstChild('RecoveryRound')
 local map=workspace:FindFirstChild('Mansion')
 return {eventId=eventId,runId=s and s:GetAttribute('QuestRunId'),round=s and s:GetAttribute('Round'),generation=s and s:GetAttribute('QuestGeneration'),mapKind=map and map:GetAttribute('MapKind'),admin=model and (model:GetAttribute('AdminEffect')==true or model:GetAttribute('AdminSpawned')==true),lobbyToy=model and model:GetAttribute('LobbyToy')==true,itemId=model and model:GetAttribute('ItemId')}
end
-- Cruise launch: driver-owned motion; server-owned docks, riders, cargo and sales.
local Players=game:GetService('Players')
local RS=game:GetService('ReplicatedStorage')
local SS=game:GetService('ServerStorage')
local Run=game:GetService('RunService')
local Collection=game:GetService('CollectionService')
local Core=require(RS:WaitForChild('CruiseBoatCore'))
local Audio=require(game:GetService('ServerScriptService'):WaitForChild('GameplayAudioServer'))
-- Live servers (owner 2026-10-27): Cruise is out of the map pool (MapGen.Profiles.Kinds), so the boat system stays off
-- (no remote, no Heartbeat); RecoveryRoundServer already treats a missing CruiseBoatApi as no boat. Studio keeps it.
if not game:GetService('RunService'):IsStudio()and not table.find(require(game:GetService('ServerScriptService'):WaitForChild('MapGen'):WaitForChild('Profiles')).Kinds,'Cruise')then return end
local remote=Instance.new('RemoteEvent');remote.Name='CruiseBoatEvent';remote.Parent=RS
local api=Instance.new('BindableFunction');api.Name='CruiseBoatApi';api.Parent=SS
local current;local serial=0;local buckets={};local missingKit=false;local initializing=false;local constructing
local releaseRider,embark,disembark,cleanup,seatRider
local landings={};local landingSerial=0
local function finishLanding(p,ticket)
 if landings[p]~=ticket then return end
 landings[p]=nil
 if ticket.state.landingSeats[ticket.index]==p then ticket.state.landingSeats[ticket.index]=nil end
 if p:GetAttribute('CruiseBoatLandingId')==ticket.id then p:SetAttribute('CruiseBoatLandingId',nil)end
 if not ticket.root.Parent then return end
 ticket.root.Anchored=ticket.anchored
 if not ticket.anchored and p.Parent==Players and p.Character==ticket.character and not p:GetAttribute('CruiseBoatEpoch')and ticket.humanoid.Parent and ticket.humanoid.Health>0 and not p:GetAttribute('RoundDead')then
  pcall(function()ticket.root:SetNetworkOwner(p)end)
 end
end
local function validLanding(p,ticket)
 return landings[p]==ticket and current==ticket.state and ticket.state.epoch==ticket.epoch
  and p.Parent==Players and p.Character==ticket.character and ticket.root.Parent and ticket.character.Parent
  and ticket.humanoid.Parent and ticket.humanoid.Health>0 and p:GetAttribute('MissionActive')==true
  and not p:GetAttribute('RoundDead')and not p:GetAttribute('CruiseBoatEpoch')
end
local function acknowledgeLanding(p,id,attempt)
 local ticket=landings[p]
 if not ticket or(attempt~=1 and attempt~=2)or ticket.id~=id or ticket.attempt~=attempt or not validLanding(p,ticket)then return false end
 ticket.acknowledged=true;return true
end
local function sendLanding(p,ticket)
 ticket.attempt+=1;ticket.acknowledged=false;ticket.nearSince=nil;ticket.deadline=os.clock()+1
 remote:FireClient(p,'land',ticket.id,ticket.attempt,ticket.character,ticket.target,ticket.state.boat)
end
local function pollLanding(p,ticket)
 if landings[p]~=ticket then return end
 if not validLanding(p,ticket)then finishLanding(p,ticket);return end
 local now=os.clock();local gap=(ticket.root.Position-ticket.target.Position).Magnitude
 if ticket.acknowledged and gap<=4 then
  ticket.nearSince=ticket.nearSince or now
  if now-ticket.nearSince>=.15 then finishLanding(p,ticket);return end
 else ticket.nearSince=nil end
 if now>=ticket.deadline then
  if ticket.attempt<2 then sendLanding(p,ticket)
  else
   local s,index=ticket.state,ticket.index
   finishLanding(p,ticket)
   -- The rollback slot was reserved after driver promotion, so another boarder
   -- cannot consume it while this client-owned character is landing.
   if current==s and p.Character==ticket.character and not s.seated[index]then
    seatRider(s,p,index,ticket.character,ticket.humanoid,ticket.root)
   end
   return
  end
 end
 task.delay(.05,function()pollLanding(p,ticket)end)
end
local function landRider(s,p,rider,target)
 local index=rider.index
 if s.seated[index]or s.landingSeats[index]then index=nil;for i=1,4 do if not s.seated[i]and not s.landingSeats[i]then index=i;break end end end
 assert(index,'No rollback seat after releasing rider')
 landingSerial+=1
 local root=rider.root
 local ticket={id=landingSerial,attempt=0,state=s,epoch=s.epoch,index=index,root=root,character=rider.character,humanoid=rider.humanoid,target=target,anchored=root.Anchored}
 landings[p]=ticket;s.landingSeats[index]=p;p:SetAttribute('CruiseBoatLandingId',ticket.id)
 pcall(function()root:SetNetworkOwner(nil)end)
 root.Anchored=true;rider.character:PivotTo(target)
 root.AssemblyLinearVelocity=Vector3.zero;root.AssemblyAngularVelocity=Vector3.zero
 task.delay(.15,function()
  if not validLanding(p,ticket)then finishLanding(p,ticket);return end
  root.Anchored=ticket.anchored
  if not ticket.anchored then pcall(function()root:SetNetworkOwner(p)end)end
  sendLanding(p,ticket);pollLanding(p,ticket)
 end)
end
local function living(p)
 local c=p and p.Character;local h=c and c:FindFirstChildOfClass('Humanoid');local root=c and c:FindFirstChild('HumanoidRootPart')
 if not p or p.Parent~=Players or p:GetAttribute('MissionActive')~=true or p:GetAttribute('RoundDead')==true or not h or h.Health<=0 or not root then return nil end
 return c,h,root
end
local function flatDistance(a,b)return(Vector3.new(a.X,0,a.Z)-Vector3.new(b.X,0,b.Z)).Magnitude end
local function yaw(cf)return math.atan2(-cf.LookVector.X,-cf.LookVector.Z)end
local function dockList(s)
 local list={};for id,dock in pairs(s.docks)do table.insert(list,{id=id,point=dock.moor.Position,dock=dock})end;return list
end
local function nearest(s,position)local row=Core.NearestDock(position,dockList(s));return row and row.dock end
local function float(s,x,z,heading)return s.water.Float(x,z,heading,s.length,s.width,workspace:GetServerTimeNow())*CFrame.new(0,s.floatOffset,0)end
local function setOwner(s,p)
 pcall(function()s.root:SetNetworkOwner(p)end)
 s.simOwner=p
end
-- Initial placement and explicit Studio fixtures only. Runtime parking never pivots.
local function placeAtDock(s,dock)
 s.docking=nil;s.boat:SetAttribute('DockingDock',nil)
 local pos=dock.moor.Position
 if not Core.Safe(pos.X,pos.Z,s.bounds,s.radius)then return false end
 s.moored=dock;s.throttle=0;s.steer=0;s.motion={x=pos.X,z=pos.Z,yaw=yaw(dock.moor),speed=0}
 local cf=float(s,pos.X,pos.Z,s.motion.yaw)
 s.boat:PivotTo(cf);s.root.AssemblyLinearVelocity=Vector3.zero;s.root.AssemblyAngularVelocity=Vector3.zero
 s.position.Position=cf.Position;s.orientation.CFrame=cf.Rotation;s.lastValid=cf;s.lastTime=os.clock()
 s.boat:SetAttribute('MooredDock',dock.id);s.boat:SetAttribute('LastDock',dock.id);s.boat:SetAttribute('MooredHome',dock.home)
 return true
end
local function finishDock(s,dock)
 if s.questTrip and dock.id~=s.questTrip.from and flatDistance(s.questTrip.position,dock.moor.Position)>=20 and s.questTrip.driver==s.driver and living(s.driver) then
  QuestService.Record(s.driver,'BoatDocked',1,questContext('dock:'..s.questTrip.id));s.questTrip=nil
 end
 s.docking=nil;s.moored=dock;s.throttle=0;s.steer=0
 s.boat:SetAttribute('DockingDock',nil);s.boat:SetAttribute('MooredDock',dock.id)
 s.boat:SetAttribute('LastDock',dock.id);s.boat:SetAttribute('MooredHome',dock.home)
 s.motion={x=dock.moor.Position.X,z=dock.moor.Position.Z,yaw=yaw(dock.moor),speed=0}
 setOwner(s,s.driver)
end
local function beginDock(s,dock,now)
 local pos=s.root.Position;local target=dock.moor.Position
 if not Core.MoorEligible(s.root.AssemblyLinearVelocity.Magnitude,s.throttle,flatDistance(pos,target),dock.radius,now,s.departUntil,yaw(s.root.CFrame),yaw(dock.moor))then return false end
 local cx,cz=Core.Clamp(pos.X,pos.Z,target.X,target.Z,s.bounds,s.radius)
 if math.abs(cx-target.X)>.05 or math.abs(cz-target.Z)>.05 then return false end
 s.docking={dock=dock,began=now,from={x=pos.X,z=pos.Z,yaw=yaw(s.root.CFrame)},to={x=target.X,z=target.Z,yaw=yaw(dock.moor)}}
 s.moored=nil;s.throttle=0;s.steer=0
 s.boat:SetAttribute('MooredDock',nil);s.boat:SetAttribute('MooredHome',false);s.boat:SetAttribute('DockingDock',dock.id)
 setOwner(s,nil)
 return true
end
local function updateDock(s,now)
 local docking=s.docking;if not docking then return end
 local pose=Core.DockPose(docking.from,docking.to,(now-docking.began)/1.6)
 local cf=float(s,pose.x,pose.z,pose.yaw)
 s.position.Position=cf.Position;s.orientation.CFrame=cf.Rotation
 if now-docking.began>=1.6 and flatDistance(s.root.Position,docking.dock.moor.Position)<.6
  and Core.HeadingError(yaw(s.root.CFrame),docking.to.yaw)<math.rad(5)and s.root.AssemblyLinearVelocity.Magnitude<3 then
  finishDock(s,docking.dock)
 elseif now-docking.began>8 then
  s.docking=nil;s.boat:SetAttribute('DockingDock',nil);s.departUntil=now+1.25
  s.motion={x=s.root.Position.X,z=s.root.Position.Z,yaw=yaw(s.root.CFrame),speed=0};setOwner(s,s.driver)
 end
end
local function enablePart(rider,part)
 if not part:IsA('BasePart')or rider.parts[part]then return end
 rider.parts[part]={collide=part.CanCollide,massless=part.Massless};part.CanCollide=false;part.Massless=true
end
local function announceDriver(s)
 s.boat:SetAttribute('DriverUserId',s.driver and s.driver.UserId or 0)
 if s.docking then setOwner(s,nil)else setOwner(s,s.driver)end
end
releaseRider=function(s,p,teleport,promote)
 local rider=s.riders[p];if not rider then return false end
 s.riders[p]=nil;s.seated[rider.index]=nil
 for _,connection in ipairs(rider.connections)do connection:Disconnect()end
 if rider.weld.Parent then rider.weld:Destroy()end
 if rider.humanoid.Parent then
  rider.humanoid.Sit=false;rider.humanoid.AutoRotate=rider.autoRotate
  rider.humanoid.WalkSpeed=rider.walkSpeed;rider.humanoid.JumpPower=rider.jumpPower;rider.humanoid.JumpHeight=rider.jumpHeight
 end
 for part,old in pairs(rider.parts)do if part.Parent then part.CanCollide=old.collide;part.Massless=old.massless end end
 p:SetAttribute('CruiseBoatSeat',nil);p:SetAttribute('CruiseBoatEpoch',nil)
 if s.driver==p then
  s.driver=nil;s.throttle=0;s.steer=0
  if promote~=false then
   for i=2,4 do local nextPlayer=s.seated[i]
    if nextPlayer and living(nextPlayer)then
     local nextRider=s.riders[nextPlayer];s.seated[i]=nil;s.seated[1]=nextPlayer;nextRider.index=1
     nextRider.weld:Destroy();nextRider.character:PivotTo(s.seats[1].CFrame)
     local weld=Instance.new('WeldConstraint');weld.Name='CruiseOccupantWeld';weld.Part0=s.seats[1];weld.Part1=nextRider.root;weld.Parent=s.seats[1];nextRider.weld=weld
     nextPlayer:SetAttribute('CruiseBoatSeat',1);s.driver=nextPlayer;break
    end
   end
  end
  announceDriver(s)
 end
 if teleport and rider.character.Parent then landRider(s,p,rider,teleport)end
 return true
end
seatRider=function(s,p,index,c,h,root)
 local rider={index=index,character=c,humanoid=h,root=root,parts={},connections={},autoRotate=h.AutoRotate,walkSpeed=h.WalkSpeed,jumpPower=h.JumpPower,jumpHeight=h.JumpHeight}
 for _,part in ipairs(c:GetDescendants())do enablePart(rider,part)end
 c:PivotTo(s.seats[index].CFrame);root.AssemblyLinearVelocity=s.root.AssemblyLinearVelocity
 local weld=Instance.new('WeldConstraint');weld.Name='CruiseOccupantWeld';weld.Part0=s.seats[index];weld.Part1=root;weld.Parent=s.seats[index];rider.weld=weld
 h.AutoRotate=false;h.WalkSpeed=0;h.JumpPower=0;h.JumpHeight=0;h.Jump=false;h.Sit=true
 s.riders[p]=rider;s.seated[index]=p;p:SetAttribute('CruiseBoatSeat',index);p:SetAttribute('CruiseBoatEpoch',s.epoch)
 table.insert(rider.connections,c.DescendantAdded:Connect(function(part)enablePart(rider,part)end))
 table.insert(rider.connections,h.Died:Connect(function()if current==s then releaseRider(s,p,nil,true)end end))
 if index==1 then s.driver=p;announceDriver(s)end
 return true
end
embark=function(s,p,id)
 local c,h,root=living(p);local dock=s.docks[id]
 if not c or not dock or landings[p]or s.riders[p]or s.moored~=dock or flatDistance(s.root.Position,dock.moor.Position)>dock.radius then return false end
 if not Core.Finite(root.Position.X)or not Core.Finite(root.Position.Y)or not Core.Finite(root.Position.Z)then return false end
 if(root.Position-dock.board.Position).Magnitude>11 or s.root.AssemblyLinearVelocity.Magnitude>3 then return false end
 local index;for i=1,4 do if not s.seated[i]and not s.landingSeats[i]then index=i;break end end;if not index then return false end
 return seatRider(s,p,index,c,h,root)
end
local function eligibleDock(s)
 if s.root.AssemblyLinearVelocity.Magnitude>3 or math.abs(s.throttle)>.08 then return nil end
 local dock=s.moored
 if dock and flatDistance(s.root.Position,dock.moor.Position)<=dock.radius then return dock end
 return nil
end
disembark=function(s,p)
 if not s.riders[p]or not living(p)then return false end
 local dock=eligibleDock(s);if not dock then return false end
 return releaseRider(s,p,dock.spawn,true)
end
local function restoreCargo(s,m)
 local entry=s.cargo[m];if not entry then return false end
 s.cargo[m]=nil;if entry.weld.Parent then entry.weld:Destroy()end
 for part,old in pairs(entry.parts)do if part.Parent then part.Massless=old.massless;part.CanCollide=old.collide end end
 if m.Parent then m:SetAttribute('CargoStored',nil);m:SetAttribute('CargoCart',nil)end
 return true
end
local function snapshot(s)
 local items={};local value=0
 for m in pairs(s.cargo)do if m.Parent and m.PrimaryPart and not m:GetAttribute('HeldBy')and not m:GetAttribute('ItemWearOwner')and not m:GetAttribute('AttachedTo')and not m:GetAttribute('MonsterCarried')and not m:GetAttribute('Gear')then
  table.insert(items,m);value+=m:GetAttribute('LootValue')or m:GetAttribute('Value')or 0
 end end
 return items,value
end
local function cargoFrame(s)return s.cargoCenter.WorldCFrame,s.cargoSize*s.boat:GetScale()end
local function updateCargo(s)
 for m in pairs(s.cargo)do if not m.Parent then restoreCargo(s,m)end end
 local cf,size=cargoFrame(s)
 for _,m in ipairs(s.map.Interactive:GetChildren())do
  if m:IsA('Model')and m.PrimaryPart and m:GetAttribute('ItemId')and not m:GetAttribute('Gear')and not m:GetAttribute('HeldBy')and not m:GetAttribute('ItemWearOwner')and not m:GetAttribute('FaceOwner')and not m:GetAttribute('AttachedTo')and not m:GetAttribute('MonsterCarried')and not m:GetAttribute('Selling')and not m:GetAttribute('CargoStored')and not s.cargo[m]then
   local point=cf:PointToObjectSpace(m.PrimaryPart.Position)
   if math.abs(point.X)<size.X/2+.25 and point.Y>-size.Y/2-.3 and point.Y<size.Y/2+1.2 and math.abs(point.Z)<size.Z/2+.25 then
    local extent=m.PrimaryPart.Size;local halfX=math.max(0,size.X/2-extent.X/2-.08);local halfZ=math.max(0,size.Z/2-extent.Z/2-.08)
    local base=-size.Y/2+.04
    for item in pairs(s.cargo)do if item.Parent and item.PrimaryPart then local q=cf:PointToObjectSpace(item.PrimaryPart.Position);base=math.max(base,q.Y+item.PrimaryPart.Size.Y/2+.06)end end
    local x,z=math.clamp(point.X,-halfX,halfX),math.clamp(point.Z,-halfZ,halfZ)
    m:PivotTo(cf*CFrame.new(x,base+extent.Y/2,z))
    local entry={parts={}}
    for _,part in ipairs(m:GetDescendants())do if part:IsA('BasePart')then entry.parts[part]={massless=part.Massless,collide=part.CanCollide};part.Anchored=false;part.CanCollide=false;part.Massless=true end end
    m.PrimaryPart.AssemblyLinearVelocity=s.root.AssemblyLinearVelocity;m.PrimaryPart.AssemblyAngularVelocity=Vector3.zero
    local weld=Instance.new('WeldConstraint');weld.Name='CargoRetention';weld.Part0=s.root;weld.Part1=m.PrimaryPart;weld.Parent=m.PrimaryPart;entry.weld=weld;s.cargo[m]=entry
    m:SetAttribute('CargoStored',true);m:SetAttribute('CargoCart',s.boat.Name)
   end
  end
 end
 local items,value=snapshot(s);s.boat:SetAttribute('CartValue',value);s.boat:SetAttribute('CargoCount',#items)
end
local function saleReady(s)
 local dock=eligibleDock(s)
 return dock and dock.home and s.boat:GetAttribute('MooredHome')==true and flatDistance(s.root.Position,dock.moor.Position)<1.5 and s.root.AssemblyLinearVelocity.Magnitude<3 or false
end
api.OnInvoke=function(action,p,m)
 local s=current;if not s then if action=='snapshot'then return {},0 end;return false end
 if action=='snapshot'then if p~=s.boat then return {},0 end;return snapshot(s)end
 if action=='saleReady'then return p==s.boat and saleReady(s)end
 if action=='takeCargo'then
  local _,_,root=living(p)
  if not root or not p:GetAttribute('PhysicalGrabActive')or not s.cargo[m]or m:GetAttribute('Selling')or not m.PrimaryPart or(root.Position-m.PrimaryPart.Position).Magnitude>10 then return false end
  return restoreCargo(s,m)
 end
 return false
end
cleanup=function(s)
 if current~=s then return end;current=nil
 local riders={};for p in pairs(s.riders)do table.insert(riders,p)end
 for _,p in ipairs(riders)do local dock=nearest(s,s.root.Position);releaseRider(s,p,living(p)and dock and dock.spawn or nil,false)end
 local items={};for m in pairs(s.cargo)do table.insert(items,m)end;for _,m in ipairs(items)do restoreCargo(s,m)end
 for _,connection in ipairs(s.connections)do connection:Disconnect()end
 for _,object in ipairs(s.prompts)do if object.Parent then object:Destroy()end end
 if s.boat.Parent then s.boat:Destroy()end
end
local function initialize(map,world,kit,water)
 serial+=1
 assert(kit.PrimaryPart and kit.PrimaryPart.Name=='Root','CruiseLaunch Root')
 local boat=kit:Clone();boat.Name='CruiseLaunch';boat:SetAttribute('Kind','boat');boat:SetAttribute('CruiseBoat',true);boat:SetAttribute('BoatEpoch',serial)
 local s={map=map,world=world,boat=boat,root=assert(boat.PrimaryPart,'CruiseLaunch Root'),water=water,epoch=serial,docks={},riders={},seated={},landingSeats={},seats={},cargo={},connections={},prompts={},throttle=0,steer=0,lastControl=0,departUntil=0,cargoClock=0,rescueClock=0}
 constructing=s
 s.length=tonumber(boat:GetAttribute('Length'))or 16;s.width=tonumber(boat:GetAttribute('Width'))or 7
 s.radius=math.sqrt(s.length^2+s.width^2)/2;s.maxSpeed=math.clamp(tonumber(boat:GetAttribute('MaxSpeed'))or 28,1,28)
 s.floatOffset=tonumber(boat:GetAttribute('FloatOffset'))or .75
 s.bounds={seaMin=world:GetAttribute('SeaMin'),seaMax=world:GetAttribute('SeaMax'),hullMin=world:GetAttribute('HullMin'),hullMax=world:GetAttribute('HullMax'),pierMin=world:GetAttribute('PierMin'),pierMax=world:GetAttribute('PierMax')}
 for _,name in ipairs({'seaMin','seaMax','hullMin','hullMax','pierMin','pierMax'})do assert(typeof(s.bounds[name])=='Vector3','CruiseWorld '..name)end
 for _,part in ipairs(boat:GetDescendants())do if part:IsA('BasePart')then part.Anchored=false;part.CanTouch=false;part.CanCollide=part==s.root;part.Massless=part~=s.root end end
 s.root.CustomPhysicalProperties=PhysicalProperties.new(.8,.25,0,1,1)
 local body=Instance.new('Attachment');body.Name='CruiseMotion';body.Parent=s.root
 local position=Instance.new('AlignPosition');position.Name='CruiseFloatPosition';position.Mode=Enum.PositionAlignmentMode.OneAttachment;position.Attachment0=body;position.ApplyAtCenterOfMass=true;position.Responsiveness=25;position.MaxForce=1000000;position.MaxVelocity=s.maxSpeed+12;position.Parent=s.root;s.position=position
 local orientation=Instance.new('AlignOrientation');orientation.Name='CruiseFloatOrientation';orientation.Mode=Enum.OrientationAlignmentMode.OneAttachment;orientation.Attachment0=body;orientation.Responsiveness=10;orientation.MaxTorque=1000000;orientation.MaxAngularVelocity=2;orientation.Parent=s.root;s.orientation=orientation
 for i=1,4 do local attachment=assert(s.root:FindFirstChild('Seat'..i),'CruiseLaunch Seat'..i)
  local seat=Instance.new('Part');seat.Name='BoatSeat'..i;seat.Size=Vector3.new(1.5,.2,1.5);seat.Transparency=1;seat.CanCollide=false;seat.CanQuery=false;seat.CanTouch=false;seat.Massless=true;seat.CFrame=s.root.CFrame*attachment.CFrame;seat.Parent=boat
  local weld=Instance.new('WeldConstraint');weld.Part0=s.root;weld.Part1=seat;weld.Parent=seat;s.seats[i]=seat
 end
 s.cargoCenter=assert(s.root:FindFirstChild('CargoCenter'),'CruiseLaunch CargoCenter')
 s.cargoSize=boat:GetAttribute('CargoSize');assert(typeof(s.cargoSize)=='Vector3','CruiseLaunch CargoSize')
 local home
 for _,part in ipairs(assert(world:FindFirstChild('Docks'),'CruiseWorld Docks'):GetChildren())do if part:IsA('BasePart')then
  local dock={id=part.Name,label=part:GetAttribute('Label')or part.Name,moor=part:GetAttribute('BoatMoor'),spawn=part:GetAttribute('DeckSpawn'),board=part:GetAttribute('BoardSpot'),radius=part:GetAttribute('Home')==true and 8 or 10,home=part:GetAttribute('Home')==true}
  assert(typeof(dock.moor)=='CFrame'and typeof(dock.spawn)=='CFrame'and typeof(dock.board)=='CFrame','Cruise dock CFrames '..part.Name)
  assert(Core.Safe(dock.moor.Position.X,dock.moor.Position.Z,s.bounds,s.radius),'BoatMoor outside navigable water '..part.Name)
  s.docks[dock.id]=dock;if dock.home then home=dock end
  local board=Instance.new('Part');board.Name='BoatBoard_'..dock.id;board.Size=Vector3.one;board.Anchored=true;board.Transparency=1;board.CanCollide=false;board.CanQuery=false;board.CanTouch=false;board.CFrame=dock.board;board.Parent=world;table.insert(s.prompts,board)
  local prompt=Instance.new('ProximityPrompt');prompt.Name='CruiseEmbark';prompt.ActionText='Board launch';prompt.ObjectText=dock.label;prompt.KeyboardKeyCode=Enum.KeyCode.E;prompt.GamepadKeyCode=Enum.KeyCode.ButtonX;prompt.MaxActivationDistance=9;prompt.RequiresLineOfSight=false;prompt.HoldDuration=.2;prompt.Parent=board;dock.prompt=prompt
  table.insert(s.connections,prompt.Triggered:Connect(function(p)if current==s then embark(s,p,dock.id)end end))
 end end
 assert(home,'Cruise Home dock missing')
 boat.Parent=map.Interactive;current=s;Collection:AddTag(boat,'CruiseBoat');placeAtDock(s,home);announceDriver(s)
 local exit=Instance.new('ProximityPrompt');exit.Name='CruiseDisembark';exit.ActionText='Disembark';exit.ObjectText='Dock';exit.KeyboardKeyCode=Enum.KeyCode.E;exit.GamepadKeyCode=Enum.KeyCode.ButtonX;exit.MaxActivationDistance=12;exit.RequiresLineOfSight=false;exit.Enabled=false;exit.Parent=s.root;s.exitPrompt=exit
 table.insert(s.connections,exit.Triggered:Connect(function(p)if current==s then disembark(s,p)end end))
 constructing=nil;return s
end
local function allow(p,action)
 local now=os.clock();local key=p.UserId..':'..action;local b=buckets[key]or{tokens=8,last=now};buckets[key]=b
 local rate=action=='control'and 30 or 3;b.tokens=math.min(action=='control'and 40 or 8,b.tokens+(now-b.last)*rate);b.last=now
 if b.tokens<1 then return false end;b.tokens-=1;return true
end
remote.OnServerEvent:Connect(function(p,action,epoch,a,b)
 if action=='landingAck'then if allow(p,action)then acknowledgeLanding(p,epoch,a)end;return end
 local s=current
 if not s or(action~='control'and action~='embark'and action~='disembark')or epoch~=s.epoch or not living(p)or not allow(p,action)then return end
 if action=='control'then
  if s.driver~=p then return end;local throttle,steer=Core.Input(a,b);if not throttle then return end
  s.lastControl=os.clock()
  if s.docking then return end -- Parking owns physics until the launch is settled.
  s.throttle=throttle;s.steer=steer
  if s.simOwner~=p then setOwner(s,p)end
  if s.moored and math.abs(throttle)>=.08 then s.questTrip={id=QuestHttp:GenerateGUID(false),from=s.moored.id,position=s.root.Position,driver=s.driver};s.departUntil=os.clock()+1.25;s.moored=nil;s.boat:SetAttribute('MooredDock',nil);s.boat:SetAttribute('MooredHome',false)end
 elseif action=='embark'then if type(a)=='string'and #a<=40 then embark(s,p,a)end
 elseif action=='disembark'then disembark(s,p)end
end)
Players.PlayerRemoving:Connect(function(p)
 if current then releaseRider(current,p,nil,true)end
 if landings[p]then finishLanding(p,landings[p])end
 for key in pairs(buckets)do if key:sub(1,#tostring(p.UserId)+1)==p.UserId..':'then buckets[key]=nil end end
end)
if Run:IsStudio()then
 local test=Instance.new('BindableFunction');test.Name='CruiseBoatTest';test.Parent=script
 test.OnInvoke=function(action,p,id)
  local s=current;if not s then return false,'Cruise boat unavailable'end
  if action=='inspect'then return {boat=s.boat,driver=s.driver,epoch=s.epoch,moored=s.moored and s.moored.id,departureProtectedFor=math.max(0,s.departUntil-os.clock()),docking=s.docking and s.docking.dock.id,cargoCount=s.boat:GetAttribute('CargoCount'),cargoValue=s.boat:GetAttribute('CartValue'),bounds=s.bounds,radius=s.radius}end
  if action=='landing'then local t=landings[p];return t and {id=t.id,attempt=t.attempt,acknowledged=t.acknowledged,gap=(t.root.Position-t.target.Position).Magnitude,index=t.index}or false end
  if action=='embark'then return embark(s,p,id)end
  if action=='disembark'then return disembark(s,p)end
  if action=='moor'then local dock=s.docks[id];return dock and placeAtDock(s,dock)or false end
  return false,'Unknown test action'
 end
end
local tick=0
Run.Heartbeat:Connect(function(dt)
 tick+=dt
 local map=workspace:FindFirstChild('Mansion');local world=map and map:FindFirstChild('CruiseWorld')
 local wanted=workspace:GetAttribute('MissionRunning')==true and map and map:GetAttribute('MapKind')=='Cruise'and map:GetAttribute('RuntimeReady')==true and world
 if current and(not wanted or current.world~=world or not current.boat.Parent)then cleanup(current)end
 if wanted and not current and not initializing and tick>=1 then
  tick=0;local kit=SS:FindFirstChild('CruiseKit');kit=kit and kit:FindFirstChild('CruiseLaunch');local water=RS:FindFirstChild('CruiseWater')
  if kit and water then
   initializing=true
   local ok,why=pcall(function()return initialize(map,world,kit,require(water))end)
   initializing=false
   if not ok then
    if current then cleanup(current)end
    if constructing then
     for _,connection in ipairs(constructing.connections)do connection:Disconnect()end
     for _,object in ipairs(constructing.prompts)do object:Destroy()end
     constructing.boat:Destroy();constructing=nil
    end
    if not missingKit then missingKit=true;warn('[CruiseBoat] '..tostring(why))end
   end
  end
 end
 local s=current;if not s then return end
 for p,rider in pairs(s.riders)do
  if not living(p)or p.Character~=rider.character or not rider.weld.Parent then releaseRider(s,p,nil,true)
  else rider.humanoid.Jump=false;rider.humanoid.Sit=true;rider.humanoid.WalkSpeed=0;rider.humanoid.JumpPower=0;rider.humanoid.JumpHeight=0;rider.humanoid.AutoRotate=false end
 end
 local now=os.clock();local pos=s.root.Position;local velocity=s.root.AssemblyLinearVelocity
 if not Core.Finite(velocity.X)or not Core.Finite(velocity.Y)or not Core.Finite(velocity.Z)then velocity=Vector3.zero;s.root.AssemblyLinearVelocity=velocity;s.root.AssemblyAngularVelocity=Vector3.zero end
 local valid=Core.Finite(pos.X)and Core.Finite(pos.Y)and Core.Finite(pos.Z)
 local x,z=s.lastValid.Position.X,s.lastValid.Position.Z
 if valid then
  local elapsed=math.clamp(now-s.lastTime,0,.5)
  local tooFast=flatDistance(pos,s.lastValid.Position)>s.maxSpeed*elapsed+3.5
  local cx,cz=Core.Clamp(x,z,pos.X,pos.Z,s.bounds,s.radius)
  local wrongHeight=math.abs(pos.Y-(s.water.Height(pos.X,pos.Z)+s.floatOffset))>5
  if tooFast or wrongHeight then
   local cf=float(s,cx,cz,yaw(s.lastValid));s.boat:PivotTo(cf);s.root.AssemblyLinearVelocity=Vector3.zero;s.root.AssemblyAngularVelocity=Vector3.zero;s.motion={x=cx,z=cz,yaw=yaw(cf),speed=0}
  elseif math.abs(cx-pos.X)>.05 or math.abs(cz-pos.Z)>.05 then
   -- Contact correction removes only inward motion; yaw and tangential motion
   -- remain available so the pilot can slide along the hull or steer away.
   local heading=yaw(s.root.CFrame);local cf=float(s,cx,cz,heading);s.boat:PivotTo(cf)
   local vx=math.abs(cx-pos.X)>.05 and 0 or velocity.X
   local vz=math.abs(cz-pos.Z)>.05 and 0 or velocity.Z
   s.root.AssemblyLinearVelocity=Vector3.new(vx,velocity.Y,vz)
   s.motion={x=cx,z=cz,yaw=heading,speed=Vector3.new(vx,0,vz).Magnitude}
  end
 else s.boat:PivotTo(s.lastValid);s.root.AssemblyLinearVelocity=Vector3.zero end
 s.lastValid=s.root.CFrame;s.lastTime=now
 local flat=Vector3.new(velocity.X,0,velocity.Z)
 if flat.Magnitude>s.maxSpeed+1 then s.root.AssemblyLinearVelocity=flat.Unit*s.maxSpeed+Vector3.new(0,math.clamp(velocity.Y,-8,8),0)end
 if now-s.lastControl>.6 then s.throttle=0;s.steer=0;if s.simOwner then setOwner(s,nil)end end
 if s.docking then
  updateDock(s,now)
 elseif s.moored then
  local cf=float(s,s.moored.moor.Position.X,s.moored.moor.Position.Z,yaw(s.moored.moor));s.position.Position=cf.Position;s.orientation.CFrame=cf.Rotation
 elseif not s.driver or not s.simOwner then
  s.motion={x=s.root.Position.X,z=s.root.Position.Z,yaw=yaw(s.root.CFrame),speed=flat.Magnitude}
  s.motion=Core.Step(s.motion,0,0,dt,s.bounds,s.radius,s.maxSpeed)
  local cf=float(s,s.motion.x,s.motion.z,s.motion.yaw);s.position.Position=cf.Position;s.orientation.CFrame=cf.Rotation
 end
 if not s.moored and not s.docking then local dock=nearest(s,s.root.Position)
  if dock then beginDock(s,dock,now)end
 end
 local eligible=eligibleDock(s);s.exitPrompt.Enabled=eligible~=nil;s.exitPrompt.ObjectText=eligible and eligible.label or 'Dock'
 for _,dock in pairs(s.docks)do dock.prompt.Enabled=s.moored==dock end
 s.cargoClock+=dt;s.rescueClock+=dt
 if s.cargoClock>=.15 then
  s.cargoClock=0;updateCargo(s)
  if saleReady(s)and(s.boat:GetAttribute('CartValue')or 0)>0 then local recovery=SS:FindFirstChild('RecoveryApi');if recovery then recovery:Invoke('sellBoat',nil,s.boat)end end
 end
 if s.rescueClock>=.1 then
  s.rescueClock=0
  for _,p in ipairs(Players:GetPlayers())do local c,_,root=living(p)
   if c and not s.riders[p]and root.Position.Y<s.water.Height(root.Position.X,root.Position.Z)+1 then
    local dock=nearest(s,root.Position);if dock then Audio.Play('PerfumeSpray',root.Position);remote:FireAllClients('splash',root.Position);c:PivotTo(dock.spawn);root.AssemblyLinearVelocity=Vector3.zero;root.AssemblyAngularVelocity=Vector3.zero end
   end
  end
 end
end)
script.Destroying:Connect(function()if current then cleanup(current)end;for p,ticket in pairs(landings)do finishLanding(p,ticket)end;if api.Parent then api:Destroy()end;if remote.Parent then remote:Destroy()end end)
