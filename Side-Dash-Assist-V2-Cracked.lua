-- SIDE DASH ASSIST V1.0 - CORE

local Services = {
	Players   = game:GetService("Players"),
	Run       = game:GetService("RunService"),
	Input     = game:GetService("UserInputService"),
	Tweens    = game:GetService("TweenService"),
	Workspace = game:GetService("Workspace"),
	Starter   = game:GetService("StarterGui")
}

local LocalPlayer = Services.Players.LocalPlayer
local Character   = LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
local Root        = Character:WaitForChild("HumanoidRootPart")
local Humanoid    = Character:FindFirstChildOfClass("Humanoid")

-- dash behaviour tuning
local DashProfile = {
	SpeedBase     = 60,
	SpeedScale    = 60,   -- affected by slider
	DistanceMin   = 1.2,
	DistanceMax   = 60,
	StopThreshold = 10,
	MinStartRange = 15
}

-- aim + path shaping
local AimProfile = {
	MaxRange      = 40,
	BlendStrength = 0.7,
	TimeToAim     = 0.7,
	VelocityBias  = 0.5,
	CurvePower    = 200,
	ArcProgress   = 390/480
}

-- timing + angles
local MotionProfile = {
	Duration      = 0.85,
	BaseAngleDeg  = 90,
	AngleSpread   = 990   -- extra from slider
}

-- animation map (per place)
local AnimationMap = {
	[10449761463] = { Left = 10480796021, Right = 10480793962, Forward = 10479335397 },
	[13076380114] = { Left = 101843860692381, Right = 100087324592640, Forward = 110878031211717 }
}

local ActiveAnim = AnimationMap[game.PlaceId] or AnimationMap[13076380114]

-- runtime state
local State = {
	IsDashing   = false,
	SideTrack   = nil,
	RotLock     = false,
	RotConn     = nil,
	TargetStore = nil,
	Flags = {
		Click     = false,
		ForceDash = false
	},
	Sliders = {
		Speed    = 84,
		Angle    = 56,
		Distance = 50
	}
}

-- utility: character valid
local function IsValidCharacter()
	if not (Humanoid and Humanoid.Parent) then return false end
	if Humanoid.Health <= 0 then return false end
	if Humanoid.PlatformStand then return false end
	local ok, st = pcall(function() return Humanoid:GetState() end)
	if ok and st == Enum.HumanoidStateType.Physics then return false end
	local rag = Character:FindChildWhichIsA("BoolValue")
	if rag and rag.Name:lower():find("rag") and rag.Value then
		return false
	end
	return true
end

-- handle respawn
local function BindRotationGuard()
	if State.RotConn then
		pcall(function() State.RotConn:Disconnect() end)
		State.RotConn = nil
	end
	local h = Character:FindFirstChildOfClass("Humanoid")
	if not h then return end
	State.RotConn = h:GetPropertyChangedSignal("AutoRotate"):Connect(function()
		if State.RotLock and h.AutoRotate then
			pcall(function() h.AutoRotate = false end)
		end
	end)
end

LocalPlayer.CharacterAdded:Connect(function(newChar)
	Character = newChar
	Root      = newChar:WaitForChild("HumanoidRootPart")
	Humanoid  = newChar:FindFirstChildOfClass("Humanoid")
	task.wait(0.05)
	BindRotationGuard()
end)

BindRotationGuard()

-- math helpers
local function NormalizeAngle(a1, a2)
	local d = a1 - a2
	while d > math.pi do d = d - 2*math.pi end
	while d < -math.pi do d = d + 2*math.pi end
	return d
end

local function EaseCubic01(t)
	t = math.clamp(t, 0, 1)
	return 1 - (1 - t)^3
end

-- animator
local function GetAnimator()
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

local function PlaySideAnimation(isLeft)
	pcall(function()
		if State.SideTrack and State.SideTrack.IsPlaying then
			State.SideTrack:Stop()
		end
	end)
	State.SideTrack = nil

	local hum, anim = GetAnimator()
	if not (hum and anim) then return end

	local chosenId = isLeft and ActiveAnim.Left or ActiveAnim.Right
	local animObj = Instance.new("Animation")
	animObj.Name = "SideDash"
	animObj.AnimationId = "rbxassetid://" .. tostring(chosenId)

	local ok, track = pcall(function() return anim:LoadAnimation(animObj) end)
	if not (ok and track) then
		pcall(function() animObj:Destroy() end)
		return
	end

	State.SideTrack = track
	track.Priority = Enum.AnimationPriority.Action
	pcall(function() track.Looped = false end)
	track:Play()

	delay(MotionProfile.Duration + 0.15, function()
		pcall(function()
			if track and track.IsPlaying then track:Stop() end
		end)
		pcall(function() animObj:Destroy() end)
	end)
end

-- target search
local function FindClosestTarget()
	local origin = Root.Position
	local closest, bestDist = nil, math.huge

	for _, plr in ipairs(Services.Players:GetPlayers()) do
		if plr ~= LocalPlayer and plr.Character then
			local h = plr.Character:FindFirstChildOfClass("Humanoid")
			local r = plr.Character:FindFirstChild("HumanoidRootPart")
			if h and r and h.Health > 0 then
				local d = (r.Position - origin).Magnitude
				if d < bestDist and d <= AimProfile.MaxRange then
					closest, bestDist = plr.Character, d
				end
			end
		end
	end

	for _, inst in ipairs(Services.Workspace:GetDescendants()) do
		if inst:IsA("Model") and inst:FindFirstChild("Humanoid") and inst:FindFirstChild("HumanoidRootPart") then
			if not Services.Players:GetPlayerFromCharacter(inst) then
				local h = inst:FindFirstChild("Humanoid")
				local r = inst:FindFirstChild("HumanoidRootPart")
				if h and h.Health > 0 then
					local d = (r.Position - origin).Magnitude
					if d < bestDist and d <= AimProfile.MaxRange then
						closest, bestDist = inst, d
					end
				end
			end
		end
	end

	return closest
