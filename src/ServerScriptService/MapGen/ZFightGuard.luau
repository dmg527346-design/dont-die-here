-- Post-build z-fighting guard for generated maps.
-- Dressing modules often lay trim, stains, cards, tape or rugs flush on another part. Two visible faces of
-- different-looking parts in the same plane flicker (z-fighting). After a map is built and dressed, Find lists
-- those pairs, skipping faces nobody can see (the space just in front of them is solid: inside a wall, under a
-- floor, above a ceiling). Apply moves ONLY the overlapping face: the smaller part's front face grows out to GAP in
-- front of the larger one (its back face stays where it was), or, when the small part may not change (a door, a
-- drawer, loot), the larger part's face is inset by GAP. Each face of a part (axis + side) is handled on its own,
-- so a part flush with neighbours on several sides gets every face fixed. Nothing is ever deleted.
-- Box-shaped MeshParts take part too (wall Base/Wallpaper/Trim pieces share end planes where a wall stops at a
-- door, window or pillar): a mesh face only counts when a raycast finds the real surface on that plane, so brick
-- panels and other shaped meshes whose bounding boxes merely line up are left alone.
-- Only anchored Parts and MeshParts change; doors, drawers, keys and loot (Interactive) never do. Terrain and characters
-- are not inside a generated map, so they are never scanned.
-- Art and dressing parts are CanQuery=false, so the solid test uses its own grid of part boxes, not spatial queries.
local M={}
local PLANE_EPS=0.02 -- coplanar if closer than this (flickers at play distances)
local GAP=0.02 -- studs between the two faces after the fix: invisible, and above the 0.005 shimmer limit at range
local PROBE=0.03 -- how far in front of a face the solid test looks
local BUCKET=0.05
local MIN_AREA=0.04
local CELL=8
local YIELD_EVERY=1500
M.PLANE_EPS=PLANE_EPS

local AXES={{'X',Vector3.xAxis},{'Y',Vector3.yAxis},{'Z',Vector3.zAxis}}
local function block(p)return p:IsA('Part')and p.Shape==Enum.PartType.Block end
-- rbxkit splits one model into per-colour pieces named Model__part__n: they share bounding boxes by design
-- (brick panels, party centrepieces) without sharing surfaces, so only whole meshes take part.
local function mesh(p)return p:IsA('MeshPart')and not p.Name:find('__',1,true)end
local function boxy(p)return block(p)or mesh(p)end
local function opaque(p)return p.Transparency<0.95 end
local function movable(p,interactive)
 return boxy(p)and p.Anchored and opaque(p)and not(interactive and p:IsDescendantOf(interactive))and p:GetAttribute('ClosedPivot')==nil
end
local function faces(p,out)
 local cf,half=p.CFrame,p.Size/2
 for i,a in AXES do
  local j,k=(i%3)+1,((i+1)%3)+1
  local hu,hv=half[AXES[j][1]],half[AXES[k][1]]
  if hu*hv*4>=MIN_AREA then
   local u,v=cf:VectorToWorldSpace(AXES[j][2]),cf:VectorToWorldSpace(AXES[k][2])
   for _,sign in{1,-1}do
    local n=cf:VectorToWorldSpace(a[2]*sign);local c=cf.Position+n*half[a[1]]
    table.insert(out,{part=p,n=n,c=c,u=u,v=v,hu=hu,hv=hv,d=n:Dot(c),area=hu*hv*4,mesh=mesh(p)})
   end
  end
 end
