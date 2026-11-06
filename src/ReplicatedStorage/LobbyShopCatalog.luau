local C={}
C.RunLevels=1
C.TokensPerRun=25
C.Categories={
 {id='HighestLevel',label='HIGHEST LEVEL',ascending=false},
 {id='FastestClearMs',label='FASTEST LEVEL 1',ascending=true,time=true},
 {id='TotalRetrieved',label='TOTAL RETRIEVED',ascending=false,money=true},
 {id='BestHaul',label='BIGGEST HAUL',ascending=false,money=true},
 {id='RunsCompleted',label='RUNS COMPLETED',ascending=false},
 {id='CollectionPercent',label='COLLECTION %',ascending=false,percent=true},
}
C.SpeedLimits={Walk=22,Sprint=35} -- unused since 2026-10-26 (2x Speed is a true double)
-- Owner 2026-10-26: everyone moves faster. Base speeds; upgrade tiers ADD on top, then the 2x Speed pass doubles it.
C.BaseSpeed={Walk=13.5,Sprint=21.5} -- owner 2026-10-26: 12.5/20.5 +1 each (14/23 felt too fast; original 12/20)
C.UpgradeCosts={150,400,900,1800} -- 2026-10-24 owner: was 25/50/100/150 (975 tokens maxed everything; now 9750)
-- Shop tutorial (owner 2026-10-25): finishing the first tutorial pays TutorialTokens once; while that player's shop
-- chapter runs, their first team boost costs at most TutorialBoostPrice and their first Movement Speed tier
-- TutorialUpgrade.price (ProgressCore / GearShopServer charge it, the shops show it).
C.TutorialTokens=50
C.TutorialBoostPrice=50
C.TutorialUpgrade={stat='Speed',price=50}
function C.UpgradeCostFor(stat,tier,shopStep)
 local cost=C.UpgradeCosts[tier+1]
 if cost and shopStep==2 and tier==0 and stat==C.TutorialUpgrade.stat then return math.min(cost,C.TutorialUpgrade.price)end
 return cost
