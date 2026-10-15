-- Handheld radar map device, built from parts so it needs no uploaded assets.
-- Front (-Z) of the Screen part is the display. Every part is welded to Body.
local D={}
D.Size=Vector3.new(1.5,1.1,.16) -- body at scale 1 (studs)
local SHELL=Color3.fromRGB(46,52,44)
local TRIM=Color3.fromRGB(150,124,62)
local GLASS=Color3.fromRGB(6,18,11)
local function part(model,body,name,size,offset,color,material,shape)
 local p=Instance.new('Part');p.Name=name;p.Size=size;p.Color=color;p.Material=material or Enum.Material.SmoothPlastic
 if shape then p.Shape=shape end
 p.CanCollide=false;p.CanQuery=false;p.CanTouch=false;p.Massless=true;p.CastShadow=false
 p.TopSurface=Enum.SurfaceType.Smooth;p.BottomSurface=Enum.SurfaceType.Smooth
 if body then p.CFrame=body.CFrame*offset;local w=Instance.new('WeldConstraint');w.Part0=body;w.Part1=p;w.Parent=p end
 p.Parent=model;return p
end
-- scale: 1 for the first-person view, ~.5 for the character's hand.
function D.Build(scale)
 scale=scale or 1
 local m=Instance.new('Model');m.Name='FieldMapDevice'
 local s=D.Size*scale
 local body=part(m,nil,'Body',s,nil,SHELL,Enum.Material.Metal)
 body.CFrame=CFrame.new()
 m.PrimaryPart=body
 local function v(x,y,z) return Vector3.new(x,y,z)*scale end
 local function at(x,y,z) return CFrame.new(x*scale,y*scale,z*scale) end
 -- Bezel ring and recessed screen on the front face.
 for _,b in {{v(1.5,.09,.05),at(0,.505,-.09)},{v(1.5,.09,.05),at(0,-.505,-.09)},{v(.09,1.1,.05),at(-.705,0,-.09)},{v(.09,1.1,.05),at(.705,0,-.09)}} do
  part(m,body,'Bezel',b[1],b[2],TRIM,Enum.Material.Metal)
 end
 local screen=part(m,body,'Screen',v(1.22,.86,.02),at(0,.02,-.085),GLASS,Enum.Material.Glass)
 screen.Transparency=0;screen.Reflectance=.05
 -- Rubber grip bumpers on the corners.
 for _,c in {{-.72,.52},{.72,.52},{-.72,-.52},{.72,-.52}} do
  part(m,body,'Bumper',v(.16,.16,.22),at(c[1],c[2],0),Color3.fromRGB(24,24,22),Enum.Material.Rubber)
 end
 -- Antenna on the top-right with a blinking tip.
 part(m,body,'Antenna',v(.62,.05,.05),at(.56,.86,.02)*CFrame.Angles(0,0,math.pi/2),Color3.fromRGB(30,30,30),Enum.Material.Metal,Enum.PartType.Cylinder)
 local tip=part(m,body,'AntennaTip',v(.11,.11,.11),at(.56,1.18,.02),Color3.fromRGB(255,70,60),Enum.Material.Neon,Enum.PartType.Ball)
 tip:SetAttribute('Blink',true)
 -- Tuning dial and status lamp on the bottom edge.
 part(m,body,'Dial',v(.08,.22,.22),at(-.42,-.6,-.02)*CFrame.Angles(0,0,math.pi/2),TRIM,Enum.Material.Metal,Enum.PartType.Cylinder)
 part(m,body,'Lamp',v(.07,.07,.03),at(.55,-.43,-.1),Color3.fromRGB(90,255,140),Enum.Material.Neon)
 -- Back plate stamped with a stripe so the device reads from behind too.
 part(m,body,'BackStripe',v(1.2,.12,.02),at(0,-.3,.09),TRIM,Enum.Material.Metal)
 return m,screen
end
return D
