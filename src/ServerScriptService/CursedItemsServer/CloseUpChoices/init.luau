-- Close-up choices (owner requests 2026-10-24): rare props you GRAB like an item; the first player to grab one claims
-- it (nobody else can until they answer or let go), the prop turns to stare at them, and a YES / NO card asks.
-- CursedItemsServer owns them (it already owns loot); this module holds their rules. Clients draw the card and the
-- prop motion (CloseUpChoiceClient) and ask; the server checks claim, distance and life and decides.
--
--   StrayCat      YES: he leaves a random item worth 25.  NO: a stone statue worth a lot + the level is cursed
--                 (monsters 15% faster and harder hitting, red flicker, tremors; map attribute CatCurse).
--   SleepingPup   YES: one monster sleeps through this level.  NO: the Lantern bursts out of it, extremely fast,
--                 hunting only you; it lifts you and gives 5 seconds to run. Escape it = it drops an item worth 120.
--   TeaParty      YES: you sit, frozen for 5 s, then +30 HP and an item worth 30.  NO: three dolls get up and slowly
--                 walk after you for the rest of the level; anyone near them is slowed.
--   FortuneTeller YES: draw one card (each player once; anyone may draw after the first YES).  NO: it cracks into a
--                 crystal ball worth 25, the lights flash red and a bulb cracks.
local Players=game:GetService('Players')
local RS=game:GetService('ReplicatedStorage')
local SS=game:GetService('ServerStorage')
local Run=game:GetService('RunService')
local Pathfinding=game:GetService('PathfindingService')

-- Each prop appears once every 3 to 4 levels, picked at random (owner 2026-10-24); never on the tutorial level.
local GAP_MIN,GAP_MAX=2,2 -- was 3,4 (owner 2026-10-25: once every 2 levels)
local FIRST_ROUND_MIN,FIRST_ROUND_MAX=2,2 -- a fresh run meets its first prop on level 2
local BACK_CHANCE=.2 -- usually by the start rooms; this often, unluckily, in the back third of the map
local CLAIM_SECONDS=15 -- time to decide before the card closes and the prop is free again
local CHOICE_REACH=11 -- studs from the player's root to the prop for a claim or an answer
local CAT_GIFT_VALUE,TEA_GIFT_VALUE,HUNT_DROP_VALUE,CRACKED_VALUE,COIN_CARD_VALUE=25,30,120,25,60
local STATUE_QUOTA_SHARE,STATUE_MIN=.45,75
local CAT_LEAVE_SECONDS=6
local TEA_SECONDS,TEA_HEAL=5,30
local PUP_WAKE_SECONDS=2.2 -- the pup shakes and opens its eyes, then the Lantern bursts out
local HUNT_SPEED,HUNT_RISE,HUNT_SECONDS=30,1.2,45 -- extremely fast (sprint is 20); surviving the hunt also counts as escaping
local DOLL_COUNT,DOLL_SPEED,DOLL_CATCHUP_SPEED,DOLL_SLOW_RADIUS,DOLL_SLOW=3,7,10,7,.6
local DOLL_STUCK_SECONDS,DOLL_BLINK_MIN=3,10 -- a doll stuck this long reappears at least this far behind its player
local RED_FLASH_SECONDS=3.5

local M={}
local ctx,event
local nextRound -- the level the next random prop appears on
local claims={} -- prop -> {player, untilT}
local drawn=setmetatable({},{__mode='k'}) -- fortune prop -> {[userId]=true}
local dolls={} -- {model, hum, root, owner, angle, nextPath, waypoints, index}
local hunts={} -- {player, model, untilT, pos}
local Health
local Extra=require(script:WaitForChild('ExtraChoices')) -- the second set of props (2026-10-25)
local Extra2=require(script:WaitForChild('ExtraChoices2')) -- the third set: FrostyFridge, ShyMailbox, SleepyLamp, TwinTeddies, PadlockKing, StaringOwl (2026-10-27)

local function now()return workspace:GetServerTimeNow()end
local function living(p)
 local c=p and p.Character;local h=c and c:FindFirstChildOfClass('Humanoid');local r=c and c:FindFirstChild('HumanoidRootPart')
 return h and r and h.Health>0 and p.Parent==Players and p:GetAttribute('MissionActive')==true and p:GetAttribute('RoundDead')~=true and r or nil
end
local function api(name)return SS:FindFirstChild(name)end

-- Words on every panel, short and plain so a young player gets it in one look (owner 2026-10-24).
-- yes/no: the big button word, then one short line that says what happens.
local DEFS={
 StrayCat={kit='StrayCat',verb='PET THE CAT',title='Save the cat?',whisper='A little cat is scared.',
  yes={'YES','He gives you a gift'},no={'NO','He turns to stone. Monsters get faster!'}},
 SleepingPup={kit='SleepingPup',verb='LOOK AT IT',title='Let it sleep?',whisper='A monster pup is sleeping.',
  yes={'YES','One monster goes to sleep'},no={'NO','It wakes up! Run away to win $120'}},
 TeaParty={kit='TeaParty',verb='HAVE TEA',title='Have tea with the dolls?',whisper='They saved you a seat.',
  yes={'YES','Sit 5 seconds. Get health and a gift'},no={'NO','The dolls will follow you'}},
 FortuneTeller={kit='FortuneTeller',verb='TOUCH THE BALL',title='Pick a card?',whisper='The magic ball can see you.',
  yes={'YES','Get a surprise card. One each!'},no={'NO','Break it for $25. Lights go red!'}},
}
for id,d in Extra.Defs do DEFS[id]=d end
for id,d in Extra2.Defs do DEFS[id]=d end
M.Defs=DEFS

