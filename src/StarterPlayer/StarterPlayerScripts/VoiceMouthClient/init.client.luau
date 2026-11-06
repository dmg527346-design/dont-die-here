local Selected=require(game.ReplicatedStorage:WaitForChild('SelectedItemCharacterEffects'))
-- Independent Studio draft leases reuse the existing renderer without owning normal curse state.
local itemDraftStudio = game:GetService('RunService'):IsStudio()
local function draftLease(q, key)
 local original = q:GetAttribute(key) or 0
 return math.max(original, itemDraftStudio and (q:GetAttribute('Draft' .. key) or 0) or 0)
end
local Preferences=require(game.ReplicatedStorage:WaitForChild('HorrorPreferences'))
-- Voice-reactive lips and local pooled spit. Reads only the local player's voice amplitude.
local Players=game:GetService('Players')
local RS=game:GetService('ReplicatedStorage')
local RunService=game:GetService('RunService')
local player=Players.LocalPlayer
local event=RS:WaitForChild('VoiceMouthLevel')
local SEND_INTERVAL=1/12
local STALE_SECONDS=.65
local SPIT_AFTER_SECONDS=1.05
local SPIT_MIN_LEVEL=.21
local SPIT_BASE_INTERVAL=.85
local SPIT_LOUD_INTERVAL_REDUCTION=.18
local SPIT_LOUD_FORCE_LEVEL=.8
local SILENCE_RESET_SECONDS=.65
local MAX_SPIT_PARTS=48
local MAX_RENDER_DISTANCE=120
-- Smile uses only the same existing mesh size and Motor6D transforms as speech.
local SMILE_WIDTH = 1.95
local SMILE_HEIGHT = .72
local SMILE_LIFT = .10
local SMILE_TILT = math.rad(0)
local SMILE_IN_SPEED = 6
-- The van radio (GearShopServer): anyone standing right next to it smiles (owner 2026-10-26).
local RADIO_SMILE_RANGE = 6
local radioPart,radioLook=nil,0
local function radioPosition()
 if os.clock()-radioLook>1 or (radioPart and not radioPart.Parent) then
  radioLook=os.clock();local camp=workspace:FindFirstChild('RecoveryCamp');local r=camp and camp:FindFirstChild('VanRadio',true);radioPart=r and r.PrimaryPart or nil
 end
 return radioPart and radioPart.Position
end
local SMILE_OUT_SPEED = 22
local SPEECH_SMILE_HOLD = .22
local LipCurve=require(script:WaitForChild('DiscoLipCurve'))
-- Selected-only assembly transform. Native speech/curse poses are evaluated first
-- on every frame, so the normal owner's sizes and missing-tooth visibility restore
-- without caching an already-deformed frame or resetting normal curse state.
local function selectedJointFrame(joint)
    return joint.Part0.CFrame*joint.C0*joint.Transform*joint.C1:Inverse()
end
local function selectedSetJointFrame(joint,worldFrame)
    joint.Transform=joint.C0:Inverse()*joint.Part0.CFrame:ToObjectSpace(worldFrame)*joint.C1
end
local function selectedScalePiece(part,joint,sourceFrame,targetFrame,scale,extra)
    local relative=sourceFrame:ToObjectSpace(selectedJointFrame(joint))
    local center=Selected.Mul(relative.Position+(extra or Vector3.zero),scale)
    -- Bone rotations remain intact. Scale each local dimension along its evaluated
    -- axis, including the normal jawbreaker's already-rotated/chipped teeth.
    local dimensions=Vector3.new(Selected.Mul(relative.XVector,scale).Magnitude,
        Selected.Mul(relative.YVector,scale).Magnitude,Selected.Mul(relative.ZVector,scale).Magnitude)
    part.Size=Selected.Mul(part.Size,dimensions)
    local scaledRelative=CFrame.new(center)*relative.Rotation
    selectedSetJointFrame(joint,targetFrame*scaledRelative)
    return scaledRelative
end
local function selectedToothEnclosed(relative,size,lipSize)
    -- The visible lip ellipse is a conservative shell bound. Closed/puckered
    -- mouths must cover a tooth completely; a tooth outside it becomes hidden.
    -- Existing smile, sad, kiss and missing-tooth transparency can only increase.
    local rx,ry=lipSize.X*.49,lipSize.Y*.49
    if rx<.025 or ry<.025 then return false end
    local half=size*.5
    local maxEllipse=0
    for _,x in {-1,1}do for _,y in {-1,1}do for _,z in {-1,1}do
        local p=relative:PointToWorldSpace(Vector3.new(x*half.X,y*half.Y,z*half.Z))
        maxEllipse=math.max(maxEllipse,(p.X/rx)^2+(p.Y/ry)^2)
        if maxEllipse>1 or math.abs(p.Z)>lipSize.Z*.8+.01 then return false end
    end end end
    return true
