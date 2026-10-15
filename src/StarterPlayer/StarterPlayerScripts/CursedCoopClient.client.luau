-- Client visuals only; ItemBatch4 owns leases, attachment identity and removal.
-- No screen UI: vision is blocked by the real meshes. Everyone else sees the server-welded
-- meshes on the character. The wearer plays in LockFirstPerson with the camera at the Head bar
-- (below the eye stalks), so a local copy of the same mesh is posed in front of their camera.
local Players=game:GetService('Players')
local Run=game:GetService('RunService')
local RS=game:GetService('ReplicatedStorage')
local Audio=require(RS:WaitForChild('GameplayAudio'))
local player=Players.LocalPlayer
-- Tuned by screenshot; keep values here.
local HAND_RISE=3 -- seconds for the hands to creep over the eyes
local HAND_CYCLE,HAND_CLOSED=4.7,3.9 -- fingers part for the last .8 s of each cycle
local HAND_PEEK_ANGLE=.7 -- finger spread (rad) before each finger's SpreadWeight
local HAND_PEEK_PART=.45 -- wearer's view: hands also slide this far apart while peeking
local HAND_RISE_UP,HAND_RISE_BACK=1.6,2.4 -- start offset above / behind the head (studs)
local HAND_VIEW_SQUEEZE=1.0 -- wearer's view only: each hand slides this far toward the nose
-- Point in each model's Root space that sits on the wearer's camera (Root axes = body axes, -Z front).
local VIEW_ANCHOR={
 GuessWhoHands=Vector3.new(0,-.258,-.445), -- eye midpoint
 CursedHair=Vector3.new(0,0,0), -- eye midpoint
 FacePlunger=Vector3.new(0,0,1.26), -- just behind the cup rim
}
-- Extra camera-space nudge per item (+Y up, -Z forward).
local VIEW_NUDGE={
 GuessWhoHands=Vector3.new(0,0,0),
 CursedHair=Vector3.new(0,.06,.04),
 FacePlunger=Vector3.new(0,-.36,-.6), -- cup rim ~.95 studs out and low: blocks the centre/lower view, edges stay visible
}
local apparition,apparitionSource,stingAt
local whispers={}
local views={} -- [source model]=view
local function stopWhisper()
 for m,sound in pairs(whispers)do pcall(function()sound:Stop();sound:Destroy()end);whispers[m]=nil end
end
local function destroyApparition()
 if apparition then apparition:Destroy()end;apparition=nil;apparitionSource=nil
end
local function dropView(src)
 local v=views[src];if not v then return end
 views[src]=nil;v.clone:Destroy()
 if src.Parent then for _,x in src:GetDescendants()do if x:IsA('BasePart')then x.LocalTransparencyModifier=0 end end end
end
local function clearViews()for src in pairs(views)do dropView(src)end end
local function makeView(src,id)
 local root=src.PrimaryPart;if not root then return end
 local arch=src.Archivable;src.Archivable=true
 local ok,clone=pcall(function()return src:Clone()end);src.Archivable=arch
 if not ok or not clone or not clone.PrimaryPart then return end
 local v={clone=clone,id=id,parts={},fingers={},src=src}
 local cr=clone.PrimaryPart
 local junk={}
 for _,x in clone:GetDescendants()do
  if x:IsA('Motor6D')and x.Name=='Knuckle'then
   local c0=x:GetAttribute('BaseC0');if typeof(c0)~='CFrame'then c0=x.C0 end
   table.insert(v.fingers,{finger=x.Part1,palm=x.Part0,c0=c0,c1=x.C1,w=x:GetAttribute('SpreadWeight')or 1})
  end
  if x:IsA('JointInstance')or x:IsA('WeldConstraint')or x:IsA('Constraint')or x:IsA('LuaSourceContainer')or x:IsA('Sound')or x:IsA('Attachment')then table.insert(junk,x)end
 end
 local isFinger={};for _,f in ipairs(v.fingers)do isFinger[f.finger]=true end
 local srcByName={};for _,x in src:GetDescendants()do if x:IsA('BasePart')then srcByName[x.Name]=x end end
 v.srcRoot=root
 for _,x in clone:GetDescendants()do if x:IsA('BasePart')then
  local n=x.Name
  local side=(n:sub(1,2)=='L_'or n:sub(1,4)=='Left')and 1 or((n:sub(1,2)=='R_'or n:sub(1,5)=='Right')and -1 or 0)
  if not isFinger[x]then table.insert(v.parts,{part=x,rel=cr.CFrame:ToObjectSpace(x.CFrame),side=side,src=srcByName[x.Name]})end
  x.Anchored=true;x.CanCollide=false;x.CanQuery=false;x.CanTouch=false;x.CastShadow=false;x.LocalTransparencyModifier=0
  if x.Name=='Root'or x.Name=='ItemGroundCollider'then x.Transparency=1 end
 end end
 for _,x in ipairs(junk)do x:Destroy()end
 clone.Name='CursedView_'..id;clone.Parent=workspace.CurrentCamera
 views[src]=v
 return v
