-- Retention metrics -> Creator Dashboard > Analytics > Custom events. Read-only observer: it only
-- watches existing attributes (MissionActive, RoundDead, RecoveryRound.Round/Phase) and never changes gameplay.
local Players=game:GetService('Players');local Analytics=game:GetService('AnalyticsService')
local RS=game:GetService('ReplicatedStorage');local Run=game:GetService('RunService')
local F1,F2,F3=Enum.AnalyticsCustomFieldKeys.CustomField01.Name,Enum.AnalyticsCustomFieldKeys.CustomField02.Name,Enum.AnalyticsCustomFieldKeys.CustomField03.Name
local LAST_EVENT_WINDOW=60 -- a quit within this many seconds is blamed on the last event
local state=RS:FindFirstChild('RecoveryRound') -- missing on lobby servers; resolved lazily below
local S={}
local function log(p,name,value,fields)
 if Run:IsStudio()then return end -- keep test sessions out of live numbers
 pcall(function()Analytics:LogCustomEvent(p,name,value,fields)end)
end
local function roundBucket()local r=state and state:GetAttribute('Round')or 0;return r<=0 and 'Lobby'or r>=10 and 'Level 10+'or 'Level '..r end
local function phase()return tostring(state and state:GetAttribute('Phase')or 'None')end
local function aliveNow(p)return p:GetAttribute('MissionActive')==true and p:GetAttribute('RoundDead')~=true end
local function bucketSeconds(s)return s<30 and '<30s'or s<120 and '30s-2m'or s<300 and '2-5m'or s<900 and '5-15m'or '15m+'end
local function event(s,name)s.lastEvent=name;s.lastEventAt=os.clock()end
local function settleAlive(s,p)
 if s.aliveSince then s.aliveTotal+=os.clock()-s.aliveSince;s.aliveSince=nil end
 if aliveNow(p)then s.aliveSince=os.clock()end
end
local function deathCause(p)
 if p:GetAttribute('MonsterJumpscareActive')then return 'Monster'end
 local c=p.Character;local r=c and c:FindFirstChild('HumanoidRootPart')
 if r and r.Position.Y<-20 then return 'Fell'end
 return 'Other'
end
-- Onboarding funnel -> Creator Dashboard > Analytics > Funnels. Each step logs once per player (Roblox keeps the
-- first), from lobby and mission servers alike; team steps (6-8) count for everyone in the mission.
local FUNNEL={'Joined','Joined party','Mission started','In the van','Grabbed cart','First item in cart','First sale','Level cleared'}
local function funnel(p,s,step)
 if s.funnel[step]then return end;s.funnel[step]=true
 if Run:IsStudio()then return end
 pcall(function()Analytics:LogOnboardingFunnelStepEvent(p,step,FUNNEL[step])end)
end
local function track(p)
 local s={joined=os.clock(),deaths=0,retries=0,revives=0,aliveTotal=0,lastEvent='Joined',lastEventAt=os.clock(),diedSinceStart=false,funnel={}}
 S[p]=s
 funnel(p,s,1)
 p:GetAttributeChangedSignal('MissionActive'):Connect(function()
  if p:GetAttribute('MissionActive')==true then
   s.lifeStart=os.clock()
   if s.diedSinceStart then s.retries+=1;event(s,'RetryAfterDeath');log(p,'RetryAfterDeath',s.retries,{[F1]=roundBucket()})
   else event(s,'MissionStart')end
   s.diedSinceStart=false
  else event(s,'MissionEnded')end
  settleAlive(s,p)
 end)
 p:GetAttributeChangedSignal('RoundDead'):Connect(function()
  if p:GetAttribute('MissionActive')~=true then settleAlive(s,p);return end
  if p:GetAttribute('RoundDead')==true then
   s.deaths+=1;s.diedSinceStart=true
   local life=s.lifeStart and os.clock()-s.lifeStart or 0
   local cause=deathCause(p)
   event(s,'Death:'..cause)
   log(p,'TimeAliveBeforeDeath',math.floor(life),{[F1]=roundBucket(),[F2]=cause,[F3]=phase()})
  else
   s.revives+=1;s.lifeStart=os.clock();event(s,'Revived')
   log(p,'Revive',1,{[F1]=roundBucket()})
  end
  settleAlive(s,p)
 end)
end
local function onPhase()
 local ph=phase()
 if ph=='Failed'or ph=='Won'then for p,s in S do if p:GetAttribute('MissionActive')then event(s,'Round'..ph)end end end
end
local function bindState(obj)if obj.Name=='RecoveryRound'then state=obj;obj:GetAttributeChangedSignal('Phase'):Connect(onPhase)end end
if state then bindState(state)else RS.ChildAdded:Connect(function(c)if not state then bindState(c)end end)end
Players.PlayerAdded:Connect(track)
for _,p in Players:GetPlayers()do track(p)end
task.spawn(function()
 while true do
  task.wait(1)
  local map=workspace:FindFirstChild('Mansion');local items=map and map:FindFirstChild('Interactive')
  local cart=items and items:FindFirstChild('RecoveryCart')
  for p,s in S do
   if p:GetAttribute('LobbyPartyId')then funnel(p,s,2)end
   if p:GetAttribute('MissionActive')==true then
    funnel(p,s,3)
    if p.Character and p.Character:GetAttribute('RecoverySpawnReady')==true then funnel(p,s,4)end
    if cart and cart:GetAttribute('HeldBy')==p.UserId then funnel(p,s,5)end
    if state then
     if(state:GetAttribute('CartValue')or 0)>0 or(state:GetAttribute('Sold')or 0)>0 then funnel(p,s,6)end
     if(state:GetAttribute('Sold')or 0)>0 then funnel(p,s,7)end
     if state:GetAttribute('Phase')=='Won'then funnel(p,s,8)end
    end
   end
  end
 end
end)
Players.PlayerRemoving:Connect(function(p)
 local s=S[p];S[p]=nil;if not s then return end
 settleAlive(s,p);if s.aliveSince then s.aliveTotal+=os.clock()-s.aliveSince end
 local session=os.clock()-s.joined
 local where=p:GetAttribute('MissionActive')~=true and 'Lobby/Menu'or p:GetAttribute('RoundDead')==true and 'Dead/Spectating'or 'Alive in mission'
 local cause=os.clock()-s.lastEventAt<=LAST_EVENT_WINDOW and s.lastEvent or 'Nothing recent'
 local fields={[F1]=where,[F2]=roundBucket(),[F3]=cause}
 log(p,'Quit',math.floor(session),fields)
 log(p,'DeathsBeforeQuit',s.deaths,{[F1]=where,[F2]=bucketSeconds(session)})
 log(p,'TimeAliveBeforeQuit',math.floor(s.aliveTotal),{[F1]=where,[F2]=roundBucket()})
 log(p,'RetriesAfterDeath',s.retries,{[F1]=s.deaths>0 and 'Died at least once'or 'Never died'})
end)
