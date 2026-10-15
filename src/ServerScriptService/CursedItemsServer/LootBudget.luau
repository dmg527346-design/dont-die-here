-- Pure level budget. Quota is supplied by the existing recovery owner.
-- Item count follows the map's real floor area (bigger maps hold more items), grows a little with the level, and the
-- whole map always holds at least twice the quota. CursedItemsServer splits the value 50/25/25 by distance from spawn.
local B={}
B.BandShare={.5,.25,.25}
B.AreaPerItem=1700 -- sq studs of room floor per item on level 1: ~13-17 on the standard maps, ~17-22 Cruise, ~24-31 Mall
B.ItemWorth=45 -- typical level-1 item value; scales with valueScale on later levels
B.MinRatio=2 -- the map never holds less than twice the quota
B.DefaultArea=26000 -- standard-size map, used when the floor area is unknown
function B.Plan(level,quota,kind,area)
 level=math.max(1,math.floor(level))
 local large=kind=='Mall'or kind=='Cruise'
 local cap=math.ceil((large and 144 or 96)*1.45)
 local valueScale=1+.12*(level-1)
 -- later levels: a few more items as the quota climbs faster than item values (at most twice the level-1 count)
 local growth=math.clamp((quota/180)/valueScale,1,2)
 local count=math.clamp(math.floor((area or B.DefaultArea)/B.AreaPerItem*growth+.5),10,cap)
 local value=math.ceil(math.max(count*B.ItemWorth*valueScale,quota*B.MinRatio))
 return {count=count,cap=cap,ratio=value/math.max(1,quota),value=value,valueScale=valueScale}
end
function B.Value(id,plan,rng)
 return math.floor((id=='GiftCard'and 120 or rng:NextInteger(28,53))*plan.valueScale)
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
function B.Distribute(values,bands,target)
 local sums={0,0,0}
 for i,v in values do local b=bands[i] or 1;sums[b]+=v end
 local share=0;for b=1,3 do if sums[b]>0 then share+=B.BandShare[b] end end
 if share==0 then return 0 end
 local total=0
 for i,v in values do
  local b=bands[i] or 1
  values[i]=math.max(5,math.floor(v*(B.BandShare[b]/share)*target/sums[b]+.5));total+=values[i]
 end
 return total
end
return B
