local testCallbacks=setmetatable({},{__mode='k'}) -- button -> its callback, for the Studio-only MainMenuTestApi
local InputHints=require(game:GetService('ReplicatedStorage'):WaitForChild('InputHints'))
task.spawn(function()local model=game.ReplicatedStorage:WaitForChild('LobbyCharacterPreview');pcall(function()game.ContentProvider:PreloadAsync({model})end)end)
local Players=game:GetService('Players')
local RS=game:GetService('ReplicatedStorage')
local Run=game:GetService('RunService')
local UIS=game:GetService('UserInputService')
local MENU_TOUCH_SCALE,MENU_TOUCH_MIN=.8,.7 -- lobby menu grid size on phones and tablets
local GuiService=game:GetService('GuiService')
-- Consoles (owner 2026-10-25): a TV is viewed from the couch, so the lobby icons, Quests bar, PLAY and rank card are 30% bigger.
local TV_SCALE=GuiService:IsTenFootInterface()and 1.3 or 1
local Tween=game:GetService('TweenService')
local CAS=game:GetService('ContextActionService')
local p=Players.LocalPlayer
local event=RS:WaitForChild('LobbyEvent')
local lobbyState=RS:WaitForChild('LobbyState')
local Audio=require(RS:WaitForChild('GameplayAudio'))
local Shop=require(RS:WaitForChild('LobbyShopCatalog'))
local UI=require(RS:WaitForChild('NeonUI'))
local storePopPending=false
local storeTweens={}
local storeCells={}
local storeColumns=4
local storeEntranceStarted
local STORE_ROW_DELAY,STORE_ROW_STAGGER,STORE_POP_TIME=.04,.05,.22
local function cancelStoreTweens()
 for _,t in storeTweens do t:Cancel()end;table.clear(storeTweens)
end
local function shopButton(parent,name,value,x,y,w,h,callback,enabled)
 local b=UI.button(parent,name,value,enabled and 'buy'or 'muted')
 b.Position=UDim2.fromOffset(x,y);b.Size=UDim2.fromOffset(w,h)
 b.Activated:Connect(function()Audio.Play('UiClick');callback()end)
 testCallbacks[b]=callback
 return b
end
local Appearance=require(RS:WaitForChild('AppearanceWidgets'))
local defaults={MasterVolume=.65,EffectsVolume=.7,MenuMusicVolume=.25,Jumpscares=true,FlashingLights=true,CameraMotion=true,SpitEffects=true,VoiceEffects=true,MobileHighQuality=true}
local preferences=table.clone(defaults)
local party,friendResults,browseResults=nil,{},{}
local tab=nil;local playMode='Create';
-- 3D lobby: the Play flow starts by stepping onto a circle (hostCircle), then SAVE -> PLAYERS -> PRIVACY.
local hostCircle,hostStep,joinTarget=nil,'save',nil
local cancelHost,startHost,build
local hostPending=false
local shopTab='Tokens';local chosenSize=1
local friendsOnly,privatePassword=false,false
-- Run saves (party owner only, 3 slots): chosen before creating a party.
local saveOpen,saveSlots,saveLoading,chosenSave,confirmDelete=false,nil,false,nil,nil
local saveLoadError=nil
local progress: any={ready=false,tokens=0,owned={},equipped={},stats={}}
local boardCategory='HighestLevel';local boardRows={};local boardPage=1;local shopPage=1;local boardLoading=false
local passwordValue,friendQuery,joinPassword='','',''
local status='Choose your crew. Bring everyone back.'
local pending={};local quietRequests={};local sequence=0;local gui,canvas,body,bodyContent,statusLabel,headerLabel,startButton
local W,H,bodyW,bodyH,compact,lowWide
local layoutScale=1
local function scaleTree(root,f,skip)
 if root==skip then return end
 local function dim(v)return UDim2.new(v.X.Scale,v.X.Offset*f,v.Y.Scale,v.Y.Offset*f)end
 if root:IsA('GuiObject')then root.Position=dim(root.Position);root.Size=dim(root.Size)end
 if root:IsA('TextLabel')or root:IsA('TextButton')or root:IsA('TextBox')then root.TextSize=math.max(10,root.TextSize*f)end
 if root:IsA('UICorner')then local v=root.CornerRadius;root.CornerRadius=UDim.new(v.Scale,v.Offset*f)end
 if root:IsA('UIStroke')then root.Thickness=math.max(1,root.Thickness*f)end
 if root:IsA('UIPadding')then for _,key in {'PaddingLeft','PaddingRight','PaddingTop','PaddingBottom'}do local v=root[key];root[key]=UDim.new(v.Scale,v.Offset*f)end end
 for _,child in root:GetChildren()do scaleTree(child,f,skip)end
end
local colors={ink=Color3.fromRGB(8,18,22),panel=Color3.fromRGB(22,42,43),card=Color3.fromRGB(31,55,53),cream=Color3.fromRGB(244,236,210),muted=Color3.fromRGB(157,181,171),green=Color3.fromRGB(167,202,127),red=Color3.fromRGB(227,141,125)}
local function corners(x,r)local c=Instance.new('UICorner');c.CornerRadius=UDim.new(0,r or 14);c.Parent=x end
local function stroke(x,color,thick)local s=Instance.new('UIStroke');s.Color=color or colors.ink;s.Thickness=thick or 3;s.ApplyStrokeMode=Enum.ApplyStrokeMode.Border;s.Parent=x;return s end
local function frame(parent,name,x,y,w,h,color)
 local f=Instance.new('Frame');f.Name=name;f.Position=UDim2.fromOffset(x,y);f.Size=UDim2.fromOffset(w,h);f.BackgroundColor3=color or colors.card;f.BorderSizePixel=0;f.Parent=parent;corners(f);stroke(f);return f
end
local function text(parent,name,value,x,y,w,h,size,color)
 local t=Instance.new('TextLabel');t.Name=name;t.Text=value;t.Position=UDim2.fromOffset(x,y);t.Size=UDim2.fromOffset(w,h);t.BackgroundTransparency=1;t.Font=Enum.Font.FredokaOne;t.TextSize=size or 20;t.TextColor3=color or colors.cream;t.TextXAlignment=Enum.TextXAlignment.Left;t.TextWrapped=true;t.Parent=parent;return t
end
-- Console focus (2026-10-22): a thick gold ring just outside the button that breathes while it is selected;
-- the old thin cream line was easy to miss on a TV.
local FOCUS_GOLD=Color3.fromRGB(255,206,64)
local function focusRing(b,radius)
 local ring=Instance.new('Frame');ring.Name='FocusRing';ring.BackgroundTransparency=1;ring.Size=UDim2.new(1,10,1,10);ring.Position=UDim2.fromOffset(-5,-5)
 corners(ring,radius+5);local line=stroke(ring,FOCUS_GOLD,4)
 b.SelectionImageObject=ring
 local pulse
 b.SelectionGained:Connect(function()if pulse then pulse:Cancel()end;line.Transparency=0;pulse=Tween:Create(line,TweenInfo.new(.55,Enum.EasingStyle.Sine,Enum.EasingDirection.InOut,-1,true),{Transparency=.5});pulse:Play()end)
 b.SelectionLost:Connect(function()if pulse then pulse:Cancel();pulse=nil end;line.Transparency=0 end)
 return ring
end
local function button(parent,name,value,x,y,w,h,callback,accent)
 
 local b=Instance.new('TextButton');b.Name=name;b.Text=value;b.Position=UDim2.fromOffset(x,y);b.Size=UDim2.fromOffset(w,h);b.BackgroundColor3=accent and colors.green or colors.card;b.BorderSizePixel=0;b.Font=Enum.Font.FredokaOne;b.TextSize=16;b.TextColor3=accent and colors.ink or colors.cream;b.AutoButtonColor=false;b.Selectable=true;b.Parent=parent;corners(b,12);local outline=stroke(b)
 focusRing(b,12)
 local base=b.BackgroundColor3
 b.MouseEnter:Connect(function()Tween:Create(b,TweenInfo.new(.12),{BackgroundColor3=base:Lerp(colors.cream,.1)}):Play();outline.Color=colors.green end)
 b.MouseLeave:Connect(function()Tween:Create(b,TweenInfo.new(.12),{BackgroundColor3=base}):Play();outline.Color=colors.ink end)
 b.Activated:Connect(function()Audio.Play('UiClick');callback()end)
 testCallbacks[b]=callback
 return b
end
local function input(parent,name,placeholder,value,x,y,w,h,changed,secret)
 
 local b=Instance.new('TextBox');b.Name=name;b.Position=UDim2.fromOffset(x,y);b.Size=UDim2.fromOffset(w,h);b.BackgroundColor3=colors.ink;b.BorderSizePixel=0;b.Text=value or '';b.PlaceholderText=placeholder;b.PlaceholderColor3=colors.muted;b.TextColor3=colors.cream;b.Font=Enum.Font.FredokaOne;b.TextSize=15;b.ClearTextOnFocus=false;b.TextXAlignment=Enum.TextXAlignment.Left;b.Parent=parent;corners(b,10);stroke(b,colors.muted,2)
 local padding=Instance.new('UIPadding');padding.PaddingLeft=UDim.new(0,12);padding.PaddingRight=UDim.new(0,10);padding.Parent=b
 if secret then
  b.TextTransparency=1
  local mask=text(parent,name..'Mask','',x+12,y,w-24,h,18);mask.ZIndex=b.ZIndex+1;mask.TextXAlignment=Enum.TextXAlignment.Left
  local function updateMask()mask.Text=#b.Text>0 and string.rep('•',math.min(#b.Text,40)) or placeholder;mask.TextColor3=#b.Text>0 and colors.cream or colors.muted end
  b:GetPropertyChangedSignal('Text'):Connect(updateMask);updateMask()
 end
 b.FocusLost:Connect(function()changed(b.Text)end)
 return b
end
local render
local noticeToken=0
-- Toast top offset: NOTICE_TOP in the lobby; in a mission it sits NOTICE_QUOTA_GAP below the quota HUD so it never covers the quota.
local NOTICE_TOP,NOTICE_QUOTA_GAP=58,14
local function notice(value)
 status=value or '';if statusLabel and statusLabel.Parent then statusLabel.Text=status;return end
 -- No panel open: a short toast at the top of the screen.
 local pg=p:FindFirstChildOfClass('PlayerGui');if not pg or status==''then return end
 local toast=pg:FindFirstChild('LobbyNotice')or Instance.new('ScreenGui');toast.Name='LobbyNotice';toast.ResetOnSpawn=false;toast.DisplayOrder=210;toast.ScreenInsets=Enum.ScreenInsets.CoreUISafeInsets;toast.Parent=pg
 local label=toast:FindFirstChild('Text')or Instance.new('TextLabel');label.Name='Text';label.AnchorPoint=Vector2.new(.5,0);label.Size=UDim2.new(.6,0,0,30);label.BackgroundTransparency=1;label.Font=Enum.Font.FredokaOne;label.TextScaled=true;label.TextColor3=Color3.fromRGB(244,236,210);label.TextStrokeTransparency=.1;label.Text=status;label.Parent=toast
 local quota=pg:FindFirstChild('RecoveryQuota');local panel=quota and quota:FindFirstChild('QuotaPanel')
 -- In a mission the quota HUD may be hidden for a moment (phase change); still keep clear of where it sits (82 px, 53 on phones).
 local top=if p:GetAttribute('MissionActive')==true and panel and panel:IsA('GuiObject')then math.max(panel.AbsoluteSize.Y,53)+NOTICE_QUOTA_GAP else NOTICE_TOP
 label.Position=UDim2.new(.5,0,0,top)
 noticeToken+=1;local mine=noticeToken;task.delay(4,function()if mine==noticeToken and toast.Parent then toast:Destroy()end end)
end
-- Achievement feedback belongs to the existing menu client, including during missions.
local BADGE_TOAST={Width=440,Height=94,HoldSeconds=4,FadeSeconds=.22,MaxQueue=5}
local badgeToasts={}
local badgeToastBusy=false
local function showBadgeToast(info)
 if type(info)~='table' or type(info.name)~='string' then return end
 if #badgeToasts>=BADGE_TOAST.MaxQueue then return end
 table.insert(badgeToasts,info)
 if badgeToastBusy then return end
 badgeToastBusy=true
 task.spawn(function()
  while #badgeToasts>0 do
   local earned=table.remove(badgeToasts,1)
   local pg=p:FindFirstChildOfClass('PlayerGui');if not pg then break end
   local screen=Instance.new('ScreenGui');screen.Name='BadgeEarnedToast';screen.ResetOnSpawn=false;screen.DisplayOrder=250;screen.ScreenInsets=Enum.ScreenInsets.CoreUISafeInsets;screen.Parent=pg
   local root=Instance.new('Frame');root.Name='Message';root.BackgroundTransparency=1;root.AnchorPoint=Vector2.new(.5,.5);root.Position=UDim2.fromScale(.5,.74);root.Size=UDim2.new(.9,0,0,BADGE_TOAST.Height);root.Parent=screen
   local size=Instance.new('UISizeConstraint');size.MaxSize=Vector2.new(BADGE_TOAST.Width,BADGE_TOAST.Height);size.Parent=root
   local group=Instance.new('CanvasGroup');group.Size=UDim2.fromScale(1,1);group.BackgroundTransparency=1;group.GroupTransparency=1;group.Parent=root
   local title=Instance.new('TextLabel');title.Name='Title';title.BackgroundTransparency=1;title.Position=UDim2.fromOffset(8,0);title.Size=UDim2.new(1,-16,0,48);title.Font=Enum.Font.FredokaOne;title.TextColor3=Color3.fromRGB(167,202,127);title.TextStrokeColor3=Color3.fromRGB(8,18,22);title.TextStrokeTransparency=.1;title.TextScaled=true;title.TextWrapped=true;title.Text=(earned.preview and 'BADGE PREVIEW: 'or 'BADGE EARNED: ')..earned.name;title.Parent=group
   local cap=Instance.new('UITextSizeConstraint');cap.MinTextSize=13;cap.MaxTextSize=24;cap.Parent=title
   local detail=title:Clone();detail.Name='Description';detail.Position=UDim2.fromOffset(8,50);detail.Size=UDim2.new(1,-16,0,40);detail.TextColor3=Color3.fromRGB(244,236,210);detail.Text=earned.description or '';detail.UITextSizeConstraint.MaxTextSize=16;detail.Parent=group
   Tween:Create(group,TweenInfo.new(BADGE_TOAST.FadeSeconds),{GroupTransparency=0}):Play()
   task.wait(BADGE_TOAST.HoldSeconds)
   local fade=Tween:Create(group,TweenInfo.new(BADGE_TOAST.FadeSeconds),{GroupTransparency=1});fade:Play();fade.Completed:Wait();screen:Destroy()
  end
  badgeToastBusy=false
 end)
end

local failHandlers={} -- optional per-request failure callbacks (error reply or timeout)
local function request(action,data,callback,quiet,onFail)
 sequence+=1;local id=sequence
 pending[id]=callback or function()end;quietRequests[id]=quiet==true;failHandlers[id]=onFail
 event:FireServer(id,action,data or {})
 task.delay(12,function()if pending[id]then pending[id]=nil;if not quietRequests[id]then notice('Taking longer than expected. Please try again.')end;quietRequests[id]=nil;local f=failHandlers[id];failHandlers[id]=nil;if f then f('Timed out')end end end)
end
local function updatePrefs(key,value)
 preferences[key]=value;p:SetAttribute('LocalSetting'..key,value)
 request('preferences',preferences,function(data)if data and data.preferences then preferences=data.preferences end end)
end
-- MobileQualityClient switches HIGH QUALITY off by itself when a phone lags: save that choice like the button does.
p:GetAttributeChangedSignal('LocalSettingMobileHighQuality'):Connect(function()
 local v=p:GetAttribute('LocalSettingMobileHighQuality')
 if type(v)=='boolean'and preferences.MobileHighQuality~=v then preferences.MobileHighQuality=v;request('preferences',preferences,nil,true)end
end)

local friendPage,browsePage=1,1
local pendingFocusRestore
local function rememberFocus(container)
 local field=UIS:GetFocusedTextBox()
 if field and container and field:IsDescendantOf(container)then return {name=field.Name,text=field.Text,cursor=field.CursorPosition,selection=field.SelectionStart}end
end
local refreshBrowse;local browseDirty=false;local browseFlight=false;local browseTicket=0
local activeRegion='body'
local draft: {[string]: any}={}
local dirty={}
local previewModel
local pickerRefresh
local function getSaved(region)
 if region=='light'then local c=p:GetAttribute('FlashlightColor');return typeof(c)=='Color3'and c or Color3.fromRGB(255,236,196)end
 local hex=p:GetAttribute(region=='body' and 'BodyColourHex' or 'EyeColourHex')
 if type(hex)=='string' and hex:match('^#%x%x%x%x%x%x$')then return Color3.fromHex(hex:sub(2))end
 return region=='body' and Color3.fromRGB(145,168,102)or Color3.fromRGB(238,233,217)
end
local function paintPreview()
 if not previewModel or not previewModel.Parent then return end
 for _,x in previewModel:GetDescendants()do if x:IsA('BasePart')then
  local region=x:GetAttribute('ColourRegion');local c
  if region=='white'then c=draft.eyes
  elseif region=='body'or region=='feet'or region=='stalks'or region=='rings'then c=draft.body end
  if c then local shade=x:GetAttribute('ColourShade')or 1;x.Color=Color3.new(math.clamp(c.R*shade,0,1),math.clamp(c.G*shade,0,1),math.clamp(c.B*shade,0,1))end
 end end
end
-- Dress the preview rig with the equipped wearables through the same CosmeticRig the server uses.
local CosmeticRig=require(RS:WaitForChild('CosmeticRig'))
local function dressPreview()
 if not previewModel or not previewModel.Parent then return end
 local old=previewModel:FindFirstChild('PreviewCosmetics');if old then old:Destroy()end
 local folder=Instance.new('Folder');folder.Name='PreviewCosmetics';folder.Parent=previewModel
 CosmeticRig.Wear(previewModel,progress.equipped or {},folder,progress.stages)
end
local function applyColour()
 local c=draft[activeRegion];if not c then return end
 if activeRegion=='light'then
  -- Flashlight beam colour: needs the Flashlight Colors pass; the server validates and saves it.
  if p:GetAttribute('Pass_flashlight_colors')~=true then notice('Unlock Flashlight Colors in the Store to change your beam colour.');return end
  local ev=RS:FindFirstChild('MonetizeEvent');if ev then ev:FireServer('setFlashlightColor',c)end
  notice('Flashlight colour applied.');return
 end
 RS.CharacterCustomColour:FireServer(activeRegion,math.round(c.R*255),math.round(c.G*255),math.round(c.B*255))
 notice('Colour applied.')
end
for _,region in {'body','eyes'}do
 draft[region]=getSaved(region)
 p:GetAttributeChangedSignal(region=='body'and 'BodyColourHex'or 'EyeColourHex'):Connect(function()
  local saved=getSaved(region)
  if not dirty[region]or draft[region]:ToHex()==saved:ToHex()then draft[region]=saved;dirty[region]=false end
  paintPreview();if pickerRefresh then pickerRefresh()end
 end)
