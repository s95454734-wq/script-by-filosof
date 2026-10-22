--[========================================================================[
  FILOSOF | Kit PvP Tester (ClickGUI + AutoCrystal/Anchor + AutoTotem)
  Игра: Kit PVP! [BUG FIXES!] [SEASON 1]  (PlaceId: 136077426077314)

  НАЗНАЧЕНИЕ: тест на приватных серверах командой тестеров / проверка
  дыр античита своей игры.

  УПРАВЛЕНИЕ:
    RightShift / Insert  - открыть / закрыть ClickGUI
    Кнопка [F] на экране - открыть GUI, когда оно закрыто (для мобильных)

  ПОДГОТОВКА (важно):
    Положи в хотбар / рюкзак: Respawn Anchor, Glowstone, Obsidian,
    End Crystal, Totem of Undying и оружие (меч). Скрипт сам ищет предметы:
      1) как Roblox Tool в Backpack/Character;
      2) как слоты кастомного хотбара в PlayerGui (выбор цифрами 1-9).
    Если автоопределение слота не сработает - укажи номера вручную в
    CONFIG.ManualHotbarSlots ниже (например Anchor = 2, Glowstone = 3 ...)
    или нажми в GUI "Дамп предметов (F9)" и пришли вывод из консоли -
    по нему подгоним имена предметов/ремотов точно под игру.

  Рестарт скрипта: просто запусти файл ещё раз - старая копия остановится.
--]========================================================================]

--// Остановка предыдущей копии ------------------------------------------------
local RUN_ID = ((_G.__FILOSOF_RUN_ID or 0) + 1)
_G.__FILOSOF_RUN_ID = RUN_ID
local function isRunning()
	return _G.__FILOSOF_RUN_ID == RUN_ID
end

--// Конфиг --------------------------------------------------------------------
local CONFIG = {
	ExpectedPlaceId = 136077426077314,

	-- AutoCrystal / Anchor
	TargetRange   = 16,    -- радиус поиска цели (стады)
	PlaceRange    = 7.5,   -- ставим/взрываем только если ты не дальше от цели
	CycleDelay    = 0.30,  -- пауза между полными циклами (якорь+кристалл)
	StepDelay     = 0.12,  -- пауза между шагами внутри цикла
	ExplodeOffset = 1.4,   -- точка взрыва: у ног цели + смещение ОТ тебя за цель
	AnchorCharges = 1,     -- сколько раз заряжать якорь светокамнем (1..4)

	-- AutoTotem
	InventoryKey  = Enum.KeyCode.E, -- открыть инвентарь
	SwapHandsKey  = Enum.KeyCode.F, -- свап рука <-> оффхенд (как в Minecraft)
	TotemHPPercent = 60,            -- если "Тотем всегда" выкл - свапать ниже этого HP

	-- Ручные номера хотбара (0 = автоопределение). Заполни, если авто не найдёт.
	ManualHotbarSlots = {
		Anchor = 0, Glowstone = 0, Obsidian = 0,
		Crystal = 0, Totem = 0, Weapon = 0,
	},

	-- Имена предметов (сравнение без пробелов/регистра, по вхождению подстроки)
	ItemPatterns = {
		Anchor    = { "respawnanchor", "anchor" },
		Glowstone = { "glowstone" },
		Obsidian  = { "obsidian" },
		Crystal   = { "endcrystal", "crystal" },
		Totem     = { "totemofundying", "totem" },
		Weapon    = { "sword", "axe", "mace", "spear", "trident" },
	},
}

local STATE = {
	AutoCrystal = false,
	UseAnchors  = true,
	UseCrystals = true,
	AutoTotem   = false,
	TotemAlways = true,
	SafeMode    = true,
	ExtraMouseClick = false, -- доп. клик мыши поверх Tool:Activate()
	AimCamera   = true,
	FaceTarget  = true,

	GuiOpen = true,
	LastTotemAttempt = 0,
	OffhandText = "?",
}

--// Сервисы -------------------------------------------------------------------
local Players           = game:GetService("Players")
local RunService        = game:GetService("RunService")
local UserInputService  = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local VirtualInputManager = game:GetService("VirtualInputManager")

local LocalPlayer = Players.LocalPlayer

local DIGIT_KEYS = {
	Enum.KeyCode.One, Enum.KeyCode.Two, Enum.KeyCode.Three,
	Enum.KeyCode.Four, Enum.KeyCode.Five, Enum.KeyCode.Six,
	Enum.KeyCode.Seven, Enum.KeyCode.Eight, Enum.KeyCode.Nine,
}
local DIGIT_VK = { 0x31, 0x32, 0x33, 0x34, 0x35, 0x36, 0x37, 0x38, 0x39 }

--// Лог / статус (GUI подключается ниже) --------------------------------------
local UI = {}
local LogLines = {}

local function Log(text)
	text = tostring(text)
	print("[FILOSOF] " .. text)
	table.insert(LogLines, text)
	while #LogLines > 5 do table.remove(LogLines, 1) end
	if UI.LogLabel then
		UI.LogLabel.Text = table.concat(LogLines, "\n")
	end
end

local ThrottleMap = {}
local function LogThrottled(key, text, interval)
	local now = os.clock()
	if (ThrottleMap[key] or 0) + (interval or 3) <= now then
		ThrottleMap[key] = now
		Log(text)
	end
end

local function SetStatus(text)
	if UI.StatusLabel then UI.StatusLabel.Text = "Статус: " .. tostring(text) end
end

--// Утилиты имён / предметов ----------------------------------------------------
local function normalize(s)
	if type(s) ~= "string" then return "" end
	s = string.lower(s)
	s = string.gsub(s, "[%s_%-%.]", "")
	return s
end

local function textMatchesKind(text, kind)
	local patterns = CONFIG.ItemPatterns[kind]
	if not patterns then return false end
	local n = normalize(text)
	if n == "" then return false end
	for _, p in ipairs(patterns) do
		if string.find(n, p, 1, true) then return true end
	end
	return false
end

-- Собираем всё, по чему можно опознать инстанс: имя, ToolTip, атрибуты, Value, Text
local function instanceBlob(inst)
	if not inst then return "" end
	local parts = { inst.Name }
	if inst:IsA("Tool") and inst.ToolTip ~= "" then
		table.insert(parts, inst.ToolTip)
	end
	pcall(function()
		for k, v in pairs(inst:GetAttributes()) do
			table.insert(parts, tostring(k))
			if type(v) == "string" then table.insert(parts, v) end
		end
	end)
	if inst:IsA("StringValue") then table.insert(parts, inst.Value) end
	if inst:IsA("ObjectValue") and inst.Value then table.insert(parts, inst.Value.Name) end
	if inst:IsA("TextLabel") or inst:IsA("TextButton") or inst:IsA("TextBox") then
		if inst.Text ~= "" then table.insert(parts, inst.Text) end
	end
	return table.concat(parts, " ")
end

local function instanceMatchesKind(inst, kind)
	return textMatchesKind(instanceBlob(inst), kind)
end

-- blob слота GUI вместе со всеми его потомками (подписи, Value-объекты, атрибуты)
local function guiSlotBlob(slot)
	local parts = { instanceBlob(slot) }
	for _, d in ipairs(slot:GetDescendants()) do
		local b = instanceBlob(d)
		if b ~= "" then table.insert(parts, b) end
	end
	return table.concat(parts, " ")
end

