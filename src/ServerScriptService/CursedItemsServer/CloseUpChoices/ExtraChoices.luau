-- Close-up choices, second set (owner 2026-10-25). Same claim / YES-NO card as CloseUpChoices (which requires this
-- module and owns the claims); this module holds the seven newer props and what each answer does.
--   HungryChest   YES: 15 s to drop an item in its mouth; it spits it back worth 50% more, happy, then sleeps.
--                 Too slow: it just falls asleep.  NO: it snaps and bites you twice (10 each), then sleeps.
--   LonelyBalloon YES: it follows you; the first monster that comes close is eaten (gone for the level, drops a
--                 Monster Orb) and the balloon pops.  NO: its golden ribbon ($75) drops and the balloon floats away.
--   BirthdayCake  YES: +40 HP, but the birthday song calls every monster nearby.  NO: take the cake ($100); its
--                 candles keep relighting with the song and show the monsters where it is.
--   JackInTheBox  YES: wind the crank before it pops: $90 of loot. Too slow: the clown screams, monsters come.
--                 NO: take the unopened box ($45).
--   Birdcage      YES: the bird flies to the nearest monsters and marks them, chirping (monsters hear it).
--                 NO: sell the antique cage ($90); something keeps tapping inside it.
--   GhostJar      YES: the ghost leads you to a valuable item.  NO: it pretends the same... and leads you to a monster.
--   Toilet        YES: flush: an $85 item shoots out, very loud.  NO: nothing happens at all.
local Players=game:GetService('Players')
local SS=game:GetService('ServerStorage')
local Run=game:GetService('RunService')
local Pathfinding=game:GetService('PathfindingService')

local CHEST_DROP_RADIUS,CHEST_DROP_SECONDS=10,3 -- an item let go of (dropped or thrown, how phones feed it) this close, this soon after, is eaten too
local recentHeld=setmetatable({},{__mode='k'}) -- item -> os.clock() it was last seen held
local CHEST_SECONDS,CHEST_MOUTH,CHEST_BONUS,CHEST_BITE,CHEST_BITE_RANGE=15,3.4,1.5,10,12
local BALLOON_EAT_RADIUS,BALLOON_FLY,BALLOON_SWALLOW=16,.7,1.1
local CAKE_HEAL,CAKE_VALUE,CAKE_RELIGHT_MIN,CAKE_RELIGHT_MAX,CAKE_LIT_SECONDS=40,100,18,28,6
local JACK_SECONDS,JACK_WINDS,JACK_LOOT,JACK_PIECES,JACK_BOX_VALUE=12,12,90,3,45 -- 12 looks up/down in 12 s (was 16 in 10; owner: easier)
local CAGE_VALUE,CAGE_MARK_SECONDS,CAGE_MARK_RANGE,CAGE_TAP_MIN,CAGE_TAP_MAX=90,8,90,14,28
local GHOST_SPEED,GHOST_WAIT,GHOST_ARRIVE,GHOST_MONSTER_ARRIVE,GHOST_SECONDS=14,14,7,10,70 -- the trick ghost takes you right up to the monster (was 22); speed 11 -> 14 to catch a roaming one
local TOILET_VALUE=85

local X={}
local S -- shared helpers from CloseUpChoices (ctx, event, giveItem, feetOf, result, finish, living, now, api)
local Health
local chests,balloons,cakes,jacks,cages,flyers,ghosts={},{},{},{},{},{},{}

X.Defs={
 HungryChest={kit='HungryChest',verb='OPEN THE CHEST',title='Feed me something?',whisper='The chest is SO hungry.',
  yes={'YES','Bring it an item in 15 seconds'},no={'NO','It gets mad and bites!'}},
 LonelyBalloon={kit='LonelyBalloon',verb='HOLD THE STRING',title='Will you be my friend?',whisper='The balloon is all alone.',
  yes={'YES','It follows you and eats a monster'},no={'NO','Take its golden ribbon ($75)'}},
 BirthdayCake={kit='Cake',verb='LOOK AT THE CAKE',title='Blow out the candles?',whisper='Somebody left a birthday cake.',
  yes={'YES','+40 health, but monsters hear the song'},no={'NO','Take the cake ($100). It keeps singing!'}},
 JackInTheBox={kit='JackInTheBox',verb='PICK UP THE BOX',title='Do you want to play?',whisper='Something is waiting inside.',
  yes={'YES','Wind it before it pops: $90!'},no={'NO','Take the closed box ($45)'}},
 Birdcage={kit='Birdcage',verb='LOOK IN THE CAGE',title='Let the bird out?',whisper='A little bird taps the bars.',
  yes={'YES','It finds the monsters (and sings)'},no={'NO','Sell the old cage ($90)'}},
 GhostJar={kit='GhostJar',verb='TOUCH THE JAR',title='Will you set me free?',whisper='A tiny ghost is stuck inside.',
  yes={'YES','It shows you something good'},no={'NO','Keep it in the jar'}},
 Toilet={kit='Toilet',verb='LOOK AT THE TOILET',title='Flush it?',whisper='Something is down there...',
  yes={'YES','Flush! (It is LOUD)'},no={'NO','Leave it alone'}},
}
X.Leases={'BalloonSafeUntil'}

