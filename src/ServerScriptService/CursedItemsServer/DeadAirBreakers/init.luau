-- Dead-air breakers (WorldB 2026-10-27; shared host for FlickerTrail / TattleMouse / RingingWallPhone, see World_shared.md). GameDiagnosis 10-26: 52% of mid-level quits had nothing happen in the 60 s
-- before; players wander looking for items 2-5 on level 1. When a player (and the team) has gone a while without
-- finding or storing loot, the level does something fun that also points at the nearest free item.
-- CursedItemsServer owns loot, so it owns this. Each breaker is a child ModuleScript returning
-- function(core) -> {name, after=seconds, budget={[level]=uses per player}, run(p,target,level,root) (yields until done), clear()}.
-- Progress: this player grabs an item never stored before (HeldBy), or an item they carried is stored (CargoStored).
-- The clock pauses while dead, outside Searching, during the intro and with a monster within 35 studs.
-- Level 1 full, level 2 thresholds x1.5, level 3+ off. Nothing is saved. Clients render from attributes:
-- item HintFor/HintUntil/HintStyle/HintRattleAt (TutorialClient), player TrailPath/TrailStart/TrailUntil (MonsterLightFlickerClient).
local Players=game:GetService('Players')
local RS=game:GetService('ReplicatedStorage')
local SS=game:GetService('ServerStorage')
local Run=game:GetService('RunService')
local Pathfinding=game:GetService('PathfindingService')
local M={}

local TICK=1 -- seconds between checks
local MONSTER_PAUSE=35 -- studs: a monster this close is not boredom, the clock pauses
local TEAM_SHARE=.5 -- a teammate's progress within this share of the threshold holds the breaker back
local GAP=8 -- seconds between two breakers for the same player
local MAX_ACTIVE=2 -- breakers running at once on the whole map
local SCALE={[1]=1,[2]=1.5} -- threshold multiplier per level; no entry = off (level 3+)
local FIRST_GAME_SCALE=.8 -- TutorialDone == false: a little sooner
local KEYS={'LootProgressAt','DeadAirLast','TrailPath','TrailStart','TrailUntil'}
local ITEM_KEYS={'HintFor','HintUntil','HintStyle','HintRattleAt'}

local ctx,roundState,rooms
local gen=0
local last,used,busy,nextAt,published={},{},{},{},{}
local stored=setmetatable({},{__mode='k'}) -- item -> true once it has been in the cart
local hinted=setmetatable({},{__mode='k'}) -- items carrying hint attributes, for cleanup
local breakers,byName={},{}

local function now()return workspace:GetServerTimeNow()end
local function living(p)
 local c=p and p.Parent and p.Character;local h=c and c:FindFirstChildOfClass('Humanoid')
 if h and h.Health>0 and p:GetAttribute('MissionActive')==true and p:GetAttribute('RoundDead')~=true then return c:FindFirstChild('HumanoidRootPart')end
end
local function progress(p)
 if not(p and p.Parent)then return end
 local t=now();last[p]=t
 if t-(published[p]or 0)>=2 then published[p]=t;p:SetAttribute('LootProgressAt',t)end
end
local function interactive()return ctx and ctx.map:FindFirstChild('Interactive')end
local function lockedRooms(items)
 local set={}
 for _,d in items:GetChildren()do if d:GetAttribute('Kind')=='door'and d:GetAttribute('Locked')and d:GetAttribute('Room')then set[d:GetAttribute('Room')]=true end end
 return set
end
-- Same "loose loot" test CursedItemsServer uses for its 'bring' admin action, plus the tutorial's locked-room rule.
local function free(m,locked)
 return m:IsA('Model')and m.PrimaryPart~=nil and m:GetAttribute('Kind')=='pickup'and m:GetAttribute('ItemId')~=nil
  and not m:GetAttribute('HeldBy')and not m:GetAttribute('CargoStored')and not m:GetAttribute('AttachedTo')
  and not m:GetAttribute('ItemWearOwner')and not m:GetAttribute('FaceOwner')and not m:GetAttribute('MonsterCarried')
  and not m:GetAttribute('Selling')and not m:GetAttribute('Gear')and not m:GetAttribute('AdminSpawned')
  and not m:GetAttribute('LobbyToy')and not m:GetAttribute('Locked')and not locked[m:GetAttribute('Room')or false]
