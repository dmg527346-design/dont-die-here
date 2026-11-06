-- Additive VR pose extension. Pickup, inventory, curses, carts and releases retain their existing owners.
local Players=game:GetService('Players')
local RS=game:GetService('ReplicatedStorage')
local Run=game:GetService('RunService')
local remote=Instance.new('RemoteEvent')
remote.Name='DDHVRTracking'
remote.Parent=RS
local sessions={}
local rates={}
local MAX_HAND_REACH=5
local CONTACT_REACH=.85 -- Contact plus network/physics tolerance, still inside the original reach rules.
local TRACKING_TIMEOUT=1
local hold=require(RS:WaitForChild('HoldPose'))
local originalItem=hold.Item

local function finiteCF(value)
 if typeof(value)~='CFrame' then return false end
 for _,n in {value:GetComponents()} do if n~=n or math.abs(n)>1e6 then return false end end
 local right,up,look=value.RightVector,value.UpVector,value.LookVector
 return math.abs(right.Magnitude-1)<.01 and math.abs(up.Magnitude-1)<.01 and math.abs(look.Magnitude-1)<.01
  and math.abs(right:Dot(up))<.01 and math.abs(up:Dot(look))<.01 and math.abs(right:Dot(look))<.01
  and (right:Cross(up)+look).Magnitude<.02
end

local function allowed(player)
 local character=player.Character
 local hum=character and character:FindFirstChildOfClass('Humanoid')
 local head=character and character:FindFirstChild('Head')
 return hum and hum.Health>0 and head and player:GetAttribute('RoundDead')~=true and player:GetAttribute('Hiding')~=true and (player:GetAttribute('MissionActive')==true or player:GetAttribute('LobbyReady')==true),head
end

local function tracked(player,headCF,handCF)
 local ok,head=allowed(player)
 if not ok or not finiteCF(headCF) or not finiteCF(handCF) then return false end
 if (headCF.Position-head.Position).Magnitude>3 or (handCF.Position-headCF.Position).Magnitude>MAX_HAND_REACH then return false end
 local params=RaycastParams.new()
 params.FilterType=Enum.RaycastFilterType.Exclude
 params.FilterDescendantsInstances={player.Character}
 params.RespectCanCollide=true
 -- A hand cannot reach through solid furniture or a closed door.
 local hit=workspace:Raycast(head.Position,handCF.Position-head.Position,params)
 if hit and hit.Distance+.2<(handCF.Position-head.Position).Magnitude then return false end
 return true
end

local function itemAllowed(player,model)
 if typeof(model)~='Instance' or not model:IsA('Model') or not model.PrimaryPart then return false end
 local mansion=workspace:FindFirstChild('Mansion')
 local world=workspace:FindFirstChild('LobbyWorld')
 local toys=world and world:FindFirstChild('Toys')
 local runtime=toys and toys:FindFirstChild('RuntimeToys')
 return (player:GetAttribute('MissionActive')==true and mansion and model.Parent==mansion:FindFirstChild('Interactive')) or (model.Parent==runtime and model:GetAttribute('LobbyToy')==true)
end

local function contactDistance(model,point)
 local best=math.huge
 for _,part in model:GetDescendants() do
  if part:IsA('BasePart') and part.Transparency<1 then
   local q=part.CFrame:PointToObjectSpace(point)
   local h=part.Size*.5
   local closest=Vector3.new(math.clamp(q.X,-h.X,h.X),math.clamp(q.Y,-h.Y,h.Y),math.clamp(q.Z,-h.Z,h.Z))
   best=math.min(best,(q-closest).Magnitude)
  end
 end
 return best
end

hold.Item=function(camera,grip,model)
 local userId=model:GetAttribute('HeldBy')
 local player=userId and Players:GetPlayerByUserId(userId)
 local state=player and sessions[player]
 if state and state.model==model and state.offset and os.clock()-state.at<TRACKING_TIMEOUT then
  state.wasHeld=true
  return state.hand*state.offset
 end
 return originalItem(camera,grip,model)
