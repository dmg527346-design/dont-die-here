-- Owned by CreatureRoamServer. One nuisance per level; never a normal weapon target.
local S={}
S.Damage=8
S.AttackRange=3.8
S.ReturnDelay=12
S.GroundSpeed=18
S.RetreatSpeed=38
S.SurfaceSpeed=15
S.StallSeconds=2
S.TrapBaitRange=25
local Y=Vector3.yAxis
local function flat(v)return Vector3.new(v.X,0,v.Z)end
local function mode(s,value)s.mode=value;s.model:SetAttribute('AIState',value)end
local function surface(s,value)s.surface=value;s.model:SetAttribute('SurfaceMode',value);s.model:SetAttribute('Grounded',value=='Ground')end
function S.New(ctx) return setmetatable({ctx=ctx,current=nil,slain=false},{__index=S})end
function S:Clear()
 if self.current and self.current.model.Parent then self.current.model:Destroy()end
 self.current=nil;self.slain=false
 self.ctx.Round:SetAttribute('SkitterCount',0);self.ctx.Round:SetAttribute('SkitterTrapped',nil)
end
function S:Spawn(owner,point,room)
 if self.current or self.slain then return false end
 local kit=self.ctx.Storage:FindFirstChild('Skitter_NPC')
 if not kit or not kit:IsA('Model')or not kit.PrimaryPart then return false end
 local model=kit:Clone();local root=model.PrimaryPart
 -- Rebuild only rigid joints: clone references can never bind this creature to outside objects.
 for _,j in model:GetDescendants()do if j:IsA('JointInstance')or j:IsA('WeldConstraint')or j:IsA('Constraint')then j:Destroy()end end
 root.Anchored=true;root.CanCollide=false;root.CanQuery=false;root.CanTouch=false
 local legs={}
 local low=math.huge
 for _,part in model:GetDescendants()do if part:IsA('BasePart')and part~=root then
  part.Anchored=false;part.CanCollide=false;part.CanTouch=false;part.CanQuery=part.Transparency<.95;part.Massless=true
  if part.Transparency<.95 then low=math.min(low,root.CFrame:PointToObjectSpace(part.Position).Y-part.Size.Y*.5)end
  if table.find({'LegFL','LegFR','LegML','LegMR','LegBL','LegBR'},part.Name)then
   local pivot=part:GetPivot();local joint=Instance.new('Motor6D');joint.Name=part.Name..'SkitterJoint';joint.Part0=root;joint.Part1=part
   joint.C0=root.CFrame:ToObjectSpace(pivot);joint.C1=part.CFrame:ToObjectSpace(pivot);joint.Parent=root
   legs[#legs+1]={joint=joint,rest=joint.C0,side=part.Name:sub(-1)=='L'and -1 or 1,index=#legs+1}
  else local w=Instance.new('WeldConstraint');w.Part0=root;w.Part1=part;w.Parent=root end
 end end
 local offset=math.max(0,tonumber(kit:GetAttribute('GroundOffset'))or(low<math.huge and -low or 0))
 model.Name='Skitter_Level'..tostring(self.ctx.Round:GetAttribute('Round')or 1)
 model:SetAttribute('CreatureKind','Skitter');model:SetAttribute('NuisanceCreature',true);model:SetAttribute('OwnerUserId',owner.UserId)
 model:SetAttribute('DifficultyLevel',self.ctx.Round:GetAttribute('Round'));model:SetAttribute('SpawnValidated',true)
 model:SetAttribute('HitDamage',S.Damage);model:SetAttribute('TrapOnly',true);model:SetAttribute('PhaseSeed',0)
 model.Parent=self.ctx.Folder
 local s={model=model,root=root,room=room,pos=point+Y*offset,offset=offset,up=Y,forward=Vector3.new(0,0,-1),legs=legs,
  mode='Patrol',surface='Ground',readyAt=os.clock()+8,decideAt=0,points=nil,index=1,progressAt=os.clock(),last=point}
 self.current=s;mode(s,'Patrol');surface(s,'Ground');root.CFrame=CFrame.new(s.pos)
 self.ctx.Round:SetAttribute('SkitterCount',1)
 return true,model
end
function S:Models()local s=self.current;return s and s.model.Parent and {s.model}or {}end
function S:Owns(model)return self.current and self.current.model==model and model.Parent~=nil end
function S:Kill(model,trapPosition)
 local s=self.current
 if not self:Owns(model)or typeof(trapPosition)~='Vector3'or s.surface~='Ground'or not self:Grounded(s)then return false end
 local d=s.pos-Y*s.offset-trapPosition
 if flat(d).Magnitude>3.2 or math.abs(d.Y)>1.1 or not self.ctx.Visible(trapPosition+Y*.5,s.pos+Y*.6)then return false end
 mode(s,'Trapped');model:SetAttribute('Trapped',true);model:Destroy();self.current=nil;self.slain=true
 self.ctx.Round:SetAttribute('SkitterCount',0);self.ctx.Round:SetAttribute('SkitterTrapped',true)
 return true
end
function S:Grounded(s)
 local feet=s.pos.Y-s.offset
 return s.surface=='Ground'and self.ctx.Ground(Vector3.new(s.pos.X,feet,s.pos.Z),s.model)~=nil
end
function S:Eligible(p)
 local c=p.Character;local h=c and c:FindFirstChildOfClass('Humanoid');local r=c and c:FindFirstChild('HumanoidRootPart')
 return p:GetAttribute('MissionActive')==true and not p:GetAttribute('RoundDead')and h and h.Health>0 and r
  and not self.ctx.Protection.IsProtected(p)and not self.ctx.NearVan(r.Position,4)
  and os.clock()>(p:GetAttribute('DisguiseUntil')or 0),r,h
end
function S:Route(s,goal,kind)
 local from=(s.surface=='Ground'and self.ctx.RoomAtFloor(s.pos-Y*s.offset))or s.room;local dest=self.ctx.RoomAtFloor(goal)
 if not from or not dest or self.ctx.NearVan(goal,4)then return false end
 local points=self.ctx.Route(from,dest,goal)
 if not points then return false end
 local out={}
 if s.surface~='Ground'then
  -- Descend at the same wall before using portals/stairs. Never cut horizontally through a ceiling.
  local floor=Vector3.new(s.pos.X,from.level*self.ctx.Floor+s.offset,s.pos.Z)
  if self.ctx.Clear(s.pos,floor,s.model,s.up,Y)and self.ctx.Ground(floor-Y*s.offset,s.model)then out[#out+1]={p=floor,up=Y,surface='Ground'}else return false end
 end
 local start=s.surface=='Ground'and s.pos or(out[1]and out[1].p)
 local skip=1
 if start then for i,p in points do local candidate=p+Y*s.offset;if self.ctx.Clear(start,candidate,s.model)and self.ctx.Visible(start+Y*.6,candidate+Y*.6)then skip=i else break end end end
 for i=skip,#points do local p=points[i];local previous=i>1 and points[i-1]or(start-Y*s.offset);out[#out+1]={p=p+Y*s.offset,up=Y,surface='Ground',stairs=self.ctx.StairSegment and self.ctx.StairSegment(previous,p)}end
 s.points=out;s.index=1;s.destination=dest;mode(s,kind)
 return true
end
function S:Excursion(s)
 local r=s.room;if not r or r.type=='Stair'or os.clock()<(s.noExcursionUntil or 0)then return false end
 local wall=self.ctx.Wall(r,s.pos,s.model)
 if not wall then return false end
 local floor=r.level*self.ctx.Floor;local n=wall.Normal
 local xz=wall.Position+n*1.8
 local a=Vector3.new(xz.X,floor+s.offset,xz.Z)
 local b=Vector3.new(xz.X,floor+7,xz.Z)
 
 local ceiling=self.ctx.Ceiling(Vector3.new((r.x1+r.x2)/2,floor+9,(r.z1+r.z2)/2))
 if not ceiling then return false end
 local c=Vector3.new(xz.X,ceiling.Y-math.max(s.offset,1.8),xz.Z)
 s.ceilingY=ceiling.Y
 -- Imported mesh triangles can sit just above their conservative collision underside.
 local d=Vector3.new((r.x1+r.x2)/2,ceiling.Y-math.max(s.offset,.2),(r.z1+r.z2)/2)
 local points={{p=a,up=Y,surface='Ground'},{p=b,up=n,surface='Wall'},{p=c,up=n,surface='Wall'},
  {p=d,up=-Y,surface='Ceiling'},{p=c,up=n,surface='Wall'},{p=b,up=n,surface='Wall'},{p=a,up=Y,surface='Ground'}}
 local previous,up=s.pos,s.up
 for _,v in points do if not self.ctx.Clear(previous,v.p,s.model,up,v.up)then return false end;previous,up=v.p,v.up end
 s.points=points;s.index=1;mode(s,'SurfacePatrol');return true
end
function S:Retreat(s,p,now)
 s.readyAt=now+S.ReturnDelay;s.target=nil;s.points=nil
 local root=p.Character and p.Character:FindFirstChild('HumanoidRootPart');local away=root and flat(s.pos-root.Position)or Vector3.new(1,0,0)
 away=away.Magnitude>.1 and away.Unit or Vector3.new(1,0,0)
 local choices={}
 for _,r in self.ctx.Rooms do if r.type~='Stair'then
  local c=Vector3.new(r.navx or(r.x1+r.x2)/2,r.level*self.ctx.Floor,r.navz or(r.z1+r.z2)/2)
  if not self.ctx.NearVan(c,6)then choices[#choices+1]={p=c,score=flat(c-s.pos):Dot(away)}end
 end end
 table.sort(choices,function(a,b)return a.score>b.score end)
 for i=1,math.min(8,#choices)do if self:Route(s,choices[i].p,'Retreat')then return end end
 mode(s,'Retreat')
end
function S:FloorClear(s,p)
 if self.ctx.FloorClear then return self.ctx.FloorClear(p,s.model)end
 local params=OverlapParams.new();params.FilterType=Enum.RaycastFilterType.Exclude;params.RespectCanCollide=true
 local ignore={self.ctx.Folder}
 for _,player in self.ctx.Players:GetPlayers()do if player.Character then ignore[#ignore+1]=player.Character end end
 params.FilterDescendantsInstances=ignore
 return #workspace:GetPartBoundsInBox(CFrame.new(p+Y*1.1),Vector3.new(3.1,2.1,3.5),params)==0
end
-- Planning is not progress. Recover only inside the current room on its supported floor.
-- A short upright sweep checks body clearance even when the long descent is obstructed.
function S:Recover(s,now)
 local r=self.ctx.RoomForXZ(s.pos,s.room.level)or s.room
 local margin=2.2
 local xmin,xmax,zmin,zmax=r.x1+margin,r.x2-margin,r.z1+margin,r.z2-margin
 if xmin>xmax or zmin>zmax then return false end
 local floor=r.level*self.ctx.Floor+s.offset
 local function point(x,z)return Vector3.new(math.clamp(x,xmin,xmax),floor,math.clamp(z,zmin,zmax))end
 local candidates={point(s.pos.X,s.pos.Z),point(r.navx or(r.x1+r.x2)/2,r.navz or(r.z1+r.z2)/2)}
 for _,d in {Vector3.new(3,0,0),Vector3.new(-3,0,0),Vector3.new(0,0,3),Vector3.new(0,0,-3),
  Vector3.new(3,0,3),Vector3.new(-3,0,3),Vector3.new(3,0,-3),Vector3.new(-3,0,-3)}do
  candidates[#candidates+1]=point(s.pos.X+d.X,s.pos.Z+d.Z)
 end
 for _,fx in {.25,.5,.75}do for _,fz in {.25,.5,.75}do
  candidates[#candidates+1]=point(xmin+(xmax-xmin)*fx,zmin+(zmax-zmin)*fz)
 end end
 local forceReset=s.recoveryOrigin and(s.pos-s.recoveryOrigin).Magnitude<.5
 local safe,descend
 for _,p in candidates do
  if(s.surface~='Ground'or(p-s.pos).Magnitude>1)and not self.ctx.NearVan(p,6)and self.ctx.Ground(p-Y*s.offset,s.model)
   and self:FloorClear(s,p)and self.ctx.Clear(p+Y*3,p,s.model,Y,Y)then
   safe=safe or p
   if not forceReset and self.ctx.Clear(s.pos,p,s.model,s.up,Y)then safe=p;descend=true;break end
  end
 end
 s.nextRecoveryAt=now+S.StallSeconds
 if not safe then return false end
 s.points=nil;s.target=nil;s.targetRoom=nil;s.targetPos=nil;s.destination=nil;s.repathAt=nil
 s.index=1;s.room=r;s.decideAt=now+S.StallSeconds;s.noExcursionUntil=now+4
 mode(s,now<s.readyAt and'Retreat'or'Patrol')
 if descend and(safe-s.pos).Magnitude>.5 then
  s.recoveryOrigin=s.pos;s.points={{p=safe,up=Y,surface='Ground'}}
 else
  -- Last resort: supported, body-clear floor in this same room, never a route through a lock.
  s.pos=safe;s.up=Y;s.forward=Vector3.new(0,0,-1);surface(s,'Ground')
  s.root.CFrame=CFrame.lookAt(safe,safe+s.forward,Y)
  s.recoveryOrigin=nil;s.last=safe;s.progressAt=now
 end
 s.model:SetAttribute('StallRecoveries',(s.model:GetAttribute('StallRecoveries')or 0)+1)
 s.model:SetAttribute('LastStallRecovery',descend and'Descend'or'FloorReset')
 s.model:SetAttribute('LastStallRecoveryAt',now)
 return true
end
-- Only armed, supported floor traps attract this creature; the gear owner retains kill authority.
function S:ClearTrapBait(s)
 if s.trapTarget and s.mode=='TrapApproach'then s.points=nil;s.decideAt=0 end
 s.trapTarget=nil;s.model:SetAttribute('TrapBaitPosition',nil)
end
function S:TryTrapBait(s,now)
 if not self.ctx.GetTraps or not self:Grounded(s)then self:ClearTrapBait(s);return false end
 local feet=s.pos-Y*s.offset;local choices={}
 for _,rec in self.ctx.GetTraps()do
  local trap,pos=rec.model,rec.position
  if trap and trap.Parent and trap.Name=='ArmedSkitterTrap'and trap:GetAttribute('Armed')==true
   and trap:GetAttribute('TargetKind')=='Skitter'and typeof(pos)=='Vector3'then
   local d=pos-feet;local room=self.ctx.RoomAtFloor(pos)
   if flat(d).Magnitude<=S.TrapBaitRange and math.abs(d.Y)<=1.1 and room
    and self.ctx.Reachable(s.room,room)and self.ctx.Ground(pos,s.model)
    and self.ctx.Visible(feet+Y*1.1,pos+Y*.6)then
    choices[#choices+1]={model=trap,position=pos,distance=d.Magnitude}
   end
  end
 end
 table.sort(choices,function(a,b)return a.distance<b.distance end)
 for _,rec in choices do
  local existing=s.trapTarget==rec.model and s.mode=='TrapApproach'
  if existing and(s.points or rec.distance<=3.2)or self:Route(s,rec.position,'TrapApproach')then
   -- Do not hit a player or leave for a ceiling while approaching/waiting on the trap.
   s.target=nil;s.targetRoom=nil;s.targetPos=nil;s.trapTarget=rec.model
   s.model:SetAttribute('TrapBaitPosition',rec.position)
   return true
  end
 end
 self:ClearTrapBait(s)
 return false
end
function S:Step(dt,now)
 local s=self.current;if not s or not s.model.Parent then return end
 dt=math.min(dt,.05)
 if now<(s.model:GetAttribute('StunnedUntil')or 0)then s.model:SetAttribute('Walking',false);s.model:SetAttribute('MoveSpeed',0);s.last=s.pos;s.progressAt=now;return end
 -- Check each ground transition immediately, including a one-frame excursion return.
 -- Stable ground patrols are throttled; existing bait routes are retained, not rebuilt.
 local grounded=self:Grounded(s)
 if grounded and(not s.baitWasGrounded or now>=(s.baitCheckAt or 0))then
  s.baitCheckAt=now+.15;self:TryTrapBait(s,now)
 elseif s.trapTarget and(not s.trapTarget.Parent or s.trapTarget:GetAttribute('Armed')~=true
  or s.trapTarget:GetAttribute('TargetKind')~='Skitter')then self:ClearTrapBait(s)end
 s.baitWasGrounded=grounded
 if now>=s.decideAt then
  s.decideAt=now+.5
  local target,root,best
  if now>=s.readyAt then for _,p in self.ctx.Players:GetPlayers()do local ok,r=self:Eligible(p)
   if ok then local d=(r.Position-s.pos).Magnitude;local room=self.ctx.RoomAtFloor(r.Position)
    if room and self.ctx.Reachable(s.room,room)and(not best or d<best)then target,root,best=p,r,d end
   end
  end end
  if s.trapTarget and s.mode=='TrapApproach'then
   -- Hold the route/contact instead of restarting an excursion while the trap catches.
  elseif target then
   local room=self.ctx.RoomAtFloor(root.Position)
   if s.target~=target or not s.points or(room~=s.targetRoom)or(now>=(s.repathAt or 0)and(not s.targetPos or(root.Position-s.targetPos).Magnitude>5))then
    if self:Route(s,Vector3.new(root.Position.X,room.level*self.ctx.Floor,root.Position.Z),'Approach')then
     s.target=target;s.targetPos=root.Position;s.targetRoom=room;s.repathAt=now+2
    end
   end
  elseif not s.points then
   s.target=nil
   if now>=s.readyAt then mode(s,'Patrol')end
   if not self:Excursion(s)then
    local r=self.ctx.Rooms[self.ctx.Random:NextInteger(1,#self.ctx.Rooms)]
    self:Route(s,Vector3.new(r.navx or(r.x1+r.x2)/2,r.level*self.ctx.Floor,r.navz or(r.z1+r.z2)/2),now<s.readyAt and'Retreat'or'Patrol')
   end
  end
 end
 local target=s.target
 if target and now>=s.readyAt and self:Grounded(s)then
  local ok,r,h=self:Eligible(target)
  if ok and flat(r.Position-s.pos).Magnitude<=S.AttackRange and math.abs(r.Position.Y-(s.pos.Y-s.offset))<5
   and self.ctx.Visible(s.pos+Y*1.1,r.Position)then
   -- Recheck protection at the actual hit; wall/ceiling states can never damage a player.
   h:TakeDamage(S.Damage);s.model:SetAttribute('LastHitUserId',target.UserId);s.model:SetAttribute('LastHitAt',now)
   s.model:SetAttribute('LastHitSurface',s.surface);s.model:SetAttribute('Hits',(s.model:GetAttribute('Hits')or 0)+1)
   self.ctx.Round:SetAttribute('SkitterHits',(self.ctx.Round:GetAttribute('SkitterHits')or 0)+1)
   if self.ctx.HitJumpscare then self.ctx.HitJumpscare(target,s.model)end
   self:Retreat(s,target,now)
  end
 end
 local wp=s.points and s.points[s.index]
 while wp and(wp.p-s.pos).Magnitude<.3 do surface(s,wp.surface);s.up=wp.up;s.index+=1;wp=s.points[s.index]end
 local speed=s.mode=='Retreat'and S.RetreatSpeed or(s.surface=='Ground'and S.GroundSpeed or S.SurfaceSpeed)
 local walking=false
 if wp then
  local delta=wp.p-s.pos;local travel=math.min(delta.Magnitude,speed*dt);local nextPos=s.pos+delta.Unit*travel
  local nextUp=wp.up
  if wp.surface=='Wall'then
   -- Keep feet pointed at their departing floor/ceiling until the body has cleared that surface.
   if s.up.Y>.5 and nextPos.Y<s.room.level*self.ctx.Floor+2 then nextUp=Y
   end
  end
  -- Floor routes must not flip the re-rooted body up into the ceiling on departure.
  if s.up.Y<-.5 and nextPos.Y>(s.ceilingY or(s.room.level*self.ctx.Floor+14))-2.4 then nextUp=-Y end
  if wp.surface=='Ground'and self.ctx.OpenDoors and now>=(s.doorCheckAt or 0)then s.doorCheckAt=now+.4;self.ctx.OpenDoors(s.pos,delta)end
  local clear=self.ctx.Clear(s.pos,nextPos,s.model,s.up,nextUp,wp.stairs)
  if not clear and wp.surface=='Ground'and s.surface=='Ground'and not wp.stairs then
   -- Preserve the graph waypoint while steering around movable room furniture.
   -- Every candidate still needs the normal solid sweep and a supported floor.
   local direction=flat(delta);local side=direction:Cross(Y)
   if direction.Magnitude>.01 then
    direction=direction.Unit;side=side.Unit
    for _,angle in {.6,1.1,1.55}do
     for _,sign in {s.detourSign or 1,-(s.detourSign or 1)}do
      local step=(direction*math.cos(angle)+side*math.sin(angle)*sign)*travel
      local candidate=s.pos+step
      if self.ctx.Ground(candidate-Y*s.offset,s.model)and self.ctx.Clear(s.pos,candidate,s.model,Y,Y)then
       nextPos=candidate;s.detourSign=sign;clear=true;break
      end
     end
     if clear then break end
    end
   end
  end
  if clear then
   s.pos=nextPos;s.up=nextUp;surface(s,wp.surface);walking=true
   local movement=nextPos-s.last
   local tangent=movement-s.up*movement:Dot(s.up)
   if tangent.Magnitude>.05 then s.forward=tangent.Unit end
   local level=wp.surface=='Ground'and math.floor((s.pos.Y-s.offset+.2)/self.ctx.Floor)or s.room.level
   s.room=self.ctx.RoomForXZ(s.pos,level)or s.room
  else s.points=nil;s.decideAt=now+1 end
 elseif s.points then s.points=nil;if s.destination then s.room=s.destination end end
 if(s.pos-s.last).Magnitude>.5 then s.last=s.pos;s.progressAt=now end
 if now-s.progressAt>=S.StallSeconds and now>=(s.nextRecoveryAt or 0)then
  if self:Recover(s,now)then walking=false end
 end
 local f=s.forward-s.up*s.forward:Dot(s.up);if f.Magnitude<.05 then f=s.up:Cross(Vector3.xAxis);if f.Magnitude<.05 then f=s.up:Cross(Y)end end
 local bob=walking and math.sin(now*24)*.045 or 0
 local cf=CFrame.lookAt(s.pos+s.up*bob,s.pos+s.up*bob+f.Unit,s.up)
 s.root.CFrame=s.root.CFrame:Lerp(cf,1-math.exp(-dt*24))
 for _,leg in s.legs do leg.joint.C0=leg.rest*CFrame.Angles(walking and math.sin(now*26+leg.index*math.pi)*.28 or 0,0,walking and leg.side*.1 or 0)end
 s.model:SetAttribute('Walking',walking);s.model:SetAttribute('MoveSpeed',walking and speed or 0);s.model:SetAttribute('CurrentRoom',s.room.name)
 s.model:SetAttribute('Grounded',self:Grounded(s))
end
function S:Snapshot()
 local s=self.current
 return s and {model=s.model,position=s.pos,surface=s.surface,mode=s.mode,grounded=self:Grounded(s),readyAt=s.readyAt,index=s.index,points=s.points,progressAt=s.progressAt,last=s.last,decideAt=s.decideAt,recoveries=s.model:GetAttribute('StallRecoveries')or 0,hits=s.model:GetAttribute('Hits')or 0,offset=s.offset}or {slain=self.slain}
end
return S


