local Services = {
	Players = game:GetService("Players"),
	Heartbeat = game:GetService("RunService").Heartbeat,
	Input = game:GetService("UserInputService"),
	Tweens = game:GetService("TweenService"),
	Workspace = game:GetService("Workspace")
}

local Me = Services.Players.LocalPlayer
local Character = Me.Character or Me.CharacterAdded:Wait()
local Root = Character:WaitForChild("HumanoidRootPart")
local Hum = Character:FindFirstChildOfClass("Humanoid")

local Settings = {
	Speed = 120,
	Angle = 120,
	Gap = 2.5,
	MaxRange = 40,
	MinDist = 15,
	ThresholdStop = 10,
	BlendRate = 0.7,
	AimTime = 0.7,
	VelPredict = 0.5,
	AimCurve = 200,
	CirclePoint = 390 / 480
}

local Anims = {
	[10449761463] = {L = 10480796021, R = 10480793962, F = 10479335397},
	[13076380114] = {L = 101843860692381, R = 100087324592640, F = 110878031211717}
}

local Maps = Anims[game.PlaceId] or Anims[13076380114]

local State = {
	Dashing = false,
	SideTrack = nil,
	RotLock = false,
	RotConn = nil,
	Target = nil,
	M1 = false,
	Dash = false,
	Settings = {Speed = 84, Angle = 56, Gap = 50}
}

local function ValidChar()
	if not (Hum and Hum.Parent) then return false end
	if Hum.Health <= 0 then return false end
	if Hum.PlatformStand then return false end
	local ok, st = pcall(function() return Hum:GetState() end)
	if ok and st == Enum.HumanoidStateType.Physics then return false end
	local rag = Character:FindFirstChild("Ragdoll")
	return not (rag and rag:IsA("BoolValue") and rag.Value)
end

Me.CharacterAdded:Connect(function(nc)
	Character = nc
	Root = nc:WaitForChild("HumanoidRootPart")
	Hum = nc:FindFirstChildOfClass("Humanoid")
	task.wait(0.05)
	ProtectRotation()
end)

local function ProtectRotation()
	if State.RotConn then
		pcall(function() State.RotConn:Disconnect() end)
		State.RotConn = nil
	end
	local h = Character:FindFirstChildOfClass("Humanoid")
	if h then
		State.RotConn = h:GetPropertyChangedSignal("AutoRotate"):Connect(function()
			if State.RotLock and h.AutoRotate then
				pcall(function() h.AutoRotate = false end)
			end
		end)
	end
end

ProtectRotation()

local function NormAng(a1, a2)
	local d = a1 - a2
	while math.pi < d do d = d - 2 * math.pi end
	while d < -math.pi do d = d + 2 * math.pi end
	return d
end

local function EaseC(t)
	return 1 - (1 - math.clamp(t, 0, 1)) ^ 3
end

local function GetAnim()
	if not (Character and Character.Parent) then return nil, nil end
	local h = Character:FindFirstChildOfClass("Humanoid")
	if not h then return nil, nil end
	local a = h:FindFirstChildOfClass("Animator")
	if not a then
		a = Instance.new("Animator")
		a.Name = "Animator"
		a.Parent = h
	end
	return h, a
end

local function PlaySide(isLeft)
	pcall(function()
		if State.SideTrack and State.SideTrack.IsPlaying then
			State.SideTrack:Stop()
		end
	end)
	State.SideTrack = nil
	local h, a = GetAnim()
	if not (h and a) then return end
	local id = isLeft and Maps.L or Maps.R
	local ao = Instance.new("Animation")
	ao.Name = "SideMv"
	ao.AnimationId = "rbxassetid://" .. tostring(id)
	local ok, tr = pcall(function() return a:LoadAnimation(ao) end)
	if not (ok and tr) then
		pcall(function() ao:Destroy() end)
		return
	end
	State.SideTrack = tr
	tr.Priority = Enum.AnimationPriority.Action
	pcall(function() tr.Looped = false end)
	tr:Play()
	delay(0.85 + 0.15, function()
		pcall(function()
			if tr and tr.IsPlaying then tr:Stop() end
		end)
		pcall(function() ao:Destroy() end)
	end)
end

