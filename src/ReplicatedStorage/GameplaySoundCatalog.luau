local C={}
C.DoorOpen={name="Wood Door Creak Squeak 2 (SFX)",id="rbxassetid://9120839010",volume=.48,speed=1,range=65}
C.DoorClose={name="door-close-wood",id="rbxassetid://111763202035471",volume=.5,speed=1,range=65}
C.DrawerOpen={name="Cabinet Drawer 7 (SFX)",id="rbxassetid://9113658569",volume=.4,speed=1,range=35}
C.DrawerClose={name="Drawer Close",id="rbxassetid://213037068",volume=.35,speed=1,range=35}
C.LockedAttempt={name="Locked door handle pool",id="rbxassetid://9114138854",pool={{id="rbxassetid://9114138854",name="Door Knob Panicky Handling 10 (SFX)"},{id="rbxassetid://9114138747",name="Door Knob Panicky Handling 8 (SFX)"},{id="rbxassetid://9114138313",name="Door Knob Panicky Handling 1 (SFX)"}},volume=.42,speed=1,range=35}
C.Unlock={name="Metal Latches 17 (SFX)",id="rbxassetid://9116725218",volume=0.22,speed=1,range=55}
C.ItemPickup={name="item_pickup",id="rbxassetid://106586585181583",volume=0.16,speed=1,range=55}
C.ItemRelease={name="Item_Drop_Sound_EffectShort",id="rbxassetid://117945572498547",volume=0.16,speed=1,range=55}
C.ItemImpact={name="action_jump_land.mp3",id="rbxasset://sounds/action_jump_land.mp3",volume=0.16,speed=0.8,range=55,duration=0.3}
C.MetalImpact={name="Shopping Cart 2 (SFX)",id="rbxassetid://9119088927",volume=0.18,speed=1,range=55}
C.GlassImpact={name="Glass Clinks 30 (SFX)",id="rbxassetid://9114597147",volume=0.18,speed=1,range=55}
C.ClothHandle={name="Cloth Rustle 5 (SFX)",id="rbxassetid://9113837941",volume=0.13,speed=1,range=55,duration=0.7}
C.CartGrab={name="Shopping Cart 2 (SFX)",id="rbxassetid://9119088927",volume=0.18,speed=1,range=55,duration=0.65}
C.CartRelease={name="Shopping Cart 2 (SFX)",id="rbxassetid://9119088927",volume=0.14,speed=0.85,range=55,duration=0.65}
C.CartRoll={name="Chair ROlling",id="rbxassetid://8409624982",volume=0.1,speed=1,range=55,loop=true}
C.CargoStore={name="Shopping Cart 2 (SFX)",id="rbxassetid://9119088927",volume=0.16,speed=1.1,range=55,duration=0.7}
C.SaleStart={name="Metal Latches 17 (SFX)",id="rbxassetid://9116725218",volume=0.18,speed=1,range=55}
C.SaleComplete={name="Cash Register",id="rbxassetid://134810204798705",volume=0.25,speed=1,range=55}
C.SaleCancelled={name="ui-simple-button-click",id="rbxassetid://88442833509532",volume=0.22,speed=0.6,range=55}
C.RoundStart={name="Cursed jingle",id="rbxassetid://103516326607012",volume=0.18,speed=1,range=55}
C.QuotaMet={name="Shop Bell open",id="rbxassetid://127488139302452",volume=0.25,speed=1,range=55}
C.RoundWin={name="Cursed jingle",id="rbxassetid://103516326607012",volume=0.25,speed=1.15,range=55}
C.TeamWipe={name="Cursed heartbeat",id="rbxassetid://9043365842",volume=0.18,speed=0.65,range=55,duration=2}
C.UiClick={name="ui-simple-button-click",id="rbxassetid://88442833509532",volume=0.17,speed=1,range=55}
C.UiOpen={name="ui-simple-button-click",id="rbxassetid://88442833509532",volume=0.17,speed=0.9,range=55}
C.UiClose={name="ui-simple-button-click",id="rbxassetid://88442833509532",volume=0.14,speed=0.75,range=55}
C.UiError={name="Metal Latches 17 (SFX)",id="rbxassetid://9116725218",volume=0.12,speed=1.35,range=55,duration=0.3}
-- 115959318 (Roblox ClickClack) is not public: live servers got HTTP 401 on every flashlight toggle. Same public latch the client fallback uses.
C.FlashlightClick={name="flashlight_click1",id="rbxassetid://128570293170805",volume=0.6,speed=1,range=55}
C.Spit={name="Spit Sound",id="rbxassetid://1370363170",volume=0.09,speed=1,range=55,duration=0.4}
C.SprintBreath={name="heavy-breathing-sound-effect-type-02-294195",id="rbxassetid://101395573137763",volume=0.085,speed=1,range=55,loop=true}
C.MonsterFootstep={name="Heavy creature footstep pool",id="rbxassetid://9114166629",pool={{id="rbxassetid://9114166629",name="Dragon Footsteps 27 (SFX)"},{id="rbxassetid://9114166413",name="Dragon Footsteps 23 (SFX)"}},volume=.38,speed=1,range=70}
C.MonsterNotice={name="monster-growl",id="rbxassetid://129162115855106",volume=.48,speed=.72,range=95}
C.MonsterRush={name='monster-growl (aggressive rush)',id='rbxassetid://129162115855106',volume=.5,speed=.95,range=90,duration=2}
C.MonsterSearch={name='Creature Mix Weird Deep Monster Breathing 3 (search)',id='rbxassetid://9113984056',volume=.3,speed=.7,range=85,duration=2.5}
C.MonsterIdle={name="Cursed heartbeat",id="rbxassetid://9043365842",volume=0.075,speed=0.65,range=80,duration=1.5}
C.MonsterJumpscare={name='Jumpscare sound effect',id='rbxassetid://109961399514238',volume=.75,speed=1,range=80}
C.MonsterJumpscareHit={name='horror-stinger',id='rbxassetid://104131914354223',volume=.25,speed=1,range=80}
C.ClockTick={name="clock tick",id="rbxassetid://134410911353980",volume=0.055,speed=1,range=55}
C.TelephoneRing={name="telephone-ringing-sound-effect",id="rbxassetid://103163121039185",volume=0.18,speed=1,range=55}
C.DinnerBell={name="Shop Bell open",id="rbxassetid://127488139302452",volume=0.22,speed=1,range=55}
C.PresentOpen={name="Paper Tear Tear Heavy Paper Bag Rustle 4 (SFX)",id="rbxassetid://9117233449",volume=0.2,speed=1,range=55}
C.FrostingSquish={name="Spit Sound",id="rbxassetid://1370363170",volume=0.08,speed=0.7,range=55,duration=0.5}
C.Wash={name="impact_water.mp3",id="rbxasset://sounds/impact_water.mp3",volume=0.2,speed=1,range=55}
C.DollCry={name="Cursed cry",id="rbxassetid://140620656253783",volume=0.2,speed=1.5,range=55,duration=3}
C.ItemRattle={name="Cursed rattle",id="rbxassetid://9125434836",volume=0.15,speed=1,range=55}
C.Heartbeat={name="Cursed heartbeat",id="rbxassetid://9043365842",volume=0.18,speed=0.65,range=55}
C.Whistle={name="Cursed whistle",id="rbxassetid://71437094653533",volume=0.25,speed=1,range=55}
C.PartyHorn={name="Cursed horn",id="rbxassetid://118248543183940",volume=0.2,speed=1,range=55}
C.MusicBox={name="Music Box Lullaby (APM)",id="rbxassetid://9047796475",volume=0.16,speed=1,range=55}
C.VacuumMotor={name="Cursed motor",id="rbxassetid://94990002530647",volume=.12,speed=1,range=55}
C.KeyJingle={name="Cursed jingle",id="rbxassetid://9116176803",volume=0.15,speed=1,range=55}
C.DiscoMusic={name="Check It Out",id="rbxassetid://1835617224",volume=0.12,speed=1,range=55,loop=true}
C.PlayerFootstep={name="Audio_wood-05",id="rbxassetid://130770473999528",volume=.27,speed=1,range=38}
C.PlayerStoneFootstep={name="Concrete Footstep",id="rbxassetid://87061775498714",volume=.25,speed=1,range=38}
C.MonsterAmbience={name="Creature Mix Weird Deep Monster Breathing 3 (SFX)",id="rbxassetid://9113984056",volume=.25,speed=.72,range=85,loop=true}

