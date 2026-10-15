-- Cosmetic look direction only; movement remains owned by the existing controllers.
local Players=game:GetService('Players')
local event=game.ReplicatedStorage:WaitForChild('CharacterLook')
local states={}
local function finite(n) return type(n)=='number' and n==n and math.abs(n)<math.huge end
event.OnServerEvent:Connect(function(p,yaw,pitch,seq,targetPoint)
    if not finite(yaw) or not finite(pitch) or not finite(seq) or seq%1~=0 or seq<0 or seq>9007199254740991 then return end
    if math.abs(yaw)>1.3 or math.abs(pitch)>1.2 then return end
    local now=os.clock();local previous=states[p]
    if previous and (now-previous.time<1/16 or seq<=previous.seq) then return end
    local c=p.Character;local h=c and c:FindFirstChildOfClass('Humanoid')
    if not c or not c:GetAttribute('CustomCharacterVersion') or not h or h.Health<=0 then return end
    local head=c:FindFirstChild('Head')
    if typeof(targetPoint)~='Vector3' or not head then return end
    if not finite(targetPoint.X) or not finite(targetPoint.Y) or not finite(targetPoint.Z) then return end
    if (targetPoint-head.Position).Magnitude>500 or (targetPoint-head.Position).Magnitude<.1 then return end
    states[p]={time=now,seq=seq}
    event:FireAllClients(p,yaw,pitch,workspace:GetServerTimeNow(),targetPoint)
end)
Players.PlayerRemoving:Connect(function(p) states[p]=nil end)


-- The existing character motion owner chooses occasional shared eye-contact targets.
local Gaze=require(game.ReplicatedStorage:WaitForChild('SocialGazeRules'))
local random=Random.new()
local social={}
local function clearGaze(p)
 p:SetAttribute('SocialGazeUserId',nil);p:SetAttribute('SocialGazeUntil',nil)
end
local function watchGaze(p)
 social[p]={nextAt=os.clock()+random:NextNumber(5,12)}
 p.CharacterRemoving:Connect(function()clearGaze(p);social[p]={nextAt=os.clock()+random:NextNumber(5,12)}end)
end
Players.PlayerAdded:Connect(watchGaze)
Players.PlayerRemoving:Connect(function(p)
 social[p]=nil
 for viewer,s in pairs(social)do if s.target==p then s.target=nil;clearGaze(viewer)end end
end)
for _,p in ipairs(Players:GetPlayers())do watchGaze(p)end
task.spawn(function()
 while true do
  task.wait(.35)
  local now=os.clock();local serverNow=workspace:GetServerTimeNow()
  for p,s in pairs(social)do
   if s.target then
    if serverNow>=s.untilAt or not s.target.Parent or not Gaze.CanLook(p,s.target)then
     s.target=nil;clearGaze(p);s.nextAt=now+random:NextNumber(8,18)
    end
   elseif now>=s.nextAt then
    s.nextAt=now+random:NextNumber(8,18)
    if Gaze.Available(p)and random:NextNumber()<.75 then
     local candidates={}
     for _,other in ipairs(Players:GetPlayers())do if Gaze.CanLook(p,other)then table.insert(candidates,other)end end
     if #candidates>0 then
      s.target=candidates[random:NextInteger(1,#candidates)]
      s.untilAt=serverNow+random:NextNumber(2.5,4.5)
      p:SetAttribute('SocialGazeUntil',s.untilAt)
      p:SetAttribute('SocialGazeUserId',s.target.UserId)
     end
    end
   end
  end
 end
end)
