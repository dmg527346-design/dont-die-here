-- Headless Blender red pepper (D:\RobloxMansion\HotSauce_20261001\build.py).
-- Blob0..1 hold base64 little-endian geometry per part: int16 vertices (mm), int8 normals (/127), uint16 triangles.
local Http=game:GetService('HttpService')
local META=[==[[{"name":"SauceBottle","color":[190,25,15],"alpha":0.0,"center":[0.0,0.0,0.0],"size":[0.34,0.62,0.34],"nv":160,"nt":316},{"name":"SauceLabel","color":[245,235,215],"alpha":0.0,"center":[0.0,-0.02,0.0],"size":[0.344,0.26,0.344],"nv":40,"nt":76},{"name":"SauceNeck","color":[190,25,15],"alpha":0.0,"center":[0.0,0.42,0.0],"size":[0.34,0.22,0.34],"nv":32,"nt":60},{"name":"SauceCap","color":[40,120,45],"alpha":0.0,"center":[0.0,0.58,0.0],"size":[0.14,0.12,0.14],"nv":24,"nt":44},{"name":"SauceFlame","color":[255,140,20],"alpha":0.0,"center":[0.0,-0.02,0.175],"size":[0.02,0.12,0.2],"nv":8,"nt":12}]]==]
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
 table.insert(data,{group='HotSauce',name=m.name,color=m.color,alpha=m.alpha,center=m.center,size=m.size,vertices=v,normals=n,triangles=t})
end
assert(o==buffer.len(raw),'HotSauce geometry length mismatch')
return data
