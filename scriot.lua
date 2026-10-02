-- Blox Strike Utility | Xeno Edition | v2
-- Работает: ESP, BHOP, SPEED (до 22), FLY (CFrame), NOCLIP (CFrame)
-- Автор: адаптация под Blox Strike

local Players          = game:GetService("Players")
local CoreGui          = game:GetService("CoreGui")
local TweenService     = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local RunService       = game:GetService("RunService")

local localPlayer = Players.LocalPlayer
local camera      = workspace.CurrentCamera

-- ============ СОСТОЯНИЯ ============
local espEnabled    = false
local bhopEnabled   = false
local flyEnabled    = false
local noclipEnabled = false
local speedEnabled  = false

local flySpeed        = 60     -- скорость CFrame-полёта
local walkSpeedValue  = 22     -- безопасный лимит в Blox Strike (16-22)
local bhopPower       = 45

-- ============ ХРАНИЛИЩА ============
local activeHighlights = {}
local noclipConnection = nil
local savedCollisions  = {}
local flyConnection    = nil

-- =========================================================
-- 1. GUI
-- =========================================================
local screenGui = Instance.new("ScreenGui")
screenGui.Name = "BloxStrikeUtility"
screenGui.ResetOnSpawn = false
screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

local ok = pcall(function() screenGui.Parent = CoreGui end)
if not ok then
    screenGui.Parent = localPlayer:WaitForChild("PlayerGui")
end

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

-- Переключение видимости меню
UserInputService.InputBegan:Connect(function(input, gp)
    if gp then return end
    if input.KeyCode == Enum.KeyCode.Insert then
        mainFrame.Visible = not mainFrame.Visible
    end
end)

local function createButton(text, pos)
    local btn = Instance.new("TextButton")
    btn.Size = UDim2.new(0, 150, 0, 40)
    btn.Position = pos
    btn.BackgroundColor3 = Color3.fromRGB(180, 50, 50)
    btn.Text = text .. ": OFF"
    btn.TextColor3 = Color3.fromRGB(255, 255, 255)
    btn.Font = Enum.Font.SourceSansBold
    btn.TextSize = 14
    btn.Parent = mainFrame

    local c = Instance.new("UICorner")
    c.CornerRadius = UDim.new(0, 6)
    c.Parent = btn
    return btn
end

local espButton    = createButton("ESP",        UDim2.new(0, 20,  0, 45))
local bhopButton   = createButton("BHOP",       UDim2.new(0, 20,  0, 95))
local speedButton  = createButton("FAST SPEED", UDim2.new(0, 20,  0, 145))
local flyButton    = createButton("FLY",        UDim2.new(0, 190, 0, 45))
local noclipButton = createButton("NO CLIP",    UDim2.new(0, 190, 0, 95))

local function toggleVisual(button, state, name)
    button.Text = name .. (state and ": ON" or ": OFF")
    local color = state and Color3.fromRGB(50, 180, 50) or Color3.fromRGB(180, 50, 50)
    TweenService:Create(button, TweenInfo.new(0.2), {BackgroundColor3 = color}):Play()
end

-- =========================================================
-- 2. ESP
-- =========================================================
local function createHighlight(char)
    if not char or not char.Parent then return end
    local old = char:FindFirstChild("BS_ESP")
    if old then old:Destroy() end

    local hl = Instance.new("Highlight")
    hl.Name = "BS_ESP"
    hl.FillColor = Color3.fromRGB(255, 0, 0)
    hl.FillTransparency = 0.4
    hl.OutlineColor = Color3.fromRGB(255, 255, 255)
    hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
    hl.Enabled = espEnabled
    hl.Parent = char
    return hl
end

local function monitorPlayer(player)
    if player == localPlayer then return end

    player.CharacterAdded:Connect(function(char)
        task.wait(0.2)
        activeHighlights[player] = createHighlight(char)
    end)

    if player.Character then
        activeHighlights[player] = createHighlight(player.Character)
    end
end

for _, p in pairs(Players:GetPlayers()) do monitorPlayer(p) end
Players.PlayerAdded:Connect(monitorPlayer)

