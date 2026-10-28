--[[
    ╔════════════════════════════════════════════════════════════════╗
    ║  HORROR TACTICAL KIT  •  Lanterna Tática + Radar de Terror      ║
    ║  Luau • Client-side • Compatível com Delta Executor (PC/Mobile) ║
    ╚════════════════════════════════════════════════════════════════╝

    O QUE FAZ
      1) Lanterna tática amarela (Tool) com SpotLight, On/Off por clique,
         tecla [F] ou botão no painel. Equipa-se automaticamente.
      2) Consola/monitor 3D com ecrã verde de varredura (SurfaceGui):
         - Radar centrado em TI: a frente do teu personagem = topo do ecrã.
         - Rastreia jogadores e entidades (NPCs com Humanoid) até ao alcance.
         - Bipe de aviso: quanto mais perto o alvo, mais rápido e mais agudo.
      3) Painel compacto arrastável (toque/rato) com botões utilitários.

    OTIMIZAÇÃO
      • Dados do radar atualizados a 5 Hz (SCAN_RATE), não a cada frame.
      • Pool fixo de blips (Frames reutilizados), zero criação em runtime.
      • Cache de NPCs por eventos (DescendantAdded/Removing), sem varrer o
        Workspace em loop.
      • Ecrã da consola desliga sozinho quando estás longe dela.
      • Uma única ligação Heartbeat para varredura + bipe.

    NOTA: por ser client-side, só TU vês a lanterna, a consola e a luz.
]]

------------------------------------------------------------
-- SERVIÇOS
------------------------------------------------------------
local Players      = game:GetService("Players")
local RunService   = game:GetService("RunService")
local UIS          = game:GetService("UserInputService")
local Workspace    = game:GetService("Workspace")
local SoundService = game:GetService("SoundService")

local lp = Players.LocalPlayer
if not lp then return end

------------------------------------------------------------
-- CONFIGURAÇÕES (edita à vontade)
------------------------------------------------------------
local CONFIG = {
	-- Lanterna
	TOOL_NAME   = "Lanterna Tática",
	FLASH_KEY   = Enum.KeyCode.F,   -- tecla para ligar/desligar
	BEAM_RANGE  = 60,               -- alcance do feixe (studs)
	BEAM_ANGLE  = 50,               -- abertura do cone (graus, máx. 180)
	BEAM_BRIGHT = 4,                -- intensidade
	BEAM_SHADOWS = false,           -- sombras (mais realista, mas pesa no FPS)

	-- Radar
	RANGE       = 80,               -- alcance de deteção (studs)
	DANGER_DIST = 30,               -- abaixo disto = estado "PERIGO"
	SCAN_RATE   = 0.2,              -- segundos entre leituras (5 Hz)
	TRACK_NPCS  = true,             -- rastrear NPCs (Humanoids que não são jogadores)
	SCREEN_CULL = 120,              -- desliga o ecrã se estiveres a mais de X studs
	SWEEP_SPEED = 200,              -- velocidade da varredura (graus/s)

	-- Bipe
	BEEP_ID      = "rbxasset://sounds/electronicpingshort.wav", -- som nativo do Roblox
	BEEP_VOLUME  = 0.6,
	BEEP_FAR     = 2.0,             -- intervalo entre bipes no limite do alcance (s)
	BEEP_NEAR    = 0.15,            -- intervalo quando o alvo está colado (s)
	PITCH_FAR    = 0.9,             -- tom do bipe ao longe
	PITCH_NEAR   = 1.8,             -- tom do bipe ao perto
}

local MAX_BLIPS = 24 -- tamanho do pool de blips