C.CrawlerBreath={name='Creature Growls Lion 8 (SFX)',id='rbxassetid://9113973128',pool={{id='rbxassetid://9113973128',name='Creature Growls Lion 8 (SFX)'},{id='rbxassetid://9125475729',name='Creature Vocal Spider Growl Belch Hiss Snarl 3 (SFX)'}},volume=.18,speed=.95,range=60}
C.CrawlerNotice={name='Creature Vocal Spider Growl Belch Hiss Snarl 1 (SFX)',id='rbxassetid://9125475724',pool={{id='rbxassetid://9125475724',name='Creature Vocal Spider Growl Belch Hiss Snarl 1 (SFX)'},{id='rbxassetid://9125476001',name='Creature Vocal Spider Growl Belch Hiss Snarl 8 (SFX)'}},volume=.4,speed=.94,range=80}
C.CrawlerRush={name='Creature Mix Giant Crab Monster Roar Growl 1 (SFX)',id='rbxassetid://9113980319',volume=.45,speed=1,range=80}
C.CrawlerSearch=C.CrawlerBreath
C.WraithBreath={name='DISTURBED WHISPERS 06',id='rbxassetid://9043347151',volume=.14,speed=1,range=60}
C.WraithNotice={name='Creature Vocal Pterodactyl Death Shriek 5 (SFX)',id='rbxassetid://9113988323',pool={{id='rbxassetid://9113988323',name='Creature Vocal Pterodactyl Death Shriek 5 (SFX)'},{id='rbxassetid://9113988331',name='Creature Vocal Pterodactyl Death Shriek 3 (SFX)'}},volume=.34,speed=.9,range=80}
C.WraithRush={name='Creature Vocal Pterodactyl Death Shriek 2 (SFX)',id='rbxassetid://9113988191',volume=.42,speed=.94,range=80}
C.WraithSearch=C.WraithBreath