end

Services.Players.PlayerRemoving:Connect(function(removed)
	if State.TargetStore == removed then
		State.TargetStore = nil
	end
end)

local function AcquireTarget()
	if State.TargetStore and State.TargetStore.Character and State.TargetStore.Character.Parent then
		local ch = State.TargetStore.Character
		local r = ch:FindFirstChild("HumanoidRootPart")
		local h = ch:FindFirstChild("Humanoid")
		if r and h and h.Health > 0 then
			if (r.Position - Root.Position).Magnitude <= AimProfile.MaxRange then
				return ch
			end
		end
		State.TargetStore = nil
	end
	return FindClosestTarget()
end

-- export for next snippets
_G.SideDash_Core = {
	Services      = Services,
	LocalPlayer   = LocalPlayer,
	GetAnimator   = GetAnimator,
	PlaySide      = PlaySideAnimation,
	AcquireTarget = AcquireTarget,
	IsValid       = IsValidCharacter,
	State         = State,
	DashProfile   = DashProfile,
	AimProfile    = AimProfile,
	MotionProfile = MotionProfile,
	ActiveAnim    = ActiveAnim,
	NormalizeAng  = NormalizeAngle,
	EaseCubic01   = EaseCubic01
}

-- ur gay wasp
-- SIDE DASH ASSIST V1.0 - MOVEMENT

local Core = _G.SideDash_Core
local Services      = Core.Services
local LocalPlayer   = Core.LocalPlayer
local State         = Core.State
local DashProfile   = Core.DashProfile
local AimProfile    = Core.AimProfile
local MotionProfile = Core.MotionProfile
local ActiveAnim    = Core.ActiveAnim
local GetAnimator   = Core.GetAnimator
local PlaySide      = Core.PlaySide
local AcquireTarget = Core.AcquireTarget
local IsValid       = Core.IsValid
local NormalizeAng  = Core.NormalizeAng
local EaseCubic01   = Core.EaseCubic01

local Character = LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
local Root      = Character:WaitForChild("HumanoidRootPart")

local function AimTowards(position, blend)
	blend = blend or AimProfile.BlendStrength
	pcall(function()
		local origin = Root.Position
		local look   = Root.CFrame.LookVector
		local delta  = position - origin
		local flat   = Vector3.new(delta.X, 0, delta.Z)
		if flat.Magnitude < 0.001 then flat = Vector3.new(1, 0, 0) end
		local dir    = flat.Unit
		local goal   = Vector3.new(dir.X, look.Y, dir.Z)
		if goal.Magnitude < 0.001 then
			goal = Vector3.new(dir.X, look.Y, dir.Z + 0.0001)
		end
		local lerped = look:Lerp(goal.Unit, blend)
		if lerped.Magnitude < 0.001 then
			lerped = Vector3.new(goal.Unit.X, look.Y, goal.Unit.Z)
		end
		Root.CFrame = CFrame.new(origin, origin + lerped.Unit)
	end)
end

local function SmoothAim(targetRoot, duration)
	duration = duration or AimProfile.TimeToAim
	if not (targetRoot and targetRoot.Parent) then return end

	local start = tick()
	local conn
	conn = Services.Run.Heartbeat:Connect(function()
		if not (targetRoot and targetRoot.Parent) then
			conn:Disconnect()
			return
		end

		local elapsed  = tick() - start
		local progress = math.clamp(elapsed / duration, 0, 1)
		local eased    = 1 - (1 - progress)^math.max(1, AimProfile.CurvePower)

		local basePos  = targetRoot.Position
		local vel      = Vector3.new(0,0,0)
		pcall(function()
			vel = targetRoot:GetVelocity() or targetRoot.Velocity or Vector3.new(0,0,0)
		end)
		local predicted = basePos + Vector3.new(vel.X, 0, vel.Z) * AimProfile.VelocityBias

		pcall(function()
			local origin = Root.Position
			local look   = Root.CFrame.LookVector
			local delta  = predicted - origin
			local flat   = Vector3.new(delta.X, 0, delta.Z)
			if flat.Magnitude < 0.001 then flat = Vector3.new(1, 0, 0) end
			local dir    = flat.Unit
			local goal   = Vector3.new(dir.X, look.Y, dir.Z).Unit
			local final  = look:Lerp(goal, eased)
			Root.CFrame  = CFrame.new(origin, origin + final)
		end)

		if progress >= 1 then
			conn:Disconnect()
		end
	end)
end

