local GameServices = {
	Players = game:GetService("Players"),
	Runtime = game:GetService("RunService"),
	Input = game:GetService("UserInputService"),
	Tweens = game:GetService("TweenService"),
	World = game:GetService("Workspace"),
	HTTP = game:GetService("HttpService")
}

local CorePlayer = GameServices.Players.LocalPlayer
local CoreCharacter = CorePlayer.Character or CorePlayer.CharacterAdded:Wait()
local CoreRoot = CoreCharacter:WaitForChild("HumanoidRootPart")
local CoreHumanoid = CoreCharacter:FindFirstChildOfClass("Humanoid")
local CoreCamera = GameServices.World.CurrentCamera

local CONFIG = {
	DASH_DURATION = 0.85,
	DASH_ANGLE_DEG = 120,
	DASH_DISTANCE = 2.5,
	DASH_VELOCITY = 120,
	RANGE_MAX = 40,
	RANGE_MIN_TARGET = 15,
	TARGET_THRESHOLD = 10,
	DIRECTION_BLEND = 0.7,
	AIM_DELAY = 0.7,
	VELOCITY_PREDICT = 0.5,
	AIM_POWER = 200,
	CIRCLE_THRESHOLD = 390 / 480,
	SOUND_CLICK = "rbxassetid://5852470908",
	SOUND_DASH = "rbxassetid://72014632956520",
	SOUND_UI = "rbxassetid://6042053626"
}

local AnimationRegistry = {
	[10449761463] = { Left = 10480796021, Right = 10480793962, Straight = 10479335397 },
	[13076380114] = { Left = 101843860692381, Right = 100087324592640, Straight = 110878031211717 }
}

local function ResolveAnimations()
	local gameID = game.PlaceId
	return AnimationRegistry[gameID] or AnimationRegistry[13076380114]
end

local ActiveAnimations = ResolveAnimations()

local RuntimeState = {
	isDashing = false,
	sideTrack = nil,
	lastPress = -math.huge,
	rotateDisabled = false,
	rotateConnection = nil,
	lockedTarget = nil,
	soundVFX = nil,
	toggleM1 = false,
	toggleDash = false,
	settingValues = {
		["Dash speed"] = nil,
		["Dash Degrees"] = nil,
		["Dash gap"] = nil
	}
}

local function IsCharacterValid()
	if not (CoreHumanoid and CoreHumanoid.Parent) then return false end
	if CoreHumanoid.Health <= 0 then return false end
	if CoreHumanoid.PlatformStand then return false end
	local ok, state = pcall(function() return CoreHumanoid:GetState() end)
	if ok and state == Enum.HumanoidStateType.Physics then return false end
	local ragVal = CoreCharacter:FindFirstChild("Ragdoll")
	return not (ragVal and ragVal:IsA("BoolValue") and ragVal.Value)
end

CorePlayer.CharacterAdded:Connect(function(newChar)
	CoreCharacter = newChar
	CoreRoot = newChar:WaitForChild("HumanoidRootPart")
	CoreHumanoid = newChar:FindFirstChildOfClass("Humanoid")
	task.wait(0.05)
	InitializeRotationProtection()
end)

local function InitializeRotationProtection()
	if RuntimeState.rotateConnection then
		pcall(function() RuntimeState.rotateConnection:Disconnect() end)
		RuntimeState.rotateConnection = nil
	end
	local targetHum = CoreCharacter:FindFirstChildOfClass("Humanoid")
	if targetHum then
		RuntimeState.rotateConnection = targetHum:GetPropertyChangedSignal("AutoRotate"):Connect(function()
			if RuntimeState.rotateDisabled and targetHum.AutoRotate then
				pcall(function() targetHum.AutoRotate = false end)
			end
		end)
	end
end

InitializeRotationProtection()

local function NormalizeAngle(a1, a2)
	local diff = a1 - a2
	while math.pi < diff do diff = diff - 2 * math.pi end
	while diff < -math.pi do diff = diff + 2 * math.pi end
	return diff
end

local function EaseInOutCubic(t)
	return 1 - (1 - math.clamp(t, 0, 1)) ^ 3
end

