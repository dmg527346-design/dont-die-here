-- Monster roles (user request 2026-10-22). Every player has 100 HP; each monster kind has its own attack:
--   Crawler  Normal  - the classic catch: the jumpscare kills.
--   Wraith   Rusher  - very fast once it is mad; a 20 HP hit, then it leaves at once.
--   Bellhop  Carrier - lifts the player up like a little rabbit, holds them, sets them down, a 35 HP swat, then leaves them alone.
--   Neon     Laser   - extremely slow; on sight it fires a spinning laser (crouching is always safe, touching it standing
--                      is death). Anyone too close gets a 30 HP kick.
--   Lantern  Seeker  - sees players hiding in closets, pulls them out gently, then gives them 5 seconds to run: still close
--                      after that is death, a real run gets away 75% of the time.
-- A monster busy with an attack does nothing else, and a player under attack can't be grabbed by another monster.
-- A kill always goes through MonsterJumpscare.Start, so each model's own jumpscare plays.
local Players=game:GetService('Players')
local RS=game:GetService('ReplicatedStorage')
local SS=game:GetService('ServerStorage')
local RunService=game:GetService('RunService')
local Workspace=game:GetService('Workspace')

local Health=require(game:GetService('ServerScriptService'):WaitForChild('PlayerHealth'))
local ROLE_BY_KIND={Crawler='Normal',Wraith='Rusher',Bellhop='Carrier',Neon='Laser',Lantern='Seeker',Mittens='Holder',Dancer='Statue',Yoyo='Normal'}
local RUSH={ChaseSpeed=25,EasyChaseSpeed=21,BlindSpeed=13,Damage=20,LeaveAfter=40,Leave=25,PesterVisits=3,PesterRange=10,Cooldown=2,Windup=.3,Dash=40,HitRange=6.5,Turn=2.4}
local CARRY={ChaseSpeed=22,EasyChaseSpeed=20,Hold=2.7,Damage=35,Ignore=20,Lift=.45,Offset=CFrame.new(0,5.7,-2.7),Windup=.25,GrabRange=8}
local LASER={Speed=5,Range=58,TriggerRange=40,Charge=1.15,Fire=4.6,Spin=1.55,LeadAngle=1.9,Height=4.0,Width=1.35,Cooldown=11,KickRange=6.5,KickDamage=30,KickCooldown=4}
local SEEK={Sense=55,Reach=6.5,Countdown=5,SafeDistance=22,EscapeChance=.75,Ignore=25,Cooldown=18,Windup=.25,GrabRange=8,ChaseSpeed=22,EasyChaseSpeed=20,RoamSpeed=16,Dull=.65}
-- Holder (Lonely Mittens, Monsters build 2026-10-27): only players WITHOUT company exist for it (teammate within Company
-- studs, cart within CartCompany, holding the cart, or at the van). Caught alone: led away by the hand for Lead s; a
-- teammate who reaches you frees you unhurt; nobody comes = a Damage squeeze and it leaves you where it stopped.
local HOLD={Company=14,CartCompany=10,ChaseSpeed=18,EasyChaseSpeed=15,LurkSpeed=10,LurkDistance=26,Lurk=6,Windup=.35,GrabRange=7.5,
 Lead=4,LeadSpeed=9,Rescue=7,Damage=25,Ignore=20,RescueIgnore=25,ChillRange=45,Side=2.3}
-- Statue (Wind-Up Dancer, Monsters build 2026-10-27): blind while her tune plays; it winds down (Wind s), she stops and
-- turns once round (Look s): anyone in sight still moving, or whose cart still rolls, is spotted and hunted for Hunt s.
local DANCE={Dance={8,12},DanceHard={6,9},HardLevel=9,Wind=1.6,Look=3,Grace=.35,Range=55,MoveTol=2.2,CartTol=3,PusherRange=60,
 Hunt=9,ChaseSpeed=22,EasyChaseSpeed=18,WindSpeed=4,Windup=.3,GrabRange=7,Twirl=1.4,Radius=2.6,Damage=30,Ignore=20,Fling=34}

local M={}
M.__index=M

local event=RS:FindFirstChild('MonsterAbilityEvent')
if not event then event=Instance.new('RemoteEvent');event.Name='MonsterAbilityEvent';event.Parent=RS end

function M.New(ctx)
 -- ctx: Jumpscare, Protection, Audio, retreat(state,now,avoid), routeTo(state,pos,mode), setMode(state,mode),
 --      sees(state,pos), roomAt(pos), closets(), eligible(p) -> root,hum,alive
 local self=setmetatable({ctx=ctx,rng=Random.new()},M)
 if ctx.Jumpscare and ctx.Jumpscare.UseFreeze then ctx.Jumpscare.UseFreeze((M::any).Freeze,(M::any).Unfreeze)end -- one shared freeze
 return self
end

function M.Role(state)
 return ROLE_BY_KIND[state.model:GetAttribute('CreatureKind')]or'Normal'
end

local function character(p)
 local c=p.Character;local r=c and c:FindFirstChild('HumanoidRootPart');local h=c and c:FindFirstChildOfClass('Humanoid')
 return c,r,h
end
local function flat(a,b)return Vector3.new(a.X-b.X,0,a.Z-b.Z).Magnitude end
local function serverNow()return Workspace:GetServerTimeNow()end

-- A player another monster is already busy with, or one this monster agreed to leave alone.
function M:Ignores(state,p)
 if state.hunt and state.hunt.player~=p then return true end -- the pup's Lantern hunts only the player who woke it
 if self:RoleIgnores(state,p)then return true end -- Lonely Mittens: anyone with company; Wind-Up Dancer: anyone she has not spotted
 local until_=state.ignore and state.ignore[p.UserId]
 if until_ and os.clock()<until_ then
  -- Rusher leave-alone (owner 2026-10-25): walking up to it again and again (PesterVisits times) brings it back.
  local leave=state.leave and state.leave[p.UserId]
  if not leave then return true end
  local c=p.Character;local r=c and c:FindFirstChild('HumanoidRootPart')
  local near=r~=nil and state.root~=nil and flat(r.Position,state.root.Position)<leave.range
  if near and not leave.near then leave.visits+=1 end;leave.near=near
  if leave.visits<leave.need then return true end
  state.ignore[p.UserId]=nil;state.leave[p.UserId]=nil
 end
 local by=p:GetAttribute('MonsterAttackedBy')
 return by~=nil and by~=state.model.Name
end
function M:Busy(state)return state.attack~=nil end
local function ignore(state,p,seconds)state.ignore=state.ignore or {};state.ignore[p.UserId]=os.clock()+seconds end

local function pose(state,name)
 state.model:SetAttribute('AttackPose',name);state.model:SetAttribute('AttackPoseAt',serverNow())
end
local function claim(state,p)p:SetAttribute('MonsterAttackedBy',state.model.Name)end
local function unclaim(state,p)if p:GetAttribute('MonsterAttackedBy')==state.model.Name then p:SetAttribute('MonsterAttackedBy',nil)end end

-- Damage that can kill: the last point always goes through the model's own jumpscare.
local CAT_CURSE_DAMAGE=1.15 -- hits 15% harder for the rest of a level where the stray cat was turned to stone
function M:Damage(p,state,amount,cue)
 local _,r,h=character(p)
 local mansion=workspace:FindFirstChild('Mansion');if mansion and mansion:GetAttribute('CatCurse')==true then amount=math.ceil(amount*CAT_CURSE_DAMAGE)end
 -- The van is a safe zone for every ability hit too (owner 2026-10-25: Rusher lunges still landed inside it).
 if not h or not r or h.Health<=0 or self.ctx.Protection.IsProtected(p)or(self.ctx.NearVan and self.ctx.NearVan(r.Position,4))then return false end
 if h.Health-amount<=0 then return self.ctx.Jumpscare.Start(p,state.model,true)end
 Health.Damage(p,amount,'monster:'..tostring(state.model:GetAttribute('CreatureKind'))..':'..tostring(cue))
 p:SetAttribute('LastMonsterHitAt',serverNow());p:SetAttribute('LastMonsterHitBy',state.model:GetAttribute('CreatureKind'))
 event:FireClient(p,'hurt',amount,state.model,cue)
 self.ctx.Audio.Play('MonsterJumpscareHit',r)
 return true