end
local function poseView(v,cam,now)
 local cf=cam.CFrame*CFrame.new(VIEW_NUDGE[v.id])
 local angle=0
 if v.id=='GuessWhoHands'then
  local age=now-(player:GetAttribute('GuessWhoStart')or now)
  local away=1-math.clamp(age/HAND_RISE,0,1);away*=away
  cf*=CFrame.new(0,HAND_RISE_UP*away,HAND_RISE_BACK*away) -- camera +Z is behind the wearer
  local peek=age>=HAND_RISE and (age-HAND_RISE)%HAND_CYCLE>=HAND_CLOSED
  v.angle=(v.angle or 0)+((peek and HAND_PEEK_ANGLE or 0)-(v.angle or 0))*.18;angle=v.angle
 end
 local rootCF=cf*CFrame.new(-VIEW_ANCHOR[v.id])
 local squeeze=v.id=='GuessWhoHands'and HAND_VIEW_SQUEEZE-HAND_PEEK_PART*(angle/HAND_PEEK_ANGLE)or 0
 local placed={}
 for _,e in ipairs(v.parts)do
  -- Items copy the live (physics) pose of the real model; the hands use their authored rest.
  local rel=e.rel;if v.id~='GuessWhoHands'and e.src and e.src.Parent then rel=v.srcRoot.CFrame:ToObjectSpace(e.src.CFrame)end
  local p=rootCF*CFrame.new(e.side*squeeze,0,0)*rel;e.part.CFrame=p;placed[e.part]=p
 end
 for _,f in ipairs(v.fingers)do
  local palm=placed[f.palm];if palm then f.finger.CFrame=palm*f.c0*CFrame.Angles(angle*f.w,0,0)*f.c1:Inverse()end
 end
 for _,x in v.src:GetDescendants()do if x:IsA('BasePart')then x.LocalTransparencyModifier=1 end end
end
-- The hand mirror only reflects what is straight behind the holder, so the monster stands on that line.
-- The doorway the server chose is kept when it is already close to the line.
local REFLECT_KEEP_DOOR_DOT=math.cos(math.rad(12))
local REFLECT_MIN,REFLECT_MAX=6,14
local function reflectionSpot(c,cam,cf)
 local r=c and c:FindFirstChild('HumanoidRootPart');local folder=workspace:FindFirstChild('HeldItemVisuals')
 if not r or not cam or not folder then return cf end
 local glass
 for _,copy in folder:GetChildren()do local s=copy:FindFirstChild('MirrorSurface');if s and copy:GetAttribute('ItemId')=='FearMirror'then glass=s end end
 if not glass then return cf end
 local back=cam.CFrame.Position-glass.Position;back=Vector3.new(back.X,0,back.Z)
 if back.Magnitude<.01 then return cf end;back=back.Unit
 local toDoor=cf.Position-r.Position;toDoor=Vector3.new(toDoor.X,0,toDoor.Z)
 if toDoor.Magnitude>.01 and toDoor.Unit:Dot(back)>=REFLECT_KEEP_DOOR_DOT then return cf end
 local dist=math.clamp(toDoor.Magnitude,REFLECT_MIN,REFLECT_MAX)
 local map=workspace:FindFirstChild('Mansion');local collision=map and map:FindFirstChild('Collision')
 if collision then
  local params=RaycastParams.new();params.FilterType=Enum.RaycastFilterType.Include;params.FilterDescendantsInstances={collision}
  -- No room before a wall behind the player: keep the server's (wall-checked) spot instead.
  local hit=workspace:Raycast(r.Position,back*dist,params);if hit then dist=hit.Distance-1.5;if dist<2 then return cf end end
 end
 local pos=Vector3.new(r.Position.X,cf.Position.Y,r.Position.Z)+back*dist
 return CFrame.lookAt(pos,Vector3.new(r.Position.X,pos.Y,r.Position.Z))
end
local function monsterSource()
 local folder=workspace:FindFirstChild('RoamingCreatures')
 if folder then for _,m in folder:GetChildren()do if m:IsA('Model') and m:FindFirstChildWhichIsA('BasePart',true)then return m end end end
end
local function createApparition(source)
 local arch=source.Archivable;source.Archivable=true
 local ok,clone=pcall(function()return source:Clone()end);source.Archivable=arch
 if not ok or not clone then return end
 for _,d in clone:GetDescendants()do
  if d:IsA('LuaSourceContainer')or d:IsA('Sound')or d:IsA('Humanoid')or d:IsA('Animator')or d:IsA('JointInstance')or d:IsA('Constraint')then d:Destroy()
  elseif d:IsA('BasePart')then d.Anchored=true;d.CanCollide=false;d.CanQuery=false;d.CanTouch=false;d.Massless=true end
 end
 clone.Name='FearMirrorApparition';clone:SetAttribute('MirrorApparition',true);clone.Parent=workspace
 local _,size=clone:GetBoundingBox();local factor=math.min(1,7/math.max(size.X,size.Z,.01),9/math.max(size.Y,.01))
 if factor<1 then clone:ScaleTo(clone:GetScale()*factor)end
 apparition=clone;apparitionSource=source
