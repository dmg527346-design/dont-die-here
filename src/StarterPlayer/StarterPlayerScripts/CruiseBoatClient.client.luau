-- Cruise launch controls, chase camera, route and dock HUD; no sale authority here.
-- Live servers (owner 2026-10-27): Cruise is out of the map pool, so the boat HUD and camera stays off there (MapGen publishes the pool
-- as the ReplicatedStorage attribute MapPool). Studio keeps it for forced-map tests; no pool after 15 s = run as before.
do local RS_=game:GetService('ReplicatedStorage');local pool,t0=RS_:GetAttribute('MapPool'),os.clock();if not game:GetService('RunService'):IsStudio()then while pool==nil and os.clock()-t0<15 do task.wait(.5);pool=RS_:GetAttribute('MapPool')end;if pool and not table.find(string.split(pool,','),'Cruise')then return end end end
local Players=game:GetService('Players')
local RS=game:GetService('ReplicatedStorage')
local Run=game:GetService('RunService')
local UIS=game:GetService('UserInputService')
local InputHints=require(game:GetService('ReplicatedStorage'):WaitForChild('InputHints'))
local CAS=game:GetService('ContextActionService')
local Debris=game:GetService('Debris')
local player=Players.LocalPlayer
local Core=require(RS:WaitForChild('CruiseBoatCore'))
local remote=RS:WaitForChild('CruiseBoatEvent',math.huge)
local keys={};local stick=Vector2.zero;local riding;local driving=false;local motion;local cameraBefore;local controls
local sendClock,scanClock,guideClock=0,0,0
local boat,world,water,bounds,radius,maxSpeed
local routeFolder;local guidePoints={};local lastGuideTarget
local gui=Instance.new('ScreenGui');gui.Name='CruiseBoatHud';gui.ResetOnSpawn=false;gui.DisplayOrder=45;gui.Enabled=false;gui.Parent=player:WaitForChild('PlayerGui')
local function label(name,size,position,text)
 local t=Instance.new('TextLabel');t.Name=name;t.Size=size;t.Position=position;t.BackgroundTransparency=1;t.Font=Enum.Font.FredokaOne;t.TextColor3=Color3.fromRGB(244,236,210);t.TextStrokeTransparency=.35;t.TextScaled=true;t.Text=text;t.Parent=gui
 local limit=Instance.new('UITextSizeConstraint');limit.MinTextSize=11;limit.MaxTextSize=20;limit.Parent=t;return t
end
local arrow=label('RouteArrow',UDim2.fromOffset(34,34),UDim2.new(.5,-17,0,76),'^')
local routeText=label('Destination',UDim2.new(.72,0,0,30),UDim2.new(.14,0,0,112),'')
local tip=label('Controls',UDim2.new(.8,0,0,34),UDim2.new(.1,0,1,-46),'')
local function button(name,text,pos,size)
 local b=Instance.new('TextButton');b.Name=name;b.Text=text;b.Size=size;b.Position=pos;b.BackgroundColor3=Color3.fromRGB(22,42,43);b.BackgroundTransparency=.12;b.TextColor3=Color3.fromRGB(244,236,210);b.TextScaled=true;b.Font=Enum.Font.FredokaOne;b.Selectable=true;b.Parent=gui
 local corner=Instance.new('UICorner');corner.CornerRadius=UDim.new(0,12);corner.Parent=b
 local limit=Instance.new('UITextSizeConstraint');limit.MinTextSize=10;limit.MaxTextSize=17;limit.Parent=b;return b