------------------------------------------------------------
-- CORES
------------------------------------------------------------
local YELLOW   = Color3.fromRGB(255, 196, 0)
local BLACK    = Color3.fromRGB(18, 18, 20)
local DARK     = Color3.fromRGB(35, 35, 38)
local STEEL    = Color3.fromRGB(190, 190, 195)
local LAMP_ON  = Color3.fromRGB(255, 244, 205)
local LAMP_OFF = Color3.fromRGB(150, 150, 150)
local NEON     = Color3.fromRGB(0, 255, 140)
local NEON_DIM = Color3.fromRGB(0, 120, 70)
local ALERT    = Color3.fromRGB(255, 60, 60)
local C_PLAYER = Color3.fromRGB(255, 230, 80)
local C_ENTITY = Color3.fromRGB(255, 70, 70)

------------------------------------------------------------
-- EVITA DUPLICAR: remove a execução anterior, se existir
------------------------------------------------------------
local GENV = (getgenv and getgenv()) or _G
if GENV.HorrorTacticalKit and GENV.HorrorTacticalKit.Destroy then
	pcall(GENV.HorrorTacticalKit.Destroy)
end

------------------------------------------------------------
-- ESTADO E LIMPEZA
------------------------------------------------------------
local connections = {}   -- todas as ligações globais (desligadas ao fechar)
local alive = true
local flashOn = false
local muted = false

local flash = { tool = nil, spot = nil, lamps = {} }
local radar = { model = nil, gui = nil, cf = nil, display = nil }
local npcs = {}          -- [Humanoid] = true (cache de entidades)
local beepSound          -- Sound do bipe
local panelGui           -- ScreenGui do painel

local function track(conn)
	table.insert(connections, conn)
	return conn
end

local function create(class, props, parent)
	local inst = Instance.new(class)
	for k, v in pairs(props) do inst[k] = v end
	inst.Parent = parent
	return inst
end

-- Escolhe o melhor local para a GUI (gethui é o mais seguro em executores)
local function getGuiParent()
	local ok, ui = pcall(function() return gethui and gethui() end)
	if ok and ui then return ui end
	local ok2, core = pcall(function() return game:GetService("CoreGui") end)
	if ok2 and core then
		local probe = Instance.new("Folder")
		local can = pcall(function() probe.Parent = core end)
		probe:Destroy()
		if can then return core end
	end
	return lp:WaitForChild("PlayerGui")
end

------------------------------------------------------------
-- 1) LANTERNA TÁTICA
------------------------------------------------------------
-- Aplica o estado On/Off à luz e às lâmpadas neon
local function applyFlash()
	if flash.spot then flash.spot.Enabled = flashOn end
	for _, lamp in ipairs(flash.lamps) do
		if lamp.Parent then
			lamp.Material = flashOn and Enum.Material.Neon or Enum.Material.SmoothPlastic
			lamp.Color = flashOn and LAMP_ON or LAMP_OFF
		end
	end
end

local function toggleFlash()
	flashOn = not flashOn
	applyFlash()
end

