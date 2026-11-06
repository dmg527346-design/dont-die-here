-- Any map: dying fixtures, fluorescent tubes and store signs stutter (client-side, cosmetic, near the camera only).
-- 2026-10-27 (ScareFeel): every map kind now has a few flickering fixtures (MapLighting.darkenFixtures, Hotel/Hospital/
-- School dressing), so the loop runs on every map; with nothing tagged it costs nothing. (It used to return on live
-- servers when 'Mall' was not in ReplicatedStorage.MapPool.)
local CollectionService=game:GetService('CollectionService')
local RunService=game:GetService('RunService')
local TAG='MallFlicker'
local state={}
local looks={} -- each part's lit look, read the first time it flickers
local function setOn(p,on)
 local light=p:FindFirstChildWhichIsA('Light')
 if light then
  local look=looks[p];if not look then look={material=p.Material,color=p.Color,transparency=p.Transparency};looks[p]=look end
  light.Enabled=on
  p.Material=on and look.material or Enum.Material.SmoothPlastic
  p.Transparency=on and look.transparency or 0
  p.Color=on and look.color or look.color:Lerp(Color3.fromRGB(20,18,16),.55)
 end
 for _,g in ipairs(p:GetChildren()) do if g:IsA('SurfaceGui') then
  local label=g:FindFirstChildWhichIsA('TextLabel');g.Brightness=on and 1.4 or .4
  if label then label.TextTransparency=on and 0 or .55 end
 end end
end
local acc=0
RunService.Heartbeat:Connect(function(dt)
 acc+=dt;if acc<1/15 then return end;local step=acc;acc=0
 local cam=workspace.CurrentCamera;if not cam then return end
 local now=os.clock();local origin=cam.CFrame.Position
 for _,p in ipairs(CollectionService:GetTagged(TAG)) do
  if p:IsA('BasePart') and p:IsDescendantOf(workspace) and (p.Position-origin).Magnitude<140 then
   local s=state[p]
   if not s then s={on=true,next=now+math.random()*4};state[p]=s end
   if now>=s.next then
    -- slowest stutter: .15 s off + .35 s on = 2 Hz (scare brief: never above 3 Hz)
    if s.on then s.on=false;s.next=now+(math.random()<.7 and math.random()*.25+.15 or math.random()*.9+.4)
    else s.on=true;s.next=now+(math.random()<.5 and math.random()*.35+.35 or math.random()*5+1.5) end
    setOn(p,s.on)
   end
  end
 end
end)
CollectionService:GetInstanceRemovedSignal(TAG):Connect(function(p) state[p]=nil;looks[p]=nil end)
