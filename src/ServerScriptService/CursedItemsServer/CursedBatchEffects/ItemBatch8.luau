-- Batch 8 (CursedB build 2026-10-27): GiggleFeather, TinCanPhone, SnoringSuitcase (co-op set), TreatSack,
-- PumpkinGrin (Halloween event items), PuppetCross, PogoSpring.
-- Required exactly once by CursedBatchEffects (Configure, Pickup, ClearPlayer, ClearLevel), own 4 Hz Heartbeat.
-- This module is the only writer of Player.CoopSpeedScale (CursedItemsServer multiplies it into CursedSpeedMultiplier).
-- Faces: the shared Player.FaceBeat/FaceBeatUntil contract (moods grin/pucker/frown/squint/laugh); StarterPlayerScripts.CursedBatchBClient draws the rest.
-- Co-op items are NOT coop=true in CursedCatalog: each one also works solo, so ItemBatch4.CanSpawn never gates them.
local Players=game:GetService('Players')
local RS=game:GetService('ReplicatedStorage')
local SS=game:GetService('ServerStorage')
local Run=game:GetService('RunService')
local Audio=require(game.ServerScriptService:WaitForChild('GameplayAudioServer'))
local Sounds=require(RS:WaitForChild('GameplaySoundCatalog'))
local EventConfig=require(RS:WaitForChild('EventConfig'))
local M={}
local TICK,LEASE=.25,.5
local ITEMS={} -- [ItemId]={pickup=fn(p,m,now),tick=fn(now,models),clearPlayer=fn(p),clearLevel=fn(),debug=fn()}
local KEYS={'CoopSpeedScale','FaceBeat','FaceBeatUntil'}
local detach,clearHold,setParts
local leases={}
local speed={} -- this tick's walk-speed factors; published as Player.CoopSpeedScale
local function living(p)
 local c=p and p.Parent==Players and p.Character
 local h=c and c:FindFirstChildOfClass('Humanoid')
 return c and h and h.Health>0 and p:GetAttribute('MissionActive')==true and c or nil
end
local function rootOf(p)local c=living(p);local r=c and c:FindFirstChild('HumanoidRootPart');return r and r:IsA('BasePart')and r or nil end
local function hidden(q)return q:GetAttribute('Hiding')or q:GetAttribute('ClosetState')or q:GetAttribute('MonsterJumpscareActive')end
local function holderOf(m)
 local p=Players:GetPlayerByUserId(m:GetAttribute('HeldBy')or 0)
 return m.Parent and m:IsDescendantOf(workspace)and living(p)and not m:GetAttribute('Selling')and not m:GetAttribute('CargoStored')and p or nil
end
local function setValue(m,v)v=math.max(0,math.floor(v+.5));m:SetAttribute('Value',v);m:SetAttribute('LootValue',v)end
local function cue(key,fallback)return Sounds[key]and key or fallback end
local function evidence(pos,radius,label,source)
 local e=SS:FindFirstChild('MonsterEvidence');if e and e:IsA('BindableEvent')then e:Fire(pos,math.clamp(radius/1.4,1,100),label,source)end
end
local function lease(p,key,now)
 local stamp=math.max(p:GetAttribute(key)or 0,now+LEASE);p:SetAttribute(key,stamp);leases[p]=leases[p]or{};leases[p][key]=stamp
end
local function clearLeases(p)
 for key,stamp in pairs(leases[p]or{})do if p:GetAttribute(key)==stamp then p:SetAttribute(key,nil)end end;leases[p]=nil
end
-- Faces use the game's shared FaceBeat/FaceBeatUntil contract (ItemBatch6.Feedback; VoiceMouthClient draws the mouth,
-- CharacterMotionClient the eyes). kind -> mood; the same mood only extends, another mood takes over, except that a
-- short (<= .5 s) 4 Hz hold refresh never cuts a different, still-running face short (like Feedback.Hold).
local MOOD={Grin='grin',Pout='pucker',Sad='frown',Squint='squint',Laugh='laugh'}
local function face(p,kind,seconds,now)
 local mood=MOOD[kind];local t=now+seconds
 if p:GetAttribute('FaceBeat')~=mood then
  if seconds<=.5 and(p:GetAttribute('FaceBeatUntil')or 0)>now+.05 then return end
  p:SetAttribute('FaceBeat',mood);p:SetAttribute('FaceBeatUntil',t)
 elseif(p:GetAttribute('FaceBeatUntil')or 0)<t then p:SetAttribute('FaceBeatUntil',t)end
end
local function notice(p,text)
 local e=RS:FindFirstChild('CursedEvent');if e and p.Parent then e:FireClient(p,'notice',text)end
end
local function slow(p,factor)speed[p]=(speed[p]or 1)*factor end
local function flatSpeed(p)
 local r=rootOf(p);if not r then return 0 end
 local v=r.AssemblyLinearVelocity;return Vector3.new(v.X,0,v.Z).Magnitude
end
local function sees(a,b)
 local map=workspace:FindFirstChild('Mansion');local collision=map and map:FindFirstChild('Collision');if not collision then return true end
 local params=RaycastParams.new();params.FilterType=Enum.RaycastFilterType.Include;params.FilterDescendantsInstances={collision};params.RespectCanCollide=true
 return workspace:Raycast(a,b-a,params)==nil
end
-- Living, unhidden teammates of p whose root is within radius of pos and in plain sight of it.
local function teammatesNear(p,pos,radius)
 local list={}
 for _,q in ipairs(Players:GetPlayers())do
  local r=q~=p and not hidden(q)and rootOf(q)
  if r and(r.Position-pos).Magnitude<=radius and sees(pos+Vector3.new(0,1,0),r.Position)then table.insert(list,q)end
 end
 return list
end
local function othersAlive(p)local n=0;for _,q in ipairs(Players:GetPlayers())do if q~=p and living(q)then n+=1 end end;return n end
local function creatures()
 local f=workspace:FindFirstChild('RoamingCreatures');return f and f:GetChildren()or{}
