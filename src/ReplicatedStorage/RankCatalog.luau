-- Rank tiers by RR (rank rating). Each tier below Legend has 3 divisions (I, II, III).
-- Rank rewards (2026-10-22), paid once each, ever: a new tier pays `tokens` plus its reward cosmetics (title, aura or
-- trail); every division step inside a tier (II, III) pays DIVISION_TOKENS. ProgressCore rrGrant pays them.
-- Icons: AI rank badges uploaded 2026-10-21 with the user's yes (icons\ranks\ai_512). '' falls back to a coloured gem.
local M={}
M.Tiers={
 {name='Newcomer',min=0,color={170,178,188},icon='rbxassetid://80751961940375'},
 {name='Wanderer',min=150,color={140,214,150},icon='rbxassetid://117221761960815',tokens=50,reward='rank_title_wanderer',reward2='aura_rank_wanderer'},
 {name='Survivor',min=450,color={110,220,210},icon='rbxassetid://128361757271495',tokens=100,reward='rank_title_survivor',reward2='aura_rank_survivor'},
 {name='Seeker',min=1000,color={120,180,245},icon='rbxassetid://96286290779818',tokens=150,reward='rank_title_seeker',reward2='aura_rank_seeker',reward3='trail_rank_seeker'},
 {name='Explorer',min=2000,color={160,150,250},icon='rbxassetid://118278577656838',tokens=250,reward='rank_title_explorer',reward2='aura_rank_explorer'},
 {name='Veteran',min=3600,color={210,155,245},icon='rbxassetid://118826806657251',tokens=400,reward='rank_title_veteran',reward2='aura_rank_veteran',reward3='trail_rank_veteran'},
 {name='Phantom',min=6000,color={225,235,250},icon='rbxassetid://138671406178072',tokens=600,reward='rank_title_phantom',reward2='aura_rank_phantom'},
 {name='Legend',min=10000,color={255,224,110},icon='rbxassetid://89890387013145',tokens=1000,reward='rank_title_legend',reward2='aura_rank_legend',reward3='trail_rank_legend'},
}
local ROMAN={'I','II','III'}
-- {tier=index, division=1..3 or nil, name='Seeker II', color=Color3, icon=string}
function M.Get(rr)
 rr=math.max(0,tonumber(rr)or 0)
 local i=1;for k,t in M.Tiers do if rr>=t.min then i=k end end
 local t=M.Tiers[i];local nextTier=M.Tiers[i+1]
 local division
 if nextTier then division=math.clamp(math.floor((rr-t.min)/((nextTier.min-t.min)/3))+1,1,3)end
 return {tier=i,division=division,name=division and (t.name..' '..ROMAN[division]) or t.name,color=Color3.fromRGB(t.color[1],t.color[2],t.color[3]),icon=t.icon}
end
-- RR span of the current division: lo, and hi (the next rank's start; nil at Legend).
function M.Progress(rr)
 rr=math.max(0,tonumber(rr)or 0)
 local r=M.Get(rr);local t=M.Tiers[r.tier];local nextTier=M.Tiers[r.tier+1]
 if not nextTier then return t.min,nil end
 local step=(nextTier.min-t.min)/3
 return math.floor(t.min+step*(r.division-1)),math.floor(t.min+step*r.division)
end
-- Rank steps: 1 = Newcomer I ... 3 per tier, Legend is the last step. Rewards are paid per step, once.
M.DIVISION_TOKENS=20
function M.Step(rr)
 local r=M.Get(rr);return (r.tier-1)*3+(r.division or 1)
end
function M.MaxStep()return (#M.Tiers-1)*3+1 end
-- What reaching `step` pays: tokens, and on a new tier its reward cosmetic ids. tier, division of that step.
function M.StepReward(step)
 local tier=math.clamp(math.floor((step-1)/3)+1,1,#M.Tiers);local division=(step-1)%3+1
 local t=M.Tiers[tier]
 if division==1 then
  local ids={};for _,id in {t.reward,t.reward2,t.reward3}do if id then table.insert(ids,id)end end
  return {tier=tier,division=1,tokens=t.tokens or 0,cosmetics=ids,newTier=true}
 end
 return {tier=tier,division=division,tokens=M.DIVISION_TOKENS,cosmetics={},newTier=false}
end
return M