-- Cave stingers (user uploads 2026-10-03), slowed for a creepier, deeper sound.
C.StingCave1={name='Cave sound 1',id='rbxassetid://106314514593607',volume=.5,speed=.62,range=90}
C.StingCave2={name='Cave sound 2',id='rbxassetid://70864591992330',volume=.5,speed=.58,range=90}
C.StingCave3={name='Cave sound 3',id='rbxassetid://138509863809625',volume=.5,speed=.55,range=90}

function C.NoiseCue(label,source)
 local lower=string.lower(label or '')
 if lower=='item set down' or lower=='thrown item' or lower=='gift music' or lower=='haunted piano music' then return nil end
 if lower:find('alarm') then return 'TelephoneRing'
 elseif lower:find('bell') or lower:find('bracelet') then return 'DinnerBell'
 elseif lower:find('present opened') then return 'PresentOpen'
 elseif lower:find('frosting') then return 'FrostingSquish'
 elseif lower:find('cry') or lower:find('scream') then return 'DollCry'
 elseif lower:find('whistle') then return 'Whistle'
 elseif lower:find('heartbeat') then return 'Heartbeat'
 elseif lower:find('music') then return 'MusicBox'
 elseif lower:find('horn') then return 'PartyHorn'
 elseif lower:find('motor') then return 'VacuumMotor'
 elseif lower:find('keys') then return 'KeyJingle'
 elseif lower:find('clown footsteps') then return 'MonsterFootstep'
 elseif lower:find('chewing') then return 'FrostingSquish'
 elseif lower:find('washed') then return 'Wash' end
 return 'ItemRattle'
end

