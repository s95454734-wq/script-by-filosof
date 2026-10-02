-- Blox Strike Utility | Xeno Edition | v3ввы
-- ESP, BHOP, SPEED, FLY (CFrame), NOCLIP (CFrame), WALLBANG, NO RECOIL

local Players          = game:GetService("Players")
local CoreGui          = game:GetService("CoreGui")
local TweenService     = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local RunService       = game:GetService("RunService")
local Workspace        = game:GetService("Workspace")

local localPlayer = Players.LocalPlayer
local camera      = workspace.CurrentCamera

-- ============ СОСТОЯНИЯ ============
local espEnabled    = false
local bhopEnabled   = false
local flyEnabled    = false
local noclipEnabled = false
local speedEnabled  = false
local wallbangEnabled = false
local norecoilEnabled = false

local flySpeed        = 60
local walkSpeedValue  = 22
local bhopPower       = 45

-- ============ ХРАНИЛИЩА ============
local activeHighlights = {}
local noclipConnection = nil
local savedCollisions  = {}
local flyConnection    = nil
local originalRaycast  = nil
local originalFindPart = nil

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

-- Панель стала выше (6 кнопок → 3 ряда)
local mainFrame = Instance.new("Frame")
mainFrame.Size = UDim2.new(0, 360, 0, 250)
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
    btn.TextSize = 13
    btn.Parent = mainFrame

    local c = Instance.new("UICorner")
    c.CornerRadius = UDim.new(0, 6)
    c.Parent = btn
    return btn
end

local espButton      = createButton("ESP",        UDim2.new(0, 20,  0, 45))
local bhopButton     = createButton("BHOP",       UDim2.new(0, 20,  0, 90))
local speedButton    = createButton("FAST SPEED", UDim2.new(0, 20,  0, 135))
local flyButton      = createButton("FLY",        UDim2.new(0, 190, 0, 45))
local noclipButton   = createButton("NO CLIP",    UDim2.new(0, 190, 0, 90))
local wallbangButton = createButton("WALLBANG",   UDim2.new(0, 20,  0, 180))
local norecoilButton = createButton("NO RECOIL",  UDim2.new(0, 190, 0, 135))
local hitboxButton   = createButton("HITBOX",     UDim2.new(0, 190, 0, 180)) -- бонус: увеличение хитбокса

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
-- 3. FLY (CFrame)
-- =========================================================
local function stopFly()
    if flyConnection then flyConnection:Disconnect() flyConnection = nil end
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
-- 4. NOCLIP
-- =========================================================
local function stopNoclip()
    if noclipConnection then noclipConnection:Disconnect() noclipConnection = nil end
    for part in pairs(savedCollisions) do
        if part and part.Parent then pcall(function() part.CanCollide = true end) end
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
-- 5. WALLBANG (прострел через стены)
-- Подменяем Workspace:Raycast и Workspace:FindPartOnRay*, чтобы они
-- игнорировали всё, кроме персонажей игроков.
-- =========================================================
local wallbangConnection = nil

local function isPlayerCharacter(part)
    if not part then return false end
    local model = part:FindFirstAncestorOfClass("Model")
    if not model then return false end
    local hum = model:FindFirstChildOfClass("Humanoid")
    if not hum then return false end
    -- Проверяем, что это чей-то персонаж
    for _, plr in pairs(Players:GetPlayers()) do
        if plr.Character == model then return true end
    end
    return false
end

local function startWallbang()
    if wallbangConnection then wallbangConnection:Disconnect() end

    -- Хукаем Workspace.Raycast
    local mt = getrawmetatable and getrawmetatable(game) or getmetatable(game)
    if mt and setreadonly then pcall(setreadonly, mt, false) end

    if mt and mt.__namecall then
        local oldNamecall = mt.__namecall
        mt.__namecall = newcclosure(function(self, ...)
            local method = getnamecallmethod and getnamecallmethod() or ""
            if wallbangEnabled and self == Workspace and (method == "Raycast" or method == "FindPartOnRay" or method == "FindPartOnRayWithIgnoreList" or method == "FindPartOnRayWithWhitelist") then
                -- Подменяем фильтр, чтобы игнорировались все части, кроме персонажей
                local args = {...}
                if method == "Raycast" then
                    -- args = (origin, direction, RaycastParams)
                    local params = args[3]
                    if typeof(params) == "RaycastParams" then
                        local newFilter = {}
                        for _, plr in pairs(Players:GetPlayers()) do
                            if plr.Character then
                                table.insert(newFilter, plr.Character)
                            end
                        end
                        params.FilterDescendantsInstances = newFilter
                        params.FilterType = Enum.RaycastFilterType.Include
                    end
                elseif method == "FindPartOnRayWithIgnoreList" then
                    -- args = (ray, ignoreList, ...)
                    local ignoreList = args[2]
                    if typeof(ignoreList) == "table" then
                        table.clear(ignoreList)
                        for _, plr in pairs(Players:GetPlayers()) do
                            if plr.Character then
                                table.insert(ignoreList, plr.Character)
                            end
                        end
                    end
                end
            end
            return oldNamecall(self, ...)
        end)
    end

    wallbangConnection = true