local function FindNear()
	local cl, cd = nil, math.huge
	local or = Root.Position
	for _, p in pairs(Services.Players:GetPlayers()) do
		if p ~= Me and p.Character then
			local ph = p.Character:FindFirstChildOfClass("Humanoid")
			local pr = p.Character:FindFirstChild("HumanoidRootPart")
			if ph and pr and ph.Health > 0 then
				local d = (pr.Position - or).Magnitude
				if d < cd and d <= Settings.MaxRange then
					cl = p.Character
					cd = d
				end
			end
		end
	end
	for _, e in pairs(Services.Workspace:GetDescendants()) do
		if e:IsA("Model") and e:FindFirstChild("Humanoid") and e:FindFirstChild("HumanoidRootPart") then
			if not Services.Players:GetPlayerFromCharacter(e) then
				local eh = e:FindFirstChild("Humanoid")
				local er = e:FindFirstChild("HumanoidRootPart")
				if eh and eh.Health > 0 then
					local d = (er.Position - or).Magnitude
					if d < cd and d <= Settings.MaxRange then
						cl = e
						cd = d
					end
				end
			end
		end
	end
	return cl
end

Services.Players.PlayerRemoving:Connect(function(rm)
	if State.Target == rm then
		State.Target = nil
	end
end)

local function GetTgt()
	if State.Target then
		if State.Target.Character and State.Target.Character.Parent then
			local tc = State.Target.Character
			local tr = tc:FindFirstChild("HumanoidRootPart")
			local th = tc:FindFirstChild("Humanoid")
			if tr and th and th.Health > 0 then
				if (tr.Position - Root.Position).Magnitude <= Settings.MaxRange then
					return tc
				end
			end
			State.Target = nil
		else
			State.Target = nil
		end
	end
	return FindNear()
end

-- ur gay wasp
local function AimPos(tp, bf)
	bf = bf or 0.7
	pcall(function()
		local o = Root.Position
		local lv = Root.CFrame.LookVector
		local d = tp - o
		local hd = Vector3.new(d.X, 0, d.Z)
		if hd.Magnitude < 0.001 then hd = Vector3.new(1, 0, 0) end
		local td = hd.Unit
		local fl = Vector3.new(td.X, lv.Y, td.Z)
		if fl.Magnitude < 0.001 then
			fl = Vector3.new(td.X, lv.Y, td.Z + 0.0001)
		end
		local bl = lv:Lerp(fl.Unit, bf)
		if bl.Magnitude < 0.001 then
			bl = Vector3.new(fl.Unit.X, lv.Y, fl.Unit.Z)
		end
		Root.CFrame = CFrame.new(o, o + bl.Unit)
	end)
end

local function SmthAim(tr, dur)
	dur = dur or Settings.AimTime
	if not (tr and tr.Parent) then return end
	local st = tick()
	local cn = nil
	cn = Services.Heartbeat:Connect(function()
		if not (tr and tr.Parent) then
			cn:Disconnect()
			return
		end
		local el = tick() - st
		local pr = math.clamp(el / dur, 0, 1)
		local ez = 1 - (1 - pr) ^ math.max(1, Settings.AimCurve)
		local tp = tr.Position
		local tv = Vector3.new(0, 0, 0)
		pcall(function()
			tv = tr:GetVelocity() or tr.Velocity or Vector3.new(0, 0, 0)
		end)
		local pp = tp + Vector3.new(tv.X, 0, tv.Z) * Settings.VelPredict
		pcall(function()
			local o = Root.Position
			local lv = Root.CFrame.LookVector
			local d = pp - o
			local hd = Vector3.new(d.X, 0, d.Z)
			if hd.Magnitude < 0.001 then hd = Vector3.new(1, 0, 0) end
			local td = hd.Unit
			local fl = lv:Lerp(Vector3.new(td.X, lv.Y, td.Z).Unit, ez)
			Root.CFrame = CFrame.new(o, o + fl)
		end)
		if pr >= 1 then cn:Disconnect() end
	end)
end

