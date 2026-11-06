-- Original spherical eye and closed, double-surface eyelid geometry for the local review.
-- Geometry is authored here; no uploaded face mesh or borrowed swollen-eye shell.
local A=game:GetService('AssetService')
local M={}
local templates
local busy=false
local VERSION=3
local function build(cap)
 local e=A:CreateEditableMesh();assert(e,'Face mesh allocation unavailable')
 local ok,result=pcall(function()
  local normals={}
  local sides,rings=32,cap and 10 or 20
  local maxTheta=cap and math.pi*.5 or math.pi
  local radius=cap and .395 or .375
  local shift=Vector3.new(0,0,cap and radius*.5 or 0)
  local function triangle(x,y,z,inner)
   if inner then y,z=z,y end
   local face=e:AddTriangle(x,y,z)
   e:SetFaceNormals(face,{normals[x],normals[y],normals[z]})
  end
  local function surface(r,inner)
   local function vertex(n)
    local v=e:AddVertex(n*r-shift)
    normals[v]=e:AddNormal(inner and -n or n)
    return v
   end
   -- One exact vertex per pole. Tiny epsilon rings left open boundaries;
   -- fans produce a closed surface with no collapsed triangles or pole holes.
   local north=vertex(Vector3.new(0,0,1))
   local rows={}
   local last=cap and rings or rings-1
   for j=1,last do
    local theta=maxTheta*j/rings;local row={};rows[j]=row
    for i=0,sides-1 do
     local phi=2*math.pi*i/sides
     row[i+1]=vertex(Vector3.new(math.sin(theta)*math.cos(phi),math.sin(theta)*math.sin(phi),math.cos(theta)))
    end
   end
   for i=1,sides do local q=i%sides+1
    triangle(north,rows[1][i],rows[1][q],inner)
   end
   for j=1,#rows-1 do for i=1,sides do
    local q=i%sides+1;local a,b,c,d=rows[j][i],rows[j+1][i],rows[j+1][q],rows[j][q]
    triangle(a,b,c,inner);triangle(a,c,d,inner)
   end end
   if not cap then
    local south=vertex(Vector3.new(0,0,-1))
    for i=1,sides do local q=i%sides+1
     triangle(rows[#rows][i],south,rows[#rows][q],inner)
    end
   end
   return rows
  end
  local outside=surface(radius,false)
  if cap then
   local inside=surface(radius-.025,true)
   local rim=e:AddNormal(Vector3.new(0,0,-1))
   for i=1,sides do local q=i%sides+1;local a,b,c,d=outside[#outside][i],inside[#inside][i],inside[#inside][q],outside[#outside][q]
    local f=e:AddTriangle(a,b,c);e:SetFaceNormals(f,{rim,rim,rim});f=e:AddTriangle(a,c,d);e:SetFaceNormals(f,{rim,rim,rim})
   end
  end
  local contentResult,content=A:CreateDataModelContentAsync(Content.fromObject(e))
  assert(contentResult==Enum.CreateContentResult.Success,tostring(contentResult))
  local mesh=A:CreateMeshPartAsync(content)
  mesh.Name=cap and 'OriginalPrecisionLid' or 'OriginalRoundEyeball'
  return mesh
 end)
 -- Destroy the EditableMesh even when allocation/content/mesh creation fails.
 e:Destroy()
 assert(ok,result)
 return result
end
function M.Prepare()
 if templates then return templates end
 if busy then repeat task.wait()until not busy;assert(templates,'Face geometry build failed');return templates end
 busy=true
 local lastError
 for attempt=1,3 do
  local made={}
  local ok,result=pcall(function()
   made.eye=build(false);made.lid=build(true);return made
  end)
  if ok then templates=result;busy=false;return templates end
  lastError=result
  for _,mesh in made do mesh:Destroy()end
  if attempt<3 then task.wait(.15*attempt)end
 end
 -- Never leave a busy lock or a partial template set after a failed build.
 busy=false
 error('Face geometry unavailable after 3 attempts: '..tostring(lastError),2)
end
local function stalkSocket(head,side)
 local stalk=head:FindFirstChild(side..'EyeStalk')
 local neck=stalk and stalk:FindFirstChild('EyeNeckJoint')
 assert(stalk and stalk:IsA('BasePart')and neck and neck:IsA('Motor6D')and neck.Part0==head,'Eye stalk root joint required')
 -- The authored stalk reaches C1 within .017 stud, but C0 sits about .10
 -- stud above the curved FaceBridge surface. A fixed rounded socket joins
 -- that surface to the stalk pivot through every animated stalk angle.
 local name=side..'SelectedStalkSocket'
 local socket=head:FindFirstChild(name)
 if socket and not(socket:IsA('Part')and socket:GetAttribute('SelectedStalkSocket'))then
  error('Unexpected eye socket name collision: '..name)
 end
 if not socket then
  socket=Instance.new('Part');socket.Name=name;socket.Shape=Enum.PartType.Ball
  socket:SetAttribute('SelectedStalkSocket',true)
 end
 local weld=socket:FindFirstChild('StalkSocketWeld')
 if weld then assert(weld:IsA('WeldConstraint'),'Unexpected stalk socket weld');weld.Enabled=false end
 socket.Size=Vector3.one*.28;socket.Color=stalk.Color;socket.Material=Enum.Material.SmoothPlastic
 for _,attribute in {'ColourRegion','ColourShade','ColourOverride'}do socket:SetAttribute(attribute,stalk:GetAttribute(attribute))end
 if not socket:GetAttribute('ColourRegion')then socket:SetAttribute('ColourRegion','stalks')end
 socket.Anchored=false;socket.Massless=true;socket.CanCollide=false;socket.CanTouch=false;socket.CanQuery=false
 socket.CastShadow=stalk.CastShadow;socket.CFrame=head.CFrame*neck.C0
 if not weld then weld=Instance.new('WeldConstraint');weld.Name='StalkSocketWeld';weld.Parent=socket end
 weld.Part0=head;weld.Part1=socket;weld.Enabled=true;socket.Parent=head
end
function M.Apply(head)
 local parts={}
 for _,side in {'Left','Right'}do
  local eye=head:FindFirstChild(side..'Eyeball');local lid=head:FindFirstChild(side..'EyeLid')
  assert(eye and eye:IsA('MeshPart')and lid and lid:IsA('MeshPart'),'Custom eye rig required')
  parts[side]={eye=eye,lid=lid}
 end
 local t=M.Prepare()
 assert(head.Parent,'Character head removed during face geometry build')
 for _,side in {'Left','Right'}do
  local eye,lid=parts[side].eye,parts[side].lid
  assert(eye:IsDescendantOf(head)and lid:IsDescendantOf(head),'Character eyes removed during face geometry build')
  local size,cf=eye.Size,eye.CFrame;eye:ApplyMesh(t.eye);eye.Size=size;eye.CFrame=cf
  local surface=eye:FindFirstChildOfClass('SurfaceAppearance');if surface then surface:Destroy()end
  eye.Color=Color3.fromRGB(246,245,234);eye.Material=Enum.Material.SmoothPlastic;eye.Reflectance=.04;eye.TextureID=''
  local oldcf=lid.CFrame;lid:ApplyMesh(t.lid);lid.Size=Vector3.new(.79,.79,.395);lid.CFrame=oldcf;lid.TextureID=''
  lid:SetAttribute('PrecisionShell',true)
  local back=head:FindFirstChild(side..'EyeBackCap');if back then back.LocalTransparencyModifier=1 end
  stalkSocket(head,side)
 end
 head:SetAttribute('SelectedFaceGeometryVersion',VERSION)
 head:SetAttribute('SelectedFaceGeometryReady',true)
 return true
end
return M