end

local function stopWallbang()
    -- Хук остаётся, но флаг wallbangEnabled=false отключает его влияние
    wallbangConnection = nil
end

-- =========================================================
-- 6. NO RECOIL (анти-отдача)
-- Перехватываем изменения CameraShake и подменяем recoil-параметры оружия
-- =========================================================
local norecoilConnection = nil

local function startNorecoil()
    if norecoilConnection then norecoilConnection:Disconnect() end

    norecoilConnection = RunService.RenderStepped:Connect(function()
        if not norecoilEnabled then return end
        -- Гасим тряску камеры
        pcall(function()
            camera.CFrame = camera.CFrame
        end)
    end)

    -- Периодически чистим recoil у активного оружия
    task.spawn(function()
        while norecoilEnabled do
            task.wait(0.1)
            local char = localPlayer.Character
            if char then
                local tool = char:FindFirstChildOfClass("Tool")
                if tool then
                    for _, obj in pairs(tool:GetDescendants()) do
                        -- Сбрасываем типичные свойства отдачи
                        pcall(function()
                            if obj:IsA("NumberValue") then
                                if obj.Name:lower():find("recoil") or obj.Name:lower():find("spread") or obj.Name:lower():find("kick") then
                                    obj.Value = 0
                                end
                            end
                            if obj:IsA("Vector3Value") then
                                if obj.Name:lower():find("recoil") or obj.Name:lower():find("spread") then
                                    obj.Value = Vector3.zero
                                end
                            end
                        end)
                    end
                end
            end

            -- Гасим CameraShake глобально
            pcall(function()
                for _, obj in pairs(camera:GetChildren()) do
                    if obj:IsA("CameraShake") or obj.Name:lower():find("shake") then
                        obj:Destroy()
                    end
                end
                if camera:FindFirstChild("CameraShake") then
                    camera.CameraShake:Destroy()
                end
            end)
        end
    end)
end

local function stopNorecoil()
    if norecoilConnection then
        norecoilConnection:Disconnect()
        norecoilConnection = nil
    end
end

-- =========================================================
-- 7. HITBOX (бонус — увеличение хитбокса игроков)
-- =========================================================
local hitboxEnabled = false
local originalSizes = {}

local function applyHitbox()
    for _, plr in pairs(Players:GetPlayers()) do
        if plr ~= localPlayer and plr.Character then
            for _, part in pairs(plr.Character:GetDescendants()) do
                if part:IsA("BasePart") and part.Name ~= "HumanoidRootPart" then
                    if not originalSizes[part] then
                        originalSizes[part] = part.Size
                    end
                    part.Size = originalSizes[part] * 2
                    part.Transparency = math.min(part.Transparency, 0.5)
                end
            end
        end
    end
end

local function restoreHitbox()
    for part, size in pairs(originalSizes) do
        if part and part.Parent then
            pcall(function() part.Size = size end)
        end
    end
    originalSizes = {}
end

-- =========================================================
-- 8. ГЛАВНЫЙ ЦИКЛ (SPEED + BHOP)
-- =========================================================
RunService.RenderStepped:Connect(function()
    local char = localPlayer.Character
    if not char then return end
    local hum = char:FindFirstChildOfClass("Humanoid")
    local root = char:FindFirstChild("HumanoidRootPart")
    if not hum or not root or hum.Health <= 0 then return end

    if speedEnabled and not flyEnabled then
        if hum.WalkSpeed ~= walkSpeedValue then hum.WalkSpeed = walkSpeedValue end
    elseif not speedEnabled and not flyEnabled then
        if hum.WalkSpeed ~= 16 then hum.WalkSpeed = 16 end
    end

    if bhopEnabled and not flyEnabled and UserInputService:IsKeyDown(Enum.KeyCode.Space) then
        if hum.FloorMaterial ~= Enum.Material.Air then
            root.Velocity = Vector3.new(root.Velocity.X, bhopPower, root.Velocity.Z)
        end
    end

    if hitboxEnabled then applyHitbox() end
end)

-- =========================================================
-- 9. КНОПКИ
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
    if flyEnabled then startFly() else stopFly() end
end)

noclipButton.MouseButton1Click:Connect(function()
    noclipEnabled = not noclipEnabled
    toggleVisual(noclipButton, noclipEnabled, "NO CLIP")
    if noclipEnabled then startNoclip() else stopNoclip() end
end)

wallbangButton.MouseButton1Click:Connect(function()
    wallbangEnabled = not wallbangEnabled
    toggleVisual(wallbangButton, wallbangEnabled, "WALLBANG")
    if wallbangEnabled then startWallbang() else stopWallbang() end
end)

norecoilButton.MouseButton1Click:Connect(function()
    norecoilEnabled = not norecoilEnabled
    toggleVisual(norecoilButton, norecoilEnabled, "NO RECOIL")
    if norecoilEnabled then startNorecoil() else stopNorecoil() end
end)

hitboxButton.MouseButton1Click:Connect(function()
    hitboxEnabled = not hitboxEnabled
    toggleVisual(hitboxButton, hitboxEnabled, "HITBOX")
    if not hitboxEnabled then restoreHitbox() end
end)
