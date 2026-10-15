-- Pure, shared reward previews. Grants are recomputed by ProgressCore on the server.
local M = {MaxSeconds = 21600, DailySeconds = 86400}
local function integer(v, default)
 if type(v) ~= 'number' or v ~= v or math.abs(v) == math.huge then return default or 0 end
 return math.max(0, math.floor(v))
end
local dailyTokens = {30,40,50,65,80,100,130}
local function rarity(tokens,revives,instantWin)
 return instantWin>0 and 'legendary' or revives>=2 and 'epic' or (revives>=1 or tokens>=100) and 'rare' or 'common'
end
M.TimedSlots = {
 {id='5m',at=300,tokens=25,revives=0,instantWin=0},
 {id='15m',at=900,tokens=35,revives=0,instantWin=0},
 {id='30m',at=1800,tokens=45,revives=0,instantWin=0},
 {id='1h',at=3600,tokens=60,revives=1,instantWin=0},
 {id='2h',at=7200,tokens=80,revives=0,instantWin=0},
 {id='3h',at=10800,tokens=100,revives=1,instantWin=0},
 {id='4h',at=14400,tokens=120,revives=0,instantWin=0},
 {id='5h',at=18000,tokens=140,revives=1,instantWin=0},
 {id='6h',at=21600,tokens=200,revives=2,instantWin=1},
}
function M.Daily(streak, roll)
 streak=math.max(1,integer(streak))
 local day=(streak-1)%7+1
 local cycle=math.floor((streak-1)/7)
 local tokens=dailyTokens[day]+math.min(cycle,14)*5
 local revives=day==4 and 1 or day==7 and (1+math.min(math.floor(cycle/4),2)) or 0
 local instantWin=day==7 and type(roll)=='number' and roll>=1 and roll<=2500 and 1 or 0
 return {tokens=tokens,revives=revives,instantWin=instantWin,rarity=rarity(tokens,revives,instantWin)}
end
function M.Timed(id)
 for _,slot in M.TimedSlots do
  if slot.id==id then return {tokens=slot.tokens,revives=slot.revives,instantWin=slot.instantWin,rarity=rarity(slot.tokens,slot.revives,slot.instantWin)},slot.at end
 end
 return nil
end
-- Stable server preview and grant roll, without callback randomness.
function M.DailyRoll(userId, utcDay)
 return (integer(userId)%10000*7919 + integer(utcDay)%10000*1049 + 3571)%10000+1
end
function M.ProfileRewards(profile)
 local old=type(profile)=='table' and profile.VanRewards or nil
 local d={lastDailyDay=-1,streak=0,timedSessions={},timedFloor=0}
 if type(old)~='table' then return d end
 if type(old.lastDailyDay)=='number' and old.lastDailyDay>=0 then d.lastDailyDay=integer(old.lastDailyDay) end
 d.streak=integer(old.streak)
 if type(old.lastDailyReward)=='table' then
  local r=old.lastDailyReward
  d.lastDailyReward={tokens=math.min(integer(r.tokens),200),revives=math.min(integer(r.revives),3),instantWin=math.min(integer(r.instantWin),1),rarity=r.rarity=='legendary' and 'legendary' or r.rarity=='epic' and 'epic' or r.rarity=='rare' and 'rare' or 'common'}
 end
 d.timedFloor=integer(old.timedFloor)
 local s=old.timedSession
 if type(s)=='table' and type(s.id)=='string' and #s.id>0 and #s.id<=100 and type(s.owner)=='string' and #s.owner>0 and #s.owner<=100 then
  d.timedSession={id=s.id,owner=s.owner,ownerOpenedAt=integer(s.ownerOpenedAt),startedAt=integer(s.startedAt),playedSeconds=math.min(integer(s.playedSeconds),M.MaxSeconds),lastSeen=integer(s.lastSeen),claimed={}}
  if type(s.claimed)=='table' then for _,slot in M.TimedSlots do if s.claimed[slot.id]==true then d.timedSession.claimed[slot.id]=true end end end
 end
 if type(old.timedSessions)=='table' then
  for id,session in old.timedSessions do
   if type(id)=='string' and #id>0 and #id<=100 and type(session)=='table' then
    local entry={startedAt=integer(session.startedAt),claimed={}}
    if entry.startedAt>d.timedFloor then
     if type(session.claimed)=='table' then for _,slot in M.TimedSlots do if session.claimed[slot.id]==true then entry.claimed[slot.id]=true end end end
     d.timedSessions[id]=entry
    end
   end
  end
 end
 return d
end
function M.EffectiveStreak(profile, utcDay)
 local d=M.ProfileRewards(profile)
 if d.lastDailyDay==utcDay then return math.max(1,d.streak) end
 if d.lastDailyDay==utcDay-1 then return math.max(1,d.streak+1) end
 return 1
end
return M
