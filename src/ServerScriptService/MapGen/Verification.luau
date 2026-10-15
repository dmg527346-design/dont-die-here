-- Explicit Studio-only physical traversal. Never runs automatically.
local Q={}
local function route(graph,destination)
 local by,adj={},{};for _,r in ipairs(graph.rooms) do by[r.name]=r;adj[r.name]={} end
 for _,e in ipairs(graph.edges) do table.insert(adj[e.a],{to=e.b,edge=e});table.insert(adj[e.b],{to=e.a,edge=e}) end
 local queue={graph.start};local back={[graph.start]=false};local head=1
 while head<=#queue do local n=queue[head];head+=1;for _,link in ipairs(adj[n]) do if back[link.to]==nil then back[link.to]={from=n,edge=link.edge};table.insert(queue,link.to) end end end
 local steps={};local n=destination
 while n~=graph.start do local b=assert(back[n],'unreachable graph room');table.insert(steps,1,{from=by[b.from],to=by[n],edge=b.edge});n=b.from end
 local result={}
 local function add(p) table.insert(result,{Position=p,Action=Enum.PathWaypointAction.Walk}) end
 local function centre(r) return Vector3.new(r.navx or (r.x1+r.x2)/2,r.level*16,r.navz or (r.z1+r.z2)/2) end
 local function circulation(r,e,outward)
  local c=centre(r);local x=math.clamp(e.x,r.x1+3.2,r.x2-3.2);local z=math.clamp(e.z,r.z1+3.2,r.z2-3.2)
  local points=if r.type=='Dining' then {c,Vector3.new(r.x2-2.8,c.Y,c.Z),Vector3.new(r.x2-2.8,c.Y,z),Vector3.new(x,c.Y,z)} else {c,Vector3.new(c.X,c.Y,z),Vector3.new(x,c.Y,z)}
  if outward then for _,p in ipairs(points) do add(p) end else for i=#points,1,-1 do add(points[i]) end end
 end
 for _,step in ipairs(steps) do local e=step.edge
  if e.kind=='stairs' then
   if step.from.level==0 then for _,p in ipairs(e.waypoints) do add(Vector3.new(unpack(p))) end else for i=#e.waypoints,1,-1 do add(Vector3.new(unpack(e.waypoints[i]))) end end
   add(centre(step.to))
  else
   circulation(step.from,e,true);add(Vector3.new(e.x,e.y,e.z));circulation(step.to,e,false)
  end
 end
 add(centre(by[destination]));return result