local function guiSlotMatchesKind(slot, kind)
	return textMatchesKind(guiSlotBlob(slot), kind)
end

--// Персонаж ------------------------------------------------------------------
local function getChar(player)
	return player and player.Character or nil
end
local function getHum(model)
	return model and model:FindFirstChildOfClass("Humanoid") or nil
end
local function getRoot(model)
	if not model then return nil end
	return model:FindFirstChild("HumanoidRootPart") or model:FindFirstChild("Torso") or model.PrimaryPart
end
local function myChar() return getChar(LocalPlayer) end
local function myHum() return getHum(myChar()) end
local function myRoot() return getRoot(myChar()) end

local function isAliveModel(model)
	local hum = getHum(model)
	local root = getRoot(model)
	return hum ~= nil and root ~= nil and hum.Health > 0
end

--// Tool-предметы (Backpack / Character) ---------------------------------------
local function findTool(kind)
	local char = myChar()
	if char then
		for _, c in ipairs(char:GetChildren()) do
			if c:IsA("Tool") and instanceMatchesKind(c, kind) then return c end
		end
	end
	local backpack = LocalPlayer:FindFirstChildOfClass("Backpack")
	if backpack then
		for _, c in ipairs(backpack:GetChildren()) do
			if c:IsA("Tool") and instanceMatchesKind(c, kind) then return c end
		end
	end
	return nil
end

local function getEquippedTool()
	local char = myChar()
	if not char then return nil end
	for _, c in ipairs(char:GetChildren()) do
		if c:IsA("Tool") then return c end
	end
	return nil
end

local function equipTool(tool)
	if not tool then return false end
	local char, hum = myChar(), myHum()
	if not char or not hum then return false end
	if tool.Parent == char then return true end
	pcall(function() hum:EquipTool(tool) end)
	local t0 = os.clock()
	while os.clock() - t0 < 0.4 and isRunning() do
		if tool.Parent == char then return true end
		task.wait(0.03)
	end
	return tool.Parent == char
end

--// Глобалы экзекьютора (mousemoveabs, mouse1click, firesignal, gethui...) -----
local function getGlobal(name)
	local ok, env = pcall(function() return getgenv() end)
	if ok and type(env) == "table" and env[name] ~= nil then return env[name] end
	local ok2, env2 = pcall(function() return getfenv() end)
	if ok2 and type(env2) == "table" and env2[name] ~= nil then return env2[name] end
	if _G and _G[name] ~= nil then return _G[name] end
	return nil
end

--// Ввод: клавиши и мышь ---------------------------------------------------------
local function sendKey(keyCode, vkCode)
	local ok = pcall(function()
		VirtualInputManager:SendKeyEvent(true, keyCode, false, game)
		task.wait(0.04)
		VirtualInputManager:SendKeyEvent(false, keyCode, false, game)
	end)
	if ok then return true end
	local keypress, keyrelease = getGlobal("keypress"), getGlobal("keyrelease")
	if keypress and vkCode then
		local ok2 = pcall(function()
			keypress(vkCode)
			task.wait(0.04)
			if keyrelease then keyrelease(vkCode) end
		end)
		return ok2
	end
	return false
end

local function pressDigit(n)
	if n and n >= 1 and n <= 9 then
		return sendKey(DIGIT_KEYS[n], DIGIT_VK[n])
	end
	return false
end

-- button: 0 = левая, 1 = правая
local function sendMouseButton(x, y, button, isDown)
	-- 1) экзекьюторные mouse1press/mouse2press и т.п.
	local pressName = (button == 0) and "mouse1press" or "mouse2press"
	local releaseName = (button == 0) and "mouse1release" or "mouse2release"
	local fn = getGlobal(isDown and pressName or releaseName)
	if fn then
		local mm = getGlobal("mousemoveabs")
		if mm then pcall(mm, x, y) end
		return pcall(fn)
	end
	if not isDown then
		-- для mouse*click отпускание отдельно не нужно
		local clickFn = getGlobal((button == 0) and "mouse1click" or "mouse2click")
		if clickFn then return true end
	end
	-- 2) VirtualInputManager
	local ok = pcall(function()
		VirtualInputManager:SendMouseButtonEvent(x, y, button, isDown, game, 1)
	end)
	if ok then return true end
	-- 3) VirtualUser
	local ok2 = pcall(function()
		local vu = game:GetService("VirtualUser")
		vu:CaptureController()
		if button == 0 then
			if isDown then vu:Button1Down(Vector2.new(x, y), workspace.CurrentCamera.CFrame)
			else vu:Button1Up(Vector2.new(x, y), workspace.CurrentCamera.CFrame) end
		else
			if isDown then vu:Button2Down(Vector2.new(x, y), workspace.CurrentCamera.CFrame)
			else vu:Button2Up(Vector2.new(x, y), workspace.CurrentCamera.CFrame) end
		end
	end)
	return ok2
end

local function clickMouseAt(x, y, button)
	-- полноценный клик одной функцией экзекьютора, если есть
	local clickFn = getGlobal((button == 0) and "mouse1click" or "mouse2click")
	local pressFn = getGlobal((button == 0) and "mouse1press" or "mouse2press")
	if clickFn and not pressFn then
		local mm = getGlobal("mousemoveabs")
		if mm then pcall(mm, x, y) end
		return pcall(clickFn)
	end
	sendMouseButton(x, y, button, true)
	task.wait(0.035)
	sendMouseButton(x, y, button, false)
	return true
end

local function worldToScreen(pos)
	local cam = workspace.CurrentCamera
	if not cam then return 0, 0, false end
	local v, onScreen = cam:WorldToViewportPoint(pos)
	return v.X, v.Y, onScreen
end

-- Навестись на мировую точку: камера + (опц.) разворот персонажа + курсор
local function aimAt(pos)
	local cam = workspace.CurrentCamera
	if STATE.AimCamera and cam then
		pcall(function()
			cam.CFrame = CFrame.lookAt(cam.CFrame.Position, pos)
		end)
	end
	if STATE.FaceTarget then
		local root = myRoot()
		if root then
			pcall(function()
				local p = root.Position
				root.CFrame = CFrame.lookAt(p, Vector3.new(pos.X, p.Y, pos.Z))
			end)
		end
	end
	local x, y, onScreen = worldToScreen(pos)
	local mm = getGlobal("mousemoveabs")
	if mm and onScreen then pcall(mm, x, y) end
	return x, y
end

local function clickAtWorld(pos, mode) -- mode: "Place"/"Interact" = ПКМ, "Hit" = ЛКМ
	local x, y = aimAt(pos)
	local button = (mode == "Hit") and 0 or 1
	return clickMouseAt(x, y, button)
end

-- Клик по GUI-объекту по его центру
local function clickGuiObject(obj)
	if not obj or not obj:IsA("GuiObject") then return false end
	local center = obj.AbsolutePosition + obj.AbsoluteSize / 2
	local ok = clickMouseAt(center.X, center.Y, 0)
	if not ok then
		local firesignal = getGlobal("firesignal")
		if firesignal and obj:IsA("GuiButton") then
			pcall(function() firesignal(obj.MouseButton1Click) end)
			pcall(function() firesignal(obj.Activated) end)
			return true
		end
	end
	return ok
end