local function evidence(pos,loudness,kind,actor)
 local bus=SS:FindFirstChild('MonsterEvidence');if bus and pos then bus:Fire(pos,loudness,kind,actor)end
end
-- The birthday song: soft, and it fades out as you walk away (gone past 35 studs; owner 2026-10-25).
local function song(at)
 local part=at and(at:IsA('BasePart')and at or at.PrimaryPart);if not part then return end
 local old=part:FindFirstChild('BirthdaySong');if old then old:Destroy()end
 local snd=Instance.new('Sound');snd.Name='BirthdaySong';snd.SoundId='rbxassetid://97102550389175';snd.Volume=.32
 snd.RollOffMode=Enum.RollOffMode.InverseTapered;snd.RollOffMinDistance=5;snd.RollOffMaxDistance=35
 local group=game:GetService('SoundService'):FindFirstChild('GameplaySFX');if group then snd.SoundGroup=group end
 snd.Parent=part;snd:Play();game:GetService('Debris'):AddItem(snd,16)
end
-- Done with it: it stands still with an outline and can't be grabbed again (CloseUpChoiceClient, InteractController).
local function spend(prop)if prop.Parent then prop:SetAttribute('ChoiceBusy',nil);prop:SetAttribute('ChoiceSpent',true)end end
local function heal(p,n,why)if not Health then Health=require(game:GetService('ServerScriptService'):WaitForChild('PlayerHealth'))end;Health.Heal(p,n,why)end
local function hurt(p,n,why)if not Health then Health=require(game:GetService('ServerScriptService'):WaitForChild('PlayerHealth'))end;Health.Damage(p,n,why)end
local function monsters()
 local w=S.api('CreatureWeaponApi');local ok,list=pcall(function()return w and w:Invoke('list')end)
 return ok and type(list)=='table'and list or{}
end
local function nearestMonster(pos,range,skip)
 local best,bd
 for _,m in monsters()do
  local pp=m.PrimaryPart
  if pp and not(skip and skip(m))then local d=(pp.Position-pos).Magnitude;if d<=(range or math.huge)and(not bd or d<bd)then best,bd=m,d end end
 end
 return best,bd
end
local function fxFolder()
 local f=workspace:FindFirstChild('ChoiceFx')or Instance.new('Folder');f.Name='ChoiceFx';f.Parent=workspace;return f
end
local function ghostly(model)
 for _,d in model:GetDescendants()do if d:IsA('BasePart')then d.Anchored=true;d.CanCollide=false;d.CanTouch=false;d.CanQuery=false end end
end
local function puff(pos,color,count)
 local a=Instance.new('Attachment');a.Parent=workspace.Terrain;a.WorldPosition=pos
 local fx=Instance.new('ParticleEmitter');fx.Texture='rbxasset://textures/particles/sparkles_main.dds';fx.Color=ColorSequence.new(color)
 fx.Size=NumberSequence.new(.6,0);fx.Lifetime=NumberRange.new(.5,1);fx.Speed=NumberRange.new(6,12);fx.SpreadAngle=Vector2.new(180,180);fx.Rate=0;fx.LightEmission=1;fx.Parent=a
 fx:Emit(count or 30);game:GetService('Debris'):AddItem(a,2)
end
local function kitModel(name)
 local kit=SS:FindFirstChild('ChoiceKit');local t=kit and kit:FindFirstChild(name)or SS.CursedItemKit:FindFirstChild(name)
 if not t then return nil end
 local m=t:Clone();for _,k in {'ItemId','Kind','GrabGripOffset','ModelPivotOffset'}do m:SetAttribute(k,nil)end
 ghostly(m);return m
end

-- Hungry chest -------------------------------------------------------------------------------------------------
local function chestYes(p,prop)
 S.finish(prop);prop:SetAttribute('ChoiceAnswer','yes');prop:SetAttribute('ChestMood','hungry')
 local deadline=S.now()+CHEST_SECONDS;prop:SetAttribute('ChestUntil',deadline)
 chests[prop]={player=p,untilT=deadline}
 S.ctx.Audio.Play('Heartbeat',prop)
 prop:SetAttribute('ChoiceBusy',true)
 S.event:FireClient(p,'cinematic','chestTimer',prop,{deadline=deadline})
end
local function chestSleep(prop,text,p)
 chests[prop]=nil;prop:SetAttribute('ChestMood','sleep');prop:SetAttribute('ChestUntil',nil);spend(prop)
 if p and text then S.result(p,text,nil)end
 if p and p.Parent then S.event:FireClient(p,'cinematic','chestDone',prop,{})end
