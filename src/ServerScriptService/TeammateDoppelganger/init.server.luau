-- Doppelganger: once per level, an exact copy of one of the players appears somewhere in the mansion,
-- wanders between rooms alongside the monsters and freaks out (sprints, red flashlight). It never hurts anyone.
-- Solo players get their own double. It leaves when the level ends or the copied player leaves.
local Players=game:GetService('Players')
local RS=game:GetService('ReplicatedStorage')
local Http=game:GetService('HttpService')
local Echo=require(script:WaitForChild('TeammateEcho'))
local Topology=require(game.ServerScriptService:WaitForChild('MapGen'):WaitForChild('Topology'))
local SPAWN_DELAY_MIN,SPAWN_DELAY_MAX=40,90 -- seconds into the Searching phase
local MIN_SPAWN_DISTANCE=60 -- studs from every player, so nobody sees it pop in
local SCARE_RADIUS,SCARE_COOLDOWN=10,12 -- a player this close makes it freak out (at most every 12 s)
local ACTIVE_PHASES={Searching=true,Returning=true}
local state=RS:WaitForChild('RecoveryRound',math.huge) -- lobby servers never get one: wait quietly
local current,currentRound,spawnToken=nil,nil,0
local lastScare=0
local function despawn()
 spawnToken+=1
 if current then current:Destroy();current=nil end
end
local function eligible(p)
 local c=p.Character;local h=c and c:FindFirstChildOfClass('Humanoid')
 return p:GetAttribute('MissionActive')==true and not p:GetAttribute('RoundDead') and c and c:GetAttribute('CustomCharacterVersion')
  and c:FindFirstChild('HumanoidRootPart') and h and h.Health>0
end
local function playerRoots()
 local list={}
 for _,p in Players:GetPlayers()do local r=p.Character and p.Character:FindFirstChild('HumanoidRootPart');if r and p:GetAttribute('MissionActive')then table.insert(list,r.Position)end end
 return list
end
-- Walkable room points from the generated map graph, with the real floor found by a short downward ray.
local function roomPoints(map)
 local graphValue=map:FindFirstChild('GeneratedGraph');if not graphValue then return {} end
 local ok,graph=pcall(function()return Http:JSONDecode(graphValue.Value)end);if not ok then return {} end
 local params=RaycastParams.new();params.FilterType=Enum.RaycastFilterType.Include;params.FilterDescendantsInstances={map}
 local points={}
 for _,r in ipairs(graph.rooms or {})do
  if r.type~='Stair'then
   local centre=Topology.Center(r)
   local hit=workspace:Raycast(centre+Vector3.new(0,6,0),Vector3.new(0,-12,0),params)
   if hit then table.insert(points,hit.Position+Vector3.new(0,3.2,0))end
  end
 end
 return points
end
local function spawnFor(round)
 local map=workspace:FindFirstChild('Mansion')
 if not map or map:GetAttribute('RuntimeReady')~=true then return end
 local candidates={};for _,p in Players:GetPlayers()do if eligible(p)then table.insert(candidates,p)end end
 if #candidates==0 then return end
 local copied=candidates[math.random(1,#candidates)]
 local points=roomPoints(map);if #points<2 then return end
 -- Furthest-feeling start: a random room at least MIN_SPAWN_DISTANCE from everyone (fall back to the furthest).
 local roots=playerRoots();local far,best,bestD={},nil,-1
 for _,pt in points do
  local nearest=math.huge;for _,r in roots do nearest=math.min(nearest,(r-pt).Magnitude)end
  if nearest>=MIN_SPAWN_DISTANCE then table.insert(far,pt)end
  if nearest>bestD then best,bestD=pt,nearest end
 end
 local start=#far>0 and far[math.random(1,#far)]or best
 local ok,result=pcall(Echo.Create,copied,CFrame.new(start),points,{mission=true,name='Doppelganger'})
 if not ok then warn('[Doppelganger] '..tostring(result));return end
 current=result;currentRound=round
 local copiedId=copied.UserId
 -- The copy leaves with the player it copied.
 local conn;conn=Players.PlayerRemoving:Connect(function(p)if p.UserId==copiedId and current==result then despawn()end end)
 result.Model.Destroying:Once(function()conn:Disconnect()end)
end
local function phaseChanged()
 local phase=state:GetAttribute('Phase');local round=state:GetAttribute('Round')
 if not ACTIVE_PHASES[phase]or(currentRound and round~=currentRound)then despawn();currentRound=nil end
 if phase=='Searching'and not current then
  spawnToken+=1;local token=spawnToken
  task.delay(math.random(SPAWN_DELAY_MIN,SPAWN_DELAY_MAX),function()
   if token==spawnToken and not current and state:GetAttribute('Phase')=='Searching'then spawnFor(state:GetAttribute('Round'))end
  end)
 end
end
state:GetAttributeChangedSignal('Phase'):Connect(phaseChanged)
state:GetAttributeChangedSignal('Round'):Connect(phaseChanged)
phaseChanged()
-- A player walking right up to it makes it bolt (a scare, never an attack).
task.spawn(function()
 while true do
  task.wait(.25)
  if current and current.Model.Parent and os.clock()-lastScare>SCARE_COOLDOWN then
   local root=current.Model:FindFirstChild('HumanoidRootPart')
   if root then for _,r in playerRoots()do if (r-root.Position).Magnitude<SCARE_RADIUS then lastScare=os.clock();current:Freakout();break end end end
  end
 end
end)