end
C.UpgradeStats={Speed={{0,0},{1,1.5},{2,3},{3,4.5},{4,6}},Stamina={100,125,150,175,200},Flashlight={1,1.6,2.3,3.1,4}}
C.TokenOffers={
 {id='upgrade_speed',name='Movement Speed',kind='Upgrade',stat='Speed',color={154,216,157},description='Permanent walk and sprint upgrades. Each tier adds +1 walk and +1.5 sprint.'},
 {id='upgrade_stamina',name='Stamina Capacity',kind='Upgrade',stat='Stamina',color={154,207,232},description='Permanent stamina upgrades, from 100 to 200 stamina.'},
 {id='upgrade_flashlight',name='Flashlight Strength',kind='Upgrade',stat='Flashlight',color={243,217,136},description='A permanently wider, longer beam. Up to a 55% wider cone and 60-stud reach.'},
 {id='title_rookie',name='Rookie Survivor',kind='Title',price=25,text='ROOKIE SURVIVOR',color={185,211,171},description='A survivor title above your character.'},
 {id='title_looter',name='Loot Goblin',kind='Title',price=50,text='LOOT GOBLIN',color={228,204,115},description='Show everyone who is grabbing the loot.'},
 {id='title_lucky',name='Still Breathing',kind='Title',price=75,text='STILL BREATHING',color={153,219,212},description='A title for surviving another bad decision.'},
 {id='title_van',name='Van VIP',kind='Title',price=100,text='VAN VIP',color={157,193,244},description='The van is your happy place.'},
 {id='title_unhinged',name='Unreasonably Happy',kind='Title',price=125,text='UNREASONABLY HAPPY',color={231,167,212},description='A suspiciously cheerful survivor title.'},
 {id='title_legend',name='Do Not Die',kind='Title',price=175,text='DO NOT DIE',color={245,230,175},description='An imposing golden survivor title.'},
 {id='aura_mint',name='Mint Mist',kind='Aura',price=50,color={166,239,192},description='Soft mint particles around your character.'},
 {id='aura_frost',name='Frost Mist',kind='Aura',price=75,color={180,222,255},description='A cool blue cosmetic mist.'},
 {id='aura_rose',name='Rose Mist',kind='Aura',price=75,color={245,153,194},description='A pink glow for a grim expedition.'},
 {id='aura_amber',name='Amber Embers',kind='Aura',price=100,color={245,190,105},description='Warm amber drifting sparks.'},
 {id='aura_violet',name='Violet Wisps',kind='Aura',price=125,color={193,151,245},description='A violet shimmer around your character.'},
 {id='aura_ghost',name='Ghost Light',kind='Aura',price=175,color={245,245,245},description='White spectral sparks. Entirely cosmetic.'},
}
C.RobuxOffers={
 {id='infinite_stamina',name='Infinite Stamina',kind='Pass',assetId=2002808579,price=117,color={154,216,157},description='Sprint without draining stamina. Permanent.'},
 {id='double_speed',name='2x Speed',kind='Pass',assetId=2001872740,price=135,color={154,207,232},description='Doubles your walk and sprint speed, upgrades included. Permanent.'},
 {id='free_revive',name='Second Chance',kind='Pass',assetId=2002556684,price=72,color={245,169,173},description='One free self revive EVERY LEVEL: it comes back at the start of each new level. Permanent pass.'},
 {id='revive_token',name='1 Revive Token',kind='Product',assetId=3715702819,price=23,color={211,179,246},description='One saved self revive. Unused tokens carry over to future games.'},
  {id='revive_pack_3',name='3 Revive Tokens',kind='Product',assetId=3716356017,price=61,grantRevives=3,color={211,179,246},description='Three saved self revives at a discount. Unused tokens carry over to future games.'},
  {id='instant_win',name='Instant Win',kind='Product',assetId=3716356019,price=180,grantInstantWin=1,color={255,214,110},description='One charge. In a game, open the ROBUX panel in the van and press USE to clear the current level for your whole team. Unused charges are kept.'},
  {id='gift_revive',name='Gift a Revive',kind='Product',assetId=3716104907,price=26,giftRevive=true,color={211,179,246},description='Pick a dead teammate from a list and bring them back. If they cannot be revived when the purchase completes, you keep one saved revive token.'},
  {id='jumpscare_all',name='Jumpscare Everyone',kind='Product',assetId=3716104905,price=68,grantJumpscare=1,color={235,90,90},description='One charge. In a game, open the ROBUX panel in the van and press USE to scare every teammate at once. Needs at least one teammate in your game.'},
  {id='flashlight_colors',name='Flashlight Colors',kind='Pass',assetId=2005790617,price=27,color={255,200,90},description='Pick any colour for your flashlight beam in Cosmetics. Permanent.'},
  -- Token packs (owner 2026-10-27: boosted 100/300/800 -> 250/750/2000, and four packs added so any shortfall has a fit).
  {id='tokens_tiny',name='100 Tokens',kind='Product',assetId=3723023765,price=25,grantTokens=100,color={243,217,136},description='100 tokens: a quick top-up for upgrades and cosmetics.'},
  {id='tokens_small',name='250 Tokens',kind='Product',assetId=3716104898,price=49,grantTokens=250,color={243,217,136},description='250 tokens for upgrades and cosmetics.'},
  {id='tokens_handful',name='450 Tokens',kind='Product',assetId=3723023771,price=79,grantTokens=450,color={243,217,136},description='450 tokens for upgrades and cosmetics.'},
  {id='tokens_medium',name='750 Tokens',kind='Product',assetId=3716104899,price=129,grantTokens=750,color={243,217,136},description='750 tokens for upgrades and cosmetics.'},
  {id='tokens_big',name='1,200 Tokens',kind='Product',assetId=3723023775,price=189,grantTokens=1200,color={243,217,136},description='1,200 tokens for upgrades and cosmetics.'},
  {id='tokens_large',name='2,000 Tokens',kind='Product',assetId=3716104902,price=299,grantTokens=2000,color={243,217,136},description='2,000 tokens for upgrades and cosmetics.'},
  {id='tokens_mega',name='5,000 Tokens',kind='Product',assetId=3723023782,price=649,grantTokens=5000,color={243,217,136},description='5,000 tokens: the biggest pack, best value.'},
 {id='double_tokens',name='2x Extraction Tokens',kind='Pass',assetId=2001770733,price=117,color={243,217,136},description='Earn 50 instead of 25 tokens per successful extraction. Permanent.'},
 {id='vip',name='Haunted VIP',kind='Pass',assetId=2002064738,price=36,color={245,205,100},description='Exclusive HAUNTED VIP title and gold spectral aura. Cosmetic.'},
}
C.OfferImages={
 ['upgrade_speed']='rbxassetid://104871605511731',
 ['upgrade_flashlight']='rbxassetid://128115087182775',
 ['title_van']='rbxassetid://98616124049494',
 ['title_rookie']='rbxassetid://76320737082159',
 ['upgrade_stamina']='rbxassetid://118049016303940',
 ['title_looter']='rbxassetid://115374007671997',
 ['title_lucky']='rbxassetid://134727822175783',
 ['title_unhinged']='rbxassetid://99914904569691',
 ['aura_rose']='rbxassetid://121487387419474',
 ['title_legend']='rbxassetid://122948063533716',
 ['aura_frost']='rbxassetid://80442346743474',
 ['aura_amber']='rbxassetid://137720891896882',
 ['aura_violet']='rbxassetid://88891140089736',
 ['aura_mint']='rbxassetid://107797273855954',
 ['aura_ghost']='rbxassetid://132408912136850',
 ['free_revive']='rbxassetid://113340175809749',
 ['double_tokens']='rbxassetid://140210032395122',
 ['double_speed']='rbxassetid://94768855455983',
 ['revive_token']='rbxassetid://122888744965333',
 ['revive_pack_3']='rbxassetid://89193424268031',
 ['instant_win']='rbxassetid://111911305328601',
 ['vip']='rbxassetid://119058449021731',
 ['infinite_stamina']='rbxassetid://131819565985606',
 ['gift_revive']='rbxassetid://130605175910404',
 ['jumpscare_all']='rbxassetid://120081436228813',
 ['flashlight_colors']='rbxassetid://77868565595406',
 ['tokens_small']='rbxassetid://116174307880260',
 ['tokens_medium']='rbxassetid://81771698335488',
 ['tokens_large']='rbxassetid://89049652686831',
 -- the four packs added 2026-10-27 reuse the three token pictures (owner: re-use the 3 we had)
 ['tokens_tiny']='rbxassetid://116174307880260',
 ['tokens_handful']='rbxassetid://81771698335488',
 ['tokens_big']='rbxassetid://89049652686831',
 ['tokens_mega']='rbxassetid://89049652686831',
}
-- Wearable cosmetics: one per slot. Token ones are bought here; Robux ones are unlocked by their game pass (grants).
-- Models live in ReplicatedStorage.CosmeticKit[id] (attached by ReplicatedStorage.CosmeticRig); Shirt cosmetics are stomach tattoo decals.
C.CosmeticSlots={'Hat','Ring','Shirt','Shoes'}
local wearPremium={}
C.TattooDecals={tat_skull='rbxassetid://120824662688648',tat_mom='rbxassetid://119723529248373',tat_web='rbxassetid://104485770046632',tat_flames='rbxassetid://92632715340544',tat_dragon='rbxassetid://88903507357470',tat_galaxy='rbxassetid://128616434221791',tat_streets='rbxassetid://84322444509963'}
local wearIcons={hat_tophat=85885290469197,hat_witch=85951432042228,hat_propeller=93372215732816,hat_cowboy=124325580174983,hat_crown=125116909014250,hat_halo=91592163281609,ring_silver=134875489014545,ring_ruby=121486535170480,ring_bone=123754379124360,ring_diamond=132398061838738,tat_skull=95056783631473,tat_mom=131781181002794,tat_web=89933116894210,tat_flames=87765163799367,tat_dragon=107178497410786,tat_galaxy=109667872502871,shoe_sneaker=91910611385077,shoe_rainboot=103771409597686,shoe_clown=129390803658156,shoe_rocket=96730871752422,shoe_gold=72383297190300,hat_durag=80798009809987,hat_snapback=122009001745270,ring_signet=102461523044387,tat_streets=121793207641379,shoe_hightop=112212447779313,shoe_slides=137543060986959}
for _,w in {
 {'hat_tophat','Top Hat','Hat',60,{90,90,100},'A tall black top hat with a red band.'},
 {'hat_witch','Witch Hat','Hat',90,{150,110,200},'A crooked purple witch hat with a gold buckle.'},
 {'hat_propeller','Propeller Cap','Hat',120,{230,90,90},'A striped beanie with a spinning propeller.'},
 {'hat_cowboy','Cowboy Hat','Hat',150,{190,140,90},'A wide brown cowboy hat.'},
 {'ring_silver','Silver Band','Ring',40,{205,210,220},'A simple silver ring.'},
 {'ring_ruby','Ruby Ring','Ring',80,{220,80,100},'A gold ring with a red ruby.'},
 {'ring_bone','Bone Ring','Ring',120,{235,228,205},'A carved bone ring with a tiny skull.'},
 {'tat_skull','Skull Tattoo','Shirt',50,{235,235,225},'A skull and crossbones tattoo on your belly.'},
 {'tat_mom','MOM Heart','Shirt',70,{230,80,100},'A classic MOM heart tattoo on your belly.'},
 {'tat_web','Spiderweb Tattoo','Shirt',100,{170,170,180},'A spiderweb tattoo on your belly.'},
 {'tat_flames','Flames Tattoo','Shirt',130,{245,140,50},'Hot rod flames across your belly.'},
 {'shoe_sneaker','Red Sneakers','Shoes',50,{230,90,90},'White sneakers with red soles.'},
 {'shoe_rainboot','Rain Boots','Shoes',80,{245,210,70},'Bright yellow rain boots.'},
 {'shoe_clown','Clown Shoes','Shoes',120,{220,60,70},'Enormous red clown shoes.'},
 -- Street set: black / white / gold.
 {'hat_durag','Silk Durag','Hat',80,{70,70,80},'A black satin durag with long tails.'},
 {'hat_snapback','Backwards Snapback','Hat',110,{240,190,60},'A black cap with a gold brim, worn backwards.'},
 {'ring_signet','Dollar Signet','Ring',140,{240,190,60},'A chunky gold ring with a dollar plate.'},
 {'tat_streets','Streets Tattoo','Shirt',110,{244,236,210},'STREETS in big arched letters with stars.'},
 {'shoe_hightop','Street High-Tops','Shoes',100,{200,200,205},'Black and white high-tops with gold eyelets.'},
 {'shoe_slides','Slides & Socks','Shoes',60,{235,235,230},'Black slides over white tube socks.'},
}do table.insert(C.TokenOffers,{id=w[1],name=w[2],kind=w[3],price=w[4],color=w[5],description=w[6]}) end
for _,w in {
 {'hat_crown','Golden Crown','Hat',2002022927,27,{245,205,100},'A gold royal crown with sapphire, emerald and amethyst stones. Cosmetic.'},
 {'hat_halo','Glowing Halo','Hat',2001746971,36,{255,240,170},'A floating glowing halo. Cosmetic.'},
 {'ring_diamond','Diamond Ring','Ring',2002028953,18,{180,235,255},'A gold ring with a big diamond. Cosmetic.'},
 {'tat_dragon','Dragon Tattoo','Shirt',2002646932,23,{90,190,120},'A winged dragon belly tattoo. Cosmetic.'},
 {'tat_galaxy','Galaxy Tattoo','Shirt',2001776991,27,{170,130,230},'A swirling galaxy belly tattoo. Cosmetic.'},
 {'shoe_rocket','Rocket Boots','Shoes',2001279007,32,{255,160,70},'White jet boots with blue fins and glowing twin thrusters. Cosmetic.'},
 {'shoe_gold','Gold Kicks','Shoes',2001549038,23,{245,205,100},'Solid gold sneakers. Cosmetic.'},
}do
 table.insert(wearPremium,{id=w[1],name=w[2],kind=w[3],color=w[6]})
 table.insert(C.RobuxOffers,{id='pass_'..w[1],name=w[2],kind='Pass',assetId=w[4],price=w[5],color=w[6],description=w[7],grants=w[1]})
 wearIcons['pass_'..w[1]]=wearIcons[w[1]]
