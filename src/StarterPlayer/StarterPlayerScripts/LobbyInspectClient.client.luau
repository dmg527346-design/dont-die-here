-- Lobby inspect (owner 2026-10-29): every cosmetic stand plaque and the Curio Cabinet card can be read up close. INSPECT
-- (R / gamepad Y / tap the prompt) glides the camera into first person square in front of the panel (InspectCamera);
-- the same key, B, Escape or the BACK button glides back. The plaque's own BUY button still works while inspecting.
-- Panels: parts named Plaque / CurioCard under LobbyWorld.Showcase (built by LobbyShowcaseServer); readable side = Front.
local Players=game:GetService('Players')
local RS=game:GetService('ReplicatedStorage')
local CAS=game:GetService('ContextActionService')
local GuiService=game:GetService('GuiService')
local PromptService=game:GetService('ProximityPromptService')
local Inspect=require(RS:WaitForChild('InspectCamera'))
local InputHints=require(RS:WaitForChild('InputHints'))
local p=Players.LocalPlayer
local pg=p:WaitForChild('PlayerGui')
local PANELS={Plaque=true,CurioCard=true}
local KEY,PAD=Enum.KeyCode.R,Enum.KeyCode.ButtonY

local function addPrompt(part)
 if not part:IsA('BasePart')or not PANELS[part.Name]or part:FindFirstChild('InspectPrompt')then return end
 local prompt=Instance.new('ProximityPrompt');prompt.Name='InspectPrompt';prompt.ActionText='Look closer';prompt.ObjectText=''
 prompt.KeyboardKeyCode=KEY;prompt.GamepadKeyCode=PAD;prompt.HoldDuration=0;prompt.MaxActivationDistance=9;prompt.RequiresLineOfSight=false
 prompt.UIOffset=Vector2.new(0,-60) -- above the Buy prompt on the same plaque
 prompt.Parent=part
end
task.spawn(function()
 local show=workspace:WaitForChild('LobbyWorld',math.huge):WaitForChild('Showcase',math.huge)
 for _,d in show:GetDescendants()do addPrompt(d)end
 show.DescendantAdded:Connect(function(d)task.defer(addPrompt,d)end)
end)

local current -- {part, prompt, gui}
local function leave()
 local c=current;if not c then return end
 current=nil
 CAS:UnbindAction('LobbyInspectBack')
 if c.gui then c.gui:Destroy()end
 if c.prompt and c.prompt.Parent then c.prompt.Enabled=true end
 GuiService.SelectedObject=nil
 task.spawn(Inspect.End,.5)
end
local function backHint()
 local device=InputHints.Get()
 if device=='touch'then return'BACK'elseif device=='pad'then return'(Y) BACK'end
 return'[R] BACK'
end
local function enter(part,prompt)
 if current or Inspect.Active()or p:GetAttribute('MissionActive')==true then return end
 current={part=part,prompt=prompt}
 prompt.Enabled=false
 -- The BACK button: big enough for thumbs, bottom centre, clear of the plaque.
 local gui=Instance.new('ScreenGui');gui.Name='LobbyInspectBack';gui.ResetOnSpawn=false;gui.IgnoreGuiInset=true;gui.DisplayOrder=200;gui.Parent=pg;current.gui=gui
 local b=Instance.new('TextButton');b.Name='Back';b.AnchorPoint=Vector2.new(.5,1);b.Position=UDim2.new(.5,0,1,-18);b.Size=UDim2.fromOffset(200,52)
 b.BackgroundColor3=Color3.fromRGB(24,30,30);b.BackgroundTransparency=.1;b.TextColor3=Color3.fromRGB(214,232,220);b.TextSize=16;b.Text=backHint();b.Parent=gui
 local c=Instance.new('UICorner');c.CornerRadius=UDim.new(0,10);c.Parent=b
 local s=Instance.new('UIStroke');s.Color=Color3.fromRGB(70,92,84);s.Thickness=2;s.ApplyStrokeMode=Enum.ApplyStrokeMode.Border;s.Parent=b
 b.Activated:Connect(leave)
 CAS:BindActionAtPriority('LobbyInspectBack',function(_,state)
  if state==Enum.UserInputState.Begin then leave()end;return Enum.ContextActionResult.Sink
 end,false,3000,KEY,PAD,Enum.KeyCode.ButtonB,Enum.KeyCode.Escape)
 task.spawn(Inspect.Begin,Inspect.FrameFor(part.CFrame,Vector2.new(part.Size.X,part.Size.Y),.76),.75,'lobbyInspect')
end
PromptService.PromptTriggered:Connect(function(prompt)
 if prompt.Name=='InspectPrompt'and prompt.Parent and PANELS[prompt.Parent.Name]then enter(prompt.Parent,prompt)end
end)
p:GetAttributeChangedSignal('MissionActive'):Connect(function()if p:GetAttribute('MissionActive')==true and current then current=nil;CAS:UnbindAction('LobbyInspectBack');Inspect.Cancel()end end)
p.CharacterAdded:Connect(function()if current then local c=current;current=nil;CAS:UnbindAction('LobbyInspectBack');if c.gui then c.gui:Destroy()end;Inspect.Cancel()end end)
