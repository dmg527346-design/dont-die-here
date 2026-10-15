local QuestService=require(game:GetService('ServerScriptService'):WaitForChild('QuestService'))
local QuestHttp=game:GetService('HttpService')
local function questContext(eventId,model)
 local s=game:GetService('ReplicatedStorage'):FindFirstChild('RecoveryRound')
 local map=workspace:FindFirstChild('Mansion')
 return {eventId=eventId,runId=s and s:GetAttribute('QuestRunId'),round=s and s:GetAttribute('Round'),generation=s and s:GetAttribute('QuestGeneration'),mapKind=map and map:GetAttribute('MapKind'),admin=model and (model:GetAttribute('AdminEffect')==true or model:GetAttribute('AdminSpawned')==true),lobbyToy=model and model:GetAttribute('LobbyToy')==true,itemId=model and model:GetAttribute('ItemId')}
end
-- Server-only evidence, beliefs and utility decisions. CreatureRoamServer owns movement.
local Players=game:GetService('Players')
local SS=game:GetService('ServerStorage')
local M={}
local Director=require(script.Parent:WaitForChild('HorrorDirector'))
local personalities={
 Hunter={pursuit=1.12,mimic=.7,stalk=.85,ambush=1.05},
 Mimic={pursuit=.85,mimic=1.4,stalk=1.1,ambush=1},
 Stalker={pursuit=.8,mimic=1,stalk=1.4,ambush=1.2},
 Trickster={pursuit=.9,mimic=1.25,stalk=1.15,ambush=1.25},
 Predator={pursuit=1.05,mimic=.95,stalk=1,ambush=1.35},
}
local names={'Hunter','Mimic','Stalker','Trickster','Predator'}
-- Losing sight starts a hunt: Search sweeps the predicted route, nearby rooms and lockers for HUNT_MEMORY
-- seconds. Only a hunt that finds nothing ends in a disengage (forget, turn away, deaf for DISENGAGE_SECONDS).
local LOST_GRACE=1.2 -- out of sight this long = no longer 'in view' (the hunt starts)
local HUNT_MEMORY,HUNT_MEMORY_HARD=10,6 -- then it hunts from memory for 10s (+6s at full difficulty) before giving up
local DISENGAGE_SECONDS=8 -- after a failed hunt it ignores noises this long (was 25)
local function flat(v)return Vector3.new(v.X,0,v.Z)end
local function normalize(t)
 local total=0;for _,value in pairs(t)do total+=math.max(0,value)end
 if total<.001 then return {escaped=1}end
 for name,value in pairs(t)do t[name]=math.max(0,value)/total end;return t
