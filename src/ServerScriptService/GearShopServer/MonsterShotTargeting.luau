-- Server-owned body geometry; registered creature models only, independent of CanQuery.
local T={}
function T.Finite(n)return type(n)=='number'and n==n and math.abs(n)<math.huge end
function T.ValidAim(aim,headPosition)
 if typeof(aim)~='CFrame'then return false end
 for _,n in ipairs({aim:GetComponents()})do if not T.Finite(n)or math.abs(n)>1e7 then return false end end
 local magnitude=aim.LookVector.Magnitude
 return(aim.Position-headPosition).Magnitude<12 and magnitude>.99 and magnitude<1.01
end
function T.BoxEntry(origin,direction,cf,size,radius,range)
 local p=cf:PointToObjectSpace(origin);local d=cf:VectorToObjectSpace(direction)
 local half=size*.5+Vector3.new(radius,radius,radius)
 local enter,leave=0,range
 for _,axis in ipairs({'X','Y','Z'})do
  if math.abs(d[axis])<1e-8 then
   if p[axis]<-half[axis]or p[axis]>half[axis]then return nil end
  else
   local a=(-half[axis]-p[axis])/d[axis];local b=(half[axis]-p[axis])/d[axis]
   if a>b then a,b=b,a end
   enter=math.max(enter,a);leave=math.min(leave,b)
   if enter>leave then return nil end
  end
 end
 if leave<0 or enter>range then return nil end
 local at=origin+direction*enter;local q=cf:PointToObjectSpace(at);local bodyHalf=size*.5
 local surface=cf:PointToWorldSpace(Vector3.new(math.clamp(q.X,-bodyHalf.X,bodyHalf.X),math.clamp(q.Y,-bodyHalf.Y,bodyHalf.Y),math.clamp(q.Z,-bodyHalf.Z,bodyHalf.Z)))
 return enter,surface
end
function T.Select(models,origin,direction,range,radius,visible)
 local candidates={}
 for _,model in ipairs(models)do if model.Parent then
  local foundBody=false
  for _,part in ipairs(model:GetDescendants())do
   if part:IsA('BasePart')and part.Transparency<.95 and not part:GetAttribute('GearIgnoreHit')then
    foundBody=true
    if(part.Position-origin):Dot(direction)>=0 then
     local distance,at=T.BoxEntry(origin,direction,part.CFrame,part.Size,radius,range)
     if distance then table.insert(candidates,{model=model,part=part,distance=distance,at=at})end
    end
   end
  end
  if not foundBody then
   local root=model.PrimaryPart or model:FindFirstChild('HumanoidRootPart')or model:FindFirstChildWhichIsA('BasePart',true)
   if root and not root:GetAttribute('GearIgnoreHit')and(root.Position-origin):Dot(direction)>=0 then
    local distance,at=T.BoxEntry(origin,direction,root.CFrame,root.Size,radius,range)
    if distance then table.insert(candidates,{model=model,part=root,distance=distance,at=at})end
   end
  end
 end end
 table.sort(candidates,function(a,b)return a.distance<b.distance end)
 for _,row in ipairs(candidates)do if row.model.Parent and row.part.Parent and visible(row.at)then return row.model,row.at,row.distance end end
 return nil
end
return T
