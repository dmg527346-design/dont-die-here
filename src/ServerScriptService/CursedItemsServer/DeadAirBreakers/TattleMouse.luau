-- Dead-air breaker (TattleMouse, WorldB 2026-10-27): after 40 s without loot progress a wind-up tin mouse pops out ahead of the player and
-- scurries a short way along the floor path toward the nearest free item, then stops and squeaks onward (a hint only:
-- no marker, no outline, it never reaches the item).
-- One small unanchored assembly owned by the server (AlignPosition / AlignOrientation), so clients get smooth physics
-- interpolation for free. Not grabbable (lives in Mansion.DeadAirFx, CanQuery off), never collides, never calls monsters.
local SS=game:GetService('ServerStorage')
local TweenService=game:GetService('TweenService')
local SPEED=10 -- studs per second (walk is 16)
local POP_AHEAD=6 -- studs along the path in front of the player where it appears
local SIT_SECONDS=5 -- squeaks onward this long at the end of its run
local LIFE=25
local RUN_SHARE,RUN_MAX=.45,18 -- it runs at most this share of the path / this many studs: a hint, not a guide
local SQUEAK_EVERY=1.3
local MONSTER_FREEZE=30
return function(core)
 local B={name='TattleMouse',after=40,budget={[1]=2,[2]=1}}
 local mice={}
 local function build(at)
  local props=SS:FindFirstChild('DeadAirProps');local template=props and props:FindFirstChild('TattleMouse')
  local m=template and template:Clone()
  if not m then -- before the mesh is shipped: a grey egg, so Studio tests still run
   m=Instance.new('Model');local b=Instance.new('Part');b.Shape=Enum.PartType.Ball;b.Size=Vector3.new(.7,.6,1.3);b.Color=Color3.fromRGB(201,206,214);b.Parent=m;m.PrimaryPart=b
  end
  m.Name='TattleMouse'
  local root=m.PrimaryPart
  for _,x in m:GetDescendants()do if x:IsA('BasePart')then x.Anchored=false;x.CanCollide=false;x.CanQuery=false;x.CanTouch=false;x.Massless=x~=root end end
  m:PivotTo(CFrame.new(at)) -- pivot is bottom centre (rbxkit prop): it stands on the floor waypoint
  local att=Instance.new('Attachment');att.Name='MouseAlign';att.Parent=root
  local ap=Instance.new('AlignPosition');ap.Mode=Enum.PositionAlignmentMode.OneAttachment;ap.Attachment0=att;ap.MaxForce=1e5;ap.MaxVelocity=SPEED;ap.Responsiveness=60;ap.Position=root.Position;ap.Parent=root
  local ao=Instance.new('AlignOrientation');ao.Mode=Enum.OrientationAlignmentMode.OneAttachment;ao.Attachment0=att;ao.MaxTorque=1e5;ao.Responsiveness=40;ao.CFrame=root.CFrame.Rotation;ao.Parent=root
  m.Parent=core.Folder()
  pcall(function()root:SetNetworkOwner(nil)end)
  return m,ap,ao
 end
 local function faceFlat(ao,from,to)
  local flat=Vector3.new(to.X,from.Y,to.Z);if(flat-from).Magnitude>.2 then ao.CFrame=CFrame.lookAt(from,flat).Rotation end
 end
 local function windDown(m,ap,ao)
  if not m.Parent then mice[m]=nil;return end
  ap.Position=m.PrimaryPart.Position;ao.CFrame*=CFrame.Angles(0,0,math.rad(80)) -- tips onto its side
  task.wait(.6)
  for _,x in m:GetDescendants()do if x:IsA('BasePart')then TweenService:Create(x,TweenInfo.new(1),{Transparency=1}):Play()end end
  task.wait(1.05);mice[m]=nil;if m.Parent then m:Destroy()end
 end
 function B.run(p,target,_level,root)
  local g=core.Generation()
  local points,found=core.Path(root.Position,core.Beside(target,root.Position)) -- yields
  -- No walkable path: a mouse gliding through a wall would look broken, so it stays home and gives the use back.
  if not found then core.Refund(p,'TattleMouse');return end
  if not core.Same(g)or not core.Free(target)or not core.Living(p)then return end
  -- A hint, not a pointer (lead 2026-10-27: players find things themselves): the mouse only scampers the first stretch
  -- of the way (at most RUN_SHARE of the path, RUN_MAX studs), then stops at that corner, squeaks onward and winds down.
  local total=0;for k=2,#points do total+=(points[k]-points[k-1]).Magnitude end
  local runTo=math.min(total*RUN_SHARE,RUN_MAX)
  local first,walked,last=#points,0,#points
  for k=2,#points do walked+=(points[k]-points[k-1]).Magnitude;if walked>=POP_AHEAD and first==#points then first=k end;if walked>=runTo then last=k;break end end
  if first>=last then core.Refund(p,'TattleMouse');return end -- the item is right here: nothing to hint
  local m,ap,ao=build(points[first])
  mice[m]=true
  local lift=m.PrimaryPart.Position.Y-m:GetPivot().Position.Y -- the align point is the root's centre, waypoints are on the floor
  local Audio=core.Audio()
  Audio.Play('MouseWind',m) -- winding clicks as it pops out
  core.Fx(p,'grin',2.2);core.Pop(p,'Squeak! This way...')
  local i=math.min(first+1,last);local born=os.clock();local nextSqueak=os.clock()+.6;local sitting,happy=nil,false
  local onward=points[math.min(last+1,#points)] -- the direction it keeps squeaking toward once it stops
  while core.Same(g)and m.Parent and os.clock()-born<LIFE do
   task.wait(.2)
   local pos=m.PrimaryPart.Position
   if not core.Free(target)then happy=target.Parent~=nil and target:GetAttribute('HeldBy')~=nil;break end -- found (or gone): job done
   local frozen=core.MonsterNear(pos,MONSTER_FREEZE)
   if frozen then ap.Position=pos -- freezes silently until the monster leaves
   elseif sitting then
    faceFlat(ao,pos,onward);ao.CFrame*=CFrame.Angles(math.rad(-12),math.sin(os.clock()*9)*.35,0) -- rears up and squeaks onward
    if os.clock()-sitting>SIT_SECONDS then break end
   else
    local goal=points[i]+Vector3.new(0,lift,0)
    while(goal-pos).Magnitude<1.2 and i<last do i+=1;goal=points[i]+Vector3.new(0,lift,0)end
    if(goal-pos).Magnitude<1.2 then sitting=os.clock() -- end of its run: the rest is up to you
    else ap.Position=goal;faceFlat(ao,pos,goal)end
   end
   if not frozen and os.clock()>=nextSqueak then nextSqueak=os.clock()+SQUEAK_EVERY*(sitting and .8 or 1);Audio.Play('MouseSqueak',m)end
  end
  if happy then local q=game:GetService('Players'):GetPlayerByUserId(target:GetAttribute('HeldBy')or 0);if q then core.Fx(q,'grin',2)end end
  if happy and m.Parent then for _=1,6 do ao.CFrame*=CFrame.Angles(0,math.pi/3,0);task.wait(.08)end;Audio.Play('MouseSqueak',m)end -- happy spin
  windDown(m,ap,ao)
 end
 function B.clear()for m in mice do if m.Parent then m:Destroy()end end;table.clear(mice)end
 return B
end