-- Перетаскивание GUI: нажать на fromObj, отпустить на toObj
local function dragGuiObject(fromObj, toObj)
	if not fromObj or not toObj then return false end
	local a = fromObj.AbsolutePosition + fromObj.AbsoluteSize / 2
	local b = toObj.AbsolutePosition + toObj.AbsoluteSize / 2
	local mm = getGlobal("mousemoveabs")
	if mm then pcall(mm, a.X, a.Y) end
	pcall(function() VirtualInputManager:SendMouseMoveEvent(a.X, a.Y, game) end)
	sendMouseButton(a.X, a.Y, 0, true)
	task.wait(0.06)
	if mm then pcall(mm, b.X, b.Y) end
	pcall(function() VirtualInputManager:SendMouseMoveEvent(b.X, b.Y, game) end)
	task.wait(0.06)
	sendMouseButton(b.X, b.Y, 0, false)
	return true
end

--// Кастомные слоты GUI (хотбар / инвентарь / оффхенд) --------------------------
local function ancestorBlobHas(obj, word, depth)
	local cur = obj
	for _ = 1, (depth or 6) do
		if not cur then break end
		if string.find(normalize(cur.Name), word, 1, true) then return true end
		cur = cur.Parent
	end
	return false
end

local function isEffectivelyVisible(obj)
	local cur = obj
	while cur do
		if cur:IsA("GuiObject") and not cur.Visible then return false end
		if cur:IsA("ScreenGui") and not cur.Enabled then return false end
		if cur:IsA("LayerCollector") and not cur.Enabled then return false end
		cur = cur.Parent
	end
	return true
end

local function slotIndexFromObject(obj)
	-- атрибут Slot/Index/...
	local ok, attrs = pcall(function() return obj:GetAttributes() end)
	if ok and attrs then
		for k, v in pairs(attrs) do
			local nk = normalize(tostring(k))
			if type(v) == "number" and (string.find(nk, "slot", 1, true) or nk == "index") then
				return v
			end
		end
	end
	-- цифра в имени
	local digits = string.match(obj.Name, "(%d+)")
	if digits then return tonumber(digits) end
	-- LayoutOrder
	if obj:IsA("GuiObject") and obj.LayoutOrder ~= 0 and obj.LayoutOrder <= 45 then
		return obj.LayoutOrder
	end
	return nil
end

-- Возвращает список: { Obj, IsHotbar, IsInventory, IsOffhand, Index, Blob }
local function collectGuiSlots()
	local playerGui = LocalPlayer:FindFirstChildOfClass("PlayerGui")
	if not playerGui then return {} end
	local cam = workspace.CurrentCamera
	local viewY = cam and cam.ViewportSize.Y or 1080

	local raw = {}
	for _, d in ipairs(playerGui:GetDescendants()) do
		if d:IsA("GuiObject") then
			local n = normalize(d.Name)
			local isNamed = string.find(n, "slot", 1, true) or string.find(n, "cell", 1, true)
			local hasHotbarAncestor = ancestorBlobHas(d, "hotbar", 5)
			local size = d.AbsoluteSize
			local squareish = size.X >= 24 and size.X <= 160 and size.Y >= 24 and size.Y <= 160
				and math.abs(size.X - size.Y) <= 40
			local okClass = d:IsA("Frame") or d:IsA("ImageLabel") or d:IsA("ImageButton")
				or d:IsA("TextButton") or d:IsA("TextLabel")
			if isNamed or (hasHotbarAncestor and squareish and okClass) then
				table.insert(raw, d)
			end
		end
	end
	-- оставить только самые внешние слоты (без слота-предка)
	local inRaw = {}
	for _, o in ipairs(raw) do inRaw[o] = true end
	local slots = {}
	for _, o in ipairs(raw) do
		local p, nested = o.Parent, false
		while p do
			if inRaw[p] then nested = true break end
			p = p.Parent
		end
		if not nested then
			local isInventory = ancestorBlobHas(o, "inventory", 6) or ancestorBlobHas(o, "backpack", 6)
			local bottomStrip = (o.AbsolutePosition.Y > viewY - 210) and o.AbsoluteSize.X > 0
			table.insert(slots, {
				Obj = o,
				IsHotbar = ancestorBlobHas(o, "hotbar", 6) or (bottomStrip and not isInventory),
				IsInventory = isInventory,
				IsOffhand = ancestorBlobHas(o, "offhand", 3) or ancestorBlobHas(o, "lefthand", 3),
				Index = slotIndexFromObject(o),
				Blob = guiSlotBlob(o),
				Visible = isEffectivelyVisible(o),
			})
		end
	end
	-- индекс по порядку соседей под одним родителем, если не определён
	for _, s in ipairs(slots) do
		if not s.Index and s.IsHotbar then
			local siblings = {}
			for _, o in ipairs(slots) do
				if o.Obj.Parent == s.Obj.Parent then table.insert(siblings, o) end
			end
			table.sort(siblings, function(a, b)
				if math.abs(a.Obj.AbsolutePosition.Y - b.Obj.AbsolutePosition.Y) > 4 then
					return a.Obj.AbsolutePosition.Y < b.Obj.AbsolutePosition.Y
				end
				return a.Obj.AbsolutePosition.X < b.Obj.AbsolutePosition.X
			end)
			for i, o in ipairs(siblings) do
				if o == s and i <= 9 then s.Index = i end
			end
		end
	end
	return slots
end

local function findHotbarSlot(kind)
	for _, s in ipairs(collectGuiSlots()) do
		if s.IsHotbar and not s.IsOffhand and textMatchesKind(s.Blob, kind) then
			return s
		end
	end
	return nil
end

local function findAnySlot(kind)
	local bestInventory, bestHotbar = nil, nil
	for _, s in ipairs(collectGuiSlots()) do
		if not s.IsOffhand and textMatchesKind(s.Blob, kind) then
			if s.IsInventory and not bestInventory then bestInventory = s end
			if s.IsHotbar and not bestHotbar then bestHotbar = s end
		end
	end
	return bestInventory or bestHotbar
end

local function findOffhandSlot(slots)
	slots = slots or collectGuiSlots()
	for _, s in ipairs(slots) do
		if s.IsOffhand then return s end
	end
	-- прямой поиск: GuiObject с offhand/lefthand в имени, самый маленький по площади
	local playerGui = LocalPlayer:FindFirstChildOfClass("PlayerGui")
	if not playerGui then return nil end
	local best, bestArea = nil, math.huge
	for _, d in ipairs(playerGui:GetDescendants()) do
		if d:IsA("GuiObject") then
			local n = normalize(d.Name)
			if string.find(n, "offhand", 1, true) or string.find(n, "lefthand", 1, true) then
				local area = d.AbsoluteSize.X * d.AbsoluteSize.Y
				if area > 0 and area < bestArea then best, bestArea = d, area end
			end
		end
	end
	if best then
		return { Obj = best, IsOffhand = true, Blob = guiSlotBlob(best), Visible = isEffectivelyVisible(best) }
	end
	return nil
end

--// Выбор предмета в руку -------------------------------------------------------
-- Возвращает ok, источник ("tool"|"hotbar"), tool?
local function selectItem(kind)
	-- 1) настоящий Tool
	local tool = findTool(kind)
	if tool then
		if equipTool(tool) then return true, "tool", tool end
	end
	-- 2) ручной слот хотбара
	local manual = CONFIG.ManualHotbarSlots[kind] or 0
	if manual >= 1 and manual <= 9 then
		pressDigit(manual)
		task.wait(0.05)
		return true, "hotbar", nil
	end
	-- 3) автопоиск по GUI хотбару
	local slot = findHotbarSlot(kind)
	if slot then
		if slot.Index and slot.Index >= 1 and slot.Index <= 9 then
			if pressDigit(slot.Index) then
				task.wait(0.05)
				return true, "hotbar", nil
			end
		end
		if clickGuiObject(slot.Obj) then
			task.wait(0.05)
			return true, "hotbar", nil
		end
	end
	return false, nil, nil
