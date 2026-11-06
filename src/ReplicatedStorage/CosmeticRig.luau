-- Single owner of how wearable cosmetics attach to the creature rig. Used by ProgressService (live characters)
-- and MainMenuClient (ViewportFrame preview). Templates: ReplicatedStorage.CosmeticKit[id].
local C=require(script.Parent:WaitForChild('LobbyShopCatalog'))
local M={}
-- Trail looks (Trail slot), shown only while moving: a glowing ribbon at foot height behind the body, plus particle
-- layers from both feet ('feet') or across the body ('body'). Textures in TRAIL_TEX are drawn in code
-- (D:\RobloxMansion\GoldenGhostAura_20261022\make_textures.py), uploaded 2026-10-22 with the user's OK, tinted per trail.
local TRAIL_TEX={star='rbxassetid://136893400437569',streak='rbxassetid://137758053386970',
 ring='rbxassetid://121324164605561',drop='rbxassetid://111170310604690',
 dot='rbxassetid://97448418934711',ribbon='rbxassetid://86489400676316'}
local HEART,COIN,SEED='rbxassetid://93764965207025','rbxassetid://117087930716286','rbxassetid://121307869288298'
local rgb=Color3.fromRGB
-- Layer fields: tex, from ('feet'|'body'), rate, life {min,max}, speed {min,max}, size {start,peak?,end}, colors,
-- spread (degrees from straight up; 180 = all round), accel (up +), drag, spin, parallel (stretch along velocity),
-- bright (Brightness), glow (LightEmission, default 1), dir ('Top'|'Back').
local TRAILS={
 trail_sparks={ribbon={rgb(255,240,170),rgb(255,150,40)},layers={
  {tex=TRAIL_TEX.streak,from='feet',rate=28,life={.25,.45},speed={6,10},size={.4,.12},colors={rgb(255,248,210),rgb(255,170,50)},spread=65,accel=-20,drag=1,parallel=true,bright=3},
  {tex=TRAIL_TEX.star,from='feet',rate=7,life={.3,.5},speed={.5,1.5},size={0,.7,0},colors={rgb(255,240,190)},spread=180,spin=true,bright=3}}},
 trail_ectoplasm={ribbon={rgb(170,255,180),rgb(60,200,110)},layers={
  {tex=TRAIL_TEX.drop,from='feet',rate=8,life={.7,1},speed={1,2},size={.35,.25},colors={rgb(180,255,190),rgb(70,220,120)},spread=35,accel=-12,bright=1.5,glow=.7},
  {tex=TRAIL_TEX.ring,from='feet',rate=5,life={.6,.9},speed={.2,.6},size={.1,.5},colors={rgb(200,255,210)},spread=60,accel=2,bright=1.5,fade=.2}}},
 trail_glitter={ribbon={rgb(255,175,235),rgb(150,220,255)},layers={
  {tex=TRAIL_TEX.star,from='feet',rate=20,life={.5,.9},speed={1,3},size={0,.55,0},colors={rgb(255,165,235),rgb(170,225,255),rgb(255,255,255)},spread=180,accel=-2,spin=true,bright=3},
  {tex=TRAIL_TEX.dot,from='feet',rate=24,life={.4,.7},speed={1,2.5},size={.18,0},colors={rgb(255,255,255),rgb(255,195,240)},spread=180,bright=2}}},
 trail_hearts={ribbon={rgb(255,185,210),rgb(255,120,165)},layers={
  {tex=HEART,from='feet',rate=7,life={.9,1.2},speed={2,3},size={0,.8,.55},colors={rgb(255,150,185)},spread=30,accel=1.5,bright=1.6,glow=.6,rot=15},
  {tex=TRAIL_TEX.star,from='feet',rate=8,life={.4,.7},speed={1,2},size={0,.4,0},colors={rgb(255,220,235)},spread=180,spin=true,bright=2.5}}},
 trail_coins={ribbon={rgb(255,242,175),rgb(255,190,50)},layers={
  {tex=COIN,from='feet',rate=8,life={.8,1},speed={5,7},size={.6,.5},colors={rgb(255,240,190)},spread=30,accel=-20,spin=true,bright=1.6,glow=.5},
  {tex=TRAIL_TEX.star,from='feet',rate=9,life={.3,.6},speed={.5,1.5},size={0,.55,0},colors={rgb(255,245,200)},spread=180,spin=true,bright=3}}},
 trail_pumpkinseeds={ribbon={rgb(255,230,170),rgb(245,160,60)},layers={
  {tex=SEED,from='feet',rate=10,life={.7,1},speed={4,6},size={.45,.38},colors={rgb(255,248,225)},spread=30,accel=-20,spin=true,bright=1.6,glow=.5},
  {tex=TRAIL_TEX.dot,from='feet',rate=12,life={.4,.7},speed={.5,1.5},size={.2,0},colors={rgb(255,215,140)},spread=180,bright=2}}},
 -- Rank reward trails (2026-10-22).
 trail_rank_seeker={ribbon={rgb(205,232,255),rgb(70,130,255)},layers={
  {tex=TRAIL_TEX.streak,from='feet',rate=20,life={.3,.5},speed={4,7},size={.45,.12},colors={rgb(225,242,255),rgb(90,150,255)},spread=50,accel=-6,drag=1.5,parallel=true,bright=3},
  {tex=TRAIL_TEX.star,from='feet',rate=8,life={.35,.6},speed={.5,1.5},size={0,.6,0},colors={rgb(200,230,255)},spread=180,spin=true,bright=3}}},
 trail_rank_veteran={ribbon={rgb(240,215,255),rgb(165,100,240)},layers={
  {tex=TRAIL_TEX.streak,from='feet',rate=16,life={.5,.8},speed={2,4},size={.4,.1},colors={rgb(245,225,255),rgb(175,110,245)},spread=25,accel=7,parallel=true,bright=3},
  {tex=TRAIL_TEX.dot,from='feet',rate=16,life={.5,.9},speed={1,2},size={.2,0},colors={rgb(235,205,255)},spread=180,accel=2,bright=2}}},
 trail_rank_legend={ribbon={rgb(255,246,200),rgb(255,196,60)},layers={
  {tex=TRAIL_TEX.star,from='feet',rate=14,life={.5,.9},speed={1.5,3.5},size={0,.8,0},colors={rgb(255,250,220),rgb(255,205,70)},spread=180,accel=-2,spin=true,bright=3.5},
  {tex=TRAIL_TEX.streak,from='feet',rate=14,life={.4,.7},speed={4,7},size={.5,.15},colors={rgb(255,245,200),rgb(255,200,70)},spread=40,accel=5,parallel=true,bright=3},
  {tex=TRAIL_TEX.dot,from='feet',rate=10,life={.6,1},speed={.5,1.5},size={.22,0},colors={rgb(255,235,150)},spread=180,accel=1.5,bright=2}}},
 trail_speed={lines={rgb(235,245,255),rgb(150,200,255)},layers={
  {tex=TRAIL_TEX.streak,from='body',dir='Back',rate=22,life={.18,.3},speed={10,14},size={.5,.2},colors={rgb(240,248,255),rgb(160,205,255)},spread=8,parallel=true,bright=2.5}}},
}
M.Trails=TRAILS
local function numSeq(v)
 if #v==1 then return NumberSequence.new(v[1])end
 local k={};for i,x in v do table.insert(k,NumberSequenceKeypoint.new((i-1)/(#v-1),x))end;return NumberSequence.new(k)
end
local function colorSeq(list)
 local k={};for i,c in list do table.insert(k,ColorSequenceKeypoint.new(#list==1 and 0 or(i-1)/(#list-1),c))end
 if #k==1 then table.insert(k,ColorSequenceKeypoint.new(1,list[1]))end;return ColorSequence.new(k)
end
-- One particle layer (TRAILS / AURA layer fields) on a part or attachment.
local function layerEmitter(layer,parent)
 local e=Instance.new('ParticleEmitter');e.Texture=layer.tex;e.Rate=layer.rate;e.LightInfluence=0;e.LightEmission=layer.glow or 1;e.Brightness=layer.bright or 1
 e.Lifetime=NumberRange.new(layer.life[1],layer.life[2]);e.Speed=NumberRange.new(layer.speed[1],layer.speed[2])
 e.Size=numSeq(layer.size);e.Color=colorSeq(layer.colors);e.Transparency=layer.trans and numSeq(layer.trans)or NumberSequence.new(layer.fade or 0,1)
 e.EmissionDirection=Enum.NormalId[layer.dir or'Top'];e.SpreadAngle=Vector2.new(layer.spread or 0,layer.spread or 0)
 e.Acceleration=Vector3.new(0,layer.accel or 0,0);e.Drag=layer.drag or 0;e.LockedToPart=layer.locked==true
 if layer.parallel then e.Orientation=Enum.ParticleOrientation.VelocityParallel
 elseif layer.flat then e.Orientation=Enum.ParticleOrientation.VelocityPerpendicular end
 if layer.spin then e.Rotation=NumberRange.new(0,360);e.RotSpeed=NumberRange.new(-200,200)
 elseif layer.rotSpeed then e.Rotation=NumberRange.new(0,360);e.RotSpeed=NumberRange.new(layer.rotSpeed[1],layer.rotSpeed[2])
 elseif layer.rot then e.Rotation=NumberRange.new(-layer.rot,layer.rot);e.RotSpeed=NumberRange.new(-20,20)end
 if parent:IsA('BasePart')and layer.box then e.Shape=Enum.ParticleEmitterShape.Box end
 if layer.zoff then e.ZOffset=layer.zoff end
 e.Parent=parent;return e
end
-- Showcase stands: a trail's ribbon and particle layers on one moving part (the stand moves it in a loop).
function M.DisplayTrail(id,part)
 local style=TRAILS[id];if not style then return end
 local function ribbon(c0,c1,y0,y1)
  local a0=Instance.new('Attachment');a0.Position=Vector3.new(0,y0,0);a0.Parent=part
  local a1=Instance.new('Attachment');a1.Position=Vector3.new(0,y1,0);a1.Parent=part
  local t=Instance.new('Trail');t.Attachment0=a0;t.Attachment1=a1;t.Lifetime=.5;t.MinLength=.05;t.FaceCamera=false
  t.Texture=TRAIL_TEX.ribbon;t.TextureMode=Enum.TextureMode.Stretch;t.LightEmission=.9;t.LightInfluence=0;t.Brightness=1.6
  t.Color=ColorSequence.new(c0,c1);t.Transparency=NumberSequence.new({NumberSequenceKeypoint.new(0,.1),NumberSequenceKeypoint.new(.6,.45),NumberSequenceKeypoint.new(1,1)})
  t.WidthScale=NumberSequence.new(1,.15);t.Parent=part
 end
 if style.ribbon then ribbon(style.ribbon[1],style.ribbon[2],-.4,.4)end
 if style.lines then for _,y in {-.5,0,.5}do ribbon(style.lines[1],style.lines[2],y-.06,y+.06)end end
 for _,layer in style.layers or {}do
  local scaled=table.clone(layer);scaled.rate=layer.rate*.6 -- one source instead of two feet
  layerEmitter(scaled,part)
 end
end

-- Showcase runners: a character running in place that shows trail `id` the way it looks on a player running at
-- `speed` studs/s. The same particle layers come off the feet and the body; they inherit the runner's (virtual)
-- backward motion, so they fall behind exactly as they do behind a moving player. The ribbon is a Beam as long as a
-- real Trail would be at that speed (a Trail only draws while its parts really move), with the Trail's own fade.
function M.RunnerTrail(ch,id,speed)
 local style=TRAILS[id];local root=ch:FindFirstChild('HumanoidRootPart');if not style or not root then return end
 speed=speed or 14
 local hum=ch:FindFirstChildOfClass('Humanoid')
 local ground=(hum and hum.HipHeight or 2)+root.Size.Y/2
 -- The runner stays put; its assembly reports the motion a running player would have, which the emitters inherit.
 root.AssemblyLinearVelocity=-root.CFrame.LookVector*speed
 local function ribbon(c0,c1,y0,y1,life)
  local a0=Instance.new('Attachment');a0.Name='RunnerBeamStart';a0.Position=Vector3.new(0,(y0+y1)/2,.35);a0.Parent=root
  local a1=Instance.new('Attachment');a1.Name='RunnerBeamEnd';a1.Position=Vector3.new(0,(y0+y1)/2,.35+speed*life);a1.Parent=root
  local b=Instance.new('Beam');b.Attachment0=a0;b.Attachment1=a1;b.Width0=y1-y0;b.Width1=(y1-y0)*.15;b.FaceCamera=true
  b.Texture=TRAIL_TEX.ribbon;b.TextureMode=Enum.TextureMode.Stretch;b.TextureSpeed=0;b.LightEmission=.9;b.LightInfluence=0;b.Brightness=1.6
  b.Color=ColorSequence.new(c0,c1);b.Transparency=NumberSequence.new({NumberSequenceKeypoint.new(0,.1),NumberSequenceKeypoint.new(.6,.45),NumberSequenceKeypoint.new(1,1)})
  b.Segments=8;b.Parent=root
 end
 -- Same heights and lifetimes as the Trails CosmeticRig.Wear gives a player.
 if style.ribbon then ribbon(style.ribbon[1],style.ribbon[2],-ground+.1,-ground+.95,.45)end
 if style.lines then for _,y in {-ground+1.3,0,1.2}do ribbon(style.lines[1],style.lines[2],y-.08,y+.08,.28)end end
 local sources={}
 for _,side in {'Left','Right'}do local foot=ch:FindFirstChild(side..'Foot');if foot then table.insert(sources,{kind='feet',part=foot,offset=CFrame.new(0,-.25,0)})end end
 -- Body layers come from a 1.6 x 2.6 box behind the body, as on a player.
 local body=Instance.new('Part');body.Name='RunnerTrailBody';body.Size=Vector3.new(1.6,2.6,.1);body.Transparency=1;body.CanCollide=false;body.CanQuery=false
 body.CanTouch=false;body.Massless=true;body.CastShadow=false;body.CFrame=root.CFrame*CFrame.new(0,0,.4);body.Anchored=true;body.Parent=ch
 body.AssemblyLinearVelocity=root.AssemblyLinearVelocity
 table.insert(sources,{kind='body',part=body})
 for _,layer in style.layers or {}do
  for _,src in sources do
   if src.kind==layer.from then
    local parent=src.part
    if src.offset then parent=Instance.new('Attachment');parent.Name='RunnerTrail';parent.CFrame=src.offset;parent.Parent=src.part end
    local e=layerEmitter(layer,parent);e.VelocityInheritance=1
    if src.kind=='body'then e.Shape=Enum.ParticleEmitterShape.Box end
   end
  end
 end
end

-- Auras (Aura slot): layered particles around the body. Each look is a list of recipes tinted with two colours
-- (light, deep); auras without their own look get the default recipes in their catalog colour.
local rgb2=Color3.fromRGB
local AURA_TEX={star=TRAIL_TEX.star,dot=TRAIL_TEX.dot,drop=TRAIL_TEX.drop,streak=TRAIL_TEX.streak,
 swirl='rbxassetid://128582632845611',ghost='rbxassetid://105076628007664'}
local RECIPES={
 motes=function(l,d)return {tex=AURA_TEX.dot,rate=14,life={1.2,1.8},speed={.5,1.2},size={.28,0},colors={l,d},spread=180,accel=1.2,bright=2}end,
 glints=function(l)return {tex=AURA_TEX.star,rate=9,life={.5,.9},speed={1.5,3},size={0,.5,0},colors={l},spread=180,drag=3,spin=true,bright=3}end,
 swirlFlat=function(l,d)return {tex=AURA_TEX.swirl,rate=2.5,life={.7,.7},speed={.01,.01},size={3.4,4.2},colors={l,d},flat=true,locked=true,
  trans={1,.1,.25,1},rotSpeed={520,620},bright=2}end,
 swirlBody=function(l,d)return {tex=AURA_TEX.swirl,rate=1.5,life={.6,.6},speed={0,0},size={4.4,5},colors={l,d},locked=true,trans={1,.35,1},rotSpeed={-480,-380},bright=1.5}end,
 snow=function(l)return {tex=AURA_TEX.star,rate=8,life={1.6,2.2},speed={.5,1},size={.3,.2},colors={l},dir='Bottom',spread=70,accel=-.4,spin=true,bright=2.5,at=2.6}end,
 petals=function(l,d)return {tex=AURA_TEX.drop,rate=7,life={1.6,2.2},speed={.6,1.2},size={.32,.22},colors={l,d},dir='Bottom',spread=80,accel=-.8,spin=true,bright=1.6,at=2.6}end,
 embers=function(l,d)return {tex=AURA_TEX.streak,rate=16,life={.6,1},speed={3,5},size={.38,.1},colors={l,d},spread=25,parallel=true,bright=3,at=-2}end,
 ghosts=function(l)return {tex=AURA_TEX.ghost,rate=1.4,life={1.6,2.2},speed={1.6,2.6},size={.4,.9,1.1},colors={l},spread=30,accel=.6,drag=.6,rot=12,
  trans={1,.1,.25,1},bright=1.8}end,
}
local AURAS={
 aura_mint={colors={rgb2(220,255,232),rgb2(110,225,165)},recipes={'motes','swirlFlat','glints'}},
 aura_frost={colors={rgb2(235,248,255),rgb2(130,195,255)},recipes={'snow','swirlBody','glints'}},
 aura_rose={colors={rgb2(255,225,238),rgb2(240,120,180)},recipes={'petals','swirlFlat','glints'}},
 aura_amber={colors={rgb2(255,236,180),rgb2(245,160,60)},recipes={'embers','motes','glints'}},
 aura_violet={colors={rgb2(235,220,255),rgb2(165,115,245)},recipes={'swirlFlat','swirlBody','motes'}},
 aura_ghost={colors={rgb2(255,255,255),rgb2(195,210,255)},recipes={'ghosts','glints','motes'}},
}
-- Rank auras (2026-10-22): one unique look per rank, each with its own drawn shapes (RK_TEX, make_rank_textures.py).
-- Layer fields as in TRAILS plus: at (studs above the root), locked, flat, trans, rotSpeed, zoff (draw order).
-- Uploaded 2026-10-22 with the user's yes.
local RK_TEX={firefly='rbxassetid://78036106738236',ecg='rbxassetid://125771081369063',plus='rbxassetid://89616317122504',eye='rbxassetid://76466000347579',constellation='rbxassetid://115766892151253',planet='rbxassetid://76956724877070',chevron='rbxassetid://135127348286741',wisp='rbxassetid://98092645775844',crown='rbxassetid://102088914796843',rays='rbxassetid://103491508201190'}
local RANK_AURAS={
 -- Wanderer: fireflies drifting lazily around you, a few low by the feet.
 aura_rank_wanderer={light=rgb2(220,240,140),layers={
  {tex=RK_TEX.firefly,rate=16,life={2.6,3.6},speed={.5,1.1},size={0,.7,.7,0},colors={rgb2(250,255,190),rgb2(190,240,110)},spread=180,drag=.5,accel=.25,rotSpeed={-30,30},trans={1,0,.15,1},bright=4},
  {tex=RK_TEX.firefly,at=-2,rate=7,life={2.5,3.5},speed={.3,.8},size={0,.55,.55,0},colors={rgb2(240,255,170)},spread=180,drag=.6,accel=.15,trans={1,0,.2,1},bright=3.5}}},
 -- Survivor: a heartbeat line ring pulsing out from the chest, little teal crosses rising.
 aura_rank_survivor={light=rgb2(90,230,210),layers={
  {tex=RK_TEX.ecg,at=.4,rate=1.25,life={.95,.95},speed={0,0},size={1.6,7.5},colors={rgb2(200,255,245),rgb2(60,220,200)},locked=true,trans={.05,1},bright=2.5},
  {tex=RK_TEX.plus,rate=5,life={1.2,1.8},speed={1.5,2.6},size={0,.42,.3},colors={rgb2(170,255,240),rgb2(70,215,195)},spread=45,accel=.8,rot=20,trans={1,0,1},bright=2.2}}},
 -- Seeker: a watching eye glyph floating over the head, small eyes drifting out, a scanning ring at the waist.
 aura_rank_seeker={light=rgb2(110,170,255),layers={
  {tex=RK_TEX.eye,at=4.4,rate=1.1,life={1.8,1.8},speed={0,0},size={1.1,1.25},colors={rgb2(220,238,255),rgb2(110,170,255)},locked=true,trans={1,.05,.05,1},bright=2.5},
  {tex=RK_TEX.eye,rate=2.5,life={1.4,2},speed={1.2,2},size={0,.45,.35},colors={rgb2(190,220,255)},spread=180,drag=1,trans={1,.1,1},bright=2},
  {tex='rbxassetid://128582632845611',rate=2.2,life={.8,.8},speed={.01,.01},size={3.6,4.2},colors={rgb2(200,230,255),rgb2(80,140,255)},flat=true,locked=true,trans={1,.15,.3,1},rotSpeed={420,520},bright=2}}},
 -- Explorer: a turning star map around you and little ringed planets drifting by.
 aura_rank_explorer={light=rgb2(160,145,255),layers={
  {tex=RK_TEX.constellation,rate=.7,life={3,3},speed={0,0},size={5.6,6},colors={rgb2(225,220,255),rgb2(150,135,255)},locked=true,rotSpeed={14,18},trans={1,.15,.15,1},bright=2.5,zoff=-1},
  {tex=RK_TEX.planet,rate=2,life={2.2,3},speed={.6,1.2},size={0,.55,.45},colors={rgb2(200,190,255),rgb2(140,200,255)},spread=180,drag=.8,rotSpeed={-40,40},trans={1,0,1},bright=2},
  {tex='rbxassetid://136893400437569',rate=7,life={.5,.9},speed={1.5,3},size={0,.45,0},colors={rgb2(240,235,255)},spread=180,drag=3,spin=true,bright=3}}},
 -- Veteran: rank chevrons rising from the feet up through the body, medal glints.
 aura_rank_veteran={light=rgb2(205,150,245),layers={
  {tex=RK_TEX.chevron,at=-2.4,rate=6,life={1.1,1.3},speed={3.4,4},size={1.05,.85},colors={rgb2(245,225,255),rgb2(200,140,245)},spread=8,trans={1,0,.1,1},bright=2.5},
  {tex='rbxassetid://136893400437569',rate=6,life={.5,.9},speed={1,2.5},size={0,.5,0},colors={rgb2(255,240,200),rgb2(220,180,255)},spread=180,drag=3,spin=true,bright=3}}},
 -- Phantom: pale smoke wisps curling up around you over a dark shadow veil, cold flakes falling.
 aura_rank_phantom={light=rgb2(190,210,255),layers={
  {tex=RK_TEX.wisp,at=-1,rate=6,life={1.8,2.6},speed={.6,1.2},size={1.2,2.4,3},colors={rgb2(30,34,52)},glow=0,spread=60,accel=.8,rotSpeed={-35,35},trans={1,.45,1},bright=1,zoff=-1},
  {tex=RK_TEX.wisp,at=-1,rate=9,life={1.6,2.4},speed={.8,1.6},size={.8,1.8,2.4},colors={rgb2(240,246,255),rgb2(170,195,240)},spread=60,accel=1,rotSpeed={-50,50},trans={1,.3,1},bright=2},
  {tex='rbxassetid://136893400437569',at=2.8,rate=6,life={1.8,2.4},speed={.5,1},size={.3,.2},colors={rgb2(225,235,255)},dir='Bottom',spread=70,accel=-.4,spin=true,bright=2.5}}},
 -- Legend: a golden crown floating over the head, a slow sunburst behind you, rising gold embers.
 aura_rank_legend={light=rgb2(255,210,90),layers={
  {tex=RK_TEX.crown,at=4.6,rate=.8,life={2.6,2.6},speed={0,0},size={1.25,1.3},colors={rgb2(255,240,170),rgb2(255,205,70)},locked=true,trans={1,0,0,1},bright=3},
  {tex=RK_TEX.rays,rate=.5,life={4.2,4.2},speed={0,0},size={8.5,9},colors={rgb2(255,235,150),rgb2(255,195,60)},locked=true,rotSpeed={18,22},trans={1,.45,.45,1},bright=2,zoff=-3},
  {tex='rbxassetid://137758053386970',at=-2,rate=14,life={.7,1.1},speed={3,5},size={.4,.1},colors={rgb2(255,248,210),rgb2(255,200,60)},spread=25,parallel=true,bright=3},
  {tex='rbxassetid://136893400437569',rate=8,life={.5,.9},speed={1.5,3},size={0,.5,0},colors={rgb2(255,245,200)},spread=180,drag=3,spin=true,bright=3}}},
}
-- Golden Ghost (VIP pass): crescents orbiting the waist and the body, energy streaks rising, golden ghosts, glints, a warm light.
local function goldenGhost(att,root)
 local GOLD={rgb2(255,248,205),rgb2(255,214,90),rgb2(245,178,50)};local PALE={rgb2(255,252,230),rgb2(255,226,140)}
 local plate=Instance.new('Part');plate.Name='EquippedAuraPlate';plate.Size=Vector3.new(3.4,.05,3.4);plate.Transparency=1
 plate.CanCollide=false;plate.CanQuery=false;plate.CanTouch=false;plate.Massless=true;plate.CastShadow=false
 local hum=root.Parent and root.Parent:FindFirstChildOfClass('Humanoid')
 plate.CFrame=root.CFrame*CFrame.new(0,-((hum and hum.HipHeight or 2)+root.Size.Y/2-.15),0);plate.Anchored=root.Anchored;plate.Parent=root.Parent
 if not root.Anchored then local w=Instance.new('WeldConstraint');w.Part0=root;w.Part1=plate;w.Parent=plate end
 layerEmitter({tex=AURA_TEX.streak,box=true,rate=16,life={.45,.75},speed={6,9},size={.55,.25},colors=PALE,parallel=true,trans={1,.1,1},bright=2.5},plate)
 layerEmitter({tex=AURA_TEX.swirl,rate=3,life={.7,.7},speed={.01,.01},size={3.6,4.4},colors=GOLD,flat=true,locked=true,trans={1,.05,.2,1},rotSpeed={520,620},bright=2},att)
 layerEmitter({tex=AURA_TEX.swirl,rate=1.5,life={.6,.6},speed={0,0},size={4.6,5.2},colors=GOLD,locked=true,trans={1,.35,1},rotSpeed={-480,-380},bright=1.5},att)
 layerEmitter({tex=AURA_TEX.ghost,rate=1.3,life={1.6,2.2},speed={1.6,2.6},size={.4,.9,1.1},colors=PALE,spread=30,accel=.6,drag=.6,rot=12,trans={1,.1,.25,1},bright=1.8},att)
 layerEmitter({tex=AURA_TEX.star,rate=12,life={.5,.9},speed={1.5,3},size={0,.55,0},colors=GOLD,spread=180,drag=3,spin=true,bright=3},att)
 local light=Instance.new('PointLight');light.Color=rgb2(255,212,110);light.Brightness=1.2;light.Range=10;light.Shadows=false;light.Parent=att
end
-- Puts aura `id` on a character (or showcase statue) root, replacing any aura already there. nil removes it.
function M.Aura(root,id)
 for _,x in root:GetChildren()do if x.Name=='EquippedAura'or x.Name=='EquippedAuraLayer'then x:Destroy()end end
 local plate=root.Parent and root.Parent:FindFirstChild('EquippedAuraPlate');if plate then plate:Destroy()end
 local offer=id and C.ById[id];if not offer then return end
 local att=Instance.new('Attachment');att.Name='EquippedAura';att.Parent=root
 if id=='aura_vip'then goldenGhost(att,root);return att end
 local rank=RANK_AURAS[id]
 if rank then
  for _,layer in rank.layers do
   local parent=att
   if layer.at then parent=Instance.new('Attachment');parent.Name='EquippedAuraLayer';parent.Position=Vector3.new(0,layer.at,0);parent.Parent=root end
   layerEmitter(layer,parent)
  end
  local glow=Instance.new('PointLight');glow.Color=rank.light;glow.Brightness=.9;glow.Range=9;glow.Shadows=false;glow.Parent=att
  return att
 end
 local look=AURAS[id]
 local deep=Color3.fromRGB(unpack(offer.color or {255,255,255}))
 local light,dark=look and look.colors[1]or deep:Lerp(Color3.new(1,1,1),.55),look and look.colors[2]or deep
 for _,name in look and look.recipes or {'motes','swirlFlat','glints'}do
  local layer=RECIPES[name](light,dark);local parent=att
  if layer.at then parent=Instance.new('Attachment');parent.Name='EquippedAuraLayer';parent.Position=Vector3.new(0,layer.at,0);parent.Parent=root end
  layerEmitter(layer,parent)
 end
 local glow=Instance.new('PointLight');glow.Color=dark;glow.Brightness=.8;glow.Range=8;glow.Shadows=false;glow.Parent=att
 return att
end
-- Torch skins sit in the right hand at this scale (the hand is small; templates are about 2 studs tall).
local TORCH_SCALE=.55
local function template_lift(id)
 local kit=script.Parent:FindFirstChild('CosmeticKit');local t=kit and kit:FindFirstChild(id)
 return t and t:GetAttribute('MountLift')
end
function M.Wear(ch,equipped,folder,stages)
 local root=ch:FindFirstChild('HumanoidRootPart');local torso=ch:FindFirstChild('UpperTorso');local kit=script.Parent:FindFirstChild('CosmeticKit')
 if not root or not torso or not kit then return end
 -- Root faces -Z, so the character's front is root.CFrame.LookVector.
 local facing=root.CFrame-root.Position
 local anchored=folder:FindFirstAncestorWhichIsA('WorldModel')~=nil
 local function wear(id,target,cf,name)
  local stage=stages and stages[id] -- staged cosmetics (LobbyShopCatalog C.Stages): CosmeticKit[id..'_s'..stage]
  local template=stage and kit:FindFirstChild(id..'_s'..stage)or kit:FindFirstChild(id);if not template or not target then return nil end
  local m=template:Clone();m:PivotTo(cf);m:SetAttribute('WearSlot',C.ById[id]and C.ById[id].kind);m:SetAttribute('CosmeticStage',stage)
  if anchored then for _,x in m:GetDescendants()do if x:IsA('BasePart')then x.Anchored=true end end
  else local w=Instance.new('WeldConstraint');w.Part0=target;w.Part1=m.PrimaryPart;w.Parent=m.PrimaryPart end
  if name then m.Name=name end -- named before parenting so watchers see the final name
  m.Parent=folder;return m
 end
 -- Hats sit above the eyes, centred over both eye stalks, exactly like the Cool Sunglasses hat:
 -- base at Head + HAT_BASE_Y, scaled to span both eyes (tune by screenshot).
 local HAT_BASE_Y=2.21 -- studs above the Head centre (Cool Sunglasses hat bottom)
 local HAT_WIDTH=3.0 -- studs across, brim included
 local hat=C.ById[equipped.Hat]
 local head=ch:FindFirstChild('Head')
 if hat then
  local target=head or torso
  local top=head and head.CFrame*Vector3.new(0,HAT_BASE_Y,0) or torso.CFrame*Vector3.new(0,torso.Size.Y/2-.14,0)
  local m=wear(hat.id,target,CFrame.new(top)*facing)
  if m then
   m.Name='CosmeticHat'
   local _,size=m:GetBoundingBox();local width=math.max(size.X,size.Z)
   if width>0 then
    -- Rescale about the hat's base, keeping it seated over the eyes.
    local weld=m.PrimaryPart and m.PrimaryPart:FindFirstChildOfClass('WeldConstraint');if weld then weld.Enabled=false end
    m:ScaleTo(m:GetScale()*HAT_WIDTH/width)
    -- Templates whose band starts above their pivot (MountLift, template studs) are lowered by that much so
    -- the band, not the pivot, sits on HAT_BASE_Y; SeatDrop (worn studs) nudges one hat further down.
    local template=kit:FindFirstChild(hat.id)
    local lift=(template_lift(hat.id)or 0)*m:GetScale()/(template and template:GetScale()or 1)+(m:GetAttribute('SeatDrop')or 0)
    m:PivotTo(CFrame.new(top-(head or torso).CFrame.UpVector*lift)*facing)
    if weld then weld.Enabled=true end
   end
  end
 end
 -- Rings go on the LEFT hand (the right hand holds the flashlight); first-person arms copy it.
 local ring=C.ById[equipped.Ring];local hand=ch:FindFirstChild('LeftHand')
 if ring and hand then wear(ring.id,hand,hand.CFrame*CFrame.new(0,.05,0),'CosmeticRing') end
 local shoes=C.ById[equipped.Shoes]
 if shoes then
  -- Wide shoes (clown) are wider than the gap between the feet: push each one out on its own side
  -- so the pair never cut into each other.
  local SHOE_GAP=.06
  local template=kit:FindFirstChild(shoes.id);local width=0
  if template then local _,size=template:GetBoundingBox();width=size.X end
  local lf,rf=ch:FindFirstChild('LeftFoot'),ch:FindFirstChild('RightFoot')
  local spacing=(lf and rf)and math.abs(root.CFrame:PointToObjectSpace(rf.Position).X-root.CFrame:PointToObjectSpace(lf.Position).X)or 1.32
  local push=math.max(0,(width+SHOE_GAP-spacing)/2)
  for _,side in {'Left','Right'}do
   local foot=ch:FindFirstChild(side..'Foot')
   local out=root.CFrame.RightVector*(side=='Left'and -push or push)
   -- Seated in the foot's own frame (the rig's foot frame faces backwards, hence the half turn), so a shoe put on
   -- mid-step still lines up with the foot instead of staying crooked.
   local m=foot and wear(shoes.id,foot,(foot.CFrame*CFrame.Angles(0,math.pi,0)*CFrame.new(0,.06,0))+out)
   local nozzle=m and not anchored and m:FindFirstChild('Nozzle')
   if nozzle then
    local e=Instance.new('ParticleEmitter');e.Texture='rbxasset://textures/particles/fire_main.dds';e.Color=ColorSequence.new(Color3.fromRGB(255,170,60),Color3.fromRGB(255,80,20))
    e.Size=NumberSequence.new({NumberSequenceKeypoint.new(0,.35),NumberSequenceKeypoint.new(1,0)});e.Lifetime=NumberRange.new(.15,.3);e.Rate=30;e.Speed=NumberRange.new(3,5);e.LightEmission=1
    e.EmissionDirection=Enum.NormalId.Back;e.Parent=nozzle
   end
  end
 end
 -- Eyes: one template per eyeball, welded to it so it follows the stalks and blinks. SingleEye templates
 -- (the monocle) only go on the left eye. Template origin = eyeball centre, front = character front.
 local eyes=C.ById[equipped.Eyes]
 if eyes and head then
  local template=kit:FindFirstChild(eyes.id)
  local sides=template and template:GetAttribute('SingleEye')and{'Left'}or{'Left','Right'}
  for _,side in sides do
   local ball=head:FindFirstChild(side..'Eyeball')
   if ball then wear(eyes.id,ball,CFrame.new(ball.Position)*facing,'CosmeticEyes'..side)end
  end
 end
 -- Back: on the rear surface of the torso (a ray from behind, like the tattoo), hanging behind (+Z).
 local back=C.ById[equipped.Back]
 if back then
  local forward=root.CFrame.LookVector
  local params=RaycastParams.new();params.FilterType=Enum.RaycastFilterType.Include;params.FilterDescendantsInstances={torso}
  local world=ch:FindFirstAncestorWhichIsA('WorldModel')or workspace
  local hit=world:Raycast(torso.Position-forward*4+Vector3.new(0,.2,0),forward*5,params)
  local point=hit and hit.Position or torso.Position-forward*(torso.Size.Z/2)
  wear(back.id,torso,CFrame.new(point)*facing,'CosmeticBack')
 end
 -- Torch: a small lamp in the right hand (the flashlight hand). FlashlightController tints the beam to match.
 local torch=C.ById[equipped.Torch];local rhand=ch:FindFirstChild('RightHand')
 if torch and rhand then
  local m=wear(torch.id,rhand,CFrame.new(rhand.Position)*facing,'CosmeticTorch')
  if m then
   local weld=m.PrimaryPart and m.PrimaryPart:FindFirstChildOfClass('WeldConstraint');if weld then weld.Enabled=false end
   m:ScaleTo(m:GetScale()*TORCH_SCALE);m:PivotTo(CFrame.new(rhand.Position)*facing)
   if weld then weld.Enabled=true end
  end
 end
 -- Trail: live characters only (a ViewportFrame cannot show particles). The emitter parts live in the
 -- cosmetics folder, so a re-equip or respawn removes them with everything else.
 local trail=C.ById[equipped.Trail];local style=trail and TRAILS[trail.id]
 if style and not anchored then
  local function carrier(target,offset)
   local part=Instance.new('Part');part.Name='CosmeticTrail';part.Size=Vector3.new(.1,.1,.1);part.Transparency=1
   part.CanCollide=false;part.CanQuery=false;part.CanTouch=false;part.Massless=true;part.CastShadow=false
   part.CFrame=target.CFrame*offset;local w=Instance.new('WeldConstraint');w.Part0=target;w.Part1=part;w.Parent=part;part.Parent=folder
   return part
  end
  local emitters={}
  local hum=ch:FindFirstChildOfClass('Humanoid')
  local ground=(hum and hum.HipHeight or 2)+root.Size.Y/2 -- studs from the root centre down to the floor
  local function seq(v)
   if #v==1 then return NumberSequence.new(v[1])end
   local k={};for i,x in v do table.insert(k,NumberSequenceKeypoint.new((i-1)/(#v-1),x))end;return NumberSequence.new(k)
  end
  local function colors(list)
   local k={};for i,c in list do table.insert(k,ColorSequenceKeypoint.new(#list==1 and 0 or(i-1)/(#list-1),c))end
   if #k==1 then table.insert(k,ColorSequenceKeypoint.new(1,list[1]))end;return ColorSequence.new(k)
  end
  local function ribbon(c0,c1,y0,y1,life,width)
   local part=carrier(root,CFrame.new(0,0,.35))
   local a0=Instance.new('Attachment');a0.Position=Vector3.new(0,y0,0);a0.Parent=part
   local a1=Instance.new('Attachment');a1.Position=Vector3.new(0,y1,0);a1.Parent=part
   local t=Instance.new('Trail');t.Attachment0=a0;t.Attachment1=a1;t.Lifetime=life;t.MinLength=.05;t.FaceCamera=false
   t.Texture=TRAIL_TEX.ribbon;t.TextureMode=Enum.TextureMode.Stretch;t.LightEmission=.9;t.LightInfluence=0;t.Brightness=1.6
   t.Color=ColorSequence.new(c0,c1);t.Transparency=NumberSequence.new({NumberSequenceKeypoint.new(0,.1),NumberSequenceKeypoint.new(.6,.45),NumberSequenceKeypoint.new(1,1)})
   t.WidthScale=NumberSequence.new(width or 1,.15);t.Parent=part
   table.insert(emitters,t)
  end
  if style.ribbon then ribbon(style.ribbon[1],style.ribbon[2],-ground+.1,-ground+.95,.45)end
  if style.lines then -- speed lines: three thin streaks at hip, chest and head height
   for _,y in {-ground+1.3,0,1.2}do ribbon(style.lines[1],style.lines[2],y-.08,y+.08,.28)end
  end
  local sources={}
  for _,side in {'Left','Right'}do
   local foot=ch:FindFirstChild(side..'Foot')
   if foot and foot:IsA('BasePart')then table.insert(sources,{kind='feet',part=carrier(foot,CFrame.new(0,-.25,0))})end
  end
  local body=carrier(root,CFrame.new(0,0,.4));body.Size=Vector3.new(1.6,2.6,.1);table.insert(sources,{kind='body',part=body})
  for _,layer in style.layers or {}do
   for _,src in sources do
    if src.kind==layer.from then
     local e=Instance.new('ParticleEmitter');e.Texture=layer.tex;e.Rate=layer.rate;e.LightInfluence=0;e.LightEmission=layer.glow or 1;e.Brightness=layer.bright or 1
     e.Lifetime=NumberRange.new(layer.life[1],layer.life[2]);e.Speed=NumberRange.new(layer.speed[1],layer.speed[2])
     e.Size=seq(layer.size);e.Color=colors(layer.colors);e.Transparency=NumberSequence.new(layer.fade or 0,1)
     e.EmissionDirection=Enum.NormalId[layer.dir or'Top'];e.SpreadAngle=Vector2.new(layer.spread or 0,layer.spread or 0)
     e.Acceleration=Vector3.new(0,layer.accel or 0,0);e.Drag=layer.drag or 0
     if layer.parallel then e.Orientation=Enum.ParticleOrientation.VelocityParallel end
     if layer.spin then e.Rotation=NumberRange.new(0,360);e.RotSpeed=NumberRange.new(-200,200)
     elseif layer.rot then e.Rotation=NumberRange.new(-layer.rot,layer.rot);e.RotSpeed=NumberRange.new(-20,20)end
     if src.kind=='body'then e.Shape=Enum.ParticleEmitterShape.Box end
     e.Parent=src.part;table.insert(emitters,e)
    end
   end
  end
  -- Only while walking, so standing still never piles particles up.
  local conn;conn=game:GetService('RunService').Heartbeat:Connect(function()
   if not root.Parent or not emitters[1]or not emitters[1].Parent then conn:Disconnect();return end
   local v=root.AssemblyLinearVelocity;local moving=Vector3.new(v.X,0,v.Z).Magnitude>3
   for _,e in emitters do if e.Enabled~=moving then e.Enabled=moving end end
  end)
 end
 local tattoo=C.TattooDecals[equipped.Shirt]
 if tattoo then
  -- A flat card on the belly: find the torso surface in front of the stomach and face the decal along its normal.
  local forward=root.CFrame.LookVector;local belly=torso.Position+Vector3.new(0,-.55,0)
  local params=RaycastParams.new();params.FilterType=Enum.RaycastFilterType.Include;params.FilterDescendantsInstances={torso}
  local world=ch:FindFirstAncestorWhichIsA('WorldModel')or workspace
  local hit=world:Raycast(belly+forward*4,-forward*5,params)
  local point=hit and hit.Position or belly+forward*(torso.Size.Z/2)
  local normal=hit and hit.Normal or forward
  local card=Instance.new('Part');card.Name='CosmeticTattoo';card.Size=Vector3.new(1.1,1.1,.02);card.Transparency=1
  card.CanCollide=false;card.CanQuery=false;card.CanTouch=false;card.Massless=true;card.CastShadow=false;card.Anchored=anchored
  card.CFrame=CFrame.lookAt(point+normal*.03,point+normal*2)
  local decal=Instance.new('Decal');decal.Texture=tattoo;decal.Face=Enum.NormalId.Front;decal.Parent=card
  if not anchored then local w=Instance.new('WeldConstraint');w.Part0=torso;w.Part1=card;w.Parent=card end
  card.Parent=folder
 end
end
return M
