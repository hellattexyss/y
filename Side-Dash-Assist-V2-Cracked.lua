local PlayersService = game:GetService("Players")
local RunService = game:GetService("RunService")
local InputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local HttpService = game:GetService("HttpService")
local WorkspaceService = game:GetService("Workspace")

local LocalPlayer = PlayersService.LocalPlayer
local CurrentCamera = WorkspaceService.CurrentCamera
local Character = LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
local HumanoidRootPart = Character:WaitForChild("HumanoidRootPart")
local Humanoid = Character:FindFirstChildOfClass("Humanoid")

_G.SideDashAssistEnabled = true

local FIXED_SPEED_SLIDER_VALUE = 84
local FIXED_DEGREES_SLIDER_VALUE = 100
local FIXED_GAP_SLIDER_VALUE = 75

local ANIMATION_IDS = {
    [10449761463] = {Left = 10480796021, Right = 10480793962, Straight = 10479335397},
    [13076380114] = {Left = 101843860692381, Right = 100087324592640, Straight = 110878031211717}
}

local gameId = game.PlaceId
local currentGameAnimations = ANIMATION_IDS[gameId] or ANIMATION_IDS[13076380114]
local leftAnimationId = currentGameAnimations.Left
local rightAnimationId = currentGameAnimations.Right
local straightAnimationId = currentGameAnimations.Straight

local MAX_TARGET_RANGE = 40
local MIN_DASH_DISTANCE = 1.2
local MAX_DASH_DISTANCE = 60
local MIN_TARGET_DISTANCE = 15
local TARGET_REACH_THRESHOLD = 10
local DASH_SPEED = 120
local DIRECTION_LERP_FACTOR = 0.7
local CAMERA_FOLLOW_DELAY = 0.7
local VELOCITY_PREDICTION_FACTOR = 0.5
local FOLLOW_EASING_POWER = 200
local CIRCLE_COMPLETION_THRESHOLD = 390 / 480

local isDashing = false
local sideAnimationTrack = nil
local lastButtonPressTime = -math.huge

local dashSound = Instance.new("Sound")
dashSound.Name = "DashSFX"
dashSound.SoundId = "rbxassetid://72014632956520"
dashSound.Volume = 2
dashSound.Looped = false
dashSound.Parent = WorkspaceService
local function isCharacterDisabled()
    if not (Humanoid and Humanoid.Parent) then return false end
    if Humanoid.Health <= 0 or Humanoid.PlatformStand then return true end
    local success, state = pcall(function() return Humanoid:GetState() end)
    if success and state == Enum.HumanoidStateType.Physics then return true end
    local ragdollValue = Character:FindFirstChild("Ragdoll")
    return ragdollValue and ragdollValue:IsA("BoolValue") and ragdollValue.Value
end

LocalPlayer.CharacterAdded:Connect(function(newCharacter)
    Character = newCharacter
    HumanoidRootPart = newCharacter:WaitForChild("HumanoidRootPart")
    Humanoid = newCharacter:FindFirstChildOfClass("Humanoid")
end)

local function getHumanoidAndAnimator()
    if not (Character and Character.Parent) then return nil, nil end
    local foundHumanoid = Character:FindFirstChildOfClass("Humanoid")
    if not foundHumanoid then return nil, nil end
    local animator = foundHumanoid:FindFirstChildOfClass("Animator")
    if not animator then
        animator = Instance.new("Animator")
        animator.Name = "Animator"
        animator.Parent = foundHumanoid
    end
    return foundHumanoid, animator
end

local function playSideAnimation(isLeftDirection)
    pcall(function() if sideAnimationTrack and sideAnimationTrack.IsPlaying then sideAnimationTrack:Stop() end end)
    sideAnimationTrack = nil
    local targetHumanoid, animator = getHumanoidAndAnimator()
    if targetHumanoid and animator then
        local animationId = isLeftDirection and leftAnimationId or rightAnimationId
        local animationInstance = Instance.new("Animation")
        animationInstance.Name = "CircularSideAnim"
        animationInstance.AnimationId = "rbxassetid://" .. tostring(animationId)
        local success, loadedAnimation = pcall(function() return animator:LoadAnimation(animationInstance) end)
        if success and loadedAnimation then
            sideAnimationTrack = loadedAnimation
            loadedAnimation.Priority = Enum.AnimationPriority.Action
            loadedAnimation.Looped = false
            loadedAnimation:Play()
            pcall(function() dashSound:Stop() dashSound:Play() end)
            delay(0.6, function()
                pcall(function() if loadedAnimation and loadedAnimation.IsPlaying then loadedAnimation:Stop() end end)
                pcall(function() animationInstance:Destroy() end)
            end)
        else
            pcall(function() animationInstance:Destroy() end)
        end
    end
end

