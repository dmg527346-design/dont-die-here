-- Local visuals owned by TutorialClient. No gameplay input, inventory or physics changes.
local Players=game:GetService('Players')
local UIS=game:GetService('UserInputService')
local Pathfinding=game:GetService('PathfindingService')
local Tween=game:GetService('TweenService')
local Debris=game:GetService('Debris')
local RunService=game:GetService('RunService')
local Preferences=require(game.ReplicatedStorage:WaitForChild('HorrorPreferences'))
local M={};M.__index=M
local WHITE=Color3.fromRGB(250,250,245)
local GREEN=Color3.fromRGB(167,227,138)
local function frame(parent,name)
 local f=Instance.new('Frame');f.Name=name;f.BorderSizePixel=0;f.Active=false;f.Parent=parent;return f
end
local function label(parent,name,size)
 local t=Instance.new('TextLabel');t.Name=name;t.BackgroundTransparency=1;t.Font=Enum.Font.FredokaOne;t.TextColor3=WHITE;t.TextSize=size;t.TextWrapped=true;t.TextXAlignment=Enum.TextXAlignment.Left;t.Parent=parent;return t
end
local function round(parent,radius)local c=Instance.new('UICorner');c.CornerRadius=UDim.new(0,radius);c.Parent=parent end
local function stroke(parent,color,width)
 local s=Instance.new('UIStroke');s.Color=color;s.Thickness=width;s.ApplyStrokeMode=Enum.ApplyStrokeMode.Border;s.Parent=parent;return s
end
-- A drawn arrow (shaft + two head bars) pointing right at Rotation 0. Text arrows ('➜' / '▼') are missing from the pixel
-- font, which showed them as '?' (spun upside down on the screen edge), so the guide draws its own (2026-10-22).
local function drawArrow(parent,name,size,z)
 local holder=frame(parent,name);holder.BackgroundTransparency=1;holder.Size=UDim2.fromOffset(size,size);holder.AnchorPoint=Vector2.new(.5,.5);holder.ZIndex=z
 local thick=math.max(4,math.floor(size*.17))
 -- Two layers of the same three rounded bars: a dark one a little larger behind, the white one on top, so the outline
 -- is one clean line round the whole arrow. The head bars overlap at the tip so it reads as one shape.
 local tipX,mid=size*.82,size/2
 local L=size*.42;local d=(L/2-thick*.32)*math.cos(math.rad(45))
 local shaftFrom,shaftTo=size*.16,tipX-thick*.35
 local function layer(color,grow,zz)
  local function bar(n,len,cx,cy,rot)
   local b=frame(holder,n);b.BackgroundColor3=color;b.AnchorPoint=Vector2.new(.5,.5);b.Size=UDim2.fromOffset(len+grow,thick+grow);b.Position=UDim2.fromOffset(cx,cy);b.Rotation=rot;b.ZIndex=zz
   round(b,math.ceil((thick+grow)/2))
  end
  bar('Shaft',shaftTo-shaftFrom,(shaftFrom+shaftTo)/2,mid,0)
  bar('HeadUp',L,tipX-d,mid-d,45)
  bar('HeadDown',L,tipX-d,mid+d,-45)
 end
 layer(Color3.fromRGB(10,22,22),5,z);layer(WHITE,0,z+1)
 return holder