end
local function chestEat(prop,c,m)
 chests[prop]=nil
 local id=m:GetAttribute('ItemId');local value=m:GetAttribute('Value')or m:GetAttribute('LootValue')or 30
 local holder=Players:GetPlayerByUserId(m:GetAttribute('HeldBy')or 0)
 local items=SS:FindFirstChild('CursedItemApi')
 if holder and items then pcall(function()items:Invoke('release',holder)end)end
 prop:SetAttribute('ChestMood','chew')
 S.ctx.Audio.Play('MonsterGrab',prop)
 task.spawn(function()
  task.wait(.15)
  local loot=SS:FindFirstChild('RecoveryLootApi')
  if loot and m.Parent then pcall(function()return loot:Invoke('remove',m)end)end
  if m.Parent then m:Destroy()end
  for _=1,3 do task.wait(.45);if prop.Parent then S.ctx.Audio.Play('MonsterHitThump',prop)end end
  if not prop.Parent then return end
  local worth=math.floor(value*CHEST_BONUS+.5)
  local front=prop:GetPivot().LookVector*Vector3.new(1,0,1);front=front.Magnitude>.1 and front.Unit or Vector3.new(0,0,-1)
  S.giveItem(id,S.feetOf(prop)+front*2.6,worth,'ChestGift')
  S.ctx.Audio.Play('PresentOpen',prop);prop:SetAttribute('ChestMood','happy')
  if c.player.Parent then S.result(c.player,('Yum! It spat it back out, now worth $%d!'):format(worth),'good');S.event:FireClient(c.player,'cinematic','chestDone',prop,{})end
  task.wait(2.2);if prop.Parent then prop:SetAttribute('ChestMood','sleep');spend(prop)end
 end)
end
local function chestNo(p,prop)
 S.finish(prop);prop:SetAttribute('ChoiceAnswer','no');prop:SetAttribute('ChestMood','angry');prop:SetAttribute('StareAt',p.UserId);prop:SetAttribute('ChoiceBusy',true)
 S.ctx.Audio.Play('MonsterNotice',prop)
 task.spawn(function()
  for _,delay in {.35,.4}do
   task.wait(delay)
   local r=S.living(p)
   if r and prop.Parent and(r.Position-prop:GetPivot().Position).Magnitude<=CHEST_BITE_RANGE then
    prop:SetAttribute('ChestBite',S.now());S.ctx.Audio.Play('MonsterHitThump',prop);hurt(p,CHEST_BITE,'hungryChest')
   end
  end
  S.result(p,'CHOMP! It bit you twice, then fell asleep.','bad')
  task.wait(.9);if prop.Parent then prop:SetAttribute('ChestMood','sleep');prop:SetAttribute('StareAt',nil);spend(prop)end
 end)
end

