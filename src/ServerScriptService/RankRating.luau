-- RR (rank rating) maths. Server only: players see their rank and the RR change, never the formula.
-- Per-level counters come from QuestService.Record (deduplicated quest events), so dropping and re-grabbing
-- the same item never counts twice.
local Players=game:GetService('Players')
local M={}
M.DAILY=1.5 -- first clear of a UTC day
M.STREAK=1.75 -- first clear of the day once the daily streak reaches STREAK_DAYS
M.STREAK_DAYS=3
M.PROTECT_BELOW=150 -- the Newcomer tier never loses RR
M.SEASON_KEEP=.6 -- RR kept when a new monthly season starts
local level={} -- [player]={grabs=n,sold=n}
local function bucket(p)local b=level[p];if not b then b={grabs=0,sold=0};level[p]=b end;return b end
function M.Note(p,hook)
 if hook=='ItemPickup'then bucket(p).grabs+=1 elseif hook=='ItemSold'then bucket(p).sold+=1 end
end
function M.Take(p)local b=level[p] or {grabs=0,sold=0};level[p]=nil;return b end
Players.PlayerRemoving:Connect(function(p)level[p]=nil end)

function M.Day(t)return math.floor((t or os.time())/86400)end
function M.Season(t)local d=os.date('!*t',t or os.time());return d.year*12+d.month end

-- One-time starting RR for saves made before ranks existed, from the stats the leaderboards already keep.
function M.Seed(d)
 local rr=(d.LevelsCleared or 0)*12+(d.HighestLevel or 0)*25+40*math.log(1+(d.TotalRetrieved or 0)/1000)
 return math.clamp(math.floor(rr),0,9000) -- nobody starts as Legend
end

-- Higher RR earns less per level, so the top ranks take a long time.
local function slow(rr)return 1/(1+rr/2500)end

-- info={rr,level,seconds,money,died,grabs,sold,friends,carry}
function M.Gain(info)
 local lv=math.max(1,info.level or 1)
 local base=10+4*math.min(lv,25)
 local par=240+20*lv -- par time grows with the level
 local speed=math.clamp((par-(info.seconds or par))/par,0,.6)*(8+2*math.min(lv,25))
 local grab=6*math.sqrt(math.min(info.grabs or 0,60))
 local sell=4*math.sqrt(math.min(info.sold or 0,60))+3*math.log(1+math.max(0,info.money or 0)/100)
 local gain=(base+speed+grab+sell)*slow(info.rr or 0)
 if info.friends then gain*=1.1 end -- clearing with a friend
 if info.carry then gain*=1.1 end -- clearing with someone two or more tiers lower
 if info.died then gain*=.5 end
 return math.clamp(math.floor(gain+.5),1,200)
end

-- A failed run (team wipe nobody revived, or the timer ran out). Deeper levels cost less; Newcomers lose nothing.
function M.Loss(info)
 if (info.rr or 0)<M.PROTECT_BELOW then return 0 end
 local lv=math.max(1,info.level or 1)
 local depth=math.clamp(1.3-.1*(lv-1),.2,1.3)
 return math.clamp(math.floor((15+(info.rr or 0)*.01)*depth+.5),1,150)
end
return M