C.CloudRain={name='Light Rain Ambient Sound Effect',id='rbxassetid://18862087062',volume=.13,speed=1,range=30,loop=true}
C.CloudSob={name='Man Crying',id='rbxassetid://688596285',volume=.17,speed=1,range=32,loop=true}
C.CoolEquip={name='Cloth Rustle 5 (SFX)',id='rbxassetid://9113837941',volume=.14,speed=1,range=25,duration=.7}
C.JarPop={name='Glass Bottle Cork Popping',id='rbxassetid://136137302295080',volume=.25,speed=1,range=35,duration=2}
C.FlyBuzz={name='Fly Buzz Irritating 2 (SFX)',id='rbxassetid://9114505206',volume=.11,speed=1,range=24,loop=true}
C.PerfumeSpray={name='Water Hose Gun 3 (SFX)',id='rbxassetid://9120563195',volume=.14,speed=1.1,range=28,duration=.65}
C.PerfumeWhistle={name='Whistle Wolf 5 (SFX)',id='rbxassetid://9120689345',volume=.22,speed=1,range=35,duration=2}
C.PartyEquip={name='Cloth Rustle 5 (SFX)',id='rbxassetid://9113837941',volume=.14,speed=1.15,range=25,duration=.7}
C.PartyBlower={name='Party blowers (29D9C83-MSH)',id='rbxassetid://1631688574',volume=.18,speed=1,range=40,duration=1.5}
C.LevelDrone={name='Low ominous room tone',id='rbxassetid://9113984056',volume=.08,speed=.38,range=100,loop=true}
C.LevelAir={name='Distant air and water ambience',id='rbxasset://sounds/impact_water.mp3',volume=.035,speed=.22,range=100,loop=true}
C.PlayerRunWood={name='Fast wood running steps',id=C.PlayerFootstep.id,volume=.30,speed=1.06,range=42}
C.PlayerRunStone={name='Fast stone running steps',id=C.PlayerStoneFootstep.id,volume=.30,speed=1.08,range=42}
C.MonsterRun={name='Heavy charging footstep pool',id=C.MonsterFootstep.id,pool=C.MonsterFootstep.pool,volume=.36,speed=1.08,range=80}
-- Audio pass (2026-10-01): level ambience beds + random stingers, and item batch 3 cues. All Roblox-licensed (ProSoundEffects / APM / Roblox).
local function pool(name,ids) local t={};for i,id in ipairs(ids)do t[i]={id='rbxassetid://'..id,name=name..' '..i}end;return t end
C.AmbWind={name='Attic Wind Whistley Cold Hollow 2 (SFX)',id='rbxassetid://9113203961',volume=.05,speed=1,range=100,loop=true}
C.AmbCreaks={name='House Creaks 1 (SFX)',id='rbxassetid://9114834184',volume=.04,speed=.9,range=100,loop=true}
C.AmbRain={name='Rain Through Nearly Closed Window 1 (SFX)',id='rbxassetid://9112858540',volume=.035,speed=1,range=100,loop=true}
C.StingCreak={name='Floor creak pool',id='rbxassetid://9125563505',pool=pool('Floor Creaks Wood Floorboard',{9125563505,9125563740,9125563286,9125562923,9125563842,9125563876}),volume=.32,speed=1,range=70}
C.StingKnock={name='Distant knocking pool',id='rbxassetid://9120918417',pool=pool('Wood Knock Wooden Door',{9120918417,9120918534,9120918492}),volume=.26,speed=.9,range=80}
C.StingBumps={name='Apartment Bumps 3 (SFX)',id='rbxassetid://9113135029',volume=.24,speed=.85,range=80}
C.StingThunder={name='Distant thunder pool',id='rbxassetid://9120018172',pool=pool('Thunder Distant Boom',{9120018172,9120018216,9120018050}),volume=.16,speed=1,range=100}
C.StingChoir={name='Heavenly Presence Eerie Choral Tones (SFX)',id='rbxassetid://9125602882',volume=.07,speed=.9,range=100,duration=12}
C.StingHull={name='Spacecraft Hull Buckle 21 (SFX)',id='rbxassetid://9119388187',volume=.2,speed=.8,range=90}
C.BirthdaySong={name='Happy Birthday (Lullaby Music Box)',id='rbxassetid://97102550389175',volume=.8,speed=1,range=120,duration=14}
C.ToiletFlush={name='toilet flush sound effect',id='rbxassetid://116759736098379',volume=1,speed=1,range=110,duration=4}
C.BalloonPop={name='Balloon Pop 3 (SFX)',id='rbxassetid://9113263649',volume=1,speed=1,range=80,duration=.6}
C.HeliumHiss={name='Medium Pressure Air Release 4 (SFX)',id='rbxassetid://9116495977',volume=.22,speed=1.15,range=35,duration=2.2}
C.ClownHonk={name='Bike horn pool',id='rbxassetid://9113438364',pool=pool('Bike Horn Squeeze',{9113438364,9113438365,9113438543}),volume=.35,speed=1,range=50}
C.CameraShutter={name='Roblox GUI - Camera Shutter',id='rbxassetid://17208312548',volume=.45,speed=1,range=40}
C.AnvilClang={name='Metal Pole Impact With Wrench 5 (SFX)',id='rbxassetid://9116768228',volume=.3,speed=.7,range=60}
C.SandSlide={name='Sand Slide 5 (SFX)',id='rbxassetid://9118771237',volume=.14,speed=1.4,range=30,duration=2.5}
C.VampireBreath={name='Cold Breath',id='rbxassetid://1836935290',volume=.25,speed=1,range=40,duration=3.5}
-- Haunted Bellhop (2026-10-01): ProSoundEffects laughs slowed into a hotel-lobby giggle, plus its hand bell.
local bellhopLaughs={{id='rbxassetid://9116239118',name='Laugh Evil Male Various Versions 1 (SFX)'},{id='rbxassetid://9116239313',name='Laugh Evil Male Various Versions 4 (SFX)'},{id='rbxassetid://9116239130',name='Laugh Evil Male Various Versions 2 (SFX)'}}
C.BellhopBreath={name='Bellhop low giggle',id=bellhopLaughs[1].id,pool=bellhopLaughs,volume=.16,speed=.74,range=60}
C.BellhopNotice={name='Bellhop laugh (noticed you)',id=bellhopLaughs[2].id,pool=bellhopLaughs,volume=.42,speed=.92,range=85}
C.BellhopRush={name='Bellhop cackle (rush)',id=bellhopLaughs[3].id,pool=bellhopLaughs,volume=.46,speed=1.12,range=85,duration=2.6}
C.BellhopSearch=C.BellhopBreath
C.BellhopBell={name='Bellhop hand bell',id=C.DinnerBell.id,volume=.34,speed=1,range=70}
C.BellhopStep={name='Bellhop stilt clack',id=C.MonsterFootstep.id,pool=C.MonsterFootstep.pool,volume=.2,speed=1.5,range=60}
-- Lantern Watcher (2026-10-01): insect flutters and whispers, teeth chatter from its chest mouth.
local lanternFlutter={{id='rbxassetid://9113977316',name='Creature Mix Big Flying Insects 4 (SFX)'},{id='rbxassetid://9113979554',name='Creature Mix Big Flying Insects 9 (SFX)'}}
C.LanternBreath={name='DISTURBED WHISPERS 06 (slowed)',id='rbxassetid://9043347151',volume=.15,speed=.8,range=60}
C.LanternNotice={name='Lantern insect flutter (noticed you)',id=lanternFlutter[1].id,pool=lanternFlutter,volume=.45,speed=.72,range=85}
C.LanternRush={name='Creature Vocal Pterodactyl Death Shriek 2 (SFX, low)',id='rbxassetid://9113988191',volume=.4,speed=.72,range=85,duration=2.4}
C.LanternSearch=C.LanternBreath
C.LanternChatter={name='Scrolling Graphic Clicks Small Chattering Metal 6 (SFX)',id='rbxassetid://9125914961',volume=.3,speed=.62,range=55}
C.LanternStep={name='Lantern spike tap',id=C.MonsterFootstep.id,pool=C.MonsterFootstep.pool,volume=.17,speed=1.75,range=55}
C.PlungerPop={name='Glass Bottle Cork Popping (plunger, loud)',id='rbxassetid://136137302295080',volume=1,speed=.72,range=110,duration=2}
C.HairRustle={name='Cloth Rustle 5 (SFX, hair)',id='rbxassetid://9113837941',volume=.55,speed=.78,range=45}
C.MirrorSting={name='horror-stinger (mirror)',id='rbxassetid://104131914354223',volume=.55,speed=1,range=30,duration=3}
-- Neon-Eyed Tripod: the dort.wav drone (NeonAmbient) was removed from the game entirely (owner 2026-10-25).
C.NeonBreath={name='DISTURBED WHISPERS 06 (very slow)',id='rbxassetid://9043347151',volume=.12,speed=.62,range=55}
C.NeonNotice={name='Neon Tripod flutter (noticed you)',id=C.LanternNotice.id,pool=C.LanternNotice.pool,volume=.5,speed=.56,range=90}
C.NeonRush={name='Creature Vocal Pterodactyl Death Shriek 2 (SFX, deep)',id='rbxassetid://9113988191',volume=.45,speed=.6,range=90,duration=2.8}
C.NeonSearch=C.NeonBreath
C.NeonChatter={name='Chattering Metal (Neon jaw)',id='rbxassetid://9125914961',volume=.32,speed=.48,range=55}
C.NeonStep={name='Neon Tripod spike tap',id=C.MonsterFootstep.id,pool=C.MonsterFootstep.pool,volume=.19,speed=1.45,range=60}
-- Distinct Hypno shot: metallic zap with client chorus wobble, separate from flashlight/slayer.
C.HypnoShot={name='Hypno metallic zap',id=C.AnvilClang.id,volume=.9,speed=1.3,range=110,minDistance=12,duration=2}
C.HypnoShotLocal={name='Hypno shooter zap',id=C.AnvilClang.id,volume=.85,speed=1.3,range=110,minDistance=12,duration=2}
C.HypnoHit={name='Hypno impact zap',id=C.JarPop.id,volume=.9,speed=1.1,range=90,minDistance=8,duration=1}