end

-- Использовать предмет kind по мировой точке. mode: Place / Interact / Hit
local function useItemAt(kind, pos, mode)
	local ok, source, tool = selectItem(kind)
	if not ok then return false end
	local x, y = aimAt(pos)
	task.wait(0.04)
	if source == "tool" and tool then
		pcall(function() tool:Activate() end)
		if STATE.ExtraMouseClick then
			clickMouseAt(x, y, (mode == "Hit") and 0 or 1)
		end
	else
		-- кастомный хотбар в стиле Minecraft: поставить/использовать = ПКМ, ударить = ЛКМ
		clickMouseAt(x, y, (mode == "Hit") and 0 or 1)
	end
	return true
end

-- Клик "пустой рукой" (если оружия нет): Tool убираем, кликаем мышью
local function useHandAt(pos, mode)
	local hum = myHum()
	if hum and getEquippedTool() then
		pcall(function() hum:UnequipTools() end)
		task.wait(0.04)
	end
	return clickAtWorld(pos, mode)
end

local function restoreWeapon(prevTool)
	if prevTool and prevTool:IsA("Tool") and (prevTool.Parent ~= nil) then
		if not instanceMatchesKind(prevTool, "Totem") then
			equipTool(prevTool)
			return
		end
	end
	pcall(function() selectItem("Weapon") end)
end

--// Цель ------------------------------------------------------------------------
local function findNearestTarget()
	local root = myRoot()
	if not root then return nil, nil end
	local myPos = root.Position
	local best, bestDist = nil, CONFIG.TargetRange

	local function consider(model, name)
		if not model or model == myChar() then return end
		if not isAliveModel(model) then return end
		if model:FindFirstChildOfClass("ForceField") then return end
		local r = getRoot(model)
		if not r then return end
		local dist = (r.Position - myPos).Magnitude
		if dist < bestDist then
			best, bestDist = model, dist
			STATE.LastTargetName = name or model.Name
		end
	end

	for _, plr in ipairs(Players:GetPlayers()) do
		if plr ~= LocalPlayer then
			local sameTeam = (LocalPlayer.Team ~= nil and plr.Team ~= nil and LocalPlayer.Team == plr.Team)
			if not sameTeam then consider(plr.Character, plr.Name) end
		end
	end
	-- боты / NPC-соперники: модели-мобы прямо в Workspace с Humanoid
	for _, child in ipairs(workspace:GetChildren()) do
		if child:IsA("Model") and child ~= myChar() and getHum(child) and getRoot(child) then
			local isPlayerChar = Players:GetPlayerFromCharacter(child) ~= nil
			if not isPlayerChar then
				local n = normalize(child.Name)
				if not (string.find(n, "npc", 1, true) or string.find(n, "shop", 1, true)
					or string.find(n, "dummy", 1, true)) then
					consider(child, child.Name)
				end
			end
		end
	end
	return best, bestDist
end

--// Позиции: земля, точка взрыва, поставленные объекты --------------------------
local function groundPosition(fromPos)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local exclude = {}
	for _, plr in ipairs(Players:GetPlayers()) do
		if plr.Character then table.insert(exclude, plr.Character) end
	end
	for _, child in ipairs(workspace:GetChildren()) do
		if child:IsA("Model") and child:FindFirstChildOfClass("Humanoid") then
			table.insert(exclude, child)
		end
	end
	params.FilterDescendantsInstances = exclude
	local origin = fromPos + Vector3.new(0, 3, 0)
	local hit = workspace:Raycast(origin, Vector3.new(0, -14, 0), params)
	if hit then return hit.Position end
	return Vector3.new(fromPos.X, fromPos.Y - 3, fromPos.Z)
end

-- Точка взрыва: земля у ног цели, смещена ОТ тебя ЗА цель (цели - макс. урон,
-- тебе - меньше; при этом взрыв всего в ExplodeOffset стадах от хитбокса цели)
local function getPlacePosition(targetModel)
	local tRoot, mRoot = getRoot(targetModel), myRoot()
	if not tRoot then return nil end
	local foot = groundPosition(tRoot.Position)
	if not mRoot then return foot end
	local flat = Vector3.new(tRoot.Position.X - mRoot.Position.X, 0, tRoot.Position.Z - mRoot.Position.Z)
	if flat.Magnitude < 0.05 then
		flat = Vector3.new(tRoot.CFrame.LookVector.X, 0, tRoot.CFrame.LookVector.Z)
	end
	flat = flat.Unit
	local candidate = Vector3.new(foot.X + flat.X * CONFIG.ExplodeOffset, foot.Y + 2.5, foot.Z + flat.Z * CONFIG.ExplodeOffset)
	return groundPosition(candidate)
end

local function instancePosition(inst)
	if inst:IsA("BasePart") then return inst.Position end
	if inst:IsA("Model") then return inst:GetPivot().Position end
	return nil
end

-- Найти поставленный объект kind рядом с точкой (якорь / кристалл / обсидиан)
local function findPlaced(kind, nearPos, radius)
	radius = radius or 6
	local ok, parts = pcall(function()
		local op = OverlapParams.new()
		op.FilterType = Enum.RaycastFilterType.Exclude
		op.FilterDescendantsInstances = myChar() and { myChar() } or {}
		op.MaxParts = 200
		return workspace:GetPartBoundsInRadius(nearPos, radius, op)
	end)
	if not ok or not parts then return nil end
	local bestPos, bestDist = nil, math.huge
	for _, part in ipairs(parts) do
		local cur, inTool, matched = part, false, nil
		for _ = 1, 5 do
			if not cur then break end
			if cur:IsA("Tool") then inTool = true break end
			if not matched and instanceMatchesKind(cur, kind) then matched = cur end
			cur = cur.Parent
		end
		if matched and not inTool then
			local pos = instancePosition(matched) or part.Position
			local dist = (pos - nearPos).Magnitude
			if dist < bestDist then bestPos, bestDist = pos, dist end
		end
	end
	return bestPos
end

local function canSafelyExplode(pos)
	if not STATE.SafeMode then return true end
	local hum, root = myHum(), myRoot()
	if not hum or not root then return false end
	local selfDist = (root.Position - pos).Magnitude
	local hpFrac = (hum.MaxHealth > 0) and (hum.Health / hum.MaxHealth) or 1
	if selfDist < 2.5 and hpFrac < 0.35 then return false end
	return true
end

