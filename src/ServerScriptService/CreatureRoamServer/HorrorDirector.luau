-- Pacing reads global outcomes. It never supplies target positions to monster intelligence.
local Players=game:GetService('Players')
local M={}
function M.New(roundProvider)
 local d={intensity=0,reliefUntil=os.clock()+12,escapes={},encounters={},deaths={},lastThreat=os.clock(),lastUpdate=0,chases=0,objectiveProgress=0,meanHealth=1}
 function d:Death(p,now)
  self.deaths[p.UserId]=now;self.reliefUntil=math.max(self.reliefUntil,now+16);self.intensity=math.max(0,self.intensity-25)
 end
 function d:Tick(now,states)
  if now-self.lastUpdate<1 then return end
  local dt=math.min(2,now-self.lastUpdate);self.lastUpdate=now
  local chasing,alive,health=0,0,0
  for _,s in states do if s.mode=='Chase' then chasing+=1 end end
  for _,p in Players:GetPlayers()do
   local h=p.Character and p.Character:FindFirstChildOfClass('Humanoid')
   if p:GetAttribute('MissionActive')and not p:GetAttribute('RoundDead')and h and h.Health>0 then alive+=1;health+=h.Health/math.max(1,h.MaxHealth)end
  end
  self.meanHealth=alive>0 and health/alive or 1
  self.chases=chasing
  self.intensity=math.clamp(self.intensity+(chasing>0 and chasing*5 or -3)*dt,0,100)
  if self.intensity>78 or self.meanHealth<.35 then self.reliefUntil=math.max(self.reliefUntil,now+10)end
  local round=roundProvider()
  if round then
   self.objectiveProgress=math.clamp((round:GetAttribute('Sold')or 0)/math.max(1,round:GetAttribute('Quota')or 180),0,1)
   round:SetAttribute('HorrorIntensity',math.floor(self.intensity));round:SetAttribute('HorrorRelief',now<self.reliefUntil)
   round:SetAttribute('HorrorMeanHealth',self.meanHealth);round:SetAttribute('HorrorObjectiveProgress',self.objectiveProgress)
  end
 end
 return d
end
return M