-- Lonely balloon --------------------------------------------------------------------------------------------------
local function balloonYes(p,prop)
 S.finish(prop);prop:SetAttribute('ChoiceAnswer','yes')
 ghostly(prop);prop:SetAttribute('ChoiceId',nil);prop.Name='FriendBalloon_'..p.UserId;prop.Parent=fxFolder()
 local cf=prop:GetPivot()
 balloons[#balloons+1]={player=p,model=prop,cf=cf,state='follow',nextScan=0}
 S.ctx.Audio.Play('HeliumHiss',prop)
 S.result(p,'Your balloon friend will eat the first monster that comes close!','good')
end
local function balloonNo(p,prop)
 S.finish(prop);prop:SetAttribute('ChoiceAnswer','no')
 local ribbon=prop:FindFirstChild('Ribbon',true);if ribbon and ribbon:IsA('BasePart')then ribbon.Transparency=1 end
 S.giveItem('GoldenRibbon',S.feetOf(prop),75,'BalloonRibbon')
 prop:SetAttribute('FloatAway',S.now());prop:SetAttribute('ChoiceBusy',true)
 S.result(p,'You took the golden ribbon ($75). The balloon floats away...',nil)
 task.delay(4,function()if prop.Parent then prop:Destroy()end end)
end
local function balloonEat(b,monster)
 b.state='eat';b.monster=monster;b.t0=os.clock();b.from=b.model:GetPivot()
 -- the orb drops where the monster stood (it is pulled up into the balloon, so its later spot is mid-air)
 b.orbSpot=monster.PrimaryPart and S.groundBelow(monster.PrimaryPart.Position)
 monster:SetAttribute('BalloonDoomed',true);monster:SetAttribute('StunnedUntil',os.clock()+BALLOON_FLY+BALLOON_SWALLOW+1)
 for _,q in Players:GetPlayers()do -- nobody gets hurt by a monster the balloon is already eating
  local r=S.living(q);if r and monster.PrimaryPart and(r.Position-monster.PrimaryPart.Position).Magnitude<40 then q:SetAttribute('BalloonSafeUntil',S.now()+BALLOON_FLY+BALLOON_SWALLOW+1.5)end
 end
 if monster.PrimaryPart then monster.PrimaryPart.Anchored=true end
 S.ctx.Audio.Play('HeliumHiss',b.model)
end
local function balloonPop(b)
 local pos=b.model:GetPivot().Position
 S.ctx.Audio.Play('BalloonPop',b.model.PrimaryPart or b.model:FindFirstChildWhichIsA('BasePart'))
 puff(pos,Color3.fromRGB(190,170,255),50)
 local m=b.monster;local name=m and m.Name
 local w=S.api('CreatureWeaponApi')
 local spot=b.orbSpot or S.groundBelow(pos)or pos
 if m and m.Parent and w then pcall(function()w:Invoke('devour',m)end)end
 if m and m.Parent then m:Destroy()end
 local spawner=SS:FindFirstChild('SpawnGearItem')
 if spawner then pcall(function()
  local orb=spawner:Invoke('MonsterOrb',CFrame.new(spot+Vector3.new(0,.8,0)))
  if orb then puff(spot+Vector3.new(0,1,0),Color3.fromRGB(170,140,255),40);orb:SetAttribute('MonsterName',name);orb:SetAttribute('MonsterRound',(game.ReplicatedStorage:FindFirstChild('RecoveryRound')or workspace):GetAttribute('Round'))end
 end)end
 if b.player.Parent then S.result(b.player,'POP! The balloon ate a monster! It left a Monster Orb.','good')end
 b.model:Destroy()
end
local function stepBalloon(b,dt,t)
 if not b.model.Parent then return false end
 if b.state=='follow'then
  local r=S.living(b.player);if not r then return true end
  local goal=r.Position+r.CFrame.RightVector*2.2-r.CFrame.LookVector*1.2+Vector3.new(0,3.4+math.sin(t*2)*.25,0)
  local cur=b.model:GetPivot();local pos=cur.Position:Lerp(goal,1-math.exp(-dt*5))
  b.model:PivotTo(CFrame.new(pos)*CFrame.Angles(0,math.sin(t*.8)*.4,math.sin(t*1.3)*.08))
  if t>=b.nextScan then
   b.nextScan=t+.2
   local m=nearestMonster(r.Position,BALLOON_EAT_RADIUS,function(x)return x:GetAttribute('BalloonDoomed')==true end)
   if m then balloonEat(b,m)end
  end
 elseif b.state=='eat'then
  local m=b.monster;local mp=m and m.Parent and m.PrimaryPart
  if not mp then balloonPop(b);return false end
  local e=t-b.t0
  local mouth=mp.Position+Vector3.new(0,(m:GetExtentsSize().Y)*.35,0)
  if e<BALLOON_FLY then
   local k=e/BALLOON_FLY;k=k*k*(3-2*k)
   b.model:PivotTo(CFrame.new(b.from.Position:Lerp(mouth+Vector3.new(0,2,0),k)))
  else
   local k=math.clamp((e-BALLOON_FLY)/BALLOON_SWALLOW,0,1)
   if not b.monsterScale then b.monsterScale=m:GetScale();b.monsterCf=m:GetPivot();b.scale=b.model:GetScale()end
   b.model:ScaleTo(b.scale*(1+1.6*math.sin(k*math.pi*.5)))
   b.model:PivotTo(CFrame.new(mouth+Vector3.new(0,2-k*1.5,0))*CFrame.Angles(0,k*6,0))
   pcall(function()m:ScaleTo(math.max(.05,b.monsterScale*(1-k)))end)
   pcall(function()m:PivotTo(b.monsterCf:Lerp(CFrame.new(mouth),k))end)
   if k>=1 then balloonPop(b);return false end
  end
 end
 return true
end

-- Birthday cake ----------------------------------------------------------------------------------------------------
local function candles(m,on)
 local root=m.PrimaryPart;if not root then return end
 local a=root:FindFirstChild('CandleFlames')
 if not a then
  a=Instance.new('Attachment');a.Name='CandleFlames';a.Position=Vector3.new(0,root.Size.Y*.5+.25,0);a.Parent=root
  local fx=Instance.new('ParticleEmitter');fx.Name='Flame';fx.Texture='rbxasset://textures/particles/fire_main.dds'
  fx.Color=ColorSequence.new(Color3.fromRGB(255,214,120));fx.LightEmission=1;fx.Size=NumberSequence.new(.35,.05);fx.Lifetime=NumberRange.new(.25,.45)
  fx.Speed=NumberRange.new(1,2);fx.Rate=40;fx.SpreadAngle=Vector2.new(15,15);fx.Parent=a
  local l=Instance.new('PointLight');l.Name='Glow';l.Color=Color3.fromRGB(255,200,120);l.Range=16;l.Brightness=2.5;l.Parent=a
 end
 for _,c in a:GetChildren()do c.Enabled=on end
end
local function cakeYes(p,prop)
 S.finish(prop);prop:SetAttribute('ChoiceAnswer','yes')
 candles(prop,false);puff(S.feetOf(prop)+Vector3.new(0,1.5,0),Color3.fromRGB(230,230,240),25)
 heal(p,CAKE_HEAL,'birthdayCake')
 song(prop);evidence(S.feetOf(prop),110,'birthday song',p)
 S.result(p,'+40 health! But the monsters heard the birthday song...','bad')
end
local function cakeNo(p,prop)
 S.finish(prop);local base=S.feetOf(prop);prop:Destroy()
 local cake=S.giveItem('BirthdayCake',base,CAKE_VALUE,'CursedCake')
 if cake then cake:SetAttribute('CandleCurse',true);candles(cake,true);task.delay(CAKE_LIT_SECONDS,function()if cake.Parent then candles(cake,false)end end)
  cakes[cake]=os.clock()+S.ctx.rng:NextNumber(CAKE_RELIGHT_MIN,CAKE_RELIGHT_MAX)end
 song(cake);evidence(base,120,'birthday no',p)
 S.result(p,'The candles lit up by themselves! The monsters know where you are. GET OUT!','bad')
end
local function relight(cake)
 candles(cake,true);task.delay(CAKE_LIT_SECONDS,function()if cake.Parent then candles(cake,false)end end)
 song(cake);local pos=cake:GetPivot().Position;evidence(pos,100,'cake candles')
 for _,q in Players:GetPlayers()do
  local r=S.living(q);if r and(r.Position-pos).Magnitude<60 then S.result(q,'The cake candles lit up again! Monsters heard it. Get out of there!','bad')end
 end
end

-- Jack-in-the-box -----------------------------------------------------------------------------------------------------
local function jackYes(p,prop)
 S.finish(prop);prop:SetAttribute('ChoiceBusy',true);prop:SetAttribute('ChoiceAnswer','yes');prop:SetAttribute('JackState','wind');prop:SetAttribute('JackWinds',0)
 local deadline=S.now()+JACK_SECONDS
 jacks[prop]={player=p,winds=0,untilT=deadline,last=0}
 p:SetAttribute('ChoiceDeciding',true) -- still and safe while winding (MonsterProtection, SpeedScale)
 S.ctx.Audio.Play('MusicBox',prop)
 S.event:FireClient(p,'cinematic','jackWind',prop,{deadline=deadline,need=JACK_WINDS})
end
local function jackEnd(prop,j,won)
 jacks[prop]=nil
 if j.player.Parent then j.player:SetAttribute('ChoiceDeciding',nil);S.event:FireClient(j.player,'cinematic','jackDone',prop,{won=won})end
 if not prop.Parent then return end
 if won then
  prop:SetAttribute('JackState','won');S.ctx.Audio.Play('PresentOpen',prop)
  for i=1,JACK_PIECES do S.giveItem(nil,S.feetOf(prop),math.floor(JACK_LOOT/JACK_PIECES),'JackLoot_'..i)end
  S.result(j.player,'You did it! The box gave you $90 of loot!','good')
 else
  prop:SetAttribute('JackState','pop')
  S.ctx.Audio.Play('ClownHonk',prop);S.ctx.Audio.Play('NeonNotice',prop);S.ctx.Audio.Play('StingChoir',prop)
  evidence(S.feetOf(prop),150,'jack scream',j.player)
  S.result(j.player,'AAAAH! The clown screamed! The monsters are coming!','bad')
 end
 task.delay(won and 1.5 or 2.5,function()if prop.Parent then puff(S.feetOf(prop)+Vector3.new(0,1,0),Color3.fromRGB(200,180,255),25);prop:Destroy()end end) -- was 6 s
end
local function jackNo(p,prop)
 S.finish(prop);local base=S.feetOf(prop);prop:Destroy()
 S.giveItem('JackInTheBox',base,JACK_BOX_VALUE,'JackBox')
 S.result(p,'You took the closed box ($45). Better not open it...',nil)
end
function X.Wind(p,prop)
 local j=jacks[prop];if not j or j.player~=p then return end
 local t=os.clock();if t-j.last<.06 then return end;j.last=t -- 16 winds a second at most
 j.winds+=1;prop:SetAttribute('JackWinds',j.winds)
 if j.winds>=JACK_WINDS then jackEnd(prop,j,true)end
end

-- Birdcage --------------------------------------------------------------------------------------------------------------
local function cageYes(p,prop)
 S.finish(prop);prop:SetAttribute('ChoiceAnswer','yes');prop:SetAttribute('CageOpen',true)
 local from=prop:GetPivot().Position+Vector3.new(0,1,0)
 S.ctx.Audio.Play('Whistle',prop);evidence(from,60,'bird song',p)
 local marked=0
 for _,m in monsters()do
  local pp=m.PrimaryPart
  if pp and(pp.Position-from).Magnitude<=CAGE_MARK_RANGE then m:SetAttribute('DangerMarkUntil',S.now()+CAGE_MARK_SECONDS);marked+=1 end
 end
 local bird=kitModel('CageBird')
 local target=nearestMonster(from,CAGE_MARK_RANGE)
 if bird then
  bird:PivotTo(CFrame.new(from));bird.Parent=fxFolder()
  flyers[#flyers+1]={model=bird,from=from,target=target,t0=os.clock(),fly=2.5,stay=2}
 end
 S.result(p,marked>0 and'The bird found the monsters! Look for the glow.'or'The bird flew away singing. No monsters near.','good')
end
local function cageNo(p,prop)
 S.finish(prop);local base=S.feetOf(prop);prop:Destroy()
 local cage=S.giveItem('Birdcage',base,CAGE_VALUE,'AntiqueCage')
 if cage then cages[cage]=os.clock()+S.ctx.rng:NextNumber(CAGE_TAP_MIN,CAGE_TAP_MAX)end
 S.result(p,'You kept the old cage ($90). It is empty... right?',nil)
end
local function stepFlyer(f,t)
 if not f.model.Parent then return false end
 local e=t-f.t0
 local goal=f.target and f.target.Parent and f.target.PrimaryPart and f.target.PrimaryPart.Position+Vector3.new(0,5,0)or f.from+Vector3.new(0,6,-20)
 if e<f.fly then
  local k=e/f.fly;local pos=f.from:Lerp(goal,k)+Vector3.new(0,math.sin(k*math.pi)*4,0)
  f.model:PivotTo(CFrame.lookAt(pos,goal))
 elseif e<f.fly+f.stay then
  local a=(e-f.fly)*4;f.model:PivotTo(CFrame.new(goal+Vector3.new(math.cos(a)*2,math.sin(a*2)*.3,math.sin(a)*2))*CFrame.Angles(0,-a,0))
 else puff(f.model:GetPivot().Position,Color3.fromRGB(180,220,255),15);f.model:Destroy();return false end
 return true
end

-- Ghost in a jar --------------------------------------------------------------------------------------------------------
local function bestLoot(exclude)
 local list={}
 for _,m in S.ctx.map.Interactive:GetChildren()do
  if m:IsA('Model')and not(exclude and exclude[m])and m.PrimaryPart and m:GetAttribute('ItemId')and m:GetAttribute('HeldBy')==nil and not m:GetAttribute('CargoStored')and(m:GetAttribute('Value')or 0)>0 then list[#list+1]=m end -- never one already in the cart
 end
 table.sort(list,function(a,b)return(a:GetAttribute('Value')or 0)>(b:GetAttribute('Value')or 0)end)
 if #list==0 then return nil end
 return list[S.ctx.rng:NextInteger(1,math.min(3,#list))]
end
-- The trick ghost's monster: one on the same floor first (a floor is 16 studs), else the nearest anywhere.
local function trickTarget(pos)
 local m=nearestMonster(pos,nil,function(x)return math.abs(x.PrimaryPart.Position.Y-pos.Y)>8 end)
 return m or nearestMonster(pos)
end
-- Can this player actually see the monster? Walls and floors (map Collision) block it.
local sightParams=RaycastParams.new();sightParams.FilterType=Enum.RaycastFilterType.Include
local function seesMonster(r,m)
 local col=S.ctx.map:FindFirstChild('Collision');if not col then return true end
 sightParams.FilterDescendantsInstances={col}
 local from=r.Position+Vector3.new(0,1.5,0);local to=m.PrimaryPart.Position
 return workspace:Raycast(from,to-from,sightParams)==nil
end
local GHOST_SEEK_SECONDS,GHOST_SEE_RANGE=40,24 -- waits this long for a monster; the reveal needs you this close, in sight
local function freeGhost(p,prop,trick)
 S.finish(prop);prop:SetAttribute('ChoiceAnswer',trick and'no'or'yes');prop:SetAttribute('JarOpen',true)
 local from=prop:GetPivot().Position+Vector3.new(0,1.5,0)
 local target;if trick then target=trickTarget(from)else target=bestLoot()end -- (an and/or here fell through to loot)
 S.ctx.Audio.Play('JarPop',prop)
 -- Both answers sound the same: the trick only shows at the end (owner: it must really feel like help).
 S.result(p,trick and'"Okay, okay! I will help you anyway. Follow me!"'or'"Thank you! Follow me, I know a secret!"','good')
 task.delay(2.5,function()if prop.Parent then prop:Destroy()end end)
 if not target and not trick then -- no loot left: it just giggles and is gone
  S.result(p,'"Oh... nothing left to find. Bye!"',nil);return
 end
 -- The trick ghost with no monster about yet hovers by you ('seek') until one turns up (owner 2026-10-25).
 local ghost=kitModel('FriendlyGhost');if not ghost then return end
 ghost:PivotTo(CFrame.new(from));ghost.Parent=fxFolder()
 ghost:SetAttribute('GuideUserId',p.UserId)
 ghost:SetAttribute('GuideTarget',target and target.Name or nil) -- tests read which model it leads to
 ghosts[#ghosts+1]={player=p,model=ghost,target=target,trick=trick,t0=os.clock(),nextPath=0,points=nil,index=1,state=target and'lead'or'seek'}
end
-- Owner 2026-10-28: the ghost flew into locked doors and straight through walls (no route = a beeline to the target).
-- A route is only taken when pathfinding finds one that keeps clear of every locked door; with none the ghost hovers
-- by you, and a loot it cannot reach is swapped for another one.
local function crossesLockedDoor(points)
 local locked={}
 for _,m in S.ctx.map.Interactive:GetChildren()do if m:GetAttribute('Kind')=='door'and m:GetAttribute('Locked')then local cf=m:GetBoundingBox();locked[#locked+1]=cf.Position end end
 if #locked==0 then return false end
 for _,w in points do for _,d in locked do
  if math.abs(w.Position.Y-d.Y)<6 and Vector2.new(w.Position.X-d.X,w.Position.Z-d.Z).Magnitude<3.5 then return true end
 end end
 return false
end
local function ghostPath(g)
 local tp=g.target and g.target.PrimaryPart;if not tp then return end
 local path=Pathfinding:CreatePath({AgentRadius=1.5,AgentHeight=4,AgentCanJump=true})
 local ok=pcall(function()path:ComputeAsync(g.model:GetPivot().Position-Vector3.new(0,2,0),tp.Position)end)
 if ok and path.Status==Enum.PathStatus.Success then
  local pts=path:GetWaypoints()
  if not crossesLockedDoor(pts)then g.points=pts;g.index=math.min(2,#pts);g.fails=0;return end
 end
 g.fails=(g.fails or 0)+1
 if not g.trick and g.fails>=2 then
  g.bad=g.bad or{};g.bad[g.target]=true
  local other=bestLoot(g.bad);if other then g.target=other;g.points=nil;g.fails=0;g.model:SetAttribute('GuideTarget',other.Name)end
 end
end
local function stepGhost(g,dt,t)
 if not g.model.Parent then return false end
 local cur=g.model:GetPivot().Position
 local r=S.living(g.player)
 if g.state=='seek'then -- the trick ghost with no monster yet: bobs beside you, checking every half second
  if not r or t-g.t0>GHOST_SEEK_SECONDS then g.state='leave';g.t1=t;if r then S.result(g.player,'"Hmm... nobody to play with. Bye!"',nil)end;return true end
  if t>=(g.nextSeek or 0)then g.nextSeek=t+.5;local m=trickTarget(cur);if m then g.target=m;g.state='lead';g.t0=t;g.model:SetAttribute('GuideTarget',m.Name)end end
  local spot=r.Position+r.CFrame.LookVector*4+Vector3.new(0,2.5,0);local step=spot-cur
  local pos=cur+(step.Magnitude>0 and step.Unit*math.min(step.Magnitude,GHOST_SPEED*dt)or Vector3.zero)
  g.model:PivotTo(CFrame.lookAt(pos,Vector3.new(r.Position.X,pos.Y,r.Position.Z))+Vector3.new(0,math.sin(t*3)*.02,0))
  return true
 end
 -- a trick ghost whose monster died or left the map picks another one
 if g.trick and g.state=='lead'and not(g.target and g.target.Parent and g.target.PrimaryPart)then
  local m=trickTarget(cur);if m then g.target=m;g.points=nil;g.model:SetAttribute('GuideTarget',m.Name)end
 end
 local tp=g.target and g.target.Parent and g.target.PrimaryPart
 if g.state=='lead'then
  if not r or not tp or t-g.t0>GHOST_SECONDS then g.state='leave';g.t1=t;return true end
  if t>=g.nextPath and not g.pathing then g.nextPath=t+(g.trick and .7 or 1.5);g.pathing=true;task.spawn(function()ghostPath(g);g.pathing=false end)end
  local d=(tp.Position-cur).Magnitude
  -- The trick only springs once YOU can see the monster, close up (it used to fire through walls and floors).
  local arrived=if g.trick then d<=GHOST_MONSTER_ARRIVE and r and(r.Position-tp.Position).Magnitude<=GHOST_SEE_RANGE and seesMonster(r,g.target)else d<=GHOST_ARRIVE
  if arrived then
   g.state=g.trick and'leave'or'show';g.t1=t
   if g.trick then
    g.model:SetAttribute('Giggle',true);S.ctx.Audio.Play('DollCry',g.model.PrimaryPart or g.model:FindFirstChildWhichIsA('BasePart'))
    if r then evidence(r.Position,100,'ghost trick',g.player);S.result(g.player,'"Hee hee! Bye bye!" ...it led you to a MONSTER!','bad')end -- only said within GHOST_MONSTER_ARRIVE of a live monster
   else g.target:SetAttribute('GhostMarkUntil',S.now()+12);S.result(g.player,'"Here it is! Something valuable!"','good')end
   return true
  end
  local far=r and(r.Position-cur).Magnitude>GHOST_WAIT
  local goal
  if g.points and g.points[g.index]then
   goal=g.points[g.index].Position+Vector3.new(0,3,0)
   if(goal-cur).Magnitude<1.5 then g.index+=1 end
  elseif g.points then goal=tp.Position+Vector3.new(0,3,0) -- walked the whole route: the last bit is in the same room
  end
  if not goal then -- no route yet: never a beeline through walls or a locked door; it hovers by you until it finds one
   if r then
    local spot=r.Position+r.CFrame.LookVector*3+Vector3.new(0,2.5,0);local step=spot-cur
    local pos=cur+(step.Magnitude>0 and step.Unit*math.min(step.Magnitude,GHOST_SPEED*dt)or Vector3.zero)
    g.model:PivotTo(CFrame.lookAt(pos,Vector3.new(r.Position.X,pos.Y,r.Position.Z))+Vector3.new(0,math.sin(t*3)*.02,0))
   end
   return true
  end
  local look=r and r.Position or goal
  if far then -- waits for you, turning to wave you on
   g.model:PivotTo(CFrame.lookAt(cur,Vector3.new(look.X,cur.Y,look.Z))+Vector3.new(0,math.sin(t*3)*.02,0))
  else
   local step=(goal-cur);local move=step.Magnitude>0 and step.Unit*math.min(step.Magnitude,GHOST_SPEED*dt)or Vector3.zero
   local pos=cur+move;g.model:PivotTo(CFrame.lookAt(pos,pos+(move.Magnitude>0 and move*Vector3.new(1,0,1)+Vector3.new(0,0,.001)or Vector3.new(0,0,-1)))+Vector3.new(0,math.sin(t*3)*.02,0))
  end
 elseif g.state=='show'then
  local a=(t-g.t1)*3;local c=tp and tp.Position+Vector3.new(0,2.5,0)or cur
  g.model:PivotTo(CFrame.new(c+Vector3.new(math.cos(a)*2.5,math.sin(a*2)*.3,math.sin(a)*2.5))*CFrame.Angles(0,-a,0))
  if t-g.t1>3 then g.state='leave';g.t1=t end
 else -- flies up and fades away
  local k=(t-g.t1)/1.6
  g.model:PivotTo(g.model:GetPivot()+Vector3.new(0,dt*8,0))
  for _,d in g.model:GetDescendants()do if d:IsA('BasePart')then d.LocalTransparencyModifier=0;d.Transparency=math.max(d.Transparency,math.min(1,k))end end
  if k>=1 then g.model:Destroy();return false end
 end
 return true
end

-- Toilet ----------------------------------------------------------------------------------------------------------------
local function toiletYes(p,prop)
 S.finish(prop);prop:SetAttribute('ChoiceAnswer','yes');prop:SetAttribute('Flushing',S.now())
 S.ctx.Audio.Play('ToiletFlush',prop);evidence(S.feetOf(prop),130,'toilet flush',p)
 task.delay(1.3,function()
  if not prop.Parent then return end
  local cf=prop:GetPivot();local front=cf.LookVector*Vector3.new(1,0,1);front=front.Magnitude>.1 and front.Unit or Vector3.new(0,0,-1)
  local land=S.feetOf(prop)+front*3.2
  local m=S.giveItem(nil,land,TOILET_VALUE,'ToiletGift')
  if m then -- shoots out of the bowl in an arc onto the floor
   local endCf=m:GetPivot();local start=cf.Position+Vector3.new(0,1.6,0)
   task.spawn(function()
    local t0=os.clock()
    while m.Parent and os.clock()-t0<.55 do
     local k=(os.clock()-t0)/.55;m:PivotTo(CFrame.new(start:Lerp(endCf.Position,k)+Vector3.new(0,math.sin(k*math.pi)*3,0))*CFrame.Angles(k*8,k*5,0));Run.Heartbeat:Wait()
    end
    if m.Parent then m:PivotTo(endCf)end
   end)
  end
  S.result(p,'WHOOSH! Something shot out ($85)... that was SO loud!','bad')
 end)
end
local function toiletNo(p,prop)
 S.finish(prop);prop:SetAttribute('ChoiceAnswer','no')
 S.event:FireClient(p,'dots')
end

X.Answer={
 HungryChest={yes=chestYes,no=chestNo},LonelyBalloon={yes=balloonYes,no=balloonNo},BirthdayCake={yes=cakeYes,no=cakeNo},
 JackInTheBox={yes=jackYes,no=jackNo},Birdcage={yes=cageYes,no=cageNo},
 GhostJar={yes=function(p,prop)freeGhost(p,prop,false)end,no=function(p,prop)freeGhost(p,prop,true)end},
 Toilet={yes=toiletYes,no=toiletNo},
}

-- Every frame: the movers (balloons, the bird, ghosts). Four times a second: chest mouths, jack timers, cakes, cages.
local acc=0
local function heartbeat(dt)
 local t=os.clock()
 for i=#balloons,1,-1 do if not stepBalloon(balloons[i],dt,t)then table.remove(balloons,i)end end
 for i=#flyers,1,-1 do if not stepFlyer(flyers[i],t)then table.remove(flyers,i)end end
 for i=#ghosts,1,-1 do if not stepGhost(ghosts[i],dt,t)then table.remove(ghosts,i)end end
 acc+=dt;if acc<.25 then return end;acc=0
 local now=S.now()
 for prop,c in chests do
  if not prop.Parent then chests[prop]=nil
  elseif now>c.untilT then chestSleep(prop,'It got bored and fell asleep. Zzz...',c.player)
  else
   local mouth=prop:GetPivot().Position+Vector3.new(0,S.ctx.lootBounds(prop).size.Y*.5,0)
   for _,m in S.ctx.map.Interactive:GetChildren()do
    -- held up to it, or dropped in from above: never the loot lying on the floor beside it
    -- the pivot, not PrimaryPart: a held item has no PrimaryPart while it is in someone's hands
    local pos=m:IsA('Model')and m~=prop and m:GetAttribute('ItemId')and m:GetPivot().Position
    if pos then
     local held=m:GetAttribute('HeldBy')~=nil;if held then recentHeld[m]=t end
     local d=(pos-mouth).Magnitude
     local dropped=not held and recentHeld[m]and t-recentHeld[m]<=CHEST_DROP_SECONDS and d<=CHEST_DROP_RADIUS
     if dropped or(held or pos.Y>=mouth.Y-1)and d<=CHEST_MOUTH then chestEat(prop,c,m);break end
    end
   end
  end
 end
 for prop,j in jacks do
  if not prop.Parent or not j.player.Parent then jacks[prop]=nil;if j.player.Parent then j.player:SetAttribute('ChoiceDeciding',nil)end
  elseif now>j.untilT or not S.living(j.player)then jackEnd(prop,j,false)end
 end
 for cake,nextT in cakes do
  if not cake.Parent then cakes[cake]=nil elseif t>=nextT then cakes[cake]=t+S.ctx.rng:NextNumber(CAKE_RELIGHT_MIN,CAKE_RELIGHT_MAX);relight(cake)end
 end
 for cage,nextT in cages do
  if not cage.Parent then cages[cage]=nil elseif t>=nextT then cages[cage]=t+S.ctx.rng:NextNumber(CAGE_TAP_MIN,CAGE_TAP_MAX);S.ctx.Audio.Play('StingKnock',cage)end
 end
end

function X.ClearLevel()
 for _,j in jacks do if j.player.Parent then j.player:SetAttribute('ChoiceDeciding',nil)end end
 table.clear(jacks);table.clear(chests);table.clear(cakes);table.clear(cages)
 for _,list in {balloons,flyers,ghosts}do for _,x in list do if x.model.Parent then x.model:Destroy()end end;table.clear(list)end
 local f=workspace:FindFirstChild('ChoiceFx');if f then f:ClearAllChildren()end
end

function X.Init(shared)
 S=shared
 Run.Heartbeat:Connect(heartbeat)
end

return X
