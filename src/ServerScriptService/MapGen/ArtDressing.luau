local F=require(script.Parent.Furnisher)
local A={}
local checker={Foyer=true,Hall=true,Kitchen=true,Pantry=true,Bath=true,Laundry=true,Conservatory=true,Stair=false}
function A.Floor(plan,room,model) if plan.mapKind=='Mall' or plan.mapKind=='Cruise' or plan.mapKind=='Hospital' or plan.mapKind=='School' or plan.mapKind=='Hotel' then return end -- MallDressing textures the terrazzo floor
 if plan.mapKind=='Birthday' then -- clean pastel vinyl: the BirthdayVinyl variants had orange-red smudges (red rule, 2026-10-21)
  local sum=plan.seed;for i=1,#room.name do sum+=room.name:byte(i) end
  local tones={Color3.fromRGB(198,226,212),Color3.fromRGB(204,216,236),Color3.fromRGB(236,228,208)}
  for _,p in ipairs(model:GetChildren()) do if p:IsA('BasePart') and p~=model.PrimaryPart then p.Color=tones[sum%3+1];p.Material=Enum.Material.SmoothPlastic;p.MaterialVariant='';if p:IsA('MeshPart') then p.TextureID='' end end end
  return
 end
 local code=plan.mapKind=='Dungeon' and 'F_DungeonFlagstone' or plan.mapKind=='Birthday' and 'F_BirthdayVinyl' or checker[room.type] and 'F_MansionChecker' or 'F_MansionParquet'
 local sum=plan.seed;for i=1,#room.name do sum+=room.name:byte(i) end
 local variant=game.MaterialService:FindFirstChild('Horror_'..code..(sum%2==0 and '_A' or '_B'));if plan.mapKind=='Dungeon' then variant=game.MaterialService:FindFirstChild('Horror_DungeonMatte') end;if not variant then return end
 for _,p in ipairs(model:GetChildren()) do if p:IsA('BasePart') and p~=model.PrimaryPart then p.Color=Color3.new(1,1,1);p.Material=variant.BaseMaterial;p.MaterialVariant=variant.Name;if p:IsA('MeshPart') then p.TextureID='' end end end
end
local function overlap(a,b,pad)
 return math.abs(a.x-b.x)<(a.w+b.w)/2+(pad or 0) and math.abs(a.z-b.z)<(a.d+b.d)/2+(pad or 0)
end
local function legal(a,r,keep,placed)
 if a.x-a.w/2<r.x1+.69 or a.x+a.w/2>r.x2-.69 or a.z-a.d/2<r.z1+.69 or a.z+a.d/2>r.z2-.69 then return false end
 for _,b in ipairs(keep) do if overlap(a,b,.15) then return false end end
 for _,b in ipairs(placed) do if overlap(a,b,.35) or b.front and overlap(a,b.front,.2) then return false end end
 if a.tall then for _,b in ipairs(r.windowKeepouts or {}) do if overlap(a,b,.1) then return false end end end
 return true
