-- Сервисы Roblox
local Players = game:GetService("Players")
local CoreGui = game:GetService("CoreGui")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local VirtualInputManager = game:GetService("VirtualInputManager") -- Сервис для симуляции кликов

local localPlayer = Players.LocalPlayer
local camera = workspace.CurrentCamera

-- Состояния функций
local espEnabled = false
local bhopEnabled = false
local aimbotEnabled = false
local triggerEnabled = false

local activeHighlights = {}

-- Настройки (можно менять под себя)
local AIM_SMOOTHNESS = 0.12 -- Плавность (меньше = быстрее)
local TRIGGER_DELAY = 0.05  -- Задержка выстрела

-- 1. СОЗДАНИЕ ИНТЕРФЕЙСА (GUI)
local screenGui = Instance.new("ScreenGui")
screenGui.Name = "BloxStrikeGUI"
screenGui.ResetOnSpawn = false

local success, err = pcall(function() screenGui.Parent = CoreGui end)
if not success then screenGui.Parent = localPlayer:WaitForChild("PlayerGui") end

local mainFrame = Instance.new("Frame")
mainFrame.Size = UDim2.new(0, 360, 0, 150)
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
titleLabel.Text = "Blox Strike Legit | Insert to Hide"
titleLabel.TextColor3 = Color3.fromRGB(200, 200, 200)
titleLabel.Font = Enum.Font.SourceSansBold
titleLabel.TextSize = 16
titleLabel.Parent = mainFrame

-- Кнопка скрытия меню (Insert)
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
    btn.TextSize = 15
    btn.Parent = mainFrame
    
    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 6)
    corner.Parent = btn
    return btn
end

-- Кнопки управления
local espButton = createButton("ESP", UDim2.new(0, 20, 0, 45))
local bhopButton = createButton("BHOP", UDim2.new(0, 20, 0, 95))
local aimButton = createButton("AIM ASSIST", UDim2.new(0, 190, 0, 45))
local triggerButton = createButton("TRIGGERBOT", UDim2.new(0, 190, 0, 95))

local function toggleVisual(button, state, name)
    button.Text = name .. (state and ": ON" or ": OFF")
    local color = state and Color3.fromRGB(50, 180, 50) or Color3.fromRGB(180, 50, 50)
    TweenService:Create(button, TweenInfo.new(0.2), {BackgroundColor3 = color}):Play()
end

-- 2. ПОИСК ЦЕЛИДЛЯ АИМА
local function getClosestPlayer()
    local closestPlayer = nil
    local shortestDistance = math.huge
    local mousePos = UserInputService:GetMouseLocation()

    for _, player in pairs(Players:GetPlayers()) do
        if player ~= localPlayer and player.Character then
            -- Ищем голову или верхнюю часть торса (на случай кастомных хитбоксов)
            local targetPart = player.Character:FindFirstChild("Head") or player.Character:FindFirstChild("HumanoidRootPart")
            local humanoid = player.Character:FindFirstChildOfClass("Humanoid")
            
            if targetPart and humanoid and humanoid.Health > 0 then
                local pos, onScreen = camera:WorldToViewportPoint(targetPart.Position)
                if onScreen then
                    local distance = (Vector2.new(pos.X, pos.Y) - mousePos).Magnitude
                    if distance < shortestDistance then
                        closestPlayer = player
                        shortestDistance = distance
                    end
                end
            end
        end
    end
    return closestPlayer
end

-- 3. ЛОГИКА ESP
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

-- 4. ЕДИНЫЙ ОБНОВЛЕННЫЙ ЦИКЛ (ОБРАБОТКА КАДРОВ)
RunService.RenderStepped:Connect(function()
    local character = localPlayer.Character
    if not character then return end
    local humanoid = character:FindFirstChildOfClass("Humanoid")
    local rootPart = character:FindFirstChild("HumanoidRootPart")
    if not humanoid or not rootPart or humanoid.Health <= 0 then return end

    -- НАДЕЖНЫЙ BHOP (Прямое изменение импульса прыжка)
    if bhopEnabled and UserInputService:IsKeyDown(Enum.KeyCode.Space) then
        if humanoid.FloorMaterial ~= Enum.Material.Air then
            rootPart.Velocity = Vector3.new(rootPart.Velocity.X, 45, rootPart.Velocity.Z)
        end
    end

    -- AIM ASSIST (Теперь наводит, когда зажата ПРАВАЯ кнопка мыши)
    if aimbotEnabled and UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton2) then
        local target = getClosestPlayer()
        if target and target.Character then
            local aimPart = target.Character:FindFirstChild("Head") or target.Character:FindFirstChild("HumanoidRootPart")
            if aimPart then
                camera.CFrame = camera.CFrame:Lerp(CFrame.new(camera.CFrame.Position, aimPart.Position), AIM_SMOOTHNESS)
            end
        end
    end

    -- ИСПРАВЛЕННЫЙ TRIGGERBOT (Использует симуляцию ввода клика мыши)
    if triggerEnabled then
        local mousePos = UserInputService:GetMouseLocation()
        local unitRay = camera:ScreenPointToRay(mousePos.X, mousePos.Y)
        
        local raycastParams = RaycastParams.new()
        raycastParams.FilterType = Enum.RaycastFilterType.Exclude
        raycastParams.FilterDescendantsInstances = {character, camera}
        
        local result = workspace:Raycast(unitRay.Origin, unitRay.Direction * 2000, raycastParams)
        if result and result.Instance then
            local hitModel = result.Instance:FindFirstAncestorOfClass("Model")
            if hitModel and hitModel:FindFirstChildOfClass("Humanoid") and hitModel ~= character then
                local targetPlayer = Players:GetPlayerFromCharacter(hitModel)
                if targetPlayer and targetPlayer ~= localPlayer then
                    -- Симулируем реальное нажатие левой кнопки мыши (MouseButton1)
                    VirtualInputManager:SendMouseButtonEvent(mousePos.X, mousePos.Y, 0, true, game, 0)
                    task.wait(TRIGGER_DELAY)
                    VirtualInputManager:SendMouseButtonEvent(mousePos.X, mousePos.Y, 0, false, game, 0)
                end
            end
        end
    end
end)

-- 5. НАЖАТИЯ КНОПОК
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

aimButton.MouseButton1Click:Connect(function()
    aimbotEnabled = not aimbotEnabled
    toggleVisual(aimButton, aimbotEnabled, "AIM ASSIST")
end)

triggerButton.MouseButton1Click:Connect(function()
    triggerEnabled = not triggerEnabled
    toggleVisual(triggerButton, triggerEnabled, "TRIGGERBOT")
end)
