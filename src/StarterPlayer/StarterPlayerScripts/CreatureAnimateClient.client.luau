local missionPlayer=game:GetService('Players').LocalPlayer
-- Preload every monster's meshes and sounds as soon as the client starts (2026-10-22): the first monster to appear in a
-- server used to freeze the game for 60-280 ms while its 12-49 meshes and its sounds loaded mid-chase.
task.spawn(function()
 local RS=game:GetService('ReplicatedStorage')
 local list={}
 local portraits=RS:WaitForChild('MasteryPortraits',30)
 if portraits then for _,m in portraits:GetChildren()do table.insert(list,m)end end
 local catalog=RS:FindFirstChild('GameplaySoundCatalog')
 local ok,C=pcall(require,catalog)
 if ok and type(C)=='table'then
  for key,def in C do
   if type(key)=='string'and(key:find('Monster')or key:match('^Crawler')or key:match('^Wraith')or key:match('^Bellhop')or key:match('^Lantern')or key:match('^Neon'))and type(def)=='table'then
    local ids={def.id};for _,entry in type(def.pool)=='table'and def.pool or {}do if type(entry)=='table'then table.insert(ids,entry.id)end end
    for _,id in ids do if type(id)=='string'then local s=Instance.new('Sound');s.SoundId=id;table.insert(list,s)end end
   end
  end
 end
 pcall(function()game:GetService('ContentProvider'):PreloadAsync(list)end)
end)
while missionPlayer:GetAttribute('MissionActive')~=true do missionPlayer:GetAttributeChangedSignal('MissionActive'):Wait()end
-- Local pose animation for the custom Motor6D mesh rig. The server owns movement.
local RunService=game:GetService('RunService')
local Workspace=game:GetService('Workspace')
local mansion=Workspace:WaitForChild('Mansion',math.huge)
while mansion:GetAttribute('Ready')~=true or mansion:GetAttribute('RuntimeReady')~=true do mansion:GetAttributeChangedSignal('RuntimeReady'):Wait() end
local folder=Workspace:WaitForChild('RoamingCreatures')
local rigs={}
local function introStage(parent)return parent~=nil and parent.Name=='MonsterIntroStage' and parent.Parent==Workspace end
local function gather(model)
    if model.Parent~=folder and not introStage(model.Parent) then return end
    local motors={}
    for _,v in ipairs(model:GetDescendants()) do
        if v:IsA('Motor6D') then motors[v.Name]=v end
    end
    local legs={}
    for n,m in pairs(motors) do if n:match('^Leg_%d+Joint$') then table.insert(legs,{name=n,motor=m}) end end
    table.sort(legs,function(a,b) return a.name<b.name end)
    local previous=rigs[model]
    rigs[model]={baseTorsoC0=previous and previous.baseTorsoC0,visualRoot=previous and previous.visualRoot,motors=motors,legs=legs,seed=model:GetAttribute('PhaseSeed') or 0,
        kind=model:GetAttribute('CreatureKind'),bh=previous and previous.bh,lw=previous and previous.lw,
        phase=0,speed=0,lookYaw=0,lookPitch=0,nextLook=0,targetYaw=0,targetPitch=0,
        frenzy=previous and previous.frenzy or 0,nextGlitch=0,shards=nil,wisps=nil,veil=nil,whiteMist=nil,whiteSparks=nil,
        clips=previous and previous.clips,toy=previous and previous.toy}
end
folder.ChildAdded:Connect(function(child)
    if child:IsA('Model') then
        task.defer(gather,child)
        task.delay(1,gather,child)
        child.DescendantAdded:Connect(function(v)
            if v:IsA('Motor6D') then task.defer(gather,child) end
        end)
    end
end)
folder.ChildRemoved:Connect(function(child) rigs[child]=nil end)
for _,child in ipairs(folder:GetChildren()) do
    if child:IsA('Model') then
        gather(child)
        task.delay(1,gather,child)
        child.DescendantAdded:Connect(function(v)
            if v:IsA('Motor6D') then task.defer(gather,child) end
        end)
    end
end
-- MonsterIntroClient's local stage (2026-10-27): its display monsters (rigged by CreatureRoamServer.makeRig) move with
-- this same procedural animation, driven by the same attributes (Walking, AIState, MoveSpeed, AttackPose).
local function watchStage(stage)
    if not stage:IsA('Folder') or not introStage(stage) then return end
    stage.ChildAdded:Connect(function(child) if child:IsA('Model') then gather(child) end end)
    stage.ChildRemoved:Connect(function(child) rigs[child]=nil end)
    for _,child in ipairs(stage:GetChildren()) do if child:IsA('Model') then gather(child) end end
end
Workspace.ChildAdded:Connect(watchStage)
for _,child in ipairs(Workspace:GetChildren()) do if child.Name=='MonsterIntroStage' then watchStage(child) end end
local function pose(m,cframe)
    if m then m.Transform=cframe end
end

-- Haunted Bellhop: two-bone IK stilt legs with a twitchy high-knee gait, plus spring-driven bell, keys,
-- coat tails and eye stalks. Rest lengths match the Blender rig (studs, feet tips at the root).
local Audio=require(game:GetService('ReplicatedStorage'):WaitForChild('GameplayAudio'))
local localPlayer=game:GetService('Players').LocalPlayer
local BH={HipsY=4.45,HipY=4.35,HipX=.4,Thigh=2.15,Shin=2.2,SoundRange=75,AnimateRange=180}
local TAU=math.pi*2
local function lerp(a,b,t)return a+(b-a)*t end
local function springTo(s,target,k,c,dt)
    local n=math.max(1,math.ceil(dt*120));local h=dt/n
    for _=1,n do s.v+=((target-s.x)*k-s.v*c)*h;s.x+=s.v*h end
    return s.x
end
local function newSpring()return{x=0,v=0}end
local function legIK(f,h,L1,L2)
    L1=L1 or BH.Thigh;L2=L2 or BH.Shin
    local d=math.clamp(math.sqrt(f*f+h*h),.4,L1+L2-.002)
    local cb=math.clamp((L1*L1+d*d-L2*L2)/(2*L1*d),-1,1)
    local cg=math.clamp((L1*L1+L2*L2-d*d)/(2*L1*L2),-1,1)
    return math.atan2(f,h)+math.acos(cb),-(math.pi-math.acos(cg))
end
-- Pendulum hanging from `part`, driven by that part's real acceleration in the creature's frame.
local function pendulum(s,part,frame,dt,k,c,gain,limit)
    local pos=part.Position;local inv=1/math.max(dt,1e-3)
    local vel=s.pos and (pos-s.pos)*inv or Vector3.zero
    local acc=s.vel and (vel-s.vel)*inv or Vector3.zero
    s.pos=pos;s.vel=vel
    if acc.Magnitude>900 then acc=Vector3.zero end
    local a=frame:VectorToObjectSpace(acc)
    local n=math.max(1,math.ceil(dt*120));local h=dt/n
    for _=1,n do
        s.vx+=(-k*s.x-c*s.vx+a.Z*gain)*h;s.x+=s.vx*h
        s.vz+=(-k*s.z-c*s.vz-a.X*gain)*h;s.z+=s.vz*h
    end
    s.x=math.clamp(s.x,-limit,limit);s.z=math.clamp(s.z,-limit,limit)
    return CFrame.Angles(s.x,0,s.z)