local function ExecDash(tc, sp)
	sp = sp or Settings.Speed
	local at = Instance.new("Attachment")
	at.Name = "DshAt"
	at.Parent = Root
	local lv = Instance.new("LinearVelocity")
	lv.Name = "DshVel"
	lv.Attachment0 = at
	lv.MaxForce = math.huge
	lv.RelativeTo = Enum.ActuatorRelativeTo.World
	lv.Parent = Root
	local st = nil
	local sa = nil
	if Maps.F then
		local h, a = GetAnim()
		if h and a then
			sa = Instance.new("Animation")
			sa.Name = "StrMv"
			sa.AnimationId = "rbxassetid://" .. tostring(Maps.F)
			local ok, tr = pcall(function() return a:LoadAnimation(sa) end)
			if ok and tr then
				tr.Priority = Enum.AnimationPriority.Movement
				pcall(function() tr.Looped = false end)
				pcall(function() tr:Play() end)
				st = tr
			else
				pcall(function() sa:Destroy() end)
			end
		end
	end
	local ic = false
	local ia = true
	local hb = nil
	hb = Services.Heartbeat:Connect(function()
		if not ia then return end
		if not (tc and tc.Parent and Root and Root.Parent) then
			ia = false
			hb:Disconnect()
			pcall(function() lv:Destroy() end)
			pcall(function() at:Destroy() end)
			pcall(function()
				if st and st.IsPlaying then st:Stop() end
				if sa then sa:Destroy() end
			end)
			return
		end
		local tp = tc.Position
		local d = tp - Root.Position
		local hd = Vector3.new(d.X, 0, d.Z)
		if hd.Magnitude > Settings.ThresholdStop then
			lv.VectorVelocity = hd.Unit * sp
			pcall(function()
				if hd.Magnitude > 0.001 then
					Root.CFrame = CFrame.new(Root.Position, Root.Position + hd.Unit)
				end
			end)
			pcall(function()
				AimPos(tp, 0.56)
			end)
		else
			ic = true
			ia = false
			hb:Disconnect()
			pcall(function() lv:Destroy() end)
			pcall(function() at:Destroy() end)
			pcall(function()
				if st and st.IsPlaying then st:Stop() end
				if sa then sa:Destroy() end
			end)
		end
	end)
	repeat task.wait() until ic or not (tc and tc.Parent and Root and Root.Parent)
end

local function SendSrv(d)
	pcall(function()
		if Character and Character:FindFirstChild("Communicate") then
			Character.Communicate:FireServer(unpack(d))
		end
	end)
end

local function DoDash(tc)
	if State.Dashing then return end
	if not (tc and tc:FindFirstChild("HumanoidRootPart")) then return end
	if not Root then return end
	State.Dashing = true
	local ch = Character:FindFirstChildOfClass("Humanoid")
	local or = nil
	if ch then
		or = ch.AutoRotate
		State.RotLock = true
		pcall(function() ch.AutoRotate = false end)
	end
	local function Rst()
		if ch and or ~= nil then
			State.RotLock = false
			pcall(function() ch.AutoRotate = or end)
		end
	end
	local sp = (State.Settings.Speed or 84) / 100 * 60 + 60
	local ang = (State.Settings.Angle or 56) / 100 * 990 + 90
	local gp = (State.Settings.Gap or 50) / 100 * 11 + 1
	local tr = tc.HumanoidRootPart
	if Settings.MinDist <= (tr.Position - Root.Position).Magnitude then
		ExecDash(tr, sp)
	end
	if not (tr and tr.Parent and Root and Root.Parent) then
		Rst()
		State.Dashing = false
		return
	end
	local tp = tr.Position
	local cp = Root.Position
	local cr = Root.CFrame.RightVector
	local d = tr.Position - Root.Position
	if d.Magnitude < 0.001 then d = Root.CFrame.LookVector end
	local il = cr:Dot(d.Unit) < 0
	PlaySide(il)
	local dm = il and 1 or -1
	local at = math.atan2(cp.Z - tp.Z, cp.X - tp.X)
	local hd = (Vector3.new(cp.X, 0, cp.Z) - Vector3.new(tp.X, 0, tp.Z)).Magnitude
	local cd = math.clamp(hd, 1.2, 60)
	local st = tick()
	local mc = nil
	local as = false
	local cc = false
	local se = false
	local df = false
	local function BE()
		if not cc then
			cc = true
			task.delay(Settings.AimTime, function()
				se = true
				Rst()
				if df then State.Dashing = false end
			end)
		end
	end
	if State.M1 then
		SendSrv({{Mobile = true, Goal = "LeftClick"}})
		task.delay(0.05, function()
			SendSrv({{Goal = "LeftClickRelease", Mobile = true}})
		end)
	end
	if State.Dash then
		SendSrv({{Dash = Enum.KeyCode.W, Key = Enum.KeyCode.Q, Goal = "KeyPress"}})
	end
	mc = Services.Heartbeat:Connect(function()
		local el = tick() - st
		local pr = math.clamp(el / 0.85, 0, 1)
		local ez = EaseC(pr)
		local ap = math.clamp(pr * 1.5, 0, 1)
		local cr = cd + (gp - cd) * EaseC(ap)
		local cr2 = math.clamp(cr, 1.2, 60)
		local ca = at + dm * math.rad(ang) * EaseC(pr)
		local ctp = tr.Position
		local ty = ctp.Y
		local cx = ctp.X + cr2 * math.cos(ca)
		local cz = ctp.Z + cr2 * math.sin(ca)
		local np = Vector3.new(cx, ty, cz)
		if tr then ctp = tr.Position or ctp end
		local ap2 = math.atan2((ctp - np).Z, (ctp - np).X)
		local ca2 = math.atan2(Root.CFrame.LookVector.Z, Root.CFrame.LookVector.X)
		local fa = ca2 + NormAng(ap2, ca2) * Settings.BlendRate
		pcall(function()
			Root.CFrame = CFrame.new(np, np + Vector3.new(math.cos(fa), 0, math.sin(fa)))
		end)
		if not as and Settings.CirclePoint <= ez then
			as = true
			pcall(function() SmthAim(tr, Settings.AimTime) end)
			BE()
		end
		if pr >= 1 then
			mc:Disconnect()
			pcall(function()
				if State.SideTrack and State.SideTrack.IsPlaying then
					State.SideTrack:Stop()
				end
				State.SideTrack = nil
			end)
			if not as then
				as = true
				pcall(function() SmthAim(tr, Settings.AimTime) end)
				BE()
			end
			df = true
			if se then State.Dashing = false end
		end
	end)