local function ExecuteLinearDash(targetRoot, dashSpeed)
	dashSpeed = dashSpeed or DashProfile.SpeedBase + DashProfile.SpeedScale

	local attach = Instance.new("Attachment")
	attach.Name  = "DashAttach"
	attach.Parent = Root

	local lv = Instance.new("LinearVelocity")
	lv.Name         = "DashVelocity"
	lv.Attachment0  = attach
	lv.MaxForce     = math.huge
	lv.RelativeTo   = Enum.ActuatorRelativeTo.World
	lv.Parent       = Root

	local moveTrack, moveAnim

	if ActiveAnim.Forward then
		local hum, anim = GetAnimator()
		if hum and anim then
			moveAnim = Instance.new("Animation")
			moveAnim.Name = "DashForward"
			moveAnim.AnimationId = "rbxassetid://" .. tostring(ActiveAnim.Forward)
			local ok, track = pcall(function() return anim:LoadAnimation(moveAnim) end)
			if ok and track then
				track.Priority = Enum.AnimationPriority.Movement
				pcall(function() track.Looped = false end)
				pcall(function() track:Play() end)
				moveTrack = track
			else
				pcall(function() moveAnim:Destroy() end)
			end
		end
	end

	local finished, active = false, true
	local conn
	conn = Services.Run.Heartbeat:Connect(function()
		if not active then return end

		if not (targetRoot and targetRoot.Parent and Root and Root.Parent) then
			active = false
			conn:Disconnect()
			pcall(function() lv:Destroy() end)
			pcall(function() attach:Destroy() end)
			pcall(function()
				if moveTrack and moveTrack.IsPlaying then moveTrack:Stop() end
				if moveAnim then moveAnim:Destroy() end
			end)
			return
		end

		local targetPos = targetRoot.Position
		local delta     = targetPos - Root.Position
		local flat      = Vector3.new(delta.X, 0, delta.Z)

		if flat.Magnitude > DashProfile.StopThreshold then
			lv.VectorVelocity = flat.Unit * dashSpeed
			pcall(function()
				if flat.Magnitude > 0.001 then
					Root.CFrame = CFrame.new(Root.Position, Root.Position + flat.Unit)
				end
			end)
			pcall(function()
				AimTowards(targetPos, 0.56)
			end)
		else
			finished = true
			active   = false
			conn:Disconnect()
			pcall(function() lv:Destroy() end)
			pcall(function() attach:Destroy() end)
			pcall(function()
				if moveTrack and moveTrack.IsPlaying then moveTrack:Stop() end
				if moveAnim then moveAnim:Destroy() end
			end)
		end
	end)

	repeat task.wait() until finished or not (targetRoot and targetRoot.Parent and Root and Root.Parent)
end

local function FireServerPacket(payload)
	pcall(function()
		if Character and Character:FindFirstChild("Communicate") then
			Character.Communicate:FireServer(unpack(payload))
		end
	end)
end

local function ExecuteCircularDash(targetChar)
	if State.IsDashing then return end
	if not (targetChar and targetChar:FindFirstChild("HumanoidRootPart")) then return end
	if not Root then return end

	State.IsDashing = true
	local hum = Character:FindFirstChildOfClass("Humanoid")
	local originalRotate

	if hum then
		originalRotate = hum.AutoRotate
		State.RotLock  = true
		pcall(function() hum.AutoRotate = false end)
	end

	local function RestoreRotation()
		if hum and originalRotate ~= nil then
			State.RotLock = false
			pcall(function() hum.AutoRotate = originalRotate end)
		end
	end

	local speedSlider    = State.Sliders.Speed    or 84
	local angleSlider    = State.Sliders.Angle    or 56
	local distanceSlider = State.Sliders.Distance or 50

	local dashSpeed   = DashProfile.SpeedBase + DashProfile.SpeedScale * (speedSlider / 100)
	local dashAngle   = MotionProfile.BaseAngleDeg + MotionProfile.AngleSpread * (angleSlider / 100)
	local dashRadius  = DashProfile.DistanceMin + (DashProfile.DistanceMax - DashProfile.DistanceMin) * (distanceSlider / 100)

	local targetRoot  = targetChar.HumanoidRootPart

	if DashProfile.MinStartRange <= (targetRoot.Position - Root.Position).Magnitude then
		ExecuteLinearDash(targetRoot, dashSpeed)
	end

	if not (targetRoot and targetRoot.Parent and Root and Root.Parent) then
		RestoreRotation()
		State.IsDashing = false
		return
	end

	local targetPos = targetRoot.Position
	local charPos   = Root.Position
	local right     = Root.CFrame.RightVector
	local direction = targetRoot.Position - Root.Position
	if direction.Magnitude < 0.001 then
		direction = Root.CFrame.LookVector
	end

	local isLeft    = right:Dot(direction.Unit) < 0
	PlaySide(isLeft)
	local dirSign   = isLeft and 1 or -1
	local baseAngle = math.atan2(charPos.Z - targetPos.Z, charPos.X - targetPos.X)
	local flatDist  = (Vector3.new(charPos.X, 0, charPos.Z) - Vector3.new(targetPos.X, 0, targetPos.Z)).Magnitude
	local startDist = math.clamp(flatDist, DashProfile.DistanceMin, DashProfile.DistanceMax)

	local startTime     = tick()
	local conn
	local aimTriggered  = false
	local arcFinished   = false
	local releaseReady  = false
	local dashDone      = false

	local function BeginRelease()
		if not arcFinished then
			arcFinished = true
			task.delay(AimProfile.TimeToAim, function()
				releaseReady = true
				RestoreRotation()
				if dashDone then
					State.IsDashing = false
				end
			end)
		end
	end

	if State.Flags.Click then
		FireServerPacket({{Mobile = true, Goal = "LeftClick"}})
		task.delay(0.05, function()
			FireServerPacket({{Goal = "LeftClickRelease", Mobile = true}})
		end)
	end

	if State.Flags.ForceDash then
		FireServerPacket({{Dash = Enum.KeyCode.W, Key = Enum.KeyCode.Q, Goal = "KeyPress"}})
	end

	conn = Services.Run.Heartbeat:Connect(function()
		local elapsed   = tick() - startTime
		local progress  = math.clamp(elapsed / MotionProfile.Duration, 0, 1)
		local eased     = EaseCubic01(progress)
		local aimProg   = math.clamp(progress * 1.5, 0, 1)

		local radiusNow = startDist + (dashRadius - startDist) * EaseCubic01(aimProg)
		local radiusCl  = math.clamp(radiusNow, DashProfile.DistanceMin, DashProfile.DistanceMax)
		local angleNow  = baseAngle + dirSign * math.rad(dashAngle) * EaseCubic01(progress)

		local liveTarget = targetRoot.Position
		local yLevel     = liveTarget.Y
		local px         = liveTarget.X + radiusCl * math.cos(angleNow)
		local pz         = liveTarget.Z + radiusCl * math.sin(angleNow)
		local newPos     = Vector3.new(px, yLevel, pz)

		local latestPos  = targetRoot and targetRoot.Position or liveTarget
		local angleToPos = math.atan2((latestPos - newPos).Z, (latestPos - newPos).X)
		local currentAng = math.atan2(Root.CFrame.LookVector.Z, Root.CFrame.LookVector.X)
		local finalAng   = currentAng + NormalizeAng(angleToPos, currentAng) * AimProfile.BlendStrength

		pcall(function()
			Root.CFrame = CFrame.new(newPos, newPos + Vector3.new(math.cos(finalAng), 0, math.sin(finalAng)))
		end)

		if not aimTriggered and AimProfile.ArcProgress <= eased then
			aimTriggered = true
			pcall(function()
				SmoothAim(targetRoot, AimProfile.TimeToAim)
			end)
			BeginRelease()
		end

		if progress >= 1 then
			conn:Disconnect()
			pcall(function()
				if State.SideTrack and State.SideTrack.IsPlaying then
					State.SideTrack:Stop()
				end
				State.SideTrack = nil
			end)
			if not aimTriggered then
				aimTriggered = true
				pcall(function()
					SmoothAim(targetRoot, AimProfile.TimeToAim)
				end)
				BeginRelease()
			end
			dashDone = true
			if releaseReady then
				State.IsDashing = false
			end
		end
	end)
