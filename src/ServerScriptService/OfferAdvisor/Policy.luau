-- Pure session policy: no persistence, purchases, or client-derived eligibility.
local M={}
M.FirstDelay=90
M.Cooldown=240
M.PerLevel=3
M.Lifetime=12
M.AnswerGrace=1
local choices={yes=true,no=true,close=true,timeout=true}
local phases={Searching=true,Returning=true,Selling=true}
function M.New(now,level)
 return {started=now,lastShown=-math.huge,level=level,shownLevel=0,deathsRun=0,deathsLevel=0,declined={},active=nil,lastOffer=nil}
end
function M.SetLevel(s,level)
 if s.level==level then return false end
 s.level=level;s.shownLevel=0;s.deathsLevel=0;s.declined={};s.active=nil
 return true
end
function M.RecordDeath(s)
 s.deathsRun+=1;s.deathsLevel+=1
end
function M.CanShow(s,c,now,permanent)
 if not c.mission or not c.ready or not c.safe or c.modal or not phases[c.phase] then return false end
 if permanent then return true end
 if s.active or now-s.started<M.FirstDelay or now-s.lastShown<M.Cooldown or s.shownLevel>=M.PerLevel then return false end
 return true
end
function M.Select(s,c)
 local candidates={}
 local function add(id,reason)
  if not s.declined[id] then table.insert(candidates,{id=id,reason=reason})end
 end
 local function revival(reason)
  if c.owned.free_revive==false then add('free_revive',reason)end
  if (c.reviveTokens or 0)==0 and not c.freeReviveAvailable then add('revive_token',reason)end
 end
 if s.deathsLevel>=2 or s.deathsRun>=3 then revival('second_chance')end
 -- Solo play never recommends a party prank or a social cosmetic.
 if #candidates==0 and c.solo then revival('solo_backup')end
 if #candidates==0 and not c.solo and c.social then
  if (c.jumpscareCharges or 0)==0 then add('jumpscare_all','friends_together')end
  for _,id in ipairs({'pass_hat_crown','pass_hat_halo','vip'})do
   if c.owned[id]==false then add(id,'friends_together')end
  end
 end
 if #candidates==0 then return nil end
 for _,offer in ipairs(candidates)do if offer.id~=s.lastOffer then return offer.id,offer.reason end end
 return candidates[1].id,candidates[1].reason
end
function M.Show(s,offer,now,id,permanent)
 s.active={id=id,offer=offer,expires=permanent and math.huge or now+M.Lifetime,level=s.level,permanent=permanent==true}
 s.lastShown=now;s.lastOffer=offer
 if not permanent then s.shownLevel+=1 end
 return s.active
end
function M.Answer(s,id,choice,now)
 local a=s.active
 if type(id)~='string'or #id>80 or not choices[choice]or not a or id~=a.id or a.level~=s.level or now>a.expires+M.AnswerGrace then return false end
 s.active=nil
 if choice~='yes'then s.declined[a.offer]=true end
 return true,a.offer
end
function M.Expire(s,now)
 local a=s.active
 if a and now>a.expires+M.AnswerGrace then s.active=nil;s.declined[a.offer]=true;return true end
 return false
end
return M