end

-- ur gay wasp
local UIKit = {
	p = Services.Players,
	tw = Services.Tweens,
	in = Services.Input,
	sg = game:GetService("StarterGui")
}

pcall(function()
	UIKit.sg:SetCore("SendNotification", {
		Title = "Side Dash Assist",
		Text = "E to dash or press button!",
		Duration = 5
	})
end)

pcall(function()
	if setclipboard then
		setclipboard("https://discord.gg/GEVGRzC4ZP")
	end
end)

local mg = Instance.new("ScreenGui")
mg.Name = "DashGUI"
mg.ResetOnSpawn = false
mg.Parent = Me:WaitForChild("PlayerGui")

local bl = Instance.new("BlurEffect")
bl.Size = 0
bl.Parent = game:GetService("Lighting")

local function Drag(obj, canDrag)
	if not canDrag then return end
	local drg = false
	local ds, sp, ci
	obj.InputBegan:Connect(function(i)
		if (i.UserInputType == Enum.UserInputType.Touch or i.UserInputType == Enum.UserInputType.MouseButton1) and not drg then
			drg = true
			ds = i.Position
			sp = obj.Position
			ci = i
			i.Changed:Connect(function()
				if i.UserInputState == Enum.UserInputState.End then
					drg = false
					ci = nil
				end
			end)
		end
	end)
	UIKit.in.InputChanged:Connect(function(i)
		if drg and ci == i and (i.UserInputType == Enum.UserInputType.Touch or i.UserInputType == Enum.UserInputType.MouseMovement) then
			local dt = i.Position - ds
			obj.Position = UDim2.new(sp.X.Scale, sp.X.Offset + dt.X, sp.Y.Scale, sp.Y.Offset + dt.Y)
		end
	end)
end

local mf = Instance.new("Frame")
mf.Name = "Main"
mf.Size = UDim2.new(0, 380, 0, 140)
mf.Position = UDim2.new(0.5, -190, 0.12, 0)
mf.BackgroundColor3 = Color3.fromRGB(15, 15, 15)
mf.BackgroundTransparency = 1
mf.BorderSizePixel = 0
mf.Visible = false
mf.Parent = mg
Drag(mf, true)

local mc = Instance.new("UICorner")
mc.CornerRadius = UDim.new(0, 20)
mc.Parent = mf

local mbg = Instance.new("UIGradient")
mbg.Color = ColorSequence.new({
	ColorSequenceKeypoint.new(0, Color3.fromRGB(25, 5, 5)),
	ColorSequenceKeypoint.new(0.5, Color3.fromRGB(15, 15, 15)),
	ColorSequenceKeypoint.new(1, Color3.fromRGB(0, 0, 0))
})
mbg.Rotation = 90
mbg.Parent = mf

local bf = Instance.new("Frame")
bf.Name = "Border"
bf.Size = UDim2.new(1, 8, 1, 8)
bf.Position = UDim2.new(0, -4, 0, -4)
bf.BackgroundColor3 = Color3.fromRGB(255, 0, 0)
bf.BackgroundTransparency = 1
bf.BorderSizePixel = 0
bf.ZIndex = 0
bf.Parent = mf

local bfc = Instance.new("UICorner")
bfc.CornerRadius = UDim.new(0, 24)
bfc.Parent = bf

local bfg = Instance.new("UIGradient")
bfg.Color = ColorSequence.new({
	ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 0, 0)),
	ColorSequenceKeypoint.new(0.5, Color3.fromRGB(120, 0, 0)),
	ColorSequenceKeypoint.new(1, Color3.fromRGB(26, 26, 26))
})
bfg.Rotation = 45
bfg.Parent = bf

