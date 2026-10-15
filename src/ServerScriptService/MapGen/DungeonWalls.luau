local D={}
function D.Apply(mansion)
 if mansion:GetAttribute('MapKind')~='Dungeon' or mansion:GetAttribute('SculptedWalls') then return end
 local kit=game.ServerStorage:FindFirstChild('DungeonMasonryKit');if not kit then return end
 local count=0
 for _,wall in ipairs(mansion.Architecture:GetChildren()) do
  if not wall:IsA('Model') or (wall.Name~='Wall' and wall.Name~='WallDoor' and wall.Name~='WallWindow') then continue end
  local surfaces=wall:GetChildren()
  for _,p in ipairs(surfaces) do if p:IsA('BasePart') then
   local span=p.Name=='Wallpaper' or p.Name=='Jamb' or p.Name=='Header' or p.Name=='Above' or p.Name=='Below'
   if span then
    p.Transparency=1;p.CanCollide=false;p.CanQuery=false
    local backing=Instance.new('Part');backing.Name='RecessedMortar';backing.Size=Vector3.new(p.Size.X,p.Size.Y,1.08);backing.CFrame=p.CFrame;backing.Color=Color3.fromRGB(35,37,34);backing.Material=Enum.Material.SmoothPlastic;backing.Anchored=true;backing.CanCollide=false;backing.CanQuery=true;backing.CanTouch=false;backing:SetAttribute('DungeonBlocks',true);backing.Parent=wall
    local name='MasonryPanel';if p.Name=='Jamb' then name='MasonryJamb' elseif p.Name=='Header' or p.Name=='Below' then name='MasonryHeader' elseif p.Name=='Above' then name='MasonryCap' end
    local template=kit[name]
    local width,height=template:GetAttribute('Width'),template:GetAttribute('Height');local n=math.max(1,math.ceil(p.Size.X/width));local tile=p.Size.X/n
    for i=1,n do local model=template:Clone();local root=model.PrimaryPart;local pose=p.CFrame*CFrame.new(-p.Size.X/2+tile*(i-.5),-p.Size.Y/2,0)
     for _,part in ipairs(model:GetChildren()) do if part:IsA('MeshPart') then local localCF=root.CFrame:ToObjectSpace(part.CFrame);local pos=localCF.Position;part.Size=Vector3.new(part.Size.X*tile/width,part.Size.Y*p.Size.Y/height,part.Size.Z);part.CFrame=pose*CFrame.new(pos.X*tile/width,pos.Y*p.Size.Y/height,pos.Z)*localCF.Rotation;part:SetAttribute('Room',p:GetAttribute('Room'));part.Parent=wall;count+=1 end end
     model:Destroy()
    end
   elseif p.Name=='Wainscot' or p.Name=='Trim' then p.Transparency=1;p.CanCollide=false;p.CanQuery=false end
  end end
 end
 mansion:SetAttribute('SculptedWalls',true);mansion:SetAttribute('MasonryMeshParts',count)
end
return D