local function GetAnimatorContext()
	if not (CoreCharacter and CoreCharacter.Parent) then return nil, nil end
	local hum = CoreCharacter:FindFirstChildOfClass("Humanoid")
	if not hum then return nil, nil end
	local anim = hum:FindFirstChildOfClass("Animator")
	if not anim then
		anim = Instance.new("Animator")
		anim.Name = "Animator"
		anim.Parent = hum
	end
	return hum, anim
end

local function PlaySideAnim(isLeft)
	pcall(function()
		if RuntimeState.sideTrack and RuntimeState.sideTrack.IsPlaying then
			RuntimeState.sideTrack:Stop()
		end
	end)
	RuntimeState.sideTrack = nil
	local hum, anim = GetAnimatorContext()
	if not (hum and anim) then return end
	local animID = isLeft and ActiveAnimations.Left or ActiveAnimations.Right
	local animObj = Instance.new("Animation")
	animObj.Name = "SideAnimate"
	animObj.AnimationId = "rbxassetid://" .. tostring(animID)
	local success, track = pcall(function() return anim:LoadAnimation(animObj) end)
	if not (success and track) then
		pcall(function() animObj:Destroy() end)
		return
	end
	RuntimeState.sideTrack = track
	track.Priority = Enum.AnimationPriority.Action
	pcall(function() track.Looped = false end)
	track:Play()
	pcall(function()
		RuntimeState.soundVFX:Stop()
		RuntimeState.soundVFX:Play()
	end)
	delay(CONFIG.DASH_DURATION + 0.15, function()
		pcall(function()
			if track and track.IsPlaying then track:Stop() end
		end)
		pcall(function() animObj:Destroy() end)
	end)
end

local function FindClosestEntity(maxRange)
	maxRange = maxRange or CONFIG.RANGE_MAX
	local closest = nil
	local closestDist = math.huge
	local origin = CoreRoot.Position
	for _, player in pairs(GameServices.Players:GetPlayers()) do
		if player ~= CorePlayer and player.Character then
			local pHum = player.Character:FindFirstChildOfClass("Humanoid")
			local pRoot = player.Character:FindFirstChild("HumanoidRootPart")
			if pHum and pRoot and pHum.Health > 0 then
				local dist = (pRoot.Position - origin).Magnitude
				if dist < closestDist and dist <= maxRange then
					closest = player.Character
					closestDist = dist
				end
			end
		end
	end
	for _, entity in pairs(GameServices.World:GetDescendants()) do
		if entity:IsA("Model") and entity:FindFirstChild("Humanoid") and entity:FindFirstChild("HumanoidRootPart") then
			if not GameServices.Players:GetPlayerFromCharacter(entity) then
				local eHum = entity:FindFirstChild("Humanoid")
				local eRoot = entity:FindFirstChild("HumanoidRootPart")
				if eHum and eHum.Health > 0 then
					local dist = (eRoot.Position - origin).Magnitude
					if dist < closestDist and dist <= maxRange then
						closest = entity
						closestDist = dist
					end
				end
			end
		end
	end
	return closest, closestDist
end

GameServices.Players.PlayerRemoving:Connect(function(removed)
	if RuntimeState.lockedTarget == removed then
		RuntimeState.lockedTarget = nil
	end
end)

local function AcquireTarget()
	if RuntimeState.lockedTarget then
		if RuntimeState.lockedTarget.Character and RuntimeState.lockedTarget.Character.Parent then
			local tChar = RuntimeState.lockedTarget.Character
			local tRoot = tChar:FindFirstChild("HumanoidRootPart")
			local tHum = tChar:FindFirstChild("Humanoid")
			if tRoot and tHum and tHum.Health > 0 then
				if (tRoot.Position - CoreRoot.Position).Magnitude <= CONFIG.RANGE_MAX then
					return tChar
				end
			end
			RuntimeState.lockedTarget = nil
		else
			RuntimeState.lockedTarget = nil
		end
	end
	return FindClosestEntity(CONFIG.RANGE_MAX)
end

RuntimeState.soundVFX = Instance.new("Sound")
RuntimeState.soundVFX.Name = "DashFX"
RuntimeState.soundVFX.SoundId = CONFIG.SOUND_DASH
RuntimeState.soundVFX.Volume = 2
RuntimeState.soundVFX.Looped = false
RuntimeState.soundVFX.Parent = GameServices.World