local hf = Instance.new("Frame")
hf.Size = UDim2.new(1, 0, 0, 50)
hf.BackgroundTransparency = 1
hf.Parent = mf

local tl = Instance.new("TextLabel")
tl.Size = UDim2.new(0, 190, 0, 30)
tl.Position = UDim2.new(0, 20, 0, 10)
tl.BackgroundTransparency = 1
tl.Text = "Side Dash Assist"
tl.TextColor3 = Color3.fromRGB(255, 255, 255)
tl.TextSize = 23
tl.Font = Enum.Font.GothamBold
tl.TextXAlignment = Enum.TextXAlignment.Left
tl.TextStrokeTransparency = 0.7
tl.Parent = hf

local vl = Instance.new("TextLabel")
vl.Size = UDim2.new(0, 55, 0, 24)
vl.Position = UDim2.new(0, 215, 0, 13)
vl.BackgroundColor3 = Color3.fromRGB(255, 0, 0)
vl.BorderSizePixel = 0
vl.Text = "v1.0"
vl.TextColor3 = Color3.fromRGB(255, 255, 255)
vl.TextSize = 13
vl.Font = Enum.Font.GothamBold
vl.Parent = hf

local vlc = Instance.new("UICorner")
vlc.CornerRadius = UDim.new(0, 8)
vlc.Parent = vl

local al = Instance.new("TextLabel")
al.Size = UDim2.new(1, -40, 0, 17)
al.Position = UDim2.new(0, 20, 0, 32)
al.BackgroundTransparency = 1
al.Text = "by CPS Network"
al.TextColor3 = Color3.fromRGB(200, 200, 200)
al.TextSize = 13
al.Font = Enum.Font.GothamMedium
al.TextXAlignment = Enum.TextXAlignment.Left
al.TextTransparency = 0.28
al.Parent = hf

local clsb = Instance.new("TextButton")
clsb.Size = UDim2.new(0, 35, 0, 35)
clsb.Position = UDim2.new(1, -45, 0, 7)
clsb.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
clsb.Text = "X"
clsb.Font = Enum.Font.GothamBold
clsb.TextColor3 = Color3.fromRGB(0, 0, 0)
clsb.TextSize = 19
clsb.BorderSizePixel = 0
clsb.Parent = mf

local clsbc = Instance.new("UICorner")
clsbc.CornerRadius = UDim.new(0, 10)
clsbc.Parent = clsb

local minb = Instance.new("TextButton")
minb.Size = UDim2.new(0, 35, 0, 35)
minb.Position = UDim2.new(1, -85, 0, 7)
minb.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
minb.Text = "_"
minb.Font = Enum.Font.GothamBold
minb.TextColor3 = Color3.fromRGB(0, 0, 0)
minb.TextSize = 22
minb.BorderSizePixel = 0
minb.Parent = mf

local minbc = Instance.new("UICorner")
minbc.CornerRadius = UDim.new(0, 10)
minbc.Parent = minb

local bc = Instance.new("Frame")
bc.Size = UDim2.new(0, 200, 0, 48)
bc.Position = UDim2.new(0.5, -100, 0, 72)
bc.BackgroundTransparency = 1
bc.Parent = mf

local tgb = Instance.new("TextButton")
tgb.Size = UDim2.new(1, 0, 1, 0)
tgb.BackgroundTransparency = 1
tgb.BorderSizePixel = 0
tgb.TextColor3 = Color3.fromRGB(255, 255, 255)
tgb.TextSize = 20
tgb.Font = Enum.Font.GothamBold
tgb.AutoButtonColor = false
tgb.ZIndex = 2
tgb.Parent = bc

local bgbg = Instance.new("Frame")
bgbg.Size = UDim2.new(1, 0, 1, 0)
bgbg.BackgroundColor3 = Color3.fromRGB(180, 13, 19)
bgbg.BorderSizePixel = 0
bgbg.ZIndex = 1
bgbg.Parent = bc

local bgc = Instance.new("UICorner")
bgc.CornerRadius = UDim.new(0, 12)
bgc.Parent = bgbg

local bgg = Instance.new("UIGradient")
bgg.Color = ColorSequence.new({
	ColorSequenceKeypoint.new(0, Color3.fromRGB(180, 13, 19)),
	ColorSequenceKeypoint.new(1, Color3.fromRGB(120, 0, 0))
})
bgg.Rotation = 90
bgg.Parent = bgbg

local bgbr = Instance.new("UIStroke")
bgbr.Color = Color3.fromRGB(255, 0, 0)
bgbr.Thickness = 2
bgbr.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
bgbr.Parent = bgbg

