local U={}
function U.Resolve(kit,name,theme)
 local template=theme and theme.templates and theme.templates[name] or name
 local found=kit:FindFirstChild(template)
 -- Themed maps can install one template at a time while retaining base contracts.
 if not found and (template:sub(1,4)=='Mall' or template:sub(1,6)=='Cruise' or template:sub(1,8)=='Hospital' or template:sub(1,5)=='Hotel' or template:sub(1,6)=='School') then found=kit:FindFirstChild(name) end
 return assert(found,'missing kit '..template)
end
function U.Clone(kit,name,cf,parent,theme)
 local m=U.Resolve(kit,name,theme):Clone()
 m.Name=name
 m:PivotTo(cf);m.Parent=parent
 for _,p in ipairs(m:GetDescendants()) do if p:IsA('BasePart') then
  p.Anchored=true;p.CanTouch=false
  local surface=p:GetAttribute('Surface')
  if theme then
   if surface=='wallpaper' or surface=='stone' or surface=='party' then p.Color=theme.wall;p.Material=theme.wallMaterial or Enum.Material.Plaster
   elseif surface=='wood' then p.Color=theme.wood;p.Material=theme.woodMaterial or Enum.Material.Wood
   elseif surface=='trim' or surface=='rust' then p.Color=theme.trim;p.Material=theme.trimMaterial or Enum.Material.Wood end
  end
 end end
 return m
end
function U.Stretch(m,x,y,z)
 local pivot=m:GetPivot()
 for _,p in ipairs(m:GetDescendants()) do if p:IsA('BasePart') and p~=m.PrimaryPart then
  local localCF=pivot:ToObjectSpace(p.CFrame);local pos=localCF.Position
  p.Size=Vector3.new(p.Size.X*x,p.Size.Y*y,p.Size.Z*z)
  p.CFrame=pivot*CFrame.new(pos.X*x,pos.Y*y,pos.Z*z)*localCF.Rotation
 end end
end
function U.Mover(m,name,cf,kind,parent)
 m.Name=name;m:PivotTo(cf)
 m:SetAttribute('Kind',kind);m:SetAttribute('ClosedPivot',cf);m:SetAttribute('Open',0);m:SetAttribute('Swing',100);m:SetAttribute('Travel',1.12);m.Parent=parent
 return m
end
return U