local function buildFlashlight()
	local tool = Instance.new("Tool")
	tool.Name = CONFIG.TOOL_NAME
	tool.ToolTip = "Lanterna tática de mão"
	tool.RequiresHandle = true
	tool.CanBeDropped = false
	tool.GripPos = Vector3.new(0, 0, 0.5) -- segura pela parte traseira

	-- Corpo principal (Handle obrigatório)
	local handle = Instance.new("Part")
	handle.Name = "Handle"
	handle.Size = Vector3.new(0.7, 0.7, 2.2)
	handle.Color = YELLOW
	handle.Material = Enum.Material.SmoothPlastic
	handle.CanCollide = false
	handle.Massless = true
	handle.Parent = tool

	-- Cria peça soldada ao Handle (offset relativo ao Handle)
	local function addPart(name, size, offset, color, material, shape)
		local p = Instance.new("Part")
		p.Name = name
		p.Size = size
		p.Color = color
		p.Material = material or Enum.Material.SmoothPlastic
		if shape then p.Shape = shape end
		p.CanCollide = false
		p.Massless = true
		p.CastShadow = false
		local w = Instance.new("Weld")
		w.Part0 = handle
		w.Part1 = p
		w.C0 = offset
		w.Parent = p
		p.Parent = tool
		return p
	end

	-- Cilindro Roblox tem eixo no X; esta rotação deita-o ao longo do eixo Z
	local ROT = CFrame.Angles(0, math.rad(90), 0)
	local CYL = Enum.PartType.Cylinder

	-- Tampa traseira + faixas de pega
	addPart("BackCap", Vector3.new(0.5, 0.78, 0.78), CFrame.new(0, 0, 1.15) * ROT, DARK, nil, CYL)
	addPart("GripBand1", Vector3.new(0.3, 0.76, 0.76), CFrame.new(0, 0, 0.5) * ROT, BLACK, nil, CYL)
	addPart("GripBand2", Vector3.new(0.3, 0.76, 0.76), CFrame.new(0, 0, 0.1) * ROT, BLACK, nil, CYL)
	-- Botão do interruptor
	addPart("Switch", Vector3.new(0.2, 0.15, 0.35), CFrame.new(0, 0.4, -0.2), BLACK)

	-- Cabeça: refletor metálico + aro preto
	addPart("Reflector", Vector3.new(0.9, 1.5, 1.5), CFrame.new(0, 0, -1.4) * ROT, STEEL, Enum.Material.Metal, CYL)
	addPart("Bezel", Vector3.new(0.15, 1.65, 1.65), CFrame.new(0, 0, -1.85) * ROT, BLACK, nil, CYL)

	-- Lente central (acende em neon quando ligada)
	local lens = addPart("Lens", Vector3.new(0.1, 1.2, 1.2), CFrame.new(0, 0, -1.9) * ROT, LAMP_OFF, nil, CYL)

	-- Ponto invisível de emissão: o SpotLight aponta na face Front (-Z)
	local muzzle = addPart("Muzzle", Vector3.new(0.2, 0.2, 0.2), CFrame.new(0, 0, -2.0), LAMP_OFF)
	muzzle.Transparency = 1

	local spot = Instance.new("SpotLight")
	spot.Name = "Beam"
	spot.Face = Enum.NormalId.Front
	spot.Color = Color3.fromRGB(255, 244, 214)
	spot.Range = CONFIG.BEAM_RANGE
	spot.Angle = CONFIG.BEAM_ANGLE
	spot.Brightness = CONFIG.BEAM_BRIGHT
	spot.Shadows = CONFIG.BEAM_SHADOWS
	spot.Enabled = false
	spot.Parent = muzzle

	flash.tool, flash.spot, flash.lamps = tool, spot, { lens }

	-- Clique (ou toque) com a lanterna equipada alterna a luz
	tool.Activated:Connect(toggleFlash)
	return tool
end

-- Cria a lanterna, coloca na mochila e equipa
local function giveFlashlight()
	if flash.tool then flash.tool:Destroy() end
	local tool = buildFlashlight()
	tool.Parent = lp:WaitForChild("Backpack")
	applyFlash()
	pcall(function()
		local hum = lp.Character and lp.Character:FindFirstChildOfClass("Humanoid")
		if hum then
			task.wait(0.1)
			hum:EquipTool(tool)
		end
	end)
end

------------------------------------------------------------
-- 2) RADAR: CACHE DE ENTIDADES (NPCs)
------------------------------------------------------------
-- Em vez de varrer o Workspace em loop, guardamos Humanoids por eventos.
if CONFIG.TRACK_NPCS then
	task.spawn(function()
		local n = 0
		for _, inst in ipairs(Workspace:GetDescendants()) do
			if inst:IsA("Humanoid") then npcs[inst] = true end
			n += 1
			if n % 1500 == 0 then task.wait() end -- cede o frame em mapas grandes
		end
	end)
	track(Workspace.DescendantAdded:Connect(function(inst)
		if inst:IsA("Humanoid") then npcs[inst] = true end
	end))
	track(Workspace.DescendantRemoving:Connect(function(inst)
		if npcs[inst] then npcs[inst] = nil end
	end))
end