end
function M:Kill(p,state)
 local _,r,h=character(p)
 if not h or h.Health<=0 or self.ctx.Protection.IsProtected(p)or(r and self.ctx.NearVan and self.ctx.NearVan(r.Position,4))then return false end
 return self.ctx.Jumpscare.Start(p,state.model,true)
end

-- Frees anything the player holds (same as the jumpscare does), so a carried player drops their loot.
local function letGo(p)
 local items=SS:FindFirstChild('CursedItemApi');if items then pcall(function()items:Invoke('release',p)end)end
 local recovery=SS:FindFirstChild('RecoveryApi');if recovery then pcall(function()recovery:Invoke('release',p)end)end
 p:SetAttribute('PhysicalGrabActive',nil)
end

-- Player freezes (Carry, Seeker lift, Lead by the hand, Twirl) share ONE counted freeze per character root (owner
-- 2026-10-27, "make sure none of these can glitch"): the root stays anchored while any grab is active and is always
-- unanchored when the last one ends. The old code restored a captured Anchored value, so two overlapping grabs (a
-- Lead plus a Twirl) put the player back to "anchored" forever; an error mid-grab skipped the restore entirely.
-- A failsafe unanchors after MAX_FREEZE seconds whatever happens.
local MAX_FREEZE=30
local freezes=setmetatable({},{__mode='k'}) -- root -> {count=n, autoRotate=bool}
local function freeze(r,h)
 local f=freezes[r];if not f then f={count=0,autoRotate=h.AutoRotate};freezes[r]=f end
 f.count+=1
 r.AssemblyLinearVelocity=Vector3.zero;r.AssemblyAngularVelocity=Vector3.zero;r.Anchored=true;h.AutoRotate=false
 task.delay(MAX_FREEZE,function()
  if freezes[r]==f and f.count>0 then freezes[r]=nil;if r.Parent then r.Anchored=false end;if h.Parent then h.AutoRotate=f.autoRotate end end
 end)
end
local function unfreeze(r,h)
 local f=freezes[r]
 if f then f.count-=1;if f.count>0 then return end;freezes[r]=nil end
 if r and r.Parent then r.Anchored=false end
 if h and h.Parent then h.AutoRotate=if f then f.autoRotate else true end
end
M.Freeze,M.Unfreeze=freeze,unfreeze
local function hold(p,r,h)
 freeze(r,h);p:SetAttribute('MonsterHeld',true)
 return true
end
local function unhold(p,r,h,_)
 if r then unfreeze(r,h)end
 p:SetAttribute('MonsterHeld',nil)
end

-- A spot on the floor near `want`: never inside a wall (falls back to `safe`).
local floorParams=RaycastParams.new();floorParams.FilterType=Enum.RaycastFilterType.Exclude
local function standSpot(want,safe,ignoreList)
 floorParams.FilterDescendantsInstances=ignoreList
 local down=Workspace:Raycast(want+Vector3.new(0,3,0),Vector3.new(0,-8,0),floorParams)
 local side=Workspace:Raycast(safe+Vector3.new(0,1.5,0),(want-safe)*Vector3.new(1,0,1),floorParams)
 if down and not side then return down.Position end
 return safe
end
local function ignoreBodies()
 local list={Workspace:FindFirstChild('RoamingCreatures')}
 for _,q in Players:GetPlayers()do if q.Character then table.insert(list,q.Character)end end
 return list
end

local function alive(p,c)
 local _,r,h=character(p)
 return p.Parent and p.Character==c and r and h and h.Health>0 and p:GetAttribute('RoundDead')~=true,r,h
end

-- Reaction face + pop word (Monsters build 2026-10-27): a short React* face on the selected-face channel (only when no
-- held item owns it) and a pop word on that player's screen (CurseEffectsClient). shake 0..1 = a small camera jolt.
local function react(p,face,secs,text,shake)
 local now=serverNow();local cur=p:GetAttribute('DraftSelectedItem')
 local mine=type(cur)=='string'and cur:sub(1,5)=='React'
 if face and(mine or now>=(p:GetAttribute('DraftSelectedUntil')or 0))then
  if not(cur==face and now<(p:GetAttribute('DraftSelectedUntil')or 0))then p:SetAttribute('DraftSelectedItem',face);p:SetAttribute('DraftSelectedStart',now)end
  p:SetAttribute('DraftSelectedUntil',now+(secs or 1.5))
 end
 if text then p:SetAttribute('ReactPop',text);p:SetAttribute('ReactPopShake',shake or 0);p:SetAttribute('ReactPopAt',now)end
end

-- ===== Rusher: 20 HP hit and run =====
local wallParams=RaycastParams.new();wallParams.FilterType=Enum.RaycastFilterType.Include;wallParams.RespectCanCollide=true
-- Telegraphed lunge: a shriek and a short dash at the player; it only connects if they are still in reach at the end.
local function rusherCatch(self,state,p,now)
 local c,r=character(p);if not r then return false end
 if os.clock()<(state.rushReadyAt or 0)then return true end -- right behind them, waiting to strike again
 state.attack={kind='Rush',player=p,started=now}
 claim(state,p);pose(state,'Lunge');self.ctx.Audio.Play('WraithLunge',state.root);task.delay(.1,function()self.ctx.Audio.Play('MonsterWhoosh',state.root)end)
 local from=r.Position
 task.spawn(function()
  local t0=os.clock();local collision=Workspace.Mansion:FindFirstChild('Collision')
  wallParams.FilterDescendantsInstances={collision}
  -- The dash homes in on the player but can only turn RUSH.Turn rad/s: running away gets caught, a hard last-moment
  -- sidestep can still slip it. It never passes through walls.
  local heading=Vector3.new(from.X-state.root.Position.X,0,from.Z-state.root.Position.Z)
  heading=heading.Magnitude>.01 and heading.Unit or state.root.CFrame.LookVector
  while os.clock()-t0<RUSH.Windup and state.model.Parent do
   local dt=RunService.Heartbeat:Wait()
   local _,r2=character(p)
   if os.clock()-t0>RUSH.Windup*.3 and r2 then
    local to=Vector3.new(r2.Position.X-state.root.Position.X,0,r2.Position.Z-state.root.Position.Z)
    if to.Magnitude>.01 then
     local want=to.Unit;local angle=math.acos(math.clamp(heading:Dot(want),-1,1))
     local turn=math.min(angle,RUSH.Turn*dt)
     if angle>1e-3 then heading=heading:Lerp(want,turn/angle).Unit end
    end
    local step=math.min(RUSH.Dash*dt,math.max(0,to.Magnitude-2.4))
    if step>0 and not Workspace:Raycast(state.root.Position+Vector3.new(0,2.4,0),heading*(step+1),wallParams)then
     state.yaw=math.atan2(-heading.X,-heading.Z);state.root.CFrame=CFrame.new(state.root.Position+heading*step)*CFrame.Angles(0,state.yaw,0)
    end
   end
  end
  local _,r2=character(p)
  local clear=r2 and not Workspace:Raycast(state.root.Position+Vector3.new(0,2.4,0),(r2.Position-(state.root.Position+Vector3.new(0,2.4,0))),wallParams)
  local hit=state.model.Parent and alive(p,c) and r2 and clear and flat(r2.Position,state.root.Position)<RUSH.HitRange and math.abs(r2.Position.Y-state.root.Position.Y)<8
  local leaving=false
  if hit then self.ctx.Audio.Play('MonsterHitThump',state.root);self:Damage(p,state,RUSH.Damage,'slash')
   -- After RUSH.LeaveAfter damage to one player it leaves them alone for RUSH.Leave s and walks off.
   state.rushDealt=state.rushDealt or {};local dealt=(state.rushDealt[p.UserId]or 0)+RUSH.Damage
   if dealt>=RUSH.LeaveAfter then dealt=0;leaving=true;ignore(state,p,RUSH.Leave)
    state.leave=state.leave or {};state.leave[p.UserId]={visits=0,need=RUSH.PesterVisits,range=RUSH.PesterRange,near=true}
    if state.target==p then state.target=nil end;state.mode='Patrol'
   end
   state.rushDealt[p.UserId]=dealt
  end
  unclaim(state,p);state.attack=nil;pose(state,nil)
  if not state.model.Parent then return end
  if hit then
   -- Hit and hop: a quick bound backwards, then it comes straight back for them (it used to wander off for 12 s).
   state.rushReadyAt=os.clock()+RUSH.Cooldown -- keeps chasing (no ignore), just can't strike again yet
   local _,r3=character(p)
   local back=r3 and Vector3.new(state.root.Position.X-r3.Position.X,0,state.root.Position.Z-r3.Position.Z)
   if back and back.Magnitude>.1 then
    back=back.Unit;local t1=os.clock()
    while os.clock()-t1<(leaving and 1.1 or .35)and state.model.Parent do
     local dt=RunService.Heartbeat:Wait();local step=18*dt
     if Workspace:Raycast(state.root.Position+Vector3.new(0,2.4,0),back*(step+1),wallParams)then break end
     state.root.CFrame=CFrame.new(state.root.Position+back*step)*CFrame.Angles(0,state.yaw,0)
    end
   end
   state.points=nil;state.pauseUntil=os.clock()+.2
  else state.pauseUntil=os.clock()+.7 end -- dodged: it stumbles, then keeps coming
 end)
 return true
