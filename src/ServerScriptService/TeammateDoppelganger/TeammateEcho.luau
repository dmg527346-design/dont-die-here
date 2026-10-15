-- Entity factory: an exact, harmless copy of a player's game character that wanders and "freaks out".
-- Used by the mission spawner (ServerScriptService.TeammateDoppelganger) and the Studio van exhibit.
-- It never damages anyone: no touch/damage code, and its body passes through players, the cart and loot.
local Players=game:GetService('Players')
local Run=game:GetService('RunService')
local Pathfinding=game:GetService('PathfindingService')
local Physics=game:GetService('PhysicsService')
local Echo={}
local WALK_SPEED=7
local SPRINT_SPEED=46
local RED=Color3.fromRGB(255,24,32)
local NORMAL=Color3.fromRGB(255,244,220)
local WAYPOINT_REACHED=2.5 -- studs: close enough to move on to the next path waypoint
local BODY_GROUP='DoppelgangerBody'
-- Walls and floors stop it; players, the cart and loot pass straight through, so it can never block or shove anyone.
pcall(function()Physics:RegisterCollisionGroup(BODY_GROUP)end)
for _,other in {'RecoveryCharacters','RecoveryCart','RecoveryHeldCart','RecoveryLoot',BODY_GROUP}do
    pcall(function()Physics:CollisionGroupSetCollidable(BODY_GROUP,other,false)end)
end
local function removeExternalJoints(clone)
    -- Clone preserves references to objects outside the character (vehicles,
    -- grabbed props and attachments). Remove them before parenting or PivotTo.
    for _,joint in clone:GetDescendants()do
        if joint:IsA('JointInstance')or joint:IsA('WeldConstraint')or joint:IsA('Constraint')then
            for _,property in {'Part0','Part1','Attachment0','Attachment1'}do
                local ok,endpoint=pcall(function()return joint[property]end)
                if ok and endpoint and not endpoint:IsDescendantOf(clone)then
                    joint:Destroy();break
                end
            end
        end
    end
