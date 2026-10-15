-- Map identity and physical scale are selected once per server, independently.
local R=require(script.Parent.Rules)
local Profiles={}
Profiles.Kinds={'Mansion','Dungeon','Birthday','Mall','Cruise','Hospital','Hotel','School'}
Profiles.MallAreaMultiplier=1.85
Profiles.MallHorizontalScale=math.sqrt(Profiles.MallAreaMultiplier)
Profiles.Sizes={'Compact','Small','Medium','Large'}
Profiles.KindSizes={Cruise={'Small','Medium','Large'}}
Profiles.Scale={
 -- width/outer bound the footprint; f1/f2 are target non-hall rooms per floor,
 -- stairs the guaranteed vertical routes (+ chance of a second), loops extra room doors.
 -- Footprints grew with the wider rooms (was 92/60, 96/64, 100/68, 108/72; then 100/64..116/76).
 -- 2026-10-04: ~38% wider for really big rooms; bigger size classes stay bigger.
 Compact={width=136,outer=88,splits=2,f1=9,f2=6,stairs=2,secondStair=0,loops=2,halls=4},
 Small={width=144,outer=94,splits=2,f1=10,f2=6,stairs=2,secondStair=0,loops=3,halls=4},
 Medium={width=152,outer=100,splits=2,f1=11,f2=7,stairs=3,secondStair=0,loops=3,halls=5},
 Large={width=164,outer=108,splits=2,f1=12,f2=8,stairs=3,secondStair=0,loops=4,halls=5},
}
local function colors(w,d,t) return {wall=Color3.fromRGB(unpack(w)),wood=Color3.fromRGB(unpack(d)),trim=Color3.fromRGB(unpack(t))} end
local stoneMap={Wall='StoneWall',WallDoor='StonePortal',WallWindow='StoneVent',Floor='StoneFloor',Ceiling='StoneCeiling',StairStep='StoneStep',Landing='StoneLanding',Door='IronDoor',Table='StoneTable',Counter='StoneCounter',Bed='StoneBed',Bookshelf='BoneShelf',Wardrobe='CageLocker'}
local partyMap={Wall='PartyWall',WallDoor='PartyPortal',WallWindow='PartyWindow',Floor='PartyFloor',Ceiling='PartyCeiling',Door='PartyDoor',Table='PartyTable',Chair='PartyChair',Wardrobe='ToyLocker',Bed='PartyBed'}
local mallMap={Wall='MallWall',WallDoor='MallPortal',WallWindow='MallWindow',Floor='MallFloor',Ceiling='MallCeiling',StairStep='MallStep',Landing='MallLanding',Door='MallDoor',Table='MallTable',Chair='MallChair',Counter='MallCounter',Shelf='MallShelf',Bookshelf='MallRack',Wardrobe='MallLocker',Sofa='MallBench',Lamp='MallLamp',Desk='MallKiosk',Crate='MallCrate',Dresser='MallDisplay',Nightstand='MallCounter',Billiard='MallTable'}
local cruiseMap={Wall='CruiseWall',WallDoor='CruisePortal',WallWindow='CruiseWindow',Floor='CruiseFloor',Ceiling='CruiseCeiling',StairStep='CruiseStep',Landing='CruiseLanding',Door='CruiseDoor',Table='CruiseTable',Chair='CruiseChair',Counter='CruiseCounter',Shelf='CruiseShelf',Bookshelf='CruiseShelf',Wardrobe='CruiseLocker',Sofa='CruiseBench',Bed='CruiseBed',Lamp='CruiseLamp',Desk='CruiseDesk',Crate='CruiseCrate',Dresser='CruiseDisplay',Nightstand='CruiseCounter',Billiard='CruiseTable'}
local hotelMap={Wall='HotelWall',WallDoor='HotelPortal',WallWindow='HotelWindow',Floor='HotelFloor',Ceiling='HotelCeiling',StairStep='HotelStep',Landing='HotelLanding',Door='HotelDoor',Table='HotelTable',Chair='HotelChair',Counter='HotelCounter',Shelf='HotelShelf',Bookshelf='HotelShelf',Wardrobe='HotelWardrobe',Sofa='HotelSofa',Bed='HotelBed',Lamp='HotelLamp',Desk='HotelDesk',Crate='HotelTrunk',Dresser='HotelDresser',Nightstand='HotelNightstand',Billiard='HotelTable',Sink='HotelSink',Toilet='HotelToilet',Bathtub='HotelBathtub',Stove='HotelStove',Piano='HotelPiano',Board='HotelBoard'}
local hospitalMap={Wall='HospitalWall',WallDoor='HospitalPortal',WallWindow='HospitalWindow',Floor='HospitalFloor',Ceiling='HospitalCeiling',StairStep='HospitalStep',Landing='HospitalLanding',Door='HospitalDoor',Table='HospitalTable',Chair='HospitalChair',Counter='HospitalCounter',Shelf='HospitalShelf',Bookshelf='HospitalShelf',Wardrobe='HospitalLocker',Sofa='HospitalBench',Bed='HospitalBed',Lamp='HospitalLamp',Desk='HospitalDesk',Crate='HospitalCrate',Dresser='HospitalDisplay',Nightstand='HospitalCounter',Billiard='HospitalTable'}
-- School has its own shell and furniture (School* templates); a few rare pieces (nurse's cot, gym bench, lamp) share the hospital's.
local schoolMap={Wall='SchoolWall',WallDoor='SchoolPortal',WallWindow='SchoolWindow',Floor='SchoolFloor',Ceiling='SchoolCeiling',StairStep='SchoolStep',Landing='SchoolLanding',Door='SchoolDoor',Table='SchoolTable',Chair='SchoolChair',Counter='SchoolCounter',Shelf='SchoolShelf',Bookshelf='SchoolShelf',Wardrobe='SchoolLocker',Sofa='HospitalBench',Bed='HospitalBed',Lamp='HospitalLamp',Desk='SchoolDesk',Crate='HospitalCrate',Dresser='HospitalDisplay',Nightstand='SchoolCounter',Billiard='SchoolTable'}
Profiles.TemplateMaps={Hotel=hotelMap,Cruise=cruiseMap,Hospital=hospitalMap,School=schoolMap}
local hotelThemes={colors({103,94,88},{65,48,38},{160,137,93}),colors({85,107,102},{52,64,60},{144,142,113}),colors({114,95,103},{69,48,58},{167,143,109})}
local hospitalThemes={colors({114,129,121},{77,91,84},{138,148,130}),colors({105,123,130},{69,83,89},{135,144,142}),colors({130,119,110},{87,75,70},{153,143,125})}
local schoolThemes={colors({150,140,104},{96,84,68},{132,132,120}),colors({116,140,124},{82,92,84},{128,134,126}),colors({150,116,104},{92,74,66},{136,128,118})}
local cruiseThemes={colors({94,109,116},{74,57,42},{154,132,83}),colors({108,126,122},{63,75,72},{151,151,128}),colors({124,111,105},{78,53,49},{154,133,104})}
local mallThemes={colors({119,126,111},{72,82,77},{144,133,101}),colors({100,119,119},{60,77,76},{133,144,127}),colors({130,117,104},{83,74,68},{158,143,106})}
local dungeonThemes={colors({112,119,106},{64,69,60},{68,58,43}),colors({105,115,119},{59,65,69},{66,60,49}),colors({124,114,99},{69,61,51},{75,60,43})}
local partyThemes={colors({82,43,69},{57,36,52},{159,126,55}),colors({38,65,79},{33,45,57},{164,111,64}),colors({80,61,43},{64,45,37},{143,77,90})}
local purpose={
 Hotel={Foyer='Lobby',Parlor='Guest Lounge',Dining='Restaurant',Kitchen='Kitchen',Pantry='Pantry',Storage='Housekeeping',Laundry='Laundry',Servants='Staff Quarters',Library='Reading Lounge',Study='Manager\'s Office',Music='Piano Lounge',Ballroom='Ballroom',Gallery='Portrait Gallery',Conservatory='Winter Garden',Bedroom='Guest Room',Master='Suite',Bath='Spa',Nursery='Family Suite',Playroom='Games Room',Sewing='Linen Room',AtticStorage='Luggage Room',Hall='Corridor',Stair='Hotel Stair'},
 School={Foyer='Front Office',Parlor='Teachers Lounge',Dining='Cafeteria',Kitchen='Cafeteria Kitchen',Pantry='Supply Closet',Storage='Janitor Closet',Laundry='Boiler Room',Servants='Nurse\'s Office',Library='Library',Study='Principal\'s Office',Music='Music Room',Ballroom='Gymnasium',Gallery='Art Room',Conservatory='Science Lab',Bedroom='Classroom',Master='Classroom',Bath='Restroom',Nursery='Kindergarten',Playroom='Classroom',Sewing='Computer Lab',AtticStorage='Lost and Found',Hall='Hallway',Stair='Stairwell'},
 Hospital={Foyer='Reception',Parlor='Reception',Dining='Staff Room',Kitchen='Staff Room',Pantry='Pharmacy',Storage='Morgue',Laundry='Staff Room',Servants='Staff Room',Library='Records',Study='Pharmacy',Music='X-Ray',Ballroom='Operating Theatre',Gallery='Ward',Conservatory='Chapel',Bedroom='Ward',Master='Isolation',Bath='Washroom',Nursery='Ward',Playroom='Ward',Sewing='X-Ray',AtticStorage='Records',Hall='Corridor',Stair='Hospital Stair'},
 Cruise={Foyer='Grand Atrium',Parlor='Grand Atrium',Dining='Dining Saloon',Kitchen='Galley',Pantry='Galley',Storage='Engine Room',Laundry='Laundry',Servants='Crew Quarters',Library='Library',Study='Purser Office',Music='Lounge',Ballroom='Theater',Gallery='Promenade',Conservatory='Promenade',Bedroom='Cabin',Master='Suite',Bath='Spa',Nursery='Kids Club',Playroom='Kids Club',Sewing='Laundry',AtticStorage='Engine Room',Hall='Promenade',Stair='Ship Stair'},
 Mall={Foyer='Mall Entrance',Parlor='Department Store',Dining='Food Court',Kitchen='Food Court Kitchen',Pantry='Concession Stockroom',Storage='Janitor Closet',Laundry='Maintenance Room',Servants='Staff Break Room',Library='Bookstore',Study='Security Office',Music='Arcade',Ballroom='Anchor Store',Gallery='Shopping Concourse',Conservatory='Indoor Garden',Bedroom='Clothing Store',Master='Boutique',Bath='Restroom',Nursery='Toy Store',Playroom='Children Store',Sewing='Tailor Shop',AtticStorage='Stockroom',Hall='Abandoned Concourse',Stair='Mall Stair'},
 Dungeon={Foyer='Sealed Entrance',Parlor='Guard Chamber',Dining='Feasting Hall',Kitchen='Rotting Scullery',Pantry='Larder',Storage='Supply Vault',Laundry='Infested Vat Room',Servants='Guard Barracks',Library='Forbidden Archives',Study='Alchemist Study',Music='Ritual Chamber',Ballroom='Sacrificial Hall',Gallery='Relic Gallery',Conservatory='Fungal Garden',Bedroom='Prison Cell',Master='Warden Quarters',Bath='Drain Chamber',Nursery='Brood Incubator',Playroom='Hatchery',Sewing='Experiment Workshop',AtticStorage='Ossuary',Hall='Stone Passage',Stair='Dungeon Stair'},
 Birthday={Foyer='Birthday Reception',Parlor='Parents Lounge',Dining='Cake Room',Kitchen='Candy Kitchen',Pantry='Treat Pantry',Storage='Gift Storage',Laundry='Cleanup Room',Servants='Staff Break Room',Library='Story Room',Study='Party Office',Music='Music Stage',Ballroom='Birthday Hall',Gallery='Prize Gallery',Conservatory='Balloon Garden',Bedroom='Sleepover Room',Master='Birthday Suite',Bath='Restroom',Nursery='Doll Nursery',Playroom='Play Zone',Sewing='Costume Room',AtticStorage='Decoration Store',Hall='Party Corridor',Stair='Birthday Stair'},
}
Profiles.Recipe={
 Hotel={Foyer={'Counter','Sofa','Chair','Dresser','Lamp'},Parlor={'Sofa','Table','Dresser','Lamp'},Dining={'Table','Chair','Chair','Counter','Lamp'},Library={'Bookshelf','Bookshelf','Desk','Chair','Lamp'},Music={'Piano','Chair','Table','Dresser','Lamp'},Ballroom={'Piano','Table','Chair','Chair','Lamp'},Gallery={'Sofa','Table','Bookshelf','Lamp'},Study={'Desk','Chair','Dresser','Bookshelf','Lamp'},Conservatory={'Table','Chair','Sofa','Lamp'},Bedroom={'Bed','Nightstand','Nightstand','Dresser','Wardrobe','Lamp'},Master={'Bed','Nightstand','Nightstand','Dresser','Wardrobe','Lamp'},Nursery={'Bed','Nightstand','Dresser','Wardrobe','Lamp'},Playroom={'Table','Chair','Crate','Dresser','Lamp'},Kitchen={'Stove','Counter','Counter','Sink','Table','Lamp'},Pantry={'Shelf','Crate','Lamp'},Storage={'Shelf','Crate','Dresser','Lamp'},Laundry={'Sink','Counter','Shelf','Table','Lamp'},Servants={'Bed','Nightstand','Dresser','Wardrobe','Lamp'},Bath={'Bathtub','Sink','Toilet','Counter','Lamp'},Sewing={'Desk','Chair','Shelf','Lamp'},AtticStorage={'Shelf','Crate','Crate','Table','Lamp'},Hall={},Stair={}},
 School={Foyer={'Counter','Chair','Lamp'},Parlor={'Sofa','Table','Counter','Lamp'},Dining={'Table','Chair','Chair','Counter','Lamp'},Kitchen={'Counter','Counter','Sink','Table','Lamp'},Pantry={'Shelf','Crate','Lamp'},Storage={'Shelf','Crate','Sink','Lamp'},Laundry={'Shelf','Crate','Counter','Lamp'},Servants={'Bed','Counter','Dresser','Wardrobe','Lamp'},Library={'Bookshelf','Bookshelf','Table','Chair','Lamp'},Study={'Desk','Chair','Dresser','Bookshelf','Lamp'},Music={'Piano','Chair','Chair','Lamp'},Ballroom={'Sofa','Crate','Lamp'},Gallery={'Table','Chair','Shelf','Lamp'},Conservatory={'Table','Counter','Shelf','Lamp'},Bedroom={'Desk','Chair','Bookshelf','Lamp'},Master={'Desk','Chair','Bookshelf','Lamp'},Playroom={'Desk','Chair','Bookshelf','Lamp'},Nursery={'Table','Chair','Chair','Crate','Lamp'},Bath={'Sink','Toilet','Lamp'},Sewing={'Desk','Desk','Chair','Lamp'},AtticStorage={'Shelf','Crate','Crate','Lamp'}},
 Hospital={Foyer={'Counter','Chair','Lamp'},Parlor={'Sofa','Table','Dresser','Lamp'},Dining={'Table','Chair','Chair','Counter','Lamp'},Library={'Bookshelf','Bookshelf','Desk','Chair','Lamp'},Music={'Counter','Table','Dresser','Lamp'},Ballroom={'Bed','Counter','Dresser','Lamp'},Gallery={'Sofa','Table','Bookshelf','Lamp'},Study={'Desk','Chair','Dresser','Lamp'},Conservatory={'Table','Chair','Sofa','Lamp'},Bedroom={'Bed','Nightstand','Dresser','Wardrobe','Lamp'},Master={'Bed','Nightstand','Dresser','Wardrobe','Lamp'},Nursery={'Bed','Dresser','Wardrobe','Lamp'},Playroom={'Table','Chair','Crate','Dresser','Lamp'},Kitchen={'Counter','Counter','Sink','Table','Lamp'},Pantry={'Shelf','Crate','Lamp'},Storage={'Shelf','Crate','Counter','Lamp'},Laundry={'Sink','Counter','Shelf','Table','Lamp'},Servants={'Bed','Nightstand','Dresser','Wardrobe','Lamp'},Bath={'Sink','Toilet','Counter','Lamp'},Sewing={'Desk','Chair','Shelf','Lamp'},AtticStorage={'Shelf','Crate','Crate','Table','Lamp'}},
 Cruise={Foyer={'Sofa','Table','Chair','Lamp'},Parlor={'Sofa','Table','Dresser','Lamp'},Dining={'Table','Chair','Chair','Counter','Lamp'},Library={'Bookshelf','Bookshelf','Desk','Chair','Lamp'},Music={'Sofa','Table','Chair','Counter','Dresser','Lamp'},Ballroom={'Table','Chair','Chair','Lamp'},Gallery={'CruiseDeckChair','Sofa','Table','Lamp','Bookshelf'},Study={'Desk','Chair','Dresser','Lamp'},Conservatory={'CruiseDeckChair','Table','Chair','Sofa','Lamp'},Bedroom={'Bed','Nightstand','Dresser','Wardrobe','Lamp'},Master={'Bed','Nightstand','Dresser','Wardrobe','Sofa','Lamp'},Nursery={'Bed','Dresser','Wardrobe','Lamp'},Playroom={'Table','Chair','Crate','Dresser','Lamp'},Kitchen={'Counter','Counter','Sink','Table','Lamp'},Pantry={'Shelf','Crate','Lamp'},Storage={'Shelf','Crate','Counter','Lamp'},Laundry={'Sink','Counter','Shelf','Table','Lamp'},Servants={'Bed','Nightstand','Dresser','Wardrobe','Lamp'},Bath={'Sink','Toilet','Counter','Lamp'},Sewing={'Desk','Chair','Shelf','Lamp'},AtticStorage={'Shelf','Crate','Crate','Table','Lamp'}},
 Mall={Foyer={'Table','Chair','Lamp'},Parlor={'Counter','Bookshelf','Lamp','Dresser'},Dining={'Table','Chair','Chair','Counter','Lamp'},Library={'Bookshelf','Bookshelf','Desk','Lamp'},Music={'Counter','Chair','Lamp','Dresser'},Ballroom={'Counter','Bookshelf','Lamp','Table'},Gallery={'Table','Chair','Lamp','Bookshelf'},Study={'Desk','Chair','Dresser','Lamp'},Conservatory={'Table','Chair','Lamp'},Bedroom={'Counter','Dresser','Wardrobe','Lamp'},Master={'Counter','Dresser','Wardrobe','Lamp'},Nursery={'Table','Dresser','Wardrobe','Lamp'},Playroom={'Table','Chair','Crate','Lamp','Dresser'},Kitchen={'Counter','Counter','Sink','Table','Lamp'},Pantry={'Shelf','Lamp'},Storage={'Shelf','Crate','Lamp'},Laundry={'Sink','Counter','Shelf','Lamp','Table'},Servants={'Bed','Nightstand','Dresser','Wardrobe','Lamp'},Bath={'Sink','Toilet','Lamp','Counter'},Sewing={'Desk','Chair','Shelf','Lamp'},AtticStorage={'Shelf','Crate','Crate','Table','Lamp'}},
 Dungeon={Parlor={'Table','Chair','Dresser','Lamp'},Music={'Table','Chair','Bookshelf','Lamp'},Ballroom={'Table','Chair','Crate','Lamp'},Gallery={'Bookshelf','Table','Lamp'},Conservatory={'Table','MushroomCluster','OrganicPod','Lamp'},Kitchen={'Stove','Counter','Sink','Lamp'},Bath={'Sink','Counter','Lamp'},Nursery={'Bed','Dresser','Wardrobe','Lamp'},Playroom={'Table','OrganicPod','MushroomCluster','Lamp'}},
 Birthday={Music={'Piano','Chair','BalloonCluster','Lamp','Dresser'},Ballroom={'Table','Chair','Chair','GiftStack','Lamp'},Gallery={'Table','GiftStack','ToyClown','Lamp'},Conservatory={'Table','BalloonCluster','GiftStack','Lamp'},Playroom={'Table','Chair','ToyClown','GiftStack','Lamp'},Nursery={'Bed','Dresser','Wardrobe','ToyClown','Lamp'}},
}
Profiles.Decor={School={'SchoolStudentDesk','SchoolDeskTipped','SchoolChalkboard','SchoolLockerBank'},Hotel={'HotelLuggageCart','HotelArmchair','HotelPlant','HotelGrandfatherClock'},Hospital={'HospitalWheelchair','HospitalGurney','HospitalIVStand','HospitalCurtain'},Cruise={'CruiseLifebuoy','CruiseDeckChair','CruiseLuggageCart','CruiseWheel'},Mall={'MallPlanter','MallMannequin','MallVending','MallArcade','MallCart','MallWetSign','MallTrash'},Dungeon={'MushroomCluster','WebNest','BonePile','OrganicPod'},Birthday={'BalloonCluster','GiftStack','ToyClown','PartyBanner'}}
for _,list in ipairs({dungeonThemes,partyThemes}) do for _,theme in ipairs(list) do
 theme.templates=if list==dungeonThemes then stoneMap else partyMap
 theme.wallMaterial=if list==dungeonThemes then Enum.Material.Slate else Enum.Material.Plaster
 theme.woodMaterial=if list==dungeonThemes then Enum.Material.Slate else Enum.Material.Wood
 theme.trimMaterial=if list==dungeonThemes then Enum.Material.CorrodedMetal else Enum.Material.Wood
 table.insert(R.Themes,theme)
end end
for _,theme in ipairs(mallThemes) do
 theme.templates=mallMap;theme.wallMaterial=Enum.Material.Plaster
 theme.woodMaterial=Enum.Material.SmoothPlastic;theme.trimMaterial=Enum.Material.Metal
 table.insert(R.Themes,theme)
end
for _,theme in ipairs(cruiseThemes) do
 theme.templates=cruiseMap;theme.wallMaterial=Enum.Material.Plaster
 theme.woodMaterial=Enum.Material.Wood;theme.trimMaterial=Enum.Material.Metal
 table.insert(R.Themes,theme)
end
for _,theme in ipairs(hospitalThemes) do
 theme.templates=hospitalMap;theme.wallMaterial=Enum.Material.Plaster
 theme.woodMaterial=Enum.Material.SmoothPlastic;theme.trimMaterial=Enum.Material.Metal
 table.insert(R.Themes,theme)
end
local schoolThemeFirst=#R.Themes+1
for _,theme in ipairs(schoolThemes) do
 theme.templates=schoolMap;theme.wallMaterial=Enum.Material.Plaster
 theme.woodMaterial=Enum.Material.SmoothPlastic;theme.trimMaterial=Enum.Material.Metal
 table.insert(R.Themes,theme)
end
local hotelThemeFirst=#R.Themes+1
for _,theme in ipairs(hotelThemes) do
 theme.templates=hotelMap;theme.wallMaterial=Enum.Material.Plaster
 theme.woodMaterial=Enum.Material.Wood;theme.trimMaterial=Enum.Material.Metal
 table.insert(R.Themes,theme)
end
-- Cruise has three physical sizes; Compact is the Small compatibility alias.
function Profiles.NormalizeSize(kind,size)
 return if kind=='Cruise' and size=='Compact' then 'Small' else size
end
function Profiles.Select(seed,forceKind,forceSize)
 local rng=Random.new(seed+18031)
 assert(not forceKind or table.find(Profiles.Kinds,forceKind),'unknown map kind')
 assert(not forceSize or Profiles.Scale[forceSize],'unknown map size')
 local kind=forceKind or Profiles.Kinds[rng:NextInteger(1,#Profiles.Kinds)]
 local sizes=Profiles.KindSizes[kind] or Profiles.Sizes
 local size=forceSize or sizes[rng:NextInteger(1,#sizes)]
 return kind,Profiles.NormalizeSize(kind,size)
end
function Profiles.Apply(plan,kind,size)
 plan.mapKind=kind;plan.sizeClass=Profiles.NormalizeSize(kind,size)
 local rng=Random.new(plan.seed+18181)
 for _,room in ipairs(plan.rooms) do
  room.purpose=(purpose[kind] and purpose[kind][room.type]) or room.type
  if kind=='Hotel' and plan.sizeClass=='Large' and room.type=='Servants' then room.purpose='Linen Room' end
  room.theme=if kind=='Dungeon' then rng:NextInteger(5,7) elseif kind=='Birthday' then rng:NextInteger(8,10) elseif kind=='Mall' then rng:NextInteger(11,13) elseif kind=='Cruise' then rng:NextInteger(14,16) elseif kind=='Hotel' then rng:NextInteger(hotelThemeFirst,hotelThemeFirst+2) elseif kind=='Hospital' then rng:NextInteger(17,19) elseif kind=='School' then rng:NextInteger(schoolThemeFirst,schoolThemeFirst+2) else rng:NextInteger(1,4)
 end
 return plan
end
-- Keep promenade seating in its intended room purpose (no slot machines: content maturity, 2026-10-07).
-- School: classrooms fill with rows of student desks (some knocked over) and a chalkboard; other rooms get the odd
-- toppled desk. Hall lockers are added by SchoolDressing; hiding lockers come from the Wardrobe entries below.
local classroom={Bedroom=true,Master=true,Playroom=true,Nursery=true,Sewing=true,Conservatory=true,Gallery=true,Music=true,Library=true}
local function schoolDecor(plan,room)
 local kit=game:GetService('ServerStorage').MapKit
 local out={}
 if not kit:FindFirstChild('SchoolStudentDesk') then return out end
 if room and classroom[room.type] then
  for _=1,2 do table.insert(out,'SchoolChalkboard') end
  for _=1,9 do table.insert(out,'SchoolStudentDesk') end
  for _=1,3 do table.insert(out,'SchoolDeskTipped') end
 elseif room and room.type~='Bath' then table.insert(out,'SchoolDeskTipped');table.insert(out,'SchoolStudentDesk') end
 if room and room.name~=plan.start and room.type~='Stair' then table.insert(out,'Wardrobe');table.insert(out,'Wardrobe') end
 return out
end
function Profiles.GetDecor(plan,room)
 if plan.mapKind=='School' then return schoolDecor(plan,room) end
 local list=Profiles.Decor[plan.mapKind] or {}
 local out={}
 for _,name in ipairs(list)do
  if (plan.mapKind=='Hospital' or plan.mapKind=='Hotel') and not game:GetService('ServerStorage').MapKit:FindFirstChild(name) then continue end
  if plan.mapKind~='Cruise' or (name~='CruiseSlot' and name~='CruiseDeckChair') then table.insert(out,name) end
 end
 if plan.mapKind=='Hotel' and room and room.type=='Master' then table.insert(out,'Sofa') end
 -- Mall and Cruise rooms are mostly shop/cabin types without bedroom wardrobes: give every regular room
 -- two optional hiding lockers (each still needs free wall space, so they never block required furniture).
 if (plan.mapKind=='Mall' or plan.mapKind=='Cruise' or plan.mapKind=='Hospital' or plan.mapKind=='Hotel') and room and room.name~=plan.start and room.type~='Stair' then
  table.insert(out,'Wardrobe');table.insert(out,'Wardrobe')
 end
 return out
end
function Profiles.GetRecipe(plan,room)
 if plan.mapKind=='Hotel' and plan.sizeClass=='Large' and room.type=='Servants' then return {'Shelf','Counter','Dresser','Wardrobe','Lamp'} end
 if plan.mapKind=='Mansion' and room.type=='Foyer' then return {'Sofa','Chair','Lamp'} end
 return (Profiles.Recipe[plan.mapKind] and Profiles.Recipe[plan.mapKind][room.type]) or R.Types[room.type].recipe
end
return Profiles


