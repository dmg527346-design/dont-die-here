-- Headless Blender red pepper (D:\RobloxMansion\VentriloquistDoll_20261001\build.py).
-- Blob0..1 hold base64 little-endian geometry per part: int16 vertices (mm), int8 normals (/127), uint16 triangles.
local Http=game:GetService('HttpService')
local META=[==[[{"name":"DollHead","color":[240,205,175],"alpha":0.0,"center":[0.0,0.32,0.0],"size":[0.384,0.42,0.374],"nv":114,"nt":224},{"name":"DollHair","color":[60,35,20],"alpha":0.0,"center":[0.0,0.4,-0.02],"size":[0.394,0.226,0.384],"nv":114,"nt":224},{"name":"DollJaw","color":[235,198,168],"alpha":0.0,"center":[0.0,0.12,0.03],"size":[0.18,0.08,0.2],"nv":8,"nt":12},{"name":"DollMouth","color":[25,10,10],"alpha":0.0,"center":[0.0,0.19,0.19],"size":[0.17,0.026,0.02],"nv":8,"nt":12},{"name":"DollEye","color":[250,250,250],"alpha":0.0,"center":[-0.075,0.36,0.17],"size":[0.066,0.07,0.07],"nv":52,"nt":100},{"name":"DollPupil","color":[20,20,30],"alpha":0.0,"center":[-0.075,0.36,0.2],"size":[0.036,0.036,0.036],"nv":42,"nt":80},{"name":"DollCheek","color":[230,90,90],"alpha":0.0,"center":[-0.12,0.25,0.16],"size":[0.058,0.06,0.024],"nv":52,"nt":100},{"name":"DollEye","color":[250,250,250],"alpha":0.0,"center":[0.075,0.36,0.17],"size":[0.066,0.07,0.07],"nv":52,"nt":100},{"name":"DollPupil","color":[20,20,30],"alpha":0.0,"center":[0.075,0.36,0.2],"size":[0.036,0.036,0.036],"nv":42,"nt":80},{"name":"DollCheek","color":[230,90,90],"alpha":0.0,"center":[0.12,0.25,0.16],"size":[0.058,0.06,0.024],"nv":52,"nt":100},{"name":"DollSuit","color":[35,35,45],"alpha":0.0,"center":[0.0,-0.13,0.0],"size":[0.3,0.34,0.2],"nv":56,"nt":108},{"name":"DollShirt","color":[240,240,240],"alpha":0.0,"center":[0.0,-0.01,0.005],"size":[0.1,0.12,0.21],"nv":8,"nt":12},{"name":"DollBowtie","color":[200,20,30],"alpha":0.0,"center":[-0.045,0.04,0.11],"size":[0.084,0.056,0.042],"nv":42,"nt":80},{"name":"DollBowtie","color":[200,20,30],"alpha":0.0,"center":[0.045,0.04,0.11],"size":[0.084,0.056,0.042],"nv":42,"nt":80}]]==]
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
 table.insert(data,{group='VentriloquistDoll',name=m.name,color=m.color,alpha=m.alpha,center=m.center,size=m.size,vertices=v,normals=n,triangles=t})
end
assert(o==buffer.len(raw),'VentriloquistDoll geometry length mismatch')
return data
