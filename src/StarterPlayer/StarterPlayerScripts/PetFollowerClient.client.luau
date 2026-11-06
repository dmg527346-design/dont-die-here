-- PetFollowerClient (WorldA 2026-10-27, World/GlowMoth): draws every player's token-shop PET on this client.
-- The pet comes from player attribute EquippedPet (ProgressService sets Equipped<slot> for every
-- LobbyShopCatalog.CosmeticSlots entry); template ReplicatedStorage.CosmeticKit.<offer id> like every wearable.
-- Found companions (PeekabooSock, DustBunnyBot: player attribute Companion) are drawn by CursedA's
-- CurseEffectsClient.ItemBatch7Client, not here. Pets are pure looks: anchored, never collide / query / touch, no shadow,
-- no lights, never on the server. They never path-find: an offset from the owner's head, one short ray keeps them out of
-- walls, and a pet too far from its goal pops back beside you.
-- Moth behaviour: bobs by your ear; a happy loop round your head when the team sells; lands on your head after 6 s idle;
-- tucks behind your head shivering while a monster chases you (ChasedUntil); hidden in closets and when dead. Your own moth in
-- first person rides behind your head and peeks in at the top-left edge of your view for ~3 s every 12 s (and on sales).
local Players=game:GetService('Players')
local RS=game:GetService('ReplicatedStorage')
local Run=game:GetService('RunService')
local Shop=require(RS:WaitForChild('LobbyShopCatalog'))
local InputHints=require(RS:WaitForChild('InputHints'))
local player=Players.LocalPlayer
local camera=workspace.CurrentCamera

local DRAW_RADIUS=90        -- pets further than this from the camera are parked (not drawn, not updated)
local SLOW_RADIUS=40        -- beyond this they update at 10 Hz instead of every frame
local MAX_DRAWN=if InputHints.IsMobile()then 4 else 8
local TELEPORT=22           -- further than this from its goal: pop next to the owner

local folder=Instance.new('Folder');folder.Name='PetFollowers';folder.Parent=workspace
local followers={}          -- userId -> state
local params=RaycastParams.new();params.FilterType=Enum.RaycastFilterType.Exclude;params.RespectCanCollide=true
local round=RS:FindFirstChild('RecoveryRound') -- mission servers only (Sold drives the happy loop)

local function flat(v)
 local f=Vector3.new(v.X,0,v.Z);return if f.Magnitude>1e-3 then f.Unit else Vector3.new(0,0,-1)
end
local function refreshExclude()
 local list={folder}
 for _,p in ipairs(Players:GetPlayers())do if p.Character then table.insert(list,p.Character)end end
 local map=workspace:FindFirstChild('Mansion');local items=map and map:FindFirstChild('Interactive')
 if items then table.insert(list,items)end
 local creatures=workspace:FindFirstChild('RoamingCreatures');if creatures then table.insert(list,creatures)end
 local companions=workspace:FindFirstChild('CompanionFollowers');if companions then table.insert(list,companions)end
 params.FilterDescendantsInstances=list
end
local function clampToRoom(from,to,pad)
 local dir=to-from;if dir.Magnitude<.05 then return to end
 local hit=workspace:Raycast(from,dir,params)
 return if hit then hit.Position-dir.Unit*math.min(pad,hit.Distance)else to
end
local function ownerParts(p)
 local c=p.Character;local h=c and c:FindFirstChildOfClass('Humanoid')
 if not c or not h or h.Health<=0 then return nil end
 local root=c:FindFirstChild('HumanoidRootPart');local head=c:FindFirstChild('Head')
 if not root or not head then return nil end
 return c,root,head,h
end
local function templateFor(id)
 local kit=RS:FindFirstChild('CosmeticKit');local t=kit and kit:FindFirstChild(id)
 local offer=Shop.ById and Shop.ById[id]
 return t and t:IsA('Model') and offer and offer.kind=='Pet' and t or nil
end

local function build(owner,id)
 local t=templateFor(id);if not t then return nil end
 local m=t:Clone();m.Name=owner.Name..'_'..id
 local wings={}
 for _,x in ipairs(m:GetDescendants())do
  if x:IsA('BasePart')then
   x.Anchored=true;x.CanCollide=false;x.CanQuery=false;x.CanTouch=false;x.CastShadow=false;x.Massless=true
   if x.Material==Enum.Material.Neon then wings[x]=x.Size end
  elseif x:IsA('LuaSourceContainer')or x:IsA('Light')or x:IsA('Sound')or x:IsA('JointInstance')or x:IsA('WeldConstraint')then x:Destroy()end
 end
 m.Parent=folder
 return {owner=owner,id=id,model=m,wings=wings,pos=nil,updatedAt=0,drawn=true,idleSince=os.clock(),loopUntil=0,distance=0,phase=math.random()*12}
end
local function destroy(key)
 local s=followers[key];if not s then return end
 s.model:Destroy();followers[key]=nil
