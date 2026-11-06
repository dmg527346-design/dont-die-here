-- Confirmed-pickup presentation only. One bounded local burst, no persistent emitter or update loop.
local Debris=game:GetService('Debris')
local M={}
local last=setmetatable({},{__mode='k'})
local active=0
function M.Burst(model)
 local part=model and model.PrimaryPart;local camera=workspace.CurrentCamera
 if not part or not camera or(part.Position-camera.CFrame.Position).Magnitude>70 or active>=12 then return end
 local now=os.clock();if now-(last[model]or -10)<.25 then return end;last[model]=now
 local holder=Instance.new('Part');holder.Name='PickupDustPuff';holder.Size=Vector3.one*.05;holder.Anchored=true;holder.Transparency=1;holder.CanCollide=false;holder.CanTouch=false;holder.CanQuery=false;holder.CastShadow=false;holder.Position=part.Position;holder.Parent=camera
 local e=Instance.new('ParticleEmitter');e.Name='PickupDust';e.Texture='rbxasset://textures/particles/smoke_main.dds';e.Rate=0;e.Lifetime=NumberRange.new(.35,.7);e.Speed=NumberRange.new(2.5,5);e.Drag=6;e.Acceleration=Vector3.new(0,1.5,0);e.SpreadAngle=Vector2.new(180,180);e.Rotation=NumberRange.new(0,360);e.RotSpeed=NumberRange.new(-40,40);e.LightInfluence=.2;e.LightEmission=.08
 e.Color=ColorSequence.new(Color3.fromRGB(229,221,202),Color3.fromRGB(188,185,173));e.Size=NumberSequence.new({NumberSequenceKeypoint.new(0,.5),NumberSequenceKeypoint.new(.4,1.3),NumberSequenceKeypoint.new(1,1.9)});e.Transparency=NumberSequence.new({NumberSequenceKeypoint.new(0,.22),NumberSequenceKeypoint.new(.35,.5),NumberSequenceKeypoint.new(1,1)});e.Parent=holder
 active+=1;holder.Destroying:Once(function()active=math.max(0,active-1)end);e:Emit(18);Debris:AddItem(holder,.9)
end
return M