end
local function newPendulum()return{x=0,vx=0,z=0,vz=0}end

-- Lantern Watcher: three spike legs stepping in sequence (IK keeps two planted while walking),
-- a lantern head swaying on its coiled neck, wandering stalk eyes and a gnashing chest mouth.
local LW={HipsY=4.35,Thigh=2.05,Shin=2.25,SoundRange=75,AnimateRange=180,
    Legs={{name='Left',hip=Vector3.new(-.42,-.05,-.16),foot=Vector3.new(-.9,0,-.6)},
        {name='Right',hip=Vector3.new(.42,-.05,-.16),foot=Vector3.new(.9,0,-.6)},
        {name='Back',hip=Vector3.new(0,-.05,.34),foot=Vector3.new(0,0,.95)}},
    WalkOffsets={0,1/3,2/3},ChaseOffsets={0,.5,.25}}
-- Neon-Eyed Tripod: same three-leg gait as the Lantern Watcher on longer, wider-set spikes, with a hinged
-- beak jaw instead of chest teeth, a fourth eye stalk and a chest light that burns red while it hunts.
local NT={HipsY=4.35,Thigh=2.1,Shin=2.25,SoundRange=80,AnimateRange=180,HeadY=8,
    Legs={{name='Left',hip=Vector3.new(-.46,0,-.18),foot=Vector3.new(-1.35,0,-.8)},
        {name='Right',hip=Vector3.new(.46,0,-.18),foot=Vector3.new(1.35,0,-.8)},
        {name='Back',hip=Vector3.new(0,0,.36),foot=Vector3.new(0,0,1.3)}},
    WalkOffsets={0,1/3,2/3},ChaseOffsets={0,.5,.25},Jaw=true,StepCue='NeonStep',ChatterCue='NeonChatter',
    LightBase=Color3.fromRGB(235,238,255),LightHunt=Color3.fromRGB(255,40,40),
    Stalks={Top=7,Left=3.5,Right=1.8,Far=2.6}}