end
-- Quest Log expansion (2026-10-07): map sets, new slots (Eyes/Back/Trail/Torch), quest and chest rewards, and the
-- Halloween event (releaseStage='event': registered so every server keeps the ids; not sold or granted until EventConfig is on).
C.CosmeticSlots={'Hat','Ring','Shirt','Shoes','Eyes','Back','Trail','Torch','Pet'}
for _,o in {
 {id='ring_ghosthost',name='Antique Key Ring',kind='Ring',price=100,color={150,110,200},description='Ghost Host set ring.',rarity='rare',set='ghosthost'},
 {id='tat_ghosthost',name='Haunted Portrait',kind='Shirt',price=90,color={150,110,200},description='Ghost Host set belly tattoo.',rarity='rare',set='ghosthost'},
 {id='shoe_ghosthost',name='Butler Shoes',kind='Shoes',price=120,color={150,110,200},description='Ghost Host set shoes.',rarity='rare',set='ghosthost'},
 {id='ring_crawler',name='Shackle Ring',kind='Ring',price=100,color={150,156,168},description='Crawler set ring.',rarity='rare',set='crawler'},
 {id='tat_crawler',name='Chains Tattoo',kind='Shirt',price=90,color={150,156,168},description='Crawler set belly tattoo.',rarity='rare',set='crawler'},
 {id='shoe_crawler',name='Iron Sabatons',kind='Shoes',price=120,color={150,156,168},description='Crawler set shoes.',rarity='rare',set='crawler'},
 {id='ring_partyanimal',name='Candy Ring',kind='Ring',price=100,color={230,110,200},description='Party Animal set ring.',rarity='rare',set='partyanimal'},
 {id='tat_partyanimal',name='Birthday Cake Tattoo',kind='Shirt',price=90,color={230,110,200},description='Party Animal set belly tattoo.',rarity='rare',set='partyanimal'},
 {id='shoe_partyanimal',name='Balloon Sneakers',kind='Shoes',price=120,color={230,110,200},description='Party Animal set shoes.',rarity='rare',set='partyanimal'},
 {id='ring_mallrat',name='Shopping Bag Ring',kind='Ring',price=100,color={230,80,80},description='Mallrat set ring.',rarity='rare',set='mallrat'},
 {id='tat_mallrat',name='SALE Tag Tattoo',kind='Shirt',price=90,color={230,80,80},description='Mallrat set belly tattoo.',rarity='rare',set='mallrat'},
 {id='shoe_mallrat',name='Light-Up Skates',kind='Shoes',price=120,color={230,80,80},description='Mallrat set shoes.',rarity='rare',set='mallrat'},
 {id='ring_captain',name='Anchor Ring',kind='Ring',price=100,color={80,120,220},description='Captain set ring.',rarity='rare',set='captain'},
 {id='tat_captain',name='Swallow Tattoo',kind='Shirt',price=90,color={80,120,220},description='Captain set belly tattoo.',rarity='rare',set='captain'},
 {id='shoe_captain',name='Boat Shoes',kind='Shoes',price=120,color={80,120,220},description='Captain set shoes.',rarity='rare',set='captain'},
 {id='ring_nightshift',name='Syringe Ring',kind='Ring',price=100,color={60,190,180},description='Night Shift set ring.',rarity='rare',set='nightshift'},
 {id='tat_nightshift',name='Heart Monitor Tattoo',kind='Shirt',price=90,color={60,190,180},description='Night Shift set belly tattoo.',rarity='rare',set='nightshift'},
 {id='shoe_nightshift',name='Comfy Clogs',kind='Shoes',price=120,color={60,190,180},description='Night Shift set shoes.',rarity='rare',set='nightshift'},
 {id='ring_bellhop',name='Room 13 Key Ring',kind='Ring',price=100,color={200,60,70},description='Bellhop set ring.',rarity='rare',set='bellhop'},
 {id='tat_bellhop',name='Do Not Disturb Tattoo',kind='Shirt',price=90,color={200,60,70},description='Bellhop set belly tattoo.',rarity='rare',set='bellhop'},
 {id='shoe_bellhop',name='Penny Loafers',kind='Shoes',price=120,color={200,60,70},description='Bellhop set shoes.',rarity='rare',set='bellhop'},
 {id='ring_detention',name='Pencil Ring',kind='Ring',price=100,color={80,140,240},description='Detention set ring.',rarity='rare',set='detention'},
 {id='tat_detention',name='Gold Star Tattoo',kind='Shirt',price=90,color={80,140,240},description='Detention set belly tattoo.',rarity='rare',set='detention'},
 {id='shoe_detention',name='Light-Up Kid Sneakers',kind='Shoes',price=120,color={80,140,240},description='Detention set shoes.',rarity='rare',set='detention'},
 {id='eyes_tophat',name='Tiny Top Hats',kind='Eyes',price=250,color={60,60,70},description='Two tiny top hats, one on each eye.',rarity='epic'},
 {id='eyes_candle',name='Birthday Candles',kind='Eyes',price=150,color={240,140,190},description='A lit candle on each eye stalk.',rarity='rare'},
 {id='back_backpack',name='Explorer Backpack',kind='Back',price=150,color={130,80,220},description='A comfy purple backpack.',rarity='rare'},
 {id='back_batwings',name='Bat Wings',kind='Back',price=250,color={120,70,200},description='Little bat wings. They do not fly.',rarity='epic'},
 {id='back_halo',name='Halo Ring',kind='Back',price=200,color={245,205,100},description='A golden ring floating behind you.',rarity='epic'},
 {id='back_jetpack',name='Jetpack',kind='Back',price=300,color={170,180,195},description='A shiny jetpack. Purely for looks.',rarity='epic'},
 {id='trail_sparks',name='Spark Trail',kind='Trail',price=120,color={255,200,90},description='Sparks follow your footsteps.',rarity='rare'},
 {id='trail_ectoplasm',name='Ectoplasm Trail',kind='Trail',price=150,color={120,255,140},description='Green slime drips behind you.',rarity='rare'},
 {id='pet_glowmoth',name='Glow Moth',kind='Pet',price=200,color={191,245,210},description='A fuzzy moth that flutters by your head. It reacts, but does nothing. Purely for looks.',rarity='epic',follow='hover'}, -- World/GlowMoth (WorldA)
}do table.insert(C.TokenOffers,o) end
C.RewardCosmetics={
 {id='hat_ghosthost',name='Tattered Top Hat',kind='Hat',color={150,110,200},description='Ghost Host set. Earned from the weekly Mansion quest.',rarity='rare',nonPurchasable=true,set='ghosthost'},
 {id='aura_set_ghosthost',name='Ghost Host Aura',kind='Aura',color={150,110,200},description='Own all four Ghost Host pieces to unlock this aura.',rarity='mythic',nonPurchasable=true,set='ghosthost'},
 {id='hat_crawler',name='Horned Helmet',kind='Hat',color={150,156,168},description='Crawler set. Earned from the weekly Dungeon quest.',rarity='rare',nonPurchasable=true,set='crawler'},
 {id='aura_set_crawler',name='Crawler Aura',kind='Aura',color={150,156,168},description='Own all four Crawler pieces to unlock this aura.',rarity='mythic',nonPurchasable=true,set='crawler'},
 {id='hat_partyanimal',name='Party Hat',kind='Hat',color={230,110,200},description='Party Animal set. Earned from the weekly Birthday quest.',rarity='rare',nonPurchasable=true,set='partyanimal'},
 {id='aura_set_partyanimal',name='Party Animal Aura',kind='Aura',color={230,110,200},description='Own all four Party Animal pieces to unlock this aura.',rarity='mythic',nonPurchasable=true,set='partyanimal'},
 {id='hat_mallrat',name='Food-Court Hat',kind='Hat',color={230,80,80},description='Mallrat set. Earned from the weekly Mall quest.',rarity='rare',nonPurchasable=true,set='mallrat'},
 {id='aura_set_mallrat',name='Mallrat Aura',kind='Aura',color={230,80,80},description='Own all four Mallrat pieces to unlock this aura.',rarity='mythic',nonPurchasable=true,set='mallrat'},
 {id='hat_captain',name='Captain\'s Cap',kind='Hat',color={80,120,220},description='Captain set. Earned from the weekly Cruise quest.',rarity='rare',nonPurchasable=true,set='captain'},
 {id='aura_set_captain',name='Captain Aura',kind='Aura',color={80,120,220},description='Own all four Captain pieces to unlock this aura.',rarity='mythic',nonPurchasable=true,set='captain'},
 {id='hat_nightshift',name='Nurse Cap',kind='Hat',color={60,190,180},description='Night Shift set. Earned from the weekly Hospital quest.',rarity='rare',nonPurchasable=true,set='nightshift'},
 {id='aura_set_nightshift',name='Night Shift Aura',kind='Aura',color={60,190,180},description='Own all four Night Shift pieces to unlock this aura.',rarity='mythic',nonPurchasable=true,set='nightshift'},
 {id='hat_bellhop',name='Bellhop Cap',kind='Hat',color={200,60,70},description='Bellhop set. Earned from the weekly Hotel quest.',rarity='rare',nonPurchasable=true,set='bellhop'},
 {id='aura_set_bellhop',name='Bellhop Aura',kind='Aura',color={200,60,70},description='Own all four Bellhop pieces to unlock this aura.',rarity='mythic',nonPurchasable=true,set='bellhop'},
 -- hat_detention (Dunce Cap) retired entirely (owner 2026-10-28): no catalog entry, so it is not shown, earned or worn;
 -- saves keep the old Owned flag (Reconcile keeps unknown ids, drops it from Equipped). The Detention set is 3 pieces.
 {id='aura_set_detention',name='Detention Aura',kind='Aura',color={80,140,240},description='Own the Detention ring, tattoo and sneakers to unlock this aura.',rarity='mythic',nonPurchasable=true,set='detention'},
 {id='eyes_monocle',name='Monocle',kind='Eyes',color={245,205,100},description='Tycoon achievement, tier III.',rarity='rare',nonPurchasable=true},
 {id='eyes_spider',name='Spider Eyes',kind='Eyes',color={140,90,220},description='Locksmith achievement, tier IV.',rarity='epic',nonPurchasable=true},
 {id='eyes_ghostflame',name='Ghost Flames',kind='Eyes',color={110,220,255},description='Escape Artist achievement, tier V.',rarity='legendary',nonPurchasable=true},
 {id='eyes_goggles',name='Aviator Goggles',kind='Eyes',color={60,110,200},description='Weekly Chest exclusive.',rarity='rare',nonPurchasable=true,chestExclusive=true},
 {id='back_ghostbuddy',name='Ghost Buddy',kind='Back',color={230,230,240},description='Weekly Chest exclusive.',rarity='epic',nonPurchasable=true,chestExclusive=true},
 {id='back_globetrotter',name='Globetrotter Pack',kind='Back',color={60,150,80},description='World Traveler achievement, tier V.',rarity='legendary',nonPurchasable=true},
 {id='trail_glitter',name='Glitter Trail',kind='Trail',color={255,150,230},description='Collector achievement, tier IV.',rarity='epic',nonPurchasable=true},
 {id='trail_speed',name='Speed Lines',kind='Trail',color={230,240,255},description='Escape Artist achievement, tier IV.',rarity='epic',nonPurchasable=true},
 {id='trail_hearts',name='Heart Trail',kind='Trail',color={255,90,130},description='Team Player achievement, tier IV.',rarity='epic',nonPurchasable=true},
 {id='trail_coins',name='Coin Trail',kind='Trail',color={255,205,70},description='Treasure Hunter achievement, tier IV.',rarity='epic',nonPurchasable=true},
 {id='torch_candle',name='Candle Torch',kind='Torch',color={255,220,150},description='Survivor achievement, tier IV.',rarity='epic',nonPurchasable=true},
 {id='torch_lantern',name='Lantern Torch',kind='Torch',color={255,170,80},description='Deep Diver achievement, tier IV.',rarity='epic',nonPurchasable=true},
 {id='torch_glowstick',name='Glowstick',kind='Torch',color={150,255,90},description='Weekly Chest exclusive.',rarity='rare',nonPurchasable=true,chestExclusive=true},
 {id='aura_collector',name='Curse Collector',kind='Aura',color={200,60,80},description='Curse Scholar achievement, tier V.',rarity='mythic',nonPurchasable=true},
 {id='hat_pumpkinking',name='Pumpkin King Head',kind='Hat',color={245,140,40},description='Halloween event.',rarity='legendary',nonPurchasable=true,releaseStage='event'},
 {id='ring_pumpkinking',name='Candy Corn Ring',kind='Ring',color={245,170,60},description='Halloween event.',rarity='legendary',nonPurchasable=true,releaseStage='event'},
 {id='tat_pumpkinking',name='Bat Swarm Tattoo',kind='Shirt',color={90,60,140},description='Halloween event.',rarity='legendary',nonPurchasable=true,releaseStage='event'},
 {id='shoe_pumpkinking',name='Witch Boots',kind='Shoes',color={60,40,80},description='Halloween event.',rarity='legendary',nonPurchasable=true,releaseStage='event'},
 {id='aura_pumpkinking',name='Pumpkin Flame',kind='Aura',color={255,120,30},description='Halloween event.',rarity='legendary',nonPurchasable=true,releaseStage='event'},
 {id='trail_pumpkinseeds',name='Pumpkin Seed Trail',kind='Trail',color={250,230,170},description='Halloween event.',rarity='legendary',nonPurchasable=true,releaseStage='event'},
 {id='eyes_pumpkin',name='Jack-o-Lantern Eyes',kind='Eyes',color={255,150,40},description='Halloween event.',rarity='legendary',nonPurchasable=true,releaseStage='event'},
 {id='torch_pumpkin',name='Pumpkin Lamp',kind='Torch',color={255,140,40},description='Halloween event.',rarity='legendary',nonPurchasable=true,releaseStage='event'},
 {id='title_monstermaster',name='Monster Master',kind='Title',text='MONSTER MASTER',color={255,214,110},description='Master every monster and the collection.',rarity='legendary',nonPurchasable=true},
 {id='title_pumpkinking',name='Pumpkin King',kind='Title',color={255,140,40},description='Halloween event.',rarity='legendary',nonPurchasable=true,releaseStage='event',text='PUMPKIN KING'},
 {id='quest_title_collector',name='Cursed Collector',kind='Title',color={230,204,140},description='Achievement tier V title.',rarity='legendary',nonPurchasable=true,text='CURSED COLLECTOR'},
 {id='quest_title_survivor',name='Seasoned Survivor',kind='Title',color={230,204,140},description='Achievement tier V title.',rarity='legendary',nonPurchasable=true,text='SEASONED SURVIVOR'},
 {id='quest_title_deep_diver',name='Abyss Walker',kind='Title',color={230,204,140},description='Achievement tier V title.',rarity='legendary',nonPurchasable=true,text='ABYSS WALKER'},
 {id='quest_title_tycoon',name='Haunted Tycoon',kind='Title',color={230,204,140},description='Achievement tier V title.',rarity='legendary',nonPurchasable=true,text='HAUNTED TYCOON'},
 {id='quest_title_escape_artist',name='Uncatchable',kind='Title',color={230,204,140},description='Achievement tier V title.',rarity='legendary',nonPurchasable=true,text='UNCATCHABLE'},
 {id='quest_title_team_player',name='Guardian Angel',kind='Title',color={230,204,140},description='Achievement tier V title.',rarity='legendary',nonPurchasable=true,text='GUARDIAN ANGEL'},
 {id='quest_title_locksmith',name='Master Locksmith',kind='Title',color={230,204,140},description='Achievement tier V title.',rarity='legendary',nonPurchasable=true,text='MASTER LOCKSMITH'},
 {id='quest_title_treasure_hunter',name='Treasure Hunter',kind='Title',color={230,204,140},description='Achievement tier V title.',rarity='legendary',nonPurchasable=true,text='TREASURE HUNTER'},
 {id='quest_title_world_traveler',name='Globetrotter',kind='Title',color={230,204,140},description='Achievement tier V title.',rarity='legendary',nonPurchasable=true,text='GLOBETROTTER'},
 {id='quest_title_curse_scholar',name='Curse Scholar',kind='Title',color={230,204,140},description='Achievement tier V title.',rarity='legendary',nonPurchasable=true,text='CURSE SCHOLAR'},
 -- Rank rewards (2026-10-21): granted once a rank tier is first reached (ProgressCore rrGrant), kept for good.
 {id='rank_title_wanderer',name='Wanderer',kind='Title',text='WANDERER',color={140,214,150},description='Rank reward: reach Wanderer.',rarity='rare',nonPurchasable=true},
 {id='rank_title_survivor',name='Survivor',kind='Title',text='SURVIVOR',color={110,220,210},description='Rank reward: reach Survivor.',rarity='rare',nonPurchasable=true},
 {id='rank_title_seeker',name='Seeker',kind='Title',text='SEEKER',color={120,180,245},description='Rank reward: reach Seeker.',rarity='rare',nonPurchasable=true},
 {id='rank_title_explorer',name='Explorer',kind='Title',text='EXPLORER',color={160,150,250},description='Rank reward: reach Explorer.',rarity='epic',nonPurchasable=true},
 {id='rank_title_veteran',name='Veteran',kind='Title',text='VETERAN',color={210,155,245},description='Rank reward: reach Veteran.',rarity='epic',nonPurchasable=true},
 {id='rank_title_phantom',name='Phantom',kind='Title',text='PHANTOM',color={225,235,250},description='Rank reward: reach Phantom.',rarity='legendary',nonPurchasable=true},
 {id='rank_title_legend',name='Legend',kind='Title',text='LEGEND',color={255,224,110},description='Rank reward: reach Legend.',rarity='legendary',nonPurchasable=true},
 {id='aura_rank_legend',name='Legend Crown',kind='Aura',color={255,224,110},description='Rank reward: reach Legend.',rarity='mythic',nonPurchasable=true},
 -- Rank reward cosmetics (2026-10-22): one aura or trail per rank tier, looks in ReplicatedStorage.CosmeticRig.
 {id='aura_rank_wanderer',name='Firefly Drift',kind='Aura',color={190,240,110},description='Rank reward: reach Wanderer.',rarity='rare',nonPurchasable=true},
 {id='aura_rank_survivor',name='Heartbeat',kind='Aura',color={110,220,210},description='Rank reward: reach Survivor.',rarity='rare',nonPurchasable=true},
 {id='aura_rank_seeker',name="Seeker's Eye",kind='Aura',color={120,180,245},description='Rank reward: reach Seeker.',rarity='rare',nonPurchasable=true},
 {id='trail_rank_seeker',name='Seeker Comet',kind='Trail',color={120,180,245},description='Rank reward: reach Seeker.',rarity='rare',nonPurchasable=true},
 {id='aura_rank_explorer',name='Star Map',kind='Aura',color={160,150,250},description='Rank reward: reach Explorer.',rarity='epic',nonPurchasable=true},
 {id='trail_rank_veteran',name='Veteran Embers',kind='Trail',color={210,155,245},description='Rank reward: reach Veteran.',rarity='epic',nonPurchasable=true},
 {id='aura_rank_veteran',name='Veteran Crest',kind='Aura',color={210,155,245},description='Rank reward: reach Veteran.',rarity='epic',nonPurchasable=true},
 {id='aura_rank_phantom',name='Phantom Veil',kind='Aura',color={225,235,250},description='Rank reward: reach Phantom.',rarity='legendary',nonPurchasable=true},
 {id='trail_rank_legend',name='Legend Comet',kind='Trail',color={255,224,110},description='Rank reward: reach Legend.',rarity='mythic',nonPurchasable=true},
 {id='Tag_Haunted',name='Haunted',kind='Tag',color={175,235,210},description='Haunted Mastery: tier V in all 10 achievement chains.',rarity='mythic',nonPurchasable=true,text='[Haunted]'},
}
for id,asset in wearIcons do C.OfferImages[id]='rbxassetid://'..asset end
-- Quest Log expansion icons and belly tattoo art (2026-10-07).
for id,image in {aura_collector='rbxassetid://87369111126561',aura_pumpkinking='rbxassetid://136879696822215',aura_set_bellhop='rbxassetid://108344135025796',aura_set_captain='rbxassetid://129321130259831',aura_set_crawler='rbxassetid://89730282746542',aura_set_detention='rbxassetid://95804538156364',aura_set_ghosthost='rbxassetid://131131100243954',aura_set_mallrat='rbxassetid://72273813593973',aura_set_nightshift='rbxassetid://99765152134357',aura_set_partyanimal='rbxassetid://85623168783880',back_backpack='rbxassetid://82823916684535',back_batwings='rbxassetid://118667383425598',back_ghostbuddy='rbxassetid://104705886098271',back_globetrotter='rbxassetid://133107464175853',back_halo='rbxassetid://80440750111702',back_jetpack='rbxassetid://83858878643478',eyes_candle='rbxassetid://129344819843404',eyes_ghostflame='rbxassetid://101418665893449',eyes_goggles='rbxassetid://107270408628766',eyes_monocle='rbxassetid://104747732876448',eyes_pumpkin='rbxassetid://80097277210331',eyes_spider='rbxassetid://103089786455925',eyes_tophat='rbxassetid://140522024607608',hat_bellhop='rbxassetid://126566433485157',hat_captain='rbxassetid://124487076073668',hat_crawler='rbxassetid://121422270013922',hat_ghosthost='rbxassetid://72303523158498',hat_mallrat='rbxassetid://96281110958052',hat_nightshift='rbxassetid://107857075887318',hat_partyanimal='rbxassetid://71584688022093',hat_pumpkinking='rbxassetid://94807108895013',quest_title_collector='rbxassetid://95230720193505',quest_title_curse_scholar='rbxassetid://120616445439264',quest_title_deep_diver='rbxassetid://85610233462164',quest_title_escape_artist='rbxassetid://93801815866217',quest_title_locksmith='rbxassetid://101002994146521',quest_title_survivor='rbxassetid://97414338726295',quest_title_team_player='rbxassetid://130368969622721',quest_title_treasure_hunter='rbxassetid://110163952125614',quest_title_tycoon='rbxassetid://139671059717691',quest_title_world_traveler='rbxassetid://135039064519111',ring_bellhop='rbxassetid://92003805302370',ring_captain='rbxassetid://86459750122051',ring_crawler='rbxassetid://112555233914342',ring_detention='rbxassetid://125846013621867',ring_ghosthost='rbxassetid://103548259218011',ring_mallrat='rbxassetid://80663145425336',ring_nightshift='rbxassetid://100994241996455',ring_partyanimal='rbxassetid://97247770937533',ring_pumpkinking='rbxassetid://130421745721110',shoe_bellhop='rbxassetid://138055837952819',shoe_captain='rbxassetid://77800445057690',shoe_crawler='rbxassetid://83709153435888',shoe_detention='rbxassetid://79078837149254',shoe_ghosthost='rbxassetid://139475266924514',shoe_mallrat='rbxassetid://107490512588808',shoe_nightshift='rbxassetid://100516496936674',shoe_partyanimal='rbxassetid://118098682139759',shoe_pumpkinking='rbxassetid://113401688043865',tat_bellhop='rbxassetid://72045087584900',tat_captain='rbxassetid://120869470404940',tat_crawler='rbxassetid://126931308297717',tat_detention='rbxassetid://106855370039355',tat_ghosthost='rbxassetid://102820627374702',tat_mallrat='rbxassetid://90580888140823',tat_nightshift='rbxassetid://113792510026477',tat_partyanimal='rbxassetid://81206457224782',tat_pumpkinking='rbxassetid://83133490341479',title_pumpkinking='rbxassetid://92035985082406',torch_candle='rbxassetid://128381538311866',torch_glowstick='rbxassetid://81728812899475',torch_lantern='rbxassetid://80817556852413',torch_pumpkin='rbxassetid://101192039362866',trail_coins='rbxassetid://94447484207736',trail_ectoplasm='rbxassetid://131470802620035',trail_glitter='rbxassetid://107343148299082',trail_hearts='rbxassetid://77374275795107',trail_pumpkinseeds='rbxassetid://72586990526160',trail_sparks='rbxassetid://111078932656224',trail_speed='rbxassetid://110501653534836'}do C.OfferImages[id]=image end
for id,image in {tat_bellhop='rbxassetid://95526566430675',tat_captain='rbxassetid://93610899668642',tat_crawler='rbxassetid://93086005524441',tat_detention='rbxassetid://71118552420277',tat_ghosthost='rbxassetid://121452432725629',tat_mallrat='rbxassetid://132992695482956',tat_nightshift='rbxassetid://114921236846347',tat_partyanimal='rbxassetid://102351237546089',tat_pumpkinking='rbxassetid://96205167407280'}do C.TattooDecals[id]=image end
-- Rank rewards show their rank's emblem as their icon.
for id,image in {rank_title_wanderer='rbxassetid://117221761960815',aura_rank_wanderer='rbxassetid://117221761960815',aura_rank_seeker='rbxassetid://96286290779818',aura_rank_veteran='rbxassetid://118826806657251',rank_title_survivor='rbxassetid://128361757271495',aura_rank_survivor='rbxassetid://128361757271495',
 rank_title_seeker='rbxassetid://96286290779818',trail_rank_seeker='rbxassetid://96286290779818',rank_title_explorer='rbxassetid://118278577656838',aura_rank_explorer='rbxassetid://118278577656838',
 rank_title_veteran='rbxassetid://118826806657251',trail_rank_veteran='rbxassetid://118826806657251',rank_title_phantom='rbxassetid://138671406178072',aura_rank_phantom='rbxassetid://138671406178072',
 rank_title_legend='rbxassetid://89890387013145',aura_rank_legend='rbxassetid://89890387013145',trail_rank_legend='rbxassetid://89890387013145'}do C.OfferImages[id]=C.OfferImages[id]or image end