end

_G.SideDash_Movement = {
	ExecuteDash   = ExecuteCircularDash,
	AcquireTarget = AcquireTarget,
	IsValid       = IsValid
}

-- ur gay wasp
-- SIDE DASH ASSIST V1.0 - GUI

local Core     = _G.SideDash_Core
local Movement = _G.SideDash_Movement

local Services    = Core.Services
local LocalPlayer = Core.LocalPlayer
local State       = Core.State

local UIKit = {
	Input  = Services.Input,
	Tween  = Services.Tweens,
	Gui    = Services.Starter
}

pcall(function()
	UIKit.Gui:SetCore("SendNotification", {
		Title   = "Side Dash Assist",
		Text    = "Press E or tap DASH button.",
		Duration = 5
	})
end)

pcall(function()
	if setclipboard then
		setclipboard("https://discord.gg/GEVGRzC4ZP")
	end
end)

local mainGui = Instance.new("ScreenGui")
mainGui.Name = "SideDashAssistGUI"
mainGui.ResetOnSpawn = false
mainGui.Parent = LocalPlayer:WaitForChild("PlayerGui")

local blur = Instance.new("BlurEffect")
blur.Size = 0
blur.Parent = game:GetService("Lighting")

local function MakeDraggable(obj, enabled)
	if not enabled then return end
	local dragging = false
	local dragStart, startPos, currentInput

	obj.InputBegan:Connect(function(inp)
		if (inp.UserInputType == Enum.UserInputType.Touch or inp.UserInputType == Enum.UserInputType.MouseButton1) and not dragging then
			dragging = true
			dragStart = inp.Position
			startPos  = obj.Position
			currentInput = inp
			inp.Changed:Connect(function()
				if inp.UserInputState == Enum.UserInputState.End then
					dragging = false
					currentInput = nil
				end
			end)
		end
	end)

	UIKit.Input.InputChanged:Connect(function(inp)
		if dragging and currentInput == inp and (inp.UserInputType == Enum.UserInputType.Touch or inp.UserInputType == Enum.UserInputType.MouseMovement) then
			local delta = inp.Position - dragStart
			obj.Position = UDim2.new(
				startPos.X.Scale, startPos.X.Offset + delta.X,
				startPos.Y.Scale, startPos.Y.Offset + delta.Y
			)
		end
	end)
end

-- main panel
local mainFrame = Instance.new("Frame")
mainFrame.Name = "MainFrame"
mainFrame.Size = UDim2.new(0, 380, 0, 140)
mainFrame.Position = UDim2.new(0.5, -190, 0.12, 0)
mainFrame.BackgroundColor3 = Color3.fromRGB(15, 15, 15)
mainFrame.BackgroundTransparency = 1
mainFrame.BorderSizePixel = 0
mainFrame.Visible = false
mainFrame.Parent = mainGui
MakeDraggable(mainFrame, true)

local mainCorner = Instance.new("UICorner")
mainCorner.CornerRadius = UDim.new(0, 20)
mainCorner.Parent = mainFrame

local mainBgGradient = Instance.new("UIGradient")
mainBgGradient.Color = ColorSequence.new({
	ColorSequenceKeypoint.new(0, Color3.fromRGB(25, 5, 5)),
	ColorSequenceKeypoint.new(0.5, Color3.fromRGB(15, 15, 15)),
	ColorSequenceKeypoint.new(1, Color3.fromRGB(0, 0, 0))
})
mainBgGradient.Rotation = 90
mainBgGradient.Parent = mainFrame