------------------------------------------------------------
-- 3) RADAR: ECRÃ (SurfaceGui com varredura e blips)
------------------------------------------------------------
local function buildDisplay(parent)
	local d = {}
	local R = 320 -- diâmetro do scope em pixels

	local root = create("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.fromRGB(2, 14, 8),
		BorderSizePixel = 0,
	}, parent)

	-- Scope circular
	local scope = create("Frame", {
		Size = UDim2.fromOffset(R, R), Position = UDim2.fromOffset(12, 10),
		BackgroundColor3 = Color3.fromRGB(0, 28, 16), BorderSizePixel = 0,
		ClipsDescendants = true,
	}, root)
	create("UICorner", { CornerRadius = UDim.new(0.5, 0) }, scope)
	local scopeStroke = create("UIStroke", { Color = NEON, Thickness = 3 }, scope)

	-- Anéis de distância
	for _, f in ipairs({ 0.66, 0.33 }) do
		local ring = create("Frame", {
			Size = UDim2.fromScale(f, f), AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5), BackgroundTransparency = 1,
		}, scope)
		create("UICorner", { CornerRadius = UDim.new(0.5, 0) }, ring)
		create("UIStroke", { Color = NEON_DIM, Thickness = 2 }, ring)
	end
	-- Cruz
	create("Frame", { Size = UDim2.new(1, 0, 0, 1), Position = UDim2.fromScale(0, 0.5),
		BackgroundColor3 = NEON_DIM, BorderSizePixel = 0 }, scope)
	create("Frame", { Size = UDim2.new(0, 1, 1, 0), Position = UDim2.fromScale(0.5, 0),
		BackgroundColor3 = NEON_DIM, BorderSizePixel = 0 }, scope)

	-- Linha de varredura (gira em torno do centro do scope)
	local sweep = create("Frame", {
		Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ZIndex = 2,
	}, scope)
	create("Frame", {
		AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromScale(0.5, 0),
		Size = UDim2.new(0, 3, 0.5, 0), BackgroundColor3 = NEON,
		BackgroundTransparency = 0.1, BorderSizePixel = 0, ZIndex = 2,
	}, sweep)

	-- Tu (centro)
	local me = create("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(10, 10), BackgroundColor3 = Color3.new(1, 1, 1),
		BorderSizePixel = 0, ZIndex = 4,
	}, scope)
	create("UICorner", { CornerRadius = UDim.new(1, 0) }, me)

	-- Pool de blips reutilizáveis
	local blips = {}
	for i = 1, MAX_BLIPS do
		local b = create("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(12, 12),
			BorderSizePixel = 0, Visible = false, ZIndex = 3,
		}, scope)
		create("UICorner", { CornerRadius = UDim.new(1, 0) }, b)
		blips[i] = b
	end

	-- Coluna de texto
	local info = create("TextLabel", {
		Position = UDim2.fromOffset(R + 28, 14), Size = UDim2.fromOffset(150, R - 10),
		BackgroundTransparency = 1, Font = Enum.Font.Code, TextSize = 19,
		TextColor3 = NEON, TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top, TextWrapped = true, Text = "",
	}, root)

	-- API do display
	function d.SetSweep(angle) sweep.Rotation = angle end

	function d.Update(count, nearest, targets)
		-- targets = lista de { nx, ny, isEntity }
		for i = 1, MAX_BLIPS do
			local t, b = targets[i], blips[i]
			if t then
				b.Visible = true
				b.Position = UDim2.fromScale(t.nx, t.ny)
				b.BackgroundColor3 = t.isEntity and C_ENTITY or C_PLAYER
			else
				b.Visible = false
			end
		end
		local danger = nearest and nearest <= CONFIG.DANGER_DIST
		local col = danger and ALERT or NEON
		scopeStroke.Color = col
		info.TextColor3 = col
		info.Text = string.format("RADAR ATIVO\n\nALVOS: %d\nMAIS PERTO:\n%s\n\nESTADO:\n%s",
			count,
			nearest and (string.format("%d m", nearest)) or "--",
			danger and "!! PERIGO !!" or (count > 0 and "ALERTA" or "LIMPO"))
	end

	return d
