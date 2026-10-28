--[[
    ================================================================
    LANCHA TÁTICA  |  Luau  |  Roblox Studio / Delta Executor
    ================================================================
    Gera uma lancha 3D 100% procedural (sem assets externos), com:
      1) Casco em V, consola, bancos e motor de popa
      2) Flutuação por pontos (raycast à água do Terrain + ondas)
      3) Condução progressiva (teclado + botões touch)
      4) Rasto de espuma/água na popa
      5) HUD tático (velocidade, motor, combustível)

    CONTROLOS (PC)
      W / ↑  acelerar          S / ↓  travar / marcha-atrás
      A / ←  esquerda          D / →  direita
      ESPAÇO travão            E      ligar/desligar motor
      F      entrar/sair       R      reabastecer

    CONTROLOS (MOBILE)
      Botões ◀ ▶ (esquerda) e ▲ ▼ (direita) + botões do HUD.

    USO COM LOADSTRING:
      loadstring(game:HttpGet("https://raw.githubusercontent.com/TEU_USER/TEU_REPO/main/lancha_tatica.lua"))()

    NOTA: corre do lado do cliente (LocalScript / executor), por isso
    a lancha só é visível para ti.
    ================================================================
]]

-- ================================================================
-- 0. SERVIÇOS E LIMPEZA DE EXECUÇÕES ANTERIORES
-- ================================================================
local Players          = game:GetService("Players")
local RunService       = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace        = game:GetService("Workspace")

local player = Players.LocalPlayer
if not player then
	warn("[LanchaTática] Precisa de correr no cliente (LocalScript / executor).")
	return
end

-- Se o script for executado duas vezes, remove a instância anterior
local env = (getgenv and getgenv()) or _G
if env.TacticalBoat and env.TacticalBoat.Destroy then
	pcall(env.TacticalBoat.Destroy)
end

-- ================================================================
-- 1. CONFIGURAÇÃO (ajusta aqui o comportamento da lancha)
-- ================================================================
local CONFIG = {
	-- Spawn
	SPAWN_DISTANCE = 18,        -- distância à frente do jogador
	-- Flutuação
	DRAFT          = 1.5,       -- calado: altura da água acima da quilha em repouso
	WAVES          = true,      -- simula ondas por cima do nível da água
	WAVE_HEIGHT    = 0.45,      -- amplitude das ondas (studs)
	HEAVE_DAMPING  = 11,        -- amortecimento vertical (maior = menos saltitar)
	WATER_SCAN_UP  = 25,        -- raycast: altura acima do ponto
	WATER_SCAN_DOWN= 60,        -- raycast: profundidade máxima
	VIRTUAL_WATER_DEPTH = 3,    -- se não houver água, cria um "lago" virtual
	-- Propulsão
	MAX_ACCEL         = 30,     -- aceleração máx. à frente (studs/s²)
	MAX_REVERSE_ACCEL = 11,     -- aceleração máx. marcha-atrás
	DRAG_FORWARD      = 0.40,   -- resistência frontal (velocidade máx ≈ ACCEL/DRAG ≈ 75 studs/s)
	DRAG_LATERAL      = 3.5,    -- resistência lateral (grip da quilha)
	BRAKE_MULT        = 3,      -- multiplicador do travão
	THROTTLE_RISE     = 0.55,   -- rapidez com que o acelerador sobe (por seg)
	THROTTLE_FALL     = 0.90,   -- rapidez com que o acelerador desce
	-- Direção
	MAX_TURN_RATE     = 1.25,   -- rad/s máximos de viragem
	STEER_FULL_SPEED  = 20,     -- velocidade a partir da qual a viragem é total
	STEER_RATE        = 3.2,    -- suavização do leme
	YAW_GAIN          = 70,     -- força de resposta da guinada
	-- Estabilidade (anti-capotamento)
	ROLL_K  = 55,  ROLL_D  = 24,
	PITCH_K = 80,  PITCH_D = 70,
	-- Combustível (% por segundo)
	FUEL_IDLE = 0.03,
	FUEL_LOAD = 0.50,
	AUTO_START_ENGINE = true,
}

-- Conversões: 1 stud ≈ 0.28 m
local STUD_TO_KNOTS = 0.28 * 1.94384
local STUD_TO_KMH   = 0.28 * 3.6

