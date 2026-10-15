-- Headless Blender red pepper (D:\RobloxMansion\SnailShell_20261001\build.py).
-- Blob0..1 hold base64 little-endian geometry per part: int16 vertices (mm), int8 normals (/127), uint16 triangles.
local Http=game:GetService('HttpService')
local META=[==[[{"name":"ShellCoil","color":[185,120,60],"alpha":0.0,"center":[0.24,0.02,0.0],"size":[0.38,0.4,0.22],"nv":52,"nt":100},{"name":"ShellCoil","color":[225,185,120],"alpha":0.0,"center":[0.136,0.1965,0.0],"size":[0.356,0.375,0.206],"nv":52,"nt":100},{"name":"ShellCoil","color":[185,120,60],"alpha":0.0,"center":[-0.052,0.2185,0.0],"size":[0.332,0.349,0.192],"nv":52,"nt":100},{"name":"ShellCoil","color":[225,185,120],"alpha":0.0,"center":[-0.173,0.093,0.0],"size":[0.308,0.324,0.178],"nv":52,"nt":100},{"name":"ShellCoil","color":[185,120,60],"alpha":0.0,"center":[-0.148,-0.064,0.0],"size":[0.284,0.298,0.164],"nv":52,"nt":100},{"name":"ShellCoil","color":[225,185,120],"alpha":0.0,"center":[-0.0215,-0.1315,0.0],"size":[0.259,0.273,0.15],"nv":52,"nt":100},{"name":"ShellCoil","color":[185,120,60],"alpha":0.0,"center":[0.0945,-0.077,0.0],"size":[0.235,0.248,0.136],"nv":52,"nt":100},{"name":"ShellCoil","color":[225,185,120],"alpha":0.0,"center":[0.1175,0.0335,0.0],"size":[0.211,0.221,0.122],"nv":52,"nt":100},{"name":"ShellCoil","color":[185,120,60],"alpha":0.0,"center":[0.0515,0.106,0.0],"size":[0.187,0.196,0.108],"nv":52,"nt":100},{"name":"ShellCoil","color":[225,185,120],"alpha":0.0,"center":[-0.03,0.0975,0.0],"size":[0.162,0.171,0.094],"nv":52,"nt":100},{"name":"ShellCoil","color":[185,120,60],"alpha":0.0,"center":[-0.063,0.0385,0.0],"size":[0.138,0.145,0.08],"nv":52,"nt":100},{"name":"ShellCoil","color":[225,185,120],"alpha":0.0,"center":[-0.039,-0.008,0.0],"size":[0.114,0.12,0.066],"nv":52,"nt":100},{"name":"ShellLip","color":[240,220,180],"alpha":0.0,"center":[0.26,-0.15,0.0],"size":[0.26,0.12,0.12],"nv":86,"nt":168}]]==]
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
 table.insert(data,{group='SnailShell',name=m.name,color=m.color,alpha=m.alpha,center=m.center,size=m.size,vertices=v,normals=n,triangles=t})
end
assert(o==buffer.len(raw),'SnailShell geometry length mismatch')
return data
