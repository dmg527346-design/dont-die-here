local M={}
function M.IsProtected(p)
 -- AdminGod: owner-only god mode set by AdminPowersServer (never caught, seen or heard).
 return p:GetAttribute('AdminGod')==true or p:GetAttribute('Hiding')==true or p:GetAttribute('ClosetState')~=nil
  or workspace:GetServerTimeNow()<(p:GetAttribute('ClosetProtectedUntil')or 0)
end
return M