end

-- ===== Carrier: pick up, hold, set down, 35 HP =====
local function carrierGrab(self,state,p,now)
 local c,r,h=character(p);if not r then return false end
 state.attack={kind='Carry',player=p,started=now}
 claim(state,p);letGo(p)
 local saved=hold(p,r,h)
 local catchSpot=r.Position
 local monsterRoot=state.root
 pose(state,'Carry')
 state.model:SetAttribute('Walking',false)
 -- Face the player while lifting.
 local look=Vector3.new(catchSpot.X-monsterRoot.Position.X,0,catchSpot.Z-monsterRoot.Position.Z)
 if look.Magnitude>.1 then state.yaw=math.atan2(-look.X,-look.Z);monsterRoot.CFrame=CFrame.new(monsterRoot.Position)*CFrame.Angles(0,state.yaw,0)end
 local startCF=r.CFrame
 task.spawn(function()
  local t0=os.clock();local staggered=false
  while true do
   local dt=RunService.Heartbeat:Wait()
   local ok=alive(p,c)
   if not ok or not state.model.Parent or not monsterRoot.Parent then break end
   if (state.model:GetAttribute('StaggerAt')or 0)>t0 then staggered=true;break end
   local age=os.clock()-t0
   if age>CARRY.Hold then break end
   -- Lift (ease), then a gentle rabbit dangle: bob, sway and a slow inspecting turn.
   local lift=math.clamp(age/CARRY.Lift,0,1);lift=lift*lift*(3-2*lift)
   local held=monsterRoot.CFrame*CARRY.Offset*CFrame.Angles(0,math.pi+math.sin(age*1.7)*.45,0)
   held=held*CFrame.new(0,math.sin(age*5.2)*.18,0)*CFrame.Angles(math.sin(age*3.1)*.12,0,math.sin(age*4.3)*.16)
   r.CFrame=startCF:Lerp(held,lift)
  end
  -- Set down where they were caught (a known walkable spot), facing the monster.
  if alive(p,c)then
   local spot=standSpot(catchSpot,catchSpot,ignoreBodies())
   local face=monsterRoot.Parent and monsterRoot.Position or spot+Vector3.new(0,0,-1)
   r.CFrame=CFrame.lookAt(Vector3.new(spot.X,catchSpot.Y,spot.Z),Vector3.new(face.X,catchSpot.Y,face.Z))
  end
  if not staggered and state.model.Parent and alive(p,c)then
   pose(state,'Swing');self.ctx.Audio.Play('MonsterWhoosh',state.root)
   task.wait(.28)
   if alive(p,c)then
    unhold(p,r,h,saved)
    self.ctx.Audio.Play('MonsterHitThump',r)
    if self:Damage(p,state,CARRY.Damage,'swat')then
     local away=Vector3.new(r.Position.X-monsterRoot.Position.X,0,r.Position.Z-monsterRoot.Position.Z)
     event:FireClient(p,'knock',away.Magnitude>.1 and away.Unit or Vector3.new(0,0,1),28,18)
    end
   end
  end
  unhold(p,r,h,saved)
  unclaim(state,p);ignore(state,p,CARRY.Ignore)
  -- Tip Bell (MonsterBatch, Monsters build 2026-10-27): the first finished carry of each Bellhop per level leaves a golden
  -- bell where the player was caught (state is per spawn, so it resets every level). A stagger means no tip.
  if not staggered and not state.tipped and state.model.Parent then
   state.tipped=true
   local spawner=SS:FindFirstChild('SpawnGearItem')
   if spawner then pcall(function()
    local spot=standSpot(catchSpot,catchSpot,ignoreBodies())
    local bell=spawner:Invoke('TipBell',CFrame.new(spot+Vector3.new(0,.7,0)))
    if bell then
     local rr=RS:FindFirstChild('RecoveryRound');local level=rr and rr:GetAttribute('Round')or 1
     local value=math.floor(110*(1+.12*(level-1)));bell:SetAttribute('Value',value);bell:SetAttribute('LootValue',value)
     self.ctx.Audio.Play('BellhopBell',bell)
     if alive(p,c)then react(p,'ReactDizzy',2,'The Bellhop left you a TIP!',.4)end
    end
   end)end
  end
  state.attack=nil;pose(state,nil)
  if state.model.Parent then self.ctx.retreat(state,os.clock(),catchSpot)end
 end)
 return true
end

-- The reach is telegraphed (arms out, bell ring); it only grabs a player still within reach when the hands close.
local function carrierCatch(self,state,p,now)
 local c,r=character(p);if not r then return false end
 state.attack={kind='Reach',player=p,started=now}
 claim(state,p);pose(state,'Reach');state.model:SetAttribute('Walking',false)
 self.ctx.Audio.Play('BellhopBell',state.root);self.ctx.Audio.Play('MonsterWhoosh',state.root)
 local look=Vector3.new(r.Position.X-state.root.Position.X,0,r.Position.Z-state.root.Position.Z)
 if look.Magnitude>.1 then state.yaw=math.atan2(-look.X,-look.Z);state.root.CFrame=CFrame.new(state.root.Position)*CFrame.Angles(0,state.yaw,0)end
 task.spawn(function()
  -- It keeps striding at the player through the reach (chase speed), so a straight sprint can't open the gap;
  -- a sidestep through the arms' swing still can.
  local t0=os.clock();local collision=Workspace.Mansion:FindFirstChild('Collision');wallParams.FilterDescendantsInstances={collision}
  while os.clock()-t0<CARRY.Windup and state.model.Parent do
   local dt=RunService.Heartbeat:Wait()
   local _,rr=character(p)
   if rr then
    local to=Vector3.new(rr.Position.X-state.root.Position.X,0,rr.Position.Z-state.root.Position.Z)
    local step=math.min((state.easy and CARRY.EasyChaseSpeed or CARRY.ChaseSpeed)*dt,math.max(0,to.Magnitude-3))
    if step>0 and not Workspace:Raycast(state.root.Position+Vector3.new(0,2.4,0),to.Unit*(step+1),wallParams)then
     state.yaw=math.atan2(-to.X,-to.Z);state.root.CFrame=CFrame.new(state.root.Position+to.Unit*step)*CFrame.Angles(0,state.yaw,0)
    end
   end
  end
  local _,r2=character(p)
  if state.model.Parent and alive(p,c)and r2 and flat(r2.Position,state.root.Position)<CARRY.GrabRange and math.abs(r2.Position.Y-state.root.Position.Y)<8 and self.ctx.sees(state,r2.Position)
   and not self.ctx.Protection.IsProtected(p)then
   self.ctx.Audio.Play('MonsterGrab',state.root)
   carrierGrab(self,state,p,os.clock())
  else
   unclaim(state,p);state.attack=nil;pose(state,nil);state.pauseUntil=os.clock()+.3
  end
 end)
 return true
end

-- ===== Laser: spinning beam, kick when close =====
local beamParams=RaycastParams.new();beamParams.FilterType=Enum.RaycastFilterType.Include;beamParams.RespectCanCollide=true
-- Closets block the beam too (their shells are not collidable, so they need their own ray): a player inside one, or
-- standing behind one, is never hit through it (owner, 2026-10-22).
local closetParams=RaycastParams.new();closetParams.FilterType=Enum.RaycastFilterType.Include;closetParams.RespectCanCollide=false
local closetList,closetListAt={},-math.huge
local function closetBlockers()
 if os.clock()-closetListAt>5 then
  closetListAt=os.clock();closetList={}
  local mansion=Workspace:FindFirstChild('Mansion')
  local folder=mansion and mansion:FindFirstChild('Closets');if folder then table.insert(closetList,folder)end
  local inter=mansion and mansion:FindFirstChild('Interactive')
  if inter then for _,d in inter:GetChildren()do if d:GetAttribute('Closet')then table.insert(closetList,d)end end end
 end
 return closetList