end
function M.New(inputHints,onSkip)
 local self=setmetatable({hints=inputHints,segments={},points={},generation=0,lastPathAt=-10,modifiers={},dismissed={},confirmed={},maskResumeAt=0},M)
 local gui=Instance.new('ScreenGui');gui.Name='GuidedFirstGameTutorial';gui.ResetOnSpawn=false;gui.DisplayOrder=150;gui.IgnoreGuiInset=true;gui.ScreenInsets=Enum.ScreenInsets.None;gui.Parent=Players.LocalPlayer:WaitForChild('PlayerGui');self.gui=gui
 local root=frame(gui,'Overlay');root.BackgroundTransparency=1;root.Size=UDim2.fromScale(1,1);self.root=root
 self.masks={};for i=1,4 do local f=frame(root,'TouchDim'..i);f.BackgroundColor3=Color3.new();f.BackgroundTransparency=.4;f.ZIndex=1;f.Visible=false;self.masks[i]=f end
 local focus=frame(root,'ButtonSpotlight');focus.BackgroundTransparency=1;focus.ZIndex=3;focus.Visible=false;round(focus,18);self.focusStroke=stroke(focus,WHITE,3);self.focus=focus
 local tap=label(root,'TapInstruction',15);tap.Text='TAP HERE';tap.TextXAlignment=Enum.TextXAlignment.Center;tap.Size=UDim2.fromOffset(155,28);tap.ZIndex=4;tap.Visible=false;self.tap=tap
 local card=frame(root,'Tip');card.AnchorPoint=Vector2.new(.5,1);card.BackgroundColor3=Color3.fromRGB(22,42,43);card.BackgroundTransparency=.12;card.ZIndex=5;round(card,14);self.cardStroke=stroke(card,Color3.fromRGB(8,18,22),2);self.card=card;local pop=Instance.new('UIScale');pop.Name='Pop';pop.Parent=card;self.cardScale=pop
 local title=label(card,'Title',18);title.Position=UDim2.fromOffset(60,7);title.Size=UDim2.new(1,-117,0,20);title.TextColor3=GREEN;title.ZIndex=6;title.TextScaled=true;local titleFit=Instance.new('UITextSizeConstraint');titleFit.MinTextSize=11;titleFit.MaxTextSize=15;titleFit.Parent=title;self.title=title
 local text=label(card,'Instruction',15);text.Font=Enum.Font.GothamMedium;text.Position=UDim2.fromOffset(60,29);text.Size=UDim2.new(1,-72,0,40);text.TextYAlignment=Enum.TextYAlignment.Top;text.ZIndex=6;text.RichText=true;text.TextScaled=true;local textFit=Instance.new('UITextSizeConstraint');textFit.MinTextSize=11;textFit.MaxTextSize=13;textFit.Parent=text;self.text=text
 local progress=label(card,'Cooperative',11);progress.Font=Enum.Font.GothamMedium;progress.TextColor3=Color3.fromRGB(185,204,191);progress.Position=UDim2.fromOffset(60,73);progress.Size=UDim2.new(1,-72,0,12);progress.TextSize=9;progress.ZIndex=6;self.progress=progress
 local skip=Instance.new('TextButton');skip.Name='Skip';skip.Text='SKIP';skip.Font=Enum.Font.GothamBold;skip.TextSize=10;skip.TextColor3=Color3.fromRGB(185,204,191);skip.BackgroundTransparency=1;skip.Position=UDim2.new(1,-59,0,3);skip.Size=UDim2.fromOffset(54,44);skip.ZIndex=8;skip.Parent=card;skip.Activated:Connect(onSkip)
 local icon=frame(card,'CustomButtonArt');icon.Position=UDim2.fromOffset(9,10);icon.Size=UDim2.fromOffset(43,44);icon.BackgroundTransparency=1;icon.ZIndex=6;self.icon=icon
 local shadow=frame(icon,'KeyShadow');shadow.Size=UDim2.fromOffset(38,38);shadow.Position=UDim2.fromOffset(2,4);shadow.BackgroundColor3=Color3.fromRGB(5,13,15);shadow.ZIndex=6;round(shadow,11);self.shadow=shadow
 local face=frame(icon,'KeyFace');face.Size=UDim2.fromOffset(38,36);face.Position=UDim2.fromOffset(2,0);face.BackgroundColor3=Color3.fromRGB(239,238,222);face.ZIndex=7;round(face,11);self.face=face
 local glyph=label(face,'Glyph',29);glyph.TextColor3=Color3.fromRGB(22,42,43);glyph.TextXAlignment=Enum.TextXAlignment.Center;glyph.Size=UDim2.fromScale(1,1);glyph.TextScaled=true;local glyphFit=Instance.new('UITextSizeConstraint');glyphFit.MinTextSize=8;glyphFit.MaxTextSize=26;glyphFit.Parent=glyph;glyph.ZIndex=8;self.glyph=glyph
 self.glyphStroke=stroke(face,WHITE,2);self.glyphStroke.Transparency=1
 local mark=Instance.new('BillboardGui');mark.Name='TutorialTarget';mark.Size=UDim2.fromOffset(160,50);mark.StudsOffsetWorldSpace=Vector3.new(0,2.5,0);mark.AlwaysOnTop=true;mark.MaxDistance=450;mark.Parent=gui;self.mark=mark
 local mt=label(mark,'TargetName',12);mt.TextXAlignment=Enum.TextXAlignment.Center;mt.Size=UDim2.new(1,0,0,28);mt.TextStrokeTransparency=.25;self.markText=mt
 local arrow=drawArrow(mark,'Arrow',24,2);arrow.Position=UDim2.new(.5,0,0,36);arrow.Rotation=90 -- points down at the target
 local glow=Instance.new('Highlight');glow.Name='TutorialTargetOutline';glow.FillTransparency=1;glow.OutlineTransparency=.35;glow.FillColor=WHITE;glow.OutlineColor=WHITE;glow.DepthMode=Enum.HighlightDepthMode.AlwaysOnTop;glow.Enabled=false;glow.Parent=gui;self.glow=glow
 -- Screen-edge guide: a round badge in the tutorial card's colours with the arrow inside. It glides and turns toward the
 -- target (smoothed every frame in EdgeStep), fades in and out, and nudges gently the way it points.
 local edge=Instance.new('CanvasGroup');edge.Name='OffscreenDirection';edge.BackgroundTransparency=1;edge.Size=UDim2.fromOffset(58,58);edge.AnchorPoint=Vector2.new(.5,.5)
 edge.ZIndex=4;edge.GroupTransparency=1;edge.Visible=false;edge.Parent=root;self.edge=edge
 local disc=frame(edge,'Badge');disc.BackgroundColor3=Color3.fromRGB(18,36,38);disc.BackgroundTransparency=.08;disc.Size=UDim2.fromOffset(50,50);disc.Position=UDim2.fromOffset(4,4);disc.ZIndex=4
 local c=Instance.new('UICorner');c.CornerRadius=UDim.new(1,0);c.Parent=disc;local ds=stroke(disc,GREEN,2.5);ds.Transparency=.15
 local inner=drawArrow(edge,'Arrow',36,5);inner.Position=UDim2.fromScale(.5,.5)
 self.edgeConn=RunService.RenderStepped:Connect(function(dt)self:EdgeStep(dt)end)
 local folder=Instance.new('Folder');folder.Name='TutorialWhiteRoute';folder.Parent=workspace;self.route=folder
 for i=1,49 do
  local a=Instance.new('Part');a.Name='RouteAnchor';a.Size=Vector3.one*.05;a.Anchored=true;a.Transparency=1;a.CanCollide=false;a.CanTouch=false;a.CanQuery=false;a.CastShadow=false;a.Parent=folder
  local attachment=Instance.new('Attachment');attachment.Parent=a
  local item={part=a,attachment=attachment};self.segments[i]=item
  if i>1 then local beam=Instance.new('Beam');beam.Name='WhiteRoute';beam.Attachment0=self.segments[i-1].attachment;beam.Attachment1=attachment;beam.Width0=.08;beam.Width1=.08;beam.FaceCamera=true;beam.Color=ColorSequence.new(WHITE);beam.Transparency=NumberSequence.new(.45);beam.LightEmission=.4;beam.Segments=1;beam.Enabled=false;beam.Parent=a;item.beam=beam end
 end
 self.typeConnection=RunService.RenderStepped:Connect(function()self:Type()end)
 return self