end

------------------------------------------------------------
-- 4) RADAR: CONSOLA 3D
------------------------------------------------------------
local function destroyConsole()
	if radar.model then radar.model:Destroy() end
	radar.model, radar.gui, radar.cf, radar.display = nil, nil, nil, nil
end

local function placeConsole()
	local char = lp.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if not hrp then return end
	destroyConsole()

	-- Posição à frente do jogador, assente no chão (raycast)
	local look = hrp.CFrame.LookVector
	local flat = Vector3.new(look.X, 0, look.Z)
	flat = (flat.Magnitude < 0.01) and Vector3.new(0, 0, -1) or flat.Unit
	local target = hrp.Position + flat * 6
	local rp = RaycastParams.new()
	rp.FilterType = Enum.RaycastFilterType.Exclude
	rp.FilterDescendantsInstances = { char }
	local hit = Workspace:Raycast(target + Vector3.new(0, 20, 0), Vector3.new(0, -60, 0), rp)
	local ground = hit and hit.Position or (target - Vector3.new(0, 3, 0))

	-- Consola virada para o jogador (a frente -Z olha para ele)
	local cf = CFrame.lookAt(ground, Vector3.new(hrp.Position.X, ground.Y, hrp.Position.Z))

	local model = Instance.new("Model")
	model.Name = "RadarConsole"

	local function part(name, size, offset, color, material)
		local p = Instance.new("Part")
		p.Name = name
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.CastShadow = false
		p.Size = size
		p.CFrame = cf * offset
		p.Color = color
		p.Material = material or Enum.Material.Metal
		p.Parent = model
		return p
	end

	part("Base", Vector3.new(4, 0.4, 2.6), CFrame.new(0, 0.2, 0), DARK)
	part("Haste", Vector3.new(0.8, 1.8, 0.8), CFrame.new(0, 1.3, 0.2), BLACK)
	part("Carcaca", Vector3.new(5.5, 3.9, 0.9), CFrame.new(0, 3.9, 0.45), DARK)
	-- Moldura neon fina e ecrã
	part("Moldura", Vector3.new(5.2, 3.6, 0.1), CFrame.new(0, 3.9, -0.02), NEON_DIM, Enum.Material.Neon)
	local screen = part("Tela", Vector3.new(5, 3.4, 0.1), CFrame.new(0, 3.9, -0.08),
		Color3.fromRGB(8, 40, 24), Enum.Material.SmoothPlastic)
	create("PointLight", { Color = NEON, Range = 12, Brightness = 0.8, Shadows = false }, screen)

	local sg = create("SurfaceGui", {
		Face = Enum.NormalId.Front,
		SizingMode = Enum.SurfaceGuiSizingMode.FixedSize,
		CanvasSize = Vector2.new(500, 340),
		LightInfluence = 0, Brightness = 1.5,
	}, screen)

	model.Parent = Workspace
	radar.model, radar.gui, radar.cf = model, sg, cf
	radar.display = buildDisplay(sg)
end

------------------------------------------------------------
-- 5) RADAR: LEITURA DE ALVOS + BIPE
------------------------------------------------------------
local targets = {}       -- reaproveitado a cada scan
local nearestDist = nil  -- alvo mais próximo (studs), nil = nenhum
local scanAcc, beepAcc, sweepAngle = 0, 0, 0

