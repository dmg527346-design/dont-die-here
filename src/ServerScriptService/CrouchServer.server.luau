-- Crouch: the one owner of the Crouching attribute and the crouched body.
-- Crouching shrinks the player's belly blob (UpperTorso, its tattoo and any torso cosmetics) into a
-- small copy of itself with a quick squash tween, sinks the body low, and lets them squeeze under desks and tables
-- (those colliders join CrouchCover, which RecoveryCrouching passes through). Tucked under one for
-- HIDE_DELAY seconds counts as hiding (DeskHiding + Hiding), like a closet. Clients only ask; the
-- server checks and applies everything, and restores it all on stand / death / respawn / leave.
local Players=game:GetService('Players')
local RS=game:GetService('ReplicatedStorage')
local Physics=game:GetService('PhysicsService')
local RunService=game:GetService('RunService')
local TweenService=game:GetService('TweenService')

local HIP_DROP=1.36 -- studs the hips sink (legs clip into the floor on purpose: it looks silly)
local WAIST_DROP=1.2 -- the mini body sits this much lower than the belly did
local MINI=.6 -- the crouched body is the real belly at this scale
local STALK_FOLD=math.rad(105) -- eye stalks fold back this far so the eyes clear desk undersides
local STALK_SPLAY=math.rad(25) -- and lean out to the sides a little
local DOWN=TweenInfo.new(.3,Enum.EasingStyle.Back,Enum.EasingDirection.Out) -- squash down with a little bounce
local UP=TweenInfo.new(.22,Enum.EasingStyle.Quad,Enum.EasingDirection.Out)
local HIDE_DELAY=0 -- under cover counts as hidden at once, like stepping into a closet (MonsterProtection reads Hiding)
local LEAVE_GRACE=.6 -- same grace a closet gives after you come out
local COVER={Desk=true,Table=true}
local CHAR_GROUP,CROUCH_GROUP,COVER_GROUP='RecoveryCharacters','RecoveryCrouching','CrouchCover'

local event=RS:FindFirstChild('CrouchEvent') or Instance.new('RemoteEvent')
event.Name='CrouchEvent';event.Parent=RS

local state={} -- [Player]={character=,saved=,coverSince=}
local busy={} -- [Player]=true while the stand-up tween runs
local groupsReady=false
local function ensureGroups()
 if groupsReady then return end
 for _,g in {CROUCH_GROUP,COVER_GROUP} do if not Physics:IsCollisionGroupRegistered(g) then Physics:RegisterCollisionGroup(g) end end
 -- Crouching collides exactly like a normal character, and cover exactly like Default, except with each other.
 local base=Physics:IsCollisionGroupRegistered(CHAR_GROUP) and CHAR_GROUP or 'Default'
 for _,g in Physics:GetRegisteredCollisionGroups() do
  local name=g.name
  if name~=CROUCH_GROUP and name~=COVER_GROUP then
   Physics:CollisionGroupSetCollidable(CROUCH_GROUP,name,Physics:CollisionGroupsAreCollidable(base,name))
   Physics:CollisionGroupSetCollidable(COVER_GROUP,name,Physics:CollisionGroupsAreCollidable('Default',name))
  end
 end
 Physics:CollisionGroupSetCollidable(CROUCH_GROUP,CROUCH_GROUP,Physics:CollisionGroupsAreCollidable(base,base))
 Physics:CollisionGroupSetCollidable(COVER_GROUP,COVER_GROUP,true)
 Physics:CollisionGroupSetCollidable(CROUCH_GROUP,COVER_GROUP,false)
 groupsReady=true
end

-- Desks and tables in the current map become cover (rebuilt maps included).
local watched
local function markCover(part)
 if part:IsA('BasePart') and COVER[part.Name] and part:GetAttribute('Furniture') then part.CollisionGroup=COVER_GROUP end
end
local function watchMap()
 local map=workspace:FindFirstChild('Mansion');local col=map and map:FindFirstChild('Collision')
 if not col or col==watched then return end
 watched=col;ensureGroups()
 for _,p in col:GetChildren() do markCover(p) end
 col.ChildAdded:Connect(markCover)
end

local function torsoAnchored(part,torso)
 for _,j in part:GetChildren() do
  if (j:IsA('JointInstance') or j:IsA('WeldConstraint')) and (j.Part0==torso or j.Part1==torso) then return true end
 end
 return false
end
local function weld(a,b,cf)
 local m=Instance.new('Motor6D');m.Part0=a;m.Part1=b;m.C0=cf;m.Parent=b;return m