end
-- Smooths the screen-edge arrow: position and angle ease toward their goals (shortest way round), the badge fades,
-- and it pulses a few pixels along the direction it points.
function M:EdgeStep(dt)
 local e=self.edge;if not e then return end
 local k=math.min(1,dt*12)
 self.edgeAlpha=(self.edgeAlpha or 0)+((self.edgeWant and 1 or 0)-(self.edgeAlpha or 0))*math.min(1,dt*9)
 e.Visible=self.edgeAlpha>.02;e.GroupTransparency=1-self.edgeAlpha
 local goal=self.edgeGoalPos;if not goal then return end
 if not self.edgePos or self.edgeAlpha<.05 then self.edgePos,self.edgeRot=goal,self.edgeGoalRot end
 self.edgePos=self.edgePos:Lerp(goal,k)
 local turn=(self.edgeGoalRot-self.edgeRot+180)%360-180;self.edgeRot+=turn*k
 local nudge=math.sin(os.clock()*5)*3;local rad=math.rad(self.edgeRot)
 e.Position=UDim2.fromOffset(self.edgePos.X+math.cos(rad)*nudge,self.edgePos.Y+math.sin(rad)*nudge);e.Rotation=self.edgeRot
end
-- Only this client's input dismisses its spotlight; teammates never acknowledge it for them.
function M:Dismiss(action,stepId)
 local key=action=='crouch'and 'crouch' or stepId or action
 self.dismissed[key]=true;self.maskResumeAt=os.clock()+.45;self:Spotlight(nil,false)
