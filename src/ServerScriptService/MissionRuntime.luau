local RunSaves=require(script.Parent.RunSavesService)
local M={started=false}
local names={'CursedItemsServer','KeyDoorServer','InteractServer','RecoveryRoundServer','CreatureRoamServer','GameplaySoundServer','MonsterMimic'} -- CruiseBoatServer removed: the cruise boat is gone, the script stays disabled
function M.Start(players,saveTicket,ownerUserId)
 if not game:GetService('RunService'):IsStudio()then
  assert(game.PrivateServerId~=''and game.PrivateServerOwnerId==0,'Mission cannot run in a public lobby')
 end
 for _,player in players do assert(player:GetAttribute('MissionAuthorized')==true,'Player was not admitted to this mission')end
 local restarting=M.started
 if restarting then
  for _,player in game.Players:GetPlayers()do
   if player:GetAttribute('MissionActive')==true then return false,'A mission is already running.'end
  end
  if not game:GetService('RunService'):IsStudio()then return false,'Rejoin the main lobby to start another mission.'end
  local round=game.ServerScriptService:FindFirstChild('RecoveryRoundServer')
  if not round or not round:FindFirstChild('RestartMission')then return false,'The previous mission is still closing. Please try again.'end
 end
 local ok,context=RunSaves.BeginMission(ownerUserId,saveTicket,players)
 if not ok then return false,context end
 M.started=true;workspace:SetAttribute('MissionRunning',true)
 for _,p in players do p:SetAttribute('ReturnedToLobby',nil);p:SetAttribute('MissionActive',true);p:SetAttribute('LobbyReady',false)end
 for _,name in names do local script=game.ServerScriptService:FindFirstChild(name);if script and not script.Enabled then script.Enabled=true end end
 if restarting then
  local restarted,reason=game.ServerScriptService.RecoveryRoundServer.RestartMission:Invoke(ownerUserId)
  if not restarted then
   local released,releaseError=RunSaves.AbortMissionStart()
   workspace:SetAttribute('MissionRunning',false)
   for _,p in players do
    p:SetAttribute('MissionActive',false);p:SetAttribute('MissionAuthorized',false);p:SetAttribute('ReturnedToLobby',true);p:SetAttribute('LobbyReady',true)
    p:SetAttribute('RoundDead',nil);p:SetAttribute('Reviving',nil);p:SetAttribute('LeavingRun',nil)
    task.spawn(function()if p.Parent==game.Players then p:LoadCharacterAsync()end end)
   end
   return false,released and reason or tostring(reason)..' '..tostring(releaseError)
  end
 end
 return true
end
return M