-- ================================================================
-- 2. UTILITÁRIOS
-- ================================================================
local connections = {}
local function track(conn) connections[#connections + 1] = conn; return conn end

local function approach(current, target, maxDelta)
	if current < target then return math.min(current + maxDelta, target) end
	return math.max(current - maxDelta, target)
end

local function new(class, props, parent)
	local o = Instance.new(class)
	for k, v in pairs(props) do o[k] = v end
	o.Parent = parent
	return o
end

local function getCharParts()
	local char = player.Character
	if not char then return end
	local hum = char:FindFirstChildOfClass("Humanoid")
	local hrp = char:FindFirstChild("HumanoidRootPart")
	if hum and hrp then return char, hum, hrp end
end

-- ================================================================
-- 3. SISTEMA DE ÁGUA
-- ================================================================
-- Raycast só contra o Terrain, com IgnoreWater = false para "ver" a água
local waterParams = RaycastParams.new()
waterParams.FilterType = Enum.RaycastFilterType.Include
waterParams.FilterDescendantsInstances = { Workspace.Terrain }
waterParams.IgnoreWater = false

local useTerrainWater = false   -- true = usa água do Terrain
local baseLevel       = 0       -- nível da água virtual
local waveScale       = 1
local virtualWater    = nil

-- Ondas procedurais (soma de 3 senos) -> valor entre -A e +A
local function waveOffset(x, z, t)
	if not CONFIG.WAVES then return 0 end
	local s = math.sin(x * 0.11 + t * 1.3)
		+ 0.6 * math.sin(z * 0.17 - t * 1.7 + 1.3)
		+ 0.3 * math.sin((x + z) * 0.31 + t * 2.9)
	return (s / 1.9) * CONFIG.WAVE_HEIGHT * waveScale
end

-- Altura da superfície da água num ponto (nil = sem água)
local function getWaterHeight(x, y, z, t)
	if useTerrainWater then
		local r = Workspace:Raycast(
			Vector3.new(x, y + CONFIG.WATER_SCAN_UP, z),
			Vector3.new(0, -(CONFIG.WATER_SCAN_UP + CONFIG.WATER_SCAN_DOWN), 0),
			waterParams
		)
		if r and r.Material == Enum.Material.Water then
			return r.Position.Y + waveOffset(x, z, t)
		end
		return nil
	end
	return baseLevel + waveOffset(x, z, t)
end

-- Procura água de Terrain à volta do jogador (frente primeiro)
local function findTerrainWater(origin, forward)
	local distances = { CONFIG.SPAWN_DISTANCE, 35, 60, 100 }
	for _, d in ipairs(distances) do
		for k = 0, 7 do
			local ang = math.rad(k * 45)
			local dir = CFrame.fromAxisAngle(Vector3.yAxis, ang):VectorToWorldSpace(forward)
			local p = origin + dir * d
			local r = Workspace:Raycast(p + Vector3.new(0, 50, 0), Vector3.new(0, -300, 0), waterParams)
			if r and r.Material == Enum.Material.Water then
				return Vector3.new(p.X, r.Position.Y, p.Z), dir
			end
		end
	end
end

-- ================================================================
-- 4. CONSTRUÇÃO PROCEDURAL DA LANCHA
-- ================================================================
-- Convenção do referencial local: frente = -Z, popa = +Z, quilha em y = 0
local WHITE  = Color3.fromRGB(240, 242, 245)
local ORANGE = Color3.fromRGB(255, 120, 20)
local YELLOW = Color3.fromRGB(255, 196, 30)
local DARK   = Color3.fromRGB(28, 30, 34)
local GRAY   = Color3.fromRGB(70, 74, 82)
local GLASS  = Color3.fromRGB(140, 200, 235)
local PLASTIC, METAL = Enum.Material.SmoothPlastic, Enum.Material.Metal

local function buildBoat(rootCF)
	local model = Instance.new("Model")
	model.Name = "TacticalBoat"

	-- Casco físico (invisível): é a única peça com massa/colisão do casco.
	-- Tudo o resto é "Massless" e soldado a ele -> física leve e estável.
	local hull = new("Part", {
		Name = "Hull", Size = Vector3.new(5, 1.5, 15),
		CFrame = rootCF * CFrame.new(0, 0.75, 0),
		Transparency = 1, CanCollide = true, Anchored = false,
		CustomPhysicalProperties = PhysicalProperties.new(1, 0.1, 0, 1, 1),
	}, model)
	model.PrimaryPart = hull

	-- Helper: cria uma peça decorativa soldada ao casco
	local function part(name, size, cf, color, material, opts)
		local p = Instance.new((opts and opts.Class) or "Part")
		p.Name = name
		p.Size = size
		p.CFrame = rootCF * cf
		p.Color = color
		p.Material = material or PLASTIC
		p.Anchored = false
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.Massless = true
		p.TopSurface = Enum.SurfaceType.Smooth
		p.BottomSurface = Enum.SurfaceType.Smooth
		if opts then
			for k, v in pairs(opts) do
				if k ~= "Class" then p[k] = v end
			end
		end
		p.Parent = model
		local w = Instance.new("WeldConstraint")
		w.Part0 = hull
		w.Part1 = p
		w.Parent = p
		return p
	end

	-- Cria attachment no casco usando coordenadas do referencial da lancha
	local function attach(name, boatPos)
		return new("Attachment", { Name = name, Position = boatPos - Vector3.new(0, 0.75, 0) }, hull)
	end

	local rad = math.rad

	-- ---------- CASCO EM V ----------
	local theta  = math.atan2(2.2, 3)                 -- ângulo do V (~36°)
	local panelW = math.sqrt(3 * 3 + 2.2 * 2.2)
	for _, s in ipairs({ 1, -1 }) do
		-- painéis inclinados que formam o V
		part("VPanel", Vector3.new(panelW, 0.4, 13),
			CFrame.new(s * 1.5, 1.1, 1) * CFrame.Angles(0, 0, s * theta), WHITE)
		-- paredes laterais (borda do casco) + faixa laranja tática
		part("SideWall", Vector3.new(0.4, 1.2, 11), CFrame.new(s * 3, 2.8, 1.5), WHITE, PLASTIC, { CanCollide = true })
		part("SideStripe", Vector3.new(0.46, 0.3, 11), CFrame.new(s * 3, 2.35, 1.5), ORANGE)

		-- proa: duas paredes que convergem num bico
		local a   = Vector3.new(s * 3, 2.8, -4)
		local b   = Vector3.new(0, 2.8, -9)
		local mid = (a + b) / 2
		local len = (b - a).Magnitude
		local dir = (b - a).Unit
		part("BowWall", Vector3.new(0.4, 1.2, len), CFrame.lookAt(mid, b), WHITE, PLASTIC, { CanCollide = true })
		local lowA, lowB = a - Vector3.new(0, 0.45, 0), b - Vector3.new(0, 0.45, 0)
		part("BowStripe", Vector3.new(0.46, 0.3, len), CFrame.lookAt((lowA + lowB) / 2, lowB), ORANGE)
		-- deck da proa (placa inclinada para dentro)
		local perp   = Vector3.new(-dir.Z, 0, dir.X)
		local inward = -s * perp
		local dpos   = Vector3.new(mid.X, 2.2, mid.Z) + inward * 1.2
		part("BowDeck", Vector3.new(2.4, 0.3, len), CFrame.lookAt(dpos, dpos + dir), WHITE)

		-- luzes de navegação (vermelha à esquerda, verde à direita)
		part("NavLight", Vector3.new(0.35, 0.35, 0.35), CFrame.new(s * 3, 3.55, -4),
			s == 1 and Color3.fromRGB(40, 255, 90) or Color3.fromRGB(255, 40, 40),
			Enum.Material.Neon, { Shape = Enum.PartType.Ball })
	end
	part("Keel", Vector3.new(0.5, 0.4, 13), CFrame.new(0, 0.1, 1), DARK)
	part("Prow", Vector3.new(3, 0.4, 5.2), CFrame.new(0, 1.5, -6.4) * CFrame.Angles(rad(18), 0, 0), WHITE)

	-- ---------- DECK E ESPELHO DE POPA ----------
	part("DeckFloor", Vector3.new(5.6, 0.25, 11.5), CFrame.new(0, 2.2, 1.4), DARK, Enum.Material.DiamondPlate, { CanCollide = true })
	part("Transom", Vector3.new(6.4, 3, 0.4), CFrame.new(0, 1.8, 7.3), WHITE, PLASTIC, { CanCollide = true })
	part("TransomStripe", Vector3.new(6.4, 0.25, 0.46), CFrame.new(0, 3.2, 7.3), ORANGE)

	-- ---------- CONSOLA DE CONDUÇÃO ----------
	part("Console", Vector3.new(3.4, 1.5, 2.4), CFrame.new(0, 3, -1.4), WHITE, PLASTIC, { CanCollide = true })
	part("Dash", Vector3.new(3.4, 0.2, 2.6), CFrame.new(0, 3.85, -1.4), DARK)
	part("Screen", Vector3.new(1.2, 0.06, 0.8), CFrame.new(-0.6, 3.97, -1.7), Color3.fromRGB(30, 200, 150), Enum.Material.Neon)
	part("Gauge", Vector3.new(0.7, 0.06, 0.7), CFrame.new(0.8, 3.97, -1.7), ORANGE, Enum.Material.Neon)
	part("WheelColumn", Vector3.new(0.2, 0.2, 1), CFrame.new(0, 4.05, -0.95), DARK)
	part("Wheel", Vector3.new(0.12, 1, 1), CFrame.new(0, 4.4, -0.55) * CFrame.Angles(0, rad(90), 0) * CFrame.Angles(0, 0, rad(-30)),
		DARK, PLASTIC, { Shape = Enum.PartType.Cylinder })
	-- para-brisas
	local wsRot = CFrame.Angles(rad(18), 0, 0)
	part("Windshield", Vector3.new(3.2, 1.5, 0.1), CFrame.new(0, 4.75, -2.45) * wsRot, GLASS, Enum.Material.Glass, { Transparency = 0.5 })
	for _, s in ipairs({ 1, -1 }) do
		part("WindshieldPost", Vector3.new(0.12, 1.6, 0.12), CFrame.new(s * 1.6, 4.75, -2.45) * wsRot, ORANGE)
	end
	part("WindshieldTop", Vector3.new(3.4, 0.15, 0.2), CFrame.new(0, 5.5, -2.3), ORANGE)
	-- mastro com radar
	part("Mast", Vector3.new(0.12, 3, 0.12), CFrame.new(1.2, 5, -1.2), DARK)
	part("Radar", Vector3.new(1.4, 0.12, 0.3), CFrame.new(1.2, 6.55, -1.2), GRAY, METAL)
	part("MastTip", Vector3.new(0.2, 0.2, 0.2), CFrame.new(1.2, 6.7, -1.2), Color3.fromRGB(255, 40, 40), Enum.Material.Neon, { Shape = Enum.PartType.Ball })

	-- ---------- ASSENTOS ----------
	part("SeatBase", Vector3.new(1.2, 0.8, 1.2), CFrame.new(0, 2.73, 1.2), DARK)
	local seat = part("DriverSeat", Vector3.new(2, 0.45, 2), CFrame.new(0, 3.35, 1.2), ORANGE, Enum.Material.Fabric, { Class = "Seat" })
	part("SeatBack", Vector3.new(2, 1.5, 0.35), CFrame.new(0, 4.3, 2.25), GRAY, Enum.Material.Fabric)
	part("BenchBase", Vector3.new(5, 0.5, 1.5), CFrame.new(0, 2.8, 4.2), DARK)
	part("BenchCushion", Vector3.new(5, 0.25, 1.4), CFrame.new(0, 3.2, 4.2), ORANGE, Enum.Material.Fabric)
	part("BenchBack", Vector3.new(5, 1.4, 0.3), CFrame.new(0, 3.8, 5.15), GRAY, Enum.Material.Fabric)

	-- ---------- MOTOR DE POPA ----------
	part("MotorCowl", Vector3.new(1.5, 1.3, 1.8), CFrame.new(0, 3.4, 8.5), ORANGE)
	part("MotorLeg", Vector3.new(0.8, 3.4, 1.1), CFrame.new(0, 1.1, 8.6), DARK)
	part("GearCase", Vector3.new(1.8, 0.7, 0.7), CFrame.new(0, -0.5, 8.7) * CFrame.Angles(0, rad(90), 0), DARK, PLASTIC, { Shape = Enum.PartType.Cylinder })
	part("Propeller", Vector3.new(0.1, 1.2, 1.2), CFrame.new(0, -0.5, 9.7) * CFrame.Angles(0, rad(90), 0), GRAY, METAL, { Shape = Enum.PartType.Cylinder })

	-- ---------- FORÇAS (flutuação + propulsão + estabilidade) ----------
	-- 6 pontos de flutuação na quilha: proa, meio (E/D) e popa (E/D)
	local floatDefs = {
		Vector3.new(0, 0, -6.5),
		Vector3.new(-2.4, 0, 0), Vector3.new(2.4, 0, 0),
		Vector3.new(-2.4, 0, 5.5), Vector3.new(2.4, 0, 5.5),
		Vector3.new(0, 0, -2.5),
	}
	local floatPoints = {}
	for i, pos in ipairs(floatDefs) do
		local at = attach("Float" .. i, pos)
		local vf = new("VectorForce", {
			Attachment0 = at, RelativeTo = Enum.ActuatorRelativeTo.World,
			ApplyAtCenterOfMass = false, Force = Vector3.zero,
		}, hull)
		floatPoints[i] = { offset = at.Position, force = vf }
	end

	local centerAtt = new("Attachment", { Name = "Center" }, hull)
	local moveForce = new("VectorForce", {
		Attachment0 = centerAtt, RelativeTo = Enum.ActuatorRelativeTo.World,
		ApplyAtCenterOfMass = true, Force = Vector3.zero,
	}, hull)
	local torque = new("Torque", {
		Attachment0 = centerAtt, RelativeTo = Enum.ActuatorRelativeTo.World, Torque = Vector3.zero,
	}, hull)

	-- ---------- EFEITOS DE POPA ----------
	local sprayAtt = attach("SprayAtt", Vector3.new(0, 1.2, 9.4))
	local foam = new("ParticleEmitter", {
		Texture = "rbxasset://textures/particles/smoke_main.dds",
		Color = ColorSequence.new(Color3.new(1, 1, 1)),
		Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.35), NumberSequenceKeypoint.new(1, 1) }),
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.2), NumberSequenceKeypoint.new(1, 4) }),
		Lifetime = NumberRange.new(0.8, 1.4), Speed = NumberRange.new(3, 8),
		SpreadAngle = Vector2.new(25, 25), EmissionDirection = Enum.NormalId.Back,
		Acceleration = Vector3.new(0, -6, 0), Rotation = NumberRange.new(0, 360),
		LockedToPart = false, Rate = 0,
	}, sprayAtt)
	local spray = new("ParticleEmitter", {
		Texture = "rbxasset://textures/particles/sparkles_main.dds",
		Color = ColorSequence.new(Color3.fromRGB(200, 235, 255)),
		Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(1, 1) }),
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.5), NumberSequenceKeypoint.new(1, 0.1) }),
		Lifetime = NumberRange.new(0.5, 0.9), Speed = NumberRange.new(10, 20),
		SpreadAngle = Vector2.new(35, 35), EmissionDirection = Enum.NormalId.Top,
		Acceleration = Vector3.new(0, -50, 0), LockedToPart = false, Rate = 0,
	}, sprayAtt)

	-- rasto de espuma: faixa entre dois attachments à linha de água
	local tA = attach("TrailL", Vector3.new(-1.4, 1.4, 7.3))
	local tB = attach("TrailR", Vector3.new(1.4, 1.4, 7.3))
	local trail = new("Trail", {
		Attachment0 = tA, Attachment1 = tB, Lifetime = 1.6, MinLength = 0.1,
		FaceCamera = false, LightEmission = 0.2, Enabled = false,
		Color = ColorSequence.new(Color3.new(1, 1, 1)),
		Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.3), NumberSequenceKeypoint.new(1, 1) }),
	}, hull)

	model.Parent = Workspace
	return {
		model = model, hull = hull, seat = seat,
		floatPoints = floatPoints, moveForce = moveForce, torque = torque,
		foam = foam, spray = spray, trail = trail,
	}