--// AutoCrystal: цикл якоря + кристалла -----------------------------------------
local function doAutoCrystalCycle()
	local target, dist = findNearestTarget()
	if not target then
		SetStatus("AutoCrystal: цели нет рядом")
		task.wait(0.25)
		return
	end
	if dist > CONFIG.PlaceRange then
		SetStatus(string.format("Цель %s далеко (%.0f) - подойди ближе", STATE.LastTargetName or "?", dist))
		task.wait(0.2)
		return
	end

	local prevTool = getEquippedTool()
	local tRoot = getRoot(target)
	local placePos = tRoot and getPlacePosition(target) or nil
	if not placePos then task.wait(0.2) return end

	SetStatus(string.format("AutoCrystal -> %s (%.0f ст.)", STATE.LastTargetName or "?", dist))

	--=== Якорь возрождения: поставить -> зарядить светокамнем -> взорвать ======
	if STATE.UseAnchors then
		if useItemAt("Anchor", placePos, "Place") then
			task.wait(CONFIG.StepDelay)
			local anchorPos = findPlaced("Anchor", tRoot.Position, 7) or placePos
			local charged = false
			for _ = 1, math.max(1, CONFIG.AnchorCharges) do
				if useItemAt("Glowstone", anchorPos, "Place") then charged = true end
				task.wait(CONFIG.StepDelay)
			end
			if not charged then
				LogThrottled("glow", "Glowstone не найден - якорь не заряжен", 4)
			end
			-- детонация: клик по заряженному якорю любым другим предметом
			anchorPos = findPlaced("Anchor", tRoot.Position, 7) or anchorPos
			if canSafelyExplode(anchorPos) then
				if not useItemAt("Weapon", anchorPos, "Interact") then
					useHandAt(anchorPos, "Interact")
				end
			else
				LogThrottled("safe", "SafeMode: пропущена детонация якоря (малый HP / слишком близко)", 3)
			end
			task.wait(CONFIG.StepDelay)
		else
			LogThrottled("anchor", "Respawn Anchor не найден в хотбаре/рюкзаке", 4)
		end
	end

	--=== Кристалл: обсидиан -> кристалл -> удар =================================
	if STATE.UseCrystals and isRunning() and isAliveModel(target) then
		tRoot = getRoot(target)
		local mRoot = myRoot()
		if tRoot and mRoot and (tRoot.Position - mRoot.Position).Magnitude <= CONFIG.PlaceRange then
			placePos = getPlacePosition(target) or placePos
			if useItemAt("Obsidian", placePos, "Place") then
				task.wait(CONFIG.StepDelay)
				local obsPos = findPlaced("Obsidian", tRoot.Position, 7) or placePos
				local crystalAim = obsPos + Vector3.new(0, 1.2, 0) -- верхняя грань обсидиана
				if useItemAt("Crystal", crystalAim, "Place") then
					task.wait(CONFIG.StepDelay)
					local crystalPos = findPlaced("Crystal", tRoot.Position, 7)
						or (obsPos + Vector3.new(0, 2, 0))
					if canSafelyExplode(crystalPos) then
						if not useItemAt("Weapon", crystalPos, "Hit") then
							useHandAt(crystalPos, "Hit")
						end
					else
						LogThrottled("safe2", "SafeMode: пропущен взрыв кристалла", 3)
					end
					task.wait(CONFIG.StepDelay)
				else
					LogThrottled("crystal", "End Crystal не найден в хотбаре/рюкзаке", 4)
				end
			else
				LogThrottled("obsidian", "Obsidian не найден в хотбаре/рюкзаке", 4)
			end
		end
	end

	restoreWeapon(prevTool)
end

--// AutoTotem -------------------------------------------------------------------
-- true = тотем в оффхенде, false = точно нет, nil = не удалось определить
local function isOffhandTotem()
	-- 1) атрибуты Offhand у игрока/персонажа
	local char = myChar()
	for _, holder in ipairs({ LocalPlayer, char }) do
		if holder then
			local ok, attrs = pcall(function() return holder:GetAttributes() end)
			if ok and attrs then
				for k, v in pairs(attrs) do
					local nk = normalize(tostring(k))
					if string.find(nk, "offhand", 1, true) or string.find(nk, "lefthand", 1, true) then
						if type(v) == "string" then
							if textMatchesKind(v, "Totem") then return true end
							if v ~= "" then return false end
						end
					end
				end
			end
			-- Value-объекты Offhand
			for _, d in ipairs(holder:GetDescendants()) do
				local nd = normalize(d.Name)
				if string.find(nd, "offhand", 1, true) then
					if d:IsA("StringValue") then
						if textMatchesKind(d.Value, "Totem") then return true end
						if d.Value ~= "" then return false end
					elseif d:IsA("ObjectValue") and d.Value then
						return instanceMatchesKind(d.Value, "Totem")
					end
				end
			end
		end
	end
	-- 2) предмет в левой руке персонажа
	if char then
		local leftHand = char:FindFirstChild("LeftHand") or char:FindFirstChild("Left Arm")
		if leftHand then
			for _, d in ipairs(leftHand:GetDescendants()) do
				if instanceMatchesKind(d, "Totem") then return true end
			end
			for _, d in ipairs(char:GetDescendants()) do
				local nd = normalize(d.Name)
				if string.find(nd, "offhand", 1, true) and instanceMatchesKind(d, "Totem") then
					return true
				end
			end
		end
	end
	-- 3) слот оффхенда в GUI
	local slot = findOffhandSlot()
	if slot then
		if textMatchesKind(slot.Blob or guiSlotBlob(slot.Obj), "Totem") then return true end
		local hasIcon = false
		for _, d in ipairs(slot.Obj:GetDescendants()) do
			if d:IsA("ImageLabel") or d:IsA("ImageButton") then
				if d.Image ~= "" and d.Visible then hasIcon = true end
			end
		end
		if hasIcon then return nil end -- что-то лежит, но не опознано по имени
		return false
	end
	return nil
end

local function inventoryIsOpen(slots)
	slots = slots or collectGuiSlots()
	for _, s in ipairs(slots) do
		if s.IsInventory and s.Visible then return true end
	end
	return false
end

-- Свап тотема в левую руку. Порядок попыток: F (свап рук) -> клики по инвентарю -> драга
local function swapTotemNow()
	local now = os.clock()
	STATE.LastTotemAttempt = now
	local prevTool = getEquippedTool()

	-- Попытка 1: взять тотем в руку и нажать F (как в Minecraft)
	local okSel, selSource = selectItem("Totem")
	if okSel then
		sendKey(CONFIG.SwapHandsKey, 0x46) -- F
		task.wait(0.18)
		local state = isOffhandTotem()
		if state == true then
			restoreWeapon(prevTool)
			Log("AutoTotem: тотем в оффхенде (свап по F)")
			return true
		end
		-- тотем исчез из руки после F - значит свап сработал, даже если оффхенд не читается
		local eq = getEquippedTool()
		if state == nil and selSource == "tool" and (not eq or not instanceMatchesKind(eq, "Totem")) then
			restoreWeapon(prevTool)
			Log("AutoTotem: свап по F выполнен (статус оффхенда не читается)")
			return true
		end
	else
		LogThrottled("totemsel", "AutoTotem: тотем не найден ни Tool-ом, ни в хотбаре - пробую инвентарь", 4)
	end

	-- Попытка 2: инвентарь - клик по тотему, клик по слоту оффхенда
	local slots = collectGuiSlots()
	local openedByUs = false
	if not inventoryIsOpen(slots) then
		sendKey(CONFIG.InventoryKey, 0x45) -- E
		openedByUs = true
		task.wait(0.3)
		slots = collectGuiSlots()
	end
	local totemSlot, offhandSlot = nil, nil
	for _, s in ipairs(slots) do
		if s.IsOffhand then offhandSlot = s end
		if not s.IsOffhand and textMatchesKind(s.Blob, "Totem") and not totemSlot then totemSlot = s end
	end
	offhandSlot = offhandSlot or findOffhandSlot(slots)

	local success = false
	if totemSlot and offhandSlot then
		clickGuiObject(totemSlot.Obj)
		task.wait(0.12)
		clickGuiObject(offhandSlot.Obj)
		task.wait(0.2)
		if isOffhandTotem() == true then
			success = true
		else
			-- если слот тотема опустел - клики сработали; если тотем всё ещё там - пробуем драгу
			local stillTotem = guiSlotMatchesKind(totemSlot.Obj, "Totem")
			if not stillTotem then
				success = true
			else
				dragGuiObject(totemSlot.Obj, offhandSlot.Obj)
				task.wait(0.2)
				if isOffhandTotem() == true or not guiSlotMatchesKind(totemSlot.Obj, "Totem") then
					success = true
				end
			end
		end
	else
		LogThrottled("totemgui", "AutoTotem: не найден слот тотема/оффхенда в GUI. Нажми Дамп (F9) и пришли вывод.", 5)
	end

	if openedByUs then
		sendKey(CONFIG.InventoryKey, 0x45)
		task.wait(0.1)
	end
	restoreWeapon(prevTool)
	if success then Log("AutoTotem: тотем перенесён в левую руку через инвентарь") end
	return success