end
local exit=button('Disembark','EXIT AT DOCK',UDim2.new(1,-160,0,154),UDim2.fromOffset(142,44))
local touchButtons={}
for _,spec in ipairs({{'W','FWD',82,-212},{'S','REV',82,-148},{'A','LEFT',18,-148},{'D','RIGHT',146,-148}})do
 local b=button('Drive'..spec[1],spec[2],UDim2.new(0,spec[3],1,spec[4]),UDim2.fromOffset(56,56));touchButtons[spec[1]]=b
 b.InputBegan:Connect(function(input)if input.UserInputType==Enum.UserInputType.Touch or input.UserInputType==Enum.UserInputType.MouseButton1 then keys[spec[1]]=true end end)
 b.InputEnded:Connect(function(input)if input.UserInputType==Enum.UserInputType.Touch or input.UserInputType==Enum.UserInputType.MouseButton1 then keys[spec[1]]=nil end end)
end
local boardButton=button('BoardLaunch','BOARD LAUNCH',UDim2.new(.5,-88,1,-104),UDim2.fromOffset(176,46))
boardButton.Visible=false
local function nearbyBoard()
 if riding or player:GetAttribute('CruiseBoatLandingId')or player:GetAttribute('MissionActive')~=true or player:GetAttribute('RoundDead')then return end
 local map=workspace:FindFirstChild('Mansion')
 if not map or map:GetAttribute('MapKind')~='Cruise' or map:GetAttribute('RuntimeReady')~=true then return end
 local folder=map:FindFirstChild('Interactive');local model=folder and folder:FindFirstChild('CruiseLaunch')
 local cruiseWorld=map:FindFirstChild('CruiseWorld');local docks=cruiseWorld and cruiseWorld:FindFirstChild('Docks')
 local dockId=model and model:GetAttribute('MooredDock');local dock=dockId and docks and docks:FindFirstChild(dockId)
 local character=player.Character;local root=character and character:FindFirstChild('HumanoidRootPart')
 local cf=dock and dock:GetAttribute('BoardSpot')
 if not root or not model or not model.PrimaryPart or typeof(cf)~='CFrame'or (root.Position-cf.Position).Magnitude>9 or model.PrimaryPart.AssemblyLinearVelocity.Magnitude>3 then return end
 return model,dock
end
local function requestBoard()
 local model,dock=nearbyBoard()
 if model then remote:FireServer('embark',model:GetAttribute('BoatEpoch'),dock.Name)end
end
boardButton.Activated:Connect(requestBoard)
CAS:BindActionAtPriority('CruiseBoard',function(_,state)
 local model=nearbyBoard()
 if not model then return Enum.ContextActionResult.Pass end
 if state==Enum.UserInputState.Begin then requestBoard()end
 return Enum.ContextActionResult.Sink
end,false,Enum.ContextActionPriority.High.Value+75,Enum.KeyCode.E,Enum.KeyCode.ButtonX)
local function requestExit()if riding and boat then remote:FireServer('disembark',riding)end end
exit.Activated:Connect(requestExit)
local function input(_,state,object)
 if not riding then return Enum.ContextActionResult.Pass end
 if object.KeyCode==Enum.KeyCode.E or object.KeyCode==Enum.KeyCode.ButtonX then
  if state==Enum.UserInputState.Begin then requestExit()end
 elseif driving then
  if object.KeyCode==Enum.KeyCode.Thumbstick1 then stick=state==Enum.UserInputState.End and Vector2.zero or Vector2.new(object.Position.X,object.Position.Y)
  else local key=object.KeyCode.Name;keys[key]=state==Enum.UserInputState.Begin or state==Enum.UserInputState.Change or nil end
 end
 return Enum.ContextActionResult.Sink
end
local function clearGuide()
 if routeFolder then routeFolder:Destroy();routeFolder=nil end;table.clear(guidePoints)
end
local hiddenViewParts={}
local function viewmodelVisibility(hidden)
 if not hidden then
  for part,old in pairs(hiddenViewParts)do if part.Parent then part.LocalTransparencyModifier=old end end
  table.clear(hiddenViewParts);return
 end
 local camera=workspace.CurrentCamera;local folder=camera and camera:FindFirstChild('FakeHands')
 if not folder then return end
 for _,part in ipairs(folder:GetDescendants())do if part:IsA('BasePart')then
  if hiddenViewParts[part]==nil then hiddenViewParts[part]=part.LocalTransparencyModifier end
  part.LocalTransparencyModifier=1
 end end