local function smooth(t)return t*t*(3-2*t)end
local function animateLantern(model,rig,m,dt,now,frenzy,walking,root,camDistance)
    local LW=rig.kind=='Neon' and NT or LW
    if camDistance>LW.AnimateRange then return end
    local b=rig.lw
    if not b then
        b={rng=Random.new(math.floor(rig.seed*1000)+7),phase=rig.seed%1,speed=0,prevLeg={},neck=newPendulum(),
            look=Vector2.zero,tilt=0,tiltTarget=0,nextTilt=0,twitch=0,nextTwitch=now+3,nextChatter=0,mouth=0,
            stalks={},
            gutter=0,nextGutter=now+2}
        for name,rate in LW.Stalks or {Top=7,Left=3.5,Right=1.8} do b.stalks[name]={yaw=0,pitch=0,ty=0,tp=0,next=0,rate=rate} end
        rig.lw=b
    end
    local rng=b.rng
    local frame=root.CFrame.Rotation
    local vr=rig.visualRoot or root.CFrame
    local measured=0
    if b.lastPos then
        local d=vr.Position-b.lastPos
        measured=Vector3.new(d.X,0,d.Z).Magnitude/math.max(dt,1e-3)
        if measured>45 then measured=0 end
    end
    b.lastPos=vr.Position
    b.speed+=(measured-b.speed)*(1-math.exp(-dt*7))
    local speed=b.speed
    local move=math.clamp((speed-.6)/6,0,1)
    local run=frenzy
    local stride=lerp(2.8,3.4,run)*lerp(.35,1,move)*move
    local duty=lerp(.6,.45,run)
    b.phase=(b.phase+dt*speed*duty/math.max(stride,1)*(1+.08*math.sin(now*2.3+rig.seed)))%1
    local p=b.phase
    b.twitch=math.max(0,b.twitch-dt*6)
    if now>=b.nextTwitch then b.twitch=1;b.twitchDir=rng:NextNumber()<.5 and -1 or 1;b.nextTwitch=now+lerp(rng:NextNumber(3,7),rng:NextNumber(1.2,2.4),run)end
    local twitch=b.twitch*b.twitch*(b.twitchDir or 1)

    -- Hips glide low between three footfalls; the chase drops into a skittering crouch.
    local crouch=lerp(.28,lerp(.5,.82,run),move)
    local bob=lerp(.05,.14,run)*move*math.sin(p*TAU*3)
    local hipsPitch=-(.03+.1*run)*move
    local hipsT=CFrame.new(math.sin(p*TAU)*.06*move,-crouch+bob,0)*CFrame.Angles(hipsPitch,math.sin(p*TAU)*.06*move,math.sin(p*TAU+1)*.05*move)
    pose(m.TorsoJoint,hipsT)
    local hipsCF=CFrame.new(0,LW.HipsY,0)*hipsT
    local offsets=run>.5 and LW.ChaseOffsets or LW.WalkOffsets
    local lift=lerp(.75,1.15,run)*move
    local splay=1+.18*run
    for i,leg in LW.Legs do
        local legPhase=(p+offsets[i])%1
        local fw,up
        if legPhase<duty then fw=stride*(.5-legPhase/duty);up=0
        else
            local t=(legPhase-duty)/(1-duty)
            fw=stride*(-.5+smooth(t));up=lift*math.sin(math.pi*t)
        end
        local footPos=Vector3.new(leg.foot.X*splay,up,leg.foot.Z*splay-fw)
        local hip=hipsCF*leg.hip
        local rel=hipsCF.Rotation:Inverse()*(footPos-hip)
        local thigh,knee=legIK(-rel.Z,math.sqrt(rel.Y*rel.Y+rel.X*rel.X),LW.Thigh,LW.Shin)
        pose(m[leg.name..'Hip'],CFrame.Angles(thigh,0,math.atan2(rel.X,-rel.Y)))
        pose(m[leg.name..'Knee'],CFrame.Angles(knee,0,0))
        local prev=b.prevLeg[i]
        if prev and prev>=duty*.98 and legPhase<prev and move>.35 then
            b.neck.vx+=.5*(.5+run)
            if camDistance<LW.SoundRange then Audio.Play(LW.StepCue or 'LanternStep',root.CFrame*footPos,{volume=lerp(.13,.2,run),speed=1.6+rng:NextNumber(0,.3)})end
        end
        b.prevLeg[i]=legPhase
    end

    -- Torso hunches toward its prey; the chest mouth breathes, then gnashes when it hunts.
    local spinePitch=-(.1*move+.36*run)+math.sin(now*1.1+rig.seed)*.03
    pose(m.SpineJoint,CFrame.Angles(spinePitch-twitch*.12,math.sin(p*TAU)*.08*move+twitch*.25,math.sin(now*.8+rig.seed)*.025))
    local mouthTarget=run>.3 and (.45+.55*math.abs(math.sin(now*21)))*run or (.12+.12*math.sin(now*1.5+rig.seed))
    b.mouth+=(mouthTarget-b.mouth)*(1-math.exp(-dt*(run>.3 and 30 or 4)))
    if LW.Jaw then pose(m.JawJoint,CFrame.Angles(-b.mouth*.55,0,0)) -- the beak snaps open and shut
    else
        pose(m.TeethLeftJoint,CFrame.new(-b.mouth*.07,0,0))
        pose(m.TeethRightJoint,CFrame.new(b.mouth*.07,0,0))
    end
    if run>.5 and now>=b.nextChatter and camDistance<LW.SoundRange then
        b.nextChatter=now+rng:NextNumber(.45,.8)
        Audio.Play(LW.ChatterCue or 'LanternChatter',(m.TeethLeftJoint or m.JawJoint).Part1,{volume=.26,speed=.55+rng:NextNumber(0,.15)})
    end

    -- Where is the local player? The lantern and its eyes turn to you.
    local lookYaw,lookPitch,lookWeight=0,0,0
    local character=localPlayer.Character
    local target=character and character:FindFirstChild('Head')
    if target then
        local d=frame:VectorToObjectSpace(target.Position-(vr*Vector3.new(0,LW.HeadY or 7.3,0)))
        local dist=d.Magnitude
        if dist<45 and -d.Z>-dist*.3 then
            lookYaw=math.clamp(math.atan2(-d.X,-d.Z),-1.2,1.2)
            lookPitch=math.clamp(math.atan2(d.Y,math.sqrt(d.X*d.X+d.Z*d.Z)),-.6,.5)
            lookWeight=math.max(run,math.clamp((28-dist)/12,0,1))
        end
    end
    b.look=b.look:Lerp(Vector2.new(lookYaw,lookPitch)*lookWeight,1-math.exp(-dt*(2.2+8*run)))

    -- Neck coil: an upright spring that lags behind the body, so the lantern sways like it hangs.
    local torsoPart=m.NeckJoint and m.NeckJoint.Part0
    if torsoPart then pendulum(b.neck,torsoPart,frame,dt,55,3.2,.3,.55) end
    if now>=b.nextTilt then b.tiltTarget=rng:NextNumber(-.38,.38)*(1-run*.6);b.nextTilt=now+rng:NextNumber(1.4,3.5)end
    b.tilt+=(b.tiltTarget-b.tilt)*(1-math.exp(-dt*2.5))
    pose(m.NeckJoint,CFrame.Angles(-b.neck.x-spinePitch*.55+b.look.Y*.35,b.look.X*.4,-b.neck.z+b.tilt*.4))
    pose(m.HeadJoint,CFrame.Angles(b.look.Y*.45-spinePitch*.35,b.look.X*.6+twitch*.7,b.tilt*.6+math.sin(now*.9+rig.seed)*.04))

    -- Stalk eyes wander on their own, then swivel onto you one after another.
    for name,st in b.stalks do
        if now>=st.next then st.ty=rng:NextNumber(-.5,.5);st.tp=rng:NextNumber(-.25,.3);st.next=now+rng:NextNumber(.8,2.6)end
        local wantYaw=lerp(st.ty,(lookYaw-b.look.X)*.9,lookWeight)
        local wantPitch=lerp(st.tp,lookPitch*.6,lookWeight)
        local rate=st.rate*(1+run*2)
        st.yaw+=(wantYaw-st.yaw)*(1-math.exp(-dt*rate))
        st.pitch+=(wantPitch-st.pitch)*(1-math.exp(-dt*rate))
        local sway=math.sin(now*1.3+#name+rig.seed)*.06
        pose(m[name..'StalkJoint'],CFrame.Angles(st.pitch*.45+sway-b.neck.x*.6,st.yaw*.45,-b.neck.z*.6+sway*.5))
        pose(m[name..'CupJoint'],CFrame.Angles(st.pitch*.5,st.yaw*.55,0))
    end

    -- Long arms: loose and swinging on patrol, reaching and clutching on the hunt.
    local swing=math.cos(p*TAU)*.25*move
    for _,side in {'Left','Right'} do
        local k=side=='Left' and 1 or -1
        local reach=math.sin(now*5.2+k*1.7+rig.seed)
        pose(m[side..'Shoulder'],CFrame.Angles(.12+swing*k+run*(1.05+.35*reach)+twitch*.3,run*.22*k,k*(-(.06+.1*run))))
        pose(m[side..'Elbow'],CFrame.Angles(.25+.1*math.sin(p*TAU+k)*move+run*(.35+.35*math.max(0,-reach)),0,0))
        pose(m[side..'Wrist'],CFrame.Angles(.3+.18*math.sin(now*3.1+k)+run*.35*math.max(0,reach),math.sin(now*2.2+k)*.12,math.sin(now*4.7+k)*.1))
    end

    -- The lantern gutters now and then, and burns hot while it hunts.
    rig.lanternLight=rig.lanternLight or model:FindFirstChild('LanternLight',true)
    if now>=b.nextGutter then b.gutter=1;b.nextGutter=now+rng:NextNumber(2,6)end
    b.gutter=math.max(0,b.gutter-dt*9)
    local light=rig.lanternLight
    if light then
        light.Brightness=(1.7+.25*math.sin(now*13+rig.seed)*math.sin(now*4.1)+1.3*run)*(1-.7*b.gutter)
        light.Color=(LW.LightBase or Color3.fromRGB(205,222,255)):Lerp(LW.LightHunt or Color3.fromRGB(255,176,160),run*.65)
    end
end

local function animateBellhop(model,rig,m,dt,now,frenzy,walking,root,camDistance)
    if camDistance>BH.AnimateRange then return end
    local b=rig.bh
    if not b then
        b={rng=Random.new(math.floor(rig.seed*1000)),phase=rig.seed%1,speed=0,head=Vector3.zero,headTarget=Vector3.zero,nextHead=0,
            spasm=0,spasmDir=1,nextSpasm=now+2,stalkL={x=newSpring(),z=newSpring()},stalkR={x=newSpring(),z=newSpring()},
            cap={x=newSpring(),z=newSpring()},bell=newPendulum(),keys=newPendulum(),prevLeg={},nextRing=0,ringFlash=0,
            ringUntil=0,nextIdleRing=now+5,wildUntil=0,nextWild=now+6,lastHead=Vector3.zero}
        rig.bh=b
    end
    local rng=b.rng
    local frame=root.CFrame.Rotation
    -- Ground speed from the smoothed visual root, so the planted spikes match what players see.
    local vr=rig.visualRoot or root.CFrame
    local measured=0
    if b.lastPos then
        local d=vr.Position-b.lastPos
        measured=Vector3.new(d.X,0,d.Z).Magnitude/math.max(dt,1e-3)
        if measured>45 then measured=0 end
    end
    b.lastPos=vr.Position
    b.speed+=(measured-b.speed)*(1-math.exp(-dt*7))
    local speed=b.speed
    local move=math.clamp((speed-.6)/6,0,1)
    local run=frenzy
    local stride=lerp(3.5,4.4,run)*lerp(.4,1,move)*move
    local duty=lerp(.56,.38,run)
    local stutter=1+.14*math.sin(now*3.3+rig.seed)*math.sin(now*1.9+rig.seed*2)
    b.phase=(b.phase+dt*speed*duty/math.max(stride,1.2)*stutter)%1
    local p=b.phase

    -- Twitch spasms: a violent jolt every few seconds, more often while chasing.
    b.spasm=math.max(0,b.spasm-dt*5.5)
    if now>=b.nextSpasm then
        b.spasm=1;b.spasmDir=rng:NextNumber()<.5 and -1 or 1
        b.nextSpasm=now+lerp(rng:NextNumber(2.2,5),rng:NextNumber(.7,1.6),run)
    end
    local spasm=b.spasm*b.spasm
    local tremor=run*math.sin(now*39+rig.seed)*math.sin(now*23.7)

    -- Hips: crouched lurch, rolling onto the stance leg, twisting with the stride.
    local crouch=lerp(.14,lerp(.48,.82,run),move)+math.sin(now*1.1+rig.seed)*.04*(1-move)
    local bob=-crouch+lerp(.15,.34,run)*move*(.5-.5*math.cos(p*TAU*2))
    local sway=math.sin(p*TAU)*.14*move+math.sin(now*.9+rig.seed)*.07*(1-move)
    local hipsPitch=-(.05+.16*run)*move-.03
    local hipsT=CFrame.new(sway,bob,0)*CFrame.Angles(hipsPitch+tremor*.03,math.sin(p*TAU)*.13*move,math.sin(p*TAU)*.08*move+tremor*.04+spasm*.12*b.spasmDir)
    pose(m.TorsoJoint,hipsT)
    local hipsCF=CFrame.new(0,BH.HipsY,0)*hipsT

    -- Legs: snap the knee up high, hang, then stab the spike down.
    local lift=lerp(1.3,2.0,run)*move
    for i,side in {'Left','Right'} do
        local sx=side=='Left' and -1 or 1
        local legPhase=(p+(i-1)*.5)%1
        local fw,up,inward
        if legPhase<duty then
            fw=stride*(.5-legPhase/duty);up=0;inward=0
        else
            local t=(legPhase-duty)/(1-duty)
            fw=stride*(-.5+(1-(1-t)^2.6));up=lift*math.sin(math.pi*math.min(1,t^.7));inward=math.sin(math.pi*t)*.18*move
        end
        local hip=hipsCF*Vector3.new(sx*BH.HipX,BH.HipY-BH.HipsY,0)
        local footPos=Vector3.new(sx*(BH.HipX-inward),up,-fw)
        local rel=hipsCF.Rotation:Inverse()*(footPos-hip)
        local h=math.sqrt(rel.Y*rel.Y+rel.X*rel.X)
        local thigh,knee=legIK(-rel.Z,h)
        local splay=math.atan2(rel.X,-rel.Y)
        pose(m[side..'Hip'],CFrame.Angles(thigh,0,splay))
        pose(m[side..'Knee'],CFrame.Angles(knee,0,0))
        b['thigh'..side]=thigh
        local prev=b.prevLeg[i]
        if prev and legPhase<prev and move>.35 then
            -- Spike lands: clack, and everything that dangles gets a kick.
            b.stalkL.x.v+=2.2*(.6+run);b.stalkR.x.v+=1.8*(.6+run);b.cap.x.v+=1.4
            if camDistance<BH.SoundRange then Audio.Play('BellhopStep',root.CFrame*footPos,{volume=lerp(.16,.26,run),speed=1.4+rng:NextNumber(0,.25)})end
        end
        b.prevLeg[i]=legPhase
    end

    -- Torso: hunched over the claw, counter-twisting the hips.
    local torsoPitch=-(.08+.22*run)*move-.06+math.sin(p*TAU*2)*.035*move+math.sin(now*1.3+rig.seed)*.02
    pose(m.SpineJoint,CFrame.Angles(torsoPitch+tremor*.05-spasm*.25,-math.sin(p*TAU)*.24*move+spasm*.35*b.spasmDir,-math.sin(p*TAU)*.05*move+tremor*.05))

    -- Head: snapping cocks and tilts; it stares at you when you are close or it is chasing.
    if now>=b.nextHead then
        local extreme=rng:NextNumber()<.35
        b.headTarget=Vector3.new(rng:NextNumber(-.18,.3),rng:NextNumber(-.45,.45),(extreme and .75 or .4)*rng:NextNumber(-1,1))
        b.nextHead=now+lerp(rng:NextNumber(.45,1.6),rng:NextNumber(.12,.38),run)
    end
    local lookYaw,lookPitch,lookWeight=0,0,0
    local character=localPlayer.Character
    local target=character and character:FindFirstChild('Head')
    if target then
        local headWorld=vr*Vector3.new(0,7.1,0)
        local d=frame:VectorToObjectSpace(target.Position-headWorld)
        local dist=d.Magnitude
        if dist<42 and -d.Z>-dist*.2 then
            lookYaw=math.clamp(math.atan2(-d.X,-d.Z),-1.15,1.15)
            lookPitch=math.clamp(math.atan2(d.Y,math.sqrt(d.X*d.X+d.Z*d.Z)),-.6,.5)
            lookWeight=math.max(run,math.clamp((26-dist)/12,0,1))
        end
    end
    local want=b.headTarget*(1-lookWeight*.55)+Vector3.new(lookPitch-torsoPitch*.7,lookYaw,0)*lookWeight
    b.head=b.head:Lerp(want,1-math.exp(-dt*(14+10*run)))
    local hv=(b.head-b.lastHead)/math.max(dt,1e-3);b.lastHead=b.head
    pose(m.NeckJoint,CFrame.Angles(b.head.X+tremor*.07,b.head.Y+spasm*1.15*b.spasmDir+tremor*.09,b.head.Z+tremor*.1-spasm*.5*b.spasmDir))

    -- Eye stalks and cap: wobbly springs fed by head snaps and footfalls.
    local wild=now<b.wildUntil and 1 or 0
    if now>=b.nextWild then b.wildUntil=now+rng:NextNumber(.6,1.3);b.nextWild=now+rng:NextNumber(5,11)end
    for _,side in {'Left','Right'} do
        local sx=side=='Left' and -1 or 1
        local st=side=='Left' and b.stalkL or b.stalkR
        local kx=springTo(st.x,-hv.X*.05+math.sin(now*1.6+sx+rig.seed)*.06,150,6.5,dt)
        local kz=springTo(st.z,hv.Y*.04*sx+hv.Z*.05+math.sin(now*1.2+sx*2)*.05,150,6.5,dt)
        pose(m[side..'StalkJoint'],CFrame.Angles(kx,0,kz))
        local eyeYaw=math.clamp((lookYaw-b.head.Y)*.5,-.35,.35)*lookWeight+wild*.45*sx*math.sin(now*9+sx)
        pose(m[side..'CupJoint'],CFrame.Angles(math.clamp(lookPitch*.4,-.3,.3)*lookWeight+wild*.3*math.cos(now*7*sx),eyeYaw,0))
    end
    pose(m.CapJoint,CFrame.Angles(springTo(b.cap.x,-hv.X*.035,210,9,dt),0,springTo(b.cap.z,hv.Z*.04,210,9,dt)))

    -- Arms: claw raised and slashing; bell arm swinging, shaking it when it hunts.
    if walking==false and now>=b.nextIdleRing then b.ringUntil=now+rng:NextNumber(.7,1.2);b.nextIdleRing=now+rng:NextNumber(5,10)end
    local ringing=math.max(run,now<b.ringUntil and 1 or 0)
    local swing=math.cos(p*TAU)*lerp(.38,.55,run)*move
    local slash=run*math.sin(p*TAU*2+1.2)
    local twitch=math.sin(now*13+rig.seed)*math.sin(now*7.7)
    pose(m.RightShoulder,CFrame.Angles(lerp(.4,1.15,run)+swing*(1-run*.6)+slash*.42+spasm*.6,-.25*run+math.sin(now*2.3)*.12*run,.22+.2*run+spasm*.5))
    pose(m.RightElbow,CFrame.Angles(lerp(.5,.3,run)+.2*math.sin(p*TAU+.6)*move+math.max(0,slash)*.6,0,0))
    pose(m.RightWrist,CFrame.Angles(.2+twitch*.25+run*.25,twitch*.15,math.sin(now*9.1)*.12))
    local shake=math.sin(now*31+rig.seed)*ringing
    pose(m.LeftShoulder,CFrame.Angles(.2-swing+ringing*(.75+.25*math.sin(now*12)),0,-(.16+.55*ringing)-spasm*.4))
    pose(m.LeftElbow,CFrame.Angles(.3+ringing*.75+.15*math.sin(p*TAU)*move,0,0))
    pose(m.LeftWrist,CFrame.Angles(shake*.55,0,shake*.35))

    -- Bell and keys hang from the moving hand and hips; real swing, never through the coat.
    local hand=m.BellJoint and m.BellJoint.Part0
    if hand then
        local swingCF=pendulum(b.bell,hand,frame,dt,95,2.4,.55,1.05)
        local handRel=frame:Inverse()*hand.CFrame.Rotation
        pose(m.BellJoint,handRel:Inverse()*swingCF)
        local bellSpeed=math.sqrt(b.bell.vx^2+b.bell.vz^2)
        if bellSpeed>2.6 and now>=b.nextRing then
            b.nextRing=now+(run>.5 and rng:NextNumber(.28,.42) or rng:NextNumber(.55,.9))
            b.ringFlash=1
            if camDistance<BH.SoundRange then Audio.Play('BellhopBell',m.BellJoint.Part1,{volume=math.clamp(.12+bellSpeed*.03,.12,.38),speed=.92+rng:NextNumber(0,.16)})end
        end
    end
    local hips=m.KeysJoint and m.KeysJoint.Part0
    if hips then
        local keyCF=pendulum(b.keys,hips,frame,dt,120,3,.5,.9)
        pose(m.KeysJoint,(frame:Inverse()*hips.CFrame.Rotation):Inverse()*keyCF)
    end
    b.ringFlash=math.max(0,b.ringFlash-dt*3)
    rig.bellLight=rig.bellLight or model:FindFirstChild('BellLight',true)
    if rig.bellLight then rig.bellLight.Brightness=2+.35*math.sin(now*17+rig.seed)*math.sin(now*5.3)+1.3*b.ringFlash end

    -- Coat tails trail behind, flare at the sides and get kicked by the knees.
    local flutter=(math.sin(now*8.3+rig.seed)*.05+math.sin(now*13.1)*.03)*move
    local trail=.03+speed*.011+.08*run
    pose(m.CoatBackJoint,CFrame.Angles(-trail+flutter,0,math.sin(p*TAU)*.05*move))
    pose(m.CoatLeftJoint,CFrame.Angles(-trail*.5+math.min(.22,math.max(0,b.thighLeft or 0)*.16)+flutter,0,-(.04+speed*.005)-flutter*.6))
    pose(m.CoatRightJoint,CFrame.Angles(-trail*.5+math.min(.22,math.max(0,b.thighRight or 0)*.16)-flutter,0,(.04+speed*.005)+flutter*.6))
end
-- Lonely Mittens and the Wind-Up Dancer (Monsters build 2026-10-27): rbxanim clips through the model's own Animator once
-- their published ids sit on the template (AnimIdle, AnimWalk, AnimChase, AnimSignature, Anim<AttackPose>); until then a
-- procedural pose. What a biped clip can't own stays procedural either way: the Dancer's key, tutu and raised leg, and
-- the Mittens' scarf tail.
local CLIP_ATTRS={'AnimIdle','AnimWalk','AnimChase','AnimSignature','AnimReach','AnimWave','AnimHug','AnimFlinch','AnimCurtsy','AnimTwirl'}
local LOOPED={AnimIdle=true,AnimWalk=true,AnimChase=true,AnimSignature=true}
local function clipsFor(model,rig)
    if rig.clips~=nil then return rig.clips end
    rig.clips=false
    local ac=model:FindFirstChildOfClass('AnimationController');local animator=ac and ac:FindFirstChildOfClass('Animator')
    if not animator then return false end
    local list={}
    for _,attr in CLIP_ATTRS do
        local id=model:GetAttribute(attr)
        if type(id)=='string' and id:match('%d') then
            local a=Instance.new('Animation');a.AnimationId=id
            local ok,track=pcall(animator.LoadAnimation,animator,a)
            if ok and track then track.Looped=LOOPED[attr]==true;list[attr]=track end
        end
    end
    if next(list) then rig.clips=list end
    return rig.clips
end
local function playClip(rig,want,speed)
    for attr,track in rig.clips do
        if attr==want then if not track.IsPlaying then track:Play(.2) end;track:AdjustSpeed(speed or 1)
        elseif track.IsPlaying then track:Stop(.2) end
    end
end
local function animateToy(model,rig,m,dt,now,frenzy,walking,root,camDistance)
    if camDistance>180 then return end
    local b=rig.toy
    if not b then b={key=0,keyRate=0,scarf=newPendulum()};rig.toy=b end
    local attack=model:GetAttribute('AttackPose')
    local dance=model:GetAttribute('DanceState')
    local signature=(rig.kind=='Dancer' and dance=='Look') or (rig.kind=='Mittens' and attack=='Lead')
    local clips=clipsFor(model,rig)
    if clips then
        local want=attack and attack~='Lead' and clips['Anim'..attack] and 'Anim'..attack
            or signature and clips.AnimSignature and 'AnimSignature'
            or walking and (frenzy>.5 and clips.AnimChase and 'AnimChase' or clips.AnimWalk and 'AnimWalk') or 'AnimIdle'
        if clips[want] then playClip(rig,want,(want=='AnimWalk' or want=='AnimChase') and math.clamp((model:GetAttribute('MoveSpeed') or 10)/10,.6,2.2) or 1) end
    else
        local p=rig.phase+rig.seed;local move=rig.speed
        local reach=(attack=='Reach' or attack=='Curtsy') and 1 or 0
        if rig.kind=='Mittens' then
            -- A shuffling waddle; the head droops and tilts, lonely; mittens swing late; reach = both arms out.
            local flinch=attack=='Flinch' and 1 or 0
            pose(m.TorsoJoint,CFrame.new(0,math.abs(math.sin(p))*.12*move,0)*CFrame.Angles(.05+.22*frenzy-.25*flinch,math.sin(p*.5)*.05*move,math.sin(p)*.07*move))
            pose(m.Neck,CFrame.Angles(.12-.1*frenzy+math.sin(now*.7+rig.seed)*.04,math.sin(now*.45+rig.seed)*.3*(1-frenzy),.22*math.sin(now*.6+rig.seed)))
            for _,s in {'Left','Right'}do
                local k=s=='Left' and 1 or -1
                local swing=math.sin(p+(k>0 and 0 or math.pi)-.6)*.35*move
                local wave=(s=='Left' and attack=='Wave') and 1 or 0
                local lead=(s=='Right' and attack=='Lead') and 1 or 0
                local hug=attack=='Hug' and 1 or 0
                pose(m[s..' Shoulder'],CFrame.Angles(swing+reach*1.35+frenzy*.9+lead*.45+hug*1.2+flinch*2.2+wave*(2.6+.25*math.sin(now*9)),0,k*(.06+hug*.5-lead*.35)))
                pose(m[s..' Hip'],CFrame.Angles(math.sin(p+(k>0 and 0 or math.pi))*.32*move,0,0))
            end
        elseif rig.kind=='Yoyo' then
            -- The Yo-Yo Kid (Story build 2026-10-29): a loose, lanky stalk; the long arms swing late, the yo-yo head lolls
            -- and turns slowly as if listening; reach = both arms out.
            pose(m.TorsoJoint,CFrame.new(0,math.abs(math.sin(p))*.1*move,0)*CFrame.Angles(.1+.25*frenzy,math.sin(p*.5)*.08*move,math.sin(p)*.05*move))
            pose(m.Neck,CFrame.Angles(math.sin(now*.8+rig.seed)*.08-.1*frenzy,math.sin(now*.37+rig.seed)*.45*(1-frenzy),.3*math.sin(now*.55+rig.seed)))
            for _,s in {'Left','Right'}do
                local k=s=='Left' and 1 or -1
                pose(m[s..' Shoulder'],CFrame.Angles(math.sin(p+(k>0 and math.pi or 0)-.8)*.45*move+reach*1.4+frenzy*.6,0,k*.05))
                pose(m[s..' Hip'],CFrame.Angles(math.sin(p+(k>0 and 0 or math.pi))*.45*move,0,0))
            end
        else
            -- The Dancer glides on her toe: arms keep the hoop, open wide while she looks; a lean into the chase.
            pose(m.TorsoJoint,CFrame.new(0,math.sin(now*1.6+rig.seed)*.06,0)*CFrame.Angles(.08*frenzy+.2*reach,0,math.sin(p*.5)*.04*move))
            pose(m.Neck,CFrame.Angles(math.sin(now*.9)*.05,math.sin(now*.5+rig.seed)*.2,math.sin(now*1.3+rig.seed)*.12))
            local open=(dance=='Look' or attack=='Twirl') and 1 or 0
            for _,s in {'Left','Right'}do
                local k=s=='Left' and 1 or -1
                pose(m[s..' Shoulder'],CFrame.Angles(-open*1.2+reach*.6+math.sin(now*1.1+k)*.04,0,k*open*1.1))
            end
        end
    end
    if rig.kind=='Dancer' then
        -- The key turns while the tune plays, slows as it winds down and stops while she looks.
        local target=dance=='Dance' and 4 or dance=='Winding' and math.max(.4,4*math.clamp(((model:GetAttribute('DanceUntil') or 0)-Workspace:GetServerTimeNow())/1.6,0,1)) or 0
        b.keyRate+=(target-b.keyRate)*(1-math.exp(-dt*6));b.key=(b.key+b.keyRate*dt)%TAU
        pose(m.KeyJoint,CFrame.Angles(0,0,b.key))
        pose(m.TutuJoint,CFrame.Angles(math.sin(now*3.1+rig.seed)*.03*(1+frenzy),0,math.sin(now*2.3)*.04*(1+frenzy)))
        pose(m.LegBackJoint,CFrame.Angles(math.sin(now*1.2+rig.seed)*.06-.15*frenzy,0,0))
    else
        -- The scarf tail trails and swings from the body's real motion.
        local torso=m.ScarfJoint and m.ScarfJoint.Part0
        if torso then pose(m.ScarfJoint,pendulum(b.scarf,torso,root.CFrame.Rotation,dt,40,2.6,.35,.6)) end
    end
end
-- Attack poses (MonsterAbilities, 2026-10-22): laid over the walk cycle while the server's AttackPose is set.
local function attackPose(model,m)
    local name=model:GetAttribute('AttackPose');if not name then return end
    local age=Workspace:GetServerTimeNow()-(model:GetAttribute('AttackPoseAt')or 0)
    local ease=math.clamp(age/.25,0,1);ease=ease*ease*(3-2*ease)
    if name=='Carry' or name=='Reach' then
        local lift=name=='Carry' and 1.55 or 1.25
        local bob=math.sin(age*5.2)*.08
        pose(m.LeftShoulder,CFrame.Angles((lift+bob)*ease,0,-.22*ease));pose(m.RightShoulder,CFrame.Angles((lift+bob)*ease,0,.22*ease))
        pose(m.LeftElbow,CFrame.Angles(.55*ease,0,0));pose(m.RightElbow,CFrame.Angles(.55*ease,0,0))
        pose(m.LeftWrist,CFrame.Angles(.25*ease,0,0));pose(m.RightWrist,CFrame.Angles(.25*ease,0,0))
        if m.NeckJoint then pose(m.NeckJoint,CFrame.Angles(.18*ease,math.sin(age*1.7)*.25,math.sin(age*2.3)*.12))end
    elseif name=='Swing' then
        local a=math.clamp(age/.3,0,1)
        pose(m.RightShoulder,CFrame.Angles(2.5-2.9*a*a,0,.35));pose(m.RightElbow,CFrame.Angles(.2+.4*a,0,0))
        pose(m.LeftShoulder,CFrame.Angles(.4,0,-.3))
    elseif name=='Stare' then
        pose(m.LeftShoulder,CFrame.Angles(.35*ease,0,-.15));pose(m.RightShoulder,CFrame.Angles(.35*ease,0,.15))
        if m.NeckJoint then pose(m.NeckJoint,CFrame.Angles(.22*ease+math.sin(age*9)*.02,0,math.sin(age*1.3)*.08))end
    elseif name=='Laser' then
        local shake=math.sin(age*48)*.04
        if m.JawJoint then pose(m.JawJoint,CFrame.Angles(.6*ease+shake,0,0))end
        pose(m.LeftShoulder,CFrame.Angles(.5*ease,0,-1.0*ease));pose(m.RightShoulder,CFrame.Angles(.5*ease,0,1.0*ease))
        if m.NeckJoint then pose(m.NeckJoint,CFrame.Angles(-.15*ease+shake,0,0))end
    elseif name=='Kick' then
        local a=math.sin(math.clamp(age/.45,0,1)*math.pi)
        pose(m.LeftHip,CFrame.Angles(1.25*a,0,0));pose(m.LeftKnee,CFrame.Angles(-.2*a,0,0))
    elseif name=='Lunge' then
        local a=math.sin(math.clamp(age/.35,0,1)*math.pi*.5)
        for _,side in {'Left','Right'}do
            local sign=side=='Left'and -1 or 1
            pose(m[side..'FlailShoulder'],CFrame.Angles(1.7*a,0,sign*.25));pose(m[side..'FlailElbow'],CFrame.Angles(.2,0,0))
        end
        if m.TorsoJoint then m.TorsoJoint.Transform*=CFrame.Angles(-.35*a,0,0)end
    end
end
-- Collar Crawler is a weeping angel: report the crawlers this player can see (on screen, not blocked by walls).
-- CreatureRoamServer freezes any crawler a living player is looking at.
local SIGHT_RANGE,SIGHT_EVERY=150,.12
local sightEvent;task.spawn(function()sightEvent=game:GetService('ReplicatedStorage'):WaitForChild('MonsterSightEvent')end)
local sightParams=RaycastParams.new();sightParams.FilterType=Enum.RaycastFilterType.Exclude
local sightTimer=0
RunService.Heartbeat:Connect(function(dt)
    sightTimer+=dt;if sightTimer<SIGHT_EVERY or not sightEvent then return end;sightTimer=0
    local lp=game:GetService('Players').LocalPlayer;local cam=Workspace.CurrentCamera
    if not cam or lp:GetAttribute('MissionActive')~=true or lp:GetAttribute('RoundDead')then return end
    local seen={}
    for _,model in folder:GetChildren()do
        if model:IsA('Model')and model:GetAttribute('CreatureKind')=='Crawler'and model.PrimaryPart then
            local cf,size=model:GetBoundingBox()
            for _,pt in {cf.Position,cf.Position+Vector3.new(0,size.Y*.35,0),cf.Position-Vector3.new(0,size.Y*.3,0)}do
                local v,on=cam:WorldToViewportPoint(pt)
                if on and v.Z>0 and v.Z<SIGHT_RANGE then
                    sightParams.FilterDescendantsInstances={lp.Character,model}
                    local hit=Workspace:Raycast(cam.CFrame.Position,pt-cam.CFrame.Position,sightParams)
                    if not hit or hit.Instance.Transparency>=.9 then table.insert(seen,model);break end
                end
            end
        end
    end
    if #seen>0 then sightEvent:FireServer(seen)end
end)
RunService.PreSimulation:Connect(function(dt)
    dt=math.min(dt,.1)
    local now=os.clock()
    for model,rig in pairs(rigs) do
        if not model.Parent then rigs[model]=nil;continue end
        if model:GetAttribute('Watched')==true then continue end -- weeping-angel crawler: holds its last pose while seen
        local m=rig.motors
        local walking=model:GetAttribute('Walking')==true
        local chasing=walking and model:GetAttribute('AIState')=='Chase'
        rig.frenzy+=((chasing and 1 or 0)-rig.frenzy)*(1-math.exp(-dt*12))
        local frenzy=rig.frenzy
        local scale=model:GetAttribute('VisualScaleMultiplier')or 1
        local jitter=now+rig.seed
        local twitch=math.sin(jitter*27)*math.sin(jitter*13.3)
        model:SetAttribute('ChaseFrenzyBlend',frenzy)
        local desired=walking and 1 or 0
        rig.speed+=(desired-rig.speed)*math.min(1,dt*4)
        rig.phase+=dt*(walking and math.clamp((model:GetAttribute('MoveSpeed') or 14)*.24,3.1,6.5) or .55)
        rig.shards=rig.shards or model:FindFirstChild('CorruptionShards',true)
        rig.wisps=rig.wisps or model:FindFirstChild('CorruptionWisps',true)
        rig.veil=rig.veil or model:FindFirstChild('CorruptionVeil',true)
        rig.whiteMist=rig.whiteMist or model:FindFirstChild('WhiteMist',true)
        rig.whiteSparks=rig.whiteSparks or model:FindFirstChild('WhiteSparks',true)
        local root=model:FindFirstChild('CreatureRoot')
                if root and m.TorsoJoint then
            rig.baseTorsoC0=rig.baseTorsoC0 or m.TorsoJoint.C0
            local target=root.CFrame
            -- The anchored root arrives in replication steps (~20-30 Hz). Buffer the steps with arrival times and draw the body slightly in the past,
            -- sliding at constant speed between two real positions instead of surging toward each new step.
            if rig.sampleRoot~=root then
                rig.sampleRoot=root;rig.samples={{t=os.clock(),cf=target}};rig.interval=.05
                if rig.sampleConn then rig.sampleConn:Disconnect() end
                rig.sampleConn=root:GetPropertyChangedSignal('CFrame'):Connect(function()
                    local samples,cf,t=rig.samples,root.CFrame,os.clock();local last=samples[#samples]
                    if last and (cf.Position-last.cf.Position).Magnitude>12 then table.clear(samples);last=nil end
                    if last and t>last.t then rig.interval=rig.interval*.8+math.min(t-last.t,.12)*.2 end
                    table.insert(samples,{t=t,cf=cf});if #samples>8 then table.remove(samples,1) end
                end)
            end
            local samples=rig.samples;local renderAt=os.clock()-math.clamp(rig.interval*1.5,.04,.12);local want=samples[#samples] and samples[#samples].cf or target
            if #samples>=2 and renderAt<samples[#samples].t then
                want=samples[1].cf
                for i=#samples,2,-1 do local a,b=samples[i-1],samples[i];if renderAt>=a.t then want=a.cf:Lerp(b.cf,math.clamp((renderAt-a.t)/math.max(b.t-a.t,1e-3),0,1));break end end
            end
            -- safety: if no replicated step arrived for a while but the root has moved on, follow the root itself
            local newest=samples[#samples];if not newest or (os.clock()-newest.t>.2 and (newest.cf.Position-target.Position).Magnitude>.01) then want=target end
            if not rig.visualRoot or (rig.visualRoot.Position-target.Position).Magnitude>12 then rig.visualRoot=target
            else rig.visualRoot=rig.visualRoot:Lerp(want,1-math.exp(-dt*40)) end
            m.TorsoJoint.C0=target:ToObjectSpace(rig.visualRoot)*rig.baseTorsoC0
        end
        local camera=Workspace.CurrentCamera

        local distance=(root and camera) and (root.Position-camera.CFrame.Position).Magnitude or math.huge
        local density=distance<75 and 1 or (distance<130 and .4 or 0)
        if rig.whiteMist then rig.whiteMist.Rate=(walking and 16 or 10)*density end
        if rig.whiteSparks then rig.whiteSparks.Rate=(walking and 7 or 4)*density end
        if rig.wisps then rig.wisps.Rate=(walking and 30 or 20)*density end
        if rig.veil then rig.veil.Rate=(walking and 13 or 9)*density end
        if rig.shards and now>=rig.nextGlitch and density>0 then
            rig.shards:Emit(math.floor((walking and 10 or 6)*density))
            rig.nextGlitch=now+.46+math.abs(math.sin(now*2.07+rig.seed))*.73
        end
        if rig.kind=='Bellhop' then
            if root then animateBellhop(model,rig,m,dt,now,frenzy,walking,root,distance) end
            attackPose(model,m)
            continue
        elseif rig.kind=='Lantern' or rig.kind=='Neon' then
            if root then animateLantern(model,rig,m,dt,now,frenzy,walking,root,distance) end
            attackPose(model,m)
            continue
        elseif rig.kind=='Mittens' or rig.kind=='Dancer' or rig.kind=='Yoyo' then
            if root then animateToy(model,rig,m,dt,now,frenzy,walking,root,distance) end
            continue
        end
        if now>=rig.nextLook then
            rig.targetYaw=math.sin(now*.91+rig.seed)*.32+math.sin(now*1.73+rig.seed)*.13
            rig.targetPitch=math.sin(now*.65+rig.seed*2)*.16
            rig.nextLook=now+1.2+math.abs(math.sin(now+rig.seed))*2.5
        end
        rig.lookYaw+=(rig.targetYaw-rig.lookYaw)*math.min(1,dt*2.2)
        rig.lookPitch+=(rig.targetPitch-rig.lookPitch)*math.min(1,dt*2.2)
        local phase=rig.phase+rig.seed
        local creep=rig.speed
        local wobble=math.sin(phase*2)*.018+math.sin(phase*.38)*.014
        pose(m.TorsoJoint,CFrame.new(math.sin(jitter*19)*.055*scale*frenzy,(math.abs(math.sin(phase))*creep*.08+wobble+math.abs(math.sin(jitter*17))*.10*frenzy)*scale,0)*CFrame.Angles(.055+math.sin(phase*.58)*.025+.22*frenzy+twitch*.15*frenzy,math.sin(phase*.36)*.04+math.sin(jitter*16)*.14*frenzy,math.sin(phase)*creep*.025+math.sin(jitter*21)*.19*frenzy))
        for i,entry in ipairs(rig.legs) do
            local wave=phase+(i%2==0 and math.pi or 0)+(i-1)*.27
            local swing=math.sin(wave)*.27*creep
            local lift=math.max(0,math.cos(wave))*.15*creep
            pose(entry.motor,CFrame.new(0,lift,0)*CFrame.Angles(swing,math.sin(wave*.5)*.035*creep,math.sin(wave+.7)*.06*creep))
        end
        local gaze=CFrame.Angles(rig.lookPitch,rig.lookYaw,math.sin(now*.7+rig.seed)*.035)
        pose(m.NeckJoint,gaze*CFrame.Angles(math.sin(phase*.7)*.035,0,0))
        pose(m.HeadJoint,gaze*CFrame.Angles(math.sin(jitter*23)*.32*frenzy,math.sin(jitter*17.1)*.42*frenzy,twitch*.38*frenzy))
        pose(m.NeckJoint,gaze*CFrame.Angles(math.sin(phase*.7)*.035+math.sin(jitter*20)*.20*frenzy,math.sin(jitter*14)*.18*frenzy,math.sin(jitter*25)*.23*frenzy))
        for _,side in ipairs({'Left','Right'}) do
            local sign=side=='Left' and -1 or 1
            pose(m[side..'StalkJoint'],CFrame.Angles(rig.lookPitch*.6+math.sin(phase*1.1+sign)*.055,
                rig.lookYaw*.65+math.sin(now*1.4+rig.seed+sign)*.045,
                math.sin(phase*.82+sign)*.05))
            pose(m[side..'CupJoint'],CFrame.Angles(rig.lookPitch*.25,rig.lookYaw*.35,0))
            pose(m[side..'EyeJoint'],CFrame.Angles(rig.lookPitch*.38,rig.lookYaw*.42,
                math.sin(now*1.9+rig.seed+sign)*.018))
        end
        for _,side in {'Left','Right'}do
            local sign=side=='Left'and -1 or 1
            local armPhase=jitter*17+sign*1.8
            local flap=math.sin(armPhase)
            local windmill=math.sin(jitter*11.7+sign*.9)
            pose(m[side..'FlailShoulder'],CFrame.Angles(
                math.sin(phase+sign)*.14*creep+(flap*1.55-.65)*frenzy,
                math.sin(armPhase*.73)*.6*frenzy,
                sign*.12+sign*(.65+windmill*1.1)*frenzy))
            pose(m[side..'FlailElbow'],CFrame.Angles((.30+math.abs(math.sin(armPhase*1.3))*2.0)*frenzy,math.sin(armPhase*1.1)*.35*frenzy,sign*math.sin(armPhase*.81)*.45*frenzy))
            pose(m[side..'FlailWrist'],CFrame.Angles(math.sin(armPhase*1.9)*.8*frenzy,math.cos(armPhase*1.4)*.5*frenzy,math.sin(armPhase*1.7)*.8*frenzy))
            local stalk=m[side..'StalkJoint']
            if stalk then stalk.Transform*=CFrame.Angles(math.sin(jitter*22+sign)*.25*frenzy,math.sin(jitter*19+sign*2)*.3*frenzy,math.sin(jitter*28+sign)*.24*frenzy)end
        end
        pose(m.CollarsJoint,CFrame.Angles(math.sin(phase*.9)*.01,0,0))
        pose(m.TearJoint,CFrame.new(0,math.sin(phase*.5)*.008,0))
        attackPose(model,m)
    end
end)