local En = true

local function UpdTg()
	if En then
		tgb.Text = "Enabled: ON"
		UIKit.tw:Create(bgbg, TweenInfo.new(0.25), {BackgroundColor3 = Color3.fromRGB(180, 13, 19)}):Play()
		UIKit.tw:Create(bgbr, TweenInfo.new(0.25), {Color = Color3.fromRGB(255, 0, 0)}):Play()
	else
		tgb.Text = "Enabled: OFF"
		UIKit.tw:Create(bgbg, TweenInfo.new(0.25), {BackgroundColor3 = Color3.fromRGB(54, 54, 54)}):Play()
		UIKit.tw:Create(bgbr, TweenInfo.new(0.25), {Color = Color3.fromRGB(110, 110, 110)}):Play()
	end
end

tgb.MouseButton1Click:Connect(function()
	En = not En
	UpdTg()
end)

UpdTg()

local dshbtn = Instance.new("TextButton")
dshbtn.Name = "DashBtn"
dshbtn.Size = UDim2.new(0, 85, 0, 85)
dshbtn.Position = UDim2.new(1, -110, 1, -110)
dshbtn.BackgroundColor3 = Color3.fromRGB(200, 20, 20)
dshbtn.Text = "DASH"
dshbtn.TextColor3 = Color3.fromRGB(255, 255, 255)
dshbtn.TextSize = 18
dshbtn.Font = Enum.Font.GothamBold
dshbtn.BorderSizePixel = 0
dshbtn.Parent = mg
Drag(dshbtn, true)

local dshc = Instance.new("UICorner")
dshc.CornerRadius = UDim.new(1, 0)
dshc.Parent = dshbtn

local dshg = Instance.new("UIGradient")
dshg.Color = ColorSequence.new({
	ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 80, 80)),
	ColorSequenceKeypoint.new(1, Color3.fromRGB(140, 10, 10))
})
dshg.Rotation = 135
dshg.Parent = dshbtn

local dshbr = Instance.new("UIStroke")
dshbr.Color = Color3.fromRGB(255, 100, 100)
dshbr.Thickness = 3
dshbr.Parent = dshbtn

local tch = {}

dshbtn.InputBegan:Connect(function(i)
	if i.UserInputType == Enum.UserInputType.Touch then
		local tid = i
		tch[tid] = true
		if #tch == 1 then
			UIKit.tw:Create(dshbtn, TweenInfo.new(0.1), {BackgroundColor3 = Color3.fromRGB(255, 100, 100)}):Play()
			if En and ValidChar() then
				local t = GetTgt()
				if t then DoDash(t) end
			end
		end
		i.Changed:Connect(function()
			if i.UserInputState == Enum.UserInputState.End then
				tch[tid] = nil
				if #tch == 0 then
					UIKit.tw:Create(dshbtn, TweenInfo.new(0.1), {BackgroundColor3 = Color3.fromRGB(200, 20, 20)}):Play()
				end
			end
		end)
	elseif i.UserInputType == Enum.UserInputType.MouseButton1 then
		UIKit.tw:Create(dshbtn, TweenInfo.new(0.1), {BackgroundColor3 = Color3.fromRGB(255, 100, 100)}):Play()
		if En and ValidChar() then
			local t = GetTgt()
			if t then DoDash(t) end
		end
	end
end)

dshbtn.InputEnded:Connect(function(i)
	if i.UserInputType == Enum.UserInputType.MouseButton1 then
		if #tch == 0 then
			UIKit.tw:Create(dshbtn, TweenInfo.new(0.1), {BackgroundColor3 = Color3.fromRGB(200, 20, 20)}):Play()
		end
	end
end)

local setb = Instance.new("TextButton")
setb.Size = UDim2.new(0, 36, 0, 36)
setb.Position = UDim2.new(0, 10, 1, -46)
setb.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
setb.Text = "⚙"
setb.Font = Enum.Font.GothamBold
setb.TextColor3 = Color3.fromRGB(0, 0, 0)
setb.TextSize = 19
setb.BorderSizePixel = 0
setb.Parent = mf

local setbc = Instance.new("UICorner")
setbc.CornerRadius = UDim.new(1, 0)
setbc.Parent = setb

local seto = Instance.new("Frame")
seto.Name = "SetOverlay"
seto.Size = UDim2.new(0, 300, 0, 240)
seto.Position = UDim2.new(0, 40, 0.2, 0)
seto.BackgroundColor3 = Color3.fromRGB(15, 15, 15)
seto.BackgroundTransparency = 1
seto.BorderSizePixel = 0
seto.Visible = false
seto.Parent = mg
Drag(seto, true)

