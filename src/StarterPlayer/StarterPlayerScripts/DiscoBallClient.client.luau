local Preferences=require(game.ReplicatedStorage:WaitForChild('HorrorPreferences'))
local missionPlayer=game:GetService('Players').LocalPlayer
while missionPlayer:GetAttribute('MissionActive')~=true do missionPlayer:GetAttributeChangedSignal('MissionActive'):Wait()end
local Run=game:GetService('RunService')
local map=workspace:WaitForChild('Mansion',math.huge)
while map:GetAttribute('RuntimeReady')~=true do task.wait(.1) end
local items=map:WaitForChild('Interactive')
local visuals={}
local function remove(m)
 local v=visuals[m];if not v then return end
 for _,ray in v.rays do ray.aim:Destroy() end
 v.folder:Destroy();v.origin:Destroy();visuals[m]=nil
end
local function create(m)
 local folder=Instance.new('Folder');folder.Name='DiscoRainbowRays';folder.Parent=workspace
 local origin=Instance.new('Attachment');origin.Name='DiscoRayOrigin';origin.Parent=m.PrimaryPart
 local light=Instance.new('PointLight');light.Name='DiscoFill';light.Range=18;light.Brightness=.7;light.Shadows=false;light.Parent=origin
 local rays={}
 for i=1,12 do
  local part=Instance.new('Part');part.Name='DiscoRayTarget';part.Size=Vector3.one*.05;part.Transparency=1;part.Anchored=true;part.CanCollide=false;part.CanQuery=false;part.CanTouch=false;part.Parent=folder
  local endpoint=Instance.new('Attachment');endpoint.Parent=part
  local beam=Instance.new('Beam');beam.Name='RainbowRay';beam.Attachment0=origin;beam.Attachment1=endpoint;beam.Width0=.035;beam.Width1=.22;beam.FaceCamera=true;beam.LightEmission=1;beam.LightInfluence=0;beam.Transparency=NumberSequence.new(.72);beam.Segments=1;beam.Parent=folder
  local spot=Instance.new('SpotLight');spot.Name='RainbowSpot';spot.Angle=34;spot.Range=30;spot.Brightness=1.6;spot.Shadows=false;spot.Parent=origin
  -- Each light receives its own rotating attachment.
  local aim=Instance.new('Attachment');aim.Name='DiscoAim'..i;aim.Parent=m.PrimaryPart;spot.Parent=aim
  table.insert(rays,{part=part,beam=beam,spot=spot,aim=aim})
 end
 local sparkle=Instance.new('ParticleEmitter');sparkle.Name='DiscoSparkles';sparkle.Texture='rbxasset://textures/particles/sparkles_main.dds';sparkle.Rate=8;sparkle.Lifetime=NumberRange.new(.3,.7);sparkle.Speed=NumberRange.new(1,3);sparkle.SpreadAngle=Vector2.new(180,180);sparkle.LightEmission=1;sparkle.Size=NumberSequence.new({NumberSequenceKeypoint.new(0,.12),NumberSequenceKeypoint.new(1,0)});sparkle.Parent=origin
 local v={folder=folder,origin=origin,rays=rays,light=light,sparkle=sparkle};visuals[m]=v;return v
end
local elapsed=0
Run.Heartbeat:Connect(function(dt)
 elapsed+=dt;if elapsed<.05 then return end;elapsed=0
 local camera=workspace.CurrentCamera;if not camera then return end
 local now=workspace:GetServerTimeNow()
 local vivid=Preferences.Get('FlashingLights')
 for _,m in items:GetChildren() do
  if m:IsA('Model') and m.PrimaryPart and m:GetAttribute('ItemId')=='DiscoBall' then
   local enabled=m:GetAttribute('DiscoPlaying')==true and (camera.CFrame.Position-m.PrimaryPart.Position).Magnitude<100
   if not enabled then remove(m);continue end
   local v=visuals[m] or create(m);local pos=m.PrimaryPart.Position
   local params=RaycastParams.new();params.FilterType=Enum.RaycastFilterType.Exclude
   local ignore={m,v.folder,camera};for _,p in game.Players:GetPlayers() do if p.Character then table.insert(ignore,p.Character) end end;params.FilterDescendantsInstances=ignore
   for i,ray in v.rays do
    local azimuth=(vivid and now*.8 or 0)+(i-1)*math.pi*2/12
    local y=vivid and math.sin(now*.65+i*2.4)*.65 or .2
    local direction=Vector3.new(math.cos(azimuth),y,math.sin(azimuth)).Unit
    local hit=workspace:Raycast(pos,direction*28,params)
    ray.part.Position=hit and hit.Position or pos+direction*28
    ray.beam.Enabled=vivid;ray.spot.Enabled=vivid
    local color=Color3.fromHSV((now*.08+i/12)%1,.85,1)
    ray.beam.Color=ColorSequence.new(color);ray.spot.Color=color
    ray.aim.CFrame=m.PrimaryPart.CFrame:ToObjectSpace(CFrame.lookAt(pos,pos+direction))
   end
   local color=vivid and Color3.fromHSV((now*.08)%1,.8,1) or Color3.fromRGB(186,210,190);v.light.Brightness=vivid and .7 or .25;v.sparkle.Enabled=vivid;v.light.Color=color;v.sparkle.Color=ColorSequence.new(color)
  end
 end
 for m in visuals do if m.Parent~=items or m:GetAttribute('DiscoPlaying')~=true then remove(m) end end
end)
