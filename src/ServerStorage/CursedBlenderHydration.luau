local A=game:GetService('AssetService')
local M={}
function M.Build()
 local SS=game.ServerStorage
 require(SS.DurableFlyGeometry).Build()
 for _,group in ipairs({'RainCloud','CoolSunglasses','CoolHat','FlyJar','CursedPerfume','PartyBlower','CryingOnion','RedPepper','HotSauce','Popsicle','BeehiveJar','MakeupKit','ChewingGum','VentriloquistDoll','SnailShell','CoffeeMug','JawbreakerBag'})do
 local data
 if group=='RainCloud'then local f=SS.CursedBlenderData;data=game.HttpService:JSONDecode(f.CloudChunk0.Value..f.CloudChunk1.Value..f.CloudChunk2.Value)else data=require(SS.CursedBlenderData[group])end
 local kit=table.find({'RainCloud','CoolSunglasses','FlyJar','CursedPerfume','CryingOnion','RedPepper','HotSauce','Popsicle','BeehiveJar','MakeupKit','ChewingGum','VentriloquistDoll','SnailShell','CoffeeMug','JawbreakerBag'},group)
 local target=(kit and SS.CursedItemKit or SS.CursedAccessoryKit)[group]
 local counts={}
 task.wait()
 for _,d in ipairs(data)do
 counts[d.name]=(counts[d.name]or 0)+1
 local name=d.name:find('FlyWing')and 'FlyWing'or d.name
 local found={};for _,p in ipairs(target:GetChildren())do if p.Name==name and p:IsA('MeshPart')then table.insert(found,p)end end
 local part=found[counts[d.name]]
 if d.name:find('FlyWing')then for _,p in ipairs(found)do if p:GetAttribute('FlySide')==(d.name:find('-1',1,true)and -1 or 1)then part=p end end end
 assert(part,group..' missing '..d.name)
 local e=A:CreateEditableMesh();assert(e,'Blender mesh allocation failed');local v,n={},{}
 local lo=Vector3.new(math.huge,math.huge,math.huge);local hi=-lo
 for _,p in ipairs(d.vertices)do local q=Vector3.new(unpack(p));lo=lo:Min(q);hi=hi:Max(q)end
 local center=(lo+hi)/2
 -- Runs while a mission server starts: yield every few thousand vertices so no single frame stalls.
 for i,p in ipairs(d.vertices)do v[i]=e:AddVertex(Vector3.new(unpack(p))-center);n[i]=e:AddNormal(Vector3.new(unpack(d.normals[i])));if i%2500==0 then task.wait()end end
 for i,f in ipairs(d.triangles)do local id=e:AddTriangle(v[f[1]+1],v[f[2]+1],v[f[3]+1]);e:SetFaceNormals(id,{n[f[1]+1],n[f[2]+1],n[f[3]+1]});if i%2500==0 then task.wait()end end
 local result,content=A:CreateDataModelContentAsync(Content.fromObject(e));assert(result==Enum.CreateContentResult.Success,tostring(result))
 local generated=A:CreateMeshPartAsync(content);local size,cf=part.Size,part.CFrame;part:ApplyMesh(generated);part.Size=size;part.CFrame=cf;generated:Destroy();e:Destroy()
 end
 end
 -- The jar contains the same detailed fly that escapes it.
 local jar=SS.CursedItemKit.FlyJar
 for _,p in ipairs(jar:GetChildren())do if p:IsA('BasePart')and(p.Name:find('Fly')or p.Name=='Antenna')then p:Destroy()end end
 for _,p in ipairs(SS.CursedAccessoryKit.AnnoyingFly:GetChildren())do if p:IsA('BasePart')and p.Name~='Root'then local c=p:Clone();for _,w in ipairs(c:GetChildren())do if w:IsA('WeldConstraint')then w:Destroy()end end;c.CFrame=jar:GetPivot()*CFrame.new(0,-.06,0)*SS.CursedAccessoryKit.AnnoyingFly:GetPivot():ToObjectSpace(p.CFrame);c.Parent=jar;local w=Instance.new('WeldConstraint');w.Part0=jar.PrimaryPart;w.Part1=c;w.Parent=c end end
end
return M