end

-- ================================================================
-- 5. SPAWN: encontra água (ou cria um lago virtual) e gera a lancha
-- ================================================================
local char0, hum0, hrp0 = getCharParts()
if not char0 then
	char0 = player.CharacterAdded:Wait()
	char0, hum0, hrp0 = getCharParts()
end

local look    = hrp0.CFrame.LookVector
local forward = Vector3.new(look.X, 0, look.Z).Unit
local spawnPos, spawnDir

local wPos, wDir = findTerrainWater(hrp0.Position, forward)
if wPos then
	useTerrainWater = true
	spawnPos, spawnDir = Vector3.new(wPos.X, wPos.Y - CONFIG.DRAFT, wPos.Z), wDir
else
	-- Sem água no mapa: cria um plano de água virtual
	local feetY = hrp0.Position.Y - (hum0.HipHeight + hrp0.Size.Y / 2)
	baseLevel = feetY + CONFIG.VIRTUAL_WATER_DEPTH
	waveScale = 0.4
	local p = hrp0.Position + forward * CONFIG.SPAWN_DISTANCE
	spawnPos, spawnDir = Vector3.new(p.X, baseLevel - CONFIG.DRAFT, p.Z), forward
	virtualWater = new("Part", {
		Name = "VirtualWater", Anchored = true, CanCollide = false, CanQuery = false, CanTouch = false,
		Size = Vector3.new(2048, 0.2, 2048), Position = Vector3.new(p.X, baseLevel - 0.1, p.Z),
		Color = Color3.fromRGB(40, 120, 190), Material = Enum.Material.Glass, Transparency = 0.4,
	}, Workspace)