end
local function beamLength(origin,dir,collision)
 beamParams.FilterDescendantsInstances={collision}
 local hit=Workspace:Raycast(origin,dir*LASER.Range,beamParams)
 local len=hit and (hit.Position-origin).Magnitude or LASER.Range
 closetParams.FilterDescendantsInstances=closetBlockers()
 local box=Workspace:Raycast(origin,dir*len,closetParams)
 return box and (box.Position-origin).Magnitude or len
end
local function angleOf(v)return math.atan2(v.X,-v.Z)end -- 0 = -Z, increasing clockwise seen from above
local function dirOf(a)return Vector3.new(math.sin(a),0,-math.cos(a))end
local function wrap(a)return (a+math.pi)%(2*math.pi)-math.pi end
local function laserFire(self,state,target,now)
 local root=state.root;local model=state.model
 state.attack={kind='Laser',started=now}
 model:SetAttribute('Walking',false)
 local _,tr=character(target)
 local toward=tr and angleOf(tr.Position-root.Position)or 0
 local spin=self.rng:NextNumber()<.5 and 1 or -1
 local yaw0=toward-spin*LASER.LeadAngle -- never aimed: it starts well off the player and sweeps round
 local floorY=root.Position.Y
 model:SetAttribute('LaserHeight',floorY+LASER.Height);model:SetAttribute('LaserYaw0',yaw0);model:SetAttribute('LaserSpin',spin*LASER.Spin)
 model:SetAttribute('LaserRange',LASER.Range);model:SetAttribute('LaserStart',serverNow()+LASER.Charge);model:SetAttribute('LaserDuration',LASER.Fire)
 model:SetAttribute('LaserState','Charge');pose(state,'Laser')
 self.ctx.Audio.Play('NeonRush',root)
 local collision=Workspace.Mansion:FindFirstChild('Collision')
 task.spawn(function()
  task.wait(LASER.Charge)
  if not model.Parent then return end
  model:SetAttribute('LaserState','Fire');self.ctx.Audio.Play('HypnoShot',root)
  local t0=os.clock();local prev=yaw0
  while model.Parent and os.clock()-t0<LASER.Fire do
   RunService.Heartbeat:Wait()
   local cur=yaw0+spin*LASER.Spin*(os.clock()-t0)
   local origin=Vector3.new(root.Position.X,floorY+LASER.Height,root.Position.Z)
   for _,p in Players:GetPlayers()do
    local _,r,h=character(p)
    if r and h and h.Health>0 and p:GetAttribute('MissionActive')==true and not p:GetAttribute('RoundDead')
     and not p:GetAttribute('Crouching')and not self.ctx.Protection.IsProtected(p)and math.abs(r.Position.Y-2.95-floorY)<6.5 then
     local d=flat(r.Position,origin)
     if d>1 and d<=LASER.Range then
      local a=angleOf(r.Position-origin)
      local tol=math.atan2(LASER.Width,d)
      -- Swept test between last frame's angle and this one, so fast spins can't skip over a player.
      local lo,hi=math.min(prev,cur),math.max(prev,cur)
      local rel=wrap(a-lo)
      if rel<0 then rel+=2*math.pi end
      local span=hi-lo
      local inside=rel<=span+tol or rel>=2*math.pi-tol
      if inside and d<=beamLength(origin,dirOf(a),collision)+.5 then self:Kill(p,state)end
     end
    end
   end
   prev=cur
  end
  model:SetAttribute('LaserState',nil);pose(state,nil)
  state.attack=nil;state.laserReady=os.clock()+LASER.Cooldown
 end)
end
local function laserStep(self,state,now)
 -- Kick anyone standing too close (any time, even mid-laser).
 state.kicked=state.kicked or {}
 for _,p in Players:GetPlayers()do
  local _,r,h=character(p)
  if r and h and h.Health>0 and p:GetAttribute('MissionActive')==true and not p:GetAttribute('RoundDead')and not self.ctx.Protection.IsProtected(p)
   and now>(state.kicked[p.UserId]or 0)and flat(r.Position,state.root.Position)<LASER.KickRange and math.abs(r.Position.Y-2.95-state.root.Position.Y)<6.5
   and not (p:GetAttribute('MonsterAttackedBy')and p:GetAttribute('MonsterAttackedBy')~=state.model.Name)then
   state.kicked[p.UserId]=now+LASER.KickCooldown
   -- Telegraphed: the leg cocks back first; it only lands on someone still in reach.
   if not state.attack then pose(state,'Kick');task.delay(.6,function()if state.model.Parent and not state.attack and state.model:GetAttribute('AttackPose')=='Kick'then pose(state,nil)end end)end
   self.ctx.Audio.Play('MonsterWhoosh',state.root)
   local c=p.Character
   task.delay(.3,function()
    local _,r2=character(p)
    if state.model.Parent and alive(p,c)and r2 and flat(r2.Position,state.root.Position)<LASER.KickRange+1 and math.abs(r2.Position.Y-2.95-state.root.Position.Y)<6.5 then
     if self:Damage(p,state,LASER.KickDamage,'kick')then
      self.ctx.Audio.Play('NeonKickClang',r2);self.ctx.Audio.Play('MonsterHitThump',r2)
      local away=Vector3.new(r2.Position.X-state.root.Position.X,0,r2.Position.Z-state.root.Position.Z)
      event:FireClient(p,'knock',away.Magnitude>.1 and away.Unit or Vector3.new(0,0,1),62,26)
     end
    end
   end)
  end
 end
 if state.attack or now<(state.laserReady or 0)or now<(state.calmUntil or 0)then return end
 -- Fire when any eligible player is in sight and in range (it never aims; the beam just spins).
 for _,p in Players:GetPlayers()do
  local r,_,ok=self.ctx.eligible(p)
  if ok and r and not self:Ignores(state,p)and not p:GetAttribute('Hiding')and not p:GetAttribute('ClosetState')
   and flat(r.Position,state.root.Position)<LASER.TriggerRange and math.abs(r.Position.Y-2.95-state.root.Position.Y)<6.5 and self.ctx.sees(state,r.Position)then
   laserFire(self,state,p,now);return
  end
 end
end

