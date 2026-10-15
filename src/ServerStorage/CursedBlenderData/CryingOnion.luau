-- Headless Blender crying onion (D:\RobloxMansion\CryingOnion_20261001\onion_build.py).
-- Blob0..1 hold base64 little-endian geometry per part: int16 vertices (mm), int8 normals (/127), uint16 triangles.
local Http=game:GetService('HttpService')
local META=[==[[{"name":"OnionBulb","color":[150,62,110],"alpha":0.0,"center":[0.0,0.155,0.0],"size":[1.024,1.13,0.99],"nv":478,"nt":952},{"name":"OnionSkin","color":[205,150,120],"alpha":0.0,"center":[0.1865,-0.0695,-0.412],"size":[0.377,0.449,0.236],"nv":24,"nt":44},{"name":"OnionNeck","color":[196,132,112],"alpha":0.0,"center":[0.0,0.6,0.0],"size":[0.18,0.22,0.18],"nv":32,"nt":60},{"name":"OnionSprout","color":[98,160,72],"alpha":0.0,"center":[0.048,0.8655,0.0],"size":[0.144,0.415,0.064],"nv":20,"nt":36},{"name":"OnionSprout","color":[98,160,72],"alpha":0.0,"center":[-0.0375,0.8385,-0.0475],"size":[0.113,0.357,0.093],"nv":20,"nt":36},{"name":"OnionSprout","color":[98,160,72],"alpha":0.0,"center":[0.0,0.8115,0.0725],"size":[0.06,0.299,0.115],"nv":20,"nt":36},{"name":"OnionRoot","color":[222,205,170],"alpha":0.0,"center":[0.05,-0.45,0.0],"size":[0.106,0.12,0.024],"nv":12,"nt":20},{"name":"OnionRoot","color":[222,205,170],"alpha":0.0,"center":[0.031,-0.45,0.039],"size":[0.072,0.122,0.094],"nv":12,"nt":20},{"name":"OnionRoot","color":[222,205,170],"alpha":0.0,"center":[-0.011,-0.45,0.0485],"size":[0.038,0.122,0.107],"nv":12,"nt":20},{"name":"OnionRoot","color":[222,205,170],"alpha":0.0,"center":[-0.045,-0.45,0.0215],"size":[0.098,0.124,0.065],"nv":12,"nt":20},{"name":"OnionRoot","color":[222,205,170],"alpha":0.0,"center":[-0.045,-0.45,-0.0215],"size":[0.098,0.124,0.065],"nv":12,"nt":20},{"name":"OnionRoot","color":[222,205,170],"alpha":0.0,"center":[-0.011,-0.45,-0.0485],"size":[0.038,0.122,0.107],"nv":12,"nt":20},{"name":"OnionRoot","color":[222,205,170],"alpha":0.0,"center":[0.031,-0.45,-0.039],"size":[0.072,0.122,0.094],"nv":12,"nt":20},{"name":"OnionEye","color":[30,18,30],"alpha":0.0,"center":[-0.15,0.1,0.446],"size":[0.114,0.134,0.05],"nv":86,"nt":168},{"name":"OnionBrow","color":[30,18,30],"alpha":0.0,"center":[-0.15,0.23,0.358],"size":[0.108,0.068,0.03],"nv":8,"nt":12},{"name":"OnionTear","color":[120,200,255],"alpha":0.15,"center":[-0.19,-0.042,0.457],"size":[0.08,0.116,0.08],"nv":86,"nt":168},{"name":"OnionEye","color":[30,18,30],"alpha":0.0,"center":[0.15,0.1,0.4455],"size":[0.114,0.134,0.049],"nv":86,"nt":168},{"name":"OnionBrow","color":[30,18,30],"alpha":0.0,"center":[0.15,0.23,0.358],"size":[0.108,0.068,0.03],"nv":8,"nt":12},{"name":"OnionTear","color":[120,200,255],"alpha":0.15,"center":[0.19,-0.042,0.457],"size":[0.08,0.116,0.08],"nv":86,"nt":168},{"name":"OnionFrown","color":[30,18,30],"alpha":0.0,"center":[0.0,-0.1405,0.468],"size":[0.202,0.083,0.028],"nv":54,"nt":96}]]==]
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
local raw=decode(script.Blob0.Value..script.Blob1.Value)
local data,o={},0
for _,m in ipairs(meta)do
 local v,n,t={},{},{}
 for i=1,m.nv do v[i]={buffer.readi16(raw,o)/1000,buffer.readi16(raw,o+2)/1000,buffer.readi16(raw,o+4)/1000};o+=6 end
 for i=1,m.nv do n[i]={buffer.readi8(raw,o)/127,buffer.readi8(raw,o+1)/127,buffer.readi8(raw,o+2)/127};o+=3 end
 for i=1,m.nt do t[i]={buffer.readu16(raw,o),buffer.readu16(raw,o+2),buffer.readu16(raw,o+4)};o+=6 end
 table.insert(data,{group='CryingOnion',name=m.name,color=m.color,alpha=m.alpha,center=m.center,size=m.size,vertices=v,normals=n,triangles=t})
end
assert(o==buffer.len(raw),'CryingOnion geometry length mismatch')
return data