local function scan()
	local char = lp.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if not hrp then nearestDist = nil; return end

	local origin = hrp.Position
	local cframe = hrp.CFrame
	local R = CONFIG.RANGE
	local count, nearest = 0, nil
	table.clear(targets)

	-- Regista um alvo se estiver dentro do alcance
	local function consider(pos, isEntity)
		local dist = (pos - origin).Magnitude
		if dist > R then return end
		count += 1
		if not nearest or dist < nearest then nearest = dist end
		if #targets < MAX_BLIPS then
			-- posição relativa ao jogador: frente (-Z) = topo do ecrã
			local rel = cframe:PointToObjectSpace(pos)
			targets[#targets + 1] = {
				nx = 0.5 + rel.X / (2 * R),
				ny = 0.5 + rel.Z / (2 * R),
				isEntity = isEntity,
			}
		end
	end

	-- Outros jogadores
	for _, plr in ipairs(Players:GetPlayers()) do
		if plr ~= lp then
			local c = plr.Character
			local root = c and c:FindFirstChild("HumanoidRootPart")
			if root then consider(root.Position, false) end
		end
	end

	-- Entidades (NPCs) em cache
	if CONFIG.TRACK_NPCS then
		for hum in pairs(npcs) do
			local model = hum.Parent
			if not model or hum.Health <= 0 then
				-- ignora mortos/removidos
			elseif model ~= char and not Players:GetPlayerFromCharacter(model) then
				local root = model:FindFirstChild("HumanoidRootPart") or model.PrimaryPart
				if root then consider(root.Position, true) end
			end
		end
	end

	nearestDist = nearest

	-- Só desenha se o ecrã estiver visível e perto (poupa FPS)
	if radar.gui and radar.display then
		local near = radar.cf and (radar.cf.Position - origin).Magnitude <= CONFIG.SCREEN_CULL
		radar.gui.Enabled = near and true or false
		if near then
			radar.display.Update(count, nearest and math.floor(nearest + 0.5), targets)
		end
	end
end

-- Calcula o intervalo do bipe: perto = rápido, longe = lento
local function beepInterval(dist)
	local t = math.clamp(1 - dist / CONFIG.RANGE, 0, 1)
	return CONFIG.BEEP_FAR + (CONFIG.BEEP_NEAR - CONFIG.BEEP_FAR) * t, t
end

-- Som do bipe (criado uma única vez)
beepSound = create("Sound", {
	Name = "RadarBeep", SoundId = CONFIG.BEEP_ID,
	Volume = CONFIG.BEEP_VOLUME, RollOffMode = Enum.RollOffMode.Linear,
}, SoundService)

-- Loop único: varredura visual + bipe + scan periódico
track(RunService.Heartbeat:Connect(function(dt)
	-- Varredura (só se o ecrã estiver ativo)
	if radar.display and radar.gui and radar.gui.Enabled then
		sweepAngle = (sweepAngle + CONFIG.SWEEP_SPEED * dt) % 360
		radar.display.SetSweep(sweepAngle)
	end

	-- Leitura de alvos a 5 Hz
	scanAcc += dt
	if scanAcc >= CONFIG.SCAN_RATE then
		scanAcc = 0
		scan()
	end

	-- Bipe de proximidade
	if nearestDist and not muted then
		local interval, t = beepInterval(nearestDist)
		beepAcc += dt
		if beepAcc >= interval then
			beepAcc = 0
			beepSound.PlaybackSpeed = CONFIG.PITCH_FAR + (CONFIG.PITCH_NEAR - CONFIG.PITCH_FAR) * t
			beepSound:Play()
		end
	else
		beepAcc = 9 -- bipe imediato quando um alvo entra no alcance
	end
end))

------------------------------------------------------------
-- 6) PAINEL (compacto, dark mode, arrastável)
------------------------------------------------------------
local function destroyAll()
	alive = false
	for _, c in ipairs(connections) do pcall(function() c:Disconnect() end) end
	table.clear(connections)
	if flash.tool then flash.tool:Destroy() end
	destroyConsole()
	if beepSound then beepSound:Destroy() end
	if panelGui then panelGui:Destroy() end
	GENV.HorrorTacticalKit = nil
end
GENV.HorrorTacticalKit = { Destroy = destroyAll }