-- ur gay wasp
local function AimAtPosition(targetPos, blendFactor)
	blendFactor = blendFactor or 0.7
	pcall(function()
		local origin = CoreRoot.Position
		local lookVec = CoreRoot.CFrame.LookVector
		local direction = targetPos - origin
		local horizontalDir = Vector3.new(direction.X, 0, direction.Z)
		if horizontalDir.Magnitude < 0.001 then
			horizontalDir = Vector3.new(1, 0, 0)
		end
		local targetDir = horizontalDir.Unit
		local finalLook = Vector3.new(targetDir.X, lookVec.Y, targetDir.Z)
		if finalLook.Magnitude < 0.001 then
			finalLook = Vector3.new(targetDir.X, lookVec.Y, targetDir.Z + 0.0001)
		end
		local blended = lookVec:Lerp(finalLook.Unit, blendFactor)
		if blended.Magnitude < 0.001 then
			blended = Vector3.new(finalLook.Unit.X, lookVec.Y, finalLook.Unit.Z)
		end
		CoreRoot.CFrame = CFrame.new(origin, origin + blended.Unit)
	end)
end

local function SmoothAimAtTarget(targetRoot, duration)
	duration = duration or CONFIG.AIM_DELAY
	if not (targetRoot and targetRoot.Parent) then return end
	local startTime = tick()
	local connection = nil
	connection = GameServices.Runtime.Heartbeat:Connect(function()
		if not (targetRoot and targetRoot.Parent) then
			connection:Disconnect()
			return
		end
		local elapsed = tick() - startTime
		local progress = math.clamp(elapsed / duration, 0, 1)
		local eased = 1 - (1 - progress) ^ math.max(1, CONFIG.AIM_POWER)
		local targetPos = targetRoot.Position
		local targetVel = Vector3.new(0, 0, 0)
		pcall(function()
			targetVel = targetRoot:GetVelocity() or targetRoot.Velocity or Vector3.new(0, 0, 0)
		end)
		local predictedPos = targetPos + Vector3.new(targetVel.X, 0, targetVel.Z) * CONFIG.VELOCITY_PREDICT
		pcall(function()
			local origin = CoreRoot.Position
			local lookVec = CoreRoot.CFrame.LookVector
			local direction = predictedPos - origin
			local horizontalDir = Vector3.new(direction.X, 0, direction.Z)
			if horizontalDir.Magnitude < 0.001 then
				horizontalDir = Vector3.new(1, 0, 0)
			end
			local targetDir = horizontalDir.Unit
			local finalLook = lookVec:Lerp(Vector3.new(targetDir.X, lookVec.Y, targetDir.Z).Unit, eased)
			CoreRoot.CFrame = CFrame.new(origin, origin + finalLook)
		end)
		if progress >= 1 then
			connection:Disconnect()
		end
	end)
end

