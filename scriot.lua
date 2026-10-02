-- Сервисы Roblox
local Players = game:GetService("Players")
local CoreGui = game:GetService("CoreGui")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")

local localPlayer = Players.LocalPlayer
local camera = workspace.CurrentCamera

-- Состояния функций
local espEnabled = false
local bhopEnabled = false
local flyEnabled = false
local noclipEnabled = false
local speedEnabled = false

local flySpeed = 50
local walkSpeedValue = 32

local activeHighlights = {}
local noclipConnection = nil
local savedCollisions = {}

-- 1. СОЗДАНИЕ ИНТЕРФЕЙСА (GUI)
local screenGui = Instance.new("ScreenGui")
screenGui.Name = "BloxStrikeLegitGUI"
screenGui.ResetOnSpawn = false

local success = pcall(function() screenGui.Parent = CoreGui end)
if not success then screenGui.Parent = localPlayer:WaitForChild("PlayerGui") end

local mainFrame = Instance.new("Frame")
mainFrame.Size = UDim2.new(0, 360, 0, 200)
mainFrame.Position = UDim2.new(0.1, 0, 0.1, 0)
mainFrame.BackgroundColor3 = Color3.fromRGB(25, 25, 25)
mainFrame.BorderSizePixel = 0
mainFrame.Active = true
mainFrame.Draggable = true
mainFrame.Parent = screenGui

local frameCorner = Instance.new("UICorner")
frameCorner.CornerRadius = UDim.new(0, 8)
frameCorner.Parent = mainFrame

local titleLabel = Instance.new("TextLabel")
titleLabel.Size = UDim2.new(1, 0, 0, 30)
titleLabel.BackgroundTransparency = 1
titleLabel.Text = "Blox Strike Utility | Insert to Hide"
titleLabel.TextColor3 = Color3.fromRGB(200, 200, 200)
titleLabel.Font = Enum.Font.SourceSansBold
titleLabel.TextSize = 16
titleLabel.Parent = mainFrame

local TOGGLE_KEY = Enum.KeyCode.Insert
UserInputService.InputBegan:Connect(function(input, gameProcessed)
    if gameProcessed then return end
    if input.KeyCode == TOGGLE_KEY then mainFrame.Visible = not mainFrame.Visible end
end)

local function createButton(text, position)
    local btn = Instance.new("TextButton")
    btn.Size = UDim2.new(0, 150, 0, 40)
    btn.Position = position
    btn.BackgroundColor3 = Color3.fromRGB(180, 50, 50)
    btn.Text = text .. ": OFF"
    btn.TextColor3 = Color3.fromRGB(255, 255, 255)
    btn.Font = Enum.Font.SourceSansBold
    btn.TextSize = 14
    btn.Parent = mainFrame

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 6)
    corner.Parent = btn
    return btn
end

local espButton = createButton("ESP", UDim2.new(0, 20, 0, 45))
local bhopButton = createButton("BHOP", UDim2.new(0, 20, 0, 95))
local speedButton = createButton("FAST SPEED", UDim2.new(0, 20, 0, 145))

local flyButton = createButton("FLY", UDim2.new(0, 190, 0, 45))
local noclipButton = createButton("NO CLIP", UDim2.new(0, 190, 0, 95))

local function toggleVisual(button, state, name)
    button.Text = name .. (state and ": ON" or ": OFF")
    local color = state and Color3.fromRGB(50, 180, 50) or Color3.fromRGB(180, 50, 50)
    TweenService:Create(button, TweenInfo.new(0.2), {BackgroundColor3 = color}):Play()
end

-- 2. ЛОГИКА ESP
local function createHighlight(character)
    local oldHighlight = character:FindFirstChild("ESPHighlight")
    if oldHighlight then oldHighlight:Destroy() end
    local highlight = Instance.new("Highlight")
    highlight.Name = "ESPHighlight"
    highlight.FillColor = Color3.fromRGB(255, 0, 0)
    highlight.FillTransparency = 0.5
    highlight.OutlineColor = Color3.fromRGB(255, 255, 255)
    highlight.Enabled = espEnabled
    highlight.Parent = character
    return highlight
end

local function monitorPlayer(player)
    if player == localPlayer then return end
    player.CharacterAdded:Connect(function(character)
        task.wait(0.2)
        if character and character.Parent then activeHighlights[player] = createHighlight(character) end
    end)
    if player.Character then activeHighlights[player] = createHighlight(player.Character) end
end

for _, player in pairs(Players:GetPlayers()) do monitorPlayer(player) end
Players.PlayerAdded:Connect(monitorPlayer)

-- 3. ЦИКЛ ДЛЯ ПОЛЕТА (FLY), СКОРОСТИ (SPEED) И BHOP
local bodyVelocity = nil
local bodyGyro = nil
local flyAttachment = nil

