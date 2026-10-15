local Topology=require(script.Parent.Topology)
local G={}
function G.FromPlan(plan)
 local graph={rooms={},edges={},seed=plan.seed,start=plan.start,mapKind=plan.mapKind,sizeClass=plan.sizeClass,
  generatorVersion=plan.generatorVersion,stairs=plan.stairs,entrance=plan.entrance}
 for _,r in ipairs(plan.rooms) do table.insert(graph.rooms,{name=r.name,type=r.type,purpose=r.purpose,level=r.level,x1=r.x1,x2=r.x2,z1=r.z1,z2=r.z2,navx=r.navx,navz=r.navz,
  stair=r.stair,generationOrder=r.order,danger=r.danger,visibility=r.visibility,hiding=r.hiding,loot=r.loot,spawnRating=r.spawnRating,search=r.search,chase=r.chase}) end
 for _,e in ipairs(plan.edges) do if not e.boarded then table.insert(graph.edges,e) end end
 -- Room depth, neighbours, vertical links and shape metrics for the AI and tooling.
 Topology.Annotate(graph)
 return graph
end
function G.Publish(plan,mansion)
 local value=Instance.new('StringValue');value.Name='GeneratedGraph';value.Value=game:GetService('HttpService'):JSONEncode(G.FromPlan(plan));value.Parent=mansion
end
return G