end
local function applySelectedMouthAssembly(rig,descriptor)
    local v=descriptor.mouth
    local sourceFrame=selectedJointFrame(rig.mouthJoint)
    local targetFrame=sourceFrame*CFrame.new(v.offset)*CFrame.Angles(v.angles.X,v.angles.Y,v.angles.Z)
    -- FaceBridge is the structural green head cap supporting the eye anchors.
    -- Its native voice-owner size/pose above must remain independent of the lips.
    for _,piece in {{rig.mouth,rig.mouthJoint},{rig.inside,rig.insideJoint},
        {rig.throat,rig.throatJoint},{rig.depth,rig.depthJoint},{rig.back,rig.backJoint}}do
        selectedScalePiece(piece[1],piece[2],sourceFrame,targetFrame,v.scale)
    end
    local hidden=0
    for _,tooth in rig.teeth do
        local chatter=Vector3.new(0,(tooth.row or 1)*v.teethChatter,0)
        local relative=selectedScalePiece(tooth.part,tooth.joint,sourceFrame,targetFrame,v.scale,chatter)
        if not selectedToothEnclosed(relative,tooth.part.Size,rig.mouth.Size)then
            tooth.part.Transparency=1;hidden+=1
        end
    end
    rig.character:SetAttribute('SelectedMouthHiddenTeeth',hidden)
end

local rigs={}
-- Resources parented outside the character need the same lifetime as their rig.
local function removeRig(p,expected)
    local rig=expected or rigs[p]
    if not rig then return end
    if rigs[p]==rig then rigs[p]=nil end
    if rig.retired then return end
    rig.retired=true
    if rig.destroyConnection then rig.destroyConnection:Disconnect();rig.destroyConnection=nil end
    if rig.gumBubble then rig.gumBubble:Destroy();rig.gumBubble=nil end
    if rig.lipCurve then rig.lipCurve:Destroy();rig.lipCurve=nil end
end

local input,analyzer,wire,hissFilter,hissAnalyzer,hissInputWire,hissOutputWire
local lastSent,lastLevel,lastEmphasis,sequence=0,0,0,0
local previewLevel,previewEmphasis,previewUntil=0,0,0
local previousLevel,plosiveUntil=0,0
local function connectInput(device)
    if input==device then return end
    if wire then wire:Destroy() end
    if hissInputWire then hissInputWire:Destroy() end
    if hissOutputWire then hissOutputWire:Destroy() end
    if analyzer then analyzer:Destroy() end
    if hissAnalyzer then hissAnalyzer:Destroy() end
    if hissFilter then hissFilter:Destroy() end
    input=device;analyzer=nil;wire=nil;hissFilter=nil;hissAnalyzer=nil;hissInputWire=nil;hissOutputWire=nil
    if not device then return end
    analyzer=Instance.new('AudioAnalyzer');analyzer.Name='VoiceMouthAnalyzer';analyzer.SpectrumEnabled=false;analyzer.Parent=script
    wire=Instance.new('Wire');wire.Name='MicrophoneAmplitudeOnly';wire.SourceInstance=device;wire.TargetInstance=analyzer;wire.Parent=analyzer
    -- GetSpectrum is unavailable for microphone input; a filtered RMS channel estimates hiss instead.
    hissFilter=Instance.new('AudioFilter');hissFilter.Name='SibilanceHighpass';hissFilter.FilterType=Enum.AudioFilterType.Highpass24dB
    hissFilter.Frequency=2600;hissFilter.Q=.707;hissFilter.Parent=script
    hissAnalyzer=Instance.new('AudioAnalyzer');hissAnalyzer.Name='SibilanceAnalyzer';hissAnalyzer.SpectrumEnabled=false;hissAnalyzer.Parent=script
    hissInputWire=Instance.new('Wire');hissInputWire.Name='MicrophoneToHighpass';hissInputWire.SourceInstance=device;hissInputWire.TargetInstance=hissFilter;hissInputWire.Parent=hissFilter
    hissOutputWire=Instance.new('Wire');hissOutputWire.Name='HighpassToAnalyzer';hissOutputWire.SourceInstance=hissFilter;hissOutputWire.TargetInstance=hissAnalyzer;hissOutputWire.Parent=hissAnalyzer
