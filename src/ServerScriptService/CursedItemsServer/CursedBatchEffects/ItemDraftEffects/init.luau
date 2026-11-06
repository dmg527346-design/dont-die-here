local SelectedSounds=game.HttpService:JSONDecode([==[{"SpringyWhisk":{"key":"DraftSelected_SpringyWhisk","interval":3.4,"loop":false,"duration":0.6},"PoutingSugarBowl":{"key":"DraftSelected_PoutingSugarBowl","interval":5.5,"loop":false,"duration":1.6},"RockingSeahorseToy":{"key":"DraftSelected_RockingSeahorseToy","interval":3.8,"loop":false,"duration":1.1},"OrbitingAtomModel":{"key":"DraftSelected_OrbitingAtomModel","interval":3.0,"loop":false,"duration":0.852},"PeekingNestingDoll":{"key":"DraftSelected_PeekingNestingDoll","interval":4.3,"loop":false,"duration":0.6},"RestlessToyExcavator":{"key":"DraftSelected_RestlessToyExcavator","interval":4.5,"loop":false,"duration":1.9},"BobbingBirdBath":{"key":"DraftSelected_BobbingBirdBath","interval":3.6,"loop":false,"duration":0.8},"CrinklyPaperBag":{"key":"DraftSelected_CrinklyPaperBag","interval":4.4,"loop":false,"duration":2.1},"SleepyMeasuringJug":{"key":"DraftSelected_SleepyMeasuringJug","interval":6.2,"loop":false,"duration":2.8},"TopsyChessRook":{"key":"DraftSelected_TopsyChessRook","interval":4.0,"loop":false,"duration":0.9},"RestlessNutcracker":{"key":"DraftSelected_RestlessNutcracker","interval":3.8,"loop":false,"duration":1.0},"SillySatelliteDish":{"key":"DraftSelected_SillySatelliteDish","interval":5.0,"loop":false,"duration":1.0},"FidgetCalculator":{"key":"DraftSelected_FidgetCalculator","interval":4.8,"loop":false,"duration":2.3},"FoldingTravelStool":{"key":"DraftSelected_FoldingTravelStool","interval":4.5,"loop":false,"duration":1.4},"TumblingDominoRack":{"key":"DraftSelected_TumblingDominoRack","interval":4.0,"loop":false,"duration":1.6},"RebelliousToyDrum":{"key":"DraftSelected_RebelliousToyDrum","interval":4.8,"loop":false,"duration":3.1},"WindUpCrabToy":{"key":"DraftSelected_WindUpCrabToy","interval":4.3,"loop":false,"duration":2.3},"OrigamiCrane":{"key":"DraftSelected_OrigamiCrane","interval":4.0,"loop":false,"duration":1.2},"DancingMetronome":{"key":"DraftSelected_DancingMetronome","interval":0.72,"loop":false,"duration":0.6},"ColdIron":{"key":"DraftSelected_ColdIron","interval":5.2,"loop":false,"duration":1.1},"GrumblingPiggyBank":{"key":"DraftSelected_GrumblingPiggyBank","interval":5.3,"loop":false,"duration":1.3},"ForgetfulDeskLamp":{"key":"DraftSelected_ForgetfulDeskLamp","interval":4.4,"loop":false,"duration":1.2},"NervousSaltShaker":{"key":"DraftSelected_NervousSaltShaker","interval":6.5,"loop":false,"duration":2.3},"CreepingTapeMeasure":{"key":"DraftSelected_CreepingTapeMeasure","interval":4.8,"loop":false,"duration":2.9},"SulkingUmbrella":{"key":"DraftSelected_SulkingUmbrella","interval":4.3,"loop":false,"duration":0.9},"BackwardsHairdryer":{"key":"DraftSelected_BackwardsHairdryer","interval":0,"loop":true,"duration":60},"NoseyMagnifier":{"key":"DraftSelected_NoseyMagnifier","interval":5.3,"loop":false,"duration":2.3},"SqueakyDuck":{"key":"DraftSelected_SqueakyDuck","interval":4.0,"loop":false,"duration":1.0}}]==])
local Crab=require(script:WaitForChild('SelectedCrabWander'))
-- ItemDraftEffects is driven only by the existing CursedBatchEffects owner.
-- It has no startup task, event connection, remote or independent heartbeat.
local Players = game:GetService('Players')
local Run = game:GetService('RunService')
local SS = game:GetService('ServerStorage')
local Audio = require(game.ServerScriptService.GameplayAudioServer)
local Registry = require(SS:WaitForChild('ItemDrafts'))
local M = {}
local states: {[Model]: any} = {}
local leaseClaims: {[Player]: any} = {}
local trailFolder: Folder? = nil

local function living(p)
    local c = p and p.Character
    local h = c and c:FindFirstChildOfClass('Humanoid')
    return p and p.Parent and p:GetAttribute('MissionActive') == true and h and h.Health > 0
end
local function root(p)
    local r = p and p.Character and p.Character:FindFirstChild('HumanoidRootPart')
    return r and r:IsA('BasePart') and r or nil
end
local function valid(s)
    local m = s.model
    return m.Parent and m:GetAttribute('SelectedItem') == true
        and SelectedSounds[s.id] ~= nil and Registry.Items[s.id] ~= nil
        and m:GetAttribute('ItemId') == s.id
        and m:GetAttribute('HeldBy') == s.player.UserId and not m:GetAttribute('Selling')
        and not m:GetAttribute('CargoStored') and not m:GetAttribute('MonsterCarried') and living(s.player)