local borderFrame = Instance.new("Frame")
borderFrame.Name = "BorderFrame"
borderFrame.Size = UDim2.new(1, 8, 1, 8)
borderFrame.Position = UDim2.new(0, -4, 0, -4)
borderFrame.BackgroundColor3 = Color3.fromRGB(255, 0, 0)
borderFrame.BackgroundTransparency = 1
borderFrame.BorderSizePixel = 0
borderFrame.ZIndex = 0
borderFrame.Parent = mainFrame

local borderCorner = Instance.new("UICorner")
borderCorner.CornerRadius = UDim.new(0, 24)
borderCorner.Parent = borderFrame

local borderGradient = Instance.new("UIGradient")
borderGradient.Color = ColorSequence.new({
	ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 0, 0)),
	ColorSequenceKeypoint.new(0.5, Color3.fromRGB(120, 0, 0)),
	ColorSequenceKeypoint.new(1, Color3.fromRGB(26, 26, 26))
})
borderGradient.Rotation = 45
borderGradient.Parent = borderFrame

local headerFrame = Instance.new("Frame")
headerFrame.Size = UDim2.new(1, 0, 0, 50)
headerFrame.BackgroundTransparency = 1
headerFrame.Parent = mainFrame

local titleLabel = Instance.new("TextLabel")
titleLabel.Size = UDim2.new(0, 190, 0, 30)
titleLabel.Position = UDim2.new(0, 20, 0, 10)
titleLabel.BackgroundTransparency = 1
titleLabel.Text = "Side Dash Assist"
titleLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
titleLabel.TextSize = 23
titleLabel.Font = Enum.Font.GothamBold
titleLabel.TextXAlignment = Enum.TextXAlignment.Left
titleLabel.TextStrokeTransparency = 0.7
titleLabel.Parent = headerFrame

local versionLabel = Instance.new("TextLabel")
versionLabel.Size = UDim2.new(0, 55, 0, 24)
versionLabel.Position = UDim2.new(0, 215, 0, 13)
versionLabel.BackgroundColor3 = Color3.fromRGB(255, 0, 0)
versionLabel.BorderSizePixel = 0
versionLabel.Text = "v1.0"
versionLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
versionLabel.TextSize = 13
versionLabel.Font = Enum.Font.GothamBold
versionLabel.Parent = headerFrame

local versionCorner = Instance.new("UICorner")
versionCorner.CornerRadius = UDim.new(0, 8)
versionCorner.Parent = versionLabel

local authorLabel = Instance.new("TextLabel")
authorLabel.Size = UDim2.new(1, -40, 0, 17)
authorLabel.Position = UDim2.new(0, 20, 0, 32)
authorLabel.BackgroundTransparency = 1
authorLabel.Text = "by CPS Network"
authorLabel.TextColor3 = Color3.fromRGB(200, 200, 200)
authorLabel.TextSize = 13
authorLabel.Font = Enum.Font.GothamMedium
authorLabel.TextXAlignment = Enum.TextXAlignment.Left
authorLabel.TextTransparency = 0.28
authorLabel.Parent = headerFrame

local closeBtn = Instance.new("TextButton")
closeBtn.Size = UDim2.new(0, 35, 0, 35)
closeBtn.Position = UDim2.new(1, -45, 0, 7)
closeBtn.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
closeBtn.Text = "X"
closeBtn.Font = Enum.Font.GothamBold
closeBtn.TextColor3 = Color3.fromRGB(0, 0, 0)
closeBtn.TextSize = 19
closeBtn.BorderSizePixel = 0
closeBtn.Parent = mainFrame

local closeBtnCorner = Instance.new("UICorner")
closeBtnCorner.CornerRadius = UDim.new(0, 10)
closeBtnCorner.Parent = closeBtn

local minimizeBtn = Instance.new("TextButton")
minimizeBtn.Size = UDim2.new(0, 35, 0, 35)
minimizeBtn.Position = UDim2.new(1, -85, 0, 7)
minimizeBtn.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
minimizeBtn.Text = "_"
minimizeBtn.Font = Enum.Font.GothamBold
minimizeBtn.TextColor3 = Color3.fromRGB(0, 0, 0)
minimizeBtn.TextSize = 22
minimizeBtn.BorderSizePixel = 0
minimizeBtn.Parent = mainFrame

local minimizeCorner = Instance.new("UICorner")
minimizeCorner.CornerRadius = UDim.new(0, 10)
minimizeCorner.Parent = minimizeBtn

local buttonContainer = Instance.new("Frame")
buttonContainer.Size = UDim2.new(0, 200, 0, 48)
buttonContainer.Position = UDim2.new(0.5, -100, 0, 72)
buttonContainer.BackgroundTransparency = 1
buttonContainer.Parent = mainFrame

local toggleButton = Instance.new("TextButton")
toggleButton.Size = UDim2.new(1, 0, 1, 0)
toggleButton.BackgroundTransparency = 1
toggleButton.BorderSizePixel = 0
toggleButton.TextColor3 = Color3.fromRGB(255, 255, 255)
toggleButton.TextSize = 20
toggleButton.Font = Enum.Font.GothamBold
toggleButton.AutoButtonColor = false
toggleButton.ZIndex = 2
toggleButton.Parent = buttonContainer