-- Token cosmetics v2 (2026-10-22): new meshes and new icons for every token cosmetic except the Bat Wings; names and
-- descriptions follow the new models.
do
 local V2={hat_tophat={82086461779835,nil,'A tall glossy top hat with a purple band and a moon charm.'},
  hat_witch={131457102496555,nil,'A crooked purple witch hat with a curled tip and a gold buckle.',{150,100,230}},
  hat_propeller={118188056363535,nil,'A teal, yellow and purple beanie with a spinning propeller.',{120,200,190}},
  hat_cowboy={114373858922414,nil,'A pinched tan cowboy hat with a curled brim.',{215,180,120}},
  hat_durag={102785573915546,nil,'A glossy black satin durag with a knot and long tails.'},
  hat_snapback={137612650900064,nil,'A black cap with a gold brim, worn backwards.'},
  ring_silver={92220622866328,nil,'A polished silver band with a crescent moon and a star.'},
  ring_ruby={96222221412533,'Amethyst Ring','A gold ring with a big violet amethyst.',{170,120,235}},
  ring_bone={103204898346416,nil,'A carved bone ring with a little bone charm.'},
  ring_signet={106233529981051,'Star Signet','A chunky gold signet ring with a raised star.'},
  ring_ghosthost={105973184561714},ring_crawler={83864797969271},ring_partyanimal={83601623795379},
  ring_mallrat={72668660042508,nil,nil,{70,200,190}},ring_captain={133104013813964},
  ring_nightshift={73404161994456,'First Aid Ring'},ring_bellhop={136311235668344,nil,nil,{150,100,220}},ring_detention={111975639162474},
  shoe_sneaker={138807943680475,'Street Sneakers','White runners with electric-blue stripes.',{90,150,255}},
  shoe_rainboot={127114007428755,nil,'Glossy yellow rain boots.'},
  shoe_clown={94452405159335,nil,'Enormous purple clown shoes with a teal toe and big yellow laces.',{150,100,230}},
  shoe_hightop={85216546325859,nil,'Black and white high-tops with a padded collar.'},
  shoe_slides={83115668638415,nil,'Teal slides over white tube socks.'},
  shoe_ghosthost={129901578461393},shoe_crawler={90253177949096},shoe_partyanimal={82128239461111},
  shoe_mallrat={97850690927947,nil,nil,{70,200,190}},shoe_captain={125449012230600},shoe_nightshift={84636423251025},
  shoe_bellhop={86701358029171,nil,nil,{150,100,220}},shoe_detention={138447908956871},
  eyes_tophat={82496534913995},eyes_candle={86014283938587,nil,'A lit candle on each eye stalk.',{120,210,200}},
  back_backpack={138321043714933,nil,'A comfy explorer backpack with a rolled-up mat.',{70,180,170}},
  back_halo={80861227138565},back_jetpack={86153343835555,nil,'A shiny twin-tank jetpack. Purely for looks.',{90,200,200}}}
 for id,v in V2 do C.OfferImages[id]='rbxassetid://'..v[1] end
 for _,o in C.TokenOffers do local v=V2[o.id];if v then o.name=v[2]or o.name;o.description=v[3]or o.description;o.color=v[4]or o.color end end