end
local function nearest(items,root,locked)
 local best,bd=nil,math.huge;local from=root.Position;local t=now()
 for _,m in items:GetChildren()do
  if free(m,locked)and not((m:GetAttribute('HintUntil')or 0)>t)then -- one breaker per item at a time
   local q=m.PrimaryPart.Position;local d=(q-from).Magnitude+math.abs(q.Y-from.Y)*4 -- other floors cost more, like the tutorial's pick
   if d<bd then best,bd=m,d end
  end
 end
 return best
end
local function unmark(m)for _,k in ITEM_KEYS do if m:GetAttribute(k)~=nil then m:SetAttribute(k,nil)end end;hinted[m]=nil end
local function monsterNear(pos,radius)
 local folder=workspace:FindFirstChild('RoamingCreatures');if not folder then return false end
 for _,c in folder:GetChildren()do if c:IsA('Model')and(c:GetPivot().Position-pos).Magnitude<radius then return true end end
 return false
end
local function activeCount()local n=0;for _ in busy do n+=1 end;return n end
local function storedOrSold()
 local items=interactive();local n=roundState and(roundState:GetAttribute('Sold')or 0)or 0
 if items then for _,m in items:GetChildren()do if m:GetAttribute('CargoStored')then n+=1 end end end
 return n
end

-- core API for breaker modules ------------------------------------------------------------------------------
M.Now=now
-- Funny reactions (shared contracts): M.Fx(p,'grin'|'gasp'|...,sec) = FaceBeat face (VoiceMouthClient); M.Pop(p,'Squeak!',shake) = ReactPop word (+ camera jolt 0..1, CurseEffectsClient)
function M.Fx(p,mood,seconds)if p and p.Parent then p:SetAttribute('FaceBeat',mood);p:SetAttribute('FaceBeatUntil',now()+seconds)end end
function M.Pop(p,text,shake)if p and p.Parent then p:SetAttribute('ReactPop',text);p:SetAttribute('ReactPopShake',shake or 0);p:SetAttribute('ReactPopAt',now())end end
M.Living=living
M.MonsterNear=monsterNear
function M.Map()return ctx.map end
function M.Audio()return ctx.Audio end
function M.Say(p,text)ctx.say(p,text)end
function M.Speech(pos,text)ctx.event:FireAllClients('speech',pos,text)end -- the bubble the antique Telephone item uses
function M.Generation()return gen end
function M.Same(g)return g==gen end
function M.Free(m)local items=interactive();return items~=nil and m~=nil and m.Parent==items and free(m,lockedRooms(items))end
function M.Nearest(root)local items=interactive();return items and nearest(items,root,lockedRooms(items))end
function M.Folder() -- breaker props that are not grabbable live here (not in Interactive), cleared with the level
 local f=ctx.map:FindFirstChild('DeadAirFx');if not f then f=Instance.new('Folder');f.Name='DeadAirFx';f.Parent=ctx.map end;return f
end
function M.Mark(m,p,seconds,style)
 if not(m and m.Parent)then return end
 m:SetAttribute('HintFor',p and p.UserId or 0);m:SetAttribute('HintUntil',now()+seconds);m:SetAttribute('HintStyle',style or 'glint');hinted[m]=true
end
function M.Rattle(m)
 if not(m and m.Parent and m.PrimaryPart)then return end
 m:SetAttribute('HintRattleAt',now());hinted[m]=true;ctx.Audio.Play('ItemRattle',m) -- not a MonsterEvidence noise key
end
-- Floor point beside an item, on the side facing `from` (navigation ends beside furniture, never on the tabletop).
function M.Beside(m,from)
 local q=m.PrimaryPart.Position;local away=Vector3.new(from.X-q.X,0,from.Z-q.Z)
 return away.Magnitude>.1 and q+away.Unit*3 or q
