-- Owner 2026-10-26: medium dailies x2, hard dailies x2.5, weeklies x2 targets (the log was cleared in an hour).
-- Owner 2026-10-26: quest token rewards halved (quests made tokens too easy); mastery ladders unchanged.
-- Pure quest definitions. Persistence and remotes are owned by ProgressService/QuestService.
-- Events must already be qualified, deduped and provenance-filtered by their server owners.
-- Scholar accepts the 104 reachable loot types; the existing 76-item tier V target and earned rewards stay unchanged.
-- MaxDistinct=128 deliberately covers 104 Scholar ids; saved definitions are migrated additively by QuestCore.
-- Map/boat weekly definitions require explicit capabilities; default excludes them.
-- Cosmetic entitlement entries must ship to all servers before any reward grant is enabled.
-- noDeath/noPartyDeath filters require explicit server booleans; missing qualification must fail closed.
local M = {
	Version = 1,
	Daily = {
		{
			id = "d_retrieve_s",
			text = "Sell 8 loot items with your team",
			hint = "Sell at the van; team sales count for everyone",
			icon = "pickup",
			target = 8,
			reward = { tokens = 20, revives = 0 },
			event = "ItemSold",
			metric = "count",
			mode = "count",
			filters = {},
			difficulty = "easy"
		},
		{
			id = "d_sell_s",
			text = "Sell $400 of loot with your team",
			hint = "Sell at the van; team sales count for everyone",
			icon = "selling",
			target = 400,
			reward = { tokens = 20, revives = 0 },
			event = "ItemSold",
			metric = "value",
			mode = "count",
			filters = {},
			difficulty = "easy"
		},
		{
			id = "d_pickup_s",
			text = "Pick up 15 loot items",
			hint = "Grab level loot; regrabbing an item does not count",
			icon = "pickup",
			target = 15,
			reward = { tokens = 20, revives = 0 },
			event = "ItemPickup",
			metric = "count",
			mode = "count",
			filters = {},
			difficulty = "easy"
		},
		{
			id = "d_hide_s",
			text = "Hide in a closet 3 times",
			hint = "Stay in a closet for 3 seconds, then leave safely",
			icon = "hiding",
			target = 3,
			reward = { tokens = 20, revives = 0 },
			event = "ClosetHide",
			metric = "count",
			mode = "count",
			filters = {},
			difficulty = "easy"
		},
		{
			id = "d_toy_s",
			text = "Try 3 different lobby toys",
			hint = "Grab 3 different toys from the lobby tables",
			icon = "pickup",
			target = 3,
			reward = { tokens = 15, revives = 0 },
			event = "LobbyToyGrab",
			metric = "itemId",
			mode = "distinct",
			filters = {},
			difficulty = "easy"
		},
		{
			id = "d_clear_m",
			text = "Finish 2 levels",
			hint = "Sell enough loot, then return to the van to finish",
			icon = "no_death",
			target = 4,
			reward = { tokens = 30, revives = 0 },
			event = "LevelCleared",
			metric = "count",
			mode = "count",
			filters = {},
			difficulty = "medium"
		},
		{
			id = "d_retrieve_m",
			text = "Sell 20 loot items with your team",
			hint = "Bring loot back and sell it at the van",
			icon = "pickup",
			target = 40,
			reward = { tokens = 30, revives = 0 },
			event = "ItemSold",
			metric = "count",
			mode = "count",
			filters = {},
			difficulty = "medium"
		},
		{
			id = "d_key_m",
			text = "Open a locked room",
			hint = "Locked doors need a key from the same floor",
			icon = "locked_room",
			target = 2,
			reward = { tokens = 30, revives = 0 },
			event = "DoorUnlocked",
			metric = "count",
			mode = "count",
			filters = {},
			difficulty = "medium"
		},
		{
			id = "d_escape_m",
			text = "Escape the monster 2 times",
			hint = "Lose the monster after a chase of at least 5 seconds",
			icon = "chase",
			target = 4,
			reward = { tokens = 30, revives = 0 },
			event = "ChaseEscaped",
			metric = "count",
			mode = "count",
			filters = {},
			difficulty = "medium"
		},
		{
			id = "d_curse_m",
			text = "Trigger 5 different cursed item effects",
			hint = "Trigger effects from different cursed item types",
			icon = "pickup",
			target = 10,
			reward = { tokens = 30, revives = 0 },
			event = "GrabUse",
			metric = "itemId",
			mode = "distinct",
			filters = {},
			difficulty = "medium"
		},
		{
			id = "d_party_m",
			text = "Finish a level with a teammate",
			hint = "Finish the level with at least one teammate",
			icon = "party",
			target = 2,
			reward = { tokens = 35, revives = 0 },
			event = "LevelCleared",
			metric = "count",
			mode = "count",
			filters = { minPartySize = 2 },
			difficulty = "medium",
			alternative = {
				id = "d_party_m_solo",
				text = "Finish 2 levels by yourself",
				hint = "Sell enough loot, then return to the van; play solo",
				icon = "no_death",
				target = 4,
				reward = { tokens = 35, revives = 0 },
				event = "LevelCleared",
				metric = "count",
				mode = "count",
				filters = {},
				difficulty = "medium"
			}
		},
		{
			id = "d_clear_h",
			text = "Finish 4 levels",
			hint = "Sell enough loot, then return to the van to finish",
			icon = "no_death",
			target = 10,
			reward = { tokens = 45, revives = 0 },
			event = "LevelCleared",
			metric = "count",
			mode = "count",
			filters = {},
			difficulty = "hard"
		},
		{
			id = "d_sell_h",
			text = "Sell $2,500 of loot with your team",
			hint = "Sell valuable loot; all team sales help",
			icon = "selling",
			target = 6250,
			reward = { tokens = 45, revives = 0 },
			event = "ItemSold",
			metric = "value",
			mode = "count",
			filters = {},
			difficulty = "hard"
		},
		{
			id = "d_nodeath_h",
			text = "Finish a level without dying",
			hint = "Sell enough loot and return to the van without dying",
			icon = "no_death",
			target = 1,
			reward = { tokens = 45, revives = 0 },
			event = "LevelCleared",
			metric = "count",
			mode = "count",
			filters = { noDeath = true },
			difficulty = "hard"
		},
		{
			id = "d_secret_h",
			text = "Find a hidden treasure",
			hint = "Explore hidden spaces and collect secret treasure",
			icon = "secrets",
			target = 3,
			reward = { tokens = 45, revives = 0 },
			event = "SecretFound",
			metric = "count",
			mode = "count",
			filters = {},
			difficulty = "hard"
		},
		{
			id = "d_team_h",
			text = "Finish a level with everyone surviving",
			hint = "Finish the level without anyone on your team dying",
			icon = "party",
			target = 3,
			reward = { tokens = 45, revives = 0 },
			event = "LevelCleared",
			metric = "count",
			mode = "count",
			filters = { minPartySize = 2, noPartyDeath = true },
			difficulty = "hard",
			alternative = {
				id = "d_team_h_solo",
				text = "Finish a level without dying",
				hint = "Finish a solo level without dying",
				icon = "no_death",
				target = 3,
				reward = { tokens = 45, revives = 0 },
				event = "LevelCleared",
				metric = "count",
				mode = "count",
				filters = { noDeath = true },
				difficulty = "hard"
			}
		},
		{
			id = "d_quota_h",
			text = "Meet quota with 30 seconds to spare",
			hint = "Meet quota with at least 30 seconds left",
			icon = "selling",
			target = 3,
			reward = { tokens = 45, revives = 0 },
			event = "QuotaMet",
			metric = "count",
			mode = "count",
			filters = { minTimeLeft = 30 },
			difficulty = "hard"
		}
	},
	Weekly = {
		{
			id = "w_retrieve",
			text = "Sell 120 loot items with your team",
			hint = "Sell cursed loot at the van throughout the week",
			icon = "pickup",
			target = 250,
			reward = { tokens = 100, revives = 0 },
			event = "ItemSold",
			metric = "count",
			mode = "count",
			filters = {}
		},
		{
			id = "w_sell",
			text = "Sell $15,000 of loot with your team",
			hint = "Sell valuable loot; all team sales help",
			icon = "selling",
			target = 30000,
			reward = { tokens = 110, revives = 0 },
			event = "ItemSold",
			metric = "value",
			mode = "count",
			filters = {}
		},
		{
			id = "w_clear",
			text = "Finish 15 levels",
			hint = "Sell enough loot, then return to the van to finish",
			icon = "no_death",
			target = 30,
			reward = { tokens = 110, revives = 0 },
			event = "LevelCleared",
			metric = "count",
			mode = "count",
			filters = {}
		},
		{
			id = "w_deep",
			text = "Reach and finish level 6 in one run",
			hint = "Keep one run going until you clear level 6",
			icon = "achievements",
			target = 12,
			reward = { tokens = 125, revives = 0 },
			event = "LevelCleared",
			metric = "level",
			mode = "max",
			filters = {}
		},
		{
			id = "w_maps",
			text = "Finish levels in 4 different map types",
			hint = "Finish different map types this week",
			icon = "maps",
			target = 4, -- 4 of the 5 map types (2026-10-27; was 8 of 8)
			reward = { tokens = 110, revives = 0 },
			event = "LevelCleared",
			metric = "mapKind",
			mode = "distinct",
			filters = {},
			capability = "maps"
		},
		{
			id = "w_map_cruise",
			text = "Finish 3 Cruise levels",
			hint = "Clear Cruise levels; first claim earns a hat",
			icon = "maps",
			target = 6,
			reward = { tokens = 90, revives = 0 },
			event = "LevelCleared",
			metric = "count",
			mode = "count",
			filters = { mapKind = "Cruise" },
			capability = "maps"
		},
		{
			id = "w_map_hospital",
			text = "Finish 3 Hospital levels",
			hint = "Clear Hospital levels; first claim earns a hat",
			icon = "maps",
			target = 6,
			reward = { tokens = 90, revives = 0 },
			event = "LevelCleared",
			metric = "count",
			mode = "count",
			filters = { mapKind = "Hospital" },
			capability = "maps"
		},
		{
			id = "w_escape",
			text = "Escape the monster 12 times",
			hint = "Lose the monster after chases of at least 5 seconds",
			icon = "chase",
			target = 24,
			reward = { tokens = 100, revives = 0 },
			event = "ChaseEscaped",
			metric = "count",
			mode = "count",
			filters = {}
		},
		{
			id = "w_keys",
			text = "Open 6 locked rooms",
			hint = "Use matching floor keys to open locked rooms",
			icon = "locked_room",
			target = 12,
			reward = { tokens = 100, revives = 0 },
			event = "DoorUnlocked",
			metric = "count",
			mode = "count",
			filters = {}
		},
		{
			id = "w_teamclear",
			text = "Finish 4 levels with everyone surviving",
			hint = "Finish the level without anyone on your team dying",
			icon = "party",
			target = 8,
			reward = { tokens = 110, revives = 0 },
			event = "LevelCleared",
			metric = "count",
			mode = "count",
			filters = { minPartySize = 2, noPartyDeath = true },
			alternative = {
				id = "w_teamclear_solo",
				text = "Finish 4 levels without dying",
				hint = "Finish solo levels without dying",
				icon = "no_death",
				target = 8,
				reward = { tokens = 110, revives = 0 },
				event = "LevelCleared",
				metric = "count",
				mode = "count",
				filters = { noDeath = true }
			}
		},
		{
			id = "w_party",
			text = "Finish 5 levels with at least 3 players",
			hint = "Finish the level with at least 3 players in your team",
			icon = "party",
			target = 10,
			reward = { tokens = 120, revives = 0 },
			event = "LevelCleared",
			metric = "count",
			mode = "count",
			filters = { minPartySize = 3 },
			alternative = {
				id = "w_party_solo",
				text = "Finish 5 levels by yourself",
				hint = "Finish solo levels; separate runs count",
				icon = "no_death",
				target = 10,
				reward = { tokens = 120, revives = 0 },
				event = "LevelCleared",
				metric = "count",
				mode = "count",
				filters = {}
			}
		},
	},
	Achievements = {
		{
			id = "collector",
			name = "Sell Loot",
			text = "Sell Loot",
			hint = "Sell at the van; team sales count for everyone",
			icon = "pickup",
			event = "ItemSold",
			metric = "count",
			mode = "count",
			targets = { 50, 250, 1000, 3000, 10000 },
			rewards = {
				{ tokens = 50, revives = 0 },
				{ tokens = 100, revives = 0 },
				{ tokens = 200, revives = 0 },
				{ tokens = 300, revives = 0 },
				{ tokens = 500, revives = 0 }
			},
			title = "CURSED COLLECTOR",
			titleId = "quest_title_collector",
			filters = {}
		},
		{
			id = "survivor",
			name = "Finish Levels",
			text = "Finish Levels",
			hint = "Sell enough loot, then return to the van to finish",
			icon = "no_death",
			event = "LevelCleared",
			metric = "count",
			mode = "count",
			targets = { 10, 50, 150, 400, 1000 },
			rewards = {
				{ tokens = 50, revives = 0 },
				{ tokens = 100, revives = 0 },
				{ tokens = 200, revives = 0 },
				{ tokens = 300, revives = 0 },
				{ tokens = 500, revives = 0 }
			},
			title = "SEASONED SURVIVOR",
			titleId = "quest_title_survivor",
			filters = {}
		},
		{
			id = "deep_diver",
			name = "Reach Higher Levels",
			text = "Reach Higher Levels",
			hint = "Clear higher levels in one run to beat your best",
			icon = "achievements",
			event = "LevelCleared",
			metric = "level",
			mode = "max",
			targets = { 3, 5, 8, 12, 20 },
			rewards = {
				{ tokens = 50, revives = 0 },
				{ tokens = 120, revives = 0 },
				{ tokens = 220, revives = 0 },
				{ tokens = 350, revives = 0 },
				{ tokens = 600, revives = 0 }
			},
			title = "ABYSS WALKER",
			titleId = "quest_title_deep_diver",
			filters = {}
		},
		{
			id = "tycoon",
			name = "Earn Cash",
			text = "Earn Cash",
			hint = "Sell valuable loot to grow your lifetime cash total",
			icon = "selling",
			event = "ItemSold",
			metric = "value",
			mode = "count",
			targets = { 10000, 50000, 200000, 750000, 2000000 },
			rewards = {
				{ tokens = 50, revives = 0 },
				{ tokens = 100, revives = 0 },
				{ tokens = 200, revives = 0 },
				{ tokens = 300, revives = 0 },
				{ tokens = 500, revives = 0 }
			},
			title = "HAUNTED TYCOON",
			titleId = "quest_title_tycoon",
			filters = {}
		},
		{
			id = "escape_artist",
			name = "Escape Monsters",
			text = "Escape Monsters",
			hint = "Lose the monster after chases of at least 5 seconds",
			icon = "chase",
			event = "ChaseEscaped",
			metric = "count",
			mode = "count",
			targets = { 10, 50, 150, 400, 1000 },
			rewards = {
				{ tokens = 50, revives = 0 },
				{ tokens = 100, revives = 0 },
				{ tokens = 200, revives = 0 },
				{ tokens = 300, revives = 0 },
				{ tokens = 500, revives = 0 }
			},
			title = "UNCATCHABLE",
			titleId = "quest_title_escape_artist",
			filters = {}
		},
		{
			id = "team_player",
			name = "Help Your Team",
			text = "Help Your Team",
			hint = "Extract with teammates or use a revive on a teammate",
			icon = "party",
			event = "LevelCleared",
			metric = "count",
			mode = "count",
			targets = { 5, 25, 75, 200, 500 },
			rewards = {
				{ tokens = 50, revives = 0 },
				{ tokens = 100, revives = 0 },
				{ tokens = 200, revives = 0 },
				{ tokens = 300, revives = 0 },
				{ tokens = 500, revives = 0 }
			},
			title = "GUARDIAN ANGEL",
			titleId = "quest_title_team_player",
			filters = { minPartySize = 2 }
		},
		{
			id = "locksmith",
			name = "Open Locked Rooms",
			text = "Open Locked Rooms",
			hint = "Locked doors need a key from the same floor",
			icon = "locked_room",
			event = "DoorUnlocked",
			metric = "count",
			mode = "count",
			targets = { 5, 25, 75, 200, 500 },
			rewards = {
				{ tokens = 50, revives = 0 },
				{ tokens = 100, revives = 0 },
				{ tokens = 200, revives = 0 },
				{ tokens = 300, revives = 0 },
				{ tokens = 500, revives = 0 }
			},
			title = "MASTER LOCKSMITH",
			titleId = "quest_title_locksmith",
			filters = {}
		},
		{
			id = "treasure_hunter",
			name = "Find Hidden Treasures",
			text = "Find Hidden Treasures",
			hint = "Explore hidden spaces and collect secret treasure",
			icon = "secrets",
			event = "SecretFound",
			metric = "count",
			mode = "count",
			targets = { 3, 10, 30, 75, 200 },
			rewards = {
				{ tokens = 50, revives = 0 },
				{ tokens = 120, revives = 0 },
				{ tokens = 220, revives = 0 },
				{ tokens = 350, revives = 0 },
				{ tokens = 600, revives = 0 }
			},
			title = "TREASURE HUNTER",
			titleId = "quest_title_treasure_hunter",
			filters = {}
		},
		{
			id = "world_traveler",
			name = "Explore Different Maps",
			text = "Explore Different Maps",
			hint = "Finish new map types; repeats do not count",
			icon = "maps",
			event = "LevelCleared",
			metric = "mapKind",
			mode = "distinct",
			targets = { 1, 2, 3, 4, 5 }, -- five map types (2026-10-27)
			rewards = {
				{ tokens = 60, revives = 0 },
				{ tokens = 120, revives = 0 },
				{ tokens = 200, revives = 0 },
				{ tokens = 300, revives = 0 },
				{ tokens = 600, revives = 0 }
			},
			title = "GLOBETROTTER",
			titleId = "quest_title_world_traveler",
			filters = {}
		},
		{
			id = "curse_scholar",
			name = "Try Different Cursed Items",
			text = "Try Different Cursed Items",
			hint = "Grab different cursed item types; repeats do not count",
			icon = "pickup",
			event = "ItemPickup",
			metric = "itemId",
			mode = "distinct",
			targets = { 10, 20, 30, 40, 76 },
			rewards = {
				{ tokens = 60, revives = 0 },
				{ tokens = 120, revives = 0 },
				{ tokens = 200, revives = 0 },
				{ tokens = 300, revives = 0 },
				{ tokens = 600, revives = 0 }
			},
			title = "CURSE SCHOLAR",
			titleId = "quest_title_curse_scholar",
			filters = {},
			eligibleIds = {
				"Doll", "Compass", "Shadow", "Backpack", "Whistle", "Teddy", "Flashlight", "Clock",
				"Coin", "Mask", "Horn", "Present", "Crown", "Clown",
				"Candles", "MusicBox", "Candy", "Bracelet", "Portrait", "Bell", "Telephone", "Vacuum",
				"Shoes", "Keyring", "Lantern", "Jawbone", "Chain", "Heart", "DiscoBall", "Mirror",
				"MagicOrb", "Moustache", "RainCloud", "CoolSunglasses", "FlyJar", "CursedPerfume", "BirthdayHat", "CryingOnion",
				"RedPepper", "HotSauce", "Popsicle", "BeehiveJar", "MakeupKit", "ChewingGum", "VentriloquistDoll", "SnailShell",
				"CoffeeMug", "JawbreakerBag", "HeliumTank", "GarlicBulb", "Lemon", "PinocchioPuppet", "ToothPillow", "ClownNose",
				"VampireTeeth", "Anvil", "Hourglass", "SpinningTop", "BlackCatStatue", "CursedPhoto", "Kazoo", "GlueBottle",
				"PartyPopper", "GuessWhoHands", "FacePlunger", "ClingyTeddy", "CursedHair", "SelfTanner", "MoodRing", "WetFloorSign",
				"MannequinHand", "GiftCard", "ClawPlushie", "MascotHead", "MuzakRadio",
				"SpringyWhisk", "PoutingSugarBowl", "RockingSeahorseToy", "OrbitingAtomModel", "PeekingNestingDoll", "RestlessToyExcavator", "BobbingBirdBath",
				"CrinklyPaperBag", "SleepyMeasuringJug", "TopsyChessRook", "RestlessNutcracker", "SillySatelliteDish", "FidgetCalculator", "FoldingTravelStool",
				"TumblingDominoRack", "RebelliousToyDrum", "WindUpCrabToy", "OrigamiCrane", "DancingMetronome", "ColdIron", "GrumblingPiggyBank",
				"ForgetfulDeskLamp", "NervousSaltShaker", "CreepingTapeMeasure", "SulkingUmbrella", "BackwardsHairdryer", "NoseyMagnifier", "SqueakyDuck"
			},
			collectionVersion = 2
		}
	},
	DailyBonus = {
		id = "daily_bonus",
		hint = "Finish all 3 Today goals, then collect this bonus",
		target = 3,
		reward = { tokens = 25, revives = 1 },
		icon = "daily"
	},
	WeeklyChest = {
		id = "weekly_chest",
		hint = "Finish 4 This Week goals, then collect your chest",
		target = 4,
		reward = { tokens = 150, revives = 2 },
		fallbackTokens = 150,
		icon = "weekly_chest"
	},
	Mastery = {
		id = "mastery",
		hint = "Claim stage 5 of all 10 lifetime goals",
		target = 10,
		reward = { tokens = 10, revives = 0 },
		title = "[Haunted]",
		titleId = "Tag_Haunted",
		kind = "Tag",
		icon = "achievements"
	},
	ResetSeconds = 86400,
	WeekSeconds = 604800,
	MondayOffsetSeconds = 259200,
	GraceSeconds = 600,
	MaxArchivedPeriods = 32,
	MaxDistinct = 128,
	MaxAppliedBatches = 256,
	MaxClaimReceipts = 256,
	ScholarCollectionVersion = 2,
	ScholarEligibleIds = {
		"Doll", "Compass", "Shadow", "Backpack", "Whistle", "Teddy", "Flashlight", "Clock",
		"Coin", "Mask", "Horn", "Present", "Crown", "Clown",
		"Candles", "MusicBox", "Candy", "Bracelet", "Portrait", "Bell", "Telephone", "Vacuum",
		"Shoes", "Keyring", "Lantern", "Jawbone", "Chain", "Heart", "DiscoBall", "Mirror",
		"MagicOrb", "Moustache", "RainCloud", "CoolSunglasses", "FlyJar", "CursedPerfume", "BirthdayHat", "CryingOnion",
		"RedPepper", "HotSauce", "Popsicle", "BeehiveJar", "MakeupKit", "ChewingGum", "VentriloquistDoll", "SnailShell",
		"CoffeeMug", "JawbreakerBag", "HeliumTank", "GarlicBulb", "Lemon", "PinocchioPuppet", "ToothPillow", "ClownNose",
		"VampireTeeth", "Anvil", "Hourglass", "SpinningTop", "BlackCatStatue", "CursedPhoto", "Kazoo", "GlueBottle",
		"PartyPopper", "GuessWhoHands", "FacePlunger", "ClingyTeddy", "CursedHair", "SelfTanner", "MoodRing", "WetFloorSign",
		"MannequinHand", "GiftCard", "ClawPlushie", "MascotHead", "MuzakRadio",
				"SpringyWhisk", "PoutingSugarBowl", "RockingSeahorseToy", "OrbitingAtomModel", "PeekingNestingDoll", "RestlessToyExcavator", "BobbingBirdBath",
				"CrinklyPaperBag", "SleepyMeasuringJug", "TopsyChessRook", "RestlessNutcracker", "SillySatelliteDish", "FidgetCalculator", "FoldingTravelStool",
				"TumblingDominoRack", "RebelliousToyDrum", "WindUpCrabToy", "OrigamiCrane", "DancingMetronome", "ColdIron", "GrumblingPiggyBank",
				"ForgetfulDeskLamp", "NervousSaltShaker", "CreepingTapeMeasure", "SulkingUmbrella", "BackwardsHairdryer", "NoseyMagnifier", "SqueakyDuck"
	},
	MapKinds = { "Hotel", "Hospital", "School", "Manor", "Dungeon" }, -- Mall, Birthday and Cruise left the map pool (owner 2026-10-27)
	RewardCosmetics = {
		{
			id = "quest_title_collector",
			name = "CURSED COLLECTOR",
			kind = "Title",
			text = "CURSED COLLECTOR",
			nonPurchasable = true,
			color = { 230, 204, 140 }
		},
		{
			id = "quest_title_survivor",
			name = "SEASONED SURVIVOR",
			kind = "Title",
			text = "SEASONED SURVIVOR",
			nonPurchasable = true,
			color = { 230, 204, 140 }
		},
		{
			id = "quest_title_deep_diver",
			name = "ABYSS WALKER",
			kind = "Title",
			text = "ABYSS WALKER",
			nonPurchasable = true,
			color = { 230, 204, 140 }
		},
		{
			id = "quest_title_tycoon",
			name = "HAUNTED TYCOON",
			kind = "Title",
			text = "HAUNTED TYCOON",
			nonPurchasable = true,
			color = { 230, 204, 140 }
		},
		{
			id = "quest_title_escape_artist",
			name = "UNCATCHABLE",
			kind = "Title",
			text = "UNCATCHABLE",
			nonPurchasable = true,
			color = { 230, 204, 140 }
		},
		{
			id = "quest_title_team_player",
			name = "GUARDIAN ANGEL",
			kind = "Title",
			text = "GUARDIAN ANGEL",
			nonPurchasable = true,
			color = { 230, 204, 140 }
		},
		{
			id = "quest_title_locksmith",
			name = "MASTER LOCKSMITH",
			kind = "Title",
			text = "MASTER LOCKSMITH",
			nonPurchasable = true,
			color = { 230, 204, 140 }
		},
		{
			id = "quest_title_treasure_hunter",
			name = "TREASURE HUNTER",
			kind = "Title",
			text = "TREASURE HUNTER",
			nonPurchasable = true,
			color = { 230, 204, 140 }
		},
		{
			id = "quest_title_world_traveler",
			name = "GLOBETROTTER",
			kind = "Title",
			text = "GLOBETROTTER",
			nonPurchasable = true,
			color = { 230, 204, 140 }
		},
		{
			id = "quest_title_curse_scholar",
			name = "CURSE SCHOLAR",
			kind = "Title",
			text = "CURSE SCHOLAR",
			nonPurchasable = true,
			color = { 230, 204, 140 }
		},
		{
			id = "Tag_Haunted",
			name = "Haunted",
			kind = "Tag",
			text = "[Haunted]",
			nonPurchasable = true,
			color = { 175, 235, 210 }
		}
	},
	IconKeys = {
		"pickup", "selling", "locked_room", "hiding", "chase", "revive", "secrets", "no_death",
		"maps", "party", "boat", "achievements", "weekly_chest", "daily", "quests"
	},
	DefaultCapabilities = { maps = false, boat = false }
}