end
function Echo.Create(player,spawnCF,points,options)
    options=options or {}
    local source=player and player.Character
    assert(source and source:GetAttribute('CustomCharacterVersion'),'Choose a spawned game character')
    local oldArchivable=source.Archivable
    source.Archivable=true
    local c=source:Clone()
    source.Archivable=oldArchivable
    assert(c,'Character clone failed')
    removeExternalJoints(c)
    c.Name=options.name or 'TeammateEcho'
    -- Keep geometry, joint setup, surfaces and worn cosmetics; remove executable/player-only state.
    for key in c:GetAttributes()do c:SetAttribute(key,nil)end
    c:SetAttribute('CustomCharacterVersion',source:GetAttribute('CustomCharacterVersion'))
    c:SetAttribute('CharacterEntity',true)
    c:SetAttribute('CopiedUserId',player.UserId)
    c:SetAttribute('CopiedName',player.DisplayName)
    c:SetAttribute('EntityState','Wandering')
    c:SetAttribute('FlashlightOn',true)
    if options.mission then c:SetAttribute('MissionEntity',true)else c:SetAttribute('TestOnly',true)end
    for _,v in c:GetDescendants()do
        if v:IsA('LuaSourceContainer') or v:IsA('Tool') or v:IsA('ForceField') or v:IsA('ProximityPrompt') or v:IsA('Sound') or v:IsA('AudioEmitter') then
            v:Destroy()
        elseif v:IsA('BasePart') then
            v.Anchored=false;v.AssemblyLinearVelocity=Vector3.zero;v.AssemblyAngularVelocity=Vector3.zero
            v.CanCollide=false;v.CanTouch=false;v.CanQuery=false;v.Massless=false;v.CollisionGroup=BODY_GROUP
        elseif v:IsA('Motor6D') or v:IsA('AnimationConstraint') then
            v.Transform=CFrame.identity
        end
    end
    local h=c:FindFirstChildOfClass('Humanoid')
    local root=c:FindFirstChild('HumanoidRootPart')
    assert(h and root,'Clone has no humanoid/root')
    root.Massless=false
    -- One body collider keeps it on floors and out of walls without limbs snagging furniture.
    local collider=Instance.new('Part');collider.Name='EchoCollider';collider.Size=Vector3.new(2,3,2)
    collider.Transparency=1;collider.CanCollide=true;collider.CanTouch=false;collider.CanQuery=false;collider.Massless=false
    collider.CFrame=root.CFrame;collider.CollisionGroup=BODY_GROUP;collider.Parent=c
    local weld=Instance.new('WeldConstraint');weld.Part0=root;weld.Part1=collider;weld.Parent=collider
    h.DisplayDistanceType=Enum.HumanoidDisplayDistanceType.None
    h.MaxHealth=100;h.Health=100;h.WalkSpeed=WALK_SPEED;h.AutoRotate=true;h.Sit=false;h.PlatformStand=false
    h.Jump=false;h.JumpPower=50;h.JumpHeight=7.2 -- Echo defaults, independent of a seated source
    h:SetStateEnabled(Enum.HumanoidStateType.Seated,false)
    h:SetStateEnabled(Enum.HumanoidStateType.FallingDown,false)
    h:SetStateEnabled(Enum.HumanoidStateType.Ragdoll,false)
    h:SetStateEnabled(Enum.HumanoidStateType.Dead,false) -- nothing can "kill" the copy into a ragdoll
    local folder=workspace:FindFirstChild('CharacterEntities')
    if not folder then folder=Instance.new('Folder');folder.Name='CharacterEntities';folder.Parent=workspace end
    c:PivotTo(spawnCF);c.Parent=folder
    for _,v in c:GetDescendants()do if v:IsA('BasePart') and not v.Anchored then pcall(function()v:SetNetworkOwner(nil)end)end end
    local head=c.Head
    local att=Instance.new('Attachment');att.Name='EchoFlashlightEmitter'
    att.CFrame=CFrame.new(.6,-.3,-1)*CFrame.Angles(0,math.pi,0);att.Parent=head
    local light=Instance.new('SpotLight');light.Name='EchoFlashlight';light.Face=Enum.NormalId.Front
    light.Range=52;light.Angle=55;light.Brightness=2;light.Color=NORMAL;light.Shadows=false;light.Parent=att
    local handle=c:FindFirstChild('FlashlightHandle')
    local glow=handle and handle:FindFirstChild('RingPart')
    local originalGlow=glow and glow.Color
    local normal=typeof(player:GetAttribute('FlashlightColor'))=='Color3' and player:GetAttribute('FlashlightColor') or NORMAL
    light.Color=normal;light.Range=player:GetAttribute('FlashlightRange') or 52
    local strength=player:GetAttribute('FlashlightStrength') or 2
    local random=Random.new()
    local alive=true;local forcedUntil=0;local nextFreak=os.clock()+random:NextNumber(12,22)
    local state='Wandering';local pauseUntil=0;local lastPosition=root.Position;local stuckAt=os.clock()
    -- Path following: each destination is reached through PathfindingService waypoints (rooms, doors, stairs).
    local route=nil;local routeIndex=0;local target=nil;local generation=0;local computing=false
    local function destination()
        return points[random:NextInteger(1,#points)]
    end
    local function plan(goal)
        if computing then return end
        computing=true;generation+=1;local token=generation;target=goal
        task.spawn(function()
            local path=Pathfinding:CreatePath({AgentRadius=1.6,AgentHeight=7,AgentCanJump=false,WaypointSpacing=6})
            local ok=pcall(function()path:ComputeAsync(root.Position,goal)end)
            computing=false
            if not alive or token~=generation then return end
            if ok and path.Status==Enum.PathStatus.Success then
                route=path:GetWaypoints();routeIndex=math.min(2,#route)
                h:MoveTo(route[routeIndex].Position)
            else
                route=nil;target=nil;pauseUntil=os.clock()+.5 -- unreachable: pick another room shortly
            end
            stuckAt=os.clock();lastPosition=root.Position
        end)
    end
    local connection
    connection=Run.Heartbeat:Connect(function()
        if not alive or not c.Parent then connection:Disconnect();return end
        local now=os.clock()
        if now>=nextFreak and now>=forcedUntil then forcedUntil=now+random:NextNumber(4,7);nextFreak=forcedUntil+random:NextNumber(20,38)end
        local newState=now<forcedUntil and 'Freakout' or 'Wandering'
        if newState~=state then
            state=newState;c:SetAttribute('EntityState',state);h.WalkSpeed=state=='Freakout' and SPRINT_SPEED or WALK_SPEED
            if state=='Freakout'then pauseUntil=0;route=nil;target=nil end -- bolt somewhere new right away
        end
        -- Slow red pulses during frantic movement; local emitter only, no global lighting changes.
        local pulse=state=='Freakout' and (.35+.65*(.5+.5*math.sin(now*math.pi*3))) or 1
        light.Color=state=='Freakout' and RED or normal;light.Brightness=strength*pulse
        if glow then glow.Color=state=='Freakout' and RED or originalGlow end
        c:SetAttribute('EntitySpeed',h.WalkSpeed)
        if now<pauseUntil or computing then return end
        if not route then plan(destination());return end
        local wp=route[routeIndex]
        local flat=Vector3.new(root.Position.X-wp.Position.X,0,root.Position.Z-wp.Position.Z).Magnitude
        if flat<WAYPOINT_REACHED then
            if routeIndex>=#route then
                route=nil;target=nil
                if state=='Wandering'then pauseUntil=now+random:NextNumber(1,3);h:MoveTo(root.Position)end
            else
                routeIndex+=1;h:MoveTo(route[routeIndex].Position)
            end
        end
        -- Re-path if it stops making progress (a door closed, something moved).
        if (root.Position-lastPosition).Magnitude>1 then lastPosition=root.Position;stuckAt=now
        elseif route and now-stuckAt>2.5 then local goal=target;route=nil;if goal then plan(goal)end;stuckAt=now end
        if root.Position.Y<spawnCF.Position.Y-60 then c:PivotTo(spawnCF);root.AssemblyLinearVelocity=Vector3.zero;route=nil;target=nil end
    end)
    local controller={Model=c}
    function controller:Freakout()
        forcedUntil=os.clock()+6;nextFreak=forcedUntil+random:NextNumber(20,38)
    end
    function controller:IsFreaking()return os.clock()<forcedUntil end
    function controller:Destroy()
        alive=false;generation+=1;connection:Disconnect();c:Destroy()
    end
    c.Destroying:Once(function()alive=false;generation+=1;connection:Disconnect()end)
    return controller
end
return Echo