end
local function publishLease(p, key)
    local byPlayer = leaseClaims[p]
    local claims = byPlayer and byPlayer[key]
    local now = workspace:GetServerTimeNow()
    local maximum = 0
    if claims then for _, untilAt in pairs(claims) do maximum = math.max(maximum, untilAt) end end
    p:SetAttribute(key, maximum > now and maximum or nil)
    if claims and not next(claims) then byPlayer[key] = nil end
    if byPlayer and not next(byPlayer) then leaseClaims[p] = nil end
end
local function restorePlayer(s, p)
    local records = s.leases[p]
    if not records then return end
    for key in pairs(records) do
        local byPlayer = leaseClaims[p]
        local claims = byPlayer and byPlayer[key]
        if claims then claims[s] = nil end
        publishLease(p, key)
    end
    s.leases[p] = nil
end
local function ownLease(s, p, key, untilAt)
    key = 'Draft' .. key -- Dedicated attributes cannot clobber normal-item ownership.
    local byPlayer = leaseClaims[p]
    if not byPlayer then byPlayer = {}; leaseClaims[p] = byPlayer end
    local claims = byPlayer[key]
    if not claims then claims = {}; byPlayer[key] = claims end
    claims[s] = untilAt
    local records = s.leases[p]
    if not records then records = {}; s.leases[p] = records end
    records[key] = untilAt
    publishLease(p, key) -- Max across all held draft sources, including simultaneous umbrellas.
end
local selectedSerial = 0
-- Character rendering has one selected channel. The newest still-held source
-- owns it; ending that source restores the previous held source deterministically.
local function publishSelected(p)
    local chosen
    for _, candidate in pairs(states) do
        if candidate.player == p and candidate.selected and valid(candidate)
            and (not chosen or candidate.selectedOrder > chosen.selectedOrder) then
            chosen = candidate
        end
    end
    p:SetAttribute('DraftSelectedItem', chosen and chosen.id or nil)
    p:SetAttribute('DraftSelectedStart', chosen and chosen.began or nil)
    p:SetAttribute('DraftSelectedUntil', chosen and workspace:GetServerTimeNow() + .8 or nil)
end
local function clear(s)
    states[s.model] = nil
    Audio.DraftStop(s.audioToken)
    if s.selected then publishSelected(s.player) end
    for p in pairs(s.leases) do restorePlayer(s, p) end
    for _, fx in pairs(s.fx) do if fx.root then fx.root:Destroy() end end
    for _, t in ipairs(s.temp) do if t.object then t.object:Destroy() end end
    for _, movers in pairs(s.movers) do
        for _, q in ipairs(movers) do
            if q.weld.Parent then q.weld.C0 = q.c0 end
            if q.part.Parent then q.part.Size = q.size end
        end
    end
    if s.model.Parent then
        s.model:SetAttribute('DraftEffectActive', nil)
        s.model:SetAttribute('DraftPulseCount', nil)
        s.model:SetAttribute('DraftLastPulse', nil)
        s.model:SetAttribute('DraftDangerNear', nil)
    end