end
local function hideTorsoStuff(c,saved,torso)
 local head=c:FindFirstChild('Head')
 local feet={c:FindFirstChild('LeftFoot'),c:FindFirstChild('RightFoot')}
 local function hide(x)
  if saved.hidden[x] then return end
  if x:IsA('BasePart') then saved.hidden[x]=x.Transparency;x.Transparency=1
  elseif x:IsA('Decal') or x:IsA('Texture') then saved.hidden[x]=x.Transparency;x.Transparency=1
  elseif x:IsA('ParticleEmitter') or x:IsA('Beam') or x:IsA('Trail') or x:IsA('SurfaceGui') or x:IsA('Light') then saved.hidden[x]=x.Enabled;x.Enabled=false end
 end
 hide(torso)
 for _,x in torso:GetDescendants() do hide(x) end
 -- the rig's feet are shoe-shaped meshes: hide them (and anything on them) too
 for _,f in feet do hide(f);for _,x in f:GetDescendants() do hide(x) end end
 -- tattoos, shirts and auras worn on the belly, hats worn on the head and shoes on the feet, go with it
 local cos=c:FindFirstChild('ProgressCosmetics')
 if cos then for _,item in cos:GetChildren() do
  local parts=item:IsA('BasePart') and {item} or item:GetDescendants()
  local onTorso=false
  for _,p in parts do if p:IsA('BasePart') and (torsoAnchored(p,torso) or (head and torsoAnchored(p,head)) or (feet[1] and torsoAnchored(p,feet[1])) or (feet[2] and torsoAnchored(p,feet[2]))) then onTorso=true break end end
  if onTorso then hide(item) for _,x in item:GetDescendants() do hide(x) end end
 end end
end

local function buildMini(c,torso)
 -- a copy of the real belly (mesh, colour and surface), welded to it, that tweens down to MINI size
 local mini=torso:Clone()
 for _,x in mini:GetChildren() do if not x:IsA('SurfaceAppearance') then x:Destroy() end end
 mini.Name='CrouchBody';mini.Transparency=0;mini.CanCollide=false;mini.CanTouch=false;mini.CanQuery=false;mini.Massless=true
 mini.CollisionGroup='Default';mini.CFrame=torso.CFrame;mini.Parent=c
 weld(torso,mini,CFrame.new()).Name='CrouchBodyJoint'
 return mini
end

-- Each EyeNeckJoint (Head -> stalk) gets a folded C0: tipped backwards (away from the face) and out to its side.
local function stalkFolds(c)
 local head=c:FindFirstChild('Head');if not head then return {} end
 local folds={}
 for _,m in head:GetDescendants() do
  if m:IsA('Motor6D') and m.Name=='EyeNeckJoint' and m.Part1 then
   local side=m.Part1.Name:find('Left') and 'Left' or 'Right'
   local ball=head:FindFirstChild(side..'Eyeball');local pupil=head:FindFirstChild(side..'Pupil')
   local face=(ball and pupil) and head.CFrame:VectorToObjectSpace(pupil.Position-ball.Position) or Vector3.new(0,0,1)
   face=Vector3.new(face.X,0,face.Z);face=face.Magnitude>1e-3 and face.Unit or Vector3.new(0,0,1)
   local back=-face
   local out=Vector3.new(m.C0.Position.X,0,m.C0.Position.Z);out=out-out:Dot(face)*face;out=out.Magnitude>1e-3 and out.Unit or Vector3.yAxis:Cross(face)
   -- rotate the stalk's up-axis toward 'back', then toward its own side
   local fold=CFrame.fromAxisAngle(Vector3.yAxis:Cross(back).Unit,STALK_FOLD)*CFrame.fromAxisAngle(Vector3.yAxis:Cross(out).Unit,STALK_SPLAY)
   folds[m]={original=m.C0,folded=CFrame.new(m.C0.Position)*fold*m.C0.Rotation}
  end
 end
 return folds
end

local function joint(c,name)
 for _,m in c:GetDescendants() do if m:IsA('Motor6D') and m.Name==name then return m end end
end

local function underCover(c)
 local root=c:FindFirstChild('HumanoidRootPart');if not root then return false end
 for _,p in workspace:GetPartBoundsInBox(root.CFrame*CFrame.new(0,.6,0),Vector3.new(1.1,3.4,1.1)) do
  if p.CollisionGroup==COVER_GROUP then return true end
 end
 return false
end

local function setHiding(p,on)
 if on then p:SetAttribute('DeskHiding',true);p:SetAttribute('Hiding',true)
 elseif p:GetAttribute('DeskHiding') then
  p:SetAttribute('DeskHiding',nil)
  if not p:GetAttribute('ClosetState') then p:SetAttribute('Hiding',nil);p:SetAttribute('ClosetProtectedUntil',workspace:GetServerTimeNow()+LEAVE_GRACE) end
 end
end

