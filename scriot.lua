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
local aimbotEnabled = false
local triggerEnabled = false
local recoilDisabled = false
local wallbangEnabled = false

local activeHighlights = {}
local AIM_SMOOTHNESS = 0.15

-- 1. СОЗДАНИЕ ИНТЕРФЕЙСА (GUI)
local screenGui = Instance.new("ScreenGui")
screenGui.Name = "PremiumMenuGUI"
screenGui.ResetOnSpawn = false

local success, err = pcall(function() screenGui.Parent = CoreGui end)
if not success then screenGui.Parent = localPlayer:WaitForChild("PlayerGui") end

-- Главная панель меню (расширена до 3 столбцов: ширина 530)
local mainFrame = Instance.new("Frame")
mainFrame.Size = UDim2.new(0, 530, 0, 150)
mainFrame.Position = UDim2.new(0.1, 0, 0.1, 0)
mainFrame.BackgroundColor3 = Color3.fromRGB(25, 25, 25)
mainFrame.BorderSizePixel = 0
mainFrame.Active = true
mainFrame.Draggable = true
mainFrame.Parent = screenGui

local frameCorner = Instance.new("UICorner")
frameCorner.CornerRadius = UDim.new(0, 8)
frameCorner.Parent = mainFrame

-- Заголовок меню
local titleLabel = Instance.new("TextLabel")
titleLabel.Size = UDim2.new(1, 0, 0, 30)
titleLabel.BackgroundTransparency = 1
titleLabel.Text = "MultiHack Premium Menu | Insert to Hide"
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

-- Функция создания кнопок
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

-- Столбец 1
local espButton = createButton("ESP", UDim2.new(0, 20, 0, 45))
local bhopButton = createButton("BHOP", UDim2.new(0, 20, 0, 95))
-- Столбец 2
local aimButton = createButton("AIM ASSIST", UDim2.new(0, 190, 0, 45))
local triggerButton = createButton("TRIGGERBOT", UDim2.new(0, 190, 0, 95))
-- Столбец 3 (Новые функции)
local recoilButton = createButton("ANTI RECOIL", UDim2.new(0, 360, 0, 45))
local wallbangButton = createButton("WALLBANG", UDim2.new(0, 360, 0, 95))

local function toggleVisual(button, state, name)
    button.Text = name .. (state and ": ON" or ": OFF")
    local color = state and Color3.fromRGB(50, 180, 50) or Color3.fromRGB(180, 50, 50)
    TweenService:Create(button, TweenInfo.new(0.2), {BackgroundColor3 = color}):Play()
end

-- [ЗДЕСЬ ОСТАЕТСЯ СТАРЫЙ КОД ЛОГИКИ ДЛЯ ESP, BHOP, AIM И TRIGGERBOTИз ПРОШЛОГО ШАГА]

-- 2. ОБРАБОТКА НАЖАТИЙ НОВЫХ КНОПОК
recoilButton.MouseButton1Click:Connect(function()
    recoilDisabled = not recoilDisabled
    toggleVisual(recoilButton, recoilDisabled, "ANTI RECOIL")
    
    if recoilDisabled then
        print("Анти-отдача активирована (требуется хук скрипта оружия)")
        -- Сюда вставляется код хука под конкретную игру
    end
end)

wallbangButton.MouseButton1Click:Connect(function()
    wallbangEnabled = not wallbangEnabled
    toggleVisual(wallbangButton, wallbangEnabled, "WALLBANG")
    
    if wallbangEnabled then
        print("Прострел стен активирован (требуется обход Raycast игры)")
        -- Сюда вставляется код модификации лучей под конкретную игру
    end
end)
