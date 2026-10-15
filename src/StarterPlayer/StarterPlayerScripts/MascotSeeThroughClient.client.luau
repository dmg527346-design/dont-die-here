-- The Mascot Head wearer sees through their own mascot head (local only; everyone else sees it solid).
-- Applied every frame just before rendering, because the held-item client resets held items' transparency.
local Players=game:GetService('Players')
local RunService=game:GetService('RunService')
local player=Players.LocalPlayer
local SEE_THROUGH=.82
local faded={}
local worn={}
local acc=1
RunService:BindToRenderStep('MascotSeeThrough',Enum.RenderPriority.Last.Value+20,function(dt)
 acc+=dt
 if acc>=.25 then
  acc=0;table.clear(worn)
  local map=workspace:FindFirstChild('Mansion');local items=map and map:FindFirstChild('Interactive')
  if items then for _,m in ipairs(items:GetChildren())do
   if m:GetAttribute('ItemId')=='MascotHead' and (m:GetAttribute('ItemWearOwner')==player.UserId or m:GetAttribute('HeldBy')==player.UserId) and m:GetAttribute('ItemWearEnd')==nil then
    local parts={};for _,p in ipairs(m:GetDescendants())do if p:IsA('BasePart')then table.insert(parts,p)end end;worn[m]=parts
   end
  end end
  for m,parts in pairs(faded)do if not worn[m] then for _,p in ipairs(parts)do if p.Parent then p.LocalTransparencyModifier=0 end end;faded[m]=nil end end
 end
 for m,parts in pairs(worn)do for _,p in ipairs(parts)do p.LocalTransparencyModifier=SEE_THROUGH end;faded[m]=parts end
end)
