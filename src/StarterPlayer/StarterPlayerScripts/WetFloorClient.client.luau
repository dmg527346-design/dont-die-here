-- Existing movement controls; a held server lease adds bounded horizontal inertia.
local Players=game:GetService('Players')
local Run=game:GetService('RunService')
local player=Players.LocalPlayer
local lastCharacter,velocity
Run.PreSimulation:Connect(function(dt)
 local c=player.Character
 local h=c and c:FindFirstChildOfClass('Humanoid')
 local root=c and c:FindFirstChild('HumanoidRootPart')
 local active=h and root and h.Health>0 and player:GetAttribute('MissionActive')==true
  and workspace:GetServerTimeNow()<(player:GetAttribute('WetFloorUntil')or 0)
  and not player:GetAttribute('Hiding')and not player:GetAttribute('MonsterJumpscareActive')
  and not root.Anchored and h.FloorMaterial~=Enum.Material.Air
 if not active then lastCharacter=nil;velocity=nil;return end
 if c~=lastCharacter then
  lastCharacter=c;velocity=Vector3.new(root.AssemblyLinearVelocity.X,0,root.AssemblyLinearVelocity.Z)
 end
 -- Exponential smoothing is frame-rate independent; retain the engine's vertical gravity/jump velocity.
 local desired=h.MoveDirection*math.min(h.WalkSpeed,32)
 local alpha=1-math.exp(-math.clamp(dt,0,.1)*2.2)
 velocity=velocity:Lerp(desired,alpha)
 local current=root.AssemblyLinearVelocity
 -- A wall collision must stop momentum rather than push continuously through it.
 if current.Magnitude<.15 and h.MoveDirection.Magnitude==0 then velocity=Vector3.zero end
 root.AssemblyLinearVelocity=Vector3.new(velocity.X,current.Y,velocity.Z)
end)
