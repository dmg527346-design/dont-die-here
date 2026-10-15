-- Portable fly geometry. No ephemeral EditableMesh content or mesh API permissions.
local M={}
local DARK=Color3.fromRGB(29,34,27)
local function part(m,name,size,cf,color,shape,transparency)
 local p=Instance.new('Part');p.Name=name;p.Size=size;p.CFrame=cf;p.Color=color
 p.Shape=shape or Enum.PartType.Block;p.Material=Enum.Material.SmoothPlastic;p.Transparency=transparency or 0
 p.Anchored=true;p.Massless=true;p.CanCollide=false;p.CanTouch=false;p.CanQuery=false;p.CastShadow=false;p.Parent=m
 if m.PrimaryPart and p~=m.PrimaryPart then local w=Instance.new('WeldConstraint');w.Part0=m.PrimaryPart;w.Part1=p;w.Parent=p end
 return p
end
local function rod(m,name,a,b,width,color)
 local delta=b-a
 return part(m,name,Vector3.new(delta.Magnitude,width,width),CFrame.lookAt((a+b)/2,b)*CFrame.Angles(0,math.pi/2,0),color,Enum.PartType.Cylinder)
end
function M.PopulateJar()
 local SS=game.ServerStorage;local fly=SS.CursedAccessoryKit.AnnoyingFly;local jar=SS.CursedItemKit.FlyJar
 for _,p in jar:GetChildren()do if p:IsA('BasePart')and(p.Name:find('Fly')or p.Name=='Antenna')then p:Destroy()end end
 for _,p in fly:GetChildren()do if p:IsA('BasePart')and p~=fly.PrimaryPart then
  local c=p:Clone();for _,w in c:GetChildren()do if w:IsA('WeldConstraint')then w:Destroy()end end
  c.CFrame=jar:GetPivot()*CFrame.new(0,-.06,0)*fly:GetPivot():ToObjectSpace(p.CFrame);c.Parent=jar
  local w=Instance.new('WeldConstraint');w.Part0=jar.PrimaryPart;w.Part1=c;w.Parent=c
 end end
 jar:SetAttribute('DurableFlyGeometryVersion',1)
end
function M.Build()
 local m=game.ServerStorage.CursedAccessoryKit.AnnoyingFly
 m:ClearAllChildren();m.WorldPivot=CFrame.identity
 local root=part(m,'Root',Vector3.new(.95,.7,1.1),CFrame.identity,DARK,nil,1);m.PrimaryPart=root
 part(m,'FlyAbdomen',Vector3.new(.58,.46,.72),CFrame.new(0,0,-.12),Color3.fromRGB(33,41,28),Enum.PartType.Ball)
 part(m,'FlyThorax',Vector3.new(.4,.38,.36),CFrame.new(0,.045,.18),DARK,Enum.PartType.Ball)
 part(m,'FlyHead',Vector3.new(.43,.4,.39),CFrame.new(0,.02,.34),Color3.fromRGB(20,25,19),Enum.PartType.Ball)
 for _,z in {-.36,-.21,-.06}do
  part(m,'FlyAbdomenBand',Vector3.new(.55,.44,.04),CFrame.new(0,0,z),Color3.fromRGB(12,18,13),Enum.PartType.Ball)
 end
 for _,side in {-1,1}do
  part(m,'FlyEye',Vector3.new(.22,.25,.2),CFrame.new(side*.17,.10,.48),Color3.fromRGB(155,39,29),Enum.PartType.Ball)
  part(m,'FlyEyeHighlight',Vector3.new(.065,.075,.035),CFrame.new(side*.19,.15,.571),Color3.fromRGB(229,152,105),Enum.PartType.Ball)
  for row=0,2 do for col=0,2 do
   part(m,'FlyEyeFacet',Vector3.new(.03,.03,.018),CFrame.new(side*.17+(col-1)*.045,.10+(row-1)*.055,.576),Color3.fromRGB(89,20,16),Enum.PartType.Ball)
  end end
  local wingCF=CFrame.new(side*.39,.25,-.14)*CFrame.Angles(0,side*.18,0)
  local wing=part(m,'FlyWing',Vector3.new(.68,.035,.44),wingCF,Color3.fromRGB(191,212,201),Enum.PartType.Ball,.38)
  wing:SetAttribute('FlySide',side);wing:SetAttribute('FlyWingRest',wingCF)
  for i=1,3 do
   local a=Vector3.new(side*.15,.268,-.02);local b=Vector3.new(side*(.45+i*.055),.268,-.31+i*.07)
   local vein=rod(m,'FlyWingVein',a,b,.012,Color3.fromRGB(88,108,92))
   vein:SetAttribute('FlySide',side);vein:SetAttribute('FlyWingLocal',wingCF:ToObjectSpace(vein.CFrame))
  end
  for i=1,3 do
   local z=.34-i*.2
   local a=Vector3.new(side*.16,-.10,z);local knee=Vector3.new(side*.32,-.2,z-.03);local foot=Vector3.new(side*.43,-.32,z+.08)
   rod(m,'FlyLeg',a,knee,.027,DARK);rod(m,'FlyLeg',knee,foot,.023,DARK)
   part(m,'FlyFoot',Vector3.new(.055,.026,.085),CFrame.new(foot),DARK,Enum.PartType.Ball)
  end
  rod(m,'Antenna',Vector3.new(side*.1,.19,.46),Vector3.new(side*.16,.36,.55),.024,DARK)
  part(m,'FlyAntennaTip',Vector3.new(.045,.045,.045),CFrame.new(side*.16,.36,.55),DARK,Enum.PartType.Ball)
 end
 m:SetAttribute('DurableFlyGeometryVersion',1);m:SetAttribute('ModelAuthor','Portable native fly geometry')
 M.PopulateJar()
 return m
end
return M