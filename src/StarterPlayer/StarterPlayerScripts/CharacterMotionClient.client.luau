local Selected=require(game.ReplicatedStorage:WaitForChild('SelectedItemCharacterEffects'))
local FaceGeometry=require(game.ReplicatedStorage:WaitForChild('SelectedFaceGeometry'))
-- Independent Studio draft leases reuse the existing renderer without owning normal curse state.
local itemDraftStudio = game:GetService('RunService'):IsStudio()
local function draftLease(q, key)
 local original = q:GetAttribute(key) or 0
 return math.max(original, itemDraftStudio and (q:GetAttribute('Draft' .. key) or 0) or 0)
end
-- Additive movement and gaze, with no changes to controller or physical arm ownership.
local Players=game:GetService('Players')
local Run=game:GetService('RunService')
local UIS=game:GetService('UserInputService')
local player=Players.LocalPlayer
local event=game.ReplicatedStorage:WaitForChild('CharacterLook')
local rigs={}
local SocialGaze=require(game.ReplicatedStorage:WaitForChild('SocialGazeRules'))
local lastSend,sequence=0,0
local LID_CENTER=.1725216 -- Authored geometry fallback only.
local BEE_LID_ANGLE=-1.4
local SQUINT_LID_ANGLE=-1.66
local SNAIL_DROOP=.9 -- radians the eye stalks sag forward while holding the snail shell
local BEE_SWELL=1.5 -- stung eyeball scale
local BOBBLE_SWELL,BOBBLE_SWAY,BOBBLE_RATE=1.7,.32,9 -- BobbleBuddy (ItemBatch6 BobbleUntil): bobblehead eyes on springy stalks
local GASP_SWELL,GASP_PUPIL=1.3,.55 -- FaceBeat 'gasp' (ItemBatch6 Feedback, close-up choices): wide startled eyes, tiny pupils, no blink
local pending={}
-- Field map hold pose (other players see this). Joint-space rotations for the left arm.
-- Solved in Studio so the left hand sits in front of the chest (root space about -0.55, 1.0, -1.35).
local MAP_SHOULDER=CFrame.Angles(1.40,1.85,-1.15)
local MAP_ELBOW=CFrame.Angles(.80,.40,2.20)
local function anchoredStalkOffset(tip,offset)
    local target=tip+offset
    if tip.Magnitude<1e-5 or target.Magnitude<1e-5 then return CFrame.identity end
    local a,b=tip.Unit,target.Unit
    local cross=a:Cross(b);local dot=math.clamp(a:Dot(b),-1,1)
    if cross.Magnitude<1e-6 then return CFrame.identity end
    return CFrame.fromAxisAngle(cross.Unit,math.atan2(cross.Magnitude,dot))
end
-- Lobby cursor rays hit the floor from third person. Keep the head forward;
-- a camera deliberately viewing our face is an eye-only inspection target.
local function lobbyGazePoint(r,camera)
    local origin=SocialGaze.EyePoint(r.character)or r.head.Position
    local forward=origin+r.root.CFrame.LookVector*200
    local offset=camera.CFrame.Position-origin
    local distance=offset.Magnitude
    if distance>=3 and distance<=35 and r.root.CFrame.LookVector:Dot(offset.Unit)>.15
        and camera.CFrame.LookVector:Dot(-offset.Unit)>.80 then
        return camera.CFrame.Position
    end
    return forward
end
local MAP_POCKET_DIP=.25
-- FK-verified holds: connected elbow bend, absolute joint poses independent of walking swing.
local SELECTED_ARM={
Default={LeftShoulder=CFrame.Angles(-0.253134042,0.351783603,-0.735742211),LeftElbow=CFrame.Angles(2.04397249,0.0278948955,0.643129647),LeftWrist=CFrame.identity},
BackwardsHairdryer={LeftShoulder=CFrame.Angles(0.139697701,-0.208630443,-0.800266564),LeftElbow=CFrame.Angles(2.04889584,-0.0858437121,0.570718467),LeftWrist=CFrame.identity},
SulkingUmbrella={LeftShoulder=CFrame.Angles(-0.209478855,0.302039027,-0.76941824),LeftElbow=CFrame.Angles(1.73204136,0.0240149051,0.649617672),LeftWrist=CFrame.identity},
}