-- ===== Seeker: pulls players out of closets, then 5 seconds to run =====
-- The Lantern's hold: it lifts the player gently, sets them down in front of it and gives them five seconds to run.
-- Still close when the count ends = its kill; a real run gets away 75% of the time. (Runs inside the caller's task.)
local function seekerHold(self,state,p,c,r,h)
  -- Gently lifted out and set down in front of it.
  local saved=hold(p,r,h)
  pose(state,'Carry');self.ctx.Audio.Play('MonsterGrab',state.root);self.ctx.Audio.Play('LanternLift',state.root)
  local from=r.CFrame;local mroot=state.root
  local look=Vector3.new(r.Position.X-mroot.Position.X,0,r.Position.Z-mroot.Position.Z)
  if look.Magnitude>.1 then state.yaw=math.atan2(-look.X,-look.Z);mroot.CFrame=CFrame.new(mroot.Position)*CFrame.Angles(0,state.yaw,0)end
  local downAt=standSpot((mroot.CFrame*CFrame.new(0,0,-4.5)).Position+Vector3.new(0,0,0),Vector3.new(from.X,mroot.Position.Y,from.Z),ignoreBodies())
  local t0=os.clock()
  while alive(p,c)and state.model.Parent and os.clock()-t0<1.6 do
   RunService.Heartbeat:Wait()
   local a=(os.clock()-t0)/1.6
   local up=math.sin(math.clamp(a,0,1)*math.pi)
   local pos=Vector3.new(from.X,from.Y,from.Z):Lerp(Vector3.new(downAt.X,from.Y,downAt.Z),math.clamp(a*1.2,0,1))+Vector3.new(0,up*2.2,0)
   r.CFrame=CFrame.lookAt(pos,Vector3.new(mroot.Position.X,pos.Y,mroot.Position.Z))*CFrame.Angles(math.sin(a*9)*.08*up,0,0)
  end
  unhold(p,r,h,saved)
  if not alive(p,c)or not state.model.Parent then unclaim(state,p);state.attack=nil;pose(state,nil);return end
  -- Five seconds to run. It stands and stares, the lantern burning brighter.
  pose(state,'Stare')
  local deadline=serverNow()+SEEK.Countdown
  p:SetAttribute('RunWarningUntil',deadline);state.model:SetAttribute('CountdownUntil',deadline)
  event:FireClient(p,'run',deadline,state.model)
  self.ctx.Audio.Play('LanternNotice',state.root)
  unclaim(state,p) -- teammates may help; other monsters still may not grab them for a moment
  p:SetAttribute('MonsterAttackedBy',state.model.Name)
  while serverNow()<deadline and alive(p,c)and state.model.Parent do task.wait(.05)end
  p:SetAttribute('RunWarningUntil',nil);state.model:SetAttribute('CountdownUntil',nil)
  unclaim(state,p)
  state.attack=nil;pose(state,nil)
  if not alive(p,c)or not state.model.Parent then return end
  local _,r2=character(p)
  if r2 and flat(r2.Position,state.root.Position)<SEEK.SafeDistance and math.abs(r2.Position.Y-state.root.Position.Y)<12 then
   self.ctx.Audio.Play('LanternRush',state.root);if state.hunt then state.model:SetAttribute('HuntResult','caught')end;self:Kill(p,state)
  elseif state.hunt then -- the pup's Lantern: a real run always escapes; CloseUpChoices drops its $120 prize
   state.model:SetAttribute('HuntResult','escaped');event:FireClient(p,'escaped')
  elseif self.rng:NextNumber()<SEEK.EscapeChance then
   ignore(state,p,SEEK.Ignore)
   event:FireClient(p,'escaped')
   self.ctx.retreat(state,os.clock(),r2 and r2.Position)
  else
   -- The 25%: it comes after them (outlined while it hunts them down).
   local model=state.model
   model:SetAttribute('Mad',true);self.ctx.Audio.Play('LanternRush',state.root)
   if r2 then self.ctx.routeTo(state,r2.Position,'Chase')end
   task.delay(6,function()if model.Parent then model:SetAttribute('Mad',nil)end end)
  end
  state.seekReady=os.clock()+SEEK.Cooldown
end
local function seekerExtract(self,state,p,closet)
 local c,r,h=character(p);if not r then return end
 local now=os.clock()
 state.attack={kind='Extract',player=p,started=now}
 claim(state,p);state.model:SetAttribute('Walking',false);pose(state,'Reach')
 local api=game.ServerScriptService:FindFirstChild('InteractServer');api=api and api:FindFirstChild('MonsterClosetApi')
 local pulled=api and api:Invoke(closet,state.root)
 task.spawn(function()
  -- Wait for the closet to let them go (doors open, they step out).
  local t=os.clock()
  while alive(p,c)and p:GetAttribute('ClosetState')~=nil and os.clock()-t<3 do task.wait(.05)end
  if not pulled or not alive(p,c)or p:GetAttribute('ClosetState')~=nil then unclaim(state,p);state.attack=nil;pose(state,nil);return end
  seekerHold(self,state,p,c,r,h)
 end)
end
-- Caught in the open during a chase: the same reach-and-lift, telegraphed (arms out, lantern flare) and dodgeable, then
-- the five-second RUN. The Lantern never kills on contact: only the Collar Crawler does (owner, 2026-10-22).
local function seekerGrab(self,state,p,now)
 local c,r,h=character(p);if not r then return false end
 state.attack={kind='Extract',player=p,started=now}
 claim(state,p);state.model:SetAttribute('Walking',false);pose(state,'Reach')
 self.ctx.Audio.Play('LanternNotice',state.root);self.ctx.Audio.Play('MonsterWhoosh',state.root)
 local look=Vector3.new(r.Position.X-state.root.Position.X,0,r.Position.Z-state.root.Position.Z)
 if look.Magnitude>.1 then state.yaw=math.atan2(-look.X,-look.Z);state.root.CFrame=CFrame.new(state.root.Position)*CFrame.Angles(0,state.yaw,0)end
 task.spawn(function()
  -- Like the Bellhop: it keeps striding at the player through the quick reach, so a straight sprint can't open the gap.
  local t0=os.clock();local collision=Workspace.Mansion:FindFirstChild('Collision');wallParams.FilterDescendantsInstances={collision}
  while os.clock()-t0<SEEK.Windup and state.model.Parent do
   local dt=RunService.Heartbeat:Wait()
   local _,rr=character(p)
   if rr then
    local to=Vector3.new(rr.Position.X-state.root.Position.X,0,rr.Position.Z-state.root.Position.Z)
    local step=math.min((state.easy and SEEK.EasyChaseSpeed or SEEK.ChaseSpeed)*dt,math.max(0,to.Magnitude-3))
    if step>0 and not Workspace:Raycast(state.root.Position+Vector3.new(0,2.4,0),to.Unit*(step+1),wallParams)then
     state.yaw=math.atan2(-to.X,-to.Z);state.root.CFrame=CFrame.new(state.root.Position+to.Unit*step)*CFrame.Angles(0,state.yaw,0)
    end
   end
  end
  local _,r2=character(p)
  if not(state.model.Parent and alive(p,c)and r2 and flat(r2.Position,state.root.Position)<SEEK.GrabRange and math.abs(r2.Position.Y-state.root.Position.Y)<8
   and self.ctx.sees(state,r2.Position)and not self.ctx.Protection.IsProtected(p))then
   unclaim(state,p);state.attack=nil;pose(state,nil);state.pauseUntil=os.clock()+.3;return
  end
  letGo(p)
  seekerHold(self,state,p,c,r2,h)
 end)
 return true
end
local function seekerStep(self,state,now)
 if state.attack or now<(state.seekReady or 0)or now<(state.calmUntil or 0)then return end
 if now<(state.seekScanAt or 0)then return end
 state.seekScanAt=now+.35
 if state.model:GetAttribute('Seeking') and now>(state.seekingUntil or 0) then state.model:SetAttribute('Seeking',nil)end
 local closets=self.ctx.closets()
 for _,p in Players:GetPlayers()do
  local _,r,h=character(p)
  if r and h and h.Health>0 and p:GetAttribute('ClosetState')=='Hidden'and p:GetAttribute('MissionActive')==true and not self:Ignores(state,p)
   and p:GetAttribute('AdminGod')~=true and not(self.ctx.Untouchable and self.ctx.Untouchable())and math.abs(r.Position.Y-state.root.Position.Y)<10 and flat(r.Position,state.root.Position)<SEEK.Sense then
   local closet,best
   for _,c in closets do if c:IsA('BasePart')then local d=(c.Position-r.Position).Magnitude;if not best or d<best then closet,best=c,d end end end
   if closet and best<8 then
    if flat(state.root.Position,closet.Position)<SEEK.Reach then seekerExtract(self,state,p,closet);return end
    -- Walk straight for the closet's doors.
    local front=closet.CFrame*CFrame.new(0,0,-4)
    if not state.seekGoal or (state.seekGoal-front.Position).Magnitude>1 or not state.points then
     state.seekGoal=front.Position
     if self.ctx.routeTo(state,Vector3.new(front.X,state.root.Position.Y,front.Z),'Chase')then state.model:SetAttribute('Seeking',p.Name)end
    end
    state.seekingUntil=now+1.2
    return
   end
  end
 end
end

-- ===== Holder: Lonely Mittens (Monsters build 2026-10-27) =====
function M:Accompanied(p)
 local _,r=character(p);if not r then return false end
 if self.ctx.NearVan and self.ctx.NearVan(r.Position,0)then return true end
 local cart=self.ctx.cart and self.ctx.cart()
 if cart then
  if cart:GetAttribute('HeldBy')==p.UserId then return true end
  local cp=cart.PrimaryPart.Position
  if flat(cp,r.Position)<HOLD.CartCompany and math.abs(cp.Y-r.Position.Y)<8 then return true end
 end
 for _,q in Players:GetPlayers()do
  if q~=p and q:GetAttribute('MissionActive')==true and not q:GetAttribute('RoundDead')and not q:GetAttribute('HandHeldBy')then
   local _,qr,qh=character(q)
   if qr and qh and qh.Health>0 and flat(qr.Position,r.Position)<HOLD.Company and math.abs(qr.Position.Y-r.Position.Y)<8 then return true end
  end
 end
 return false
end
-- A living teammate (not held themselves) who has reached the held player.
local function rescuer(p,r)
 for _,q in Players:GetPlayers()do
  if q~=p and q:GetAttribute('MissionActive')==true and not q:GetAttribute('RoundDead')and not q:GetAttribute('HandHeldBy')then
   local _,qr,qh=character(q)
   if qr and qh and qh.Health>0 and flat(qr.Position,r.Position)<HOLD.Rescue and math.abs(qr.Position.Y-r.Position.Y)<8 then return q end
  end
 end
 return nil
end
-- The way out: away from the cart and every teammate (closer ones push harder), smoothed with the previous heading.
local function awayFromCompany(self,p,pos,prev)
 local push=Vector3.zero
 local function from(q)local d=Vector3.new(pos.X-q.X,0,pos.Z-q.Z);local m=d.Magnitude;if m>.1 then push+=d.Unit/math.max(m,8)end end
 local cart=self.ctx.cart and self.ctx.cart();if cart then from(cart.PrimaryPart.Position)end
 for _,q in Players:GetPlayers()do if q~=p then local _,qr=character(q);if qr then from(qr.Position)end end end
 if prev then push+=prev*.08 end
 if push.Magnitude<1e-3 then return prev or Vector3.new(self.rng:NextNumber(-1,1),0,self.rng:NextNumber(-1,1)+.01).Unit end
 return push.Unit
end
-- Led by the hand: anchored at its side while it walks off; a teammate's touch frees you, otherwise a squeeze.
local function holderLead(self,state,p,c,r,h)
 state.attack={kind='Lead',player=p,started=os.clock()}
 letGo(p)
 freeze(r,h)
 local root=state.root;local lift=r.Position.Y-root.Position.Y;local caughtAt=r.Position
 p:SetAttribute('HandHeldBy',state.model.Name);p:SetAttribute('HandHeldUntil',serverNow()+HOLD.Lead)
 pose(state,'Lead');self.ctx.Audio.Play('MonsterGrab',root)
 react(p,'ReactSob',HOLD.Lead+.4,nil) -- a sad little face while it walks you off
 event:FireClient(p,'handheld',serverNow()+HOLD.Lead,state.model)
 local collision=Workspace.Mansion:FindFirstChild('Collision')
 local heading,turnAt,freedBy,broken=nil,0,nil,false
 local t0=os.clock()
 while os.clock()-t0<HOLD.Lead do
  local dt=RunService.Heartbeat:Wait()
  if not alive(p,c)or not state.model.Parent or not root.Parent then broken=true;break end
  -- Raw protection (no omen side effect) and the van zone end it at once.
  if (self.ctx.Sighted or self.ctx.Protection).IsProtected(p)or(self.ctx.NearVan and self.ctx.NearVan(root.Position,4))then broken=true;break end
  freedBy=rescuer(p,r);if freedBy then break end
  if os.clock()>turnAt then turnAt=os.clock()+.5;heading=awayFromCompany(self,p,root.Position,heading)end
  wallParams.FilterDescendantsInstances={collision}
  -- The held player walks on its right, or its left when a wall is there.
  local sideSign=Workspace:Raycast(root.Position+Vector3.new(0,2.4,0),root.CFrame.RightVector*(HOLD.Side+.8),wallParams)and -1 or 1
  local step=HOLD.LeadSpeed*dt;local moved=false
  for _,a in {0,.7,-.7,1.4,-1.4}do
   local dir=CFrame.Angles(0,a,0):VectorToWorldSpace(heading)
   local beside=CFrame.lookAt(Vector3.zero,dir).RightVector*HOLD.Side*sideSign
   if not Workspace:Raycast(root.Position+Vector3.new(0,2.4,0),dir*(step+1.5),wallParams)
    and not Workspace:Raycast(root.Position+beside+Vector3.new(0,2.4,0),dir*(step+1.5),wallParams)then
    state.yaw=math.atan2(-dir.X,-dir.Z);root.CFrame=CFrame.new(root.Position+dir*step)*CFrame.Angles(0,state.yaw,0);moved=true;break
   end
  end
  state.model:SetAttribute('Walking',moved);state.model:SetAttribute('MoveSpeed',moved and HOLD.LeadSpeed or 0)
  r.CFrame=root.CFrame*CFrame.new(HOLD.Side*sideSign,lift+math.abs(math.sin(os.clock()*7))*.12,.2)
 end
 state.model:SetAttribute('Walking',false)
 p:SetAttribute('HandHeldBy',nil);p:SetAttribute('HandHeldUntil',nil)
 if alive(p,c)and root.Parent then
  local spot=standSpot(r.Position,Vector3.new(root.Position.X,r.Position.Y,root.Position.Z),ignoreBodies())
  r.CFrame=CFrame.lookAt(Vector3.new(spot.X,root.Position.Y+lift,spot.Z),Vector3.new(root.Position.X,root.Position.Y+lift,root.Position.Z))
 end
 unfreeze(r,h)
 unclaim(state,p)
 if freedBy then
  -- A teammate reached you: it lets go, startled, and leaves you both alone.
  pose(state,'Flinch');self.ctx.Audio.Play('MonsterWhoosh',root)
  ignore(state,p,HOLD.RescueIgnore);ignore(state,freedBy,HOLD.RescueIgnore)
  react(p,'ReactGrin',1.6,nil);react(freedBy,'ReactGrin',1.6,nil)
  event:FireClient(p,'freed',freedBy.Name);event:FireClient(freedBy,'rescuer',p.Name)
  task.wait(.5)
 elseif not broken and alive(p,c)and state.model.Parent then
  -- Nobody came: one lonely squeeze, then it lets go where it stopped.
  pose(state,'Hug');task.wait(.35)
  if alive(p,c)and state.model.Parent then self.ctx.Audio.Play('MonsterHitThump',r);react(p,'ReactWince',1,nil);self:Damage(p,state,HOLD.Damage,'squeeze')end
  ignore(state,p,HOLD.Ignore)
 else ignore(state,p,8)end
 state.attack=nil;pose(state,nil)
 if state.model.Parent then self.ctx.forget(state,p);self.ctx.retreat(state,os.clock(),caughtAt)end
end
-- Telegraphed reach (both mittens out); it only takes a hand that is still in reach, in sight and still alone.
local function holderCatch(self,state,p,now)
 local c,r=character(p);if not r then return false end
 state.attack={kind='Reach',player=p,started=now}
 claim(state,p);pose(state,'Reach');state.model:SetAttribute('Walking',false)
 self.ctx.Audio.Play('MonsterWhoosh',state.root)
 local look=Vector3.new(r.Position.X-state.root.Position.X,0,r.Position.Z-state.root.Position.Z)
 if look.Magnitude>.1 then state.yaw=math.atan2(-look.X,-look.Z);state.root.CFrame=CFrame.new(state.root.Position)*CFrame.Angles(0,state.yaw,0)end
 task.spawn(function()
  local t0=os.clock();local collision=Workspace.Mansion:FindFirstChild('Collision')
  while os.clock()-t0<HOLD.Windup and state.model.Parent do
   local dt=RunService.Heartbeat:Wait()
   wallParams.FilterDescendantsInstances={collision}
   local _,rr=character(p)
   if rr then
    local to=Vector3.new(rr.Position.X-state.root.Position.X,0,rr.Position.Z-state.root.Position.Z)
    local step=math.min((state.easy and HOLD.EasyChaseSpeed or HOLD.ChaseSpeed)*dt,math.max(0,to.Magnitude-3))
    if step>0 and not Workspace:Raycast(state.root.Position+Vector3.new(0,2.4,0),to.Unit*(step+1),wallParams)then
     state.yaw=math.atan2(-to.X,-to.Z);state.root.CFrame=CFrame.new(state.root.Position+to.Unit*step)*CFrame.Angles(0,state.yaw,0)
    end
   end
  end
  local _,r2,h2=character(p)
  if state.model.Parent and alive(p,c)and r2 and h2 and flat(r2.Position,state.root.Position)<HOLD.GrabRange and math.abs(r2.Position.Y-state.root.Position.Y)<8
   and self.ctx.sees(state,r2.Position)and not self.ctx.Protection.IsProtected(p)and not self:Accompanied(p)then
   holderLead(self,state,p,c,r2,h2)
  else
   unclaim(state,p);state.attack=nil;pose(state,nil);state.pauseUntil=os.clock()+.3
  end
 end)
 return true
end
-- 4 Hz: the lonely-chill lease on every lone player near it, a notice cue on a new lonely target, and letting go of a
-- target who found company.
local function holderStep(self,state,now)
 if state.attack or now<(state.holdScanAt or 0)then return end
 state.holdScanAt=now+.25
 for _,p in Players:GetPlayers()do
  local r,_,ok=self.ctx.eligible(p)
  if ok and r and flat(r.Position,state.root.Position)<HOLD.ChillRange and math.abs(r.Position.Y-state.root.Position.Y)<12 and not self:Accompanied(p)then
   p:SetAttribute('LonelyUntil',serverNow()+.6)
  end
 end
 local t=state.target
 if typeof(t)=='Instance'and t:IsA('Player')and state.holdNoticed~=t then state.holdNoticed=t;self.ctx.Audio.Play('MonsterNotice',state.root)end
 if typeof(t)~='Instance'then state.holdNoticed=nil end
 if typeof(t)=='Instance'and t:IsA('Player')and self:Accompanied(t)then
  -- Its lonely one found company: it lets them be, gives a little wave and waits at a distance for someone to stray.
  local _,tr=character(t)
  self.ctx.forget(state,t);state.holdNoticed=nil
  pose(state,'Wave');task.delay(1.2,function()if state.model.Parent and state.model:GetAttribute('AttackPose')=='Wave'then pose(state,nil)end end)
  state.lurkUntil=now+HOLD.Lurk;state.model:SetAttribute('Lurking',true)
  if tr then
   local away=Vector3.new(state.root.Position.X-tr.Position.X,0,state.root.Position.Z-tr.Position.Z)
   away=away.Magnitude>.1 and away.Unit or -state.root.CFrame.LookVector
   self.ctx.routeTo(state,tr.Position+away*HOLD.LurkDistance,'Stalk')
  end
 elseif state.lurkUntil and now>state.lurkUntil then state.lurkUntil=nil;state.model:SetAttribute('Lurking',nil)end
end

-- ===== Statue: Wind-Up Dancer (Monsters build 2026-10-27) =====
local function danceLength(self,state)
 local range=(state.level or 1)>=DANCE.HardLevel and DANCE.DanceHard or DANCE.Dance
 return self.rng:NextNumber(range[1],range[2])
end
-- The cycle is published for the clients (tune pitch, key spin, FREEZE label) as DanceState + DanceUntil (server time).
local function setDance(state,phase,seconds)
 local d=state.dance;d.phase=phase;d.untilT=os.clock()+seconds
 state.model:SetAttribute('DanceState',phase);state.model:SetAttribute('DanceUntil',serverNow()+seconds)
end
local function spot(self,state,p,now,why)
 state.spotted=state.spotted or {}
 local fresh=not(state.spotted[p.UserId]and now<state.spotted[p.UserId])
 state.spotted[p.UserId]=now+DANCE.Hunt
 if fresh then
  event:FireClient(p,'spotted',state.model,why)
  self.ctx.Audio.Play('MonsterNotice',state.root)
  react(p,'ReactStartle',1.8,nil)
  state.model:SetAttribute('Mad',true);state.model:SetAttribute('SpottedAt',serverNow())
 end
end
-- Caught: she takes both hands and spins you twice round her, faster and faster, sets you down where you were caught and
-- lets go: Damage, a fling and a dizzy camera. Whatever you held was dropped at the grab.
local function statueTwirl(self,state,p,c,r,h)
 state.attack={kind='Twirl',player=p,started=os.clock()}
 freeze(r,h)
 pose(state,'Twirl');self.ctx.Audio.Play('MonsterGrab',state.root)
 react(p,'ReactDizzy',DANCE.Twirl+2.5,nil)
 event:FireClient(p,'twirl',serverNow()+DANCE.Twirl,state.model)
 local root=state.root;local center=root.Position;local lift=r.Position.Y-center.Y;local caughtAt=r.Position
 local start=math.atan2(r.Position.X-center.X,r.Position.Z-center.Z)
 local t0=os.clock()
 while alive(p,c)and state.model.Parent and root.Parent and os.clock()-t0<DANCE.Twirl do
  RunService.Heartbeat:Wait()
  local k=(os.clock()-t0)/DANCE.Twirl;local a=start+k*k*4*math.pi
  local pos=Vector3.new(center.X+math.sin(a)*DANCE.Radius,center.Y+lift+math.sin(k*math.pi)*.8,center.Z+math.cos(a)*DANCE.Radius)
  r.CFrame=CFrame.lookAt(pos,Vector3.new(center.X,pos.Y,center.Z))
  state.yaw=math.atan2(-(pos.X-center.X),-(pos.Z-center.Z));root.CFrame=CFrame.new(center)*CFrame.Angles(0,state.yaw,0)
 end
 if alive(p,c)then
  -- Set down on a walkable floor spot (never inside a wall: falls back to where they were caught).
  local spotAt=standSpot(r.Position,caughtAt,ignoreBodies())
  local at=Vector3.new(spotAt.X,caughtAt.Y,spotAt.Z);local face=Vector3.new(center.X,caughtAt.Y,center.Z)
  r.CFrame=(at-face).Magnitude>.5 and CFrame.lookAt(at,face)or CFrame.new(at)
 end
 unfreeze(r,h)
 unclaim(state,p)
 if alive(p,c)and state.model.Parent then
  self.ctx.Audio.Play('MonsterHitThump',r)
  if self:Damage(p,state,DANCE.Damage,'twirl')then
   local away=Vector3.new(r.Position.X-center.X,0,r.Position.Z-center.Z)
   event:FireClient(p,'knock',away.Magnitude>.1 and away.Unit or Vector3.new(0,0,1),DANCE.Fling,16)
  end
 end
 if state.spotted then state.spotted[p.UserId]=nil end
 ignore(state,p,DANCE.Ignore)
 state.attack=nil;pose(state,nil)
 if state.model.Parent then self.ctx.forget(state,p);self.ctx.retreat(state,os.clock(),caughtAt)end
end
-- A telegraphed curtsy; she only takes hands still in reach, in sight and unprotected (a sidestep through a door works).
local function statueCatch(self,state,p,now)
 local c,r=character(p);if not r then return false end
 state.attack={kind='Curtsy',player=p,started=now}
 claim(state,p);pose(state,'Curtsy');state.model:SetAttribute('Walking',false)
 self.ctx.Audio.Play('MonsterWhoosh',state.root)
 local look=Vector3.new(r.Position.X-state.root.Position.X,0,r.Position.Z-state.root.Position.Z)
 if look.Magnitude>.1 then state.yaw=math.atan2(-look.X,-look.Z);state.root.CFrame=CFrame.new(state.root.Position)*CFrame.Angles(0,state.yaw,0)end
 task.spawn(function()
  task.wait(DANCE.Windup)
  local _,r2,h2=character(p)
  if state.model.Parent and alive(p,c)and r2 and h2 and flat(r2.Position,state.root.Position)<DANCE.GrabRange and math.abs(r2.Position.Y-state.root.Position.Y)<8
   and self.ctx.sees(state,r2.Position)and not self.ctx.Protection.IsProtected(p)then
   letGo(p);statueTwirl(self,state,p,c,r2,h2)
  else
   unclaim(state,p);state.attack=nil;pose(state,nil);state.pauseUntil=os.clock()+.3
  end
 end)
 return true
end
-- Every frame: run the cycle; while she looks she stands and turns (returns true = M:Step holds her still) and spots movers.
local function statueStep(self,state,now)
 if not state.dance then state.dance={};setDance(state,'Dance',danceLength(self,state))end
 local d=state.dance
 local cart=self.ctx.cart and self.ctx.cart()
 local by=cart and cart:GetAttribute('HeldBy');if by then d.pusher=by end -- a cart left rolling still gives its pusher away
 -- Hunts run out: forgotten again, back to blind dancing.
 if state.spotted then
  local any=false
  for id,untilT in state.spotted do
   if now>untilT then state.spotted[id]=nil;local q=Players:GetPlayerByUserId(id);if q then self.ctx.forget(state,q)end else any=true end
  end
  if not any and state.model:GetAttribute('Mad')then state.model:SetAttribute('Mad',nil)end
 end
 if state.attack then return false end
 if d.phase=='Dance'and now>=d.untilT then setDance(state,'Winding',DANCE.Wind)
 elseif d.phase=='Winding'and now>=d.untilT then
  setDance(state,'Look',DANCE.Look);d.lookStart=now;d.yaw0=state.yaw or 0
  self.ctx.Audio.Play('ClockTick',state.root)
 elseif d.phase=='Look'and now>=d.untilT then setDance(state,'Dance',danceLength(self,state))end
 if d.phase~='Look'then
  -- Hunting whoever she spotted: she knows where they are (re-routed about 3x a second) until the hunt runs out or they hide.
  if state.spotted and now>=(d.huntRouteAt or 0)then
   d.huntRouteAt=now+.35
   local best,bestR,bd=nil,nil,math.huge
   for id,untilT in state.spotted do
    local q=now<untilT and Players:GetPlayerByUserId(id)
    if q then
     local qr,_,ok=self.ctx.eligible(q)
     if ok and qr and not(self.ctx.Sighted or self.ctx.Protection).IsProtected(q)then local dd=flat(qr.Position,state.root.Position);if dd<bd then best,bestR,bd=q,qr,dd end end
    end
   end
   if best then state.target=best;self.ctx.routeTo(state,bestR.Position,'Chase')end
  end
  return false
 end
 -- She stands on her toe and turns once around, watching.
 state.model:SetAttribute('Walking',false)
 local age=now-d.lookStart
 state.yaw=d.yaw0+2*math.pi*age/DANCE.Look;state.root.CFrame=CFrame.new(state.root.Position)*CFrame.Angles(0,state.yaw,0)
 local m=state.model
 if age<DANCE.Grace or now<(state.calmUntil or 0)or now<(m:GetAttribute('CalmUntil')or 0)or now<(m:GetAttribute('StunnedUntil')or 0)
  or now<(m:GetAttribute('FleeUntil')or 0)or now<(m:GetAttribute('HypnoUntil')or 0)or now<(d.scanAt or 0)then return true end
 d.scanAt=now+.1
 local raw=self.ctx.Sighted or self.ctx.Protection -- raw MonsterProtection: a look must never start the Untouchable shield
 local pos=state.root.Position
 for _,p in Players:GetPlayers()do
  local r,_,ok=self.ctx.eligible(p)
  if ok and r and not(state.ignore and state.ignore[p.UserId]and now<state.ignore[p.UserId])and not raw.IsProtected(p)
   and not(self.ctx.NearVan and self.ctx.NearVan(r.Position,3))and flat(r.Position,pos)<DANCE.Range and math.abs(r.Position.Y-pos.Y)<10
   and flat(r.AssemblyLinearVelocity,Vector3.zero)>DANCE.MoveTol and(self.ctx.sees(state,r.Position)or self.ctx.sees(state,r.Position+Vector3.new(0,1.6,0)))then
   spot(self,state,p,now,'moved')
  end
 end
 local body=cart and cart.PrimaryPart
 if body then
  local v=body.AssemblyLinearVelocity
  if Vector3.new(v.X,0,v.Z).Magnitude>DANCE.CartTol and flat(body.Position,pos)<DANCE.Range and math.abs(body.Position.Y-pos.Y)<10
   and self.ctx.sees(state,body.Position+Vector3.new(0,1,0))then
   local q=Players:GetPlayerByUserId(cart:GetAttribute('HeldBy')or d.pusher or 0)
   if q then
    local qr,_,ok=self.ctx.eligible(q)
    if ok and qr and flat(qr.Position,body.Position)<DANCE.PusherRange and not raw.IsProtected(q)then spot(self,state,q,now,'cart')end
   end
  end
 end
 return true
end
-- Per-role blindness used by M:Ignores.
function M:RoleIgnores(state,p)
 local role=M.Role(state)
 if role=='Holder'then return self:Accompanied(p)end
 if role=='Statue'then local s=state.spotted and state.spotted[p.UserId];return not(s and os.clock()<s)end
 return false
end

-- ===== Hooks used by CreatureRoamServer =====
-- Called at the top of every step. Returns true when the monster must do nothing else this frame.
function M:Step(state,now,dt)
 -- The Lantern roams far and fast but sees poorly (CreatureRoamServer reads state.roamy / state.dull).
 if state.roamy==nil then local seeker=M.Role(state)=='Seeker';state.roamy=seeker;state.dull=seeker and SEEK.Dull or nil end
 -- The pup's Lantern (CloseUpChoices): chases only the player who woke it, re-routing to them three times a second.
 if state.hunt and not state.attack and now>=(state.pauseUntil or 0)then
  local _,hr=character(state.hunt.player)
  if hr then
   state.target=state.hunt.player
   if now>=(state.hunt.routeAt or 0)then state.hunt.routeAt=now+.35;self.ctx.routeTo(state,hr.Position,'Chase')end
  end
 end
 if state.attack then
  if state.attack.kind~=nil then
   state.model:SetAttribute('Walking',false)
   if M.Role(state)=='Laser' then laserStep(self,state,now)end
   return true
  end
 end
 local role=M.Role(state)
 if role=='Laser' then laserStep(self,state,now);if state.attack then return true end
 elseif role=='Seeker' then seekerStep(self,state,now);if state.attack then return true end end
 if role=='Holder' then holderStep(self,state,now);if state.attack then return true end
 elseif role=='Statue' then if statueStep(self,state,now) then return true end end
 return false
end
-- Perception pause while a Seeker walks to a closet (the brain would otherwise re-route it).
function M:HoldsRoute(state,now)return state.hunt~=nil or now<(state.seekingUntil or 0)end
-- Chase speed override; nil keeps the normal speed.
function M:Speed(state,mode)
 if state.hunt then return state.hunt.speed end -- the pup's Lantern: extremely fast
 local role=M.Role(state)
 if role=='Laser' then return LASER.Speed end
 if role=='Rusher' and mode=='Chase' then
  -- Only mad (and fast) while it can actually SEE its target; out of sight it slows to a normal chase and has to find
  -- them again (owner, 2026-10-22: chasing at full speed from memory was overpowered). Checked 5 times a second.
  local now=os.clock()
  if now>(state.rushSightAt or 0)then
   state.rushSightAt=now+.2
   local t=state.target;local c=t and t.Character;local tr=c and c:FindFirstChild('HumanoidRootPart')
   state.rushSees=tr~=nil and not (self.ctx.Sighted or self.ctx.Protection).IsProtected(t)and self.ctx.sees(state,tr.Position)
  end
  if state.rushSees then
   if not state.model:GetAttribute('Mad')then state.model:SetAttribute('Mad',true);self.ctx.Audio.Play('WraithRush',state.root)end
   return state.easy and RUSH.EasyChaseSpeed or RUSH.ChaseSpeed
  end
  if state.model:GetAttribute('Mad')then state.model:SetAttribute('Mad',nil)end
  return RUSH.BlindSpeed
 end
 if role=='Rusher' and state.model:GetAttribute('Mad')then state.model:SetAttribute('Mad',nil)end
 -- The Bellhop strides after anyone it sees: faster than a sprint (20), so almost nobody outruns it (owner, 2026-10-22).
 if role=='Carrier' and mode=='Chase' then return state.easy and CARRY.EasyChaseSpeed or CARRY.ChaseSpeed end
 if role=='Seeker' then if mode=='Chase' then return state.easy and SEEK.EasyChaseSpeed or SEEK.ChaseSpeed end;return SEEK.RoamSpeed end
 if role=='Holder' then
  if mode=='Chase' then return state.easy and HOLD.EasyChaseSpeed or HOLD.ChaseSpeed end
  if state.lurkUntil and os.clock()<state.lurkUntil then return HOLD.LurkSpeed end
 end
 if role=='Statue' then
  if state.dance and state.dance.phase=='Winding' then return DANCE.WindSpeed end -- her spring runs down
  if mode=='Chase' then return state.easy and DANCE.EasyChaseSpeed or DANCE.ChaseSpeed end
 end
 return nil
end
-- A chase reached the player. Returns true when the role handled it (otherwise the classic jumpscare runs).
function M:Catch(state,p,now)
 if self:Ignores(state,p)then return true end
 local role=M.Role(state)
 if role=='Rusher' then return rusherCatch(self,state,p,now)
 elseif role=='Carrier' then return carrierCatch(self,state,p,now)
 elseif role=='Laser' then return true -- it kicks instead (laserStep)
 elseif role=='Seeker' then return seekerGrab(self,state,p,now)
 elseif role=='Holder' then return holderCatch(self,state,p,now)
 elseif role=='Statue' then return statueCatch(self,state,p,now)
 end
 return false
end
M.Roles=ROLE_BY_KIND
return M
