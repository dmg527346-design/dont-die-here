-- Close-up choices, third set (owner 2026-10-27). Same claim / YES-NO card as CloseUpChoices (which requires this
-- module next to ExtraChoices and owns the claims, the remote, SpeedScale and the leases); this module holds six props.
--   FrostyFridge  YES: every monster freezes for 20 s, but you are an ice cube for the first 8.
--                 NO: +60 s on the level clock, but everyone walks cold and slow (70%) for 30 s.
--   ShyMailbox    YES: 15 s to hold an item up to its door; it mails it into the cart and keeps 20% as a stamp.
--                 NO: take the mailbox itself ($110); it is so heavy you walk at 60% while you carry it.
--   SleepyLamp    YES: a big golden flashlight beam for 60 s; while it is on, monsters hear it every 6 s.
--                 NO: it eats your flashlight light for 45 s; take the lamp ($90), it glows a little in your hands.
--   TwinTeddies   TWO players vote in secret. Same answer wins: both YES = +35 health and a $35 gift each, both NO =
--                 a $120 gift. Different answers: the teddies cry so loud the monsters come, both voters slowed 8 s.
--                 Alone (or nobody comes in 30 s), the second teddy votes for itself.
--   PadlockKing   YES: every locked door on the level pops open for the whole team, but monsters can walk through
--                 those doors now and every padlock CLANGS.  NO: take the sleepy padlock ($70); its keys jingle.
--   StaringOwl    YES: the owl flies a figure-eight; keep it in your crosshair 5 of 9 seconds for $80. Lose: it
--                 screeches in your face and the monsters hear.  NO: it flies off, leaving a $30 gift.
-- Every answer has a funny beat (owner 2026-10-27): a face every player sees (FaceBeat: grin / gasp / pucker, drawn by
-- VoiceMouthClient; or CryingUntil, the onion's sob) and a short screen beat for that player (ScreenBeat: a popping
-- word with a tint, wobble or shake, drawn by CloseUpChoiceClient).
local Players=game:GetService('Players')
local SS=game:GetService('ServerStorage')
local Run=game:GetService('RunService')

local DROP_RADIUS,DROP_SECONDS=10,3 -- an item let go of this close, this soon after, counts as fed (how phones feed it)
local FRIDGE_FREEZE,FRIDGE_ICE,FRIDGE_TIME,FRIDGE_CHILL=20,8,60,30
local MAIL_SECONDS,MAIL_SLOT_UP,MAIL_SLOT_FRONT,MAIL_REACH,MAIL_STAMP,MAIL_GULP=15,2,.9,3.4,.8,.7
local MAILBOX_VALUE=110
local HEAVY_SLOW,CHILL_SLOW=.6,.7
local LAMP_BOOST_SECONDS,LAMP_PING_EVERY,LAMP_PING_LOUD,LAMP_EAT_SECONDS,LAMP_VALUE,LAMP_GULP=60,6,45,45,90,1.2
local TEDDY_WAIT,TEDDY_HEAL,TEDDY_HUG_GIFT,TEDDY_TREAT,TEDDY_CRY,TEDDY_SLOW=30,35,35,120,130,8
local PADLOCK_VALUE,PADLOCK_CLANG,PADLOCK_STAGGER,PADLOCK_JINGLE_MIN,PADLOCK_JINGLE_MAX,PADLOCK_JINGLE_LOUD=70,70,.18,14,28,45
local OWL_SECONDS,OWL_NEED,OWL_PRIZE,OWL_GIFT,OWL_SCREECH=9,5,80,30,140
local OWL_RADIUS,OWL_HEIGHT,OWL_TOWARD,OWL_GRACE=3.2,2.2,1.2,.8 -- flight shape (studs) sent to clients as attributes
local OWL_FACING=.3 -- server check: the player's body must roughly face the owl (first person turns the body)

local X={}
local S -- shared helpers from CloseUpChoices (ctx, event, giveItem, feetOf, result, finish, living, now, api, groundBelow)
local Health
local mailboxes,heavies,beams={},setmetatable({},{__mode='k'}),{}
local teddies,padlocks,owls={},{},{}
local recentHeld=setmetatable({},{__mode='k'}) -- item -> os.clock() it was last seen held