end

local boat = buildBoat(CFrame.lookAt(spawnPos, spawnPos + spawnDir))
local hull, seat = boat.hull, boat.seat

-- ================================================================
-- 6. ESTADO, ENTRADA (TECLADO + TOUCH)
-- ================================================================
local state = {
	driving = false, engineOn = false, fuel = 100,
	throttle = 0, steer = 0, speed = 0,
}
local keysDown = {}
local held = { up = false, down = false, left = false, right = false }
local manualWeld, controlsModule

local K = Enum.KeyCode
local function readInput()
	local thr, str = 0, 0
	if keysDown[K.W] or keysDown[K.Up] or held.up then thr += 1 end
	if keysDown[K.S] or keysDown[K.Down] or held.down then thr -= 1 end
	if keysDown[K.D] or keysDown[K.Right] or held.right then str += 1 end
	if keysDown[K.A] or keysDown[K.Left] or held.left then str -= 1 end
	return thr, str, keysDown[K.Space] == true
end

-- Desativa/ativa os controlos normais do personagem enquanto se conduz
local function setControls(enabled)
	if not controlsModule then
		pcall(function()
			local pm = player:WaitForChild("PlayerScripts"):WaitForChild("PlayerModule", 3)
			controlsModule = require(pm):GetControls()
		end)
	end
	if controlsModule then
		pcall(function()
			if enabled then controlsModule:Enable() else controlsModule:Disable() end
		end)
	end
