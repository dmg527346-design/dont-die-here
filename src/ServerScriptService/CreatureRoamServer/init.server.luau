-- Two authored mesh creatures; no Humanoid, PathfindingService, or avatar rig.
local Players = game:GetService('Players')
local RunService = game:GetService('RunService')
local ServerStorage = game:GetService('ServerStorage')
local Workspace = game:GetService('Workspace')
-- Monster intro display copies (ReplicatedStorage.IntroMonsters) are built right after makeRig below.
local mansion = Workspace:WaitForChild('Mansion',math.huge)
local CAT_CURSE_SPEED=1.15 -- monsters 15% faster for the rest of a level where someone answered NO to the stray cat
while mansion:GetAttribute('Ready')~=true or mansion:GetAttribute('RuntimeReady')~=true do mansion:GetAttributeChangedSignal('RuntimeReady'):Wait() end
local graph = game:GetService('HttpService'):JSONDecode(mansion:WaitForChild('GeneratedGraph').Value)
local collision = mansion:WaitForChild('Collision')
local templates = {
    {name='CollarCrawler_BlackNPC',speed=13,offset=3.0},
    {name='TearWraith_BlackNPC',speed=16,offset=-3.0}, -- the Rusher: quick even when roaming (MonsterAbilities)
    -- Blender-built hotel bellhop (8.85 studs, authored at final size; joints come from part attributes).
    {name='HauntedBellhop_NPC',speed=13,offset=0,kind='Bellhop',scale=1},
    -- Blender-built tripod lantern stalker (9.4 studs, crouches to clear doorways).
    {name='LanternWatcher_NPC',speed=12,offset=0,kind='Lantern',scale=1},
    -- Blender-built Neon-Eyed Tripod (9.99 studs with eye stalks; spike legs, beak jaw, droning ambience).
    {name='NeonTripod_NPC',speed=12,offset=0,kind='Neon',scale=1},
    -- rbxkit-built knitted hand-holder (7.5 studs): only sees players who are ALONE (MonsterAbilities 'Holder'). From level 5.
    {name='LonelyMittens_NPC',speed=12,offset=0,kind='Mittens',scale=1,minLevel=5},
    -- rbxkit-built clockwork ballerina (8.5 studs): blind while her tune plays, spots movers when it stops ('Statue'). From level 6.
    {name='WindUpDancer_NPC',speed=11,offset=0,kind='Dancer',scale=1,minLevel=6},
    -- rbxkit-built Yo-Yo Kid (8 studs, Story build 2026-10-29): the Homesick Yoyo's owner. Classic catch ('Normal'). From level 3.
    {name='YoyoKid_NPC',speed=13,offset=0,kind='Yoyo',scale=1,minLevel=3},
}
local folder = Workspace:FindFirstChild('RoamingCreatures') or Instance.new('Folder')
folder.Name='RoamingCreatures'; folder.Parent=Workspace
local roomByName, adjacency = {}, {}
for _,r in ipairs(graph.rooms) do roomByName[r.name]=r;adjacency[r.name]={} end
for _,e in ipairs(graph.edges) do
    table.insert(adjacency[e.a],{to=e.b,edge=e,reverse=false})
    table.insert(adjacency[e.b],{to=e.a,edge=e,reverse=true})
end
local TUNE={SightRange=58,NearSight=10,VisionDot=.25,PerceptionInterval=.16,ChaseSpeed=19,ChaseAngerBonus=1,BurstSpeed=24,BurstDuration=0,BurstPeriod=7,SearchMemory=6}
local VAN_SAFE_RADIUS=40
-- Pacing. Monsters roam slowly and close in once they have a target; seen modes
-- were slower than blind ones (Stalk 10 / Suspicious 9 vs Search 19 / Investigate 17).
local MODE_SPEED={Retreat=13,Investigate=12,Search=13,Stalk=14,Suspicious=13,CheckHiding=12,Ambush=13,Steal=16} -- Steal: hurrying off with cart loot
local PATROL_SCALE=.75 -- idle roaming at 75% of the template speed (about 9-11 studs/s)
local CAMP_RADIUS=90 -- walking-route studs around the player spawn that idle patrols avoid
local CALM_BASE,CALM_STEP,CALM_MIN=10,2,6 -- (owner 2026-10-22: monsters barely noticed anyone)
local EASY_EXTRA_CALM,EASY_SPEED=10,.92 -- level 1 only: longer calm start, slower patrol and chase (new-player retention) -- seconds after spawning before they hunt (was 45,4,25: too passive)
local EASY_CHASE_SPEED=15 -- was 13; level 1 chase cap: walk 12, sprint 20, sustainable sprint-walk mix ~15, so a running player can get away (was 14; easier start 2026-10-22)
-- Level 2 (user request 2026-10-22): chases 1.35x faster once it sees someone, and after giving up a hunt it heads off
-- elsewhere quicker (Retreat / Patrol x1.25). MonsterIntelligence also shortens its hunt from memory on level 2.
local LEVEL2_CHASE,LEVEL2_MOVE_ON=1.35,1.25
local EASY_HEADSTART=15 -- owner 2026-10-26: 15 s (was 45) so the first item already has a monster around; owner 2026-10-22: 45 s (was 30, before that 60); level 1: seconds after Searching starts before the monster spawns at all (back to 60 after new-player playtime dropped, 2026-10-22)
local LEVEL2_HEADSTART=15 -- was 25; level 2: a shorter quiet start (was none; easier start 2026-10-22)
local CALM_NOTICE=50 -- a player this close and in sight still gets noticed while calm (was 35, 16)
-- Sight awareness (was 58 range / 70 falloff / .25 facing / .12 floor / 10 instant / .45 dark light).
local SIGHT_RANGE=115 -- studs a monster can spot a player in front of it (was 80)
local SIGHT_FALLOFF=135 -- visibility fades to the floor at this distance (was 95)
local SIGHT_FACING_DOT=-.15 -- ~100 degree half-angle: wide peripheral vision, only directly behind is blind
local SIGHT_MIN_VISIBILITY=.4 -- even a far, dark, crouched player builds suspicion steadily
local SIGHT_INSTANT_RANGE=26 -- anyone this close and visible is noticed immediately (was 20)
-- Owner 2026-10-22 ("sometimes doesnt even detect me" when near): no blind spot up close, doorways count as in the map.
local NEAR_SENSE,NEAR_SENSE_RUNNING=12,20 -- studs: sensed from any direction with a clear line (running: further)
-- Ramp-up for new players (owner 2026-10-22, faster bounce): rounds 1-3 sense less close by, full power from round 4.
local NEAR_BY_ROUND={[1]={6,10},[2]={8,14},[3]={10,17}}
-- Spread out (owner 2026-10-22): most patrol picks skip rooms near another monster, and a 'loner' monster leaves a player
-- another monster is already chasing alone. A player who hit it (thrown item, grenade) overrides both for PROVOKE_SECONDS.
local SPREAD_CHANCE,SPREAD_RADIUS,PROVOKE_SECONDS=.7,45,40
local NEAR_MARGIN=4 -- studs past a room's rectangle that still count as inside it (door gaps between rooms)
local DARK_VISIBILITY=.75 -- visibility multiplier away from lights (was .65)
local CATCH_RANGE=7 -- grab reach in a chase (was 4.1; players could sidestep too easily)
local AVOID_SECONDS,AVOID_RADIUS=5,45 -- was 10,60; after losing sight: stay this far (route studs) from where the player was
local nearSpawn,disengageMonster -- defined below (route helpers)
local function vanPosition()
 local camp=Workspace:FindFirstChild('RecoveryCamp')
 local van=camp and camp:FindFirstChild('AnomalyRecoveryVan')
 return van and van:GetPivot().Position
end
local function nearVan(p,extra)
 local v=vanPosition();if not v then return false end
 return Vector3.new(p.X-v.X,0,p.Z-v.Z).Magnitude<VAN_SAFE_RADIUS+(extra or 0)
end
local function vanSegmentSafe(a,b)
 local v=vanPosition();if not v then return true end
 local delta=Vector3.new(b.X-a.X,0,b.Z-a.Z)
 local relative=Vector3.new(v.X-a.X,0,v.Z-a.Z)
 local t=delta:Dot(delta)>.01 and math.clamp(relative:Dot(delta)/delta:Dot(delta),0,1) or 0
 return not nearVan(a+delta*t,4)
end
local active={}
local Protection=require(game.ServerScriptService:WaitForChild('MonsterProtection'))
-- Omens (RecoveryRoundServer, level 3+): read live, the level's omen changes every level.
local function omen()local s=game.ReplicatedStorage:FindFirstChild('RecoveryRound');return s and s:GetAttribute('Omen')end
-- One harm check for every monster hit, grab, laser and kill: 'Untouchable' blocks only the first contact of the level.
local Sighted=Protection
Protection={IsProtected=function(p)return Sighted.IsProtected(p)or Sighted.OmenShield(p)end,OmenShield=Sighted.OmenShield}
local chasedAt={} -- Adrenaline omen: player -> last ChasedUntil refresh

local doorByEdge={}
for _,e in ipairs(graph.edges) do if e.kind=='door' then for _,m in ipairs(mansion.Interactive:GetChildren()) do if m:GetAttribute('Kind')=='door' and not m:GetAttribute('Closet') then local cf=m:GetAttribute('ClosedPivot');if cf and (cf.Position-Vector3.new(e.x,e.y,e.z)).Magnitude<4 then doorByEdge[e]=m;break end end end end end
local function blocked(e)local d=doorByEdge[e];return e.boarded or (d and(d:GetAttribute('Locked')==true or(d:GetAttribute('WedgedUntil')or 0)>workspace:GetServerTimeNow()))or(e.locked and not d)end -- Door Wedge gear: wedged doors route like locked ones
local rng=Random.new()
-- Accelerated route verification is opt-in and ignored outside Studio.
local verificationSpeed=if RunService:IsStudio() then math.clamp(script:GetAttribute('VerificationSpeed') or 1,1,16) else 1

local Topology=require(game.ServerScriptService:WaitForChild('MapGen'):WaitForChild('Topology'))
local FLOOR=Topology.FloorHeight
local function roomAt(p)
    local level=Topology.Level(p.Y)
    for _,r in ipairs(graph.rooms) do
        if r.level==level and p.X>=r.x1 and p.X<=r.x2 and p.Z>=r.z1 and p.Z<=r.z2 then return r end
    end
    local best,bestD
    for _,r in ipairs(graph.rooms) do
        if r.level==level then
            local dx=math.max(r.x1-p.X,0,p.X-r.x2)
            local dz=math.max(r.z1-p.Z,0,p.Z-r.z2)
            local d=dx*dx+dz*dz
            if not bestD or d<bestD then best,bestD=r,d end
        end
    end
    return best
end
local function center(r)
    return Vector3.new(r.navx or (r.x1+r.x2)/2,r.level*FLOOR,r.navz or (r.z1+r.z2)/2)
end
local AngledCorners=require(game:GetService('ServerScriptService').MapGen:WaitForChild('AngledCorners'))
local function safePoint(r,p,pad)
    local q=Vector3.new(math.clamp(p.X,r.x1+pad,r.x2-pad),r.level*FLOOR,
        math.clamp(p.Z,r.z1+pad,r.z2-pad))
    -- A goal behind a diagonal corner cut is unreachable: move it onto the room side of the cut.
    return AngledCorners.Clear(workspace:FindFirstChild('Mansion'),q,pad)
end
local function shortest(startName,destName)
    local q={startName};local head=1;local back={[startName]=false}
    while head<=#q do
        local n=q[head];head+=1
        if n==destName then break end
        for _,link in ipairs(adjacency[n]) do
            if not blocked(link.edge) and back[link.to]==nil then back[link.to]={from=n,link=link};table.insert(q,link.to) end
        end
    end
    if back[destName]==nil then return nil end
    local path={};local n=destName
    while n~=startName do local step=back[n];table.insert(path,1,step.link);n=step.from end
    return path
end
local function makeWaypoints(currentRoom,steps,goal)
    local points={};local from=currentRoom
    local function circulation(r,e,outward)
        local c=center(r)
        local x=math.clamp(e.x,r.x1+3.2,r.x2-3.2)
        local z=math.clamp(e.z,r.z1+3.2,r.z2-3.2)
        local route
        if r.type=='Dining' then
            route={c,Vector3.new(r.x2-2.8,c.Y,c.Z),Vector3.new(r.x2-2.8,c.Y,z),Vector3.new(x,c.Y,z)}
        else route={c,Vector3.new(c.X,c.Y,z),Vector3.new(x,c.Y,z)} end
        if outward then for _,p in ipairs(route) do table.insert(points,p) end
        else for i=#route,1,-1 do table.insert(points,route[i]) end end
    end
    for _,step in ipairs(steps) do
        local e=step.edge;local nextRoom=roomByName[step.to]
        if e.kind=='stairs' then
            if e.waypoints then
                if from.level==0 then for _,p in ipairs(e.waypoints) do table.insert(points,Vector3.new(unpack(p))) end
                else for i=#e.waypoints,1,-1 do table.insert(points,Vector3.new(unpack(e.waypoints[i]))) end end
            else
                local ascending=from.level==0
                if ascending then
                    table.insert(points,Vector3.new(12,0,-30))
                    for i=1,16 do table.insert(points,Vector3.new(12+i*1.5,i,-30)) end
                    table.insert(points,Vector3.new(37,16,-30))
                else
                    table.insert(points,Vector3.new(37,16,-30))
                    for i=16,1,-1 do table.insert(points,Vector3.new(12+i*1.5,i,-30)) end
                    table.insert(points,Vector3.new(12,0,-30))
                end
            end
        else
            if graph.seed then circulation(from,e,true) end
            local port=Vector3.new(e.x,e.y,e.z)
            local side=center(nextRoom)-center(from)
            local direction=if e.axis=='x' then Vector3.new(0,0,math.sign(side.Z)) elseif e.axis=='z' then Vector3.new(math.sign(side.X),0,0) else Vector3.new(side.X,0,side.Z).Unit
            table.insert(points,port-direction*2.2)
            table.insert(points,port)
            table.insert(points,port+direction*2.2)
            if graph.seed then circulation(nextRoom,e,false) end
        end
        from=nextRoom
    end
    table.insert(points,goal)
    return points
