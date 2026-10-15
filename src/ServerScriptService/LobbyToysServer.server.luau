local QuestService=require(game:GetService('ServerScriptService'):WaitForChild('QuestService'))
-- Table lifecycle only. The existing cursed-item owners handle grab, physics and effects.
local Players=game:GetService('Players')
local RS=game:GetService('ReplicatedStorage')
local SS=game:GetService('ServerStorage')
local Run=game:GetService('RunService')
local Items=require(RS:WaitForChild('LobbyToyEffects')).Items
local state=RS:WaitForChild('LobbyState')
local world=workspace:WaitForChild('LobbyWorld')
while world:GetAttribute('Ready')~=true do task.wait(.1)end
local toys=world:WaitForChild('Toys')
local runtime=Instance.new('Folder');runtime.Name='RuntimeToys';runtime.Parent=toys
-- Only enable stopped owners; lobby and mission share one running instance.
for _,name in {'CursedItemsServer','InteractServer'}do
 local owner=game.ServerScriptService:WaitForChild(name);if not owner.Enabled then owner.Enabled=true end
end
local api=SS:WaitForChild('CursedItemApi',60);assert(api,'Shared cursed-item owner did not initialize')
-- Map rebuild replaces the shared API; resolve it for each operation instead of retaining a dead callback.
local function invoke(action,p,m)
 local current=SS:FindFirstChild('CursedItemApi')
 local owner=game.ServerScriptService:FindFirstChild('CursedItemsServer')
 if not current or not owner or not owner.Enabled then return false end
 local ok,value=pcall(function()return current:Invoke(action,p,m)end)
 if ok then return value end
 if tostring(value):find('destroyed while calling async callback',1,true)then return false end
 error(value,0)
end
local kit=SS:WaitForChild('CursedItemKit')
local records={}
local CLOTH_EDGE_INSET=.2
local EDGE_CLEARANCE=.08
local tables={}
for _,part in world:GetDescendants()do
 if part:IsA('MeshPart') and part.Name=='LobbyToyTable' and part.Transparency<1 then table.insert(tables,part)end
end
local function supportFor(spot)
 local best,distance=nil,math.huge
 for _,part in tables do
  local point=part.CFrame:PointToObjectSpace(spot.Position)
  local d=point.X*point.X+point.Z*point.Z
  if math.abs(point.X)<=part.Size.X/2 and math.abs(point.Z)<=part.Size.Z/2 and d<distance then best=part;distance=d end
 end
 return best
end
local function placeOnTable(record,m)
 local support=record.support
 local cf,size=m:GetBoundingBox()
 local localCF=support.CFrame:ToObjectSpace(cf)
 local halfX=(math.abs(localCF.RightVector.X)*size.X+math.abs(localCF.UpVector.X)*size.Y+math.abs(localCF.LookVector.X)*size.Z)/2
 local halfZ=(math.abs(localCF.RightVector.Z)*size.X+math.abs(localCF.UpVector.Z)*size.Y+math.abs(localCF.LookVector.Z)*size.Z)/2
 local limitX=support.Size.X/2-CLOTH_EDGE_INSET-EDGE_CLEARANCE-halfX
 local limitZ=support.Size.Z/2-CLOTH_EDGE_INSET-EDGE_CLEARANCE-halfZ
 assert(limitX>=0 and limitZ>=0,'Lobby toy footprint is larger than its tablecloth: '..record.id)
 local x,z=math.clamp(localCF.Position.X,-limitX,limitX),math.clamp(localCF.Position.Z,-limitZ,limitZ)
 local top=support.Position.Y+(math.abs(support.CFrame.RightVector.Y)*support.Size.X+math.abs(support.CFrame.UpVector.Y)*support.Size.Y+math.abs(support.CFrame.LookVector.Y)*support.Size.Z)/2
 local halfY=(math.abs(cf.RightVector.Y)*size.X+math.abs(cf.UpVector.Y)*size.Y+math.abs(cf.LookVector.Y)*size.Z)/2
 local shift=support.CFrame:VectorToWorldSpace(Vector3.new(x-localCF.Position.X,0,z-localCF.Position.Z))+Vector3.new(0,top-(cf.Position.Y-halfY),0)
 m:PivotTo(m:GetPivot()+shift);record.home=m:GetPivot()
 invoke('lobbyHome',nil,m)
end
local function menu()return state:GetAttribute('Mode')=='Menu'and workspace:GetAttribute('MissionRunning')~=true end
local function clear(p)
 invoke('reset',p);p:SetAttribute('LobbyToyId',nil);p:SetAttribute('LobbyToySpeedMultiplier',nil)