end
function M:Success(action,stepId)
 self:Dismiss(action,stepId)
 local key=stepId or action;if self.confirmed[key]then return end;self.confirmed[key]=true
 if true or not Preferences.Get('FlashingLights')or not workspace.CurrentCamera then return end -- calmer: no screen pulse
 local pulse=Instance.new('ColorCorrectionEffect');pulse.Name='TutorialSuccessPulse';pulse.Parent=workspace.CurrentCamera
 local previous=self.pulse;self.pulse=pulse;if previous then previous:Destroy()end
 local up=Tween:Create(pulse,TweenInfo.new(.07,Enum.EasingStyle.Sine,Enum.EasingDirection.Out),{Brightness=.025,Contrast=.018,Saturation=.05,TintColor=Color3.fromRGB(244,255,246)})
 up.Completed:Once(function(state)
  if state~=Enum.PlaybackState.Completed or self.pulse~=pulse or not pulse.Parent then return end
  local down=Tween:Create(pulse,TweenInfo.new(.28,Enum.EasingStyle.Sine,Enum.EasingDirection.Out),{Brightness=0,Contrast=0,Saturation=0,TintColor=Color3.new(1,1,1)})
  down.Completed:Once(function()if self.pulse==pulse then self.pulse=nil end;pulse:Destroy()end);down:Play()
 end)
 Debris:AddItem(pulse,.5);up:Play()
end
function M:Button(action,device)
 local pad=device=='pad';local text='';local red=false;local circle=false
 if action=='light'then
  text=pad and 'B'or 'F';red=pad
  if pad and self.hints.Button('ButtonB')=='Circle'then text='';circle=true end
 elseif action=='crouch'then text=pad and self.hints.Button('ButtonR3')or 'C'
 elseif action=='use'then text=pad and self.hints.Button('ButtonX')or 'E';if text=='Square'then text='□'end
 elseif action=='grab'or action=='hold'or action=='release'then text=pad and self.hints.Button('ButtonR2')or device=='touch'and 'TAP'or 'LMB'
 elseif action=='move'then text=pad and 'LS'or device=='touch'and 'MOVE'or 'WASD'
 else text='✓'end
 if device=='touch'and(action=='light'or action=='crouch')then text='TAP';red=false;circle=false end
 self.glyph.Text=text;self.glyph.TextSize=#text>3 and 16 or #text>1 and 20 or 30
 self.face.BackgroundColor3=red and Color3.fromRGB(24,28,30)or Color3.fromRGB(239,238,222)
 self.glyph.TextColor3=red and Color3.fromRGB(245,78,81)or Color3.fromRGB(22,42,43)
 self.glyphStroke.Color=red and Color3.fromRGB(245,78,81)or WHITE;self.glyphStroke.Transparency=circle and 0 or 1
 self.face.UICorner.CornerRadius=UDim.new(circle and .5 or 0,circle and 0 or 11)
 self.shadow.Visible=not circle
 self.icon:SetAttribute('Platform',device);self.icon:SetAttribute('Action',action);self.icon:SetAttribute('PlayStationCircle',circle)