end
local function joint(model,parentName,partName,pivot,tag)
    local parent=model:FindFirstChild(parentName)
    local part=model:FindFirstChild(partName)
    if not parent or not part then return end
    local world=CFrame.new(pivot)
    local motor=Instance.new('Motor6D')
    motor.Name=tag or partName..'Joint'
    motor.Part0=parent;motor.Part1=part
    motor.C0=parent.CFrame:ToObjectSpace(world)
    motor.C1=part.CFrame:ToObjectSpace(world)
    motor.Parent=parent
end
local TALL_KINDS={Bellhop=true,Lantern=true,Neon=true,Mittens=true,Dancer=true,Yoyo=true} -- authored tall monsters (collision field size)
local function addCorruptionVFX(model,root,kind)
    local field=Instance.new('Part')
    field.Name='CorruptionField'
    local scale=model:GetAttribute('VisualScaleMultiplier')or 1
    field.Size=(kind=='Crawler' and Vector3.new(5.4,5.1,4.2) or TALL_KINDS[kind] and Vector3.new(3.2,7.6,2.2) or Vector3.new(4.3,7.5,2.9))*scale
    field.Transparency=1;field.CanCollide=false;field.CanTouch=false;field.CanQuery=false
    field.Anchored=false;field.Massless=true
    field.CFrame=root.CFrame*CFrame.new(0,(kind=='Crawler' and 2.3 or TALL_KINDS[kind] and 3.9 or 3.5)*scale,0)
    field.Parent=model
    local weld=Instance.new('WeldConstraint')
    weld.Part0=root;weld.Part1=field;weld.Parent=field

    local wisps=Instance.new('ParticleEmitter')
    wisps.Name='CorruptionWisps'
    wisps.Texture='rbxasset://textures/particles/smoke_main.dds'
    wisps.Shape=Enum.ParticleEmitterShape.Box
    wisps.ShapeStyle=Enum.ParticleEmitterShapeStyle.Volume
    wisps.Color=ColorSequence.new(Color3.fromRGB(34,30,42),Color3.fromRGB(6,6,9))
    wisps.Transparency=NumberSequence.new({
        NumberSequenceKeypoint.new(0,1),NumberSequenceKeypoint.new(.14,.17),
        NumberSequenceKeypoint.new(.68,.36),NumberSequenceKeypoint.new(1,1)})
    wisps.Size=NumberSequence.new({
        NumberSequenceKeypoint.new(0,.32),NumberSequenceKeypoint.new(.43,1.16),
        NumberSequenceKeypoint.new(1,1.8)})
    wisps.Rate=18;wisps.Lifetime=NumberRange.new(1.2,1.9)
    wisps.Speed=NumberRange.new(.25,1.0)
    wisps.Acceleration=Vector3.new(0,1.35,0)
    wisps.Drag=1.15;wisps.SpreadAngle=Vector2.new(180,180)
    wisps.Rotation=NumberRange.new(-180,180)
    wisps.RotSpeed=NumberRange.new(-35,35)
    wisps.LightEmission=0;wisps.LightInfluence=.12
    wisps.LockedToPart=false
    wisps.Parent=field

    local veil=Instance.new('ParticleEmitter')
    veil.Name='CorruptionVeil'
    veil.Texture='rbxasset://textures/particles/smoke_main.dds'
    veil.Shape=Enum.ParticleEmitterShape.Box
    veil.ShapeStyle=Enum.ParticleEmitterShapeStyle.Surface
    veil.Color=ColorSequence.new(Color3.fromRGB(46,39,55),Color3.fromRGB(9,8,13))
    veil.Transparency=NumberSequence.new({
        NumberSequenceKeypoint.new(0,1),NumberSequenceKeypoint.new(.18,.49),
        NumberSequenceKeypoint.new(.70,.60),NumberSequenceKeypoint.new(1,1)})
    veil.Size=NumberSequence.new({
        NumberSequenceKeypoint.new(0,.65),NumberSequenceKeypoint.new(.5,1.7),
        NumberSequenceKeypoint.new(1,2.8)})
    veil.Rate=8;veil.Lifetime=NumberRange.new(1.2,1.8)
    veil.Speed=NumberRange.new(.1,.55)
    veil.Acceleration=Vector3.new(0,.85,0)
    veil.Drag=1;veil.SpreadAngle=Vector2.new(180,180)
    veil.Rotation=NumberRange.new(-180,180)
    veil.RotSpeed=NumberRange.new(-25,25)
    veil.LightEmission=0;veil.LightInfluence=.08
    veil.Parent=field

    local shards=Instance.new('ParticleEmitter')
    shards.Name='CorruptionShards'
    shards.Texture='rbxasset://textures/particles/sparkles_main.dds'
    shards.Shape=Enum.ParticleEmitterShape.Box
    shards.ShapeStyle=Enum.ParticleEmitterShapeStyle.Volume
    shards.Color=ColorSequence.new(Color3.fromRGB(82,72,99),Color3.fromRGB(17,15,24))
    shards.Transparency=NumberSequence.new({
        NumberSequenceKeypoint.new(0,1),NumberSequenceKeypoint.new(.12,.13),
        NumberSequenceKeypoint.new(.65,.32),NumberSequenceKeypoint.new(1,1)})
    shards.Size=NumberSequence.new({
        NumberSequenceKeypoint.new(0,.25),NumberSequenceKeypoint.new(.55,.66),
        NumberSequenceKeypoint.new(1,0)})
    shards.Rate=0;shards.Lifetime=NumberRange.new(.32,.7)
    shards.Speed=NumberRange.new(.9,2.0)
    shards.Acceleration=Vector3.new(0,.3,0)
    shards.SpreadAngle=Vector2.new(180,180)
    shards.Rotation=NumberRange.new(-180,180)
    shards.RotSpeed=NumberRange.new(-240,240)
    shards.LightEmission=.07;shards.LightInfluence=.15
    shards.Parent=field
    local white=wisps:Clone()
    white.Name='WhiteMist';white.Color=ColorSequence.new(Color3.new(1,1,1))
    white.Rate=12;white.Lifetime=NumberRange.new(.65,1.15)
    white.Size=NumberSequence.new({NumberSequenceKeypoint.new(0,.18),NumberSequenceKeypoint.new(.4,.7),NumberSequenceKeypoint.new(1,1.2)})
    white.Transparency=NumberSequence.new({NumberSequenceKeypoint.new(0,1),NumberSequenceKeypoint.new(.18,.35),NumberSequenceKeypoint.new(.7,.65),NumberSequenceKeypoint.new(1,1)})
    white.LightEmission=.65;white.LightInfluence=0;white.Speed=NumberRange.new(.7,1.6);white.Parent=field
    local sparks=shards:Clone()
    sparks.Name='WhiteSparks';sparks.Color=ColorSequence.new(Color3.new(1,1,1))
    sparks.Rate=5;sparks.LightEmission=1;sparks.LightInfluence=0
    sparks.Size=NumberSequence.new({NumberSequenceKeypoint.new(0,.12),NumberSequenceKeypoint.new(.3,.3),NumberSequenceKeypoint.new(1,0)})
    sparks.Parent=field
end
-- Sized to the mansion: doorways are 10 studs tall, rooms 14. Crawler 1.8 is ~9.4 tall (the largest that
-- still clears a doorway); the wraith doubled to 1.2 is ~8.4 tall.
local MONSTER_VISUAL_SCALE=1.8
local WRAITH_VISUAL_SCALE=1.2
local function addFlailingArms(model)
 local torso=model.Torso;local center=torso.Position;local width=torso.Size.X
 local length=width*.60;local thickness=width*.12
 local function limb(name,size,cf,shape)
  local p=Instance.new('Part');p.Name=name;p.Size=size;p.CFrame=cf;p.Shape=shape or Enum.PartType.Block
  p.Color=Color3.fromRGB(13,13,16);p.Material=Enum.Material.SmoothPlastic
  p.Anchored=false;p.Massless=true;p.CanCollide=false;p.CanTouch=false;p.CanQuery=false;p.Parent=model
  return p
 end
 for _,side in {'Left','Right'}do
  local sign=side=='Left'and -1 or 1
  local shoulder=center+Vector3.new(sign*(width*.5+thickness*.4),torso.Size.Y*.30,0)
  local elbow=shoulder-Vector3.new(0,length,0)
  local wrist=elbow-Vector3.new(0,length*.9,0)
  limb(side..'FlailUpperArm',Vector3.new(length,thickness,thickness),CFrame.new((shoulder+elbow)/2)*CFrame.Angles(0,0,math.pi/2),Enum.PartType.Cylinder)
  limb(side..'FlailForearm',Vector3.new(length*.9,thickness*.85,thickness*.85),CFrame.new((elbow+wrist)/2)*CFrame.Angles(0,0,math.pi/2),Enum.PartType.Cylinder)
  local hand=limb(side..'FlailHand',Vector3.new(thickness*1.7,thickness*2.1,thickness),CFrame.new(wrist-Vector3.new(0,thickness*.7,0)),Enum.PartType.Ball)
  joint(model,'Torso',side..'FlailUpperArm',shoulder,side..'FlailShoulder')
  joint(model,side..'FlailUpperArm',side..'FlailForearm',elbow,side..'FlailElbow')
  joint(model,side..'FlailForearm',side..'FlailHand',wrist,side..'FlailWrist')
  for i=1,3 do
   local finger=limb(side..'FlailFinger'..i,Vector3.new(thickness*.32,thickness*2.1,thickness*.35),
    hand.CFrame*CFrame.new((i-2)*thickness*.55,-thickness*1.8,0)*CFrame.Angles(0,0,(i-2)*.18),Enum.PartType.Ball)
   local w=Instance.new('WeldConstraint');w.Part0=hand;w.Part1=finger;w.Parent=finger
  end
 end
end

local function makeRig(template,owner,spawn,display) -- display: a folder to build an unparented-from-the-game copy into (intro)
    local model=ServerStorage:WaitForChild(template.name):Clone()
    local visualScale=template.scale or (template.name:find('Wraith')and WRAITH_VISUAL_SCALE or MONSTER_VISUAL_SCALE)
    if visualScale~=1 then model:ScaleTo(model:GetScale()*visualScale) end
    model:SetAttribute('VisualScaleMultiplier',visualScale)
    -- Always streamed to every player: jumpscares clone the monster on the scared player's own device.
    model.ModelStreamingMode=Enum.ModelStreamingMode.Persistent
    model.Name=template.name..'_'..owner.UserId
    model:SetAttribute('CreatureKind',template.kind or (template.name:find('Crawler') and 'Crawler' or 'Wraith'))
    local authored=template.kind~=nil
    model:SetAttribute('OwnerUserId',owner.UserId)
    model:SetAttribute('PhaseSeed',rng:NextNumber(0,20))
    model:SetAttribute('Walking',false);model:SetAttribute('AIState','Patrol')
    local root=Instance.new('Part')
    root.Name='CreatureRoot';root.Size=Vector3.new(1,1,1)
    root.Transparency=1;root.CanCollide=false;root.CanTouch=false;root.Anchored=true
    root.CFrame=model:GetPivot();root.Parent=model
    model.PrimaryPart=root
    for _,part in ipairs(model:GetDescendants()) do
        if part:IsA('BasePart') and part~=root then
            part.Anchored=false;part.CanCollide=false;part.CanTouch=false
            part.Massless=true
            if authored then -- keeps its authored crimson, gold and brass colours
            elseif part.Name=='LeftEye' or part.Name=='RightEye' then
                part.Color=Color3.new(1,1,1);part.Material=Enum.Material.Neon
            elseif part.Name:match('^MouthTooth_')then part.Color=Color3.fromRGB(235,229,210)
            elseif part.Name=='MouthOpening'then part.Color=Color3.fromRGB(3,2,3)
            else part.Color=Color3.fromRGB(13,13,16) end
        end
    end
    local kind=model:GetAttribute('CreatureKind')
    if authored then
        -- Parents before children so every Motor6D is built from the rest pose.
        local pending={}
        for _,part in ipairs(model:GetChildren()) do if part:GetAttribute('JointParent') then table.insert(pending,part) end end
        local built={CreatureRoot=true}
        while #pending>0 do
            local progressed=false
            for i=#pending,1,-1 do
                local part=pending[i]
                if built[part:GetAttribute('JointParent')] then
                    joint(model,part:GetAttribute('JointParent'),part.Name,part:GetAttribute('JointPivot')*visualScale,part:GetAttribute('JointName'))
                    built[part.Name]=true;table.remove(pending,i);progressed=true
                end
            end
            if not progressed then error('Bellhop joint without parent: '..pending[1].Name) end
        end
        model.Parent=display or folder
        root.CFrame=CFrame.new(spawn)*CFrame.Angles(0,rng:NextNumber(-math.pi,math.pi),0)
        addCorruptionVFX(model,root,kind)
        return model,root
    end
    local torso=model:FindFirstChild('Torso')
    joint(model,'CreatureRoot','Torso',torso.Position,'TorsoJoint')
    for _,part in ipairs(model:GetChildren()) do
        if part:IsA('MeshPart') and part.Name:match('^Leg_%d+') then
            local hip=part.Position+Vector3.new(0,part.Size.Y*.47,0)
            joint(model,'Torso',part.Name,hip,part.Name..'Joint')
        end
    end
    if kind=='Crawler' then
        joint(model,'Torso','Neck',model.Neck.Position-Vector3.new(0,model.Neck.Size.Y*.42,0),'NeckJoint')
        joint(model,'Torso','Collars',model.Collars.Position,'CollarsJoint')
        joint(model,'Neck','Head',model.Head.Position-Vector3.new(0,model.Head.Size.Y*.35,0),'HeadJoint')
        joint(model,'Head','HeartEmblem',model.HeartEmblem.Position,'HeartJoint')
        for _,side in ipairs({'Left','Right'}) do
            local stalk=model[side..'Stalk']
            joint(model,'Head',side..'Stalk',stalk.Position-Vector3.new(0,stalk.Size.Y*.47,0),side..'StalkJoint')
            joint(model,side..'Stalk',side..'EyeCup',model[side..'EyeCup'].Position,side..'CupJoint')
            joint(model,side..'EyeCup',side..'Eye',model[side..'Eye'].Position,side..'EyeJoint')
        end
    else
        joint(model,'Torso','TearRecess',model.TearRecess.Position,'TearJoint')
        for _,side in ipairs({'Left','Right'}) do
            local stalk=model[side..'Stalk']
            joint(model,'Torso',side..'Stalk',stalk.Position-Vector3.new(0,stalk.Size.Y*.46,0),side..'StalkJoint')
            joint(model,side..'Stalk',side..'EyeCup',model[side..'EyeCup'].Position,side..'CupJoint')
            joint(model,side..'EyeCup',side..'Eye',model[side..'Eye'].Position,side..'EyeJoint')
        end
    end
    addFlailingArms(model)
    model.Parent=display or folder
    root.CFrame=CFrame.new(spawn)*CFrame.Angles(0,rng:NextNumber(-math.pi,math.pi),0)
    addCorruptionVFX(model,root,kind)
    return model,root