end

local function autoTotemTick()
	local hum = myHum()
	if not hum or hum.Health <= 0 then return end
	if not STATE.TotemAlways then
		local frac = (hum.MaxHealth > 0) and (hum.Health / hum.MaxHealth * 100) or 100
		if frac > CONFIG.TotemHPPercent then return end
	end
	local state = isOffhandTotem()
	STATE.OffhandText = (state == true and "тотем") or (state == false and "ПУСТО") or "?"
	if state == true then return end
	-- кулдаун, чтобы не спамить свапами, когда статус оффхенда не читается
	local cooldown = (state == nil) and 2.5 or 0.6
	if os.clock() - STATE.LastTotemAttempt < cooldown then return end
	swapTotemNow()
end

--// Дамп для точной подгонки под игру (кнопка в GUI, вывод - F9) -----------------
local function dumpDebug()
	local function line(s) print("[FILOSOF-DUMP] " .. s) end
	line("PlaceId=" .. tostring(game.PlaceId))
	local char = myChar()
	line("-- Tools в Character:")
	if char then
		for _, c in ipairs(char:GetChildren()) do
			if c:IsA("Tool") then line("  " .. c.Name .. " | tip=" .. tostring(c.ToolTip) .. " | blob=" .. instanceBlob(c)) end
		end
	end
	line("-- Tools в Backpack:")
	local bp = LocalPlayer:FindFirstChildOfClass("Backpack")
	if bp then
		for _, c in ipairs(bp:GetChildren()) do
			if c:IsA("Tool") then line("  " .. c.Name .. " | tip=" .. tostring(c.ToolTip) .. " | blob=" .. instanceBlob(c)) end
		end
	end
	line("-- Дети Character:")
	if char then
		for _, c in ipairs(char:GetChildren()) do line("  " .. c.ClassName .. " " .. c.Name) end
	end
	line("-- GUI слоты (хотбар/инвентарь/оффхенд), до 80:")
	local slots = collectGuiSlots()
	for i, s in ipairs(slots) do
		if i > 80 then break end
		line(string.format("  [%s%s%s] idx=%s path=%s blob=%s",
			s.IsHotbar and "HOT " or "", s.IsInventory and "INV " or "", s.IsOffhand and "OFF " or "",
			tostring(s.Index), s.Obj:GetFullName(), string.sub(s.Blob, 1, 160)))
	end
	local off = findOffhandSlot(slots)
	line("-- Offhand слот: " .. (off and off.Obj:GetFullName() or "НЕ НАЙДЕН")
		.. " | isOffhandTotem=" .. tostring(isOffhandTotem()))
	line("-- ScreenGui в PlayerGui:")
	local pg = LocalPlayer:FindFirstChildOfClass("PlayerGui")
	if pg then
		for _, c in ipairs(pg:GetChildren()) do line("  " .. c.ClassName .. " " .. c.Name) end
	end
	line("-- RemoteEvent/RemoteFunction в ReplicatedStorage, до 120:")
	local cnt = 0
	for _, d in ipairs(ReplicatedStorage:GetDescendants()) do
		if d:IsA("RemoteEvent") or d:IsA("RemoteFunction") then
			cnt = cnt + 1
			if cnt <= 120 then line("  " .. d.ClassName .. " " .. d:GetFullName()) end
		end
	end
	line("-- Всего ремотов: " .. tostring(cnt))
	Log("Дамп выведен в консоль (F9) - пришли его, чтобы подогнать скрипт точно")
end

--// ClickGUI ---------------------------------------------------------------------
local GUI_NAME = "FilosofKitPvPTester"

local guiParent = nil
do
	local gethui = getGlobal("gethui")
	if gethui then
		local ok, res = pcall(gethui)
		if ok and res then guiParent = res end
	end
	if not guiParent then
		guiParent = LocalPlayer:WaitForChild("PlayerGui")
	end
end
-- убрать старое GUI
for _, holder in ipairs({ guiParent, LocalPlayer:FindFirstChildOfClass("PlayerGui") }) do
	if holder then
		local old = holder:FindFirstChild(GUI_NAME)
		if old then old:Destroy() end
	end
end

local function create(className, props, parent)
	local obj = Instance.new(className)
	for k, v in pairs(props or {}) do
		pcall(function() obj[k] = v end)
	end
	if parent then obj.Parent = parent end
	return obj
end

local COLORS = {
	Bg      = Color3.fromRGB(22, 22, 28),
	Title   = Color3.fromRGB(32, 32, 44),
	Row     = Color3.fromRGB(36, 36, 50),
	RowAlt  = Color3.fromRGB(30, 30, 42),
	Accent  = Color3.fromRGB(255, 170, 0),   -- Minecraft-золото
	On      = Color3.fromRGB(60, 200, 90),
	Off     = Color3.fromRGB(90, 90, 110),
	Text    = Color3.fromRGB(235, 235, 245),
	SubText = Color3.fromRGB(160, 160, 185),
}

local screenGui = create("ScreenGui", {
	Name = GUI_NAME, ResetOnSpawn = false, DisplayOrder = 999,
	IgnoreGuiInset = true, ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
}, guiParent)

-- Плавающая кнопка открытия (видно, когда GUI закрыто)
local openButton = create("TextButton", {
	Name = "OpenButton", Text = "F", Font = Enum.Font.GothamBlack, TextSize = 22,
	TextColor3 = Color3.fromRGB(20, 20, 20), BackgroundColor3 = COLORS.Accent,
	Size = UDim2.new(0, 46, 0, 46), Position = UDim2.new(0, 14, 0.5, -23),
	Visible = false, AutoButtonColor = true,
}, screenGui)
create("UICorner", { CornerRadius = UDim.new(1, 0) }, openButton)
create("UIStroke", { Color = Color3.fromRGB(0, 0, 0), Thickness = 2 }, openButton)

-- Главное окно
local main = create("Frame", {
	Name = "Main", BackgroundColor3 = COLORS.Bg, BorderSizePixel = 0,
	Size = UDim2.new(0, 348, 0, 470), Position = UDim2.new(0.5, -174, 0.5, -235),
	Active = true,
}, screenGui)
create("UICorner", { CornerRadius = UDim.new(0, 10) }, main)
create("UIStroke", { Color = COLORS.Accent, Thickness = 1.5 }, main)

