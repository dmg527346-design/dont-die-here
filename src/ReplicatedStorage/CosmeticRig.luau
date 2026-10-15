-- Single owner of how wearable cosmetics attach to the creature rig. Used by ProgressService (live characters)
-- and MainMenuClient (ViewportFrame preview). Templates: ReplicatedStorage.CosmeticKit[id].
local C=require(script.Parent:WaitForChild('LobbyShopCatalog'))
local M={}
-- Trail looks (Trail slot): particles from both feet while moving; 'streak' is a Trail behind the body.
local SPARK='rbxasset://textures/particles/sparkles_main.dds'
local SMOKE='rbxasset://textures/particles/smoke_main.dds'
local TRAILS={
 trail_sparks={tex=SPARK,colors={Color3.fromRGB(255,220,120),Color3.fromRGB(255,150,40)},size=.35,rate=14,life=.6,speed=1.5,glow=1},
 trail_ectoplasm={tex=SMOKE,colors={Color3.fromRGB(130,255,150)},size=.55,grow=1.1,rate=8,life=1.2,speed=.3,fall=1,fade=.35},
 trail_glitter={tex=SPARK,colors={Color3.fromRGB(255,150,230),Color3.fromRGB(150,220,255),Color3.fromRGB(255,255,255)},size=.3,rate=18,life=.8,speed=1,glow=1},
 trail_hearts={tex='rbxassetid://93764965207025',colors={Color3.fromRGB(255,90,130)},size=.35,rate=6,life=1,speed=1,rise=2},
 trail_coins={tex='rbxassetid://117087930716286',colors={Color3.fromRGB(255,205,70)},size=.35,rate=6,life=.9,speed=1.5,spin=true,fall=4},
 trail_pumpkinseeds={tex='rbxassetid://121307869288298',colors={Color3.fromRGB(250,230,170)},size=.25,rate=8,life=.9,speed=1.5,spin=true,fall=6},
 trail_speed={streak=true,colors={Color3.fromRGB(230,240,255)}},
}
-- Torch skins sit in the right hand at this scale (the hand is small; templates are about 2 studs tall).
local TORCH_SCALE=.55
local function template_lift(id)
 local kit=script.Parent:FindFirstChild('CosmeticKit');local t=kit and kit:FindFirstChild(id)
 return t and t:GetAttribute('MountLift')