local function findNearestTarget(maxRange)
    maxRange = maxRange or MAX_TARGET_RANGE
    local nearestTarget, nearestDistance = nil, math.huge
    if not HumanoidRootPart then return nil end
    local rootPosition = HumanoidRootPart.Position
    for _, player in pairs(PlayersService:GetPlayers()) do
        if player ~= LocalPlayer and player.Character and player.Character:FindFirstChild("HumanoidRootPart") and player.Character:FindFirstChild("Humanoid") then
            local playerHumanoid = player.Character:FindFirstChild("Humanoid")
            if playerHumanoid and playerHumanoid.Health > 0 then
                local distance = (player.Character.HumanoidRootPart.Position - rootPosition).Magnitude
                if distance < nearestDistance and distance <= maxRange then
                    nearestTarget = player.Character
                    nearestDistance = distance
                end
            end
        end
    end
    return nearestTarget, nearestDistance
end
local function calculateDashDuration(speedSliderValue) local clampedValue = math.clamp(speedSliderValue or 84, 0, 100) / 100 return 1.5 + (0.12 - 1.5) * clampedValue end
local function calculateDashAngle(degreesSliderValue) return 90 + 990 * (math.clamp(degreesSliderValue or 56, 0, 100) / 100) end
local function calculateDashDistance(gapSliderValue) return 1 + 11 * (math.clamp(gapSliderValue or 50, 0, 100) / 100) end

local function getFixedSettings()
    local speedValue = FIXED_SPEED_SLIDER_VALUE
    local degreesValue = FIXED_DEGREES_SLIDER_VALUE
    local gapValue = FIXED_GAP_SLIDER_VALUE
    local dashDuration = calculateDashDuration(speedValue)
    local dashAngle = calculateDashAngle(degreesValue)
    local dashAngleRad = math.rad(dashAngle)
    local dashDistance = math.clamp(calculateDashDistance(gapValue), MIN_DASH_DISTANCE, MAX_DASH_DISTANCE)
    return dashDuration, dashAngleRad, dashDistance
end

local function performCircularDash(targetCharacter)
    if not _G.SideDashAssistEnabled or isDashing or not (targetCharacter and targetCharacter:FindFirstChild("HumanoidRootPart")) or not HumanoidRootPart then return end
    isDashing = true
    local characterHumanoid = Character:FindFirstChildOfClass("Humanoid")
    local originalAutoRotate = characterHumanoid and characterHumanoid.AutoRotate
    if characterHumanoid then characterHumanoid.AutoRotate = false end

    local dashDuration, dashAngleRad, dashDistance = getFixedSettings()
    local targetRoot = targetCharacter.HumanoidRootPart
    local targetPosition = targetRoot.Position
    local characterPosition = HumanoidRootPart.Position
    local characterRightVector = HumanoidRootPart.CFrame.RightVector
    local directionToTarget = targetRoot.Position - HumanoidRootPart.Position
    local isLeftDirection = characterRightVector:Dot(directionToTarget.Unit) < 0
    playSideAnimation(isLeftDirection)
    local directionMultiplier = isLeftDirection and 1 or -1
    local angleToTarget = math.atan2(characterPosition.Z - targetPosition.Z, characterPosition.X - targetPosition.X)
    local horizontalDistance = (Vector3.new(characterPosition.X, 0, characterPosition.Z) - Vector3.new(targetPosition.X, 0, targetPosition.Z)).Magnitude
    local clampedDistance = math.clamp(horizontalDistance, MIN_DASH_DISTANCE, MAX_DASH_DISTANCE)
    
    local startTime = tick()
    local movementConnection = RunService.Heartbeat:Connect(function()
        local currentTime = tick()
        local progress = math.clamp((currentTime - startTime) / dashDuration, 0, 1)
        local easedProgress = 1 - (1 - progress) ^ 3
        local aimProgress = math.clamp(progress * 1.5, 0, 1)
        local currentRadius = clampedDistance + (dashDistance - clampedDistance) * (1 - (1 - aimProgress) ^ 3)
        local clampedRadius = math.clamp(currentRadius, MIN_DASH_DISTANCE, MAX_DASH_DISTANCE)
        local currentAngle = angleToTarget + directionMultiplier * dashAngleRad * (1 - (1 - progress) ^ 3)
        local currentTargetPosition = targetRoot.Position
        local targetY = currentTargetPosition.Y
        local circleX = currentTargetPosition.X + clampedRadius * math.cos(currentAngle)
        local circleZ = currentTargetPosition.Z + clampedRadius * math.sin(currentAngle)
        local newPosition = Vector3.new(circleX, targetY, circleZ)
        local angleToTargetPosition = math.atan2((currentTargetPosition - newPosition).Z, (currentTargetPosition - newPosition).X)
        local characterAngle = math.atan2(HumanoidRootPart.CFrame.LookVector.Z, HumanoidRootPart.CFrame.LookVector.X)
        local finalCharacterAngle = characterAngle + (angleToTargetPosition - characterAngle) * DIRECTION_LERP_FACTOR
        pcall(function()
            HumanoidRootPart.CFrame = CFrame.new(newPosition, newPosition + Vector3.new(math.cos(finalCharacterAngle), 0, math.sin(finalCharacterAngle)))
        end)
        if progress >= 1 then
            movementConnection:Disconnect()
            pcall(function() if sideAnimationTrack and sideAnimationTrack.IsPlaying then sideAnimationTrack:Stop() end end)
            sideAnimationTrack = nil
            isDashing = false
            if characterHumanoid and originalAutoRotate ~= nil then characterHumanoid.AutoRotate = originalAutoRotate end
        end
    end)