end

local function boardBoat()
	local char, hum, hrp = getCharParts()
	if not char or state.driving then return end
	char:PivotTo(seat.CFrame * CFrame.new(0, 3, 0))
	pcall(function() seat:Sit(hum) end)
	-- Fallback: se o Seat não prender o jogador (lancha só local), solda manualmente
	task.delay(0.35, function()
		if state.driving and hum.SeatPart ~= seat and not manualWeld then
			manualWeld = new("Weld", {
				Name = "DriverWeld", Part0 = seat, Part1 = hrp,
				C0 = CFrame.new(0, seat.Size.Y / 2 + hum.HipHeight + hrp.Size.Y / 2, 0),
			}, seat)
			hum.Sit = true
		end
	end)
	state.driving = true
	state.engineOn = CONFIG.AUTO_START_ENGINE and state.fuel > 0
	setControls(false)
end

local function exitBoat()
	if not state.driving then return end
	state.driving, state.engineOn = false, false
	if manualWeld then manualWeld:Destroy(); manualWeld = nil end
	local char, hum = getCharParts()
	if char and hum then
		hum.Sit = false
		char:PivotTo(seat.CFrame * CFrame.new(0, 3.2, 3.5)) -- deixa o jogador no deck
	end
	setControls(true)
end

local function toggleBoard()
	if state.driving then
		exitBoat()
	else
		local _, _, hrp = getCharParts()
		if hrp and (hrp.Position - seat.Position).Magnitude < 30 then boardBoat() end
	end
end

local function toggleEngine()
	if not state.driving then return end
	if state.engineOn then state.engineOn = false
	elseif state.fuel > 0 then state.engineOn = true end