-- Distinct, provenance-verified selected Toolbox partner effects.
C["DraftSelected_SpringyWhisk"]={name="Comic Tube Bounce 4 (SFX)",id="rbxassetid://9113863445",volume=0.5,speed=1.0,minDistance=5,range=45,loop=false}
C["DraftSelected_PoutingSugarBowl"]={name="Slide Whistle 4 (SFX)",id="rbxassetid://9119198140",volume=1.0,speed=1.0,minDistance=5,range=45,loop=false}
C["DraftSelected_RockingSeahorseToy"]={name="Wooden Mechanism Jerks Squeaks 7 (SFX)",id="rbxassetid://9120874322",volume=0.32,speed=1.0,minDistance=5,range=45,loop=false}
C["DraftSelected_OrbitingAtomModel"]={name="Electronic Zing Pass By Swirly Chirps 2 (SFX)",id="rbxassetid://9114292248",volume=0.25,speed=1.0,minDistance=5,range=45,loop=false}
C["DraftSelected_PeekingNestingDoll"]={name="Wood Box Open Close Solid Tight 1 (SFX)",id="rbxassetid://9120798631",volume=0.4,speed=1.0,minDistance=5,range=45,loop=false}
C["DraftSelected_RestlessToyExcavator"]={name="Servo Motor 29 (SFX)",id="rbxassetid://9118927552",volume=0.65,speed=1.0,minDistance=5,range=45,loop=false}
C["DraftSelected_BobbingBirdBath"]={name="Water Drip Water Filled Bucket Constant 21 (SFX)",id="rbxassetid://9120548220",volume=0.42,speed=1.0,minDistance=5,range=45,loop=false}
C["DraftSelected_CrinklyPaperBag"]={name="Newspaper Wadding Into A Ball 16 (SFX)",id="rbxassetid://9117088526",volume=1.8,speed=1.0,minDistance=5,range=45,loop=false}
C["DraftSelected_SleepyMeasuringJug"]={name="Plastic Water Jug Glugs 14 (SFX)",id="rbxassetid://9117644772",volume=0.38,speed=1.0,minDistance=5,range=45,loop=false}
C["DraftSelected_TopsyChessRook"]={name="Marble Table Hit On Wood Portion Thuddy Hits (SFX)",id="rbxassetid://9125654847",volume=0.38,speed=1.0,minDistance=5,range=45,loop=false}
C["DraftSelected_RestlessNutcracker"]={name="Puppet Rattle Miscellaneous Wooden 6 (SFX)",id="rbxassetid://9117975185",volume=0.36,speed=1.0,minDistance=5,range=45,loop=false}
C["DraftSelected_SillySatelliteDish"]={name="Shortwave Bleep Beeps Radio Staticky Telemet (SFX)",id="rbxassetid://9125937530",volume=1.6,speed=1.0,minDistance=5,range=45,loop=false}
C["DraftSelected_FidgetCalculator"]={name="Canon Calculator 5 (SFX)",id="rbxassetid://9113712304",volume=0.38,speed=1.0,minDistance=5,range=45,loop=false}
C["DraftSelected_FoldingTravelStool"]={name="Ratchet Comic 2 (SFX)",id="rbxassetid://9118043348",volume=0.3,speed=1.0,minDistance=5,range=45,loop=false}
C["DraftSelected_TumblingDominoRack"]={name="Dominoes Smack 18 (SFX)",id="rbxassetid://9114126496",volume=0.35,speed=1.0,minDistance=5,range=45,loop=false}
C["DraftSelected_RebelliousToyDrum"]={name="Drum Tom Tom Single Hits Bent Drum Head Stri (SFX)",id="rbxassetid://9125514393",volume=0.28,speed=1.0,minDistance=5,range=45,loop=false}
C["DraftSelected_WindUpCrabToy"]={name="Crab Claw Repetitive Clicks 3 (SFX)",id="rbxassetid://9113957245",volume=0.32,speed=1.0,minDistance=5,range=45,loop=false}
C["DraftSelected_OrigamiCrane"]={name="Typing Paper Flutter Single Sheet Passing By (SFX)",id="rbxassetid://9126143504",volume=0.4,speed=1.0,minDistance=5,range=45,loop=false}
C["DraftSelected_DancingMetronome"]={name="Dial Switch Twisting Sharp Ticking 79 (SFX)",id="rbxassetid://9114071134",volume=0.28,speed=1.0,minDistance=5,range=45,loop=false}
C["DraftSelected_ColdIron"]={name="Swish By Blowing Air Hissing Tubular 1 (SFX)",id="rbxassetid://9119694091",volume=1.6,speed=1.0,minDistance=5,range=45,loop=false}
C["DraftSelected_GrumblingPiggyBank"]={name="Pig Grunts 4 (SFX)",id="rbxassetid://9117346376",volume=1.0,speed=1.0,minDistance=5,range=45,loop=false}
C["DraftSelected_ForgetfulDeskLamp"]={name="Lamp Switch Luxo Lamp Twist Clicks 11 (SFX)",id="rbxassetid://9116214302",volume=0.45,speed=1.0,minDistance=5,range=45,loop=false}
C["DraftSelected_NervousSaltShaker"]={name="Sneezing Comical 3 (SFX)",id="rbxassetid://9119304618",volume=0.27,speed=1.0,minDistance=5,range=45,loop=false}
C["DraftSelected_CreepingTapeMeasure"]={name="Measuring Tape 2 (SFX)",id="rbxassetid://9116480952",volume=3.2,speed=1.0,minDistance=5,range=45,loop=false}
C["DraftSelected_SulkingUmbrella"]={name="Cloth Flap 6 (SFX)",id="rbxassetid://9113819490",volume=0.42,speed=1.0,minDistance=5,range=45,loop=false}
C["DraftSelected_BackwardsHairdryer"]={name="Hair Dryer 1 (SFX)",id="rbxassetid://9114742693",volume=0.23,speed=1.0,minDistance=5,range=45,loop=true}
C["DraftSelected_NoseyMagnifier"]={name="Magic Glows Soft Clusters Of Chiming Hits 1 (SFX)",id="rbxassetid://9116394545",volume=3.0,speed=1.0,minDistance=5,range=45,loop=false}
C["DraftSelected_SqueakyDuck"]={name="Squeeze Toy Squeaky Rubber With Noisemaker H (SFX)",id="rbxassetid://9125994553",volume=0.28,speed=1.0,minDistance=5,range=45,loop=false}
-- Monster attack sounds (2026-10-22, Creator Store / Pro Sound Effects): wind-ups, grabs, hits and the Tripod's kick.
C.WraithLunge={name='Creature Screech Pterodactyl Vocals 1 (SFX)',id='rbxassetid://9125474229',volume=.5,speed=1.08,range=85}
C.MonsterWhoosh={name='cloth fast whoosh swing',id='rbxassetid://111254855668531',volume=.55,speed=1,range=55}
C.MonsterHitThump={name='Soccer Ball Tackle 4 (SFX): deep thump',id='rbxassetid://9119330371',volume=.6,speed=.9,range=60}
C.MonsterGrab={name='Leg Grab Toss Body 1 (SFX)',id='rbxassetid://9116258509',volume=.55,speed=1,range=55}
C.NeonKickClang={name='Shield Clang As Hit Metal 1 (SFX)',id='rbxassetid://9119072660',volume=.45,speed=.8,range=70}
C.LanternLift={name='Creaks And Squeaks 6 (SFX): heavy metal creak',id='rbxassetid://9113969124',volume=.45,speed=.9,range=60}
-- Fortune teller smashed (CloseUpChoices); owner picked this one by ear, 2026-10-24.
C.BulbCrack={name='light bulb break',id='rbxassetid://133426190455626',volume=.6,speed=1,range=70}
-- Level scares (LevelAmbienceClient, 2026-10-25): every one comes from a real thing nearby (a closed door, the floor
-- above, a loot item, a monster out of sight). Swap an id here to change a sound; the owner picks them by ear.
C.ScareKnock={name='Knocking on a nearby door',id='rbxassetid://9120918417',pool={{id='rbxassetid://9120918417',name='Wood Knock Wooden Door 1'},{id='rbxassetid://9120918534',name='Wood Knock Wooden Door 2'},{id='rbxassetid://9120918492',name='Wood Knock Wooden Door 3'},{id='rbxassetid://91168254607377',name='Door Knock (InterTMCH)'},{id='rbxassetid://138990412937492',name='Door Knock (Reblrthztv)'}},volume=.55,speed=.92,range=60,minDistance=6}
C.ScarePound={name='Door pounds, handle jiggles',id='rbxassetid://9114148744',pool=pool('Door Pounds',{9114148744,9114149153}),volume=.5,speed=.95,range=60,minDistance=6}
C.ScareSteps={name='Creeping floorboards (footsteps above)',id='rbxassetid://9120836780',pool={{id='rbxassetid://9120836780',name='Wood Creaks 51 (creeping)'},{id='rbxassetid://9114496099',name='Floor Creaks 20'},{id='rbxassetid://71387640148003',name='Wood Footsteps'}},volume=.5,speed=.9,range=55,minDistance=8}
C.ScareThud={name='Something falls in the next room',id='rbxassetid://9126090621',pool={{id='rbxassetid://9126090621',name='Table Falls'},{id='rbxassetid://9113437538',name='Big Thuds Wall Impact 2'},{id='rbxassetid://9116250707',name='Leather Bible falls'}},volume=.45,speed=.9,range=60,minDistance=6}
C.ScareWhisper={name='Whisper behind you',id='rbxassetid://9043347151',pool={{id='rbxassetid://9043347151',name='DISTURBED WHISPERS 06'},{id='rbxassetid://128699976960071',name='creepy whispering'},{id='rbxassetid://89930215709196',name='creepy whispering 1'}},volume=.22,speed=.92,range=20,minDistance=2}
-- Van utility gear (GearShopServer, 2026-10-27). Both reuse assets already in this catalog; swap by ear.
C.DecoyChirp={name='Chirpy Decoy chirp (Whistle Wolf 5, sped up)',id='rbxassetid://9120689345',volume=.3,speed=1.8,range=70,duration=.6}
C.CartBellRing={name='Cart Bell ring (Shop Bell open, pitched up)',id='rbxassetid://127488139302452',volume=.5,speed=1.35,range=110,duration=.8}
-- CursedA 2026-10-27: HungryLunchbox chomp (reuses the Chattering Metal asset of NeonChatter, sped up).
C.LunchboxChomp={name='Chattering Metal (lunchbox chomp, fast)',id='rbxassetid://9125914961',volume=.42,speed=1.35,range=60,duration=.5}
-- Dread layer (LevelAmbienceClient.DreadLayer, 2026-10-27 ScareSound): Roblox library sounds (APM / Pro Sound Effects), swap by ear.
C.ScareBreath={name='Breathing right behind you',id='rbxassetid://9043349702',pool=pool('HORROR BREATH OUT',{9043349702,9043349874,9043349882}),volume=.3,speed=.95,range=18,minDistance=2,duration=6}
C.ScareGasp={name='Your gasp when a monster sees you',id='rbxassetid://9043348617',pool=pool('HORROR BREATH IN FAST',{9043348617,9043348620}),volume=.3,speed=1,range=30,duration=2.5}
C.ScareSpotted={name='BIG IMPACT HIT 11 (spotted)',id='rbxassetid://9043338036',volume=.3,speed=1,range=60,duration=2.5}
C.ScareRelief={name='AMBIENT BOOM 04 (it lost you)',id='rbxassetid://9043340902',volume=.2,speed=.8,range=100,duration=3}
C.ScareScrape={name='Something dragged in the next room',id='rbxassetid://9116621800',pool={{id='rbxassetid://9116621800',name='Metal Drum 3 (SFX)'},{id='rbxassetid://9125690244',name='Metal Slide Metal Box On Metal Desk 2 (SFX)'},{id='rbxassetid://9118767462',name='Sand Bag Slide 5 (SFX)'}},volume=.4,speed=.8,range=60,minDistance=6}
C.ScareDrip={name='Distant drips',id='rbxassetid://9126190246',pool=pool('Water Drips Into Filled Bowl Cave',{9126190246,9126190182,9126190364,9126190341}),volume=.08,speed=1,range=45,minDistance=4,duration=4}
-- WorldB world features (2026-10-27). Every id is an existing catalog asset (no new uploads); see WorldB SOUNDS.md.
C.CartSqueak={name='Wood Door Creak Squeak 2 (runaway cart wheel, fast)',id='rbxassetid://9120839010',volume=.32,speed=1.75,range=70,duration=.5}
C.MouseWind={name='Crab Claw Repetitive Clicks 3 (SFX) (tattle mouse winding)',id='rbxassetid://9113957245',volume=.3,speed=1.4,minDistance=5,range=40}
C.MouseSqueak={name='Squeeze Toy Squeaky Rubber With Noisemaker H (SFX) (tattle mouse)',id='rbxassetid://9125994553',volume=.22,speed=1.5,minDistance=5,range=55}
-- WorldB flood valve (2026-10-27): the drain gurgle, an alias of an existing draft-item asset.
C.DrainGurgle={name='Plastic Water Jug Glugs 14 (SFX) (flood drain)',id='rbxassetid://9117644772',volume=.35,speed=.8,minDistance=6,range=60}
return C
