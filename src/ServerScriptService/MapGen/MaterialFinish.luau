local M={}
function M.Apply(mansion)
 if mansion:GetAttribute('MaterialFinishVersion') then return end -- idempotent: desaturation must run once per map
 local kind=mansion:GetAttribute('MapKind')
 for _,p in ipairs(mansion:GetDescendants()) do if p:IsA('BasePart') and p.Transparency<1 then
  local s=p:GetAttribute('Surface') or '';local owner=p:FindFirstAncestorOfClass('Model');local floor=owner and (owner.Name:find('Floor')~=nil or owner.Name=='Landing')
  local glass=p.Name=='Glass' or s=='glass' or s=='moss'
  if glass then p.MaterialVariant='';p.Material=Enum.Material.Glass;p.Color=Color3.fromRGB(34,42,43);p.Transparency=.25;if kind=='Mall' then p.Color=Color3.fromRGB(118,136,134);p.Transparency=.6;p.Reflectance=.12 end;if p:IsA('MeshPart') then p.TextureID='' end
  elseif not floor then
   if p.Material~=Enum.Material.Neon and not (kind=='Mall' and p.Material==Enum.Material.Metal) then p.Material=Enum.Material.SmoothPlastic end
   p.MaterialVariant='';p.Reflectance=0
   if p:IsA('MeshPart') and (s=='oak_dark' or s=='dustsheet' or s=='masonry' or s=='brick_old') then p.TextureID='' end
   if not p:GetAttribute('DungeonBlocks') then local h,sat,v=p.Color:ToHSV();p.Color=Color3.fromHSV(h,math.min(sat*.85,.65),v) end
  end
 end end
 mansion:SetAttribute('MaterialFinishVersion',1)
end
return M