M.MapSets={Manor='ghosthost',Dungeon='crawler',Birthday='partyanimal',Mall='mallrat',Cruise='captain',Hospital='nightshift',Hotel='bellhop',School='detention'}
for kind,set in M.MapSets do
 local id='w_map_'..string.lower(kind);local def
 for _,q in M.Weekly do if q.id==id then def=q end end
 if not def then def={id=id,text='Finish 3 '..kind..' levels',hint='Clear '..kind..' levels; first claim earns a hat',icon='maps',target=3,reward={tokens=180,revives=0},event='LevelCleared',metric='count',mode='count',filters={mapKind=kind},capability='maps'};table.insert(M.Weekly,def) end
 if set=='detention'then def.firstReward=nil;def.hint='Clear '..kind..' levels' -- the Dunce Cap was retired (owner 2026-10-28)
 else def.firstReward={cosmeticIds={'hat_'..set}}end
end
local extras={collector={[4]='trail_glitter'},survivor={[4]='torch_candle'},deep_diver={[4]='torch_lantern'},tycoon={[3]='eyes_monocle'},escape_artist={[4]='trail_speed',[5]='eyes_ghostflame'},team_player={[4]='trail_hearts'},locksmith={[4]='eyes_spider'},treasure_hunter={[4]='trail_coins'},world_traveler={[5]='back_globetrotter'},curse_scholar={[5]='aura_collector'}}
for _,def in M.Achievements do for tier,id in extras[def.id] or {} do def.rewards[tier].cosmeticIds={id} end end
M.WeeklyChest.exclusiveIds={'eyes_goggles','back_ghostbuddy','torch_glowstick'}
M.WeeklyChest.exclusiveChance=5
M.Event={id='halloween_2026',quests={
 {id='e_carve',hint="Find pumpkins in levels and carve their glowing faces",text='Carve 5 jack-o-lanterns',icon='pickup',target=5,event='PumpkinCarved',reward={candyCorn=80}},
 {id='e_escape',hint="Lose the monster after long chases during Halloween",text='Escape 10 Halloween chases',icon='chase',target=10,event='ChaseEscaped',filters={eventOnly=true},reward={candyCorn=120,cosmeticIds={'eyes_pumpkin'}}},
 {id='e_head',hint="Search levels for the Horseman's flaming head",text='Find the Horseman head',icon='secrets',target=1,event='HorsemanHeadFound',reward={candyCorn=150,cosmeticIds={'hat_pumpkinking'}}},
 {id='e_clear',hint="Meet quota and extract while Halloween is active",text='Clear 10 levels during Halloween',icon='maps',target=10,event='LevelCleared',reward={candyCorn=150}},
 {id='e_treasure',hint="Find hidden Halloween treasures in mission levels",text='Find 8 event treasures',icon='secrets',target=8,event='EventTreasureFound',reward={candyCorn=120,cosmeticIds={'torch_pumpkin'}}},
 {id='e_collect',hint="Grab new loot objects during Halloween missions",text='Collect 25 cursed items during Halloween',icon='pickup',target=25,event='ItemPickup',reward={candyCorn=100}},
 },shop={{id='ring_pumpkinking',cost=100},{id='tat_pumpkinking',cost=120},{id='shoe_pumpkinking',cost=150},{id='aura_pumpkinking',cost=180},{id='trail_pumpkinseeds',cost=150}},
 finale={target=6,reward={cosmeticIds={'title_pumpkinking'}}}}