local titleBar = create("Frame", {
	Name = "TitleBar", BackgroundColor3 = COLORS.Title, BorderSizePixel = 0,
	Size = UDim2.new(1, 0, 0, 40), Active = true,
}, main)
create("UICorner", { CornerRadius = UDim.new(0, 10) }, titleBar)

create("TextLabel", {
	Text = "⛏  FILOSOF | Kit PvP Tester", Font = Enum.Font.GothamBlack, TextSize = 15,
	TextColor3 = COLORS.Accent, BackgroundTransparency = 1,
	Size = UDim2.new(1, -90, 1, 0), Position = UDim2.new(0, 10, 0, 0),
	TextXAlignment = Enum.TextXAlignment.Left,
}, titleBar)

create("TextLabel", {
	Text = "RightShift", Font = Enum.Font.Gotham, TextSize = 11,
	TextColor3 = COLORS.SubText, BackgroundTransparency = 1,
	Size = UDim2.new(0, 54, 1, 0), Position = UDim2.new(1, -88, 0, 0),
}, titleBar)

local closeButton = create("TextButton", {
	Name = "Close", Text = "✕", Font = Enum.Font.GothamBlack, TextSize = 16,
	TextColor3 = Color3.fromRGB(255, 255, 255), BackgroundColor3 = Color3.fromRGB(190, 50, 50),
	Size = UDim2.new(0, 32, 0, 28), Position = UDim2.new(1, -38, 0, 6), AutoButtonColor = true,
}, titleBar)
create("UICorner", { CornerRadius = UDim.new(0, 6) }, closeButton)

local content = create("ScrollingFrame", {
	Name = "Content", BackgroundTransparency = 1, BorderSizePixel = 0,
	Size = UDim2.new(1, -12, 1, -52), Position = UDim2.new(0, 6, 0, 46),
	CanvasSize = UDim2.new(0, 0, 0, 0), ScrollBarThickness = 5,
	ScrollBarImageColor3 = COLORS.Accent,
}, main)
local layout = create("UIListLayout", {
	Padding = UDim.new(0, 5), SortOrder = Enum.SortOrder.LayoutOrder,
}, content)
layout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
	content.CanvasSize = UDim2.new(0, 0, 0, layout.AbsoluteContentSize.Y + 10)
end)

local layoutOrder = 0
local function nextOrder()
	layoutOrder = layoutOrder + 1
	return layoutOrder
end

local function addSection(text)
	create("TextLabel", {
		Text = text, Font = Enum.Font.GothamBlack, TextSize = 13,
		TextColor3 = COLORS.Accent, BackgroundTransparency = 1,
		Size = UDim2.new(1, -4, 0, 22), LayoutOrder = nextOrder(),
		TextXAlignment = Enum.TextXAlignment.Left,
	}, content)
end

local function addToggle(text, initial, onChanged)
	local value = initial and true or false
	local btn = create("TextButton", {
		Text = "", BackgroundColor3 = COLORS.Row, BorderSizePixel = 0,
		Size = UDim2.new(1, -4, 0, 34), LayoutOrder = nextOrder(), AutoButtonColor = false,
	}, content)
	create("UICorner", { CornerRadius = UDim.new(0, 7) }, btn)
	local label = create("TextLabel", {
		Text = text, Font = Enum.Font.GothamBold, TextSize = 13,
		TextColor3 = COLORS.Text, BackgroundTransparency = 1,
		Size = UDim2.new(1, -64, 1, 0), Position = UDim2.new(0, 10, 0, 0),
		TextXAlignment = Enum.TextXAlignment.Left,
	}, btn)
	local stateLabel = create("TextLabel", {
		Font = Enum.Font.GothamBlack, TextSize = 12, BackgroundTransparency = 1,
		Size = UDim2.new(0, 52, 1, 0), Position = UDim2.new(1, -56, 0, 0),
	}, btn)
	local function render()
		stateLabel.Text = value and "ON ●" or "○ OFF"
		stateLabel.TextColor3 = value and COLORS.On or COLORS.Off
		btn.BackgroundColor3 = value and Color3.fromRGB(34, 52, 40) or COLORS.Row
	end
	render()
	btn.MouseButton1Click:Connect(function()
		value = not value
		render()
		onChanged(value)
		Log(text .. ": " .. (value and "ВКЛ" or "ВЫКЛ"))
	end)
	return btn
end

local function addStepper(text, initial, minV, maxV, step, format, onChanged)
	local value = initial
	local row = create("Frame", {
		BackgroundColor3 = COLORS.RowAlt, BorderSizePixel = 0,
		Size = UDim2.new(1, -4, 0, 34), LayoutOrder = nextOrder(),
	}, content)
	create("UICorner", { CornerRadius = UDim.new(0, 7) }, row)
	create("TextLabel", {
		Text = text, Font = Enum.Font.Gotham, TextSize = 12,
		TextColor3 = COLORS.Text, BackgroundTransparency = 1,
		Size = UDim2.new(1, -150, 1, 0), Position = UDim2.new(0, 10, 0, 0),
		TextXAlignment = Enum.TextXAlignment.Left,
	}, row)
	local minus = create("TextButton", {
		Text = "−", Font = Enum.Font.GothamBlack, TextSize = 16,
		TextColor3 = COLORS.Text, BackgroundColor3 = Color3.fromRGB(55, 55, 75),
		Size = UDim2.new(0, 30, 0, 26), Position = UDim2.new(1, -146, 0, 4),
	}, row)
	create("UICorner", { CornerRadius = UDim.new(0, 6) }, minus)
	local valLabel = create("TextLabel", {
		Font = Enum.Font.GothamBlack, TextSize = 13, TextColor3 = COLORS.Accent,
		BackgroundTransparency = 1, Size = UDim2.new(0, 70, 1, 0),
		Position = UDim2.new(1, -114, 0, 0),
	}, row)
	local plus = create("TextButton", {
		Text = "+", Font = Enum.Font.GothamBlack, TextSize = 16,
		TextColor3 = COLORS.Text, BackgroundColor3 = Color3.fromRGB(55, 55, 75),
		Size = UDim2.new(0, 30, 0, 26), Position = UDim2.new(1, -42, 0, 4),
	}, row)
	create("UICorner", { CornerRadius = UDim.new(0, 6) }, plus)
	local function render()
		valLabel.Text = string.format(format, value)
	end
	local function apply(v)
		value = math.clamp(math.floor(v / step + 0.5) * step, minV, maxV)
		render()
		onChanged(value)
	end
	render()
	minus.MouseButton1Click:Connect(function() apply(value - step) end)
	plus.MouseButton1Click:Connect(function() apply(value + step) end)
	return row
end

local function addButton(text, color, onClick)
	local btn = create("TextButton", {
		Text = text, Font = Enum.Font.GothamBold, TextSize = 13,
		TextColor3 = Color3.fromRGB(255, 255, 255), BackgroundColor3 = color,
		Size = UDim2.new(1, -4, 0, 36), LayoutOrder = nextOrder(), AutoButtonColor = true,
	}, content)
	create("UICorner", { CornerRadius = UDim.new(0, 7) }, btn)
	btn.MouseButton1Click:Connect(function()
		task.spawn(function()
			local ok, err = pcall(onClick)
			if not ok then Log("Ошибка кнопки: " .. tostring(err)) end
		end)
	end)
	return btn
end