local setoc = Instance.new("UICorner")
setoc.CornerRadius = UDim.new(0, 19)
setoc.Parent = seto

local setog = Instance.new("UIGradient")
setog.Color = ColorSequence.new({
	ColorSequenceKeypoint.new(0, Color3.fromRGB(25, 5, 5)),
	ColorSequenceKeypoint.new(0.5, Color3.fromRGB(15, 15, 15)),
	ColorSequenceKeypoint.new(1, Color3.fromRGB(0, 0, 0))
})
setog.Rotation = 90
setog.Parent = seto

local sett = Instance.new("TextLabel")
sett.Size = UDim2.new(1, -60, 0, 40)
sett.Position = UDim2.new(0, 16, 0, 5)
sett.BackgroundTransparency = 1
sett.Text = "Settings"
sett.TextColor3 = Color3.fromRGB(255, 255, 255)
sett.TextSize = 21
sett.Font = Enum.Font.GothamBold
sett.TextXAlignment = Enum.TextXAlignment.Left
sett.Parent = seto

local setclsb = Instance.new("TextButton")
setclsb.Size = UDim2.new(0, 35, 0, 35)
setclsb.Position = UDim2.new(1, -45, 0, 6)
setclsb.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
setclsb.Text = "X"
setclsb.Font = Enum.Font.GothamBold
setclsb.TextColor3 = Color3.fromRGB(0, 0, 0)
setclsb.TextSize = 19
setclsb.BorderSizePixel = 0
setclsb.Parent = seto

local setclsc = Instance.new("UICorner")
setclsc.CornerRadius = UDim.new(0, 10)
setclsc.Parent = setclsb

local slnames = {"Dash speed", "Dash Angle", "Dash Gap"}
for idx, nm in ipairs(slnames) do
	local lbl = Instance.new("TextLabel")
	lbl.Parent = seto
	lbl.BackgroundTransparency = 1
	lbl.Text = nm
	lbl.Font = Enum.Font.Gotham
	lbl.TextColor3 = Color3.fromRGB(120, 120, 120)
	lbl.TextScaled = true
	lbl.TextXAlignment = Enum.TextXAlignment.Left
	lbl.Size = UDim2.new(0, 120, 0, 20)
	lbl.Position = UDim2.new(0.04, 0, 0.18 + (idx - 1) * 0.24, 0)
	
	local slc = Instance.new("Frame")
	slc.Parent = seto
	slc.BackgroundTransparency = 1
	slc.Size = UDim2.new(0, 160, 0, 24)
	slc.Position = UDim2.new(0.38, 5, 0.18 + (idx - 1) * 0.24, 0)
	
	local slt = Instance.new("Frame")
	slt.Parent = slc
	slt.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	slt.BackgroundTransparency = 0.7
	slt.Size = UDim2.new(1, -20, 0, 6)
	slt.Position = UDim2.new(0, 10, 0.5, -3)
	Instance.new("UICorner", slt).CornerRadius = UDim.new(1, 0)
	
	local slh = Instance.new("TextButton")
	slh.Parent = slc
	slh.BackgroundColor3 = Color3.fromRGB(180, 180, 180)
	slh.Size = UDim2.new(0, 20, 0, 20)
	slh.Position = UDim2.new(0, -10, 0.5, -10)
	slh.Text = ""
	slh.AutoButtonColor = false
	slh.ZIndex = 2
	Instance.new("UICorner", slh).CornerRadius = UDim.new(1, 0)
	
	local vl = Instance.new("TextLabel")
	vl.Parent = seto
	vl.Size = UDim2.new(0, 70, 0, 20)
	vl.Position = UDim2.new(0.82, 0, 0.18 + (idx - 1) * 0.24, 0)
	vl.BackgroundTransparency = 1
	vl.Font = Enum.Font.GothamBold
	vl.TextColor3 = Color3.fromRGB(25, 25, 25)
	vl.TextSize = 14
	vl.Text = "0"
	
	local drg2 = false
	local skey = string.sub(nm, 6)
	local dval = State.Settings[skey] or (nm == "Dash speed" and 84 or nm == "Dash Angle" and 56 or 50)
	slh.Position = UDim2.new(dval / 100, -10, 0.5, -10)
	State.Settings[skey] = dval
	
	local function updv()
		vl.Text = tostring(dval)
	end
	updv()
	
	local function upslpos(ix)
		local tw = slt.AbsoluteSize.X
		local tp = slt.AbsolutePosition.X
		if tw ~= 0 then
			local cp = math.clamp((ix - tp) / tw, 0, 1)
			slh.Position = UDim2.new(cp, -10, 0.5, -10)
			dval = math.floor(cp * 100)
			State.Settings[skey] = dval
			updv()
		end
	end
	
	slh.InputBegan:Connect(function(i)
		if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
			drg2 = true
			i.Changed:Connect(function()
				if i.UserInputState == Enum.UserInputState.End then drg2 = false end
			end)
		end
	end)
	
	UIKit.in.InputChanged:Connect(function(i)
		if drg2 and (i.UserInputType == Enum.UserInputType.MouseMovement or i.UserInputType == Enum.UserInputType.Touch) then
			upslpos(i.Position.X)
		end
	end)