end
function M.Path(from,to) -- yields; floor waypoints + true, or a straight two-point line + false when there is no path
 local path=Pathfinding:CreatePath({AgentRadius=1.8,AgentHeight=5,AgentCanJump=false,WaypointSpacing=4})
 local ok=pcall(function()path:ComputeAsync(from,to)end)
 local out={}
 if ok and path.Status==Enum.PathStatus.Success then for _,w in path:GetWaypoints()do out[#out+1]=w.Position end end
 path:Destroy()
 local found=#out>=2
 if not found then out={from-Vector3.new(0,2.6,0),to}end
 return out,found
end
function M.Refund(p,name) -- a breaker that could not show itself (no wall, no path) gives its use back
 if used[p]and used[p][name]then used[p][name]=math.max(0,used[p][name]-1)end
end
function M.Where(m) -- "upstairs, in the master bedroom" / "in the kitchen" from GeneratedGraph (decoded once per level)
 if not rooms then
  rooms={};local g=ctx.map:FindFirstChild('GeneratedGraph')
  local ok,graph=pcall(function()return game:GetService('HttpService'):JSONDecode(g.Value)end)
  if ok and graph and graph.rooms then for _,r in graph.rooms do rooms[r.name]=r end end
 end
 local r=rooms[m:GetAttribute('Room')or false]
 if not r then return 'in one of the rooms'end
 local kind=tostring(r.purpose or r.type or 'room'):gsub('(%l)(%u)','%1 %2'):lower()
 return((r.level or 0)>=1 and 'upstairs, in the 'or 'in the ')..kind
end

-- progress watchers -----------------------------------------------------------------------------------------
local function watchModel(m)
 if not m:GetAttribute('ItemId')then return end
 m:GetAttributeChangedSignal('HeldBy'):Connect(function()
  local id=m:GetAttribute('HeldBy');if not id then return end
  if hinted[m]then unmark(m)end -- found: the hint is done
  local p=Players:GetPlayerByUserId(id)
  if p and not stored[m]then progress(p)end
 end)
 m:GetAttributeChangedSignal('CargoStored'):Connect(function()
  if m:GetAttribute('CargoStored')and not stored[m]then
   stored[m]=true;if hinted[m]then unmark(m)end
   progress(Players:GetPlayerByUserId(m:GetAttribute('LastOwner')or 0))
  end
 end)
end

local function start(p,b,target,level,root)
 used[p]=used[p]or{};used[p][b.name]=(used[p][b.name]or 0)+1
 local token={name=b.name};busy[p]=token
 p:SetAttribute('DeadAirLast',b.name..'#'..used[p][b.name])
 task.spawn(function()
  local ok,err=pcall(b.run,p,target,level,root)
  if not ok then warn('[DeadAir] '..b.name..': '..tostring(err))end
  if busy[p]==token then busy[p]=nil;nextAt[p]=now()+GAP end
 end)
end

local acc=0
local function tick(dt)
 acc+=dt;if acc<TICK then return end;local step=acc;acc=0
 if not roundState then return end
 local items=interactive();if not items then return end
 local level=roundState:GetAttribute('Round')or 0;local searching=roundState:GetAttribute('Phase')=='Searching'
 local t=now()
 local holding={};for _,m in items:GetChildren()do local id=m:GetAttribute('HeldBy');if id and m:GetAttribute('ItemId')then holding[id]=true end end
 local team=-math.huge
 for _,p in Players:GetPlayers()do
  local r=living(p);last[p]=last[p]or t
  if r and holding[p.UserId]then last[p]=t end
  if not r or not searching or p:GetAttribute('IntroPlaying')==true or monsterNear(r.Position,MONSTER_PAUSE)then last[p]=math.min(t,last[p]+step)end -- paused
  if r then team=math.max(team,last[p])end
 end
 local scale=SCALE[level]
 if not scale or not searching or #breakers==0 then return end
 if(roundState:GetAttribute('Sold')or 0)+(roundState:GetAttribute('CartValue')or 0)>=(roundState:GetAttribute('Quota')or math.huge)then return end
 local locked;local firstLoot=storedOrSold()==0 and not(Run:IsStudio()and SS:GetAttribute('DeadAirIgnoreTutorial')==true) -- Studio tests skip the tutorial rule
 for _,p in Players:GetPlayers()do
  if activeCount()>=MAX_ACTIVE then return end
  local r=living(p)
  if r and not busy[p]and t>=(nextAt[p]or 0)and not holding[p.UserId]and not(firstLoot and p:GetAttribute('TutorialDone')==false)then
   local s=scale*(p:GetAttribute('TutorialDone')==false and FIRST_GAME_SCALE or 1)
   local quiet,teamQuiet=t-last[p],t-team
   for i=#breakers,1,-1 do -- strongest due breaker with budget left wins
    local b=breakers[i];local u=used[p]and used[p][b.name]or 0
    if quiet>=b.after*s and teamQuiet>=b.after*s*TEAM_SHARE and u<(b.budget[level]or 0)then
     locked=locked or lockedRooms(items)
     local target=nearest(items,r,locked)
     if target then start(p,b,target,level,r)end
     break
    end
   end
  end
 end
end

function M.ClearLevel()
 if not ctx then return end
 gen+=1;rooms=nil
 for _,b in breakers do if b.clear then pcall(b.clear)end end
 for m in hinted do if m.Parent then unmark(m)end end;table.clear(hinted)
 table.clear(used);table.clear(busy);table.clear(nextAt)
 local f=ctx.map:FindFirstChild('DeadAirFx');if f then f:ClearAllChildren()end
 local t=now()
 for _,p in Players:GetPlayers()do last[p]=t;for _,k in KEYS do if p:GetAttribute(k)~=nil then p:SetAttribute(k,nil)end end end
end

-- ctx: map, Audio (GameplayAudioServer), say(p,text), event (CursedEvent)
function M.Init(c) -- runs again on every CursedItemsServer reboot (once per level): start from empty lists
 ctx=c;table.clear(breakers);table.clear(byName)
 for _,child in script:GetChildren()do
  if child:IsA('ModuleScript')then
   local ok,b=pcall(function()return require(child)(M)end)
   if ok and type(b)=='table'then table.insert(breakers,b);byName[b.name]=b else warn('[DeadAir] '..child.Name..' failed: '..tostring(b))end
  end
 end
 table.sort(breakers,function(a,b)return a.after<b.after end)
 task.spawn(function()
  local items=ctx.map:WaitForChild('Interactive')
  for _,m in items:GetChildren()do watchModel(m)end
  items.ChildAdded:Connect(watchModel)
 end)
 local function track(p)
  last[p]=now()
  p:GetAttributeChangedSignal('RoundDead'):Connect(function()if p:GetAttribute('RoundDead')~=true then progress(p)end end) -- revived: fresh start
 end
 for _,p in Players:GetPlayers()do track(p)end
 Players.PlayerAdded:Connect(track)
 Players.PlayerRemoving:Connect(function(p)last[p]=nil;used[p]=nil;busy[p]=nil;nextAt[p]=nil;published[p]=nil end)
 Run.Heartbeat:Connect(tick)
 task.spawn(function()
  roundState=RS:WaitForChild('RecoveryRound',math.huge)
  roundState:GetAttributeChangedSignal('Round'):Connect(M.ClearLevel)
  roundState:GetAttributeChangedSignal('Phase'):Connect(function()
   local phase=roundState:GetAttribute('Phase')
   if phase=='Won'or phase=='Failed'or phase=='Deploying'then M.ClearLevel()
   elseif phase=='Searching'then local t=now();for _,p in Players:GetPlayers()do last[p]=t end end
  end)
 end)
 -- Test hook (rbxdev scenarios): 'state' anywhere; 'age' / 'fire' only in Studio.
 local api=SS:FindFirstChild('DeadAirApi')or Instance.new('BindableFunction');api.Name='DeadAirApi';api.Parent=SS
 api.OnInvoke=function(action,p,a)
  if action=='state'then return{quiet=p and last[p]and now()-last[p]or -1,busy=p and busy[p]and busy[p].name or nil,used=p and used[p]or{},breakers=#breakers}end
  if not Run:IsStudio()then return nil end
  if action=='age'then last[p]=(last[p]or now())-(tonumber(a)or 60);return true end
  if action=='fire'then
   local b=byName[a];local r=living(p);local items=interactive()
   if not(b and r and items)then return false end
   local target=nearest(items,r,lockedRooms(items));if not target then return false end
   start(p,b,target,roundState and roundState:GetAttribute('Round')or 1,r);return true
  end
 end
end

return M
