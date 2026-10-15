-- Authored module library for the socket generator. Footprints, sockets and
-- pacing metadata are data; Builder turns placed rectangles into MapKit walls.
-- Sizes are {alongEntryWall, depth} in studs (multiples of 4); widened by 4 for roomier spaces.
local M={}
M.HallWidth=16
M.DoorWidth=8
-- Straight halls: room slots every 12 studs down both long sides, open ends.
M.Halls={
 {id='Hall24',length=24,weight=.9},
 {id='Hall36',length=36,weight=1.4},
 {id='Hall48',length=48,weight=.9},
 {id='Junction',length=16,weight=.55,junction=true},
}
function M.Slots(length)
 local t={};for i=0,length/12-1 do table.insert(t,-length/2+6+12*i) end;return t
end
M.Foyer={w=36,d=28}
-- Two-floor stair module in its local frame: entry face is local West (-X),
-- centre at the origin, lower floor at y=0. Geometry matches the original
-- authored stair bay (two flights, two landings, upper floor patch).
M.Stair={
 size=24,
 socketT=-6, -- opening centre along the entry face (whole studs keep walls on the grid)
 socketWidth=9,
 nav={lower={-8,0},upper={-6,0}},
 upperPatch={x=-7.6,w=8.8},
}
do
 local w={{-8,0,-9},{0,0,-9},{0,0,-6}}
 for i=1,12 do table.insert(w,{0,i*2/3,-6+i}) end
 table.insert(w,{4,8,9});table.insert(w,{8,8,6})
 for i=1,12 do table.insert(w,{8,8+i*2/3,6-i}) end
 table.insert(w,{4,16,-9});table.insert(w,{-8,16,-9})
 M.Stair.waypoints=w
end
-- Room types. danger/visibility/hiding/loot/spawn feed pacing and the AI;
-- they never script encounters directly.
M.Rooms={
 Parlor={floors={[0]=true},sizes={{32,24},{36,24},{36,28}},weight=1.2,max=3,danger=.35,visibility=.7,hiding=.5,loot=.5,spawn=.5},
 Library={floors={[0]=true},sizes={{36,24},{40,28}},weight=1,max=2,danger=.5,visibility=.4,hiding=.6,loot=.7,spawn=.6,search=.8},
 Study={floors={[0]=true},sizes={{32,24},{32,28}},weight=.9,max=2,danger=.4,visibility=.5,hiding=.4,loot=.7,spawn=.4},
 Music={floors={[0]=true},sizes={{36,24},{36,28}},weight=.8,max=1,danger=.5,visibility=.6,hiding=.3,loot=.5,spawn=.5},
 Ballroom={floors={[0]=true},sizes={{44,28},{40,32}},weight=.7,max=1,danger=.7,visibility=.9,hiding=.2,loot=.4,spawn=.7,chase=.9},
 Gallery={floors={[0]=true},sizes={{40,24},{44,24}},weight=.8,max=2,danger=.6,visibility=.8,hiding=.2,loot=.6,spawn=.6,chase=.8},
 Conservatory={floors={[0]=true},sizes={{36,28},{40,28}},weight=.6,max=1,exterior=true,danger=.5,visibility=.7,hiding=.4,loot=.4,spawn=.5},
 Laundry={floors={[0]=true},sizes={{32,24},{36,24}},weight=.7,max=1,danger=.5,visibility=.4,hiding=.5,loot=.4,spawn=.6},
 Servants={floors={[0]=true},sizes={{36,24},{36,28}},weight=.7,max=2,danger=.5,visibility=.4,hiding=.7,loot=.5,spawn=.6},
 Storage={floors={[0]=true,[1]=true},sizes={{28,24},{32,24}},weight=.6,max=2,danger=.6,visibility=.3,hiding=.6,loot=.8,spawn=.7,search=.9},
 Pantry={floors={[0]=true},sizes={{28,24},{32,24}},weight=.4,max=1,danger=.5,visibility=.3,hiding=.4,loot=.6,spawn=.5},
 Bedroom={floors={[1]=true},sizes={{36,24},{36,28},{40,28}},weight=1.6,max=4,danger=.4,visibility=.5,hiding=.9,loot=.6,spawn=.4},
 Bath={floors={[1]=true},sizes={{32,24},{36,24}},weight=.8,max=2,deadEndOnly=true,danger=.6,visibility=.4,hiding=.3,loot=.3,spawn=.3},
 Sewing={floors={[1]=true},sizes={{32,24},{32,28}},weight=.7,max=1,danger=.5,visibility=.5,hiding=.4,loot=.6,spawn=.5},
 AtticStorage={floors={[1]=true},sizes={{32,24},{36,28}},weight=.7,max=2,danger=.7,visibility=.3,hiding=.7,loot=.8,spawn=.8,search=.9},
 -- Suite members are placed through M.Suites only.
 Dining={floors={[0]=true},sizes={{40,28},{44,28}},weight=0,max=1,suite=true,danger=.4,visibility=.8,hiding=.3,loot=.5,spawn=.4},
 Kitchen={floors={[0]=true},sizes={{40,28},{44,28},{40,32}},weight=0,max=1,suite=true,danger=.6,visibility=.5,hiding=.5,loot=.6,spawn=.6},
 Master={floors={[1]=true},sizes={{40,28},{44,28}},weight=0,max=1,suite=true,danger=.5,visibility=.5,hiding=.8,loot=.8,spawn=.4},
 Nursery={floors={[1]=true},sizes={{36,24},{36,28}},weight=0,max=1,suite=true,danger=.8,visibility=.4,hiding=.6,loot=.5,spawn=.6},
 Playroom={floors={[1]=true},sizes={{36,24},{36,28}},weight=0,max=1,suite=true,danger=.7,visibility=.5,hiding=.6,loot=.6,spawn=.6},
}
-- Required spaces: guaranteed by the generator, never left to weighting.
M.Suites={
 {primary='Dining',secondary='Kitchen',floor=0,minDepth=2},
 {primary='Master',secondary='Bath',floor=1,minDepth=1},
 {primary='Nursery',secondary='Playroom',floor=1,minDepth=1},
}
return M