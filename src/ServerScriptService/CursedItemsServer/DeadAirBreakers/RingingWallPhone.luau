-- Dead-air breaker (RingingWallPhone, WorldB 2026-10-27): after 55 s without loot progress an antique wall phone appears on a wall near the
-- player and rings. Anyone may answer it with GRAB: it is Kind 'choice' (InteractController shows ChoiceVerb and sends
-- CloseUpChoiceEvent 'claim'); CloseUpChoices ignores it because it has no ChoiceId. Answering whispers the room of the
-- nearest free item; 4 s later that item rattles once (a sound to find it by). No outline, no path: a hint, not a pointer.
-- Not the antique Telephone cursed item (that one is loot and gives key clues).
local Players=game:GetService('Players')
local RS=game:GetService('ReplicatedStorage')
local SS=game:GetService('ServerStorage')
local TweenService=game:GetService('TweenService')
local Catalog=require(RS:WaitForChild('CursedCatalog'))
local RING_SECONDS=20
local RING_EVERY=4
local REACH=11 -- same as CloseUpChoices CHOICE_REACH
local WALL_MIN,WALL_MAX=6,22
local MOUNT_HEIGHT=2.4 -- floor to the phone's bottom
local RIGHT_BEHIND=15 -- studs: the item is close, the line says so
local LINES={
 function(n,w)return 'Psst... the '..n..' is lonely. Look '..w..'.'end,
 function(n,w)return 'Hello? ...The '..n..'. It is '..w..'. Hurry.'end,
 function(n,w)return 'Nobody ever calls me... Something cursed is waiting '..w..'.'end,
 function(n,w)return 'Are you lost? I am not. Check '..w..'.'end,
 function(_,w)return 'Shhh. '..w:sub(1,1):upper()..w:sub(2)..'. Bring the cart.'end,
}
return function(core)
 local B={name='RingingWallPhone',after=55,budget={[1]=2,[2]=1}}
 local phones={} -- model -> true
 local function exclude()
  local map=core.Map();local list={}
  for _,x in{map:FindFirstChild('Interactive'),map:FindFirstChild('Furniture'),map:FindFirstChild('DeadAirFx'),workspace:FindFirstChild('RoamingCreatures'),workspace:FindFirstChild('RecoveryCamp')}do if x then table.insert(list,x)end end
  for _,q in Players:GetPlayers()do if q.Character then table.insert(list,q.Character)end end
  return list
 end
 -- A tall vertical wall 6-22 studs away at chest height, preferring the item's direction, then nearer.
 local function wallSpot(root,target)
  local params=RaycastParams.new();params.FilterType=Enum.RaycastFilterType.Exclude;params.FilterDescendantsInstances=exclude()
  local toward=(target.PrimaryPart.Position-root.Position)*Vector3.new(1,0,1);toward=toward.Magnitude>.1 and toward.Unit or root.CFrame.LookVector
  local best,score
  for k=0,7 do
   local a=k*math.pi/4;local dir=Vector3.new(math.cos(a),0,math.sin(a))
   local hit=workspace:Raycast(root.Position,dir*WALL_MAX,params)
   local part=hit and hit.Instance
   if hit and hit.Distance>=WALL_MIN and math.abs(hit.Normal.Y)<.2 and part~=workspace.Terrain and part:IsA('BasePart')and part.Size.Y>=6 then
    local s=dir:Dot(toward)-hit.Distance/WALL_MAX*.3
    if not score or s>score then best,score=hit,s end
   end
  end
  if not best then return nil end
  local down=workspace:Raycast(best.Position+best.Normal*1.5,Vector3.new(0,-12,0),params)
  return best.Position,best.Normal,down and down.Position.Y or root.Position.Y-3
 end
 local function build(pos,normal,floorY)
  local props=SS:FindFirstChild('DeadAirProps');local template=props and props:FindFirstChild('RingingWallPhone')
  local m=template and template:Clone()
  if not m then -- before the mesh is shipped: an oak-coloured box
   m=Instance.new('Model');local b=Instance.new('Part');b.Size=Vector3.new(1.3,2.5,.6);b.Color=Color3.fromRGB(182,130,66);b.Parent=m;m.PrimaryPart=b
  end
  for _,x in m:GetDescendants()do if x:IsA('BasePart')then x.Anchored=true;x.CanCollide=false;x.CanTouch=false;x.CanQuery=true end end -- CanQuery: the grab aim must hit it
  local depth=m:GetExtentsSize().Z
  local base=Vector3.new(pos.X,floorY+MOUNT_HEIGHT,pos.Z)+normal*(depth/2+.03) -- pivot is bottom centre: back flush on the wall
  m:PivotTo(CFrame.lookAt(base,base+normal)) -- front (-Z) faces into the room
  m.Name='RingingWallPhone'
  m:SetAttribute('Kind','choice');m:SetAttribute('ChoiceVerb','ANSWER THE PHONE');m:SetAttribute('DeadAirKind','Phone')
  m.Parent=core.Map():FindFirstChild('Interactive')
  return m
 end
 local function fadeOut(m)
  if not m.Parent then phones[m]=nil;return end
  m:SetAttribute('Kind',nil);m:SetAttribute('ChoiceVerb',nil) -- no longer grabbable
  for _,x in m:GetDescendants()do if x:IsA('BasePart')then TweenService:Create(x,TweenInfo.new(1),{Transparency=1}):Play()end end
  task.wait(1.05);phones[m]=nil;if m.Parent then m:Destroy()end
 end
 local function itemName(m)
  local entry=Catalog.Items[m:GetAttribute('ItemId')or '']
  return string.lower(tostring(m:GetAttribute('DisplayName')or entry and entry.name or 'cursed thing'))
 end
 -- The claim arrives on the close-up choice remote (InteractController sends it for any Kind 'choice' target).
 task.spawn(function()
  local ev=RS:WaitForChild('CloseUpChoiceEvent',30);if not ev then warn('[DeadAir] CloseUpChoiceEvent missing: the phone cannot be answered');return end
  ev.OnServerEvent:Connect(function(p,action,prop)
   if action~='claim'or typeof(prop)~='Instance'or not phones[prop]or prop:GetAttribute('Answered')then return end
   local r=core.Living(p);if not r or not (prop::any).PrimaryPart or((prop::any).PrimaryPart.Position-r.Position).Magnitude>REACH then return end
   prop:SetAttribute('Answered',p.UserId)
  end)
 end)
 function B.run(p,target,_level,root)
  local g=core.Generation()
  local pos,normal,floorY=wallSpot(root,target)
  if not pos then core.Refund(p,B.name);return end -- nowhere to hang it: try again later
  local m=build(pos,normal,floorY);phones[m]=true
  local Audio=core.Audio();local born=os.clock();local nextRing=0;local answerer
  core.Fx(p,'gasp',1.4);core.Pop(p,'RIIING!',.35) -- RING! the bored searcher jumps
  while core.Same(g)and m.Parent and os.clock()-born<RING_SECONDS do
   answerer=Players:GetPlayerByUserId(m:GetAttribute('Answered')or 0)
   if answerer then break end
   if os.clock()>=nextRing then nextRing=os.clock()+RING_EVERY;Audio.Play('TelephoneRing',m)end
   task.wait(.2)
  end
  if not core.Same(g)then return end
  if answerer and m.Parent then
   local r=core.Living(answerer)or root
   local item=core.Free(target)and target or core.Nearest(r) -- the first item may have been taken meanwhile
   local text
   if not item then text='...Click. Nothing left to find. Go to the van.'
   elseif(item.PrimaryPart.Position-r.Position).Magnitude<RIGHT_BEHIND then text='Turn around. It is right behind you.'
   else text=LINES[math.random(1,#LINES)](itemName(item),core.Where(item))end
   Audio.Play('ScareWhisper',m);core.Fx(answerer,'gasp',1.2);core.Pop(answerer,'...psst...',.25)
   task.delay(1.3,function()if item then core.Fx(answerer,'grin',2.5);core.Pop(answerer,'A clue!')end end)
   core.Speech(m.PrimaryPart.Position+Vector3.new(0,2,0),text);core.Say(answerer,'Phone: '..text)
   -- A hint, not a pointer (lead 2026-10-27): only the whispered room name, then one rattle from the item itself a moment
   -- later (a sound to home in on), no outline or path.
   if item then task.delay(4,function()if core.Free(item)then core.Rattle(item)end end)end
   task.wait(1.5)
  end
  fadeOut(m)
 end
 function B.clear()for m in phones do if m.Parent then m:Destroy()end end;table.clear(phones)end
 return B
end
