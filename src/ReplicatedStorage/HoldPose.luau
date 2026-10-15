local H={}
H.GrabSeconds=.22
local grab
local function smooth(t) t=math.clamp(t,0,1);return t*t*(3-2*t) end
function H.BeginGrab(model,duration)
 grab={model=model,phase='reach',started=os.clock(),duration=duration or H.GrabSeconds,origin=model.PrimaryPart.CFrame}
end
function H.ConfirmGrab(model)
 if grab and grab.model==model then grab.phase='hold';grab.started=os.clock() end
end
function H.EndGrab()
 if grab then grab.phase='release';grab.started=os.clock();grab.duration=.12 end
end
function H.HasGrip() return grab and grab.phase=='hold' end
function H.IsPerfumeSpraying()
 local p=game:GetService('Players').LocalPlayer
 return p~=nil and workspace:GetServerTimeNow()<(p:GetAttribute('PerfumeSprayUntil')or 0)
end
-- Field map: the left hand dips to the left pocket, then raises the radar to read.
local MAP_DIP,MAP_RAISE,MAP_LOWER,MAP_RETURN=.2,.28,.18,.2
local map={open=false,changed=-100}
function H.SetMap(open)
 if map.open~=open then map.open=open;map.changed=os.clock() end
end
function H.MapOpen() return map.open end
-- phase, 0..1 progress. 'idle' once fully put away.
function H.MapPhase()
 local t=os.clock()-map.changed
 if map.open then
  if t<MAP_DIP then return 'dip',smooth(t/MAP_DIP) end
  return 'raise',smooth((t-MAP_DIP)/MAP_RAISE)
 end
 if t<MAP_LOWER then return 'lower',smooth(t/MAP_LOWER) end
 if t<MAP_LOWER+MAP_RETURN then return 'return',smooth((t-MAP_LOWER)/MAP_RETURN) end
 return 'idle',1
end
function H.MapActive() return H.MapPhase()~='idle' end
-- Where the device sits while reading: lower-left of view, screen turned to the eye.
function H.MapReadPose(camera)
 return camera*CFrame.new(-.58,-.62,-1.9)*CFrame.Angles(math.rad(12),math.rad(16),math.rad(-3))*CFrame.Angles(0,math.pi,0)
end
local HAND_UNDER_DEVICE=CFrame.new(.5,-.5,.1) -- device-local: hand cups the lower-left corner
function H.MapDevice()
 -- Valid only after H.Hand(camera,-1) ran this frame (SprintController, Camera+1).
 if not map.hand then return nil,false end
 local phase=H.MapPhase()
 local visible=phase=='raise' or phase=='lower'
 return map.hand*map.handToDevice,visible
end
function H.IsAnimating() return grab~=nil or H.IsPerfumeSpraying() or H.MapActive() end
function H.GrabProgress()
 return grab and grab.phase=='reach' and math.clamp((os.clock()-grab.started)/grab.duration,0,1) or 0
end
function H.CarryPose(camera,grip,model)
 local pose=H.Item(camera,grip,model)
 if grab and grab.model==model and grab.phase=='hold' then
  local t=smooth((os.clock()-grab.started)/.12)
  return CFrame.new(pose.Position)*grab.origin.Rotation:Lerp(pose.Rotation,t)
 end
 return pose
end
local function segment(part,aName,bName,a,b,up)
 local aa=part:FindFirstChild(aName);local bb=part:FindFirstChild(bName)
 if not aa or not bb or (b-a).Magnitude<.001 then return part.CFrame end
 local localFrame=CFrame.lookAt(aa.Position,bb.Position,Vector3.zAxis)
 return CFrame.lookAt(a,b,up)*localFrame:Inverse()
end
function H.ArmFrames(camera,hand,handPart,upper,lower)
 if (not grab and not H.IsPerfumeSpraying() and not H.MapActive())or not upper or not lower then return nil end
 local wristAtt=handPart:FindFirstChild('LeftWristRigAttachment')
 local shoulderAtt=upper:FindFirstChild('LeftShoulderRigAttachment');local elbowUpper=upper:FindFirstChild('LeftElbowRigAttachment')
 local elbowLower=lower:FindFirstChild('LeftElbowRigAttachment');local wristLower=lower:FindFirstChild('LeftWristRigAttachment')
 if not wristAtt or not shoulderAtt or not elbowUpper or not elbowLower or not wristLower then return nil end
 local wrist=hand:PointToWorldSpace(wristAtt.Position)
 local shoulder=camera:PointToWorldSpace(Vector3.new(-1.05,-.85,.15))
 local l1=(shoulderAtt.Position-elbowUpper.Position).Magnitude;local l2=(elbowLower.Position-wristLower.Position).Magnitude
 local delta=wrist-shoulder;local distance=delta.Magnitude;if distance<.01 then return nil end
 local axis=delta.Unit
 -- Keep the authored bones connected even at the far end of the pickup reach.
 if distance>l1+l2-.03 then shoulder=wrist-axis*(l1+l2-.03);distance=l1+l2-.03 end
 local along=math.clamp((distance*distance+l1*l1-l2*l2)/(2*distance),0,l1)
 local bend=-camera.RightVector-camera.UpVector*.7;bend-=axis*bend:Dot(axis)
 if bend.Magnitude<.01 then bend=camera.UpVector else bend=bend.Unit end
 local elbow=shoulder+axis*along+bend*math.sqrt(math.max(0,l1*l1-along*along))
 return segment(upper,'LeftShoulderRigAttachment','LeftElbowRigAttachment',shoulder,elbow,camera.LookVector),segment(lower,'LeftElbowRigAttachment','LeftWristRigAttachment',elbow,wrist,camera.LookVector)