end
-- Monster intro cutscene (owner 2026-10-26; rigged 2026-10-27 "they just float and are super stiff"): script-free display
-- copies of every monster for MonsterIntroClient, built by makeRig itself (same Motor6Ds, flail arms and corruption
-- VFX as the real ones), so CreatureAnimateClient moves them with the real procedural animation. The root stays at its
-- rest pose (rig-consistent pivot); nothing collides, touches or is queried; no scripts, no sounds.
do
 local RS=game:GetService('ReplicatedStorage')
 if not RS:FindFirstChild('IntroMonsters')then
  local intro=Instance.new('Folder');intro.Name='IntroMonsters'
  for i,n in {'CollarCrawler_BlackNPC','TearWraith_BlackNPC','HauntedBellhop_NPC','LanternWatcher_NPC','NeonTripod_NPC'}do
   local template;for _,t in templates do if t.name==n then template=t end end
   if template and ServerStorage:FindFirstChild(n)then
    local ok,m,root=pcall(makeRig,template,{UserId=0},Vector3.zero,intro)
    if ok and m and root then
     m.Name=n;m:SetAttribute('IntroOrder',i);m:SetAttribute('OwnerUserId',nil)
     for _,j in root:GetChildren()do -- put the root back where the joints were built (makeRig turned it to a random yaw)
      if j:IsA('Motor6D')and j.Part0==root and j.Part1 then root.CFrame=j.Part1.CFrame*j.C1*j.C0:Inverse();break end
     end
     for _,d in m:GetDescendants()do
      if d:IsA('LuaSourceContainer')or d:IsA('Sound')then d:Destroy()
      elseif d:IsA('BasePart')then d.CanCollide=false;d.CanQuery=false;d.CanTouch=false end
     end
    else warn('[IntroMonsters] '..n..': '..tostring(m))end
   end
  end
  intro.Parent=RS
 end
end

local sightParams=RaycastParams.new();sightParams.FilterType=Enum.RaycastFilterType.Include;sightParams.FilterDescendantsInstances={collision,mansion.Interactive};sightParams.RespectCanCollide=true
-- A recovery cart's low basket never hides the player riding in or standing beside it.
local CART_COVER_RADIUS=8
local function sees(state,pos)
 local origin=state.root.Position+Vector3.new(0,2.5,0)
 local delta=pos-origin
 if delta.Magnitude<.1 then return true end
 local params,skipped=sightParams,{}
 for _=1,3 do
  local hit=Workspace:Raycast(origin,delta,params)
  if not hit then return true end
  local model=hit.Instance:FindFirstAncestorOfClass('Model')
  if not (model and model:GetAttribute('Kind')=='cart' and (hit.Position-pos).Magnitude<CART_COVER_RADIUS) then return false end
  -- Recast the whole ray with only that cart removed, so walls and doors still block.
  skipped[model]=true
  local list={collision}
  for _,child in mansion.Interactive:GetChildren()do if not skipped[child] then table.insert(list,child)end end
  params=RaycastParams.new();params.FilterType=Enum.RaycastFilterType.Include;params.FilterDescendantsInstances=list;params.RespectCanCollide=true
 end
 return false
end
local Audio=require(game.ServerScriptService:WaitForChild('GameplayAudioServer'))
local function soundCue(state,name)
 if os.clock()-(state.lastCue or 0)<3 then return end;state.lastCue=os.clock()
 Audio.Play(name=='Rush' and 'MonsterRush' or name=='Attack' and 'MonsterJumpscare' or 'MonsterNotice',state.root)
end
local function setMode(state,mode)
 if state.mode~=mode then state.mode=mode;state.model:SetAttribute('AIState',mode);if mode=='Chase' then soundCue(state,'Notice') elseif mode=='Search' then Audio.Play('MonsterSearch',state.root)end end
end
local MOVE_CLEARANCE_SIZE=Vector3.new(1.6,4.4,1.6)
local function clearSegment(a,b)
 if math.abs(a.Y-b.Y)>.3 or not vanSegmentSafe(a,b) then return false end
 local delta=b-a
 return delta.Magnitude<.01 or Workspace:Blockcast(CFrame.new(a+Vector3.new(0,2.4,0)),MOVE_CLEARANCE_SIZE,delta,sightParams)==nil
end
-- Stairs: a creature part-way up a flight finishes it before anything else. Re-planning from there used to start at
-- a floor-level room point and cut a straight line through the steps, floor or ceiling.
local function stairEdgeOf(roomName)
 for _,e in ipairs(graph.edges)do if e.kind=='stairs'and e.waypoints and(e.a==roomName or e.b==roomName)then return e end end
end
local function onFlight(y)local f=y/FLOOR;return math.abs(f-math.floor(f+.5))*FLOOR>.5 end
-- Distance from p to the nearest authored stair flight (polyline through its waypoints).
local function flightGap(p)
 local best=math.huge
 for _,e in ipairs(graph.edges)do
  if e.kind=='stairs'and e.waypoints then
   local wp=e.waypoints
   for i=1,#wp-1 do
    local a,b=Vector3.new(unpack(wp[i])),Vector3.new(unpack(wp[i+1]));local ab=b-a
    local t=ab:Dot(ab)>0 and math.clamp((p-a):Dot(ab)/ab:Dot(ab),0,1)or 0
    best=math.min(best,(a+ab*t-p).Magnitude)
   end
  end
 end
 return best
end
local function stairLeg(pos,destLevel)
 if not onFlight(pos.Y)then return nil end
 local bestEdge,bestI,bestD
 for _,e in ipairs(graph.edges)do
  if e.kind=='stairs'and e.waypoints then
   for i,p in ipairs(e.waypoints)do local d=(Vector3.new(unpack(p))-pos).Magnitude;if not bestD or d<bestD then bestEdge,bestI,bestD=e,i,d end end
  end
 end
 if not bestEdge then return nil end
 local wp,leg=bestEdge.waypoints,{} -- authored bottom to top
 if destLevel>0 then for i=bestI,#wp do table.insert(leg,Vector3.new(unpack(wp[i])))end
 else for i=bestI,1,-1 do table.insert(leg,Vector3.new(unpack(wp[i])))end end
 return leg