end
local function remove(record)
 record.generation+=1
 local m=record.model;record.model=nil;record.owner=nil;record.releasedAt=nil
 if m then invoke('lobbyRemove',nil,m);m:Destroy()end
end
local function spawn(record)
 remove(record)
 if not menu()then return end
 local m=kit:FindFirstChild(record.id):Clone();m.Name='LobbyToy_'..record.index
 m:SetAttribute('LobbyToy',true);m:SetAttribute('LobbyToyIndex',record.index)
 m:PivotTo(record.base);m.Parent=runtime
 if not invoke('lobbyRegister',nil,m)then m:Destroy();warn('Lobby toy registration failed: '..record.id);return end
 placeOnTable(record,m)
 record.model=m
 local generation=record.generation
 m:GetAttributeChangedSignal('HeldBy'):Connect(function()
  if record.generation~=generation then return end
  local uid=m:GetAttribute('HeldBy');local previous=record.owner
  record.owner=uid and Players:GetPlayerByUserId(uid) or nil
  if previous and previous~=record.owner and previous:GetAttribute('LobbyToyId')==record.id then previous:SetAttribute('LobbyToyId',nil)end
  if record.owner then QuestService.Record(record.owner,'LobbyToyGrab',1,{eventId='toy:'..tostring(record.owner.UserId)..':'..tostring(math.floor(os.time()/86400))..':'..record.id,itemId=record.id,lobbyToy=true});record.owner:SetAttribute('LobbyToyId',record.id);record.releasedAt=nil
  else record.releasedAt=os.clock()end
 end)
end
local spots={}
for _,part in toys:GetDescendants()do if part:IsA('BasePart') and part.Name=='ToySpot'then table.insert(spots,part)end end
table.sort(spots,function(a,b)if a.Position.X~=b.Position.X then return a.Position.X<b.Position.X end;if a.Position.Z~=b.Position.Z then return a.Position.Z<b.Position.Z end;return a.Position.Y<b.Position.Y end)
for i,id in Items do
 local spot=spots[i];local template=kit:FindFirstChild(id)
 if spot and template and template:IsA('Model') and template.PrimaryPart then
  spot:SetAttribute('ItemId',id)
  local support=supportFor(spot);assert(support,'Visible lobby toy table missing for '..id)
  local _,yaw=support.CFrame:ToOrientation()
  local base=CFrame.new(spot.Position.X,support.Position.Y,spot.Position.Z)*CFrame.Angles(0,yaw,0)
  local record={id=id,index=i,base=base,support=support,generation=0}
  records[i]=record;spawn(record)
 else warn('Lobby toy spot/template missing: '..id)end
end
local function bind(p)
 p.CharacterRemoving:Connect(function()if p:GetAttribute('MissionActive')~=true then clear(p)end end)
 p:GetAttributeChangedSignal('MissionActive'):Connect(function()if p:GetAttribute('MissionActive')==true then clear(p)end end)
end
Players.PlayerAdded:Connect(bind);for _,p in Players:GetPlayers()do bind(p)end
Players.PlayerRemoving:Connect(clear)
state:GetAttributeChangedSignal('Mode'):Connect(function()
 if not menu()then for _,p in Players:GetPlayers()do clear(p)end;for _,r in records do remove(r)end
 else for _,r in records do spawn(r)end end
end)
-- The table timer is2Hz; there is no lobby copy of item effects or a per-frame mission simulation.
task.spawn(function()
 while script.Parent do
  task.wait(.5)
  if menu()then for _,r in records do
   local m=r.model
   if not m or not m.Parent or (not m:GetAttribute('HeldBy') and r.releasedAt and os.clock()-r.releasedAt>=15)then spawn(r)end
  end end
 end
end)
if Run:IsStudio()then
 local test=Instance.new('BindableFunction');test.Name='LobbyToyTestApi';test.Parent=SS
 test.OnInvoke=function(action,p,index)
  if action=='pickup'then local r=records[index];if not r or not r.model or not menu()then return false end;local previous=p:GetAttribute('PhysicalGrabActive');p:SetAttribute('PhysicalGrabActive',true);local ok=invoke('pickup',p,r.model);if not ok then p:SetAttribute('PhysicalGrabActive',previous)end;return ok
  elseif action=='drop'then p:SetAttribute('PhysicalGrabActive',nil);return invoke('release',p)
  elseif action=='reset'then clear(p);if index and records[index]then spawn(records[index])end;return true
  elseif action=='list'then local list={};for i,r in records do list[i]={id=r.id,model=r.model,home=r.home,owner=r.owner and r.owner.UserId}end;return list end
  return false
 end
end

