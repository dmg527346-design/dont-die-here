-- Server-only admission rules for one reserved party mission.
local M={}
M.LobbyCapacity=20
M.ArrivalSeconds=120
M.MaximumPartySize=4
function M.Validate(session,context)
 if type(session)~='table'or session.version~=2 then return false,'Missing mission session.'end
 if type(context)~='table'or context.reserved~=true then return false,'Mission requires a reserved server.'end
 if context.closed then return false,'This mission is already sealed.'end
 if type(context.token)~='string'or context.token~=session.token then return false,'Invalid launch ticket.'end
 if context.sourcePlaceId~=session.sourcePlaceId or context.sourceGameId~=session.sourceGameId then return false,'Join through the main lobby.'end
 if context.privateId~=session.privateId then return false,'Wrong reserved server.'end
 if type(session.expires)~='number'or context.now>session.expires then return false,'The launch window has closed.'end
 if type(session.owner)~='number'or session.owner~=session.owner or session.owner%1~=0 or session.owner<1 or session.owner>9007199254740991 or type(session.allowed)~='table'or session.allowed[tostring(session.owner)]~=true then return false,'Invalid party owner.'end
 if type(session.runSave)~='table'or session.runSave.ownerUserId~=session.owner then return false,'Missing owner run save.'end
 if type(session.count)~='number'or session.count<1 or session.count>M.MaximumPartySize then return false,'Invalid party size.'end
 if type(session.allowed)~='table'or session.allowed[tostring(context.userId)]~=true then return false,'You are not in this party.'end
 if session.destinationJob and session.destinationJob~=''and session.destinationJob~=context.job then return false,'This party belongs to another instance.'end
 if type(session.admitted)=='table'and session.admitted[tostring(context.userId)]then return false,'Your launch ticket was already used.'end
 return true
end
function M.Claim(session,context)
 local ok,reason=M.Validate(session,context);if not ok then return nil,reason end
 local nextSession=table.clone(session)
 nextSession.allowed=table.clone(session.allowed)
 nextSession.admitted=table.clone(session.admitted or {})
 nextSession.destinationJob=context.job
 nextSession.admitted[tostring(context.userId)]=context.job
 return nextSession
end
return M
