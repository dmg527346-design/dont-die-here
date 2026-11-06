--!strict
-- Driven by ItemDraftEffects only: no connections, tasks, remotes, or startup.
-- This module is for the separate Studio draft review. It never moves stored cargo.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Crab = {}
local GRACE = 1.6
local ROAM_SECONDS = 12
local MAX_WAIT_FOR_FLOOR = 6
local SPEED = 3
local MAX_RADIUS = 22
local MAX_STEP = 0.4

type State = {
    model: Model,
    root: BasePart,
    collider: BasePart,
    releasedAt: number,
    began: number?,
    origin: Vector3?,
    heading: Vector3,
    nextTurn: number,
    ownerId: number?,
    random: Random,
    params: RaycastParams,
    attachment: Attachment?,
    align: AlignOrientation?,
    driven: boolean,
    travelled: number,
    previous: Vector3?,
}
local active: {[Model]: State} = {}
local owners: {[Model]: number} = setmetatable({}, {__mode = "k"}) :: any

local function flat(v: Vector3): Vector3
    local h = Vector3.new(v.X, 0, v.Z)
    return h.Magnitude > 0.0001 and h.Unit or Vector3.xAxis
end

local function isCartSurface(part: Instance): boolean
    local cursor: Instance? = part
    while cursor and cursor ~= workspace do
        local kind = cursor:GetAttribute("Kind")
        if kind == "cart" or kind == "boat" then return true end
        cursor = cursor.Parent
    end
    return false
end

-- Do not clear velocities on these transitions. The assembly may already be
-- welded to a cart, hand, creature, or sale assembly when the owner calls us.
local function externallyOwned(m: Model, root: BasePart): boolean
    if not m.Parent or not root.Parent then return true end
    for _, key in ipairs({"CargoStored", "HeldBy", "MonsterCarried", "Selling",
        "AttachedTo", "ItemWearOwner", "FaceOwner", "AdminFrozen"}) do
        if m:GetAttribute(key) then return true end
    end
    if m:FindFirstChild("CargoRetention", true) then return true end
    local assemblyRoot = root.AssemblyRootPart
    if assemblyRoot and not assemblyRoot:IsDescendantOf(m) then return true end
    -- Also catches a retention weld before CargoStored has been set, regardless
    -- of which model owns the joint instance.
    for _, connected in ipairs(root:GetConnectedParts(true)) do
        if not connected:IsDescendantOf(m) then return true end
    end
    return false
end

local function stop(s: State, haltOwnMotion: boolean)
    active[s.model] = nil
    -- Destroy only instances created by this state. Destroying the upright
    -- constraint is safe even after a cargo weld was created.
    if s.align then s.align:Destroy(); s.align = nil end
    if s.attachment then s.attachment:Destroy(); s.attachment = nil end
    if haltOwnMotion and s.driven and not externallyOwned(s.model, s.root) then
        local velocity = s.root.AssemblyLinearVelocity
        s.root.AssemblyLinearVelocity = Vector3.new(0, velocity.Y, 0)
        s.root.AssemblyAngularVelocity = Vector3.zero
    end
    if s.model.Parent then
        s.model:SetAttribute("DraftCrabRoaming", nil)
        s.model:SetAttribute("DraftCrabRoamDistance", s.travelled)
    end
end

local function ownerAlive(s: State): boolean
    if not s.ownerId then return true end
    local player = Players:GetPlayerByUserId(s.ownerId)
    if not player or not player.Parent then return false end
    local character = player.Character
    local humanoid = character and character:FindFirstChildOfClass("Humanoid")
    return humanoid ~= nil and humanoid.Health > 0
end

local function support(s: State, position: Vector3, floorY: number?): RaycastResult?
    local startY = floorY and floorY + 0.9 or position.Y + 0.15
    local depth = floorY and 1.8 or s.collider.Size.Y * 0.5 + 0.9
    local hit = workspace:Raycast(Vector3.new(position.X, startY, position.Z),
        Vector3.new(0, -depth, 0), s.params)
    if not hit or hit.Normal.Y < 0.7 then return nil end
    if floorY and math.abs(hit.Position.Y - floorY) > MAX_STEP then return nil end
    return hit
end

