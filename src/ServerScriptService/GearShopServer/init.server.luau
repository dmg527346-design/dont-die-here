-- Gear shop: the team bank (every dollar sold this run) buys gear from the van's right-wall crates.
-- Owns: bank, gear inventory across level rebuilds and run saves, gear effects (GearUseApi).
-- Monster effects go through CreatureRoamServer's CreatureWeaponApi; item spawning through CursedItemsServer's SpawnGearItem.
local Players=game:GetService('Players');local RS=game:GetService('ReplicatedStorage');local SS=game:GetService('ServerStorage')
local Debris=game:GetService('Debris');local TweenService=game:GetService('TweenService')
local Targeting=require(script:WaitForChild('MonsterShotTargeting'))
local Shop=require(RS:WaitForChild('LobbyShopCatalog'))
local Progress=require(game:GetService('ServerScriptService'):WaitForChild('ProgressService'))
local Audio=require(game:GetService('ServerScriptService'):WaitForChild('GameplayAudioServer'))

local SHOP={ -- crate order: nearest the spawn first (lowest van-local Z)
 {id='Grenade',name='Grenade',price=150,charges=1},
 {id='ProxMine',name='Proximity Grenade',price=200,charges=1},
 {id='HypnoGun',name='Hypno Gun',price=500,charges=3},
 {id='SlayerGun',name='Monster Slayer',price=1250,charges=3},
 {id='SkitterTrap',name='Skitter Trap',price=150,charges=1},
 {id='MedKit',name='MedKit',price=150,charges=1},
 {id='BigMedKit',name='Big MedKit',price=250,charges=1},
 {id='ChirpyDecoy',name='Chirpy Decoy',price=150,charges=1}, -- utility gear (2026-10-27): its own shelf above the gear locker
 {id='DoorWedge',name='Door Wedge',price=100,charges=1},
 {id='CartBeacon',name='Cart Beacon',price=120,charges=1},
 {id='CartBell',name='Cart Bell',price=140,charges=1},
}
local BY_ID={};for _,e in SHOP do BY_ID[e.id]=e end
local UTILITY_SHOW={ChirpyDecoy=.9,DoorWedge=1,CartBeacon=.75,CartBell=1} -- utility gear: showcase scale on its own shelf
local onGearSet -- utility gear: set below; track() calls it when a tracked gear item is let go
local BLAST_RADIUS=16      -- grenade / proximity blast reach (studs)
local FLEE_SECONDS=12      -- how long a blasted monster ignores players while fleeing
local HYPNO_SECONDS=35
local MINE_TRIGGER=3       -- horizontal studs: a monster must step onto the mine
local GUN_RANGE=160
local ORB_VALUE=75        -- sell value of the orb a slain monster drops
local MONSTER_HP=100       -- gear damage a monster can take
local GRENADE_DAMAGE=34    -- 3 grenades kill
local MINE_DAMAGE=50       -- 2 proximity grenades kill
local LOCKER_OFFSET=CFrame.new(9,.3,-7) -- van-local storage tray: right of spawn, left of the shop crates
local LOCKER_SIZE=Vector3.new(2.6,.12,5)
local SHOWCASE_SCALE=1.25 -- shop display models (the grey crates are hidden)
local BANK_SIGN_OFFSET=Vector3.new(-2.6,1.9,0) -- van-local: out from the shop wall toward the aisle, just above the items
local SLAYER_SHOT_SOUND=111381796854533 -- 'Collateral Ruin Hit 1': heavy impact, distinct from the hypno gun's zap

local bank=0;local lastSold=0;local lastRound=0;local loadedContext=false
local boosts={Speed=0,Stamina=0,Recovery=0,Flashlight=0,Crouch=0} -- run boosts bought (tiers), see BOOSTS below
local records={} -- live gear model -> {id, charges}
local pending={} -- gear waiting to be (re)spawned in the van locker: {id, charges}
local state

local event=RS:FindFirstChild('GearShopEvent')or Instance.new('RemoteEvent');event.Name='GearShopEvent';event.Parent=RS
local function toast(p,text)if p and p.Parent then event:FireClient(p,'toast',text)end end
local function toastAll(text)event:FireAllClients('toast',text)end
local function publishBank()if state then state:SetAttribute('Bank',bank)end end

local function van()return workspace:FindFirstChild('AnomalyRecoveryVan',true)end
local function vanCF()local v=van();return v and v:GetPivot()end
local function missionMap()return workspace:FindFirstChild('Mansion')end
local function phase()return state and state:GetAttribute('Phase')end
local function alive(p)
 local c=p.Character;local h=c and c:FindFirstChildOfClass('Humanoid');local r=c and c:FindFirstChild('HumanoidRootPart')
 return p:GetAttribute('MissionActive')==true and not p:GetAttribute('RoundDead')and h and h.Health>0 and r,r
end

-- Run save: RecoveryRoundServer's captureRunSave asks for this.
local grantGear -- utility gear core (below): the playtest 'grant' action
local api=SS:FindFirstChild('GearShopApi')or Instance.new('BindableFunction');api.Name='GearShopApi';api.Parent=SS
api.OnInvoke=function(action,...)
 if action=='grant'then return grantGear and grantGear(...)end
 if action=='snapshot'then
  local gear={}
  for m,rec in records do if m.Parent and #gear<24 then table.insert(gear,{id=rec.id,charges=m:GetAttribute('Charges')or rec.charges})end end
  for _,rec in pending do if #gear<24 then table.insert(gear,{id=rec.id,charges=rec.charges})end end
  return {bank=bank,gear=gear,boosts=table.clone(boosts)}
 elseif action=='addBank'then
  local amount=...
  bank+=amount;publishBank();toastAll(('The owner added $%d to the team bank. Team bank: $%d'):format(amount,bank))
  return true,('Team bank +$%d (now $%d).'):format(amount,bank)
 end
end

local function track(m,id,charges)
 records[m]={id=id,charges=charges}
 m:GetAttributeChangedSignal('HeldBy'):Connect(function()if m:GetAttribute('HeldBy')==nil and onGearSet then onGearSet(m,id)end end)
 m.AncestryChanged:Connect(function()
  if m.Parent then return end
  local rec=records[m];records[m]=nil
  -- Not consumed (map rebuilt / cleared): bring it back in the van locker next level.
  if rec and not rec.consumed then table.insert(pending,{id=rec.id,charges=m:GetAttribute('Charges')or rec.charges})end
 end)
end
local function spawnGear(id,cf,charges)
 local spawner=SS:FindFirstChild('SpawnGearItem');if not spawner then return nil end
 local ok,m=pcall(function()return spawner:Invoke(id,cf,charges)end)
 if ok and m then track(m,id,charges);return m end
end
local function consume(p,m)
 local rec=records[m];if rec then rec.consumed=true end
 local items=SS:FindFirstChild('CursedItemApi');if items and p then pcall(function()items:Invoke('release',p)end)end
 if m.Parent then m:Destroy()end
end

-- Run boosts: team-wide upgrades bought from the team bank on the bottom shelf (the three seat cushions under the
-- gear). They last for this run only (a wipe restart clears them, the run save keeps them) and cost more every
-- level, so buying early pays off. The three slots show three of the four boosts: a bought one slides down out of
-- its slot and another rises in; maxed boosts leave the rotation. Effects: SprintController / FlashlightController
-- read the RunBoost<Id> player attributes.
local BOOSTS={
 Speed={name='Speed Boost',short='SPEED',info='Run & walk faster',color=Color3.fromRGB(90,200,255),base={120,240,480}},
 Stamina={name='Stamina Boost',short='STAMINA',info='+15% stamina',color=Color3.fromRGB(120,220,110),base={100,200,400}},
 Recovery={name='Recovery Boost',short='RECOVERY',info='Stamina refills faster',color=Color3.fromRGB(255,190,80),base={100,200,400}},
 Flashlight={name='Flashlight Boost',short='FLASHLIGHT',info='Wider, longer beam',color=Color3.fromRGB(255,240,170),base={90,180,360}},
 Crouch={name='Crouch Speed Boost',short='CROUCH SPEED',info='Sneak faster',color=Color3.fromRGB(190,140,255),base={100,200,400}},
}
local BOOST_IDS={'Speed','Stamina','Recovery','Flashlight','Crouch'}
local BOOST_MAX=3
local BOOST_ROUND_GROWTH=.35 -- every level after the first adds 35% to boost prices
local BOOST_SINK=1.9 -- studs a display drops into the bench when it leaves its slot
local boostOffer={'Speed','Stamina','Recovery'} -- slot index -> boost id, or false when nothing is left
local boostSlots={} -- slot index -> {home, anchor, model, id, busy, title, info, price, prompt}

-- Level 2 sale (user request 2026-10-22): gear and boosts cost 25% less on level 2 only.
local LEVEL2_PRICE=.75
-- Late-run sale (owner 2026-10-28): every van item (gear, guns, med kits, run boosts) costs 15% less from level 5 on.
local LATE_PRICE,LATE_FROM=.85,5
local function levelSale()local r=state and state:GetAttribute('Round')or 1;return r==2 and LEVEL2_PRICE or r>=LATE_FROM and LATE_PRICE or 1 end
local function boostPrice(id)
 local base=BOOSTS[id].base[boosts[id]+1];if not base then return nil end
 local round=math.max(1,state and state:GetAttribute('Round')or 1)
 return math.floor(base*(1+BOOST_ROUND_GROWTH*(round-1))*levelSale()/10+.5)*10
end
-- Guns get pricier as the run goes on: +GUN_LEVEL_GROWTH per level after the first (like boosts) and x GUN_BUY_GROWTH
-- for every one of that gun the team already bought this run. Other gear keeps its list price.
-- Per gun: {growth per level after the first, multiplier per one already bought this run}.
local GUN_IDS={HypnoGun={.35,1.5},SlayerGun={.2,1.25},
 -- Med kits are back (owner, 2026-10-22): +50% per level after the first, x1.35 / x1.45 for every one the team already
 -- bought this run, and only ONE of each per level (MED_STOCK); health no longer comes back for free between levels.
 MedKit={.5,1.35},BigMedKit={.5,1.45}}
local MED_STOCK={MedKit=true,BigMedKit=true}
local medBoughtLevel={} -- med kit id -> the level it was last bought on
local gunBuys={} -- gun id -> bought this run (this server)
local function gearPrice(entry)
 if not GUN_IDS[entry.id] then return math.floor(entry.price*levelSale()/10+.5)*10 end
 local round=math.max(1,state and state:GetAttribute('Round')or 1)
 local growth=GUN_IDS[entry.id]
 local price=entry.price*(1+growth[1]*(round-1))*growth[2]^(gunBuys[entry.id]or 0)*levelSale()
 if entry.id=='SlayerGun'and state and state:GetAttribute('Omen')=='SlayerSale'then price*=.65 end -- omen: 35% off the Monster Slayer
 return math.floor(price/10+.5)*10
end
-- Pit Stop Snacks (WorldA; van, between levels): a free snack hatch by the left wall. From the clear of level 1 on it shows
-- a FIXED pair for the coming level (the level number picks the pair; three omens swap in a fitting one; never random,
-- never paid). Each player takes one: +1 tier of that run boost for themselves, for that level only (capped at BOOST_MAX).
-- PlaytestFixes 2026-10-27 (owner: "no idea what glow gun is for the snack machine"): every label now leads with the
-- run boost the player knows from the van shop (BOOSTS names) and says what it does and for which level.
local SNACKS={
 Speed={name='Zoom Soda',info='You run & walk faster',color=Color3.fromRGB(66,201,240)},
 Stamina={name='Marathon Muffin',info='You can sprint longer',color=Color3.fromRGB(240,138,46)},
 Recovery={name='Mint Breeze',info='Sprint refills faster',color=Color3.fromRGB(154,210,63)},
 Flashlight={name='Glow Gum',info='Flashlight shines wider & further',color=Color3.fromRGB(247,201,62)},
 Crouch={name='Tiptoe Taffy',info='You sneak (crouch) faster',color=Color3.fromRGB(190,140,255)},
}
local function snackBoostName(id)return(BOOSTS[id]and BOOSTS[id].name or id)..' +1' end
local SNACK_PAIRS={{'Speed','Flashlight'},{'Stamina','Crouch'},{'Recovery','Speed'},{'Flashlight','Stamina'},{'Crouch','Recovery'}} -- levels 2..6, then again
local SNACK_OMEN_PAIRS={DimBatteries={'Flashlight','Recovery'},Restless={'Crouch','Speed'},HeavyQuota={'Speed','Stamina'}}
local SNACK_FIRST_LEVEL=2
local SNACK_OFFSET=CFrame.new(-10.3,.25,-3)*CFrame.Angles(0,-math.pi/2,0) -- van-local: left wall, front faces the aisle (+X)
local snacks={} -- userId -> {level=n, id=boost id}: the snack a player took for that level
local snackSlots={} -- 1/2 -> {anchor, title, info, prompt}
local snackSign -- the marquee billboard's TextLabel
local takeSnack -- set beside dressVan; RunBoostApi forwards to it
local function snackLevel() -- the level the machine stocks: the next one while the clear holds, else this one
 local r=state and state:GetAttribute('Round')or 0
 return phase()=='Won'and r+1 or r