end
-- Everyone's view of a wearer: hands creep up from behind, fingers part for a peek.
local function peerHands(p,now)
 local c=p.Character;local hands=c and c:FindFirstChild('CursedAttach_GuessWhoHands')
 if not hands then return end
 local age=now-(p:GetAttribute('GuessWhoStart')or now)
 local active=now<(p:GetAttribute('GuessWhoUntil')or 0)
 local peek=active and age>=HAND_RISE and (age-HAND_RISE)%HAND_CYCLE>=HAND_CLOSED
 local target=peek and HAND_PEEK_ANGLE or 0
 local root=hands.PrimaryPart;local weld=root and root:FindFirstChild('CursedVisualWeld')
 local rest=root and root:GetAttribute('CursedVisualRestC0')
 -- Head +Z is the face front, so -Z is behind. The offset is in Head space: left of the rest C0.
 local away=1-math.clamp(age/HAND_RISE,0,1);away*=away
 if weld and typeof(rest)=='CFrame'then weld.C0=CFrame.new(0,HAND_RISE_UP*away,-HAND_RISE_BACK*away)*rest end
 -- The character Animator resets Motor6D.Transform inside the rig every frame, so pose C0 locally.
 for _,d in hands:GetDescendants()do if d:IsA('Motor6D')and d.Name=='Knuckle'then
  local base=d:GetAttribute('BaseC0');if typeof(base)~='CFrame'then base=d.C0;d:SetAttribute('BaseC0',base)end
  local angle=d:GetAttribute('SpreadNow')or 0;angle+=(target*(d:GetAttribute('SpreadWeight')or 1)-angle)*.18
  d:SetAttribute('SpreadNow',angle);d.C0=base*CFrame.Angles(angle,0,0)
 end end
end
Run:BindToRenderStep('CursedCoopVisuals',Enum.RenderPriority.Camera.Value+8,function()
 local now=workspace:GetServerTimeNow()
 for _,p in Players:GetPlayers()do peerHands(p,now)end
 local c=player.Character
 local alive=c and c:FindFirstChildOfClass('Humanoid')and c:FindFirstChildOfClass('Humanoid').Health>0
 local cam=workspace.CurrentCamera
 local map=workspace:FindFirstChild('Mansion');local interactive=map and map:FindFirstChild('Interactive')
 -- Wearer view models: hands visual plus attached plunger / hair.
 local want={}
 if alive and cam and cam.CameraType~=Enum.CameraType.Scriptable then
  local hands=c:FindFirstChild('CursedAttach_GuessWhoHands')
  if hands and now<(player:GetAttribute('GuessWhoUntil')or 0)then want[hands]='GuessWhoHands'end
  if interactive then for _,m in interactive:GetChildren()do
   local id=m:GetAttribute('ItemId')
   if VIEW_ANCHOR[id]and id~='GuessWhoHands'and m:GetAttribute('AttachedTo')==player.UserId then want[m]=id end
  end end
 end
 for src in pairs(views)do if not want[src]or not src.Parent then dropView(src)end end
 for src,id in pairs(want)do local v=views[src]or makeView(src,id);if v then poseView(v,cam,now)end end
 local fear=alive and now<(player:GetAttribute('MirrorFearUntil')or 0)
 local cf=player:GetAttribute('MirrorMonsterCF')
 if fear and typeof(cf)=='CFrame'then
  if not apparition then local source=monsterSource();if source then createApparition(source)end end
  if apparition then
   cf=reflectionSpot(c,cam,cf)
   apparition:PivotTo(cf);local box,size=apparition:GetBoundingBox();local lift=cf.Position.Y-(box.Position.Y-size.Y*.5)
   apparition:PivotTo(apparition:GetPivot()+Vector3.new(0,lift,0));apparition:SetAttribute('FearHolder',player.UserId)
  end
  local start=player:GetAttribute('MirrorFearStart')or now
  if stingAt~=start then stingAt=start;Audio.Play('MirrorSting',c:FindFirstChild('Head'))end
  if cam then cam.CFrame*=CFrame.Angles(math.sin(now*39)*.0015,math.sin(now*31)*.002,math.sin(now*27)*.002)end
 else destroyApparition();stingAt=nil end
 local present={}
 if interactive then for _,m in interactive:GetChildren()do if m:GetAttribute('AttachedTo')and m:GetAttribute('ItemId')=='ClingyTeddy'and m.PrimaryPart then
  present[m]=true
 end end end
 for m,sound in pairs(whispers)do if not present[m]then pcall(function()sound:Stop();sound:Destroy()end);whispers[m]=nil end end
end)
player.CharacterRemoving:Connect(function()destroyApparition();stopWhisper();clearViews()end)