end
local function routeTo(state,pos,mode)

 if nearVan(pos,3) then return false end
 local current=roomAt(state.root.Position);local dest=roomAt(pos);if not current or not dest then return false end
 -- Only a live chase may enter the spawn area; nothing else heads there.
 if mode~='Chase' and nearSpawn and nearSpawn(dest) then return false end
 local leg=stairLeg(state.root.Position,dest.level)
 if leg then current=roomAt(leg[#leg])or current end
 local links=shortest(current.name,dest.name);if not links then return false end
  local goal=safePoint(dest,pos,2)
 -- A goal inside a stair room (e.g. a player on the landing) goes to that floor's end of the flight, never mid-air over the shaft.
 if dest.type=='Stair'then local e=stairEdgeOf(dest.name);if e then local wp=e.waypoints;goal=Vector3.new(unpack(dest.level>0 and wp[#wp]or wp[1]))end end
 state.room=current;state.destination=dest
 if leg then
  state.points=leg
  for _,p in ipairs(makeWaypoints(current,links,goal))do table.insert(state.points,p)end
 elseif clearSegment(state.root.Position,goal) then state.points={goal}
 else
  state.points=makeWaypoints(current,links,goal)
  -- Skip room-center detours only when the actual corridor is clear.
  local skip=1
  for i,p in ipairs(state.points) do
   if math.abs(p.Y-state.root.Position.Y)>.3 then break end
   if clearSegment(state.root.Position,p) then skip=i end
  end
  for _=1,skip-1 do table.remove(state.points,1) end
 end
 state.pointIndex=1;state.pauseUntil=0;state.model:SetAttribute('TargetRoom',dest.name);setMode(state,mode);return true

end
local function retreat(state,now,avoid)
 local current=roomAt(state.root.Position);local best,dist=nil,-1
 for _,r in ipairs(graph.rooms) do if not mansion:GetAttribute('LegacyFallback') and not r.name:find('Starter') then local d=(center(r)-(avoid or state.root.Position)).Magnitude;if d>dist and shortest(current.name,r.name) then best,dist=r,d end end end
 state.target=nil;state.lastSeen=nil;state.lastSeenPosition=nil;state.clue=nil;state.clueUntil=nil;state.searchUntil=nil
 state.catching=nil;state.points=nil;state.destination=nil;state.repathAt=0;state.pauseUntil=0
 state.model:SetAttribute('LurePosition',nil);state.model:SetAttribute('LureUntil',nil)
 setMode(state,'Retreat')
 if best then routeTo(state,center(best),'Retreat') end
 if avoid and current then
  local away=Vector3.new(state.root.Position.X-avoid.X,0,state.root.Position.Z-avoid.Z)
  if away.Magnitude<.1 then away=state.root.CFrame.LookVector end
  local escape=safePoint(current,state.root.Position+away.Unit*8,2)
  if (escape-state.root.Position).Magnitude>1 and (escape-avoid).Magnitude>(state.root.Position-avoid).Magnitude and clearSegment(state.root.Position,escape) then
   -- Step away first, then keep going on the long route to the far room (a lone 8-stud step left a fleeing monster standing).
   if state.points then table.insert(state.points,state.pointIndex or 1,escape) else state.points={escape};state.pointIndex=1;state.destination=current end
  end
 end
 state.retreatUntil=now+4
end
-- Route length through doors and stairs; locked doors are respected lazily.
local routes=Topology.New(graph,blocked)
local function routeDistance(a,b)
 local ra,rb=roomAt(a),roomAt(b)
 if not ra or not rb then return (a-b).Magnitude end
 return routes:Distance(a,ra.name,b,rb.name)
end
local BrainModule=require(script:WaitForChild('MonsterIntelligence'))
local Brain=BrainModule.New({
 rng=rng,roomAt=roomAt,rooms=roomByName,adjacency=adjacency,center=center,safePoint=safePoint,
 sees=sees,nearVan=nearVan,routeTo=routeTo,setMode=setMode,routeDistance=routeDistance,level=Topology.Level,
 disengage=function(s,avoid) if disengageMonster then disengageMonster(s,avoid) end end,
 reachable=function(a,b)return a and b and shortest(a.name,b.name)~=nil end,
 crowded=function(s,p) -- another monster already chases p, and p has not provoked s
  if s.target==p then return false end
  local at=s.model:GetAttribute('ProvokedAt')
  if s.model:GetAttribute('ProvokedBy')==p.UserId and at and workspace:GetServerTimeNow()-at<PROVOKE_SECONDS then return false end
  for _,list in pairs(active)do for _,o in list do if o~=s and o.target==p and o.model.Parent then return true end end end
  return false
 end,
 closets=function()local f=mansion:FindFirstChild('Closets');return f and f:GetChildren()or{}end,
 round=function()return game.ReplicatedStorage:FindFirstChild('RecoveryRound')end,
})
local noiseMotion={}
local lights={}
for _,l in mansion:GetDescendants()do if l:IsA('PointLight')or l:IsA('SpotLight')then table.insert(lights,l)end end
local function lightVisibility(pos)
 local value=DARK_VISIBILITY
 for _,l in lights do
  local part=l.Parent
  -- part is nil for a light destroyed by a map rebuild (live error, 559x on V1369)
  if part and l.Enabled and part:IsA('BasePart') and (part.Position-pos).Magnitude<l.Range then value=math.max(value,.8);break end
 end
 return value
end
local function eligiblePlayer(p)
 local c=p.Character;local r=c and c:FindFirstChild('HumanoidRootPart');local h=c and c:FindFirstChildOfClass('Humanoid')
 -- A close-up yes/no card is up (ChoiceDeciding): monsters can't see, hear or reach them (owner 2026-10-25).
 return r,h,h and h.Health>0 and p:GetAttribute('MissionActive')==true and not p:GetAttribute('RoundDead') and p:GetAttribute('ChoiceDeciding')~=true
end
-- Monster roles (2026-10-22): per-kind attacks, 100 HP damage, spinning laser, closet seeker. See MonsterAbilities.
local Abilities=require(script:WaitForChild('MonsterAbilities')).New({Jumpscare=require(script:WaitForChild('MonsterJumpscare')),Protection=Protection,Sighted=Sighted,NearVan=nearVan,Audio=Audio,
 retreat=function(s,now,avoid)retreat(s,now,avoid)end,routeTo=routeTo,setMode=setMode,sees=sees,eligible=eligiblePlayer,
 closets=function()local f=mansion:FindFirstChild('Closets');return f and f:GetChildren()or{}end,
 -- Lonely Mittens / Wind-Up Dancer (Monsters build 2026-10-27): the recovery cart (company for a soloist, a rolling cart
 -- gives you away) and a way to wipe what the brain remembers about one player (so a dropped hunt does not turn into a search).
 cart=function()local c=mansion.Interactive:FindFirstChild('RecoveryCart');return c and c:GetAttribute('Kind')=='cart'and c.PrimaryPart and c or nil end,
 forget=function(s,p)if s.brain and s.brain.knowledge then s.brain.knowledge[p.UserId]=nil end;if s.target==p then s.target=nil end end})
local function perceive(state,now)
 if nearVan(state.root.Position,4)then state.target=nil;return end
 local observations={}
 -- Level 1 is the gentle first impression: monsters see 33% less far (range, falloff and instant-notice).
 local rr=game:GetService('ReplicatedStorage'):FindFirstChild('RecoveryRound')
 local hush=omen()=='Hush' and .8 or 1 -- Hush omen: sight range, near sense and hearing x0.8 (owner 2026-10-26: was .6)
 local levelSight=(rr and rr:GetAttribute('Round')==1 and .85 or 1)*hush -- was .67
 for _,p in Players:GetPlayers()do
  -- ...and forget them: no last-seen spot to walk to and stand on while they choose.
  local erased=state.model:GetAttribute('ErasedUserId')==p.UserId and now<(state.model:GetAttribute('ErasedUntil')or 0) -- TrailEraser (ItemBatch9)
  if p:GetAttribute('ChoiceDeciding')==true or erased then
   if state.brain then state.brain.knowledge[p.UserId]=nil end
   if state.target==p then state.target=nil end
   if erased then state.lastSeen=nil;state.lastSeenPosition=nil;state.clue=nil;state.clueUntil=nil;state.searchUntil=nil end
  end
  local r,h,alive=eligiblePlayer(p)
  if alive and r then
   local room=roomAt(r.Position)
   local inMap=room and r.Position.X>=room.x1-NEAR_MARGIN and r.Position.X<=room.x2+NEAR_MARGIN and r.Position.Z>=room.z1-NEAR_MARGIN and r.Position.Z<=room.z2+NEAR_MARGIN -- doorways sit between room rectangles
   local testProtected=workspace:GetServerTimeNow()<(p:GetAttribute('ClosetProtectedUntil')or 0) or p:GetAttribute('AdminGod')==true
   if inMap and not nearVan(r.Position,3) and not testProtected and now>(p:GetAttribute('DisguiseUntil')or 0) and not Abilities:Ignores(state,p) and p:GetAttribute('ChoiceDeciding')~=true then -- a close-up card is up: not a target at all (owner 2026-10-25)
    local hidden=p:GetAttribute('Hiding')==true or p:GetAttribute('ClosetState')~=nil
    local fogged=now<(p:GetAttribute('FogCoverUntil')or 0)or now<(state.model:GetAttribute('FogBlindUntil')or 0) -- PocketFogger (ItemBatch6): only near sense in fog
    local pos=r.Position;local delta=pos-(state.root.Position+Vector3.new(0,2.5,0));local distance=delta.Magnitude
    local cursed=(p:GetAttribute('BlackCatCurse')and 1.45 or 1)*((p:GetAttribute('CrownedUntil')or 0)>workspace:GetServerTimeNow()and 1.3 or 1)*levelSight*(state.dull or 1)*(p:GetAttribute('OmenShrunk')and .75 or 1) -- a dull monster (the Lantern) sees less far
    local speed=Vector3.new(r.AssemblyLinearVelocity.X,0,r.AssemblyLinearVelocity.Z).Magnitude
    -- Close by it senses you in any direction (no blind spot right behind it); running carries further.
    local near=NEAR_BY_ROUND[state.level or 1] or {NEAR_SENSE,NEAR_SENSE_RUNNING}
    local close=distance<(speed>12 and near[2] or near[1])*hush
    local facing=close or distance<.1 or state.root.CFrame.LookVector:Dot(delta.Unit)>SIGHT_FACING_DOT
    -- Torso first, then the head: a low monster's ray to the torso clips table-height furniture boxes.
    if not hidden and(close or not fogged)and distance<SIGHT_RANGE*cursed and facing and(sees(state,pos)or sees(state,pos+Vector3.new(0,1.6,0)))then
     local stance=p:GetAttribute('Crouching')and((state.level or 1)>=3 and .75 or .55)or 1 -- crouching hides less from round 3
     local visibility=math.clamp((1-distance/(SIGHT_FALLOFF*cursed))*lightVisibility(pos)*stance*(speed>18 and 1.7 or speed>2 and 1.2 or .85),SIGHT_MIN_VISIBILITY,2.5)
     if state.dull then visibility*=state.dull end
     if close or distance<SIGHT_INSTANT_RANGE*levelSight*(state.dull or 1) then visibility=2.5 end
     table.insert(observations,{player=p,position=pos,velocity=r.AssemblyLinearVelocity,visibility=visibility,gaze=r.CFrame.LookVector})
    end
   end
  end
 end
 local lure=state.model:GetAttribute('LurePosition')
 local expires=state.model:GetAttribute('LureUntil')or 0
 if lure and now<expires and state.consumedLure~=lure then
  state.consumedLure=lure
  Brain:Init(state,now)
  Brain:Hear(state,{position=lure,loudness=45,kind='Object',time=now},now)
 end
 Brain:Update(state,observations,now)
end
local function sampleNoise(now)
 local bus=ServerStorage:FindFirstChild('MonsterEvidence');if not bus then return end
 for _,p in Players:GetPlayers()do
  local r,h,alive=eligiblePlayer(p)
  if not alive or not r then noiseMotion[p]=nil;continue end
  local n=noiseMotion[p]or{next=0,voice=0};noiseMotion[p]=n
  local hidden=p:GetAttribute('Hiding')or p:GetAttribute('ClosetState')
  local testProtected=workspace:GetServerTimeNow()<(p:GetAttribute('ClosetProtectedUntil')or 0) or p:GetAttribute('AdminGod')==true
  if not hidden and not testProtected and not nearVan(r.Position,3)then
   if now>n.next then
    n.next=now+.65
    local v=Vector3.new(r.AssemblyLinearVelocity.X,0,r.AssemblyLinearVelocity.Z).Magnitude
    if v>2 then bus:Fire(r.Position,v>18 and 30 or p:GetAttribute('Crouching')and 5 or 12,v>18 and 'Running'or 'Footsteps',p)end
   end
   local stamp=p:GetAttribute('VoiceNoiseAt')or 0;local level=p:GetAttribute('VoiceNoiseLevel')or 0
   if stamp>n.voice and now-stamp<1 and level>.12 then n.voice=stamp;bus:Fire(r.Position,math.clamp(level*80,12,70),'Speaking',p)end
  end
 end
 local trails=Workspace:FindFirstChild('SpitTrails')
 if trails then for _,trail in trails:GetChildren()do
  if trail:IsA('BasePart')and not trail:GetAttribute('AIHeardEvent')and now-(trail:GetAttribute('BornAt')or 0)<1 then
   trail:SetAttribute('AIHeardEvent',true);bus:Fire(trail.Position,25,'Spit',Players:GetPlayerByUserId(trail:GetAttribute('OwnerUserId')or 0))
  end
 end end
end
-- Rooms within CAMP_RADIUS walking distance of the player spawn are off-limits to idle patrols.
local campCache={}
nearSpawn=function(r)
    if campCache[r.name]==nil then
        local spawnPoint=mansion:GetAttribute('SpawnPosition') or Workspace.SpawnLocation.Position
        campCache[r.name]=routeDistance(center(r)+Vector3.new(0,2,0),spawnPoint)<CAMP_RADIUS
    end
    return campCache[r.name]
end
local function chooseDestination(state)
    -- Part-way up a flight: walk to its nearer end first; the next pick starts from a real floor.
    local pos=state.root.Position
    local leg=stairLeg(pos,pos.Y>=FLOOR/2 and 1 or 0)
    if leg then
     state.points=leg;state.pointIndex=1;state.destination=roomAt(leg[#leg])or state.room
     return
    end
    local candidates={};local least=math.huge
    local others={}
    if rng:NextNumber()<SPREAD_CHANCE and not (state.model:GetAttribute('ProvokedAt') and workspace:GetServerTimeNow()-state.model:GetAttribute('ProvokedAt')<PROVOKE_SECONDS) then
     for _,list in pairs(active)do for _,o in list do if o~=state and o.model.Parent and o.root then table.insert(others,o.root.Position);if o.destination then table.insert(others,center(o.destination))end end end end
    end
    local function crowdedRoom(r)local c=center(r);for _,q in others do if (q-c).Magnitude<SPREAD_RADIUS then return true end end;return false end
    -- Nearby rooms first, then further afield, before ever patrolling the spawn area.
    -- A roamy monster (the Lantern) heads for rooms several doors away instead of the next one over.
    local passes=state.roamy and {{hops=5,min=2,avoid=true},{hops=8,avoid=true},{hops=3,avoid=false}} or {{hops=2,avoid=true},{hops=6,avoid=true},{hops=2,avoid=false}}
    for _,pass in ipairs(passes) do
        for _,r in ipairs(graph.rooms) do
            local localRoute=shortest(state.room.name,r.name)
            local avoiding=pass.avoid and state.avoidUntil and os.clock()<state.avoidUntil and routeDistance(center(r)+Vector3.new(0,2,0),state.avoidPoint)<AVOID_RADIUS
            if r.name~=state.room.name and not nearVan(center(r),4) and localRoute and #localRoute<=pass.hops and #localRoute>=(pass.min or 0) and not (pass.avoid and nearSpawn(r)) and not avoiding and not (pass.avoid and crowdedRoom(r)) then
                local count=state.visits[r.name] or 0
                if count<least then least=count;candidates={r}
                elseif count==least then table.insert(candidates,r) end
            end
        end
        if #candidates>0 then break end
    end
    if #candidates==0 then state.pauseUntil=os.clock()+1;return end
    local dest=candidates[rng:NextInteger(1,#candidates)]
    local links=shortest(state.room.name,dest.name)
    if not links then return end
    local goal=if graph.seed then center(dest) else safePoint(dest,center(dest)+Vector3.new(rng:NextNumber(-3,3),0,rng:NextNumber(-3,3)),3)
    state.points=makeWaypoints(state.room,links,goal)
    state.pointIndex=1;state.destination=dest
    state.model:SetAttribute('TargetRoom',dest.name)
end
-- Lost sight of the player: walk to a reachable room far (by route) from where they
-- were, outside the spawn area, and keep patrols away from that spot for a while.
disengageMonster=function(state,avoid)
 state.avoidPoint=avoid;state.avoidUntil=os.clock()+AVOID_SECONDS
 local current=roomAt(state.root.Position);if not current then return end
 local best,bestScore
 for _,r in ipairs(graph.rooms) do
  if r~=current and r.type~='Stair' and not nearSpawn(r) and not nearVan(center(r),4) then
   local links=shortest(current.name,r.name)
   if links and #links<=6 then
    local away=math.min(400,routeDistance(center(r)+Vector3.new(0,2,0),avoid))
    local score=away-#links*4
    if not bestScore or score>bestScore then best,bestScore=r,score end
   end
  end
 end
 if not (best and routeTo(state,center(best),'Retreat')) then state.points=nil;setMode(state,'Patrol') end
end
local function unobstructed(state,direction,distance)
    return vanSegmentSafe(state.root.Position,state.root.Position+direction*distance) and Workspace:Blockcast(CFrame.new(state.root.Position+Vector3.new(0,2.4,0)),MOVE_CLEARANCE_SIZE,direction*distance,sightParams)==nil
end
-- Last resort when no steer angle or detour works: a free-standing cart in the way is nudged sideways.
-- Never a cart someone holds, one selling or near the van, never fast, and at most one nudge per cart per second.
local CART_NUDGE_SPEED=5 -- studs/s sideways; the cart's own friction/decay stops it within ~a stud
local CART_NUDGE_COOLDOWN=1
local cartNudgedAt={}
local function nudgeBlockingCart(state,direction,distance)
 local hit=Workspace:Blockcast(CFrame.new(state.root.Position+Vector3.new(0,2.4,0)),MOVE_CLEARANCE_SIZE,direction*(distance+1.5),sightParams)
 if not hit then return false end
 local cart=hit.Instance:FindFirstAncestorOfClass('Model')
 while cart and cart.Parent~=mansion.Interactive do cart=cart.Parent:FindFirstAncestorOfClass('Model')end
 if not cart or cart:GetAttribute('Kind')~='cart'or cart:GetAttribute('HeldBy')or not cart.PrimaryPart then return false end
 local body=cart.PrimaryPart;if body.Anchored or nearVan(body.Position,6)then return false end
 for _,m in ipairs(mansion.Interactive:GetChildren())do if m:GetAttribute('Selling')then return false end end
 local now=os.clock()
 -- A cart that will not move (pinned against a wall) is given up on: the old re-route takes over.
 if now-(state.cartNudgeWindow or 0)>6 then state.cartNudgeWindow=now;state.cartNudgeCount=0 end
 if (state.cartNudgeCount or 0)>=4 then return false end
 if now-(cartNudgedAt[cart]or 0)<CART_NUDGE_COOLDOWN then return true end
 cartNudgedAt[cart]=now;state.cartNudgeCount=(state.cartNudgeCount or 0)+1
 -- Push to whichever side of the monster's path the cart already leans toward, so it slides clear.
 local side=Vector3.new(-direction.Z,0,direction.X)
 if side:Dot(body.Position-state.root.Position)<0 then side=-side end
 local v=body.AssemblyLinearVelocity
 body.AssemblyLinearVelocity=Vector3.new(0,v.Y,0)+side*CART_NUDGE_SPEED+direction*1.5
 state.model:SetAttribute('CartNudges',(state.model:GetAttribute('CartNudges')or 0)+1)
 return true
end
-- Bounded local A*: only collision-tested positions, no player information.
local function localDetour(state,target,now)
 if now<(state.detourRetryAt or 0)or math.abs(target.Y-state.root.Position.Y)>.3 then return false end
 state.detourRetryAt=now+1.5
 local origin=state.root.Position
 local spacing=3;local radius=5;local nodes={};local open={}
 local function key(x,z)return x..':'..z end
 local function add(x,z,g,parent)
  local k=key(x,z);local prior=nodes[k]
  if prior and prior.g<=g then return end
  local pos=origin+Vector3.new(x*spacing,0,z*spacing)
  local n={x=x,z=z,p=pos,g=g,f=g+(target-pos).Magnitude,parent=parent};nodes[k]=n;table.insert(open,n)
 end
 add(0,0,0,nil)
 local expanded=0;local found
 while #open>0 and expanded<96 do
  local best=1;for i=2,#open do if open[i].f<open[best].f then best=i end end
  local n=table.remove(open,best)
  if n.closed or nodes[key(n.x,n.z)]~=n then continue end
  n.closed=true;expanded+=1
  if n.parent and (target-n.p).Magnitude<(target-origin).Magnitude-1.5 and clearSegment(n.p,target)then found=n;break end
  for _,offset in {{1,0},{-1,0},{0,1},{0,-1}}do
   local x,z=n.x+offset[1],n.z+offset[2]
   if math.abs(x)>radius or math.abs(z)>radius then continue end
   local p=origin+Vector3.new(x*spacing,0,z*spacing)
   local old=nodes[key(x,z)]
   if (not old or not old.closed)and clearSegment(n.p,p)then add(x,z,n.g+spacing,n)end
  end
 end
 state.model:SetAttribute('LocalDetourExpanded',expanded)
 if not found then return false end
 local path={};local n=found
 while n and n.parent do table.insert(path,1,n.p);n=n.parent end
 for i=#path,1,-1 do table.insert(state.points,state.pointIndex,path[i])end
 state.progressTarget=nil;state.waypointProgressAt=now
 state.model:SetAttribute('LocalDetours',(state.model:GetAttribute('LocalDetours')or 0)+1)
 return true
end

-- Cart thief: a creature that reaches the recovery cart pulls ONE stored item out and carries it to a room a
-- fair walk from the players (not the furthest one, never near the van or spawn), then drops it there as
-- ordinary loot. While carrying it ignores players.
local STEAL_RANGE=7.5 -- flat studs from the creature to the cart body
local STEAL_COOLDOWN,STEAL_GLOBAL_COOLDOWN=60,30 -- seconds per creature / shared by every creature
local STEAL_GIVE_UP=45 -- carrying this long drops the item where it stands
local STEAL_DROP_WANT,STEAL_DROP_LEAST,STEAL_DROP_MAX_WALK=80,50,170 -- drop spot: route studs from the nearest player / the carrier's longest walk
local CART_SEEK_RANGE,CART_SEEK_COOLDOWN=150,30 -- an idle creature this close (route studs) wanders to a loaded, unattended cart
local SAFE_VAN_MARGIN=30 -- drop and teleport spots stay this far beyond the van's safe radius
-- Anti-loop: a creature that keeps trying to move but stays inside STUCK_RADIUS is teleported to a safe spot
-- away from the players. Next to the cart it gives up quickly; anywhere else it gets longer.
local STUCK_RADIUS,STUCK_CART_RADIUS=10,18
local STUCK_CART_SECONDS,STUCK_ANY_SECONDS=6,20
local TELEPORT_WANT,TELEPORT_LEAST=110,60
local lastStealAt=-math.huge
local wallParams=RaycastParams.new();wallParams.FilterType=Enum.RaycastFilterType.Include;wallParams.FilterDescendantsInstances={collision};wallParams.RespectCanCollide=true
local safeOverlap=OverlapParams.new();safeOverlap.FilterType=Enum.RaycastFilterType.Include;safeOverlap.FilterDescendantsInstances={collision,mansion.Interactive,mansion:FindFirstChild('Furniture')};safeOverlap.RespectCanCollide=true
local function recoveryCart()
 local c=mansion.Interactive:FindFirstChild('RecoveryCart')
 return c and c:GetAttribute('Kind')=='cart' and c.PrimaryPart and c or nil
end
local function cartLoaded()
 for _,m in ipairs(mansion.Interactive:GetChildren())do if m:GetAttribute('CargoStored') and not m:GetAttribute('Selling') then return true end end
 return false
end
-- Same floor and clearance test as ValidMonsterSpawn, and clear of other creatures.
local function standable(p,self)
 local floor=Workspace:Raycast(p+Vector3.new(0,2,0),Vector3.new(0,-4,0),sightParams)
 if not floor or floor.Normal.Y<.9 or math.abs(floor.Position.Y-p.Y)>.25 then return false end
 for _,m in ipairs(folder:GetChildren())do if m~=self and m.PrimaryPart and (m.PrimaryPart.Position-p).Magnitude<10 then return false end end
 return #Workspace:GetPartBoundsInBox(CFrame.new(p+Vector3.new(0,5,0)),Vector3.new(6,9.6,6),safeOverlap)==0
end
-- A spot about `want` route studs from the nearest living player or `avoid` point (never closer than `least`),
-- reachable from `from` within `maxWalk`, preferring the same floor and a short walk. Never near the van,
-- spawn, stairs or starter rooms.
local function fairSpot(state,from,want,least,maxWalk,needClearance,avoid)
 local players=table.clone(avoid or {})
 for _,p in Players:GetPlayers()do local r,_,alive=eligiblePlayer(p);if alive and r then table.insert(players,r.Position)end end
 local level=Topology.Level(from.Y)
 local options={}
 for _,r in ipairs(graph.rooms)do
  if r.type~='Stair' and not r.name:find('Starter') and not (graph.closed and graph.closed[r.name]) and not nearSpawn(r) then
   local base=center(r);local samples={base}
   if r.type=='Hall' then for _,f in {.15,.85}do
    if r.x2-r.x1>r.z2-r.z1 then table.insert(samples,Vector3.new(r.x1+(r.x2-r.x1)*f,base.Y,base.Z))
    else table.insert(samples,Vector3.new(base.X,base.Y,r.z1+(r.z2-r.z1)*f))end
   end end
   for _,p in samples do
    local walk=routeDistance(from,p+Vector3.new(0,2,0))
    if not nearVan(p,SAFE_VAN_MARGIN) and walk<(maxWalk or math.huge) then
     local away=1000
     for _,q in players do away=math.min(away,routeDistance(p+Vector3.new(0,2,0),q),(p-q).Magnitude*1.75)end
     table.insert(options,{p=p,room=r,away=away,cost=math.abs(math.min(away,1000)-want)+(r.level~=level and 40 or 0)+walk*.1})
    end
   end
  end
 end
 table.sort(options,function(a,b)return a.cost<b.cost end)
 for _,minimum in {least,0}do
  for _,o in options do if o.away>=minimum and (not needClearance or standable(o.p,state.model)) then return o.p,o.room end end
 end
end
local function itemApi()return ServerStorage:FindFirstChild('CursedItemApi')end
local function dropLoot(state)
 local carry=state.carry;state.carry=nil;state.model:SetAttribute('CarryingLoot',nil)
 if not carry or not carry.item.Parent or not carry.item.PrimaryPart then return end
 local item=carry.item
 local weld=item.PrimaryPart:FindFirstChild('MonsterCarryWeld');if weld then weld:Destroy()end
 -- Dropped at the creature's feet: a walkable floor spot, never inside a wall.
 item:PivotTo(CFrame.new(state.root.Position+Vector3.new(0,item.PrimaryPart.Size.Y/2+.6,0))*item:GetPivot().Rotation)
 local api=itemApi()
 if not (api and api:Invoke('monsterDrop',nil,item)) then item:SetAttribute('MonsterCarried',nil)end
end
-- Teleports a looping or stuck creature to a safe spot away from the players; carried loot is left there.
local function teleportSafe(state,now,reason)
 if now<(state.teleportReadyAt or 0) then return false end
 state.teleportReadyAt=now+4
 local spawnPoint=mansion:GetAttribute('SpawnPosition') or Workspace.SpawnLocation.Position
 local from=state.root.Position
 local cart=recoveryCart()
 local spot,room=fairSpot(state,spawnPoint,TELEPORT_WANT,TELEPORT_LEAST,nil,true,{from,cart and cart.PrimaryPart.Position})
 if not spot then state.model:SetAttribute('SafeTeleportFailed',reason);return false end
 state.root.CFrame=CFrame.new(spot)*CFrame.Angles(0,state.yaw,0)
 if state.carry then dropLoot(state) end
 state.room=room;state.points=nil;state.destination=nil;state.target=nil;state.catching=nil;state.progressTarget=nil
 state.stallPosition=nil;state.stallSince=nil;state.stuckAnchor=spot;state.stuckTime=0
 state.lastPosition=spot;state.lastProgress=now;state.pauseUntil=now+1
 state.avoidPoint=from;state.avoidUntil=now+AVOID_SECONDS -- patrols stay away from where it was stuck
 if state.brain then state.brain.engaged=false;state.brain.disengageUntil=now+10 end
 setMode(state,'Patrol')
 state.model:SetAttribute('CurrentRoom',room.name);state.model:SetAttribute('LastSafeTeleport',reason)
 state.model:SetAttribute('SafeTeleports',(state.model:GetAttribute('SafeTeleports')or 0)+1)
 return true
end
local function routeCarry(state)
 local cart=recoveryCart()
 local spot=fairSpot(state,state.root.Position,STEAL_DROP_WANT,STEAL_DROP_LEAST,STEAL_DROP_MAX_WALK,false,{cart and cart.PrimaryPart.Position})
 state.carry.spot=spot;state.points=nil;state.destination=nil;state.pauseUntil=0
 return spot~=nil and routeTo(state,spot,'Steal')
end
local function tryStealFromCart(state,now)
 if state.mode=='Chase' or now-lastStealAt<STEAL_GLOBAL_COOLDOWN or now<(state.stealReadyAt or 0) then return false end
 local cart=recoveryCart();if not cart then return false end
 local body=cart.PrimaryPart.Position;local pos=state.root.Position
 if math.abs(body.Y-pos.Y)>5 or Vector3.new(body.X-pos.X,0,body.Z-pos.Z).Magnitude>STEAL_RANGE or nearVan(body,6) then return false end
 local eye=pos+Vector3.new(0,2.5,0)
 if Workspace:Raycast(eye,body-eye,wallParams) then return false end -- no grabbing through a wall
 local recovery=ServerStorage:FindFirstChild('RecoveryApi');local api=itemApi()
 if not recovery or not api then return false end
 state.stealReadyAt=now+3
 local item=recovery:Invoke('monsterTake') -- exactly one item, chosen and released by the cart's owner
 if not item then return false end
 if not api:Invoke('monsterCarry',nil,item) then item:SetAttribute('MonsterCarried',nil);return false end
 item:PivotTo(state.root.CFrame*CFrame.new(0,3.2,-1.8))
 local w=Instance.new('WeldConstraint');w.Name='MonsterCarryWeld';w.Part0=state.root;w.Part1=item.PrimaryPart;w.Parent=item.PrimaryPart
 lastStealAt=now;state.stealReadyAt=now+STEAL_COOLDOWN
 state.carry={item=item,giveUpAt=now+STEAL_GIVE_UP}
 state.target=nil;state.catching=nil
 state.model:SetAttribute('CarryingLoot',item:GetAttribute('DisplayName') or item.Name)
 state.model:SetAttribute('CartThefts',(state.model:GetAttribute('CartThefts')or 0)+1)
 Audio.Play('CargoStore',state.root)
 if not routeCarry(state) then teleportSafe(state,now,'StealNoRoute');return true end
 -- Step back from the basket first so the route does not start by walking into the cart.
 local away=Vector3.new(pos.X-body.X,0,pos.Z-body.Z)
 if away.Magnitude>.1 and state.points then local back=pos+away.Unit*4;if clearSegment(pos,back) then table.insert(state.points,1,back);state.pointIndex=1 end end
 return true
end
-- An idle creature near a loaded cart nobody is pushing walks up to it (stopping just short of the basket).
local function seekCart(state,now)
 if state.mode~='Patrol' or now<(state.cartSeekAt or 0) or now<(state.stealReadyAt or 0) or now-lastStealAt<STEAL_GLOBAL_COOLDOWN then return false end
 state.cartSeekAt=now+CART_SEEK_COOLDOWN
 local cart=recoveryCart();if not cart or cart:GetAttribute('HeldBy') or not cartLoaded() then return false end
 local body=cart.PrimaryPart.Position;local pos=state.root.Position
 if nearVan(body,6) or routeDistance(pos,body)>CART_SEEK_RANGE then return false end
 local side=Vector3.new(pos.X-body.X,0,pos.Z-body.Z);side=side.Magnitude>.1 and side.Unit or Vector3.new(0,0,1)
 return routeTo(state,Vector3.new(body.X,Topology.Level(body.Y)*FLOOR,body.Z)+side*4.5,'Patrol')
end

-- Collar Crawler = weeping angel (owner, 2026-10-24): it cannot move or attack while any living player is looking at it.
-- Each client reports the crawlers on its screen and not blocked by walls (CreatureAnimateClient, ~8 Hz).
local WATCH_HOLD=.35 -- seconds a sighting keeps it frozen (covers a missed report)
local sightEvent=game:GetService('ReplicatedStorage'):FindFirstChild('MonsterSightEvent')or Instance.new('RemoteEvent')
sightEvent.Name='MonsterSightEvent';sightEvent.Parent=game:GetService('ReplicatedStorage')
local watchedUntil=setmetatable({},{__mode='k'})
sightEvent.OnServerEvent:Connect(function(p,list)
 if type(list)~='table'or #list>8 or p:GetAttribute('MissionActive')~=true or p:GetAttribute('RoundDead')then return end
 local c=p.Character;local h=c and c:FindFirstChildOfClass('Humanoid');local head=c and c:FindFirstChild('Head')
 if not h or h.Health<=0 or not head then return end
 for _,m in list do
  if typeof(m)=='Instance'and m:IsA('Model')and m.Parent and m:GetAttribute('CreatureKind')=='Crawler'and m.PrimaryPart and(m.PrimaryPart.Position-head.Position).Magnitude<160 then
   watchedUntil[m]=os.clock()+WATCH_HOLD
  end
 end
end)
local function step(state,dt)
    if not state.model.Parent then return end
    local now=os.clock()
    if state.model:GetAttribute('CreatureKind')=='Crawler'then
     local watched=now<(watchedUntil[state.model]or 0)or now<(state.model:GetAttribute('GnomeWatchedUntil')or 0) -- Watch Gnome (MonsterBatch) stares it frozen too
     if state.model:GetAttribute('Watched')~=watched then state.model:SetAttribute('Watched',watched)end
     if watched then state.model:SetAttribute('Walking',false);state.lastProgress=now;state.stallPosition=nil;state.stallSince=nil;return end
    end
    if nearVan(state.root.Position,4) and not state.hunt then -- the pup's Lantern stays on its player (Studio van test) and never wanders
        state.target=nil;state.lastSeen=nil;state.clue=nil;state.points=nil
        setMode(state,'AvoidVan')
        local v=vanPosition();local away=Vector3.new(state.root.Position.X-v.X,0,state.root.Position.Z-v.Z)
        if away.Magnitude<.1 then away=Vector3.new(0,0,-1) else away=away.Unit end
        local travel=18*dt
        -- Exit outward; never steer deeper into the protected radius.
        local origin=state.root.Position+Vector3.new(0,2.4,0)
        if not Workspace:Blockcast(CFrame.new(origin),Vector3.new(1.6,4.4,1.6),away*(travel+.2),sightParams) then
            state.yaw=math.atan2(-away.X,-away.Z)
            state.root.CFrame=CFrame.new(state.root.Position+away*travel)*CFrame.Angles(0,state.yaw,0)
            state.room=roomAt(state.root.Position);state.lastPosition=state.root.Position;state.lastProgress=now
            state.model:SetAttribute('Walking',true);state.model:SetAttribute('MoveSpeed',18)
        else state.model:SetAttribute('Walking',false) end
        return
    elseif state.mode=='AvoidVan' then
        state.points=nil;state.pauseUntil=0;setMode(state,'Patrol')
    end
    if state.mode=='Chase' and typeof(state.target)=='Instance' and state.target:IsA('Player') and os.clock()>(chasedAt[state.target] or 0)+.25 then
        chasedAt[state.target]=os.clock();state.target:SetAttribute('ChasedUntil',workspace:GetServerTimeNow()+1.2) -- Adrenaline omen reads it
    end
    -- A monster in the middle of its attack (carrying, lasering, pulling someone out) does nothing else.
    if Abilities:Step(state,now,dt) then state.stallPosition=nil;state.stallSince=nil;state.lastProgress=now;return end
    -- Gear shop: a blasted monster flees and a hypnotized one forgets players; neither perceives or catches anyone.
    local fleeing=now<(state.model:GetAttribute('FleeUntil') or 0);local hypnotized=now<(state.model:GetAttribute('HypnoUntil') or 0)
    if fleeing or hypnotized or state.carry then state.target=nil;state.catching=nil;if hypnotized and state.mode=='Chase' then setMode(state,'Patrol')end
    elseif now>(state.perceptionAt
 or 0) and not (state.debugUntil and now<state.debugUntil) and not Abilities:HoldsRoute(state,now) then perceive(state,now);state.perceptionAt=now+TUNE.PerceptionInterval end
    if now<(state.model:GetAttribute('StunnedUntil') or 0) or now<(state.model:GetAttribute('CalmUntil') or 0) then state.stallPosition=nil;state.stallSince=nil;state.model:SetAttribute('Walking',false);return end
    if state.catching then
        if state.catching.Parent and state.catching:GetAttribute('MonsterJumpscareActive')then state.stallPosition=nil;state.stallSince=nil;state.model:SetAttribute('Walking',false);return end
        state.catching=nil
    end
    if now>(state.lastGrab or 0)+2.5 then
        for _,player in ipairs(Players:GetPlayers()) do
            local char=player.Character;local root=char and char:FindFirstChild('HumanoidRootPart');local hum=char and char:FindFirstChildOfClass('Humanoid')
            if state.mode=='Chase' and state.target==player and not Abilities:Ignores(state,player) and root and hum and hum.Health>0 and not nearVan(root.Position,3) and not Protection.IsProtected(player) and now>(player:GetAttribute('DisguiseUntil') or 0) and Vector3.new(root.Position.X-state.root.Position.X,0,root.Position.Z-state.root.Position.Z).Magnitude<CATCH_RANGE and math.abs(root.Position.Y-state.root.Position.Y)<12 and sees(state,root.Position) then
                if Abilities:Catch(state,player,now) or require(script.MonsterJumpscare).Start(player,state.model)then
                 state.lastGrab=now;state.catching=player;state.model:SetAttribute('Walking',false)
                 state.model:SetAttribute('LastGrabUserId',player.UserId);state.model:SetAttribute('LurePosition',root.Position);state.model:SetAttribute('LureUntil',now+8)
                 return
                end
            end
        end
    end
    if state.carry then
        if not state.carry.item.Parent or state.carry.item:GetAttribute('MonsterCarried')~=true then state.carry=nil;state.model:SetAttribute('CarryingLoot',nil)
        elseif now>state.carry.giveUpAt then
            if nearVan(state.root.Position,SAFE_VAN_MARGIN) then teleportSafe(state,now,'CarryTimeout') else dropLoot(state);state.points=nil;setMode(state,'Patrol') end
        end
    elseif tryStealFromCart(state,now) then state.model:SetAttribute('Walking',false);return end
    if now<state.pauseUntil then if state.pauseUntil~=state.blockedPauseUntil then state.stallPosition=nil;state.stallSince=nil end;state.model:SetAttribute('Walking',false);return end
    if not state.points then
        if state.carry then
            -- No route: teleport it out (cooldown permitting); never drop the loot back beside the cart.
            if not routeCarry(state) then teleportSafe(state,now,'CarryNoRoute') end
            state.model:SetAttribute('Walking',false);return
        elseif not seekCart(state,now) then chooseDestination(state) end
    end
        local pos=state.root.Position
    -- Consume coincident points in the same update instead of stopping for each one.
    while state.points and state.points[state.pointIndex] do
     local p=state.points[state.pointIndex]
     if (p-pos).Magnitude<.5 then state.pointIndex+=1 else break end
    end
    if state.points then
     for i=state.pointIndex+1,math.min(#state.points,state.pointIndex+6) do
      local p=state.points[i]
      if math.abs(p.Y-pos.Y)>.3 then break end
      if clearSegment(pos,p) then state.pointIndex=i end
     end
    end
    local target=state.points and state.points[state.pointIndex]
    -- Never step off a flight part-way: a target away from the stairs first gets the rest of the flight.
    if target and onFlight(pos.Y)and flightGap(target)>1.5 then
     local leg=stairLeg(pos,target.Y>=FLOOR/2 and 1 or 0)
     if leg then for i=#leg,1,-1 do table.insert(state.points,state.pointIndex,leg[i])end;target=state.points[state.pointIndex]end
    end

    if not target then
        -- Reached the drop room with stolen loot: leave it there.
        if state.carry and state.carry.spot and Vector3.new(pos.X-state.carry.spot.X,0,pos.Z-state.carry.spot.Z).Magnitude<6 then
            dropLoot(state);state.points=nil;state.destination=nil;state.pauseUntil=now+1;setMode(state,'Patrol')
            state.model:SetAttribute('Walking',false);return
        end
        if not state.destination then state.pauseUntil=now+.5;state.model:SetAttribute('Walking',false);return end
        state.visits[state.destination.name]=(state.visits[state.destination.name] or 0)+1
        state.room=state.destination;state.points=nil
        state.pauseUntil=now+(state.roamy and .02 or state.mode=='Patrol' and rng:NextNumber(.03,.12) or .1)
        state.model:SetAttribute('CurrentRoom',state.room.name)
        state.model:SetAttribute('Walking',false)
        return
    end
    if not state.stallPosition or (pos-state.stallPosition).Magnitude>.6 then
     state.stallPosition=pos;state.stallSince=now
    end
    -- Anti-loop (STUCK_*): only time spent trying to move counts, so pauses and ambushes never trigger it.
    if not state.stuckAnchor or (pos-state.stuckAnchor).Magnitude>STUCK_RADIUS then state.stuckAnchor=pos;state.stuckTime=0 else state.stuckTime=(state.stuckTime or 0)+dt end
    if state.stuckTime>STUCK_CART_SECONDS then
     local cart=recoveryCart()
     local atCart=cart~=nil and (cart.PrimaryPart.Position-pos).Magnitude<STUCK_CART_RADIUS
     if (atCart or state.stuckTime>STUCK_ANY_SECONDS) and teleportSafe(state,now,atCart and 'StuckAtCart' or 'Stuck') then state.model:SetAttribute('Walking',false);return end
    end
    local distanceToWaypoint=(target-pos).Magnitude
    if state.progressTarget~=target then
     if RunService:IsStudio()then state.model:SetAttribute('NextWaypoint',target)end
     state.progressTarget=target;state.bestWaypointDistance=distanceToWaypoint;state.waypointProgressAt=now
    elseif distanceToWaypoint<(state.bestWaypointDistance or math.huge)-.3 then
     state.bestWaypointDistance=distanceToWaypoint;state.waypointProgressAt=now
    end
    if now-(state.stallSince or now)>2.5 then
     state.stallSince=now
     if state.destination then state.visits[state.destination.name]=(state.visits[state.destination.name]or 0)+1 end
     state.room=roomAt(pos)or state.room;state.points=nil;state.destination=nil;state.progressTarget=nil
     for i=0,7 do
      local angle=i*math.pi/4+rng:NextNumber(-.2,.2)
      local goal=safePoint(state.room,pos+Vector3.new(math.cos(angle)*8,0,math.sin(angle)*8),2)
      if(goal-pos).Magnitude>3 and clearSegment(pos,goal)then
       state.points={goal};state.pointIndex=1;state.destination=state.room;break
      end
     end
     state.pauseUntil=now+.05
     state.model:SetAttribute('RouteRecoveries',(state.model:GetAttribute('RouteRecoveries')or 0)+1)
     state.model:SetAttribute('Walking',false)
     return
    end
    local delta=Vector3.new(target.X-pos.X,0,target.Z-pos.Z)
    local flat=delta.Magnitude
    if flat<.45 and math.abs(target.Y-pos.Y)<.25 then
        state.pointIndex+=1;return
    end
    if flat<.05 then
        local y=pos.Y+math.clamp(target.Y-pos.Y,-dt*8,dt*8)
        state.root.CFrame=CFrame.new(pos.X,y,pos.Z)*CFrame.Angles(0,state.yaw,0)
        state.model:SetAttribute('Walking',true)
        return
    end
    local direction=delta.Unit
    local speed=state.mode=='Chase' and (TUNE.ChaseSpeed+2.5*(state.difficulty or 0)+(state.anger or 0)*TUNE.ChaseAngerBonus) or MODE_SPEED[state.mode] or state.speed*PATROL_SCALE
     if state.easy and state.mode=='Chase' then speed=math.min(speed*EASY_SPEED,EASY_CHASE_SPEED) end
     if state.level==2 then if state.mode=='Chase' then speed*=LEVEL2_CHASE elseif state.mode=='Retreat' or state.mode=='Patrol' then speed*=LEVEL2_MOVE_ON end end
    local roleSpeed=Abilities:Speed(state,state.mode);if roleSpeed then speed=roleSpeed end
    if state.mode=='Chase' then
     state.chaseStart=state.chaseStart or now
     local cycle=(now-state.chaseStart)%TUNE.BurstPeriod
     if cycle>2 and cycle<2+TUNE.BurstDuration and (state.anger or 0)>.35 then speed=TUNE.BurstSpeed+6*(state.difficulty or 0);soundCue(state,'Rush') end
    else state.chaseStart=nil end
    if now<(state.model:GetAttribute('FleeUntil') or 0) then speed=math.max(speed,24) elseif now<(state.model:GetAttribute('HypnoUntil') or 0) then speed=speed*.55 end
    if mansion:GetAttribute('CatCurse')==true then speed*=CAT_CURSE_SPEED end -- the stray cat was turned to stone (CloseUpChoices)
    state.model:SetAttribute('MoveSpeed',speed)
    local travel=math.min(flat,speed*dt)
    if now>(state.doorCheckAt or 0)then
     state.doorCheckAt=now+.4
     local owner=game.ServerScriptService:FindFirstChild('InteractServer')
     local api=owner and owner:FindFirstChild('MonsterDoorApi')
     if api then for _,door in pairs(doorByEdge)do
      local closed=door:GetAttribute('ClosedPivot')
      if closed and not door:GetAttribute('Locked')and(door:GetAttribute('Open')or 0)<.5 then
       local delta=closed.Position-pos
       if delta.Magnitude<8 and Vector3.new(delta.X,0,delta.Z):Dot(direction)>0 then
        api:Invoke(door);break
       end
      end
     end end
    end
    -- Stairs follow the authored climb path. A flat blockcast hits the stair ramp's
    -- collider at the foot of the flight, which used to stall monsters at the first step.
    -- Stair rooms hold nothing but the stairs, so there is nothing to steer around there.
    local here,there=roomAt(pos),roomAt(target)
    local climbing=math.abs(target.Y-pos.Y)>.3 or (here and here.type=='Stair') or (there and there.type=='Stair')
    if not climbing and not unobstructed(state,direction,math.min(travel+.7,flat)) then
        local found=nil
        for _,angle in ipairs({-.48,.48,-.95,.95,-1.45,1.45}) do
            local test=CFrame.Angles(0,angle,0):VectorToWorldSpace(direction)
            if unobstructed(state,test,travel+.7) then found=test;break end
        end
        if found then direction=found else
            if localDetour(state,target,now)then state.model:SetAttribute('Walking',false);return end
            if nudgeBlockingCart(state,direction,travel+.7)then state.lastProgress=now;state.model:SetAttribute('Walking',false);return end
            if now-state.lastProgress>1.5 then
                state.points=nil;state.pauseUntil=now+.2;state.blockedPauseUntil=state.pauseUntil;state.lastProgress=now
            end
            state.model:SetAttribute('Walking',false)
            return
        end
    end
    local nextPos=pos+direction*travel
    local y=pos.Y+(target.Y-pos.Y)*math.min(1,travel/math.max(flat,.01))
    nextPos=Vector3.new(nextPos.X,y,nextPos.Z)
    local desired=math.atan2(-direction.X,-direction.Z)
    local d=(desired-state.yaw+math.pi)%(2*math.pi)-math.pi
    state.yaw+=d*(1-math.exp(-dt*10))
    state.root.CFrame=CFrame.new(nextPos)*CFrame.Angles(0,state.yaw,0)
    state.model:SetAttribute('Walking',true)
    if (nextPos-state.lastPosition).Magnitude>.6 then state.lastPosition=nextPos;state.lastProgress=now end
end

-- One roster for the mission, independent of party size and character respawns.
local roundState
repeat roundState=game:GetService('ReplicatedStorage'):FindFirstChild('RecoveryRound');if not roundState then task.wait(.1)end until roundState
-- Insert after roundState acquisition, before roster functions. Private to existing monster owner.
local SkitterClass=require(script:WaitForChild('SkitterController'))
local skitter
local function floorRoom(pos)
 local floor=math.floor((pos.Y+1)/FLOOR)
 for _,r in graph.rooms do if r.level==floor and pos.X>=r.x1 and pos.X<=r.x2 and pos.Z>=r.z1 and pos.Z<=r.z2 then return r end end
end
local function skitterParams(self)
 local p=RaycastParams.new();p.FilterType=Enum.RaycastFilterType.Exclude;p.RespectCanCollide=true
 local ignore={folder};for _,player in Players:GetPlayers()do if player.Character then ignore[#ignore+1]=player.Character end end
 local camera=Workspace:FindFirstChild('Camera');if camera then ignore[#ignore+1]=camera end
 p.FilterDescendantsInstances=ignore;return p
end
local function skitterGround(pos,self)
 local hit=Workspace:Raycast(pos+Vector3.new(0,.65,0),Vector3.new(0,-1.25,0),skitterParams(self))
 if hit and hit.Normal.Y>.9 and math.abs(hit.Position.Y-pos.Y)<.2 then return hit.Position end
end
local stairSupport={}
local ceilingSupport={}
for _,container in {mansion.Architecture,mansion.Collision}do
 for _,part in container:GetChildren()do
  if part.Name=='StairRamp'or part.Name=='Landing'then stairSupport[#stairSupport+1]=part end
  if container==mansion.Collision and part.Name=='Ceiling'then ceilingSupport[#ceilingSupport+1]=part end
 end
end
local function skitterClear(a,b,self,upA,upB,onStairs)
 local d=b-a;if d.Magnitude<.01 then return true end
 -- Follow the surface normal; a continuous stair sweep never jumps to another floor.
 local start=a+(upA or Vector3.yAxis)*1.1;local finish=b+(upB or upA or Vector3.yAxis)*1.1;local delta=finish-start
 if delta.Magnitude<.01 then return true end
 local params=skitterParams(self)
 if onStairs then local ignore=params.FilterDescendantsInstances;for _,support in stairSupport do ignore[#ignore+1]=support end;params.FilterDescendantsInstances=ignore end
 return Workspace:Blockcast(CFrame.new(start),Vector3.new(3.1,2.1,3.5),delta,params)==nil
end
local function skitterVisible(a,b)return Workspace:Raycast(a,b-a,skitterParams())==nil end
skitter=SkitterClass.New({Storage=ServerStorage,Folder=folder,Round=roundState,Players=Players,Protection=Protection,Rooms=graph.rooms,
 Random=rng,Floor=FLOOR,NearVan=nearVan,
 HitJumpscare=function(p,monster)return require(script.MonsterJumpscare).Hit(p,monster)end,
 GetTraps=function()
  local traps={};for _,model in mansion:GetChildren()do
   if model.Name=='ArmedSkitterTrap'and model:GetAttribute('Armed')==true and model:GetAttribute('TargetKind')=='Skitter'then
    local pos=model:GetAttribute('TrapPosition');if typeof(pos)=='Vector3' then traps[#traps+1]={model=model,position=pos}end
   end
  end;return traps
 end,
 StairSegment=function(a,b)
  local here,there=floorRoom(a),floorRoom(b)
  return math.abs(b.Y-a.Y)>.3 or(here and here.type=='Stair')or(there and there.type=='Stair')
 end,
 OpenDoors=function(pos,direction)
  local owner=game.ServerScriptService:FindFirstChild('InteractServer');local api=owner and owner:FindFirstChild('MonsterDoorApi')
  if not api then return end
  for _,door in pairs(doorByEdge)do local closed=door:GetAttribute('ClosedPivot')
   if closed and not door:GetAttribute('Locked')and(door:GetAttribute('Open')or 0)<.5 then
    local delta=closed.Position-pos
    if delta.Magnitude<8 and Vector3.new(delta.X,0,delta.Z):Dot(Vector3.new(direction.X,0,direction.Z))>0 then api:Invoke(door);break end
   end
  end
 end,Ground=skitterGround,Clear=skitterClear,Visible=skitterVisible,RoomAtFloor=floorRoom,
 RoomForXZ=function(p,level)for _,r in graph.rooms do if r.level==level and p.X>=r.x1 and p.X<=r.x2 and p.Z>=r.z1 and p.Z<=r.z2 then return r end end end,
 Route=function(from,dest,goal)
  local links=shortest(from.name,dest.name);if not links then return end
  return makeWaypoints(from,links,safePoint(dest,goal,2.2))
 end,
 Reachable=function(from,dest)return shortest(from.name,dest.name)~=nil end,
 Wall=function(r,pos,self)
  local origin=Vector3.new(math.clamp(pos.X,r.x1+4,r.x2-4),r.level*FLOOR+7,math.clamp(pos.Z,r.z1+4,r.z2-4))
  local options={Vector3.new(r.x1-2-origin.X,0,0),Vector3.new(r.x2+2-origin.X,0,0),Vector3.new(0,0,r.z1-2-origin.Z),Vector3.new(0,0,r.z2+2-origin.Z)}
  for _,direction in options do local hit=Workspace:Raycast(origin,direction,skitterParams(self))
   if hit and math.abs(hit.Normal.Y)<.1 and(hit.Position-origin).Magnitude>3 then return hit end
  end
 end,
 Ceiling=function(pos)
  local r=floorRoom(pos);local model=r and mansion.Architecture:FindFirstChild(r.name..'_Ceiling');if not model then return end
  -- Collision proxies expose the true flat underside even when imported mesh bevel normals are slanted.
  local params=RaycastParams.new();params.FilterType=Enum.RaycastFilterType.Include;params.FilterDescendantsInstances=#ceilingSupport>0 and ceilingSupport or {model};params.RespectCanCollide=false
  local hit=Workspace:Raycast(pos,Vector3.new(0,7,0),params);if hit and hit.Normal.Y<-.9 then return hit.Position end
 end,
})
local skitterSpawnAt=0
local function refreshSkitter(now)
 -- The Skitter is switched off (user, 2026-10-06); set CreatureRoamServer.SkitterEnabled=true to bring it back.
 if script:GetAttribute('SkitterEnabled')~=true then return end
 if skitter.current or skitter.slain or now<skitterSpawnAt or roundState:GetAttribute('Phase')~='Searching'or script:GetAttribute('AdminNoMonsters')then return end
 skitterSpawnAt=now+2
 local owner
 for _,p in Players:GetPlayers()do local h=p.Character and p.Character:FindFirstChildOfClass('Humanoid');if p:GetAttribute('MissionActive')and not p:GetAttribute('RoundDead')and h and h.Health>0 then owner=p;break end end
 if not owner then return end
 local candidates={}
 for _,r in graph.rooms do local p=center(r)
  if r.type~='Stair'and r.name~=graph.start and not(graph.closed and graph.closed[r.name])and not nearVan(p,6)and skitterGround(p)and standable(p)and shortest(graph.start,r.name)then candidates[#candidates+1]=r end
 end
 for _=1,#candidates do
  local r=table.remove(candidates,rng:NextInteger(1,#candidates))
  if skitter:Spawn(owner,center(r),r)then return end
 end
end

local rosterGeneration=0
local rosterRound=nil
local function clearRoster()
 skitter:Clear();skitterSpawnAt=0
 rosterGeneration+=1
 Brain:Reset()
 for _,states in pairs(active)do for _,s in states do if s.model.Parent then s.model:Destroy()end end end
 table.clear(active)
 folder:ClearAllChildren()
 roundState:SetAttribute('MonsterCount',0)
end
local function refreshRoster()
 local level=roundState:GetAttribute('Round')or 0
 if level<1 or roundState:GetAttribute('Phase')~='Searching' or rosterRound==level then return end
 if script:GetAttribute('AdminNoMonsters')==true then return end -- owner panel: auto-spawning paused
 local owner
 for _,p in Players:GetPlayers()do
  local h=p.Character and p.Character:FindFirstChildOfClass('Humanoid')
  if p:GetAttribute('MissionActive') and h and h.Health>0 then owner=p;break end
 end
 if not owner then return end
 clearRoster();rosterRound=level
 local token=rosterGeneration
 local list={};active.mission=list
 local oneKind
 local count=if level<=1 then 1 elseif level<=4 then 2 elseif level<=8 then 3 else 4 -- two from level 2 (owner 2026-10-22: monsters barely noticed anyone); gentler late game (was level-1, up to 6): L4+ was near impossible
 local difficulty=1-math.exp(-math.max(0,level-2)/4) -- L3 .22, L4 .39, L5 .53 (was /10)
 roundState:SetAttribute('MonsterCountTarget',count)
 roundState:SetAttribute('MonsterDifficultyLevel',level)
 local anchor=roomAt(mansion:GetAttribute('SpawnPosition')or workspace.SpawnLocation.Position)
 if not anchor then rosterRound=nil;return end
 roundState:SetAttribute('MonsterSpawnPending',true)
 task.spawn(function()
  local ok,err=xpcall(function()
  local validator=require(script.ValidMonsterSpawn)
  if level<=2 then -- head start: new players get a quiet minute to loot and learn the van before anything hunts (level 2: 25 s)
   local headstart=level==1 and EASY_HEADSTART or LEVEL2_HEADSTART
   roundState:SetAttribute('MonsterHeadstartUntil',workspace:GetServerTimeNow()+headstart)
   local wakeAt=os.clock()+headstart
   while os.clock()<wakeAt do
    if token~=rosterGeneration or roundState:GetAttribute('Phase')~='Searching' and roundState:GetAttribute('Phase')~='Selling' and roundState:GetAttribute('Phase')~='Returning' then return end
    task.wait(.5)
   end
  end
  for index=1,count do
   if token~=rosterGeneration then return end
   local choice,total
   repeat
    if token~=rosterGeneration then return end
    choice,total=validator.Select(mansion,graph,anchor,center,shortest,makeWaypoints,rng,function(p)return not nearVan(p,4)end,routeDistance)
    if not choice then task.wait(1)end
   until choice
   if token~=rosterGeneration then return end
   local template=templates[(index+level-2)%#templates+1]
   -- Late debut (Monsters build 2026-10-27): a template whose minLevel is above this level hands its slot to the next
   -- template in rotation order that is allowed here and not already on this level's roster (levels 1-4 are unchanged).
   if (template.minLevel or 1)>level then
    for step=1,#templates do
     local t=templates[(index+level-2+step)%#templates+1]
     local taken=false;for _,s in ipairs(list)do if s.model.Name:sub(1,#t.name)==t.name then taken=true end end
     if (t.minLevel or 1)<=level and not taken then template=t;break end
    end
   end
   -- OneKind omen: the whole level uses one template, picked once (skip the Lantern on a map without closets).
   if index==1 then
    oneKind=nil
    if omen()=='OneKind' then
     local hasClosets=mansion:FindFirstChild('Closets')and #mansion.Closets:GetChildren()>0
     local pool={};for _,t in ipairs(templates)do if (t.kind~='Lantern' or hasClosets) and (t.minLevel or 1)<=level then table.insert(pool,t)end end
     oneKind=pool[rng:NextInteger(1,#pool)]
     roundState:SetAttribute('OmenMonster',({Bellhop='Bellhop',Lantern='Lantern Watcher',Neon='Neon Tripod',Mittens='Lonely Mittens',Dancer='Wind-Up Dancer',Yoyo='Yo-Yo Kid'})[oneKind.kind or '']or(oneKind.name:find('Crawler')and 'Crawler' or 'Wraith'))
    else roundState:SetAttribute('OmenMonster',nil)end
   end
   if oneKind then template=oneKind end
   -- Studio-only: set this script's StudioForceTemplate attribute (e.g. 'Bellhop') to test one monster.
   local forced=RunService:IsStudio() and script:GetAttribute('StudioForceTemplate')
   if forced then for _,t in ipairs(templates)do if t.name==forced or t.kind==forced then template=t end end end
   local model,root=makeRig(template,owner,choice.point)
   model.Name=template.name..'_Level'..level..'_'..index
   model:SetAttribute('CurrentRoom',choice.room.name);model:SetAttribute('SpawnValidated',true)
   model:SetAttribute('SpawnPosition',choice.point);model:SetAttribute('SpawnPlayerDistance',choice.distance)
   model:SetAttribute('SpawnStartDistance',choice.spawnDistance);model:SetAttribute('SpawnFloor',choice.room.level)
   model:SetAttribute('SpawnCandidateCount',total);model:SetAttribute('DifficultyLevel',level)
   local _,yaw,_=root.CFrame:ToOrientation()
   table.insert(list,{model=model,root=root,speed=(template.speed+2*difficulty)*verificationSpeed*(level==1 and EASY_SPEED or 1),room=choice.room,visits={[choice.room.name]=1},
    mode='Patrol',anger=0,difficulty=difficulty,spawnedAt=os.clock(),easy=level==1,level=level,calmUntil=os.clock()+math.max(CALM_MIN,CALM_BASE-(level-1)*CALM_STEP)+(level==1 and EASY_EXTRA_CALM or 0),calmNotice=CALM_NOTICE,points=nil,pointIndex=1,pauseUntil=os.clock()+.2,
    lastPosition=choice.point,lastProgress=os.clock(),yaw=yaw})
   roundState:SetAttribute('MonsterCount',#list)
  end
  end,debug.traceback)
  if token==rosterGeneration then
   roundState:SetAttribute('MonsterSpawnPending',false)
   if not ok then roundState:SetAttribute('MonsterSpawnError',tostring(err));rosterRound=nil end
  end
 end)
end
roundState:GetAttributeChangedSignal('Round'):Connect(function()
 local nextLevel=roundState:GetAttribute('Round')
 if rosterRound and nextLevel~=rosterRound then clearRoster();rosterRound=nil end
 task.defer(refreshRoster)
end)
roundState:GetAttributeChangedSignal('Phase'):Connect(function()
 local phase=roundState:GetAttribute('Phase')
 if phase=='Deploying' then clearRoster();rosterRound=nil
 elseif phase=='Searching'then task.defer(refreshRoster)end
end)
local function watchPlayer(p)
 p:GetAttributeChangedSignal('RoundDead'):Connect(function()if p:GetAttribute('RoundDead')then Brain:Death(p,os.clock())end end)
 p.CharacterAdded:Connect(function()task.defer(refreshRoster)end)
 p:GetAttributeChangedSignal('MissionActive'):Connect(function()task.defer(refreshRoster)end)
end
Players.PlayerAdded:Connect(watchPlayer)
Players.PlayerRemoving:Connect(function(p)
 noiseMotion[p]=nil
 task.defer(function()
  local remains=false;for _,other in Players:GetPlayers()do if other~=p and other:GetAttribute('MissionActive')then remains=true;break end end
  if not remains then clearRoster();rosterRound=nil end
 end)
end)
for _,p in Players:GetPlayers()do watchPlayer(p)end
task.defer(refreshRoster)
-- Studio-only test hook: set this script's DebugRouteTarget (Vector3) to send
-- monster #1 there for 30 s with its decision-making paused. Ignored live.
if RunService:IsStudio() then
 script:GetAttributeChangedSignal('DebugRouteTarget'):Connect(function()
  local pos=script:GetAttribute('DebugRouteTarget');local s=active.mission and active.mission[1]
  if typeof(pos)~='Vector3' or not s then return end
  s.debugUntil=os.clock()+30;s.calmUntil=0;s.room=roomAt(s.root.Position)
  script:SetAttribute('DebugRouteResult',routeTo(s,pos,'Investigate'))
 end)
end
local slainRound -- see roster audit below
-- A slain monster comes back RETURN_AFTER seconds later, or at once when its Monster Orb is sold, whichever
-- comes first (once only): same monster, placed like a level-start spawn (validated room, far from every
-- player and away from the van). Only on the level it was slain in.
local RETURN_AFTER=150
local returnCount=0
local slainPending={} -- slain model name -> level, until it has come back
local function respawnSlain(name,slainLevel)
 local level=roundState:GetAttribute('Round')or 0
 if typeof(name)~='string' or level<1 or rosterRound~=level or (slainLevel~=nil and slainLevel~=level) then return false end
 local phase=roundState:GetAttribute('Phase')
 if phase~='Searching' and phase~='Selling' and phase~='Returning' then return false end
 if script:GetAttribute('AdminNoMonsters')==true then return false end
 local template;for _,t in ipairs(templates)do if name:sub(1,#t.name)==t.name then template=t;break end end
 if not template then return false end
 local owner
 for _,p in Players:GetPlayers()do
  local h=p.Character and p.Character:FindFirstChildOfClass('Humanoid')
  if p:GetAttribute('MissionActive') and h and h.Health>0 then owner=p;break end
 end
 if not owner then return false end
 local anchor=roomAt(mansion:GetAttribute('SpawnPosition')or workspace.SpawnLocation.Position)
 if not anchor then return false end
 local token=rosterGeneration
 local validator=require(script.ValidMonsterSpawn)
 local choice,total
 for _=1,20 do
  if token~=rosterGeneration then return false end
  choice,total=validator.Select(mansion,graph,anchor,center,shortest,makeWaypoints,rng,function(p)return not nearVan(p,4)end,routeDistance)
  if choice then break end
  task.wait(1)
 end
 if not choice or token~=rosterGeneration or rosterRound~=level then return false end
 local list=active.mission;if not list then list={};active.mission=list end
 local difficulty=1-math.exp(-math.max(0,level-2)/4) -- L3 .22, L4 .39, L5 .53 (was /10)
 local model,root=makeRig(template,owner,choice.point)
 returnCount+=1;model.Name=template.name..'_Level'..level..'_Returned'..returnCount
 model:SetAttribute('CurrentRoom',choice.room.name);model:SetAttribute('SpawnValidated',true);model:SetAttribute('ReturnedFromOrb',true)
 model:SetAttribute('SpawnPosition',choice.point);model:SetAttribute('SpawnPlayerDistance',choice.distance)
 model:SetAttribute('SpawnStartDistance',choice.spawnDistance);model:SetAttribute('SpawnFloor',choice.room.level)
 model:SetAttribute('SpawnCandidateCount',total);model:SetAttribute('DifficultyLevel',level)
 local _,yaw,_=root.CFrame:ToOrientation()
 table.insert(list,{model=model,root=root,speed=(template.speed+2*difficulty)*verificationSpeed*(level==1 and EASY_SPEED or 1),room=choice.room,visits={[choice.room.name]=1},
  mode='Patrol',anger=0,difficulty=difficulty,spawnedAt=os.clock(),easy=level==1,level=level,calmUntil=os.clock()+math.max(CALM_MIN,CALM_BASE-(level-1)*CALM_STEP)+(level==1 and EASY_EXTRA_CALM or 0),calmNotice=CALM_NOTICE,points=nil,pointIndex=1,pauseUntil=os.clock()+.2,
  lastPosition=choice.point,lastProgress=os.clock(),yaw=yaw})
 roundState:SetAttribute('MonsterCount',#list)
 return true
end
-- Gear shop weapons (GearShopServer): blast -> stun then flee far from players; hypnotize -> ignores players; kill -> gone for the level.
do
 local old=ServerStorage:FindFirstChild('CreatureWeaponApi');if old then old:Destroy()end
 local weapon=Instance.new('BindableFunction');weapon.Name='CreatureWeaponApi';weapon.Parent=ServerStorage
 local function find(model)for _,list in pairs(active)do for _,s in list do if s.model==model then return s,list end end end end
 weapon.OnInvoke=function(action,model,a,b)
  if action=='respawn'then -- the orb was sold: bring it back now unless the timer already did
   if typeof(a)~='string' or slainPending[a]==nil then return false end
   local level=slainPending[a];slainPending[a]=nil;return respawnSlain(a,level)
  end
  if action=='skitters'then return skitter:Models()end
  if action=='skitterTrap'then return skitter:Kill(model,a)end
  -- Close-up choices (CursedItemsServer.CloseUpChoices): 'dismiss' = a roster monster sleeps through the level
  -- (model nil) or one hunter is removed; 'hunt' = the Lantern rises out of the sleeping pup and hunts only player `a`.
  if action=='dismiss'then
   local pick,from
   for _,list in pairs(active)do for _,s in list do
    if s.model.Parent and((model==nil and not s.hunt and not s.attack)or s.model==model)then pick,from=s,list end
   end end
   if not pick then return nil end
   for i,x in ipairs(from)do if x==pick then table.remove(from,i);break end end
   if model==nil then slainRound=rosterRound end -- it stays asleep: the roster does not refill this level
   local name=pick.model.Name;pick.model:Destroy()
   roundState:SetAttribute('MonsterCount',math.max(0,(roundState:GetAttribute('MonsterCount')or 1)-1))
   return name
  end
  if action=='grab'then -- the pup's Lantern grabs the player who woke it as soon as it is out of the floor
   local state=find(model)
   if not state or typeof(a)~='Instance'or not a:IsA('Player')then return false end
   state.target=a;state.pauseUntil=0;state.lastGrab=os.clock()
   return Abilities:Catch(state,a,os.clock())==true
  end
  if action=='hunt'then
   local p,opts=a,type(b)=='table'and b or{}
   if typeof(p)~='Instance'or not p:IsA('Player')or typeof(opts.pos)~='Vector3'then return nil end
   local template;for _,t in ipairs(templates)do if t.kind=='Lantern'then template=t end end
   local room=roomAt(opts.pos)
   if not room then -- woken outside the house (the Studio van test)
    local entrance=mansion:GetAttribute('SpawnPosition');room=entrance and roomAt(entrance)
    -- it still rises right where the pup was (it grabs at once), routing as if from the entrance room
   end
   if not template or not room then return nil end
   local list=active.mission;if not list then list={};active.mission=list end
   local rise,headStart=tonumber(opts.rise)or 1,tonumber(opts.headStart)or 1
   local made,root=makeRig(template,p,opts.pos)
   made.Name=template.name..'_Hunter_'..p.UserId
   made:SetAttribute('CurrentRoom',room.name);made:SetAttribute('SpawnValidated',true);made:SetAttribute('Hunter',true)
   made:SetAttribute('HuntUserId',p.UserId);made:SetAttribute('Mad',true)
   local _,yaw=root.CFrame:ToOrientation();local now=os.clock()
   local state={model=made,root=root,speed=template.speed,room=room,visits={[room.name]=1},mode='Patrol',anger=1,difficulty=0,
    level=math.max(1,roundState:GetAttribute('Round')or 1),spawnedAt=now,calmUntil=0,calmNotice=CALM_NOTICE,points=nil,pointIndex=1,
    pauseUntil=now+rise+headStart,lastGrab=now+rise+headStart-2.5,lastPosition=opts.pos,lastProgress=now,yaw=yaw,
    hunt={player=p,speed=tonumber(opts.speed)or 30}}
   table.insert(list,state);roundState:SetAttribute('MonsterCount',#list)
   local final=root.CFrame
   task.spawn(function() -- it rises out of the floor where the pup was
    local t0=os.clock()
    while os.clock()-t0<rise and root.Parent do local k=(os.clock()-t0)/rise;root.CFrame=final-Vector3.new(0,(1-k)^2*7,0);RunService.Heartbeat:Wait()end
    if root.Parent then root.CFrame=final end
   end)
   return made
  end
  if skitter:Owns(model)then return false end -- normal guns and blast never target the nuisance
  if action=='list'then local out={};for _,list in pairs(active)do for _,s in list do if s.model.Parent then table.insert(out,s.model)end end end;return out end
  local state,list=find(model);if not state then return false end
  local now=os.clock()
  if action=='blast'then
   model:SetAttribute('StunnedUntil',now+1);model:SetAttribute('FleeUntil',now+1+(tonumber(b)or 12))
   state.target=nil;state.catching=nil
   task.delay(1,function()if model.Parent then retreat(state,os.clock(),typeof(a)=='Vector3'and a or nil)end end)
   return true
  elseif action=='hypnotize'then
   model:SetAttribute('HypnoUntil',now+(tonumber(a)or 20));state.target=nil;state.catching=nil;setMode(state,'Patrol');return true
  elseif action=='devour'then -- the friend balloon ate it: gone for the whole level, no return timer (its orb never revives it)
   for i,x in ipairs(list)do if x==state then table.remove(list,i);break end end
   slainRound=rosterRound
   model:Destroy();roundState:SetAttribute('MonsterCount',math.max(0,(roundState:GetAttribute('MonsterCount')or 1)-1));return true
  elseif action=='kill'then
   for i,x in ipairs(list)do if x==state then table.remove(list,i);break end end
   slainRound=rosterRound
   local slainName,slainLevel=model.Name,roundState:GetAttribute('Round')
   slainPending[slainName]=slainLevel
   task.delay(RETURN_AFTER,function()
    if slainPending[slainName]~=slainLevel then return end
    slainPending[slainName]=nil;respawnSlain(slainName,slainLevel)
   end)
   model:Destroy();roundState:SetAttribute('MonsterCount',math.max(0,(roundState:GetAttribute('MonsterCount')or 1)-1));return true
  end
  return false
 end
end
-- Owner admin panel: spawn an extra driven monster at a position, or clear them all.
local adminApi=Instance.new('BindableFunction');adminApi.Name='CreatureAdminApi'
adminApi.OnInvoke=function(action,owner,pos,index)
 if action=='templates' then local names={};for _,t in ipairs(templates)do table.insert(names,t.kind or t.name)end;return names end
 if action=='clear' then clearRoster();rosterRound=roundState:GetAttribute('Round');return true end
 if action=='hold' then script:SetAttribute('AdminNoMonsters',pos==true);if pos==true then clearRoster() else rosterRound=nil;task.defer(refreshRoster) end;return true end
 if action~='spawn' or typeof(pos)~='Vector3' or not owner then return false end
 local template=templates[math.clamp(math.floor(tonumber(index)or 1),1,#templates)]
 local room=roomAt(pos)
 if not room then return false,'Stand inside the map to spawn a monster.' end
 local list=active.mission;if not list then list={};active.mission=list end
 local level=math.max(1,roundState:GetAttribute('Round')or 1)
 local difficulty=1-math.exp(-math.max(0,level-2)/4) -- L3 .22, L4 .39, L5 .53 (was /10)
 local model,root=makeRig(template,owner,pos)
 model.Name=template.name..'_Admin_'..(#list+1)
 model:SetAttribute('CurrentRoom',room.name);model:SetAttribute('SpawnValidated',true);model:SetAttribute('SpawnPosition',pos);model:SetAttribute('AdminSpawned',true)
 local _,yaw,_=root.CFrame:ToOrientation()
 table.insert(list,{model=model,root=root,speed=(template.speed+2*difficulty)*verificationSpeed,room=room,visits={[room.name]=1},
  mode='Patrol',anger=0,difficulty=difficulty,level=level,spawnedAt=os.clock(),calmUntil=os.clock()+5,calmNotice=CALM_NOTICE,points=nil,pointIndex=1,pauseUntil=os.clock()+.2,
  lastPosition=pos,lastProgress=os.clock(),yaw=yaw})
 roundState:SetAttribute('MonsterCount',#list)
 return true,model.Name
end
adminApi.Parent=ServerStorage
local rosterAudit=0
slainRound=nil -- (declared above) set by the gear shop kill: slain monsters stay gone for the rest of that level
RunService.Heartbeat:Connect(function(dt)
 rosterAudit+=dt
 if rosterAudit>=2 then
  rosterAudit=0
  if roundState:GetAttribute('Phase')=='Searching'then
   if rosterRound and active.mission and #active.mission>0 then
    local alive=false;for _,state in ipairs(active.mission)do if state.model.Parent and state.root.Parent then alive=true;break end end
    if not alive then rosterRound=nil end
   end
   if rosterRound and active.mission and #active.mission==0 and not roundState:GetAttribute('MonsterSpawnPending')and slainRound~=rosterRound then rosterRound=nil end
   refreshRoster()
  end
 end
 local phase=roundState:GetAttribute('Phase')
 if phase=='Deploying'or phase=='Won'or phase=='Failed'then return end
 local tickDt=math.min(dt,.05)
 if phase=='Searching'then refreshSkitter(os.clock())end
 skitter:Step(tickDt,os.clock())
 sampleNoise(os.clock())
 Brain:TickDirector(os.clock(),active.mission or {})
 for _,states in pairs(active)do for _,state in states do step(state,tickDt)end end
end)