-- Masteries: lifetime ladders, one per monster (escape its chases) and one for collecting loot. Ten levels each;
-- every level pays MasteryLevelReward the moment it is reached, level 10 also pays MasteryCompleteReward.
-- The first MasteryDailyBoost mastery points of every UTC day count double, so each new day moves the bars faster.
M.MasteryLevelReward={tokens=25,revives=0}
M.MasteryCompleteReward={tokens=0,revives=1}
M.MasteryDailyBoost=5
local ESCAPES={2,5,9,14,20,27,35,45,56,70}
M.Masteries={
 {id='m_crawler',name='Collar Crawler',kind='monster',creatureKind='Crawler',event='ChaseEscaped',unit='escapes',hint='Survive its chases until it loses you',color={150,210,255},targets=ESCAPES},
 {id='m_wraith',name='Tear Wraith',kind='monster',creatureKind='Wraith',event='ChaseEscaped',unit='escapes',hint='Survive its chases until it loses you',color={200,170,255},targets=ESCAPES},
 {id='m_bellhop',name='Haunted Bellhop',kind='monster',creatureKind='Bellhop',event='ChaseEscaped',unit='escapes',hint='Survive its chases until it loses you',color={255,200,110},targets=ESCAPES},
 {id='m_lantern',name='Lantern Watcher',kind='monster',creatureKind='Lantern',event='ChaseEscaped',unit='escapes',hint='Survive its chases until it loses you',color={255,236,150},targets=ESCAPES},
 {id='m_neon',name='Neon Tripod',kind='monster',creatureKind='Neon',event='ChaseEscaped',unit='escapes',hint='Survive its chases until it loses you',color={120,255,190},targets=ESCAPES},
 {id='m_collector',name='Collector',kind='collection',event='ItemPickup',unit='items',hint='Pick up cursed loot in missions',color={255,170,80},targets={15,40,75,120,180,250,340,450,580,750}},
}
M.GrandMastery={id='grand_mastery',name='Monster Master',hint='Master every monster and the collection',reward={tokens=0,revives=0,cosmeticIds={'title_monstermaster'}}}

M.ById = {}
for _, list in {M.Daily, M.Weekly, M.Achievements} do
 for _, def in list do
  assert(not M.ById[def.id], "Duplicate quest id")
  M.ById[def.id] = def
  if def.alternative then M.ById[def.alternative.id] = def.alternative end
 end
end
for _, def in {M.DailyBonus,M.WeeklyChest,M.Mastery} do M.ById[def.id]=def end
return M
