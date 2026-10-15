-- Developer harness: plans and validates many seeds without building or playing.
-- Plan-level only. Built geometry, navmesh and live AI still need MapGen's
-- V.Built/V.Paths and Verification.Traverse on selected seeds.
-- Usage (Studio command bar): require(game.ServerScriptService.MapGen.StressTest).Run(1000)
local P=require(script.Parent.Planner)
local V=require(script.Parent.Validator)
local G=require(script.Parent.GraphExport)
local T=require(script.Parent.Topology)
local Profiles=require(script.Parent.Profiles)
local S={}
local function bump(t,k)t[k]=(t[k]or 0)+1 end
local function spread(list)
 table.sort(list);local n=#list;if n==0 then return nil end
 local sum=0;for _,v in ipairs(list)do sum+=v end
 return {min=list[1],p50=list[math.ceil(n*.5)],p95=list[math.ceil(n*.95)],max=list[n],mean=sum/n}
end
-- Route probes. Severed pairs and absurd same-floor detours fail the seed.
-- Cross-floor detour (route minus horizontal gap) is a tuning metric: with one
-- staircase, rooms stacked 16 studs apart can be 250+ studs apart by route.
local function probe(graph,rng,pairs,crossDetours,maxRatio,ratios)
 local oracle=T.New(graph);local issues={}
 local rooms=graph.rooms
 for _=1,pairs do
  local a,b=rooms[rng:NextInteger(1,#rooms)],rooms[rng:NextInteger(1,#rooms)]
  if a~=b then
   local route=oracle:RoomDistance(a.name,b.name)
   local d=T.Center(a)-T.Center(b);local flat=Vector3.new(d.X,0,d.Z).Magnitude
   if route==math.huge then table.insert(issues,'severed '..a.name..'>'..b.name)
   elseif a.level~=b.level then table.insert(crossDetours,route-flat)
   elseif flat>8 and table.insert(ratios,route/flat)==nil and route/flat>maxRatio then table.insert(issues,('pathological %s>%s %.0f/%.0f'):format(a.name,b.name,route,flat))end
  end
 end
 return issues
end
function S.Run(count,options)
 options=options or {}
 count=count or 1000
 local base=options.seed or 1
 local report={count=count,passed=0,failures={},reasons={},byKind={}}
 local times,rooms,f1,f2,depth,deadEnds,loops,vertical,longest,cross,ratios={},{},{},{},{},{},{},{},{},{},{}
 for i=0,count-1 do
  local seed=base+i
  local kind,size=Profiles.Select(seed,options.forceKind or options.kind,options.forceSize or options.size)
  local began=os.clock()
  local ok,plan=pcall(P.Generate,seed,options.players or 1,kind,size)
  local valid,reasons
  if ok then valid,reasons=V.Plan(plan) else valid,reasons=false,{'planner error: '..tostring(plan)} end
  local issues={}
  if valid then
   local graph=G.FromPlan(plan);local m=graph.metrics
   if m.unreachable>0 or m.components>1 then table.insert(issues,'disconnected graph') end
   local required=Profiles.Scale[size].stairs
   if m.verticalConnections<required then table.insert(issues,'missing guaranteed stair connection') end
   if plan.mapKind~=kind or plan.sizeClass~=size then table.insert(issues,'map identity mismatch') end
   if (kind=='Hospital' or kind=='Hotel') and (plan.horizontalScale~=1 or plan.openAreaMultiplier~=1) then table.insert(issues,kind..' scale contract') end
   if kind=='Cruise' and (plan.horizontalScale~=1 or plan.openAreaMultiplier~=1 or size=='Compact') then table.insert(issues,'Cruise size/scale contract') end
   if m.floors[2]==nil or m.floors[2]==0 then table.insert(issues,'empty upper floor') end
   for _,s in ipairs(probe(graph,Random.new(seed),options.probes or 12,cross,options.maxDetourRatio or 8,ratios))do table.insert(issues,s)end
   table.insert(rooms,m.rooms);table.insert(f1,m.floors[1]);table.insert(f2,m.floors[2]or 0)
   table.insert(depth,m.maxDepth);table.insert(deadEnds,m.deadEnds);table.insert(loops,m.loops)
   table.insert(vertical,m.verticalConnections);table.insert(longest,m.longestRouteFromStart)
  end
  table.insert(times,(os.clock()-began)*1000)
  for _,s in ipairs(issues)do table.insert(reasons,s)end
  local key=kind..'_'..size;report.byKind[key]=report.byKind[key]or{runs=0,passed=0}
  report.byKind[key].runs+=1
  if valid and #issues==0 then report.passed+=1;report.byKind[key].passed+=1
  else
   for _,r in ipairs(reasons or {})do bump(report.reasons,(r:gsub(' L%d_[%w_]+.*','')))end
   if #report.failures<50 then table.insert(report.failures,{seed=seed,kind=kind,size=size,reasons=reasons})end
  end
  if i%25==24 then task.wait()end
 end
 report.successRate=report.passed/count
 report.stats={planMs=spread(times),rooms=spread(rooms),floor1=spread(f1),floor2=spread(f2),maxDepth=spread(depth),
  deadEnds=spread(deadEnds),loops=spread(loops),verticalConnections=spread(vertical),longestRouteStuds=spread(longest),crossFloorDetourStuds=spread(cross),sameFloorDetourRatio=spread(ratios)}
 return report
end
return S