-- =========================================================
-- 3. FLY (CFrame-стиль — работает там, где физика заблокирована)
-- =========================================================
local function stopFly()
    if flyConnection then
        flyConnection:Disconnect()
        flyConnection = nil
    end
    -- Возвращаем управление персонажем
    local char = localPlayer.Character
    if char then
        local hum = char:FindFirstChildOfClass("Humanoid")
        if hum then
            hum.PlatformStand = false
            pcall(function() hum:ChangeState(Enum.HumanoidStateType.GettingUp) end)
        end
    end
end

local function startFly()
    if flyConnection then flyConnection:Disconnect() end

    local char = localPlayer.Character
    if char then
        local hum = char:FindFirstChildOfClass("Humanoid")
        if hum then hum.PlatformStand = true end
    end

    flyConnection = RunService.RenderStepped:Connect(function()
        if not flyEnabled then return end
        local char = localPlayer.Character
        if not char then return end
        local root = char:FindFirstChild("HumanoidRootPart")
        if not root then return end

        local dir = Vector3.zero
        if UserInputService:IsKeyDown(Enum.KeyCode.W) then dir += camera.CFrame.LookVector end
        if UserInputService:IsKeyDown(Enum.KeyCode.S) then dir -= camera.CFrame.LookVector end
        if UserInputService:IsKeyDown(Enum.KeyCode.A) then dir -= camera.CFrame.RightVector end
        if UserInputService:IsKeyDown(Enum.KeyCode.D) then dir += camera.CFrame.RightVector end
        if UserInputService:IsKeyDown(Enum.KeyCode.Space) then dir += Vector3.yAxis end
        if UserInputService:IsKeyDown(Enum.KeyCode.LeftShift) then dir -= Vector3.yAxis end

        if dir.Magnitude > 0 then
            root.CFrame = root.CFrame + dir.Unit * (flySpeed / 60)
        end
    end)
end

-- =========================================================
-- 4. NOCLIP (CFrame-стиль — двигаемся сквозь стены телепортом)
-- =========================================================
local function stopNoclip()
    if noclipConnection then
        noclipConnection:Disconnect()
        noclipConnection = nil
    end
    for part in pairs(savedCollisions) do
        if part and part.Parent then
            pcall(function() part.CanCollide = true end)
        end
    end
    savedCollisions = {}
end

local function startNoclip()
    if noclipConnection then noclipConnection:Disconnect() end

    noclipConnection = RunService.Stepped:Connect(function()
        if not noclipEnabled then return end
        local char = localPlayer.Character
        if not char then return end
        for _, part in pairs(char:GetDescendants()) do
            if part:IsA("BasePart") and part.CanCollide then
                savedCollisions[part] = true
                part.CanCollide = false
            end
        end
    end)
end

-- =========================================================
-- 5. ГЛАВНЫЙ ЦИКЛ (SPEED + BHOP)
-- =========================================================
RunService.RenderStepped:Connect(function()
    local char = localPlayer.Character
    if not char then return end
    local hum = char:FindFirstChildOfClass("Humanoid")
    local root = char:FindFirstChild("HumanoidRootPart")
    if not hum or not root or hum.Health <= 0 then return end

    -- FAST SPEED
    if speedEnabled and not flyEnabled then
        if hum.WalkSpeed ~= walkSpeedValue then
            hum.WalkSpeed = walkSpeedValue
        end
    elseif not speedEnabled and not flyEnabled then
        if hum.WalkSpeed ~= 16 then
            hum.WalkSpeed = 16
        end
    end

    -- BHOP
    if bhopEnabled and not flyEnabled and UserInputService:IsKeyDown(Enum.KeyCode.Space) then
        if hum.FloorMaterial ~= Enum.Material.Air then
            root.Velocity = Vector3.new(root.Velocity.X, bhopPower, root.Velocity.Z)
        end
    end
end)

-- =========================================================
-- 6. КНОПКИ
-- =========================================================
espButton.MouseButton1Click:Connect(function()
    espEnabled = not espEnabled
    toggleVisual(espButton, espEnabled, "ESP")
    for _, hl in pairs(activeHighlights) do
        if hl and hl.Parent then hl.Enabled = espEnabled end
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
    if flyEnabled then
        startFly()
    else
        stopFly()
    end
end)

noclipButton.MouseButton1Click:Connect(function()
    noclipEnabled = not noclipEnabled
    toggleVisual(noclipButton, noclipEnabled, "NO CLIP")
    if noclipEnabled then
        startNoclip()
    else
        stopNoclip()
    end
end)