end
local function nkey(n)return('%d,%d,%d'):format(math.round(n.X*200),math.round(n.Y*200),math.round(n.Z*200))end
-- Overlap of two coplanar oriented rectangles; returns area and the overlap centre (in a's frame).
local function overlap(a,b)
 local du=(b.c-a.c):Dot(a.u);local dv=(b.c-a.c):Dot(a.v)
 local ehu=math.abs(b.hu*b.u:Dot(a.u))+math.abs(b.hv*b.v:Dot(a.u))
 local ehv=math.abs(b.hu*b.u:Dot(a.v))+math.abs(b.hv*b.v:Dot(a.v))
 local lo_u,hi_u=math.max(-a.hu,du-ehu),math.min(a.hu,du+ehu)
 local lo_v,hi_v=math.max(-a.hv,dv-ehv),math.min(a.hv,dv+ehv)
 local ou,ov=hi_u-lo_u,hi_v-lo_v
 if ou<=0.05 or ov<=0.05 then return 0 end
 if math.abs(b.u:Dot(a.u))<0.999 and math.abs(b.u:Dot(a.v))<0.999 then
  local adu=(a.c-b.c):Dot(b.u);local adv=(a.c-b.c):Dot(b.v)
  local ahu=math.abs(a.hu*a.u:Dot(b.u))+math.abs(a.hv*a.v:Dot(b.u))
  local ahv=math.abs(a.hu*a.u:Dot(b.v))+math.abs(a.hv*a.v:Dot(b.v))
  if math.abs(adu)>=b.hu+ahu-0.05 or math.abs(adv)>=b.hv+ahv-0.05 then return 0 end
 end
 return ou*ov,a.c+a.u*((lo_u+hi_u)/2)+a.v*((lo_v+hi_v)/2),ou,ov
end
-- Same colour and material only looks the same when nothing is drawn on top: Texture/Decal/SurfaceAppearance
-- children or a mesh TextureID (Mall/Hotel walls and floors are white parts with textures) still Z-fight.
local function skinned(p)
 if p:IsA('MeshPart')and p.TextureID~=''then return true end
 for _,c in p:GetChildren()do if c:IsA('Decal')or c:IsA('SurfaceAppearance')then return true end end
 return false
end
local function sameLook(a,b)return a.Color==b.Color and a.Material==b.Material and a.Transparency==b.Transparency and a.MaterialVariant==b.MaterialVariant and not skinned(a)and not skinned(b)end

-- Grid of opaque part boxes (any shape) for the "is this point inside something solid" test.
local function buildGrid(parts)
 local grid={}
 for _,p in parts do
  local cf,s=p.CFrame,p.Size
  local ext=Vector3.new(math.abs(cf.RightVector.X)*s.X+math.abs(cf.UpVector.X)*s.Y+math.abs(cf.LookVector.X)*s.Z,
   math.abs(cf.RightVector.Y)*s.X+math.abs(cf.UpVector.Y)*s.Y+math.abs(cf.LookVector.Y)*s.Z,
   math.abs(cf.RightVector.Z)*s.X+math.abs(cf.UpVector.Z)*s.Y+math.abs(cf.LookVector.Z)*s.Z)/2
  local lo,hi=(cf.Position-ext)/CELL,(cf.Position+ext)/CELL
  if (hi-lo).Magnitude<40 then -- skip enormous parts (skyboxes, grounds) from per-cell lists; test them separately
   for x=math.floor(lo.X),math.floor(hi.X)do for y=math.floor(lo.Y),math.floor(hi.Y)do for z=math.floor(lo.Z),math.floor(hi.Z)do
    local key=x..','..y..','..z;local cell=grid[key];if not cell then cell={};grid[key]=cell end;table.insert(cell,p)
   end end end
  else grid.big=grid.big or{};table.insert(grid.big,p)end
 end
 return grid
end
local function inside(p,point)
 local q=p.CFrame:PointToObjectSpace(point);local h=p.Size/2
 return math.abs(q.X)<h.X and math.abs(q.Y)<h.Y and math.abs(q.Z)<h.Z
end
local function solidAt(grid,point,skipA,skipB)
 local c=grid[math.floor(point.X/CELL)..','..math.floor(point.Y/CELL)..','..math.floor(point.Z/CELL)]
 if c then for _,p in c do if p~=skipA and p~=skipB and inside(p,point)then return true end end end
 if grid.big then for _,p in grid.big do if p~=skipA and p~=skipB and inside(p,point)then return true end end end
 return false
end

-- A mesh's bounding-box face is only a real surface when the mesh actually reaches it: cast at the point from just
-- outside, against that part alone (CanQuery is switched on for the cast and restored).
local castParams=RaycastParams.new();castParams.FilterType=Enum.RaycastFilterType.Include
local surfaceCache=setmetatable({},{__mode='k'}) -- [part][face key|4-stud cell]=bool: a floor with a stair hole is real away from the hole
local casts=0
local function surfaceAt(p,point,n)
 local cf=p.CFrame;local key
 for i,a in{cf.RightVector,cf.UpVector,cf.LookVector}do local dot=a:Dot(n);if math.abs(dot)>0.999 then key=i*(dot>0 and 1 or -1)break end end
 local cache=surfaceCache[p];if not cache then cache={};surfaceCache[p]=cache end
 if key then key=key..'|'..math.floor(point.X/4)..','..math.floor(point.Y/4)..','..math.floor(point.Z/4)end
 if key and cache[key]~=nil then return cache[key]end
 casts+=1;if casts%300==0 then task.wait()end
 local query=p.CanQuery;if not query then p.CanQuery=true end
 castParams.FilterDescendantsInstances={p}
 local hit=workspace:Raycast(point+n*0.3,-n*0.6,castParams)
 if not query then p.CanQuery=false end
 local real=hit~=nil and math.abs((hit.Position-point):Dot(n))<0.01
 if key then cache[key]=real end
 return real
end

-- Visible z-fighting pairs: {a,b,faceA,faceB,area,point,n}; only (optional set of parts) limits it to pairs touching them
function M.Find(root,eps,only)
 eps=eps or PLANE_EPS
 local list,parts,count,index={}, {},0,{}
 for _,p in root:GetDescendants()do
  if p:IsA('BasePart')and(opaque(p)or p.CanCollide)then
   table.insert(parts,p);index[p]=#parts -- solid for the visibility test (an invisible collision wall still hides what is inside it)
   if boxy(p)and opaque(p)then faces(p,list)end
   count+=1;if count%YIELD_EVERY==0 then task.wait()end
  end
 end
 local grid=buildGrid(parts)
 local buckets={}
 for i,f in list do f.i=i;local k=nkey(f.n)..'|'..math.floor(f.d/BUCKET);local b=buckets[k];if not b then b={};buckets[k]=b end;table.insert(b,f)end
 local found,seen,checks={}, {},0
 local outer=list
 if only then outer={};for _,f in list do if only[f.part]then table.insert(outer,f)end end end
 for _,f in outer do
  local base=nkey(f.n);local slot=math.floor(f.d/BUCKET)
  for off=-1,1 do
   local b=buckets[base..'|'..(slot+off)]
   if b then for _,g in b do
    checks+=1;if checks%20000==0 then task.wait()end
    if g.part~=f.part and(not only or only[f.part]or only[g.part])and math.abs(g.d-f.d)<eps and f.n:Dot(g.n)>0.9995 and not sameLook(f.part,g.part)then
     -- per face pair, not per part pair: two parts can meet on several planes (bottoms hidden, ends visible)
     local ia,ib=f.i,g.i
     local id=ia<ib and ia..'|'..ib or ib..'|'..ia
     if not seen[id]then
      seen[id]=true
      local area,point,ou,ov=overlap(f,g)
      if area>=MIN_AREA then
       -- visible only if the space just in front of the shared face is not solid
       -- visible if any of 3x3 spots over the overlap has open space in front (a crossing wall may cover the centre)
       local open=false
       for _,su in{-0.4,0,0.4}do for _,sv in{-0.4,0,0.4}do
        if not open and not solidAt(grid,point+f.u*(ou*su)+f.v*(ov*sv)+f.n*PROBE,f.part,g.part)then open=true end
       end end
       local real=(not f.mesh or surfaceAt(f.part,point,f.n))and(not g.mesh or surfaceAt(g.part,point,f.n))
       if real and open then
        table.insert(found,{a=f.part,b=g.part,fa=f,fb=g,area=area,point=point,n=f.n})
       end
      end
     end
    end
   end end
  end
 end
 return found
end

-- Local axis name and side of a world-space face normal on a part.
local function faceOf(p,n)
 local cf=p.CFrame
 for _,a in{{'X',cf.RightVector},{'Y',cf.UpVector},{'Z',-cf.LookVector}}do
  local dot=a[2]:Dot(n);if math.abs(dot)>0.999 then return a[1],dot>0 and 1 or -1 end
 end
end
-- Move one face of a part along its own normal by amount (positive = outward), leaving the opposite face in place.
local function shiftFace(p,axis,sign,amount)
 if amount<=0 and p.Size[axis]<=0.01-amount then return false end -- Roblox clamps sizes; never inset a very thin axis
 local delta=Vector3.new(axis=='X'and amount or 0,axis=='Y'and amount or 0,axis=='Z'and amount or 0)
 p.Size+=delta;p.CFrame*=CFrame.new(delta*0.5*sign)
 return true
end

-- Returns how many faces moved and the set of parts that moved.
local function applyOnce(root,only)
 local interactive=root:FindFirstChild('Interactive')
 local done,count,moved={},0,{} -- done[part][axis..sign]: each face fixed at most once, every face of a part considered
 for _,pair in M.Find(root,nil,only)do
  local small,big,sf,bf=pair.a,pair.b,pair.fa,pair.fb
  if pair.fb.area<pair.fa.area then small,big,sf,bf=pair.b,pair.a,pair.fb,pair.fa end
  local fixed=false
  if movable(small,interactive)then
   local axis,sign=faceOf(small,pair.n)
   local key=axis and axis..sign
   done[small]=done[small]or{}
   if axis and not done[small][key]then
    -- grow the small part's front face to GAP in front of the big part's face
    local grow=(bf.d+GAP)-small.CFrame.Position:Dot(pair.n)-small.Size[axis]/2
    if grow>0 then fixed=shiftFace(small,axis,sign,grow);if fixed then count+=1;moved[small]=true end else fixed=true end
    done[small][key]=true
   elseif axis then fixed=true end
  end
  if not fixed and movable(big,interactive)then
   local axis,sign=faceOf(big,pair.n)
   local key=axis and axis..sign
   done[big]=done[big]or{}
   if axis and not done[big][key]then
    -- pull the big part's face back to GAP behind the small part's face
    local inset=big.CFrame.Position:Dot(pair.n)+big.Size[axis]/2-(sf.d-GAP)
    if inset>0 then fixed=shiftFace(big,axis,sign,-inset);if fixed then count+=1;moved[big]=true end end
    done[big][key]=true
   end
  end
 end
 return count,moved
end

-- Three or more parts on one plane: the first pass moves two of them the same GAP out, where they meet again;
-- later passes separate what the previous one left.
function M.Apply(root)
 local total,t0=0,os.clock()
 local interactive=root:FindFirstChild('Interactive')
 -- Zero-length wall pieces (0.001 studs on an axis) are two coplanar faces on top of their neighbours' ends:
 -- they cannot be moved apart, so they stop drawing (collision stays).
 for _,p in root:GetDescendants()do
  if p:IsA('BasePart')and movable(p,interactive)and math.min(p.Size.X,p.Size.Y,p.Size.Z)<=0.002 then
   p.Transparency=1;p.CastShadow=false
   for _,c in p:GetChildren()do if c:IsA('Decal')then c.Transparency=1 end end
  end
 end
 local only
 for _=1,6 do
  local n,moved=applyOnce(root,only);total+=n
  if n==0 then break end
  only=moved -- later passes only look at pairs that touch a part the previous pass moved
 end
 root:SetAttribute('ZFightFixed',total);root:SetAttribute('ZFightSeconds',os.clock()-t0)
 return total
end
return M