local function ExecuteDashMovement(targetRoot, dashSpeed)
	dashSpeed = dashSpeed or CONFIG.DASH_VELOCITY
	local attach = Instance.new("Attachment")
	attach.Name = "MoveAttach"
	attach.Parent = CoreRoot
	local linVel = Instance.new("LinearVelocity")
	linVel.Name = "MoveVelocity"
	linVel.Attachment0 = attach
	linVel.MaxForce = math.huge
	linVel.RelativeTo = Enum.ActuatorRelativeTo.World
	linVel.Parent = CoreRoot
	local straightTrack = nil
	local straightAnim = nil
	if ActiveAnimations.Straight then
		local hum, anim = GetAnimatorContext()
		if hum and anim then
			straightAnim = Instance.new("Animation")
			straightAnim.Name = "StraightMove"
			straightAnim.AnimationId = "rbxassetid://" .. tostring(ActiveAnimations.Straight)
			local success, track = pcall(function() return anim:LoadAnimation(straightAnim) end)
			if success and track then
				track.Priority = Enum.AnimationPriority.Movement
				pcall(function() track.Looped = false end)
				pcall(function() track:Play() end)
				straightTrack = track
			else
				pcall(function() straightAnim:Destroy() end)
			end
		end
	end
	local isComplete = false
	local isActive = true
	local heartbeat = nil
	heartbeat = GameServices.Runtime.Heartbeat:Connect(function()
		if not isActive then return end
		if not (targetRoot and targetRoot.Parent and CoreRoot and CoreRoot.Parent) then
			isActive = false
			heartbeat:Disconnect()
			pcall(function() linVel:Destroy() end)
			pcall(function() attach:Destroy() end)
			pcall(function()
				if straightTrack and straightTrack.IsPlaying then straightTrack:Stop() end
				if straightAnim then straightAnim:Destroy() end
			end)
			return
		end
		local targetPos = targetRoot.Position
		local direction = targetPos - CoreRoot.Position
		local horizontalDir = Vector3.new(direction.X, 0, direction.Z)
		if horizontalDir.Magnitude > CONFIG.TARGET_THRESHOLD then
			linVel.VectorVelocity = horizontalDir.Unit * dashSpeed
			pcall(function()
				if horizontalDir.Magnitude > 0.001 then
					CoreRoot.CFrame = CFrame.new(CoreRoot.Position, CoreRoot.Position + horizontalDir.Unit)
				end
			end)
			pcall(function()
				AimAtPosition(targetPos, 0.56)
			end)
		else
			isComplete = true
			isActive = false
			heartbeat:Disconnect()
			pcall(function() linVel:Destroy() end)
			pcall(function() attach:Destroy() end)
			pcall(function()
				if straightTrack and straightTrack.IsPlaying then straightTrack:Stop() end
				if straightAnim then straightAnim:Destroy() end
			end)
		end
	end)
	repeat task.wait() until isComplete or not (targetRoot and targetRoot.Parent and CoreRoot and CoreRoot.Parent)
end

local function SendServerMessage(data)
	pcall(function()
		if CoreCharacter and CoreCharacter:FindFirstChild("Communicate") then
			CoreCharacter.Communicate:FireServer(unpack(data))
		end
	end)
end

