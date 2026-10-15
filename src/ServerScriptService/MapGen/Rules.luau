local R = {}
R.Grid = 4
R.FloorStep = 16
R.ClearHeight = 14
R.DoorWidth = 8
R.DoorHeight = 10
R.HallWidth = 32
R.LockCount = 3
R.KeyCount = 8 -- one per open room; was 4 (keys felt too rare)
R.KeyScale = 0.55 -- keys drawn 45% smaller than the largest that fits their slot
R.DoorChance = 0.45
R.MaxAttempts = 20
R.BatchSize = 100
R.LightCap = 2
R.Types = {
 Foyer={zone='public',min=64,max=4600,recipe={}},
 Parlor={zone='public',min=400,max=6000,recipe={'Sofa','Table','Lamp','Dresser'}},
 Dining={zone='public',min=400,max=6000,recipe={'Table','Chair','Chair','Counter','Lamp'}},
 Library={zone='public',min=400,max=6000,recipe={'Bookshelf','Bookshelf','Desk','Chair','Lamp'}},
 Music={zone='public',min=400,max=6000,recipe={'Piano','Chair','Lamp','Dresser'}},
 Ballroom={zone='public',min=400,max=6400,recipe={'Piano','Chair','Lamp','Table'}},
 Gallery={zone='public',min=400,max=6000,recipe={'Table','Chair','Lamp','Bookshelf'}},
 Study={zone='public',min=400,max=6000,recipe={'Desk','Chair','Bookshelf','Lamp'}},
 Conservatory={zone='public',min=400,max=6000,exterior=true,recipe={'Table','Chair','Sofa','Lamp'}},
 Kitchen={zone='service',min=400,max=6000,recipe={'Stove','Counter','Counter','Sink','Table','Lamp'}},
 Pantry={zone='service',min=256,max=6000,recipe={'Shelf','Lamp'}},
 Laundry={zone='service',min=400,max=6000,recipe={'Sink','Counter','Shelf','Lamp','Table'}},
 Servants={zone='service',min=400,max=6000,recipe={'Bed','Nightstand','Dresser','Wardrobe','Lamp'}},
 Storage={zone='service',min=256,max=6000,recipe={'Shelf','Crate','Lamp'}},
 Bedroom={zone='private',min=400,max=6000,recipe={'Bed','Nightstand','Nightstand','Dresser','Wardrobe','Lamp'}},
 Master={zone='private',min=400,max=6000,recipe={'Bed','Nightstand','Nightstand','Dresser','Wardrobe','Lamp'}},
 Bath={zone='private',min=400,max=6000,recipe={'Bathtub','Sink','Toilet','Lamp','Counter'}},
 Nursery={zone='private',min=400,max=6000,recipe={'Bed','Dresser','Wardrobe','Lamp'}},
 Playroom={zone='private',min=400,max=6000,recipe={'Table','Chair','Crate','Lamp','Dresser'}},
 Sewing={zone='private',min=400,max=6000,recipe={'Desk','Chair','Shelf','Lamp'}},
 AtticStorage={zone='private',min=400,max=6000,recipe={'Shelf','Crate','Crate','Table','Lamp'}},
 Hall={zone='hall',min=1,max=10000,recipe={}},
 Stair={zone='hall',min=1,max=10000,recipe={}},
}
R.Themes = {
 {wall=Color3.fromRGB(78,65,58),wood=Color3.fromRGB(65,40,29),trim=Color3.fromRGB(147,121,82)},
 {wall=Color3.fromRGB(49,64,57),wood=Color3.fromRGB(55,35,25),trim=Color3.fromRGB(132,112,74)},
 {wall=Color3.fromRGB(74,47,51),wood=Color3.fromRGB(69,40,31),trim=Color3.fromRGB(147,123,86)},
 {wall=Color3.fromRGB(57,60,75),wood=Color3.fromRGB(54,35,26),trim=Color3.fromRGB(139,121,91)},
}
R.Optional = {Ballroom={'Billiard'},Library={'Bookshelf'},Gallery={'Bookshelf'},Storage={'Crate'},AtticStorage={'Crate'},Playroom={'Crate'}}
-- Extra hiding spots: optional wardrobes (closets), only in rooms where a wardrobe makes sense.
-- Optional dressing never displaces required furniture, so it cannot cause rejected seeds.
R.WardrobeChance = 0.5
R.ExtraWardrobes = 1 -- optional wardrobes tried per listed room (each needs free wall space)
R.WardrobeWallSlack = 1.1 -- extra wardrobes stand flush against a wall, never out in the room
R.WardrobeRooms = {Bedroom=true,Master=true,Servants=true,Nursery=true,Storage=true,AtticStorage=true,Laundry=true,Sewing=true,Playroom=true}
for t in pairs(R.WardrobeRooms) do
 R.Optional[t]=R.Optional[t] or {}
 for _=1,R.ExtraWardrobes do table.insert(R.Optional[t],'Wardrobe') end
end
return R