end
function M:Spotlight(button,enabled,dim)
 local show=enabled and button and button.Visible and button.AbsoluteSize.X>0
 self.focus.Visible=show==true;self.tap.Visible=show==true
 for _,f in self.masks do f.Visible=false end -- no screen dimming by default; the ring is enough (dim: shop chapter)
 if not show then return end
 local size=self.root.AbsoluteSize;local pos=button.AbsolutePosition-self.root.AbsolutePosition
 local x,y=math.clamp(pos.X-6,0,size.X),math.clamp(pos.Y-6,0,size.Y)
 local right,bottom=math.clamp(pos.X+button.AbsoluteSize.X+6,x,size.X),math.clamp(pos.Y+button.AbsoluteSize.Y+6,y,size.Y)
 local rects={{0,0,size.X,y},{0,bottom,size.X,size.Y-bottom},{0,y,x,bottom-y},{right,y,size.X-right,bottom-y}}
 for i,r in rects do self.masks[i].Position=UDim2.fromOffset(r[1],r[2]);self.masks[i].Size=UDim2.fromOffset(r[3],r[4]);self.masks[i].Visible=dim==true end
 self.focus.Position=UDim2.fromOffset(x,y);self.focus.Size=UDim2.fromOffset(right-x,bottom-y)
 self.focusStroke.Transparency=.1+.25*(.5+.5*math.sin(os.clock()*4))
 self.tap.Position=UDim2.fromOffset(math.clamp((x+right-155)/2,6,math.max(6,size.X-161)),math.clamp(y-34,36,math.max(36,size.Y-34)))
end
-- A later chapter (the shop, 2026-10-25): its own accent on the title, rim and edge badge, and a small tag over the
-- card (under it when the card sits at the top of a phone screen), so it reads as something new.
function M:Chapter(tag,accent)
 local t=self.chapterTag
 if not t then
  t=label(self.card,'ChapterTag',11);t.Font=Enum.Font.GothamBold;t.TextXAlignment=Enum.TextXAlignment.Center;t.TextWrapped=false
  t.AutomaticSize=Enum.AutomaticSize.X;t.Size=UDim2.fromOffset(0,18);t.BackgroundTransparency=0;t.TextColor3=Color3.fromRGB(22,42,43);t.ZIndex=7;round(t,9)
  local pad=Instance.new('UIPadding');pad.PaddingLeft=UDim.new(0,9);pad.PaddingRight=UDim.new(0,9);pad.Parent=t
  self.chapterTag=t
 end
 local top=self.card.AnchorPoint.Y==0
 t.AnchorPoint=Vector2.new(0,top and 0 or 1);t.Position=top and UDim2.new(0,12,1,5)or UDim2.new(0,12,0,-6)
 t.Text=tag;t.BackgroundColor3=accent
 self.title.TextColor3=accent;self.cardStroke.Color=accent:Lerp(Color3.fromRGB(8,18,22),.6)
 local badge=self.edge:FindFirstChild('Badge');local ring=badge and badge:FindFirstChildOfClass('UIStroke');if ring then ring.Color=accent end
end
function M:DoorPassage(map)
 if self.map==map then return end
 for _,m in self.modifiers do if m.Parent then m:Destroy()end end;table.clear(self.modifiers);self.map=map
 local interactive=map and map:FindFirstChild('Interactive');if not interactive then return end
 for _,model in interactive:GetChildren()do
  if model:IsA('Model')and model:GetAttribute('Open')~=nil and not model:GetAttribute('Locked')then
   for _,part in model:GetDescendants()do if part:IsA('BasePart')and part.CanCollide then
    local modifier=Instance.new('PathfindingModifier');modifier.Name='TutorialDoorPassage';modifier.PassThrough=true;modifier.Parent=part;table.insert(self.modifiers,modifier)
   end end
  end
 end
end
function M:HideRoute()
 for _,r in self.segments do if r.beam then r.beam.Enabled=false end end
 self.edgeWant=false
