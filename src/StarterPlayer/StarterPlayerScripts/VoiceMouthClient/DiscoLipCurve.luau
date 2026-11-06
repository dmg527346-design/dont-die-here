local AssetService=game:GetService('AssetService')
local M={}
function M.Create(part)
 local mesh,generated
 local ok,result=pcall(function()
 mesh=AssetService:CreateEditableMeshAsync(part.MeshContent)
 if not mesh then error('Lip editable mesh allocation failed') end
 local vertices={};local halfWidth=0
 for _,id in mesh:GetVertices() do local pos=mesh:GetPosition(id);table.insert(vertices,{id=id,pos=pos});halfWidth=math.max(halfWidth,math.abs(pos.X)) end
 generated=AssetService:CreateMeshPartAsync(Content.fromObject(mesh))
 local size=part.Size
 part:ApplyMesh(generated);part.Size=size;generated:Destroy();generated=nil
 local state={mesh=mesh,vertices=vertices,halfWidth=halfWidth,last=-1}
 function state:Update(blend,sad,wind)
  wind=wind or 0
  sad=sad or 0
  if math.abs(wind-(self.lastWind or 0))<.003 and math.abs(blend-self.last)<.003 and math.abs(sad-(self.lastSad or 0))<.003 and blend~=0 and blend~=1 then return end
  if blend==self.last and sad==(self.lastSad or 0)and wind==(self.lastWind or 0)then return end;self.last=blend;self.lastSad=sad;self.lastWind=wind
  for _,v in self.vertices do
   local p=v.pos
   local center=math.max(0,1-(p.X/self.halfWidth)^2)
   local upper=math.clamp(p.Y/25,0,1)
   -- Fold the upper arch into a shallow U. The lower lip stays authored.
   local down=(p.Y*.65+35*center)*upper
   self.mesh:SetPosition(v.id,Vector3.new(p.X,p.Y-down*blend+(110*center-60)*sad,p.Z-wind*self.halfWidth*.72*math.abs(p.X/self.halfWidth)^1.8))
  end
 end
 function state:Destroy()
  if self.destroyed then return end
  self.destroyed=true;self.mesh:Destroy()
 end
 return state
 end)
 if not ok then
  if generated then generated:Destroy()end
  if mesh then mesh:Destroy()end
  error(tostring(result),2)
 end
 return result
end
return M