end
player.ChildAdded:Connect(function(child) if child:IsA('AudioDeviceInput') then connectInput(child) end end)
player.ChildRemoved:Connect(function(child) if child==input then connectInput(nil) end end)
connectInput(player:FindFirstChildOfClass('AudioDeviceInput'))
local function addCharacter(p,character)
 local function silence(x)
  if x:IsA('Sound') and x.Name=='Running' then x.Volume=0;x.SoundId=''
   x:GetPropertyChangedSignal('SoundId'):Connect(function()if x.SoundId~='' then x.SoundId='' end end)
  end
 end
 for _,x in ipairs(character:GetDescendants()) do silence(x) end;character.DescendantAdded:Connect(silence)
    removeRig(p)
    if not character:GetAttribute('CustomCharacterVersion') then return end
    local head=character:WaitForChild('Head',10)
    if not head then return end
    local mouth=head:WaitForChild('ConnectedLips',10);local inside=head:WaitForChild('MouthInterior',10);local bridge=head:WaitForChild('FaceBridge',10)
    if not mouth or not inside or not bridge or p.Character~=character then return end
    local throat=head:WaitForChild('MouthThroat',10)
    local depth=head:WaitForChild('ThroatDepth',10)
    local back=head:WaitForChild('MouthBack',10)
    if not throat or not depth or not back then return end
    local teeth={}
    for _,row in {'Upper','Lower'} do
        for i=1,7 do
            local tooth=head:WaitForChild(row..'Tooth'..i,10)
            if not tooth then return end
            table.insert(teeth,{part=tooth,size=tooth.Size,joint=tooth:WaitForChild('VoiceMouthJoint'),row=tooth:GetAttribute('ToothRow'),x=tooth:GetAttribute('ToothX'),transparency=tooth.Transparency})
        end
    end
    rigs[p]={character=character,head=head,mouth=mouth,inside=inside,bridge=bridge,throat=throat,depth=depth,back=back,teeth=teeth,
        mouthSize=mouth.Size,insideSize=inside.Size,bridgeSize=bridge.Size,
        throatSize=throat.Size,depthSize=depth.Size,backSize=back.Size,
        mouthJoint=mouth:WaitForChild('VoiceLipJoint'),insideJoint=inside:WaitForChild('VoiceLipJoint'),bridgeJoint=bridge:WaitForChild('FaceBridgeJoint'),
        throatJoint=throat:WaitForChild('VoiceMouthJoint'),depthJoint=depth:WaitForChild('VoiceMouthJoint'),backJoint=back:WaitForChild('VoiceMouthJoint'),
        -- The template's lip joints now rest on the modelled face (C0); this script's poses were written for the old C0
        -- (attribute DriverC0), so each frame they are re-expressed against the new one (lipFix below). Same look as before.
        mouthFix=(function()local j=mouth:FindFirstChild('VoiceLipJoint');local d=j and j:GetAttribute('DriverC0');return typeof(d)=='CFrame'and j.C0:Inverse()*d or CFrame.identity end)(),
        insideFix=(function()local j=inside:FindFirstChild('VoiceLipJoint');local d=j and j:GetAttribute('DriverC0');return typeof(d)=='CFrame'and j.C0:Inverse()*d or CFrame.identity end)(),
        kiss=0,smile=0,sad=0,lastSpeech=-math.huge,
        target=0,emphasis=0,prevEmphasis=0,envelope=0,updated=0,talk=0,quiet=0,lastSpit=0,lastAccent=0,lastStamp=0}
    local rig=rigs[p]
    task.spawn(function()
        local ok,curve=pcall(LipCurve.Create,mouth)
        if not ok then mouth:SetAttribute('DiscoLipCurveError',tostring(curve));return end
        if rigs[p]~=rig or not mouth.Parent then curve:Destroy();return end
        rig.lipCurve=curve
        mouth:SetAttribute('DiscoLipCurveReady',true)
    end)
    rig.destroyConnection=character.Destroying:Once(function()removeRig(p,rig)end)
end
local function join(p)
    p.CharacterAdded:Connect(function(c) task.spawn(addCharacter,p,c) end)
    p.CharacterRemoving:Connect(function(c) if rigs[p] and rigs[p].character==c then removeRig(p,rigs[p]) end end)
    if p.Character then task.spawn(addCharacter,p,p.Character) end
end
Players.PlayerAdded:Connect(join)
Players.PlayerRemoving:Connect(function(p) removeRig(p) end)
for _,p in Players:GetPlayers() do join(p) end
task.spawn(function()
    require(game.ReplicatedStorage:WaitForChild('CharacterEntityAdapter')).Watch(addCharacter,function(p)removeRig(p)end)
end)
event.OnClientEvent:Connect(function(p,level,stamp,emphasis)
    if p==player then return end
    local rig=rigs[p]
    if not rig or stamp<rig.lastStamp then return end
    rig.lastStamp=stamp;rig.target=level;rig.emphasis=emphasis or 0;rig.updated=os.clock()
end)
local drops={};local poolIndex=0
local folder=Instance.new('Folder');folder.Name='VoiceSpitCosmetics';folder.Parent=workspace
local rng=Random.new()
local Audio=require(game.ReplicatedStorage:WaitForChild('GameplayAudio'))
local function spit(rig,level,now,emphasis)
    if not Preferences.Get('SpitEffects')then return end
    local root=rig.character:FindFirstChild('HumanoidRootPart')
    if not root then return end
    if now-(rig.lastSpitSound or 0)>.8 then rig.lastSpitSound=now;Audio.Play('Spit',root)end
    local count=emphasis>.4 and (3+math.floor(emphasis*3)+math.floor(level*2)) or (level>=SPIT_LOUD_FORCE_LEVEL and 2+math.floor(level*2) or 1+math.floor(level*2))
    for i=1,count do
        poolIndex=poolIndex%MAX_SPIT_PARTS+1
        local drop=drops[poolIndex]
        if not drop then
            local part=Instance.new('Part');part.Name='Spit';part.Shape=Enum.PartType.Ball;part.Material=Enum.Material.SmoothPlastic
            part.Color=Color3.fromRGB(221,237,235);part.Reflectance=.22;part.Anchored=true;part.CanCollide=false;part.CanQuery=false;part.CanTouch=false;part.CastShadow=false
            part.Parent=folder;drop={part=part};drops[poolIndex]=drop
        end
        local size=rng:NextNumber(.025,.075)*(1+level*.35)
        drop.part.Size=Vector3.new(size,size*.8,size*rng:NextNumber(1.6,3.8))
        drop.origin=rig.inside.Position+root.CFrame.LookVector*.35+root.CFrame.RightVector*rng:NextNumber(-.18,.18)
        drop.velocity=root.CFrame.LookVector*rng:NextNumber(13+level*8,20+level*14)+root.CFrame.RightVector*rng:NextNumber(-3.5,3.5)+Vector3.new(0,rng:NextNumber(-1,4),0)+root.AssemblyLinearVelocity*.65
        drop.born=now;drop.life=rng:NextNumber(.28,.55);drop.part.Transparency=.25
        drop.part.CFrame=CFrame.lookAt(drop.origin,drop.origin+drop.velocity)
    end