end

local function refuel() state.fuel = 100 end

track(UserInputService.InputBegan:Connect(function(io, gp)
	if gp or io.UserInputType ~= Enum.UserInputType.Keyboard then return end
	keysDown[io.KeyCode] = true
	if io.KeyCode == K.E then toggleEngine()
	elseif io.KeyCode == K.F then toggleBoard()
	elseif io.KeyCode == K.R then refuel() end
end))
track(UserInputService.InputEnded:Connect(function(io)
	if io.UserInputType == Enum.UserInputType.Keyboard then keysDown[io.KeyCode] = nil end
end))

-- Se o personagem desaparecer (morte/reset), liberta o estado de condução
track(player.CharacterRemoving:Connect(function()
	state.driving, state.engineOn = false, false
	if manualWeld then manualWeld:Destroy(); manualWeld = nil end
	setControls(true)
end))

-- ================================================================
-- 7. HUD DE TELEMETRIA + BOTÕES TOUCH
-- ================================================================
local okHui, hui = pcall(function() return gethui and gethui() end)
local guiParent = (okHui and hui) or player:WaitForChild("PlayerGui")

local gui = new("ScreenGui", {
	Name = "TacticalBoatHUD", ResetOnSpawn = false, IgnoreGuiInset = true,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling, DisplayOrder = 50,
}, guiParent)

local function styleBox(frame, radius)
	new("UICorner", { CornerRadius = UDim.new(0, radius or 8) }, frame)
	new("UIStroke", { Color = ORANGE, Thickness = 1.5, Transparency = 0.25 }, frame)
end

local function label(parent, text, pos, size, textSize, color, font, align)
	return new("TextLabel", {
		BackgroundTransparency = 1, Text = text, Position = pos, Size = size,
		TextSize = textSize, TextColor3 = color or WHITE, Font = font or Enum.Font.GothamBold,
		TextXAlignment = align or Enum.TextXAlignment.Left,
	}, parent)
end

local panel = new("Frame", {
	Name = "Panel", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 10),
	Size = UDim2.fromOffset(290, 150), BackgroundColor3 = Color3.fromRGB(15, 18, 22), BackgroundTransparency = 0.15,
}, gui)
styleBox(panel, 8)
if UserInputService.TouchEnabled then new("UIScale", { Scale = 0.85 }, panel) end

label(panel, "◢ LANCHA TÁTICA · TELEMETRIA", UDim2.fromOffset(10, 6), UDim2.fromOffset(270, 16), 11, ORANGE)
local speedLbl  = label(panel, "0", UDim2.fromOffset(10, 22), UDim2.fromOffset(110, 44), 38, WHITE, Enum.Font.GothamBlack)
label(panel, "NÓS", UDim2.fromOffset(118, 40), UDim2.fromOffset(40, 20), 13, YELLOW)
local kmhLbl    = label(panel, "0 km/h", UDim2.fromOffset(10, 66), UDim2.fromOffset(150, 16), 12, Color3.fromRGB(170, 175, 185), Enum.Font.Gotham)
local engineDot = new("Frame", { Position = UDim2.fromOffset(170, 32), Size = UDim2.fromOffset(12, 12), BackgroundColor3 = Color3.fromRGB(220, 50, 50) }, panel)
new("UICorner", { CornerRadius = UDim.new(1, 0) }, engineDot)
local engineLbl = label(panel, "MOTOR: DESLIGADO", UDim2.fromOffset(188, 26), UDim2.fromOffset(98, 24), 11)
local throttleLbl = label(panel, "ACEL 0%", UDim2.fromOffset(170, 50), UDim2.fromOffset(116, 16), 12, Color3.fromRGB(170, 175, 185), Enum.Font.Gotham)
local fuelLbl   = label(panel, "COMBUSTÍVEL 100%", UDim2.fromOffset(10, 88), UDim2.fromOffset(270, 14), 11)
local fuelBack  = new("Frame", { Position = UDim2.fromOffset(10, 104), Size = UDim2.fromOffset(270, 10), BackgroundColor3 = Color3.fromRGB(40, 44, 52) }, panel)
new("UICorner", { CornerRadius = UDim.new(0, 4) }, fuelBack)
local fuelFill  = new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.fromRGB(70, 220, 90) }, fuelBack)
new("UICorner", { CornerRadius = UDim.new(0, 4) }, fuelFill)

local function hudButton(text, x, callback)
	local b = new("TextButton", {
		Text = text, Position = UDim2.fromOffset(x, 120), Size = UDim2.fromOffset(132, 24),
		BackgroundColor3 = Color3.fromRGB(40, 44, 52), TextColor3 = WHITE,
		Font = Enum.Font.GothamBold, TextSize = 12, AutoButtonColor = true,
	}, panel)
	new("UICorner", { CornerRadius = UDim.new(0, 6) }, b)
	b.Activated:Connect(callback)
	return b
end
local engineBtn = hudButton("MOTOR [E]", 10, toggleEngine)
local boardBtn  = hudButton("ENTRAR [F]", 148, toggleBoard)