end
local function monsterNear(pos,radius)
 for _,e in ipairs(creatures())do
  local pp=e:IsA('Model')and e.PrimaryPart;local h=e:FindFirstChildOfClass('Humanoid')
  if pp and(not h or h.Health>0)and(pp.Position-pos).Magnitude<=radius then return true end
 end
 return false
end
local function nearestCreature(pos)
 local best=math.huge
 for _,e in ipairs(creatures())do
  local pp=e:IsA('Model')and e.PrimaryPart;local h=e:FindFirstChildOfClass('Humanoid')
  if pp and(not h or h.Health>0)then best=math.min(best,(pp.Position-pos).Magnitude)end
 end
 return best
end
-- Halloween event switch: the same rule as CursedItemsServer.eventLive; Studio tests force it with
-- ReplicatedStorage attribute StudioHalloween=true (ignored outside Studio).
function M.HalloweenLive()
 if Run:IsStudio()and RS:GetAttribute('StudioHalloween')==true then return true end
 local h=EventConfig.Halloween;local t=os.time()
 return type(h)=='table'and h.Enabled==true and type(h.StartsAt)=='number'and type(h.EndsAt)=='number'and h.EndsAt>h.StartsAt and t>=h.StartsAt and t<h.EndsAt
end
-- GiggleFeather --------------------------------------------------------------------------------------------
-- While it is held, a giggle fit every EVERY seconds (the first one on the grab). Each fit goes to whoever in
-- range (holder + teammates in sight within RANGE) giggled least recently, so a group shares the curse. Every
-- fit that lands on a teammate tickles STEP more sale value into the feather (cap MAX).
local GIG={EVERY=7,FIT=2.2,RANGE=14,SLOW=.6,NOISE=40,STEP=2,MAX=20}
local GIGGLE_PINK=Color3.fromRGB(255,170,220)
local feathers={} -- [Model]={nextAt=t}
local lastFit={} -- [Player]=time of that player's last fit
local sparkles={} -- [Player]=Attachment on the head while a fit runs
local function sparkle(q,on)
 local fx=sparkles[q]
 if not on then if fx then fx:Destroy();sparkles[q]=nil end;return end
 if fx and fx.Parent then return end
 local head=q.Character and q.Character:FindFirstChild('Head');if not head then return end
 local a=Instance.new('Attachment');a.Name='GiggleSparkles';a.Position=Vector3.new(0,.9,0)
 local e=Instance.new('ParticleEmitter');e.Name='Giggles';e.Texture='rbxasset://textures/particles/sparkles_main.dds';e.Color=ColorSequence.new(GIGGLE_PINK)
 e.Size=NumberSequence.new({NumberSequenceKeypoint.new(0,.25),NumberSequenceKeypoint.new(1,0)});e.Lifetime=NumberRange.new(.5,.8);e.Rate=18
 e.Speed=NumberRange.new(2,4);e.SpreadAngle=Vector2.new(50,50);e.Acceleration=Vector3.new(0,3,0);e.LightEmission=.4;e.Parent=a
 a.Parent=head;sparkles[q]=a
end
local function fit(q,m,now)
 lastFit[q]=now;q:SetAttribute('GiggleStart',now);q:SetAttribute('GiggleUntil',now+GIG.FIT)
 face(q,'Laugh',GIG.FIT,now)
 local head=q.Character and q.Character:FindFirstChild('Head')
 Audio.Play(cue('FeatherGiggle','PartyBlower'),head or m)
 evidence((head or m.PrimaryPart).Position,GIG.NOISE,'giggle fit',m)
end
ITEMS.GiggleFeather={
 pickup=function(_p,m,now)
  local s=feathers[m]or{};feathers[m]=s;s.nextAt=now -- the special action fires on the grab
  if m:GetAttribute('GiggleBase')==nil then m:SetAttribute('GiggleBase',m:GetAttribute('Value')or 0);m:SetAttribute('GiggleBonus',0)end
 end,
 tick=function(now,list)
  for m in pairs(feathers)do if not m.Parent then feathers[m]=nil end end
  for _,m in ipairs(list)do
   local p=holderOf(m);local s=feathers[m]
   if p and s and now>=s.nextAt then
    s.nextAt=now+GIG.EVERY
    local r=rootOf(p);local pool=r and teammatesNear(p,r.Position,GIG.RANGE)or{}
    if not hidden(p)then table.insert(pool,1,p)end -- holder first, so ties (and solo) land on the holder
    local pick;for _,q in ipairs(pool)do if not pick or(lastFit[q]or 0)<(lastFit[pick]or 0)then pick=q end end
    if pick then
     fit(pick,m,now)
     if pick~=p then
      local bonus=math.min(GIG.MAX,(m:GetAttribute('GiggleBonus')or 0)+GIG.STEP)
      m:SetAttribute('GiggleBonus',bonus);setValue(m,(m:GetAttribute('GiggleBase')or 0)+bonus)
     end
    end
   end
  end
  for _,q in ipairs(Players:GetPlayers())do
   local on=living(q)~=nil and now<(q:GetAttribute('GiggleUntil')or 0)
   if on then slow(q,GIG.SLOW)end;sparkle(q,on)
  end
 end,
 clearPlayer=function(p)lastFit[p]=nil;sparkle(p,false)end,
 clearLevel=function()table.clear(feathers);table.clear(lastFit);for q in pairs(sparkles)do sparkle(q,false)end end,
 debug=function()
  local list={};for m,s in pairs(feathers)do table.insert(list,{model=m:GetFullName(),nextAt=s.nextAt,value=m:GetAttribute('Value'),bonus=m:GetAttribute('GiggleBonus')})end
  return list
 end,
}
table.insert(KEYS,'GiggleStart');table.insert(KEYS,'GiggleUntil')