--=== Наполнение меню =============================================================
addSection("⚔  COMBAT")
addToggle("AutoCrystal (якоря + кристаллы)", false, function(v) STATE.AutoCrystal = v end)
addToggle("Использовать якори возрождения", true, function(v) STATE.UseAnchors = v end)
addToggle("Использовать кристаллы Края", true, function(v) STATE.UseCrystals = v end)
addToggle("AutoTotem (тотем в левую руку)", false, function(v) STATE.AutoTotem = v end)
addToggle("Тотем всегда (иначе на низком HP)", true, function(v) STATE.TotemAlways = v end)

addSection("⚙  НАСТРОЙКИ")
addToggle("Безопасность (не взрывать у себя на низком HP)", true, function(v) STATE.SafeMode = v end)
addToggle("Прицел камерой в точку взрыва", true, function(v) STATE.AimCamera = v end)
addToggle("Доп. клик мыши поверх Tool", false, function(v) STATE.ExtraMouseClick = v end)
addStepper("Дистанция поиска цели", CONFIG.TargetRange, 6, 40, 1, "%.0f", function(v) CONFIG.TargetRange = v end)
addStepper("Дистанция постановки", CONFIG.PlaceRange, 3, 14, 0.5, "%.1f", function(v) CONFIG.PlaceRange = v end)
addStepper("Смещение взрыва за цель", CONFIG.ExplodeOffset, 0, 3, 0.1, "%.1f", function(v) CONFIG.ExplodeOffset = v end)
addStepper("Задержка цикла (сек)", CONFIG.CycleDelay, 0, 1.5, 0.05, "%.2f", function(v) CONFIG.CycleDelay = v end)
addStepper("Задержка шага (сек)", CONFIG.StepDelay, 0.02, 0.6, 0.01, "%.2f", function(v) CONFIG.StepDelay = v end)
addStepper("Зарядов якоря светокамнем", CONFIG.AnchorCharges, 1, 4, 1, "%.0f", function(v) CONFIG.AnchorCharges = v end)
addStepper("Порог HP тотема (%)", CONFIG.TotemHPPercent, 10, 100, 5, "%.0f", function(v) CONFIG.TotemHPPercent = v end)

addSection("🧪 ТЕСТ / ДЕБАГ")
addButton("Свапнуть тотем сейчас", Color3.fromRGB(120, 85, 20), function()
	local ok = swapTotemNow()
	Log("Ручной свап тотема: " .. (ok and "OK" or "не получилось - смотри лог выше"))
end)
addButton("Дамп предметов и ремотов (F9)", Color3.fromRGB(45, 70, 140), dumpDebug)

-- Статус / цель / лог
UI.StatusLabel = create("TextLabel", {
	Text = "Статус: готово", Font = Enum.Font.GothamBold, TextSize = 12,
	TextColor3 = COLORS.Text, BackgroundColor3 = COLORS.Row, BorderSizePixel = 0,
	Size = UDim2.new(1, -4, 0, 28), LayoutOrder = nextOrder(),
	TextXAlignment = Enum.TextXAlignment.Left, TextWrapped = true,
}, content)
create("UICorner", { CornerRadius = UDim.new(0, 7) }, UI.StatusLabel)

UI.TargetLabel = create("TextLabel", {
	Text = "Цель: - | Оффхенд: ?", Font = Enum.Font.Gotham, TextSize = 12,
	TextColor3 = COLORS.SubText, BackgroundTransparency = 1,
	Size = UDim2.new(1, -4, 0, 20), LayoutOrder = nextOrder(),
	TextXAlignment = Enum.TextXAlignment.Left,
}, content)

UI.LogLabel = create("TextLabel", {
	Text = "", Font = Enum.Font.Code, TextSize = 11,
	TextColor3 = COLORS.SubText, BackgroundColor3 = Color3.fromRGB(16, 16, 22),
	BorderSizePixel = 0, Size = UDim2.new(1, -4, 0, 86), LayoutOrder = nextOrder(),
	TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top,
	TextWrapped = true,
}, content)
create("UICorner", { CornerRadius = UDim.new(0, 7) }, UI.LogLabel)
UI.LogLabel.Text = table.concat(LogLines, "\n")

--// Открыть / закрыть GUI ---------------------------------------------------------
local function setGuiOpen(open)
	STATE.GuiOpen = open
	main.Visible = open
	openButton.Visible = not open
end
closeButton.MouseButton1Click:Connect(function() setGuiOpen(false) end)
openButton.MouseButton1Click:Connect(function() setGuiOpen(true) end)

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then return end
	if input.KeyCode == Enum.KeyCode.RightShift or input.KeyCode == Enum.KeyCode.Insert then
		setGuiOpen(not STATE.GuiOpen)
	end
end)

--// Перетаскивание окна и кнопки ---------------------------------------------------
local function makeDraggable(frame, handle)
	handle = handle or frame
	local dragging, dragStart, frameStart = false, nil, nil
	handle.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch then
			dragging, dragStart, frameStart = true, input.Position, frame.Position
			input.Changed:Connect(function()
				if input.UserInputState == Enum.UserInputState.End then dragging = false end
			end)
		end
	end)
	UserInputService.InputChanged:Connect(function(input)
		if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement
			or input.UserInputType == Enum.UserInputType.Touch) then
			local delta = input.Position - dragStart
			frame.Position = UDim2.new(frameStart.X.Scale, frameStart.X.Offset + delta.X,
				frameStart.Y.Scale, frameStart.Y.Offset + delta.Y)
		end
	end)
end
makeDraggable(main, titleBar)
makeDraggable(openButton, openButton)

--// Главные циклы ------------------------------------------------------------------
task.spawn(function()
	while isRunning() do
		if STATE.AutoCrystal then
			local ok, err = pcall(doAutoCrystalCycle)
			if not ok then LogThrottled("cycerr", "AutoCrystal ошибка: " .. tostring(err), 3) end
			task.wait(CONFIG.CycleDelay)
		else
			task.wait(0.2)
		end
	end
end)

task.spawn(function()
	while isRunning() do
		if STATE.AutoTotem then
			local ok, err = pcall(autoTotemTick)
			if not ok then LogThrottled("toterr", "AutoTotem ошибка: " .. tostring(err), 3) end
		end
		task.wait(0.3)
	end
end)

task.spawn(function()
	while isRunning() do
		if UI.TargetLabel then
			local target, dist = nil, nil
			pcall(function() target, dist = findNearestTarget() end)
			local targetText = target and string.format("%s (%.0f ст.)", STATE.LastTargetName or target.Name, dist or 0) or "-"
			UI.TargetLabel.Text = string.format("Цель: %s  |  Оффхенд: %s", targetText, STATE.OffhandText)
		end
		task.wait(0.6)
	end
end)

LocalPlayer.CharacterAdded:Connect(function()
	Log("Персонаж возродился - скрипт продолжает работу")
	STATE.LastTotemAttempt = 0
end)

setGuiOpen(true)
if game.PlaceId ~= CONFIG.ExpectedPlaceId then
	Log("ВНИМАНИЕ: PlaceId " .. tostring(game.PlaceId) .. " != Kit PvP (" .. tostring(CONFIG.ExpectedPlaceId) .. ") - продолжаю в универсальном режиме")
else
	Log("Kit PvP определена. Готово к тестам на приватном сервере.")
end
Log("Загружено: RightShift - меню, кнопка F - открыть. Положи Anchor/Glowstone/Obsidian/Crystal/Totem в хотбар!")