end
local function part(s, name)
    for _, p in ipairs(s.model:GetChildren()) do
        if p:IsA('BasePart') and (p.Name == name or p.Name:sub(1, #name + 6) == name .. '_Color') then return p end
    end
    return s.model.PrimaryPart
end
local function effectPart(s)
    return part(s, s.spec.params.effectParts[1])
end
local function mark(s, now)
    s.model:SetAttribute('DraftPulseCount', (s.model:GetAttribute('DraftPulseCount') or 0) + 1)
    s.model:SetAttribute('DraftLastPulse', now)
end
local function sound(s, key)
    -- Draft audio uses the existing owner with a bounded, immediately stoppable token.
    local duration = s.spec.params.audioDuration or math.min(s.spec.duration_seconds or .8, 1.4)
    Audio.DraftPlay(key == 'CloudRain' and 'Wash' or key, s.model, s.audioToken, duration)
end
local function evidence(s, radius, label)
    local event = SS:FindFirstChild('MonsterEvidence')
    local r = s.model.PrimaryPart
    if event and event:IsA('BindableEvent') and r then
        event:Fire(r.Position, math.clamp(radius / 1.4, 1, 100), label, s.model)
    end
end
local function makeParticles(s, key, parent, kind, rate, life, owner)
    if not parent or not parent:IsA('BasePart') then return nil end
    local prior = s.fx[key]
    if prior and prior.root.Parent == parent then return prior end
    if prior then prior.root:Destroy() end
    local a = Instance.new('Attachment')
    a.Name = 'ItemDraftFX_' .. s.id .. '_' .. key
    a:SetAttribute('ItemDraftFX', true)
    a:SetAttribute('DraftSource', s.id)
    if owner then a:SetAttribute('DraftOwner', owner.UserId) end
    if kind == 'snow' or kind == 'rain' then a.Position = Vector3.new(0, 1.4, 0) end
    if kind == 'foam' then a.Position = Vector3.new(0, 0, -.1) end
    local e = Instance.new('ParticleEmitter')
    e.Name = 'DraftParticles'
    e.Texture = 'rbxasset://textures/particles/smoke_main.dds'
    e.Rate = math.clamp(rate or 6, 0, 8)
    e.Lifetime = NumberRange.new(life or .45, life or .6)
    e.Speed = NumberRange.new(.3, .8)
    e.SpreadAngle = Vector2.new(25, 25)
    e.LightEmission = .15
    e.Size = NumberSequence.new({NumberSequenceKeypoint.new(0, .08), NumberSequenceKeypoint.new(.5, .18), NumberSequenceKeypoint.new(1, 0)})
    e.Transparency = NumberSequence.new({NumberSequenceKeypoint.new(0, .55), NumberSequenceKeypoint.new(.7, .7), NumberSequenceKeypoint.new(1, 1)})
    e.Color = ColorSequence.new(Color3.fromRGB(240, 235, 220))
    if kind == 'water' or kind == 'rain' then
        e.Texture = 'rbxasset://textures/particles/sparkles_main.dds'
        e.Color = ColorSequence.new(Color3.fromRGB(151, 207, 225))
        e.Acceleration = Vector3.new(0, -7, 0)
        e.EmissionDirection = Enum.NormalId.Bottom
        e.Speed = NumberRange.new(1, 2)
        e.Size = NumberSequence.new(.055)
        e.Transparency = NumberSequence.new(.3)
        if kind == 'rain' then e.SpreadAngle = Vector2.new(60, 60) end
    elseif kind == 'snow' then
        e.Texture = 'rbxasset://textures/particles/sparkles_main.dds'
        e.Acceleration = Vector3.new(0, -1, 0)
        e.Color = ColorSequence.new(Color3.fromRGB(228, 244, 255))
        e.Size = NumberSequence.new(.055)
        e.Transparency = NumberSequence.new(.15)
        e.SpreadAngle = Vector2.new(80, 80)
    elseif kind == 'coldMist' or kind == 'steam' then
        e.Color = ColorSequence.new(Color3.fromRGB(196, 224, 236))
        e.Acceleration = Vector3.new(0, .6, 0)
    elseif kind == 'glimmer' then
        e.Texture = 'rbxasset://textures/particles/sparkles_main.dds'
        e.Color = ColorSequence.new(Color3.fromRGB(130, 200, 246))
        e.LightEmission = .6
        e.Size = NumberSequence.new(.075)
    elseif kind == 'dust' then
        e.Color = ColorSequence.new(Color3.fromRGB(198, 177, 140))
        e.Transparency = NumberSequence.new(.75)
    elseif kind == 'muffle' then
        e.Color = ColorSequence.new(Color3.fromRGB(65, 67, 76))
        e.Rate = 0
    elseif kind == 'salt' then
        e.Texture = 'rbxasset://textures/particles/sparkles_main.dds'
        e.Size = NumberSequence.new(.04)
        e.Rate = 0
    end
    e.Parent = a
    a.Parent = parent
    local fx = {root = a, emitter = e, owner = owner}
    s.fx[key] = fx
    return fx
end
local function light(s, key, parent, color, range)
    local prior = s.fx[key]
    if prior and prior.root.Parent == parent then return prior.light end
    if prior then prior.root:Destroy() end
    local a = Instance.new('Attachment')
    a.Name = 'ItemDraftFX_' .. s.id .. '_' .. key
    a:SetAttribute('ItemDraftFX', true)
    local l = Instance.new('PointLight')
    l.Name = 'DraftLight'; l.Color = color; l.Range = range; l.Brightness = 0; l.Shadows = false
    l.Parent = a; a.Parent = parent
    s.fx[key] = {root = a, light = l, owner = s.player}
    return l
end
local function movers(s, name)
    if s.movers[name] then return s.movers[name] end
    local list = {}
    for _, p in ipairs(s.model:GetChildren()) do
        if p:IsA('BasePart') and (p.Name == name or p.Name:sub(1, #name + 6) == name .. '_Color') then
            local w = p:FindFirstChild('DraftMeshWeld')
            if w and w:IsA('Weld') then list[#list + 1] = {part = p, weld = w, c0 = w.C0, size = p.Size} end
        end
    end
    s.movers[name] = list
    return list
end
local function worldFolder()
    if not trailFolder or not trailFolder.Parent then
        local folder = Instance.new('Folder'); folder.Name = 'ItemDraftTransientFX'; folder.Parent = workspace
        trailFolder = folder
    end
    return trailFolder
end
local function linePart(parent, a, b, width, color)
    local d = (b - a).Magnitude
    if d < .01 then return nil end
    local p = Instance.new('Part')
    p.Name = 'DraftTrail'; p.Size = Vector3.new(width, width, d)
    p.CFrame = CFrame.lookAt((a + b) * .5, b)
    p.Color = color; p.Material = Enum.Material.SmoothPlastic
    p.Anchored = true; p.CanCollide = false; p.CanTouch = false; p.CanQuery = false; p.CastShadow = false
    p:SetAttribute('ItemDraftFX', true); p.Parent = parent
    return p
end
local function temporary(s, object, now, life, maxCount)
    if not object then return end
    s.temp[#s.temp + 1] = {object = object, born = now, life = life}
    while #s.temp > maxCount do local q = table.remove(s.temp, 1); q.object:Destroy() end
end
local function canRain(p, q, radius)
    local a, b = root(p), root(q)
    if p:GetAttribute('Hiding') or p:GetAttribute('ClosetState') or p:GetAttribute('MonsterJumpscareActive') or not living(q) or not a or not b or (a.Position - b.Position).Magnitude > radius
        or q:GetAttribute('Hiding') or q:GetAttribute('ClosetState') or q:GetAttribute('MonsterJumpscareActive') then return false end
    if p == q then return true end
    local map = workspace:FindFirstChild('Mansion')
    local collision = map and map:FindFirstChild('Collision')
    if not collision then return false end
    local params = RaycastParams.new(); params.FilterType = Enum.RaycastFilterType.Include
    params.FilterDescendantsInstances = {collision}; params.RespectCanCollide = true
    return workspace:Raycast(a.Position + Vector3.new(0, 1, 0), b.Position - a.Position, params) == nil
end
-- Expansion channels share the existing owner's tick/frame and cleanup tables.
local motionAxes={X=Vector3.new(1,0,0),Y=Vector3.new(0,1,0),Z=Vector3.new(0,0,1)}
local function motionGroup(s,name)
    s.motionGroups=s.motionGroups or {}
    if s.motionGroups[name]then return s.motionGroups[name]end
    local list=movers(s,name)
    assert(#list>0,'Missing expansion motion group '..name)
    local low=Vector3.new(math.huge,math.huge,math.huge);local high=-low
    for _,q in ipairs(list)do
        local cf,z=q.c0,q.size
        local half=Vector3.new(math.abs(cf.RightVector.X)*z.X+math.abs(cf.UpVector.X)*z.Y+math.abs(cf.LookVector.X)*z.Z,
            math.abs(cf.RightVector.Y)*z.X+math.abs(cf.UpVector.Y)*z.Y+math.abs(cf.LookVector.Y)*z.Z,
            math.abs(cf.RightVector.Z)*z.X+math.abs(cf.UpVector.Z)*z.Y+math.abs(cf.LookVector.Z)*z.Z)*.5
        low=low:Min(cf.Position-half);high=high:Max(cf.Position+half)
    end
    local group={name=name,movers=list,center=(low+high)*.5,low=low,high=high,delta=CFrame.identity,scale=Vector3.one,offsets={}}
    s.motionGroups[name]=group
    return group
end
local function motionInit(s)
    if s.motionInitialized then return end
    local par=s.spec.params
    s.motionNeedsPeers=par.trigger=='peerNear'or par.trigger=='peerFar'
    for _,ch in ipairs(par.motionChannels)do
        for _,name in ipairs(ch.parts)do motionGroup(s,name)end
        if ch.pivotPart then motionGroup(s,ch.pivotPart)end
        local driver=ch.driver
        if driver=='peerNear'or driver=='peerFar'or driver=='peerYaw'or ch.operation=='trackPeer'then
            s.motionNeedsPeers=true
        elseif ch.operation=='fan'and ch.restAnglesDegrees then
            -- Only the authored-rest fan formula below depends on peer distance.
            for _,name in ipairs(ch.parts)do
                if ch.restAnglesDegrees[name]then s.motionNeedsPeers=true;break end
            end
        end
    end
    for child,parent in pairs(par.motionParents or {})do motionGroup(s,child);motionGroup(s,parent)end
    s.motionMoving=0;s.motionPeer=0;s.motionYaw=0;s.motionInput={moving=0,near=0,yaw=0}
    s.motionAngles={};s.motionInitialized=true
end
local function motionInput(s)
    motionInit(s)
    local par=s.spec.params;local r=root(s.player)
    if not r then return end
    local velocity=r.AssemblyLinearVelocity
    local speed=Vector3.new(velocity.X,0,velocity.Z).Magnitude
    if speed>(par.speedThreshold or 1.5)then s.motionMovingTarget=true
    elseif speed<.7 then s.motionMovingTarget=false end
    local nearest,dist=nil,par.peerRadius or 7
    if s.motionNeedsPeers then
        for _,q in ipairs(Players:GetPlayers())do
            if q~=s.player and canRain(s.player,q,dist)then
                local qr=root(q)
                if qr then local d=(qr.Position-r.Position).Magnitude;if d<=dist then nearest=q;dist=d end end
            end
        end
    end
    local yaw=0
    if nearest and s.model.PrimaryPart then
        local qr=root(nearest)
        if qr then local d=s.model.PrimaryPart.CFrame:VectorToObjectSpace(qr.Position-s.model.PrimaryPart.Position);yaw=math.atan2(-d.X,-d.Z)end
    end
    s.motionInput={moving=s.motionMovingTarget and 1 or 0,near=nearest and 1 or 0,yaw=yaw}
end
local function motionStrength(s,driver)
    if driver=='moving' then return s.motionMoving
    elseif driver=='still'then return 1-s.motionMoving
    elseif driver=='peerNear'then return s.motionPeer
    elseif driver=='peerFar'then return 1-s.motionPeer end
    return 1
end
local function motionPop(phase)
    local t=phase%1
    if t<.15 then local x=t/.15;return x*x*(3-2*x)
    elseif t<.45 then return 1
    elseif t<.7 then local x=(t-.45)/.25;return 1-x*x*(3-2*x)end
    return 0
end
local function motionWorld(s,g,visiting)
    if g.world then return g.world end
    assert(not visiting[g.name],'Cyclic expansion motion parent')
    visiting[g.name]=true
    local parent=(s.spec.params.motionParents or {})[g.name]
    g.world=parent and motionWorld(s,s.motionGroups[parent],visiting)*g.delta or g.delta
    visiting[g.name]=nil
    return g.world
end
local function motionFrame(s,dt,now)
    motionInit(s)
    local par=s.spec.params;local input=s.motionInput
    local ease=1-math.exp(-dt/0.12)
    s.motionMoving+=(input.moving-s.motionMoving)*ease
    s.motionPeer+=(input.near-s.motionPeer)*ease
    local yawDelta=(input.yaw-s.motionYaw+math.pi)%(math.pi*2)-math.pi
    s.motionYaw+=yawDelta*ease
    local strength=motionStrength(s,par.trigger)
    s.motionGate=strength
    -- Every channel starts from the same authored group pose; later channels compose.
    for _,g in pairs(s.motionGroups)do
        g.delta=CFrame.identity;g.scale=Vector3.one;table.clear(g.offsets);g.world=nil
    end
    local cycle=(now-s.began)/math.max(par.period or 3,.3)
    for index,ch in ipairs(par.motionChannels)do
        local axis=motionAxes[ch.axis]or motionAxes.Y
        local phase=cycle+(ch.phase or 0)
        local driver=ch.driver or 'sine'
        local value
        if driver=='sine'then value=math.sin(phase*math.pi*2)
        elseif driver=='pop'then value=motionPop(phase)
        elseif driver=='peerYaw'then value=s.motionYaw
        elseif driver=='movingRate'then value=.12+.88*s.motionMoving
        else value=driver==par.trigger and 1 or motionStrength(s,driver)end
        value*=strength
        local angle
        if ch.operation=='rotateContinuous'then
            local rate=driver=='movingRate'and(.12+.88*s.motionMoving)or 1
            s.motionAngles[index]=((s.motionAngles[index]or 0)+math.rad(ch.amplitude)*dt*rate*strength)%(math.pi*2)
            angle=s.motionAngles[index]
        elseif ch.operation=='trackPeer'then angle=math.clamp(s.motionYaw,-math.rad(ch.amplitude),math.rad(ch.amplitude))*s.motionPeer*strength
        else angle=math.rad(ch.amplitude)*value end
        local shared
        if ch.pivotPart then shared=motionGroup(s,ch.pivotPart).center
        else
            local low=Vector3.new(math.huge,math.huge,math.huge);local high=-low
            for _,name in ipairs(ch.parts)do local g=motionGroup(s,name);low=low:Min(g.low);high=high:Max(g.high)end
            shared=(low+high)*.5
        end
        for leafIndex,name in ipairs(ch.parts)do
            local g=motionGroup(s,name)
            if ch.operation=='translate'then g.delta*=CFrame.new(axis*(ch.amplitude*value))
            elseif ch.operation=='scale'then
                local fraction=math.clamp(ch.amplitude*value,-.4,.4)
                local factor=Vector3.one+axis*fraction
                g.scale*=factor
                local anchor=ch.anchor=='min'and g.low or shared
                if ch.anchorPart then anchor=motionGroup(s,ch.anchorPart).center end
                for _,q in ipairs(g.movers)do
                    g.offsets[q]=(g.offsets[q]or Vector3.zero)+(q.c0.Position-anchor)*axis*fraction
                end
            else
                local rotation=angle
                if ch.operation=='fan'then
                    local rest=(ch.restAnglesDegrees or {})[name]
                    local delta=(ch.deltaAnglesDegrees or {})[name]
                    if rest then rotation=-math.rad(rest)*(1-s.motionPeer)
                    elseif delta then rotation=math.rad(delta)*value
                    else rotation=math.rad(ch.amplitude)*((leafIndex-1)/math.max(1,#ch.parts-1)*2-1)*value end
                end
                local pivot=CFrame.new(shared)
                g.delta*=pivot*CFrame.fromAxisAngle(axis,rotation)*pivot:Inverse()
            end
        end
    end
    for _,g in pairs(s.motionGroups)do
        local transform=motionWorld(s,g,{})
        for _,q in ipairs(g.movers)do
            q.weld.C0=transform*CFrame.new(q.c0.Position+(g.offsets[q]or Vector3.zero))*q.c0.Rotation
            q.part.Size=q.size*g.scale
        end
    end
    local fx=s.fx.expansionGlimmer
    if fx then fx.emitter.Enabled=strength>.1 end
end

local function stamp(s, now, r)
    local params = RaycastParams.new(); params.FilterType = Enum.RaycastFilterType.Exclude
    params.FilterDescendantsInstances = {s.player.Character, s.model, worldFolder()}; params.RespectCanCollide = true
    local hit = workspace:Raycast(r.Position, Vector3.new(0, -s.spec.params.rayStuds, 0), params)
    if not hit or hit.Normal.Y < .5 then return end
    local normal = hit.Normal
    local tangent = normal:Cross(Vector3.new(0, 0, 1))
    if tangent.Magnitude < .1 then tangent = normal:Cross(Vector3.new(1, 0, 0)) end
    tangent = tangent.Unit
    local up = normal:Cross(tangent).Unit
    local f = Instance.new('Folder'); f.Name = 'DraftStamp_' .. s.player.UserId; f.Parent = worldFolder()
    local center = hit.Position + normal * .04
    for i = 0, 11 do
        local a, b = i * math.pi / 6, (i + 1) * math.pi / 6
        linePart(f, center + (tangent * math.cos(a) + up * math.sin(a)) * .32,
            center + (tangent * math.cos(b) + up * math.sin(b)) * .32, .035, Color3.fromRGB(158, 56, 72))
    end
    temporary(s, f, now, s.spec.params.markLife, s.spec.params.maxMarks)
    sound(s, s.spec.cues[1]); evidence(s, s.spec.params.noiseRadius, 'cursed rubber stamp'); mark(s, now)
end

function M.Pickup(p, m)
    if m:GetAttribute('SelectedItem') ~= true then return end
    local id = m:GetAttribute('ItemId')
    local entry = Registry.Items[id]
    if not entry or not SelectedSounds[id] or not living(p) then return end
    if states[m] then clear(states[m]) end
    local now = workspace:GetServerTimeNow()
    local s = {id = id, model = m, player = p, spec = entry.effect, began = now,
        next = now + (entry.effect.params.warmupSeconds or 0), stillSince = now,
        leases = {}, fx = {}, movers = {}, temp = {}, lastMoving = false, wasMoving = false,
        audioToken = game:GetService('HttpService'):GenerateGUID(false)}
    s.selected=SelectedSounds[id]
    Crab.Pickup(m)
    if s.selected then selectedSerial += 1; s.selectedOrder = selectedSerial end
    states[m] = s
    if s.selected then publishSelected(p) end
    m:SetAttribute('DraftEffectActive', id)
    if not s.selected and s.spec.kind == 'swollen_eye' then ownLease(s, p, 'MagnifierUntil', now + .5); sound(s, s.spec.cues[1]) end
end
function M.Release(p, m)
    local s = states[m]
    if s and s.player == p then clear(s);if s.id=='WindUpCrabToy'then Crab.Release(m,workspace:GetServerTimeNow(),p)end end
end
function M.ClearPlayer(p)
    Crab.ClearPlayer(p)
    local remove = {}
    for _, s in pairs(states) do
        if s.player == p then remove[#remove + 1] = s
        else
            restorePlayer(s, p)
            for key, fx in pairs(s.fx) do if fx.owner == p then fx.root:Destroy(); s.fx[key] = nil end end
        end
    end
    for _, s in ipairs(remove) do clear(s) end
end
function M.ClearLevel()
    Crab.ClearLevel()
    local remove = {}; for _, s in pairs(states) do remove[#remove + 1] = s end
    for _, s in ipairs(remove) do clear(s) end
    if trailFolder then trailFolder:Destroy(); trailFolder = nil end
end

function M.Tick(now)
    for _, s in pairs(states) do
        if not valid(s) then clear(s); continue end
        local p, spec = s.player, s.spec
        local par, kind = spec.params, spec.kind
        local r = root(p); if not r then clear(s); continue end
        local v = r.AssemblyLinearVelocity
        local speed = Vector3.new(v.X, 0, v.Z).Magnitude
        local moving = speed > (par.speedThreshold or .7)
        if speed >= (par.stillSpeed or .7) then s.stillSince = now end
        if moving then s.wasMoving = true end
        local age = now - s.began
        if s.selected then
            if p:GetAttribute('DraftSelectedItem') == s.id and p:GetAttribute('DraftSelectedStart') == s.began then
                p:SetAttribute('DraftSelectedUntil', now + .8)
            end
            local cue=s.selected
            if now>=(s.selectedAudioAt or 0)then
             Audio.DraftPlay(cue.key,s.model,s.audioToken,cue.loop and 60 or cue.duration)
             s.selectedAudioAt=now+(cue.loop and 50 or math.max(.3,cue.interval));mark(s,now)
            end
            if kind=='expansion_motion'then motionInput(s)end
            if kind=='moving_light'then
             s.lightOn=moving;light(s,'lamp',effectPart(s),Color3.fromRGB(255,221,155),par.range)
            end
            if s.id=='BackwardsHairdryer'then
             local nozzle=part(s,'Nozzle')
             local fx=s.fx.selectedWind
             if not fx and nozzle then
              local a=Instance.new('Attachment');a.Name='SelectedWindNozzle';a.Position=Vector3.new(0,0,-nozzle.Size.Z*.45);a.Parent=nozzle
              local em=Instance.new('ParticleEmitter');em.Name='Wind';em.Texture='rbxasset://textures/particles/smoke_main.dds';em.EmissionDirection=Enum.NormalId.Front
              em.Speed=NumberRange.new(12,18);em.Lifetime=NumberRange.new(.18,.35);em.Rate=42;em.SpreadAngle=Vector2.new(8,8)
              em.Size=NumberSequence.new({NumberSequenceKeypoint.new(0,.08),NumberSequenceKeypoint.new(.45,.25),NumberSequenceKeypoint.new(1,.42)})
              em.Transparency=NumberSequence.new({NumberSequenceKeypoint.new(0,.55),NumberSequenceKeypoint.new(1,1)});em.Color=ColorSequence.new(Color3.fromRGB(210,241,250));em.LightEmission=.25;em.Parent=a
              s.fx.selectedWind={root=a,emitter=em}
             end
            end
            continue
        end
        if kind == 'expansion_motion' then
            motionInput(s)
            if par.particle then makeParticles(s,'expansionGlimmer',effectPart(s),par.particle,math.min(par.maxParticleRate or 4,4),math.min(par.particleLifetime or .8,.8))end
            if now>=s.next and (s.motionGate or 1)>.1 then
                s.next=now+(par.period or 3);mark(s,now)
                if s.id=='ClackingCastanets'and s.motionMovingTarget then sound(s,'ItemRattle');evidence(s,16,'clacking castanets')end
            end
        elseif kind == 'moving_honk' or kind == 'moving_jingle' or kind == 'sneeze_pulse' then
            if moving and now >= s.next then
                s.next = now + spec.cooldown_seconds; sound(s, spec.cues[1]); mark(s, now)
                if spec.attributes[1] then ownLease(s, p, spec.attributes[1], now + spec.duration_seconds) end
                if par.noiseRadius then evidence(s, par.noiseRadius, s.id) end
                if par.particle then local fx = makeParticles(s, 'salt', effectPart(s), par.particle, 0, .4); fx.emitter:Emit(5) end
            end
        elseif kind == 'swollen_eye' then
            ownLease(s, p, 'MagnifierUntil', now + .5)
        elseif kind == 'pour_slide' or kind == 'held_buzz' or kind == 'held_muffle' or kind == 'cold_steam' then
            ownLease(s, p, spec.attributes[1], now + (par.leaseSeconds or .5))
            local fx = makeParticles(s, 'item', effectPart(s), par.particle, kind == 'held_muffle' and 0 or 6, .45)
            if now >= s.next then
                s.next = now + (spec.cooldown_seconds > 0 and spec.cooldown_seconds or 5)
                if fx and kind == 'held_muffle' then fx.emitter:Emit(3) end
                sound(s, spec.cues[1]); mark(s, now)
            end
        elseif kind == 'inflate_cycle' then
            local cycle = age % par.periodSeconds
            if cycle < par.onSeconds then
                ownLease(s, p, 'HeliumUntil', now + .5)
                if now >= s.next then s.next = now + par.periodSeconds; sound(s, spec.cues[1]); mark(s, now) end
            else restorePlayer(s, p) end
        elseif kind == 'coop_rain' then
            if now >= s.next then
                s.next = now + spec.cooldown_seconds
                for _, q in ipairs(Players:GetPlayers()) do
                    if canRain(p, q, par.radius) then
                        ownLease(s, q, 'CryingUntil', now + par.leaseSeconds)
                        local h = q.Character and q.Character:FindFirstChild('Head')
                        local fx = makeParticles(s, 'rain' .. q.UserId, h, 'rain', 8, .45, q)
                        if fx then fx.expires = now + par.leaseSeconds end
                    end
                end
                sound(s, spec.cues[1]); mark(s, now)
            end
        elseif kind == 'snap' then
            if now >= s.next then s.next = now + spec.cooldown_seconds; s.snapAt = now; sound(s, spec.cues[1]); evidence(s, par.noiseRadius, 'chattering stapler'); mark(s, now) end
        elseif kind == 'mouth_foam' or kind == 'head_snow' then
            local head = p.Character and p.Character:FindFirstChild('Head')
            local target = kind == 'mouth_foam' and head and head:FindFirstChild('ConnectedLips') or head
            makeParticles(s, 'character', target, par.particle, par.maxRate, par.lifeSeconds or .45, p)
            if now >= s.next then s.next = now + 6; sound(s, spec.cues[1]); mark(s, now) end
        elseif kind == 'extend_tape' then
            if age >= par.warmupSeconds and now >= s.next then s.next = now + spec.cooldown_seconds; sound(s, spec.cues[1]); mark(s, now) end
        elseif kind == 'moving_light' then
            if moving ~= s.lastMoving then s.stableSince = now; s.lastMoving = moving end
            if now - (s.stableSince or s.began) >= par.stableSeconds and s.lightOn ~= moving then
                s.lightOn = moving; sound(s, spec.cues[1]); mark(s, now)
            end
            light(s, 'lamp', effectPart(s), Color3.fromRGB(255, 221, 155), par.range)
        elseif kind == 'drowsy_still' then
            if now - s.stillSince >= par.warmupSeconds then ownLease(s, p, 'SnailUntil', now + par.leaseSeconds)
            else restorePlayer(s, p) end
        elseif kind == 'whisper_source' then
            if now >= s.next then s.next = now + spec.cooldown_seconds; sound(s, spec.cues[1]); evidence(s, par.noiseRadius, 'gossip seashell'); mark(s, now) end
        elseif kind == 'teapot_whistle' then
            if now - s.stillSince >= par.warmupSeconds and now >= s.next then
                s.next = now + spec.cooldown_seconds; ownLease(s, p, 'WhistleUntil', now + spec.duration_seconds)
                local fx = makeParticles(s, 'steam', effectPart(s), 'steam', 6, .45); if fx then fx.expires = now + spec.duration_seconds end
                sound(s, spec.cues[1]); mark(s, now)
            end
        elseif kind == 'danger_abacus' then
            local near = false; local folder = workspace:FindFirstChild('RoamingCreatures')
            if folder then for _, creature in ipairs(folder:GetChildren()) do
                local cr = creature:IsA('Model') and creature.PrimaryPart
                if cr and (cr.Position - r.Position).Magnitude <= par.dangerRadius then near = true; break end
            end end
            s.model:SetAttribute('DraftDangerNear', near)
            if now >= s.next then
                s.next = now + (near and par.nearInterval or par.farInterval)
                local l = light(s, 'bead', effectPart(s), Color3.fromRGB(240, 171, 70), 2); l.Brightness = .8
                s.flashUntil = now + .25; sound(s, spec.cues[1]); mark(s, now)
            end
        elseif kind == 'moving_dust' then
            local fx = makeParticles(s, 'dust', effectPart(s), 'dust', par.maxRate, .45)
            if fx then fx.emitter.Enabled = moving end
        elseif kind == 'face_halo' then
            local head = p.Character and p.Character:FindFirstChild('Head')
            if head and head:IsA('BasePart') then light(s, 'halo', head, Color3.fromRGB(144, 197, 244), par.range) end
        elseif kind == 'thread_trail' then
            local point = r.Position - Vector3.new(0, 2.5, 0)
            if moving and now >= s.next then
                if s.lastPoint and (point - s.lastPoint).Magnitude >= par.minTravel then
                    local segment = linePart(worldFolder(), s.lastPoint, point, par.segmentRadius * 2, Color3.fromRGB(113, 61, 115))
                    temporary(s, segment, now, par.segmentLife, par.maxSegments)
                end
                s.lastPoint = point; s.next = now + spec.cooldown_seconds
            elseif not moving then s.lastPoint = point end
        elseif kind == 'metronome_beat' then
            if now >= s.next then
                s.next = now + spec.cooldown_seconds; s.beats = (s.beats or 0) + 1
                sound(s, spec.cues[1]); if s.beats % 2 == 0 then evidence(s, par.noiseRadius, 'dancing metronome') end; mark(s, now)
            end
        elseif kind == 'floor_stamp' then
            if s.wasMoving and speed < .7 and now - s.stillSince >= par.stableSeconds and now >= s.next then
                stamp(s, now, r); s.wasMoving = false; s.next = now + spec.cooldown_seconds
            end
        end
    end
end

function M.Frame(dt, now)
    Crab.Frame(dt,now)
    for _, s in pairs(states) do
        if not valid(s) then clear(s); continue end
        for key, fx in pairs(s.fx) do
            if not fx.root.Parent or (fx.expires and now >= fx.expires) then fx.root:Destroy(); s.fx[key] = nil end
        end
        for i = #s.temp, 1, -1 do
            local t = s.temp[i]; local age = now - t.born
            if age >= t.life then t.object:Destroy(); table.remove(s.temp, i)
            else
                local alpha = math.clamp(age / t.life, 0, 1)
                if t.object:IsA('BasePart') then t.object.Transparency = alpha
                else for _, p in ipairs(t.object:GetChildren()) do if p:IsA('BasePart') then p.Transparency = alpha end end end
            end
        end
        local spec, par = s.spec, s.spec.params
        local age = now - s.began
        if spec.kind == 'expansion_motion' then motionFrame(s,dt,now)
        elseif spec.kind == 'snap' then
            local phase = s.snapAt and math.clamp((now - s.snapAt) / spec.duration_seconds, 0, 1) or 1
            local angle = phase < .65 and math.sin(phase / .65 * math.pi * .5) or (1 - phase) / .35
            for _, q in ipairs(movers(s, par.animatedPart)) do q.weld.C0 = q.c0 * CFrame.Angles(math.rad(par.angleDegrees) * angle, 0, 0) end
        elseif spec.kind == 'extend_tape' then
            local extension = age < par.warmupSeconds and 0 or (.5 - .5 * math.cos((age - par.warmupSeconds) * math.pi * 2 / spec.cooldown_seconds)) * par.extensionStuds
            local sign = s.model:GetAttribute('DraftForwardSign') or -1
            for _, q in ipairs(movers(s, par.animatedPart)) do q.part.Size = q.size + Vector3.new(0, 0, extension); q.weld.C0 = q.c0 * CFrame.new(0, 0, sign * extension * .5) end
            for _, q in ipairs(movers(s, par.companionPart)) do q.weld.C0 = q.c0 * CFrame.new(0, 0, sign * extension) end
            for _,name in {'HookFlange','HookRivets'}do for _,q in movers(s,name)do q.weld.C0=q.c0*CFrame.new(0,0,sign*extension)end end
            for _,q in movers(s,'TapeMarks')do q.weld.C0=q.c0*CFrame.new(0,0,sign*extension*.5);q.part.Size=q.size+Vector3.new(0,0,extension*.9)end
        elseif spec.kind == 'metronome_beat' then
            local angle = math.sin(age * math.pi * 2 / par.periodSeconds) * math.rad(par.angleDegrees)
            local rod = movers(s, par.animatedPart)[1]
            if rod then
                local pivot = CFrame.new(rod.c0.Position - Vector3.new(0, rod.size.Y * .5, 0))
                local transform = pivot * CFrame.Angles(0, 0, angle) * pivot:Inverse()
                for _, name in ipairs({par.animatedPart, par.companionPart}) do for _, q in ipairs(movers(s, name)) do q.weld.C0 = transform * q.c0 end end
            end
        elseif spec.kind == 'moving_light' then
            local l = s.fx.lamp and s.fx.lamp.light
            if l then local target = s.lightOn and par.brightness or 0; l.Brightness += (target - l.Brightness) * math.min(1, dt / par.fadeSeconds) end
        elseif spec.kind == 'face_halo' then
            local l = s.fx.halo and s.fx.halo.light
            if l then l.Brightness = par.minBrightness + (par.maxBrightness - par.minBrightness) * (.5 + .5 * math.sin(age * math.pi * 2 / par.periodSeconds)) end
        elseif spec.kind == 'danger_abacus' then
            local l = s.fx.bead and s.fx.bead.light
            if l and now >= (s.flashUntil or 0) then l.Brightness = 0 end
        end
    end
end
return M
