-- Physical animation follows R15 animation; invisible limb colliders avoid Humanoid's
-- automatic collision suppression on named R15 arms. No self collisions.
local Players=game:GetService('Players')
local RunService=game:GetService('RunService')
local PhysicsService=game:GetService('PhysicsService')
local ARM_GROUP='HorrorPhysicalArms'
local BODY_GROUP='HorrorPlayerBodies'
for _,name in {ARM_GROUP,BODY_GROUP} do
    if not PhysicsService:IsCollisionGroupRegistered(name) then PhysicsService:RegisterCollisionGroup(name) end
end
PhysicsService:CollisionGroupSetCollidable(ARM_GROUP,BODY_GROUP,false)
PhysicsService:CollisionGroupSetCollidable(ARM_GROUP,ARM_GROUP,false)
local rigs={}
local function update(player)
    local rig=rigs[player]
    if not rig then return end
    local healthy=rig.humanoid.Health>0 and not player:GetAttribute('Hiding')
    local physical=false -- Animated arms stay kinematic; no ragdoll-like loose limbs.
    if rig.physical==physical then return end
    rig.physical=physical
    for _,joint in rig.joints do
        -- Tiny wrists are unstable as free physics joints. The shoulders and
        -- elbows stay physical once the player settles; all six animate while moving.
        joint.IsKinematic=joint.Name:find('Wrist')~=nil or not physical
    end
    for _,part in rig.colliders do part.CanCollide=physical end
end
local function characterAdded(player,character)
    local humanoid=character:WaitForChild('Humanoid',10)
    local root=character:WaitForChild('HumanoidRootPart',10)
    if not humanoid or not root then return end
    humanoid:SetStateEnabled(Enum.HumanoidStateType.Ragdoll,false);humanoid:SetStateEnabled(Enum.HumanoidStateType.FallingDown,false);humanoid:SetStateEnabled(Enum.HumanoidStateType.Physics,false)
    if not character:GetAttribute('HybridArmPhysics') then return end
    local joints,colliders={},{}
    local function markBody(instance)
        if instance:IsA('BasePart') and instance.Name~='ArmPhysicsCollider' and instance.CollisionGroup=='Default' then
            instance.CollisionGroup=BODY_GROUP
        end
    end
    for _,instance in character:GetDescendants() do markBody(instance) end
    local bodyConnection=character.DescendantAdded:Connect(markBody)
    for _,v in character:GetDescendants() do
        if v:IsA('AnimationConstraint') and v:GetAttribute('HybridArmJoint') then table.insert(joints,v) end
    end
    for _,side in {'Left','Right'} do
        for _,suffix in {'UpperArm','LowerArm','Hand'} do
            local part=character:WaitForChild(side..suffix,10)
            if not part then bodyConnection:Disconnect();return end
            local collider=Instance.new('Part')
            collider.Name='ArmPhysicsCollider'
            collider.Transparency=1;collider.Massless=true;collider.CanTouch=false;collider.CanQuery=false
            collider.CollisionGroup=ARM_GROUP
            collider.CustomPhysicalProperties=PhysicalProperties.new(.3,.15,0)
            if suffix=='Hand' then
                collider.Shape=Enum.PartType.Ball;collider.Size=part.Size*.9;collider.CFrame=part.CFrame
            else
                local startName=suffix=='UpperArm' and 'Shoulder' or 'Elbow'
                local endName=suffix=='UpperArm' and 'Elbow' or 'Wrist'
                local a=part:FindFirstChild(side..startName..'RigAttachment').WorldPosition
                local b=part:FindFirstChild(side..endName..'RigAttachment').WorldPosition
                collider.Shape=Enum.PartType.Cylinder
                collider.Size=Vector3.new((b-a).Magnitude,.25,.25)
                collider.CFrame=CFrame.lookAt((a+b)/2,b)*CFrame.Angles(0,math.pi/2,0)
            end
            collider.Parent=part
            local weld=Instance.new('WeldConstraint');weld.Part0=part;weld.Part1=collider;weld.Parent=collider
            table.insert(colliders,collider)
        end
    end
    -- Owner 2026-10-29 'everything loads at the same time on spawn': no NoCollisionConstraints any more. Every collider
    -- was paired with every body part (~670 constraints per character, created at spawn, replicated to all players and
    -- copied by every character clone: lobby board avatar, first-person hands). They did nothing: the colliders never
    -- collide (update() keeps physical=false) and the ARM / BODY collision groups above already exclude each other.
    if player.Character==character then
        rigs[player]={character=character,humanoid=humanoid,root=root,colliders=colliders,joints=joints,bodyConnection=bodyConnection,quiet=0}
        -- The owner's Animator also drives the physical arm targets. Pin all six
        -- loose assemblies to that player so a nearby player cannot take them over.
        for _,side in {'Left','Right'} do
            for _,suffix in {'UpperArm','LowerArm','Hand'} do
                local limb=character[side..suffix]
                local canOwn=limb:CanSetNetworkOwnership()
                if canOwn then limb:SetNetworkOwner(player) end
            end
        end
        update(player)
        humanoid.Died:Connect(function() if rigs[player] and rigs[player].character==character then update(player) end end)
    else
        bodyConnection:Disconnect()
    end
end
RunService.Heartbeat:Connect(function(dt)
    for player,rig in rigs do
        local velocity=rig.root.AssemblyLinearVelocity
        local horizontal=Vector3.new(velocity.X,0,velocity.Z).Magnitude
        local calm=rig.humanoid.Health>0 and not player:GetAttribute('Hiding')
            and rig.humanoid.MoveDirection.Magnitude<.02
            and horizontal<.35 and math.abs(rig.root.AssemblyAngularVelocity.Y)<.3
        rig.quiet=calm and math.min(rig.quiet+math.min(dt,.1),1) or 0
        update(player)
    end
end)
local function join(player)
    player.CharacterAdded:Connect(function(character) characterAdded(player,character) end)
    player.CharacterRemoving:Connect(function(character) if rigs[player] and rigs[player].character==character then rigs[player].bodyConnection:Disconnect();rigs[player]=nil end end)
    player:GetAttributeChangedSignal('Hiding'):Connect(function() update(player) end)
    if player.Character then task.spawn(characterAdded,player,player.Character) end
end
Players.PlayerAdded:Connect(join)
Players.PlayerRemoving:Connect(function(player) if rigs[player] then rigs[player].bodyConnection:Disconnect() end;rigs[player]=nil end)
for _,player in Players:GetPlayers() do join(player) end