end
local function stop()
 viewmodelVisibility(false)
 CAS:UnbindAction('CruiseDrive');CAS:UnbindAction('CruiseExit');table.clear(keys);stick=Vector2.zero
 if controls then pcall(function()controls:Enable()end);controls=nil end
 local camera=workspace.CurrentCamera
 if cameraBefore and camera then camera.CameraType=cameraBefore.type;camera.FieldOfView=cameraBefore.fov;if cameraBefore.subject and cameraBefore.subject.Parent then camera.CameraSubject=cameraBefore.subject end end
 cameraBefore=nil;riding=nil;driving=false;motion=nil;boat=nil;gui.Enabled=false;clearGuide()
end
local function start(epoch,model,cruiseWorld)
 stop();riding=epoch;boat=model;world=cruiseWorld;water=require(RS:WaitForChild('CruiseWater'))
 bounds={seaMin=world:GetAttribute('SeaMin'),seaMax=world:GetAttribute('SeaMax'),hullMin=world:GetAttribute('HullMin'),hullMax=world:GetAttribute('HullMax'),pierMin=world:GetAttribute('PierMin'),pierMax=world:GetAttribute('PierMax')}
 local len,wid=boat:GetAttribute('Length')or 16,boat:GetAttribute('Width')or 7;radius=math.sqrt(len^2+wid^2)/2;maxSpeed=math.clamp(boat:GetAttribute('MaxSpeed')or 28,1,28)
 local camera=workspace.CurrentCamera;if camera then cameraBefore={type=camera.CameraType,subject=camera.CameraSubject,fov=camera.FieldOfView};camera.CameraType=Enum.CameraType.Scriptable end
 -- Custom character projects may omit Roblox's default PlayerModule.
 pcall(function()local module=player.PlayerScripts:FindFirstChild('PlayerModule');if module then controls=require(module):GetControls();controls:Disable()end end)
 CAS:BindActionAtPriority('CruiseExit',input,false,Enum.ContextActionPriority.High.Value+100,Enum.KeyCode.E,Enum.KeyCode.ButtonX)
 CAS:BindActionAtPriority('CruiseDrive',input,false,Enum.ContextActionPriority.High.Value+100,Enum.KeyCode.W,Enum.KeyCode.A,Enum.KeyCode.S,Enum.KeyCode.D,Enum.KeyCode.Thumbstick1)
 gui.Enabled=true
end
local function heading(cf)return math.atan2(-cf.LookVector.X,-cf.LookVector.Z)end
local function driveVelocity(position,yaw,speed,dt,bounds,radius)
 local look=Vector3.new(-math.sin(yaw),0,-math.cos(yaw))
 local wanted=look*speed;local span=math.clamp(dt,1/240,1/15)
 -- Feed the travel velocity forward; the aligner only corrects residual error.
 -- Project blocked components so the same feed-forward slides along keepouts.
 local x,z=Core.Slide(position.X,position.Z,position.X+wanted.X*span,position.Z+wanted.Z*span,bounds,radius)
 local function component(value,delta)
  if value*delta<=0 then return 0 end
  return math.sign(value)*math.min(math.abs(value),math.abs(delta)/span)
 end
 return Vector3.new(component(wanted.X,x-position.X),0,component(wanted.Z,z-position.Z))
end
local function syncMotion(motion,root,dt,bounds,radius)
 if not motion then return{x=root.Position.X,z=root.Position.Z,yaw=heading(root.CFrame),speed=0}end
 if(Vector3.new(motion.x,0,motion.z)-Vector3.new(root.Position.X,0,root.Position.Z)).Magnitude<=18 then return motion end
 local yaw=heading(root.CFrame)
 local allowed=driveVelocity(root.Position,yaw,motion.speed,dt,bounds,radius)
 return{x=root.Position.X,z=root.Position.Z,yaw=yaw,speed=math.sign(motion.speed)*math.min(math.abs(motion.speed),allowed.Magnitude)}
