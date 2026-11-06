-- VR-only version of the existing owner. Original source remains untouched.
return function(script, VRSupport)
local Players=game:GetService('Players')
local Run=game:GetService('RunService')
local p=Players.LocalPlayer
local views={}
local function copyPart(source,world)
 local ok,c=pcall(function()return source:Clone()end)
 if not ok or not c then return end
 for _,d in c:GetDescendants() do
  if d:IsA('BasePart') or d:IsA('LuaSourceContainer') or d:IsA('JointInstance') or d:IsA('Constraint') or d:IsA('Sound') or d:IsA('LayerCollector') then d:Destroy() end
 end
 c.Anchored=true;c.CanCollide=false;c.CanTouch=false;c.CanQuery=false;c.LocalTransparencyModifier=0;c.Parent=world
 return {source=source,part=c}
end
local function create(m)
 local surface=m:FindFirstChild('MirrorSurface')
 if not surface then return end
 local gui=Instance.new('SurfaceGui');gui.Name='LiveMirror';gui.Adornee=surface;gui.Face=Enum.NormalId.Front;gui.SizingMode=Enum.SurfaceGuiSizingMode.FixedSize;gui.CanvasSize=Vector2.new(384,512);gui.LightInfluence=0;gui.Brightness=1;gui.Parent=p:WaitForChild('PlayerGui')
 local v=Instance.new('ViewportFrame');v.Size=UDim2.fromScale(1,1);v.BackgroundColor3=Color3.fromRGB(22,27,32);v.Ambient=Color3.fromRGB(185,185,185);v.LightColor=Color3.fromRGB(220,220,220);v.LightDirection=Vector3.new(-1,-1,-1);v.Parent=gui
 local w=Instance.new('WorldModel');w.Parent=v
 local camera=Instance.new('Camera');camera.Parent=v;v.CurrentCamera=camera
 local state={model=m,surface=surface,gui=gui,world=w,camera=camera,parts={},mapClones={},bodyClones={},rebuilt=-100}
 views[m]=state;return state