end
function Q.Traverse(mansion,only)
 assert(game:GetService('RunService'):IsStudio(),'Studio only')
 local Players=game:GetService('Players')
 local player=assert(Players:GetPlayers()[1],'test player missing')
 local graph=game:GetService('HttpService'):JSONDecode(mansion.GeneratedGraph.Value)
 local targets={}
 for _,r in ipairs(graph.rooms) do if not only or only[r.name] then table.insert(targets,{name=r.name,position=Vector3.new(r.navx or (r.x1+r.x2)/2,r.level*16+3,r.navz or (r.z1+r.z2)/2)}) end end
 local Physics=game:GetService('PhysicsService');local group='MapGenProbe'
 local registered=Physics:IsCollisionGroupRegistered(group)
 if not registered then Physics:RegisterCollisionGroup(group) end
 Physics:CollisionGroupSetCollidable(group,group,false)
 local description=Instance.new('HumanoidDescription')
 local originalHum=player.Character and player.Character:FindFirstChildOfClass('Humanoid')
 for _,pair in ipairs({{'HeightScale','BodyHeightScale'},{'WidthScale','BodyWidthScale'},{'DepthScale','BodyDepthScale'},{'HeadScale','HeadScale'}}) do
  local value=originalHum and originalHum:FindFirstChild(pair[2]);if value then description[pair[1]]=value.Value end
 end
 local template=Players:CreateHumanoidModelFromDescriptionAsync(description,Enum.HumanoidRigType.R15);description:Destroy()
 for _,p in ipairs(template:GetDescendants()) do
  if p:IsA('LuaSourceContainer') then p:Destroy()
  elseif p:IsA('BasePart') then p.Transparency=1;p.Anchored=false;p.CanTouch=false;p.CollisionGroup=group end
 end
 local originalRoot=player.Character and player.Character:FindFirstChild('HumanoidRootPart')
 local originalCF=originalRoot and originalRoot.CFrame;local originalAnchor=originalRoot and originalRoot.Anchored
 if originalRoot then originalRoot.Anchored=true;originalRoot.CFrame=workspace.SpawnLocation.CFrame*CFrame.new(0,30,25) end
 local doors={}
 for _,p in ipairs(mansion.Interactive:GetDescendants()) do if p:IsA('BasePart') and p:GetAttribute('DoorSlab') then doors[p]=p.CanCollide;p.CanCollide=false end end
 local status=Instance.new('StringValue');status.Name='TraversalProgress';status.Parent=mansion
 local reports={};local workers=12;local done=0
 local start=workspace.SpawnLocation.Position+Vector3.new(0,3,0)
 for worker=1,workers do task.spawn(function()
  local bot=template:Clone();bot.Name='MapGenTraversalProbe_'..worker;bot.Parent=workspace
  local h=bot:FindFirstChildOfClass('Humanoid');local root=bot.HumanoidRootPart
  h.WalkSpeed=16;h.MaxSlopeAngle=55;h.JumpPower=50;h.DisplayDistanceType=Enum.HumanoidDisplayDistanceType.None
  pcall(function() root:SetNetworkOwner(nil) end)
  local path=game:GetService('PathfindingService'):CreatePath({AgentRadius=2,AgentHeight=5,AgentCanJump=true,WaypointSpacing=4})
  local ok,err=pcall(function()
   for index=worker,#targets,workers do
    local target=targets[index];h.Jump=false;h:MoveTo(start);bot:PivotTo(CFrame.new(start));root.AssemblyLinearVelocity=Vector3.zero;root.AssemblyAngularVelocity=Vector3.zero;h:ChangeState(Enum.HumanoidStateType.Running);task.wait(.2)
    path:ComputeAsync(start,target.position)
    local passed=path.Status==Enum.PathStatus.Success;local failure
    local same=(Vector3.new(start.X,0,start.Z)-Vector3.new(target.position.X,0,target.position.Z)).Magnitude<1 and math.abs(start.Y-target.position.Y)<2
    if same then passed=true
    elseif passed then
     -- Global navigation verifies reachability. Reserved circulation paths
     -- provide exact door and stair steering instead of voxel corner shortcuts.
     local refined=if graph.seed then route(graph,target.name) else path:GetWaypoints()
     for _,point in ipairs(refined) do
      h.WalkSpeed=16
      if point.Action==Enum.PathWaypointAction.Jump then h.Jump=true;h:ChangeState(Enum.HumanoidStateType.Jumping) end
      local complete,reached=false,false
      local connection=h.MoveToFinished:Connect(function(value)
       local flat=(Vector3.new(root.Position.X,0,root.Position.Z)-Vector3.new(point.Position.X,0,point.Position.Z)).Magnitude
       if not value or (flat<3 and math.abs(root.Position.Y-point.Position.Y)<4.5) then complete=true;reached=value end
      end)
      local timeout=math.max(4,(root.Position-point.Position).Magnitude/16+2)
      h:MoveTo(point.Position);local began=os.clock()
      repeat
       task.wait(.03)
       local flat=(Vector3.new(root.Position.X,0,root.Position.Z)-Vector3.new(point.Position.X,0,point.Position.Z)).Magnitude
       if flat<1.75 and math.abs(root.Position.Y-point.Position.Y-3.2)<2 then complete=true;reached=true end
      until complete or os.clock()-began>timeout
      connection:Disconnect()
      if not reached then passed=false;failure={waypoint={point.Position.X,point.Position.Y,point.Position.Z},action=point.Action.Name};break end
     end
     if (root.Position-target.position).Magnitude>5 then passed=false end
    end
    table.insert(reports,{name=target.name,passed=passed,final={root.Position.X,root.Position.Y,root.Position.Z},failure=failure})
    status.Value=#reports..'/'..#targets..' '..target.name..' '..tostring(passed)
   end
  end)
  if not ok then table.insert(reports,{name='worker '..worker,passed=false,error=tostring(err)}) end
  path:Destroy();bot:Destroy();done+=1
 end) end
 repeat task.wait(.1) until done==workers
 template:Destroy();status:Destroy()
 for p,value in pairs(doors) do if p.Parent then p.CanCollide=value end end
 if originalRoot and originalRoot.Parent then originalRoot.CFrame=originalCF;originalRoot.Anchored=originalAnchor end
 if not registered then Physics:UnregisterCollisionGroup(group) end
 table.sort(reports,function(a,b) return a.name<b.name end)
 return reports