local buttonBg = Instance.new("Frame")
buttonBg.Size = UDim2.new(1, 0, 1, 0)
buttonBg.BackgroundColor3 = Color3.fromRGB(180, 13, 19)
buttonBg.BorderSizePixel = 0
buttonBg.ZIndex = 1
buttonBg.Parent = buttonContainer

local buttonCorner = Instance.new("UICorner")
buttonCorner.CornerRadius = UDim.new(0, 12)
buttonCorner.Parent = buttonBg

local buttonGradient = Instance.new("UIGradient")
buttonGradient.Color = ColorSequence.new({
	ColorSequenceKeypoint.new(0, Color3.fromRGB(180, 13, 19)),
	ColorSequenceKeypoint.new(1, Color3.fromRGB(120, 0, 0))
})
buttonGradient.Rotation = 90
buttonGradient.Parent = buttonBg

local buttonBorder = Instance.new("UIStroke")
buttonBorder.Color = Color3.fromRGB(255, 0, 0)
buttonBorder.Thickness = 2
buttonBorder.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
buttonBorder.Parent = buttonBg

local EnabledFlag = true

local function UpdateToggle()
	if EnabledFlag then
		toggleButton.Text = "Enabled: ON"
		UIKit.Tween:Create(buttonBg, TweenInfo.new(0.25), {BackgroundColor3 = Color3.fromRGB(180, 13, 19)}):Play()
		UIKit.Tween:Create(buttonBorder, TweenInfo.new(0.25), {Color = Color3.fromRGB(255, 0, 0)}):Play()
	else
		toggleButton.Text = "Enabled: OFF"
		UIKit.Tween:Create(buttonBg, TweenInfo.new(0.25), {BackgroundColor3 = Color3.fromRGB(54, 54, 54)}):Play()
		UIKit.Tween:Create(buttonBorder, TweenInfo.new(0.25), {Color = Color3.fromRGB(110, 110, 110)}):Play()
	end
end

toggleButton.MouseButton1Click:Connect(function()
	EnabledFlag = not EnabledFlag
	UpdateToggle()
end)

UpdateToggle()

-- settings button + overlay (just sliders already wired in State.Sliders)
local settingsBtn = Instance.new("TextButton")
settingsBtn.Size = UDim2.new(0, 36, 0, 36)
settingsBtn.Position = UDim2.new(0, 10, 1, -46)
settingsBtn.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
settingsBtn.Text = "⚙"
settingsBtn.Font = Enum.Font.GothamBold
settingsBtn.TextColor3 = Color3.fromRGB(0, 0, 0)
settingsBtn.TextSize = 19
settingsBtn.BorderSizePixel = 0
settingsBtn.Parent = mainFrame

local settingsBtnCorner = Instance.new("UICorner")
settingsBtnCorner.CornerRadius = UDim.new(1, 0)
settingsBtnCorner.Parent = settingsBtn

local settingsOverlay = Instance.new("Frame")
settingsOverlay.Name = "SettingsOverlay"
settingsOverlay.Size = UDim2.new(0, 300, 0, 240)
settingsOverlay.Position = UDim2.new(0, 40, 0.2, 0)
settingsOverlay.BackgroundColor3 = Color3.fromRGB(15, 15, 15)
settingsOverlay.BackgroundTransparency = 1
settingsOverlay.BorderSizePixel = 0
settingsOverlay.Visible = false
settingsOverlay.Parent = mainGui
MakeDraggable(settingsOverlay, true)

local overlayCorner = Instance.new("UICorner")
overlayCorner.CornerRadius = UDim.new(0, 19)
overlayCorner.Parent = settingsOverlay

local overlayGradient = Instance.new("UIGradient")
overlayGradient.Color = ColorSequence.new({
	ColorSequenceKeypoint.new(0, Color3.fromRGB(25, 5, 5)),
	ColorSequenceKeypoint.new(0.5, Color3.fromRGB(15, 15, 15)),
	ColorSequenceKeypoint.new(1, Color3.fromRGB(0, 0, 0))
})
overlayGradient.Rotation = 90
overlayGradient.Parent = settingsOverlay

local settingsTitle = Instance.new("TextLabel")
settingsTitle.Size = UDim2.new(1, -60, 0, 40)
settingsTitle.Position = UDim2.new(0, 16, 0, 5)
settingsTitle.BackgroundTransparency = 1
settingsTitle.Text = "Settings"
settingsTitle.TextColor3 = Color3.fromRGB(255, 255, 255)
settingsTitle.TextSize = 21
settingsTitle.Font = Enum.Font.GothamBold
settingsTitle.TextXAlignment = Enum.TextXAlignment.Left
settingsTitle.Parent = settingsOverlay

local settingsCloseBtn = Instance.new("TextButton")
settingsCloseBtn.Size = UDim2.new(0, 35, 0, 35)
settingsCloseBtn.Position = UDim2.new(1, -45, 0, 6)
settingsCloseBtn.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
settingsCloseBtn.Text = "X"
settingsCloseBtn.Font = Enum.Font.GothamBold
settingsCloseBtn.TextColor3 = Color3.fromRGB(0, 0, 0)
settingsCloseBtn.TextSize = 19
settingsCloseBtn.BorderSizePixel = 0
settingsCloseBtn.Parent = settingsOverlay

local settingsCloseCorner = Instance.new("UICorner")
settingsCloseCorner.CornerRadius = UDim.new(0, 10)
settingsCloseCorner.Parent = settingsCloseBtn

-- sliders: Speed / Angle / Distance
local sliderNames = {"Speed", "Angle", "Distance"}