X.Defs={
 FrostyFridge={kit='FrostyFridge',verb='OPEN THE FRIDGE',title='Freeze the monsters?',whisper='The fridge is SO cold inside.',
  yes={'YES','Monsters freeze! You freeze too (8 s)'},no={'NO','+1 minute! But everyone walks slow'}},
 ShyMailbox={kit='ShyMailbox',verb='KNOCK ON IT',title='Mail something?',whisper='The mailbox is too shy to say hi.',
  yes={'YES','Mail an item to the cart. It keeps 20%'},no={'NO','Take the mailbox ($110). SO heavy!'}},
 SleepyLamp={kit='SleepyLamp',verb='WAKE THE LAMP',title='Want my light?',whisper='The lamp is too sleepy to shine.',
  yes={'YES','Super flashlight! Monsters see it'},no={'NO','It eats your light. Take it ($90)'}},
 TwinTeddies={kit='TwinTeddies',verb='HOLD A PAW',title='Will your friend say YES?',whisper='Two teddies. Pick the SAME as your friend!',
  yes={'YES','Both YES: +35 health each'},no={'NO','Both NO: a $120 gift'}},
 PadlockKing={kit='PadlockKing',verb='KNOCK ON IT',title='Open every door?',whisper='The padlock king has ALL the keys.',
  yes={'YES','All locked doors open. For monsters too!'},no={'NO','Take the sleepy padlock ($70)'}},
 StaringOwl={kit='StaringOwl',verb='LOOK AT THE OWL',title='Staring contest?',whisper='Its big eyes never blink.',
  yes={'YES','Watch it fly 5 seconds: $80!'},no={'NO','It flies off. Small gift ($30)'}},
}
-- Player leases cleared by CloseUpChoices.ClearLevel (CardSlowUntil and ChoiceDeciding are already there).
X.Leases={'HeavyMailUntil','LampBoostUntil','LampAteLightUntil','IceCubeUntil','ChillyUntil','FaceBeat','FaceBeatUntil','ScreenBeat','ScreenBeatAt'}

-- Walk-speed share for CloseUpChoices.SpeedScale (server time): the ice cube stands still, the heavy mailbox and
-- the fridge's cold slow you down.
function X.SpeedScale(p,t)
 if t<(p:GetAttribute('IceCubeUntil')or 0)then return 0 end
 local s=1
 if t<(p:GetAttribute('HeavyMailUntil')or 0)then s*=HEAVY_SLOW end
 if t<(p:GetAttribute('ChillyUntil')or 0)then s*=CHILL_SLOW end
 return s
end

local function evidence(pos,loudness,kind,actor)
 local bus=SS:FindFirstChild('MonsterEvidence');if bus and pos then bus:Fire(pos,loudness,kind,actor)end
end
local function spend(prop)if prop.Parent then prop:SetAttribute('ChoiceBusy',nil);prop:SetAttribute('ChoiceSpent',true)end end
local function heal(p,n,why)if not Health then Health=require(game:GetService('ServerScriptService'):WaitForChild('PlayerHealth'))end;Health.Heal(p,n,why)end
local function puff(pos,color,count)
 local a=Instance.new('Attachment');a.Parent=workspace.Terrain;a.WorldPosition=pos
 local fx=Instance.new('ParticleEmitter');fx.Texture='rbxasset://textures/particles/sparkles_main.dds';fx.Color=ColorSequence.new(color)
 fx.Size=NumberSequence.new(.6,0);fx.Lifetime=NumberRange.new(.5,1);fx.Speed=NumberRange.new(6,12);fx.SpreadAngle=Vector2.new(180,180);fx.Rate=0;fx.LightEmission=1;fx.Parent=a
 fx:Emit(count or 30);game:GetService('Debris'):AddItem(a,2)
end
local function monsters()
 local w=S.api('CreatureWeaponApi');local ok,list=pcall(function()return w and w:Invoke('list')end)
 return ok and type(list)=='table'and list or{}
