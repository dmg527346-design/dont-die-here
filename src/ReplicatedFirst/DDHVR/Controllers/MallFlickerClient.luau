-- VR-only version of the existing owner. Original source remains untouched.
return function(script, VRSupport)
-- Live servers (owner 2026-10-27): Mall is out of the map pool, so the flicker loop stays off there (MapGen publishes the pool
-- as the ReplicatedStorage attribute MapPool). Studio keeps it for forced-map tests; no pool after 15 s = run as before.
do local RS_=game:GetService('ReplicatedStorage');local pool,t0=RS_:GetAttribute('MapPool'),os.clock();if not game:GetService('RunService'):IsStudio()then while pool==nil and os.clock()-t0<15 do task.wait(.5);pool=RS_:GetAttribute('MapPool')end;if pool and not table.find(string.split(pool,','),'Mall')then return end end end
-- Mall only: dying fluorescent tubes and store signs stutter (client-side, cosmetic, near the camera only).
local CollectionService=game:GetService('CollectionService')
local RunService=game:GetService('RunService')
local TAG='MallFlicker'
local state={}
local function setOn(p,on)
 local light=p:FindFirstChildWhichIsA('Light')
 if light then
  light.Enabled=on
  p.Material=on and Enum.Material.Neon or Enum.Material.SmoothPlastic
  p.Transparency=on and .12 or 0
  p.Color=on and Color3.fromRGB(236,230,196) or Color3.fromRGB(150,147,132)
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
    if s.on then s.on=false;s.next=now+(math.random()<.7 and math.random()*.12+.04 or math.random()*.9+.2)
    else s.on=true;s.next=now+(math.random()<.6 and math.random()*.25+.05 or math.random()*5+1.5) end
    setOn(p,true) -- Stable fluorescent lighting in VR.
   end
  end
 end
end)
CollectionService:GetInstanceRemovedSignal(TAG):Connect(function(p) state[p]=nil end)

end