end
-- Staged token cosmetics (WorldB 2026-10-27; shared host, see World_shared.md): one offer, several looks that change with
-- lifetime progress (no new save field). stages.by: 'rankTier' (RRBestTier, never drops) | 'mastery' (QuestCore
-- q.masteries[stages.mastery].level) | 'highestLevel' (HighestLevel). stages.at[i] = value needed for look i;
-- stages.unlock = value needed to buy (optional). Worn mesh: CosmeticKit[id..'_s'..look]; CosmeticKit[id] (the top look)
-- is the fallback and the showcase look. Other staged offers: append to C.StagedOffers here (before the loop below).
C.StagedOffers={
 {id='hat_rankhelmet',name="Climber's Lamp Helmet",kind='Hat',price=75,color={247,201,62},rarity='epic',
  description='A lamp helmet that rebuilds itself as your best rank rises: dented pot, hard hat, explorer, golden crest.',
  stages={by='rankTier',at={1,3,5,7},names={'Dented Pot','Hard Hat','Explorer','Golden Crest'},
   next={[1]='Survivor',[2]='Explorer',[3]='Phantom'},cue='Unlock'}},
}
for _,o in C.StagedOffers do table.insert(C.TokenOffers,o) end
local function stageValue(st,stats)
 stats=stats or {}
 if st.by=='rankTier'then return stats.rankTier or 1 end
 if st.by=='highestLevel'then return stats.highestLevel or 0 end
 if st.by=='mastery'then return stats.mastery and stats.mastery[st.mastery] or 0 end
 return 0