end
local function dockData()
 local docks={};local home
 for _,part in ipairs(world.Docks:GetChildren())do local cf=part:GetAttribute('BoatMoor')
  if part:IsA('BasePart')and typeof(cf)=='CFrame'then local dock={id=part.Name,label=part:GetAttribute('Label')or part.Name,point=cf.Position};table.insert(docks,dock);if part:GetAttribute('Home')then home=dock end end
 end
 return docks,home
end
local function routeData(docks)
 local grouped={};local guide=world:FindFirstChild('Guide')
 if guide then for _,part in ipairs(guide:GetChildren())do if part:IsA('BasePart')then local id,index=part.Name:match('^R_(.-)_(%d+)$');if id then grouped[id]=grouped[id]or{};table.insert(grouped[id],{index=tonumber(index),point=part.Position})end end end end
 local routes={}
 for _,dock in ipairs(docks)do if dock.id~='Home'then local points={};local list=grouped[dock.id]or{};table.sort(list,function(a,b)return a.index<b.index end);for _,row in ipairs(list)do table.insert(points,row.point)end;table.insert(points,dock.point);table.insert(routes,{id=dock.id,points=points})end end
 return routes
end
local function updateGuide()
 if not boat or not boat.PrimaryPart or not world or not world.Parent then return end
 local docks,home=dockData();if not home then return end
 local target=if(boat:GetAttribute('CargoCount')or 0)>0 then home else Core.NearestDock(boat.PrimaryPart.Position,docks)
 if not target then return end
 local points,length=Core.Route(boat.PrimaryPart.Position,target,home,routeData(docks),bounds,radius)
 lastGuideTarget=points[1]or target.point
 routeText.Text=target.label..' | '..math.floor(length or(boat.PrimaryPart.Position-target.point).Magnitude)..' studs'..' | Cargo $'..(boat:GetAttribute('CartValue')or 0)
 clearGuide();routeFolder=Instance.new('Folder');routeFolder.Name='CruiseBoatRoute';routeFolder.Parent=workspace
 local previous
 for _,point in ipairs({boat.PrimaryPart.Position,unpack(points)})do
  local p=Instance.new('Part');p.Size=Vector3.new(.1,.1,.1);p.Transparency=1;p.Anchored=true;p.CanCollide=false;p.CanTouch=false;p.CanQuery=false;p.Position=Vector3.new(point.X,water.Height(point.X,point.Z)+.25,point.Z);p.Parent=routeFolder
  local attachment=Instance.new('Attachment');attachment.Parent=p;table.insert(guidePoints,p)
  if previous then local beam=Instance.new('Beam');beam.Attachment0=previous;beam.Attachment1=attachment;beam.Width0=.35;beam.Width1=.35;beam.FaceCamera=true;beam.Color=ColorSequence.new(Color3.fromRGB(108,228,203));beam.Transparency=NumberSequence.new(.3);beam.LightEmission=.6;beam.Parent=p end
  previous=attachment
 end