end
local function others(p) -- other living players on the mission
 local list={};for _,q in Players:GetPlayers()do if q~=p and S.living(q)then list[#list+1]=q end end;return list
end
-- The funny beat: face = 'grin' | 'gasp' | 'pucker' (FaceBeat, every screen) or 'cry' (the onion's sob, CryingUntil);
-- word + style = a popping word on this player's screen ('frost', 'gold', 'dark', 'pink', 'wobble', 'shake', 'plain').
local function beat(p,face,seconds,word,style)
 if not p or not p.Parent then return end
 local t=S.now()
 if face=='cry'then p:SetAttribute('CryingUntil',math.max(p:GetAttribute('CryingUntil')or 0,t+seconds))
 elseif face then p:SetAttribute('FaceBeat',face);p:SetAttribute('FaceBeatUntil',t+seconds)end
 if word then p:SetAttribute('ScreenBeat',word..'|'..(style or'plain'));p:SetAttribute('ScreenBeatAt',t)end
end
X.Beat=beat

-- [FrostyFridge] -----------------------------------------------------------------------------------------------------
local function fridgeYes(p,prop)
 S.finish(prop);prop:SetAttribute('ChoiceAnswer','yes');prop:SetAttribute('FridgeOpen',S.now())
 local clock,frozen=os.clock(),0
 for _,m in monsters()do
  m:SetAttribute('CalmUntil',math.max(m:GetAttribute('CalmUntil')or 0,clock+FRIDGE_FREEZE)) -- CreatureRoamServer: no moving, no catching
  m:SetAttribute('IceMarkUntil',S.now()+FRIDGE_FREEZE);frozen+=1 -- the icy glow (CloseUpChoiceClient)
 end
 p:SetAttribute('IceCubeUntil',S.now()+FRIDGE_ICE) -- SpeedScale 0 and an ice block on every screen
 puff(S.feetOf(prop)+Vector3.new(0,1.6,0),Color3.fromRGB(210,240,255),60)
 S.ctx.Audio.Play('HeliumHiss',prop);S.ctx.Audio.Play('GlassImpact',prop)
 beat(p,'gasp',FRIDGE_ICE,'BRRR!','frost')
 S.result(p,frozen>0 and'Every monster is frozen for 20 s! You are an ice cube for 8...'or'Brrr! No monsters to freeze... and you are an ice cube for 8 s.','good')
end
local function fridgeNo(p,prop)
 S.finish(prop);prop:SetAttribute('ChoiceAnswer','no');prop:SetAttribute('FridgeOpen',S.now())
 local rec=SS:FindFirstChild('RecoveryApi')
 local ok,added=pcall(function()return rec and rec:Invoke('bonusTime',p,FRIDGE_TIME)end)
 local cold=S.now()+FRIDGE_CHILL
 local text=ok and added and'Brrr! +1 minute on the clock, but everyone is cold and slow for 30 s.'or'Brrr! Everyone is cold and slow for 30 s.'
 for _,q in Players:GetPlayers()do
  if S.living(q)then q:SetAttribute('ChillyUntil',cold);S.result(q,text,nil);beat(q,'gasp',1.6,ok and added and'+1 MINUTE! BRRR!'or'BRRR!','frost')end
 end
 puff(S.feetOf(prop)+Vector3.new(0,1.6,0),Color3.fromRGB(210,240,255),60)
 S.ctx.Audio.Play('HeliumHiss',prop);S.ctx.Audio.Play('ClockTick',prop)
end

-- [ShyMailbox] -------------------------------------------------------------------------------------------------------
local function frontOf(prop)
 local f=prop:GetPivot().LookVector*Vector3.new(1,0,1);return f.Magnitude>.1 and f.Unit or Vector3.new(0,0,-1)
end
local function slotOf(prop)return prop:GetPivot().Position+Vector3.new(0,MAIL_SLOT_UP,0)+frontOf(prop)*MAIL_SLOT_FRONT end
local function mailYes(p,prop)
 S.finish(prop);prop:SetAttribute('ChoiceAnswer','yes');prop:SetAttribute('MailMood','open');prop:SetAttribute('ChoiceBusy',true)
 local deadline=S.now()+MAIL_SECONDS;prop:SetAttribute('MailUntil',deadline)
 mailboxes[prop]={player=p,untilT=deadline}
 S.ctx.Audio.Play('DrawerOpen',prop)
 beat(p,'grin',2) -- no pop word: the race card already says MAIL IT! and its countdown sits where the word would (UI pass 2026-10-27)
 S.event:FireClient(p,'cinematic','mailTimer',prop,{deadline=deadline})
end
local function mailClose(prop,text,p,tone)
 mailboxes[prop]=nil
 if prop.Parent then prop:SetAttribute('MailMood','sleep');prop:SetAttribute('MailUntil',nil);spend(prop)end
 if p and text then S.result(p,text,tone)end
 if p and p.Parent then S.event:FireClient(p,'cinematic','mailDone',prop,{})end
end
-- The cart basket's floor, or nil (a Cruise level has the boat instead).
local function basketFloor()
 local cart=S.ctx.map.Interactive:FindFirstChild('RecoveryCart');return cart and cart:FindFirstChild('BasketFloor')
end
local function mailEat(prop,c,m)
 mailboxes[prop]=nil
 local holder=Players:GetPlayerByUserId(m:GetAttribute('HeldBy')or 0)
 local items=SS:FindFirstChild('CursedItemApi')
 if holder and items then pcall(function()items:Invoke('release',holder)end)end
 prop:SetAttribute('MailMood','gulp');S.ctx.Audio.Play('DrawerClose',prop)
 -- swallowed: parked still inside the box while the door shuts, then it pops out in the cart
 local anchored={}
 for _,d in m:GetDescendants()do if d:IsA('BasePart')then anchored[d]=d.Anchored;d.Anchored=true end end
 m:PivotTo(CFrame.new(prop:GetPivot().Position+Vector3.new(0,MAIL_SLOT_UP,0)))
 task.delay(MAIL_GULP,function()
  if not m.Parent then return end
  for d,a in anchored do if d.Parent then d.Anchored=a end end
  local floor=basketFloor()
  if not floor then -- nothing to mail to: it hands the item back in front of itself, unchanged
   if prop.Parent then m:PivotTo(CFrame.new(S.feetOf(prop)+frontOf(prop)*2.4-Vector3.new(0,S.ctx.lootBounds(m).bottom-.05,0)))end
   mailClose(prop,'No cart to mail to... here, have it back.',c.player,nil);return
  end
  local value=m:GetAttribute('LootValue')or m:GetAttribute('Value')or 30
  local worth=math.max(1,math.floor(value*MAIL_STAMP+.5))
  m:SetAttribute('Value',worth);m:SetAttribute('LootValue',worth);m:SetAttribute('MailedBy',c.player.UserId)
  -- dropped onto the basket floor: RecoveryRoundServer's cargo check welds it in like any item let go over the cart
  m:PivotTo(floor.CFrame*CFrame.new(0,floor.Size.Y*.5-S.ctx.lootBounds(m).bottom+.1,0))
  puff(floor.Position+Vector3.new(0,1.5,0),Color3.fromRGB(200,180,255),25);S.ctx.Audio.Play('CargoStore',floor)
  if prop.Parent then S.ctx.Audio.Play('Whistle',prop);prop:SetAttribute('MailMood','happy')end
  beat(c.player,'grin',2.5,'WHOOSH! MAILED!','gold')
  task.delay(1.2,function()mailClose(prop,('Whoosh! It mailed it to the cart (now $%d).'):format(worth),c.player,'good')end)
 end)
end
local function mailNo(p,prop)
 S.finish(prop);local base=S.feetOf(prop);prop:Destroy()
 local box=S.giveItem('ShyMailbox',base,MAILBOX_VALUE,'HeavyMailbox')
 if box then heavies[box]=true;S.ctx.Audio.Play('MetalImpact',box)end
 beat(p,'gasp',1.8,'OOF! SO HEAVY!','wobble')
 S.result(p,'You took the mailbox ($110). It is SO heavy!',nil)
end
-- 4 Hz: open mailboxes look for an item at their door; whoever holds a heavy mailbox is slowed (a short lease).
local function stepMail(now,t)
 for prop,c in mailboxes do
  if not prop.Parent then mailboxes[prop]=nil
  elseif now>c.untilT then mailClose(prop,'Too slow! It got shy and shut its door.',c.player,nil)
  else
   local slot=slotOf(prop)
   for _,m in S.ctx.map.Interactive:GetChildren()do
    -- the pivot, not PrimaryPart: a held item has no PrimaryPart while it is in someone's hands
    local pos=m:IsA('Model')and m~=prop and m:GetAttribute('ItemId')and not m:GetAttribute('Gear')and not m:GetAttribute('CargoStored')and m:GetPivot().Position
    if pos then
     local held=m:GetAttribute('HeldBy')~=nil;if held then recentHeld[m]=t end
     local d=(pos-slot).Magnitude
     local dropped=not held and recentHeld[m]and t-recentHeld[m]<=DROP_SECONDS and d<=DROP_RADIUS
     if dropped or held and d<=MAIL_REACH then mailEat(prop,c,m);break end
    end
   end
  end
 end
 for m in heavies do
  if not m.Parent then heavies[m]=nil
  else local q=Players:GetPlayerByUserId(m:GetAttribute('HeldBy')or 0);if q then q:SetAttribute('HeavyMailUntil',now+.5)end end
 end
end

-- [SleepyLamp] -------------------------------------------------------------------------------------------------------
local function lampYes(p,prop)
 S.finish(prop);prop:SetAttribute('ChoiceAnswer','yes');prop:SetAttribute('LampMood','dark')
 local untilT=S.now()+LAMP_BOOST_SECONDS
 p:SetAttribute('LampBoostUntil',untilT);p:SetAttribute('LampAteLightUntil',nil)
 beams[p]={untilT=untilT,nextPing=S.now()+LAMP_PING_EVERY}
 S.ctx.Audio.Play('FlashlightClick',prop);S.ctx.Audio.Play('PresentOpen',prop)
 beat(p,'grin',2.5,'SUPER LIGHT!','gold')
 S.result(p,'Super flashlight for 1 minute! Monsters see it. Switch it off to hide.','good')
end
-- The lamp you took glows softly with the light it ate (a little help in the dark).
local function lampGlow(m)
 local part=m:FindFirstChild('Bulb')or m.PrimaryPart;if not part then return end
 local l=Instance.new('PointLight');l.Name='LampGlow';l.Color=Color3.fromRGB(255,214,140);l.Range=12;l.Brightness=1.6;l.Shadows=false;l.Parent=part
end
local function lampNo(p,prop)
 S.finish(prop);prop:SetAttribute('ChoiceAnswer','no');prop:SetAttribute('LampMood','gulp');prop:SetAttribute('ChoiceBusy',true)
 p:SetAttribute('LampAteLightUntil',S.now()+LAMP_EAT_SECONDS);p:SetAttribute('LampBoostUntil',nil);beams[p]=nil
 S.ctx.Audio.Play('FlashlightClick',prop);S.ctx.Audio.Play('MonsterGrab',prop)
 beat(p,'gasp',2,'GULP!','dark')
 S.result(p,'GULP! It ate your flashlight light (45 s). Take the lamp ($90).','bad')
 task.delay(LAMP_GULP,function()
  if not prop.Parent then return end
  local base=S.feetOf(prop);prop:Destroy()
  local lamp=S.giveItem('SleepyLamp',base,LAMP_VALUE,'GreedyLamp');if lamp then lampGlow(lamp)end
 end)
end
-- 4 Hz: the golden beam gives you away every few seconds, but only while the flashlight is on.
local function stepBeams(now)
 for q,b in beams do
  if not q.Parent or now>b.untilT then beams[q]=nil
  elseif now>=b.nextPing then
   b.nextPing=now+LAMP_PING_EVERY
   local r=S.living(q)
   if r and q.Character:GetAttribute('FlashlightOn')==true then evidence(r.Position,LAMP_PING_LOUD,'lamp beam',q)end
  end
 end
end

-- [TwinTeddies] ------------------------------------------------------------------------------------------------------
-- The first vote is kept here only (never an attribute: it must stay secret from every client).
local function teddyName(v)return v.player and v.player.DisplayName or'the teddy'end
local function teddyResolve(prop,a,b)
 teddies[prop]=nil
 if not prop.Parent then return end
 S.finish(prop);prop:SetAttribute('TeddyWaiting',nil);prop:SetAttribute('ChoiceVerb',X.Defs.TwinTeddies.verb)
 prop:SetAttribute('ChoiceAnswer',a.vote==b.vote and a.vote or'split')
 local humans={};for _,v in {a,b}do if v.player and v.player.Parent then humans[#humans+1]=v.player end end
 local base=S.feetOf(prop)
 if a.vote=='yes'and b.vote=='yes'then
  prop:SetAttribute('TeddyMood','hug');S.ctx.Audio.Play('MusicBox',prop)
  for _,q in humans do
   if S.living(q)then heal(q,TEDDY_HEAL,'twinTeddies')end
   S.giveItem(nil,base,TEDDY_HUG_GIFT,'TeddyHug')
   beat(q,'grin',3,'BIG HUG!','pink')
   S.result(q,('You both said YES! Big hug: +%d health and a gift!'):format(TEDDY_HEAL),'good')
  end
 elseif a.vote=='no'and b.vote=='no'then
  prop:SetAttribute('TeddyMood','treat');S.ctx.Audio.Play('PresentOpen',prop)
  S.giveItem(nil,base,TEDDY_TREAT,'TeddyTreat')
  for _,q in humans do beat(q,'grin',3,'TREAT!','gold');S.result(q,('You both said NO! The teddies give you a $%d treat!'):format(TEDDY_TREAT),'good')end
 else
  prop:SetAttribute('TeddyMood','cry');S.ctx.Audio.Play('DollCry',prop);S.ctx.Audio.Play('StingCreak',prop)
  evidence(base,TEDDY_CRY,'teddy tantrum',a.player)
  for _,v in {a,b}do
   local q=v.player;if q and q.Parent then
    local other=v==a and b or a
    q:SetAttribute('CardSlowUntil',S.now()+TEDDY_SLOW)
    beat(q,'cry',4,'WAAAAH!','wobble')
    S.result(q,('You said %s, %s said %s! The teddies cry SO loud. Monsters heard!'):format(v.vote:upper(),teddyName(other),other.vote:upper()),'bad')
   end
  end
 end
 prop:SetAttribute('ChoiceBusy',true)
 task.delay(4,function()if prop.Parent then prop:SetAttribute('TeddyMood',nil);spend(prop)end end)
end
-- The other teddy votes for itself: alone, or nobody came in time. Free, never bought: just a coin it flips.
local function teddySelf(prop,tv,why)
 local bot={player=nil,vote=S.ctx.rng:NextNumber()<.5 and'yes'or'no'}
 if tv.first.player.Parent and why then S.result(tv.first.player,why,nil)end
 prop:SetAttribute('TeddyMood','think')
 task.delay(1.5,function()if teddies[prop]==tv then teddyResolve(prop,tv.first,bot)end end)
end
local function teddyVote(vote)
 return function(p,prop)
  local tv=teddies[prop]
  if not tv then -- the first vote: keep it secret and wait for a friend
   tv={first={player=p,vote=vote},untilT=S.now()+TEDDY_WAIT};teddies[prop]=tv
   prop:SetAttribute('TeddyFirst',p.UserId);prop:SetAttribute('TeddyWaiting',true);prop:SetAttribute('TeddyMood','wait')
   prop:SetAttribute('ChoiceVerb','HOLD THE OTHER PAW')
   S.ctx.Audio.Play('MusicBox',prop)
   beat(p,'pucker',1.6,'SHH!','pink')
   local friends=others(p)
   if #friends==0 then teddySelf(prop,tv,'"Nobody else is here... I will pick too!"');return end
   S.result(p,'Shh! Now a FRIEND must hold the other paw. Go get one!',nil)
   for _,q in friends do S.result(q,('%s found the Twin Teddies! Go hold the other paw!'):format(p.DisplayName),nil)end
  elseif tv.first.player~=p then
   teddyResolve(prop,tv.first,{player=p,vote=vote})
  end
 end
end
-- CloseUpChoices claim hooks: the first voter can't vote twice; the second sees a different whisper.
local function teddyGate(p,prop)
 local tv=teddies[prop];if tv and tv.first.player==p then return'You picked already! A friend must pick now.'end
 return nil
end
local function teddyWhisper(_,prop)if teddies[prop]then return'Your friend picked in secret. Pick the SAME!'end;return nil end

-- [PadlockKing] ------------------------------------------------------------------------------------------------------
local function lockedDoors()
 local list={}
 for _,m in S.ctx.map.Interactive:GetChildren()do
  if m:IsA('Model')and m:GetAttribute('Kind')=='door'and m:GetAttribute('Locked')and m.PrimaryPart then list[#list+1]=m end
 end
 return list
end
local function padlockYes(p,prop)
 S.finish(prop);prop:SetAttribute('ChoiceAnswer','yes');prop:SetAttribute('PadlockOpen',S.now())
 S.ctx.Audio.Play('KeyJingle',prop);S.ctx.Audio.Play('Unlock',prop)
 local doors=lockedDoors()
 -- sorted nearest first, so the clangs ripple out through the house from the padlock
 local from=prop:GetPivot().Position
 table.sort(doors,function(a,b)return(a.PrimaryPart.Position-from).Magnitude<(b.PrimaryPart.Position-from).Magnitude end)
 local owner=game:GetService('ServerScriptService'):FindFirstChild('InteractServer');local opener=owner and owner:FindFirstChild('MonsterDoorApi')
 task.spawn(function()
  task.wait(.8)
  for _,d in doors do
   if d.Parent and d:GetAttribute('Locked')then
    -- the same unlock as KeyDoorServer / CursedItemsServer: CreatureRoamServer's blocked() reads Locked live, so the
    -- monsters can path through this doorway from now on
    d:SetAttribute('Locked',nil);d:SetAttribute('PadlockKingOpened',true)
    for _,c in d:GetChildren()do if c.Name=='Padlock'then if c:IsA('BasePart')then puff(c.Position,Color3.fromRGB(245,200,90),14)end;c:Destroy()end end
    S.ctx.Audio.Play('Unlock',d);S.ctx.Audio.Play('KeyJingle',d)
    if opener then pcall(function()opener:Invoke(d)end)end -- swing it open (InteractServer.MonsterDoorApi)
    evidence(d.PrimaryPart.Position,PADLOCK_CLANG,'padlock pop',p)
    task.wait(PADLOCK_STAGGER)
   end
  end
 end)
 local n=#doors
 for _,q in Players:GetPlayers()do
  local mine=('CLANG! %d locked doors popped open! Monsters can get in too...'):format(n)
  local theirs=('%s opened every locked door! New rooms to search, but monsters can get in too.'):format(p.DisplayName)
  if S.living(q)then S.result(q,q==p and mine or theirs,'bad');beat(q,q==p and'gasp'or nil,2,'CLANG! CLANG!','shake')end
 end
 prop:SetAttribute('ChoiceBusy',true)
 task.delay(.8+n*PADLOCK_STAGGER+1.5,function()spend(prop)end)
end
local function padlockNo(p,prop)
 S.finish(prop);local base=S.feetOf(prop);prop:Destroy()
 local lock=S.giveItem('PadlockKing',base,PADLOCK_VALUE,'SleepyPadlock')
 if lock then padlocks[lock]=os.clock()+S.ctx.rng:NextNumber(PADLOCK_JINGLE_MIN,PADLOCK_JINGLE_MAX)end
 beat(p,'pucker',2,'SHHH... ZZZ','plain')
 S.result(p,('He fell asleep. Take him ($%d)! Shh... his keys jingle.'):format(PADLOCK_VALUE),nil)
end
-- Only placed on a level that has a locked door (a YES with nothing to open would be a dud).
local function padlockCanSpawn()return #lockedDoors()>0 end

-- [StaringOwl] -------------------------------------------------------------------------------------------------------
-- Where the owl is `e` seconds after take-off: a figure-eight in front of its perch, facing the player, a little
-- faster every second. CloseUpChoiceClient computes the very same point from the Owl* attributes.
local function owlSpot(frame,e,radius,height,toward)
 local lift=math.min(1,e/.7);local a=e*(1.1+e*.12)
 return frame*Vector3.new(math.sin(a)*radius*lift,height*lift+math.sin(a*2)*.9*lift,-toward*lift)
end
local function owlEnd(prop,o,won)
 owls[prop]=nil
 local p=o.player
 if p.Parent then p:SetAttribute('ChoiceDeciding',nil);S.event:FireClient(p,'cinematic','owlDone',prop,{won=won})end
 if not prop.Parent then return end
 local base=S.feetOf(prop)
 if won then
  prop:SetAttribute('OwlState','won');S.ctx.Audio.Play('PresentOpen',prop);S.ctx.Audio.Play('Whistle',prop)
  S.giveItem(nil,base,OWL_PRIZE,'OwlPrize')
  beat(p,'grin',3,'YOU WIN!','gold')
  S.result(p,('You won the staring contest! The owl left you $%d!'):format(OWL_PRIZE),'good')
 else
  prop:SetAttribute('OwlState','lost');prop:SetAttribute('OwlLostAt',S.now())
  S.ctx.Audio.Play('StingChoir',prop);S.ctx.Audio.Play('MonsterWhoosh',prop)
  evidence(base,OWL_SCREECH,'owl screech',p)
  beat(p,'gasp',2,'SCREEEECH!','shake')
  S.result(p,'SCREEEECH! You looked away! The monsters heard that!','bad')
 end
 task.delay(won and 2 or 2.5,function()if prop.Parent then puff(prop:GetPivot().Position+Vector3.new(0,2,0),Color3.fromRGB(210,210,230),20);prop:Destroy()end end)
end
local function owlYes(p,prop)
 S.finish(prop);prop:SetAttribute('ChoiceAnswer','yes');prop:SetAttribute('ChoiceBusy',true)
 local r=S.living(p);if not r then spend(prop);return end
 local owl=prop:FindFirstChild('Owl');local rest=owl and owl:IsA('BasePart')and owl.Position or prop:GetPivot().Position+Vector3.new(0,2.6,0)
 local flat=Vector3.new(r.Position.X,rest.Y,r.Position.Z)
 local frame=(flat-rest).Magnitude>.1 and CFrame.lookAt(rest,flat)or CFrame.new(rest)
 local start=S.now()+OWL_GRACE;local deadline=start+OWL_SECONDS
 prop:SetAttribute('OwlFrame',frame);prop:SetAttribute('OwlStart',start);prop:SetAttribute('OwlRadius',OWL_RADIUS)
 prop:SetAttribute('OwlHeight',OWL_HEIGHT);prop:SetAttribute('OwlToward',OWL_TOWARD);prop:SetAttribute('OwlStare',0);prop:SetAttribute('OwlState','fly')
 prop:SetAttribute('StareAt',p.UserId) -- the owl keeps its eyes on you the whole flight (the claim cleared it)
 owls[prop]={player=p,frame=frame,start=start,untilT=deadline,stared=0,last=os.clock()}
 p:SetAttribute('ChoiceDeciding',true) -- still and safe while staring, like the jack-in-the-box crank
 S.ctx.Audio.Play('Whistle',prop)
 beat(p,'gasp',OWL_GRACE+OWL_SECONDS,nil,nil) -- wide-mouthed concentration for the whole contest
 S.event:FireClient(p,'cinematic','owlStare',prop,{deadline=deadline,need=OWL_NEED})
end
local function owlNo(p,prop)
 S.finish(prop);prop:SetAttribute('ChoiceAnswer','no');prop:SetAttribute('OwlState','leave');prop:SetAttribute('OwlLeaveAt',S.now())
 S.giveItem(nil,S.feetOf(prop),OWL_GIFT,'OwlGift');S.ctx.Audio.Play('Whistle',prop)
 beat(p,'pucker',1.8,'HOO HOO! BYE!','plain')
 S.result(p,('The owl flew away. It left a little gift ($%d).'):format(OWL_GIFT),nil)
 task.delay(2,function()if prop.Parent then prop:Destroy()end end)
end
-- The client says "I am looking at it" about five times a second; the server only counts it while the player's
-- body faces the owl's real spot, and never more than a quarter second per message.
function X.Stare(p,prop)
 local o=owls[prop];if not o or o.player~=p then return end
 local t=os.clock();if t-o.last<.15 then return end
 local credit=math.min(.25,t-o.last);o.last=t
 local e=S.now()-o.start;if e<0 then return end
 local r=S.living(p);if not r then return end
 local spot=owlSpot(o.frame,e,OWL_RADIUS,OWL_HEIGHT,OWL_TOWARD)
 local to=(spot-r.Position)*Vector3.new(1,0,1);local look=r.CFrame.LookVector*Vector3.new(1,0,1)
 if to.Magnitude>.5 and look.Magnitude>.1 and to.Unit:Dot(look.Unit)<OWL_FACING then return end
 o.stared+=credit;prop:SetAttribute('OwlStare',o.stared)
 if o.stared>=OWL_NEED then owlEnd(prop,o,true)end
end

X.Answer={
 FrostyFridge={yes=fridgeYes,no=fridgeNo},ShyMailbox={yes=mailYes,no=mailNo},SleepyLamp={yes=lampYes,no=lampNo},
 TwinTeddies={yes=teddyVote('yes'),no=teddyVote('no')},PadlockKing={yes=padlockYes,no=padlockNo},StaringOwl={yes=owlYes,no=owlNo},
}
-- Claim hooks called by CloseUpChoices: a deny message, or nil to allow.
function X.ClaimGate(p,prop,id)if id=='TwinTeddies'then return teddyGate(p,prop)end;return nil end
function X.Whisper(p,prop,id)if id=='TwinTeddies'then return teddyWhisper(p,prop)end;return nil end
function X.CanSpawn(id)if id=='PadlockKing'then return padlockCanSpawn()end;return true end

-- Four times a second: mailboxes, lamp beams, teddy wait timers, owl deadlines, jingling padlocks.
local acc=0
local function heartbeat(dt)
 acc+=dt;if acc<.25 then return end;acc=0
 local now,t=S.now(),os.clock()
 stepMail(now,t);stepBeams(now)
 for prop,tv in teddies do
  if not prop.Parent then teddies[prop]=nil
  elseif not tv.first.player.Parent then -- the first voter left: back to a fresh prop
   teddies[prop]=nil;prop:SetAttribute('TeddyFirst',nil);prop:SetAttribute('TeddyWaiting',nil);prop:SetAttribute('TeddyMood',nil)
   prop:SetAttribute('ChoiceVerb',X.Defs.TwinTeddies.verb)
  elseif now>tv.untilT and prop:GetAttribute('ClaimedBy')==nil and prop:GetAttribute('TeddyMood')=='wait'then
   teddySelf(prop,tv,'"Nobody came... I will pick too!"')
  end
 end
 for prop,o in owls do
  if not prop.Parent or not o.player.Parent then owls[prop]=nil;if o.player.Parent then o.player:SetAttribute('ChoiceDeciding',nil)end
  elseif now>o.untilT or not S.living(o.player)then owlEnd(prop,o,false)end
 end
 for lock,nextT in padlocks do
  if not lock.Parent then padlocks[lock]=nil
  elseif t>=nextT then
   padlocks[lock]=t+S.ctx.rng:NextNumber(PADLOCK_JINGLE_MIN,PADLOCK_JINGLE_MAX);S.ctx.Audio.Play('KeyJingle',lock)
   evidence(lock:GetPivot().Position,PADLOCK_JINGLE_LOUD,'padlock jingle')
  end
 end
end

function X.ClearLevel()
 for _,o in owls do if o.player.Parent then o.player:SetAttribute('ChoiceDeciding',nil)end end
 table.clear(mailboxes);table.clear(heavies);table.clear(beams)
 table.clear(teddies);table.clear(owls);table.clear(padlocks)
end

function X.Init(shared)
 S=shared
 Run.Heartbeat:Connect(heartbeat)
end

return X