end

local openb = Instance.new("TextButton")
openb.Name = "OpenBtn"
openb.Size = UDim2.new(0, 90, 0, 34)
openb.Position = UDim2.new(0, 10, 0.5, -17)
openb.BackgroundColor3 = Color3.fromRGB(25, 25, 25)
openb.Text = "Open GUI"
openb.TextColor3 = Color3.fromRGB(255, 255, 255)
openb.TextSize = 15
openb.Font = Enum.Font.GothamBold
openb.BorderSizePixel = 0
openb.Visible = false
openb.Parent = mg

local openbc = Instance.new("UICorner")
openbc.CornerRadius = UDim.new(0, 10)
openbc.Parent = openb
Drag(openb, true)

local function SetTr(al)
	mf.BackgroundTransparency = al
	bf.BackgroundTransparency = al
	tl.TextTransparency = al
	al.TextTransparency = 0.28 + (al * 0.7)
	vl.TextTransparency = al
	tgb.TextTransparency = al
	clsb.TextTransparency = al
	minb.TextTransparency = al
	setb.TextTransparency = al
end

local function FIn()
	mf.Visible = true
	SetTr(1)
	UIKit.tw:Create(bl, TweenInfo.new(0.3), {Size = 12}):Play()
	UIKit.tw:Create(mf, TweenInfo.new(0.3), {BackgroundTransparency = 0}):Play()
	UIKit.tw:Create(bf, TweenInfo.new(0.3), {BackgroundTransparency = 0}):Play()
	UIKit.tw:Create(tl, TweenInfo.new(0.3), {TextTransparency = 0}):Play()
	UIKit.tw:Create(al, TweenInfo.new(0.3), {TextTransparency = 0.28}):Play()
	UIKit.tw:Create(vl, TweenInfo.new(0.3), {TextTransparency = 0}):Play()
	UIKit.tw:Create(tgb, TweenInfo.new(0.3), {TextTransparency = 0}):Play()
	UIKit.tw:Create(clsb, TweenInfo.new(0.3), {TextTransparency = 0}):Play()
	UIKit.tw:Create(minb, TweenInfo.new(0.3), {TextTransparency = 0}):Play()
	UIKit.tw:Create(setb, TweenInfo.new(0.3), {TextTransparency = 0}):Play()
end

local function FOt(cb)
	local t1 = UIKit.tw:Create(bl, TweenInfo.new(0.3), {Size = 0})
	local t2 = UIKit.tw:Create(mf, TweenInfo.new(0.3), {BackgroundTransparency = 1})
	local t3 = UIKit.tw:Create(bf, TweenInfo.new(0.3), {BackgroundTransparency = 1})
	t1:Play() t2:Play() t3:Play()
	t2.Completed:Connect(function()
		mf.Visible = false
		if cb then cb() end
	end)
end

local function FSIn()
	seto.Visible = true
	UIKit.tw:Create(seto, TweenInfo.new(0.25), {BackgroundTransparency = 0}):Play()
end

local function FSOut()
	local t = UIKit.tw:Create(seto, TweenInfo.new(0.25), {BackgroundTransparency = 1})
	t:Play()
	t.Completed:Connect(function() seto.Visible = false end)
end

clsb.MouseButton1Click:Connect(function() FOt() end)
minb.MouseButton1Click:Connect(function() FOt(function() openb.Visible = true end) end)
openb.MouseButton1Click:Connect(function() openb.Visible = false FIn() end)
setb.MouseButton1Click:Connect(function() FSIn() end)
setclsb.MouseButton1Click:Connect(function() FSOut() end)

FIn()

UIKit.in.InputBegan:Connect(function(i, gp)
	if gp then return end
	if not En then return end
	if i.KeyCode == Enum.KeyCode.E then
		if not ValidChar() then return end
		local t = GetTgt()
		if t then DoDash(t) end
	end
end)

-- ur gay wasp
