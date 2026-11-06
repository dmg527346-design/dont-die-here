local C={Order={},Items={}}
C.Order[#C.Order+1]="Doll";C.Items["Doll"]={name="Crying doll",map="Any",hint="Cries louder near danger; set it down to bait a creature.",value=20}
C.Order[#C.Order+1]="Compass";C.Items["Compass"]={name="Wrong-way compass",map="Any",hint="Finds keys, but shakes and switches to a nearby monster.",value=20}
C.Order[#C.Order+1]="Shadow";C.Items["Shadow"]={name="Second shadow",map="Any",hint="A delayed shadow scouts danger, but can reveal your location.",value=20}
C.Order[#C.Order+1]="Backpack";C.Items["Backpack"]={name="Hungry backpack",map="Any",hint="Four carrying slots; feed it valuables before it eats them loudly.",value=20}
C.Order[#C.Order+1]="Whistle";C.Items["Whistle"]={name="Emergency whistle",map="Any",hint="Blows when you grab it: stuns the closest creature, but the blast alerts the others.",value=20}
C.Order[#C.Order+1]="Teddy";C.Items["Teddy"]={name="Clingy teddy",map="Any",hint="Survive one grab; re-grab it to pull its arms away from your eyes.",value=20}
C.Order[#C.Order+1]="Flashlight";C.Items["Flashlight"]={name="Haunted flashlight",map="Any",hint="Reveals hidden signs; occasionally shows a false nearby figure.",value=20}
C.Order[#C.Order+1]="Clock";C.Items["Clock"]={name="Alarm clock",map="Any",hint="Shows the next danger pulse; wind it down before it rings.",value=20}
C.Order[#C.Order+1]="Coin";C.Items["Coin"]={name="Sticky lucky coin",map="Any",hint="More treasure; hand it to a friend or wash it off.",value=20}
C.Order[#C.Order+1]="Mask";C.Items["Mask"]={name="Borrowed face",map="Any",hint="Grab it to briefly fool creatures; teammates see your borrowed monster face.",value=20}
-- Balloon: removed from the loot pool (not in C.Order); entry kept for held items and hold poses.
C.Items["Balloon"]={name="Birthday balloon",map="Birthday",hint="Rise to high shelves; drop it to descend.",value=20}
C.Order[#C.Order+1]="Horn";C.Items["Horn"]={name="Never-ending party horn",map="Birthday",hint="Blows when you grab it to distract creatures. Once unrolled it never stops.",value=20}
C.Order[#C.Order+1]="Present";C.Items["Present"]={name="Suspicious present",map="Birthday",hint="Opens when you grab it: treasure, or a crawling follower.",value=20}
C.Order[#C.Order+1]="Cake";C.Items["Cake"]={name="Melting cake",map="Birthday",hint="Valuable intact; rough movement spills frosting and leaves a trail.",value=45,noLoot=true} -- 2026-10-18: out of the loot pool (admin spawn still works)
C.Order[#C.Order+1]="Crown";C.Items["Crown"]={name="Party crown",map="Birthday",hint="Open a party door; creatures try to return you to reception.",value=20}
C.Order[#C.Order+1]="Clown";C.Items["Clown"]={name="Wind-up clown",map="Birthday",hint="Set down and wind to send it away; neglected toys run back screaming.",value=20}
C.Order[#C.Order+1]="Candles";C.Items["Candles"]={name="Trick candles",map="Birthday",hint="Reveal hidden signs; extinguished candles relight unless covered.",value=20}
C.Order[#C.Order+1]="MusicBox";C.Items["MusicBox"]={name="Musical gift box",map="Birthday",hint="Wind continuously to keep nearby creatures calm.",value=20}
C.Order[#C.Order+1]="Candy";C.Items["Candy"]={name="Too-many-teeth candy",map="Birthday",hint="Sprint briefly, then chatter loudly until you wash.",value=20}
C.Order[#C.Order+1]="Bracelet";C.Items["Bracelet"]={name="Friendship bracelet",map="Birthday",hint="Link to a nearby teammate; separation makes both bracelets ring.",value=20}
C.Order[#C.Order+1]="Portrait";C.Items["Portrait"]={name="Judgmental portrait",map="Mansion",hint="Tracks creatures through walls; criticizes careless bumps and drops.",value=20}
C.Order[#C.Order+1]="Bell";C.Items["Bell"]={name="Silver dinner bell",map="Mansion",hint="Ring it beside a locked door: a ghost butler unlocks it, but the ring draws creatures.",value=20}
C.Order[#C.Order+1]="Telephone";C.Items["Telephone"]={name="Antique telephone",map="Mansion",hint="Calls give key clues; a stuttering call may give a false clue.",value=20}
C.Order[#C.Order+1]="Vacuum";C.Items["Vacuum"]={name="Possessed vacuum",map="Mansion",hint="Collect small treasure at range; a loud motor may grab a nearby shoe.",value=20}
C.Order[#C.Order+1]="Shoes";C.Items["Shoes"]={name="Dancing shoes",map="Mansion",hint="Move quietly; nearby cursed music makes you dance.",value=20}
C.Order[#C.Order+1]="Keyring";C.Items["Keyring"]={name="Jailer's keyring",map="Dungeon",hint="Three lock bypasses; grabbing it holds it quiet.",value=20}
C.Order[#C.Order+1]="Lantern";C.Items["Lantern"]={name="Hungry lantern",map="Dungeon",hint="Reveals secret rewards. Crouch while holding it to feed it one nearby item.",value=20}
C.Order[#C.Order+1]="Jawbone";C.Items["Jawbone"]={name="Loose jawbone",map="Dungeon",hint="Chatters near secret signs; grab it with empty hands to keep it quiet.",value=20}
C.Order[#C.Order+1]="Chain";C.Items["Chain"]={name="Prisoner's chain",map="Dungeon",hint="Pull distant loose items toward you; dragging it attracts creatures.",value=20}
C.Order[#C.Order+1]="Heart";C.Items["Heart"]={name="Stone heart",map="Dungeon",hint="Absorbs one lethal grab; a growing heartbeat gives you away.",value=40}
C.Order[#C.Order+1]="DiscoBall";C.Items.DiscoBall={name="Cursed disco ball",map="Any",hint="Hold to bob your head to its rainbow lights and quiet disco music.",value=35}
C.Order[#C.Order+1]="Mirror";C.Items.Mirror={name="Vanity mirror",map="Any",hint="Hold to admire yourself, wink and blow kisses.",value=45}
C.Order[#C.Order+1]="MagicOrb";C.Items.MagicOrb={name="Magic orb",map="Any",hint="Your voice becomes deeper while you hold the orb.",value=50}
C.Order[#C.Order+1]='Moustache';C.Items.Moustache={name='Clingy moustache',map='Any',hint='Hold grab for three seconds to pull it off. Release early and it sticks for five seconds.',value=25}

C.Order[#C.Order+1]='RainCloud';C.Items.RainCloud={name='Crybaby cloud',map='Any',hint='Five seconds of rain and tears. The dehydrated cloud keeps its sale value.',value=40}
C.Order[#C.Order+1]='CoolSunglasses';C.Items.CoolSunglasses={name='Suspiciously cool sunglasses',map='Any',hint='Hold grab for three seconds to pull the shades off. Release early and they stick for five seconds. The cool hat stays this level.',value=40}
C.Order[#C.Order+1]='FlyJar';C.Items.FlyJar={name='Jar of annoying fly',map='Any',hint='Picking it up pops the lid. The glowing fly will not leave you alone this level.',value=35}
C.Order[#C.Order+1]='CursedPerfume';C.Items.CursedPerfume={name='Cursed perfume',map='Any',hint='Automatically spray yourself. A faint pink aura makes nearby teammates whistle this level.',value=45}
C.Order[#C.Order+1]='BirthdayHat';C.Items.BirthdayHat={name='Compulsory party hat',map='Any',hint='Five seconds of birthday hat and an embarrassingly persistent party blower.',value=35}
C.Order[#C.Order+1]='CryingOnion';C.Items.CryingOnion={name='Crying onion',map='Any',hint='Holding it makes you sob uncontrollably. Put it down to stop crying.',value=35}
C.Order[#C.Order+1]='RedPepper';C.Items.RedPepper={name='Red hot pepper',map='Any',hint='Holding it sets your eyes on fire. You will be squinting for the rest of this level.',value=40}
C.Order[#C.Order+1]='HotSauce';C.Items.HotSauce={name='Hot sauce',map='Any',hint='While you hold it, talking makes you breathe fire.',value=40}
C.Order[#C.Order+1]='Popsicle';C.Items.Popsicle={name='Frozen popsicle',map='Any',hint='Brain freeze: frosty eyes and chattering teeth while you hold it.',value=35}
C.Order[#C.Order+1]='BeehiveJar';C.Items.BeehiveJar={name='Beehive jar',map='Any',hint='Bees swarm you while held, and one sting swells an eye for the rest of the level.',value=40}
C.Order[#C.Order+1]='MakeupKit';C.Items.MakeupKit={name='Stage makeup kit',map='Any',hint='Bright red lipstick, huge lashes and a permanent pout until the level ends.',value=45}
C.Order[#C.Order+1]='ChewingGum';C.Items.ChewingGum={name='Bubble gum pack',map='Any',hint='Take a stick, chew, and blow a bubble until it pops loudly.',value=35}
C.Order[#C.Order+1]='VentriloquistDoll';C.Items.VentriloquistDoll={name='Ventriloquist doll',map='Any',hint='Your voice comes out of the doll. Other people make your mouth move.',value=45}
C.Order[#C.Order+1]='SnailShell';C.Items.SnailShell={name='Snail shell',map='Any',hint='Droopy snail eyes and a slow crawl while you hold it.',value=35}
C.Order[#C.Order+1]='CoffeeMug';C.Items.CoffeeMug={name='Black coffee',map='Any',hint='Drink it in one gulp. Your teeth stay stained until the level ends.',value=35}
C.Order[#C.Order+1]='JawbreakerBag';C.Items.JawbreakerBag={name='Jawbreaker bag',map='Any',hint='Crunch away while you hold it. Each crunch breaks a tooth for the rest of the level.',value=40}
-- Item batch 3 (2026-10-01)
C.Order[#C.Order+1]="HeliumTank";C.Items["HeliumTank"]={name="Helium tank",map='Any',hint="Holding it makes your voice squeaky and puffs your body up like a balloon.",value=40}
C.Order[#C.Order+1]="GarlicBulb";C.Items["GarlicBulb"]={name="Garlic bulb",map='Any',hint="You stink while you hold it. Teammates standing close start tearing up.",value=30}
C.Order[#C.Order+1]="Lemon";C.Items["Lemon"]={name="Sour lemon",map='Any',hint="Holding it puckers your whole face and squeezes your eyes shut in waves.",value=30}
C.Order[#C.Order+1]="PinocchioPuppet";C.Items["PinocchioPuppet"]={name="Pinocchio puppet",map='Any',hint="Your nose grows longer the longer you hold it. Drop it and it shrinks back.",value=45}
C.Order[#C.Order+1]="ToothPillow";C.Items["ToothPillow"]={name="Tooth fairy pillow",map='Any',hint="Grab it to lose a tooth. Each tooth makes the pillow worth more, up to 5 teeth.",value=25}
C.Order[#C.Order+1]="ClownNose";C.Items["ClownNose"]={name="Clown nose",map='Any',hint="Grab it to wear a big red nose until the level ends. It honks when you jump.",value=35}
C.Order[#C.Order+1]="VampireTeeth";C.Items["VampireTeeth"]={name="Vampire teeth",map='Any',hint="Grab them to grow fangs, go pale and get glowing red eyes until the level ends.",value=45}
C.Order[#C.Order+1]="Anvil";C.Items["Anvil"]={name="Heavy anvil",map='Any',hint="Worth a fortune, but it is so heavy you crawl along and cannot sprint.",value=120}
C.Order[#C.Order+1]="Hourglass";C.Items["Hourglass"]={name="Upside-down hourglass",map='Any',hint="Holding it slowly turns your whole view upside down.",value=45}
C.Order[#C.Order+1]="SpinningTop";C.Items["SpinningTop"]={name="Spinning top",map='Any',hint="Holding it keeps you slowly turning in circles.",value=35}
C.Order[#C.Order+1]="BlackCatStatue";C.Items["BlackCatStatue"]={name="Black cat statue",map='Any',hint="Grab it and a black cat follows you. Creatures find you faster for the rest of the level.",value=45}
C.Order[#C.Order+1]="CursedPhoto";C.Items["CursedPhoto"]={name="Cursed instant camera",map='Any',hint="Grab it to snap a cursed photo of a teammate. The photo sticks to your stomach.",value=40}
C.Order[#C.Order+1]="Kazoo";C.Items["Kazoo"]={name="Kazoo",map='Any',hint="Holding it turns your voice into a buzzing kazoo for everyone.",value=30}
C.Order[#C.Order+1]="GlueBottle";C.Items["GlueBottle"]={name="Super glue",map='Any',hint="Grab it and it sticks to your hand. You cannot let go for 5 seconds.",value=30,noTutorial=true}
C.Order[#C.Order+1]="PartyPopper";C.Items["PartyPopper"]={name="Party popper",map='Any',hint="Grab it for a burst of confetti. You stay covered in confetti until the level ends.",value=35}
C.Order[#C.Order+1]="GuessWhoHands";C.Items["GuessWhoHands"]={name="Guess-who hands",map='Any',hint="Grab it and two cold hands creep over your eyes. Guess who? Sometimes they let you peek.",value=35}
C.Order[#C.Order+1]="FacePlunger";C.Items["FacePlunger"]={name="Face plunger",map='Any',hint="Grab it and it sticks to your face. A teammate has to pull it off.",value=35,coop=true}
C.Order[#C.Order+1]="ClingyTeddy";C.Items["ClingyTeddy"]={name="Clingy teddy",map='Any',hint="Grab it and it climbs onto your back and whispers. A teammate has to pull it off.",value=35,coop=true}
C.Order[#C.Order+1]="CursedHair";C.Items["CursedHair"]={name="Cursed hair",map='Any',hint="Grab it and it covers your eyes. A teammate has to take it off.",value=35,coop=true}
-- Gear shop items (bought in the van with the team bank). Not in C.Order: never level loot, never sold.
C.Items.Grenade={name='Grenade',map='Any',hint='Press use to throw. It blasts monsters and sends them running. 3 blasts kill a monster.',value=0,gear=true}
C.Items.ProxMine={name='Proximity Grenade',map='Any',hint='Press use to set it down. It goes off when a monster steps on it. 2 blasts kill a monster.',value=0,gear=true}
C.Items.HypnoGun={name='Hypno Gun',map='Any',hint='Press use to shoot. A hit monster forgets everyone and wanders off dazed for 35 seconds. Misses are free. 3 hypnotizes.',value=0,gear=true}
C.Items.MonsterOrb={name='Monster Orb',map='Any',hint='Dropped by a slain monster. Sell it in the van. The monster comes back after 2:30, or right away when the orb is sold.',value=75,reward=true}
C.Items.SlayerGun={name='Monster Slayer',map='Any',hint='Press use to shoot. A hit kills the monster. 3 shots.',value=0,gear=true}
-- Mall collectibles remain eligible in every map; only the two rescue curses require a party.
C.Order[#C.Order+1]='SelfTanner';C.Items.SelfTanner={name='Self-Tanner Bottle',map='Any',hint='Grab it to turn bright orange until the level ends.',value=35}
C.Order[#C.Order+1]='MoodRing';C.Items.MoodRing={name='Mood Ring',map='Any',hint='Your body tint shifts red as monsters get close.',value=35}
C.Order[#C.Order+1]='WetFloorSign';C.Items.WetFloorSign={name='Wet Floor Sign',map='Any',hint='While you hold it, you slide around like ice.',value=35}
C.Order[#C.Order+1]='MannequinHand';C.Items.MannequinHand={name='Mannequin Hand',map='Any',hint='It grips your hand until a teammate pulls it off.',value=35,coop=true}
C.Order[#C.Order+1]='GiftCard';C.Items.GiftCard={name='Gift Card',map='Any',hint='Worth a lot, but its value drains while you hold it.',value=120}
C.Order[#C.Order+1]='ClawPlushie';C.Items.ClawPlushie={name='Claw Machine Plushie',map='Any',hint='It lands on your head until a teammate pulls it off.',value=35,coop=true}
C.Order[#C.Order+1]='MascotHead';C.Items.MascotHead={name='Mascot Head',map='Any',hint='Wear a huge mall mascot head with a muffled voice.',value=35}
C.Order[#C.Order+1]='MuzakRadio';C.Items.MuzakRadio={name='Muzak Radio',map='Any',hint='Elevator music calms nearby creatures but gets louder.',value=35}
C.Items.SkitterTrap={name='Skitter Trap',map='Any',hint='Use while holding to place it on the floor. Catches only the Skitter; other monsters ignore it.',value=0,gear=true}
C.Items.MedKit={name='MedKit',map='Any',hint='Hold it and press your interact key to heal 50 health. Used once.',value=0,gear=true}
C.Items.BigMedKit={name='Big MedKit',map='Any',hint='Hold it and press your interact key to heal 100 health. Used once.',value=0,gear=true}
C.Items.ChirpyDecoy={name='Chirpy Decoy',map='Any',hint='Set it down inside the level: it winds up and chirps for 20 seconds, pulling nearby monsters to it.',value=0,gear=true}
C.Items.DoorWedge={name='Door Wedge',map='Any',hint='Close a door, then set this down right next to it: monsters cannot open it for 45 seconds (or until one bashes through). Opening the door pops the wedge.',value=0,gear=true}
C.Items.CartBeacon={name='Cart Beacon',map='Any',hint='Drop it into the cart: it clips onto the rail, lights the cart and shows it to your whole team through walls for this level.',value=0,gear=true}
C.Items.CartBell={name='Cart Bell',map='Any',hint='Drop it into the cart: it clips onto the handle. Monsters can never steal from a belled cart this level, but it rings every 30 seconds and the monsters come to see.',value=0,gear=true}

-- Approved selected items join the existing equal-ticket loot roster.
C.Order[#C.Order+1]="SpringyWhisk";C.Items["SpringyWhisk"]={name="Springy whisk",hint="Twists your eyes into a whisking stare.",map="Any",value=32,SelectedItem=true}
C.Order[#C.Order+1]="PoutingSugarBowl";C.Items["PoutingSugarBowl"]={name="Pouting sugar bowl",hint="Gives you a heavy pout and a sulky stare.",map="Any",value=37,SelectedItem=true}
C.Order[#C.Order+1]="RockingSeahorseToy";C.Items["RockingSeahorseToy"]={name="Rocking seahorse toy",hint="Rocks your long-necked seahorse pose.",map="Any",value=40,SelectedItem=true}
C.Order[#C.Order+1]="OrbitingAtomModel";C.Items["OrbitingAtomModel"]={name="Restless atom model",hint="Sends your eyes around an imaginary atom.",map="Any",value=47,SelectedItem=true}
C.Order[#C.Order+1]="PeekingNestingDoll";C.Items["PeekingNestingDoll"]={name="Peeking nesting doll",hint="Tucks your head down, then peeks back out.",map="Any",value=43,SelectedItem=true}
C.Order[#C.Order+1]="RestlessToyExcavator";C.Items["RestlessToyExcavator"]={name="Restless toy excavator",hint="Makes your jaw scoop as you lean into a dig.",map="Any",value=49,SelectedItem=true}
C.Order[#C.Order+1]="BobbingBirdBath";C.Items["BobbingBirdBath"]={name="Bobbing birdbath toy",hint="Spreads your grin into a bobbing birdbath basin.",map="Any",value=39,SelectedItem=true}
C.Order[#C.Order+1]="CrinklyPaperBag";C.Items["CrinklyPaperBag"]={name="Crinkly paper bag",hint="Crumples your body and folds your face like paper.",map="Any",value=30,SelectedItem=true}
C.Order[#C.Order+1]="SleepyMeasuringJug";C.Items["SleepyMeasuringJug"]={name="Measuring mug",hint="Makes you nod off, droop your eyelids and yawn.",map="Any",value=35,SelectedItem=true}
C.Order[#C.Order+1]="TopsyChessRook";C.Items["TopsyChessRook"]={name="Topsy-turvy chess rook",hint="Makes you tall and stiff like a chess tower.",map="Any",value=36,SelectedItem=true}
C.Order[#C.Order+1]="RestlessNutcracker";C.Items["RestlessNutcracker"]={name="Restless nutcracker toy",hint="Clacks your jaw with a toy-soldier stare.",map="Any",value=44,SelectedItem=true}
C.Order[#C.Order+1]="SillySatelliteDish";C.Items["SillySatelliteDish"]={name="Daydreaming satellite dish",hint="Turns your eyes into dishes scanning for a signal.",map="Any",value=40,SelectedItem=true}
C.Order[#C.Order+1]="FidgetCalculator";C.Items["FidgetCalculator"]={name="Fidgeting calculator",hint="Taps your eyes above a little display-mouth.",map="Any",value=34,SelectedItem=true}
C.Order[#C.Order+1]="FoldingTravelStool";C.Items["FoldingTravelStool"]={name="Indecisive travel stool",hint="Folds you into a squat, wide-footed stool.",map="Any",value=37,SelectedItem=true}
C.Order[#C.Order+1]="TumblingDominoRack";C.Items["TumblingDominoRack"]={name="Tumbling domino rack",hint="Tips one eye after the other like dominoes.",map="Any",value=43,SelectedItem=true}
C.Order[#C.Order+1]="RebelliousToyDrum";C.Items["RebelliousToyDrum"]={name="Rebellious toy drum",hint="Pumps your drum belly while your eyes keep time.",map="Any",value=40,SelectedItem=true}
C.Order[#C.Order+1]="WindUpCrabToy";C.Items["WindUpCrabToy"]={name="Wind-up crab toy",hint="Gives you crab eyes and broad claw hands.",map="Any",value=41,SelectedItem=true}
C.Order[#C.Order+1]="OrigamiCrane";C.Items["OrigamiCrane"]={name="Restless origami crane",hint="Gives you a thin paper body and folded beak.",map="Any",value=38,SelectedItem=true}
C.Order[#C.Order+1]="DancingMetronome";C.Items["DancingMetronome"]={name="Dancing metronome",hint="Swings your head like a metronome pendulum.",map="Any",value=39,SelectedItem=true}
C.Order[#C.Order+1]="ColdIron";C.Items["ColdIron"]={name="Cold iron",hint="Presses you flat and makes your teeth chatter.",map="Any",value=39,SelectedItem=true}
C.Order[#C.Order+1]="GrumblingPiggyBank";C.Items["GrumblingPiggyBank"]={name="Grumbling piggy bank",hint="Gives you a round piggy body and snout.",map="Any",value=40,SelectedItem=true}
C.Order[#C.Order+1]="ForgetfulDeskLamp";C.Items["ForgetfulDeskLamp"]={name="Forgetful desk lamp",hint="Stretches your neck into a searching desk lamp.",map="Any",value=45,SelectedItem=true}
C.Order[#C.Order+1]="NervousSaltShaker";C.Items["NervousSaltShaker"]={name="Nervous salt shaker",hint="Scrunches your face into a sneeze, then lets go.",map="Any",value=30,SelectedItem=true}
C.Order[#C.Order+1]="CreepingTapeMeasure";C.Items["CreepingTapeMeasure"]={name="Creeping tape measure",hint="Spreads your eyes above a long ruler-mouth.",map="Any",value=44,SelectedItem=true}
C.Order[#C.Order+1]="SulkingUmbrella";C.Items["SulkingUmbrella"]={name="Inside-out umbrella",hint="Huddles you under a droopy, unhappy stare.",map="Any",value=48,SelectedItem=true}
C.Order[#C.Order+1]="BackwardsHairdryer";C.Items["BackwardsHairdryer"]={name="Backwards hairdryer",hint="Blows your eyes and mouth back in the wind.",map="Any",value=46,SelectedItem=true}
C.Order[#C.Order+1]="NoseyMagnifier";C.Items["NoseyMagnifier"]={name="Nosey magnifying glass",hint="Magnifies one eye while the other squints.",map="Any",value=38,SelectedItem=true}
C.Order[#C.Order+1]="SqueakyDuck";C.Items["SqueakyDuck"]={name="Squeaky rubber duck",hint="Gives you a duckbill and wide webbed feet.",map="Any",value=34,SelectedItem=true}
-- Stone cat: what the stray cat becomes when you answer NO (CloseUpChoices). Never normal loot; value set per level.
C.Order[#C.Order+1]="StoneCat";C.Items["StoneCat"]={name="Stone cat statue",map="Any",hint="He was a cat until you said no. Worth a fortune, but the house is angry now.",value=75,noLoot=true}
-- Cracked crystal ball: what the fortune teller leaves when you answer NO (CloseUpChoices). Never normal loot.
C.Order[#C.Order+1]="CrackedCrystalBall";C.Items["CrackedCrystalBall"]={name="Cracked crystal ball",map="Any",hint="It saw your future, then you broke it.",value=25,noLoot=true}
-- Close-up choice drops, second set (CloseUpChoices.ExtraChoices, 2026-10-25). Never normal loot.
C.Order[#C.Order+1]="GoldenRibbon";C.Items["GoldenRibbon"]={name="Golden ribbon",map="Any",hint="A lonely balloon's ribbon. You said no to being its friend.",value=75,noLoot=true}
C.Order[#C.Order+1]="JackInTheBox";C.Items["JackInTheBox"]={name="Unopened jack-in-the-box",map="Any",hint="Do not wind it. Just sell it.",value=45,noLoot=true}
C.Order[#C.Order+1]="Birdcage";C.Items["Birdcage"]={name="Antique birdcage",map="Any",hint="Old and valuable. Something still taps inside.",value=90,noLoot=true}
C.Order[#C.Order+1]="BirthdayCake";C.Items["BirthdayCake"]={name="Birthday cake",map="Any",hint="You took the whole cake. Its candles keep lighting up and singing.",value=100,noLoot=true}
-- Monsters build 2026-10-27 (ItemDrafts_20261026\Monsters). WatchGnome is loot from level 2; TipBell (Bellhop drop) and
-- CuckooClock (omen THE CUCKOO prop) are never normal loot: reward=true gives them a fixed value through SpawnGearItem.
C.Order[#C.Order+1]='WatchGnome';C.Items.WatchGnome={name='Watch Gnome',map='Any',hint='Set it down: it stares Collar Crawlers frozen. Gets sleepy after a while.',value=35,noTutorial=true}
C.Order[#C.Order+1]='TipBell';C.Items.TipBell={name="Bellhop's Tip Bell",map='Any',hint='Left behind by the Bellhop. Worth a lot, but it rings when you run.',value=110,reward=true,noLoot=true}
C.Order[#C.Order+1]='CuckooClock';C.Items.CuckooClock={name='Cuckoo Clock',map='Any',hint='Calls every monster to it once a minute. Grab it to wind it back, or sell it to shut it up.',value=60,reward=true,noLoot=true}
C.Order[#C.Order+1]="PorcelainCat";C.Items["PorcelainCat"]={name="Porcelain cat",map="Any",hint="One of three. It misses its shelf; bring all three home and the shelf turns them gold.",value=8,noLoot=true} -- World/CatShelf (WorldA)
-- Close-up choice NO items (CloseUpChoices.ExtraChoices2, 2026-10-27): never in the loot pool.
C.Order[#C.Order+1]="ShyMailbox";C.Items["ShyMailbox"]={name="Shy mailbox",map="Any",hint="You took the whole mailbox. It is SO heavy: you walk slowly.",value=110,noLoot=true}
C.Order[#C.Order+1]="SleepyLamp";C.Items["SleepyLamp"]={name="Sleepy lamp",map="Any",hint="It ate your flashlight's light. Now it glows a little for you.",value=90,noLoot=true}
C.Order[#C.Order+1]="PadlockKing";C.Items["PadlockKing"]={name="Sleepy padlock",map="Any",hint="The padlock king fell asleep. Shh... his keys still jingle.",value=70,noLoot=true}
-- CursedA build 2026-10-27 (ItemBatch6 / ItemBatch7). firstFind: only the level 1 start-room bonus item (never in the
-- loot bag). mapOnly: spawns only on that MapKind (CursedItemsServer.eligibleItems). treasure / treasureMult: rare
-- treasure placed by a fixed rule from that level on (LootBudget.Treasure, CursedItemsServer.restock); never random/paid.
C.Order[#C.Order+1]="FoamFinger";C.Items["FoamFinger"]={name="Foam finger",map="Any",hint="Grab it and the crowd goes wild. Carry it to the cart!",value=40,firstFind=true}
C.Order[#C.Order+1]="BobbleBuddy";C.Items["BobbleBuddy"]={name="Bobblehead buddy",map="Any",hint="Grab it and your eyes go boing with every step.",value=40,firstFind=true}
C.Order[#C.Order+1]="WobbleJelly";C.Items["WobbleJelly"]={name="Wobbly jelly",map="Any",hint="Grab it and you wobble like jelly until it is in the cart.",value=40,firstFind=true}
C.Order[#C.Order+1]="HiccupBubbleBath";C.Items["HiccupBubbleBath"]={name="Hiccuping bubble bath",map="Any",hint="Its bubbles show nearby monsters through walls. Every so often it hiccups you into a big bubble until a teammate pops it.",value=50,noTutorial=true}
C.Order[#C.Order+1]="PopUpToaster";C.Items["PopUpToaster"]={name="Pop-up toaster",map="Any",hint="Every few seconds it DINGS and pops you and anyone close into the air. The ding startles monsters right next to it.",value=40}
C.Order[#C.Order+1]="HomesickYoyo";C.Items["HomesickYoyo"]={name="Homesick yo-yo",map="Any",hint="Grab it to zip along its string to the nearest teammate. Alone, it bonks you.",value=38}
C.Order[#C.Order+1]="HideyBox";C.Items["HideyBox"]={name="Hidey box",map="Any",hint="Climb in and stand still. Monsters ignore a box. Friends do not.",value=40,noTutorial=true}
C.Order[#C.Order+1]="PocketFogger";C.Items["PocketFogger"]={name="Pocket fog machine",map="Any",hint="Two puffs of party fog. Monsters lose you in it. So does everyone else.",value=45,noTutorial=true}
C.Order[#C.Order+1]="HungryLunchbox";C.Items["HungryLunchbox"]={name="Hungry lunchbox",map="Any",hint="Put it in the cart: every 15 seconds it eats the cheapest item and gains 1.5x its value. Chomping is loud. Starving, it rattles.",value=30,noTutorial=true}
C.Order[#C.Order+1]="DustBunnyBot";C.Items["DustBunnyBot"]={name="Dusty the dust bunny bot",map="Any",hint="A haunted little vacuum. It adopts you: drop loot by your feet and it carries it to the cart. It panics near monsters.",value=40,noTutorial=true}
C.Order[#C.Order+1]="PeekabooSock";C.Items["PeekabooSock"]={name="Peekaboo sock",map="Any",hint="Grab it and the sock ghost rides your shoulder for the level. It whispers when something creeps up behind you.",value=40,noTutorial=true}
C.Order[#C.Order+1]="FoodCourtPager";C.Items["FoodCourtPager"]={name="Food court pager",map="Mall",mapOnly="Mall",hint="It buzzes and tugs you to the Food Court. Get it there before the order is cancelled for a big bonus.",value=40}
C.Order[#C.Order+1]="HallPass";C.Items["HallPass"]={name="Hall pass",map="School",mapOnly="School",hint="Walk the hallways with it and monsters ignore you. Run and the whistle takes it away.",value=30}
C.Order[#C.Order+1]="GildedIdol";C.Items["GildedIdol"]={name="Gilded idol",map="Any",hint="Treasure! The lights die behind it. Keep moving.",value=200,noLoot=true,treasure=3,treasureMult=4}
C.Order[#C.Order+1]="MansionCrown";C.Items["MansionCrown"]={name="Mansion crown",map="Any",hint="Treasure! Every monster wants the head that wears it.",value=300,noLoot=true,treasure=5,treasureMult=5}
-- CursedB build 2026-10-27 (CursedBatchEffects.ItemBatch8 / ItemBatch9).
C.Order[#C.Order+1]='GiggleFeather';C.Items.GiggleFeather={name='Giggle feather',map='Any',hint='Giggle fits while you hold it. Teammates nearby take turns giggling, and every giggle they share makes it worth more.',value=40}
C.Order[#C.Order+1]='TinCanPhone';C.Items.TinCanPhone={name='Tin can telephone',map='Any',hint='Grabbing it unspools a second can. Hold one each: a monster near one can rings the other. Too far apart and the string snaps. Both cans in the cart sell for more.',value=50}
C.Order[#C.Order+1]='SnoringSuitcase';C.Items.SnoringSuitcase={name='Snoring suitcase',map='Any',hint='So heavy you crawl, and it snores while you carry it alone. A teammate with empty hands at the end handle helps you carry it, and it falls asleep.',value=90}
C.Order[#C.Order+1]='PumpkinGrin';C.Items.PumpkinGrin={name="Nervous jack-o'-lantern",map='Any',hint='Its carved face shows how close the monsters are. When it panics it shrieks: crouch to cover its mouth.',value=45,event='Halloween',noTutorial=true}
C.Order[#C.Order+1]='TreatSack';C.Items.TreatSack={name='Trick-or-treat sack',map='Any',hint='Fills with candy while you walk: more value, but every candy makes you slower. Hand it to a friend.',value=35,event='Halloween',noTutorial=true}
C.Order[#C.Order+1]='PuppetCross';C.Items.PuppetCross={name='Puppet strings',map='Any',hint='Grab it to string the nearest monster: it only moves when you move. Sprint and the strings snap.',value=44,noTutorial=true}
C.Order[#C.Order+1]='PogoSpring';C.Items.PogoSpring={name='Pogo spring',map='Any',hint='Every step is a BOING. Crouch to plant it and stay quiet.',value=38}
C.Order[#C.Order+1]='RunawayToiletPaper';C.Items.RunawayToiletPaper={name='Runaway toilet paper',map='Any',hint='Unrolls behind you while held. The trail sticks to shoes and tangles monsters, but every stud of paper lowers its value.',value=45}
C.Order[#C.Order+1]='SnowGlobe';C.Items.SnowGlobe={name='Haunted snow globe',map='Any',hint="Grab it and you're inside the globe. Running shakes it into a whiteout. Something is looking in.",value=42}
C.Order[#C.Order+1]='SongbirdMusicBox';C.Items.SongbirdMusicBox={name='Songbird music box',map='Any',hint="Treasure! Keep it wound. A friend's grab winds it full.",value=230,noLoot=true,treasure=4,treasureMult=4}
C.Order[#C.Order+1]='TrailEraser';C.Items.TrailEraser={name='Big pink eraser',map='Any',hint='Grab it mid-chase to rub yourself out of their memory. Rubs out your map too.',value=38,noTutorial=true}
C.Order[#C.Order+1]='XRayLightBox';C.Items.XRayLightBox={name='Toy x-ray light box',map='Hospital',mapOnly='Hospital',hint='See monsters through the walls around you. Every few seconds its flash shows them you.',value=45}
C.Order[#C.Order+1]='CartMagnet';C.Items.CartMagnet={name='Lovesick magnet',map='Any',hint='The cart has a crush on it. Hold it and the cart rolls after you, loudly.',value=40}
C.Order[#C.Order+1]='PullbackRacer';C.Items.PullbackRacer={name='Pull-back racer',map='Any',hint='Stand still and it winds up. Take a step and it ZOOMS you.',value=42,noTutorial=true}
C.Order[#C.Order+1]="LullabyRecord";C.Items["LullabyRecord"]={name="Lullaby record",map="Any",hint="A music-box lullaby on a black record. Put it on the gramophone and every monster dozes off.",value=10,noLoot=true} -- World/LullabyGramophone (WorldB)
return C