end
local lockedTargetPlayer = nil
PlayersService.PlayerRemoving:Connect(function(removedPlayer) if lockedTargetPlayer == removedPlayer then lockedTargetPlayer = nil end end)

local function getCurrentTarget()
    if lockedTargetPlayer and lockedTargetPlayer.Character and lockedTargetPlayer.Character:FindFirstChild("HumanoidRootPart") then
        local targetRoot = lockedTargetPlayer.Character.HumanoidRootPart
        local targetHumanoid = lockedTargetPlayer.Character:FindFirstChild("Humanoid")
        if targetHumanoid and targetHumanoid.Health > 0 and (targetRoot.Position - HumanoidRootPart.Position).Magnitude <= MAX_TARGET_RANGE then
            return lockedTargetPlayer.Character
        end
    end
    return findNearestTarget(MAX_TARGET_RANGE)
end

local function createMobileDashButton()
    pcall(function()
        local existingGui = LocalPlayer.PlayerGui:FindFirstChild("CircularTweenUI_Merged")
        if existingGui then existingGui:Destroy() end
    end)
    local mobileGui = Instance.new("ScreenGui")
    mobileGui.Name = "CircularTweenUI_Merged"
    mobileGui.ResetOnSpawn = false
    mobileGui.Parent = LocalPlayer:WaitForChild("PlayerGui")
    local dashButton = Instance.new("ImageButton")
    dashButton.Name = "DashButton"
    dashButton.Size = UDim2.new(0, 110, 0, 110)
    dashButton.Position = UDim2.new(0.5, -55, 0.8, -55)
    dashButton.BackgroundTransparency = 1
    dashButton.Image = "rbxassetid://99317918824094"
    dashButton.Parent = mobileGui
    local buttonScale = Instance.new("UIScale", dashButton)
    buttonScale.Scale = 1
    local pressSound = Instance.new("Sound", dashButton)
    pressSound.SoundId = "rbxassetid://5852470908"
    pressSound.Volume = 0.9
    
    local isButtonPressed = false
    local isBeingDragged = false
    local dragInput, dragStartPosition, buttonStartPosition
    local dragThreshold = 8
    
    local function animateButtonScale(targetScale, duration)
        duration = duration or 0.06
        local success, tween = pcall(function()
            return TweenService:Create(buttonScale, TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {Scale = targetScale})
        end)
        if success and tween then tween:Play() end
    end
    
    dashButton.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
            isButtonPressed = true
            isBeingDragged = false
            dragStartPosition = input.Position
            buttonStartPosition = dashButton.Position
            dragInput = input
            animateButtonScale(0.92, 0.06)
            pcall(function() pressSound:Play() end)
        end
    end)
    
    InputService.InputChanged:Connect(function(input)
        if isButtonPressed and dragInput and input == dragInput then
            local delta = input.Position - dragStartPosition
            if not isBeingDragged and delta.Magnitude >= dragThreshold then
                isBeingDragged = true
                animateButtonScale(1, 0.06)
            end
            if isBeingDragged then
                local viewportSize = WorkspaceService.CurrentCamera.ViewportSize
                local newX = math.clamp(buttonStartPosition.X.Offset + delta.X, 0, viewportSize.X - dashButton.AbsoluteSize.X)
                local newY = math.clamp(buttonStartPosition.Y.Offset + delta.Y, 0, viewportSize.Y - dashButton.AbsoluteSize.Y)
                dashButton.Position = UDim2.new(0, newX, 0, newY)
            end
        end
    end)
    
    InputService.InputEnded:Connect(function(input)
        if input == dragInput and isButtonPressed then
            if not isBeingDragged and tick() - lastButtonPressTime >= 2 then
                if not isCharacterDisabled() then
                    local target = getCurrentTarget()
                    if target then performCircularDash(target) end
                end
            end
            animateButtonScale(1, 0.06)
            dragInput, buttonStartPosition, dragStartPosition = nil, nil, nil
            isBeingDragged, isButtonPressed = false, false
        end
    end)
end

createMobileDashButton()

InputService.InputBegan:Connect(function(input, gp)
    if gp then return end
    if input.KeyCode == Enum.KeyCode.E and _G.SideDashAssistEnabled and not isCharacterDisabled() then
        local target = getCurrentTarget()
        if target then performCircularDash(target) end
    end
end)

-- Cleanup old GUIs
task.wait(1)
pcall(function()
    local pg = LocalPlayer.PlayerGui
    if pg:FindFirstChild("SettingsGUI_Only_V2_Merged") then pg:FindFirstChild("SettingsGUI_Only_V2_Merged"):Destroy() end
    if pg:FindFirstChild("DashSettingsGui_Merged") then pg:FindFirstChild("DashSettingsGui_Merged"):Destroy() end
end)