end
local function pager(parent,name,page,total,x,y,width,change,targetHeight)
 local pages=math.max(1,total)
 local h=targetHeight or 32;local arrowW=targetHeight and math.max(40,h)or 40
 button(parent,name..'Previous','<',x,y,arrowW,h,function()change(math.max(1,page-1))end)
 local label=text(parent,name..'Page',page..' / '..pages,x+arrowW+4,y,width-2*(arrowW+4),h,13,colors.muted);label.TextXAlignment=Enum.TextXAlignment.Center
 button(parent,name..'Next','>',x+width-arrowW,y,arrowW,h,function()change(math.min(pages,page+1))end)
end
local function drawFriends(parent,x,y,w,h)
 local card=frame(parent,'Friends',x,y,w,h)
 button(card,'InviteFriends','INVITE FRIENDS',12,8,w-24,26,function()
  friendQuery='';request('friends',{query=''},function(data)friendResults=data.friends or {};friendPage=1;notice(#friendResults==0 and 'No friends available. Search by @username or display name.'or 'Create a 2–4 player party, then invite your friends below.');render()end)
 end,true)
 local box=input(card,'FriendSearch','@username or display name',friendQuery,12,40,w-74,34,function(v)friendQuery=v end)
 button(card,'SearchFriends','GO',w-56,40,44,34,function()
  friendQuery=box.Text;request('friends',{query=friendQuery},function(data)friendResults=data.friends or {};friendPage=1;notice(#friendResults==0 and 'No friends matched.'or 'Choose a friend to invite.');render()end)
 end,true)
 local rows=math.max(1,math.min(5,math.floor((h-120)/52)));local pages=math.max(1,math.ceil(#friendResults/rows));friendPage=math.clamp(friendPage,1,pages)
 if #friendResults==0 then text(card,'Empty','Find your friends and invite your crew.',12,82,w-24,math.max(26,h-128),15,colors.muted)
 else
  for index=(friendPage-1)*rows+1,math.min(#friendResults,friendPage*rows)do
   local friend=friendResults[index];local row=frame(card,'Friend_'..friend.id,12,82+(index-(friendPage-1)*rows-1)*52,w-24,46,colors.panel)
   local avatar=Instance.new('ImageLabel');avatar.Name='Avatar';avatar.Position=UDim2.fromOffset(6,5);avatar.Size=UDim2.fromOffset(36,36);avatar.BackgroundColor3=colors.ink;avatar.BorderSizePixel=0;avatar.Image='rbxthumb://type=AvatarHeadShot&id='..friend.id..'&w=150&h=150';avatar.Parent=row;corners(avatar,8)
   text(row,'Display',friend.display,50,3,w-156,22,15)
   text(row,'Username','@'..friend.username,50,24,w-156,17,11,colors.muted)
   button(row,'Invite','INVITE',w-100,7,68,32,function()if not party then notice('Create a 2–4 player party first, then invite your friend.');return end;request('invite',{userId=friend.id},function(data)notice(type(data)=='string'and data or 'Invite sent.')end)end)
  end
 end
 pager(card,'Friends',friendPage,pages,12,h-36,w-24,function(page)friendPage=page;render()end)
end
-- Controllers: put the selection straight on the save list (no extra Select/View press needed).
local function padFocus(target)
 local GS=game:GetService('GuiService')
 local last=UIS:GetLastInputType()
 if InputHints.Get()~='pad'or not target then return end
 task.defer(function()if target.Parent then GS.SelectedObject=target end end)
end
local focusCreateNext=false
local function drawSavePicker()
 local card=frame(bodyContent,'RunSaves',0,46,bodyW,bodyH-46)
 text(card,'Title',hostCircle and 'STEP 1: PICK A SAVE' or 'CHOOSE A SAVE',12,8,bodyW-24,26,20)
 if not saveSlots then
  if saveLoadError then
   -- Failed or timed out: say so and offer a retry instead of loading forever.
   text(card,'LoadError','Could not load your saves: '..tostring(saveLoadError),12,44,bodyW-24,40,14,colors.muted)
   local retry=button(card,'RetrySaves','RETRY',12,90,140,32,function()saveLoadError=nil;saveLoading=false;render()end,true)
   padFocus(retry)
  else
   text(card,'Loading','Loading your saves...',12,44,bodyW-24,24,14,colors.muted)
   if not saveLoading then
    saveLoading=true
    request('runSaves.list',{},function(data)
     saveLoading=false;saveLoadError=nil;saveSlots=type(data)=='table'and data.slots or{false,false,false}
     -- No saves at all (first visit, or every save deleted): make Run 1 and go straight to WHO PLAYS, no picking.
     local any=false;for i=1,3 do if saveSlots[i]then any=true end end
     if not any and hostCircle and type(data)=='table'then
      request('runSaves.create',{index=1,name='Run 1'},function(made)
       saveSlots=type(made)=='table'and made.slots or saveSlots;chosenSave={slot=1,mode='new'};saveOpen=false;hostStep='size';focusCreateNext=true
       notice('Your first save is ready. Choose who plays.');render()
      end,false,function()render()end)
      return
     end
     render()
    end,true,function(err)
     saveLoading=false;saveLoadError=err or 'Please try again.';if saveOpen then render()end
    end)
   end
  end
 else
  -- Rows share the space between the title and the BACK button, whatever the screen height.
  local cardH=bodyH-46;local backY=cardH-40
  local gap=compact and 4 or 6
  local rowH=math.min(80,math.floor((backY-6-40-gap*2)/3))
  local bw=compact and 70 or 86
  for i=1,3 do
   local s=saveSlots[i];local y=40+(i-1)*(rowH+gap)
   local row=frame(card,'Save'..i,12,y,bodyW-24,rowH,colors.panel)
   local selected=chosenSave and chosenSave.slot==i
   local infoW=bodyW-24-bw*2-34
   -- Two lines when the row is tall enough, otherwise the name only; text always stays inside the row.
   local twoLines=rowH>=44
   local nameH=twoLines and math.floor(rowH*.48)or rowH-4
   local nameLabel=text(row,'Name',(s and(s.name or('SAVE '..i))or('EMPTY SLOT '..i))..(selected and '  (SELECTED)'or ''),10,twoLines and 3 or 2,infoW,nameH,15,selected and colors.green or colors.cream)
   nameLabel.TextScaled=true;nameLabel.TextWrapped=false;local nameCap=Instance.new('UITextSizeConstraint');nameCap.MaxTextSize=15;nameCap.MinTextSize=8;nameCap.Parent=nameLabel
   if twoLines then
    local info=text(row,'Info',s and('Level '..(s.round or 1)..'  |  '..math.min(s.chances or 2,2)..'/2 chances'..(type(s.updatedAt)=='number'and('  |  saved '..os.date('%b %d %H:%M',s.updatedAt))or ''))or 'Start a brand-new run here.',10,3+nameH,infoW,rowH-nameH-6,12,colors.muted)
    info.TextScaled=true;info.TextWrapped=false;local infoCap=Instance.new('UITextSizeConstraint');infoCap.MaxTextSize=12;infoCap.MinTextSize=7;infoCap.Parent=info
   end
   local bh=math.min(32,rowH-6);local by=math.floor((rowH-bh)/2)
   if s then
    button(row,'Load','CONTINUE',bodyW-24-bw*2-16,by,bw,bh,function()chosenSave={slot=i,mode='load'};saveOpen=false;hostStep='size';focusCreateNext=true;notice('Save selected: '..(s.name or('Save '..i))..', level '..(s.round or 1)..'.');render()end,true).TextSize=compact and 12 or 14
    button(row,'Delete',confirmDelete==i and 'SURE?'or 'DELETE',bodyW-24-bw-8,by,bw,bh,function()
     if confirmDelete~=i then confirmDelete=i;notice('Press again to erase this save.');render();return end
     confirmDelete=nil;request('runSaves.delete',{index=i},function(data)saveSlots=type(data)=='table'and data.slots or saveSlots;if chosenSave and chosenSave.slot==i then chosenSave=nil end;notice('Save deleted.');render()end)
    end)
   else
    button(row,'New','NEW GAME',bodyW-24-bw*2-16,by,bw*2+8,bh,function()
     request('runSaves.create',{index=i,name='Run '..i},function(data)saveSlots=type(data)=='table'and data.slots or saveSlots;chosenSave={slot=i,mode='new'};saveOpen=false;hostStep='size';focusCreateNext=true;notice('New save made in slot '..i..'.');render()end)
    end,true)
   end
  end
 end
 local back=button(card,'Back',hostCircle and 'CANCEL' or 'BACK',12,bodyH-46-40,120,32,function()saveOpen=false;confirmDelete=nil;if hostCircle then cancelHost();return end;focusCreateNext=true;render()end)
 -- First selectable slot action (LOAD or NEW SAVE), else BACK while the list loads.
 local first
 for i=1,3 do local row=card:FindFirstChild('Save'..i);local b=row and(row:FindFirstChild('Load')or row:FindFirstChild('New'));if b then first=b;break end end
 padFocus(first or back)
end
local function drawPlay()
 if party then
  -- Joined or hosting: members are on the party bar; this page is for inviting friends.
  local card=frame(bodyContent,'PartyInfo',0,0,bodyW,92)
  text(card,'Title',(party.owner==p.UserId and 'YOUR RUN'or party.ownerDisplay.."'S RUN")..(party.circle and('  |  CIRCLE '..party.circle)or''),12,8,bodyW-24,26,20)
  text(card,'Info','Friends join by walking into your glowing box.  '..#party.members..' / '..party.size..' here.',12,40,bodyW-24,40,14,colors.muted)
  drawFriends(bodyContent,0,102,bodyW,bodyH-102)
  return
 end
 if not hostCircle then
  text(bodyContent,'Hint','Walk into a green glowing box to host a run, or into a purple one to join a run.',0,0,bodyW,80,18,colors.muted)
  return
 end
 -- Step tabs: SAVE first, then PLAYERS, then PRIVACY (later steps unlock once a save is chosen).
 local steps={{'save','1  PICK SAVE'},{'size','2  WHO PLAYS'},{'privacy','3  WHO CAN JOIN'}}
 for i,st in ipairs(steps)do
  local key=st[1]
  local b=button(bodyContent,'Step'..i,st[2],(i-1)*(bodyW+10)/3,0,(bodyW-20)/3,32,function()
   if key=='save'then hostStep='save';saveOpen=true;saveSlots=nil;render()
   elseif chosenSave then hostStep=key;render()else notice('Choose a save first.')end
  end,hostStep==key);b.TextSize=13
 end
 -- Plain next-step guidance under the header for first-time hosts (overwrites the last notice on purpose).
 if statusLabel then statusLabel.Text=hostStep=='save'and'Your level is kept in a save. New here? Press NEW GAME.'or hostStep=='size'and'Playing alone? Press JUST ME and the game starts.'or'Choose who can join, then press OPEN MY RUN.';statusLabel.TextColor3=colors.cream end
 if hostPending then text(bodyContent,'Opening','OPENING CIRCLE '..tostring(hostCircle)..'...',0,40,bodyW,40,22);return end
 if hostStep=='save'then saveOpen=true;drawSavePicker();return end
 local cardH=bodyH-46
 local card=frame(bodyContent,'HostSetup',0,46,bodyW,cardH)
 button(card,'CancelHost','CANCEL',12,cardH-46,120,34,function()cancelHost()end)
 if hostStep=='size'then
  text(card,'Title','PLAY SOLO OR WITH FRIENDS',12,8,bodyW-24,26,20)
  local cell=(bodyW-24-18)/4
  for n=1,4 do
   local b=button(card,'Size'..n,n==1 and 'JUST ME'or tostring(n),12+(n-1)*(cell+6),44,cell,64,function()
    chosenSize=n
    if n==1 then
     -- Solo: nobody to wait for, so skip privacy and go straight into the game.
     request('create',{size=1,friendsOnly=false,password='',save=chosenSave,circle=hostCircle},function(data)
      party=data.party;hostCircle=nil;hostStep='save';tab=nil;build()
      request('start',{},function(msg)notice(type(msg)=='string'and msg or 'Starting your run...')end)
     end)
     return
    end
    hostStep='privacy';render()
   end,chosenSize==n);b.TextSize=n==1 and 22 or 28
  end
  text(card,'Note','Play alone instantly, or invite up to 3 friends to survive together.',12,120,bodyW-24,44,14,colors.muted)
  padFocus(card:FindFirstChild('Size'..chosenSize))
 else
  text(card,'Title','STEP 3: WHO CAN JOIN?',12,8,bodyW-24,26,20)
  local third=(bodyW-24-12)/3
  local options={{'Public','PUBLIC',not friendsOnly and not privatePassword},{'Friends','FRIENDS ONLY',friendsOnly and not privatePassword},{'Password','PASSWORD',privatePassword}}
  for i,o in ipairs(options)do
   button(card,'Access'..o[1],o[2],12+(i-1)*(third+6),44,third,48,function()friendsOnly=o[1]=='Friends';privatePassword=o[1]=='Password';render()end,o[3]).TextSize=15
  end
  local pass=input(card,'PartyPassword',privatePassword and 'Type a password (4-40 characters)'or friendsOnly and 'Only your Roblox friends can join.'or 'Anyone in the lobby can walk in and join.',passwordValue,12,104,bodyW-24,38,function(v)passwordValue=v end,true);pass.TextEditable=privatePassword
  local create=button(card,'CreateParty','OPEN MY RUN  ('..chosenSize..(chosenSize==1 and ' PLAYER)'or ' PLAYERS)'),12,156,bodyW-24,48,function()
   passwordValue=pass.Text
   request('create',{size=chosenSize,friendsOnly=friendsOnly and not privatePassword,password=privatePassword and passwordValue or '',save=chosenSave,circle=hostCircle},function(data)
    party=data.party;hostCircle=nil;hostStep='save';tab=nil
    notice(chosenSize==1 and 'Your run is ready. Press START GAME.'or 'Run open. Friends walk into your box to join.');build()
   end)
  end,true);create.TextSize=17
  padFocus(create)
 end
end
local function drawJoin()
 local model=workspace:FindFirstChild('LobbyWorld')and workspace.LobbyWorld.Circles:FindFirstChild('Circle'..tostring(joinTarget))
 local card=frame(bodyContent,'JoinCircle',0,0,bodyW,190)
 text(card,'Title',model and((model:GetAttribute('OwnerName')or'A player').."'S RUN")or 'JOIN RUN',12,8,bodyW-24,26,20)
 text(card,'Info','This run needs a password.',12,40,bodyW-24,22,14,colors.muted)
 local box=input(card,'JoinPassword','Password',joinPassword,12,70,bodyW-24,38,function(v)joinPassword=v end,true)
 local go=button(card,'JoinRun','JOIN',12,120,bodyW-24,48,function()
  joinPassword=box.Text
  request('circle.join',{circle=joinTarget,password=joinPassword},function(data)party=data.party;joinTarget=nil;tab=nil;notice('Joined the run. Wait for the host to start.');build()end)
 end,true)
 padFocus(go)
end
local function audioSlider(parent,key,label,y,w)
 text(parent,key..'Title',label,12,y,w-74,23,16)
 local number=text(parent,key..'Percent',math.round(preferences[key]*100)..'%',w-58,y,46,23,13,colors.green)
 local track=frame(parent,key..'Track',50,y+30,w-100,9,colors.ink)
 local fill=Instance.new('Frame');fill.Name='Fill';fill.Size=UDim2.fromScale(preferences[key],1);fill.BackgroundColor3=colors.green;fill.BorderSizePixel=0;fill.Parent=track;corners(fill,4)
 local function change(v)updatePrefs(key,math.clamp(math.round(v*100)/100,0,1));number.Text=math.round(preferences[key]*100)..'%';fill.Size=UDim2.fromScale(preferences[key],1)end
 button(parent,key..'Minus','-',12,y+23,30,27,function()change(preferences[key]-.05)end)
 button(parent,key..'Plus','+',w-42,y+23,30,27,function()change(preferences[key]+.05)end)
 local hit=Instance.new('TextButton');hit.Name='Drag';hit.Text='';hit.BackgroundTransparency=1;hit.Position=UDim2.fromOffset(0,-12);hit.Size=UDim2.new(1,0,0,34);hit.Selectable=false;hit.Parent=track
 local drag,lastSend=false,0
 local function update(i)
  local value=math.clamp((i.Position.X-track.AbsolutePosition.X)/track.AbsoluteSize.X,0,1);preferences[key]=math.round(value*100)/100;p:SetAttribute('LocalSetting'..key,preferences[key]);fill.Size=UDim2.fromScale(preferences[key],1);number.Text=math.round(preferences[key]*100)..'%'
  if os.clock()-lastSend>.2 then lastSend=os.clock();request('preferences',preferences)end
 end
 hit.InputBegan:Connect(function(i)if i.UserInputType==Enum.UserInputType.MouseButton1 or i.UserInputType==Enum.UserInputType.Touch then drag=true;update(i)end end)
 local move=UIS.InputChanged:Connect(function(i)if drag and(i.UserInputType==Enum.UserInputType.MouseMovement or i.UserInputType==Enum.UserInputType.Touch)then update(i)end end)
 local finish=UIS.InputEnded:Connect(function(i)if drag and(i.UserInputType==Enum.UserInputType.MouseButton1 or i.UserInputType==Enum.UserInputType.Touch)then drag=false;request('preferences',preferences)end end)
 hit.Destroying:Once(function()move:Disconnect();finish:Disconnect()end)
end
local function drawSettings()
 local audioW=bodyW -- volume sliders are the whole settings page
 local audioH=compact and 250 or bodyH-44
 local card=frame(bodyContent,'AudioSettings',0,0,audioW,audioH)
 text(card,'Title','AUDIO',12,8,audioW-24,26,21)
 -- Phones and tablets: HIGH QUALITY is on by default (MobileQualityClient turns it off if the game lags); this toggles it.
 if InputHints.IsMobile()then
  local on=require(RS.HorrorPreferences).Get('MobileHighQuality')~=false
  button(card,'HighQuality',on and 'HIGH QUALITY: ON'or 'HIGH QUALITY: OFF',audioW-172,6,160,30,function()
   preferences.MobileHighQuality=not on;p:SetAttribute('LocalSettingMobileHighQuality',not on);request('preferences',preferences);render()
  end,on)
 end
 for i,row in {{'MasterVolume','Overall volume'},{'EffectsVolume','Sound effects'},{'MenuMusicVolume','Menu music'}}do audioSlider(card,row[1],row[2],42+(i-1)*55,audioW)end
 button(card,'TestSound','TEST SOUND',12,210,audioW-24,28,function()
  local pref=require(RS.HorrorPreferences)
  if pref.Get('MasterVolume')<=0 or pref.Get('EffectsVolume')<=0 then notice('Sound is muted. Raise Overall volume and Sound effects.');return end
  local sound=Audio.Test()
  if not sound then notice('Sound effects are busy. Try again in a moment.');return end
  notice('Playing a sound test. If it is silent, check Roblox volume and your output device.')
 end)
 button(bodyContent,'ResetSettings','RESET DEFAULTS',0,bodyH-34,bodyW,34,function()preferences=table.clone(defaults);for key,value in preferences do p:SetAttribute('LocalSetting'..key,value)end;request('preferences',preferences);render()end)
end
local function drawCharacter()
 local previewW=compact and bodyW or math.floor(bodyW*.39)
 local previewH=compact and 170 or bodyH
 local preview=frame(bodyContent,'CharacterPreview',0,0,previewW,previewH)
 text(preview,'Title','YOUR CHARACTER',12,8,previewW-24,25,19)
 local viewport=Instance.new('ViewportFrame');viewport.Name='Preview';viewport.BackgroundTransparency=1;viewport.Position=UDim2.fromOffset(6,36);viewport.Size=UDim2.fromOffset(previewW-12,math.max(30,math.floor(previewH*.45)-36));viewport.Ambient=Color3.fromRGB(200,210,190);viewport.LightColor=Color3.fromRGB(255,235,208);viewport.LightDirection=Vector3.new(-1,-1,-1);viewport.Parent=preview
 local world=Instance.new('WorldModel');world.Parent=viewport
 local template=RS:FindFirstChild('LobbyCharacterPreview');previewModel=template and template:Clone()
 if previewModel then
  previewModel.Parent=world;previewModel:PivotTo(CFrame.identity);paintPreview();dressPreview()
  local cf,size=previewModel:GetBoundingBox();local center=cf.Position
  local camera=Instance.new('Camera');camera.FieldOfView=35;camera.CFrame=CFrame.lookAt(center+Vector3.new(0,size.Y*.04,-math.max(size.Y*1.7,8)),center);camera.Parent=viewport;viewport.CurrentCamera=camera
 end
 local ownedTop=math.floor(previewH*.45)
 local ownedFrame=Instance.new('Frame');ownedFrame.Name='AppearanceInventory';ownedFrame.BackgroundTransparency=1;ownedFrame.Position=UDim2.fromOffset(10,ownedTop);ownedFrame.Size=UDim2.fromOffset(previewW-20,previewH-ownedTop-8);ownedFrame.Parent=preview
 Appearance.Draw(ownedFrame,progress,function(id,slot)request('appearanceEquip',{offer=id,slot=slot},function(data)progress=data.progress;notice(data.message);render()end)end)
 local x=compact and 0 or previewW+12;local y=compact and previewH+12 or 0
 local w=compact and bodyW or bodyW-previewW-12;local h=compact and bodyH-previewH-12 or bodyH
 local editor=frame(bodyContent,'ColourPicker',x,y,w,h)
 draft.light=draft.light or getSaved('light')
 local regionW=(w-36)/3
 button(editor,'BodyRegion','BODY',12,10,regionW,32,function()activeRegion='body';render()end,activeRegion=='body')
 button(editor,'EyeRegion','EYES',18+regionW,10,regionW,32,function()activeRegion='eyes';render()end,activeRegion=='eyes')
 button(editor,'LightRegion','LIGHT',24+regionW*2,10,regionW,32,function()activeRegion='light';render()end,activeRegion=='light')
 local hue,saturation,value=draft[activeRegion]:ToHSV()
 local squareH=math.max(72,h-182)
 local pickerEditing=false
 local square
 square=button(editor,'SaturationValue','',12,54,w-68,squareH,function()
  if UIS:GetLastInputType()==Enum.UserInputType.Keyboard or UIS:GetLastInputType().Name:find('Gamepad')then
   pickerEditing=not pickerEditing;notice(pickerEditing and 'Adjust colour with directions. Press B or Enter to finish.'or 'Colour ready to apply.')
  end
 end)
 square.BackgroundColor3=Color3.fromHSV(hue,1,1)
 local white=Instance.new('Frame');white.Name='Saturation';white.Size=UDim2.fromScale(1,1);white.BackgroundColor3=Color3.new(1,1,1);white.BorderSizePixel=0;white.Parent=square;corners(white,10)
 local whiteGradient=Instance.new('UIGradient');whiteGradient.Transparency=NumberSequence.new({NumberSequenceKeypoint.new(0,0),NumberSequenceKeypoint.new(1,1)});whiteGradient.Parent=white
 local black=Instance.new('Frame');black.Name='Value';black.Size=UDim2.fromScale(1,1);black.BackgroundColor3=Color3.new();black.BorderSizePixel=0;black.Parent=square;corners(black,10)
 local blackGradient=Instance.new('UIGradient');blackGradient.Rotation=90;blackGradient.Transparency=NumberSequence.new({NumberSequenceKeypoint.new(0,1),NumberSequenceKeypoint.new(1,0)});blackGradient.Parent=black
 local marker=Instance.new('Frame');marker.Name='Cursor';marker.AnchorPoint=Vector2.new(.5,.5);marker.Size=UDim2.fromOffset(12,12);marker.BackgroundTransparency=1;marker.ZIndex=4;marker.Parent=square;corners(marker,20);stroke(marker,colors.cream,2)
 local hueBar=button(editor,'Hue','',w-44,54,32,squareH,function()end)
 hueBar.BackgroundColor3=Color3.new(1,1,1)
 local hueGradient=Instance.new('UIGradient');hueGradient.Rotation=90
 local keys={};for i=0,6 do table.insert(keys,ColorSequenceKeypoint.new(i/6,Color3.fromHSV(i/6,1,1)))end;hueGradient.Color=ColorSequence.new(keys);hueGradient.Parent=hueBar
 local hueMarker=Instance.new('Frame');hueMarker.Name='Cursor';hueMarker.Size=UDim2.new(1,4,0,3);hueMarker.Position=UDim2.fromScale(0,hue);hueMarker.BackgroundColor3=colors.cream;hueMarker.BorderSizePixel=0;hueMarker.ZIndex=4;hueMarker.Parent=hueBar
 local brightness=button(editor,'Brightness','',100,h-116,w-112,18,function()end)
 text(editor,'BrightnessLabel','BRIGHTNESS',12,h-120,86,26,12)
 local brightnessGradient=Instance.new('UIGradient');brightnessGradient.Color=ColorSequence.new(Color3.new(),Color3.new(1,1,1));brightnessGradient.Parent=brightness;brightness.BackgroundColor3=Color3.new(1,1,1)
 local brightnessMarker=Instance.new('Frame');brightnessMarker.Name='Cursor';brightnessMarker.Size=UDim2.fromOffset(3,22);brightnessMarker.BackgroundColor3=colors.cream;brightnessMarker.BorderSizePixel=0;brightnessMarker.Parent=brightness
 local swatch=frame(editor,'SelectedColour',12,h-80,40,30,draft[activeRegion])
 local hex=text(editor,'Hex','',60,h-80,w-150,30,14)
 button(editor,'HueMinus','H-',w-84,h-80,32,30,function()hue=(hue-.04)%1;dirty[activeRegion]=true;draft[activeRegion]=Color3.fromHSV(hue,saturation,value);paintPreview();pickerRefresh()end).TextSize=13
 button(editor,'HuePlus','H+',w-46,h-80,32,30,function()hue=(hue+.04)%1;dirty[activeRegion]=true;draft[activeRegion]=Color3.fromHSV(hue,saturation,value);paintPreview();pickerRefresh()end).TextSize=13
 button(editor,'ApplyColour','APPLY COLOUR',12,h-40,w-108,30,applyColour,true)
 button(editor,'ResetColour','RESET',w-88,h-40,76,30,function()draft[activeRegion]=getSaved(activeRegion);dirty[activeRegion]=false;paintPreview();pickerRefresh()end)
 local function refresh()
  local nextHue,nextSaturation,nextValue=draft[activeRegion]:ToHSV()
  if nextSaturation>0 and nextValue>0 then hue=nextHue end
  if nextValue>0 then saturation=nextSaturation end
  value=nextValue
  square.BackgroundColor3=Color3.fromHSV(hue,1,1);marker.Position=UDim2.fromScale(saturation,1-value);hueMarker.Position=UDim2.fromScale(0,hue)
  brightnessMarker.Position=UDim2.new(value,-1,0,-2)
  swatch.BackgroundColor3=draft[activeRegion];hex.Text='#'..string.upper(draft[activeRegion]:ToHex())
 end
 pickerRefresh=refresh;refresh()
 local function setColor()dirty[activeRegion]=true;draft[activeRegion]=Color3.fromHSV(hue,saturation,value);paintPreview();refresh()end
 local dragTarget,touch
 local function pointer(i)
  if dragTarget=='Square'then saturation=math.clamp((i.Position.X-square.AbsolutePosition.X)/square.AbsoluteSize.X,0,1);value=1-math.clamp((i.Position.Y-square.AbsolutePosition.Y)/square.AbsoluteSize.Y,0,1)
  elseif dragTarget=='Brightness'then value=math.clamp((i.Position.X-brightness.AbsolutePosition.X)/brightness.AbsoluteSize.X,0,1)
  elseif dragTarget=='Hue'then hue=math.clamp((i.Position.Y-hueBar.AbsolutePosition.Y)/hueBar.AbsoluteSize.Y,0,.99999)end
  setColor()
 end
 local function begin(target,i)if i.UserInputType==Enum.UserInputType.MouseButton1 or i.UserInputType==Enum.UserInputType.Touch then dragTarget=target;touch=i;pointer(i)end end
 brightness.InputBegan:Connect(function(i)begin('Brightness',i)end)
 square.InputBegan:Connect(function(i)begin('Square',i)end);hueBar.InputBegan:Connect(function(i)begin('Hue',i)end)
 local selection=GuiService:GetPropertyChangedSignal('SelectedObject'):Connect(function()
  if pickerEditing and GuiService.SelectedObject~=square then task.defer(function()if pickerEditing and square.Parent then GuiService.SelectedObject=square end end)end
 end)
 local move=UIS.InputChanged:Connect(function(i)if dragTarget and(i.UserInputType==Enum.UserInputType.MouseMovement or i==touch)then pointer(i)end end)
 local finish=UIS.InputEnded:Connect(function(i)if i==touch or i.UserInputType==Enum.UserInputType.MouseButton1 then dragTarget=nil;touch=nil end end)
 local adjust=UIS.InputBegan:Connect(function(i)
  if not pickerEditing then return end
  local key=i.KeyCode
  if key==Enum.KeyCode.ButtonB then pickerEditing=false;GuiService.SelectedObject=editor.ApplyColour;notice('Colour ready to apply.');return end
  if key==Enum.KeyCode.Left or key==Enum.KeyCode.DPadLeft then saturation=math.max(0,saturation-.04)
  elseif key==Enum.KeyCode.Right or key==Enum.KeyCode.DPadRight then saturation=math.min(1,saturation+.04)
  elseif key==Enum.KeyCode.Up or key==Enum.KeyCode.DPadUp then value=math.min(1,value+.04)
  elseif key==Enum.KeyCode.Down or key==Enum.KeyCode.DPadDown then value=math.max(0,value-.04)
  else return end
  setColor()
 end)
 editor.Destroying:Once(function()pickerEditing=false;selection:Disconnect();move:Disconnect();finish:Disconnect();adjust:Disconnect();if pickerRefresh==refresh then pickerRefresh=nil end end)
end
local function statValue(id,value)
 if id=='FastestClearMs'then if value==0 then return '--'end;return ('%d:%05.2f'):format(math.floor(value/60000),(value%60000)/1000)end
 if id=='TotalRetrieved'or id=='BestHaul'then return '$'..value end
 if id=='CollectionPercent'then return tostring(value)..'%'end
 return tostring(value)
end
local function fetchBoard(id)
 boardCategory=id;boardPage=1;boardRows={};boardLoading=true;render()
 request('leaderboard',{category=id},function(data)
  if boardCategory~=data.category then return end
  boardRows=data.rows or {};boardLoading=false;render()
 end)
end
local function drawLeaders()
 local cols=3;local cell=(bodyW-12)/3
 for i,cat in Shop.Categories do
  button(bodyContent,'Board'..cat.id,cat.label,((i-1)%cols)*(cell+6),math.floor((i-1)/cols)*36,cell,30,function()fetchBoard(cat.id)end,boardCategory==cat.id).TextSize=12
 end
 local own=(progress.stats or {})[boardCategory]or 0
 text(bodyContent,'PersonalBest','YOUR RECORD: '..statValue(boardCategory,own),0,76,bodyW-95,26,14,colors.green)
 button(bodyContent,'RefreshBoard','REFRESH',bodyW-88,74,88,28,function()fetchBoard(boardCategory)end).TextSize=12
 local card=frame(bodyContent,'LeaderboardRows',0,112,bodyW,bodyH-112)
 local rows=math.max(1,math.floor((bodyH-160)/44));local pages=math.max(1,math.ceil(#boardRows/rows));boardPage=math.clamp(boardPage,1,pages)
 if #boardRows==0 then
  local message=boardLoading and 'LOADING RECORDS...'or 'NO RECORDS YET\nComplete an extraction to set your record.'
  local label=text(card,'Empty',message,12,16,bodyW-24,math.max(40,bodyH-190),18,colors.muted);label.TextXAlignment=Enum.TextXAlignment.Center
 else
  for i=(boardPage-1)*rows+1,math.min(#boardRows,boardPage*rows)do
   local entry=boardRows[i];local row=frame(card,'Rank'..i,10,10+(i-(boardPage-1)*rows-1)*44,bodyW-20,38,colors.panel)
   text(row,'Rank','#'..entry.rank,8,0,36,38,14,colors.green)
   local avatar=Instance.new('ImageLabel');avatar.Name='Avatar';avatar.BackgroundTransparency=1;avatar.Position=UDim2.fromOffset(48,4);avatar.Size=UDim2.fromOffset(30,30);avatar.Image='rbxthumb://type=AvatarHeadShot&id='..entry.id..'&w=150&h=150';avatar.Parent=row;corners(avatar,8)
   local nameLabel=text(row,'Player',entry.name,86,0,bodyW-220,38,14)
   local tagInfo=require(game:GetService('ReplicatedStorage'):WaitForChild('CustomTags')).Get(entry.id)
   if tagInfo and tagInfo.icon then local icon=Instance.new('ImageLabel');icon.Name='TagIcon';icon.BackgroundTransparency=1;icon.AnchorPoint=Vector2.new(0,.5);icon.Size=UDim2.fromOffset(24,24);icon.Image=tagInfo.icon;icon.Parent=nameLabel;task.defer(function()icon.Position=UDim2.new(0,nameLabel.TextBounds.X+6,.5,0)end)end
   local value=text(row,'Value',statValue(boardCategory,entry.value),bodyW-126,0,98,38,14,colors.green);value.TextXAlignment=Enum.TextXAlignment.Right
  end
 end
 pager(card,'Leaderboard',boardPage,pages,10,bodyH-150,bodyW-20,function(page)boardPage=page;render()end)
end
local Marketplace=game:GetService('MarketplaceService')
local robuxPrices,priceLoading,robuxAvailable={},{},{}
local function displayRobuxPrice(offer)
 if robuxPrices[offer.id]~=nil then return robuxPrices[offer.id]end
 if not priceLoading[offer.id]then priceLoading[offer.id]=true;task.spawn(function()
  local ok,info=pcall(function()return Marketplace:GetProductInfoAsync(offer.assetId,offer.kind=='Pass'and Enum.InfoType.GamePass or Enum.InfoType.Product)end)
  robuxPrices[offer.id]=ok and(info.PriceInRobux or offer.price)or(Run:IsStudio()and offer.price or false)
  robuxAvailable[offer.id]=ok and info.IsForSale==true
  if tab=='Store'and shopTab=='Robux'then render()end
 end)end
 return nil
end
local storeQuietUntil=0
local function drawStore()
 button(bodyContent,'TokenShop','TOKEN SHOP',0,0,(bodyW-10)/2,36,function()shopTab='Tokens';shopPage=1;storePopPending=true;render()end,shopTab=='Tokens')
 button(bodyContent,'RobuxShop','ROBUX SHOP',(bodyW+10)/2,0,(bodyW-10)/2,36,function()shopTab='Robux';shopPage=1;storePopPending=true;render()end,shopTab=='Robux')
 storeCells={}
 local storeBack=Instance.new('Frame');storeBack.Name='StoreBackplate';storeBack.Size=UDim2.fromScale(1,1);storeBack.BackgroundColor3=UI.Color.plate;storeBack.BorderSizePixel=0;storeBack.ZIndex=0;storeBack.Parent=bodyContent;UI.corner(storeBack,16)
 local robux=shopTab=='Robux'
 text(bodyContent,'TokenBalance',robux and ('REVIVE TOKENS: '..(progress.reviveTokens or 0))or('TOKENS: '..(progress.tokens or 0)),0,44,bodyW,25,19,colors.green)
 text(bodyContent,'EarnTokens',robux and 'Permanent passes · Saved consumables · Roblox purchase confirmation'or('+'..(progress.passes and progress.passes.double_tokens and 50 or 25)..' tokens per extraction · Permanent upgrades & cosmetics'),0,74,bodyW,32,12,colors.muted)
 local offers=robux and Shop.RobuxOffers or Shop.TokenOffers
 local phoneShop=layoutScale<.85
 local touchH=phoneShop and math.ceil(40/layoutScale)or 32
 local rows=phoneShop and((bodyW-10)*layoutScale/2>=180 and 2 or 1)or compact and 2 or lowWide and 5 or 4
 storeColumns=rows
 local pages=math.max(1,math.ceil(#offers/rows));shopPage=math.clamp(shopPage,1,pages)
 local cardTop=lowWide and 68 or 108;local cardH=bodyH-cardTop-(phoneShop and touchH+8 or 40)
 local gap=10;local cardW=(bodyW-gap*(rows-1))/rows
 if lowWide then bodyContent.EarnTokens.Visible=false;bodyContent.TokenBalance.Position=UDim2.fromOffset(0,40);bodyContent.TokenBalance.TextSize=15 end
 for i=(shopPage-1)*rows+1,math.min(#offers,shopPage*rows)do
  local offer=offers[i];local tier=progress.upgrades and progress.upgrades[offer.stat]or 0;local upgrade=offer.kind=='Upgrade'
  local owned=robux and progress.passes and progress.passes[offer.id]or(not robux and progress.owned and progress.owned[offer.id])
  local grant=offer.grants and Shop.ById[offer.grants] -- Robux pass that unlocks a wearable cosmetic
  local equipped=progress.equipped and(offer.id=='vip'and progress.equipped.Title=='title_vip'and progress.equipped.Aura=='aura_vip'or grant and progress.equipped[grant.kind]==grant.id or progress.equipped[offer.kind]==offer.id)
  local cost=upgrade and Shop.UpgradeCostFor(offer.stat,tier,p:GetAttribute('ShopTutorialStep'))or offer.price
  local actualPrice=robux and displayRobuxPrice(offer)
  local maxed=upgrade and tier>=#Shop.UpgradeCosts
  local column=i-(shopPage-1)*rows-1
  local colour=Color3.fromRGB(unpack(offer.color))
  local cell=Instance.new('Frame');cell.Name='StoreCell_'..offer.id;cell.LayoutOrder=column;cell.BackgroundTransparency=1;cell.Position=UDim2.fromOffset(column*(cardW+gap),cardTop);cell.Size=UDim2.fromOffset(cardW,cardH);cell.Parent=bodyContent;table.insert(storeCells,cell)
  local popCard=Instance.new('Frame');popCard.Name='Card';popCard.AnchorPoint=Vector2.new(.5,.5);popCard.Position=UDim2.fromScale(.5,.5);popCard.Size=UDim2.fromScale(1,1);popCard.BackgroundTransparency=1;popCard.Parent=cell
  local pop=Instance.new('UIScale');pop.Name='Pop';pop.Parent=popCard
  local card=frame(popCard,'Offer_'..offer.id,0,0,cardW,cardH,Color3.new(1,1,1))
  local rim=card:FindFirstChildOfClass('UIStroke');rim.Color=colour;rim.Thickness=1.5;rim.Transparency=.45
  local tint=Instance.new('UIGradient');tint.Rotation=125;tint.Color=ColorSequence.new(colour:Lerp(UI.Color.cardLow,.55),UI.Color.card);tint.Parent=card
  local badgeSize=math.min(cardW-16,cardH*(lowWide and .25 or .42))
  local badge=frame(card,'Badge',(cardW-badgeSize)/2,lowWide and 5 or 10,badgeSize,badgeSize,colour)
  badge.BackgroundTransparency=.78;local round=badge:FindFirstChildOfClass('UICorner');round.CornerRadius=UDim.new(1,0);local badgeRim=badge:FindFirstChildOfClass('UIStroke');badgeRim.Color=colour;badgeRim.Thickness=2;badgeRim.Transparency=.25
  local symbol=offer.stat=='Speed'and'SPD'or offer.stat=='Stamina'and'STA'or offer.stat=='Flashlight'and'LUX'or offer.id=='infinite_stamina'and'∞'or offer.id=='double_speed'and'2×'or offer.id=='double_tokens'and'2×'or offer.id:find('revive')and'+'or offer.kind=='Aura'and'✦'or offer.kind=='Title'and'TTL'or(grant or offer).kind=='Hat'and'HAT'or(grant or offer).kind=='Ring'and'RING'or(grant or offer).kind=='Shirt'and'INK'or(grant or offer).kind=='Shoes'and'KICK'or'VIP'
  local badgeText=text(badge,'Symbol',symbol,0,0,badgeSize,badgeSize,lowWide and 10 or 18,colors.ink);badgeText.TextXAlignment=Enum.TextXAlignment.Center;badgeText.TextScaled=true;local badgeLimit=Instance.new('UITextSizeConstraint');badgeLimit.MinTextSize=5;badgeLimit.MaxTextSize=18;badgeLimit.Parent=badgeText;badgeText.FontFace=UI.Font.Display;badgeText.TextColor3=UI.Color.text;UI.outline(badgeText,1.4)
  if offer.image then
   local art=Instance.new('ImageLabel');art.Name='OfferArtwork';art.BackgroundTransparency=1;art.Size=UDim2.fromScale(1,1);art.Image=offer.image;art.ScaleType=Enum.ScaleType.Fit;art.Parent=badge
   local rounding=Instance.new('UICorner');rounding.CornerRadius=UDim.new(0,12);rounding.Parent=art
   badgeText.Visible=not art.IsLoaded
   art:GetPropertyChangedSignal('IsLoaded'):Connect(function()badgeText.Visible=not art.IsLoaded end)
  end
  local nameY=(lowWide and 5 or 10)+badgeSize+8;local nameH=lowWide and(workspace.CurrentCamera.ViewportSize.Y<420 and 20 or 28)or 44
  local nameLabel=text(card,'Name',(lowWide and upgrade and(offer.stat:upper()..'\n'..tier..' / 4')or offer.name:upper()..(upgrade and('\nTIER '..tier..' / 4')or'')),8,nameY,cardW-16,nameH,lowWide and 11 or compact and 15 or 14);nameLabel.TextXAlignment=Enum.TextXAlignment.Center;nameLabel.TextWrapped=true;nameLabel.TextScaled=true;local nameLimit=Instance.new('UITextSizeConstraint');nameLimit.MinTextSize=7;nameLimit.MaxTextSize=lowWide and 11 or 16;nameLimit.Parent=nameLabel;nameLabel.FontFace=UI.Font.Display;nameLabel.TextColor3=UI.Color.text;UI.outline(nameLabel,1.4)
  if phoneShop then
   badge.Position=UDim2.fromOffset(8,8)
   local nameHeight=math.ceil(32/layoutScale)
   nameLabel.Position=UDim2.fromOffset(badgeSize+20,8);nameLabel.Size=UDim2.fromOffset(cardW-badgeSize-28,nameHeight)
   nameLimit.MinTextSize=12;nameLimit.MaxTextSize=18
  end
  local desc=offer.description
  if upgrade then
   local values=Shop.UpgradeStats[offer.stat];local v=values[tier+1]
   desc=offer.stat=='Speed'and(v[1]..' walk / '..v[2]..' sprint\nMax: 16 / 26')or offer.stat=='Stamina'and(v..' stamina\nMax: 200')or(v..'x brightness\n'..'36'..' stud reach')
  end
  if lowWide and robux then
   local short={infinite_stamina='Unlimited sprint.\nPermanent.',double_speed='2x walk and sprint.\nPermanent.',free_revive='1 free revive\nevery level.',revive_token='1 saved revive.\nCarries over.',revive_pack_3='3 saved revives.\nCarries over.',instant_win='1 saved clear charge.\nUSE it in the van.',double_tokens='50 tokens per extraction.',vip='Exclusive title + aura.'}
   desc=short[offer.id]or desc
  elseif lowWide and not upgrade then desc=offer.kind=='Title'and'Permanent survivor title.'or offer.kind=='Aura'and'Permanent cosmetic aura.'or offer.kind=='Shirt'and'Permanent belly tattoo.'or('Permanent '..offer.kind:lower()..' cosmetic.')end
  -- Staged cosmetics (WorldB): a locked one says what unlocks it; an owned one says which look it is on and what is next.
  local lockText=not robux and not owned and progress.stageStats and Shop.CosmeticLocked and Shop.CosmeticLocked(offer,progress.stageStats)or nil
  if lockText then desc=lockText
  elseif not robux and offer.stages and progress.stageStats and Shop.CosmeticStage then
   local look=Shop.CosmeticStage(offer,progress.stageStats);local st=offer.stages
   desc=(desc or '')..'\nNow: '..(st.names and st.names[look] or ('look '..look))..' ('..look..' of '..#st.at..')'..(st.next and st.next[look] and ('. Next look at '..st.next[look]..'.')or '')
  end
  local descY=nameY+nameH+5
  local descLabel=text(card,'Description',desc,8,descY,cardW-16,math.max(12,cardH-descY-(lowWide and 54 or 82)),lowWide and 10 or 12,colors.muted);descLabel.Visible=not(lowWide and workspace.CurrentCamera.ViewportSize.Y<420);descLabel.TextXAlignment=Enum.TextXAlignment.Center;descLabel.TextWrapped=true;descLabel.TextScaled=true;local descLimit=Instance.new('UITextSizeConstraint');descLimit.MinTextSize=7;descLimit.MaxTextSize=12;descLimit.Parent=descLabel;descLabel.FontFace=UI.Font.Body;descLabel.TextColor3=UI.Color.muted;descLabel.Visible=descLabel.Visible and not phoneShop
  local priceText=robux and(owned and 'OWNED'or actualPrice and('R$ '..actualPrice)or actualPrice==false and 'UNAVAILABLE'or'LOADING PRICE…')or(maxed and'MAXED'or owned and'OWNED'or(cost..' TOKENS'))
  if lockText then priceText='LOCKED - '..tostring(cost)..' TOKENS' end
  local priceLabel=text(card,'Price',priceText,6,cardH-(lowWide and 51 or 72),cardW-12,lowWide and 18 or 24,lowWide and 10 or 13,colors.green);priceLabel.TextXAlignment=Enum.TextXAlignment.Center;priceLabel.TextScaled=true;local priceLimit=Instance.new('UITextSizeConstraint');priceLimit.MinTextSize=5;priceLimit.MaxTextSize=13;priceLimit.Parent=priceLabel;priceLabel.FontFace=UI.Font.Display;priceLabel.TextColor3=UI.Color.gold;UI.outline(priceLabel,1.3)
  if phoneShop then
   priceLabel.Position=UDim2.fromOffset(8,math.ceil(32/layoutScale)+12);priceLabel.Size=UDim2.fromOffset(cardW-16,math.ceil(18/layoutScale))
   priceLimit.MinTextSize=12;priceLimit.MaxTextSize=16
  end
  local wearable=(grant or offer);wearable=table.find(Shop.CosmeticSlots,wearable.kind)and wearable
  local buyButton=shopButton(card,'Buy',owned and wearable and(equipped and 'EQUIPPED'or 'EQUIP')or owned and 'OWNED'or maxed and 'MAXED'or upgrade and 'UPGRADE'or robux and(robuxAvailable[offer.id]and 'BUY'or 'UNAVAILABLE')or 'UNLOCK',8,cardH-(lowWide and 30 or 42),cardW-16,lowWide and 24 or 34,function()
   if not progress.ready then notice('Wait for your saved data to load.');return end
   if owned and wearable then request('appearanceEquip',{offer=equipped and ''or wearable.id,slot=wearable.kind},function(data)progress=data.progress;notice(data.message);render()end);return end
   if owned then notice('Already unlocked. Equip it from Character → Owned Cosmetics.');return end
   if maxed then notice('This upgrade is already maxed.');return end
   if robux and offer.giftRevive then notice('Gift a Revive is bought during a game: when a teammate dies, open the ROBUX panel in the van, press BUY on Gift a Revive and pick who to bring back.');return end
   if robux then
    if not actualPrice or not robuxAvailable[offer.id]then notice('This offer is not available yet.');return end
    local ok=pcall(function()if offer.kind=='Pass'then Marketplace:PromptGamePassPurchase(p,offer.assetId)else Marketplace:PromptProductPurchase(p,offer.assetId)end end)
    if not ok then notice('Roblox purchases are unavailable right now.')end;return
   end
   local function buy()request('purchase',{offer=offer.id},function(data)progress=data.progress;notice(data.message);storeQuietUntil=os.clock()+2;render()end)end
   -- Short on tokens (owner 2026-10-27): offer the smallest token pack that covers it; the purchase finishes when they arrive.
   if cost and(progress.tokens or 0)<cost then
    local pack,short=require(game:GetService('ReplicatedStorage'):WaitForChild('TokenTopUp')).Offer(cost,progress.tokens,buy)
    if pack then notice(('You need %d more tokens. The %s pack covers it, and this finishes as soon as they arrive.'):format(short,pack.name));return end
   end
   buy()
  end,not owned and not maxed or wearable and owned and not equipped)
  if wearable and equipped then card:FindFirstChildOfClass('UIStroke').Color=colors.green end
  buyButton.TextScaled=true;local buyLimit=buyButton:FindFirstChildOfClass('UITextSizeConstraint')or Instance.new('UITextSizeConstraint');buyLimit.MinTextSize=6;buyLimit.MaxTextSize=13;buyLimit.Parent=buyButton
  if lowWide then local pad=buyButton:FindFirstChildOfClass('UIPadding');if pad then pad.PaddingTop=UDim.new(0,2);pad.PaddingBottom=UDim.new(0,2)end end
  if phoneShop then
   buyButton.Position=UDim2.fromOffset(8,cardH-touchH-6);buyButton.Size=UDim2.fromOffset(cardW-16,touchH)
   buyLimit.MinTextSize=12;buyLimit.MaxTextSize=18
  end
 end
 pager(bodyContent,'Shop',shopPage,pages,0,bodyH-touchH,bodyW,function(page)shopPage=page;render()end,phoneShop and touchH or nil)
end
-- How to Play: real in-game shots (no HUD) with a plain-language walkthrough of one level.
local GUIDE={
 {title='THE JOB',image='rbxassetid://87708580292288',body='You and up to three friends are an anomaly recovery crew. Every level starts in the back of the van. The board on the wall shows the level, the money your team has sold and the quota you must reach. The cart parked beside you is how you bring loot home.'},
 {title='EXPLORE',image='rbxassetid://81669469944858',body={kb='Walk into the mansion and search it room by room. Press F to switch your flashlight on and hold Shift to sprint. Your stamina bar is at the bottom left. Press E to open doors and drawers. Keys you find open locked doors.',pad='Walk into the mansion and search it room by room. Press B to switch your flashlight on and click the left stick to sprint. Your stamina bar is at the bottom left. Press X to open doors and drawers. Keys you find open locked doors.',touch='Walk into the mansion and search it room by room. Tap the flashlight button to light the way and tap RUN to sprint. Your stamina bar is at the bottom left. Aim at a door or drawer and tap OPEN DOOR or OPEN DRAWER. The button changes to CLOSE when it is open. Keys you find open locked doors.'}},
 {title='FIND LOOT',image='rbxassetid://92033552387060',body='Cursed loot sits on tables, shelves and floors. Get close and each item shows its name and how many dollars it is worth. Grab the valuable things first so your team reaches the quota sooner.'},
 {title='CARRY IT',image='rbxassetid://86133121534016',body={kb='Hold left click on an item to pick it up and keep holding to carry it. Let go to drop it. Scroll up to hold it further away and down to pull it closer. Most loot is cursed and changes you while you hold it: crying, burning eyes, swollen faces and stranger things. Some items do something the moment you grab them. Holding a cursed item near water washes it clean.',pad='Hold RT on an item to pick it up and keep holding to carry it. Let go of RT to drop it. Most loot is cursed and changes you while you hold it: crying, burning eyes, swollen faces and stranger things. Some items do something the moment you grab them. Holding a cursed item near water washes it clean.',touch='Aim at an item and tap GRAB to pick it up. Tap DROP to put it down. Most loot is cursed and changes you while you hold it: crying, burning eyes, swollen faces and stranger things. Some items do something the moment you grab them.'}},
 {title='LOAD THE CART',image='rbxassetid://104525918495959',body={kb='Let go of loot over the cart to drop it in, then hold left click on the cart to push it. Everything inside rides along, so one trip with a full cart beats many trips with your hands full. Keep the cart out of the way of creatures.',pad='Let go of loot over the cart to drop it in, then hold RT on the cart to push it. Everything inside rides along, so one trip with a full cart beats many trips with your hands full. Keep the cart out of the way of creatures.',touch='Drop loot into the cart, then aim at the cart and tap GRAB to push it. Tap DROP to let go. Everything inside rides along, so one trip with a full cart beats many trips with your hands full.'}},
 {title='SELL AND LEAVE',image='rbxassetid://107169339054581',body='Push the cart up to the van and leave it there while it sells. Once the board reaches the quota, everyone still alive climbs into the van and waits out the countdown to clear the level. Every level has a timer and a bigger quota. Clearing runs earns tokens for the Store.'},
 {title='STAY ALIVE',image='rbxassetid://139023300337438',body='Creatures roam the halls and follow noise. Talking and sprinting leave a trail. Keep your light on, stick together and hide in a closet if one gets close. If you die you spectate until your team clears the level, or use a revive. If everyone dies, your team retries the same level. A save gets 2 tries at a level; lose both and it starts over as a new save at level 1.'},
 {title='CROUCH',image='rbxassetid://139023300337438',body={kb='Press C or Left Ctrl to crouch. Your whole belly flattens into a spinning disc, you move at half speed and you cannot sprint or jump. Crouch walks under desks and tables: stay tucked under one for a second and creatures lose track of you. Press C again to stand once you are out from under it.',pad='Click the right stick to crouch. Your whole belly flattens into a spinning disc, you move at half speed and you cannot sprint or jump. Crouch walks under desks and tables: stay tucked under one for a second and creatures lose track of you. Click the right stick again to stand once you are out from under it.',touch='Tap CROUCH to crouch. Your whole belly flattens into a spinning disc, you move at half speed and you cannot sprint or jump. Crouch walks under desks and tables: stay tucked under one for a second and creatures lose track of you. Tap STAND once you are out from under it.'}},
}
table.insert(GUIDE,{title='Badges',badges=true})
local guidePage=1
local function guideDevice()
 return InputHints.Get()
end
local lastGuideDevice
InputHints.Changed:Connect(function()
 local d=guideDevice();if d~=lastGuideDevice then lastGuideDevice=d;if tab=='Guide'and render then render()end end
end)
local function guideBody(entry)
 local device=guideDevice()
 local body=type(entry.body)=='table'and(entry.body[device]or entry.body.kb)or entry.body
 return device=='pad'and InputHints.PadText(body)or body -- RT on Xbox, R2 on PlayStation
end
local function drawGuide()
 local entry=GUIDE[guidePage]
 local listW=compact and 0 or 190
 local x=compact and 0 or listW+12;local w=bodyW-x
 if compact then
  button(bodyContent,'GuidePrev','<',0,0,44,34,function()guidePage=(guidePage-2)%#GUIDE+1;render()end)
  text(bodyContent,'GuideStep',guidePage..' / '..#GUIDE..'  '..entry.title,54,4,w-108,28,17).TextXAlignment=Enum.TextXAlignment.Center
  button(bodyContent,'GuideNext','>',w-44,0,44,34,function()guidePage=guidePage%#GUIDE+1;render()end)
 else
  local rowH=math.floor((bodyH-6*6)/#GUIDE)
  for i,topic in GUIDE do
   local b=button(bodyContent,'Guide'..i,i..'. '..topic.title,0,(i-1)*(rowH+6),listW,rowH,function()guidePage=i;render()end,i==guidePage)
   b.TextXAlignment=Enum.TextXAlignment.Left;local pad=Instance.new('UIPadding');pad.PaddingLeft=UDim.new(0,12);pad.Parent=b
  end
 end
 local top=compact and 44 or 0
 if entry.badges then
  local badges=progress.badges or {}
  local HEADER_HEIGHT,ROW_GAP=36,6
  text(bodyContent,'BadgeHeading',(badges[1] and badges[1].preview and 'BADGES - STUDIO PREVIEW' or 'YOUR RECOVERY RECORD'),x,top,w,28,20,colors.green)
  if #badges==0 then text(bodyContent,'BadgeLoading','Loading your badges...',x,top+HEADER_HEIGHT,w,40,16);return end
  local rowH=math.max(30,math.floor((bodyH-top-HEADER_HEIGHT-(#badges-1)*ROW_GAP)/#badges))
  for i,b in badges do
   local rowY=top+HEADER_HEIGHT+(i-1)*(rowH+ROW_GAP)
   local row=frame(bodyContent,'Badge_'..b.key,x,rowY,w,rowH,colors.card)
   local iconSize=math.min(56,rowH-8)
   local textX=10
   if (b.iconId or 0)>0 then
    local icon=Instance.new('ImageLabel');icon.Name='Icon';icon.BackgroundTransparency=1;icon.Position=UDim2.fromOffset(6,4);icon.Size=UDim2.fromOffset(iconSize,iconSize);icon.Image='rbxassetid://'..b.iconId;icon.Parent=row
    textX=iconSize+14
   end
   local textWidth=w-textX-10
   local label=(b.earned and 'EARNED' or b.eligible and 'READY' or tostring(b.value)..' / '..tostring(b.goal))
   local title=text(row,'Title',b.name..'  -  '..label,textX,2,textWidth,math.max(16,math.floor(rowH*.48)),18,b.earned and colors.green or colors.cream)
   title.TextScaled=true;local limit=Instance.new('UITextSizeConstraint');limit.MinTextSize=10;limit.MaxTextSize=GuiService:IsTenFootInterface()and 22 or 18;limit.Parent=title
   local desc=text(row,'Goal',b.description,textX,math.floor(rowH*.5),textWidth,math.floor(rowH*.5)-2,13)
   desc.TextScaled=true;local dl=Instance.new('UITextSizeConstraint');dl.MinTextSize=9;dl.MaxTextSize=14;dl.Parent=desc
  end
  return
 end
 -- Short landscape screens (phones) put the text beside the shot; otherwise the shot sits above the text.
 local beside=lowWide
 local imageW=beside and math.floor(w*.52)or w
 local imageH=math.floor(imageW*9/16)
 local shot=Instance.new('ImageLabel');shot.Name='GuideShot';shot.Image=entry.image;shot.ScaleType=Enum.ScaleType.Crop;shot.BackgroundColor3=colors.ink;shot.BorderSizePixel=0;shot.Position=UDim2.fromOffset(x,top);shot.Size=UDim2.fromOffset(imageW,imageH);shot.Parent=bodyContent;corners(shot,12);stroke(shot)
 local textX=beside and x+imageW+12 or x;local textW=beside and w-imageW-12 or w
 local textTop=beside and top or top+imageH+10
 if not compact then text(bodyContent,'GuideTitle',entry.title,textX,textTop,textW,26,20,colors.green);textTop+=28 end
 local body=text(bodyContent,'GuideBody',guideBody(entry),textX,textTop,textW,bodyH-textTop,15)
 body.TextYAlignment=Enum.TextYAlignment.Top;body.TextScaled=true;local limit=Instance.new('UITextSizeConstraint');limit.MaxTextSize=GuiService:IsTenFootInterface()and 20 or 15;limit.MinTextSize=9;limit.Parent=body -- larger on TVs
end
local renderPartyBar
render=function()
 cancelStoreTweens()
 if renderPartyBar then renderPartyBar()end
 local focused=pendingFocusRestore or rememberFocus(bodyContent);pendingFocusRestore=nil
 if not bodyContent or not bodyContent.Parent then return end
 local selected=GuiService.SelectedObject;local selectionName=selected and selected:IsDescendantOf(bodyContent)and selected.Name
 if selectionName then GuiService.SelectedObject=nil end
 pickerRefresh=nil;previewModel=nil;bodyContent:ClearAllChildren()
 if tab=='Play'then drawPlay()elseif tab=='Join'then drawJoin()elseif tab=='Settings'then drawSettings()elseif tab=='Character'then drawCharacter()elseif tab=='Leaders'then drawLeaders()elseif tab=='Guide'then drawGuide()else drawStore()end
 scaleTree(bodyContent,layoutScale)
 if tab=='Store'then
  if storePopPending then storePopPending=false;storeEntranceStarted=os.clock()end
  if storeEntranceStarted then
   local elapsed=os.clock()-storeEntranceStarted
   if elapsed<STORE_ROW_DELAY+STORE_POP_TIME then
    storeTweens=UI.popRows(storeCells,storeColumns,STORE_ROW_DELAY,STORE_ROW_STAGGER,STORE_POP_TIME,elapsed)
   end
  end
 else storeEntranceStarted=nil;storePopPending=false end
 -- Fixed pages: no scroll listeners, clipped controls or off-screen sections.
 bodyContent.Size=UDim2.fromOffset(bodyW*layoutScale,bodyH*layoutScale)
 headerLabel.Text=tab=='Play'and(hostCircle and('START A RUN  |  CIRCLE '..hostCircle)or 'YOUR RUN.')or tab=='Join'and 'JOIN A RUN.'or tab=='Settings'and 'SOUND SETTINGS.'or tab=='Character'and 'PICK YOUR COLOUR.'or tab=='Leaders'and 'THE LEADERBOARDS.'or tab=='Guide'and 'HOW TO PLAY.'or 'THE STORE.'
 if selectionName then local item=bodyContent:FindFirstChild(selectionName,true)or bodyContent:FindFirstChild('StartGame',true)or bodyContent:FindFirstChild('CreateParty',true);if item and item:IsA('GuiObject')and item.Selectable then GuiService.SelectedObject=item end end
 if focused then
  local field=bodyContent:FindFirstChild(focused.name,true)
  if field and field:IsA('TextBox')then field.Text=focused.text;field:CaptureFocus();field.CursorPosition=focused.cursor;field.SelectionStart=focused.selection end
 end
end
refreshBrowse=function(manual)
 if browseFlight or party or p:GetAttribute('MissionActive')or tab~='Play'or playMode~='Browse'then return end
 browseFlight=true;browseTicket+=1;local ticket=browseTicket
 request('browse',{},function(data)
  if ticket~=browseTicket then return end
  browseFlight=false
  local nextResults=data.parties or {}
  if game.HttpService:JSONEncode(nextResults)~=game.HttpService:JSONEncode(browseResults)then browseResults=nextResults;browseDirty=true end
  if gui then gui:SetAttribute('PartyAutoRefreshAt',workspace:GetServerTimeNow());gui:SetAttribute('PartyAutoRefreshCount',(gui:GetAttribute('PartyAutoRefreshCount')or 0)+1)end
 end,not manual)
 task.delay(12,function()if ticket==browseTicket then browseFlight=false end end)
end
local function refreshPartyRows()
 local selected=GuiService.SelectedObject
 local row=selected and selected.Parent and selected.Parent.Name:match('^Party_')and selected.Parent.Name
 local name=selected and selected.Name
 browseDirty=false;render()
 if row then
  local replacement=bodyContent:FindFirstChild(row,true)
  GuiService.SelectedObject=replacement and replacement:FindFirstChild(name)or bodyContent:FindFirstChild('BrowseTab')
 end
end
-- Scoped lobby button finish; other menus retain their existing helpers and styling.
local LOBBY_BUTTON={Radius=5,Outline=3,Drop=5,PressTime=.09,HoverTime=.16,
 Purple=Color3.fromRGB(65,51,72),Green=Color3.fromRGB(69,83,53),Rust=Color3.fromRGB(98,61,48)}
local function lobbyButtonFinish(b,faceColor)
 b.AutoButtonColor=false;b.BorderSizePixel=0;b.BackgroundTransparency=0;b.BackgroundColor3=faceColor;b.Selectable=true
 for _,v in b:GetChildren()do if v:IsA('UICorner')or v:IsA('UIStroke')or v:IsA('UIGradient')then v:Destroy()end end
 corners(b,LOBBY_BUTTON.Radius);stroke(b,colors.ink,LOBBY_BUTTON.Outline)
 local origin=b.Position
 local shadow=Instance.new('Frame');shadow.Name=b.Name..'Drop';shadow.BorderSizePixel=0;shadow.BackgroundColor3=Color3.fromRGB(19,16,22)
 shadow.AnchorPoint=b.AnchorPoint;shadow.Position=origin+UDim2.fromOffset(0,LOBBY_BUTTON.Drop);shadow.Size=b.Size;shadow.ZIndex=math.max(0,b.ZIndex-1);shadow.Parent=b.Parent
 corners(shadow,LOBBY_BUTTON.Radius);stroke(shadow,colors.ink,LOBBY_BUTTON.Outline)
 -- The glow covers the whole button face, including the area its UIPadding reserves (PLAY's caption strip).
 local pad=b:FindFirstChildOfClass('UIPadding')
 local pl,pt=pad and pad.PaddingLeft.Offset or 0,pad and pad.PaddingTop.Offset or 0
 local pr,pb=pad and pad.PaddingRight.Offset or 0,pad and pad.PaddingBottom.Offset or 0
 local glow=Instance.new('Frame');glow.Name='SelectedGlow';glow.BackgroundTransparency=1;glow.Position=UDim2.fromOffset(-pl,-pt);glow.Size=UDim2.new(1,pl+pr,1,pt+pb);glow.Parent=b;corners(glow,LOBBY_BUTTON.Radius)
 local glowRim=stroke(glow,FOCUS_GOLD,3);glowRim.Transparency=1 -- gold, not red (red rule)
 focusRing(b,LOBBY_BUTTON.Radius)
 -- Deterministic wear: small low-contrast scratches on the face, never across its label.
 for i=1,5 do
  local scratch=Instance.new('Frame');scratch.Name='Wear'..i;scratch.BorderSizePixel=0;scratch.BackgroundColor3=colors.cream;scratch.BackgroundTransparency=.88
  scratch.AnchorPoint=Vector2.new(.5,.5);scratch.Position=UDim2.fromScale(.12+(i%3)*.35,i%2==0 and .13 or .84);scratch.Size=UDim2.new(.09,0,0,1);scratch.Rotation=i%2==0 and -18 or 12;scratch.Parent=b
 end
 local hovered,selected,pressed=false,false,false
 local motion,colorTween,glowTween
 local function refresh()
  if motion then motion:Cancel()end;if colorTween then colorTween:Cancel()end;if glowTween then glowTween:Cancel()end
  local focus=hovered or selected
  motion=Tween:Create(b,TweenInfo.new(LOBBY_BUTTON.PressTime),{Position=origin+UDim2.fromOffset(0,pressed and LOBBY_BUTTON.Drop or 0)});motion:Play()
  colorTween=Tween:Create(b,TweenInfo.new(LOBBY_BUTTON.HoverTime),{BackgroundColor3=focus and faceColor:Lerp(colors.cream,.14)or faceColor});colorTween:Play()
  glowTween=Tween:Create(glowRim,TweenInfo.new(LOBBY_BUTTON.HoverTime),{Transparency=focus and .3 or 1});glowTween:Play()
  -- One short, smooth shiver on focus; no repeating flicker or strobe.
  if preferences.CameraMotion~=false then Tween:Create(b,TweenInfo.new(.09,Enum.EasingStyle.Sine,Enum.EasingDirection.InOut,0,true),{Rotation=focus and .65 or 0}):Play()end
 end
 b.MouseEnter:Connect(function()hovered=true;refresh()end)
 b.MouseLeave:Connect(function()hovered=false;pressed=false;refresh()end)
 b.SelectionGained:Connect(function()selected=true;refresh()end)
 b.SelectionLost:Connect(function()selected=false;pressed=false;refresh()end)
 local function pressInput(input)
  return input.UserInputType==Enum.UserInputType.MouseButton1 or input.UserInputType==Enum.UserInputType.Touch or input.KeyCode==Enum.KeyCode.ButtonA
 end
 b.InputBegan:Connect(function(input)if pressInput(input)then pressed=true;refresh()end end)
 b.InputEnded:Connect(function(input)if pressInput(input)then pressed=false;refresh()end end)
 b.Activated:Connect(function()pressed=false;refresh()end)
 b:GetPropertyChangedSignal('Visible'):Connect(function()shadow.Visible=b.Visible end)
 b.Destroying:Connect(function()shadow:Destroy()end)
end
local MENU={
 {key='Settings',label='SETTINGS',icon='rbxassetid://125816849270898',tab='Settings'},
 {key='Character',label='CHARACTER',icon='rbxassetid://134740703980338',tab='Character'},
 {key='Tokens',label='TOKENS',icon='rbxassetid://125439267216921',tab='Store',shop='Tokens'},
 {key='Robux',label='SHOP',icon='rbxassetid://126379629055315',tab='Store',shop='Robux'},
 {key='Leaders',label='LEADERS',icon='rbxassetid://81964192209417',tab='Leaders'},
 {key='Guide',label='HOW TO PLAY',icon='rbxassetid://123355770486667',tab='Guide'},
}
local function setMovementBlocked(blocked)
 -- Walking is free in the 3D lobby; it is held only while a menu panel is open (and during a mission load).
 if blocked then CAS:BindActionAtPriority('LobbyMovement',function()return Enum.ContextActionResult.Sink end,false,4000,unpack(Enum.PlayerActions:GetEnumItems()))
 else CAS:UnbindAction('LobbyMovement')end
end
local function vanScreen(name)
 -- VanShop owns OpenLobbyShop; CharacterColourPicker's ScreenGui owns OpenLobbyAppearance.
 local pg=p:FindFirstChild('PlayerGui')
 for _,g in pg and pg:GetChildren()or{}do local b=g:FindFirstChild(name);if b and b:IsA('BindableEvent')then return b end end
 return nil
end
local function openTab(entryTab,shop)
 -- Tokens, Robux and Character use the van's own shop and appearance screens.
 if entryTab=='Store'or entryTab=='Character'then
  local ev=vanScreen(entryTab=='Store'and 'OpenLobbyShop'or 'OpenLobbyAppearance')
  if ev then tab=nil;build();ev:Fire(shop);return end
 end
 if entryTab=='Store'then if tab~='Store'then storePopPending=true end;if shop then shopTab=shop end end
 tab=entryTab;build()
 if entryTab=='Leaders'then fetchBoard(boardCategory)end
end
local function closePanel()
 if tab=='Play'and hostCircle then cancelHost();return end
 tab=nil;joinTarget=nil;build()
end
build=function()
 pendingFocusRestore=rememberFocus(gui)
 if gui then GuiService.SelectedObject=nil;gui:Destroy()end
 local viewport=workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize or Vector2.new(1280,760)
 local inset,bottom=GuiService:GetGuiInset();viewport=Vector2.new(viewport.X,math.max(220,viewport.Y-inset.Y-bottom.Y))
 compact=viewport.X/viewport.Y<1.25;lowWide=not compact and viewport.Y<550
 W=compact and 420 or lowWide and 680 or 760;H=compact and 560 or lowWide and 360 or 480
 gui=Instance.new('ScreenGui');gui.Name='HorrorMainMenu';gui.ScreenInsets=Enum.ScreenInsets.CoreUISafeInsets;gui.SafeAreaCompatibility=Enum.SafeAreaCompatibility.None;gui.ResetOnSpawn=false;gui.DisplayOrder=200;gui.Parent=p:WaitForChild('PlayerGui')
 -- The van shop / appearance screens sit below this menu; on phones they fill the screen, so hide the menu while one is open.
 gui.Enabled=(p:GetAttribute('MissionActive')~=true and not(p:GetAttribute('VanShopOpen')==true or p:GetAttribute('AppearanceOpen')==true or p:GetAttribute('QuestLogOpen')==true))
 local oldBackdrop=p.PlayerGui:FindFirstChild('HorrorMenuBackdrop');if oldBackdrop then oldBackdrop:Destroy()end
 layoutScale=math.min(1.15,(viewport.X-24)/W,(viewport.Y-24)/H)
 -- Left side: 3 x 2 grid of icon buttons, one per destination (Play is the world itself).
 local g=math.clamp(math.min(viewport.X,viewport.Y)/720,.88,1.1) -- icon >= 46 px: touch target floor
 -- Phones and tablets (owner 2026-10-24): the grid and the Quests bar took a big share of a small screen. Touch
 -- screens get MENU_TOUCH_SCALE of that, never below MENU_TOUCH_MIN (icons stay about 36 px: still easy to tap).
 local menuTouch=InputHints.Get()=='touch'
 if menuTouch then g=math.max(MENU_TOUCH_MIN,g*MENU_TOUCH_SCALE)end
 g*=TV_SCALE -- consoles: the grid and Quests bar size themselves (ConsoleUiScale skips MenuGrid / NavQuests)
 local cellW,cellH,icon=62*g,76*g,52*g
 local grid=Instance.new('Frame');grid.Name='MenuGrid';grid.BackgroundTransparency=1;grid.AnchorPoint=Vector2.new(0,0);grid.Position=UDim2.fromOffset(12,12+(compact and 0 or 30));grid.Size=UDim2.fromOffset(3*cellW,2*cellH);grid.Parent=gui
 for i,entry in ipairs(MENU)do
  local col,row=(i-1)%3,math.floor((i-1)/3)
  local active=tab==entry.tab and(entry.shop==nil or shopTab==entry.shop)
  local b=Instance.new('ImageButton');b.Name='Nav'..entry.key;b.Image=entry.icon;b.BackgroundTransparency=1;b.AutoButtonColor=false
  b.Position=UDim2.fromOffset(col*cellW+(cellW-icon)/2,row*cellH);b.Size=UDim2.fromOffset(icon,icon);b.Selectable=true;b.Parent=grid
  local symbol=Instance.new('ImageLabel');symbol.Name='Icon';symbol.BackgroundTransparency=1;symbol.Image=entry.icon;symbol.Size=UDim2.fromScale(.88,.88);symbol.Position=UDim2.fromScale(.06,.02);symbol.Parent=b;b.Image=''
  local palette={LOBBY_BUTTON.Purple,LOBBY_BUTTON.Green,LOBBY_BUTTON.Rust}
  lobbyButtonFinish(b,palette[(i-1)%3+1])
  local label=Instance.new('TextLabel');label.Name='Label';label.BackgroundTransparency=1;label.Position=UDim2.new(0,-(cellW-icon)/2,1,3);label.Size=UDim2.fromOffset(cellW,cellH-icon-6)
  label.Font=Enum.Font.Antique;label.Text=entry.label;label.TextScaled=true;label.TextColor3=active and colors.green or colors.cream;label.TextStrokeColor3=colors.ink;label.TextStrokeTransparency=.2;label.Parent=b
  local cap=Instance.new('UITextSizeConstraint');cap.MaxTextSize=math.floor(14*g+.5);cap.MinTextSize=menuTouch and 6 or 9;cap.Parent=label -- touch: the smaller cells fit 'CHARACTER' / 'HOW TO PLAY' only below 9
  b.Activated:Connect(function()Audio.Play('UiClick');if active then closePanel()else openTab(entry.tab,entry.shop)end end)
 end
 do
  local log=p.PlayerGui:FindFirstChild('QuestLog')
  if log and not p:GetAttribute('MissionActive')then
   local touchQ=InputHints.Get()=='touch' -- phones: a shorter bar, tucked under the grid, keeps the left thumb area free for moving and sprinting
   local qh=touchQ and math.floor(36*g+.5) or math.max(44,math.floor(46*g+.5)) -- touch: was a flat 34
   local q=Instance.new('TextButton');q.Name='NavQuests';q.Text='';q.AutoButtonColor=false;q.Selectable=true;q.BorderSizePixel=0
   q.Position=UDim2.fromOffset(12,grid.Position.Y.Offset+grid.Size.Y.Offset+(touchQ and 0 or 6));q.Size=UDim2.fromOffset(grid.Size.X.Offset,qh)
   q.Parent=gui;lobbyButtonFinish(q,LOBBY_BUTTON.Purple)
   local rim=q:FindFirstChildOfClass('UIStroke')
   local ic=Instance.new('ImageLabel');ic.Name='Icon';ic.BackgroundTransparency=1;ic.Image='rbxassetid://76180641217444';ic.Size=UDim2.fromOffset(qh+6,qh+6)
   ic.AnchorPoint=Vector2.new(0,.5);ic.Position=UDim2.new(0,-4,.5,0);ic.Parent=q
   local ql=Instance.new('TextLabel');ql.Name='Label';ql.BackgroundTransparency=1;ql.Position=UDim2.fromOffset(qh+2,0);ql.Size=UDim2.new(1,-qh-10,1,0)
   ql.Font=Enum.Font.Antique;ql.Text='QUESTS';ql.TextScaled=true;ql.TextColor3=colors.cream;ql.TextStrokeColor3=colors.ink;ql.TextStrokeTransparency=.1;ql.Parent=q
   local qc=Instance.new('UITextSizeConstraint');qc.MaxTextSize=math.floor(22*g);qc.MinTextSize=10;qc.Parent=ql
   local badge=Instance.new('TextLabel');badge.Name='Badge';badge.AnchorPoint=Vector2.new(.5,.5);badge.Position=UDim2.new(1,-4,0,4);badge.Size=UDim2.fromOffset(24*g,24*g)
   badge.BackgroundColor3=Color3.fromRGB(232,36,72);badge.Font=Enum.Font.FredokaOne;badge.TextScaled=true;badge.TextColor3=colors.cream;badge.ZIndex=1;badge.Parent=q -- layer 1: on its Quests button, but under menu panels opened over it
   corners(badge,999);stroke(badge,colors.cream,2)
   local function refresh()
    local n=tonumber(p:GetAttribute('QuestReadyCount'))or 0
    badge.Visible=n>0;badge.Text=tostring(math.min(n,99));rim.Color=n>0 and Color3.fromRGB(160,139,96)or colors.ink
   end
   refresh();p:GetAttributeChangedSignal('QuestReadyCount'):Connect(function()if q.Parent then refresh()end end)
   q.Activated:Connect(function()
    Audio.Play('UiClick');if tab then tab=nil;build()end
    local ev=log:FindFirstChild('Open');if ev then ev:Fire('daily')end
   end)
   testCallbacks[q]=function()local ev=log:FindFirstChild('Open');if ev then ev:Fire('daily')end end
  end
 end
 if tab then
  canvas=Instance.new('Frame');canvas.Name='Canvas';canvas.AnchorPoint=Vector2.new(.5,.5);canvas.Position=UDim2.fromScale(.5,.5);canvas.Size=UDim2.fromOffset(W,H);canvas.BackgroundTransparency=1;canvas.Parent=gui
  local pw,ph=W,H
  local panel=frame(canvas,'Panel',0,0,pw,ph,colors.panel)
  headerLabel=text(panel,'PageTitle','',14,10,pw-80,30,22)
  button(panel,'Close','X',pw-54,10,40,36,closePanel)
  statusLabel=text(panel,'Status',status,14,45,pw-28,32,13,colors.muted)
  bodyW=pw-28;bodyH=ph-96
  body=Instance.new('Frame');body.Name='Body';body.BackgroundTransparency=1;body.Position=UDim2.fromOffset(14,82);body.Size=UDim2.fromOffset(bodyW,bodyH);body.Parent=panel
  bodyContent=Instance.new('Frame');bodyContent.Name='Content';bodyContent.BackgroundTransparency=1;bodyContent.Size=UDim2.fromOffset(bodyW,bodyH);bodyContent.Parent=body
  render();scaleTree(canvas,layoutScale,bodyContent)
 else
  canvas=nil;bodyContent=nil;headerLabel=nil;statusLabel=nil
  if renderPartyBar then renderPartyBar()end
 end
 if not p:GetAttribute('MissionActive')then setMovementBlocked(tab~=nil)end
 if tab then CAS:BindAction('LobbyMenuBack',function(_,state)if state==Enum.UserInputState.Begin then closePanel()end;return Enum.ContextActionResult.Sink end,false,Enum.KeyCode.ButtonB)
 else CAS:UnbindAction('LobbyMenuBack')end
end
-- Party bar: who is in your run, START for the host, LEAVE for everyone. Lives under the menu gui.
renderPartyBar=function()
 if not gui then return end
 local old=gui:FindFirstChild('PartyBar');if old then old:Destroy()end
 if not party or p:GetAttribute('MissionActive')then return end
 local n=party.size;local w,h=280,74+n*24
 local bar=frame(gui,'PartyBar',0,0,w,h,colors.panel);local grid=gui:FindFirstChild('MenuGrid');local qb=gui:FindFirstChild('NavQuests');local top=grid and grid.Position.Y.Offset or 12 -- the left buttons hide while in a circle, so the run panel takes their place
 if grid then grid.Visible=false end;if qb then qb.Visible=false end
 if InputHints.Get()=='touch'then bar.AnchorPoint=Vector2.new(.5,0);bar.Position=UDim2.new(.5,0,0,8) -- phones/tablets: top centre, clear of the thumbstick and jump button
 else bar.AnchorPoint=Vector2.new(0,0);bar.Position=UDim2.fromOffset(12,top)end -- left, under the menu grid: straight down from the icons on a controller
 local owner=party.owner==p.UserId
 text(bar,'Title',(owner and 'YOUR RUN'or party.ownerDisplay.."'S RUN")..(party.circle and('  |  CIRCLE '..party.circle)or''),12,6,w-24,24,17)
 text(bar,'Access',(party.passwordRequired and 'PASSWORD'or party.friendsOnly and 'FRIENDS ONLY'or 'PUBLIC')..'  |  '..#party.members..' / '..n,12,28,w-24,18,12,colors.green)
 for i=1,n do
  local member=party.members[i]
  text(bar,'Member'..i,member and(member.display..(member.id==party.owner and '  (host)'or''))or (owner and 'Open spot: a friend walks into your circle' or 'Open spot'),member and 42 or 16,44+(i-1)*24,member and w-58 or w-32,22,13,member and colors.cream or colors.muted)
  if member then -- rank icon left of each member (Codex party-row patch)
   local who=Players:GetPlayerByUserId(member.id)
   local icon=Instance.new('ImageLabel');icon.Name='RankBadge'..i;icon.BackgroundTransparency=1;icon.ScaleType=Enum.ScaleType.Fit
   icon.Position=UDim2.fromOffset(16,45+(i-1)*24);icon.Size=UDim2.fromOffset(22,22)
   icon.Image=who and require(RS:WaitForChild('RankCatalog')).Get(who:GetAttribute('RR')).icon or '';icon.Parent=bar
  end
 end
 local full=#party.members>=n
 -- The host can start any time: a 3-slot run started with 2 people plays as a 2-player run.
 startButton=button(bar,'StartGame',owner and(full and 'START GAME'or('START NOW  '..#party.members..'/'..n))or 'HOST WILL START',12,h-34,w-110,28,function()
  if not owner then notice('Your host starts the game.');return end
  request('start',{},function(data)notice(type(data)=='string'and data or 'Getting ready...')end)
 end,owner)
 button(bar,'LeaveParty','LEAVE',w-92,h-34,80,28,function()request('leave',{},function(data)party=data.party;build();notice('You left the run.')end)end)
 local s=math.clamp((workspace.CurrentCamera and math.min(workspace.CurrentCamera.ViewportSize.X,workspace.CurrentCamera.ViewportSize.Y)or 720)/720,.7,1.05)
 if InputHints.Get()~='touch'then s*=1.35 end -- PC / Xbox: a bigger panel on the left, easy to read and to reach with a controller
 scaleTree(bar,s)
end
-- Party rows show each member's rank icon: redraw the open bar when any member's RR changes.
local function watchRank(other)
 other:GetAttributeChangedSignal('RR'):Connect(function()
  if party and gui and gui:FindFirstChild('PartyBar')then for _,m in party.members do if m.id==other.UserId then renderPartyBar();return end end end
 end)
end
for _,other in Players:GetPlayers()do watchRank(other)end
Players.PlayerAdded:Connect(watchRank)
local menuMusic=Instance.new('Sound');menuMusic.Name='MainMenuMusic';menuMusic.SoundId='rbxassetid://125926708472079';menuMusic.Volume=.03;menuMusic.Looped=true;menuMusic.PlaybackSpeed=1;menuMusic.Parent=game.SoundService
local function applySettings()
 local master=p:GetAttribute('LocalSettingMasterVolume') or p:GetAttribute('SettingMasterVolume') or preferences.MasterVolume
 local effects=p:GetAttribute('LocalSettingEffectsVolume') or p:GetAttribute('SettingEffectsVolume') or preferences.EffectsVolume
 local music=p:GetAttribute('LocalSettingMenuMusicVolume') or p:GetAttribute('SettingMenuMusicVolume') or preferences.MenuMusicVolume
 local sfx=game.SoundService:FindFirstChild('GameplaySFX');if sfx then sfx.Volume=2.4*master*effects end
 local ui=game.SoundService:FindFirstChild('GameplayUI');if ui then ui.Volume=2.25*master*effects end
 local worldMusic=game.SoundService:FindFirstChild('GameplayMusic');if worldMusic then worldMusic.Volume=.6*master*effects end -- level music quarter of the old level (2.4 -> 1.2 -> .6, 2026-10-25)
 menuMusic.Volume=.5*master*music -- owner 2026-10-25: too low at .28 (was .4 before that)
end
for key in pairs(defaults)do p:GetAttributeChangedSignal('Setting'..key):Connect(function()preferences[key]=p:GetAttribute('Setting'..key);p:SetAttribute('LocalSetting'..key,nil);applySettings()end);p:GetAttributeChangedSignal('LocalSetting'..key):Connect(applySettings)end
applySettings()
local launching=false
local missionLoader
local function beginMissionLoading(countdown,restarting)
 if launching then
  if missionLoader and missionLoader.Parent then missionLoader:SetAttribute('Countdown',countdown)end
  return
 end
 launching=true;menuMusic:Stop()
 if gui then gui.Enabled=false end
 local backdrop=p.PlayerGui:FindFirstChild('HorrorMenuBackdrop');if backdrop then backdrop.Enabled=false end
 GuiService.SelectedObject=nil
 local loader=game.ReplicatedFirst:FindFirstChild('MansionLoading')
 if loader and not p.PlayerGui:FindFirstChild('MansionLoading')then
  missionLoader=loader:Clone();missionLoader.Name='MissionLoading';missionLoader:SetAttribute('MissionEntry',true);missionLoader:SetAttribute('RunRestart',restarting==true);missionLoader:SetAttribute('Countdown',countdown);missionLoader.Parent=p.PlayerScripts
 end
end
local function cancelMissionLoading()
 if p:GetAttribute('MissionActive')then return end
 if missionLoader then missionLoader:Destroy();missionLoader=nil end
 local loaderGui=p.PlayerGui:FindFirstChild('MansionLoading');if loaderGui then loaderGui:Destroy()end
 launching=false
 if gui then gui.Enabled=true end
 local backdrop=p.PlayerGui:FindFirstChild('HorrorMenuBackdrop');if backdrop then backdrop.Enabled=true end
 menuMusic:Play()
end
-- A party update can arrive before MissionActive replicates and re-open the menu; hide it again once the mission is ours.
p:GetAttributeChangedSignal('MissionActive'):Connect(function()
 if p:GetAttribute('MissionActive')~=true then return end
 if gui then gui.Enabled=false end
 local backdrop=p.PlayerGui:FindFirstChild('HorrorMenuBackdrop');if backdrop then backdrop.Enabled=false end
 menuMusic:Stop()
end)
local function mission()
 beginMissionLoading()
 CAS:UnbindAction('LobbyMovement')
end

event.OnClientEvent:Connect(function(action,data)
 if action=='bench'or action=='booth'then local relay=script:FindFirstChild('SocialRelay');if relay then relay:Fire(action,data)end;return end
 if action=='response'then
  if not pending[data.id]then return end
  local callback=pending[data.id];pending[data.id]=nil;local quiet=quietRequests[data.id];quietRequests[data.id]=nil
  local onFail=failHandlers[data.id];failHandlers[data.id]=nil
  if not data.ok then if not quiet then notice(data.error);Audio.Play('UiError')end;if onFail then onFail(data.error)end
  elseif callback then callback(data.data)end
 elseif action=='progress'then
  -- The first progress snapshot on a new server is the baseline, not a reward (it used to toast the whole balance).
  local known=progress.ready==true -- the placeholder snapshot (ready=false, tokens=0) is not a real balance
  local earned=(data.tokens or 0)-(progress.tokens or 0);progress=data
  if known and earned>0 and p:GetAttribute('MissionActive')then task.spawn(function()
   -- A van gift being opened holds this toast until the player presses COLLECT (the reveal shows it first).
   local held=os.clock();while p:GetAttribute('VanRewardHold')and os.clock()-held<30 do task.wait(.1)end
   local old=p.PlayerGui:FindFirstChild('RunTokenReward');if old then old:Destroy()end
   local toast=Instance.new('ScreenGui');toast.Name='RunTokenReward';toast.ResetOnSpawn=false;toast.DisplayOrder=600;toast.ScreenInsets=Enum.ScreenInsets.CoreUISafeInsets;toast.Parent=p.PlayerGui
   local card=frame(toast,'Reward',0,0,280,64,colors.panel);card.AnchorPoint=Vector2.new(.5,.5);card.Position=UDim2.fromScale(.5,.72)
   local label=text(card,'Message','+'..earned..' TOKENS',12,8,256,48,19,colors.green);label.TextXAlignment=Enum.TextXAlignment.Center
   task.delay(4,function()if toast.Parent then toast:Destroy()end end)
  end)end
  -- A purchase reply already redrew the store with this same snapshot; a second full redraw right after hitched (2026-10-24).
  if gui and gui.Enabled and(tab=='Store'or tab=='Leaders')and os.clock()>=storeQuietUntil then render()end
 elseif action=='state'then
  party=data.party;if data.preferences then preferences=data.preferences end
  if party and(party.status=='Starting'or party.status=='Teleporting')then beginMissionLoading(party.countdown)
  elseif launching and not p:GetAttribute('MissionActive')then cancelMissionLoading()end
  if gui and gui.Enabled then render()end;applySettings()
 elseif action=='badgeState'then
  progress.badges=data;if gui and gui.Enabled and tab=='Guide'and GUIDE[guidePage].badges then render()end
 elseif action=='badgeEarned'then showBadgeToast(data)
 elseif action=='notice'then notice(data)
 elseif action=='invite'then
  notice(data.party.ownerDisplay..' invited you to a party. Open Find Party to join.')
  if gui and gui.Enabled then
   local old=gui:FindFirstChild('InviteToast');if old then old:Destroy()end
   local toast=frame(gui,'InviteToast',20,80,360,122,colors.card)
   text(toast,'Title',data.party.ownerDisplay..'’s invitation',14,8,330,36,20)
   button(toast,'Accept','JOIN',14,56,208,50,function()toast:Destroy();request('join',{id=data.party.id,password=''},function(result)if result and result.party then party=result.party;build()elseif result and result.transferring then notice("Joining your friend's lobby...")end end,false,function()if data.party.circle then notice('Walk into circle '..data.party.circle..' to join.')end end)end,true)
   button(toast,'Dismiss','×',236,56,106,50,function()toast:Destroy()end)
   task.delay(60,function()if toast.Parent then toast:Destroy()end end)
  end
 elseif action=='restart'then
  if missionLoader then missionLoader:Destroy();missionLoader=nil end
  local old=p.PlayerGui:FindFirstChild('MansionLoading');if old then old:Destroy()end
  launching=false;beginMissionLoading(nil,true)
 elseif action=='returnedToLobby'then
  task.spawn(function()
   local deadline=os.clock()+5
   repeat task.wait(.05)until p:GetAttribute('MissionActive')~=true and p:GetAttribute('ReturnedToLobby')==true or os.clock()>deadline
   if p:GetAttribute('MissionActive')==true then return end
   party=nil;hostCircle=nil;saveOpen=false;tab=nil;cancelMissionLoading();build();menuMusic:Play()
   request('sync',{},function(data)party=data.party;preferences=data.preferences or preferences;progress=data.progress or progress;render();applySettings()end)
  end)
 elseif action=='launch'then mission()end
end)
InputHints.Changed:Connect(function(device)if device=='pad'and gui and gui.Enabled and tab and canvas and not GuiService.SelectedObject then GuiService.SelectedObject=gui:FindFirstChild('Close',true)end end)
-- Controller: Select (View) jumps into the left menu grid.
CAS:BindAction('LobbyMenuFocus',function(_,state)if state==Enum.UserInputState.Begin and gui and gui.Enabled and not p:GetAttribute('MissionActive')then GuiService.SelectedObject=gui:FindFirstChild('NavSettings',true)end;return Enum.ContextActionResult.Pass end,false,Enum.KeyCode.ButtonSelect)
-- The menu holds the camera in a fixed Scriptable shot. A live mission is a fresh server, but a Studio
-- mission starts in this same session, so hand the camera back to the player when a mission begins.
local function playerCamera()
 local camera=workspace.CurrentCamera;local h=p.Character and p.Character:FindFirstChildOfClass('Humanoid')
 if camera and h and h.Health>0 and p:GetAttribute('MissionActive')and p:GetAttribute('RoundDead')~=true then camera.CameraSubject=h;camera.CameraType=Enum.CameraType.Custom end
end
p:GetAttributeChangedSignal('MissionActive'):Connect(function()if p:GetAttribute('MissionActive')then task.defer(playerCamera)end end)
p.CharacterAdded:Connect(function()task.delay(.5,playerCamera)end)
local lastViewport
Run.RenderStepped:Connect(function()
 if browseDirty and gui and gui.Enabled and tab=='Play'and playMode=='Browse'and not party and not UIS:GetFocusedTextBox()then refreshPartyRows()end
 if p:GetAttribute('MissionActive')then mission();return end
 if lobbyState:GetAttribute('Mode')~='Menu'and p:GetAttribute('ReturnedToLobby')~=true then return end
 -- 3D lobby: LobbyWorldClient owns the third-person camera; the menu only rebuilds on resize.
 local camera=workspace.CurrentCamera
 if camera then local size=camera.ViewportSize;if size~=lastViewport then lastViewport=size;build()end end
 if party and party.status=='Starting' and party.countdown then local left=math.max(0,math.ceil(party.countdown-workspace:GetServerTimeNow()));if startButton and startButton.Parent then startButton.Text='STARTING IN '..left end end
end)
if lobbyState:GetAttribute('Mode')=='Mission'then
else
 build();menuMusic:Play()
 request('sync',{},function(data)
  party=data.party;preferences=data.preferences or preferences;progress=data.progress or progress;render();applySettings()
  request('friends',{query=''},function(friends)friendResults=friends.friends or {};friendPage=1;if tab=='Play'and playMode~='Browse'then render()end end)
 end)
end

task.spawn(function()
 while script.Parent do
  task.wait(5)
  if gui and gui.Enabled and lobbyState:GetAttribute('Mode')=='Menu'then refreshBrowse(false)end
 end
end)
-- Bridge: LobbyWorldClient (circles, store kiosks) drives the menu through these; all LobbyEvent traffic stays here.
-- The server's claim (player attr LobbyCircle on a Setup circle we own) counts too, so a retry after a lost
-- release still frees the circle even though the local host state is already cleared.
local function ownSetupClaim()
 local i=p:GetAttribute('LobbyCircle');if not i then return nil end
 local model=workspace:FindFirstChild('LobbyWorld')and workspace.LobbyWorld.Circles:FindFirstChild('Circle'..tostring(i))
 if model and model:GetAttribute('Status')=='Setup'and model:GetAttribute('OwnerUserId')==p.UserId then return i end
 return nil
end
cancelHost=function()
 if hostCircle or ownSetupClaim()then request('circle.release',{},function()end,true)end
 hostCircle=nil;hostStep='save';saveOpen=false
 if tab=='Play'then tab=nil end;build()
end
startHost=function(index)
 if party then notice('Leave your current run first.');return end
 -- Open the host panel the moment you step in; the save list loads once the server confirms the claim
 -- (the server handles one request at a time per player).
 hostCircle=index;hostPending=true;hostStep='save';chosenSave=nil;saveOpen=true;saveSlots=nil;chosenSize=1;friendsOnly=false;privatePassword=false
 tab='Play';build()
 request('circle.claim',{circle=index},function()
  if hostCircle~=index then return end
  hostPending=false;build()
 end,false,function()
  if hostCircle==index and hostPending then hostPending=false;hostCircle=nil;if tab=='Play'then tab=nil end;build()end
 end)
end
local function joinCircle(index)
 if party then notice('You are already in a run.');return end
 notice('Joining circle '..index..'...')
 local model=workspace:FindFirstChild('LobbyWorld')and workspace.LobbyWorld.Circles:FindFirstChild('Circle'..index)
 if model and model:GetAttribute('Access')=='Password'then joinTarget=index;joinPassword='';tab='Join';build();return end
 request('circle.join',{circle=index,password=''},function(data)party=data.party;notice('Joined the run. Wait for the host to start.');build()end)
end
local bridge=Instance.new('BindableEvent');bridge.Name='LobbyMenuBridge';bridge.Parent=script
for _,attr in{'VanShopOpen','AppearanceOpen','QuestLogOpen'}do
 p:GetAttributeChangedSignal(attr):Connect(function()
  if gui then gui.Enabled=(p:GetAttribute('MissionActive')~=true and not(p:GetAttribute('VanShopOpen')==true or p:GetAttribute('AppearanceOpen')==true or p:GetAttribute('QuestLogOpen')==true))end
 end)
end
-- A claim the server granted but whose reply never arrived still gets the wizard (and its CANCEL), so the box lock
-- in LobbyWorldClient can never trap a player without a way out.
p:GetAttributeChangedSignal('LobbyCircle'):Connect(function()
 task.delay(1,function()
  local i=ownSetupClaim()
  if i and not hostCircle and not party and not p:GetAttribute('MissionActive')then
   hostCircle=i;hostStep='save';chosenSave=nil;saveOpen=true;saveSlots=nil;chosenSize=p:GetAttribute('BenchBuddy')and 4 or 1;friendsOnly=p:GetAttribute('BenchFriends')==true;privatePassword=false
   tab='Play';build()
  end
 end)
end)
bridge.Event:Connect(function(command,value)
 if p:GetAttribute('MissionActive')or launching then return end
 if command=='open'then
  for _,entry in ipairs(MENU)do if entry.key==value then openTab(entry.tab,entry.shop)end end
 elseif command=='host'then startHost(value)
 elseif command=='join'then joinCircle(value)
 elseif command=='leave'then if party then request('leave',{},function(data)party=data.party;build();notice('You left the run.')end,true)end
 elseif command=='cancelHost'then if hostCircle or ownSetupClaim()then cancelHost()end
 elseif command=='openQuests'then local log=p.PlayerGui:FindFirstChild('QuestLog');local ev=log and log:FindFirstChild('Open');if ev then if tab then tab=nil;build()end;ev:Fire(value or 'daily')end
 end
end)
if game:GetService('RunService'):IsStudio()then
 -- Studio-only: tests press a real, visible, active menu button through the callback its factory registered.
 local api=Instance.new('BindableFunction');api.Name='MainMenuTestApi';api.Parent=script
 api.OnInvoke=function(action,target)
  if action~='activate'or typeof(target)~='Instance'or not target:IsA('GuiButton')then return false,'bad request'end
  if not gui or not target:IsDescendantOf(gui)then return false,'not a menu button'end
  local x=target;while x and x~=gui do if x:IsA('GuiObject')and not x.Visible then return false,'hidden'end;x=x.Parent end
  if not target.Active then return false,'inactive'end
  local callback=testCallbacks[target];if not callback then return false,'no callback'end
  task.spawn(callback);return true
 end
end
p.PlayerGui.ChildAdded:Connect(function(c)if c.Name=='QuestLog'and gui and not gui:FindFirstChild('NavQuests')then build()end end)
-- Invite nudge: a small pill at the top of the lobby, 8 s after arriving, once per session. Roblox's own invite
-- prompt brings friends who are not in the game yet. Never in a mission, never when already partied with someone.
task.spawn(function()
 local Social=game:GetService('SocialService');local Tween=game:GetService('TweenService');local UIS=game:GetService('UserInputService')
 local t=os.clock();while p:GetAttribute('LobbyReady')~=true and os.clock()-t<60 do task.wait(.5)end
 task.wait(8)
 local ls=game:GetService('ReplicatedStorage'):FindFirstChild('LobbyState')
 if p:GetAttribute('MissionActive')==true or not(ls and ls:GetAttribute('Mode')=='Menu')then return end
 local id=p:GetAttribute('LobbyPartyId')
 if id then for _,q in game:GetService('Players'):GetPlayers()do if q~=p and q:GetAttribute('LobbyPartyId')==id then return end end end
 local can=false;pcall(function()can=Social:CanSendGameInviteAsync(p)end);if not can then return end
 local nudge=Instance.new('ScreenGui');nudge.Name='InviteNudge';nudge.ResetOnSpawn=false;nudge.DisplayOrder=40;nudge.ScreenInsets=Enum.ScreenInsets.CoreUISafeInsets;nudge.Parent=p.PlayerGui
 local pill=Instance.new('Frame');pill.AnchorPoint=Vector2.new(.5,0);pill.Position=UDim2.new(.5,0,0,6);pill.Size=UDim2.fromOffset(300,40);pill.BackgroundColor3=Color3.fromRGB(22,20,30);pill.BackgroundTransparency=1;pill.BorderSizePixel=0;pill.Parent=nudge
 Instance.new('UICorner',pill).CornerRadius=UDim.new(1,0)
 local hints=require(game:GetService('ReplicatedStorage'):WaitForChild('InputHints'))
 local touch=hints.Get()=='touch'
 -- phones/tablets: bottom centre above the stamina bar, so the lobby sign ('walk into a glowing circle') stays readable
 if touch then pill.AnchorPoint=Vector2.new(.5,1);pill.Position=UDim2.new(.5,0,1,-122)end -- above the (two-line) PLAY button, clear of it on phones
 local scale=Instance.new('UIScale');scale.Scale=touch and .85 or 1;scale.Parent=pill
 local stroke=Instance.new('UIStroke');stroke.Color=Color3.fromRGB(150,120,200);stroke.Transparency=1;stroke.Thickness=1;stroke.Parent=pill
 local label=Instance.new('TextLabel');label.BackgroundTransparency=1;label.Position=UDim2.fromOffset(16,0);label.Size=UDim2.new(1,-130,1,0);label.Font=Enum.Font.GothamMedium;label.TextSize=14;label.TextColor3=Color3.fromRGB(225,218,240);label.TextTransparency=1;label.TextXAlignment=Enum.TextXAlignment.Left;label.Text='Scarier with friends';label.Parent=pill
 local invite=Instance.new('TextButton');invite.AnchorPoint=Vector2.new(1,.5);invite.Position=UDim2.new(1,-38,.5,0);invite.Size=UDim2.fromOffset(76,28);invite.BackgroundColor3=Color3.fromRGB(120,90,180);invite.BackgroundTransparency=1;invite.Font=Enum.Font.GothamBold;invite.TextSize=13;invite.TextColor3=Color3.new(1,1,1);invite.TextTransparency=1;invite.Text='INVITE';invite.AutoButtonColor=true;invite.Parent=pill
 Instance.new('UICorner',invite).CornerRadius=UDim.new(1,0)
 local close=Instance.new('TextButton');close.AnchorPoint=Vector2.new(1,.5);close.Position=UDim2.new(1,-8,.5,0);close.Size=UDim2.fromOffset(38,38);close.BackgroundTransparency=1;close.Font=Enum.Font.GothamBold;close.TextSize=14;close.TextColor3=Color3.fromRGB(170,160,190);close.TextTransparency=1;close.Text='\u{00D7}';close.Parent=pill
 local function fade(show)
  local ti=TweenInfo.new(.5,Enum.EasingStyle.Quad)
  Tween:Create(pill,ti,{BackgroundTransparency=show and .25 or 1}):Play();Tween:Create(stroke,ti,{Transparency=show and .55 or 1}):Play()
  Tween:Create(label,ti,{TextTransparency=show and 0 or 1}):Play();Tween:Create(invite,ti,{BackgroundTransparency=show and .1 or 1,TextTransparency=show and 0 or 1}):Play()
  Tween:Create(close,ti,{TextTransparency=show and 0 or 1}):Play()
 end
 local gone=false
 local function dismiss()if gone then return end;gone=true;fade(false);task.delay(.6,function()nudge:Destroy()end)end
 invite.Activated:Connect(function()pcall(function()Social:PromptGameInvite(p)end);dismiss()end)
 close.Activated:Connect(dismiss)
 fade(true)
 task.delay(12,dismiss)
 p:GetAttributeChangedSignal('MissionActive'):Connect(function()if p:GetAttribute('MissionActive')==true then dismiss()end end)
end)
-- Buddy Bench (2026-10-26): alone on the lobby bench for 3 s (tutorial done) a pill offers SAVE A SEAT; INVITE opens
-- Roblox's own invite prompt on that press only (CanSendGameInviteAsync first). A friend who joins from it gets a
-- glowing path to the saved seat (server 'bench' message via SocialRelay). Ticks while two players count down.
do local socialRelay=Instance.new('BindableEvent');socialRelay.Name='SocialRelay';socialRelay.Parent=script -- no new top-level local (200-local limit)
task.spawn(function()
 local Social=game:GetService('SocialService');local Http=game:GetService('HttpService');local CAS=game:GetService('ContextActionService')
 local studioRun=game:GetService('RunService'):IsStudio()
 local gui=Instance.new('ScreenGui');gui.Name='BenchInvite';gui.ResetOnSpawn=false;gui.DisplayOrder=41;gui.ScreenInsets=Enum.ScreenInsets.CoreUISafeInsets;gui.Enabled=false;gui.Parent=p.PlayerGui
 local pill=Instance.new('Frame');pill.Name='Pill';pill.AnchorPoint=Vector2.new(.5,0);pill.Position=UDim2.new(.5,0,0,6);pill.Size=UDim2.fromOffset(330,44)
 pill.BackgroundColor3=Color3.fromRGB(22,20,30);pill.BackgroundTransparency=.25;pill.BorderSizePixel=0;pill.Parent=gui
 Instance.new('UICorner',pill).CornerRadius=UDim.new(1,0)
 local stroke=Instance.new('UIStroke');stroke.Color=Color3.fromRGB(255,190,90);stroke.Transparency=.4;stroke.Parent=pill
 local touch=InputHints.Get()=='touch'
 if touch then pill.AnchorPoint=Vector2.new(.5,1);pill.Position=UDim2.new(.5,0,1,-122)end -- same slot as the invite nudge, above PLAY
 local scale=Instance.new('UIScale');scale.Scale=touch and .85 or 1;scale.Parent=pill
 local label=Instance.new('TextLabel');label.BackgroundTransparency=1;label.Position=UDim2.fromOffset(16,0);label.Size=UDim2.new(1,-124,1,0);label.Font=Enum.Font.GothamMedium;label.TextSize=14
 label.TextColor3=Color3.fromRGB(240,228,210);label.TextXAlignment=Enum.TextXAlignment.Left;label.Text='Save this seat for a friend';label.Parent=pill
 local invite=Instance.new('TextButton');invite.Name='Invite';invite.AnchorPoint=Vector2.new(1,.5);invite.Position=UDim2.new(1,-8,.5,0);invite.Size=UDim2.fromOffset(100,34)
 invite.BackgroundColor3=Color3.fromRGB(240,160,60);invite.AutoButtonColor=true;invite.Font=Enum.Font.GothamBold;invite.TextSize=13;invite.TextColor3=Color3.new(1,1,1);invite.Text='INVITE';invite.Parent=pill
 Instance.new('UICorner',invite).CornerRadius=UDim.new(1,0)
 local function benchSeat()
  local c=p.Character;local h=c and c:FindFirstChildOfClass('Humanoid');local seat=h and h.SeatPart
  return seat and seat.Parent and seat.Parent.Name=='BuddyBench'and seat or nil
 end
 local function sendInvite()
  if not gui.Enabled then return end
  local options=Instance.new('ExperienceInviteOptions')
  options.PromptMessage='Come sit with me on the Buddy Bench!'
  options.LaunchData=Http:JSONEncode({bench=p.UserId})
  pcall(function()Social:PromptGameInvite(p,options)end);Audio.Play('UiOpen')
 end
 invite.Activated:Connect(sendInvite)
 local bound=false
 local function bind(on)
  if on==bound then return end;bound=on
  if on then CAS:BindActionAtPriority('BenchInvite',function(_,st)if st==Enum.UserInputState.Begin then sendInvite()end;return Enum.ContextActionResult.Sink end,false,2050,Enum.KeyCode.ButtonX)
  else CAS:UnbindAction('BenchInvite')end
 end
 socialRelay.Event:Connect(function(kind,data)
  if kind~='bench'or type(data)~='table'or typeof(data.seat)~='Instance'or not data.seat:IsA('BasePart')then return end
  notice(tostring(data.by)..' saved you a seat on the Buddy Bench!');Audio.Play('PartyHorn')
  local c=p.Character or p.CharacterAdded:Wait();local r=c:WaitForChild('HumanoidRootPart',10);if not r then return end
  local a0=Instance.new('Attachment');a0.Name='BenchGuideFrom';a0.Parent=r
  local a1=Instance.new('Attachment');a1.Name='BenchGuideTo';a1.Position=Vector3.new(0,.6,0);a1.Parent=data.seat
  local beam=Instance.new('Beam');beam.Name='BenchGuide';beam.Attachment0=a0;beam.Attachment1=a1;beam.Width0=.6;beam.Width1=.6;beam.FaceCamera=true;beam.LightEmission=1
  beam.Color=ColorSequence.new(Color3.fromRGB(255,214,90),Color3.fromRGB(45,181,165));beam.Transparency=NumberSequence.new(.25);beam.Parent=r
  local t=os.clock()
  while os.clock()-t<120 and beam.Parent and data.seat.Parent and benchSeat()==nil do task.wait(.25)end
  beam:Destroy();a0:Destroy();a1:Destroy()
 end)
 local aloneSince,allowed,lastTick=nil,nil,0
 while script.Parent do
  task.wait(.25)
  local seat=benchSeat();local model=seat and seat.Parent
  local other=model and model:FindFirstChild(seat.Name=='BenchSeat1'and'BenchSeat2'or'BenchSeat1')
  local alone=other~=nil and other.Occupant==nil and p:GetAttribute('TutorialDone')==true and p:GetAttribute('LobbyPartyId')==nil and p:GetAttribute('MissionActive')~=true
  if alone then aloneSince=aloneSince or os.clock()else aloneSince=nil;allowed=nil end
  if aloneSince and os.clock()-aloneSince>=3 and allowed==nil then
   local ok,can=pcall(function()return Social:CanSendGameInviteAsync(p)end)
   allowed=studioRun or(ok and can==true) -- Studio has no invite service; show the pill so tests can see it
  end
  local show=aloneSince~=nil and os.clock()-aloneSince>=3 and allowed==true
  invite.Text=InputHints.Get()=='pad'and'(X) INVITE'or'INVITE'
  gui.Enabled=show;bind(show)
  local bench=workspace:FindFirstChild('LobbyWorld')and workspace.LobbyWorld:FindFirstChild('BuddyBench')
  local ends=bench and bench:GetAttribute('PairEndsAt')
  if ends and(seat or(p.Character and p.Character:FindFirstChild('HumanoidRootPart')and(p.Character.HumanoidRootPart.Position-bench:GetPivot().Position).Magnitude<20))then
   local left=math.ceil(ends-workspace:GetServerTimeNow())
   if left>0 and left~=lastTick then lastTick=left;Audio.Play('ClockTick')end
  else lastTick=0 end
 end
end)
end
-- PLAY button: bottom centre of the lobby while you are not in a run. One press (click, tap or gamepad Y) puts you on
-- the nearest free circle, which opens the normal host setup (save, players, privacy). Joining someone is done by walking into their circle.
-- First-time players (TutorialDone false) see it pulse.
task.spawn(function()
 local RS=game:GetService('ReplicatedStorage');local CAS=game:GetService('ContextActionService')
 local hints=require(RS:WaitForChild('InputHints'));local ls=RS:WaitForChild('LobbyState')
 local qp=Instance.new('ScreenGui');qp.Name='QuickPlay';qp.ResetOnSpawn=false;qp.DisplayOrder=35;qp.ScreenInsets=Enum.ScreenInsets.CoreUISafeInsets;qp.Enabled=false;qp.Parent=p.PlayerGui
 local row=Instance.new('Frame');row.Name='Row';row.AnchorPoint=Vector2.new(.5,1);row.BackgroundTransparency=1;row.Size=UDim2.fromOffset(220,66);row.Parent=qp
 local rowScale=Instance.new('UIScale');rowScale.Parent=row
 -- Two lines: the action, and under it a small caption saying what it does.
 local function bigButton(name,label,color,size,caption)
  local holder=Instance.new('Frame');holder.Name=name;holder.BackgroundTransparency=1;holder.AnchorPoint=Vector2.new(.5,.5);holder.Size=UDim2.fromOffset(size,66);holder.Parent=row
  local b=Instance.new('TextButton');b.Name='Button';b.Size=UDim2.fromScale(1,1);b.AutoButtonColor=true;b.BackgroundColor3=color;b.BorderSizePixel=0;b.Font=Enum.Font.FredokaOne;b.TextColor3=Color3.fromRGB(16,26,18);b.Text=label;b.Parent=holder
  local lift=Instance.new('UIPadding');lift.PaddingBottom=UDim.new(0,16);lift.Parent=b
  local cap=Instance.new('TextLabel');cap.Name='Caption';cap.BackgroundTransparency=1;cap.AnchorPoint=Vector2.new(.5,0);cap.Position=UDim2.new(.5,0,1,-4);cap.Size=UDim2.new(1,-16,0,18);cap.Font=Enum.Font.FredokaOne;cap.TextSize=14;cap.TextColor3=b.TextColor3;cap.Text=caption;cap.TextTruncate=Enum.TextTruncate.AtEnd;cap.Parent=b
  Instance.new('UICorner',b).CornerRadius=UDim.new(0,14)
  local s=Instance.new('UIStroke');s.ApplyStrokeMode=Enum.ApplyStrokeMode.Border;s.Color=Color3.fromRGB(8,18,22);s.Thickness=3;s.Parent=b
  local pop=Instance.new('UIScale');pop.Name='Pop';pop.Parent=holder
  return holder,b,pop
 end
 local playHolder,play,playPop=bigButton('Play','PLAY',LOBBY_BUTTON.Green,220,'start your own run');play.TextSize=30
 lobbyButtonFinish(play,LOBBY_BUTTON.Green);play.Font=Enum.Font.Antique;play.TextColor3=colors.cream;play.Caption.TextColor3=colors.cream;play.Caption.Font=Enum.Font.Antique
 local badge=Instance.new('TextLabel');badge.Name='PadKey';badge.AnchorPoint=Vector2.new(0,.5);badge.Position=UDim2.new(0,12,.5,0);badge.Size=UDim2.fromOffset(30,30);badge.BackgroundColor3=Color3.fromRGB(8,18,22);badge.TextColor3=Color3.fromRGB(255,214,90);badge.Font=Enum.Font.FredokaOne;badge.TextSize=18;badge.Text='Y';badge.Parent=play
 Instance.new('UICorner',badge).CornerRadius=UDim.new(1,0)
 local badgeNudge=Instance.new('UIPadding');badgeNudge.PaddingRight=UDim.new(0,2);badgeNudge.Parent=badge -- FredokaOne's Y sits a hair right of centre (same as the revive PadY)
 -- PlayStation pads have a triangle where Xbox has Y: same badge, gold outline triangle (same as RecoveryRoundClient PadY).
 local function padGlyph(label,nudge)
  if InputHints.Glyph(label,'ButtonY')then return end -- PlayStation: the real triangle button art
  local ok,name=pcall(function()return UIS:GetStringForKeyCode(Enum.KeyCode.ButtonY)end)
  local ps=ok and name=='ButtonTriangle'
  label.Text=ps and utf8.char(0x25B3)or'Y';label.Font=ps and Enum.Font.BuilderSansBold or Enum.Font.FredokaOne;label.TextSize=ps and 20 or 18;nudge.PaddingRight=UDim.new(0,ps and 0 or 2)
  -- triangle: dark frog green and raised a little; Y: gold
  label.TextColor3=ps and Color3.fromRGB(58,110,48)or Color3.fromRGB(255,214,90);nudge.PaddingBottom=UDim.new(0,ps and 3 or 0)
 end
 local function circles()local w=workspace:FindFirstChild('LobbyWorld');return w and w:FindFirstChild('Circles')end
 local function eligible(m,want)
  local pad=m:FindFirstChild('Pad')
  return pad~=nil and pad:IsA('BasePart')and string.match(m.Name,'^Circle%d+$')~=nil and m:GetAttribute('Status')==want and(want=='Free'or m:GetAttribute('Access')=='Public')
 end
 local busyUntil=0
 local function go(kind)
  if os.clock()<busyUntil or party or hostCircle or launching or p:GetAttribute('LobbyPartyId')or p:GetAttribute('LobbyCircle')then return end
  local folder=circles();local char=p.Character
  local r=char and char:FindFirstChild('HumanoidRootPart');local hum=char and char:FindFirstChildOfClass('Humanoid')
  if not folder or not r or not hum or hum.Health<=0 then return end
  busyUntil=os.clock()+3
  -- The server picks, reserves and moves us to an empty circle far from other players; the setup menu opens on the reply.
  request('circle.quick',{},function(data)
   busyUntil=0
   if party or launching or type(data)~='table'or type(data.circle)~='number'then return end
   hostCircle=data.circle;hostPending=false;hostStep='save';chosenSave=nil;saveOpen=true;saveSlots=nil;chosenSize=1;friendsOnly=false;privatePassword=false
   tab='Play';build()
  end,false,function()busyUntil=0 end)
 end
 play.Activated:Connect(function()go('solo')end)
 -- Rank card right of PLAY, in the mastery card look: rank icon and name, RR toward the next rank above the right end
 -- of a white bar. RR comes from the server's player attribute; the formula is never shown.
 local Ranks=require(RS:WaitForChild('RankCatalog'))
 -- Preload every rank icon (own rank-ups, other players' name tags) so none pops in late.
 task.spawn(function()
  local icons={};for _,t in Ranks.Tiers do if t.icon~=''then local img=Instance.new('ImageLabel');img.Image=t.icon;table.insert(icons,img)end end
  pcall(function()game:GetService('ContentProvider'):PreloadAsync(icons)end)
  for _,img in icons do img:Destroy()end
 end)
 local card=Instance.new('Frame');card.Name='RankCard';card.AnchorPoint=Vector2.new(0,.5);card.Position=UDim2.new(1,14,.5,0);card.Size=UDim2.fromOffset(260,76)
 card.BackgroundTransparency=1;card.Visible=false;card.Parent=row
 -- Card face (owner 2026-10-25, second pass): the lobby buttons' chrome, shared with the mastery card (HudCardStyle).
 local cardStyle=require(RS:WaitForChild('HudCardStyle')).Build(card,'RANK')
 local socket=cardStyle.socket
 local RANK_CORNER_MARGIN,RANK_CORNER_TOP=12,8 -- computer / console: the card's gap from the top-right corner
 local CARD_SCALE=TV_SCALE -- the whole card at 100% (shrinks toward its anchor, so it stays beside / above PLAY)
 local cardScale=Instance.new('UIScale');cardScale.Scale=CARD_SCALE;cardScale.Parent=card
 local rim=Instance.new('UIStroke');rim.ApplyStrokeMode=Enum.ApplyStrokeMode.Border;rim.Thickness=2;rim.Enabled=false;rim.Parent=card -- the plank art has its own glowing edge
 local seasonPeak=Instance.new('ImageLabel');seasonPeak.Name='SeasonPeak';seasonPeak.BackgroundTransparency=1;seasonPeak.ScaleType=Enum.ScaleType.Fit;seasonPeak.Position=UDim2.fromOffset(50,44);seasonPeak.Size=UDim2.fromOffset(20,20);seasonPeak.ZIndex=4;seasonPeak.Visible=false;seasonPeak.Parent=card
 local iconHolder=Instance.new('Frame');iconHolder.Name='Icon';iconHolder.BackgroundTransparency=1;iconHolder.AnchorPoint=Vector2.new(.5,.5);iconHolder.Position=UDim2.fromScale(.5,.5);iconHolder.Size=UDim2.fromOffset(40,40);iconHolder.ZIndex=2;iconHolder.Parent=socket
 local function label(name,font,size,color,align)
  local t=Instance.new('TextLabel');t.Name=name;t.BackgroundTransparency=1;t.Font=font;t.TextSize=size;t.TextColor3=color;t.TextXAlignment=align;t.TextStrokeTransparency=.35;t.TextStrokeColor3=Color3.fromRGB(8,10,14);t.TextTruncate=Enum.TextTruncate.AtEnd;t.Parent=card
  return t
 end
 local rankName=label('RankName',Enum.Font.FredokaOne,13,Color3.new(1,1,1),Enum.TextXAlignment.Left);rankName.Position=UDim2.fromOffset(80,13);rankName.Size=UDim2.new(1,-104,0,16)
 local rrText=label('RR',Enum.Font.FredokaOne,11,Color3.fromRGB(150,255,220),Enum.TextXAlignment.Right)
 -- Under the bar: how much RR is left to the next rank, by name ("326 RR TO SEEKER III").
 local nextText=label('NextRank',Enum.Font.FredokaOne,10,Color3.fromRGB(214,214,224),Enum.TextXAlignment.Left);nextText.TextScaled=true
 local nextMax=Instance.new('UITextSizeConstraint');nextMax.MaxTextSize=10;nextMax.MinTextSize=7;nextMax.Parent=nextText
 local function sliceBar(parent,name,image)
  local i=Instance.new('ImageLabel');i.Name=name;i.BackgroundTransparency=1;i.Image=image;i.ScaleType=Enum.ScaleType.Slice;i.SliceCenter=Rect.new(48,23,464,25);i.SliceScale=.25;i.Parent=parent
  return i
 end
 local bar=sliceBar(card,'Bar','rbxassetid://90113844865582');bar.Position=UDim2.fromOffset(80,49);bar.Size=UDim2.new(1,-104,0,12)
 local fill=sliceBar(bar,'Fill','rbxassetid://137368694415108');fill.Size=UDim2.fromScale(0,1)
 local minFill=Instance.new('UISizeConstraint');minFill.MinSize=Vector2.new(24,0);minFill.Parent=fill -- keeps both rounded ends
 local shownTier
 local function drawRank()
  local rr=p:GetAttribute('RR')
  if type(rr)~='number'then card.Visible=false;return end
  card.Visible=true
  local r=Ranks.Get(rr);local lo,hi=Ranks.Progress(rr)
  rankName.Text=string.upper(r.name);rankName.TextColor3=r.color
  local master=p:GetAttribute('RRMaster')==true -- every mastery done: gold rim
  rim.Color=master and Color3.fromRGB(255,214,110)or r.color;rim.Thickness=master and 3 or 2
  local peak=Ranks.Tiers[p:GetAttribute('RRSeasonPeakTier')or 0] -- last season's peak rank, small in the icon corner
  seasonPeak.Image=peak and peak.icon or '';seasonPeak.Visible=peak~=nil
  rrText.Text=math.floor(rr)..' RR'
  nextText.Text=hi and((hi-math.floor(rr))..' RR TO '..string.upper(Ranks.Get(hi+1).name))or'TOP RANK REACHED'
  local frac=hi and math.clamp((rr-lo)/math.max(1,hi-lo),0,1)or 1
  fill.Visible=frac>0;game:GetService('TweenService'):Create(fill,TweenInfo.new(.45,Enum.EasingStyle.Quad),{Size=UDim2.fromScale(frac,1)}):Play()
  if shownTier~=r.tier then
   shownTier=r.tier;iconHolder:ClearAllChildren()
   cardStyle.SetAccent(r.color:Lerp(Color3.new(1,1,1),.15)) -- tag, inner line and socket ring take the rank's colour
   if r.icon~=''then
    local img=Instance.new('ImageLabel');img.BackgroundTransparency=1;img.Size=UDim2.fromScale(1,1);img.Image=r.icon;img.Parent=iconHolder
   else -- coloured gem until the rank icons are uploaded
    local gem=Instance.new('Frame');gem.AnchorPoint=Vector2.new(.5,.5);gem.Position=UDim2.fromScale(.5,.5);gem.Size=UDim2.fromOffset(26,26);gem.Rotation=45;gem.BackgroundColor3=r.color;gem.BorderSizePixel=0;gem.Parent=iconHolder
    Instance.new('UICorner',gem).CornerRadius=UDim.new(0,5)
    local s=Instance.new('UIStroke');s.Color=Color3.fromRGB(8,12,16);s.Thickness=3;s.Parent=gem
   end
  end
 end
 p:GetAttributeChangedSignal('RR'):Connect(drawRank);drawRank()
 p:GetAttributeChangedSignal('RRMaster'):Connect(drawRank);p:GetAttributeChangedSignal('RRSeasonPeakTier'):Connect(drawRank)
 local Tween=game:GetService('TweenService');local pulse=nil
 local bound=false
 local function bind(on)
  if on==bound then return end;bound=on
  if on then CAS:BindActionAtPriority('LobbyQuickPlay',function(_,st)if st==Enum.UserInputState.Begin then go('solo')end;return Enum.ContextActionResult.Sink end,false,2000,Enum.KeyCode.ButtonY)
  else CAS:UnbindAction('LobbyQuickPlay')end
 end
 while true do
  task.wait(.2)
  local inLobby=(ls:GetAttribute('Mode')=='Menu'or p:GetAttribute('ReturnedToLobby')==true)and p:GetAttribute('MissionActive')~=true and p:GetAttribute('LobbyReady')==true
  local idle=not party and not hostCircle and not launching and tab==nil and not p:GetAttribute('LobbyPartyId')and not p:GetAttribute('LobbyCircle')
   and not(p:GetAttribute('VanShopOpen')==true or p:GetAttribute('AppearanceOpen')==true or p:GetAttribute('QuestLogOpen')==true)
  local show=inLobby and idle
  qp.Enabled=show;bind(show)
  -- In a circle (owner 2026-10-25): the left-side buttons and the mastery card step aside for the circle's menu and come
  -- back when the player leaves it. InLobbyCircle is local; QuestLogClient and the admin buttons read it too.
  local circling=inLobby and(party~=nil or hostCircle~=nil or p:GetAttribute('LobbyPartyId')~=nil or p:GetAttribute('LobbyCircle')~=nil)
  if p:GetAttribute('InLobbyCircle')~=(circling or nil)then p:SetAttribute('InLobbyCircle',circling or nil)end
  if gui then for _,name in {'MenuGrid','NavQuests'}do local o=gui:FindFirstChild(name);if o and o.Visible==circling then o.Visible=not circling end end end
  if show then
   local device=hints.Get();local touch=device=='touch'
   badge.Visible=device=='pad';if badge.Visible then padGlyph(badge,badgeNudge)end
   playHolder.Position=UDim2.new(.5,0,.5,0)
   rowScale.Scale=touch and .85 or TV_SCALE
   -- touch: a narrower rank card so it ends before the jump button
   local ch=touch and 58 or 84 -- card height (phones: compact card, owner 2026-10-22)
   local s=ch/84
   card.Size=UDim2.fromOffset(touch and 186 or 330,ch) -- 330: same width as the mastery card it stacks with
   rankName.TextSize=touch and 12 or math.floor(14*s);rrText.TextSize=touch and 10 or math.floor(11*s);nextMax.MaxTextSize=math.floor(10*s);nextText.Visible=not touch
   local sock=cardStyle.Layout(ch,ch+4) -- round socket 7 px in; the RANK tag sits in the top border over the text column
   local ic=math.floor(sock*.74);iconHolder.Size=UDim2.fromOffset(ic,ic)
   seasonPeak.Position=UDim2.fromOffset(math.floor(7+sock*.78-10),math.floor(ch/2+sock*.28-10)) -- on the socket's lower-right rim
   -- Beside PLAY when it fits; above PLAY on narrow screens (Quest headsets, small windows). Touch keeps the jump
   -- button clear; VR keeps the card inside the headset's central view (the panel edges blur).
   local W=qp.AbsoluteSize.X;local vr=game:GetService('VRService').VREnabled
   local reserve=touch and 135 or vr and W*.08+16 or 16
   if touch then
    -- Phones: always right of PLAY, shrunk to fit the gap before the jump button.
    card.AnchorPoint=Vector2.new(0,.5);card.Position=UDim2.new(1,10,.5,0)
    local room=(W-reserve)-(W/2+(110+10)*rowScale.Scale)
    cardScale.Scale=W>0 and math.clamp(room/(card.Size.X.Offset*rowScale.Scale),.6,1)or 1
   elseif not vr then
    -- Computer and console (owner 2026-10-25): the card sits in the very top-right corner; the mastery card
    -- (QuestLogClient MasteryHud) moves down under it.
    cardScale.Scale=CARD_SCALE;card.Parent=qp
    card.AnchorPoint=Vector2.new(1,0);card.Position=UDim2.new(1,-RANK_CORNER_MARGIN,0,RANK_CORNER_TOP)
   else
    cardScale.Scale=CARD_SCALE
    if W>0 and W/2+(110+14+card.Size.X.Offset*CARD_SCALE)*rowScale.Scale>W-reserve then card.AnchorPoint=Vector2.new(.5,1);card.Position=UDim2.new(.5,0,0,-10)
    else card.AnchorPoint=Vector2.new(0,.5);card.Position=UDim2.new(1,14,.5,0)end
   end
   if (touch or vr)and card.Parent~=row then card.Parent=row end
   -- Rows: rank name with the player's RR on the right / the bar / RR left to the next rank.
   local x=ch+4;local right=math.floor(14*s);local rrW=math.floor(78*s) -- text starts right after the socket
   rankName.Position=UDim2.fromOffset(x,math.floor(14*s));rankName.Size=UDim2.new(1,-x-right-rrW,0,math.floor(16*s))
   rrText.Position=UDim2.new(1,-right-rrW,0,math.floor(14*s));rrText.Size=UDim2.fromOffset(rrW,math.floor(16*s))
   bar.Position=UDim2.fromOffset(x,math.floor((touch and 40 or 36)*s));bar.Size=UDim2.new(1,-x-right,0,math.max(10,math.floor(12*s)))
   nextText.Position=UDim2.fromOffset(x,math.floor(54*s));nextText.Size=UDim2.new(1,-x-right,0,math.floor(13*s))
   if touch then -- phones: the rank name gets the whole top row, the RR sits under the bar
    rankName.Size=UDim2.new(1,-x-right,0,math.floor(16*s))
    rrText.Position=UDim2.fromOffset(x,math.floor(56*s));rrText.Size=UDim2.new(1,-x-right,0,11);rrText.TextXAlignment=Enum.TextXAlignment.Left
   else rrText.TextXAlignment=Enum.TextXAlignment.Right end
   row.Position=UDim2.new(.5,0,1,touch and -46 or -24) -- touch: above the centred stamina bar
  end
  local wantPulse=show and p:GetAttribute('TutorialDone')==false
  if wantPulse and not pulse then pulse=Tween:Create(playPop,TweenInfo.new(.6,Enum.EasingStyle.Sine,Enum.EasingDirection.InOut,-1,true),{Scale=1.07});pulse:Play()
  elseif not wantPulse and pulse then pulse:Cancel();pulse=nil;playPop.Scale=1 end
 end
end)
-- Lobby guide: a yellow line on the floor from you to the nearest free circle while the PLAY button shows.
task.spawn(function()
 local PFS=game:GetService('PathfindingService')
 local qp=p:WaitForChild('PlayerGui'):WaitForChild('QuickPlay')
 local folder=Instance.new('Folder');folder.Name='LobbyCircleGuide'
 local YELLOW=Color3.fromRGB(255,214,60)
 local LIFT=Vector3.new(0,.12,0) -- just above the floor so it never z-fights
 local segs,dots={},{}
 local function piece(list,i,shape)
  local s=list[i]
  if not s then
   s=Instance.new('Part');s.Name='Guide';s.Shape=shape;s.Anchored=true;s.CanCollide=false;s.CanQuery=false;s.CanTouch=false;s.CastShadow=false
   s.Material=Enum.Material.Neon;s.Color=YELLOW;s.Transparency=.15;s.Parent=folder;list[i]=s
  end
  return s
 end
 local function trim(list,n)for i=#list,n+1,-1 do list[i]:Destroy();list[i]=nil end end
 local function draw(points)
  local n=0
  for i=1,#points-1 do
   local a,b=points[i],points[i+1];local len=(b-a).Magnitude
   if len>.05 then
    n+=1;local s=piece(segs,n,Enum.PartType.Block);s.Size=Vector3.new(.5,.06,len);s.CFrame=CFrame.lookAt((a+b)/2,b)
    local d=piece(dots,n,Enum.PartType.Cylinder);d.Size=Vector3.new(.06,.5,.5);d.CFrame=CFrame.new(b)*CFrame.Angles(0,0,math.pi/2) -- rounds the corners
   end
  end
  trim(segs,n);trim(dots,n)
 end
 local function nearestFree(r)
  local w=workspace:FindFirstChild('LobbyWorld');local c=w and w:FindFirstChild('Circles');if not c then return nil,nil end
  local best,bestD=nil,math.huge
  for _,m in c:GetChildren()do
   local pad=m:FindFirstChild('Pad')
   if pad and pad:IsA('BasePart')and string.match(m.Name,'^Circle%d+$')and m:GetAttribute('Status')=='Free'then
    local d=(pad.Position-r.Position).Magnitude;if d<bestD then best,bestD=pad,d end
   end
  end
  return best,bestD
 end
 local path=PFS:CreatePath({AgentRadius=1.5,AgentHeight=5,AgentCanJump=true})
 local lastPad,lastFrom,lastAt=nil,Vector3.zero,0
 while true do
  task.wait(.25)
  local char=p.Character;local r=char and char:FindFirstChild('HumanoidRootPart');local hum=char and char:FindFirstChildOfClass('Humanoid')
  local pad,dist
  if qp.Enabled and r and hum then pad,dist=nearestFree(r)end
  if not pad or dist<6 then
   folder.Parent=nil;lastPad=nil
  else
   folder.Parent=workspace
   if pad~=lastPad or(r.Position-lastFrom).Magnitude>1.5 or os.clock()-lastAt>2 then
    lastPad,lastFrom,lastAt=pad,r.Position,os.clock()
    local feet=r.Position-Vector3.new(0,hum.HipHeight+r.Size.Y/2,0)
    local goal=pad.Position+Vector3.new(0,pad.Size.Y/2,0)
    local points={feet+LIFT}
    local ok=pcall(function()path:ComputeAsync(feet,goal)end)
    if ok and path.Status==Enum.PathStatus.Success then
     for i,wp in path:GetWaypoints()do if i>1 then table.insert(points,wp.Position+LIFT)end end
    else table.insert(points,goal+LIFT)end
    if pad.Parent and qp.Enabled then draw(points)end
   end
  end
 end
end)