local function add(p,c)
    if pending[p]==c or rigs[p]and rigs[p].character==c then return end
    pending[p]=c
    local h=c:WaitForChild('Head',10);local root=c:WaitForChild('HumanoidRootPart',10)
    if not h or not root or not c:GetAttribute('CustomCharacterVersion') then if pending[p]==c then pending[p]=nil end;return end
    local faceOk,faceError=pcall(FaceGeometry.Apply,h)
    -- A missing mesh API must not stop the normal character renderer.
    -- Keep the failure visible; each eye falls back to its authored blink geometry.
    c:SetAttribute('SelectedFaceError',not faceOk and tostring(faceError)or nil)
    local joints={}
    for _,name in {'Root','Waist','Neck','LeftHip','RightHip','LeftKnee','RightKnee','LeftAnkle','RightAnkle','LeftShoulder','RightShoulder','LeftElbow','RightElbow','LeftWrist','RightWrist'} do
        local j=c:FindFirstChild(name,true)
        if j and (j:IsA('Motor6D') or j:IsA('AnimationConstraint')) then joints[name]={joint=j,base=j.Transform} end
    end
    local pupils={}
    for _,side in {'Left','Right'} do
        local pupil=h:WaitForChild(side..'Pupil',5)
        local eye=h:WaitForChild(side..'Eyeball',10)
        local joint=pupil and pupil:WaitForChild('GazeJoint',10)
        local stalk=h:WaitForChild(side..'EyeStalk',10)
        local neck=stalk and stalk:WaitForChild('EyeNeckJoint',10)
        local lid=h:WaitForChild(side..'EyeLid',10)
        local lidJoint=lid and lid:WaitForChild('EyeLidJoint',10)
        if eye and joint and neck and lidJoint then
            table.insert(pupils,{joint=joint,eye=eye,eyeSize=eye.Size,pupil=pupil,pupilSize=pupil.Size,neck=neck,base=joint.C0,side=side,
                lid=lid,lidJoint=lidJoint,lidOpen=lidJoint.C0,precision=lid:GetAttribute('PrecisionShell')==true,
                lidSize=lid:GetAttribute('PrecisionShell')==true and Vector3.new(.79,.79,.395)or lid.Size/.82,
                stalk=stalk,stalkSize=stalk.Size,stalkTip=(h.CFrame*neck.C0):PointToObjectSpace(eye.Position)})
        end
    end
    if p.Character~=c or pending[p]~=c then if pending[p]==c then pending[p]=nil end;return end
    if #pupils~=2 then if pending[p]==c then pending[p]=nil end;task.delay(1,function()if p.Parent and p.Character==c then add(p,c)end end);return end
    c:SetAttribute('MotionEyesReady',true)
    local selectedParts={}
    for _,n in {'UpperTorso','LeftFoot','RightFoot','LeftHand','RightHand'}do local q=c:FindFirstChild(n);if q then selectedParts[n]={part=q,size=q.Size}end end
    local blinkRandom=Random.new(p.UserId+4021)
    rigs[p]={character=c,head=h,root=root,humanoid=c:FindFirstChildOfClass('Humanoid'),joints=joints,pupils=pupils,
        yaw=0,pitch=0,targetYaw=0,targetPitch=0,stamp=0,updated=0,lean=Vector3.zero,velocity=Vector3.zero,
        phase=0,land=0,air=false,idle=0,selectedParts=selectedParts,blinkRandom=blinkRandom,blinkStart=-100,blinkCount=1,bodyScale=c:GetScale(),
        nextBlink=os.clock()+blinkRandom:NextNumber(1.1,2.1)}
end
local function join(p)
    p.CharacterAdded:Connect(function(c) task.spawn(add,p,c) end)
    p.CharacterRemoving:Connect(function(c)if pending[p]==c then pending[p]=nil end;if rigs[p]and rigs[p].character==c then rigs[p]=nil end end)
    if p.Character then task.spawn(add,p,p.Character) end