for i, key in ipairs(sliderNames) do
	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(0, 120, 0, 20)
	label.Position = UDim2.new(0.04, 0, 0.18 + (i-1)*0.24, 0)
	label.BackgroundTransparency = 1
	label.Text = "Dash " .. key
	label.TextColor3 = Color3.fromRGB(200, 200, 200)
	label.TextScaled = true
	label.Font = Enum.Font.Gotham
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.Parent = settingsOverlay

	local sliderFrame = Instance.new("Frame")
	sliderFrame.Size = UDim2.new(0, 160, 0, 24)
	sliderFrame.Position = UDim2.new(0.38, 5, 0.18 + (i-1)*0.24, 0)
	sliderFrame.BackgroundTransparency = 1
	sliderFrame.Parent = settingsOverlay

	local track = Instance.new("Frame")
	track.Size = UDim2.new(1, -20, 0, 6)
	track.Position = UDim2.new(0, 10, 0.5, -3)
	track.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	track.BackgroundTransparency = 0.7
	track.Parent = sliderFrame

	local trackCorner = Instance.new("UICorner")
	trackCorner.CornerRadius = UDim.new(1, 0)
	trackCorner.Parent = track

	local handle = Instance.new("TextButton")
	handle.Size = UDim2.new(0, 20, 0, 20)
	handle.Position = UDim2.new(0, -10, 0.5, -10)
	handle.BackgroundColor3 = Color3.fromRGB(180, 180, 180)
	handle.BorderSizePixel = 0
	handle.Text = ""
	handle.AutoButtonColor = false
	handle.Parent = sliderFrame

	local handleCorner = Instance.new("UICorner")
	handleCorner.CornerRadius = UDim.new(1, 0)
	handleCorner.Parent = handle

	local valueLabel = Instance.new("TextLabel")
	valueLabel.Size = UDim2.new(0, 70, 0, 20)
	valueLabel.Position = UDim2.new(0.82, 0, 0.18 + (i-1)*0.24, 0)
	valueLabel.BackgroundTransparency = 1
	valueLabel.TextColor3 = Color3.fromRGB(230, 230, 230)
	valueLabel.TextSize = 14
	valueLabel.Font = Enum.Font.GothamBold
	valueLabel.Text = "0"
	valueLabel.Parent = settingsOverlay

	local dragging = false
	local val = State.Sliders[key] or 50
	handle.Position = UDim2.new(val/100, -10, 0.5, -10)
	valueLabel.Text = tostring(val)
	State.Sliders[key] = val

	local function SetFromX(x)
		local width  = track.AbsoluteSize.X
		local origin = track.AbsolutePosition.X
		if width <= 0 then return end
		local alpha = math.clamp((x - origin) / width, 0, 1)
		val = math.floor(alpha * 100)
		State.Sliders[key] = val
		handle.Position = UDim2.new(alpha, -10, 0.5, -10)
		valueLabel.Text = tostring(val)
	end

	handle.InputBegan:Connect(function(inp)
		if inp.UserInputType == Enum.UserInputType.MouseButton1 or inp.UserInputType == Enum.UserInputType.Touch then
			dragging = true
			inp.Changed:Connect(function()
				if inp.UserInputState == Enum.UserInputState.End then
					dragging = false
				end
			end)
		end
	end)

	UIKit.Input.InputChanged:Connect(function(inp)
		if dragging and (inp.UserInputType == Enum.UserInputType.MouseMovement or inp.UserInputType == Enum.UserInputType.Touch) then
			SetFromX(inp.Position.X)
		end
	end)
end

local openButton = Instance.new("TextButton")
openButton.Name = "OpenGuiButton"
openButton.Size = UDim2.new(0, 90, 0, 34)
openButton.Position = UDim2.new(0, 10, 0.5, -17)
openButton.BackgroundColor3 = Color3.fromRGB(25, 25, 25)
openButton.Text = "Open GUI"
openButton.TextColor3 = Color3.fromRGB(255, 255, 255)
openButton.TextSize = 15
openButton.Font = Enum.Font.GothamBold
openButton.BorderSizePixel = 0
openButton.Visible = false
openButton.Parent = mainGui

local openCorner = Instance.new("UICorner")
openCorner.CornerRadius = UDim.new(0, 10)
openCorner.Parent = openButton
MakeDraggable(openButton, true)

local function SetMainTransparency(alpha)
	mainFrame.BackgroundTransparency   = alpha
	borderFrame.BackgroundTransparency = alpha
	titleLabel.TextTransparency        = alpha
	authorLabel.TextTransparency       = 0.28 + (alpha * 0.7)
	versionLabel.TextTransparency      = alpha
	toggleButton.TextTransparency      = alpha
	closeBtn.TextTransparency          = alpha
	minimizeBtn.TextTransparency       = alpha
	settingsBtn.TextTransparency       = alpha
end