end
-- Map BaseParts are listed once per map and refreshed at most every 10 s (a live map changes constantly, and
-- re-listing thousands of parts on every change was the mirror's main lag).
local mapCache={map=nil,parts=nil,at=0}
local function mapParts(map)
 if mapCache.map~=map or not mapCache.parts or os.clock()-mapCache.at>10 then
  local parts={};for _,x in map:GetDescendants() do if x:IsA('BasePart') then table.insert(parts,x) end end
  mapCache.map=map;mapCache.parts=parts;mapCache.at=os.clock()
 end
 return mapCache.parts
end
-- The nearest 160 map parts are re-ranked every rebuild, but clones of parts that stay selected are kept instead of
-- recloned. Character parts are recloned each time so appearance changes still show in the reflection.
local function rebuild(s)
 local pos=s.surface.Position
 local candidates={}
 local map=workspace:FindFirstChild('Mansion')
 if map then for _,x in mapParts(map) do
  if x.Parent and not x:IsDescendantOf(s.model) and x.Transparency<1 and (x.Position-pos).Magnitude<35+x.Size.Magnitude*.5 then table.insert(candidates,x) end
 end end
 local apparition=workspace:FindFirstChild('FearMirrorApparition')
 if s.model:GetAttribute('ItemId')=='FearMirror' and apparition then for _,x in apparition:GetDescendants()do if x:IsA('BasePart')then table.insert(candidates,x)end end end
 table.sort(candidates,function(a,b)return (a.Position-pos).Magnitude<(b.Position-pos).Magnitude end)
 local keep={};s.parts={}
 for i=1,math.min(#candidates,110) do
  local source=candidates[i];local pair=s.mapClones[source]
  if not pair or not pair.part.Parent then pair=copyPart(source,s.world) end
  if pair then keep[source]=pair;table.insert(s.parts,pair) end
 end
 for source,pair in s.mapClones do if keep[source]~=pair then pair.part:Destroy() end end
 s.mapClones=keep
  if os.clock()-(s.bodiesAt or -100)<3 and #s.bodyClones>0 then
  for _,pair in s.bodyClones do table.insert(s.parts,pair) end
  s.rebuilt=os.clock();s.position=pos;s.gui:SetAttribute('ReflectedParts',#s.parts);return
 end
 s.bodiesAt=os.clock()
 for _,pair in s.bodyClones do pair.part:Destroy() end
 s.bodyClones={}
 for _,pl in Players:GetPlayers()do if pl.Character and pl.Character:FindFirstChild('Head') and (pl.Character.Head.Position-pos).Magnitude<40 then
  for _,x in pl.Character:GetDescendants() do if x:IsA('BasePart') and x.Name~='HumanoidRootPart' then local c=copyPart(x,s.world);if c then table.insert(s.parts,c);table.insert(s.bodyClones,c)end end end
 end end
 s.rebuilt=os.clock();s.position=pos;s.gui:SetAttribute('ReflectedParts',#s.parts)
end
local scan=0
Run.RenderStepped:Connect(function(dt)
 local cam=workspace.CurrentCamera;if not cam then return end
 scan+=dt
 if scan>.5 then scan=0
  local map=workspace:FindFirstChild('Mansion')
  local interactive=map and map:FindFirstChild('Interactive')
  if interactive then for _,m in interactive:GetChildren() do if (m:GetAttribute('ItemId')=='Mirror'or m:GetAttribute('ItemId')=='FearMirror') and m.PrimaryPart and (m.PrimaryPart.Position-VRSupport.Head().Position).Magnitude<35 and not views[m] then create(m) end end end
 end
 for m,s in views do
  if not m.Parent then s.gui:Destroy();views[m]=nil;continue end
  -- A held mirror is drawn by CursedItemsClient as HeldVisual_<name> (the real one is hidden): reflect on what is visible.
  -- Only the local holder has a HeldVisual copy of this exact mirror (one held item at a time).
  local heldFolder=m:GetAttribute('HeldBy')==p.UserId and workspace:FindFirstChild('HeldItemVisuals');local heldCopy=heldFolder and heldFolder:FindFirstChild('HeldVisual_'..m.Name)
  local shown=(heldCopy and heldCopy:FindFirstChild('MirrorSurface'))or m:FindFirstChild('MirrorSurface')
  if not shown or not shown:IsA('BasePart')or not shown.Parent then s.gui.Enabled=false;continue end
  if s.surface~=shown then
   s.surface=shown;s.gui.Adornee=shown;s.rebuilt=-100;s.position=nil
  elseif s.gui.Adornee~=shown then s.gui.Adornee=shown end
  if (shown.Position-VRSupport.Head().Position).Magnitude>45 then s.gui:Destroy();views[m]=nil;continue end
  local plane=s.surface.CFrame*CFrame.new(0,0,-s.surface.Size.Z*.5)
  local normal=plane.LookVector;local distance=(VRSupport.Head().Position-plane.Position):Dot(normal)
  s.gui.Enabled=distance>.05
  if not s.gui.Enabled then continue end
  if os.clock()-s.rebuilt>(s.model:GetAttribute('ItemId')=='FearMirror' and .5 or 3) or not s.position or (s.position-plane.Position).Magnitude>7 then rebuild(s)end
  local eye=VRSupport.Head().Position-2*normal*distance
  s.camera.CFrame=CFrame.lookAt(eye,plane.Position,plane.UpVector)
  s.camera.FieldOfView=math.clamp(math.deg(2*math.atan(s.surface.Size.Y*.5/math.max(distance,.1))),10,110)
  s.syncTick=((s.syncTick or 0)+1)%6
  local bodySet=s.bodySet or {};if s.bodySetFor~=s.bodyClones then bodySet={};for _,b in s.bodyClones do bodySet[b]=true end;s.bodySet=bodySet;s.bodySetFor=s.bodyClones end
  for _,pair in s.parts do if not bodySet[pair] and s.syncTick~=0 then continue end
  if pair.source.Parent then
   pair.part.CFrame=pair.source.CFrame;pair.part.Size=pair.source.Size;pair.part.Color=pair.source.Color;pair.part.Transparency=pair.source.Transparency
   if pair.part.Material~=pair.source.Material then pair.part.Material=pair.source.Material end
  else pair.part.Transparency=1 end end
  s.gui:SetAttribute('ReflectionReady',true)
 end
end)
local lastCycle={}
Run.Heartbeat:Connect(function()
 local time=workspace:GetServerTimeNow()
 for _,pl in Players:GetPlayers() do
  local c=pl.Character;local t=time+pl.UserId%7*.17;local cycle=math.floor(t/4.5);local phase=t%4.5
  if pl:GetAttribute('CursedActive')=='Mirror' and c and c:GetAttribute('MirrorSpeaking')~=true and phase>1.45 and phase<1.85 and lastCycle[pl]~=cycle then
   lastCycle[pl]=cycle
   local mouth=c:FindFirstChild('ConnectedLips',true);local root=c:FindFirstChild('HumanoidRootPart')
   if mouth and root then
    local heart=Instance.new('Part');heart.Name='BlownKiss';heart.Size=Vector3.one*.02;heart.Anchored=true;heart.Transparency=1;heart.CanCollide=false;heart.CanQuery=false;heart.CanTouch=false;heart.CastShadow=false;heart.Parent=workspace
    local g=Instance.new('BillboardGui');g.Size=UDim2.fromOffset(28,28);g.Adornee=heart;g.Parent=heart
    local label=Instance.new('TextLabel');label.Size=UDim2.fromScale(1,1);label.BackgroundTransparency=1;label.Text='♥';label.TextColor3=Color3.fromRGB(255,111,166);label.TextStrokeTransparency=.4;label.TextScaled=true;label.Parent=g
    local origin=mouth.Position;local direction=root.CFrame.LookVector
    task.spawn(function()local born=os.clock();while heart.Parent and os.clock()-born<.85 and pl:GetAttribute('CursedActive')=='Mirror' do local age=os.clock()-born;heart.Position=origin+direction*age*3+Vector3.new(0,age*.65,0);label.TextTransparency=age/.85;Run.Heartbeat:Wait()end;heart:Destroy()end)
   end
  end
 end
end)
Players.PlayerRemoving:Connect(function(pl)lastCycle[pl]=nil end)


end