-- Botões touch (só aparecem em dispositivos com ecrã tátil)
if UserInputService.TouchEnabled then
	local function holdButton(text, anchor, pos, size, key)
		local b = new("TextButton", {
			Text = text, AnchorPoint = anchor, Position = pos, Size = size,
			BackgroundColor3 = Color3.fromRGB(15, 18, 22), BackgroundTransparency = 0.3,
			TextColor3 = ORANGE, Font = Enum.Font.GothamBlack, TextSize = 30, AutoButtonColor = false,
		}, gui)
		styleBox(b, 14)
		local function isPress(io)
			return io.UserInputType == Enum.UserInputType.Touch or io.UserInputType == Enum.UserInputType.MouseButton1
		end
		b.InputBegan:Connect(function(io)
			if isPress(io) then
				held[key] = true
				b.BackgroundTransparency = 0
				local c; c = io.Changed:Connect(function()
					if io.UserInputState == Enum.UserInputState.End then
						held[key] = false; b.BackgroundTransparency = 0.3; c:Disconnect()
					end
				end)
			end
		end)
		b.InputEnded:Connect(function(io)
			if isPress(io) then held[key] = false; b.BackgroundTransparency = 0.3 end
		end)
	end
	holdButton("◀", Vector2.new(0, 1), UDim2.new(0, 16, 1, -16), UDim2.fromOffset(78, 78), "left")
	holdButton("▶", Vector2.new(0, 1), UDim2.new(0, 104, 1, -16), UDim2.fromOffset(78, 78), "right")
	holdButton("▲", Vector2.new(1, 1), UDim2.new(1, -16, 1, -100), UDim2.fromOffset(82, 82), "up")
	holdButton("▼", Vector2.new(1, 1), UDim2.new(1, -16, 1, -16), UDim2.fromOffset(82, 76), "down")
end

local function updateHUD()
	local studs = state.speed
	speedLbl.Text = tostring(math.floor(math.abs(studs) * STUD_TO_KNOTS + 0.5))
	kmhLbl.Text = string.format("%d km/h", math.floor(math.abs(studs) * STUD_TO_KMH + 0.5))
	throttleLbl.Text = string.format("ACEL %d%%", math.floor(state.throttle * 100 + 0.5))

	if state.engineOn then
		engineDot.BackgroundColor3 = Color3.fromRGB(70, 230, 100)
		engineLbl.Text = "MOTOR: LIGADO"
	else
		engineDot.BackgroundColor3 = Color3.fromRGB(220, 50, 50)
		engineLbl.Text = state.fuel <= 0 and "SEM COMBUSTÍVEL" or "MOTOR: DESLIGADO"
	end

	local f = math.clamp(state.fuel, 0, 100)
	fuelLbl.Text = string.format("COMBUSTÍVEL %d%%", math.floor(f + 0.5))
	fuelFill.Size = UDim2.fromScale(f / 100, 1)
	fuelFill.BackgroundColor3 = (f > 30 and Color3.fromRGB(70, 220, 90))
		or (f > 15 and ORANGE) or Color3.fromRGB(230, 50, 50)

	engineBtn.Text = state.engineOn and "DESLIGAR [E]" or "LIGAR [E]"
	boardBtn.Text = state.driving and "SAIR [F]" or "ENTRAR [F]"
end