end
-- Explicit Studio-only visual test hook. It does not unmute or send fake voice packets.
if RunService:IsStudio() then
    local preview=Instance.new('BindableEvent');preview.Name='PreviewVoice';preview.Parent=script
    preview.Event:Connect(function(level,duration,emphasis)
        if type(level)=='number' and level==level and type(duration)=='number' and duration==duration then
            previewLevel=math.clamp(level,0,1);previewEmphasis=type(emphasis)=='number' and emphasis==emphasis and math.clamp(emphasis,0,1) or 0
            previewUntil=os.clock()+math.clamp(duration,0,15)
        end
    end)
end
local function microphoneFeatures(now)
    if not input or not input.Parent or input.Muted or not analyzer then previousLevel=0;return 0,0 end
    local amplitude=math.max(analyzer.RmsLevel,analyzer.PeakLevel*.35)
    local level=amplitude<.005 and 0 or math.clamp((20*math.log10(amplitude)+42)/30,0,1)
    local hiss=0
    if hissAnalyzer and analyzer.RmsLevel>.004 then
        local ratio=hissAnalyzer.RmsLevel/math.max(analyzer.RmsLevel,.004)
        hiss=math.clamp((ratio-.28)/.42,0,1)
        if hiss>.4 then level=math.max(level,.14) end
    end
    -- Repeated P sounds create short, sharp amplitude onsets. This is an acoustic
    -- approximation; the microphone API does not expose exact phoneme labels.
    if level>.15 and level-previousLevel>.14 then plosiveUntil=now+.22 end
    previousLevel=level
    return level,math.max(hiss,now<plosiveUntil and .85 or 0)
