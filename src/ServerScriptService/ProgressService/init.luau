local Players=game:GetService('Players')
local RS=game:GetService('ReplicatedStorage')
local Run=game:GetService('RunService')
local DSS=game:GetService('DataStoreService')
local Http=game:GetService('HttpService')
local Core=require(script.Parent.ProgressCore)
local Q=require(script.Parent.QuestService)
local RankRating=require(script.Parent.RankRating)
local Ranks=require(RS:WaitForChild('RankCatalog'))
-- Rank events for the client: 'rr' (this player's RR change) and 'rankUp' (everyone, for banners and name tag glow).
local RankEvent=RS:FindFirstChild('RankEvent')or Instance.new('RemoteEvent');RankEvent.Name='RankEvent';RankEvent.Parent=RS
local Analytics=game:GetService('AnalyticsService')
local C=require(RS.LobbyShopCatalog)
local studio=Run:IsStudio()
local suffix=studio and '_Studio' or ''
local LOCAL_REVIEW=studio and game.PlaceId==0 and game.GameId==0
local STUDIO_MEMORY=LOCAL_REVIEW or game:GetService('RunService'):IsStudio()and workspace:GetAttribute('StudioDataStores')~=true -- Studio playtests keep saves in memory: stopping during a DataStore call hangs Studio. Workspace StudioDataStores=true tests real saves
local store
local ordered={}
if not STUDIO_MEMORY then
 store=DSS:GetDataStore('DontDieHereProgress_v1'..suffix)
 for _,cat in C.Categories do ordered[cat.id]=DSS:GetOrderedDataStore('DDH_'..cat.id..'_v1'..suffix)end
end
local data,loaded,loading,busy,mode,queue,boardCache,nameCache={},{},{},{},{},{},{},{}
local M={}
-- Players with unlimited revives (UserId): reviving never spends a token and they always show 999.
local UNLIMITED_REVIVES={[2565716611]=true} -- DRAGONAMANDA15
local rewardDepartureFlush
-- Personal saves still include developer progress; only competitive ranking excludes it.
local EXCLUDED_USER_IDS={[315936607]=true}
local creatorIsGroup=game.CreatorType==Enum.CreatorType.Group
local eligibility=require(script:WaitForChild('LeaderboardEligibility')).new(EXCLUDED_USER_IDS,
 not creatorIsGroup and game.CreatorId or nil,not creatorIsGroup)
local excludedIndexes,orderedAttempts=0,0
local orderedAttemptsByUser={}
local cleanupResults,cleanupBusy={},false
if creatorIsGroup then
 task.spawn(function()
  local Groups=game:GetService('GroupService')
  while not eligibility.CreatorReady() do
   local ok,info=pcall(function()return Groups:GetGroupInfoAsync(game.CreatorId)end)
   if ok and type(info)=='table' then
    eligibility.ResolveCreator(info.Owner and info.Owner.Id)
    boardCache={}
    script:SetAttribute('LeaderboardCreatorStatus','Resolved')
   else
    script:SetAttribute('LeaderboardCreatorStatus','Retrying group owner lookup')
    task.wait(30)
   end
  end
 end)
else script:SetAttribute('LeaderboardCreatorStatus','Resolved')end
function M.LeaderboardDiagnostics()
 return {creatorReady=eligibility.CreatorReady(),excludedUserIds=eligibility.ExcludedIds(),
  excludedIndexes=excludedIndexes,orderedAttempts=orderedAttempts,orderedAttemptsByUser=table.clone(orderedAttemptsByUser),
  cleanupBusy=cleanupBusy,cleanup=table.clone(cleanupResults)}
end
-- Server-only, explicitly invoked maintenance. Successful keys are never deleted twice in this session.
function M.RemoveExcludedLeaderboardEntries(includeProduction)
 if STUDIO_MEMORY then return false,'Leaderboard maintenance is disabled in the local review copy.'end
 if not eligibility.CreatorReady()then return false,'Creator lookup is still pending.'end
 if cleanupBusy then return false,'Leaderboard cleanup is already running.'end
 cleanupBusy=true
 local namespaces={suffix}
 if includeProduction==true and suffix~=''then table.insert(namespaces,'')end
 local allOk=true
 for _,namespace in namespaces do
  for _,cat in C.Categories do
   for _,userId in eligibility.ExcludedIds()do
    local storeName='DDH_'..cat.id..'_v1'..namespace
    local key='player_'..userId
    local identity=storeName..'/'..key
    local previous=cleanupResults[identity]
    if not previous or previous.ok~=true then
     local target=namespace==suffix and ordered[cat.id]or DSS:GetOrderedDataStore(storeName)
     local result={store=storeName,key=key,userId=userId,ok=false}
     for attempt=1,3 do
      result.attempts=attempt
      local ok,value=pcall(function()return target:RemoveAsync(key)end)
      if ok then result.ok=true;result.removedValue=value;break end
      result.error=tostring(value);task.wait(attempt)
     end
     cleanupResults[identity]=result
     if not result.ok then allOk=false end
    end
   end
  end
 end
 boardCache={};cleanupBusy=false
 return allOk,M.LeaderboardDiagnostics()
end
local Marketplace=game:GetService('MarketplaceService')
local entitlements={}
-- Owner test mode (AdminPowersServer sets AdminSimulateNoPasses): this session acts as if the player owns no game
-- passes. Only what the game reads and shows is filtered; the saved data and Roblox ownership are never changed.
local PASS_ITEMS={title_vip=true,aura_vip=true};for _,offer in C.RobuxOffers do if offer.grants then PASS_ITEMS[offer.grants]=true end end
-- Studio StudioNewPlayer=true: no passes at all, like a brand-new player (the owner owns them for real).
-- Studio StudioNoPasses=true: passes off but owner powers kept (admin panel works); owner 2026-10-26.
local function simulateNoPasses(p) return p:GetAttribute('AdminSimulateNoPasses')==true or studio and(workspace:GetAttribute('StudioNewPlayer')==true or workspace:GetAttribute('StudioNoPasses')==true)end
local function shownEquipped(p,d)
 if not simulateNoPasses(p) then return d.Equipped end
 local out=table.clone(d.Equipped);for slot,id in out do if PASS_ITEMS[id] then out[slot]='' end end;return out
end
local function shownOwned(p,d)
 local out=table.clone(d.Owned);if simulateNoPasses(p) then for id in PASS_ITEMS do out[id]=nil end end;return out
end
local function notify(p,message)local e=RS:FindFirstChild('LobbyEvent');if e and p.Parent then e:FireClient(p,'notice',message)end end
local paidStep={} -- [player] = RRRewardStep as of the last setRank: which rank steps a rank-up has newly paid
local function setRank(p)
 local d=data[p];if not d then return end
 paidStep[p]=d.RRRewardStep or 1;p:SetAttribute('RRRewardStep',d.RRRewardStep or 1)
 local r=Ranks.Get(d.RR);p:SetAttribute('Rank',r.name);p:SetAttribute('RankTier',r.tier);p:SetAttribute('RankDivision',r.division);p:SetAttribute('RR',d.RR)
 p:SetAttribute('RRStreak',d.RRStreak or 0);p:SetAttribute('RRSeasonPeakTier',d.RRSeasonPeaks and d.RRSeasonPeaks[tostring((d.RRSeason or 0)-1)]or 0)
 p:SetAttribute('RRMaster',d.Owned~=nil and d.Owned.title_monstermaster==true)
 -- Spook-o-Meter (WorldB 2026-10-27): the lobby meter shows the daily first-clear bonus, its streak step and the season peak.
 p:SetAttribute('RRDay',d.RRDay or 0);p:SetAttribute('RRPeak',d.RRPeak or 0)
 p:SetAttribute('RRDailyMult',RankRating.DAILY);p:SetAttribute('RRStreakMult',RankRating.STREAK);p:SetAttribute('RRStreakDays',RankRating.STREAK_DAYS)
end
-- Rank icon left of the name; an empty spacer on the right keeps the name centred over the head.
local function rankBadge(gui,p)
 setRank(p)
 local d=data[p];if not d then return end;local r=Ranks.Get(d.RR)
 local list=Instance.new('UIListLayout');list.FillDirection=Enum.FillDirection.Horizontal;list.HorizontalAlignment=Enum.HorizontalAlignment.Center;list.VerticalAlignment=Enum.VerticalAlignment.Center;list.Padding=UDim.new(0,5);list.SortOrder=Enum.SortOrder.LayoutOrder;list.Parent=gui
 local badge=Instance.new('Frame');badge.Name='RankBadge';badge.BackgroundTransparency=1;badge.Size=UDim2.fromOffset(24,24);badge.LayoutOrder=1;badge.Parent=gui
 local spacer=badge:Clone();spacer.Name='RankSpacer';spacer.LayoutOrder=3;spacer.Parent=gui
 if d.Owned.title_monstermaster then -- every mastery done: gold ring around the rank icon
  local corner=Instance.new('UICorner');corner.CornerRadius=UDim.new(1,0);corner.Parent=badge
  local ring=Instance.new('UIStroke');ring.Color=Color3.fromRGB(255,214,110);ring.Thickness=2;ring.Parent=badge
 end
 if r.icon~=''then
  local img=Instance.new('ImageLabel');img.BackgroundTransparency=1;img.Size=UDim2.fromScale(1,1);img.Image=r.icon;img.Parent=badge
 else -- coloured gem until the rank icons are uploaded
  local gem=Instance.new('Frame');gem.AnchorPoint=Vector2.new(.5,.5);gem.Position=UDim2.fromScale(.5,.5);gem.Size=UDim2.fromOffset(14,14);gem.Rotation=45;gem.BackgroundColor3=r.color;gem.BorderSizePixel=0;gem.Parent=badge
  local corner=Instance.new('UICorner');corner.CornerRadius=UDim.new(0,3);corner.Parent=gem
  local stroke=Instance.new('UIStroke');stroke.Color=Color3.fromRGB(8,12,16);stroke.Thickness=2;stroke.Parent=gem
 end
end
local shownStage={} -- [player] = {[cosmeticId]=look} last rendered, for the staged-cosmetic notice (WorldB)
local function cosmetic(p)
 local d=data[p];local ch=p.Character;if not d or not ch then return end
 local head=ch:FindFirstChild('Head');local root=ch:FindFirstChild('HumanoidRootPart')
 local old=ch:FindFirstChild('ProgressCosmetics');if old then old:Destroy()end
 local folder=Instance.new('Folder');folder.Name='ProgressCosmetics';folder.Parent=ch
 local equipped=shownEquipped(p,d)
 local title=C.ById[equipped.Title]

 -- Aura looks (layered particles) live in CosmeticRig, shared with the lobby showcase statues.
 if root then require(RS.CosmeticRig).Aura(root,C.ById[equipped.Aura]and equipped.Aura or nil)end
 -- Wearables (one per slot) attach through the shared CosmeticRig so the menu preview matches.
 local stages=C.Stages and C.Stages(equipped,C.StageStats(d))or {}
 require(RS.CosmeticRig).Wear(ch,equipped,folder,stages)
 -- Staged cosmetics (WorldB): a look that moved up since the last render gets a notice, the Unlock cue and a grin.
 local seen=shownStage[p];shownStage[p]=stages
 if seen then for id,look in stages do
  local o=C.ById[id]
  if o and seen[id] and look>seen[id] then
   local lookName=o.stages.names and o.stages.names[look] or ('look '..look)
   notify(p,o.name..' changed: '..lookName..'!')
   local now=workspace:GetServerTimeNow();p:SetAttribute('FaceBeat','grin');p:SetAttribute('FaceBeatUntil',now+3);p:SetAttribute('ReactPop','NEW LOOK: '..lookName:upper()..'!');p:SetAttribute('ReactPopShake',0);p:SetAttribute('ReactPopAt',now)
   pcall(function()require(game.ServerScriptService.GameplayAudioServer).Play(o.stages.cue or 'Unlock',head or root)end)
  end
 end end
 -- One overhead owner and billboard, custom/title rows remain above Haunted Mastery.
 local Tags=require(RS:WaitForChild('CustomTags'));local tagInfo=Tags.Get(p.UserId)
 local haunted=d.Owned.Tag_Haunted==true and d.Settings and d.Settings.ShowHauntedTag~=false
 -- Lobby name tag: its own billboard just above the head (and any hat); the tag stack moves up one row to sit
 -- above it, so custom tags, titles and [Haunted] stay where they read best. Players see their own tag too.
 local lobbyName=head~=nil and p:GetAttribute('MissionActive')~=true
 local baseRise=2.4;local hatModel=folder:FindFirstChild('CosmeticHat')
 if head and hatModel and hatModel:IsA('Model') then local cf,size=hatModel:GetBoundingBox();baseRise=math.max(baseRise,(cf.Position.Y+size.Y/2)-head.Position.Y+.9)end
 -- In a mission the same name + rank tag is built hidden (VanOnly) above the tag stack; the van loop below shows it
 -- only while its player stands in the van (owner 2026-10-28).
 local stackCount=(tagInfo and 1 or 0)+(title and 1 or 0)+(haunted and 1 or 0)
 if head then
  local nameGui=Instance.new('BillboardGui');nameGui.Name='LobbyNameTag';nameGui.Adornee=head;nameGui.Size=UDim2.fromOffset(260,26)
  if not lobbyName then nameGui.Enabled=false;nameGui:SetAttribute('VanOnly',true)end
  nameGui.StudsOffsetWorldSpace=Vector3.new(0,lobbyName and baseRise-.35 or baseRise+stackCount*.62+(stackCount>0 and .1 or -.35),0);nameGui.MaxDistance=60;nameGui.AlwaysOnTop=false;nameGui.LightInfluence=0;nameGui.Parent=folder
  local nameLabel=Instance.new('TextLabel');nameLabel.Name='NameText';nameLabel.BackgroundTransparency=1;nameLabel.Size=UDim2.fromScale(0,1);nameLabel.AutomaticSize=Enum.AutomaticSize.X;nameLabel.LayoutOrder=2;nameLabel.Font=Enum.Font.FredokaOne;nameLabel.TextSize=17
  nameLabel.Text=p.DisplayName;nameLabel.TextColor3=Color3.fromRGB(244,236,210);nameLabel.TextStrokeTransparency=.2;nameLabel.TextStrokeColor3=Color3.fromRGB(8,12,16);nameLabel.Parent=nameGui
  rankBadge(nameGui,p)
 end
 if head and (tagInfo or title or haunted) then
  local rise=baseRise+(lobbyName and .45 or 0)
  local count=(tagInfo and 1 or 0)+(title and 1 or 0)+(haunted and 1 or 0)
  local gui=Instance.new('BillboardGui');gui.Name='ProgressTagStack';gui.Adornee=head;gui.Size=UDim2.fromOffset(320,count*30)
  gui.StudsOffsetWorldSpace=Vector3.new(0,rise+(count-1)*.3,0);gui.MaxDistance=60;gui.AlwaysOnTop=false;gui.LightInfluence=0;gui.Parent=folder
  local layout=Instance.new('UIListLayout');layout.SortOrder=Enum.SortOrder.LayoutOrder;layout.HorizontalAlignment=Enum.HorizontalAlignment.Center;layout.Parent=gui
  local function row(name,text,color,size,order,rich,iconId)
   local frame=Instance.new('Frame');frame.Name=name;frame.BackgroundTransparency=1;frame.Size=UDim2.new(1,0,0,30);frame.LayoutOrder=order;frame.Parent=gui
   local list=Instance.new('UIListLayout');list.FillDirection=Enum.FillDirection.Horizontal;list.HorizontalAlignment=Enum.HorizontalAlignment.Center;list.VerticalAlignment=Enum.VerticalAlignment.Center;list.Padding=UDim.new(0,4);list.SortOrder=Enum.SortOrder.LayoutOrder;list.Parent=frame
   local label=Instance.new('TextLabel');label.BackgroundTransparency=1;label.AutomaticSize=Enum.AutomaticSize.X;label.Size=UDim2.new(0,0,1,0);label.Font=Enum.Font.FredokaOne;label.TextSize=size;label.RichText=rich==true;label.Text=text;label.TextColor3=color;label.TextStrokeTransparency=.15;label.LayoutOrder=1;label.Parent=frame
   if iconId then local icon=Instance.new('ImageLabel');icon.BackgroundTransparency=1;icon.Size=UDim2.fromOffset(28,28);icon.Image=iconId;icon.LayoutOrder=2;icon.Parent=frame end
  end
  if tagInfo then row('CustomTag',Tags.RichText(tagInfo),Color3.new(1,1,1),20,1,true,tagInfo.icon)end
  if title then row('SurvivorTitle',title.text or title.name,Color3.fromRGB(unpack(title.color or {230,204,140})),14,2,false)end
  if haunted then row('HauntedMastery','[Haunted]',Color3.fromRGB(175,235,210),16,3,false)end
 end
end
-- Van rank tags (owner 2026-10-28 "make it so that the ranks are visible inside of the van"): the hidden mission name +
-- rank tag (VanOnly) shows while its player is inside the van; out in the map nobody's tag gives them away.
task.spawn(function()
 while true do
  task.wait(.5)
  local camp=workspace:FindFirstChild('RecoveryCamp');local van=camp and camp:FindFirstChild('AnomalyRecoveryVan')
  local ok,cf,size=false,nil,nil;if van then ok,cf,size=pcall(function()return van:GetBoundingBox()end)end
  for _,q in Players:GetPlayers()do
   local c=q.Character;local folder=c and c:FindFirstChild('ProgressCosmetics');local tag=folder and folder:FindFirstChild('LobbyNameTag')
   if tag and tag:GetAttribute('VanOnly')then
    local r=c:FindFirstChild('HumanoidRootPart');local inside=false
    if ok and r then local o=cf:PointToObjectSpace(r.Position);inside=math.abs(o.X)<=size.X/2 and math.abs(o.Z)<=size.Z/2 and math.abs(o.Y)<=size.Y/2+3 end
    if tag.Enabled~=inside then tag.Enabled=inside end
   end
  end
 end
end)
-- After a saved RR change: attributes, the client's 'rr' event, analytics, and a 'rankUp' for everyone on a new rank.
local function rrNotify(p,before,reason,bonuses,protected)
 local d=data[p];if not d or not p.Parent then return end
 local paidBefore=paidStep[p]or 1
 setRank(p)
 local r=Ranks.Get(d.RR);local _,hi=Ranks.Progress(d.RR)
 RankEvent:FireClient(p,'rr',{delta=d.RR-before,before=before,rr=d.RR,rank=r.name,tier=r.tier,nextAt=hi,nextRank=hi and Ranks.Get(hi).name or nil,reason=reason,bonuses=bonuses or {},protected=protected or nil})
 pcall(function()Analytics:LogCustomEvent(p,d.RR>=before and 'RRGain'or 'RRLoss',math.abs(d.RR-before))end)
 local old=Ranks.Get(before)
 if r.tier>old.tier or r.tier==old.tier and(r.division or 0)>(old.division or 0)then
  local reward=r.tier>old.tier and C.ById[Ranks.Tiers[r.tier].reward]or nil
  -- Everything this rank-up newly paid (ProgressCore rrGrant): tokens of each new step, cosmetics of each new tier.
  local gained={tokens=0,items={}}
  for s=paidBefore+1,(d.RRRewardStep or 1)do
   local sr=Ranks.StepReward(s);gained.tokens+=sr.tokens
   for _,id in sr.cosmetics do local c=C.ById[id];if c then table.insert(gained.items,{id=id,name=c.name,kind=c.kind})end end
  end
  RankEvent:FireAllClients('rankUp',{userId=p.UserId,name=p.DisplayName,rank=r.name,tier=r.tier,division=r.division,icon=r.icon,newTier=r.tier>old.tier,reward=reward and {id=reward.id,name=reward.name}or nil,gained=gained})
  pcall(function()Analytics:LogCustomEvent(p,'RankReached',r.tier)end)
  if r.tier>old.tier and p:GetAttribute('MissionActive')~=true then cosmetic(p)end -- new icon on the lobby name tag
 end
end
-- Native badge ownership is the achievement save; existing progress stats stay unchanged.
local BadgeService=game:GetService('BadgeService')
local BADGES={
 {key='first_shift',name='First Shift',description='Start your first mission.',stat='MissionStarted',goal=1},
 {key='made_it_out',name='Made It Out',description='Successfully extract from your first level.',stat='LevelsCleared',goal=1},
 {key='full_recovery',name='Full Recovery',description='Complete 5 successful extractions.',stat='RunsCompleted',goal=5},
 {key='seasoned_survivor',name='Seasoned Survivor',description='Successfully clear 10 levels.',stat='LevelsCleared',goal=10},
 {key='haul_of_a_lifetime',name='Haul of a Lifetime',description='Recover $10,000 total across successful extractions.',stat='TotalRetrieved',goal=10000},
 -- 2026-10-18: early hooks (level 3, a $500 level) and long goals (level 10, 25 runs, 50 levels). Read-only stats.
 {key='deeper_than_you_should',name='Deeper Than You Should',description='Reach level 3 in a single run.',stat='HighestLevel',goal=3},
 {key='jackpot',name='Big Haul',description='Recover $500 or more in a single level.',stat='BestHaul',goal=500},
 {key='point_of_no_return',name='Point of No Return',description='Reach level 10 in a single run.',stat='HighestLevel',goal=10},
 {key='house_regular',name='House Regular',description='Complete 25 successful extractions.',stat='RunsCompleted',goal=25},
 {key='legend_of_the_house',name='Legend of the House',description='Successfully clear 50 levels.',stat='LevelsCleared',goal=50},
}
local badgeOwned,badgePending,badgeSession={},{},{}
local badgeQueue={}
local nextBadgeRequest=0
local BADGE_RETRY_SECONDS={5,15,45}
local function badgeId(b)
 local id=script:GetAttribute('Badge_'..b.key)
 return type(id)=='number' and id>0 and id%1==0 and id or 0
end
local function badgeValue(p,b)
 local d=data[p]
 return b.stat=='MissionStarted' and (badgeSession[p] and 1 or d and d.LevelsCleared>0 and 1 or 0) or d and d[b.stat] or 0
end
local function badgeSnapshot(p)
 local out={}
 for _,b in BADGES do
  local value=math.min(b.goal,badgeValue(p,b))
  table.insert(out,{key=b.key,name=b.name,description=b.description,goal=b.goal,value=value,badgeId=badgeId(b),iconId=script:GetAttribute('BadgeIcon_'..b.key) or 0,
   earned=badgeOwned[p] and badgeOwned[p][b.key]==true or false,
   eligible=value>=b.goal,preview=studio})
 end
 return out
end
local function pushBadges(p)
 local event=RS:FindFirstChild('LobbyEvent')
 if event and p.Parent==Players then event:FireClient(p,'badgeState',badgeSnapshot(p))end
end
local function queueBadges(p)
 if p.Parent~=Players or not loaded[p] then return end
 badgeOwned[p]=badgeOwned[p] or {};badgePending[p]=badgePending[p] or {}
 for _,b in BADGES do
  if badgeValue(p,b)>=b.goal and not badgeOwned[p][b.key] and not badgePending[p][b.key] then
   if studio or badgeId(b)>0 then
    badgePending[p][b.key]=true
    table.insert(badgeQueue,{player=p,badge=b,attempt=0})
   end
  end
 end
end
local function badgeRequestSlot(p)
 while os.clock()<nextBadgeRequest and p.Parent==Players do task.wait(.1)end
 nextBadgeRequest=os.clock()+math.max(.5,60/(10+5*#Players:GetPlayers()))
 return p.Parent==Players
end
task.spawn(function()
 while true do
  local job=table.remove(badgeQueue,1)
  if not job then task.wait(.25);continue end
  local p,b=job.player,job.badge
  if p.Parent~=Players or not loaded[p] then continue end
  local pending=badgePending[p]
  if not pending then continue end
  local id=badgeId(b)
  local success,owned,newly=false,false,false
  if studio then
   success,owned,newly=true,true,true
  elseif id>0 then
   if badgeRequestSlot(p) then
    local ok,has=pcall(function()return BadgeService:UserHasBadgeAsync(p.UserId,id)end)
    if ok and has then success,owned=true,true
    elseif ok and p.Parent==Players and badgeRequestSlot(p) then
     local awardOk,result=pcall(function()return BadgeService:AwardBadgeAsync(p.UserId,id)end)
     success,owned,newly=awardOk and result==true,awardOk and result==true,awardOk and result==true
    end
   end
  end
  if p.Parent~=Players then continue end
  if success then
   badgeOwned[p][b.key]=owned;pending[b.key]=nil
   pushBadges(p)
   if newly then
    local event=RS:FindFirstChild('LobbyEvent')
    if event then event:FireClient(p,'badgeEarned',{key=b.key,name=b.name,description=b.description,badgeId=id,preview=studio})end
   end
  elseif job.attempt<#BADGE_RETRY_SECONDS and id>0 then
   job.attempt+=1
   task.delay(BADGE_RETRY_SECONDS[job.attempt],function()
    if p.Parent==Players and badgePending[p]==pending then table.insert(badgeQueue,job)end
   end)
  else
   pending[b.key]=nil
   p:SetAttribute('BadgeAwardStatus',id==0 and 'Badge configuration pending' or 'Will retry on next progress update')
  end
 end
end)
local function loadBadgeOwnership(p)
 if studio or p.Parent~=Players then return end
 local ids={}
 for _,b in BADGES do local id=badgeId(b);if id>0 then table.insert(ids,id)end end
 if #ids==0 then return end
 for attempt=1,3 do
  if not badgeRequestSlot(p) then return end
  local ok,owned=pcall(function()return BadgeService:CheckUserBadgesAsync(p.UserId,ids)end)
  if p.Parent~=Players then return end
  if ok then
   badgeOwned[p]=badgeOwned[p] or {}
   for _,b in BADGES do if table.find(owned,badgeId(b))then badgeOwned[p][b.key]=true end end
   pushBadges(p);queueBadges(p);return
  end
  task.wait(attempt*3)
 end
end

-- IDs are configuration, so connecting newly-created badges never rewrites player data.
for _,b in BADGES do
 script:GetAttributeChangedSignal('Badge_'..b.key):Connect(function()
  for _,p in Players:GetPlayers()do queueBadges(p);pushBadges(p)end
 end)
end

local function publish(p)
 local d=data[p];if not d or not p.Parent then return end
 -- base + tier bonus (upgrades add), then the 2x Speed pass doubles the result with no cap (owner 2026-10-26)
 local bonus=C.UpgradeStats.Speed[d.Upgrades.Speed+1]
 local multiplier=p:GetAttribute('Pass_double_speed')and 2 or 1
 p:SetAttribute('UpgradeWalkSpeed',(C.BaseSpeed.Walk+bonus[1])*multiplier);p:SetAttribute('UpgradeSprintSpeed',(C.BaseSpeed.Sprint+bonus[2])*multiplier)
 p:SetAttribute('MaxStamina',C.UpgradeStats.Stamina[d.Upgrades.Stamina+1])
 for _,stat in {'Speed','Stamina','Flashlight'}do p:SetAttribute('UpgradeTier_'..stat,d.Upgrades[stat])end -- TokenGoalHint names the next tier
 p:SetAttribute('FlashlightStrength',C.UpgradeStats.Flashlight[d.Upgrades.Flashlight+1]);p:SetAttribute('FlashlightRange',52+d.Upgrades.Flashlight*2)
 p:SetAttribute('ReviveTokens',UNLIMITED_REVIVES[p.UserId]and 999 or d.ReviveTokens)
 p:SetAttribute('JumpscareCharges',d.JumpscareCharges)
 p:SetAttribute('InstantWinCharges',d.InstantWinCharges)
 p:SetAttribute('FlashlightColor',type(d.FlashlightColor)=='table'and Color3.fromRGB(d.FlashlightColor.r,d.FlashlightColor.g,d.FlashlightColor.b)or nil)
  -- Veterans who cleared a level before the tutorial existed skip it.
  p:SetAttribute('TutorialDone',d.TutorialDone or d.LevelsCleared>0)
 -- Monster intro cutscene: only saves that never played a level see it (MonsterIntroClient).
 p:SetAttribute('IntroSeen',d.IntroSeen or d.TutorialDone or d.LevelsCleared>0)
 p:SetAttribute('ShopTutorialStep',d.ShopTutorialStep>0 and d.ShopTutorialStep or nil)
 p:SetAttribute('Tokens',d.Tokens);p:SetAttribute('HighestLevel',d.HighestLevel);p:SetAttribute('ProgressSaveStatus',mode[p]=='memory'and 'Studio session only'or 'Saved')
 local equipped=shownEquipped(p,d)
 p:SetAttribute('EquippedTitle',equipped.Title);p:SetAttribute('EquippedAura',equipped.Aura)
 for _,slot in C.CosmeticSlots do p:SetAttribute('Equipped'..slot,equipped[slot])end
 p:SetAttribute('ShowHauntedTag',d.Owned.Tag_Haunted==true and d.Settings.ShowHauntedTag~=false)
 queueBadges(p)
 local e=RS:FindFirstChild('LobbyEvent');if e then e:FireClient(p,'progress',M.Snapshot(p))end
 cosmetic(p)
end
local function collectionPercent(d)
 local owned,total=0,0
 for id,item in C.ById do
  if table.find({'Hat','Ring','Shirt','Shoes','Title','Aura','Eyes','Back','Trail','Torch','Tag','Pet'},item.kind) and item.releaseStage~='event' then
   total+=1;if d and d.Owned and d.Owned[id]==true then owned+=1 end
  end
 end
 return total>0 and math.floor(owned*100/total) or 0
end
local function rankValue(d,id)return id=='CollectionPercent' and collectionPercent(d) or d and d[id] or 0 end
local function index(p,d)
 if not eligibility.CanRank(p.UserId)then excludedIndexes+=1;return end
 if mode[p]=='memory'then return end
 task.spawn(function()
  for _,cat in C.Categories do
   local value=rankValue(d,cat.id)
   if value>0 or cat.id=='CollectionPercent' then
    for attempt=1,3 do
     if not eligibility.CanRank(p.UserId)then return end
     orderedAttempts+=1;orderedAttemptsByUser[p.UserId]=(orderedAttemptsByUser[p.UserId]or 0)+1
     local ok=pcall(function()ordered[cat.id]:UpdateAsync('player_'..p.UserId,function(old)
      if not eligibility.CanRank(p.UserId)then return nil end
      if type(old)~='number' or cat.id=='CollectionPercent'then return value end
      return cat.ascending and math.min(old,value)or math.max(old,value)
     end)end)
     if ok then break end;task.wait(attempt)
    end
   end
  end
 end)
end
function M.Load(p)
 if loaded[p]then return true end
 -- A player who already left can never be loaded (see below); never spend a DataStore read on them.
 if p.Parent~=Players then return false end
 if loading[p]then local untilAt=os.clock()+15;repeat task.wait(.05)until not loading[p]or os.clock()>untilAt;return loaded[p]==true end
 loading[p]=true
 local ok,old
 if STUDIO_MEMORY or studio and p.UserId<=0 then ok=false;old=nil
 else for attempt=1,3 do ok,old=pcall(function()assert(store,'Persistence store is not available');return store:GetAsync('player_'..p.UserId)end);if ok then break end;if studio then break end;task.wait(attempt)end end
 if not ok and not studio then loading[p]=nil;p:SetAttribute('ProgressSaveStatus','Unavailable');return false end
 local d,err=Core.Reconcile(ok and old or nil)
 if not d then loading[p]=nil;p:SetAttribute('ProgressSaveStatus','Unsupported save');return false end
 if not p.Parent then loading[p]=nil;return false end
 mode[p]=ok and 'persistent'or 'memory';data[p]=d;loaded[p]=true;loading[p]=nil;task.spawn(loadBadgeOwnership,p);task.spawn(function()if M.RRSeasonCheck then M.RRSeasonCheck(p)end end);publish(p);index(p,d);return true
end
function M.Snapshot(p)
 local d=data[p];if not d then return {ready=false,tokens=0,status=p:GetAttribute('ProgressSaveStatus')or 'Loading'}end
 return {ready=true,tokens=d.Tokens,upgrades=table.clone(d.Upgrades),reviveTokens=UNLIMITED_REVIVES[p.UserId]and 999 or d.ReviveTokens,jumpscareCharges=d.JumpscareCharges,flashlightColor=type(d.FlashlightColor)=='table'and table.clone(d.FlashlightColor)or false,passes=table.clone(entitlements[p]or {}),owned=shownOwned(p,d),equipped=table.clone(shownEquipped(p,d)),badges=badgeSnapshot(p),museum=table.clone(d.Museum or {}),storyNotes=table.clone(d.StoryNotes or {}),stats={HighestLevel=d.HighestLevel,FastestClearMs=d.FastestClearMs,TotalRetrieved=d.TotalRetrieved,BestHaul=d.BestHaul,LevelsCleared=d.LevelsCleared,RunsCompleted=d.RunsCompleted},stages=C.Stages and C.Stages(shownEquipped(p,d),C.StageStats(d)),stageStats=C.StageStats and C.StageStats(d),status=mode[p]=='memory'and 'Studio session only'or 'Saved'}
end
local function studioTrace(line) -- Studio only: the last analytics calls, for playtest checks (live servers send them instead)
 local ss=game:GetService('ServerStorage');ss:SetAttribute('AnalyticsTrace',string.sub((ss:GetAttribute('AnalyticsTrace')or'')..line..';',-800))
end
-- Economy analytics (Creator Dashboard > Analytics > Economy). Admin grants and test (memory) profiles are left out.
local ECONOMY_SKIP={adminPass=true,ownerAward=true,questAdminRewards=true,ownerRankCosmetics=true}
local TT=Enum.AnalyticsEconomyTransactionType
local ECONOMY_TYPE={clear=TT.Gameplay,purchase=TT.Shop,receipt=TT.IAP,tutorial=TT.Onboarding,vanDaily=TT.TimedReward,vanTimed=TT.TimedReward,vanSessionCheckpoint=TT.TimedReward,vanSessionOpen=TT.TimedReward}
local function logEconomy(p,op,before,after)
 if ECONOMY_SKIP[op.kind]then return end
 if not studio and mode[p]~='persistent'then return end
 local kind=(ECONOMY_TYPE[op.kind]or TT.Gameplay).Name
 local sku=tostring(op.offer or op.kind or 'unknown')
 for _,currency in {{'Tokens','Tokens'},{'ReviveTokens','Revives'}}do
  local was,now=tonumber(before[currency[1]])or 0,tonumber(after[currency[1]])or 0
  if now~=was then
   local flow=now>was and Enum.AnalyticsEconomyFlowType.Source or Enum.AnalyticsEconomyFlowType.Sink
   if studio then studioTrace('econ:'..flow.Name..':'..currency[2]..':'..math.abs(now-was)..':'..now..':'..kind..':'..sku)
   else pcall(function()game:GetService('AnalyticsService'):LogEconomyEvent(p,flow,currency[2],math.abs(now-was),now,kind,sku)end)end
  end
 end
end
local function transaction(p,op)
 if not M.Load(p)then return false,'Your save is unavailable. Please try again.'end
 local deadline=os.clock()+20;while busy[p]and os.clock()<deadline do task.wait(.05)end
 if busy[p]then return false,'Save is busy. Please try again.'end
 -- The player can leave during the wait above (PlayerRemoving clears data[p]): live error 'index nil with Tokens'.
 if not data[p]or p.Parent==nil then return false,'Your save is unavailable. Please try again.'end
 busy[p]=true
 -- Queued clears and ambiguous requests retain identities/events, but execute at current server time.
 if op.quest then op.quest.now=Q.Now(p)end
 if op.questClear then op.questClear.now=Q.Now(p)end
 local previousCollection=collectionPercent(data[p])
 local before={Tokens=data[p].Tokens,ReviveTokens=data[p].ReviveTokens}
 local result,message,err
 if mode[p]=='memory'then result,message=Core.Apply(data[p],op)
 else
  for attempt=1,3 do
   local ok,value=pcall(function()assert(store,'Persistence store is not available');return store:UpdateAsync('player_'..p.UserId,function(old)
    local next,msg=Core.Apply(old,op);message=msg;return next
   end,{p.UserId})end)
   if ok then result=value;err=nil;break end;err=value;task.wait(attempt)
  end
 end
 busy[p]=nil
 if result then logEconomy(p,op,before,result);data[p]=result;boardCache={};publish(p);if Q.ProfileChanged then Q.ProfileChanged(p)end;if op.kind=='clear' or collectionPercent(result)~=previousCollection then index(p,result)end;return true,message,result end
 if err then p:SetAttribute('ProgressSaveStatus','Retrying');return false,'Save service is unavailable. Please try again.'end
 return false,message or 'Could not update your save.'
end
function M.SetShowHauntedTag(p,show)
 if type(show)~='boolean' then return false,'Invalid tag setting.'end
 return transaction(p,{kind='showHauntedTag',show=show})
end
function M.CanUseVanShop(p)
 if not p or not p.Parent or not p:GetAttribute('MissionActive')then return false end
 local api=game.ServerStorage:FindFirstChild('RecoveryApi')
 if not api then return false end
 local ok,allowed=pcall(function()return api:Invoke('shopAllowed',p)end)
 return ok and allowed==true
end
function M.VanShopInfo(p)
 -- In a mission only inside the van; in the 3D lobby (Menu mode) the same shop opens from the menu and kiosks.
 local lobbyState=game:GetService('ReplicatedStorage'):FindFirstChild('LobbyState')
 local inLobby=not p:GetAttribute('MissionActive')and(lobbyState and lobbyState:GetAttribute('Mode')=='Menu'or p:GetAttribute('ReturnedToLobby')==true)
 if not inLobby and not M.CanUseVanShop(p)then return false,'Use the supply shop inside the van.'end
 if not M.Load(p)then return false,'Your saved data is unavailable.'end
 return true,{progress=M.Snapshot(p)}
end
function M.RobuxShopInfo(p)
 if not p or p.Parent~=Players or p:GetAttribute('MissionActive')~=true then return false,'Open the Robux shop during a mission.'end
 if not M.Load(p)then return false,'Your saved data is unavailable.'end
 return true,{progress=M.Snapshot(p)}
end
function M.Purchase(p,id)
 if type(id)~='string'or #id>60 or not C.Purchasable[id]then return false,'Invalid offer.'end
 if p:GetAttribute('MissionActive')and not M.CanUseVanShop(p)then return false,'Use the supply shop inside the van.'end
 local ok,msg=transaction(p,{kind='purchase',offer=id});return ok,ok and {progress=M.Snapshot(p),message=msg}or msg
end
function M.Equip(p,id,slot)
 if type(id)~='string'or #id>60 then return false,'Invalid cosmetic.'end
 if p:GetAttribute('MissionActive')and not M.CanUseVanShop(p)then return false,'Equip cosmetics inside the van.'end
 local ok,msg=transaction(p,{kind='equip',offer=id,slot=slot});return ok,ok and {progress=M.Snapshot(p),message=msg}or msg
end
-- Referral pair reward (LobbyServer decides when two players played together). Invitee first: an already
-- rewarded invitee never pays the inviter again.
function M.ReferralReward(invitee,inviter)
 local ok=transaction(invitee,{kind='referral',role='invitee'})
 if not ok then return false end
 transaction(inviter,{kind='referral',role='inviter',friend=invitee.UserId})
 return true
end
function M.MarkIntroSeen(p)
 if not data[p]or data[p].IntroSeen then return true,{}end
 local ok,msg=transaction(p,{kind='introSeen'});return ok,ok and {}or msg
end
function M.CompleteTutorial(p)
 if data[p]and data[p].TutorialDone then
  -- The owner's every-run tutorial replay also replays the team boost part of the shop chapter (not the token part).
  local round=RS:FindFirstChild('RecoveryRound')
  if p:GetAttribute('AdminOwner')==true and data[p].ShopTutorialStep==3 and round and(round:GetAttribute('Phase')=='Won'or(round:GetAttribute('Round')or 1)>=2)then
   p:SetAttribute('ShopTutorialReplay',true);transaction(p,{kind='shopTutorialReplay'})
  end
  return true,{}
 end
 -- Only a won first level counts as finishing (skips send the same action): that pays the tutorial tokens.
 local round=RS:FindFirstChild('RecoveryRound')
 local completed=p:GetAttribute('MissionActive')==true and round~=nil and(round:GetAttribute('Phase')=='Won'or(round:GetAttribute('Round')or 1)>=2)
 local ok,msg=transaction(p,{kind='tutorial',completed=completed});return ok,ok and {}or msg
end
-- Shop chapter steps (GearShopServer moves 1 -> 2 on the first team boost; the client's SKIP asks for 3).
function M.ShopTutorialAdvance(p,step)
 if not data[p]then return false end
 local ok,msg=transaction(p,{kind='shopTutorial',step=step});return ok,ok and {}or msg
end
-- Clear rewards keep retrying after the player leaves (saves are keyed by UserId and clear ids are idempotent) and
-- are never dropped; the gap backs off while the save service is down. The worker releases the queue and the
-- departed player's cached data once everything has saved.
local CLEAR_RETRY_SECONDS,CLEAR_RETRY_MAX_SECONDS=5,30
local function releaseDeparted(p)
 if p.Parent~=Players and not queue[p] and not busy[p] and not Q.HasPending(p) then data[p]=nil;loaded[p]=nil;mode[p]=nil end
end
-- A failed run (wipe nobody revived, or time ran out) costs RR; failId is unique per failure.
function M.RecordFailure(players,failId,level)
 for _,p in players do
  RankRating.Take(p)
  local d=data[p]
  if d and p:GetAttribute('MissionActive')==true and p:GetAttribute('RewardTestMode')~=true and p:GetAttribute('AdminSimulateNoPasses')~=true and p:GetAttribute('QuestTestMode')~=true then
   local before=d.RR or 0
   if before<RankRating.PROTECT_BELOW then task.spawn(rrNotify,p,before,'fail',{},true) -- Newcomer tier: nothing lost
   else
    local op={kind='rrLoss',id=failId..':'..p.UserId,rr=RankRating.Loss({rr=before,level=level}),season=RankRating.Season()}
    task.spawn(function()local ok,msg=transaction(p,op);if ok and p.Parent then notify(p,msg);if msg~='Already credited.'then rrNotify(p,before,'fail',{},msg=='Rank protected.')end end end)
   end
  end
 end
end
-- Team wipe still revivable: show what the loss WOULD be (pending=true), nothing saved. RecordFailure follows if nobody revives.
function M.PreviewFailure(players,level)
 for _,p in players do
  local d=data[p]
  if d and p.Parent and p:GetAttribute('MissionActive')==true and p:GetAttribute('RewardTestMode')~=true and p:GetAttribute('AdminSimulateNoPasses')~=true and p:GetAttribute('QuestTestMode')~=true then
   local before=d.RR or 0;local protected=before<RankRating.PROTECT_BELOW
   local after=before-(protected and 0 or RankRating.Loss({rr=before,level=level}))
   local r=Ranks.Get(after);local _,hi=Ranks.Progress(after)
   RankEvent:FireClient(p,'rr',{delta=after-before,before=before,rr=after,rank=r.name,tier=r.tier,nextAt=hi,nextRank=hi and Ranks.Get(hi).name or nil,reason='fail',bonuses={},protected=protected or nil,pending=true})
  end
 end
end
-- New monthly season (and rewards for tiers reached before rewards existed): one save op on join when needed.
function M.RRSeasonCheck(p)
 local d=data[p];if not d then return end
 local season=RankRating.Season()
 -- Rank rewards added after a player reached their rank (new auras, trails, tokens) are granted here on join.
 local missing=d.RRBestTier<Ranks.Get(d.RR).tier or(d.RRRewardStep or 1)<Ranks.Step(d.RR)
 for i=1,math.max(d.RRBestTier,Ranks.Get(d.RR).tier)do local t=Ranks.Tiers[i]
  for _,id in {t.reward,t.reward2,t.reward3}do if C.ById[id]and not(d.Owned and d.Owned[id])then missing=true end end
 end
 if d.RRSeason~=season or missing then
  local ownedBefore=table.clone(d.Owned or {});local tokensBefore=d.Tokens
  local ok,_,after=transaction(p,{kind='rrSeason',season=season})
  if ok and after and missing then
   local names={}
   for i=1,after.RRBestTier do local t=Ranks.Tiers[i]
    for _,id in {t.reward,t.reward2,t.reward3}do local c=C.ById[id];if c and after.Owned[id]and not ownedBefore[id]then table.insert(names,c.name)end end
   end
   local tokens=after.Tokens-tokensBefore
   if #names>0 or tokens>0 then
    local ev=RS:FindFirstChild('LobbyEvent')
    if ev and p.Parent then ev:FireClient(p,'notice','Rank rewards unlocked: '..(tokens>0 and('+'..tokens..' tokens'..(#names>0 and', 'or''))or'')..table.concat(names,', ')..'. Equip them in Character.')end
   end
  end
 end
 setRank(p)
end
-- RR party bonuses: a friend in the clear, or someone two or more tiers lower (carrying a newer player).
local friendCache={}
Players.PlayerRemoving:Connect(function(p)friendCache[p]=nil;paidStep[p]=nil;shownStage[p]=nil end)
local function rrParty(p,players)
 local friends,carry=false,false
 local mine=Ranks.Get(data[p] and data[p].RR or 0).tier
 local cache=friendCache[p] or {};friendCache[p]=cache
 for _,o in players do if o~=p and o.Parent==Players then
  if Ranks.Get(data[o] and data[o].RR or 0).tier<=mine-2 then carry=true end
  local known=cache[o.UserId]
  if known==nil then local ok,f=pcall(function()return p:IsFriendsWith(o.UserId)end);known=ok and f==true;cache[o.UserId]=known end
  friends=friends or known
 end end
 return friends,carry
end
-- Curio Cabinet (2026-10-29): each van sale notes its item types for every player still in the run (dead or alive),
-- assisted rounds included; the caller leaves out admin-spawned items and lobby toys. No write when nothing is new.
function M.NoteMuseum(players,ids)
 for _,p in players do task.spawn(function()
  if p:GetAttribute('RewardTestMode')==true or not M.Load(p) or not data[p] then return end
  local museum=data[p].Museum or {};local fresh={}
  for _,id in ids do if type(id)=='string' and museum[id]==nil and not table.find(fresh,id)then table.insert(fresh,id)end end
  if #fresh>0 then transaction(p,{kind='museum',ids=fresh,at=os.time()})end
 end)end
end
-- Story (2026-10-29): a note read in a level (WorldHappenings) is kept for the lobby Case Board. No write when known.
function M.NoteStory(p,id)
 task.spawn(function()
  if type(id)~='string'or not M.Load(p)or not data[p]then return end
  if type(data[p].StoryNotes)=='table'and data[p].StoryNotes[id]~=nil then return end
  transaction(p,{kind='storyNote',id=id,at=os.time()})
 end)
end
function M.RecordClear(players,runId,level,money,ms,context)
 for _,p in players do
  local op={kind='clear',id=runId..':'..level..':'..p.UserId,level=level,money=money,ms=ms,completed=level%C.RunLevels==0,doubleTokens=p:GetAttribute('Pass_double_tokens')==true,omenDouble=RS:FindFirstChild('RecoveryRound')~=nil and RS.RecoveryRound:GetAttribute('Omen')=='DoubleTokens',plusBonus=p.MembershipType==Enum.MembershipType.Premium,favoriteBonus=false}
  local ctx=context or {}
  local rrLevel=RankRating.Take(p)
  if not ctx.assisted and not ctx.admin and p:GetAttribute('AdminSimulateNoPasses')~=true and p:GetAttribute('RewardTestMode')~=true and p:GetAttribute('QuestTestMode')~=true and p:GetAttribute('MissionActive')==true and not Q.IsAssisted(runId,ctx.round)then
   local deaths=ctx.deathsByUser;local count=deaths and (deaths[p.UserId] or deaths[tostring(p.UserId)]) or nil
   local eventCtx={runId=runId,round=ctx.round or level,generation=ctx.generation or 0,mapKind=ctx.mapKind or '',partySize=ctx.teamSize or #players,level=level,noDeath=type(deaths)=='table' and count~=true and (tonumber(count)or 0)==0,noPartyDeath=ctx.noPartyDeath==true,timeLeft=math.max(0,math.floor(ctx.timeLeft or 0))}
   op.questClear=Q.ClearContext(p,{{hook='LevelCleared',eventId=op.id..':quest',at=Q.Now(p),amount=1,ctx=eventCtx}})
   local friends,carry=rrParty(p,players)
   op.rr=RankRating.Gain({rr=data[p] and data[p].RR or 0,level=level,seconds=ms/1000,money=money,died=count==true or (tonumber(count)or 0)>0,grabs=rrLevel.grabs,sold=rrLevel.sold,friends=friends,carry=carry})
   op.rrBonuses={};if friends then table.insert(op.rrBonuses,'friends')end;if carry then table.insert(op.rrBonuses,'carry')end
   op.day=RankRating.Day();op.season=RankRating.Season()
   op.crew={};for _,o in players do if o~=p and o.Parent==Players and o:GetAttribute('MissionActive')==true and #op.crew<3 then table.insert(op.crew,o.UserId)end end
  end
  local jobs=queue[p]or {};queue[p]=jobs;table.insert(jobs,op)
  if #jobs==1 then task.spawn(function()
   local failures=0
   while #jobs>0 do
    local job=jobs[1]
     M.Load(p);local rrBefore,dayBefore=data[p]and data[p].RR,data[p]and data[p].RRDay
     local ok,msg=transaction(p,job)
     if ok and type(job.rr)=='number'and rrBefore and msg~='Already credited.'then
      local d=data[p];local bonuses=table.clone(job.rrBonuses or {})
      if d and d.RRDay~=dayBefore then table.insert(bonuses,'daily');if d.RRStreak>=RankRating.STREAK_DAYS then table.insert(bonuses,'streak')end end
      task.spawn(rrNotify,p,rrBefore,'clear',bonuses)
     end
    if ok then table.remove(jobs,1);failures=0;if p.Parent then notify(p,msg);setRank(p)
      -- Recap confirmation: only after the save committed. A repeat id earns nothing new.
      local recap=RS:FindFirstChild('RoundRecap')
      if recap then
       local duplicate=msg=='Already credited.'
       local earned=(not duplicate and job.completed) and Core.RunTokens(job) or 0
       recap:FireClient(p,'tokens',{recapId=job.id:gsub(':%d+$','')..':Won',earned=earned,balance=data[p] and data[p].Tokens or 0,duplicate=duplicate})
      end
     end
    else
     failures+=1
     task.wait(p.Parent and CLEAR_RETRY_SECONDS or math.min(CLEAR_RETRY_MAX_SECONDS,CLEAR_RETRY_SECONDS*2^(failures-1)))
    end
   end
   queue[p]=nil
   releaseDeparted(p)
  end)end
 end
end
local function playerName(id)
 if nameCache[id]then return nameCache[id]end
 local live=Players:GetPlayerByUserId(id);if live then nameCache[id]=live.DisplayName;return live.DisplayName end
 local ok,name=pcall(function()return Players:GetNameFromUserIdAsync(id)end);nameCache[id]=ok and name or ('Player '..id);return nameCache[id]
end
local liveStores={}
local function liveOrdered(id)
 if STUDIO_MEMORY then return nil end
 liveStores[id]=liveStores[id]or DSS:GetOrderedDataStore('DDH_'..id..'_v1')
 return liveStores[id]
end
function M.Board(id)
 local cat;for _,v in C.Categories do if v.id==id then cat=v end end
 if not cat then return false,'Unknown leaderboard.'end
 if not eligibility.CreatorReady()then return false,'Leaderboard owner lookup is temporarily unavailable.'end
 local cached=boardCache[id];if cached and os.clock()-cached.time<60 then return true,cached.value end
 local rows={};local persistence=true
 -- Studio reads the LIVE board (read-only; Studio writes still go to the _Studio stores) so the lobby board shows real players.
 local source=not STUDIO_MEMORY and(studio and liveOrdered(id)or ordered[id])or nil
 local seen={}
 local ok,pages=false,nil
 if source then ok,pages=pcall(function()return source:GetSortedAsync(cat.ascending,eligibility.PageSize(),1)end)end
 if ok then
  while true do
   for _,item in pages:GetCurrentPage()do
    local uid=tonumber(item.key:match('^player_(%d+)$'))
    if uid and not seen[uid]and eligibility.CanRank(uid)then seen[uid]=true;table.insert(rows,{rank=#rows+1,id=uid,name=playerName(uid),value=item.value})end
    if #rows>=10 then break end
   end
   if #rows>=10 or pages.IsFinished then break end
   local advanced=pcall(function()pages:AdvanceToNextPageAsync()end)
   if not advanced then return false,'Leaderboard service is temporarily unavailable.'end
  end
 elseif studio then
  persistence=false
  for p,d in data do
   if eligibility.CanRank(p.UserId)and rankValue(d,id)>0 then table.insert(rows,{id=p.UserId,name=p.DisplayName,value=rankValue(d,id)})end
  end
  table.sort(rows,function(a,b)return cat.ascending and a.value<b.value or not cat.ascending and a.value>b.value end)
  while #rows>10 do table.remove(rows)end
  for rank,row in rows do row.rank=rank end
 else return false,'Leaderboard service is temporarily unavailable.'end
 local value={category=id,rows=rows,persistent=persistence};boardCache[id]={time=os.clock(),value=value};return true,value
end

-- Board plus the asking player's own value and rank (rank only when they are in the top 10).
function M.BoardFor(p,id)
 local ok,value=M.Board(id)
 if not ok then return ok,value end
 local mine=rankValue(data[p],id)
 if studio and not STUDIO_MEMORY then -- Published Studio only; local review boards are session-only
  local got,live=pcall(function()local source=liveOrdered(id);assert(source,'Persistence store is not available');return source:GetAsync('player_'..p.UserId)end)
  if got and type(live)=='number'then mine=live end
 end
 local rank;for _,row in value.rows do if row.id==p.UserId then rank=row.rank;mine=row.value end end
 return true,{category=value.category,rows=value.rows,persistent=value.persistent,me={value=mine,rank=rank}}
end
-- Crew Trophy (2026-10-26): what the lobby trophy engraves for this viewer. Party: the best level any two members present
-- here cleared together (each pair is saved on both saves; the higher of the two wins). Solo: their 3 best crews.
-- Read-only; names come from playerName (display name for players in the server, cached lookup otherwise).
function M.CrewRecord(p)
 local d=data[p];if not d then return false,'Your save is still loading.'end
 local today=RankRating.Day()
 local partyId=p:GetAttribute('LobbyPartyId')
 local members={p}
 if partyId then for _,o in Players:GetPlayers()do if o~=p and o:GetAttribute('LobbyPartyId')==partyId and data[o]then table.insert(members,o)end end end
 if #members>=2 then
  local best
  for i=1,#members do for j=i+1,#members do
   local a,b=members[i],members[j]
   for _,pair in {{a,b},{b,a}}do
    local recs=data[pair[1]].CrewRecords;local r=recs and recs[tostring(pair[2].UserId)]
    if r and(not best or r.l>best.l or r.l==best.l and r.t>best.t)then best={l=r.l,t=r.t,a=a,b=b}end
   end
  end end
  if not best then return true,{mode='party',level=0,size=#members}end
  return true,{mode='party',level=best.l,today=best.t==today,names={best.a.DisplayName,best.b.DisplayName},size=#members}
 end
 local rows={}
 for key,r in d.CrewRecords or {}do table.insert(rows,{id=tonumber(key),l=r.l,t=r.t})end
 table.sort(rows,function(x,y)if x.l~=y.l then return x.l>y.l end;return x.t>y.t end)
 local out={}
 for i=1,math.min(3,#rows)do local r=rows[i];if r.id then table.insert(out,{name=playerName(r.id),level=r.l,today=r.t==today})end end
 return true,{mode=#out>0 and 'solo' or 'none',rows=out}
end
function M.RefreshPasses(p)
 if not M.Load(p)then return end
 local owned=entitlements[p]or {};entitlements[p]=owned
 for _,offer in C.RobuxOffers do if offer.kind=='Pass'then
  local validId=type(offer.assetId)=='number'and offer.assetId>0 and offer.assetId%1==0
  local ok,value=true,false;if validId then ok,value=pcall(function()return Marketplace:UserOwnsGamePassAsync(p.UserId,offer.assetId)end)end
  if not p.Parent then return end
  local granted=data[p]and data[p].AdminPasses[offer.id]==true
  if simulateNoPasses(p) then ok,value,granted=true,false,false end
  if ok or granted then owned[offer.id]=value==true or granted;p:SetAttribute('Pass_'..offer.id,owned[offer.id])end
 end end
 if simulateNoPasses(p) then publish(p);return end -- test mode: no pass grants are written
 if owned.vip and M.Load(p)then transaction(p,{kind='vip'})end
 local grants={}
 for _,offer in C.RobuxOffers do if offer.grants and owned[offer.id]and data[p]and not data[p].Owned[offer.grants]then table.insert(grants,offer.grants)end end
 if #grants>0 and M.Load(p)then local ok,msg=transaction(p,{kind='grant',ids=grants});if ok then notify(p,msg)end end
 publish(p)
end
local giftTargets={}
function M.SetGiftReviveTarget(p,userId,identity)
 if typeof(p)~='Instance'or not p:IsA('Player')or p.Parent~=Players then return false,'Player is unavailable.'end
 giftTargets[p]=nil -- Invalid new choices must never leave an older valid recipient armed.
 if userId==nil then return true end
 if type(userId)~='number'or userId~=userId or userId<=0 or userId%1~=0 or math.abs(userId)>9007199254740991 or userId==p.UserId then return false,'Invalid teammate.'end
 if type(identity)~='table'or identity.targetUserId~=userId then return false,'Revive identity is unavailable.'end
 local target=Players:GetPlayerByUserId(userId)
 if not target or target:GetAttribute('MissionActive')~=true or target:GetAttribute('RoundDead')~=true or p:GetAttribute('MissionActive')~=true then return false,'Choose a dead mission teammate.'end
 giftTargets[p]={userId=userId,identity=table.clone(identity),expires=os.clock()+60}
 return true
end
function M.ConsumeJumpscare(p,id)return transaction(p,{kind='consumeJumpscare',id=id})end
function M.RefundJumpscare(p,id)return transaction(p,{kind='refundJumpscare',id=id})end
function M.ConsumeInstantWin(p,id)return transaction(p,{kind='consumeInstantWin',id=id})end
function M.RefundInstantWin(p,id)return transaction(p,{kind='refundInstantWin',id=id})end
function M.SetFlashlightColor(p,color)
 if typeof(color)~='Color3'or not p or not p.Parent or p:GetAttribute('Pass_flashlight_colors')~=true then return false,'Flashlight Colors pass required.'end
 local values={r=color.R,g=color.G,b=color.B};local bytes={}
 for key,v in values do if v~=v or math.abs(v)==math.huge then return false,'Invalid flashlight color.'end;bytes[key]=math.clamp(math.floor(v*255+.5),0,255)end
 return transaction(p,{kind='flashlightColor',color=bytes})
end
-- Purchase feedback (2026-10-22): a bought product always tells the buyer what happened, instead of granting silently
-- or, while the save is not ready, doing nothing visible (Roblox retries the receipt; the purchase is never lost).
local pendingNotified={}
local function purchaseNotice(p,text)
 local ev=RS:FindFirstChild('LobbyEvent');if ev and p.Parent then ev:FireClient(p,'notice',text)end
end
function M.Receipt(receipt)
 if type(receipt)~='table'or type(receipt.PlayerId)~='number'or type(receipt.ProductId)~='number'then return Enum.ProductPurchaseDecision.NotProcessedYet end
 local p=Players:GetPlayerByUserId(receipt.PlayerId)
 local purchaseId=receipt.PurchaseId;local offer=C.Products[receipt.ProductId]
 if not p or not offer or type(purchaseId)~='string'or #purchaseId==0 or #purchaseId>160 then return Enum.ProductPurchaseDecision.NotProcessedYet end
 -- Studio saves are session only ('memory'): test purchases are granted into that session so they can be tested.
 local usable=M.Load(p)and(mode[p]=='persistent'or studio and mode[p]=='memory')
 if not usable then
  if not pendingNotified[purchaseId]then pendingNotified[purchaseId]=true;purchaseNotice(p,'Thanks! Your '..offer.name..' purchase is safe: it will be added as soon as your save finishes loading.')end
  return Enum.ProductPurchaseDecision.NotProcessedYet
 end
 local ok,message,committed=transaction(p,{kind='receipt',id=purchaseId,productId=receipt.ProductId})
 if not ok or not committed or committed.PurchaseReceipts[purchaseId]~=true then
  if not pendingNotified[purchaseId]then pendingNotified[purchaseId]=true;purchaseNotice(p,'Thanks! Your '..offer.name..' purchase is safe: it will be added in a moment.')end
  return Enum.ProductPurchaseDecision.NotProcessedYet
 end
 pendingNotified[purchaseId]=nil
 if message~='Already granted.'then
  local extra=((tonumber(offer.grantRevives)or 0)>0 or offer.id=='revive_token')and(' You have '..committed.ReviveTokens..' revive token'..(committed.ReviveTokens==1 and''or's')..'.')or''
  purchaseNotice(p,tostring(message)..extra)
 end
 if offer.giftRevive==true and committed.GiftClaims[purchaseId]=='pending'then
  local claimant=Http:GenerateGUID(false)
  local claimed,_,claimState=transaction(p,{kind='claimGift',id=purchaseId,claim=claimant})
  if claimed and claimState and claimState.GiftClaims[purchaseId]==claimant then
   local selection=giftTargets[p];giftTargets[p]=nil
   if selection and selection.expires>=os.clock()then
    local target=Players:GetPlayerByUserId(selection.userId)
    local recovery=game.ServerStorage:FindFirstChild('RecoveryApi')
    if recovery and target then
     local operationId=purchaseId -- Recovery's stable raw PurchaseId operation key, <=160 bytes.
     -- The durable token exists before this attempt; Recovery owns consume/confirm/refund.
     -- Keep ProcessReceipt bounded; the game-thread attempt may yield during LoadCharacterAsync.
     task.spawn(function()
      local success=pcall(function()return recovery:Invoke('GiftRevive',p,target,operationId,selection.identity)end)
      if not success then M.RefundRevive(p,operationId)end
     end)
    end
   end
  end
 end
 return Enum.ProductPurchaseDecision.PurchaseGranted
end
Players.PlayerRemoving:Connect(function(p)giftTargets[p]=nil end)
function M.ConsumeRevive(p,id)if UNLIMITED_REVIVES[p.UserId]then return true,'Revive used (unlimited).'end;return transaction(p,{kind='consumeRevive',id=id})end
function M.ConfirmRevive(p,id)return transaction(p,{kind='confirmRevive',id=id})end
function M.RecoverRevives(p)return transaction(p,{kind='recoverRevives'})end
function M.RefundRevive(p,id)return transaction(p,{kind='refundRevive',id=id})end

-- Saved pass benefits are granted exclusively by the experience owner's Roblox account.
local ADMIN_OWNER_USER_ID=315936607
local AdminAccess=require(script.Parent:WaitForChild('AdminAccess'))
function M.AdminPassInfo(actor)
 if typeof(actor)~='Instance'or not actor:IsA('Player')or actor.Parent~=Players or not AdminAccess.IsAdmin(actor) then return false,'Owner access only.'end
 local passes={};for _,offer in C.RobuxOffers do if offer.kind=='Pass'then table.insert(passes,{id=offer.id,name=offer.name})end end
 local roster={};for _,target in Players:GetPlayers()do
  table.insert(roster,{id=target.UserId,name=target.Name,displayName=target.DisplayName,passes=table.clone(entitlements[target]or {})})
 end
 table.sort(roster,function(a,b)return a.name:lower()<b.name:lower()end)
 return true,{passes=passes,players=roster}
end
function M.AdminGrantPass(actor,userId,offerId)
 if typeof(actor)~='Instance'or not actor:IsA('Player')or actor.Parent~=Players or not AdminAccess.IsOwner(actor) then return false,'Owner access only.'end
 if type(userId)~='number'or userId~=userId or userId%1~=0 or userId<=0 or userId>9007199254740991 then return false,'Invalid player.'end
 if type(offerId)~='string'or #offerId>60 then return false,'Invalid pass.'end
 local offer=C.RobuxById[offerId];if not offer or offer.kind~='Pass'then return false,'Unknown game pass.'end
 local target=Players:GetPlayerByUserId(userId)
 if not target then return false,'Choose someone currently in your server.'end
 local ok,message=transaction(target,{kind='adminPass',offer=offerId})
 if not ok then return false,message end
 local owned=entitlements[target]or {};entitlements[target]=owned;owned[offerId]=true
 target:SetAttribute('Pass_'..offerId,true);publish(target)
 local persistent=mode[target]=='persistent'
 notify(target,'The owner gave you '..offer.name..' access.'..(persistent and ' Saved for future games.'or ' Studio preview only.'))
 return true,{message=message..(persistent and ' Saved for future games.'or ' Studio preview only; saves are unavailable.'),persistent=persistent,targetId=userId,offerId=offerId}
end
local adminEvent=RS:FindFirstChild('AdminPassEvent')or Instance.new('RemoteEvent')
adminEvent.Name='AdminPassEvent';adminEvent.Parent=RS
local adminBusy,adminNext={},{}
local function adminRequest(actor,action,userId,offerId)
 if typeof(actor)~='Instance'or not actor:IsA('Player')or actor.Parent~=Players or not AdminAccess.IsAdmin(actor) then return false,'Owner access only.'end
 if action=='list'then return M.AdminPassInfo(actor)end
 if action~='grant'then return false,'Unknown admin action.'end
 return M.AdminGrantPass(actor,userId,offerId)
end
adminEvent.OnServerEvent:Connect(function(actor,requestId,action,userId,offerId)
 if not AdminAccess.IsAdmin(actor)then return end
 if type(requestId)~='number'or requestId~=requestId or requestId%1~=0 or requestId<1 or requestId>1e9 then return end
 if type(action)~='string'or #action>12 then return end
 if adminBusy[actor]or os.clock()<(adminNext[actor]or 0)then adminEvent:FireClient(actor,requestId,false,'Please wait for the previous request.');return end
 adminNext[actor]=os.clock()+.5;adminBusy[actor]=true
 task.spawn(function()
  local success,ok,result=pcall(adminRequest,actor,action,userId,offerId)
  adminBusy[actor]=nil
  if actor.Parent then adminEvent:FireClient(actor,requestId,success and ok==true,success and result or 'Admin service is unavailable.')end
 end)
end)
Players.PlayerRemoving:Connect(function(p)adminBusy[p]=nil;adminNext[p]=nil end)
if studio then
 local test=Instance.new('BindableFunction');test.Name='AdminPassTest';test.Parent=script
 test.OnInvoke=adminRequest
end

-- 2026-10-03: revive token buyers had to press revive again after buying; +1 token per purchase made before the fix.
local REVIVE_COMP={[10469325456]=2,[2503307865]=1,[3019418768]=1}
local function compensate(p)
 local amount=REVIVE_COMP[p.UserId];if not amount then return end
 if not M.Load(p)or mode[p]~='persistent'then return end
 transaction(p,{kind='compensate',key='ReviveToken_20261003',amount=amount})
end
-- 2026-10-17: Jumpscare Everyone often did nothing on phones; every earlier buyer gets one free charge, shown
-- to them in the middle of the screen (GrantNotice client) on the join it is granted.
local JUMPSCARE_COMP_KEY='JumpscareAll_20261017'
local function compensateJumpscare(p)
 if not M.Load(p)or mode[p]~='persistent'then return end
 local d=data[p];if not d or d.CompGrants[JUMPSCARE_COMP_KEY]then return end
 local ok,message=transaction(p,{kind='compJumpscare',key=JUMPSCARE_COMP_KEY})
 if ok and message=='granted'and p.Parent then p:SetAttribute('GrantNotice','jumpscare')end
end
-- 2026-10-17 owner appreciation award: the top 4 Total Retrieved players get the Flashlight Colors pass, 3 revive
-- tokens and 500 tokens once, with a gold card on that join. OWNER_AWARD_LIVE stays false until the owner approves
-- the preview (Studio: ServerStorage.OwnerAwardPreview:Invoke() shows the card to the owner without granting).
local OWNER_AWARD_KEY='OwnerAward_20261017'
local OWNER_AWARD_LIVE=true
local OWNER_AWARD_USERS={[3184980922]=true,[1768534720]=true,[10083716019]=true,[7552093693]=true}
local function ownerAward(p)
 if studio and not OWNER_AWARD_LIVE then p:SetAttribute('GrantNotice','ownerAward');return end -- Studio playtests: preview the card on join, grant nothing
 if not OWNER_AWARD_LIVE or not OWNER_AWARD_USERS[p.UserId]then return end
 if not M.Load(p)or mode[p]~='persistent'then return end
 local d=data[p];if not d or d.CompGrants[OWNER_AWARD_KEY]then return end
 local ok,message=transaction(p,{kind='ownerAward',key=OWNER_AWARD_KEY})
 if ok and message=='granted'and p.Parent then M.RefreshPasses(p);p:SetAttribute('GrantNotice','ownerAward')end
end
if studio then
 local preview=Instance.new('BindableFunction');preview.Name='OwnerAwardPreview';preview.Parent=game:GetService('ServerStorage')
 preview.OnInvoke=function()for _,p in Players:GetPlayers()do p:SetAttribute('GrantNotice','ownerAward')end;return true end
end
-- The owner's account gets every rank reward cosmetic once (owner request 2026-10-22). Studio session saves get it every session.
local OWNER_RANK_KEY='OwnerRankCosmetics_20261022'
local function ownerRankCosmetics(p)
 if p.UserId~=315936607 then return end
 if not M.Load(p)or not(mode[p]=='persistent'or studio and mode[p]=='memory')then return end
 local d=data[p];if not d or d.CompGrants[OWNER_RANK_KEY]then return end
 local ok,message=transaction(p,{kind='ownerRankCosmetics',key=OWNER_RANK_KEY})
 if ok and message=='granted'and p.Parent then
  local ev=RS:FindFirstChild('LobbyEvent');if ev then ev:FireClient(p,'notice','Every rank title, aura and trail is now yours. Equip them in Character.')end
 end
end
-- No like/favorite reward: Roblox does not allow rewards for liking or favoriting (removed 2026-10-07).
-- Owner gifts (owner 2026-10-28 "give user @DRAGONAMANDA15 the heart trail"): cosmetics added to a player's save on their
-- next join through the normal 'grant' op (additive; one they already own is skipped), with a notice.
local OWNER_GIFTS={[2565716611]={'trail_hearts'}} -- DRAGONAMANDA15: Heart Trail
local function ownerGifts(p)
 local ids=OWNER_GIFTS[p.UserId];if not ids then return end
 if not M.Load(p)or mode[p]~='persistent'then return end
 local d=data[p];if not d then return end
 local missing={};for _,id in ids do if not d.Owned[id]then table.insert(missing,id)end end
 if #missing==0 then return end
 local ok,message=transaction(p,{kind='grant',ids=missing})
 if ok then publish(p);notify(p,'The owner sent you a gift! '..tostring(message)..' Equip it in CHARACTER.')end
end
local function joinedBonus(p)
 compensate(p)
 compensateJumpscare(p)
 ownerAward(p)
 ownerRankCosmetics(p)
 ownerGifts(p)
end
Players.PlayerAdded:Connect(function(p)task.spawn(joinedBonus,p)end)
for _,p in Players:GetPlayers()do task.spawn(joinedBonus,p)end
Marketplace.ProcessReceipt=M.Receipt
Marketplace.PromptGamePassPurchaseFinished:Connect(function(p,passId,purchased)
 if purchased then task.spawn(function()
  -- Roblox ownership is checked again on the server; the prompt is not the authority.
  for attempt=1,3 do M.RefreshPasses(p);local found=false;for _,offer in C.RobuxOffers do if offer.assetId==passId and p:GetAttribute('Pass_'..offer.id)then found=true end end;if found then break end;task.wait(attempt)end
 end)end
end)

local function joined(p)
 -- First Shift requires the server's completed spawn handshake, not a client badge request.
 local function observeCharacter(ch)
  local function entered()
   if p.Character==ch and p:GetAttribute('MissionActive')==true and ch:GetAttribute('RecoverySpawnReady')==true then
    badgeSession[p]=true;queueBadges(p);pushBadges(p)
   end
  end
  ch:GetAttributeChangedSignal('RecoverySpawnReady'):Connect(entered)
  entered()
 end
 p.CharacterAdded:Connect(observeCharacter)
 if p.Character then observeCharacter(p.Character)end
 p:GetAttributeChangedSignal('MissionActive'):Connect(function()
  local ch=p.Character
  if ch and p:GetAttribute('MissionActive')==true and ch:GetAttribute('RecoverySpawnReady')==true then badgeSession[p]=true;queueBadges(p);pushBadges(p)end
 end)
 p:GetAttributeChangedSignal('AdminSimulateNoPasses'):Connect(function()task.spawn(M.RefreshPasses,p)end)
 p.CharacterAdded:Connect(function(ch)task.spawn(function()ch:WaitForChild('Head',12);ch:WaitForChild('HumanoidRootPart',12);if p.Character==ch then cosmetic(p)end end)end)
 p:GetAttributeChangedSignal('MissionActive'):Connect(function()if p.Character then cosmetic(p)end end) -- lobby name tag on/off
 task.spawn(function()if M.Load(p)then local d=data[p];local pending=false;for _,status in d.ReviveUses do if status=='consumed'then pending=true end end;if pending then M.RecoverRevives(p)end
  local top=C.TokenPackTopUps and C.TokenPackTopUps[p.UserId] -- one-time top-up for old token-pack buyers (2026-10-27)
  if top then local ok,msg=transaction(p,{kind='packTopUp',id=top.id,tokens=top.tokens});if ok and msg~='Already granted.'then purchaseNotice(p,msg)end end
 end;M.RefreshPasses(p)end)
end
Q.Bind({Load=M.Load,Profile=function(p)return data[p]end,Transaction=transaction,CanUseVanShop=function(p)return M.CanUseVanShop(p)end,CanPersist=function(p)return mode[p]=='persistent'end,ReleaseDeparted=releaseDeparted})
Players.PlayerAdded:Connect(joined);for _,p in Players:GetPlayers()do joined(p)end
-- Item effects win the head slot: hide the cosmetic hat while a cursed hat/cloud is on that player, restore it after.
local HEAD_WEAR={BirthdayHat=true,Cloud=true}
task.spawn(function()
 while true do
  task.wait(.25)
  local busy={}
  local level=workspace:FindFirstChild('CursedLevelCosmetics')
  if level then for _,m in level:GetChildren()do if m:GetAttribute('CosmeticRole')=='CoolHat'then busy[m:GetAttribute('CosmeticOwner')or 0]=true end end end
  local map=workspace:FindFirstChild('Mansion');local items=map and map:FindFirstChild('Interactive')
  if items then for _,m in items:GetChildren()do if HEAD_WEAR[m:GetAttribute('ItemWearRole')or'']then busy[m:GetAttribute('ItemWearOwner')or 0]=true end end end
  for _,p in Players:GetPlayers()do
   local folder=p.Character and p.Character:FindFirstChild('ProgressCosmetics');local hat=folder and folder:FindFirstChild('CosmeticHat')
   if hat then
    local hidden=busy[p.UserId]==true
    if hat:GetAttribute('HiddenByEffect')~=hidden then
     hat:SetAttribute('HiddenByEffect',hidden)
     for _,part in hat:GetDescendants()do if part:IsA('BasePart')and part.Name~='Handle'then
      if hidden then part:SetAttribute('ShownTransparency',part.Transparency);part.Transparency=1 else part.Transparency=part:GetAttribute('ShownTransparency')or 0 end
     end end
    end
   end
  end
 end
end)
Players.PlayerRemoving:Connect(function(p)
 if rewardDepartureFlush then rewardDepartureFlush(p) end
 badgeOwned[p]=nil;badgePending[p]=nil;badgeSession[p]=nil
 for i=#badgeQueue,1,-1 do if badgeQueue[i].player==p then table.remove(badgeQueue,i)end end
 entitlements[p]=nil
 task.spawn(function()
  local deadline=os.clock()+20;while(busy[p]or queue[p])and os.clock()<deadline do task.wait(.1)end
  if not queue[p] and not busy[p] and not Q.HasPending(p)then data[p]=nil;loaded[p]=nil;mode[p]=nil end -- quest/clear retry owners release departed data after confirmed saves
 end)
end)
game:BindToClose(function()
 if game:GetService('RunService'):IsStudio() then return end -- Studio stop: close-time saves can hang the server shutdown
 local deadline=os.clock()+25
 repeat local pending=false;for _,jobs in queue do if #jobs>0 then pending=true end end;for _,value in busy do if value then pending=true end end;if not pending then break end;task.wait(.1)until os.clock()>deadline
end)
-- Van rewards share ProgressService's transaction and ProgressCore's atomic currency grants.
local RewardsConfig=require(RS:WaitForChild('RewardsConfig'))
local rewardSessions,rewardBusy,rewardNext,rewardStateNext,rewardOpening={},{},{},{},{}
local function ensureRewardRemote(parent,name,className)
 local child=parent:FindFirstChild(name)
 assert(not child or child.ClassName==className,'VanRewards '..name..' has the wrong class')
 if not child then child=Instance.new(className);child.Name=name;child.Parent=parent end
 return child
end
local rewardsFolder=ensureRewardRemote(RS,'VanRewards','Folder')
local rewardsGetState=ensureRewardRemote(rewardsFolder,'GetState','RemoteFunction')
local rewardsClaim=ensureRewardRemote(rewardsFolder,'Claim','RemoteFunction')
local rewardsChanged=ensureRewardRemote(rewardsFolder,'StateChanged','RemoteEvent')
local function startRewardSession(p)
 if rewardSessions[p] then return rewardSessions[p] end
 local s={owner=Http:GenerateGUID(false),newId=Http:GenerateGUID(false),openAt=os.time(),openedAt=DateTime.now().UnixTimestampMillis,pendingDaily=nil}
 rewardSessions[p]=s
 return s
end
local function rewardSeconds(s)
 return math.clamp(math.floor((s.baseSeconds or 0)+os.clock()-(s.startedClock or os.clock())),0,RewardsConfig.MaxSeconds)
end
local function ensureRewardSession(p)
 local s=startRewardSession(p)
 if s.id then return s end
 local deadline=os.clock()+20
 while rewardOpening[p] and os.clock()<deadline do task.wait(.05) end
 if s.id then return s end
 if rewardOpening[p] then return nil,'Rewards are still loading. Please try again.' end
 if p.Parent~=Players then return nil,'Player is unavailable.' end
 rewardOpening[p]=true
 local clockBefore=os.clock()
 local ok,message,committed=transaction(p,{kind='vanSessionOpen',sessionId=s.newId,owner=s.owner,now=s.openAt,openedAt=s.openedAt})
 rewardOpening[p]=nil
 if not ok or not committed then return nil,message end
 local saved=RewardsConfig.ProfileRewards(committed).timedSession
 if not saved or saved.owner~=s.owner then return nil,'Your rewards session moved to another server.' end
 s.id=saved.id;s.startedAt=saved.startedAt;s.baseSeconds=saved.playedSeconds;s.startedClock=clockBefore
 return s
end
local function rewardState(p)
 local d=data[p];local s=rewardSessions[p]
 if not d or not s or not s.id then return nil end
 local now=os.time();local utcDay=math.floor(now/86400)
 local saved=RewardsConfig.ProfileRewards(d)
 local canClaim=saved.lastDailyDay<utcDay
 local streak=RewardsConfig.EffectiveStreak(d,utcDay)
 local cycleStart=math.floor((math.max(streak,1)-1)/7)*7+1
 local track={}
 for day=cycleStart,cycleStart+6 do
  local claimed=day<streak or (day==streak and not canClaim)
  local reward=RewardsConfig.Daily(day,RewardsConfig.DailyRoll(p.UserId,utcDay+day-streak))
  if day==streak and not canClaim and saved.lastDailyReward then reward=table.clone(saved.lastDailyReward) end
  table.insert(track,{day=day,reward=reward,claimed=claimed})
 end
 local elapsed=rewardSeconds(s);local ledger=saved.timedSession
 local slots={};local nextTimed=false
 for _,slot in RewardsConfig.TimedSlots do
  local claimed=ledger~=nil and ledger.id==s.id and ledger.claimed[slot.id]==true
  local reward=RewardsConfig.Timed(slot.id)
  table.insert(slots,{id=slot.id,at=slot.at,reward=reward,claimed=claimed,ready=not claimed and elapsed>=slot.at})
  if not claimed and not nextTimed then
   nextTimed={id=slot.id,at=slot.at,reward=table.clone(reward),remainingSeconds=math.max(0,slot.at-elapsed)}
  end
 end
 local nextDay=canClaim and streak or streak+1
 local nextRewardDay=canClaim and utcDay or utcDay+1
 return {serverTime=now,
  daily={streak=streak,canClaim=canClaim,nextClaimAt=(utcDay+1)*86400,track=track},
  timed={sessionSeconds=elapsed,maxSeconds=RewardsConfig.MaxSeconds,slots=slots},
  teaser={daily={day=nextDay,reward=RewardsConfig.Daily(nextDay,RewardsConfig.DailyRoll(p.UserId,nextRewardDay)),rarePossible=nextDay%7==0},timed=nextTimed}}
end
local function rewardPush(p)
 if p.Parent~=Players then return end
 local state=rewardState(p)
 if state then rewardsChanged:FireClient(p,state) end
end
function M.VanRewardsState(p)
 if typeof(p)~='Instance' or not p:IsA('Player') or p.Parent~=Players then return {ok=false,reason='Player is unavailable.'} end
 if not M.Load(p) or p.Parent~=Players then return {ok=false,reason='Your save is unavailable. Please try again.'} end
 local session,reason=ensureRewardSession(p)
 if not session then return {ok=false,reason=reason or 'Rewards are unavailable.'} end
 return {ok=true,state=rewardState(p)}
end
local function claimVanRewardInner(p,kind,slotId)
 if not M.Load(p) or p.Parent~=Players then return {ok=false,reason='Your save is unavailable. Please try again.'} end
 local s,sessionReason=ensureRewardSession(p)
 if not s then return {ok=false,reason=sessionReason or 'Rewards are unavailable.'} end
 local now=os.time();local utcDay=math.floor(now/86400)
 local saved=RewardsConfig.ProfileRewards(data[p])
 local op
 if kind=='daily' then
  -- Keep an unresolved operation (including its random roll) across ambiguous save failures.
  -- UpdateAsync may have committed before transport failure; Core checks the durable day marker.
  if s.pendingDaily then
   op=s.pendingDaily
  else
   if saved.lastDailyDay>=utcDay then return {ok=false,reason='Today\'s reward is already claimed.'} end
   op={kind='vanDaily',day=utcDay,roll=RewardsConfig.DailyRoll(p.UserId,utcDay)}
   s.pendingDaily=op
  end
 else
  local reward=RewardsConfig.Timed(slotId)
  if not reward then return {ok=false,reason='Invalid timed reward.'} end
  local slot
  for _,candidate in RewardsConfig.TimedSlots do if candidate.id==slotId then slot=candidate;break end end
  local elapsed=rewardSeconds(s)
  if not slot or elapsed<slot.at then return {ok=false,reason='Keep playing to unlock this reward.'} end
  local ledger=saved.timedSession
  if ledger and ledger.claimed[slotId] then return {ok=false,reason='This session reward is already claimed.'} end
  op={kind='vanTimed',sessionId=s.id,sessionStartedAt=s.startedAt,owner=s.owner,now=now,slotId=slotId,elapsedSeconds=elapsed}
 end
 local ok,message,committed=transaction(p,op)
 if not ok or not committed then
  if kind=='daily' and message=='Daily reward clock moved backwards.' then s.pendingDaily=nil end
  return {ok=false,reason=message or 'Your reward could not save. Please try again.'}
 end
 local result=RewardsConfig.ProfileRewards(committed)
 local reward
 if kind=='daily' then
  if result.lastDailyDay~=op.day then s.pendingDaily=nil;return {ok=false,reason='A newer daily reward was already claimed.'} end
  reward=result.lastDailyReward or RewardsConfig.Daily(result.streak,op.roll)
  s.pendingDaily=nil
 else
  local ledger=result.timedSession
  if not ledger or ledger.id~=s.id or ledger.owner~=s.owner or ledger.claimed[slotId]~=true then return {ok=false,reason='This session reward could not be confirmed.'} end
  reward=RewardsConfig.Timed(slotId)
 end
 rewardPush(p)
 return {ok=true,reward=table.clone(reward),state=rewardState(p)}
end
function M.ClaimVanReward(p,kind,slotId)
 if typeof(p)~='Instance' or not p:IsA('Player') or p.Parent~=Players then return {ok=false,reason='Player is unavailable.'} end
 if type(kind)~='string' or (kind~='daily' and kind~='timed') then return {ok=false,reason='Invalid reward kind.'} end
 if kind=='daily' and slotId~=nil then return {ok=false,reason='Daily rewards do not use a slot.'} end
 if kind=='timed' and (type(slotId)~='string' or #slotId>8 or not RewardsConfig.Timed(slotId)) then return {ok=false,reason='Invalid timed reward.'} end
 if rewardBusy[p] or os.clock()<(rewardNext[p] or 0) then return {ok=false,reason='Please wait before claiming again.'} end
 rewardBusy[p]=true;rewardNext[p]=os.clock()+.75
 local ok,result=pcall(claimVanRewardInner,p,kind,slotId)
 rewardBusy[p]=nil
 if p.Parent~=Players then rewardNext[p]=nil end
 if not ok then warn('VanRewards claim failed for '..p.UserId..': '..tostring(result));return {ok=false,reason='Your reward could not save. Please try again.'} end
 return result
end
rewardsGetState.OnServerInvoke=function(p)
 if os.clock()<(rewardStateNext[p] or 0) then return {ok=false,reason='Please wait before refreshing.'} end
 rewardStateNext[p]=os.clock()+.25
 return M.VanRewardsState(p)
end
rewardsClaim.OnServerInvoke=function(p,kind,slotId) return M.ClaimVanReward(p,kind,slotId) end
local function joinedRewards(p)
 startRewardSession(p)
 task.spawn(function()
  if M.Load(p) and p.Parent==Players then ensureRewardSession(p);rewardPush(p) end
 end)
end
Players.PlayerAdded:Connect(joinedRewards)
for _,p in Players:GetPlayers() do joinedRewards(p) end
local function rewardCheckpoint(p,s)
 if not s or not s.id or p.Parent~=Players or rewardSessions[p]~=s then return false end
 return Q.Checkpoint(p,{kind='vanSessionCheckpoint',owner=s.owner,now=os.time(),playedSeconds=rewardSeconds(s)})
end
rewardDepartureFlush=function(p)
 local s=rewardSessions[p]
 if s and s.id and loaded[p] then
  -- This runs inside the existing ProgressService removal callback before it releases cached data.
  local op={kind='vanSessionCheckpoint',owner=s.owner,now=os.time(),playedSeconds=rewardSeconds(s)}
  Q.Checkpoint(p,op)
 elseif loaded[p] then Q.Flush(p) end
end
Players.PlayerRemoving:Connect(function(p)
 rewardSessions[p]=nil;rewardNext[p]=nil;rewardStateNext[p]=nil
 -- An in-flight request holds its own session and releases its lock after transaction finishes.
 if not busy[p] then rewardBusy[p]=nil end
end)
task.spawn(function()
 local tickCount=0
 while true do
  task.wait(15)
  tickCount+=1
  for _,p in Players:GetPlayers() do
   rewardPush(p)
   -- Play-time save every 75 s (5 ticks; was 30 s): it was most of the DataStore write traffic. Leaving still saves.
   if tickCount%5==0 then local s=rewardSessions[p];task.spawn(rewardCheckpoint,p,s) end
  end
 end
end)
game:BindToClose(function()
 if game:GetService('RunService'):IsStudio() then return end -- Studio stop: close-time saves can hang the server shutdown
 local pending=0
 for p,s in rewardSessions do
  if s.id then pending+=1;task.spawn(function()rewardCheckpoint(p,s);pending-=1 end) end
 end
 local deadline=os.clock()+25
 while pending>0 and os.clock()<deadline do task.wait(.1) end
end)

-- Owner admin: simulate reward time for testing (AdminPowersServer only, through a ServerStorage bindable that
-- clients cannot reach). The tester's profile switches to memory mode for the rest of the session, so test
-- grants and resets never write the real save; RESTORE puts the saved profile and save mode back.
do
 local adminBackups={}
 local function free(p) local t=os.clock();while(busy[p]or rewardBusy[p]or rewardOpening[p])and os.clock()-t<6 do task.wait(.1)end;return not(busy[p]or rewardBusy[p]or rewardOpening[p])end
 local function simulate(p,seconds,daily)
  if type(seconds)~='number'or seconds~=seconds or seconds<0 or seconds>86400 then return false,'Invalid seconds.'end
  seconds=math.floor(seconds)
  if not free(p)then return false,'Busy saving. Try again.'end
  if not M.Load(p)then return false,'Progress unavailable.'end
  local s,reason=ensureRewardSession(p);if not s then return false,reason or 'No reward session.'end
  task.wait(1.05) -- a deliberate reset can lower the claim score; push it in a later Unix second
  if p.Parent~=Players or rewardSessions[p]~=s or not free(p)then return false,'Session changed. Try again.'end
  local saved=Core.Reconcile(data[p]);if not saved then return false,'Profile unavailable.'end
  if not adminBackups[p]then adminBackups[p]={profile=Core.Reconcile(data[p]),mode=mode[p],session=table.clone(s)}end
  local v=RewardsConfig.ProfileRewards(saved);local now=os.time()
  if daily then local day=math.floor(now/86400);local today=RewardsConfig.EffectiveStreak(saved,day);v.lastDailyDay=day-1;v.streak=math.max(0,today-1);v.lastDailyReward=nil end
  local elapsed=math.min(RewardsConfig.MaxSeconds,rewardSeconds(s)+seconds)
  local current=v.timedSession
  if current and current.owner==s.owner and current.id==s.id then current.playedSeconds=elapsed;current.lastSeen=now end
  saved.VanRewards=v
  mode[p]='memory';data[p]=saved
  s.baseSeconds=elapsed;s.startedClock=os.clock();s.pendingDaily=nil
  rewardNext[p]=nil;rewardStateNext[p]=nil
  p:SetAttribute('RewardTestMode',true)
  publish(p);rewardPush(p)
  return true,(daily and 'Daily gift is claimable again. 'or '')..('Playtime now '..math.floor(elapsed/60)..' min. TEST MODE: nothing saves until RESTORE.')
 end
 local function restore(p)
  local backup=adminBackups[p];if not backup then return false,'Nothing to restore.'end
  if not free(p)then return false,'Busy saving. Try again.'end
  task.wait(1.05)
  data[p]=backup.profile;mode[p]=backup.mode;rewardSessions[p]=backup.session
  rewardNext[p]=nil;rewardStateNext[p]=nil;adminBackups[p]=nil
  p:SetAttribute('RewardTestMode',nil)
  publish(p);rewardPush(p)
  return true,'Real save restored. Saving works normally again.'
 end
 Players.PlayerRemoving:Connect(function(p)adminBackups[p]=nil end)
 local SS=game:GetService('ServerStorage')
 local api=SS:FindFirstChild('RewardAdminApi')or Instance.new('BindableFunction');api.Name='RewardAdminApi';api.Parent=SS
 api.OnInvoke=function(action,p,value)
  if typeof(p)~='Instance'or not p:IsA('Player')or p.Parent~=Players then return false,'Live player required.'end
  if action=='time'then return simulate(p,value,false)end
  if action=='daily'then return simulate(p,0,true)end
  if action=='restore'then return restore(p)end
  if action=='revives'then
   -- Owner admin grant: saved like any other revive tokens (one-time keyed grant, at most 10 per call).
   local n=math.clamp(math.floor(tonumber(value)or 1),1,10)
   local ok,msg=transaction(p,{kind='compensate',key='Admin_'..game:GetService('HttpService'):GenerateGUID(false),amount=n})
   if ok~=false then return true,'+'..n..' revive token'..(n>1 and 's'or'')..' (you now have '..tostring(p:GetAttribute('ReviveTokens'))..').'end
   return false,msg or 'Could not add revive tokens.'
  end
  return false,'Unknown reward action.'
 end
end
-- Native test bridge exists only in Studio with all three explicit test arguments.
do
 local ok,args=false,nil
 if studio then ok,args=pcall(function()return game:GetService('StudioTestService'):GetTestArgs()end)end
 if ok and type(args)=='table' and args.kind=='QuestNativeTest' and args.questTest==true and args.forceName=='QuestNativeTest' then
  local backups={};local SS=game:GetService('ServerStorage')
  local api=SS:FindFirstChild('QuestTestApi')or Instance.new('BindableFunction');api.Name='QuestTestApi';api.Parent=SS
  local function live(p)return typeof(p)=='Instance' and p:IsA('Player') and p.Parent==Players and p.UserId<=0 end
  api.OnInvoke=function(action,p,a,b,c)
   if action=='recordTeam' then
    if type(p)~='table' then return {ok=false,reason='Invalid roster.'}end
    for _,member in p do if not live(member) or not backups[member] then return {ok=false,reason='Isolated testers required.'}end end
    local ctx=table.clone(c or {});ctx.fixture=true
    return {ok=true,count=Q.RecordParty(p,a,b,ctx)}
   end
   if not live(p) then return {ok=false,reason='Native negative-ID player required.'}end
   if action=='begin' then
    if a~='QuestNativeTest' or backups[p] then return {ok=false,reason='Invalid fixture begin.'}end
    if not M.Load(p) or busy[p] then return {ok=false,reason='Save busy.'}end
    backups[p]={profile=Core.Reconcile(data[p]),mode=mode[p]}
    mode[p]='memory';data[p]=Core.Reconcile(nil);Q.SetFixture(p,true,20370*86400+1200);p:SetAttribute('QuestTestMode',true);publish(p)
    return {ok=true}
   end
   if not backups[p] then return {ok=false,reason='Isolated test not begun.'}end
   if action=='restore' then
    local saved=backups[p];Q.SetFixture(p,false);data[p]=saved.profile;mode[p]=saved.mode;backups[p]=nil;p:SetAttribute('QuestTestMode',nil);publish(p);return {ok=true}
   elseif action=='setTime' then
    if type(a)~='number' or a~=a or a%1~=0 or a<0 or a>100000000000 then return {ok=false,reason='Invalid time.'}end
    Q.SetTime(p,a);return {ok=true}
   elseif action=='state' then return Q.GetState(p)
   elseif action=='getProfile' then return {ok=true,profile=Core.Reconcile(data[p])}
   elseif action=='flush' then local success,reason=Q.Flush(p);return {ok=success,reason=reason}
   elseif action=='record' then local ctx=table.clone(c or {});ctx.fixture=true;return {ok=Q.Record(p,a,b,ctx)}
   elseif action=='claim' then return Q.Mutate(p,'claim',a,b,c)
   elseif action=='adminRewards' then return Q.AdminRewards(p,a,b,c)
   elseif action=='adminCatalog' then return {ok=true,rows=Q.AdminCatalog(p)}
   elseif action=='seedReady' then
    local r=Q.GetState(p);if not r.ok then return r end
    if a=='achievements'then for _,item in data[p].Quests.achievements do item.count=item.definition.targets[5]end;data[p].Quests.rev+=1;publish(p);Q.Push(p);return {ok=true,state=Core.QuestEngine.State(data[p],Q.Now(p))}end
    if a~='daily' and a~='weekly' then return {ok=false,reason='Invalid seed tab.'}end
    for _,item in data[p].Quests[a].entries do item.progress=item.definition.target end
    data[p].Quests.rev+=1;publish(p);Q.Push(p);return {ok=true,state=Core.QuestEngine.State(data[p],Q.Now(p))}
   end
   return {ok=false,reason='Unknown fixture action.'}
  end
  Players.PlayerRemoving:Connect(function(p)backups[p]=nil end)
 end
end
-- Studio-only fixture for the shop chapter (Studio saves stay in memory): 'fresh' turns this save into a never-tutored
-- one and completes the tutorial as a won first level would; 'freshSkip' goes through CompleteTutorial (the level check);
-- 'state' reads the chapter fields back.
if studio then
 local SS=game:GetService('ServerStorage')
 local api=SS:FindFirstChild('ShopTutorialTestApi')or Instance.new('BindableFunction');api.Name='ShopTutorialTestApi';api.Parent=SS
 api.OnInvoke=function(action,p)
  local d=data[p];if not d then return {ok=false,reason='no data'}end
  if action=='fresh'or action=='freshSkip'then
   d.TutorialDone=false;d.ShopTutorialStep=0;d.Upgrades.Speed=0
   if action=='freshSkip'then return {ok=(M.CompleteTutorial(p))}end
   local ok,msg=transaction(p,{kind='tutorial',completed=true});return {ok=ok,message=msg}
  end
  if action=='ownerReplay'then -- an owner whose chapter is done replays the tutorial (round must be 2+ or Won)
   d.TutorialDone=true;d.ShopTutorialStep=3;p:SetAttribute('AdminOwner',true);return {ok=(M.CompleteTutorial(p))}
  end
  if action=='state'then d=data[p];return {ok=true,step=d.ShopTutorialStep,tokens=d.Tokens,speed=d.Upgrades.Speed,tutorialDone=d.TutorialDone}end
  return {ok=false,reason='unknown action'}
 end
end

return M
