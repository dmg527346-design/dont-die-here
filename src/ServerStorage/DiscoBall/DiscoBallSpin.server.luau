local RunService = game:GetService("RunService")
local model = script.Parent
local center = model.PrimaryPart.Position
local angle = 0
RunService.Heartbeat:Connect(function(dt)
	angle += math.rad(25) * dt
	model:PivotTo(CFrame.new(center) * CFrame.Angles(0, angle, 0))
end)
