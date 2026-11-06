local M={}
M.DefaultPreferences={MasterVolume=.65,EffectsVolume=.7,MenuMusicVolume=.25,Jumpscares=true,FlashingLights=true,CameraMotion=true,SpitEffects=true,VoiceEffects=true,MobileHighQuality=true}
function M.Preferences(input)
 local out=table.clone(M.DefaultPreferences)
 if type(input)=='table' then for key,default in pairs(out)do
  local value=input[key]
  if type(default)=='boolean' and type(value)=='boolean' then out[key]=value
  elseif type(default)=='number' and type(value)=='number' and value==value and value>=0 and value<=1 then out[key]=math.round(value*100)/100 end
 end end
 return out
end
function M.New(owner,size,friends,password,id,job,circle)
 if type(size)~='number' or size%1~=0 or size<1 or size>4 then return nil,'Choose 1 to 4 players.'end
 if type(friends)~='boolean' or type(password)~='string' or #password>40 or #password>0 and #password<4 then return nil,'Use a password with 4 to 40 characters.'end
 if circle~=nil and (type(circle)~='number' or circle%1~=0 or circle<1 or circle>20) then return nil,'Choose a lobby circle from 1 to 20.'end
 return {id=id,job=job,circle=circle,owner=owner.id,ownerName=owner.name,ownerDisplay=owner.display,size=size,friendsOnly=friends,password=password,status='Waiting',members={{id=owner.id,name=owner.name,display=owner.display}},invited={},updated=os.time()}
end
function M.Admit(record,user,isFriend,password)
 if not record or record.status~='Waiting' then return false,'This party is no longer available.'end
 for _,member in record.members do if member.id==user.id then return true end end
 if #record.members>=record.size then return false,'This party is full.'end
 if record.friendsOnly and not isFriend then return false,'This party is for the host’s friends only.'end
 if record.password~='' and password~=record.password then return false,'Incorrect password.'end
 table.insert(record.members,{id=user.id,name=user.name,display=user.display});record.updated=os.time();return true
end
function M.Remove(record,id)
 for i=#record.members,1,-1 do if record.members[i].id==id then table.remove(record.members,i)end end
 record.updated=os.time()
end
function M.Snapshot(record)
 if not record then return nil end
 local members={};for _,member in record.members do table.insert(members,table.clone(member))end
 return {id=record.id,circle=record.circle,owner=record.owner,ownerName=record.ownerName,ownerDisplay=record.ownerDisplay,size=record.size,friendsOnly=record.friendsOnly,passwordRequired=record.password~='',status=record.status,members=members,countdown=record.countdown}
end
function M.MatchFriend(friend,query)
 local q=string.lower(query or ''):gsub('^@','')
 return q=='' or string.lower(friend.username or ''):find(q,1,true)~=nil or string.lower(friend.display or ''):find(q,1,true)~=nil
end
return M
