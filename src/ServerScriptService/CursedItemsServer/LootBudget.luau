-- Pure level budget. Quota is supplied by the existing recovery owner.
-- Item count follows the map's real floor area (bigger maps hold more items), grows a little with the level, and the
-- whole map always holds at least twice the quota. CursedItemsServer splits the value 50/25/25 by distance from spawn.
local B={}
B.BandShare={.5,.25,.25}
B.AreaPerItem=1700 -- sq studs of room floor per item on level 1: ~13-17 on the standard maps, ~17-22 Cruise, ~24-31 Mall
B.ItemWorth=50 -- 45 x1.1 (2026-10-26);-- typical level-1 item value; scales with valueScale on later levels
B.MinRatio=2 -- the map never holds less than twice the quota
B.Level1Worth=29 -- 26 x1.1 (2026-10-26);-- level 1 items are cheaper (typical value ~26 instead of 45)
B.Cheaper=.85 -- level 2+: item value multiplier
B.DefaultArea=26000 -- standard-size map, used when the floor area is unknown
function B.Plan(level,quota,kind,area)
 level=math.max(1,math.floor(level))
 local large=kind=='Mall'or kind=='Cruise'
 local cap=math.ceil((large and 144 or 96)*1.45)
 local valueScale=1+.12*(level-1)
 -- later levels: a few more items as the quota climbs faster than item values (at most twice the level-1 count)
 local growth=math.clamp((quota/180)/valueScale,1,2)
 local count=math.clamp(math.floor((area or B.DefaultArea)/B.AreaPerItem*growth+.5),10,cap)
 local worth=level==1 and B.Level1Worth or B.ItemWorth
 local value=math.ceil(math.max(count*worth*valueScale,quota*B.MinRatio))
 -- Owner 2026-10-25: from level 2 every item is worth 15% less; more items spawn so the map holds the same total
 -- (at the cap the total may fall, never under 1.6x the quota).
 if level>=2 then
  local each=value/count*B.Cheaper
  count=math.min(cap,math.ceil(value/each))
  value=math.ceil(math.max(count*each,quota*1.6))
 end
 return {count=count,cap=cap,ratio=value/math.max(1,quota),value=value,valueScale=valueScale}
end
function B.Value(id,plan,rng)
 -- x1.1 (owner 2026-10-26: items 10% more valuable)
 return math.floor((id=='GiftCard'and 120 or rng:NextInteger(28,53))*plan.valueScale*1.1)
end
function B.EnsureValues(values,minimum)
 local total=0;for _,value in values do total+=value end
 if total<minimum and total>0 then
  local scale=minimum/total;total=0
  for i,value in values do values[i]=math.ceil(value*scale);total+=values[i]end
 end
 return total
end
-- Scale each distance band's items to its share of the target, up or down; a band with no items hands its
-- share to the others in proportion. Relative values inside a band (gift cards stay pricier) are kept.
function B.Distribute(values,bands,target,shares)
 shares=shares or B.BandShare
 local sums={0,0,0}
 for i,v in values do local b=bands[i] or 1;sums[b]+=v end
 local share=0;for b=1,3 do if sums[b]>0 then share+=shares[b] end end
 if share==0 then return 0 end
 local total=0
 for i,v in values do
  local b=bands[i] or 1
  values[i]=math.max(5,math.floor(v*(shares[b]/share)*target/sums[b]+.5));total+=values[i]
 end
 return total
end
-- Rare treasure (CursedA 2026-10-27): a fixed rule, never a random or paid reward. From each treasure's gate level
-- (catalog `treasure`) there is one treasure per level, rotating through the unlocked ones (kit template present) by
-- level number. Worth = treasureMult x the level's average item, capped at 75% of the quota; on top of the budget.
B.TreasureCap=.75
function B.Treasure(level,quota,plan,catalog,kit)
 local unlocked={}
 for _,id in catalog.Order do
  local meta=catalog.Items[id]
  if meta and meta.treasure and level>=meta.treasure and not table.find(unlocked,id) and (not kit or kit:FindFirstChild(id)) then unlocked[#unlocked+1]=id end
 end
 if #unlocked==0 then return nil,0 end
 table.sort(unlocked,function(a,b)
  local ga,gb=catalog.Items[a].treasure,catalog.Items[b].treasure
  if ga~=gb then return ga<gb end;return a<b
 end)
 local id=unlocked[(level-catalog.Items[unlocked[1]].treasure)%#unlocked+1]
 local each=plan.value/math.max(1,plan.count)
 local value=math.min(each*(catalog.Items[id].treasureMult or 4),quota*B.TreasureCap)
 return id,math.floor(value/5+.5)*5
end
return B