end
local function snackPair(level)
 local omen;if state then if phase()=='Won'then omen=state:GetAttribute('NextOmen')else omen=state:GetAttribute('Omen')end end
 return SNACK_OMEN_PAIRS[omen or '']or SNACK_PAIRS[(level-SNACK_FIRST_LEVEL)%#SNACK_PAIRS+1]
end
local function snackTier(p,id)
 local s=snacks[p.UserId];local r=state and state:GetAttribute('Round')or 0
 return(s and s.level==r and s.id==id)and 1 or 0
end
local function publishBoosts()
 for _,p in Players:GetPlayers()do
  local on=p:GetAttribute('MissionActive')==true
  for _,id in BOOST_IDS do local n=on and math.min(BOOST_MAX,boosts[id]+snackTier(p,id))or 0;local key='RunBoost'..id;if(p:GetAttribute(key)or 0)~=n then p:SetAttribute(key,n>0 and n or nil)end end
 end
end
local function boostModel(id)
 -- Cereal box from ServerStorage.RunBoostKit (rbxkit meshes, pivot bottom centre, front = LookVector).
 local kit=SS:FindFirstChild('RunBoostKit');local template=kit and kit:FindFirstChild('BoostCereal_'..id)
 if template then
  local box=template:Clone();box.Name='BoostDisplay_'..id
  for k in box:GetAttributes()do box:SetAttribute(k,nil)end
  for _,d in box:GetDescendants()do if d:IsA('BasePart')then d.Anchored=true;d.CanCollide=false;d.CanQuery=false;d.CanTouch=false end end
  return box
 end
 local def=BOOSTS[id];local m=Instance.new('Model');m.Name='BoostDisplay_'..id
 local up=CFrame.Angles(0,0,math.rad(90)) -- cylinders lie along X; stand them up
 local function part(name,size,y,color,material,transparency)
  local p=Instance.new('Part');p.Name=name;p.Shape=Enum.PartType.Cylinder;p.Size=size;p.CFrame=CFrame.new(0,y,0)*up;p.Color=color;p.Material=material;p.Transparency=transparency or 0
  p.Anchored=true;p.CanCollide=false;p.CanQuery=false;p.CanTouch=false;p.CastShadow=false;p.Parent=m;return p
 end
 part('Base',Vector3.new(.22,1.5,1.5),.11,Color3.fromRGB(30,36,34),Enum.Material.Metal)
 local core=part('Core',Vector3.new(1.05,.6,.6),.76,def.color,Enum.Material.Neon)
 part('Glass',Vector3.new(1.25,1.05,1.05),.84,Color3.fromRGB(200,230,255),Enum.Material.Glass,.65)
 part('Cap',Vector3.new(.14,1.15,1.15),1.53,Color3.fromRGB(30,36,34),Enum.Material.Metal)
 local light=Instance.new('PointLight');light.Color=def.color;light.Brightness=1.2;light.Range=6;light.Parent=core
 m.WorldPivot=CFrame.identity -- bottom centre
 return m
end
local function renderSlot(slot)
 local id=slot.id;local def=id and BOOSTS[id];local price=id and boostPrice(id)
 local anyOpen=false;for _,b in BOOST_IDS do if boosts[b]<BOOST_MAX then anyOpen=true end end
 slot.title.Text=def and def.short or 'SOLD';slot.title.TextColor3=def and def.color or Color3.fromRGB(150,150,150)
 slot.info.Text=def and(def.info..'  ·  '..boosts[id]..'/'..BOOST_MAX)or(anyOpen and'New boost next level'or'All boosts maxed')
 slot.price.Text=price and('$'..price)or''
 slot.prompt.Enabled=price~=nil and not slot.busy
 if def and price then slot.prompt.ObjectText=('%s %d/%d (team)'):format(def.name,boosts[id]+1,BOOST_MAX);slot.prompt.ActionText='Buy $'..price end
end
local function slide(m,from,to,duration,style,direction)
 local v=Instance.new('CFrameValue');v.Value=from
 v.Changed:Connect(function(c)if m.Parent then m:PivotTo(c)end end)
 local tw=TweenService:Create(v,TweenInfo.new(duration,style,direction),{Value=to});tw:Play();tw.Completed:Wait();v:Destroy()
end
local function setSlot(slot,id,animate)
 slot.busy=true;renderSlot(slot)
 local low=slot.home*CFrame.new(0,-BOOST_SINK,0)
 local old=slot.model;slot.model=nil
 if old then if animate and old.Parent then slide(old,slot.home,low,.35,Enum.EasingStyle.Quad,Enum.EasingDirection.In)end;old:Destroy()end
 slot.id=id or nil
 if id and slot.anchor.Parent then
  local m=boostModel(id);m:PivotTo(animate and low or slot.home);m.Parent=slot.anchor.Parent;slot.model=m
  if animate then slide(m,low,slot.home,.45,Enum.EasingStyle.Back,Enum.EasingDirection.Out)end
 end
 slot.busy=false;renderSlot(slot)
end
-- Pick a fresh set of three from the boosts that are not maxed (after a reset or a loaded save).
local function rebuildOffer()
 local open={};for _,id in BOOST_IDS do if boosts[id]<BOOST_MAX then table.insert(open,id)end end
 boostOffer={};for i=1,3 do boostOffer[i]=table.remove(open,math.random(1,math.max(1,#open)))or false end
 for i,slot in boostSlots do task.spawn(setSlot,slot,boostOffer[i],false)end
end
local function resetBoosts()for _,id in BOOST_IDS do boosts[id]=0 end;publishBoosts();rebuildOffer()end
local function buyBoost(p,i)
 local slot=boostSlots[i];local id=slot and slot.id
 if not id or slot.busy then return end
 local ok,r=alive(p);if not ok then return end
 if(r.Position-slot.home.Position).Magnitude>9 then return end
 local price=boostPrice(id);if not price then return end
 -- Shop chapter (step 1): this player's first team boost costs at most the tutorial price, so level 1's money covers it.
 local tutorial=p:GetAttribute('ShopTutorialStep')==1;if tutorial then price=math.min(price,Shop.TutorialBoostPrice)end
 if bank<price then toast(p,('Not enough in the team bank ($%d / $%d).'):format(bank,price));return end
 bank-=price;publishBank();boosts[id]+=1;publishBoosts()
 -- A team boost counts for everyone on step 1: whoever pays, the whole team's boost step is done (the token step stays each player's own).
 for _,o in Players:GetPlayers()do if o:GetAttribute('ShopTutorialStep')==1 then task.spawn(Progress.ShopTutorialAdvance,o,o:GetAttribute('ShopTutorialReplay')==true and 3 or 2)end end -- owner replay: no token step
 toastAll(('%s bought %s %d/%d for the team. Team bank: $%d'):format(p.DisplayName,BOOSTS[id].name,boosts[id],BOOST_MAX,bank))
 -- The bought box sinks away and the slot stays empty until the next level, which refills all three at random.
 boostOffer[i]=false
 task.spawn(setSlot,slot,false,true)
end
local function dressBoosts(v,cf)
 local cushions={}
 for _,d in v:GetDescendants()do if d:IsA('BasePart')and d.Name=='BenchCushion'and cf:PointToObjectSpace(d.Position).X>0 then table.insert(cushions,d)end end
 table.sort(cushions,function(a,b)return cf:PointToObjectSpace(a.Position).Z<cf:PointToObjectSpace(b.Position).Z end)
 table.clear(boostSlots)
 for i=1,math.min(3,#cushions)do
  local c=cushions[i];local top=c.CFrame*CFrame.new(0,c.Size.Y/2,0)
  local slot:any={home=CFrame.lookAt(top.Position,top.Position+cf:VectorToWorldSpace(Vector3.new(-1,0,0))),busy=false} -- box fronts face the aisle
  local anchor=Instance.new('Part');anchor.Name='BoostSlot'..i;anchor.Size=Vector3.new(1.4,1.7,1.4);anchor.CFrame=slot.home*CFrame.new(0,.85,0)
  anchor.Transparency=1;anchor.Anchored=true;anchor.CanCollide=false;anchor.CanQuery=false;anchor.CanTouch=false;anchor.Parent=v;slot.anchor=anchor
  local bb=Instance.new('BillboardGui');bb.Name='BoostLabel';bb.Size=UDim2.fromOffset(150,50);bb.StudsOffset=Vector3.new(0,-.85,1.3); -- pulled toward the viewer so it floats in front of its own cereal box, just below it
 bb.MaxDistance=24;bb.LightInfluence=0;bb.Parent=anchor
  local function line(y,h,color)local t=Instance.new('TextLabel');t.Position=UDim2.fromScale(0,y);t.Size=UDim2.fromScale(1,h);t.BackgroundTransparency=1;t.Font=Enum.Font.FredokaOne;t.TextScaled=true;t.TextColor3=color;t.Parent=bb;local s=Instance.new('UIStroke');s.Thickness=1.5;s.Transparency=.3;s.Parent=t;return t end
  slot.title=line(0,.42,Color3.fromRGB(244,236,210));slot.info=line(.42,.26,Color3.fromRGB(220,224,210));slot.price=line(.68,.32,Color3.fromRGB(167,202,127))
  local prompt=Instance.new('ProximityPrompt');prompt.Name='BoostPrompt';prompt.KeyboardKeyCode=Enum.KeyCode.E;prompt.GamepadKeyCode=Enum.KeyCode.ButtonX;prompt.HoldDuration=.35;prompt.MaxActivationDistance=7
  prompt.RequiresLineOfSight=false;prompt.ClickablePrompt=true;prompt.Exclusivity=Enum.ProximityPromptExclusivity.OnePerButton;prompt.Parent=anchor;slot.prompt=prompt
  prompt.Triggered:Connect(function(p)buyBoost(p,i)end)
  boostSlots[i]=slot
  setSlot(slot,boostOffer[i],false)
  task.spawn(function()while anchor.Parent do if not slot.busy then renderSlot(slot)end;task.wait(.5)end end) -- prices follow the level
 end
end
-- Server-only hook for playtests: buy the boost in a slot as player p (same checks as the prompt).
local boostApi=SS:FindFirstChild('RunBoostApi')or Instance.new('BindableFunction');boostApi.Name='RunBoostApi';boostApi.Parent=SS
local visitorGift -- set below, once the gear locker helpers exist
boostApi.OnInvoke=function(action,p,i)
 if action=='visitor'then return visitorGift()end
 if action=='snack'then if takeSnack then takeSnack(p,i)end;local s=snacks[p.UserId];return s and{level=s.level,id=s.id}or false end -- Pit Stop Snacks tests
 if action=='buy'then buyBoost(p,i)end
 local offer={};for k,slot in boostSlots do offer[k]=slot.id or false end
 return {boosts=table.clone(boosts),offer=offer,bank=bank}
end

-- Van locker (storage tray) and shop crates are dressed whenever a new van appears.
local function lockerCF()local cf=vanCF();return cf and cf*LOCKER_OFFSET end
-- Omen 'Visitor' (owner 2026-10-26): a gift for the team at the start of the level. 60%: a free run boost tier
-- (lucky 30% of those: the boost you stacked highest, skipping its higher price); otherwise any shop gear item in the locker.
-- The gift was easy to miss (owner 2026-10-28 "I did not see what the visitor gave me, it didn't go anywhere"): every
-- gift is now announced to the team, and a gear gift glows gold in the locker with a VISITOR'S GIFT tag until someone takes it.
local function markGift(m)
 local root=m.PrimaryPart or m:FindFirstChildWhichIsA('BasePart',true);if not root then return end
 local hl=Instance.new('Highlight');hl.Name='VisitorGiftGlow';hl.FillColor=Color3.fromRGB(255,214,110);hl.FillTransparency=.75;hl.OutlineColor=Color3.fromRGB(255,224,140);hl.DepthMode=Enum.HighlightDepthMode.Occluded;hl.Adornee=m;hl.Parent=m
 local sp=Instance.new('ParticleEmitter');sp.Name='VisitorGiftSparkle';sp.Texture='rbxasset://textures/particles/sparkles_main.dds';sp.Color=ColorSequence.new(Color3.fromRGB(255,226,140));sp.LightEmission=1
 sp.Size=NumberSequence.new(.25,0);sp.Lifetime=NumberRange.new(.6,1);sp.Rate=8;sp.Speed=NumberRange.new(.5,1.2);sp.SpreadAngle=Vector2.new(180,180);sp.Parent=root
 local bb=Instance.new('BillboardGui');bb.Name='VisitorGiftTag';bb.Size=UDim2.fromOffset(170,44);bb.StudsOffset=Vector3.new(0,1.6,0);bb.AlwaysOnTop=true;bb.MaxDistance=40;bb.LightInfluence=0;bb.Adornee=root;bb.Parent=root
 local t=Instance.new('TextLabel');t.BackgroundTransparency=1;t.Size=UDim2.fromScale(1,1);t.Font=Enum.Font.FredokaOne;t.TextScaled=true;t.Text="VISITOR'S GIFT";t.TextColor3=Color3.fromRGB(255,224,140);t.Parent=bb
 local s=Instance.new('UIStroke');s.Thickness=2;s.Color=Color3.fromRGB(40,24,10);s.Parent=t
 m:GetAttributeChangedSignal('HeldBy'):Connect(function()if m:GetAttribute('HeldBy')then for _,x in{hl,sp,bb}do if x.Parent then x:Destroy()end end end end)
end
visitorGift=function()
 local open={};for _,id in BOOST_IDS do if boosts[id]<BOOST_MAX then open[#open+1]=id end end
 if #open>0 and math.random()<.6 then
  local id=open[math.random(1,#open)]
  if math.random()<.3 then local best;for _,o in open do if boosts[o]>0 and(not best or boosts[o]>boosts[best])then best=o end end;id=best or id end
  boosts[id]+=1;publishBoosts();rebuildOffer()
  toastAll(('THE VISITOR gave the team a free %s boost (%d/%d)!'):format(BOOSTS[id].name,boosts[id],BOOST_MAX))
  return ('a free %s (%d/%d)'):format(BOOSTS[id].name,boosts[id],BOOST_MAX)
 end
 local entry=SHOP[math.random(1,#SHOP)];local cf=lockerCF()
 local gift=cf and spawnGear(entry.id,cf*CFrame.new(0,1.2,0),entry.charges)
 if gift then markGift(gift)end
 toastAll(('THE VISITOR left a free %s in the van gear locker (the glowing one)!'):format(entry.name))
 return 'a free '..entry.name..' in the gear locker'
end
-- Van radio (owner 2026-10-26): an old radio on the van table, behind the cats on the left, plays "Action"
-- (130366303895413) , "Funky A" (1840434670) and "Scrub Down Shuffle" (136111011818042) back to back on repeat, and switches song each new level, through a crunchy, band-limited old-radio filter. Heard only near it (Linear
-- roll-off: full volume within RADIO_NEAR studs, silent past RADIO_FAR). Level music fades out in the van
-- (LevelAmbienceClient), so inside the van the radio is the music.
local RADIO_SONGS={'rbxassetid://130366303895413','rbxassetid://1840434670','rbxassetid://136111011818042','rbxassetid://1842627030','rbxassetid://87210168734983'} -- Action, Funky A, Scrub Down Shuffle, Funky Beats, Funky Town: all through the same radio effects
local radioSong,radioIndex=nil,1 -- the playing Sound and its playlist slot
local radioStartedAt -- os.clock() when the current song started: a rebuilt van (mission start) picks up where it was
local function radioPlay(i)
 radioIndex=(i-1)%#RADIO_SONGS+1
 radioStartedAt=os.clock()
 if radioSong and radioSong.Parent then radioSong.SoundId=RADIO_SONGS[radioIndex];radioSong.TimePosition=0;radioSong:Play()end
end
local radioHooked=false
local function hookRadioLevels() -- a new level, a new song (hooked on the first build: never yields script load)
 local rs=RS:FindFirstChild('RecoveryRound');if radioHooked or not rs then return end
 -- Only a level that goes UP from a real level changes the song: the mission start (nil/0 -> 1) and retries keep it.
 local last=rs:GetAttribute('Round')
 radioHooked=true;rs:GetAttributeChangedSignal('Round'):Connect(function()
  local r=rs:GetAttribute('Round');if type(last)=='number'and last>=1 and type(r)=='number'and r>last then radioPlay(radioIndex+1)end;last=r
 end)
end
local RADIO_NEAR,RADIO_FAR,RADIO_VOLUME=8,42,.35 -- owner 2026-10-29: 'van music too loud' (was .594); 2026-10-26: faint from the spawn (~25-31 studs)
local function buildRadio(parent,cf)
 local old=parent:FindFirstChild('VanRadio');if old then old:Destroy()end
 local m=Instance.new('Model');m.Name='VanRadio'
 local function piece(name,size,offset,color,material,shape)
  local p=Instance.new('Part');p.Name=name;p.Size=size;p.CFrame=cf*offset;p.Color=color;p.Material=material or Enum.Material.SmoothPlastic
  p.Anchored=true;p.CanCollide=false;p.CanQuery=false;p.CanTouch=false;p.CastShadow=false;p.TopSurface=Enum.SurfaceType.Smooth;p.BottomSurface=Enum.SurfaceType.Smooth
  if shape then p.Shape=shape end;p.Parent=m;return p
 end
 -- Front is -Z (faces into the van). About 1.6 x 1 x .7 studs: a little tabletop set.
 local body=piece('Body',Vector3.new(1.6,.95,.7),CFrame.new(0,.475,0),Color3.fromRGB(92,64,44),Enum.Material.Wood)
 piece('Grille',Vector3.new(.8,.62,.05),CFrame.new(-.33,.5,-.36),Color3.fromRGB(48,44,40),Enum.Material.Fabric)
 piece('Dial',Vector3.new(.5,.24,.05),CFrame.new(.42,.62,-.36),Color3.fromRGB(255,214,140),Enum.Material.Neon)
 piece('KnobL',Vector3.new(.06,.16,.16),CFrame.new(.28,.28,-.38)*CFrame.Angles(0,math.rad(90),0),Color3.fromRGB(30,26,24),nil,Enum.PartType.Cylinder)
 piece('KnobR',Vector3.new(.06,.16,.16),CFrame.new(.56,.28,-.38)*CFrame.Angles(0,math.rad(90),0),Color3.fromRGB(30,26,24),nil,Enum.PartType.Cylinder)
 piece('Handle',Vector3.new(1.1,.08,.08),CFrame.new(0,1.02,0),Color3.fromRGB(36,32,30),Enum.Material.Metal)
 piece('Antenna',Vector3.new(.04,1.1,.04),CFrame.new(.62,1.4,.18)*CFrame.Angles(0,0,math.rad(-18)),Color3.fromRGB(180,180,176),Enum.Material.Metal)
 m.PrimaryPart=body
 local glow=Instance.new('PointLight');glow.Color=Color3.fromRGB(255,206,130);glow.Brightness=.6;glow.Range=5;glow.Shadows=false;glow.Parent=m.Dial
 local s=Instance.new('Sound');s.Name='RadioSong';s.SoundId=RADIO_SONGS[radioIndex];s.Looped=false;s.Volume=RADIO_VOLUME
 s.RollOffMode=Enum.RollOffMode.Linear;s.RollOffMinDistance=RADIO_NEAR;s.RollOffMaxDistance=RADIO_FAR
 local music=game:GetService('SoundService'):FindFirstChild('GameplayMusic');if music then s.SoundGroup=music end
 -- The old-radio sound: no bass, thin top, a honky mid, light crunch and a faint wobble. Kept gentle so it stays nice.
 local eq=Instance.new('EqualizerSoundEffect');eq.LowGain=-24;eq.MidGain=5;eq.HighGain=-14;eq.Priority=1;eq.Parent=s
 local crunch=Instance.new('DistortionSoundEffect');crunch.Level=.32;crunch.Priority=2;crunch.Parent=s
 local wobble=Instance.new('TremoloSoundEffect');wobble.Depth=.12;wobble.Frequency=5;wobble.Duty=.5;wobble.Priority=3;wobble.Parent=s
 local eq2=Instance.new('EqualizerSoundEffect');eq2.LowGain=-10;eq2.MidGain=0;eq2.HighGain=-8;eq2.Priority=4;eq2.Parent=s -- tame the crunch's fizz
 s.Parent=body
 m.Parent=parent
 radioSong=s;s.Ended:Connect(function()if radioSong==s then radioPlay(radioIndex+1)end end) -- one ends, the other starts
 if radioStartedAt then s.TimePosition=math.max(0,os.clock()-radioStartedAt)else radioStartedAt=os.clock()end
 s:Play();hookRadioLevels()
 return m
end
local function renderSnacks()
 local level=snackLevel();local ph=phase()
 local open=level>=SNACK_FIRST_LEVEL and(ph=='Won'or ph=='Searching'or ph=='Selling'or ph=='Returning')
 if snackSign then
  snackSign.Text=level<SNACK_FIRST_LEVEL and'FREE SNACKS AFTER YOUR FIRST CLEAR'or('FREE SNACK: PICK 1 BOOST FOR LEVEL '..level)
 end
 local pair=snackPair(level)
 for i,slot in snackSlots do
  local id=pair[i];local def=SNACKS[id];local maxed=boosts[id]>=BOOST_MAX
  slot.title.Text=open and snackBoostName(id):upper()or'';slot.title.TextColor3=def.color
  slot.info.Text=open and(maxed and'Already maxed for the team'or def.info)or''
  slot.when.Text=open and(def.name..' \u{00B7} level '..level..' only')or''
  slot.prompt.Enabled=open and not maxed
  slot.prompt.ObjectText=('%s: %s'):format(def.name,snackBoostName(id));slot.prompt.ActionText=('Eat (free, level %d only)'):format(level)
 end
end
takeSnack=function(p,i)
 local slot=snackSlots[i];if not slot or not slot.anchor.Parent then return end
 local ok,r=alive(p);if not ok or not r then return end
 if(r.Position-slot.anchor.Position).Magnitude>9 then return end
 local ph=phase();if ph~='Won'and ph~='Searching'and ph~='Selling'and ph~='Returning'then return end
 local level=snackLevel()
 if level<SNACK_FIRST_LEVEL then toast(p,'Free snacks start after your first cleared level.');return end
 local id=snackPair(level)[i];local def=SNACKS[id]
 local have=snacks[p.UserId]
 if have and have.level==level then toast(p,('You already ate %s (%s) for level %d. One snack each per level.'):format(SNACKS[have.id].name,snackBoostName(have.id),level));return end
 if boosts[id]>=BOOST_MAX then toast(p,('Your team already has the most %s. Take the other snack!'):format(BOOSTS[id].name));return end
 snacks[p.UserId]={level=level,id=id};publishBoosts()
 Audio.Play('JarPop',slot.anchor)
 -- the snack flies out of its bay into the player (server-side, everyone sees it), then a happy munch: chewing mouth
 -- (VoiceMouthClient CrunchUntil) with a squish, and a grin after it (FaceBeat 'grin')
 local pop=Instance.new('Part');pop.Name='SnackPop';pop.Shape=Enum.PartType.Ball;pop.Size=Vector3.new(.5,.5,.5);pop.Color=def.color;pop.Material=Enum.Material.Neon
 pop.Anchored=true;pop.CanCollide=false;pop.CanQuery=false;pop.CanTouch=false;pop.CastShadow=false;pop.CFrame=slot.anchor.CFrame;pop.Parent=slot.anchor.Parent
 TweenService:Create(pop,TweenInfo.new(.45,Enum.EasingStyle.Quad,Enum.EasingDirection.In),{CFrame=r.CFrame*CFrame.new(0,1.2,0),Size=Vector3.new(.15,.15,.15)}):Play()
 Debris:AddItem(pop,.5)
 local t=workspace:GetServerTimeNow()
 p:SetAttribute('CrunchUntil',math.max(p:GetAttribute('CrunchUntil')or 0,t+1.8));p:SetAttribute('FaceBeat','grin');p:SetAttribute('FaceBeatUntil',t+3.4)
 task.delay(.45,function()local c=p.Character;local head=c and c:FindFirstChild('Head');if head then Audio.Play('FrostingSquish',head)end end)
 local now=(state and state:GetAttribute('Round'))==level
 toast(p,now and('%s: %s for this level. %s.'):format(def.name,snackBoostName(id),def.info)or('%s: %s saved for level %d. %s.'):format(def.name,snackBoostName(id),level,def.info))
end
local function dressSnacks(v,cf)
 table.clear(snackSlots);snackSign=nil
 local home=cf*SNACK_OFFSET
 local template=SS:FindFirstChild('PitStopSnacksDecor')
 if template then
  local m=template:Clone();m.Name='PitStopSnacks'
  for _,d in m:GetDescendants()do if d:IsA('BasePart')then d.Anchored=true;d.CanQuery=false;d.CanTouch=false end end
  m:PivotTo(home);m.Parent=v
 end
 local function anchorPart(name,size,offset)
  local a=Instance.new('Part');a.Name=name;a.Size=size;a.Transparency=1;a.Anchored=true;a.CanCollide=false;a.CanQuery=false;a.CanTouch=false;a.CastShadow=false
  a.CFrame=home*offset;a.Parent=v;return a
 end
 local function line(parent,y,h,color)
  local t=Instance.new('TextLabel');t.Position=UDim2.fromScale(0,y);t.Size=UDim2.fromScale(1,h);t.BackgroundTransparency=1;t.Font=Enum.Font.FredokaOne;t.TextScaled=true;t.TextColor3=color;t.Text='';t.Parent=parent
  local s=Instance.new('UIStroke');s.Thickness=1.5;s.Transparency=.3;s.Parent=t;return t
 end
 local top=anchorPart('PitStopSign',Vector3.new(2.4,.4,.2),CFrame.new(0,4.75,0))
 local bb=Instance.new('BillboardGui');bb.Name='PitStopLabel';bb.Size=UDim2.fromOffset(250,30);bb.MaxDistance=40;bb.LightInfluence=0;bb.Parent=top
 snackSign=line(bb,0,1,Color3.fromRGB(255,214,110))
 for i,side in {-1,1}do
  local anchor=anchorPart('SnackSlot'..i,Vector3.new(1,1.2,.4),CFrame.new(side*.6,2.45,-1.1)) -- in front of each bay (front = -Z)
  -- sized in studs (was 130x44 px, so far away the two labels ran into each other): boost +1 / what it does / snack + level
  local label=Instance.new('BillboardGui');label.Name='SnackLabel';label.Size=UDim2.fromScale(1.15,.78);label.StudsOffset=Vector3.new(0,-1.05,.3);label.MaxDistance=20;label.LightInfluence=0;label.Parent=anchor
  local title=line(label,0,.4,Color3.fromRGB(244,236,210));local info=line(label,.42,.3,Color3.fromRGB(230,232,220));local when=line(label,.74,.26,Color3.fromRGB(190,196,186))
  local prompt=Instance.new('ProximityPrompt');prompt.Name='SnackPrompt';prompt.KeyboardKeyCode=Enum.KeyCode.E;prompt.GamepadKeyCode=Enum.KeyCode.ButtonX
  prompt.HoldDuration=.2;prompt.MaxActivationDistance=6;prompt.RequiresLineOfSight=false;prompt.ClickablePrompt=true;prompt.Exclusivity=Enum.ProximityPromptExclusivity.OnePerButton;prompt.Parent=anchor
  prompt.Triggered:Connect(function(p)takeSnack(p,i)end)
  snackSlots[i]={anchor=anchor,title=title,info=info,when=when,prompt=prompt}
 end
 renderSnacks()
 task.spawn(function()while top.Parent do renderSnacks();task.wait(.5)end end) -- follows the phase and level, like the boost labels
end
local function dressVan(v)
 if v:FindFirstChild('GearLocker')then return end
 local cf=v:GetPivot()
 -- The radio stands on the console desk just behind the alien cats (toward the windshield), facing into the van.
 do local cats=v:FindFirstChild('AlienCatsDecor',true);local desk=v:FindFirstChild('ConsoleDesk')
  if cats and desk then local q=cf:PointToObjectSpace(cats:GetPivot().Position);local top=cf:PointToObjectSpace(desk.Position).Y+desk.Size.Y/2
   buildRadio(v,cf*CFrame.new(q.X-.1,top,q.Z+1.6))end end
 local tray=Instance.new('Part');tray.Name='GearLocker';tray.Anchored=true;tray.CanCollide=true;tray.Size=LOCKER_SIZE
 tray.CFrame=cf*LOCKER_OFFSET;tray.Color=Color3.fromRGB(38,44,42);tray.Material=Enum.Material.DiamondPlate;tray.Parent=v
 for _,side in {-1,1}do
  local rim=Instance.new('Part');rim.Name='GearLockerRim';rim.Anchored=true;rim.CanCollide=false;rim.Size=Vector3.new(.12,.3,LOCKER_SIZE.Z)
  rim.CFrame=tray.CFrame*CFrame.new(side*LOCKER_SIZE.X/2,.15,0);rim.Color=Color3.fromRGB(70,80,74);rim.Material=Enum.Material.Metal;rim.Parent=v
 end
 local sign=Instance.new('BillboardGui');sign.Name='GearLockerSign';sign.Size=UDim2.fromOffset(160,26);sign.StudsOffset=Vector3.new(0,1.6,0);sign.MaxDistance=30;sign.LightInfluence=0;sign.Parent=tray
 local t=Instance.new('TextLabel');t.Size=UDim2.fromScale(1,1);t.BackgroundTransparency=1;t.Font=Enum.Font.FredokaOne;t.TextScaled=true;t.TextColor3=Color3.fromRGB(244,236,210);t.Text='GEAR LOCKER';t.Parent=sign
 local st=Instance.new('UIStroke');st.Thickness=1.5;st.Transparency=.3;st.Parent=t
 -- Shop: the 4 crates on the spawn's right wall (+X), nearest first.
 local crates={}
 for _,d in v:GetDescendants()do if d:IsA('BasePart')and d.Name=='EquipmentCrate'and cf:PointToObjectSpace(d.Position).X>0 then table.insert(crates,d)end end
 table.sort(crates,function(a,b)return cf:PointToObjectSpace(a.Position).Z<cf:PointToObjectSpace(b.Position).Z end)
 -- A fifth interaction on its own shelf below the four existing gear displays.
 local upperShelf
 for _,d in v:GetDescendants()do if d:IsA('BasePart')and d.Name=='StorageShelf'and cf:PointToObjectSpace(d.Position).X>0 then upperShelf=d end end
 if upperShelf and #crates>=4 then
  local q=cf:PointToObjectSpace(upperShelf.Position)
  local shelf=Instance.new('Part');shelf.Name='SkitterTrapShelf';shelf.Size=Vector3.new(upperShelf.Size.X,.12,4.8);shelf.CFrame=cf*CFrame.new(q.X-.8,q.Y-2.14,q.Z-.5)
  shelf.Anchored=true;shelf.CanCollide=false;shelf.CanQuery=false;shelf.Transparency=1;shelf.Color=upperShelf.Color;shelf.Material=upperShelf.Material;shelf.Parent=v
  local crate=Instance.new('Part');crate.Name='SkitterTrapShopCrate';crate.Size=Vector3.new(2,.8,3);crate.CFrame=shelf.CFrame*CFrame.new(0,.48,0);crate.Anchored=true;crate.Transparency=1;crate.CanCollide=false;crate.CanTouch=false;crate.Parent=v
  table.insert(crates,crate)
 end
 -- Med kits get their own first-aid shelf under the van's safety cabinet (owner, 2026-10-22), away from the gear shelf
 -- and the run-boost stands on the bench: MedKit on the left, Big MedKit on the right, with a FIRST AID lip sign.
 if upperShelf and #crates==5 then
  local cabinet=v:FindFirstChild('SafetyCabinet',true)
  if cabinet and cabinet:IsA('BasePart')then
   local c=cf:PointToObjectSpace(cabinet.Position)
   local shelfX,shelfY,shelfLen=c.X-.62,c.Y-2.3,4.4
   local shelf=Instance.new('Part');shelf.Name='FirstAidShelf';shelf.Size=Vector3.new(1.3,.16,shelfLen);shelf.CFrame=cf*CFrame.new(shelfX,shelfY,c.Z)
   shelf.Anchored=true;shelf.CanCollide=false;shelf.CanQuery=false;shelf.CanTouch=false;shelf.Color=upperShelf.Color;shelf.Material=upperShelf.Material;shelf.Parent=v
   for _,dz in {-shelfLen/2+.4,shelfLen/2-.4}do
    local bracket=Instance.new('Part');bracket.Name='FirstAidBracket';bracket.Size=Vector3.new(.9,.5,.1);bracket.CFrame=cf*CFrame.new(shelfX+.2,shelfY-.3,c.Z+dz)
    bracket.Anchored=true;bracket.CanCollide=false;bracket.CanQuery=false;bracket.CanTouch=false;bracket.Color=Color3.fromRGB(60,60,66);bracket.Material=Enum.Material.Metal;bracket.Parent=v
   end
   local lip=Instance.new('Part');lip.Name='FirstAidLip';lip.Size=Vector3.new(.08,.32,shelfLen);lip.CFrame=cf*CFrame.new(shelfX-.66,shelfY-.06,c.Z)
   lip.Anchored=true;lip.CanCollide=false;lip.CanQuery=false;lip.CanTouch=false;lip.Color=Color3.fromRGB(238,234,224);lip.Material=Enum.Material.SmoothPlastic;lip.Parent=v
   local sg=Instance.new('SurfaceGui');sg.Face=Enum.NormalId.Left;sg.CanvasSize=Vector2.new(440,32);sg.LightInfluence=0;sg.Parent=lip
   local tx=Instance.new('TextLabel');tx.Size=UDim2.fromScale(1,1);tx.BackgroundTransparency=1;tx.Font=Enum.Font.FredokaOne;tx.TextScaled=true
   tx.TextColor3=Color3.fromRGB(60,140,80);tx.Text='FIRST AID  -  ONE OF EACH PER LEVEL';tx.Parent=sg
   for _,dz in {1.15,-1.15}do -- MedKit first (SHOP order), toward the gear shop side
    local crate=Instance.new('Part');crate.Name='MedicalGearShopCrate';crate.Size=Vector3.new(1.2,.8,1.8)
    crate.CFrame=cf*CFrame.new(shelfX,shelfY+.08+.4,c.Z+dz)
    crate.Anchored=true;crate.Transparency=1;crate.CanCollide=false;crate.CanTouch=false;crate.Parent=v;crates[#crates+1]=crate
   end
  else
   local q=cf:PointToObjectSpace(upperShelf.Position)
   for _,dz in {-4.5,3.5}do
    local crate=Instance.new('Part');crate.Name='MedicalGearShopCrate';crate.Size=Vector3.new(2,.8,3)
    crate.CFrame=cf*CFrame.new(q.X-.8,q.Y-2.14+.48,q.Z+dz)
    crate.Anchored=true;crate.Transparency=1;crate.CanCollide=false;crate.CanTouch=false;crate.Parent=v;crates[#crates+1]=crate
   end
  end
 end
 -- Utility gear (2026-10-27): a third shelf on the right wall straight above the GEAR LOCKER. Only when the seven
 -- older crates exist, so SHOP[8..11] land on these four.
 if #crates==7 and SHOP[8] then
  local shelfX,shelfY,shelfZ,shelfLen=10.2,3.1,-6.9,6 -- low enough that the tallest item (the beacon) clears the mastery board above
  local shelf=Instance.new('Part');shelf.Name='UtilityGearShelf';shelf.Size=Vector3.new(2.4,.16,shelfLen);shelf.CFrame=cf*CFrame.new(shelfX,shelfY,shelfZ)
  shelf.Anchored=true;shelf.CanCollide=false;shelf.CanQuery=false;shelf.CanTouch=false;shelf.Color=Color3.fromRGB(79,91,78);shelf.Material=Enum.Material.SmoothPlastic;shelf.Parent=v
  for _,dz in {-shelfLen/2+.5,shelfLen/2-.5}do
   local b=Instance.new('Part');b.Name='UtilityGearBracket';b.Size=Vector3.new(.14,1.1,.14);b.CFrame=cf*CFrame.new(11.1,shelfY-.55,shelfZ+dz)
   b.Anchored=true;b.CanCollide=false;b.CanQuery=false;b.CanTouch=false;b.Color=Color3.fromRGB(117,126,106);b.Material=Enum.Material.Metal;b.Parent=v
  end
  local lip=Instance.new('Part');lip.Name='UtilityGearLip';lip.Size=Vector3.new(.08,.3,shelfLen);lip.CFrame=cf*CFrame.new(shelfX-1.22,shelfY-.05,shelfZ)
  lip.Anchored=true;lip.CanCollide=false;lip.CanQuery=false;lip.CanTouch=false;lip.Color=Color3.fromRGB(238,234,224);lip.Material=Enum.Material.SmoothPlastic;lip.Parent=v
  local sg=Instance.new('SurfaceGui');sg.Face=Enum.NormalId.Left;sg.CanvasSize=Vector2.new(600,30);sg.LightInfluence=0;sg.Parent=lip
  local tx=Instance.new('TextLabel');tx.Size=UDim2.fromScale(1,1);tx.BackgroundTransparency=1;tx.Font=Enum.Font.FredokaOne;tx.TextScaled=true
  tx.TextColor3=Color3.fromRGB(70,120,150);tx.Text='UTILITY  -  SET IT DOWN TO USE IT';tx.Parent=sg
  for n=8,math.min(11,#SHOP)do -- nearest the spawn (lowest van-local Z) first, like the other crates
   local crate=Instance.new('Part');crate.Name='UtilityGearShopCrate';crate.Size=Vector3.new(1.6,.8,1.4)
   crate.CFrame=cf*CFrame.new(shelfX,shelfY+.08+.4,shelfZ-2.25+(n-8)*1.5)
   crate.Anchored=true;crate.Transparency=1;crate.CanCollide=false;crate.CanTouch=false;crate.Parent=v;crates[#crates+1]=crate
  end
 end
 for i,crate in crates do
  local entry=SHOP[i];if not entry then break end
  if entry.id=='SkitterTrap' and game.ServerScriptService.CreatureRoamServer:GetAttribute('SkitterEnabled')~=true then crate:Destroy();continue end -- no Skitter, no trap for sale
  crate:SetAttribute('GearShopId',entry.id);crate.Transparency=1;crate.CanCollide=false
  local template=SS.CursedItemKit:FindFirstChild(entry.id)
  if template then
   local show=template:Clone();show.Name='GearShowcase_'..entry.id
   for k in show:GetAttributes()do show:SetAttribute(k,nil)end
   for _,d in show:GetDescendants()do if d:IsA('BasePart')then d.Anchored=true;d.CanCollide=false;d.CanQuery=false;d.CanTouch=false end end
   show:ScaleTo(UTILITY_SHOW[entry.id] or(entry.id=='MedKit'and .85 or entry.id=='BigMedKit'and .7 or(entry.id=='SkitterTrap'and .9 or SHOWCASE_SCALE)))
   -- Sits on the shelf where the crate was.
   local base=crate.CFrame*CFrame.new(0,-crate.Size.Y/2,0)
   show:PivotTo(CFrame.new(base.Position+Vector3.new(0,show.PrimaryPart.Size.Y/2,0))*cf.Rotation) -- side-on: the aisle sees each item's profile
   if entry.id=='MedKit'or entry.id=='BigMedKit'then
    show:PivotTo(CFrame.new(base.Position)*cf.Rotation*CFrame.Angles(0,math.pi/2,0))
    local box,size=show:GetBoundingBox();show:PivotTo(show:GetPivot()+Vector3.new(0,base.Position.Y+.025-(box.Position.Y-size.Y/2),0))
   end
   show.Parent=v
  end
  local prompt=Instance.new('ProximityPrompt');prompt.Name='GearShopPrompt';prompt.ObjectText=entry.name;prompt.ActionText='Buy $'..gearPrice(entry)
  prompt.KeyboardKeyCode=Enum.KeyCode.E;prompt.GamepadKeyCode=Enum.KeyCode.ButtonX;prompt.HoldDuration=.35;prompt.MaxActivationDistance=7
  prompt.RequiresLineOfSight=false;prompt.ClickablePrompt=true;prompt.Exclusivity=Enum.ProximityPromptExclusivity.OnePerButton;prompt.Parent=crate
  local label=Instance.new('BillboardGui');label.Name='GearShopLabel';label.Size=UDim2.fromOffset(150,40);label.StudsOffset=Vector3.new(0,(entry.id=='SkitterTrap'or entry.id=='MedKit'or entry.id=='BigMedKit')and .65 or UTILITY_SHOW[entry.id]and 1.3 or 1.5,0);if entry.id=='MedKit'or entry.id=='BigMedKit'then label.StudsOffset=Vector3.zero;label.StudsOffsetWorldSpace=cf:VectorToWorldSpace(Vector3.new(-1.25,0,0))+Vector3.new(0,.75,0)end;if UTILITY_SHOW[entry.id]then label.Size=UDim2.fromOffset(112,32);label.StudsOffset=Vector3.zero;label.StudsOffsetWorldSpace=cf:VectorToWorldSpace(Vector3.new(-1.35,0,0))+Vector3.new(0,-1.05,0)end;label.MaxDistance=24;label.LightInfluence=0;label.Parent=crate
  local n=Instance.new('TextLabel');n.Size=UDim2.fromScale(1,.55);n.BackgroundTransparency=1;n.Font=Enum.Font.FredokaOne;n.TextScaled=true;n.TextColor3=Color3.fromRGB(244,236,210);n.Text=entry.name:upper();n.Parent=label
  local pr=n:Clone();pr.Position=UDim2.fromScale(0,.55);pr.Size=UDim2.fromScale(1,.45);pr.TextColor3=Color3.fromRGB(167,202,127);pr.Text='$'..gearPrice(entry)..(entry.charges>1 and(' - '..entry.charges..' shots')or'');pr.Parent=label
  do -- the price follows the level (level 2 sale) and, for guns, earlier buys
   task.spawn(function()while crate.Parent do
    local price=gearPrice(entry)
    local soldOut=MED_STOCK[entry.id] and medBoughtLevel[entry.id]==(state and state:GetAttribute('Round'))
    prompt.Enabled=not soldOut;prompt.ActionText='Buy $'..price
    pr.Text=soldOut and 'SOLD OUT - next level' or('$'..price..(entry.charges>1 and(' - '..entry.charges..' shots')or''))
    pr.TextColor3=soldOut and Color3.fromRGB(200,190,170)or Color3.fromRGB(167,202,127)
    task.wait(.5)
   end end)
  end
  for _,x in {n,pr}do local s2=Instance.new('UIStroke');s2.Thickness=1.5;s2.Transparency=.3;s2.Parent=x end
  prompt.Triggered:Connect(function(p)
   local ok,r=alive(p);if not ok then return end
   if (r.Position-crate.Position).Magnitude>9 then return end
   local price=gearPrice(entry)
   local round=state and state:GetAttribute('Round')
   if MED_STOCK[entry.id] and medBoughtLevel[entry.id]==round then toast(p,entry.name..' is sold out. One per level: it restocks next level.');return end
   if bank<price then toast(p,('Not enough in the team bank ($%d / $%d).'):format(bank,price));return end
   bank-=price;publishBank()
   local out=crate.CFrame*CFrame.new(-1.6,-.2,0) -- pops out on the aisle side of the crate
   if not spawnGear(entry.id,CFrame.new(out.Position),entry.charges)then bank+=price;publishBank();toast(p,'The shop is restocking. Try again in a moment.');return end
   if GUN_IDS[entry.id]then gunBuys[entry.id]=(gunBuys[entry.id]or 0)+1 end
   if MED_STOCK[entry.id]then medBoughtLevel[entry.id]=round end
   toastAll(('%s bought a %s. Team bank: $%d'):format(p.DisplayName,entry.name,bank))
  end)
 end
 -- Line the display items up along the shelf: evenly spaced by their real lengths, resting on the top,
 -- none past either end. Each crate (buy prompt, label, spawn point) moves with its item.
 local shelf
 local tallest=0 -- the tallest gear item on the shelf (the money panel goes above it)
 for _,d in v:GetDescendants()do if d:IsA('BasePart')and d.Name=='StorageShelf'and cf:PointToObjectSpace(d.Position).X>0 then shelf=d end end
 if shelf then
  local q=cf:PointToObjectSpace(shelf.Position);local length=shelf.Size.Z;local top=q.Y+shelf.Size.Y/2
  local rows={}
  for i,crate in crates do
   local show=SHOP[i] and v:FindFirstChild('GearShowcase_'..SHOP[i].id)
   if show and i<=4 then
    local box,size=show:GetBoundingBox();local extent=cf:VectorToObjectSpace(box:VectorToWorldSpace(size))
    table.insert(rows,{crate=crate,show=show,center=cf:PointToObjectSpace(box.Position),z=math.abs(extent.Z),y=math.abs(extent.Y)})
   end
  end
  local used=0;for _,row in rows do used+=row.z;tallest=math.max(tallest,row.y)end
  local gap=math.max(0,(length-used)/(#rows+1));local z=q.Z-length/2+gap
  for _,row in rows do
   local target=Vector3.new(q.X,top+row.y/2,z+row.z/2)
   row.show:PivotTo(row.show:GetPivot()+cf:VectorToWorldSpace(target-row.center))
   local c=cf:PointToObjectSpace(row.crate.Position)
   row.crate.CFrame=row.crate.CFrame+cf:VectorToWorldSpace(Vector3.new(0,0,target.Z-c.Z))
   z+=row.z+gap
  end
 end
 -- Team money: a real panel on the wall above the gear items (owner 2026-10-29; was a floating BillboardGui).
 -- Dark board with a gold rim, facing the aisle (van-local -X), as wide as the shelf.
 if crates[1]then
  local local0,width
  if shelf then
   local q=cf:PointToObjectSpace(shelf.Position)
   -- above the items AND their floating name / price tags (GearShopLabel), so nothing overlaps the panel
   local0=Vector3.new(q.X+shelf.Size.X/2-.08,q.Y+shelf.Size.Y/2+tallest+2.5,q.Z);width=math.min(shelf.Size.Z*.85,7.5)
  else
   local mid=crates[math.min(#crates,2)];local0=cf:PointToObjectSpace(mid.Position)+BANK_SIGN_OFFSET;width=5
  end
  local at=cf*CFrame.new(local0)
  local function panelPart(name,size,c,color,mat)
   local x=Instance.new('Part');x.Name=name;x.Size=size;x.CFrame=c;x.Color=color;x.Material=mat;x.Anchored=true;x.CanCollide=false;x.CanQuery=false;x.CanTouch=false;x.CastShadow=false;x.Parent=v;return x
  end
  panelPart('GearBankTrim',Vector3.new(.06,1.3,width+.2),at*CFrame.new(.04,0,0),Color3.fromRGB(196,156,72),Enum.Material.Metal)
  local panel=panelPart('GearBankPanel',Vector3.new(.1,1.1,width),at,Color3.fromRGB(24,20,30),Enum.Material.SmoothPlastic)
  local g=Instance.new('SurfaceGui');g.Name='TeamMoney';g.Face=Enum.NormalId.Left;g.SizingMode=Enum.SurfaceGuiSizingMode.PixelsPerStud;g.PixelsPerStud=80
  g.LightInfluence=0;g.MaxDistance=60;g.Parent=panel
  local t2=Instance.new('TextLabel');t2.Size=UDim2.fromScale(1,1);t2.BackgroundTransparency=1;t2.TextScaled=true;t2.TextColor3=Color3.fromRGB(255,214,110);t2.Parent=g
  local pad=Instance.new('UIPadding');pad.PaddingTop=UDim.new(.18,0);pad.PaddingBottom=UDim.new(.18,0);pad.PaddingLeft=UDim.new(.04,0);pad.PaddingRight=UDim.new(.04,0);pad.Parent=t2
  local function show()t2.Text='TEAM MONEY:  $'..bank end;show()
  task.spawn(function()while panel.Parent do show();task.wait(.5)end end)
 end
 dressBoosts(v,cf)
 dressSnacks(v,cf) -- Pit Stop Snacks (WorldA)
end

-- Pending gear (level rebuild / loaded save) lands in the locker once the new level is running.
local function flushPending()
 if #pending==0 then return end
 local cf=lockerCF();local spawner=SS:FindFirstChild('SpawnGearItem');local map=missionMap()
 if not cf or not spawner or not map or not map:GetAttribute('RuntimeReady')or phase()~='Searching'then return end
 local list=pending;pending={}
 for i,rec in list do
  if BY_ID[rec.id]then
   local slot=cf*CFrame.new(((i-1)%2-.5)*1.1,.6,-1.8+math.floor((i-1)/2)*1.2%4.8)
   if not spawnGear(rec.id,CFrame.new(slot.Position),rec.charges)then table.insert(pending,rec)end
  end
 end
end

-- Bank: every dollar sold this run. Sold resets to 0 each level, so only increases count.
local function bindState(obj)
 state=obj;lastSold=obj:GetAttribute('Sold')or 0;publishBank()
 obj:GetAttributeChangedSignal('Sold'):Connect(function()
  local s=obj:GetAttribute('Sold')or 0
  if s>lastSold then bank+=s-lastSold;publishBank()end
  lastSold=s
 end)
 obj:GetAttributeChangedSignal('Round'):Connect(function()
  local r=obj:GetAttribute('Round')or 0
  if r<=0 then return end
  if not loadedContext then
   loadedContext=true
   local ok,RunSaves=pcall(require,game.ServerScriptService:WaitForChild('RunSavesService',5))
   local ctx=ok and RunSaves and RunSaves.GetMissionContext and RunSaves.GetMissionContext()
   if ctx and ctx.mode=='load'and type(ctx.slot)=='table'then
    bank=tonumber(ctx.slot.bank)or 0
    local saved=type(ctx.slot.boosts)=='table'and ctx.slot.boosts or {}
    for _,id in BOOST_IDS do boosts[id]=math.clamp(math.floor(tonumber(saved[id])or 0),0,BOOST_MAX)end;publishBoosts();rebuildOffer()
    for _,g in ipairs(ctx.slot.gear or {})do if BY_ID[g.id]then table.insert(pending,{id=g.id,charges=math.clamp(tonumber(g.charges)or BY_ID[g.id].charges,1,BY_ID[g.id].charges)})end end
   end
  elseif r<lastRound then
   -- Team wipe restart: the run starts over, so do the bank and gear.
   bank=0;resetBoosts();table.clear(pending);table.clear(snacks);for m,rec in records do rec.consumed=true;if m.Parent then m:Destroy()end end
  end
  if r~=lastRound then rebuildOffer()end -- every level restocks the boost shelf with a random three
  lastRound=r;lastSold=obj:GetAttribute('Sold')or 0;publishBank()
 end)
end
local existing=RS:FindFirstChild('RecoveryRound');if existing then bindState(existing)end
RS.ChildAdded:Connect(function(c)if c.Name=='RecoveryRound'then bindState(c)end end)

task.spawn(function()
 while true do
  task.wait(1)
  local v=van();if v then dressVan(v)end
  flushPending();publishBoosts() -- players joining / leaving the mission
 end
end)

---------------------------------------------------------------- effects
local function monsters()local w=SS:FindFirstChild('CreatureWeaponApi');if not w then return {}end;local ok,list=pcall(function()return w:Invoke('list')end);return ok and list or {}end
local function weapon(action,model,a,b)local w=SS:FindFirstChild('CreatureWeaponApi');if not w then return false end;local ok,result=pcall(function()return w:Invoke(action,model,a,b)end);return ok and result==true end
local function monsterRoot(model)return model.PrimaryPart or model:FindFirstChild('HumanoidRootPart')or model:FindFirstChildWhichIsA('BasePart',true)end
local function playersCentroid()
 local sum,n=Vector3.zero,0
 for _,p in Players:GetPlayers()do local ok,r=alive(p);if ok then sum+=r.Position;n+=1 end end
 return n>0 and sum/n or nil
end
local function sound(id,parent,volume)
 local s=Instance.new('Sound');s.SoundId='rbxassetid://'..id;s.Volume=volume or 1;s.RollOffMaxDistance=140;s.Parent=parent;s:Play();Debris:AddItem(s,6)
end
local killMonster -- defined below (shared with the slayer)
-- Explosions are visual only (no pressure, no joint breaking): they never hurt players. Monsters take gear damage.
local function explode(pos,damage,by)
 local e=Instance.new('Explosion');e.Position=pos;e.BlastPressure=0;e.BlastRadius=BLAST_RADIUS;e.DestroyJointRadiusPercent=0;e.ExplosionType=Enum.ExplosionType.NoCraters;e.Parent=workspace
 local avoid=playersCentroid()
 for _,m in monsters()do local r=monsterRoot(m);if r and (r.Position-pos).Magnitude<=BLAST_RADIUS then
  local hp=(m:GetAttribute('GearHealth')or MONSTER_HP)-(damage or 0);m:SetAttribute('GearHealth',hp)
  if by then m:SetAttribute('ProvokedBy',by.UserId);m:SetAttribute('ProvokedAt',workspace:GetServerTimeNow())end -- CreatureRoamServer: overrides the spread-out rules
  if hp<=0 then killMonster(m,r.Position)else weapon('blast',m,avoid,FLEE_SECONDS)end
 end end
end
local function beam(from,to,color,width)
 width=width or .12
 local d=(to-from);if d.Magnitude<.01 then return end;local p=Instance.new('Part');p.Anchored=true;p.CanCollide=false;p.CanQuery=false;p.CanTouch=false;p.Material=Enum.Material.Neon;p.Color=color
 p.Size=Vector3.new(width,width,d.Magnitude);p.CFrame=CFrame.lookAt(from+d/2,to);p.Parent=workspace
 TweenService:Create(p,TweenInfo.new(.3),{Transparency=1,Size=Vector3.new(.02,.02,d.Magnitude)}):Play();Debris:AddItem(p,.4)
end
local function aimOf(p,r)
 local aim=p:GetAttribute('GearAim');local head=p.Character and p.Character:FindFirstChild('Head')
 local origin=(head or r).Position
 if Targeting.ValidAim(aim,origin)then return aim.Position,aim.LookVector.Unit end
 return origin,r.CFrame.LookVector
end
local SLAYER_HIT_RADIUS,SLAYER_BEAM_WIDTH=5,.45 -- studs; the other guns use 2.5 and a .12 beam
local function shoot(p,r,m,color,hitRadius,beamWidth)
 local origin,dir=aimOf(p,r)
 local models=monsters()
 local params=RaycastParams.new();params.FilterType=Enum.RaycastFilterType.Exclude;params.RespectCanCollide=true
 local ignore={m};local cam=workspace:FindFirstChild('Camera');if cam then table.insert(ignore,cam)end
 for _,q in Players:GetPlayers()do if q.Character then table.insert(ignore,q.Character)end end
 for _,model in ipairs(models)do table.insert(ignore,model)end
 params.FilterDescendantsInstances=ignore
 local head=p.Character and p.Character:FindFirstChild('Head')
 local anchor=(head or r).Position
 -- A camera may be near the character but on the other side of a wall.
 local offset=origin-anchor
 if offset.Magnitude>.01 and workspace:Raycast(anchor,offset,params)then origin=anchor end
 local hit=workspace:Raycast(origin,dir*GUN_RANGE,params)
 local range=hit and math.min(GUN_RANGE,(hit.Position-origin).Magnitude)or GUN_RANGE
 local muzzle=m.PrimaryPart and m.PrimaryPart.Position or anchor
 local function clear(from,to)
  local delta=to-from
  if delta.Magnitude<.01 then return true end
  local obstruction=workspace:Raycast(from,delta,params)
  return not obstruction
 end
 local target,at=Targeting.Select(models,origin,dir,range,hitRadius or 2.5,function(point)
  return clear(origin,point)and clear(anchor,point)and clear(muzzle,point)
 end)
 local to=at or(hit and hit.Position or origin+dir*GUN_RANGE)
 beam(muzzle,to,color,beamWidth)
 return target,to,muzzle
end
local function spendCharge(p,m,entry)
 local left=(m:GetAttribute('Charges')or entry.charges)-1;m:SetAttribute('Charges',left)
 if records[m]then records[m].charges=left end
 if left<=0 then toast(p,entry.name..' is out of shots.');consume(p,m)else toast(p,entry.name..': '..left..' shot'..(left==1 and''or's')..' left')end
end

local function armMine(pos)
 local template=SS.CursedItemKit:FindFirstChild('ProxMine');if not template then return end
 local mine=template:Clone();mine.Name='ArmedProxMine'
 for _,d in mine:GetDescendants()do if d:IsA('BasePart')then d.Anchored=true;d.CanCollide=false;d.CanQuery=false end end
 for k in mine:GetAttributes()do mine:SetAttribute(k,nil)end
 mine:PivotTo(CFrame.new(pos+Vector3.new(0,mine.PrimaryPart.Size.Y/2,0)))
 mine.Parent=missionMap()or workspace
 local led=mine:FindFirstChild('ProxMine__Led')
 sound(9113438364,mine.PrimaryPart,.5)
 task.spawn(function()
  task.wait(1.5) -- arming time
  local blink=0
  while mine.Parent do
   blink+=1;if led then led.Transparency=blink%4<2 and 0 or .8 end
   for _,m in monsters()do local mr=monsterRoot(m)
    if mr then local d=mr.Position-pos
     if Vector3.new(d.X,0,d.Z).Magnitude<=MINE_TRIGGER and math.abs(d.Y)<9 then mine:Destroy();explode(pos,MINE_DAMAGE);return end
    end
   end
   task.wait(.15)
  end
 end)
end

local function armSkitterTrap(pos)
 local map=missionMap();local template=SS.CursedItemKit:FindFirstChild('SkitterTrap')
 if not map or not template or not template.PrimaryPart then return nil end
 local trap=template:Clone();trap.Name='ArmedSkitterTrap'
 for k in trap:GetAttributes()do trap:SetAttribute(k,nil)end
 local pivot=trap:GetPivot();local bottom=math.huge
 for _,part in trap:GetDescendants()do if part:IsA('BasePart')then
  if part.Transparency<.95 then bottom=math.min(bottom,pivot:PointToObjectSpace(part.Position).Y-part.Size.Y*.5)end
  part.Anchored=true;part.CanCollide=false;part.CanTouch=false;part.CanQuery=false
 end end
 if bottom==math.huge then bottom=0 end
 trap:PivotTo(CFrame.new(pos+Vector3.new(0,.035-bottom,0)));trap:SetAttribute('Armed',false);trap:SetAttribute('TargetKind','Skitter');trap:SetAttribute('TrapPosition',pos)
 trap.Parent=map
 sound(9113438364,trap.PrimaryPart,.5)
 task.spawn(function()
  task.wait(.8)
  if not trap.Parent or missionMap()~=map then return end
  trap:SetAttribute('Armed',true)
  while trap.Parent and missionMap()==map do
   if phase()=='Deploying'or phase()=='Won'or phase()=='Failed'then trap:Destroy();return end
   local api=SS:FindFirstChild('CreatureWeaponApi')
   if api then
    local ok,list=pcall(function()return api:Invoke('skitters')end)
    if ok and type(list)=='table'then for _,monster in list do
     if monster:GetAttribute('CreatureKind')=='Skitter'and monster:GetAttribute('Grounded')==true then
      -- Creature owner revalidates registered identity, floor support, proximity and LOS atomically.
      if weapon('skitterTrap',monster,pos)then
       trap:SetAttribute('Armed',false);sound(9113438364,trap.PrimaryPart,.65)
       toastAll('The Skitter Trap caught the Skitter!');trap:Destroy();return
      end
     end
    end end
   end
   task.wait(.1)
  end
  if trap.Parent then trap:Destroy()end
 end)
 return trap
end

killMonster=function(target,dropAt)
 local slainName,slainLevel=target.Name,state and state:GetAttribute('Round') -- the orb remembers its monster: selling it sets that monster loose again
 if not weapon('kill',target)then return false end;toastAll('A monster was destroyed! It dropped a $'..ORB_VALUE..' orb. It comes back after 2:30, or as soon as the orb is sold.')
 -- Reward: a sellable orb drops where the monster died (snapped to the floor below).
 local params=RaycastParams.new();params.FilterType=Enum.RaycastFilterType.Exclude
 local folder=workspace:FindFirstChild('RoamingCreatures');params.FilterDescendantsInstances=folder and {folder} or {}
 local floor=workspace:Raycast(dropAt+Vector3.new(0,2,0),Vector3.new(0,-30,0),params)
 local spawner=SS:FindFirstChild('SpawnGearItem')
 if spawner then pcall(function()local orb=spawner:Invoke('MonsterOrb',CFrame.new((floor and floor.Position or dropAt)+Vector3.new(0,.8,0)));if orb then orb:SetAttribute('MonsterName',slainName);orb:SetAttribute('MonsterRound',slainLevel)end end)end
end
-- Thrown items (CursedItemsServer, 2026-10-22): each direct hit takes 20% of a monster's health and staggers it (a carried
-- player is dropped). The fifth hit destroys it, with the usual orb.
local throwApi=SS:FindFirstChild('MonsterThrowApi')or Instance.new('BindableFunction');throwApi.Name='MonsterThrowApi';throwApi.Parent=SS
throwApi.OnInvoke=function(m,thrower)
 local r=m and m.Parent and monsterRoot(m);if not r then return nil end
 local hp=(m:GetAttribute('GearHealth')or MONSTER_HP)-MONSTER_HP*.2;m:SetAttribute('GearHealth',hp)
 m:SetAttribute('HitFlashAt',workspace:GetServerTimeNow())
 if thrower then m:SetAttribute('ProvokedBy',thrower.UserId);m:SetAttribute('ProvokedAt',workspace:GetServerTimeNow())end -- antagonized: overrides the spread-out rules (CreatureRoamServer)
 if hp<=0 then killMonster(m,r.Position);return 'killed' end
 -- A hit stuns it for a second (dizzy stars, MonsterAbilityClient), drops anyone it carries, then it runs from the thrower
 -- for 6 s, like a grenade blast (owner, 2026-10-22).
 m:SetAttribute('StaggerAt',os.clock());m:SetAttribute('StunnedVisualUntil',workspace:GetServerTimeNow()+1)
 local tr=thrower and thrower.Character and thrower.Character:FindFirstChild('HumanoidRootPart')
 weapon('blast',m,tr and tr.Position or playersCentroid(),6)
 return 'hit'
end
---------------------------------------------------------------- utility gear core (ChirpyDecoy / DoorWedge / CartBeacon / CartBell)
-- Owner 2026-10-27. Utility gear has no use key: it acts when its holder lets go of it in the right spot (track()
-- calls onGearSet when HeldBy clears). It is then consumed and never returns to the locker. Anywhere else it is just
-- set down. Bought from the team bank like every gear (never Robux, never random).
local HttpService=game:GetService('HttpService')
local graphMap,graphRooms=nil,{} -- the decoded GeneratedGraph rooms of the current map
local function roomAt(pos) -- the generated room whose rectangle holds pos (nil in the van / courtyard)
 local map=missionMap();local graph=map and map:FindFirstChild('GeneratedGraph');if not graph then return nil end
 if graphMap~=map then
  local ok,g=pcall(function()return HttpService:JSONDecode(graph.Value)end)
  graphMap=map;graphRooms=ok and type(g)=='table'and g.rooms or {}
 end
 for _,v in graphRooms do
  local floorY=(v.level or 0)*16
  if v.x1 and pos.X>v.x1 and pos.X<v.x2 and pos.Z>v.z1 and pos.Z<v.z2 and pos.Y>floorY-1 and pos.Y<floorY+8 then return v end
 end
 return nil
end
local function floorBelow(pos,ignore)
 local params=RaycastParams.new();params.FilterType=Enum.RaycastFilterType.Exclude;params.RespectCanCollide=true
 local ig={ignore};local creatures=workspace:FindFirstChild('RoamingCreatures');if creatures then ig[#ig+1]=creatures end
 for _,q in Players:GetPlayers()do if q.Character then ig[#ig+1]=q.Character end end;params.FilterDescendantsInstances=ig
 local hit=workspace:Raycast(pos+Vector3.new(0,1,0),Vector3.new(0,-10,0),params)
 return hit and hit.Normal.Y>.7 and hit.Position or nil
end
local function placedClone(id,name) -- an inert, anchored copy of the gear template + its bottom offset from the pivot
 local template=SS.CursedItemKit:FindFirstChild(id);if not template or not template.PrimaryPart then return nil,0 end
 local m=template:Clone();m.Name=name
 for k in m:GetAttributes()do m:SetAttribute(k,nil)end
 local pivot=m:GetPivot();local bottom=math.huge
 for _,part in m:GetDescendants()do if part:IsA('BasePart')then
  if part.Transparency<.95 then bottom=math.min(bottom,pivot:PointToObjectSpace(part.Position).Y-part.Size.Y*.5)end
  part.Anchored=true;part.CanCollide=false;part.CanTouch=false;part.CanQuery=false
 end end
 return m,(bottom==math.huge and 0 or bottom)
end
local function placerOf(m)local uid=m:GetAttribute('LastOwner');return uid and Players:GetPlayerByUserId(uid)or nil end
local function levelLive()local map=missionMap();local ph=phase();return map~=nil and map:GetAttribute('RuntimeReady')==true and(ph=='Searching'or ph=='Returning')end
local function puff(at,color,count)
 local a=Instance.new('Attachment');a.WorldPosition=at;a.Parent=workspace.Terrain
 local pe=Instance.new('ParticleEmitter');pe.Texture='rbxasset://textures/particles/sparkles_main.dds';pe.Color=ColorSequence.new(color,Color3.new(1,1,1))
 pe.Speed=NumberRange.new(4,8);pe.SpreadAngle=Vector2.new(180,180);pe.Lifetime=NumberRange.new(.4,.8);pe.Size=NumberSequence.new(.6,0);pe.LightEmission=1;pe.Rate=0;pe.Parent=a
 pe:Emit(count or 30);Debris:AddItem(a,1.5)
end
local function tagOn(part,text,color,maxDistance,onTop) -- the small floating label the placed gear wears
 local bb=Instance.new('BillboardGui');bb.Name='UtilityGearTag';bb.Size=UDim2.fromOffset(130,30);bb.StudsOffsetWorldSpace=Vector3.new(0,2.2,0);bb.MaxDistance=maxDistance or 60;bb.LightInfluence=0;bb.AlwaysOnTop=onTop==true;bb.Parent=part
 local tl=Instance.new('TextLabel');tl.Size=UDim2.fromScale(1,1);tl.BackgroundTransparency=1;tl.Font=Enum.Font.FredokaOne;tl.TextScaled=true;tl.TextColor3=color;tl.Text=text;tl.Parent=bb
 local st=Instance.new('UIStroke');st.Thickness=1.5;st.Transparency=.3;st.Parent=tl
 return tl,bb
end
-- The funny beat (owner 2026-10-27): a face every player sees (VoiceMouthClient: grin / gasp / pucker) and a popping
-- word on this player's screen (CloseUpChoiceClient: 'WORD|style'). The same attributes as the close-up choices.
local function beat(p,face,seconds,word,style)
 if not p or not p.Parent then return end
 local t=workspace:GetServerTimeNow()
 if face then p:SetAttribute('FaceBeat',face);p:SetAttribute('FaceBeatUntil',t+seconds)end
 if word then p:SetAttribute('ScreenBeat',word..'|'..(style or'plain'));p:SetAttribute('ScreenBeatAt',t)end
end
local function lure(pos,radius,seconds) -- CreatureRoamServer hears LurePosition as an object noise (a NEW position each time)
 local at=pos+Vector3.new(math.random()-.5,0,math.random()-.5)*.6
 for _,mon in monsters()do local r=monsterRoot(mon)
  if r and(r.Position-pos).Magnitude<=radius then mon:SetAttribute('LurePosition',at);mon:SetAttribute('LureUntil',os.clock()+seconds)end
 end
end
local PLACED={} -- item id -> function(p, m, pos): true when it took effect (the held item is then consumed)
onGearSet=function(m,id)
 local handler=PLACED[id];if not handler then return end
 task.delay(.6,function() -- let it land (and RecoveryRoundServer's basket catch run)
  if not m.Parent or m:GetAttribute('HeldBy')or m:GetAttribute('MonsterCarried')or not levelLive()then return end
  local rec=records[m];if not rec or rec.consumed or not m.PrimaryPart then return end
  if handler(placerOf(m),m,m.PrimaryPart.Position)then consume(nil,m)end
 end)
end
-- Playtest hook (server only): a tracked copy of a shop gear item, as if bought: GearShopApi:Invoke('grant', id, cframe).
grantGear=function(id,cf)
 local entry=BY_ID[id]
 if not entry or typeof(cf)~='CFrame'then return nil end
 return spawnGear(id,cf,entry.charges)
end

-- Chirpy Decoy: set down inside a room, it winds up, then waddles and chirps for 20 s. Every pulse is a lure for every
-- monster in range (CreatureRoamServer hears LurePosition as an object noise); one that reaches it stands confused.
local DECOY_WIND,DECOY_SECONDS,DECOY_PULSE,DECOY_RADIUS,DECOY_CONFUSE,DECOY_REACH=1.2,20,2,90,1.5,5
local function runDecoy(p,at)
 local map=missionMap();local decoy,bottom=placedClone('ChirpyDecoy','ArmedChirpyDecoy');if not map or not decoy then return false end
 local base=CFrame.new(at+Vector3.new(0,.03-bottom,0))*CFrame.Angles(0,math.random()*math.pi*2,0)
 decoy:PivotTo(base);decoy.Parent=map
 local tl=tagOn(decoy.PrimaryPart,'*wind wind*',Color3.fromRGB(255,232,120),70)
 Audio.Play('ClockTick',decoy.PrimaryPart)
 task.spawn(function()
  -- wind-up: it shivers on the spot while the key turns
  local w0=os.clock()
  while decoy.Parent and os.clock()-w0<DECOY_WIND do
   decoy:PivotTo(base*CFrame.new(math.noise(os.clock()*30,1)*.05,0,math.noise(os.clock()*30,2)*.05));task.wait(.05)
  end
  local start=os.clock();local nextPulse=0;local confused={}
  while decoy.Parent and missionMap()==map and os.clock()-start<DECOY_SECONDS do
   local ph=phase();if ph=='Deploying'or ph=='Won'or ph=='Failed'then break end
   local t=os.clock()-start
   -- waddle: a small circle with a hop on every step, always facing the way it walks
   local spot=base*CFrame.Angles(0,t*2.4,0)*CFrame.new(0,0,-.6)
   decoy:PivotTo(spot*CFrame.new(0,math.abs(math.sin(t*14))*.18,0)*CFrame.Angles(0,-math.pi/2,0)*CFrame.Angles(0,0,math.sin(t*14)*.12))
   local pos=decoy.PrimaryPart.Position
   if os.clock()>=nextPulse then
    nextPulse=os.clock()+DECOY_PULSE
    Audio.Play('DecoyChirp',decoy.PrimaryPart);puff(pos+Vector3.new(0,.8,0),Color3.fromRGB(255,232,120),8)
    tl.Text=('CHIRP!  %d'):format(math.ceil(DECOY_SECONDS-t))
    local evidence=SS:FindFirstChild('MonsterEvidence');if evidence then evidence:Fire(pos,60,'Decoy',decoy)end
    lure(pos,DECOY_RADIUS,DECOY_PULSE+1)
   end
   for _,mon in monsters()do local r=monsterRoot(mon)
    if r and not confused[mon]and(r.Position-pos).Magnitude<DECOY_REACH then
     confused[mon]=true;mon:SetAttribute('StunnedUntil',os.clock()+DECOY_CONFUSE) -- it found a toy, not a player
     local q=Instance.new('BillboardGui');q.Name='DecoyConfused';q.Size=UDim2.fromOffset(60,60);q.StudsOffsetWorldSpace=Vector3.new(0,4,0);q.MaxDistance=80;q.LightInfluence=0;q.Parent=r
     local ql=Instance.new('TextLabel');ql.Size=UDim2.fromScale(1,1);ql.BackgroundTransparency=1;ql.Font=Enum.Font.FredokaOne;ql.TextScaled=true;ql.TextColor3=Color3.fromRGB(255,232,120);ql.Text='?';ql.Parent=q
     Debris:AddItem(q,DECOY_CONFUSE+.5)
    end
   end
   task.wait(.05)
  end
  if decoy.Parent then puff(decoy.PrimaryPart.Position,Color3.fromRGB(255,226,90));Audio.Play('ItemRattle',decoy.PrimaryPart);decoy:Destroy()end
  if p and p.Parent then toast(p,'Your Chirpy Decoy wound down.')end
 end)
 return true
end
PLACED.ChirpyDecoy=function(p,m,pos)
 if not roomAt(pos)then return false end -- the van / courtyard: just set down
 local at=floorBelow(pos,m);if not at then return false end
 if not runDecoy(p,at)then return false end
 beat(p,'grin',2.5,'CHIRP CHIRP!','gold')
 toastAll(('%s set down a Chirpy Decoy. Monsters nearby will go to it for %d seconds.'):format(p and p.DisplayName or 'Someone',DECOY_SECONDS))
 return true
end

-- Door Wedge: let go of it next to a closed door. The door holds against monsters for WEDGE_SECONDS (InteractServer's
-- MonsterDoorApi refuses it, CreatureRoamServer routes around it) until WEDGE_BUMPS bashes or anyone opens it.
local WEDGE_SECONDS,WEDGE_REACH,WEDGE_BUMPS,WEDGE_BUMP_GAP=45,5,8,1
local wedged=setmetatable({},{__mode='k'}) -- door model -> {prop, bumps, lastBump, conns, by}
local function doorSlab(d)local s=d:FindFirstChild('Slab');return s and s:IsA('BasePart')and s or nil end
local function doorNear(pos)
 local map=missionMap();local inter=map and map:FindFirstChild('Interactive');if not inter then return nil end
 local best,dist
 for _,d in inter:GetChildren()do
  if d:IsA('Model')and d:GetAttribute('Kind')=='door'and not d:GetAttribute('Closet')then
   local closed=d:GetAttribute('ClosedPivot');local slab=doorSlab(d)
   local at=slab and slab.Position or(typeof(closed)=='CFrame'and closed.Position)
   if at then
    local dl=at-pos;local flat=Vector3.new(dl.X,0,dl.Z).Magnitude
    if flat<=WEDGE_REACH and math.abs(dl.Y)<10 and(not dist or flat<dist)then best,dist=d,flat end
   end
  end
 end
 return best
end
local function unwedge(door,why)
 local w=wedged[door];if not w then return end;wedged[door]=nil
 for _,c in w.conns do c:Disconnect()end
 if door.Parent then door:SetAttribute('WedgedUntil',nil);door:SetAttribute('WedgeBumps',nil)end
 if w.prop.Parent then puff(w.prop.PrimaryPart.Position,Color3.fromRGB(170,230,90));Audio.Play('MetalImpact',w.prop.PrimaryPart);w.prop:Destroy()end
 if why then toastAll(why)elseif w.by and w.by.Parent then toast(w.by,'Your door wedge slipped out.')end
end
local function wedgeDoor(p,door,at)
 if wedged[door]then if p then toast(p,'That door is already wedged.')end;return false end
 if door:GetAttribute('Locked')then if p then toast(p,'That door is locked already. Save the wedge.')end;return false end
 if(door:GetAttribute('Open')or 0)>.05 then if p then toast(p,'Close the door first, then set the wedge by it.')end;return false end
 local prop,bottom=placedClone('DoorWedge','PlacedDoorWedge');if not prop then return false end
 -- Snap flat against the door on the side it was dropped, thin edge toward the door, slid along the door at most 1.5 studs.
 local slab=doorSlab(door);local closed=door:GetAttribute('ClosedPivot')
 local doorPos=slab and slab.Position or(typeof(closed)=='CFrame'and closed.Position or at)
 local n=slab and(slab.Size.X<slab.Size.Z and slab.CFrame.RightVector or slab.CFrame.LookVector)or Vector3.new(0,0,1)
 n=Vector3.new(n.X,0,n.Z);n=n.Magnitude>.01 and n.Unit or Vector3.new(0,0,1)
 local along=Vector3.new(-n.Z,0,n.X);local rel=Vector3.new(at.X-doorPos.X,0,at.Z-doorPos.Z)
 local side=rel:Dot(n)>=0 and 1 or -1;local thick=slab and math.min(slab.Size.X,slab.Size.Z)or .4
 local spot=Vector3.new(doorPos.X,at.Y,doorPos.Z)+n*side*(thick/2+1.05)+along*math.clamp(rel:Dot(along),-1.5,1.5)
 local floor=floorBelow(spot,prop)or Vector3.new(spot.X,at.Y,spot.Z)
 prop:PivotTo(CFrame.lookAt(floor,floor-n*side)+Vector3.new(0,.02-bottom,0))
 prop.Parent=missionMap()
 local untilT=workspace:GetServerTimeNow()+WEDGE_SECONDS
 door:SetAttribute('WedgedUntil',untilT);door:SetAttribute('WedgeBumps',0)
 Audio.Play('Unlock',prop.PrimaryPart);puff(prop.PrimaryPart.Position,Color3.fromRGB(170,235,110),16)
 local tl=tagOn(prop.PrimaryPart,('WEDGED  %d'):format(WEDGE_SECONDS),Color3.fromRGB(170,235,110),50)
 local w={prop=prop,bumps=0,lastBump=0,conns={},by=p};wedged[door]=w
 table.insert(w.conns,door:GetAttributeChangedSignal('Open'):Connect(function()
  if(door:GetAttribute('Open')or 0)>.05 then unwedge(door,'The door was opened: the wedge popped out.')end
 end))
 table.insert(w.conns,door:GetAttributeChangedSignal('WedgeBumpAt'):Connect(function()
  local now=os.clock();if now-w.lastBump<WEDGE_BUMP_GAP then return end;w.lastBump=now
  w.bumps+=1;door:SetAttribute('WedgeBumps',w.bumps);Audio.Play('LockedAttempt',door)
  if w.prop.Parent then puff(w.prop.PrimaryPart.Position+Vector3.new(0,.6,0),Color3.fromRGB(200,200,210),6)end -- dust off the door
  if w.bumps>=WEDGE_BUMPS then unwedge(door,'A monster broke through a wedged door!')end
 end))
 task.spawn(function()
  while wedged[door]==w and door.Parent and w.prop.Parent do
   local left=untilT-workspace:GetServerTimeNow()
   if left<=0 then unwedge(door);return end
   tl.Text=('WEDGED  %d'):format(math.ceil(left))..(w.bumps>0 and('  '..string.rep('|',WEDGE_BUMPS-w.bumps))or'')
   task.wait(.25)
  end
  if wedged[door]==w then unwedge(door)end -- door or wedge gone (map rebuilt)
 end)
 return true
end
PLACED.DoorWedge=function(p,m,pos)
 local door=doorNear(pos)
 if not door then if roomAt(pos)and p then toast(p,'Set the wedge down right next to a closed door.')end;return false end
 if not wedgeDoor(p,door,floorBelow(pos,m)or pos)then return false end
 beat(p,'grin',2,'WEDGED!','plain')
 toastAll(('%s wedged a door shut for %d seconds.'):format(p and p.DisplayName or 'Someone',WEDGE_SECONDS))
 return true
end

-- The cart helpers shared by the Cart Beacon and the Cart Bell.
local function cartOf()local map=missionMap();local i=map and map:FindFirstChild('Interactive');return i and i:FindFirstChild('RecoveryCart')end
local function basketOf(cart) -- the same frame RecoveryRoundServer's basketFrame() uses
 local s=cart:GetScale()
 return cart.PrimaryPart.CFrame*CFrame.new((cart:GetAttribute('BasketOffset')or Vector3.zero)*s),(cart:GetAttribute('BasketSize')or Vector3.new(4,2,6))*s
end
local function inBasket(cart,pos)
 if not cart.PrimaryPart then return false end
 local cf,size=basketOf(cart);local q=cf:PointToObjectSpace(pos)
 return math.abs(q.X)<size.X/2+.4 and math.abs(q.Z)<size.Z/2+.4 and q.Y>-size.Y/2-.3 and q.Y<size.Y/2+1.5
end
local function weldToCart(prop,cart,name)
 local root=cart.PrimaryPart
 for _,part in prop:GetDescendants()do if part:IsA('BasePart')then
  part.Anchored=false;part.Massless=true;part.CanCollide=false;part.CanQuery=false;part.CanTouch=false;part.CollisionGroup='RecoveryCart'
  local w=Instance.new('WeldConstraint');w.Name=name;w.Part0=root;w.Part1=part;w.Parent=part
 end end
 prop.Parent=cart -- a cart child: RecoveryRoundServer's clientOwnsCart hands it to the pusher with the rest of the cart
end

-- Cart Beacon: let go of it in the cart basket and it clamps onto the right rail: a pulsing cyan light, and every
-- teammate's TutorialClient draws a CART tag through walls while the cart has BeaconFitted. Gone with the cart each level.
local BEACON_RANGE,BEACON_BRIGHTNESS,BEACON_COLOR=24,1.6,Color3.fromRGB(120,230,255)
local function fitBeacon(p,cart)
 if cart:GetAttribute('BeaconFitted')then if p then toast(p,'The cart already has a beacon.')end;return false end
 local prop,bottom=placedClone('CartBeacon','FittedCartBeacon');if not prop then return false end
 local cf,size=basketOf(cart)
 -- Right side rail, front (handle) corner: the clamp's open side faces into the basket, the lamp stands above the rail.
 prop:PivotTo(cf*CFrame.new(size.X/2+.05,size.Y/2-.4-bottom,-size.Z/2+.45)*CFrame.Angles(0,math.pi/2,0))
 weldToCart(prop,cart,'BeaconWeld')
 local lamp=prop:FindFirstChild('CartBeacon_neon',true)or prop.PrimaryPart
 local light=Instance.new('PointLight');light.Name='BeaconLight';light.Color=BEACON_COLOR;light.Brightness=BEACON_BRIGHTNESS;light.Range=BEACON_RANGE;light.Shadows=false;light.Parent=lamp
 pcall(function()cart.ModelStreamingMode=Enum.ModelStreamingMode.Persistent end) -- every teammate's CART tag needs it streamed in
 cart:SetAttribute('BeaconFitted',true);cart:SetAttribute('BeaconBy',p and p.DisplayName or nil)
 Audio.Play('Unlock',cart.PrimaryPart);Audio.Play('FlashlightClick',lamp);puff(lamp.Position,BEACON_COLOR,24)
 task.spawn(function()local t=0;while light.Parent do t+=.1;light.Brightness=BEACON_BRIGHTNESS*(.875+.125*math.sin(t*3));task.wait(.1)end end)
 return true
end
PLACED.CartBeacon=function(p,m,pos)
 local cart=cartOf()
 if not cart or not inBasket(cart,pos)then if roomAt(pos)and p then toast(p,'Drop it into the cart to clip it on.')end;return false end
 if not fitBeacon(p,cart)then return false end
 beat(p,'grin',2,'BEACON ON!','frost')
 toastAll(('%s clipped a beacon on the cart. Everyone can see the cart now.'):format(p and p.DisplayName or 'Someone'))
 return true
end

-- Cart Bell (owner 2026-10-27: "make the monsters angry and come to it, but they can't take anything from the cart;
-- make it sit right on the handle"). Let go of it in the cart basket and it clamps onto the push handle for the rest
-- of the level. The deal: RecoveryRoundServer.monsterTake never hands a monster an item from a belled cart (no ring
-- limit), but the bell rings every BELL_RING_EVERY seconds and every ring calls the monsters to the cart. A monster
-- that reaches in anyway gets NOTHING: brring-brring, it flinches, roars, and the ring calls more of them over.
local BELL_RING_EVERY,BELL_LURE_RADIUS,BELL_LURE_SECONDS,BELL_LOUD=30,150,4,70
local BELL_FLINCH,BELL_FLINCH_REACH,BELL_ALARM_GAP,BELL_TAG_SECONDS=1.2,16,4,3
local BELL_BAR_DROP=.276 -- the model's clamp bar sits this far below its centre pivot: this seats the bar on the handle
local function bellTag(dome,text)
 local old=dome:FindFirstChild('CartBellTag');if old then old:Destroy()end
 local bb=Instance.new('BillboardGui');bb.Name='CartBellTag';bb.AlwaysOnTop=true;bb.LightInfluence=0;bb.MaxDistance=400
 bb.Size=UDim2.fromOffset(150,44);bb.StudsOffsetWorldSpace=Vector3.new(0,3,0);bb.Parent=dome
 local tl=Instance.new('TextLabel');tl.Size=UDim2.fromScale(1,1);tl.BackgroundTransparency=1;tl.Font=Enum.Font.FredokaOne;tl.TextScaled=true
 tl.TextColor3=Color3.fromRGB(255,214,90);tl.Text=text;tl.Parent=bb
 local st=Instance.new('UIStroke');st.Thickness=2;st.Color=Color3.fromRGB(40,30,10);st.Parent=tl
 Debris:AddItem(bb,BELL_TAG_SECONDS)
end
local function ringBell(cart,prop,angry)
 if not cart.Parent or not cart.PrimaryPart or not prop.Parent then return end
 local pos=cart.PrimaryPart.Position;local dome=prop.PrimaryPart or prop:FindFirstChildWhichIsA('BasePart',true);if not dome then return end
 Audio.Play('CartBellRing',dome);task.delay(.4,function()if dome.Parent then Audio.Play('CartBellRing',dome)end end) -- brring-brring
 puff(dome.Position+Vector3.new(0,.5,0),Color3.fromRGB(255,214,90),14)
 cart:SetAttribute('BellRings',(cart:GetAttribute('BellRings')or 0)+1)
 local evidence=SS:FindFirstChild('MonsterEvidence');if evidence then evidence:Fire(pos,BELL_LOUD,'cart bell',cart)end
 lure(pos,BELL_LURE_RADIUS,BELL_LURE_SECONDS)
 if angry then
  bellTag(dome,'BRRING!\nHANDS OFF!')
  for _,mon in monsters()do local r=monsterRoot(mon)
   if r and(r.Position-pos).Magnitude<BELL_FLINCH_REACH then mon:SetAttribute('StunnedUntil',os.clock()+BELL_FLINCH);Audio.Play('MonsterNotice',r)end -- empty-handed and cross
  end
  for _,q in Players:GetPlayers()do
   local ok,r=alive(q);if ok and(r.Position-pos).Magnitude<60 then beat(q,'gasp',1.2,'BRRING BRRING!','shake')end
  end
  local now=os.clock()
  if now-(cart:GetAttribute('BellToastAt')or -99)>10 then cart:SetAttribute('BellToastAt',now)
   toastAll('A monster reached into the cart... the bell rang and it got NOTHING! More are coming to look.')end
 else
  bellTag(dome,'BRRING!')
 end
end
local function fitBell(p,cart)
 if cart:GetAttribute('BellFitted')then if p then toast(p,'The cart already has a bell.')end;return false end
 local handle=cart:FindFirstChild('Handle');if not handle or not cart.PrimaryPart then return false end
 local prop=placedClone('CartBell','FittedCartBell');if not prop then return false end
 -- Right on the push handle, right of centre, dome up, lever toward the pusher: its clamp bar wraps the handle bar.
 prop:PivotTo(handle.CFrame*CFrame.new(handle.Size.X*.28,BELL_BAR_DROP,0))
 weldToCart(prop,cart,'BellWeld')
 cart:SetAttribute('BellFitted',true);cart:SetAttribute('BellRings',0);cart:SetAttribute('BellBy',p and p.DisplayName or nil)
 local lastAlarm=0
 cart:GetAttributeChangedSignal('BellRangAt'):Connect(function() -- a refused theft (RecoveryRoundServer.monsterTake)
  local now=os.clock();if now-lastAlarm<BELL_ALARM_GAP then return end;lastAlarm=now
  ringBell(cart,prop,true)
 end)
 task.spawn(function() -- the price: it rings by itself every BELL_RING_EVERY seconds while the level runs
  local nextRing=os.clock()+BELL_RING_EVERY
  while cart.Parent and prop.Parent do
   if os.clock()>=nextRing then
    nextRing=os.clock()+BELL_RING_EVERY
    if levelLive()and not(van()and(van():GetPivot().Position-cart.PrimaryPart.Position).Magnitude<30)then ringBell(cart,prop,false)end
   end
   task.wait(.5)
  end
 end)
 Audio.Play('Unlock',cart.PrimaryPart);Audio.Play('CartBellRing',prop.PrimaryPart or cart.PrimaryPart) -- the clamp bites, one test ding
 return true
end
PLACED.CartBell=function(p,m,pos)
 local cart=cartOf()
 if not cart or not inBasket(cart,pos)then if roomAt(pos)and p then toast(p,'Drop it into the cart to clip it on.')end;return false end
 if not fitBell(p,cart)then return false end
 beat(p,'grin',2,'BRRING!','gold')
 toastAll(('%s clipped a bell on the cart handle: monsters can never steal from the cart this level, but it rings every %d seconds and they come to look!'):format(p and p.DisplayName or'Someone',BELL_RING_EVERY))
 return true
end

local use=SS:FindFirstChild('GearUseApi')or Instance.new('BindableFunction');use.Name='GearUseApi';use.Parent=SS
use.OnInvoke=function(p,m)
 local ok,r=alive(p);if not ok or not m or not m.Parent then return end
 local id=m:GetAttribute('ItemId');local entry=BY_ID[id];if not entry then return end
 if id=='MedKit'or id=='BigMedKit'then
  if m:GetAttribute('HeldBy')~=p.UserId or m:GetAttribute('MedKitUsed')then return false end
  local h=p.Character and p.Character:FindFirstChildOfClass('Humanoid');if not h or h.Health<=0 then return false end
  if h.Health>=h.MaxHealth then toast(p,'You are already at full health. Keep it for later.');return false end
  m:SetAttribute('MedKitUsed',true)
  local healed=require(game:GetService('ServerScriptService'):WaitForChild('PlayerHealth')).Heal(p,id=='BigMedKit'and 100 or 50,'gear:'..id)
  consume(p,m);toast(p,('Healed %d health.'):format(math.floor(healed+.5)));return true
 elseif id=='Grenade'then
  local origin,dir=aimOf(p,r)
  local start=(m.PrimaryPart and m.PrimaryPart.Position)or origin
  consume(p,m)
  local ball=Instance.new('Part');ball.Shape=Enum.PartType.Ball;ball.Size=Vector3.one*.6;ball.Color=Color3.fromRGB(78,92,52);ball.Anchored=true;ball.CanCollide=false;ball.CanQuery=false;ball.Position=start;ball.Parent=workspace
  local vel=dir*48+Vector3.new(0,14,0);local pos=start
  local params=RaycastParams.new();params.FilterType=Enum.RaycastFilterType.Exclude;local ig={ball};for _,q in Players:GetPlayers()do if q.Character then table.insert(ig,q.Character)end end;params.FilterDescendantsInstances=ig
  local landed=false
  for _=1,120 do
   local dt=1/30;local nextPos=pos+vel*dt;vel+=Vector3.new(0,-workspace.Gravity*.6,0)*dt
   local hit=workspace:Raycast(pos,nextPos-pos,params)
   if hit then pos=hit.Position+hit.Normal*.3;ball.Position=pos;landed=true;break end
   pos=nextPos;ball.Position=pos;task.wait(dt)
  end
  sound(9113438364,ball,.6)
  task.wait(landed and 1.2 or 0)
  ball:Destroy();explode(pos,GRENADE_DAMAGE,p)
 elseif id=='ProxMine'then
  local look=Vector3.new(r.CFrame.LookVector.X,0,r.CFrame.LookVector.Z);look=look.Magnitude>.01 and look.Unit or Vector3.new(0,0,-1)
  local params=RaycastParams.new();params.FilterType=Enum.RaycastFilterType.Exclude;local ig={m};for _,q in Players:GetPlayers()do if q.Character then table.insert(ig,q.Character)end end;params.FilterDescendantsInstances=ig
  local hit=workspace:Raycast(r.Position+look*2.5+Vector3.new(0,1,0),Vector3.new(0,-12,0),params)
  if not hit then toast(p,'Find solid floor to set the proximity grenade.');return end
  consume(p,m);armMine(hit.Position);toast(p,'Proximity grenade armed. It goes off when a monster steps on it.')
 elseif id=='SkitterTrap'then
  if m:GetAttribute('TrapDeploying')then return end
  if m:GetAttribute('HeldBy')~=p.UserId then return end
  m:SetAttribute('TrapDeploying',true)
  local look=Vector3.new(r.CFrame.LookVector.X,0,r.CFrame.LookVector.Z);look=look.Magnitude>.01 and look.Unit or Vector3.new(0,0,-1)
  local params=RaycastParams.new();params.FilterType=Enum.RaycastFilterType.Exclude;params.RespectCanCollide=true;local ig={m}
  local creatures=workspace:FindFirstChild('RoamingCreatures');if creatures then ig[#ig+1]=creatures end
  for _,q in Players:GetPlayers()do if q.Character then ig[#ig+1]=q.Character end end;params.FilterDescendantsInstances=ig
  local hit=workspace:Raycast(r.Position+look*3.5+Vector3.new(0,1,0),Vector3.new(0,-8,0),params)
  local map=missionMap();local room
  if hit and map and hit.Normal.Y>.9 then
   for _,v in game.HttpService:JSONDecode(map.GeneratedGraph.Value).rooms do if hit.Position.X>v.x1+1 and hit.Position.X<v.x2-1 and hit.Position.Z>v.z1+1 and hit.Position.Z<v.z2-1 and math.abs(hit.Position.Y-v.level*16)<.25 then room=v;break end end
  end
  if room then
   local head=p.Character:FindFirstChild('Head')or r
   if workspace:Raycast(head.Position,hit.Position+Vector3.new(0,.15,0)-head.Position,params)then room=nil end
   local template=SS.CursedItemKit:FindFirstChild('SkitterTrap')
   if not template then room=nil else
    local _,size=template:GetBoundingBox();local overlap=OverlapParams.new();overlap.FilterType=Enum.RaycastFilterType.Exclude;overlap.FilterDescendantsInstances={m};overlap.RespectCanCollide=false
    for _,part in workspace:GetPartBoundsInBox(CFrame.new(hit.Position+Vector3.new(0,size.Y*.5+.08,0)),Vector3.new(size.X+.1,size.Y,size.Z+.1),overlap)do
     if part.CanCollide or part:IsDescendantOf(p.Character)then room=nil;break end
    end
   end
  end
  local trap=room and armSkitterTrap(hit.Position)
  if not trap then m:SetAttribute('TrapDeploying',nil);toast(p,'Find a clear floor inside the map to set the Skitter Trap.');return end
  consume(p,m);toast(p,'Skitter Trap armed. Only a grounded Skitter can trigger it.')
 elseif id=='HypnoGun'then
  -- Misses are free, so shots are rate-limited per player.
  local nowT=os.clock();if nowT<(p:GetAttribute('HypnoReadyAt')or 0)then return end;p:SetAttribute('HypnoReadyAt',nowT+1.2)
  -- Wide, glowing spiral shot with the same generous aim assist as the Monster Slayer.
  local target,_,muzzle=shoot(p,r,m,Color3.fromRGB(255,60,190),5,.4)
  -- Shooter gets one immediate 2D cue; nearby players get the positional muzzle cue.
  Audio.ToPlayer(p,'HypnoShotLocal')
  for _,listener in Players:GetPlayers()do if listener~=p then RS.GameplaySoundEvent:FireClient(listener,'HypnoShot',muzzle)end end
  if target and weapon('hypnotize',target,HYPNO_SECONDS)then
   target:SetAttribute('FleeUntil',os.clock()+4) -- staggers away from whoever is near first, then wanders dazed
   local mr=monsterRoot(target)
   if mr then
    Audio.Play('HypnoHit',mr)
    local fx=Instance.new('Folder');fx.Name='HypnoFX';fx.Parent=mr
    -- Swirling sparkles + a pulsing pink glow everyone can see.
    local att=Instance.new('Attachment');att.Name='HypnoSwirl';att.Position=Vector3.new(0,3,0);att.Parent=mr
    local pe=Instance.new('ParticleEmitter');pe.Texture='rbxasset://textures/particles/sparkles_main.dds';pe.Color=ColorSequence.new(Color3.fromRGB(255,60,190),Color3.fromRGB(120,255,230))
    pe.Rate=60;pe.Lifetime=NumberRange.new(.8,1.4);pe.Speed=NumberRange.new(2,4);pe.RotSpeed=NumberRange.new(180,360);pe.SpreadAngle=Vector2.new(180,180);pe.Size=NumberSequence.new(1,0);pe.LightEmission=1;pe.Parent=att
    local glow=Instance.new('PointLight');glow.Color=Color3.fromRGB(255,80,200);glow.Brightness=3;glow.Range=16;glow.Parent=att
    -- Spinning hypno rings over its head.
    local rings={}
    for i=1,2 do
     local ring=Instance.new('Part');ring.Name='HypnoRing';ring.Shape=Enum.PartType.Cylinder;ring.Size=Vector3.new(.12,3.4-i*.9,3.4-i*.9);ring.Material=Enum.Material.Neon
     ring.Color=i==1 and Color3.fromRGB(255,60,190)or Color3.fromRGB(120,255,230);ring.Transparency=.35;ring.CanCollide=false;ring.CanQuery=false;ring.CanTouch=false;ring.Massless=true;ring.Anchored=true;ring:SetAttribute('GearIgnoreHit',true);ring.Parent=fx
     table.insert(rings,ring)
    end
    -- Floating countdown everyone can read.
    local bb=Instance.new('BillboardGui');bb.Name='HypnoTag';bb.Size=UDim2.fromOffset(180,44);bb.StudsOffsetWorldSpace=Vector3.new(0,6.5,0);bb.AlwaysOnTop=true;bb.MaxDistance=120;bb.Parent=mr
    local tl=Instance.new('TextLabel');tl.Size=UDim2.fromScale(1,1);tl.BackgroundTransparency=1;tl.Font=Enum.Font.FredokaOne;tl.TextScaled=true;tl.TextColor3=Color3.fromRGB(255,120,220);tl.TextStrokeTransparency=0;tl.Parent=bb
    local untilT=os.clock()+HYPNO_SECONDS
    task.spawn(function()
     local spin=0
     while mr.Parent and target.Parent and os.clock()<untilT do
      spin+=.12
      local top=mr.CFrame*CFrame.new(0,4.6,0)
      for i,ring in rings do ring.CFrame=CFrame.new(top.Position+Vector3.new(0,(i-1)*.5,0))*CFrame.Angles(0,spin*(i==1 and 1 or -1.6),math.rad(90)) end
      tl.Text='HYPNOTIZED  '..math.ceil(untilT-os.clock())
      glow.Brightness=2.2+math.sin(spin*3)
      task.wait(.03)
     end
     fx:Destroy();att:Destroy();bb:Destroy()
    end)
   end
   toast(p,'Hypnotized! It wanders off dazed for '..HYPNO_SECONDS..' seconds.')
   spendCharge(p,m,entry)
  else
   -- A miss keeps the shot: the gun only spends a charge when it actually hypnotizes something.
   toast(p,'Missed! No shot used. Aim at a monster.')
  end
 elseif id=='SlayerGun'then
  sound(SLAYER_SHOT_SOUND,r,.6)
  local target,at=shoot(p,r,m,Color3.fromRGB(255,40,30),SLAYER_HIT_RADIUS,SLAYER_BEAM_WIDTH)
  if target then
   local e=Instance.new('Explosion');e.Position=at;e.BlastPressure=0;e.BlastRadius=6;e.DestroyJointRadiusPercent=0;e.ExplosionType=Enum.ExplosionType.NoCraters;e.Parent=workspace
   local mr=monsterRoot(target);killMonster(target,mr and mr.Position or at)
  end
  spendCharge(p,m,entry)
 end
end


