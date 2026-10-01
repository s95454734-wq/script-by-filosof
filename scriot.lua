-- Сервисы Roblox
local Players = game:GetService("Players")
local CoreGui = game:GetService("CoreGui")
local TweenService = game:GetService("TweenService")

local localPlayer = Players.LocalPlayer

-- Переменная состояния ESP
local espEnabled = false
local activeHighlights = {}

-- 1. СОЗДАНИЕ ИНТЕРФЕЙСА (GUI)
local screenGui = Instance.new("ScreenGui")
screenGui.Name = "CustomMenuGUI"
screenGui.ResetOnSpawn = false

-- Пытаемся спрятать GUI в CoreGui, чтобы он не удалялся, либо в PlayerGui
local success, err = pcall(function()
    screenGui.Parent = CoreGui
end)
if not success then
    screenGui.Parent = localPlayer:WaitForChild("PlayerGui")
end

-- Главная панель меню
local mainFrame = Instance.new("Frame")
mainFrame.Size = UDim2.new(0, 200, 0, 100)
mainFrame.Position = UDim2.new(0.1, 0, 0.1, 0)
mainFrame.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
mainFrame.BorderSizePixel = 0
mainFrame.Active = true
mainFrame.Draggable = true -- Позволяет перетаскивать меню мышкой
mainFrame.Parent = screenGui

-- Скругление углов панели
local frameCorner = Instance.new("UICorner")
frameCorner.CornerRadius = UDim.new(0, 8)
frameCorner.Parent = mainFrame

-- Сервис для отслеживания нажатий клавиатуры
local UserInputService = game:GetService("UserInputService")

-- Настройка клавиши (по умолчанию Insert)
local TOGGLE_KEY = Enum.KeyCode.Insert 

UserInputService.InputBegan:Connect(function(input, gameProcessed)
    -- Если игрок пишет в чат, скрипт не должен срабатывать
    if gameProcessed then return end
    
    -- Проверяем нажатие нужной клавиши
    if input.KeyCode == TOGGLE_KEY then
        mainFrame.Visible = not mainFrame.Visible
    end
end)

-- Кнопка переключения ESP
local espButton = Instance.new("TextButton")
espButton.Size = UDim2.new(0, 160, 0, 40)
espButton.Position = UDim2.new(0.5, -80, 0.5, -20)
espButton.BackgroundColor3 = Color3.fromRGB(180, 50, 50) -- Красный (выключено)
espButton.Text = "ESP: OFF"
espButton.TextColor3 = Color3.fromRGB(255, 255, 255)
espButton.Font = Enum.Font.SourceSansBold
espButton.TextSize = 18
espButton.Parent = mainFrame

local buttonCorner = Instance.new("UICorner")
buttonCorner.CornerRadius = UDim.new(0, 6)
buttonCorner.Parent = espButton


-- 2. ФУНКЦИЯ ESP (ПОДСВЕТКА)
local function applyESP(player)
    if player == localPlayer then return end
    
    local function onCharacterAdded(character)
        if not espEnabled then return end
        
        -- Если подсветка уже есть, удаляем старую
        if character:FindFirstChild("ESPHighlight") then
            character.ESPHighlight:Destroy()
        end
        
        -- Создаем объект Highlight
        local highlight = Instance.new("Highlight")
        highlight.Name = "ESPHighlight"
        highlight.FillColor = Color3.fromRGB(255, 0, 0) -- Цвет заливки (Красный)
        highlight.FillTransparency = 0.5 -- Прозрачность заливки
        highlight.OutlineColor = Color3.fromRGB(255, 255, 255) -- Цвет обводки (Белый)
        highlight.OutlineTransparency = 0 -- Прозрачность обводки
        highlight.Adornee = character
        highlight.Parent = character
        
        activeHighlights[player] = highlight
    end
    
    if player.Character then
        onCharacterAdded(player.Character)
    end
    player.CharacterAdded:Connect(onCharacterAdded)
end

-- Функция удаления подсветки
local function removeESP()
    for player, highlight in pairs(activeHighlights) do
        if highlight and highlight.Parent then
            highlight:Destroy()
        end
    end
    activeHighlights = {}
    
    -- Дополнительная очистка по всей игре
    for _, v in pairs(workspace:GetDescendants()) do
        if v:IsA("Highlight") and v.Name == "ESPHighlight" then
            v:Destroy()
        end
    end
end


-- 3. ОБРАБОТКА НАЖАТИЯ КНОПКИ
espButton.MouseButton1Click:Connect(function()
    espEnabled = not espEnabled
    
    if espEnabled then
        -- Включаем ESP
        espButton.Text = "ESP: ON"
        TweenService:Create(espButton, TweenInfo.new(0.3), {BackgroundColor3 = Color3.fromRGB(50, 180, 50)}):Play() -- Зеленый
        
        -- Включаем для текущих игроков
        for _, player in pairs(Players:GetPlayers()) do
            applyESP(player)
        end
        
        -- Следим за новыми зашедшими игроками
        Players.PlayerAdded:Connect(applyESP)
    else
        -- Выключаем ESP
        espButton.Text = "ESP: OFF"
        TweenService:Create(espButton, TweenInfo.new(0.3), {BackgroundColor3 = Color3.fromRGB(180, 50, 50)}):Play() -- Красный
        removeESP()
    end
end)