local function ExecuteCircularDash(targetChar)
	if RuntimeState.isDashing then return end
	if not (targetChar and targetChar:FindFirstChild("HumanoidRootPart")) then return end
	if not CoreRoot then return end
	RuntimeState.isDashing = true
	local charHum = CoreCharacter:FindFirstChildOfClass("Humanoid")
	local origAutoRotate = nil
	if charHum then
		origAutoRotate = charHum.AutoRotate
		RuntimeState.rotateDisabled = true
		pcall(function() charHum.AutoRotate = false end)
	end
	local function RestoreRotation()
		if charHum and origAutoRotate ~= nil then
			RuntimeState.rotateDisabled = false
			pcall(function() charHum.AutoRotate = origAutoRotate end)
		end
	end
	local dashDur = CONFIG.DASH_DURATION
	local dashAngleDeg = CONFIG.DASH_ANGLE_DEG
	local dashDist = CONFIG.DASH_DISTANCE
	local targetRoot = targetChar.HumanoidRootPart
	if CONFIG.RANGE_MIN_TARGET <= (targetRoot.Position - CoreRoot.Position).Magnitude then
		ExecuteDashMovement(targetRoot, CONFIG.DASH_VELOCITY)
	end
	if not (targetRoot and targetRoot.Parent and CoreRoot and CoreRoot.Parent) then
		RestoreRotation()
		RuntimeState.isDashing = false
		return
	end
	local targetPos = targetRoot.Position
	local charPos = CoreRoot.Position
	local charRight = CoreRoot.CFrame.RightVector
	local direction = targetRoot.Position - CoreRoot.Position
	if direction.Magnitude < 0.001 then
		direction = CoreRoot.CFrame.LookVector
	end
	local isLeft = charRight:Dot(direction.Unit) < 0
	PlaySideAnim(isLeft)
	local dirMult = isLeft and 1 or -1
	local angleToTarget = math.atan2(charPos.Z - targetPos.Z, charPos.X - targetPos.X)
	local horizDist = (Vector3.new(charPos.X, 0, charPos.Z) - Vector3.new(targetPos.X, 0, targetPos.Z)).Magnitude
	local clampDist = math.clamp(horizDist, 1.2, 60)
	local startTime = tick()
	local movConn = nil
	local aimStarted = false
	local circleComplete = false
	local shouldEnd = false
	local dashFinished = false
	local function BeginEnd()
		if not circleComplete then
			circleComplete = true
			task.delay(CONFIG.AIM_DELAY, function()
				shouldEnd = true
				RestoreRotation()
				RuntimeState.lastPress = tick()
				if dashFinished then
					RuntimeState.isDashing = false
				end
			end)
		end
	end
	if RuntimeState.toggleM1 then
		SendServerMessage({ { Mobile = true, Goal = "LeftClick" } })
		task.delay(0.05, function()
			SendServerMessage({ { Goal = "LeftClickRelease", Mobile = true } })
		end)
	end
	if RuntimeState.toggleDash then
		SendServerMessage({ { Dash = Enum.KeyCode.W, Key = Enum.KeyCode.Q, Goal = "KeyPress" } })
	end
	movConn = GameServices.Runtime.Heartbeat:Connect(function()
		local elapsed = tick() - startTime
		local progress = math.clamp(elapsed / dashDur, 0, 1)
		local eased = EaseInOutCubic(progress)
		local aimProg = math.clamp(progress * 1.5, 0, 1)
		local currentRadius = clampDist + (dashDist - clampDist) * EaseInOutCubic(aimProg)
		local clampedRadius = math.clamp(currentRadius, 1.2, 60)
		local currentAngle = angleToTarget + dirMult * math.rad(dashAngleDeg) * EaseInOutCubic(progress)
		local currentTargetPos = targetRoot.Position
		local targetY = currentTargetPos.Y
		local circleX = currentTargetPos.X + clampedRadius * math.cos(currentAngle)
		local circleZ = currentTargetPos.Z + clampedRadius * math.sin(currentAngle)
		local newPos = Vector3.new(circleX, targetY, circleZ)
		if targetRoot then
			currentTargetPos = targetRoot.Position or currentTargetPos
		end
		local angleToPos = math.atan2((currentTargetPos - newPos).Z, (currentTargetPos - newPos).X)
		local charAngle = math.atan2(CoreRoot.CFrame.LookVector.Z, CoreRoot.CFrame.LookVector.X)
		local finalAngle = charAngle + NormalizeAngle(angleToPos, charAngle) * CONFIG.DIRECTION_BLEND
		pcall(function()
			CoreRoot.CFrame = CFrame.new(newPos, newPos + Vector3.new(math.cos(finalAngle), 0, math.sin(finalAngle)))
		end)
		if not aimStarted and CONFIG.CIRCLE_THRESHOLD <= eased then
			aimStarted = true
			pcall(function()
				SmoothAimAtTarget(targetRoot, CONFIG.AIM_DELAY)
			end)
			BeginEnd()
		end
		if progress >= 1 then
			movConn:Disconnect()
			pcall(function()
				if RuntimeState.sideTrack and RuntimeState.sideTrack.IsPlaying then
					RuntimeState.sideTrack:Stop()
				end
				RuntimeState.sideTrack = nil
			end)
			if not aimStarted then
				aimStarted = true
				pcall(function()
					SmoothAimAtTarget(targetRoot, CONFIG.AIM_DELAY)
				end)
				BeginEnd()
			end
			dashFinished = true
			if shouldEnd then
				RuntimeState.isDashing = false
			end
		end
	end)
end

-- ur gay wasp
local GUIServices = {
	players = GameServices.Players,
	tween = GameServices.Tweens,
	input = GameServices.Input,
	lp = CorePlayer,
	starterGui = game:GetService("StarterGui")
}