local function safeDirection(s: State, direction: Vector3, floorY: number): boolean
    local collider = s.collider
    local radius = math.max(collider.Size.X, collider.Size.Z) * 0.5
    local reach = 0.7 + SPEED * 0.18
    local castSize = Vector3.new(math.max(0.1, collider.Size.X * 0.98),
        math.max(0.1, collider.Size.Y - 0.15), math.max(0.1, collider.Size.Z * 0.98))
    if workspace:Blockcast(collider.CFrame + Vector3.new(0, 0.08, 0), castSize,
        direction * reach, s.params) then return false end
    -- Test support beyond both front corners before applying any horizontal
    -- motion. Gravity remains in charge of the item's vertical movement.
    local ahead = collider.Position + direction * (radius + 0.55)
    local across = Vector3.new(-direction.Z, 0, direction.X) * math.min(0.45, radius * 0.65)
    for _, point in ipairs({ahead, ahead + across, ahead - across}) do
        local floor = support(s, point, floorY)
        if not floor or isCartSurface(floor.Instance) then return false end
    end
    return true
end

local function directionAfterTurn(direction: Vector3, angle: number): Vector3
    return flat(CFrame.Angles(0, angle, 0):VectorToWorldSpace(direction))
end

local function chooseDirection(s: State, now: number, floorY: number): Vector3?
    local desired = s.heading
    local origin = s.origin
    if origin and (s.collider.Position - origin).Magnitude > MAX_RADIUS then
        desired = flat(origin - s.collider.Position)
    elseif now >= s.nextTurn then
        desired = directionAfterTurn(desired, math.rad(s.random:NextNumber(-38, 38)))
        s.nextTurn = now + s.random:NextNumber(1.8, 3.0)
    end
    if safeDirection(s, desired, floorY) then return desired end
    local side = s.random:NextInteger(0, 1) == 0 and -1 or 1
    for _, degrees in ipairs({45 * side, -45 * side, 90 * side, -90 * side, 135 * side, -135 * side, 180}) do
        local candidate = directionAfterTurn(desired, math.rad(degrees))
        if safeDirection(s, candidate, floorY) then
            s.nextTurn = now + s.random:NextNumber(1.0, 1.8)
            return candidate
        end
    end
    return nil
end

local function beginDriving(s: State, now: number)
    -- The existing quiet-drop owner can anchor all pieces after four seconds.
    -- Only a confirmed free, floor-supported crab may be reactivated.
    if externallyOwned(s.model, s.root) then return end
    for _, part in ipairs(s.model:GetDescendants()) do
        if part:IsA("BasePart") then part.Anchored = false end
    end
    s.collider.CanCollide = true
    pcall(function() s.root:SetNetworkOwner(nil) end)
    local attachment = Instance.new("Attachment")
    attachment.Name = "SelectedCrabWanderUpright"
    attachment:SetAttribute("SelectedCrabWander", true)
    local align = Instance.new("AlignOrientation")
    align.Name = "SelectedCrabWanderUpright"
    align:SetAttribute("SelectedCrabWander", true)
    align.Mode = Enum.OrientationAlignmentMode.OneAttachment
    align.Attachment0 = attachment
    align.MaxTorque = math.clamp(s.root.AssemblyMass * 8000, 20000, 200000)
    align.MaxAngularVelocity = 3.5
    align.Responsiveness = 12
    align.RigidityEnabled = false
    align.CFrame = CFrame.fromMatrix(Vector3.zero, s.heading, Vector3.yAxis,
        s.heading:Cross(Vector3.yAxis))
    attachment.Parent = s.root
    align.Parent = s.root
    s.attachment, s.align = attachment, align
    s.began = now
    s.origin = s.collider.Position
    s.previous = s.collider.Position
    s.driven = true
    s.model:SetAttribute("DraftCrabRoaming", true)
end

local function wakeQuietDrop(s: State)
    if externallyOwned(s.model, s.root) then return end
    for _, part in ipairs(s.model:GetDescendants()) do
        if part:IsA("BasePart") then part.Anchored = false end
    end
    s.collider.CanCollide = true
    pcall(function() s.root:SetNetworkOwner(nil) end)
end