local function FadeInMain()
	mainFrame.Visible = true
	SetMainTransparency(1)

	UIKit.Tween:Create(blur, TweenInfo.new(0.3), {Size = 12}):Play()
	UIKit.Tween:Create(mainFrame, TweenInfo.new(0.3), {BackgroundTransparency = 0}):Play()
	UIKit.Tween:Create(borderFrame, TweenInfo.new(0.3), {BackgroundTransparency = 0}):Play()
	UIKit.Tween:Create(titleLabel, TweenInfo.new(0.3), {TextTransparency = 0}):Play()
	UIKit.Tween:Create(authorLabel, TweenInfo.new(0.3), {TextTransparency = 0.28}):Play()
	UIKit.Tween:Create(versionLabel, TweenInfo.new(0.3), {TextTransparency = 0}):Play()
	UIKit.Tween:Create(toggleButton, TweenInfo.new(0.3), {TextTransparency = 0}):Play()
	UIKit.Tween:Create(closeBtn, TweenInfo.new(0.3), {TextTransparency = 0}):Play()
	UIKit.Tween:Create(minimizeBtn, TweenInfo.new(0.3), {TextTransparency = 0}):Play()
	UIKit.Tween:Create(settingsBtn, TweenInfo.new(0.3), {TextTransparency = 0}):Play()
end

local function FadeOutMain(callback)
	local t1 = UIKit.Tween:Create(blur, TweenInfo.new(0.3), {Size = 0})
	local t2 = UIKit.Tween:Create(mainFrame, TweenInfo.new(0.3), {BackgroundTransparency = 1})
	local t3 = UIKit.Tween:Create(borderFrame, TweenInfo.new(0.3), {BackgroundTransparency = 1})

	t1:Play() t2:Play() t3:Play()

	t2.Completed:Connect(function()
		mainFrame.Visible = false
		if callback then callback() end
	end)
end

local function FadeInSettings()
	settingsOverlay.Visible = true
	UIKit.Tween:Create(settingsOverlay, TweenInfo.new(0.25), {BackgroundTransparency = 0}):Play()
end

local function FadeOutSettings()
	local t = UIKit.Tween:Create(settingsOverlay, TweenInfo.new(0.25), {BackgroundTransparency = 1})
	t:Play()
	t.Completed:Connect(function()
		settingsOverlay.Visible = false
	end)
end

closeBtn.MouseButton1Click:Connect(function()
	FadeOutMain()
end)

minimizeBtn.MouseButton1Click:Connect(function()
	FadeOutMain(function()
		openButton.Visible = true
	end)
end)

openButton.MouseButton1Click:Connect(function()
	openButton.Visible = false
	FadeInMain()
end)

settingsBtn.MouseButton1Click:Connect(function()
	FadeInSettings()
end)

settingsCloseBtn.MouseButton1Click:Connect(function()
	FadeOutSettings()
end)

FadeInMain()

-- DASH BUTTON (right side)
local dashButton = Instance.new("TextButton")
dashButton.Name = "DashButton"
dashButton.Size = UDim2.new(0, 80, 0, 80)
dashButton.Position = UDim2.new(1, -110, 1, -110)
dashButton.BackgroundColor3 = Color3.fromRGB(200, 20, 20)
dashButton.Text = "DASH"
dashButton.TextColor3 = Color3.fromRGB(255, 255, 255)
dashButton.TextSize = 18
dashButton.Font = Enum.Font.GothamBold
dashButton.BorderSizePixel = 0
dashButton.Parent = mainGui
MakeDraggable(dashButton, true)

local dashCorner = Instance.new("UICorner")
dashCorner.CornerRadius = UDim.new(1, 0)
dashCorner.Parent = dashButton

local dashGradient = Instance.new("UIGradient")
dashGradient.Color = ColorSequence.new({
	ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 80, 80)),
	ColorSequenceKeypoint.new(1, Color3.fromRGB(140, 10, 10))
})
dashGradient.Rotation = 135
dashGradient.Parent = dashButton

local dashStroke = Instance.new("UIStroke")
dashStroke.Color = Color3.fromRGB(255, 100, 100)
dashStroke.Thickness = 3
dashStroke.Parent = dashButton

local touchMap = {}

local function TryDash()
	if not EnabledFlag then return end
	if not Movement.IsValid() then return end
	local target = Movement.AcquireTarget()
	if target then
		Movement.ExecuteDash(target)
	end
end

dashButton.InputBegan:Connect(function(inp)
	if inp.UserInputType == Enum.UserInputType.Touch then
		local key = tostring(inp)
		touchMap[key] = true
		if next(touchMap) ~= nil and select(2,next(touchMap)) == nil then
			UIKit.Tween:Create(dashButton, TweenInfo.new(0.1), {BackgroundColor3 = Color3.fromRGB(255, 100, 100)}):Play()
			TryDash()
		end
		inp.Changed:Connect(function()
			if inp.UserInputState == Enum.UserInputState.End then
				touchMap[key] = nil
				if next(touchMap) == nil then
					UIKit.Tween:Create(dashButton, TweenInfo.new(0.1), {BackgroundColor3 = Color3.fromRGB(200, 20, 20)}):Play()
				end
			end
		end)
	elseif inp.UserInputType == Enum.UserInputType.MouseButton1 then
		UIKit.Tween:Create(dashButton, TweenInfo.new(0.1), {BackgroundColor3 = Color3.fromRGB(255, 100, 100)}):Play()
		TryDash()
	end
end)

dashButton.InputEnded:Connect(function(inp)
	if inp.UserInputType == Enum.UserInputType.MouseButton1 then
		if next(touchMap) == nil then
			UIKit.Tween:Create(dashButton, TweenInfo.new(0.1), {BackgroundColor3 = Color3.fromRGB(200, 20, 20)}):Play()
		end
	end
end)

-- keyboard input
UIKit.Input.InputBegan:Connect(function(input, processed)
	if processed then return end
	if not EnabledFlag then return end
	if input.KeyCode == Enum.KeyCode.E then
		TryDash()
	end
end)

print("Side Dash Assist V1.0 loaded (3‑snippet build).")

-- ur gay wasp