end
UIS.WindowFocusReleased:Connect(function()table.clear(keys);stick=Vector2.zero end)
local lastLandingCommand
local function applyLanding(id,attempt,character,target,boatToken)
 if not Core.Finite(id)or id<1 or id%1~=0 or(attempt~=1 and attempt~=2)or character~=player.Character or typeof(target)~='CFrame'then return end
 if not Core.Finite(target.Position.X)or not Core.Finite(target.Position.Y)or not Core.Finite(target.Position.Z)then return end
 local map=workspace:FindFirstChild('Mansion');local folder=map and map:FindFirstChild('Interactive')
 if not boatToken or not folder or folder:FindFirstChild('CruiseLaunch')~=boatToken then return end
 if lastLandingCommand and lastLandingCommand.boat==boatToken and lastLandingCommand.character==character and(id<lastLandingCommand.id or id==lastLandingCommand.id and attempt<lastLandingCommand.attempt)then return end
 local command={id=id,attempt=attempt,boat=boatToken,character=character};lastLandingCommand=command
 task.spawn(function()
  local root=character:FindFirstChild('HumanoidRootPart');local h=character:FindFirstChildOfClass('Humanoid');if not root or not h then return end
  local deadline=os.clock()+.6
  while player:GetAttribute('CruiseBoatLandingId')~=id or root.Anchored do
   if lastLandingCommand~=command or player.Character~=character or not root.Parent or player:GetAttribute('CruiseBoatEpoch')or os.clock()>=deadline then return end
   task.wait(.03)
  end
  if lastLandingCommand~=command or player.Character~=character or not root.Parent or h.Health<=0 or player:GetAttribute('RoundDead')or player:GetAttribute('MissionActive')~=true or player:GetAttribute('CruiseBoatEpoch')then return end
  character:PivotTo(target);root.AssemblyLinearVelocity=Vector3.zero;root.AssemblyAngularVelocity=Vector3.zero
  task.wait()
  if lastLandingCommand==command and player.Character==character and player:GetAttribute('CruiseBoatLandingId')==id and not player:GetAttribute('CruiseBoatEpoch')then remote:FireServer('landingAck',id,attempt)end
 end)