end
function M.Wear(ch,equipped,folder)
 local root=ch:FindFirstChild('HumanoidRootPart');local torso=ch:FindFirstChild('UpperTorso');local kit=script.Parent:FindFirstChild('CosmeticKit')
 if not root or not torso or not kit then return end
 -- Root faces -Z, so the character's front is root.CFrame.LookVector.
 local facing=root.CFrame-root.Position
 local anchored=folder:FindFirstAncestorWhichIsA('WorldModel')~=nil
 local function wear(id,target,cf,name)
  local template=kit:FindFirstChild(id);if not template or not target then return nil end
  local m=template:Clone();m:PivotTo(cf);m:SetAttribute('WearSlot',C.ById[id]and C.ById[id].kind)
  if anchored then for _,x in m:GetDescendants()do if x:IsA('BasePart')then x.Anchored=true end end
  else local w=Instance.new('WeldConstraint');w.Part0=target;w.Part1=m.PrimaryPart;w.Parent=m.PrimaryPart end
  if name then m.Name=name end -- named before parenting so watchers see the final name
  m.Parent=folder;return m
 end
 -- Hats sit above the eyes, centred over both eye stalks, exactly like the Cool Sunglasses hat:
 -- base at Head + HAT_BASE_Y, scaled to span both eyes (tune by screenshot).
 local HAT_BASE_Y=2.21 -- studs above the Head centre (Cool Sunglasses hat bottom)
 local HAT_WIDTH=3.0 -- studs across, brim included
 local hat=C.ById[equipped.Hat]
 local head=ch:FindFirstChild('Head')
 if hat then
  local target=head or torso
  local top=head and head.CFrame*Vector3.new(0,HAT_BASE_Y,0) or torso.CFrame*Vector3.new(0,torso.Size.Y/2-.14,0)
  local m=wear(hat.id,target,CFrame.new(top)*facing)
  if m then
   m.Name='CosmeticHat'
   local _,size=m:GetBoundingBox();local width=math.max(size.X,size.Z)
   if width>0 then
    -- Rescale about the hat's base, keeping it seated over the eyes.
    local weld=m.PrimaryPart and m.PrimaryPart:FindFirstChildOfClass('WeldConstraint');if weld then weld.Enabled=false end
    m:ScaleTo(m:GetScale()*HAT_WIDTH/width)
    -- Templates whose band starts above their pivot (MountLift, template studs) are lowered by that much so
    -- the band, not the pivot, sits on HAT_BASE_Y; SeatDrop (worn studs) nudges one hat further down.
    local template=kit:FindFirstChild(hat.id)
    local lift=(template_lift(hat.id)or 0)*m:GetScale()/(template and template:GetScale()or 1)+(m:GetAttribute('SeatDrop')or 0)
    m:PivotTo(CFrame.new(top-(head or torso).CFrame.UpVector*lift)*facing)
    if weld then weld.Enabled=true end
   end
  end
 end
 -- Rings go on the LEFT hand (the right hand holds the flashlight); first-person arms copy it.
 local ring=C.ById[equipped.Ring];local hand=ch:FindFirstChild('LeftHand')
 if ring and hand then wear(ring.id,hand,hand.CFrame*CFrame.new(0,.05,0),'CosmeticRing') end
 local shoes=C.ById[equipped.Shoes]
 if shoes then
  -- Wide shoes (clown) are wider than the gap between the feet: push each one out on its own side
  -- so the pair never cut into each other.
  local SHOE_GAP=.06
  local template=kit:FindFirstChild(shoes.id);local width=0
  if template then local _,size=template:GetBoundingBox();width=size.X end
  local lf,rf=ch:FindFirstChild('LeftFoot'),ch:FindFirstChild('RightFoot')
  local spacing=(lf and rf)and math.abs(root.CFrame:PointToObjectSpace(rf.Position).X-root.CFrame:PointToObjectSpace(lf.Position).X)or 1.32
  local push=math.max(0,(width+SHOE_GAP-spacing)/2)
  for _,side in {'Left','Right'}do
   local foot=ch:FindFirstChild(side..'Foot')
   local out=root.CFrame.RightVector*(side=='Left'and -push or push)
   -- Seated in the foot's own frame (the rig's foot frame faces backwards, hence the half turn), so a shoe put on
   -- mid-step still lines up with the foot instead of staying crooked.
   local m=foot and wear(shoes.id,foot,(foot.CFrame*CFrame.Angles(0,math.pi,0)*CFrame.new(0,.06,0))+out)
   local nozzle=m and not anchored and m:FindFirstChild('Nozzle')
   if nozzle then
    local e=Instance.new('ParticleEmitter');e.Texture='rbxasset://textures/particles/fire_main.dds';e.Color=ColorSequence.new(Color3.fromRGB(255,170,60),Color3.fromRGB(255,80,20))
    e.Size=NumberSequence.new({NumberSequenceKeypoint.new(0,.35),NumberSequenceKeypoint.new(1,0)});e.Lifetime=NumberRange.new(.15,.3);e.Rate=30;e.Speed=NumberRange.new(3,5);e.LightEmission=1
    e.EmissionDirection=Enum.NormalId.Back;e.Parent=nozzle
   end
  end
 end
 -- Eyes: one template per eyeball, welded to it so it follows the stalks and blinks. SingleEye templates
 -- (the monocle) only go on the left eye. Template origin = eyeball centre, front = character front.
 local eyes=C.ById[equipped.Eyes]
 if eyes and head then
  local template=kit:FindFirstChild(eyes.id)
  local sides=template and template:GetAttribute('SingleEye')and{'Left'}or{'Left','Right'}
  for _,side in sides do
   local ball=head:FindFirstChild(side..'Eyeball')
   if ball then wear(eyes.id,ball,CFrame.new(ball.Position)*facing,'CosmeticEyes'..side)end
  end
 end
 -- Back: on the rear surface of the torso (a ray from behind, like the tattoo), hanging behind (+Z).
 local back=C.ById[equipped.Back]
 if back then
  local forward=root.CFrame.LookVector
  local params=RaycastParams.new();params.FilterType=Enum.RaycastFilterType.Include;params.FilterDescendantsInstances={torso}
  local world=ch:FindFirstAncestorWhichIsA('WorldModel')or workspace
  local hit=world:Raycast(torso.Position-forward*4+Vector3.new(0,.2,0),forward*5,params)
  local point=hit and hit.Position or torso.Position-forward*(torso.Size.Z/2)
  wear(back.id,torso,CFrame.new(point)*facing,'CosmeticBack')
 end
 -- Torch: a small lamp in the right hand (the flashlight hand). FlashlightController tints the beam to match.
 local torch=C.ById[equipped.Torch];local rhand=ch:FindFirstChild('RightHand')
 if torch and rhand then
  local m=wear(torch.id,rhand,CFrame.new(rhand.Position)*facing,'CosmeticTorch')
  if m then
   local weld=m.PrimaryPart and m.PrimaryPart:FindFirstChildOfClass('WeldConstraint');if weld then weld.Enabled=false end
   m:ScaleTo(m:GetScale()*TORCH_SCALE);m:PivotTo(CFrame.new(rhand.Position)*facing)
   if weld then weld.Enabled=true end
  end
 end
 -- Trail: live characters only (a ViewportFrame cannot show particles). The emitter parts live in the
 -- cosmetics folder, so a re-equip or respawn removes them with everything else.
 local trail=C.ById[equipped.Trail];local style=trail and TRAILS[trail.id]
 if style and not anchored then
  local function carrier(target,offset)
   local part=Instance.new('Part');part.Name='CosmeticTrail';part.Size=Vector3.new(.1,.1,.1);part.Transparency=1
   part.CanCollide=false;part.CanQuery=false;part.CanTouch=false;part.Massless=true;part.CastShadow=false
   part.CFrame=target.CFrame*offset;local w=Instance.new('WeldConstraint');w.Part0=target;w.Part1=part;w.Parent=part;part.Parent=folder
   return part
  end
  local emitters={}
  if style.streak then
   local part=carrier(root,CFrame.new(0,0,.6))
   local a0=Instance.new('Attachment');a0.Position=Vector3.new(0,1.2,0);a0.Parent=part
   local a1=Instance.new('Attachment');a1.Position=Vector3.new(0,-1.6,0);a1.Parent=part
   local t=Instance.new('Trail');t.Attachment0=a0;t.Attachment1=a1;t.Lifetime=.22;t.MinLength=.1;t.FaceCamera=true;t.LightEmission=.6
   t.Color=ColorSequence.new(style.colors[1]);t.Transparency=NumberSequence.new(.35,1);t.WidthScale=NumberSequence.new(1,.2);t.Parent=part
   table.insert(emitters,t)
  else
   for _,side in {'Left','Right'}do
    local foot=ch:FindFirstChild(side..'Foot')
    if foot and foot:IsA('BasePart')then
     local part=carrier(foot,CFrame.new(0,-.25,0))
     local e=Instance.new('ParticleEmitter');e.Texture=style.tex;e.Rate=style.rate;e.Lifetime=NumberRange.new(style.life*.7,style.life)
     local keys={};for i,c in style.colors do table.insert(keys,ColorSequenceKeypoint.new(#style.colors==1 and 0 or(i-1)/(#style.colors-1),c))end
     if #keys==1 then table.insert(keys,ColorSequenceKeypoint.new(1,style.colors[1]))end
     e.Color=ColorSequence.new(keys);e.LightEmission=style.glow or 0;e.Speed=NumberRange.new(style.speed*.5,style.speed);e.SpreadAngle=Vector2.new(180,180)
     e.Size=NumberSequence.new({NumberSequenceKeypoint.new(0,style.size),NumberSequenceKeypoint.new(1,(style.grow or .2)*style.size)})
     e.Transparency=NumberSequence.new(style.fade or 0,1)
     e.Acceleration=Vector3.new(0,(style.rise or 0)-(style.fall or 0),0)
     if style.spin then e.RotSpeed=NumberRange.new(-180,180);e.Rotation=NumberRange.new(0,360)end
     e.Parent=part;table.insert(emitters,e)
    end
   end
  end
  -- Only while walking, so standing still never piles particles up.
  local conn;conn=game:GetService('RunService').Heartbeat:Connect(function()
   if not root.Parent or not emitters[1]or not emitters[1].Parent then conn:Disconnect();return end
   local v=root.AssemblyLinearVelocity;local moving=Vector3.new(v.X,0,v.Z).Magnitude>3
   for _,e in emitters do if e.Enabled~=moving then e.Enabled=moving end end
  end)
 end
 local tattoo=C.TattooDecals[equipped.Shirt]
 if tattoo then
  -- A flat card on the belly: find the torso surface in front of the stomach and face the decal along its normal.
  local forward=root.CFrame.LookVector;local belly=torso.Position+Vector3.new(0,-.55,0)
  local params=RaycastParams.new();params.FilterType=Enum.RaycastFilterType.Include;params.FilterDescendantsInstances={torso}
  local world=ch:FindFirstAncestorWhichIsA('WorldModel')or workspace
  local hit=world:Raycast(belly+forward*4,-forward*5,params)
  local point=hit and hit.Position or belly+forward*(torso.Size.Z/2)
  local normal=hit and hit.Normal or forward
  local card=Instance.new('Part');card.Name='CosmeticTattoo';card.Size=Vector3.new(1.1,1.1,.02);card.Transparency=1
  card.CanCollide=false;card.CanQuery=false;card.CanTouch=false;card.Massless=true;card.CastShadow=false;card.Anchored=anchored
  card.CFrame=CFrame.lookAt(point+normal*.03,point+normal*2)
  local decal=Instance.new('Decal');decal.Texture=tattoo;decal.Face=Enum.NormalId.Front;decal.Parent=card
  if not anchored then local w=Instance.new('WeldConstraint');w.Part0=torso;w.Part1=card;w.Parent=card end
  card.Parent=folder
 end
end
return M