local function buildPanel()
	panelGui = create("ScreenGui", {
		Name = "HorrorTacticalKit_GUI", ResetOnSpawn = false,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	}, nil)
	panelGui.Parent = getGuiParent()

	local frame = create("Frame", {
		Size = UDim2.fromOffset(180, 0), AutomaticSize = Enum.AutomaticSize.Y,
		Position = UDim2.new(0, 16, 0.35, 0),
		BackgroundColor3 = Color3.fromRGB(20, 22, 26), BorderSizePixel = 0,
	}, panelGui)
	create("UICorner", { CornerRadius = UDim.new(0, 10) }, frame)
	create("UIStroke", { Color = YELLOW, Thickness = 1.2 }, frame)
	create("UIPadding", { PaddingTop = UDim.new(0, 8), PaddingBottom = UDim.new(0, 8),
		PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8) }, frame)
	create("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }, frame)

	-- Cabeçalho (arrastar) + fechar
	local header = create("Frame", { Size = UDim2.new(1, 0, 0, 22),
		BackgroundTransparency = 1, LayoutOrder = 0 }, frame)
	create("TextLabel", { Size = UDim2.new(1, -26, 1, 0), BackgroundTransparency = 1,
		Text = "☣ TACTICAL KIT", TextColor3 = YELLOW, Font = Enum.Font.GothamBold,
		TextSize = 12, TextXAlignment = Enum.TextXAlignment.Left }, header)
	local close = create("TextButton", { Size = UDim2.fromOffset(22, 22),
		Position = UDim2.new(1, -22, 0, 0), BackgroundColor3 = Color3.fromRGB(150, 40, 40),
		Text = "✕", TextColor3 = Color3.new(1, 1, 1), Font = Enum.Font.GothamBold,
		TextSize = 12 }, header)
	create("UICorner", { CornerRadius = UDim.new(0, 6) }, close)
	track(close.Activated:Connect(destroyAll))

	local function makeButton(text, order, onClick)
		local b = create("TextButton", { Size = UDim2.new(1, 0, 0, 30),
			BackgroundColor3 = Color3.fromRGB(42, 42, 48), Text = text,
			TextColor3 = Color3.new(1, 1, 1), Font = Enum.Font.GothamBold,
			TextSize = 12, LayoutOrder = order, AutoButtonColor = true }, frame)
		create("UICorner", { CornerRadius = UDim.new(0, 8) }, b)
		track(b.Activated:Connect(function() onClick(b) end))
		return b
	end

	makeButton("🔦 Lanterna On/Off [F]", 1, toggleFlash)
	makeButton("📡 Criar/Mover Radar", 2, placeConsole)
	makeButton("🔊 Bipe: ON", 3, function(b)
		muted = not muted
		b.Text = muted and "🔇 Bipe: OFF" or "🔊 Bipe: ON"
	end)
	makeButton("🗑 Remover Radar", 4, destroyConsole)

	-- Arrastar com rato ou toque
	local dragging, dragStart, startPos
	track(header.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch then
			dragging, dragStart, startPos = true, input.Position, frame.Position
			local conn
			conn = input.Changed:Connect(function()
				if input.UserInputState == Enum.UserInputState.End then
					dragging = false
					conn:Disconnect()
				end
			end)
		end
	end))
	track(UIS.InputChanged:Connect(function(input)
		if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement
			or input.UserInputType == Enum.UserInputType.Touch) then
			local delta = input.Position - dragStart
			frame.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X,
				startPos.Y.Scale, startPos.Y.Offset + delta.Y)
		end
	end))
end

------------------------------------------------------------
-- 7) ENTRADA, RESPAWN E ARRANQUE
------------------------------------------------------------
-- Tecla de atalho da lanterna
track(UIS.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed or not alive then return end
	if input.KeyCode == CONFIG.FLASH_KEY then toggleFlash() end
end))

-- Ao respawnar a mochila é limpa: recriamos a lanterna
track(lp.CharacterAdded:Connect(function(char)
	if not alive then return end
	char:WaitForChild("Humanoid", 10)
	task.wait(0.5)
	if alive then giveFlashlight() end
end))

-- Início
buildPanel()
giveFlashlight()
placeConsole()