end
-- Look number (1..#stages.at) worn with these stats; nil for an unstaged offer.
function C.CosmeticStage(offer,stats)
 local st=offer and offer.stages;if not st then return nil end
 local v,n=stageValue(st,stats),1
 for i,need in st.at do if v>=need then n=i end end
 return n
end
-- Why `offer` cannot be bought yet (shop text and the purchase refusal), or nil.
function C.CosmeticLocked(offer,stats)
 local st=offer and offer.stages;if not st or not st.unlock then return nil end
 local v=stageValue(st,stats);if v>=st.unlock then return nil end
 return string.format(st.lockText or 'Locked (%d / %d).',v,st.unlock)
end
-- What the stage rules read, from a reconciled save. Pure: never writes.
function C.StageStats(d)
 if type(d)~='table'then return {rankTier=1,highestLevel=0,mastery={}}end
 local m={};local q=type(d.Quests)=='table'and d.Quests.masteries
 if type(q)=='table'then for id,rec in q do if type(rec)=='table'and type(rec.level)=='number'then m[id]=rec.level end end end
 return {rankTier=d.RRBestTier or 1,highestLevel=d.HighestLevel or 0,mastery=m}
end
-- {[id]=look} for every staged cosmetic in an Equipped table.
function C.Stages(equipped,stats)
 local out={};for _,id in equipped or {} do local o=C.ById and C.ById[id];if o and o.stages then out[id]=C.CosmeticStage(o,stats)end end
 return out
end
C.QuestPropImages={weekly_chest='rbxassetid://83515915547281',candy_corn='rbxassetid://80836839034885'}
for _,offers in {C.TokenOffers,C.RobuxOffers} do for _,offer in offers do offer.image=C.OfferImages[offer.id] end end
C.PremiumCosmetics={
 {id='title_vip',name='Haunted VIP',kind='Title',text='HAUNTED VIP',color={245,205,100}},
 {id='aura_vip',name='Golden Ghost',kind='Aura',color={245,205,100}},
}
for _,cosmetic in wearPremium do table.insert(C.PremiumCosmetics,cosmetic) end
C.ById={};for _,offer in C.TokenOffers do C.ById[offer.id]=offer end
for _,offer in C.PremiumCosmetics do C.ById[offer.id]=offer end
for _,offer in C.RewardCosmetics do C.ById[offer.id]=offer end
-- Robux shop order (owner 2026-10-22): 3 revives first, then 1 revive, the other developer products, then the passes,
-- best-looking first. Every Robux shop (menu, van, lobby showcase) lists offers in this order; unknown ids go last.
local ROBUX_ORDER={'revive_pack_3','revive_token','instant_win','gift_revive','jumpscare_all','tokens_tiny','tokens_small','tokens_handful','tokens_medium','tokens_big','tokens_large','tokens_mega',
 'free_revive','double_speed','infinite_stamina','double_tokens',
 'pass_hat_crown','pass_hat_halo','pass_shoe_rocket','pass_shoe_gold','pass_ring_diamond','pass_tat_galaxy','pass_tat_dragon','vip',
 'flashlight_colors'}
do local rank={};for i,id in ROBUX_ORDER do rank[id]=i end
 local original={};for i,o in C.RobuxOffers do original[o]=i end
 table.sort(C.RobuxOffers,function(a,b)local ra,rb=rank[a.id]or(1000+original[a]),rank[b.id]or(1000+original[b]);return ra<rb end)
end
-- One-time token top-ups for players who bought the old, smaller token packs (owner 2026-10-27): userId -> {id=unique
-- receipt id, tokens=n}. ProgressService grants each once on join (stored in PurchaseReceipts).
C.TokenPackTopUps={
 [1827913225]={id='packtopup_20261027_1827913225',tokens=300}, -- Hazul: 2x the old 100-token pack (2026-10-25) -> 250 now: +150 each
}
C.RobuxById={};C.Products={};for _,offer in C.RobuxOffers do C.RobuxById[offer.id]=offer;if offer.kind=='Product'then C.Products[offer.assetId]=offer end end
-- Retired sales stay in ById so existing owned/equipped saves remain compatible.
-- Token titles stay retired; the six token auras are sold again (2026-10-22: each has its own look now and they are on the lobby showcase).
local offers={};for _,o in C.TokenOffers do if o.kind~='Title'then table.insert(offers,o)end end;C.TokenOffers=offers
-- Token shop order (owner 2026-10-22): the trails come right after the last aura (Ghost Light); everything else keeps its order.
do local rest,trails={},{};for _,o in C.TokenOffers do if o.kind=='Trail'then table.insert(trails,o)else table.insert(rest,o)end end
 local out={};for _,o in rest do table.insert(out,o);if o.id=='aura_ghost'then for _,t in trails do table.insert(out,t)end;trails={}end end
 for _,t in trails do table.insert(out,t)end;C.TokenOffers=out
end
-- Token prices x1.5 (owner, 2026-10-22: cosmetics were too cheap), rounded to 5 tokens.
-- Live token price = catalog base x COSMETIC_PRICE_SCALE, rounded to 5 (2026-10-24 owner: 1.5 -> 4, rewards made them too easy).
local COSMETIC_PRICE_SCALE=4
for _,o in C.TokenOffers do if type(o.price)=='number' and o.price>0 then o.price=math.floor(o.price*COSMETIC_PRICE_SCALE/5+.5)*5 end end
C.Purchasable={};for _,o in C.TokenOffers do C.Purchasable[o.id]=true end
return C