end

local function release(player,state)
 local model=state.model
 if not model or not model.Parent or not state.wasHeld or not model.PrimaryPart then state.model=nil;return end
 -- Never override another player, a cart, a worn curse, or the game's glue mechanic.
 local owner=model:GetAttribute('HeldBy')
 if owner and owner~=player.UserId or model:GetAttribute('Kind')~='pickup' or model:GetAttribute('FaceOwner') or model:GetAttribute('ItemWearOwner') then state.model=nil;return end
 local api=game.ServerStorage:FindFirstChild('CursedItemApi')
 if api and owner==player.UserId then player:SetAttribute('PhysicalGrabActive',nil);api:Invoke('release',player,model) end
 if model:GetAttribute('HeldBy') then return end
 -- Original owner performs the release first. Preserve the final validated hand pose when space is clear.
 local goal=state.hand*state.offset
 local root=player.Character and player.Character:FindFirstChild('HumanoidRootPart')
 if root and (goal.Position-root.Position).Magnitude<=8 then
  local params=RaycastParams.new();params.FilterType=Enum.RaycastFilterType.Exclude;params.FilterDescendantsInstances={player.Character,model};params.RespectCanCollide=true
  local hit=workspace:Raycast(root.Position+Vector3.yAxis,goal.Position-root.Position-Vector3.yAxis,params)
  if not hit or hit.Distance+.1>=(goal.Position-root.Position-Vector3.yAxis).Magnitude then
   model:PivotTo(goal*model.PrimaryPart.CFrame:ToObjectSpace(model:GetPivot()))
   model.PrimaryPart.AssemblyLinearVelocity=Vector3.new(0,-1,0)
   model.PrimaryPart.AssemblyAngularVelocity=Vector3.zero
  end
 end
 state.model=nil;state.offset=nil;state.wasHeld=false
end

remote.OnServerEvent:Connect(function(player,action,headCF,handCF,model)
 if action~='tracking' and action~='contact' and action~='release' then return end
 local now=os.clock()
 local rate=rates[player]
 if not rate or now-rate.at>=1 then rate={at=now,count=0};rates[player]=rate end
 rate.count+=1;if rate.count>65 then return end
 local state=sessions[player]
 if state and now-(state.window or 0)>=1 then state.window=now;state.count=0 end
 if state and state.count>=65 then return end
 if not tracked(player,headCF,handCF) then return end
 if not state then state={window=now,count=0,at=0};sessions[player]=state end
 state.count+=1
 if action=='tracking' and now-state.at<1/45 then return end
 state.hand=handCF;state.at=now
 player:SetAttribute('DDHVRActive',true)
 player:SetAttribute('TouchCarry',true)
 if action=='contact' then
  if player:GetAttribute('MapOpen') or player:GetAttribute('MonsterJumpscareActive') or not itemAllowed(player,model) then return end
  if model:GetAttribute('HeldBy') or contactDistance(model,handCF.Position)>CONTACT_REACH then return end
  state.model=model;state.offset=handCF:ToObjectSpace(model.PrimaryPart.CFrame);state.wasHeld=false
 elseif action=='release' then
  if model~=state.model then return end
  release(player,state)
 end
end)

local clock=0
Run.Heartbeat:Connect(function(dt)
 clock+=dt;if clock<.2 then return end;clock=0
 for player,state in sessions do
  if state.model and state.wasHeld and (not state.model.Parent or state.model:GetAttribute('HeldBy')~=player.UserId) then
   state.model=nil;state.offset=nil;state.wasHeld=false
  end
  if os.clock()-state.at>TRACKING_TIMEOUT then
   release(player,state)
   sessions[player]=nil
   player:SetAttribute('DDHVRActive',nil)
  end
 end
end)
Players.PlayerRemoving:Connect(function(player)sessions[player]=nil;rates[player]=nil end)