pcall(function()
	GUIServices.starterGui:SetCore("SendNotification", {
		Title = "Side Dash Assist V2.1",
		Text = "Enjoy! Report bugs on discord server",
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
mainGui.Parent = CorePlayer:WaitForChild("PlayerGui")

local blur = Instance.new("BlurEffect")
blur.Size = 0
blur.Parent = game:GetService("Lighting")

local function MakeDraggable(obj)
	local dragging = false
	local dragStart, startPos, curInput
	obj.InputBegan:Connect(function(inp)
		if (inp.UserInputType == Enum.UserInputType.Touch or inp.UserInputType == Enum.UserInputType.MouseButton1) and not dragging then
			dragging = true
			dragStart = inp.Position
			startPos = obj.Position
			curInput = inp
			inp.Changed:Connect(function()
				if inp.UserInputState == Enum.UserInputState.End then
					dragging = false
					curInput = nil
				end
			end)
		end
	end)
	GUIServices.input.InputChanged:Connect(function(inp)
		if dragging and curInput == inp and (inp.UserInputType == Enum.UserInputType.Touch or inp.UserInputType == Enum.UserInputType.MouseMovement) then
			local delta = inp.Position - dragStart
			obj.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y)
		end
	end)
end

local mainFrame = Instance.new("Frame")
mainFrame.Name = "MainFrame"
mainFrame.Size = UDim2.new(0, 380, 0, 140)
mainFrame.Position = UDim2.new(0.5, -190, 0.12, 0)
mainFrame.BackgroundColor3 = Color3.fromRGB(15, 15, 15)
mainFrame.BackgroundTransparency = 1
mainFrame.BorderSizePixel = 0
mainFrame.Visible = false
mainFrame.Parent = mainGui
MakeDraggable(mainFrame)

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
versionLabel.Text = "v2.1"
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
		GUIServices.tween:Create(buttonBg, TweenInfo.new(0.25), {BackgroundColor3 = Color3.fromRGB(180, 13, 19)}):Play()
		GUIServices.tween:Create(buttonBorder, TweenInfo.new(0.25), {Color = Color3.fromRGB(255, 0, 0)}):Play()
	else
		toggleButton.Text = "Enabled: OFF"
		GUIServices.tween:Create(buttonBg, TweenInfo.new(0.25), {BackgroundColor3 = Color3.fromRGB(54, 54, 54)}):Play()
		GUIServices.tween:Create(buttonBorder, TweenInfo.new(0.25), {Color = Color3.fromRGB(110, 110, 110)}):Play()
	end
end

toggleButton.MouseButton1Click:Connect(function()
	EnabledFlag = not EnabledFlag
	UpdateToggle()
end)

UpdateToggle()

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
settingsOverlay.Size = UDim2.new(0, 300, 0, 190)
settingsOverlay.Position = UDim2.new(0, 40, 0.2, 0)
settingsOverlay.BackgroundColor3 = Color3.fromRGB(15, 15, 15)
settingsOverlay.BackgroundTransparency = 1
settingsOverlay.BorderSizePixel = 0
settingsOverlay.Visible = false
settingsOverlay.Parent = mainGui
MakeDraggable(settingsOverlay)

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

local comingSoon = Instance.new("TextLabel")
comingSoon.Size = UDim2.new(1, 0, 0, 40)
comingSoon.Position = UDim2.new(0, 0, 0, 52)
comingSoon.BackgroundTransparency = 1
comingSoon.Text = "COMING SOON!..."
comingSoon.TextColor3 = Color3.fromRGB(255, 60, 60)
comingSoon.TextSize = 22
comingSoon.Font = Enum.Font.GothamBold
comingSoon.TextXAlignment = Enum.TextXAlignment.Center
comingSoon.Parent = settingsOverlay

local keybindFrame = Instance.new("Frame")
keybindFrame.Size = UDim2.new(1, -32, 0, 90)
keybindFrame.Position = UDim2.new(0, 16, 0, 98)
keybindFrame.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
keybindFrame.BorderSizePixel = 0
keybindFrame.Parent = settingsOverlay

local keybindCorner = Instance.new("UICorner")
keybindCorner.CornerRadius = UDim.new(0, 14)
keybindCorner.Parent = keybindFrame

local keyTitle = Instance.new("TextLabel")
keyTitle.Size = UDim2.new(1, -20, 0, 24)
keyTitle.Position = UDim2.new(0, 10, 0, 8)
keyTitle.BackgroundTransparency = 1
keyTitle.Text = "Keybind Info"
keyTitle.TextColor3 = Color3.fromRGB(230, 230, 230)
keyTitle.TextSize = 18
keyTitle.Font = Enum.Font.GothamBold
keyTitle.TextXAlignment = Enum.TextXAlignment.Left
keyTitle.Parent = keybindFrame

local keyInfo = Instance.new("TextLabel")
keyInfo.Size = UDim2.new(1, -20, 0, 24)
keyInfo.Position = UDim2.new(0, 10, 0, 40)
keyInfo.BackgroundTransparency = 1
keyInfo.Text = "CP Keybinds: E"
keyInfo.TextColor3 = Color3.fromRGB(205, 205, 205)
keyInfo.TextSize = 16
keyInfo.Font = Enum.Font.Gotham
keyInfo.TextXAlignment = Enum.TextXAlignment.Left
keyInfo.Parent = keybindFrame

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
MakeDraggable(openButton)

local function SetMainTransparency(alpha)
	mainFrame.BackgroundTransparency = alpha
	borderFrame.BackgroundTransparency = alpha
	titleLabel.TextTransparency = alpha
	authorLabel.TextTransparency = 0.28 + (alpha * 0.7)
	versionLabel.TextTransparency = alpha
	toggleButton.TextTransparency = alpha
	closeBtn.TextTransparency = alpha
	minimizeBtn.TextTransparency = alpha
	settingsBtn.TextTransparency = alpha
end

local function FadeInMain()
	mainFrame.Visible = true
	SetMainTransparency(1)
	GUIServices.tween:Create(blur, TweenInfo.new(0.3), {Size = 12}):Play()
	GUIServices.tween:Create(mainFrame, TweenInfo.new(0.3), {BackgroundTransparency = 0}):Play()
	GUIServices.tween:Create(borderFrame, TweenInfo.new(0.3), {BackgroundTransparency = 0}):Play()
	GUIServices.tween:Create(titleLabel, TweenInfo.new(0.3), {TextTransparency = 0}):Play()
	GUIServices.tween:Create(authorLabel, TweenInfo.new(0.3), {TextTransparency = 0.28}):Play()
	GUIServices.tween:Create(versionLabel, TweenInfo.new(0.3), {TextTransparency = 0}):Play()
	GUIServices.tween:Create(toggleButton, TweenInfo.new(0.3), {TextTransparency = 0}):Play()
	GUIServices.tween:Create(closeBtn, TweenInfo.new(0.3), {TextTransparency = 0}):Play()
	GUIServices.tween:Create(minimizeBtn, TweenInfo.new(0.3), {TextTransparency = 0}):Play()
	GUIServices.tween:Create(settingsBtn, TweenInfo.new(0.3), {TextTransparency = 0}):Play()
end

local function FadeOutMain(callback)
	local t1 = GUIServices.tween:Create(blur, TweenInfo.new(0.3), {Size = 0})
	local t3 = GUIServices.tween:Create(mainFrame, TweenInfo.new(0.3), {BackgroundTransparency = 1})
	local t4 = GUIServices.tween:Create(borderFrame, TweenInfo.new(0.3), {BackgroundTransparency = 1})
	local t5 = GUIServices.tween:Create(titleLabel, TweenInfo.new(0.3), {TextTransparency = 1})
	local t6 = GUIServices.tween:Create(authorLabel, TweenInfo.new(0.3), {TextTransparency = 1})
	local t7 = GUIServices.tween:Create(versionLabel, TweenInfo.new(0.3), {TextTransparency = 1})
	local t8 = GUIServices.tween:Create(toggleButton, TweenInfo.new(0.3), {TextTransparency = 1})
	local t9 = GUIServices.tween:Create(closeBtn, TweenInfo.new(0.3), {TextTransparency = 1})
	local t10 = GUIServices.tween:Create(minimizeBtn, TweenInfo.new(0.3), {TextTransparency = 1})
	local t11 = GUIServices.tween:Create(settingsBtn, TweenInfo.new(0.3), {TextTransparency = 1})
	t1:Play() t3:Play() t4:Play()
	t5:Play() t6:Play() t7:Play()
	t8:Play() t9:Play() t10:Play() t11:Play()
	t4.Completed:Connect(function()
		mainFrame.Visible = false
		if callback then callback() end
	end)
end

local function FadeInSettings()
	settingsOverlay.Visible = true
	GUIServices.tween:Create(settingsOverlay, TweenInfo.new(0.25), {BackgroundTransparency = 0}):Play()
end

local function FadeOutSettings()
	local t = GUIServices.tween:Create(settingsOverlay, TweenInfo.new(0.25), {BackgroundTransparency = 1})
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

GUIServices.input.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then return end
	if not EnabledFlag then return end
	if input.KeyCode == Enum.KeyCode.E then
		if not IsCharacterValid() then return end
		local target = AcquireTarget()
		if target then
			ExecuteCircularDash(target)
		end
	end
end)

-- ur gay wasp