end
Players.PlayerAdded:Connect(join)
Players.PlayerRemoving:Connect(function(p) rigs[p]=nil;pending[p]=nil end)
for _,p in Players:GetPlayers() do join(p) end
task.spawn(function()
    require(game.ReplicatedStorage:WaitForChild('CharacterEntityAdapter')).Watch(add,function(p)rigs[p]=nil;pending[p]=nil end)
end)
-- Tell the server we listen (it only sends look updates to ready clients); deferred so it runs after this Connect.
task.defer(function() event:FireServer('ready') end)
event.OnClientEvent:Connect(function(p,yaw,pitch,stamp,targetPoint)
    local r=rigs[p]
    if p~=player and r and stamp>r.stamp then
        r.targetYaw=yaw;r.targetPitch=pitch;r.targetPoint=targetPoint;r.updated=os.clock();r.stamp=stamp
    end
end)
-- Remove our previous layer before Animator evaluates; this also avoids accumulating offsets on idle joints.
Run.PreAnimation:Connect(function()
    for _,r in rigs do for _,j in r.joints do
        j.joint.Transform=j.base
    end end
end)
Run.PreSimulation:Connect(function(dt)
    dt=math.clamp(dt,0,.1);local now=os.clock();local camera=workspace.CurrentCamera
    local own=rigs[player]
    if own and camera then
        if player:GetAttribute('MissionActive')==true then
        local point=camera.ViewportSize/2
        -- The pointer can still move in Studio and UI modes while MouseBehavior reports LockCenter.
        -- Use its actual screen position whenever mouse input is active; a truly locked cursor
        -- already reports the center. Touch and gamepad gaze stays at viewport center.
        if UIS.MouseEnabled and UIS:GetLastInputType()~=Enum.UserInputType.Touch and not UIS:GetLastInputType().Name:find('Gamepad') then
            local raw=UIS:GetMouseLocation()
            point=Vector2.new(math.clamp(raw.X,0,camera.ViewportSize.X),math.clamp(raw.Y,0,camera.ViewportSize.Y))
        end
        local ray=camera:ViewportPointToRay(point.X,point.Y)
        local params=RaycastParams.new()
        params.FilterType=Enum.RaycastFilterType.Exclude
        params.FilterDescendantsInstances={own.character}
        params.IgnoreWater=true
        local hit=workspace:Raycast(ray.Origin,ray.Direction*500,params)
        own.targetPoint=hit and hit.Position or ray.Origin+ray.Direction*200
        local direction=(own.targetPoint-own.head.Position).Unit
        local localDirection=own.root.CFrame:VectorToObjectSpace(direction)
        own.targetYaw=math.clamp(math.atan2(-localDirection.X,-localDirection.Z),-1.3,1.3)
        own.targetPitch=math.clamp(math.asin(math.clamp(localDirection.Y,-1,1)),-1.2,1.2)
        else
            own.targetYaw=0;own.targetPitch=0
            own.targetPoint=lobbyGazePoint(own,camera)
        end
        own.updated=now
        if now-lastSend>=.1 then lastSend=now;sequence+=1;event:FireServer(own.targetYaw,own.targetPitch,sequence,own.targetPoint) end
    end
    for p,r in rigs do
        if not r.root.Parent then rigs[p]=nil;continue end
        local active=r.humanoid and r.humanoid.Health>0 and not p:GetAttribute('Hiding')
        local near=not camera or (camera.CFrame.Position-r.root.Position).Magnitude<150
        local inMission=p:GetAttribute('MissionActive')==true
        local isEntity=type(p)=='table'and p.IsEntity
        local yaw,pitch=0,0
        if active and near and inMission and now-r.updated<.7 then yaw=r.targetYaw;pitch=r.targetPitch end
        if (type(p)=='table' and p.IsEntity) and active then
            local frantic=r.character:GetAttribute('EntityState')=='Freakout'
            yaw=frantic and math.sin(now*9)*.65 or math.sin(now*.5)*.18
            pitch=frantic and math.sin(now*13)*.22 or -.06
        end
        local alpha=1-math.exp(-dt*12)
        if inMission or isEntity then
            r.yaw+=(yaw-r.yaw)*alpha;r.pitch+=(pitch-r.pitch)*alpha
        else
            -- Discard a previous mission's cosmetic look immediately on returning to lobby.
            r.yaw=0;r.pitch=0
        end
        local v=r.root.CFrame:VectorToObjectSpace(r.root.AssemblyLinearVelocity)
        local acceleration=(v-r.velocity)/math.max(dt,.001);r.velocity=v
        local grounded=r.humanoid and r.humanoid.FloorMaterial~=Enum.Material.Air
        if grounded and r.air then r.land=.07 end
        r.air=not grounded;r.land*=math.exp(-dt*12)
        local speed=Vector3.new(v.X,0,v.Z).Magnitude
        local selected=active and Selected.Read(p,speed)or nil
        local body=selected and selected.body
        if body or r.selectedWasActive then
         for n,q in r.selectedParts do
          local key=({UpperTorso='torsoScale',LeftFoot='leftFootScale',RightFoot='rightFootScale',LeftHand='leftHandScale',RightHand='rightHandScale'})[n]
          q.part.Size=Selected.Mul(q.size,body and body[key]or Vector3.one)
         end
        end
        r.selectedWasActive=body~=nil
        r.character:SetAttribute('SelectedRenderedItem',selected and selected.id or nil)
        local resting=active and grounded and speed<.65 and r.humanoid.MoveDirection.Magnitude<.05
        r.idle+=((resting and 1 or 0)-r.idle)*(1-math.exp(-dt*5))
        if speed<.65 then v=Vector3.zero;acceleration=Vector3.zero end
        r.phase+=dt*math.min(speed,28)*.7
        local desired=Vector3.zero
        if active and near then desired=Vector3.new(math.clamp(-v.Z*.006-acceleration.Z*.00035,-.18,.18),(speed>.65 and math.clamp(r.root.AssemblyAngularVelocity.Y*.02,-.10,.10) or 0),math.clamp(-v.X*.008-acceleration.X*.00035,-.18,.18)) end
        r.lean=r.lean:Lerp(desired,1-math.exp(-dt*8))
        local bob=active and near and grounded and math.sin(r.phase*2)*math.min(speed/26,1)*.035 or 0
        local crying=active and workspace:GetServerTimeNow()<(draftLease(p,'CryingUntil'))
        local spraying=active and workspace:GetServerTimeNow()<(p:GetAttribute('PerfumeSprayUntil')or 0)
        local sprayAge=workspace:GetServerTimeNow()-(p:GetAttribute('PerfumeSprayStart')or 0)
        local sprayBlend=spraying and math.clamp(sprayAge/.22,0,1)*math.clamp((1.8-sprayAge)/.20,0,1)or 0
        -- Field map (FieldMapServer's MapOpen): left arm dips toward the pocket, then lifts the radar to read.
        local mapTarget=active and p:GetAttribute('MapOpen')==true and 1 or 0
        r.map=(r.map or 0)+(mapTarget-(r.map or 0))*(1-math.exp(-dt*7))
        local mapBlend=r.map
        -- Studio tuning: workspace MapPoseShoulder / MapPoseElbow (CFrame) override the constants live.
        local studioShoulder=Run:IsStudio() and workspace:GetAttribute('MapPoseShoulder')
        local studioElbow=Run:IsStudio() and workspace:GetAttribute('MapPoseElbow')
        local mapShoulder=CFrame.new():Lerp(typeof(studioShoulder)=='CFrame' and studioShoulder or MAP_SHOULDER,mapBlend)
        local mapElbow=CFrame.new():Lerp(typeof(studioElbow)=='CFrame' and studioElbow or MAP_ELBOW,mapBlend)
        local pocketDip=CFrame.Angles(math.sin(mapBlend*math.pi)*MAP_POCKET_DIP,0,0)
        local offsets={
            LeftShoulder=CFrame.Angles(-.8*sprayBlend,.12*sprayBlend,-.525*sprayBlend)*mapShoulder*pocketDip,
            LeftElbow=CFrame.Angles(2.8*sprayBlend,0,math.sin(sprayAge*math.pi*4)*.06*sprayBlend)*mapElbow,
            Root=CFrame.new(0,bob-r.land+math.sin(now*1.45)*.012*r.idle,0)*CFrame.Angles(-.05+r.lean.X*.4,0,r.lean.Z*.4),
            Waist=CFrame.Angles(-.27+r.lean.X*.6+r.pitch*.08,r.yaw*.12+r.lean.Y,r.lean.Z*.6),
            -- Imported Head +Z points forward. Offline FK: -.05 root -.27 waist +.32 neck is level.
            -- Only the lobby neck baseline changes; torso, arm poses and all grips stay authored.
            Neck=CFrame.Angles(((inMission or isEntity)and .10 or .32)+r.pitch*.30+(crying and .16+math.sin(now*8)*.018 or 0)+(active and p:GetAttribute('CursedActive')=='DiscoBall' and math.sin(workspace:GetServerTimeNow()*math.pi*4)*.30 or 0),r.yaw*.32,-r.lean.Z*.25+(active and p:GetAttribute('CursedActive')=='DiscoBall' and math.sin(workspace:GetServerTimeNow()*math.pi*2)*.065 or 0))}
        if (type(p)=='table' and p.IsEntity) and active then
            -- NPCs do not run a player's Animate LocalScript. Supply only their locomotion layer.
            local stride=math.sin(r.phase)
            local amount=math.clamp(speed/14,0,1)
            local frantic=r.character:GetAttribute('EntityState')=='Freakout'
            local swing=stride*amount*(frantic and 1.0 or .55)
            offsets.LeftHip=CFrame.Angles(swing,0,0)
            offsets.RightHip=CFrame.Angles(-swing,0,0)
            offsets.LeftKnee=CFrame.Angles(math.max(0,-stride)*amount*.9,0,0)
            offsets.RightKnee=CFrame.Angles(math.max(0,stride)*amount*.9,0,0)
            offsets.LeftShoulder=CFrame.Angles(-swing*.7,0,-.12)
            offsets.RightShoulder=CFrame.Angles(swing*.7,0,.12)
            offsets.LeftElbow=CFrame.Angles(frantic and -.6 or -.15,0,0)
            offsets.RightElbow=CFrame.Angles(frantic and -.6 or -.15,0,0)
        end
        if body then
         offsets.Neck*=CFrame.new(body.neckOffset)*CFrame.Angles(body.neckAngles.X,body.neckAngles.Y,body.neckAngles.Z)
         offsets.Waist*=CFrame.Angles(body.waistAngles.X,body.waistAngles.Y,body.waistAngles.Z)
         -- A readable grip pose; observer item presentation follows the evaluated physical hand.
         -- Arm pose below is absolute so the walk animation cannot twist the held elbow.
        end
        if selected then r.selectedArmId=selected.id end
        r.selectedArmWeight=math.clamp((r.selectedArmWeight or 0)+(selected and dt/.20 or -dt/.20),0,1)
        local arm=SELECTED_ARM[r.selectedArmId]or SELECTED_ARM.Default
        local armBlend=r.selectedArmWeight*r.selectedArmWeight*(3-2*r.selectedArmWeight)
        for name,j in r.joints do
            j.base=j.joint.Transform
            local pose=j.base:Lerp(CFrame.identity,r.idle)
            if name=='Waist' then pose*=CFrame.Angles(math.sin(now*1.45)*.006*r.idle,0,0) end
            local native=pose*(offsets[name]or CFrame.identity)
            j.joint.Transform=arm[name]and native:Lerp(arm[name],armBlend)or native
        end
        -- Head's imported local +Z is the character's forward direction.
        local worldDirection=r.root.CFrame:VectorToWorldSpace(Vector3.new(-math.sin(r.yaw)*math.cos(r.pitch),math.sin(r.pitch),-math.cos(r.yaw)*math.cos(r.pitch)))
        if active and now>=r.nextBlink then
            r.blinkStart=now
            local burst=r.blinkRandom:NextNumber()
            r.blinkCount=burst<.25 and 1 or burst<.73 and 2 or 3
            r.nextBlink=now+r.blinkRandom:NextNumber(1.1,2.1)
        end
        local blinkAge=now-r.blinkStart
        local blink=0
        if active and blinkAge>=0 then
            local cycle=math.floor(blinkAge/.255)
            if cycle<r.blinkCount then
                local age=blinkAge-cycle*.255
                if age<.025 then blink=age/.025
                elseif age<.145 then blink=1
                elseif age<.205 then blink=1-(age-.145)/.06 end
            end
        end
        if crying then blink=math.max(blink,.28)end
        -- Red pepper squint (until the server clears PepperSquint at level end): only the lid moves, see the eye loop.
        local squint=active and (p:GetAttribute('PepperSquint')==true or (p:GetAttribute('FaceBeat')=='squint' or p:GetAttribute('FaceBeat')=='laugh') and workspace:GetServerTimeNow()<(p:GetAttribute('FaceBeatUntil')or 0)) -- FaceBeat squint/laugh: ItemBatch8/9
        -- Beehive sting (one eye, whole level) and popsicle frost (while held) only restyle the eye; blink logic is unchanged.
        local swollenSide=active and p:GetAttribute('BeeSwollen')
        local frosty=active and workspace:GetServerTimeNow()<(draftLease(p,'FrozenUntil'))
        -- Snail shell (while held): stalks sag forward and sway lazily, easing back when dropped.
        local snailTarget=active and workspace:GetServerTimeNow()<(draftLease(p,'SnailUntil'))and 1 or 0
        r.snail=(r.snail or 0)+(snailTarget-(r.snail or 0))*(1-math.exp(-dt*3))
        local bobbleTarget=active and workspace:GetServerTimeNow()<(draftLease(p,'BobbleUntil'))and 1 or 0
        r.bobble=(r.bobble or 0)+(bobbleTarget-(r.bobble or 0))*(1-math.exp(-dt*6))
        local bobbleAge=workspace:GetServerTimeNow()-(p:GetAttribute('FirstFindGrabAt')or 0)
        local bobbleKick=p:GetAttribute('FirstFindGrabItem')=='BobbleBuddy'and bobbleAge>=0 and bobbleAge<2 and math.exp(-bobbleAge*2.2)*math.sin(bobbleAge*17)*.9 or 0
        local gaspTarget=active and p:GetAttribute('FaceBeat')=='gasp'and workspace:GetServerTimeNow()<(p:GetAttribute('FaceBeatUntil')or 0)and 1 or 0
        r.gasp=(r.gasp or 0)+(gaspTarget-(r.gasp or 0))*(1-math.exp(-dt*(gaspTarget>(r.gasp or 0)and 18 or 5)))
        local neckJoint=r.joints.Neck and r.joints.Neck.joint
        if neckJoint then neckJoint.Transform*=CFrame.Angles(-.12*blink,0,0) end
        -- Eye contact is a separate eye-only layer; camera and neck use the normal input aim.
        local socialId=p:GetAttribute('SocialGazeUserId')
        local socialTarget=socialId and Players:GetPlayerByUserId(socialId)
        local socialPoint=socialTarget and SocialGaze.EyePoint(socialTarget.Character)
        local wantsSocial=active and near and socialPoint~=nil
            and SocialGaze.Available(p)and SocialGaze.Available(socialTarget)
            and(p:GetAttribute('MissionActive')==true)==(socialTarget:GetAttribute('MissionActive')==true)
            and workspace:GetServerTimeNow()<(p:GetAttribute('SocialGazeUntil')or 0)
        if wantsSocial then r.socialPoint=socialPoint end
        r.socialBlend=(r.socialBlend or 0)+((wantsSocial and 1 or 0)-(r.socialBlend or 0))*(1-math.exp(-dt*3.5))
        for _,eye in r.pupils do
            local shape=selected and selected.eyes[eye.side]
            local blink=blink
            -- Sour lemon: eyes squeeze shut in waves while it is held.
            if active and workspace:GetServerTimeNow()<(draftLease(p,'LemonUntil'))then local wave=math.sin(os.clock()*2.4+p.UserId%5)*.5+.5;blink=math.max(blink,math.clamp((wave-.3)/.35,0,1))end
            if r.gasp>.01 then blink*=1-r.gasp end -- startled: eyes stay wide open
            local vanityPhase=(workspace:GetServerTimeNow()+p.UserId%7*.17)%4.5
            if active and p:GetAttribute('PhysicalGrabActive')==true and p:GetAttribute('CursedActive')=='Mirror' and eye.side=='Left' then blink=math.max(blink,math.clamp(vanityPhase/.12,0,1)*math.clamp((.65-vanityPhase)/.18,0,1)) end
            -- Explicit visual QA override; nil keeps the native blink schedule.
            local forcedBlink=itemDraftStudio and workspace:GetAttribute('SelectedForceBlink')
            if typeof(forcedBlink)=='number' then blink=math.clamp(forcedBlink,0,1)end
            local liveTarget=active and near and now-r.updated<.7 and r.targetPoint
            local aim=liveTarget or (r.head.Position+worldDirection*200)
            if not inMission and not isEntity then
                -- A peer's old mission ray must never become its lobby floor target.
                -- Own camera inspection is local; shared social eye-contact blends below.
                aim=(p==player and camera and r.targetPoint)
                    or ((SocialGaze.EyePoint(r.character)or r.head.Position)+r.root.CFrame.LookVector*200)
            end
            local delta=aim-eye.eye.Position
            local gaze=delta.Magnitude>.001 and delta.Unit or worldDirection
            if r.socialPoint and r.socialBlend>.001 then
                local contact=r.socialPoint-eye.eye.Position
                if contact.Magnitude>.1 then gaze=gaze:Lerp(contact.Unit,r.socialBlend).Unit end
            end
            local headAim=r.head.CFrame:VectorToObjectSpace(gaze)
            local stalkYaw=math.clamp(math.atan2(headAim.X,math.max(headAim.Z,.2)),-1.15,1.15)
            local stalkPitch=math.clamp(math.atan2(headAim.Y,math.sqrt(headAim.X*headAim.X+headAim.Z*headAim.Z)),-.95,.95)
            local stalkAlpha=1-math.exp(-dt*24)
            eye.yaw=(eye.yaw or 0)+(stalkYaw-(eye.yaw or 0))*stalkAlpha
            eye.pitch=(eye.pitch or 0)+(stalkPitch-(eye.pitch or 0))*stalkAlpha
            -- Folded stalks nod with the neck and flex independently while moving.
            local motion=math.clamp(speed/16,0,1)
            local side=eye.side=='Left' and -1 or 1
            local inertia=math.clamp(acceleration.Z*.002,-.12,.12)
            local wiggle=motion*math.sin(now*10+side*1.3)*.11
            local roll=side*motion*math.sin(now*13+side)*.095
            eye.neck.Transform=CFrame.Angles(-eye.pitch*.55+wiggle+inertia-.20*blink,eye.yaw*.55+motion*math.sin(now*7+side)*.045,roll+side*blink*.30)
            if r.snail>.001 then eye.neck.Transform*=CFrame.Angles(-(SNAIL_DROOP+math.sin(now*1.3+side)*.12)*r.snail,0,side*.25*r.snail)end
            if r.bobble>.001 then local sway=BOBBLE_SWAY*(.3+.7*motion)*math.sin(now*BOBBLE_RATE+side*.9);eye.neck.Transform*=CFrame.Angles((sway+bobbleKick)*r.bobble,0,side*(sway*.6+bobbleKick*.5)*r.bobble)end
            if shape then eye.neck.Transform*=anchoredStalkOffset(eye.stalkTip,shape.stalkOffset)*CFrame.Angles(shape.stalkAngles.X,shape.stalkAngles.Y,shape.stalkAngles.Z)end
            -- The new lid actually closes over a round eye, instead of flattening it into a disc.
            local eyeSize=eye.eyeSize
            local swell=swollenSide==eye.side and BEE_SWELL or 1
            eyeSize=Selected.Mul(eyeSize*swell,shape and shape.size or Vector3.one)
            if not eye.precision then
                eyeSize=Vector3.new(eye.eyeSize.X*(1-.22*blink),eye.eyeSize.Y*(1-.80*blink),eye.eyeSize.Z*(1-.30*blink))*swell
            end
            local bobbleScale=(1+(BOBBLE_SWELL-1)*r.bobble)*(1+(GASP_SWELL-1)*r.gasp)
            eyeSize*=bobbleScale
            if (eye.eye.Size-eyeSize).Magnitude>.001 then eye.eye.Size=eyeSize end
            local pupilSize=Selected.Mul(eye.pupilSize*(swell>1 and 1.2 or 1),shape and shape.pupilSize or Vector3.one)
            -- The old0.061-stud bulge poked through a fully closed eyelid.
            -- Keep the readable oval, but make it a thin surface at every eye size.
            local eyeDepthScale=eyeSize.Z/eye.eyeSize.Z
            pupilSize=Vector3.new(pupilSize.X,pupilSize.Y,math.min(pupilSize.Z,.012*eyeDepthScale))
            if not eye.precision then
                pupilSize=Vector3.new(eye.pupilSize.X*(1-.22*blink),eye.pupilSize.Y*(1-.70*blink),eye.pupilSize.Z*(1-.30*blink))*(swell>1 and 1.2 or 1)
            end
            -- Tints capture the real colours when an effect starts and restore them when it ends,
            -- so the character colour system still owns the colours the rest of the time.
            local tinted=swell>1 or frosty
            -- Body-region parts show their colour through a UniformBodySurface SurfaceAppearance, not Part.Color.
            local lidSurface=eye.lid:FindFirstChild('UniformBodySurface')
            if tinted and not eye.tintBase then eye.tintBase={eye=eye.eye.Color,lid=lidSurface and lidSurface.Color or eye.lid.Color,pupil=eye.pupil.Color}end
            local base=eye.tintBase
            if base then
                local eyeColor=swell>1 and base.eye:Lerp(Color3.fromRGB(255,140,150),.45)or base.eye
                local lidColor=frosty and base.lid:Lerp(Color3.fromRGB(190,230,255),.75)or base.lid
                local pupilColor=frosty and base.pupil:Lerp(Color3.fromRGB(215,240,255),.65)or base.pupil
                if eye.eye.Color~=eyeColor then eye.eye.Color=eyeColor end
                if lidSurface then if lidSurface.Color~=lidColor then lidSurface.Color=lidColor end
                elseif eye.lid.Color~=lidColor then eye.lid.Color=lidColor end
                if eye.pupil.Color~=pupilColor then eye.pupil.Color=pupilColor end
                if not tinted then eye.tintBase=nil end
            end
            pupilSize*=bobbleScale*(1-(1-GASP_PUPIL)*r.gasp)
            if (eye.pupil.Size-pupilSize).Magnitude>.001 then eye.pupil.Size=pupilSize end
            -- Aim each pupil from its own eyeball at the same 3D cursor point.
            -- This keeps the two eyes converged on nearby objects, including for other players.
            local d=eye.eye.CFrame:VectorToObjectSpace(gaze)
            d=Vector3.new(math.clamp(d.X,-.78,.78),math.clamp(d.Y,-.78,.78),math.max(d.Z,.35)).Unit
            local radius=eyeSize.Z*.5+.002*eyeDepthScale
            local surface=Vector3.new(d.X*eyeSize.X*.5,d.Y*eyeSize.Y*.5,d.Z*radius)
            local desiredPupil=CFrame.lookAt(surface,surface-d)
            if not eye.precision then
                desiredPupil=CFrame.lookAt(d*(.352-.10*blink)*swell*bobbleScale,d*(.352-.10*blink)*swell*bobbleScale-d)
            end
            eye.joint.Transform=eye.base:Inverse()*desiredPupil
            -- A full shell flips behind the eyeball when open and closes over its entire front.
            -- Squint: the shell hangs from the top (negative angle) with its edge just above the pupil, and blinks close from there.
            if eye.precision then
            local lidAngle=-(swell>1 and math.pi*.66 or squint and math.pi*.45 or math.pi)*(1-blink)
            if shape then lidAngle-=shape.lidOffset*(1-blink)end
            -- The cap shares the eyeball radius at EVERY magnification and blink pose.
            local lidScale=Vector3.new(eyeSize.X/.7169283,eyeSize.Y/.7199988,eyeSize.Z/.7169285)
            -- Enclose even the pupil's oriented bounding corners. This protects
            -- wide/squashed-eye recipes as well as the2x magnifier without hiding
            -- the pupil or changing its transparency during a blink.
            local pupilExtent=1
            for _,sx in {-1,1}do for _,sy in {-1,1}do for _,sz in {-1,1}do
                local corner=desiredPupil:PointToWorldSpace(Vector3.new(sx*pupilSize.X*.5,sy*pupilSize.Y*.5,sz*pupilSize.Z*.5))
                local normalized=Vector3.new(corner.X/(eyeSize.X*.5),corner.Y/(eyeSize.Y*.5),corner.Z/(eyeSize.Z*.5))
                pupilExtent=math.max(pupilExtent,normalized.Magnitude)
            end end end
            local fit=math.max(1,(pupilExtent+.015)/math.min(.79/.7169283,.79/.7199988,.79/.7169285))
            lidScale*=fit
            local rotation=CFrame.Angles(lidAngle,0,0)
            local lidPose=rotation*CFrame.new(0,0,.1975*lidScale.Z)
            eye.lidJoint.Transform=eye.lidOpen:Inverse()*lidPose
            eye.lid.Size=Selected.Mul(eye.lidSize,lidScale)
            else
                -- The fresh base's eye mesh uses its original pivot and blink squash.
                local lidAngle=swell>1 and BEE_LID_ANGLE*(1-blink) or squint and SQUINT_LID_ANGLE*(1-blink) or math.pi*(1-blink)
                local lidPose=CFrame.Angles(lidAngle,0,0)*CFrame.new(0,0,LID_CENTER*swell*bobbleScale)*CFrame.Angles(0,math.pi,0)
                eye.lidJoint.Transform=eye.lidOpen:Inverse()*lidPose
                local lidSize=eye.lidSize*((squint or swell>1)and 1.22 or .82+.40*blink)*swell*bobbleScale
                if (eye.lid.Size-lidSize).Magnitude>.001 then eye.lid.Size=lidSize end
            end

        end
    end
end)




-- TEENY TINY omen (RecoveryRoundServer, Monsters build 2026-10-27): the server announces a body rescale with OmenScaleAt
-- (the server time it happens). The cached eye sizes belong to the old size and this rig keeps writing them locally, so a
-- rebuild could read its own stale sizes back: the rig is dropped at once and rebuilt half a second after the change with
-- every cached size scaled by new/old body scale.
do
 local function watchScale(p)
  p:GetAttributeChangedSignal('OmenScaleAt'):Connect(function()
   local at=p:GetAttribute('OmenScaleAt');if type(at)~='number'then return end
   local c=p.Character;local old=rigs[p];local oldScale=old and old.bodyScale
   rigs[p]=nil;pending[p]=nil
   task.delay(math.max(0,at-workspace:GetServerTimeNow())+.5,function()
    if not(p.Parent and c and p.Character==c and c.Parent and not rigs[p])then return end
    add(p,c)
    local new=rigs[p];if not new then return end
    if old and oldScale and oldScale>0 then
     local k=new.bodyScale/oldScale
     for i,e in new.pupils do
      local o=old.pupils[i]
      if o then
       e.eyeSize=o.eyeSize*k;e.pupilSize=o.pupilSize*k;e.lidSize=o.lidSize*k;e.stalkSize=o.stalkSize*k
       e.eye.Size=e.eyeSize;e.pupil.Size=e.pupilSize
      end
     end
    end
   end)
  end)
 end
 for _,p in Players:GetPlayers()do watchScale(p)end
 Players.PlayerAdded:Connect(watchScale)
end