end
RunService.PreSimulation:Connect(function(dt)
    dt=math.min(dt,.1)
    local now=os.clock();local ownLevel,ownEmphasis=microphoneFeatures(now)
    if now-lastSent>=SEND_INTERVAL and (math.abs(ownLevel-lastLevel)>.015 or math.abs(ownEmphasis-lastEmphasis)>.08 or ownLevel>0 and now-lastSent>.25) then
        lastSent=now;lastLevel=ownLevel;lastEmphasis=ownEmphasis;sequence+=1;event:FireServer(ownLevel,sequence,ownEmphasis)
    end
    local localRig=rigs[player]
    if localRig then
        localRig.target=now<previewUntil and previewLevel or ownLevel
        localRig.emphasis=now<previewUntil and previewEmphasis or ownEmphasis
        localRig.updated=now
    end
    local camera=workspace.CurrentCamera
    for p,rig in rigs do
        if not rig.head.Parent then removeRig(p,rig);continue end
        local target=now-rig.updated<STALE_SECONDS and rig.target or 0
        local emphasis=now-rig.updated<STALE_SECONDS and rig.emphasis or 0
        -- Ventriloquist doll: the holder's own voice drives the doll's mouth; everyone else's voice drives the holder's mouth.
        local dollHeld=workspace:GetServerTimeNow()<(p:GetAttribute('DollUntil')or 0)
        if dollHeld then
            rig.dollLevel=target
            local others=0
            for q,other in rigs do if q~=p and now-other.updated<STALE_SECONDS then others=math.max(others,other.target or 0)end end
            target=others;emphasis=0
        end
        local healthy=rig.character:FindFirstChildOfClass('Humanoid')
        if not healthy or healthy.Health<=0 then target=0;emphasis=0 end
        local speed=target>rig.envelope and 22 or 12
        rig.envelope+=(target-rig.envelope)*(1-math.exp(-dt*speed))
        local level=rig.envelope
        if target>.06 or emphasis>.15 then rig.lastSpeech=now end
        local holdingDisco=p:GetAttribute('CursedActive')=='DiscoBall' and healthy and healthy.Health>0
        local speaking=target>.06 or level>.045 or now-rig.lastSpeech<SPEECH_SMILE_HOLD
        local crying=healthy and healthy.Health>0 and workspace:GetServerTimeNow()<(draftLease(p,'CryingUntil'))
        -- Funny face beats (close-up choices ExtraChoices2, van gear GearShopServer): 'grin' | 'gasp' | 'pucker' for a moment.
        local faceBeat=healthy and healthy.Health>0 and workspace:GetServerTimeNow()<(p:GetAttribute('FaceBeatUntil')or 0) and p:GetAttribute('FaceBeat') or nil
        local fear=healthy and healthy.Health>0 and (workspace:GetServerTimeNow()<(p:GetAttribute('MirrorFearUntil')or 0) or (type(p)=='table' and p.IsEntity) and rig.character:GetAttribute('EntityState')=='Freakout')
        if faceBeat=='gasp' or faceBeat=='frown' then fear=true end -- 'frown': ItemBatch6/7 sulk -- wide open, trembling: the shocked face
        local sadTarget=(crying or fear) and not speaking and 1 or 0
        rig.sad+=(sadTarget-rig.sad)*(1-math.exp(-dt*6))
        local radioAt=radioPosition()
        local byRadio=radioAt~=nil and healthy and healthy.Health>0 and (rig.head.Position-radioAt).Magnitude<RADIO_SMILE_RANGE
        if (rig.character:GetAttribute('RadioSmile')==true)~=(byRadio==true) then rig.character:SetAttribute('RadioSmile',byRadio or nil) end -- local mark only (tests)
        local grinning=healthy and healthy.Health>0 and workspace:GetServerTimeNow()<(p:GetAttribute('GrinUntil')or 0) -- world features (WorldA): a short proud grin
        local smileTarget=(holdingDisco or byRadio or grinning or faceBeat=='grin' or faceBeat=='laugh') and not crying and not speaking and 1 or 0
        local smileSpeed=smileTarget>rig.smile and SMILE_IN_SPEED or SMILE_OUT_SPEED
        rig.smile+=(smileTarget-rig.smile)*(1-math.exp(-dt*smileSpeed))
        if rig.smile<.0001 then rig.smile=0 end

        if target>.08 then rig.talk+=dt;rig.quiet=0 else rig.quiet+=dt;if rig.quiet>SILENCE_RESET_SECONDS then rig.talk=0 end end
        local near=not camera or (rig.head.Position-camera.CFrame.Position).Magnitude<MAX_RENDER_DISTANCE
        local myHead=nil
        if p==player and p.Character then myHead=p.Character:FindFirstChild('Head') end
        local firstPerson=myHead~=nil and camera~=nil and(camera.CFrame.Position-myHead.Position).Magnitude<2.5
        local phase=now*(14+level*10)+p.UserId%13
        local chatter=.58+.42*math.abs(math.sin(phase)*math.cos(phase*.61))
        local opening=level*(.22+level*1.5)*chatter
        if fear then opening=math.max(opening,.28+math.abs(math.sin(now*23))*.05)end
        local wild=level*level
        local width=1+wild*.9+level*.10*math.sin(phase*.73)
        local wobble=math.sin(phase*.47)*wild*.16
        rig.mouth.Size=Vector3.new(rig.mouthSize.X*width,.55+opening*.95,rig.mouthSize.Z*(1+wild*.25))
        rig.inside.Size=Vector3.new(rig.insideSize.X*width,.30+opening*.8,rig.insideSize.Z)
        local mouthPose=CFrame.new(wobble*.1,-opening*.10,.50+level*.30)*CFrame.Angles(0,0,wobble*.7)
        rig.mouthJoint.Transform=mouthPose
        rig.insideJoint.Transform=mouthPose*CFrame.new(0,0,-.11)
        rig.bridge.Size=Vector3.new(rig.bridgeSize.X*(1+wild*.1),rig.bridgeSize.Y+opening*.20,rig.bridgeSize.Z+level*.35)
        rig.bridgeJoint.Transform=CFrame.new(0,-opening*.08,level*.16)
        local mouthMotion=CFrame.new(wobble*.1,-opening*.10,level*.30)*CFrame.Angles(0,0,wobble*.7)
        rig.throat.Size=Vector3.new(rig.throatSize.X*width,rig.throatSize.Y+opening*.65,rig.throatSize.Z+level*.10)
        rig.depth.Size=Vector3.new(rig.depthSize.X*width,rig.depthSize.Y+opening*.28,rig.depthSize.Z)
        rig.throatJoint.Transform=mouthMotion
        rig.depthJoint.Transform=mouthMotion
        rig.back.Size=Vector3.new(rig.backSize.X*width,rig.backSize.Y+opening*.80,rig.backSize.Z+level*.18)
        rig.backJoint.Transform=CFrame.new(wobble*.1,-opening*.10,level*.30)
        for _,tooth in rig.teeth do
            tooth.joint.Transform=mouthMotion*CFrame.new(tooth.x*(width-1),tooth.row*opening*.34,0)
            tooth.part.Size=Vector3.new(tooth.size.X*(1+wild*.3),tooth.size.Y*(1+opening*.1),tooth.size.Z)
        end
        -- Blend from the fully evaluated voice pose: speech and spit retain their existing owner.
        local smile=rig.smile
        if rig.lipCurve then rig.lipCurve:Update(smile,rig.sad,p:GetAttribute('DraftSelectedItem')=='BackwardsHairdryer'and workspace:GetServerTimeNow()<(p:GetAttribute('DraftSelectedUntil')or 0)and 1 or 0) end
        local smilePose=CFrame.new(0,SMILE_LIFT,.62)*CFrame.Angles(SMILE_TILT,0,0)
        rig.mouth.Size=rig.mouth.Size:Lerp(Vector3.new(rig.mouthSize.X*SMILE_WIDTH,SMILE_HEIGHT,rig.mouthSize.Z),smile)
        rig.inside.Size=rig.inside.Size:Lerp(Vector3.new(rig.insideSize.X*SMILE_WIDTH,.54,rig.insideSize.Z),smile)
        rig.mouthJoint.Transform=rig.mouthJoint.Transform:Lerp(smilePose,smile)
        rig.insideJoint.Transform=rig.insideJoint.Transform:Lerp(smilePose*CFrame.new(0,0,-.11),smile)
        rig.bridge.Size=rig.bridge.Size:Lerp(Vector3.new(rig.bridgeSize.X*1.75,rig.bridgeSize.Y,rig.bridgeSize.Z),smile)
        rig.bridgeJoint.Transform=rig.bridgeJoint.Transform:Lerp(CFrame.new(0,SMILE_LIFT*.35,.015),smile)
        rig.throat.Size=rig.throat.Size:Lerp(Vector3.new(rig.throatSize.X*SMILE_WIDTH,.57,rig.throatSize.Z),smile)
        rig.depth.Size=rig.depth.Size:Lerp(Vector3.new(rig.depthSize.X*SMILE_WIDTH,.40,rig.depthSize.Z),smile)
        local smileMotion=CFrame.new(0,SMILE_LIFT,.02)*CFrame.Angles(SMILE_TILT,0,0)
        rig.throatJoint.Transform=rig.throatJoint.Transform:Lerp(smileMotion,smile)
        rig.depthJoint.Transform=rig.depthJoint.Transform:Lerp(smileMotion,smile)
        rig.back.Size=rig.back.Size:Lerp(Vector3.new(rig.backSize.X*SMILE_WIDTH,rig.backSize.Y,rig.backSize.Z),smile)
        rig.backJoint.Transform=rig.backJoint.Transform:Lerp(CFrame.new(0,SMILE_LIFT,.02),smile)
        for _,tooth in rig.teeth do
            tooth.part.Transparency=tooth.transparency+(1-tooth.transparency)*smile
        end
        local sad=rig.sad
        rig.mouth.Size=rig.mouth.Size:Lerp(Vector3.new(rig.mouthSize.X*1.05,.48,rig.mouthSize.Z),sad)
        rig.inside.Size=rig.inside.Size:Lerp(Vector3.new(rig.insideSize.X,.18,rig.insideSize.Z),sad)
        rig.mouthJoint.Transform=rig.mouthJoint.Transform:Lerp(CFrame.new(0,-.05,.58),sad)
        rig.insideJoint.Transform=rig.insideJoint.Transform:Lerp(CFrame.new(0,-.05,.45),sad)
        for _,tooth in rig.teeth do tooth.part.Transparency=math.max(tooth.part.Transparency,sad)end
        rig.character:SetAttribute('CloudSadWeight',sad)
        local vanityPhase=(workspace:GetServerTimeNow()+p.UserId%7*.17)%4.5
        local kissTarget=p:GetAttribute('CursedActive')=='Mirror' and healthy and healthy.Health>0 and not speaking and math.clamp((vanityPhase-.75)/.3,0,1)*math.clamp((2.1-vanityPhase)/.45,0,1) or 0
        local whistle=workspace:GetServerTimeNow()<(draftLease(p,'WhistleUntil'))
        local party=workspace:GetServerTimeNow()<(p:GetAttribute('PartyBlowerUntil')or 0)
        local partyPhase=(workspace:GetServerTimeNow()-(p:GetAttribute('PartyBlowerStart')or 0))%1.65
        if healthy and healthy.Health>0 and not speaking and (whistle or party and partyPhase<.95)then kissTarget=1 end
        -- Makeup kit: lips stay scrunched into a pout for the whole level (server clears MadeUp).
        if healthy and healthy.Health>0 and not speaking and p:GetAttribute('MadeUp')then kissTarget=math.max(kissTarget,.92)end
        -- Sour lemon: the whole mouth puckers hard while it is held (even mid-sentence).
        if healthy and healthy.Health>0 and workspace:GetServerTimeNow()<(draftLease(p,'LemonUntil'))then kissTarget=1 end
        if faceBeat=='pucker' and healthy and healthy.Health>0 and not speaking then kissTarget=1 end
        rig.kiss+=(kissTarget-rig.kiss)*(1-math.exp(-dt*18))
        local kiss=rig.kiss
        rig.mouth.Size=rig.mouth.Size:Lerp(Vector3.new(rig.mouthSize.X*.48,.48,rig.mouthSize.Z*1.5),kiss)
        rig.inside.Size=rig.inside.Size:Lerp(Vector3.new(rig.insideSize.X*.35,.14,rig.insideSize.Z),kiss)
        rig.mouthJoint.Transform=rig.mouthJoint.Transform:Lerp(CFrame.new(0,.03,.94),kiss)
        rig.insideJoint.Transform=rig.insideJoint.Transform:Lerp(CFrame.new(0,.03,.79),kiss)
        for _,tooth in rig.teeth do tooth.part.Transparency=math.max(tooth.part.Transparency,kiss) end
        rig.character:SetAttribute('MirrorKissWeight',kiss)
        rig.character:SetAttribute('MirrorSpeaking',speaking)
        local alive=healthy and healthy.Health>0
        local serverNow=workspace:GetServerTimeNow()
        -- Hot sauce: fire pours from the mouth only while this player is actually talking.
        local breathing=alive and serverNow<(p:GetAttribute('HotSauceUntil')or 0)and(target>.06 or level>.045)
        if breathing and not rig.sauceFire then
            local a=Instance.new('Attachment');a.Name='HotSauceFire'
            rig.sauceDir=Vector3.new(1,0,1)*rig.head.CFrame:VectorToObjectSpace(rig.mouth.Position-rig.head.Position)
            local e=Instance.new('ParticleEmitter');e.Texture='rbxasset://textures/particles/fire_main.dds'
            e.Color=ColorSequence.new({ColorSequenceKeypoint.new(0,Color3.fromRGB(255,245,140)),ColorSequenceKeypoint.new(.4,Color3.fromRGB(255,130,20)),ColorSequenceKeypoint.new(1,Color3.fromRGB(190,25,10))})
            e.Size=NumberSequence.new({NumberSequenceKeypoint.new(0,.3),NumberSequenceKeypoint.new(1,1.6)})
            e.Transparency=NumberSequence.new({NumberSequenceKeypoint.new(0,.1),NumberSequenceKeypoint.new(1,1)})
            e.LightEmission=1;e.Lifetime=NumberRange.new(.35,.5);e.Speed=NumberRange.new(13,18);e.SpreadAngle=Vector2.new(10,10)
            e.EmissionDirection=Enum.NormalId.Front;e.RotSpeed=NumberRange.new(-180,180);e.Rate=0;e.Parent=a
            local l=Instance.new('PointLight');l.Color=Color3.fromRGB(255,140,40);l.Range=12;l.Brightness=0;l.Parent=a
            a.Parent=rig.mouth;rig.sauceFire={attachment=a,emitter=e,light=l}
        end
        if rig.sauceFire then
            local fire=rig.sauceFire
            local dir=rig.sauceDir.Magnitude>.01 and rig.head.CFrame:VectorToWorldSpace(rig.sauceDir.Unit)or rig.head.CFrame.LookVector
            fire.attachment.WorldCFrame=CFrame.lookAt(rig.mouth.Position+dir*.2,rig.mouth.Position+dir*2)
            fire.emitter.Rate=breathing and 70+level*160 or 0
            fire.light.Brightness=breathing and 2.2 or 0
        end
        -- Popsicle: teeth chatter while frozen and not talking.
        if alive and not speaking and serverNow<(draftLease(p,'FrozenUntil'))then
            for i,tooth in rig.teeth do tooth.joint.Transform*=CFrame.new(math.sin(now*47+i)*.012,(tooth.row or 1)*math.abs(math.sin(now*38))*.035,0)end
        end
        local faceDir=rig.head.CFrame:VectorToWorldSpace(Vector3.new(1,0,1)*rig.head.CFrame:VectorToObjectSpace(rig.mouth.Position-rig.head.Position))
        faceDir=faceDir.Magnitude>.01 and faceDir.Unit or rig.head.CFrame.LookVector
        -- Doll mouth flaps with the holder's voice.
        local doll=rig.doll
        if dollHeld and(not doll or not doll.Parent or doll:GetAttribute('HeldBy')~=p.UserId)then
            doll=nil
            local map=workspace:FindFirstChild('Mansion');local items=map and map:FindFirstChild('Interactive')
            if items then for _,m in items:GetChildren()do if m:GetAttribute('ItemId')=='VentriloquistDoll'and m:GetAttribute('HeldBy')==p.UserId then doll=m;break end end end
            rig.doll=doll
        end
        local dollMouth=doll and doll:FindFirstChild('DollMouth')
        if dollMouth then
            local base=dollMouth:GetAttribute('BaseSize')or dollMouth.Size;dollMouth:SetAttribute('BaseSize',base)
            local open=dollHeld and math.clamp((rig.dollLevel or 0)*6,0,1)or 0
            dollMouth.Size=Vector3.new(base.X,base.Y+open*.09,base.Z)
            if not dollHeld then rig.doll=nil end
        end
        -- Bubble gum: chew for 3 s, blow a growing bubble, pop at 5.5 s (server plays the pop).
        local gumAge=serverNow-(p:GetAttribute('GumChewStart')or -100)
        local crunching=alive and serverNow<(p:GetAttribute('CrunchUntil')or 0)
        local chewing=alive and not speaking and(gumAge>=0 and gumAge<3 or crunching)
        if chewing then
            local c=math.abs(math.sin(now*(crunching and 14 or 9)))
            rig.mouth.Size=Vector3.new(rig.mouthSize.X*.8,.5+.35*c,rig.mouthSize.Z)
            for _,tooth in rig.teeth do tooth.joint.Transform*=CFrame.new(0,(tooth.row or 1)*c*.05,0)end
        end
        if alive and gumAge>=3 and gumAge<5.5 then
            local b=rig.gumBubble
            if not b then
                b=Instance.new('Part');b.Name='GumBubble';b.Shape=Enum.PartType.Ball;b.Color=Color3.fromRGB(255,130,190);b.Material=Enum.Material.SmoothPlastic
                b.Transparency=.15;b.Anchored=true;b.CanCollide=false;b.CanQuery=false;b.CanTouch=false;b.CastShadow=false;b.Parent=workspace;rig.gumBubble=b
            end
            local d=.08+1.35*((gumAge-3)/2.5)^.8
            b.Size=Vector3.one*d;b.CFrame=CFrame.new(rig.mouth.Position+faceDir*(d/2+.05))
            rig.mouth.Size=rig.mouth.Size:Lerp(Vector3.new(rig.mouthSize.X*.48,.48,rig.mouthSize.Z*1.5),.9)
        elseif rig.gumBubble then
            local b=rig.gumBubble;rig.gumBubble=nil
            if alive and gumAge>=5.5 and gumAge<6.5 then
                local burst=Instance.new('Attachment');burst.WorldPosition=b.Position;burst.Parent=workspace.Terrain
                local e=Instance.new('ParticleEmitter');e.Color=ColorSequence.new(Color3.fromRGB(255,130,190));e.Size=NumberSequence.new({NumberSequenceKeypoint.new(0,.25),NumberSequenceKeypoint.new(1,0)})
                e.Lifetime=NumberRange.new(.3,.6);e.Speed=NumberRange.new(4,8);e.SpreadAngle=Vector2.new(180,180);e.Rate=0;e.Parent=burst;e:Emit(30)
                task.delay(1,function()burst:Destroy()end)
            end
            b:Destroy()
        end
        -- Jawbreaker: cracked teeth (BrokenTeeth, server-owned) stay broken for the rest of the level.
        local broken=alive and p:GetAttribute('BrokenTeeth')or 0
        if broken>0 then
            for i,tooth in rig.teeth do
                if (i*5+p.UserId)%14<broken then
                    tooth.part.Size*=Vector3.new(.8,.35,1)
                    tooth.joint.Transform*=CFrame.new(0,-(tooth.row or 1)*.03,0)*CFrame.Angles(0,0,i%2==0 and .35 or -.35)
                end
            end
        end

        rig.mouthJoint.Transform=rig.mouthFix*rig.mouthJoint.Transform
        rig.insideJoint.Transform=rig.insideFix*rig.insideJoint.Transform
        local descriptor=healthy and healthy.Health>0 and Selected.Read(p,0)
        local selectedMouth=descriptor and descriptor.mouth
        if selectedMouth then
            applySelectedMouthAssembly(rig,descriptor)
            rig.character:SetAttribute('SelectedMouthRendered',descriptor.id)
        else
            -- The native owner above has rebuilt all sizes, joints and tooth
            -- transparency for this frame, including missing/broken teeth.
            rig.character:SetAttribute('SelectedMouthRendered',nil)
            rig.character:SetAttribute('SelectedMouthHiddenTeeth',nil)
        end
        local forced=target>=SPIT_LOUD_FORCE_LEVEL

        local accent=emphasis>.4 and target>.1
        local regular=target>SPIT_MIN_LEVEL and rig.talk>=SPIT_AFTER_SECONDS
        local accentOnset=accent and emphasis>.6 and rig.prevEmphasis<=.4 and now-rig.lastAccent>.18
        rig.prevEmphasis=emphasis
        local interval=accent and math.max(.18,.27-.07*level) or forced and .44 or math.max(.65,SPIT_BASE_INTERVAL-SPIT_LOUD_INTERVAL_REDUCTION*level)
        if near and not firstPerson and not p:GetAttribute('Hiding') and (forced or accent or regular) and (now-rig.lastSpit>interval or accentOnset and now-rig.lastSpit>.14) then
            rig.lastSpit=now
            if accent then rig.lastAccent=now end
            spit(rig,level,now,emphasis)
        end
    end
    for _,drop in drops do
        local age=now-drop.born
        if Preferences.Get('SpitEffects') and age<drop.life then
            local position=drop.origin+drop.velocity*((1-math.exp(-age*1.8))/1.8)+Vector3.new(0,-26*age*age,0)
            drop.part.CFrame=CFrame.lookAt(position,position+drop.velocity*math.exp(-age*1.8)+Vector3.new(0,-52*age,0))
            drop.part.Transparency=.25+.75*(age/drop.life)^2
        else drop.part.Transparency=1 end
    end
end)


-- TEENY TINY omen (RecoveryRoundServer, Monsters build 2026-10-27): OmenScaleAt announces a body rescale. The cached mouth
-- and teeth sizes belong to the old size, so the rig is dropped at once and rebuilt half a second after the change.
do
 local function watchScale(p)
  p:GetAttributeChangedSignal('OmenScaleAt'):Connect(function()
   local at=p:GetAttribute('OmenScaleAt');if type(at)~='number'then return end
   local c=p.Character;removeRig(p)
   task.delay(math.max(0,at-workspace:GetServerTimeNow())+.5,function()
    if p.Parent and c and p.Character==c and c.Parent and not rigs[p]then addCharacter(p,c)end
   end)
  end)
 end
 for _,p in Players:GetPlayers()do watchScale(p)end
 Players.PlayerAdded:Connect(watchScale)
end