end
function Q.DrawPlan(plan,parent)
 assert(game:GetService('RunService'):IsStudio(),'Studio only')
 local model=Instance.new('Model');model.Name='MapPlanDebug';model:SetAttribute('Seed',plan.seed);model.Parent=parent or workspace
 local rules=require(script.Parent.Rules)
 local colors={public=Color3.fromRGB(115,167,128),private=Color3.fromRGB(117,142,195),service=Color3.fromRGB(180,142,96),hall=Color3.fromRGB(195,185,148)}
 local floorSpacing=plan.width*2+80
 local topology=require(script.Parent.Topology).Analyze(require(script.Parent.GraphExport).FromPlan(plan))
 model:SetAttribute('Loops',topology.metrics.loops);model:SetAttribute('DeadEnds',topology.metrics.deadEnds);model:SetAttribute('MaxDepth',topology.metrics.maxDepth)
 for _,r in ipairs(plan.rooms) do
  local p=Instance.new('Part');p.Name=r.name;p.Anchored=true;p.CanCollide=false;p.CanQuery=false
  p.Size=Vector3.new(r.x2-r.x1-.3,.3,r.z2-r.z1-.3)
  p.Position=Vector3.new(450+r.level*floorSpacing+(r.x1+r.x2)/2,1,(r.z1+r.z2)/2)
  p.Color=colors[rules.Types[r.type].zone];p.Material=Enum.Material.SmoothPlastic;p.Parent=model
  local gui=Instance.new('SurfaceGui');gui.Face=Enum.NormalId.Top;gui.CanvasSize=Vector2.new(300,150);gui.Parent=p
  local label=Instance.new('TextLabel');label.Size=UDim2.fromScale(1,1);label.BackgroundTransparency=1;label.Text=(r.purpose or r.type)..'\nF'..r.level..'  depth '..topology.rooms[r.name].depth;p:SetAttribute('GraphDepth',topology.rooms[r.name].depth);label.TextColor3=Color3.fromRGB(20,20,20);label.TextScaled=true;label.Font=Enum.Font.Garamond;label.Parent=gui
 end
 for _,e in ipairs(plan.edges) do if e.kind~='stairs' then
  local p=Instance.new('Part');p.Name=e.a..'_'..e.b;p.Anchored=true;p.CanCollide=false;p.CanQuery=false
  p.Size=if e.axis=='x' then Vector3.new(6,.6,1.3) else Vector3.new(1.3,.6,6)
  p.Position=Vector3.new(450+math.floor(e.y/16)*floorSpacing+e.x,1.5,e.z)
  p.Color=if e.boarded then Color3.fromRGB(55,45,40) elseif e.locked then Color3.fromRGB(220,143,53) else Color3.fromRGB(235,235,220);p.Parent=model
 else
  -- Vertical links: a tall magenta marker on each floor's stair endpoint.
  for _,name in ipairs({e.a,e.b}) do for _,r in ipairs(plan.rooms) do if r.name==name then
   local p=Instance.new('Part');p.Name='Vertical_'..e.a..'_'..e.b;p.Anchored=true;p.CanCollide=false;p.CanQuery=false
   p.Size=Vector3.new(3,8,3);p.Material=Enum.Material.Neon;p.Color=Color3.fromRGB(214,60,200)
   p.Position=Vector3.new(450+r.level*floorSpacing+(r.x1+r.x2)/2,5,(r.z1+r.z2)/2);p.Parent=model
  end end end
 end end
 return model
end
return Q