end
function A.Decorate(plan,mansion)
 local kit=game.ServerStorage:FindFirstChild('ClaudeArtKit');if not kit then return end
 local pool={};for _,m in ipairs(kit:GetChildren()) do local s=game.HttpService:JSONDecode(m:GetAttribute('Spec'));if s.map==plan.mapKind and s.placement~='floor-module' then table.insert(pool,{model=m,spec=s}) end end
 table.sort(pool,function(a,b)return a.spec.name<b.spec.name end)
 local rng=Random.new(plan.seed+137891);local count,meshCount,proxyCount=0,0,0;local used={}
 for _,room in ipairs(plan.rooms) do
  if room.type=='Stair' or room.type=='Hall' then continue end
  local keep=F.Keepouts(plan,room);local placed={};for _,a in ipairs(plan.placements) do if a.room==room.name then table.insert(placed,a) end end
  local options={};for _,entry in ipairs(pool) do local s=entry.spec;if table.find(s.roomTypes,room.type) or table.find(s.roomTypes,'*') then table.insert(options,entry) end end
  -- Prefer underused pieces; this yields a varied kit without forcing unsafe placements.
  for _,e in ipairs(options) do e.rank=(used[e.spec.name] or 0)+rng:NextNumber() end
  table.sort(options,function(a,b)return a.rank<b.rank end)
  local roomCount=0
  for _,entry in ipairs(options) do
   if roomCount>=1 then break end
   local s,template=entry.spec,entry.model;local cost=s.meshParts
   if meshCount+cost>180 then continue end
   local size=Vector3.new(unpack(s.bounds.size));local min=Vector3.new(unpack(s.bounds.min));local max=Vector3.new(unpack(s.bounds.max));local offset=(min+max)/2
   local candidates={};local wall=s.wallSide or s.placement=='floor-wall' or s.placement=='ceiling-corner'
   for _,angle in ipairs({0,90,180,270}) do
    local rotation=CFrame.Angles(0,math.rad(angle),0);local shifted=rotation:VectorToWorldSpace(offset)
    local w,d=angle%180==0 and size.X or size.Z,angle%180==0 and size.Z or size.X
    local xs,zs={},{}
    for x=room.x1+w/2+.71,room.x2-w/2-.71,2 do table.insert(xs,x) end
    for z=room.z1+d/2+.71,room.z2-d/2-.71,2 do table.insert(zs,z) end
    if wall then
     if angle==0 then zs={room.z2-d/2-.71} elseif angle==90 then xs={room.x2-w/2-.71} elseif angle==180 then zs={room.z1+d/2+.71} else xs={room.x1+w/2+.71} end
    end
    if s.placement=='ceiling-corner' then
     if angle%180==0 then xs={room.x1+w/2+.71,room.x2-w/2-.71} else zs={room.z1+d/2+.71,room.z2-d/2-.71} end
    end
    for _,x in ipairs(xs) do for _,z in ipairs(zs) do
     local a={x=x,z=z,w=w,d=d,angle=angle,room=room.name,level=room.level,name=room.name..'_Art_'..s.name,template=s.name,optional=true,tall=s.tall}
     local supported=true
     if s.placement=='wall-mounted'then
      supported=false
      local mount=CFrame.new(x-shifted.X,room.level*16,z-shifted.Z)*rotation
      local back=mount*Vector3.new(offset.X,offset.Y,max.Z)
      for _,wallModel in ipairs(mansion.Architecture:GetChildren())do
       if wallModel:IsA('Model')and wallModel.Name=='Wall'then
        local wallpaper=wallModel:FindFirstChild('Wallpaper')
        if wallpaper then
         local lp=wallpaper.CFrame:PointToObjectSpace(back)
         local across=math.abs(wallpaper.CFrame.RightVector:Dot(rotation.RightVector))
         if across>.99 and math.abs(lp.X)+size.X/2+.4<wallpaper.Size.X/2 and math.abs(lp.Z)<1.2 and math.abs(lp.Y)+size.Y/2<wallpaper.Size.Y/2 then supported=true;break end
        end
       end
      end
     end
     if supported and legal(a,room,keep,placed) then a.cf=CFrame.new(x-shifted.X,room.level*16,z-shifted.Z)*rotation;table.insert(candidates,a) end
    end end
   end
   if #candidates==0 then continue end
   local a=candidates[rng:NextInteger(1,#candidates)];local model=template:Clone();model.Name=a.name;model:PivotTo(a.cf);model:SetAttribute('Room',room.name);model.Parent=mansion.Furniture
   for _,p in ipairs(model:GetDescendants()) do if p:IsA('BasePart') then p.CanCollide=false;p.CanQuery=false;p.CanTouch=false;p.Anchored=true;p:SetAttribute('Room',room.name) end end
   for _,c in ipairs(s.collision) do
    local p=Instance.new('Part');p.Name='ArtCollision_'..c.name;p.Size=Vector3.new(unpack(c.size));p.CFrame=a.cf*CFrame.new(unpack(c.position));p.Anchored=true;p.Transparency=1;p.CanCollide=true;p.CanQuery=true;p.CanTouch=false;p:SetAttribute('Room',room.name);p.Parent=model;proxyCount+=1
   end
   a.cf=nil;table.insert(plan.placements,a);table.insert(placed,a);count+=1;roomCount+=1;meshCount+=cost;used[s.name]=(used[s.name] or 0)+1
  end
 end
 mansion:SetAttribute('ArtDetails',count);mansion:SetAttribute('ArtMeshParts',meshCount);mansion:SetAttribute('ArtCollisionProxies',proxyCount);mansion:SetAttribute('ArtTemplatesUsed',game.HttpService:JSONEncode(used));mansion:SetAttribute('FinalArtVersion',1)
end
return A