end
local function wanted()
 local list={}
 for _,p in ipairs(Players:GetPlayers())do
  if ownerParts(p)and not p:GetAttribute('RoundDead')and not p:GetAttribute('Hiding')and not p:GetAttribute('ClosetState')then
   local pet=p:GetAttribute('EquippedPet')
   if type(pet)=='string'and pet~=''then list[p.UserId]={p,pet}end
  end
 end
 return list
end
local function sync()
 local want=wanted()
 for key,s in pairs(followers)do
  local w=want[key];if not w or w[1]~=s.owner or w[2]~=s.id then destroy(key)end
 end
 for key,w in pairs(want)do if not followers[key]then followers[key]=build(w[1],w[2])end end
 local camPos=camera.CFrame.Position;local order={}
 for _,s in pairs(followers)do
  local _,root=ownerParts(s.owner)
  s.distance=root and(root.Position-camPos).Magnitude or math.huge;table.insert(order,s)
 end
 table.sort(order,function(a,b)return a.distance<b.distance end)
 for i,s in ipairs(order)do
  local draw=i<=MAX_DRAWN and s.distance<=DRAW_RADIUS
  if draw~=s.drawn then s.drawn=draw;s.model.Parent=draw and folder or nil;if not draw then s.pos=nil end end
 end
end

local function update(s,root,head,now,dt,own)
 local look=flat(root.CFrame.LookVector);local right=look:Cross(Vector3.yAxis)
 local moving=Vector3.new(root.AssemblyLinearVelocity.X,0,root.AssemblyLinearVelocity.Z).Magnitude>.5
 if moving then s.idleSince=now end
 local chased=(s.owner:GetAttribute('ChasedUntil')or 0)>workspace:GetServerTimeNow()
 local goal;local flap=16;local scale=1
 if own and not chased then -- first person: tucked behind your head, then a short peek at the top-left edge of the view
  local peek=now<s.loopUntil or(now+s.phase)%12<3.2
  if peek then local cf=camera.CFrame;goal=cf.Position+cf.RightVector*-2.3+cf.UpVector*(1.05+math.sin(now*2.4)*.18)+cf.LookVector*4.6;flap=20
  else goal=head.Position+Vector3.yAxis*.15-look*.9;flap=6 end
 elseif chased then          -- hides behind your head ("in your hood"), shivering
  goal=head.Position+Vector3.yAxis*.1-look*.75+Vector3.new(math.sin(now*40)*.04,0,0);flap=26;scale=.85
 elseif now<s.loopUntil then -- sale: a happy loop round your head
  local a=now*6;goal=head.Position+Vector3.yAxis*.6+(right*math.cos(a)+look*math.sin(a))*1.8;flap=24
 elseif now-s.idleSince>6 then -- idle: lands on top of your head, slow wings
  goal=head.Position+Vector3.yAxis*(head.Size.Y/2+.02);flap=3
 else
  goal=head.Position+right*1.5+Vector3.yAxis*(.6+math.sin(now*2.1)*.25)-look*.4+right*math.sin(now*1.3)*.35
 end
 goal=clampToRoom(head.Position,goal,.35)
 s.pos=if s.pos and(s.pos-goal).Magnitude<TELEPORT then s.pos:Lerp(goal,1-math.exp(-9*dt))else goal
 local yaw=math.atan2(-look.X,-look.Z)+math.sin(now*1.7)*.35
 s.model:PivotTo(CFrame.new(s.pos)*CFrame.Angles(0,yaw,0))
 local beat=.4+.6*math.abs(math.sin(now*flap))
 for part,base in pairs(s.wings)do part.Size=Vector3.new(base.X*beat*scale,base.Y*scale,base.Z)end
end

if round then -- a sale (Sold went up): every pet does a happy loop
 local lastSold=round:GetAttribute('Sold')or 0
 round:GetAttributeChangedSignal('Sold'):Connect(function()
  local sold=round:GetAttribute('Sold')or 0;local up=sold>lastSold;lastSold=sold
  if not up then return end
  local now=os.clock()
  for _,s in pairs(followers)do s.loopUntil=now+1.4 end
 end)
end
local syncAt,excludeAt=0,0
Run.RenderStepped:Connect(function(dt)
 local now=os.clock()
 if now>=excludeAt then excludeAt=now+1;refreshExclude()end
 if now>=syncAt then syncAt=now+.25;sync()end
 for _,s in pairs(followers)do
  if not s.drawn then continue end
  local _,root,head=ownerParts(s.owner)
  if not root or not head then continue end
  local slow=(s.distance or 0)>SLOW_RADIUS
  if slow and now-s.updatedAt<.1 then continue end
  local step=if slow then now-s.updatedAt else dt
  s.updatedAt=now
  local own=s.owner==player and (camera.CFrame.Position-head.Position).Magnitude<1.3 -- first person: never in your face (peeks instead)
  if s.model.Parent~=folder then s.model.Parent=folder end
  update(s,root,head,now,math.min(step,.2),own)
 end
end)
Players.PlayerRemoving:Connect(function(p)
 for key,s in pairs(followers)do if s.owner==p then destroy(key)end end
end)