end
H.HandX=1.8;H.HandY=-1.35;H.HandZ=-2.75
function H.Hand(camera,side,sway,lift,swing)
 local base=camera*CFrame.new(side*H.HandX-(sway or 0),H.HandY+(lift or 0),H.HandZ+(swing or 0))*CFrame.Angles(math.rad(90+12),math.rad(-side*8),0)*CFrame.Angles(0,math.pi,0)
 if side==-1 and H.MapActive() then
  local read=H.MapReadPose(camera)
  local hold=read*HAND_UNDER_DEVICE
  hold=CFrame.new(hold.Position)*base.Rotation*CFrame.Angles(-.35,0,.25)
  local pocket=CFrame.new(camera:PointToWorldSpace(Vector3.new(-1.25,-2.45,-.85)))*base.Rotation*CFrame.Angles(.5,0,.2)
  map.handToDevice=hold:Inverse()*read
  local phase,a=H.MapPhase()
  local pose
  if phase=='dip' then pose=base:Lerp(pocket,a)
  elseif phase=='raise' then pose=pocket:Lerp(hold,a)*CFrame.Angles(0,0,math.sin(a*math.pi)*.1)
  elseif phase=='lower' then pose=hold:Lerp(pocket,a)
  else pose=pocket:Lerp(base,a) end
  map.hand=pose
  return pose
 end
 if side==-1 then
  local player=game:GetService('Players').LocalPlayer
  local now=workspace:GetServerTimeNow()
  if player and now<(player:GetAttribute('PerfumeSprayUntil')or 0)then
   local start=player:GetAttribute('PerfumeSprayStart')or now
   local age=now-start;local blend=smooth(age/.22)*smooth((1.8-age)/.20)
   local spray=camera*CFrame.new(-.75,-.65,-2.2)*base.Rotation*CFrame.Angles(0,0,math.sin(age*math.pi*4)*.12)
   return base:Lerp(spray,blend)
  end
 end
 if side~=-1 or not grab then return base end
 if grab.phase=='release' then
  local t=smooth((os.clock()-grab.started)/grab.duration)
  local pose=(grab.last or base):Lerp(base,t)
  if t>=1 then grab=nil end
  return pose
 end
 local model=grab.model
 if not model or not model.Parent or not model.PrimaryPart then H.EndGrab();return base end
 local size=model.PrimaryPart.Size;local id=model:GetAttribute('ItemId');local lift=size.Y*.28
 if id=='Balloon' then lift=size.Y*.47 elseif id=='Keyring' or id=='Chain' then lift=-size.Y*.25 elseif id=='Coin' or id=='Bracelet' then lift=0 end
 local contact=grab.origin.Position-camera.UpVector*lift-camera.LookVector*(size.Z*.18)
 local gripLocal=model:GetAttribute('GrabGripOffset') or CFrame.new(0,-.07,0)
 local contactHand=CFrame.new(contact)*base.Rotation*gripLocal:Inverse()
 local pose
 if grab.phase=='reach' then
  local t=smooth((os.clock()-grab.started)/grab.duration)
  pose=base:Lerp(contactHand,t)*CFrame.Angles(0,0,math.sin(t*math.pi)*-.12)
 else
  local t=smooth((os.clock()-grab.started)/.12)
  pose=contactHand:Lerp(base,t)*CFrame.Angles(0,0,math.sin(t*math.pi)*-.1)
 end
 grab.last=pose;return pose

end
function H.LeftGrip(camera)
 return H.Hand(camera,-1)*CFrame.new(0,-.07,0)
end
function H.Item(camera,grip,model)
 local size=model.PrimaryPart.Size;local id=model:GetAttribute('ItemId')
 if id=='CursedPerfume' and workspace:GetServerTimeNow()-(model:GetAttribute('PerfumeSprayStart')or -100)<1.8 then
  return camera*CFrame.new(-.75,-.42,-2.2)*CFrame.Angles(.35,.56,math.sin((workspace:GetServerTimeNow()-(model:GetAttribute('PerfumeSprayStart')or 0))*math.pi*4)*.12)*(model:GetAttribute('ModelPivotOffset')or CFrame.identity)
 end
 local lift=size.Y*.28
 if id=='Balloon' then lift=size.Y*.47 elseif id=='Keyring' or id=='Chain' then lift=-size.Y*.25 elseif id=='Coin' or id=='Bracelet' then lift=0 end
 local pos=grip.Position+camera.UpVector*lift+camera.LookVector*(size.Z*.18)
 local facing=(id=='Doll' or id=='Teddy' or id=='Portrait' or id=='Mask' or id=='Mirror') and math.pi or 0
 return CFrame.new(pos)*camera.Rotation*CFrame.Angles(0,facing,0)
end
return H