function Crab.Release(m: Model, now: number, owner: Player?): boolean
    if m:GetAttribute("SelectedItem") ~= true
        or m:GetAttribute("ItemId") ~= "WindUpCrabToy" then return false end
    local prior = active[m]
    if prior then stop(prior, true) end
    local root = m.PrimaryPart
    local collider = m:FindFirstChild("ItemGroundCollider")
    if not m.Parent or not root or not collider or not collider:IsA("BasePart") then return false end
    -- ReleaseHold is called synchronously before CursedItemsServer clears
    -- HeldBy. Queue now; the passive grace lets the normal detach finish.
    if m:GetAttribute("CargoStored") or m:FindFirstChild("CargoRetention", true)
        or m:GetAttribute("Selling") or m:GetAttribute("MonsterCarried") then return false end
    local ownerId = owner and owner.UserId or owners[m]
        or (m:GetAttribute("HeldBy") :: number?) or (m:GetAttribute("LastOwner") :: number?)
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    params.FilterDescendantsInstances = {m}
    params.RespectCanCollide = true
    params.IgnoreWater = false
    active[m] = {
        model = m, root = root, collider = collider,
        releasedAt = now, began = nil, origin = nil,
        heading = flat(root.CFrame.RightVector), nextTurn = now + GRACE + 2.3,
        ownerId = ownerId, random = Random.new(math.floor(now * 1000) % 2147483647),
        params = params, attachment = nil, align = nil, driven = false,
        travelled = 0, previous = nil,
    }
    return true
end

function Crab.Pickup(m: Model, owner: Player?)
    local s = active[m]
    if s then stop(s, false) end
    local ownerId = owner and owner.UserId or (m:GetAttribute("HeldBy") :: number?)
        or (m:GetAttribute("LastOwner") :: number?)
    if ownerId then owners[m] = ownerId end
end

function Crab.Frame(_dt: number, now: number)
    for _, s in pairs(active) do
        if externallyOwned(s.model, s.root) or not s.collider.Parent then
            stop(s, false)
            continue
        end
        if not ownerAlive(s) then stop(s, true); continue end
        if now < s.releasedAt + GRACE then continue end
        if s.began and now >= s.began + ROAM_SECONDS then stop(s, true); continue end
        if not s.began and now > s.releasedAt + GRACE + MAX_WAIT_FOR_FLOOR then
            stop(s, true)
            continue
        end
        local floor = support(s, s.collider.Position, nil)
        if not floor then
            -- No hovering and no new push while airborne. Remove previous
            -- horizontal drive, preserve vertical velocity, let gravity settle.
            if s.driven then
                local velocity = s.root.AssemblyLinearVelocity
                s.root.AssemblyLinearVelocity = Vector3.new(0, velocity.Y, 0)
            end
            continue
        end
        if isCartSurface(floor.Instance) then stop(s, false); continue end
        local direction = chooseDirection(s, now, floor.Position.Y)
        if not direction then
            if s.driven then
                local velocity = s.root.AssemblyLinearVelocity
                s.root.AssemblyLinearVelocity = Vector3.new(0, velocity.Y, 0)
            end
            continue
        end
        s.heading = direction
        if not s.driven then beginDriving(s, now) end
        if not s.driven then stop(s, false); continue end
        if s.root.Anchored or s.collider.Anchored then wakeQuietDrop(s) end
        -- A free crab scuttles sideways: its local right vector follows travel.
        local align = s.align
        if align then
            align.CFrame = CFrame.fromMatrix(Vector3.zero, direction,
                Vector3.yAxis, direction:Cross(Vector3.yAxis))
        end
        local velocity = s.root.AssemblyLinearVelocity
        local age = now - (s.began or now)
        local scuttleSpeed = SPEED * (0.9 + 0.1 * math.sin(age * 18))
        local target = direction * scuttleSpeed
        -- Reassert a strictly bounded speed instead of accelerating from the
        -- post-contact velocity. Static friction consumed the old18*dt impulse
        -- every frame, leaving a winding crab almost stationary in live play.
        s.root.AssemblyLinearVelocity = Vector3.new(target.X, velocity.Y, target.Z)
        local previous = s.previous
        if previous then
            local moved = s.collider.Position - previous
            s.travelled += Vector3.new(moved.X, 0, moved.Z).Magnitude
        end
        s.previous = s.collider.Position
    end
end

function Crab.ClearPlayer(player: Player)
    for _, s in pairs(active) do
        if s.ownerId == player.UserId then stop(s, true) end
    end
    for model, ownerId in pairs(owners) do
        if ownerId == player.UserId then owners[model] = nil end
    end
end

function Crab.ClearLevel()
    for _, s in pairs(active) do stop(s, true) end
    table.clear(owners)
end

return Crab
