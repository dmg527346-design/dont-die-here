-- Headless Blender red pepper (D:\RobloxMansion\JawbreakerBag_20261001\build.py).
-- Blob0..1 hold base64 little-endian geometry per part: int16 vertices (mm), int8 normals (/127), uint16 triangles.
local Http=game:GetService('HttpService')
local META=[==[[{"name":"CandyBag","color":[230,240,250],"alpha":0.65,"center":[0.0,0.0,0.0],"size":[0.576,0.66,0.472],"nv":114,"nt":224},{"name":"Jawbreaker1","color":[230,40,60],"alpha":0.0,"center":[-0.1,-0.12,0.02],"size":[0.19,0.2,0.2],"nv":52,"nt":100},{"name":"Jawbreaker2","color":[60,140,230],"alpha":0.0,"center":[0.11,-0.12,-0.02],"size":[0.19,0.2,0.2],"nv":52,"nt":100},{"name":"Jawbreaker3","color":[250,200,40],"alpha":0.0,"center":[0.0,0.02,0.05],"size":[0.19,0.2,0.2],"nv":52,"nt":100},{"name":"Jawbreaker4","color":[120,200,80],"alpha":0.0,"center":[-0.1,0.08,-0.05],"size":[0.19,0.2,0.2],"nv":52,"nt":100},{"name":"Jawbreaker5","color":[200,90,210],"alpha":0.0,"center":[0.1,0.1,0.04],"size":[0.19,0.2,0.2],"nv":52,"nt":100},{"name":"BagTwist","color":[230,240,250],"alpha":0.5,"center":[0.0,0.36,0.0],"size":[0.14,0.1,0.14],"nv":24,"nt":44},{"name":"BagTie","color":[220,40,60],"alpha":0.0,"center":[0.0,0.32,0.0],"size":[0.076,0.04,0.08],"nv":20,"nt":36}]]==]
local ALPHABET='ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'
local function decode(s)
 local map={};for i=1,64 do map[string.byte(ALPHABET,i)]=i-1 end
 local pad=(s:sub(-2)=='==' and 2)or(s:sub(-1)=='=' and 1)or 0
 local out=buffer.create(#s//4*3-pad);local o=0
 for i=1,#s,4 do
  local a,b,c,d=string.byte(s,i,i+3)
  local n=map[a]*262144+map[b]*4096+(map[c] or 0)*64+(map[d] or 0)
  buffer.writeu8(out,o,n//65536);o+=1
  if o<buffer.len(out)then buffer.writeu8(out,o,n//256%256);o+=1 end
  if o<buffer.len(out)then buffer.writeu8(out,o,n%256);o+=1 end
 end
 return out
end
local meta=Http:JSONDecode(META)
local raw=decode(script.Blob0.Value)
local data,o={},0
for _,m in ipairs(meta)do
 local v,n,t={},{},{}
 for i=1,m.nv do v[i]={buffer.readi16(raw,o)/1000,buffer.readi16(raw,o+2)/1000,buffer.readi16(raw,o+4)/1000};o+=6 end
 for i=1,m.nv do n[i]={buffer.readi8(raw,o)/127,buffer.readi8(raw,o+1)/127,buffer.readi8(raw,o+2)/127};o+=3 end
 for i=1,m.nt do t[i]={buffer.readu16(raw,o),buffer.readu16(raw,o+2),buffer.readu16(raw,o+4)};o+=6 end
 table.insert(data,{group='JawbreakerBag',name=m.name,color=m.color,alpha=m.alpha,center=m.center,size=m.size,vertices=v,normals=n,triangles=t})
end
assert(o==buffer.len(raw),'JawbreakerBag geometry length mismatch')
return data