end
local function direction(v)return v.Magnitude>.1 and v.Unit or Vector3.zero end
function M.New(ctx)
 local self={ctx=ctx,queue={},serial=0,sessionHabits={},director=Director.New(ctx.round)}
 local rng=ctx.rng
 local function rngGrace(id)return 7+(id%5)end
 local bus=SS:FindFirstChild('MonsterEvidence')or Instance.new('BindableEvent')
 bus.Name='MonsterEvidence';bus.Parent=SS
 self.connection=bus.Event:Connect(function(pos,loudness,kind,source,detail)
  if typeof(pos)~='Vector3' or type(loudness)~='number' or loudness~=loudness then return end
  self.serial+=1
  table.insert(self.queue,{id=self.serial,position=pos,loudness=math.clamp(loudness,0,100),kind=kind,source=source,detail=detail,time=os.clock()})
  if #self.queue>96 then table.remove(self.queue,1)end
 end)
 function self:Reset()
  table.clear(self.queue)
  self.director=Director.New(ctx.round)
 end
 function self:Init(s,now)
  if s.brain then return end
  local name=names[rng:NextInteger(1,#names)]
  local identity=(s.model:GetAttribute('CreatureKind')or s.model.Name)..':'..(s.model.Name:match('_(%d+)$')or '1')
  self.sessionHabits[identity]=self.sessionHabits[identity]or{}
  s.brain={habits=self.sessionHabits[identity],knowledge={},rooms={},visited={},noiseCursor=self.serial,personality=personalities[name],decisionAt=0,lastSense=now,untilAt=0,lastMimic=now-20,lastHiddenCheck=0}
  s.model:SetAttribute('Personality',name)
 end
 local function record(b,p)
  local k=b.knowledge[p.UserId]
  if not k then k={player=p,genericHideConfidence=b.habits[p.UserId]or 0,confidence=0,suspicion=0,velocity=Vector3.zero,beliefs={},hideHabit={},routeHabit={},samples={},encounters=0,escapes=0};b.knowledge[p.UserId]=k end
  return k
 end
 function self:TickDirector(now,states)self.director:Tick(now,states)end
 function self:Death(p,now)self.director:Death(p,now)end
 function self:ObservedHide(s,p,closet,now)
  self:Init(s,now)
  local k=s.brain.knowledge[p.UserId]
  if not k or not k.seenAt or now-k.seenAt>.75 then return false end
  if (k.position-closet.Position).Magnitude>12 then return false end
  -- Called before the player is hidden, with the normal vision gate checked by the owner.
  k.observedCloset=closet;k.observedUntil=now+12+13*s.difficulty
  local adaptation=.06+.08*s.difficulty
  k.hideHabit[closet.Name]=math.min(.65,(k.hideHabit[closet.Name]or .05)+adaptation)
  k.genericHideConfidence=math.min(.65,k.genericHideConfidence+adaptation*.5)
  s.brain.habits[p.UserId]=k.genericHideConfidence
  k.suspicion=100;k.confidence=1;k.position=closet.Position
  s.brain.decisionAt=0
  return true
 end
 -- Awareness tuning (was 58 suspicion/s, .8 confidence/s, chase at 95, suspicious at 20, chase-confidence floor 0).
 local SUSPICION_GAIN,CONFIDENCE_GAIN=120,1.8
 local CHASE_SUSPICION,SUSPICIOUS_SUSPICION=70,8
 local CHASE_CONFIDENCE_FLOOR=.75 -- a monster that clearly sees you commits to the chase instead of stalking
 local POINT_BLANK_RANGE,POINT_BLANK_CHASE=20,1.7 -- standing this close in sight: chase beats every other plan
 local VISIBLE_CHASE_FLOOR=160 -- a confirmed, visible target is always chased; only losing sight ends it
 function self:Sight(s,p,pos,velocity,visibility,now,dt,gaze)
  local b=s.brain;local k=record(b,p)
  if k.position and k.seenAt and now-k.seenAt<2 then
   local oldRoom=self.ctx.roomAt(k.position);local newRoom=self.ctx.roomAt(pos)
   if oldRoom and newRoom and oldRoom~=newRoom then
    local key=oldRoom.name..'>'..newRoom.name
    k.routeHabit[key]=math.min(.65,(k.routeHabit[key]or 0)+.08)
   end
  end
  k.position=pos;k.velocity=flat(velocity);k.seenAt=now;k.visible=true;k.gaze=gaze
  k.suspicion=math.clamp(k.suspicion+visibility*dt*SUSPICION_GAIN,0,100)
  k.confidence=math.clamp(k.confidence+visibility*dt*CONFIDENCE_GAIN,0,1)
  local r=self.ctx.roomAt(pos)
  if r then k.room=r.name;b.rooms[r.name]=math.max(b.rooms[r.name]or 0,k.suspicion);k.beliefs={[r.name]=.9,escaped=.1}end
  k.samples[#k.samples+1]={p=pos,t=now}
  while #k.samples>48 do table.remove(k.samples,1)end
  -- A repeated return near an earlier observed point, with significant observed travel, is loop evidence.
  if #k.samples>=12 and now-(k.loopAt or 0)>8 then
   local oldest=k.samples[1];local length=0
   for i=2,#k.samples do length+=(k.samples[i].p-k.samples[i-1].p).Magnitude end
   if now-oldest.t>1.5 and length>24 and (pos-oldest.p).Magnitude<7 then k.loopAt=now;k.loopConfidence=math.min(.75,(k.loopConfidence or 0)+.25)end
  end
 end
 function self:Hear(s,e,now)
  if now-e.time>1.5 or self.ctx.nearVan(e.position,3)then return end
  local distance=(e.position-s.root.Position).Magnitude
  -- Across floors, sound travels the stair route; a player 4 studs overhead can be 40 away.
  if self.ctx.routeDistance and self.ctx.level(e.position.Y)~=self.ctx.level(s.root.Position.Y) then
   distance=math.max(distance,self.ctx.routeDistance(s.root.Position,e.position))
  end
  local radius=e.loudness*1.4
  if distance>=radius then return end
  local obstructed=not self.ctx.sees(s,e.position+Vector3.new(0,2,0))
  local strength=(1-distance/math.max(1,radius))*(obstructed and .32 or 1)
  if strength<.15 then return end
  local accuracy=.60+.30*s.difficulty
  local error=(1-strength)*(14-8*accuracy)+2
  local reported=e.position+Vector3.new(rng:NextNumber(-error,error),0,rng:NextNumber(-error,error))
  local b=s.brain
  b.noise={position=reported,confidence=math.min(.82,strength*accuracy),time=now,kind=e.kind}
  local room=self.ctx.roomAt(reported)
  if room then
   b.rooms[room.name]=math.min(100,(b.rooms[room.name]or 0)+strength*45)
   for _,link in self.ctx.adjacency[room.name]or{}do b.rooms[link.to]=math.max(b.rooms[link.to]or 0,strength*18)end
  end
  if typeof(e.source)=='Instance' and e.source:IsA('Player')then
   local k=record(b,e.source)
   k.heardPosition=reported;k.heardAt=now;k.confidence=math.max(k.confidence,math.min(.7,strength));k.suspicion=math.min(100,k.suspicion+strength*20)
   if room then
    local old=k.beliefs;local beliefs={};for name,value in pairs(old)do beliefs[name]=value*.45 end
    beliefs[room.name]=(beliefs[room.name]or 0)+.55;k.beliefs=normalize(beliefs)
   end
   if e.kind=='Speaking' then
    s.model:SetAttribute('HeardVoice_'..e.source.UserId,now)
    local api=SS:FindFirstChild('MonsterMimicApi');if api then api:Invoke('heard',s.model,e.source.UserId,now)end
   end
  end
  s.model:SetAttribute('LastHeardKind',e.kind);s.model:SetAttribute('LastHeardAt',now)
 end
 local function add(candidates,action,score,pos,k,detail)
  if score>0 then table.insert(candidates,{action=action,score=score,pos=pos,k=k,detail=detail})end
 end
 function self:Search(s,k,now)
  local b=s.brain;local origin=k.position or k.heardPosition
  local r=origin and self.ctx.roomAt(origin)
  if not r then return end
  local candidates={}
  local forward=direction(k.velocity)
  local age=now-(k.seenAt or k.heardAt or now)
  local function candidate(room,pos,bias,detail)
   if self.ctx.nearVan(pos,4) or not self.ctx.reachable(s.room,room)then return end
   local dir=direction(flat(pos-origin))
   local directional=forward:Dot(dir)*16
   local previous=(b.visited[detail or room.name]or -100)
   local recent=now-previous<18 and 45 or 0
   local belief=(k.beliefs[room.name]or 0)*40
   local habit=(k.routeHabit[r.name..'>'..room.name]or 0)*15
   local score=(bias+directional+belief+habit+(b.rooms[room.name]or 0)*.3-recent)*rng:NextNumber(.9,1.1)
   if score>0 then table.insert(candidates,{pos=pos,room=room,score=score,detail=detail})end
  end
  candidate(r,self.ctx.safePoint(r,origin,2),32,'last:'..r.name)
  for _,link in self.ctx.adjacency[r.name]or{}do
   local nextRoom=self.ctx.rooms[link.to]
   candidate(nextRoom,self.ctx.center(nextRoom),36,'room:'..nextRoom.name)
   for _,nextLink in self.ctx.adjacency[nextRoom.name]or{}do
    if nextLink.to~=r.name then local rr=self.ctx.rooms[nextLink.to];candidate(rr,self.ctx.center(rr),22,'route:'..rr.name)end
   end
  end
  table.sort(candidates,function(a,b)return a.score>b.score end)
  local choice=candidates[1]
  if choice then
   k.predictedPosition=choice.pos
   -- Beliefs change from visited evidence, never from an occupant table.
   local previous=k.beliefs[choice.room.name]or 0
   k.beliefs[choice.room.name]=previous*.65
   k.beliefs.escaped=(k.beliefs.escaped or 0)+previous*.35
   k.beliefs=normalize(k.beliefs)
   b.visited[choice.detail]=now
   return choice.pos,choice.room
  end
 end
 function self:Update(s,observations,now)
  self:Init(s,now);local b=s.brain;local d=self.director
  local dt=math.clamp(now-b.lastSense,0,60);b.lastSense=now
  for id,k in pairs(b.knowledge)do
   if not k.player.Parent or k.player:GetAttribute('RoundDead')then b.knowledge[id]=nil
   else k.visible=false;k.suspicion=math.max(0,k.suspicion-dt*1.8);k.confidence*=math.exp(-dt/(8+17*s.difficulty))
    local latest=math.max(k.seenAt or -100,k.heardAt or -100)
    if now-latest>8+17*s.difficulty then k.confidence=0 end
    if k.seenAt and now-k.seenAt>45 then k.position=nil;k.velocity=Vector3.zero;k.samples={}end
   end
  end
  for name,value in pairs(b.rooms)do b.rooms[name]=math.max(0,value-dt*1.4)end
  for _,o in observations do self:Sight(s,o.player,o.position,o.velocity,o.visibility,now,math.min(dt,.5),o.gaze)end
  for _,e in self.queue do if e.id>b.noiseCursor then
   if e.kind=='HideObserved' then
    local delta=e.position-(s.root.Position+Vector3.new(0,2.5,0))
    if delta.Magnitude<80 and (delta.Magnitude<.1 or s.root.CFrame.LookVector:Dot(delta.Unit)>-.15) and self.ctx.sees(s,e.position)then self:ObservedHide(s,e.source,e.detail,now)end
   else self:Hear(s,e,now)end
  end end
  b.noiseCursor=self.serial
  if now<b.decisionAt then return end
  b.decisionAt=now+rng:NextNumber(.55,.9)
  local candidates={}
  local pressure=now<d.reliefUntil and .45 or 1
  local eligible={}
  -- still being hunted: recently seen players stay on the list even after confidence fades
  for _,k in pairs(b.knowledge)do if k.visible or k.confidence>.15 or (k.seenAt and now-k.seenAt<HUNT_MEMORY+HUNT_MEMORY_HARD*s.difficulty) then table.insert(eligible,k)end end
  -- Calm after spawning (CreatureRoamServer calmUntil): only a player close and in sight matters.
  local calm=now<(s.calmUntil or 0)
  s.model:SetAttribute('Calm',calm or nil)
  local disengaged=now<(b.disengageUntil or 0)
  local anyVisible=false
  for _,k in eligible do if k.seenAt and now-k.seenAt<LOST_GRACE then anyVisible=true;break end end
  local huntMemory=HUNT_MEMORY+HUNT_MEMORY_HARD*s.difficulty
  if anyVisible then b.lastSeenAny=now end
  if b.engaged and not anyVisible and now-(b.lastSeenAny or now)>huntMemory then
   b.engaged=false;b.disengageUntil=now+DISENGAGE_SECONDS;disengaged=true
    local episode=b.questChase;local p=episode and episode.player;local h=p and p.Character and p.Character:FindFirstChildOfClass('Humanoid')
    if episode and now-episode.started>=5 and h and h.Health>0 and p:GetAttribute('MissionActive')==true and not p:GetAttribute('RoundDead') and not p:GetAttribute('LeavingRun') and p.Character==episode.character then QuestService.Record(p,'ChaseEscaped',1,questContext('chase:'..episode.id))end
    b.questChase=nil
   local avoid=b.engagedAt or s.root.Position
   for _,k in pairs(b.knowledge) do
    k.confidence=0;k.suspicion=0;k.position=nil;k.heardPosition=nil;k.beliefs={};k.samples={};k.velocity=Vector3.zero;k.loopConfidence=nil
   end
   b.noise=nil;b.fakeReturn=nil;s.model:SetAttribute('FakeDisengage',false)
   if b.chaseAt then
    if s.target then d.escapes[s.target.UserId]=now end

    d.reliefUntil=math.max(d.reliefUntil,now+5);b.chaseAt=nil
   end
   s.target=nil;s.model:SetAttribute('UtilityAction','Disengage')
   if self.ctx.disengage then self.ctx.disengage(s,avoid) end
   s.model:SetAttribute('Disengaged',true)
   return
  end
  s.model:SetAttribute('Disengaged',disengaged or nil)
  for _,k in eligible do
   local known=k.position or k.heardPosition
   if not known then continue end
   if calm and not (k.visible and k.position and (k.position-s.root.Position).Magnitude<(s.calmNotice or 16)) then continue end
   local age=now-(k.seenAt or 0)
   local group=0
   -- Social classification uses this monster's observed records, never the roster's hidden positions.
   for _,other in eligible do if other~=k and other.position and other.seenAt and now-other.seenAt<3 and (known-other.position).Magnitude<22 then group+=1 end end
   k.group=group==0 and 'ISOLATED' or group==1 and 'PAIR' or 'GROUP'
   local isolation=group==0 and 1.15 or group==1 and .85 or .6
   local grace=now-(d.escapes[k.player.UserId]or -100)<rngGrace(k.player.UserId) and .22 or 1
   local deathGrace=now-(d.deaths[k.player.UserId]or -100)<45 and .35 or 1
   local novice=1 -- (was .8 for a player's first two encounters)
   if k.visible and k.suspicion>=CHASE_SUSPICION then
    local chaseAge=b.chaseAt and now-b.chaseAt or 0
    local persistence=math.max(.4,1-math.max(0,chaseAge-18)/35)
    local loopPressure=k.loopConfidence and now-(k.loopAt or 0)<12 and math.max(.4,1-k.loopConfidence*.8)or 1
    local score=100*loopPressure*math.max(k.confidence,CHASE_CONFIDENCE_FLOOR)*b.personality.pursuit*isolation*pressure*grace*novice*deathGrace*persistence*((known-s.root.Position).Magnitude<POINT_BLANK_RANGE and POINT_BLANK_CHASE or 1)
    local horizon=rng:NextNumber(.3,.65+.45*s.difficulty)
    local error=(1-(.6+.3*s.difficulty))*rng:NextNumber(-4,4)
    local goal=known+k.velocity*horizon+Vector3.new(error,0,-error)
    add(candidates,'Chase',math.max(score,VISIBLE_CHASE_FLOOR),goal,k)
   elseif k.visible and k.suspicion>=SUSPICIOUS_SUSPICION then
    add(candidates,'Suspicious',30+k.suspicion*.4,known,k)
    add(candidates,'Stalk',k.suspicion*.65*b.personality.stalk*isolation,known,k)
   end
   -- Out of sight: hunt the predicted route from the last sighting, then fresh sounds of this player.
   if not k.visible and not calm and not disengaged then
    if k.position and k.seenAt and now-k.seenAt<huntMemory then
     add(candidates,'Search',115*b.personality.pursuit*math.max(.5,k.confidence),known,k)
    elseif k.heardPosition and k.heardAt and now-k.heardAt<6+6*s.difficulty then
     add(candidates,'Search',60+k.confidence*40,k.heardPosition,k)
    end
   end
   if k.observedCloset and k.observedCloset.Parent and now<(k.observedUntil or 0) then
    add(candidates,'CheckHiding',125,k.observedCloset.Position,k,k.observedCloset)
   end
   local mimicApi=SS:FindFirstChild('MonsterMimicApi')
   local mimicAvailable=not disengaged and k.suspicion>25 and now-b.lastMimic>25 and k.confidence>.2 and not k.visible and mimicApi and mimicApi:Invoke('available',s.model,k.player.UserId)
   if mimicAvailable then
    add(candidates,'Mimic',55*isolation*b.personality.mimic*pressure,known,k)
   end
  end
  if not calm and not disengaged and b.noise and now-b.noise.time<8+12*s.difficulty then
   add(candidates,'Investigate',28+b.noise.confidence*65,b.noise.position)
  end
  add(candidates,'Patrol',12+(now-d.lastThreat>55 and 10 or 0))
  for _,c in candidates do c.score*=rng:NextNumber(.9,1.1)end
  table.sort(candidates,function(a,b)return a.score>b.score end)
  local c=candidates[1]
  local old=s.mode
  -- Engaged while the target is actually in sight; losing sight later triggers disengage.
  if c.k and c.k.visible and (c.action=='Chase' or c.action=='Stalk' or c.action=='Suspicious' or c.action=='Ambush') then
   b.engaged=true;b.engagedAt=c.k.position
  end
  if old=='Chase' and c.action~='Chase' and b.chaseAt then
   if s.target then d.escapes[s.target.UserId]=now;local k=b.knowledge[s.target.UserId];if k then k.escapes+=1 end end
   d.reliefUntil=math.max(d.reliefUntil,now+5);b.chaseAt=nil
  end
  s.target=nil
  if c.k then s.model:SetAttribute('KnowledgeConfidence',c.k.confidence);s.model:SetAttribute('Suspicion',c.k.suspicion);s.model:SetAttribute('TargetSituation',c.k.group)end
  s.model:SetAttribute('UtilityAction',c.action);s.model:SetAttribute('UtilityScore',math.floor(c.score))
  if c.action=='Chase' then
   s.target=c.k.player;b.chaseAt=b.chaseAt or now;d.lastThreat=now
   if not b.questChase or b.questChase.player~=s.target then b.questChase={player=s.target,character=s.target.Character,started=now,id=QuestHttp:GenerateGUID(false)}end
   if old~='Chase' then d.encounters[c.k.player.UserId]=(d.encounters[c.k.player.UserId]or 0)+1 end
   self.ctx.routeTo(s,c.pos,'Chase')
  elseif c.action=='CheckHiding' then
   if (s.root.Position-c.pos).Magnitude<9 then
    local api=nil -- monsters never open closets (user decision 2026-10-07): they may linger near one, a hider stays safe
    if api and now-b.lastHiddenCheck>5 then
     b.lastHiddenCheck=now
     task.spawn(function()api:Invoke(c.detail,s.root)end)
     c.k.observedUntil=0
    end
    self.ctx.setMode(s,'CheckHiding');s.points=nil;s.pauseUntil=now+rng:NextNumber(1,2)
   else self.ctx.routeTo(s,c.pos,'CheckHiding')end
  elseif c.action=='Search' or c.action=='Ambush' then
   if s.points and old==c.action then return end
   if old=='Ambush' and now<(b.ambushUntil or 0)then self.ctx.setMode(s,'Ambush');s.pauseUntil=now+.8;return end
   if old=='Ambush' and not s.points and not b.ambushUntil then b.ambushUntil=now+rng:NextNumber(5,9);s.pauseUntil=b.ambushUntil;return end
   if b.ambushUntil and now>=b.ambushUntil then b.ambushUntil=nil end
   local pos=self:Search(s,c.k,now)
   if c.action=='Ambush' then
    local origin=c.k.position or c.k.heardPosition
    local room=origin and self.ctx.roomAt(origin)
    local forward=direction(c.k.velocity)
    local best,bestScore
    if room then for _,link in self.ctx.adjacency[room.name]or{}do
     local rr=self.ctx.rooms[link.to];local location=self.ctx.center(rr)
     local score=forward:Dot(direction(location-origin))*30+(c.k.beliefs[rr.name]or 0)*20+rng:NextNumber(-6,6)
     if not self.ctx.nearVan(location,4)and self.ctx.reachable(s.room,rr)and (not bestScore or score>bestScore)then best,bestScore=location,score end
    end end
    if best then pos=best end
   end
   if pos then self.ctx.routeTo(s,pos,c.action)else self.ctx.setMode(s,'Listen');s.pauseUntil=now+rng:NextNumber(2,5)end
   -- Unobserved lockers are candidates in a suspected room, independently of occupancy.
   if c.action=='Search' and now-b.lastHiddenCheck>10 then
    local closets=self.ctx.closets()
    for _,closet in closets do
     local r=self.ctx.roomAt(closet.Position)
     local probability=math.clamp(.08+.12*s.difficulty+(c.k.hideHabit[closet.Name]or 0)*.3+c.k.genericHideConfidence*.12,.08,.35)
     if r and (b.rooms[r.name]or 0)>25 and (closet.Position-s.root.Position).Magnitude<8 and rng:NextNumber()<probability then
      local api=nil -- monsters never open closets (user decision 2026-10-07): they may linger near one, a hider stays safe
      if api then b.lastHiddenCheck=now;task.spawn(function()api:Invoke(closet,s.root)end)end
      break
     end
    end
   end
  elseif c.action=='Stalk' or c.action=='Suspicious' then
   local away=direction(flat(s.root.Position-c.pos))
   local r=self.ctx.roomAt(c.pos)
   local lookedAt=c.k.gaze and c.k.gaze:Dot(direction(s.root.Position-c.pos))>.65
   local distance=lookedAt and 26 or 18
   local pos=r and self.ctx.safePoint(r,c.pos+away*distance,2)
   if pos then self.ctx.routeTo(s,pos,c.action)end
   if (s.root.Position-c.pos).Magnitude<23 then s.pauseUntil=now+rng:NextNumber(1,3)end
  elseif c.action=='Mimic' then
   b.lastMimic=now
   local api=SS:FindFirstChild('MonsterMimicApi')
   local purpose=c.k.group~='ISOLATED'and 'Separation' or c.k.suspicion>65 and 'FakeDistress' or d.intensity<30 and 'FakeSafety' or 'Lure'
   if now-(c.k.heardAt or -100)<35 and rng:NextNumber()<.35 then purpose=rng:NextNumber()<.5 and 'Echo'or 'Psychological'end
   if api then api:Invoke('context',s.model,c.k.player.UserId,purpose,.85+.1*s.difficulty)end
   self.ctx.setMode(s,'Mimic');s.points=nil;s.pauseUntil=now+rng:NextNumber(3,7)
  elseif c.action=='Investigate' then
   if not s.points or old~='Investigate' then self.ctx.routeTo(s,c.pos,'Investigate')end
  else
   -- Keep walking the disengage route instead of resetting it to a patrol.
   if old=='Retreat' and s.points and disengaged then return end
   if old~='Patrol' then
    s.points=nil;s.pauseUntil=now+rng:NextNumber(2,6)
    if not calm and not disengaged and #eligible>0 and rng:NextNumber()<.08+.05*s.difficulty then
     local k=eligible[rng:NextInteger(1,#eligible)]
     local pos=self:Search(s,k,now)
     if pos then b.fakeReturn={position=pos,at=now+rng:NextNumber(6,12),expires=now+18};s.model:SetAttribute('FakeDisengage',true)end
    end
   end
   if b.fakeReturn and now>b.fakeReturn.at and now<b.fakeReturn.expires then
    local pos=b.fakeReturn.position;b.fakeReturn=nil;s.model:SetAttribute('FakeDisengage',false)
    self.ctx.routeTo(s,pos,'Search');return
   end
   self.ctx.setMode(s,'Patrol')
  end
 end
 -- Stable per-player grace avoids re-rolling the escape threshold every decision.
 return self
end
return M