end
function M:Route(from,to,key,push)
 local now=os.clock()
 if not from or not to then self:HideRoute();self.goalKey=nil;self.generation+=1;return end
 local changed=self.goalKey~=key
 if changed then self.goalKey=key;self.generation+=1;self.points={};self.lastPathAt=-10;self:HideRoute()end
 if not self.pathBusy and now-self.lastPathAt>1.4 and(changed or not self.pathFrom or(from-self.pathFrom).Magnitude>3 or not self.pathTo or(to-self.pathTo).Magnitude>3 or #self.points==0)then
  self.pathBusy=true;self.lastPathAt=now;self.pathFrom=from;self.pathTo=to
  local generation=self.generation
  task.spawn(function()
   local path=Pathfinding:CreatePath({AgentRadius=push and 2.4 or 1.8,AgentHeight=5,AgentCanJump=false,WaypointSpacing=3})
   local ok=pcall(function()path:ComputeAsync(from,to)end)
   local points={};if ok and path.Status==Enum.PathStatus.Success then for _,w in path:GetWaypoints()do table.insert(points,w.Position+Vector3.new(0,.1,0))end end
   path:Destroy();if self.generation==generation then self.points=points end;self.pathBusy=false
  end)
 end
 local points=self.points;local nearest,best=1,math.huge
 for i,pt in points do local d=(pt-from).Magnitude;if d<best then nearest,best=i,d end end
 local used=0
 for i=nearest,math.min(#points,nearest+16)do used+=1;self.segments[used].part.Position=points[i]end
 for i=2,49 do self.segments[i].beam.Enabled=i<=used end
 local camera=workspace.CurrentCamera
 if camera then
  local point,onScreen=camera:WorldToViewportPoint(to+Vector3.new(0,2,0));self.edgeWant=not onScreen
  if not onScreen then
   local v=camera.ViewportSize;local direction=Vector2.new(point.X-v.X/2,point.Y-v.Y/2);if point.Z<0 then direction=-direction end
   if direction.Magnitude<1 then direction=Vector2.new(0,-1)end
   local scale=math.min((v.X*.5-45)/math.max(math.abs(direction.X),1),(v.Y*.5-60)/math.max(math.abs(direction.Y),1))
   self.edgeGoalPos=Vector2.new(v.X/2+direction.X*scale,v.Y/2+direction.Y*scale);self.edgeGoalRot=math.deg(math.atan2(direction.Y,direction.X))
  end
 end
end
-- Each new card: the background pops in, then the title types fast and the instruction letter by letter,
-- so the eye follows the words. MaxVisibleGraphemes keeps the layout fixed while typing (no reflow).
local TITLE_CPS,BODY_CPS=90,75 -- letters per second (was 45,32; faster 2026-10-22)
local function glyphs(s)local plain=string.gsub(s or'','<[^>]->','');return utf8.len(plain)or #plain end
-- Labels drawn by PixelFontEverywhere keep their glyphs in PixelFace / PixelShadow children: type those too.
local function setVisible(label,n)
 label.MaxVisibleGraphemes=n
 for _,c in label:GetChildren()do if c.Name=='PixelFace'or c.Name=='PixelShadow'then c.MaxVisibleGraphemes=n end end
end
function M:Pop(id)
 self.typedId=id;self.typeAt=os.clock()
 setVisible(self.title,0);setVisible(self.text,0)
 self.cardScale.Scale=.82;self.card.BackgroundTransparency=1;self.cardStroke.Transparency=1
 Tween:Create(self.cardScale,TweenInfo.new(.28,Enum.EasingStyle.Back,Enum.EasingDirection.Out),{Scale=1}):Play()
 Tween:Create(self.card,TweenInfo.new(.2),{BackgroundTransparency=.12}):Play()
 Tween:Create(self.cardStroke,TweenInfo.new(.2),{Transparency=0}):Play()
end
function M:Type()
 if not self.typeAt or not self.card.Visible then return end
 local t=os.clock()-self.typeAt-.12 -- the background pops first
 local titleLen=glyphs(self.title.Text);local n=math.floor(t*TITLE_CPS)
 setVisible(self.title,n>=titleLen and -1 or math.max(0,n))
 local bodyLen=glyphs(self.text.Text);local m=math.floor((t-titleLen/TITLE_CPS-.08)*BODY_CPS)
 setVisible(self.text,m>=bodyLen and -1 or math.max(0,m))
 if n>=titleLen and m>=bodyLen then self.typeAt=nil end
end
function M:Show(step,data)
 local device=self.hints.Get();local camera=workspace.CurrentCamera;local v=camera and camera.ViewportSize or Vector2.new(1280,720)
 self.card.Visible=step~=nil
 if not step then self.currentStep=nil;self.typedId=nil;if self.buttonConnection then self.buttonConnection:Disconnect();self.buttonConnection=nil end;self.button=nil;self.mark.Enabled=false;self.glow.Enabled=false;self:Spotlight(nil,false);self:HideRoute();return end
 self.currentStep=step
 if self.button~=data.button then
  if self.buttonConnection then self.buttonConnection:Disconnect();self.buttonConnection=nil end;self.button=data.button
  if self.button then self.buttonConnection=self.button.Activated:Connect(function()local current=self.currentStep;if current then self:Dismiss(current.action,current.id)end end)end
 end
 self.gui:SetAttribute('CurrentStep',step.id);self.gui:SetAttribute('SharedStep',step.shared==true)
 -- Phones: a small card at the top centre, clear of the thumbs and the action buttons; no key art.
 -- Tablets (touch, 500+ px tall): the full-size card at the bottom middle like the computer, easier to read (owner 2026-10-26).
 local touch=device=='touch';local phone=touch and v.Y<500;local width=math.min(phone and 260 or 320,v.X-24)
 self.card.AnchorPoint=phone and Vector2.new(.5,0)or Vector2.new(.5,1)
 self.card.Size=UDim2.fromOffset(width,phone and 56 or 64)
 self.card.Position=phone and UDim2.new(.5,0,0,6)or UDim2.new(.5,0,1,touch and -110 or -100)
 self.icon.Visible=not touch
 local left=touch and 12 or 60
 self.title.Position=UDim2.fromOffset(left,6);self.title.Size=UDim2.new(1,-left-56,0,18);self.title.Text=data.title
 self.text.Position=UDim2.fromOffset(left,26);self.text.Size=UDim2.new(1,-left-12,0,touch and 24 or 32);self.text.Text=data.text
 if self.typedId~=step.id then self:Pop(step.id)end
 self.progress.Visible=false
 self:Button(step.action,device)
 local maskKey=step.action=='crouch'and 'crouch'or step.id
 self:Spotlight(data.button,device=='touch'and data.button~=nil and not self.dismissed[maskKey]and os.clock()>=self.maskResumeAt)
 self.mark.Adornee=typeof(data.targetPart)=='Instance'and data.targetPart or nil;self.mark.Enabled=self.mark.Adornee~=nil;self.markText.Text=data.targetName or ''
 self.glow.Adornee=typeof(data.targetModel)=='Instance'and data.targetModel or nil;self.glow.Enabled=self.glow.Adornee~=nil
 -- Owner 2026-10-29: the thin white outline was hard to see on phones. Phones: a solid outline and a soft white fill
 -- over the target (the cart lights up); other devices: a firmer outline.
 local touchTarget=self.hints~=nil and self.hints.Get()=='touch'
 self.glow.OutlineTransparency=touchTarget and 0 or .15;self.glow.FillTransparency=touchTarget and .68 or .9
 self.route.Parent=workspace
 self:DoorPassage(data.map)
 self:Route(data.from,data.goal,data.goalKey,data.push)
end
function M:Destroy()
 self.generation+=1;self:HideRoute()
 if self.typeConnection then self.typeConnection:Disconnect();self.typeConnection=nil end
 if self.edgeConn then self.edgeConn:Disconnect();self.edgeConn=nil end
 if self.buttonConnection then self.buttonConnection:Disconnect();self.buttonConnection=nil end
 self.currentStep=nil;local pulse=self.pulse;self.pulse=nil;if pulse then pulse:Destroy()end
 for _,m in self.modifiers do if m.Parent then m:Destroy()end end
 self.route:Destroy();self.gui:Destroy()
end
return M