-- Fortune cards: name, symbol, the line on the card, good or bad, and what it does.
local CARDS={
 {name='THE FEATHER',symbol='F',text='You run faster for 1 minute!',good=true},
 {name='THE CHAINS',symbol='C',text='You walk slower for 45 seconds.',good=false},
 {name='THE HEART',symbol='H',text='You get 40 health back!',good=true},
 {name='THE THORN',symbol='T',text='Ouch! You lose 25 health.',good=false},
 {name='THE COIN',symbol='$',text='A $60 gift drops next to you!',good=true},
 {name='THE EYE',symbol='E',text='Uh oh! The monsters know where you are.',good=false},
 {name='THE VEIL',symbol='V',text='Monsters cannot see you for 20 seconds!',good=true},
 {name='THE CROW',symbol='W',text='The closest monster freezes for 20 seconds!',good=true},
}
M.Cards=CARDS
local LEASES={'CardSpeedUntil','CardSlowUntil','DollSlowUntil','TeaUntil','ChoiceFreezeUntil','ChoiceDeciding'}
for _,k in Extra.Leases do LEASES[#LEASES+1]=k end
for _,k in Extra2.Leases do LEASES[#LEASES+1]=k end

-- Walk-speed scale for CursedSpeedMultiplier (CursedItemsServer's 4 Hz player loop).
function M.SpeedScale(p)
 local t=now();local s=1
 -- Frozen while deciding, sitting for tea or watching the pup wake (works for every device and control scheme).
 if t<(p:GetAttribute('TeaUntil')or 0)or t<(p:GetAttribute('ChoiceFreezeUntil')or 0)or p:GetAttribute('ChoiceDeciding')then return 0 end
 if t<(p:GetAttribute('CardSpeedUntil')or 0)then s*=1.25 end
 if t<(p:GetAttribute('CardSlowUntil')or 0)then s*=.75 end
 if t<(p:GetAttribute('DollSlowUntil')or 0)then s*=DOLL_SLOW end
 s*=Extra2.SpeedScale(p,t) -- the third set: ice cube, heavy mailbox, cold (ExtraChoices2)
 return s
end

-- A floor spot for `template` near `centre` (rings of 8 directions), or nil.
local function floorSpot(template,centre,from,to)
 local b=ctx.lootBounds(template)
 for dist=from,to,.75 do
  for i=0,7 do
   local a=i*math.pi/4;local x,z=centre.X+math.cos(a)*dist,centre.Z+math.sin(a)*dist
   local pos=ctx.supported(template,x,z,ctx.map.Collision,centre.Y+3,centre.Y-4,true)
   if pos and ctx.clear(template,pos,nil)then
    local op=OverlapParams.new();op.FilterType=Enum.RaycastFilterType.Exclude;op.FilterDescendantsInstances={ctx.map.Collision}
    local free=true
    for _,hit in workspace:GetPartBoundsInBox(CFrame.new(pos+b.centre+Vector3.new(0,.1,0)),b.size,op)do
     if hit.CanCollide or (hit.Transparency<1 and hit:FindFirstAncestorOfClass('Model')~=nil)then free=false;break end
    end
    if free then return pos end
   end
  end
 end
end
local function feetOf(m)return m:GetPivot().Position+Vector3.new(0,ctx.lootBounds(m).bottom,0)end
-- The solid floor under `pos`: any collidable surface (the house, the van, a stair), not only the map's Collision folder.
local function groundBelow(pos)
 local skip={ctx.map.Interactive,workspace:FindFirstChild('ChoiceDolls'),workspace:FindFirstChild('RoamingCreatures')}
 for _,q in Players:GetPlayers()do if q.Character then skip[#skip+1]=q.Character end end
 local rp=RaycastParams.new();rp.FilterType=Enum.RaycastFilterType.Exclude;rp.FilterDescendantsInstances=skip;rp.RespectCanCollide=true
 local hit=workspace:Raycast(pos+Vector3.new(0,3,0),Vector3.new(0,-40,0),rp)
 return hit and hit.Normal.Y>.7 and hit.Position or nil
end

-- Spawn a sellable item next to `base` (a floor point). id nil = a random item from this level's loot list.
local function giveItem(id,base,value,tag)
 if not id then local list=ctx.eligible();if #list==0 then return nil end;id=list[ctx.rng:NextInteger(1,#list)]end
 local template=SS.CursedItemKit:FindFirstChild(id);if not template then return nil end
 -- No loot spot near (the van, a stair): stand it on whatever floor is under `base` (owner: an item fell under the van).
 local floor=groundBelow(base)or base
 local pos=floorSpot(template,base,1.2,5)or Vector3.new(base.X,floor.Y-ctx.lootBounds(template).bottom+.05,base.Z)
 local m=template:Clone();m.Name=(tag or 'ChoiceGift')..'_'..id;m:PivotTo(CFrame.new(pos));m.Parent=ctx.map.Interactive;ctx.register(m)
 m:SetAttribute('Value',value);m:SetAttribute('LootValue',value);m:SetAttribute(tag or 'ChoiceGift',true)
 return m
end
M.GiveItem=giveItem -- WallSafe 'worldGift', PuzzleBatch pieces, toy chest toys: same spot finding and registration

-- Placement ----------------------------------------------------------------------------------------------
local function spawnProp(choiceId,round,placed)
 local def=DEFS[choiceId];local template=def and SS.CursedItemKit:FindFirstChild(def.kit)
 if not template or #placed==0 then return nil end
 if not Extra2.CanSpawn(choiceId)then return nil end -- the padlock king only on a level with a locked door
 local order=table.clone(placed)
 for i=#order,2,-1 do local j=ctx.rng:NextInteger(1,i);order[i],order[j]=order[j],order[i]end
 -- Owner 2026-10-25: usually in the rooms by the spawn, sometimes (unlucky) deep in the back. Items in that third
 -- are tried first, the rest after.
 local sp=ctx.map:GetAttribute('SpawnPosition')
 if typeof(sp)=='Vector3'then
  local function dist(m)return m.PrimaryPart and(m.PrimaryPart.Position-sp).Magnitude or math.huge end
  local byDist=table.clone(order);table.sort(byDist,function(a,b)return dist(a)<dist(b)end)
  local third=math.max(1,math.floor(#byDist/3));local back=ctx.rng:NextNumber()<BACK_CHANCE
  local first,seen={},{}
  for i=back and #byDist-third+1 or 1,back and #byDist or third do first[#first+1]=byDist[i];seen[byDist[i]]=true end
  for i=#first,2,-1 do local j=ctx.rng:NextInteger(1,i);first[i],first[j]=first[j],first[i]end
  for _,m in order do if not seen[m]then first[#first+1]=m end end
  order=first
 end
 for _,item in order do
  -- Next to a floor item, never by the start-room bonus, so it is found while exploring.
  -- Ground floor only (owner 2026-10-25): never upstairs (a floor is 16 studs; SpawnPosition is ground level).
  if item.Parent and item.PrimaryPart and item:GetAttribute('BonusLoot')~=true and(typeof(sp)~='Vector3'or math.abs(feetOf(item).Y-sp.Y)<8)then
   local pos=floorSpot(template,feetOf(item),2.5,6)
   if pos then
    local prop=template:Clone();prop.Name=choiceId
    for _,k in {'ItemId','GrabGripOffset','ModelPivotOffset'}do prop:SetAttribute(k,nil)end
    prop:SetAttribute('Kind','choice');prop:SetAttribute('ChoiceId',choiceId);prop:SetAttribute('ChoiceRound',round)
    prop:SetAttribute('DisplayName',def.title);prop:SetAttribute('ChoiceVerb',def.verb)
    prop:SetAttribute('ChoiceYes',def.yes[1]);prop:SetAttribute('ChoiceNo',def.no[1]) -- the words other players see on the panel
    prop:PivotTo(CFrame.new(pos)*CFrame.Angles(0,ctx.rng:NextNumber(0,math.pi*2),0))
    if item:GetAttribute('Room')then prop:SetAttribute('Room',item:GetAttribute('Room'))end
    prop.Parent=ctx.map.Interactive
    return prop
   end
  end
 end
end

-- Studio only (CursedItemsServer attribute StudioVanChoices = true, or a comma list of ids): the props stand on the
-- van floor at the start of every level so the owner can try them without searching.
local VAN_SPOTS={Vector3.new(-7,0,-14),Vector3.new(7,0,-14),Vector3.new(-7,0,0),Vector3.new(7,0,0),Vector3.new(-7,0,12),Vector3.new(7,0,12),
 Vector3.new(-7,0,-21),Vector3.new(7,0,-21),Vector3.new(-7,0,-7),Vector3.new(7,0,-7),Vector3.new(-7,0,6),Vector3.new(7,0,6)} -- 11 props since 2026-10-25
local function placeInVan(list,round)
 local camp=workspace:FindFirstChild('RecoveryCamp');local van=camp and camp:FindFirstChild('AnomalyRecoveryVan')
 local floor=van and(van.PrimaryPart or van:FindFirstChild('Floor',true))
 if not floor then return end
 local i=0
 for id in list:gmatch('[^,%s]+')do
  local def=DEFS[id];local template=def and SS.CursedItemKit:FindFirstChild(def.kit)
  local item=not def and SS.CursedItemKit:FindFirstChild(id) -- a normal item id: a real grabbable, sellable copy
  if item and floor then
   i+=1;local spot=VAN_SPOTS[(i-1)%#VAN_SPOTS+1]
   local m=item:Clone();m.Name='VanTest_'..id
   m:PivotTo(floor.CFrame*CFrame.new(spot+Vector3.new(0,floor.Size.Y*.5-ctx.lootBounds(item).bottom+.05,0)))
   m.Parent=ctx.map.Interactive;ctx.register(m);m:SetAttribute('StudioVanTest',true)
  end
  if template then
   i+=1;local spot=VAN_SPOTS[(i-1)%#VAN_SPOTS+1]
   local prop=template:Clone();prop.Name=id
   for _,k in {'ItemId','GrabGripOffset','ModelPivotOffset'}do prop:SetAttribute(k,nil)end
   prop:SetAttribute('Kind','choice');prop:SetAttribute('ChoiceId',id);prop:SetAttribute('ChoiceRound',round)
   prop:SetAttribute('DisplayName',def.title);prop:SetAttribute('ChoiceVerb',def.verb)
   prop:SetAttribute('ChoiceYes',def.yes[1]);prop:SetAttribute('ChoiceNo',def.no[1]);prop:SetAttribute('StudioVanTest',true)
   local lift=floor.Size.Y*.5-ctx.lootBounds(template).bottom+.03
   prop:PivotTo(floor.CFrame*CFrame.new(spot+Vector3.new(0,lift,0))*CFrame.Angles(0,spot.X<0 and -math.pi/2 or math.pi/2,0))
   prop.Parent=ctx.map.Interactive
  end
 end
end

-- Called at the end of every level restock with that level's placed loot.
function M.Restock(round,quota,placed)
 M.quota=quota
 local van=Run:IsStudio()and ctx.script:GetAttribute('StudioVanChoices')
 if van then placeInVan(van==true and 'StrayCat,SleepingPup,TeaParty,FortuneTeller,HungryChest,LonelyBalloon,BirthdayCake,JackInTheBox,Birdcage,GhostJar,Toilet'or tostring(van),round)end
 local forced=Run:IsStudio()and ctx.script:GetAttribute('ForceChoice')
 if type(forced)=='string'and forced~=''then
  for id in forced:gmatch('[^,%s]+')do if DEFS[id]then spawnProp(id,round,placed)end end
  return
 end
 -- ONE prop, picked at random from all of them, every 2 levels (owner 2026-10-25; was every 3 to 4), never two on
 -- one level. First one on level 2 of this server's run (a resumed run starts counting from here).
 -- Owner 2026-10-26: one prop EVERY level except level 1 (was every 2 levels).
 if round<=1 then return end
 local ids={};for id in DEFS do ids[#ids+1]=id end;table.sort(ids)
 for i=#ids,2,-1 do local j=ctx.rng:NextInteger(1,i);ids[i],ids[j]=ids[j],ids[i]end
 for _,id in ids do
  -- placed: the next one comes 3 to 4 levels later; no safe spot for this prop: try another
  if spawnProp(id,round,placed)then nextRound=round+ctx.rng:NextInteger(GAP_MIN,GAP_MAX);return end
 end
 nextRound=round+1 -- no prop found a safe spot this level: try again next level
end

-- Claims -------------------------------------------------------------------------------------------------
local function release(prop,tell)
 local c=claims[prop];claims[prop]=nil
 if c and c.player.Parent then c.player:SetAttribute('ChoiceDeciding',nil)end
 if prop.Parent then prop:SetAttribute('ClaimedBy',nil);prop:SetAttribute('StareAt',nil)end
 if tell and c and c.player.Parent then event:FireClient(c.player,'close',prop)end
end
local function claimOf(p)for prop,c in claims do if c.player==p then return prop end end end

-- Results ------------------------------------------------------------------------------------------------
local function result(p,text,tone)if p.Parent then event:FireClient(p,'result',text,tone)end end
-- Answered: no more claims; 3 s later (or when its effect ends, ChoiceBusy) it goes still with an outline (ChoiceSpent).
local function finish(prop)
 prop:SetAttribute('Kind',nil);prop:SetAttribute('ChoiceDone',true)
 task.delay(3,function()if prop.Parent and not prop:GetAttribute('ChoiceBusy')then prop:SetAttribute('ChoiceSpent',true)end end)
end

local function catYes(p,prop)
 finish(prop);prop:SetAttribute('ChoiceAnswer','yes');ctx.Audio.Play('PresentOpen',prop)
 giveItem(nil,feetOf(prop),CAT_GIFT_VALUE,'CatGift')
 result(p,'He purrs and gives you a gift!','good')
 task.delay(CAT_LEAVE_SECONDS,function()if prop.Parent then prop:Destroy()end end)
end
local function catNo(p,prop)
 finish(prop);local cf=prop:GetPivot();local room=prop:GetAttribute('Room');prop:Destroy()
 local template=SS.CursedItemKit:FindFirstChild('StoneCat')
 if template then
  local statue=template:Clone();statue.Name='StoneCat';statue:PivotTo(cf);statue.Parent=ctx.map.Interactive;ctx.register(statue)
  local value=math.max(STATUE_MIN,math.floor((M.quota or 0)*STATUE_QUOTA_SHARE))
  statue:SetAttribute('Value',value);statue:SetAttribute('LootValue',value)
  if room then statue:SetAttribute('Room',room)end
  ctx.Audio.Play('StingThunder',statue);ctx.Audio.Play('MirrorSting',statue)
 end
 ctx.map:SetAttribute('CatCurse',true);ctx.map:SetAttribute('CatCurseBy',p.DisplayName)
 result(p,'He turned to stone. Monsters are faster now!','bad')
end

local function pupYes(p,prop)
 finish(prop);prop:SetAttribute('ChoiceAnswer','yes')
 local weapons=api('CreatureWeaponApi')
 local name=weapons and weapons:Invoke('dismiss')
 ctx.Audio.Play('MusicBox',prop)
 result(p,name and 'Shh... one monster went to sleep.'or 'Shh... it is still sleeping.','good')
end
local function pupNo(p,prop)
 finish(prop);prop:SetAttribute('ChoiceAnswer','no');prop:SetAttribute('Waking',true)
 local pos=feetOf(prop)
 event:FireClient(p,'cinematic','pupWake',prop,{wake=PUP_WAKE_SECONDS,rise=HUNT_RISE})
 p:SetAttribute('ChoiceFreezeUntil',now()+PUP_WAKE_SECONDS+HUNT_RISE+.4)
 ctx.Audio.Play('Heartbeat',prop);ctx.Audio.Play('StingCreak',prop)
 task.delay(PUP_WAKE_SECONDS,function()
  local burst=prop.Parent and prop.PrimaryPart
  if burst then
   local a=Instance.new('Attachment');a.Parent=workspace.Terrain;a.WorldPosition=burst.Position
   local fx=Instance.new('ParticleEmitter');fx.Texture='rbxasset://textures/particles/smoke_main.dds';fx.Color=ColorSequence.new(Color3.fromRGB(74,58,110),Color3.fromRGB(28,26,36))
   fx.Size=NumberSequence.new(2,6);fx.Transparency=NumberSequence.new(.2,1);fx.Lifetime=NumberRange.new(1,1.8);fx.Speed=NumberRange.new(6,14);fx.SpreadAngle=Vector2.new(180,180);fx.Rate=0;fx.Parent=a
   fx:Emit(60);game:GetService('Debris'):AddItem(a,3)
  end
  if prop.Parent then prop:Destroy()end
  ctx.Audio.Play('StingThunder',burst or nil)
  local weapons=api('CreatureWeaponApi')
  local model=weapons and living(p)and weapons:Invoke('hunt',nil,p,{pos=pos,speed=HUNT_SPEED,rise=HUNT_RISE,headStart=.2})
  if typeof(model)=='Instance'then
   hunts[#hunts+1]={player=p,model=model,untilT=os.clock()+HUNT_RISE+HUNT_SECONDS}
   event:FireClient(p,'cinematic','hunterOut',model,{rise=HUNT_RISE})
   -- Out of the floor, it grabs them straight away (owner: no wandering): the lift, then the 5-second run.
   task.delay(HUNT_RISE+.1,function()if model.Parent and living(p)then weapons:Invoke('grab',model,p)end end)
  end
 end)
end

local function spawnDolls(p,prop)
 local kit=SS:FindFirstChild('ChoiceKit');local template=kit and kit:FindFirstChild('ChoiceDoll');if not template then return end
 local folder=workspace:FindFirstChild('ChoiceDolls')or Instance.new('Folder');folder.Name='ChoiceDolls';folder.Parent=workspace
 local tint={Color3.fromRGB(150,112,214),Color3.fromRGB(70,176,166),Color3.fromRGB(64,82,150)}
 for i=1,DOLL_COUNT do
  local seat=prop:FindFirstChild('Doll'..i)
  local at=(seat and seat.Position or prop:GetPivot().Position)*Vector3.new(1,0,1)+Vector3.new(0,feetOf(prop).Y,0)
  local d=template:Clone();d.Name='TeaDoll'..i
  d.Torso.Color=tint[(i-1)%#tint+1]
  d:PivotTo(CFrame.new(at+Vector3.new(0,1.45,0)))
  d:SetAttribute('FollowUserId',p.UserId)
  d.Parent=folder
  pcall(function()d.HumanoidRootPart:SetNetworkOwner(nil)end)
  local hum=d:FindFirstChildOfClass('Humanoid');hum.WalkSpeed=DOLL_SPEED
  dolls[#dolls+1]={model=d,hum=hum,root=d.HumanoidRootPart,owner=p,angle=(i-1)*math.pi*2/DOLL_COUNT,nextPath=0,nextGiggle=os.clock()+math.random(6,14)}
 end
end
local function teaYes(p,prop)
 finish(prop);prop:SetAttribute('ChoiceAnswer','yes')
 local r=living(p);if not r then return end
 p:SetAttribute('TeaUntil',now()+TEA_SECONDS);prop:SetAttribute('StareAt',p.UserId);prop:SetAttribute('ChoiceBusy',true)
 event:FireClient(p,'cinematic','tea',prop,{seconds=TEA_SECONDS})
 r.Anchored=true;ctx.Audio.Play('MusicBox',prop)
 task.delay(TEA_SECONDS,function()
  if r.Parent then r.Anchored=false end
  if prop.Parent then prop:SetAttribute('StareAt',nil);prop:SetAttribute('ChoiceBusy',nil);prop:SetAttribute('ChoiceSpent',true)end
  p:SetAttribute('TeaUntil',nil)
  if not living(p)then return end
  if not Health then Health=require(game:GetService('ServerScriptService'):WaitForChild('PlayerHealth'))end
  Health.Heal(p,TEA_HEAL,'teaParty')
  if prop.Parent then giveItem(nil,feetOf(prop),TEA_GIFT_VALUE,'TeaGift')end
  result(p,'+30 health! The dolls left you a gift.','good')
 end)
end
local function teaNo(p,prop)
 finish(prop);prop:SetAttribute('ChoiceAnswer','no')
 ctx.Audio.Play('DollCry',prop);ctx.Audio.Play('StingCreak',prop)
 spawnDolls(p,prop)
 for i=1,DOLL_COUNT do local seat=prop:FindFirstChild('Doll'..i);if seat then seat.Transparency=1 end end -- they stood up
 result(p,'The dolls are coming with you...','bad')
end

local function drawCard(p,prop)
 local seen=drawn[prop]or{};drawn[prop]=seen;seen[p.UserId]=true
 prop:SetAttribute('CardsDrawn',(prop:GetAttribute('CardsDrawn')or 0)+1)
 local index=ctx.rng:NextInteger(1,#CARDS);local card=CARDS[index]
 local r=living(p);local t=now()
 if card.name=='THE FEATHER'then p:SetAttribute('CardSpeedUntil',t+60)
 elseif card.name=='THE CHAINS'then p:SetAttribute('CardSlowUntil',t+45)
 elseif card.name=='THE HEART'or card.name=='THE THORN'then
  if not Health then Health=require(game:GetService('ServerScriptService'):WaitForChild('PlayerHealth'))end
  if card.name=='THE HEART'then Health.Heal(p,40,'fortuneCard')
  else local h=p.Character and p.Character:FindFirstChildOfClass('Humanoid');local hurt=h and math.min(25,math.max(0,h.Health-10))or 0
   if hurt>0 then Health.Damage(p,hurt,'fortuneCard')end end
 elseif card.name=='THE COIN'then if r then giveItem(nil,r.Position-Vector3.new(0,3,0),COIN_CARD_VALUE,'CardGift')end
 elseif card.name=='THE EYE'then local bus=SS:FindFirstChild('MonsterEvidence');if bus and r then bus:Fire(r.Position,100,'fortune eye')end
 elseif card.name=='THE VEIL'then p:SetAttribute('DisguiseUntil',os.clock()+20)
 elseif card.name=='THE CROW'and r then
  local best,bd;local folder=workspace:FindFirstChild('RoamingCreatures')
  if folder then for _,m in folder:GetChildren()do local pp=m:IsA('Model')and m.PrimaryPart;if pp then local d=(pp.Position-r.Position).Magnitude;if not bd or d<bd then best,bd=m,d end end end end
  if best then best:SetAttribute('CalmUntil',os.clock()+20)end
 end
 ctx.Audio.Play(card.good and 'PresentOpen'or 'StingCreak',prop)
 event:FireClient(p,'card',{name=card.name,symbol=card.symbol,text=card.text,good=card.good})
end
local function fortuneNo(p,prop)
 finish(prop);local cf=prop:GetPivot();local base=feetOf(prop);local room=prop:GetAttribute('Room')
 ctx.Audio.Play('BulbCrack',prop);ctx.Audio.Play('MirrorSting',prop)
 ctx.map:SetAttribute('RedFlashAt',cf.Position);ctx.map:SetAttribute('RedFlashUntil',now()+RED_FLASH_SECONDS)
 prop:Destroy()
 local template=SS.CursedItemKit:FindFirstChild('CrackedCrystalBall')
 if template then
  local ball=template:Clone();ball.Name='CrackedCrystalBall';ball:PivotTo(CFrame.new(base+Vector3.new(0,ctx.lootBounds(template).size.Y*.5+.05,0)))
  ball.Parent=ctx.map.Interactive;ctx.register(ball);ball:SetAttribute('Value',CRACKED_VALUE);ball:SetAttribute('LootValue',CRACKED_VALUE)
  if room then ball:SetAttribute('Room',room)end
 end
 result(p,'It broke! The lights flash red.','bad')
end

local ANSWER={
 StrayCat={yes=catYes,no=catNo},SleepingPup={yes=pupYes,no=pupNo},TeaParty={yes=teaYes,no=teaNo},
 FortuneTeller={yes=drawCard,no=fortuneNo},
}
for id,a in Extra.Answer do ANSWER[id]=a end
for id,a in Extra2.Answer do ANSWER[id]=a end

-- Remote ---------------------------------------------------------------------------------------------------
local function near(p,prop)
 local r=living(p);return r and prop.PrimaryPart and(prop.PrimaryPart.Position-r.Position).Magnitude<=CHOICE_REACH
end
local function onEvent(p,action,prop,answer)
 if typeof(prop)~='Instance'or not prop:IsA('Model')or prop.Parent~=ctx.map.Interactive then return end
 local id=prop:GetAttribute('ChoiceId');local def=DEFS[id]
 if action=='wind'then Extra.Wind(p,prop);return end -- the jack-in-the-box crank (after YES)
 if action=='stare'then Extra2.Stare(p,prop);return end -- the staring owl (after YES)
 if not def or prop:GetAttribute('Kind')~='choice'then return end
 if action=='claim'then
  if not near(p,prop)then return end
  local c=claims[prop]
  if c and c.player~=p then event:FireClient(p,'deny',prop,'Someone else is picking.');return end
  if c then return end -- the same player's grab again (a click on their own panel): the card is already up
  if claimOf(p)and claimOf(p)~=prop then return end
  if id=='FortuneTeller'and drawn[prop]and drawn[prop][p.UserId]then event:FireClient(p,'deny',prop,'You already picked a card.');return end
  local gate=Extra2.ClaimGate(p,prop,id);if gate then event:FireClient(p,'deny',prop,gate);return end -- twin teddies: no second vote
  local deadline=now()+CLAIM_SECONDS
  claims[prop]={player=p,untilT=deadline};p:SetAttribute('ChoiceDeciding',true)
  prop:SetAttribute('ClaimedBy',p.UserId);prop:SetAttribute('StareAt',p.UserId)
  local copy={id=id,title=def.title,whisper=def.whisper,yes=def.yes,no=def.no,deadline=deadline}
  if id=='FortuneTeller'and(prop:GetAttribute('CardsDrawn')or 0)>0 then copy.whisper='Someone already picked one.'end
  copy.whisper=Extra2.Whisper(p,prop,id)or copy.whisper
  event:FireClient(p,'open',prop,copy)
 elseif action=='answer'then
  local c=claims[prop];if not c or c.player~=p or(answer~='yes'and answer~='no')or not near(p,prop)then return end
  release(prop,false)
  local handler=ANSWER[id]and ANSWER[id][answer]
  if handler then handler(p,prop)end
 elseif action=='cancel'then
  local c=claims[prop];if c and c.player==p then release(prop,false)end
 end
end

-- Dolls, hunts and claim expiry ------------------------------------------------------------------------------
local function dollTarget(d)
 local r=living(d.owner)
 if not r then -- their friend is gone: the closest living player
  local best,bd
  for _,q in Players:GetPlayers()do local qr=living(q);if qr then local dist=(qr.Position-d.root.Position).Magnitude;if not bd or dist<bd then best,bd=q,dist end end end
  if best then d.owner=best;d.model:SetAttribute('FollowUserId',best.UserId);r=living(best)end
 end
 return r
end
-- A floor spot 10 to 16 studs behind the player (outside their view), clear of walls, or nil.
local function behind(r,d)
 local back=-r.CFrame.LookVector*Vector3.new(1,0,1);if back.Magnitude<.1 then return nil end;back=back.Unit
 local side=Vector3.new(-back.Z,0,back.X)
 -- Anything solid except people, dolls, monsters and items (map floors are not all in Collision).
 local skip={ctx.map.Interactive,workspace:FindFirstChild('ChoiceDolls'),workspace:FindFirstChild('RoamingCreatures')}
 for _,q in Players:GetPlayers()do if q.Character then skip[#skip+1]=q.Character end end
 local rp=RaycastParams.new();rp.FilterType=Enum.RaycastFilterType.Exclude;rp.FilterDescendantsInstances=skip;rp.RespectCanCollide=true
 local op=OverlapParams.new();op.FilterType=Enum.RaycastFilterType.Exclude;op.FilterDescendantsInstances=skip;op.RespectCanCollide=true
 for _,dist in {DOLL_BLINK_MIN,13,16}do for _,s in {0,-3,3,-6,6}do
  local at=r.Position+back*dist+side*(s+math.cos(d.angle)*2) -- each doll a little apart
  local hit=workspace:Raycast(at+Vector3.new(0,3,0),Vector3.new(0,-9,0),rp)
  local wall=workspace:Raycast(r.Position,at-r.Position,rp) -- same room: no wall between them and the spot
  if hit and hit.Normal.Y>.8 and not wall then
   local spot=hit.Position+Vector3.new(0,1.45,0)
   if #workspace:GetPartBoundsInBox(CFrame.new(spot+Vector3.new(0,.3,0)),Vector3.new(1.2,2.4,1.2),op)==0 then return spot end
  end
 end end
end
local function stepDoll(d,t)
 if not d.model.Parent or not d.root.Parent then return false end
 local r=dollTarget(d);if not r then d.hum:Move(Vector3.zero);return true end
 local goal=r.Position+Vector3.new(math.cos(d.angle)*3,0,math.sin(d.angle)*3) -- walks near them, never on them
 local dist=(r.Position-d.root.Position).Magnitude
 d.hum.WalkSpeed=dist>40 and DOLL_CATCHUP_SPEED or DOLL_SPEED
 if t>=d.nextPath then
  d.nextPath=t+1
  local path=Pathfinding:CreatePath({AgentRadius=1,AgentHeight=3,AgentCanJump=true}) -- stair steps
  local ok=pcall(function()path:ComputeAsync(d.root.Position,goal)end)
  if ok and path.Status==Enum.PathStatus.Success then d.waypoints=path:GetWaypoints();d.index=math.min(2,#d.waypoints)else d.waypoints=nil end
 end
 if d.waypoints and d.waypoints[d.index]then
  local wp=d.waypoints[d.index].Position
  if Vector3.new(wp.X-d.root.Position.X,0,wp.Z-d.root.Position.Z).Magnitude<1.5 then d.index+=1 end
  local wpNext=d.waypoints[d.index]
  if wpNext and wpNext.Action==Enum.PathWaypointAction.Jump then d.hum.Jump=true end
  d.hum:MoveTo(wpNext and wpNext.Position or goal)
 elseif dist>3.5 then d.hum:MoveTo(goal)end
 -- Stuck (a closed door, no path): when the player is not looking, the doll is simply somewhere behind them.
 if dist>DOLL_BLINK_MIN then
  if not d.lastPos or(d.root.Position-d.lastPos).Magnitude>1 then d.lastPos=d.root.Position;d.stuckSince=t end
  if t-(d.stuckSince or t)>DOLL_STUCK_SECONDS then
   local spot=behind(r,d)
   if spot then d.model:PivotTo(CFrame.lookAt(spot,Vector3.new(r.Position.X,spot.Y,r.Position.Z)));d.lastPos=nil;d.waypoints=nil;d.nextPath=0 end
   d.stuckSince=t
  end
 else d.stuckSince=t end
 if t>=d.nextGiggle then d.nextGiggle=t+math.random(10,18);ctx.Audio.Play('DollCry',d.root)end
 for _,q in Players:GetPlayers()do
  local qr=living(q);if qr and(qr.Position-d.root.Position).Magnitude<DOLL_SLOW_RADIUS then q:SetAttribute('DollSlowUntil',now()+.6)end
 end
 return true
end
local function endHunt(h,escaped)
 local weapons=api('CreatureWeaponApi')
 local pos=h.model.Parent and h.model.PrimaryPart and h.model.PrimaryPart.Position
 if weapons and h.model.Parent then weapons:Invoke('dismiss',h.model)end
 if escaped and pos and h.player.Parent then
  local lantern=SS.CursedItemKit:FindFirstChild('Lantern')and 'Lantern'or nil
  giveItem(lantern,groundBelow(pos)or pos-Vector3.new(0,3,0),HUNT_DROP_VALUE,'HunterDrop')
  result(h.player,'You got away! It dropped a $120 lantern.','good')
 end
end
local acc=0
local function heartbeat(dt)
 acc+=dt;if acc<.25 then return end;acc=0
 local t,clock=now(),os.clock()
 for prop,c in claims do
  if not prop.Parent or t>c.untilT or not living(c.player)or not near(c.player,prop)then release(prop,true)end
 end
 for i=#dolls,1,-1 do if not stepDoll(dolls[i],clock)then table.remove(dolls,i)end end
 for i=#hunts,1,-1 do
  local h=hunts[i];local result_=h.model:GetAttribute('HuntResult')
  if result_=='escaped'or(clock>h.untilT and living(h.player))then table.remove(hunts,i);endHunt(h,true)
  elseif result_=='caught'or not h.model.Parent or not living(h.player)then table.remove(hunts,i);endHunt(h,false)end
 end
end

function M.ClearLevel()
 if not ctx then return end
 if ctx.map:GetAttribute('CatCurse')~=nil then ctx.map:SetAttribute('CatCurse',nil);ctx.map:SetAttribute('CatCurseBy',nil)end
 ctx.map:SetAttribute('RedFlashUntil',nil)
 for prop in claims do release(prop,true)end
 for _,d in dolls do if d.model.Parent then d.model:Destroy()end end;table.clear(dolls)
 for _,h in hunts do endHunt(h,false)end;table.clear(hunts)
 Extra.ClearLevel()
 Extra2.ClearLevel()
 for _,p in Players:GetPlayers()do for _,k in LEASES do if p:GetAttribute(k)~=nil then p:SetAttribute(k,nil)end end end
end

-- ctx: map, script, rng, Audio, register, lootBounds, supported, clear, eligible() -> live eligible id list.
function M.Init(c)
 ctx=c
 event=RS:FindFirstChild('CloseUpChoiceEvent')or Instance.new('RemoteEvent')
 event.Name='CloseUpChoiceEvent';event.Parent=RS
 event.OnServerEvent:Connect(onEvent)
 Run.Heartbeat:Connect(heartbeat)
 local shared={ctx=ctx,event=event,giveItem=giveItem,feetOf=feetOf,result=result,finish=finish,living=living,now=now,api=api,groundBelow=groundBelow}
 Extra.Init(shared);Extra2.Init(shared)
 Players.PlayerRemoving:Connect(function(p)local prop=claimOf(p);if prop then release(prop,false)end end)
 task.spawn(function()
  local roundState=RS:WaitForChild('RecoveryRound',math.huge)
  roundState:GetAttributeChangedSignal('Round'):Connect(M.ClearLevel)
  roundState:GetAttributeChangedSignal('Phase'):Connect(function()
   local phase=roundState:GetAttribute('Phase');if phase=='Won'or phase=='Failed'or phase=='Deploying'then M.ClearLevel()end
  end)
 end)
end

return M