local function stand(p,force)
 local s=state[p];if not s then return true end
 local c=s.character
 if not force and c.Parent and underCover(c) then return false end -- no room to stand under a desk
 state[p]=nil;setHiding(p,false);p:SetAttribute('Crouching',nil)
 local saved=s.saved
 local hum=c:FindFirstChildOfClass('Humanoid')
 local mini=c:FindFirstChild('CrouchBody')
 local function finish()
  for x,v in saved.hidden do if x.Parent then if typeof(v)=='boolean' then x.Enabled=v else x.Transparency=v end end end
  if mini then mini:Destroy() end
  if hum then hum.HipHeight=saved.hip;hum.JumpHeight=saved.jumpHeight;hum.JumpPower=saved.jumpPower end
  if saved.waist and saved.waist.Parent then saved.waist.C0=saved.waistC0 end
  if saved.neck and saved.neck.Parent then saved.neck.C0=saved.neckC0 end
  for m,f in saved.stalks or {} do if m.Parent then m.C0=f.original end end
  for x,g in saved.groups do if x.Parent and x.CollisionGroup==CROUCH_GROUP then x.CollisionGroup=g end end
  busy[p]=nil
 end
 if force or not c.Parent or not hum or not mini then finish() return true end
 -- grow back to full size while rising, then hand over to the real belly
 busy[p]=true
 TweenService:Create(hum,UP,{HipHeight=saved.hip}):Play()
 if saved.waist then TweenService:Create(saved.waist,UP,{C0=saved.waistC0}):Play() end
 if saved.neck then TweenService:Create(saved.neck,UP,{C0=saved.neckC0}):Play() end
 for m,f in saved.stalks or {} do if m.Parent then TweenService:Create(m,UP,{C0=f.original}):Play() end end
 local grow=TweenService:Create(mini,UP,{Size=saved.torsoSize})
 grow.Completed:Once(finish);grow:Play()
 return true
end

local function crouch(p)
 if state[p] or busy[p] then return end
 local c=p.Character;local hum=c and c:FindFirstChildOfClass('Humanoid');local torso=c and c:FindFirstChild('UpperTorso')
 if not hum or hum.Health<=0 or not torso or p:GetAttribute('MissionActive')~=true then return end
 if p:GetAttribute('ClosetState') or p:GetAttribute('Hiding') or p:GetAttribute('MonsterJumpscareActive') or p:GetAttribute('RoundDead') then return end
 watchMap();ensureGroups()
 local saved={hidden={},groups={},hip=hum.HipHeight,jumpHeight=hum.JumpHeight,jumpPower=hum.JumpPower}
 saved.waist=joint(c,'Waist');saved.neck=joint(c,'Neck')
 saved.waistC0=saved.waist and saved.waist.C0;saved.neckC0=saved.neck and saved.neck.C0
 state[p]={character=c,saved=saved,coverSince=nil}
 saved.torsoSize=torso.Size
 local mini=buildMini(c,torso) -- copy first, then hide the real belly: no gap, no pop
 hideTorsoStuff(c,saved,torso)
 hum.JumpHeight=0;hum.JumpPower=0
 TweenService:Create(hum,DOWN,{HipHeight=math.max(.2,saved.hip-HIP_DROP)}):Play()
 TweenService:Create(mini,DOWN,{Size=saved.torsoSize*MINI}):Play()
 if saved.waist then TweenService:Create(saved.waist,DOWN,{C0=saved.waistC0*CFrame.new(0,-WAIST_DROP,0)}):Play() end
 saved.stalks=stalkFolds(c)
 for m,f in saved.stalks do TweenService:Create(m,DOWN,{C0=f.folded}):Play() end
 if saved.neck then local pos=saved.neckC0.Position;TweenService:Create(saved.neck,DOWN,{C0=CFrame.new(pos.X,pos.Y*MINI,pos.Z)*saved.neckC0.Rotation}):Play() end
 for _,x in c:GetDescendants() do if x:IsA('BasePart') and x.CollisionGroup==CHAR_GROUP then saved.groups[x]=x.CollisionGroup;x.CollisionGroup=CROUCH_GROUP end end
 p:SetAttribute('Crouching',true)
end

event.OnServerEvent:Connect(function(p,want)
 if type(want)~='boolean' then return end
 if want then crouch(p) else local ok=stand(p,false);if not ok then event:FireClient(p,'blocked') end end
end)

-- anything that ends the crouch: death, respawn, closet, jumpscare, leaving the mission
local function watchPlayer(p)
 p.CharacterAdded:Connect(function() stand(p,true) end)
 p.CharacterRemoving:Connect(function() stand(p,true) end)
 for _,a in {'ClosetState','MonsterJumpscareActive','RoundDead','MissionActive'} do
  p:GetAttributeChangedSignal(a):Connect(function()
   if not state[p] then return end
   if (a=='MissionActive' and p:GetAttribute(a)~=true) or (a~='MissionActive' and p:GetAttribute(a)) then stand(p,true) end
  end)
 end
end
for _,p in Players:GetPlayers() do watchPlayer(p) end
Players.PlayerAdded:Connect(watchPlayer)
Players.PlayerRemoving:Connect(function(p) state[p]=nil;busy[p]=nil end)

-- cover check: tucked under a desk/table long enough counts as hiding
local timer=0
RunService.Heartbeat:Connect(function(dt)
 timer+=dt;if timer<.1 then return end;timer=0
 watchMap()
 local now=os.clock()
 for p,s in state do
  local c=s.character;local hum=c.Parent and c:FindFirstChildOfClass('Humanoid')
  if not hum or hum.Health<=0 then stand(p,true) continue end
  if underCover(c) then
   s.coverSince=s.coverSince or now
   if now-s.coverSince>=HIDE_DELAY and not p:GetAttribute('DeskHiding') then setHiding(p,true) end
  else s.coverSince=nil;setHiding(p,false) end
 end
end)