-- ================================================================
-- 8. FÍSICA: flutuação, propulsão, direção e estabilidade
-- ================================================================
local function stepBoat(dt)
	local cf    = hull.CFrame
	local mass  = hull.AssemblyMass
	local g     = Workspace.Gravity
	local t     = os.clock()
	local N     = #boat.floatPoints

	-- ---- 8.1 FLUTUAÇÃO (um raycast por ponto) ----
	local submerged = 0
	for _, pt in ipairs(boat.floatPoints) do
		local wp = cf:PointToWorldSpace(pt.offset)
		local h  = getWaterHeight(wp.X, wp.Y, wp.Z, t)
		local f  = 0
		if h then
			local depth = h - wp.Y                       -- profundidade submersa do ponto
			if depth > 0 then
				submerged += 1
				depth = math.min(depth, CONFIG.DRAFT * 3)
				local vy = hull:GetVelocityAtPosition(wp).Y
				-- mola (empuxo proporcional à submersão) + amortecedor vertical
				f = (mass * g / N) * (depth / CONFIG.DRAFT) - (mass / N) * CONFIG.HEAVE_DAMPING * vy
				if f < 0 then f = 0 end
			end
		end
		pt.force.Force = Vector3.new(0, f, 0)
	end
	local inWater = submerged / N

	-- ---- 8.2 ENTRADAS E SUAVIZAÇÃO ----
	local inThr, inStr, brake = 0, 0, false
	if state.driving then inThr, inStr, brake = readInput() end
	if not state.engineOn then inThr = 0 end

	-- acelerador progressivo (sobe devagar, desce mais depressa)
	local rate = (math.abs(inThr) > math.abs(state.throttle)) and CONFIG.THROTTLE_RISE or CONFIG.THROTTLE_FALL
	state.throttle = approach(state.throttle, inThr, rate * dt)
	state.steer    = approach(state.steer, inStr, CONFIG.STEER_RATE * dt)

	-- ---- 8.3 PROPULSÃO E ARRASTO (referencial local) ----
	local vel    = hull.AssemblyLinearVelocity
	local vLocal = cf:VectorToObjectSpace(vel)
	local fwdSpeed = -vLocal.Z                           -- frente = -Z
	state.speed = Vector3.new(vel.X, 0, vel.Z).Magnitude * (fwdSpeed >= 0 and 1 or -1)

	local accel = state.throttle >= 0 and state.throttle * CONFIG.MAX_ACCEL
		or state.throttle * CONFIG.MAX_REVERSE_ACCEL
	local dragF = CONFIG.DRAG_FORWARD * (brake and CONFIG.BRAKE_MULT or 1)
	local localAcc = Vector3.new(
		-CONFIG.DRAG_LATERAL * vLocal.X,                 -- grip lateral
		0,
		-accel - dragF * vLocal.Z                        -- motor - arrasto
	) * inWater                                          -- fora de água: sem motor/arrasto
	boat.moveForce.Force = cf:VectorToWorldSpace(localAcc) * mass

	-- ---- 8.4 TORQUE: estabilidade + direção ----
	local w = cf:VectorToObjectSpace(hull.AssemblyAngularVelocity)

	-- erro de inclinação como vetor eixo*ângulo (funciona até 180°, impede capotar)
	local up    = cf.UpVector
	local cross = up:Cross(Vector3.yAxis)
	local err   = Vector3.zero
	if cross.Magnitude > 1e-4 then
		err = cross.Unit * math.acos(math.clamp(up.Y, -1, 1))
	elseif up.Y < 0 then
		err = cf.LookVector * math.pi
	end
	local eL = cf:VectorToObjectSpace(err)
	local tx = eL.X * CONFIG.PITCH_K - w.X * CONFIG.PITCH_D
	local tz = eL.Z * CONFIG.ROLL_K  - w.Z * CONFIG.ROLL_D

	-- viragem: velocidade angular alvo proporcional à velocidade da lancha
	local sf = math.clamp(math.abs(fwdSpeed) / CONFIG.STEER_FULL_SPEED, 0, 1)
	sf = math.max(sf, 0.2 * math.abs(state.throttle))
	local dirSign = fwdSpeed < -2 and -1 or 1            -- em marcha-atrás o leme inverte
	local targetYaw = -state.steer * CONFIG.MAX_TURN_RATE * sf * dirSign
	local ty = (targetYaw - w.Y) * CONFIG.YAW_GAIN * inWater

	boat.torque.Torque = cf:VectorToWorldSpace(Vector3.new(tx, ty, tz)) * mass

	-- ---- 8.5 COMBUSTÍVEL ----
	if state.engineOn then
		local use = CONFIG.FUEL_IDLE + CONFIG.FUEL_LOAD * math.abs(state.throttle)
		state.fuel = math.max(0, state.fuel - use * dt)
		if state.fuel <= 0 then state.engineOn = false end
	end

	-- ---- 8.6 EFEITOS VISUAIS DE POPA ----
	local sp = math.abs(state.speed)
	boat.foam.Rate  = inWater * math.clamp(sp * 1.1 + math.abs(state.throttle) * 35, 0, 120)
	boat.spray.Rate = inWater * math.clamp((sp - 12) * 1.5 + math.abs(state.throttle) * 20, 0, 90)
	boat.trail.Enabled = inWater > 0.3 and sp > 6

	-- Água virtual acompanha a lancha (parece infinita)
	if virtualWater then
		virtualWater.Position = Vector3.new(cf.Position.X, baseLevel - 0.1, cf.Position.Z)
	end

	-- Se o jogador saltar do assento, sai da condução
	if state.driving and not manualWeld then
		local _, hum = getCharParts()
		if hum and hum.SeatPart ~= seat and os.clock() - (state.boardTime or 0) > 1 then
			if hum.SeatPart == nil and hum.Sit == false and state.seatedOnce then exitBoat() end
		end
		if hum and hum.SeatPart == seat then state.seatedOnce = true end
	end
end

-- ================================================================
-- 9. LOOP PRINCIPAL E LIMPEZA
-- ================================================================
local Destroy
local hudTimer = 0
track(RunService.Heartbeat:Connect(function(dt)
	if not hull.Parent then Destroy(); return end
	stepBoat(math.min(dt, 0.1))
	hudTimer += dt
	if hudTimer >= 0.08 then hudTimer = 0; updateHUD() end
end))

Destroy = function()
	for _, c in ipairs(connections) do pcall(function() c:Disconnect() end) end
	table.clear(connections)
	if manualWeld then pcall(function() manualWeld:Destroy() end) end
	setControls(true)
	if boat.model then boat.model:Destroy() end
	if gui then gui:Destroy() end
	if virtualWater then virtualWater:Destroy() end
	env.TacticalBoat = nil
end
env.TacticalBoat = { Destroy = Destroy, Boat = boat.model }

-- Entra automaticamente na lancha
state.boardTime = os.clock()
boardBoat()
updateHUD()
print("[LanchaTática] Pronta! W/A/S/D conduzir · E motor · F entrar/sair · R reabastecer")