end
remote.OnClientEvent:Connect(function(action,point,attempt,character,target,boatToken)
 if action=='land'then applyLanding(point,attempt,character,target,boatToken);return end
 if action~='splash'or typeof(point)~='Vector3' then return end
 local p=Instance.new('Part');p.Name='CruiseSplash';p.Transparency=1;p.Size=Vector3.one;p.Anchored=true;p.CanCollide=false;p.CanTouch=false;p.CanQuery=false;p.Position=point;p.Parent=workspace
 local emitter=Instance.new('ParticleEmitter');emitter.Texture='rbxasset://textures/particles/sparkles_main.dds';emitter.Color=ColorSequence.new(Color3.fromRGB(151,213,222));emitter.Lifetime=NumberRange.new(.35,.7);emitter.Speed=NumberRange.new(4,9);emitter.SpreadAngle=Vector2.new(65,65);emitter.Rate=0;emitter.Size=NumberSequence.new(.2);emitter.Acceleration=Vector3.new(0,-18,0);emitter.Parent=p;emitter:Emit(25);Debris:AddItem(p,1)
end)
Run.Heartbeat:Connect(function(dt)
 scanClock+=dt
 if scanClock>=.1 then
  scanClock=0;local epoch=player:GetAttribute('CruiseBoatEpoch');local map=workspace:FindFirstChild('Mansion');local folder=map and map:FindFirstChild('Interactive');local model=folder and folder:FindFirstChild('CruiseLaunch');local cruiseWorld=map and map:FindFirstChild('CruiseWorld')
  if epoch and model and model:GetAttribute('BoatEpoch')==epoch and cruiseWorld then
   if riding~=epoch or boat~=model then start(epoch,model,cruiseWorld)end
  elseif riding then stop()end
 end
 local boarding,boardDock=nearbyBoard()
 boardButton.Visible=boarding~=nil
 if boarding then boardButton.Text=(InputHints.Get()=='pad'and 'X: 'or InputHints.Get()=='touch'and ''or 'E: ')..'BOARD LAUNCH'end
 arrow.Visible=riding~=nil;routeText.Visible=riding~=nil;tip.Visible=riding~=nil
 gui.Enabled=riding~=nil or boarding~=nil
 if not riding or not boat or not boat.Parent or not boat.PrimaryPart then exit.Visible=false;for _,b in pairs(touchButtons)do b.Visible=false end;return end
 local root=boat.PrimaryPart;local driver=boat:GetAttribute('DriverUserId')==player.UserId and not boat:GetAttribute('DockingDock')
 if driver~=driving then driving=driver;motion={x=root.Position.X,z=root.Position.Z,yaw=heading(root.CFrame),speed=0}end
 local throttle=math.clamp((keys.W and 1 or 0)-(keys.S and 1 or 0)+(math.abs(stick.Y)>.12 and stick.Y or 0),-1,1)
 local steer=math.clamp((keys.D and 1 or 0)-(keys.A and 1 or 0)+(math.abs(stick.X)>.12 and stick.X or 0),-1,1)
 if driving then
  motion=syncMotion(motion,root,dt,bounds,radius)
  local dockId=boat:GetAttribute('MooredDock');local dock=dockId and world.Docks:FindFirstChild(dockId)
  if dock and math.abs(throttle)<.08 then local cf=dock:GetAttribute('BoatMoor');motion={x=cf.Position.X,z=cf.Position.Z,yaw=heading(cf),speed=0}
  else motion=Core.Step(motion,throttle,steer,dt,bounds,radius,maxSpeed)end
  local velocity=driveVelocity(root.Position,motion.yaw,motion.speed,dt,bounds,radius)
  root.AssemblyLinearVelocity=Vector3.new(velocity.X,root.AssemblyLinearVelocity.Y,velocity.Z)
  local goal=water.Float(motion.x,motion.z,motion.yaw,boat:GetAttribute('Length')or 16,boat:GetAttribute('Width')or 7,workspace:GetServerTimeNow())*CFrame.new(0,boat:GetAttribute('FloatOffset')or .75,0)
  local pos=root:FindFirstChild('CruiseFloatPosition');local ori=root:FindFirstChild('CruiseFloatOrientation');if pos and ori then pos.Position=goal.Position;ori.CFrame=goal.Rotation end
  sendClock+=dt;if sendClock>=.05 then sendClock=0;remote:FireServer('control',riding,throttle,steer)end
 end
 local touch=InputHints.Get()=='touch'
 for _,b in pairs(touchButtons)do b.Visible=touch and driving end
 local canExit=boat:GetAttribute('MooredDock')~=nil;exit.Visible=touch;exit.Active=canExit;exit.Text=canExit and 'DISEMBARK'or 'DOCK TO EXIT'
 tip.Text=if boat:GetAttribute('DockingDock')then 'Parking launch | Wait until it settles'elseif not driving then 'Passenger | '..(canExit and 'Use the dock prompt to disembark'or 'Stay seated until the launch docks')elseif touch then 'Hold arrows to drive | Exit at a dock'elseif InputHints.Get()=='pad'then 'Left stick: throttle / steer | X: disembark at dock'else 'W/S: throttle | A/D: steer | E: disembark at dock'
 guideClock+=dt;if guideClock>=.5 then guideClock=0;updateGuide()end
end)
Run:BindToRenderStep('CruiseBoatCamera',Enum.RenderPriority.Camera.Value+10,function(dt)
 if not riding or not boat or not boat.Parent or not boat.PrimaryPart then return end
 viewmodelVisibility(true)
 local camera=workspace.CurrentCamera;if not camera then return end;camera.CameraType=Enum.CameraType.Scriptable
 local root=boat.PrimaryPart;local look=root.CFrame.LookVector;look=Vector3.new(look.X,0,look.Z).Unit
 local desired=CFrame.lookAt(root.Position-look*23+Vector3.new(0,11,0),root.Position+look*5+Vector3.new(0,2,0))
 camera.CFrame=camera.CFrame:Lerp(desired,math.min(1,dt*6));camera.Focus=CFrame.new(root.Position)
 if lastGuideTarget then local direction=lastGuideTarget-root.Position;arrow.Rotation=math.deg(math.atan2(direction:Dot(camera.CFrame.RightVector),direction:Dot(camera.CFrame.LookVector)))end
 if guidePoints[1]and guidePoints[1].Parent then guidePoints[1].Position=Vector3.new(root.Position.X,water.Height(root.Position.X,root.Position.Z)+.25,root.Position.Z)end
end)
script.Destroying:Connect(function()CAS:UnbindAction('CruiseBoard');stop();Run:UnbindFromRenderStep('CruiseBoatCamera');gui:Destroy()end)