RunService.RenderStepped:Connect(function()
    local character = localPlayer.Character
    if not character then return end
    local humanoid = character:FindFirstChildOfClass("Humanoid")
    local rootPart = character:FindFirstChild("HumanoidRootPart")
    if not humanoid or not rootPart or humanoid.Health <= 0 then return end

    -- ЛОГИКА FAST SPEED (через отдельную переменную speedEnabled)
    if not flyEnabled then
        local targetSpeed = speedEnabled and walkSpeedValue or 16
        if humanoid.WalkSpeed ~= targetSpeed then
            humanoid.WalkSpeed = targetSpeed
        end
    end

    -- ЛОГИКА BHOP
    if bhopEnabled and not flyEnabled and UserInputService:IsKeyDown(Enum.KeyCode.Space) then
        if humanoid.FloorMaterial ~= Enum.Material.Air then
            rootPart.Velocity = Vector3.new(rootPart.Velocity.X, 45, rootPart.Velocity.Z)
        end
    end

    -- ЛОГИКА ПОЛЕТА (FLY) — LinearVelocity + BodyGyro
    if flyEnabled then
        humanoid.PlatformStand = true
        humanoid:ChangeState(Enum.HumanoidStateType.Physics)

        if not bodyVelocity or bodyVelocity.Parent ~= rootPart then
            if bodyVelocity then bodyVelocity:Destroy() end
            if bodyGyro then bodyGyro:Destroy() end
            if flyAttachment then flyAttachment:Destroy() end

            flyAttachment = Instance.new("Attachment")
            flyAttachment.Parent = rootPart

            bodyVelocity = Instance.new("LinearVelocity")
            bodyVelocity.MaxForce = math.huge
            bodyVelocity.VelocityConstraintMode = Enum.VelocityConstraintMode.Vector
            bodyVelocity.RelativeTo = Enum.ActuatorRelativeTo.World
            bodyVelocity.Attachment0 = flyAttachment
            bodyVelocity.Parent = rootPart

            bodyGyro = Instance.new("BodyGyro")
            bodyGyro.MaxTorque = Vector3.new(math.huge, math.huge, math.huge)
            bodyGyro.P = 10000
            bodyGyro.D = 500
            bodyGyro.CFrame = rootPart.CFrame
            bodyGyro.Parent = rootPart
        end

        -- Гироскоп удерживает ориентацию по камере
        bodyGyro.CFrame = CFrame.new(rootPart.Position, rootPart.Position + camera.CFrame.LookVector)

        local direction = Vector3.new(0, 0, 0)
        if UserInputService:IsKeyDown(Enum.KeyCode.W) then direction += camera.CFrame.LookVector end
        if UserInputService:IsKeyDown(Enum.KeyCode.S) then direction -= camera.CFrame.LookVector end
        if UserInputService:IsKeyDown(Enum.KeyCode.A) then direction -= camera.CFrame.RightVector end
        if UserInputService:IsKeyDown(Enum.KeyCode.D) then direction += camera.CFrame.RightVector end
        if UserInputService:IsKeyDown(Enum.KeyCode.Space) then direction += Vector3.new(0, 1, 0) end
        if UserInputService:IsKeyDown(Enum.KeyCode.LeftShift) then direction -= Vector3.new(0, 1, 0) end

        if direction.Magnitude > 0 then
            bodyVelocity.VectorVelocity = direction.Unit * flySpeed
        else
            bodyVelocity.VectorVelocity = Vector3.new(0, 0, 0)
        end
    else
        if bodyVelocity then bodyVelocity:Destroy() bodyVelocity = nil end
        if bodyGyro then bodyGyro:Destroy() bodyGyro = nil end
        if flyAttachment then flyAttachment:Destroy() flyAttachment = nil end
        if humanoid.PlatformStand then humanoid.PlatformStand = false end
    end
end)

-- 4. ЛОГИКА NO CLIP
local function startNoclip()
    if noclipConnection then noclipConnection:Disconnect() end
    noclipConnection = RunService.Stepped:Connect(function()
        if noclipEnabled and localPlayer.Character then
            for _, part in pairs(localPlayer.Character:GetDescendants()) do
                if part:IsA("BasePart") and part.CanCollide then
                    savedCollisions[part] = true
                    part.CanCollide = false
                end
            end
        end
    end)
end

-- 5. ОБРАБОТКА НАЖАТИЙ КНОПОК
espButton.MouseButton1Click:Connect(function()
    espEnabled = not espEnabled
    toggleVisual(espButton, espEnabled, "ESP")
    for _, highlight in pairs(activeHighlights) do
        if highlight and highlight.Parent then highlight.Enabled = espEnabled end
    end
end)

bhopButton.MouseButton1Click:Connect(function()
    bhopEnabled = not bhopEnabled
    toggleVisual(bhopButton, bhopEnabled, "BHOP")
end)

speedButton.MouseButton1Click:Connect(function()
    speedEnabled = not speedEnabled
    toggleVisual(speedButton, speedEnabled, "FAST SPEED")
end)

flyButton.MouseButton1Click:Connect(function()
    flyEnabled = not flyEnabled
    toggleVisual(flyButton, flyEnabled, "FLY")
end)

noclipButton.MouseButton1Click:Connect(function()
    noclipEnabled = not noclipEnabled
    toggleVisual(noclipButton, noclipEnabled, "NO CLIP")
    if noclipEnabled then
        startNoclip()
    else
        if noclipConnection then
            noclipConnection:Disconnect()
            noclipConnection = nil
        end
        for part, _ in pairs(savedCollisions) do
            if part and part.Parent then
                part.CanCollide = true
            end
        end
        savedCollisions = {}
    end
end)