-- TinCanPhone ----------------------------------------------------------------------------------------------
-- Two cans on one string. The first grab unspools the twin can: its own registered loot, half the value each.
-- Two holders: a monster near one holder rings the OTHER can. Past STRING studs the string snaps.
-- One holder (solo): the loose can is tied on a short rope and clatters along behind. Both cans in a cart: pair bonus.
local CAN={STRING=50,TAUT=40,DRAG=5,REEL=1,ROPE_START=12,DANGER=30,RING_EVERY=3,RING_NOISE=20,CLATTER_EVERY=2.5,CLATTER_NOISE=28,SNAP_NOISE=30,BONUS=1.4}
local STRING_CREAM,STRING_TAUT=Color3.fromRGB(240,228,200),Color3.fromRGB(255,214,60)
local pairsOf={} -- [Model]=pair; both halves map to the same table
local function hideParts(m,prefixes)
 for _,x in ipairs(m:GetDescendants())do if x:IsA('BasePart')then
  for _,pre in ipairs(prefixes)do if x.Name:sub(1,#pre)==pre then x.Transparency=1;x.CanCollide=false;x.CanQuery=false;x.CanTouch=false end end
 end end
end
-- The string ties onto the knot on top of the visible can (mesh 'TinCanPhone' on half A, 'CanB' on half B).
local function grip(m)
 local a=m.PrimaryPart:FindFirstChild('CanStringGrip');if a then return a end
 local want=m:GetAttribute('CanHalf')=='B'and'CanB'or'TinCanPhone';local can
 for _,x in ipairs(m:GetDescendants())do if x:IsA('BasePart')and x.Name==want and x.Transparency<1 then can=x;break end end
 a=Instance.new('Attachment');a.Name='CanStringGrip';a.Parent=m.PrimaryPart
 if can then a.WorldPosition=can.Position+Vector3.new(0,can.Size.Y*.45,0)end
 return a
end
local function makeString(pair)
 local beam=Instance.new('Beam');beam.Name='CanString';beam.Attachment0=grip(pair.a);beam.Attachment1=grip(pair.b)
 beam.Color=ColorSequence.new(STRING_CREAM);beam.Width0=.07;beam.Width1=.07;beam.FaceCamera=true;beam.Segments=12
 beam.Transparency=NumberSequence.new(0);beam.Parent=pair.a.PrimaryPart;pair.beam=beam
end
local function dropRope(pair)if pair.rope then pair.rope:Destroy();pair.rope=nil end end
local function applyBonus(pair,on)
 if pair.bonus==on then return end;pair.bonus=on
 for _,m in ipairs({pair.a,pair.b})do if m.Parent and not m:GetAttribute('Selling')then
  setValue(m,pair.base[m]*(on and CAN.BONUS or 1));m:SetAttribute('CanPairBonus',on or nil)
 end end
 if on then Audio.Play('DinnerBell',pair.a)end
end
local function endPair(pair)
 dropRope(pair);if pair.beam then pair.beam:Destroy();pair.beam=nil end
 pairsOf[pair.a]=nil;pairsOf[pair.b]=nil
end
local function snap(pair,now)
 pair.snapped=true;dropRope(pair);if pair.beam then pair.beam:Destroy();pair.beam=nil end
 applyBonus(pair,false)
 for _,m in ipairs({pair.a,pair.b})do if m.Parent and m.PrimaryPart then
  m:SetAttribute('CanSnapped',true);Audio.Play('BalloonPop',m);evidence(m.PrimaryPart.Position,CAN.SNAP_NOISE,'tin can string snap',m)
  local p=holderOf(m);if p then face(p,'Pout',1.4,now);p:SetAttribute('CanSnapAt',now)end
 end end
end
ITEMS.TinCanPhone={
 pickup=function(p,m,now)
  if m:GetAttribute('CanSplit')then return end
  m:SetAttribute('CanSplit',true);m:SetAttribute('CanHalf','A')
  hideParts(m,{'CanB','StringCoil'})
  local spawner=SS:FindFirstChild('SpawnTwinItem') -- CursedItemsServer: clone + register (the only owner of loot registration)
  local ok,twin=pcall(function()return spawner and spawner:Invoke(m)end)
  if not ok or typeof(twin)~='Instance'or not twin:IsA('Model')or not twin.PrimaryPart then return end -- graceful: one can, full value, no string
  twin:SetAttribute('CanSplit',true);twin:SetAttribute('CanHalf','B')
  hideParts(twin,{'TinCanPhone','StringCoil'})
  if setParts then setParts(twin,false,true)end -- loose physics; the ground collider refits the one visible can
  local total=m:GetAttribute('Value')or 0;local half=math.ceil(total/2)
  setValue(m,half);setValue(twin,total-half)
  local pair={a=m,b=twin,base={[m]=half,[twin]=total-half},bonus=false,snapped=false,ringAt=0,clatterAt=0}
  pairsOf[m]=pair;pairsOf[twin]=pair;makeString(pair)
  Audio.Play('ClothHandle',m);face(p,'Grin',1.2,now)
 end,
 tick=function(now)
  local seen={}
  for _,pair in pairs(pairsOf)do if not seen[pair]then seen[pair]=true
   local a,b=pair.a,pair.b
   if not a.Parent or not b.Parent or not a.PrimaryPart or not b.PrimaryPart then endPair(pair);continue end
   if pair.snapped then continue end
   local pa,pb=holderOf(a),holderOf(b)
   local d=(a.PrimaryPart.Position-b.PrimaryPart.Position).Magnitude
   -- Pair bonus while both halves sit in a cart; it reverts if one is taken back out.
   if not a:GetAttribute('Selling')and not b:GetAttribute('Selling')then applyBonus(pair,a:GetAttribute('CargoStored')==true and b:GetAttribute('CargoStored')==true)end
   if pa and pb and pa~=pb then
    dropRope(pair)
    if d>CAN.STRING then snap(pair,now);continue end
    if pair.beam then
     local slack=math.clamp((CAN.TAUT-d)/CAN.TAUT,0,1)*1.6
     pair.beam.Color=ColorSequence.new(d>CAN.TAUT and STRING_TAUT or STRING_CREAM);pair.beam.CurveSize0=slack;pair.beam.CurveSize1=-slack
    end
    -- Danger relay: a monster near one holder rings the OTHER can (and tells the other holder who is in trouble).
    for _,side in ipairs({{pa,pb,b},{pb,pa,a}})do
     local near,far,farCan=side[1],side[2],side[3];local r=rootOf(near)
     if r and monsterNear(r.Position,CAN.DANGER)then
      lease(far,'CanCallUntil',now);far:SetAttribute('CanCallFrom',near.UserId);face(far,'Pout',.6,now)
      if now>=pair.ringAt then pair.ringAt=now+CAN.RING_EVERY;Audio.Play('TelephoneRing',farCan);evidence(farCan.PrimaryPart.Position,CAN.RING_NOISE,'tin can ringing',farCan)end
     end
    end
   elseif pa or pb then
    -- One holder: the loose can rides a short rope behind them (reeled in 1 stud a tick) and clatters.
    local held,loose=pa and a or b,pa and b or a
    if loose:GetAttribute('HeldBy')or loose:GetAttribute('CargoStored')or loose:GetAttribute('Selling')or loose:GetAttribute('MonsterCarried')or loose:GetAttribute('AttachedTo')then dropRope(pair)
    elseif pair.rope then
     if d>CAN.ROPE_START+2 then snap(pair,now);continue end -- snagged on a doorframe: the string gives
     pair.rope.Length=math.max(CAN.DRAG,math.min(pair.rope.Length,d+.5)-CAN.REEL)
     local hr=rootOf(pa or pb);local v=hr and hr.AssemblyLinearVelocity
     if v and Vector3.new(v.X,0,v.Z).Magnitude>2 and now>=pair.clatterAt then
      pair.clatterAt=now+CAN.CLATTER_EVERY;Audio.Play('MetalImpact',loose);evidence(loose.PrimaryPart.Position,CAN.CLATTER_NOISE,'dragged tin can',loose)
     end
    elseif d<=CAN.ROPE_START then
     local r=Instance.new('RopeConstraint');r.Name='CanDragRope';r.Attachment0=grip(held);r.Attachment1=grip(loose)
     r.Visible=false;r.Restitution=0;r.Length=math.max(CAN.DRAG,d+.5);r.Parent=held.PrimaryPart;pair.rope=r
    elseif d>CAN.STRING then snap(pair,now);continue end
   else
    dropRope(pair)
    if d>CAN.STRING then snap(pair,now);continue end
   end
  end end
 end,
 clearPlayer=function(p)p:SetAttribute('CanCallFrom',nil)end,
 clearLevel=function()
  local seen={};for _,pair in pairs(pairsOf)do if not seen[pair]then seen[pair]=true;endPair(pair)end end;table.clear(pairsOf)
 end,
 debug=function()
  local list,seen={},{}
  for _,pair in pairs(pairsOf)do if not seen[pair]then seen[pair]=true
   table.insert(list,{a=pair.a:GetFullName(),b=pair.b:GetFullName(),valueA=pair.a:GetAttribute('Value'),valueB=pair.b:GetAttribute('Value'),
    bonus=pair.bonus,snapped=pair.snapped,rope=pair.rope~=nil,beam=pair.beam~=nil})
  end end
  return list
 end,
}
table.insert(KEYS,'CanCallUntil');table.insert(KEYS,'CanCallFrom');table.insert(KEYS,'CanSnapAt')

-- SnoringSuitcase ------------------------------------------------------------------------------------------
-- Alone it is a crawl and it snores for the monsters (the holder's eyes droop). An empty-handed teammate who
-- stands at the end handle for half a second takes the other side: both walk at 90 % and the suitcase sleeps.
local SUIT={SOLO=.5,LONE=.6,DUO=.9,REACH=6,KEEP=9,DWELL=.5,FIRST_SNORE=1.5,SNORE_EVERY=5,SNORE_NOISE=45}
local STRAP=Color3.fromRGB(236,224,196)
local suits={} -- [Model]={helper=Player?,since={[Player]=t},snoreAt=t,strap=Beam?,grip=Attachment?}
local function sideHandle(m)
 for _,x in ipairs(m:GetDescendants())do if x:IsA('BasePart')and x.Name=='SideHandle'then return x end end
 return m.PrimaryPart
end
local function endHelp(s)
 if s.strap then s.strap:Destroy();s.strap=nil end;if s.grip then s.grip:Destroy();s.grip=nil end
 if s.helper and s.helper.Parent then s.helper:SetAttribute('SuitcaseHelpOwner',nil)end
 s.helper=nil;table.clear(s.since)
end
-- Empty hands (the one-item rule), not stuck, not hiding, at the end handle and in plain sight of it.
local function canHelp(q,p,m,reach)
 local r=q~=p and not hidden(q)and rootOf(q);local h=sideHandle(m)
 local owner=q:GetAttribute('SuitcaseHelpOwner')
 return r and h and(owner==nil or owner==p.UserId)and(q:GetAttribute('CursedHeldCount')or 0)==0 and(q:GetAttribute('CursedAttach')or '')==''
  and(r.Position-h.Position).Magnitude<=reach and sees(r.Position,h.Position)or false
end
local function startHelp(s,q,m,p)
 s.helper=q;q:SetAttribute('SuitcaseHelpOwner',p.UserId);table.clear(s.since)
 local hand=q.Character and(q.Character:FindFirstChild('RightHand')or q.Character:FindFirstChild('HumanoidRootPart'))
 local h=sideHandle(m);if not hand or not h then return end
 local a0=h:FindFirstChild('SuitcaseStrapHandle');if not a0 then a0=Instance.new('Attachment');a0.Name='SuitcaseStrapHandle';a0.Parent=h end
 local a1=Instance.new('Attachment');a1.Name='SuitcaseStrapGrip';a1.Parent=hand;s.grip=a1
 local beam=Instance.new('Beam');beam.Name='SuitcaseStrap';beam.Attachment0=a0;beam.Attachment1=a1;beam.Color=ColorSequence.new(STRAP)
 beam.Width0=.14;beam.Width1=.1;beam.FaceCamera=true;beam.Segments=8;beam.CurveSize0=-.6;beam.Transparency=NumberSequence.new(0);beam.Parent=h;s.strap=beam
 Audio.Play('ClothHandle',m)
end
ITEMS.SnoringSuitcase={
 pickup=function(_p,m,now)
  local s=suits[m]or{since={}};suits[m]=s
  s.snoreAt=now+SUIT.FIRST_SNORE -- the grab wakes it: first snore 1.5 s later unless someone takes the other handle
  m:SetAttribute('SuitcaseWokeAt',now)
 end,
 tick=function(now,list)
  for m,s in pairs(suits)do if not m.Parent then endHelp(s);suits[m]=nil end end
  for _,m in ipairs(list)do
   local p=holderOf(m);local s=suits[m]
   if not p then if s then endHelp(s)end;continue end
   if not s then s={since={},snoreAt=now+SUIT.FIRST_SNORE};suits[m]=s end
   if s.helper and not canHelp(s.helper,p,m,SUIT.KEEP)then endHelp(s)end
   if not s.helper then
    local h=sideHandle(m);local fresh={}
    for _,q in ipairs(h and teammatesNear(p,h.Position,SUIT.REACH)or{})do
     if canHelp(q,p,m,SUIT.REACH)then fresh[q]=s.since[q]or now;if now-fresh[q]>=SUIT.DWELL then startHelp(s,q,m,p);break end end
    end
    if not s.helper then s.since=fresh end
   end
   if s.helper then
    slow(p,SUIT.DUO);slow(s.helper,SUIT.DUO);lease(p,'SuitcaseDuoUntil',now);lease(s.helper,'SuitcaseHelpUntil',now)
    face(p,'Grin',.5,now);face(s.helper,'Grin',.5,now)
    s.snoreAt=math.max(s.snoreAt,now+2) -- rocked to sleep: no snoring while two carry it
   else
    slow(p,othersAlive(p)==0 and SUIT.LONE or SUIT.SOLO);lease(p,'SuitcaseHeavyUntil',now)
    face(p,'Squint',.5,now) -- so heavy, so sleepy
    if now>=s.snoreAt then
     s.snoreAt=now+SUIT.SNORE_EVERY;m:SetAttribute('SnoreAt',now)
     Audio.Play(cue('SuitcaseSnore','MonsterIdle'),m);evidence(m.PrimaryPart.Position,SUIT.SNORE_NOISE,'snoring suitcase',m)
     face(p,'Sad',1.2,now)
    end
   end
  end
 end,
 clearPlayer=function(p)for _,s in pairs(suits)do if s.helper==p then endHelp(s)end;s.since[p]=nil end end,
 clearLevel=function()for _,s in pairs(suits)do endHelp(s)end;table.clear(suits)end,
 debug=function()
  local list={};for m,s in pairs(suits)do table.insert(list,{model=m:GetFullName(),helper=s.helper and s.helper.Name or nil,snoreAt=s.snoreAt,strap=s.strap~=nil})end
  return list
 end,
}
for _,key in ipairs({'SuitcaseHeavyUntil','SuitcaseDuoUntil','SuitcaseHelpUntil','SuitcaseHelpOwner'})do table.insert(KEYS,key)end

-- TreatSack (Halloween) ------------------------------------------------------------------------------------
-- While held, every CANDY_EVERY studs walked adds a candy: fixed value per candy (scaled like LootBudget), and the
-- holder walks slower per candy. The candy, value and weight stay on the sack for the next carrier.
local SACK={EVERY=18,MAX=12,VALUE=3,SLOW=.035,MAX_STEP=12}
local CANDY_PARTS={CandyA=3,CandyB=6,CandyC=9,CandyD=12}
local sacks={} -- [Model]={walked=n,last=Vector3?}
local function valueScale()
 local state=RS:FindFirstChild('RecoveryRound');local round=state and tonumber(state:GetAttribute('Round'))or 1
 return 1+.12*(math.max(1,round)-1)
end
local function showCandy(m,count)
 for name,need in pairs(CANDY_PARTS)do
  local part=m:FindFirstChild(name,true)
  if part and part:IsA('BasePart')then part.Transparency=count>=need and 0 or 1 end
 end
end
ITEMS.TreatSack={
 pickup=function(p,m,now)
  if not M.HalloweenLive()then return end
  local s=sacks[m]or{walked=0};sacks[m]=s;s.last=nil -- a new carrier starts measuring from where they stand
  showCandy(m,m:GetAttribute('Candy')or 0);Audio.Play('ClothHandle',m);face(p,'Grin',1,now)
 end,
 tick=function(now)
  local live=M.HalloweenLive()
  for m,s in pairs(sacks)do
   if not m.Parent then sacks[m]=nil;continue end
   local candy=m:GetAttribute('Candy')or 0
   local p=holderOf(m);local r=p and rootOf(p)
   if not live or not r then s.last=nil;continue end
   if candy>0 then slow(p,1-SACK.SLOW*candy)end
   local flat=Vector3.new(r.Position.X,0,r.Position.Z)
   if s.last then local step=(flat-s.last).Magnitude;if step<SACK.MAX_STEP then s.walked+=step end end
   s.last=flat
   if candy>=SACK.MAX then s.walked=0;continue end
   while s.walked>=SACK.EVERY and candy<SACK.MAX do
    s.walked-=SACK.EVERY;candy+=1
    local v=m:GetAttribute('LootValue');if type(v)~='number'then v=m:GetAttribute('Value')end
    setValue(m,(type(v)=='number'and v or 0)+math.max(1,math.floor(SACK.VALUE*valueScale()+.5)))
    m:SetAttribute('Candy',candy);m:SetAttribute('SackSpeed',1-SACK.SLOW*candy)
    showCandy(m,candy);Audio.Play('ItemRattle',m);evidence(r.Position,10+candy*2,'candy rustle',m)
    if candy>=9 then face(p,'Sad',.9,now)else face(p,'Grin',.9,now)end -- so heavy...
   end
  end
 end,
 clearPlayer=function(_p)end,
 clearLevel=function()table.clear(sacks)end,
 debug=function()local list={};for m,s in pairs(sacks)do table.insert(list,{model=m:GetFullName(),walked=s.walked,candy=m:GetAttribute('Candy')})end;return list end,
}

-- PumpkinGrin (Halloween) ----------------------------------------------------------------------------------
-- Face by the nearest creature (Calm grin / Wary squint / Scared "O"); shrieks on entering Scared and every 12 s
-- while scared; crouching muffles it. Keeps watching after you let go; sleeps in the cart, on sale, or after the event.
-- The holder's own face copies the pumpkin's.
local FACES={'FaceCalm','FaceWary','FaceScared'}
local FACE_COLOR={Calm=Color3.fromRGB(255,170,60),Wary=Color3.fromRGB(255,222,90),Scared=Color3.fromRGB(205,240,255),Sleep=Color3.fromRGB(170,110,45)}
local GLOW={Calm={12,1.4},Wary={14,1.8},Scared={16,2.4}}
local PUMP={FLARE=3,FLARE_RANGE=26,FLARE_BRIGHT=3,WARY=50,SCARED=22,HYST=4,SHRIEK=40,COOLDOWN=12}
local pumpkins={} -- [Model]={face=string?,shriekAt=t,flareUntil=t}
local function looseOf(m)
 return m.Parent~=nil and m:IsDescendantOf(workspace)and m:GetAttribute('HeldBy')==nil and not m:GetAttribute('Selling')and not m:GetAttribute('CargoStored')
end
local function pumpkinGlow(root)
 local light=root:FindFirstChild('PumpkinGlow')
 if not light then light=Instance.new('PointLight');light.Name='PumpkinGlow';light.Shadows=false;light.Parent=root end
 return light
end
local function showFace(m,s,f)
 if s.face==f then return end
 s.face=f;m:SetAttribute('PumpkinFace',f)
 for _,name in ipairs(FACES)do
  local part=m:FindFirstChild(name,true)
  if part and part:IsA('BasePart')then
   local on=name=='Face'..f or(f=='Sleep'and name=='FaceCalm')
   part.Transparency=on and(f=='Sleep'and .55 or 0)or 1
   part.Color=FACE_COLOR[f];part.Material=f=='Sleep'and Enum.Material.SmoothPlastic or Enum.Material.Neon
  end
 end
end
ITEMS.PumpkinGrin={
 pickup=function(p,m,now)
  if not M.HalloweenLive()then return end
  local s=pumpkins[m]or{shriekAt=0};pumpkins[m]=s;s.flareUntil=now+PUMP.FLARE -- on grab: the candle flares
  face(p,'Grin',1.5,now)
 end,
 tick=function(now)
  local live=M.HalloweenLive()
  for m,s in pairs(pumpkins)do
   local root=m.PrimaryPart
   if not m.Parent or not root then pumpkins[m]=nil;continue end
   local p=holderOf(m);local light=pumpkinGlow(root)
   if not live or not(p or looseOf(m))then showFace(m,s,'Sleep');light.Enabled=false;light:SetAttribute('GlowBase',nil);continue end
   local chased=p~=nil and(p:GetAttribute('ChasedUntil')or 0)>now
   local d=nearestCreature(root.Position)
   local f
   if chased or d<PUMP.SCARED+(s.face=='Scared'and PUMP.HYST or 0)then f='Scared'
   elseif d<PUMP.WARY+((s.face=='Scared'or s.face=='Wary')and PUMP.HYST or 0)then f='Wary'
   else f='Calm'end
   showFace(m,s,f)
   if p then if f=='Scared'then face(p,'Pout',.5,now)elseif f=='Wary'then face(p,'Squint',.5,now)else face(p,'Grin',.5,now)end end
   local g=GLOW[f];local flare=now<s.flareUntil;local base=flare and PUMP.FLARE_BRIGHT or g[2]
   light.Enabled=true;light.Color=FACE_COLOR[f];light.Range=flare and PUMP.FLARE_RANGE or g[1]
   light.Brightness=base;light:SetAttribute('GlowBase',base) -- CursedBatchBClient flickers around GlowBase
   if f=='Scared'and now>=s.shriekAt then
    s.shriekAt=now+PUMP.COOLDOWN
    if p and p:GetAttribute('Crouching')==true then
     Audio.Play('ClothHandle',m);m:SetAttribute('PumpkinMuffledAt',now) -- crouched: the holder's hand covers its mouth
    else
     Audio.Play(cue('PumpkinShriek','ScareWhisper'),m);evidence(root.Position,PUMP.SHRIEK,'pumpkin shriek',m)
     m:SetAttribute('PumpkinShriekAt',now)
    end
   end
  end
 end,
 clearPlayer=function(_p)end,
 clearLevel=function()table.clear(pumpkins)end,
 debug=function()local list={};for m,s in pairs(pumpkins)do table.insert(list,{model=m:GetFullName(),face=s.face})end;return list end,
}

-- PuppetCross ----------------------------------------------------------------------------------------------
-- Grab: strings latch onto the nearest monster within RANGE; it only moves while the holder moves (CalmUntil while
-- the holder stands still). Snaps (angry lure to the holder's spot) after 10 s, on a sprint, or past SNAP_RANGE.
local PUP={RANGE=35,SECONDS=15,SNAP_RANGE=70,STILL=2,REST=25,ANGRY=8} -- owner 2026-10-27 "doesn't cling on properly": 10 s / 45 studs / a flat 18 studs/s sprint line were too strict
-- Sprinting snaps the strings: judged per player (their walk/sprint speeds include upgrades, boosts and the 2x Speed pass),
-- 60% of the way from walk to sprint, held for two ticks so a bump or a step down never counts.
local function sprinting(p,s,v)
 local walk=p:GetAttribute('UpgradeWalkSpeed')or 13.5;local run=p:GetAttribute('UpgradeSprintSpeed')or 21.5
 local line=walk+(math.max(run,walk+2)-walk)*.6
 s.fast=v>=line and(s.fast or 0)+1 or 0
 return s.fast>=2
end
local STRING_COLOR=Color3.fromRGB(240,230,205)
local PUPPET_GLOW=Color3.fromRGB(150,95,255)
local BAR_POINTS={Vector3.new(0,.33,-.5),Vector3.new(-.8,.25,0),Vector3.new(.8,.25,0),Vector3.new(0,.33,.5)}
local puppets={} -- [item]={holder=Player,monster=Model,ends=clock,parts={Instance},beams={Beam}}
local function attach(parent,name,position)local a=Instance.new('Attachment');a.Name=name;a.Position=position;a.Parent=parent;return a end
local function puppetString(a0,a1,parent)
 local b=Instance.new('Beam');b.Name='PuppetString';b.Attachment0=a0;b.Attachment1=a1
 b.Color=ColorSequence.new(STRING_COLOR);b.Width0=.07;b.Width1=.05;b.FaceCamera=true;b.LightEmission=.35;b.LightInfluence=.4
 b.Segments=12;b.Transparency=NumberSequence.new(.05);b.Parent=parent;return b
end
local function nearestMonster(pos)
 local best,bestD=nil,PUP.RANGE
 for _,n in ipairs(creatures())do
  local root=n:IsA('Model')and n.PrimaryPart
  if root and n:GetAttribute('CreatureKind')and not n:GetAttribute('PuppetedBy')then
   local d=(root.Position-pos).Magnitude
   if d<bestD then best,bestD=n,d end
  end
 end
 return best
end
local function cutStrings(m,angry)
 local s=puppets[m];if not s then return end
 puppets[m]=nil
 for _,x in ipairs(s.parts)do if x.Parent then x:Destroy()end end
 local n=s.monster
 if n.Parent then
  if n:GetAttribute('PuppetedBy')==s.holder.UserId then n:SetAttribute('PuppetedBy',nil)end
  if angry then
   local c=living(s.holder);local root=c and c:FindFirstChild('HumanoidRootPart')
   if root then n:SetAttribute('LurePosition',root.Position);n:SetAttribute('LureUntil',os.clock()+PUP.ANGRY)end
   if n.PrimaryPart then Audio.Play('MonsterNotice',n.PrimaryPart)end
   if s.holder.Parent then
    notice(s.holder,'SNAP! The strings broke and it is coming for you.')
    local now=workspace:GetServerTimeNow();face(s.holder,'Pout',1.6,now);s.holder:SetAttribute('PuppetSnapAt',now)
   end
  end
 end
 if m.Parent then m:SetAttribute('StringsRestUntil',os.clock()+PUP.REST);m:SetAttribute('PuppetActive',false)end
end
local function startPuppet(p,m,c,now)
 if puppets[m]or not m.PrimaryPart then return end
 if os.clock()<(m:GetAttribute('StringsRestUntil')or 0)then
  Audio.Play('StingCreak',m.PrimaryPart);notice(p,'The strings are tangled. Give it a moment.');return
 end
 local root=c:FindFirstChild('HumanoidRootPart');if not root then return end
 local n=nearestMonster(root.Position)
 if not n then Audio.Play('ScareWhisper',m.PrimaryPart);notice(p,'The strings go slack. Nothing close enough to play with.');face(p,'Sad',1.2,now);return end
 local nRoot=n.PrimaryPart
 local box,size=n:GetBoundingBox()
 local top=box.Position+box.UpVector*size.Y*.5
 local side=box.RightVector*size.X*.35;local drop=box.UpVector*size.Y*.25
 local s={holder=p,monster=n,ends=os.clock()+PUP.SECONDS,parts={},beams={}}
 -- strings hold onto the monster's biggest visible part (its body), not the invisible root, so they move with it
 local body,bodyV=nRoot,0
 for _,x in ipairs(n:GetDescendants())do if x:IsA('BasePart')and x.Transparency<.9 then local v=x.Size.X*x.Size.Y*x.Size.Z;if v>bodyV then body,bodyV=x,v end end end
 local function onMonster(name,world)local a=attach(body,name,body.CFrame:PointToObjectSpace(world));table.insert(s.parts,a);return a end
 local ends={onMonster('PuppetHead',top),onMonster('PuppetLeft',top-side-drop),onMonster('PuppetRight',top+side-drop),onMonster('PuppetBack',top-box.LookVector*size.Z*.3)}
 for i,point in ipairs(BAR_POINTS)do
  local a=attach(m.PrimaryPart,'PuppetBar'..i,point);table.insert(s.parts,a)
  local b=puppetString(a,ends[i],m.PrimaryPart);table.insert(s.parts,b);table.insert(s.beams,b)
 end
 local glow=Instance.new('PointLight');glow.Name='PuppetGlow';glow.Color=PUPPET_GLOW;glow.Range=10;glow.Brightness=1.5;glow.Parent=nRoot
 table.insert(s.parts,glow)
 n:SetAttribute('PuppetedBy',p.UserId);m:SetAttribute('PuppetActive',true)
 puppets[m]=s
 Audio.Play('StingCreak',m.PrimaryPart);face(p,'Grin',2,now)
 notice(p,'The strings caught the '..tostring(n:GetAttribute('CreatureKind'))..'. Stand still and it stands still.')
end
ITEMS.PuppetCross={
 pickup=function(p,m,now)local c=living(p);if c then startPuppet(p,m,c,now)end end,
 tick=function(now)
  local clock=os.clock()
  for m,s in pairs(puppets)do
   local p=s.holder;local n=s.monster
   if not m.Parent or holderOf(m)~=p or not n.Parent or not n.PrimaryPart then cutStrings(m,false);continue end
   local root=rootOf(p);if not root then cutStrings(m,false);continue end
   local v=flatSpeed(p)
   if clock>=s.ends or sprinting(p,s,v)or(n.PrimaryPart.Position-root.Position).Magnitude>PUP.SNAP_RANGE then cutStrings(m,true);continue end
   local still=v<PUP.STILL
   if still then n:SetAttribute('CalmUntil',math.max(n:GetAttribute('CalmUntil')or 0,clock+LEASE));face(p,'Squint',.5,now)end
   lease(p,'PuppetUntil',now)
   for i,b in ipairs(s.beams)do local sway=still and math.sin(clock*3+i)*.8 or 0;b.CurveSize0=sway;b.CurveSize1=-sway end
  end
 end,
 clearPlayer=function(p)for m,s in pairs(puppets)do if s.holder==p then cutStrings(m,false)end end end,
 clearLevel=function()for m in pairs(puppets)do cutStrings(m,false)end;table.clear(puppets)end,
 debug=function()local list={};for m,s in pairs(puppets)do table.insert(list,{model=m:GetFullName(),monster=s.monster:GetFullName()})end;return list end,
}
table.insert(KEYS,'PuppetUntil');table.insert(KEYS,'PuppetSnapAt')

-- PogoSpring -----------------------------------------------------------------------------------------------
-- While held: lease PogoUntil; the holder's client auto-hops (CursedBatchBClient). The server makes the hops loud
-- (noise every POGO.EVERY s while moving on foot, louder every 4th) and grins the face. Sprint is blocked in publish().
local POGO={EVERY=.9,NOISE=24,SUPER_NOISE=36,MOVING=2}
local pogos={} -- [Player]={nextAt=t,count=n}
ITEMS.PogoSpring={
 pickup=function(p,m,now)
  Audio.Play(cue('PogoBoing','ClownHonk'),m);face(p,'Grin',1.5,now)
  if not m:GetAttribute('PogoTold')then m:SetAttribute('PogoTold',true);notice(p,'Boing! Every step is a hop. Crouch to plant it.')end
 end,
 tick=function(now,list)
  local held={}
  for _,m in ipairs(list)do
   local p=holderOf(m)
   if p then
    held[p]=true;lease(p,'PogoUntil',now)
    local s=pogos[p]or{nextAt=now+POGO.EVERY,count=0};pogos[p]=s
    local r=rootOf(p)
    if r and flatSpeed(p)>POGO.MOVING and p:GetAttribute('Crouching')~=true then
     face(p,'Grin',.5,now)
     if now>=s.nextAt then
      s.nextAt=now+POGO.EVERY;s.count+=1
      evidence(r.Position,s.count%4==0 and POGO.SUPER_NOISE or POGO.NOISE,'pogo boing',m)
     end
    end
   end
  end
  for p in pairs(pogos)do if not held[p]then pogos[p]=nil end end
 end,
 clearPlayer=function(p)pogos[p]=nil end,
 clearLevel=function()table.clear(pogos)end,
}
table.insert(KEYS,'PogoUntil')

-- Shared lifecycle -----------------------------------------------------------------------------------------
function M.Configure(drop,clear,parts)detach=drop;clearHold=clear;setParts=parts end
function M.Pickup(p,m)
 local item=ITEMS[m:GetAttribute('ItemId')];if not item or not living(p)or not m.PrimaryPart then return end
 local ok,err=pcall(item.pickup,p,m,workspace:GetServerTimeNow())
 if not ok then warn('[ItemBatch8] pickup '..tostring(m:GetAttribute('ItemId'))..': '..tostring(err))end
end
function M.ClearPlayer(p)
 for _,item in pairs(ITEMS)do item.clearPlayer(p)end
 clearLeases(p);speed[p]=nil
 for _,key in ipairs(KEYS)do p:SetAttribute(key,nil)end
end
function M.ClearLevel()
 for _,item in pairs(ITEMS)do item.clearLevel()end
 for _,p in ipairs(Players:GetPlayers())do M.ClearPlayer(p)end
end
local function lobbyOnly()
 local state=RS:FindFirstChild('LobbyState')
 if not state or state:GetAttribute('Mode')~='Menu'then return false end
 for _,p in ipairs(Players:GetPlayers())do if p:GetAttribute('MissionActive')==true then return false end end
 return true
end
local elapsed=0
Run.Heartbeat:Connect(function(dt)
 if lobbyOnly()then return end
 elapsed+=dt;if elapsed<TICK then return end;elapsed=0
 local now=workspace:GetServerTimeNow();table.clear(speed)
 local byId={}
 local map=workspace:FindFirstChild('Mansion');local interactive=map and map:FindFirstChild('Interactive')
 if interactive then for _,m in ipairs(interactive:GetChildren())do
  local id=m:GetAttribute('ItemId');if id and ITEMS[id]and m.PrimaryPart then byId[id]=byId[id]or{};table.insert(byId[id],m)end
 end end
 for id,item in pairs(ITEMS)do local ok,err=pcall(item.tick,now,byId[id]or{});if not ok then warn('[ItemBatch8] '..id..': '..tostring(err))end end
 for _,p in ipairs(Players:GetPlayers())do
  local s=living(p)and speed[p]or nil;if s and math.abs(s-1)<.001 then s=nil end
  if p:GetAttribute('CoopSpeedScale')~=s then p:SetAttribute('CoopSpeedScale',s)end
 end
end)
-- Studio-only read-only probe for rbxdev scenarios. No RemoteEvent, never created in a live server.
if Run:IsStudio()then
 local old=SS:FindFirstChild('Batch8Test');if old then old:Destroy()end
 local probe=Instance.new('BindableFunction');probe.Name='Batch8Test'
 probe.OnInvoke=function(action,p)
  if action=='state'and typeof(p)=='Instance'and p:IsA('Player')then return {attributes=p:GetAttributes(),speed=p:GetAttribute('CoopSpeedScale')or 1}end
  local item=ITEMS[action];return item and item.debug and item.debug()or false
 end
 probe.Parent=SS
end
Players.PlayerRemoving:Connect(M.ClearPlayer)
return M
