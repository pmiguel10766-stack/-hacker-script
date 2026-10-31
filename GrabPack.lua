--[[
	=====================================================================
	 GrabPack_Definitivo.lua
	 GrabPack (Capítulos 1, 2, 3 + Protótipos) em Luau para Roblox
	 Feito para executores (Delta) - roda 100% no cliente (LocalPlayer)

	 USO:
	   loadstring(game:HttpGet("https://raw.githubusercontent.com/SEU_USER/SEU_REPO/main/GrabPack_Definitivo.lua"))()

	 CONTROLES (PC):
	   Botão esquerdo do mouse / Q  -> dispara mão ESQUERDA (segure para manter)
	   E                            -> dispara mão DIREITA   (segure para manter)
	   F  -> equipar / guardar      T -> alterna lado selecionado no menu
	   1-8 -> equipa a mão escolhida no lado selecionado
	   M  -> liga/desliga som
	 MOBILE: botões "E" e "D" na tela + menu GRABPACK no canto superior esquerdo.
	=====================================================================
]]

------------------------------------------------------------------------
-- 0. LIMPEZA de execução anterior (evita duplicar HUD/mochila)
------------------------------------------------------------------------
local env = (getgenv and getgenv()) or _G
if env.GrabPackDefinitivo then
	pcall(env.GrabPackDefinitivo.Destroy)
end

if not game:IsLoaded() then game.Loaded:Wait() end

------------------------------------------------------------------------
-- 1. SERVIÇOS
------------------------------------------------------------------------
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local CollectionService = game:GetService("CollectionService")
local Debris = game:GetService("Debris")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer

------------------------------------------------------------------------
-- 2. CONFIGURAÇÃO (ajuste aqui sem mexer no resto)
------------------------------------------------------------------------
local CONFIG = {
	-- Sons
	SoundOn = true,
	SoundLaunch = "rbxassetid://123573488983461", -- vai (disparo)
	SoundRetract = "rbxassetid://103751410300272", -- volta (retorno)
	SoundVolume = 0.6,
	KeySound = Enum.KeyCode.M,

	-- Cabo / disparo
	ProjectileSpeed = 260,
	RetractSpeed = 340,
	MinAttachTime = 0.35,

	-- Agarre (Azul / Vermelha / Omni)
	ZipSpeed = 75,
	ZipStopDistance = 5,
	MaxPullMass = 500,
	PullStrength = 6,
	PullMaxSpeed = 70,

	-- Verde (energia)
	ChargeMax = 100,
	ChargeRate = 60,
	TransferRate = 30,
	ChargeDecay = 3,
	PoweredDuration = 12,

	-- Roxa (Spring)
	SpringPower = 135,
	SpringSideBoost = 25,
	SpringMaxDistance = 40,
	SpringCooldown = 0.8,

	-- Laranja (sinalizadores)
	FlareSpeed = 110,
	FlareCooldown = 0.7,
	FlareLifetime = 35,
	MaxFlares = 8,
	LightRange = 48,

	-- Luzes táticas (Omni)
	TacticalLightLifetime = 25,
	MaxTacticalLights = 6,

	-- Magnética (protótipo)
	MagnetRadius = 22,
	MagnetMaxParts = 10,
	MagnetSpeed = 55,

	-- Pressão (protótipo)
	PressureHoldTime = 0.5,
	PressureImpulse = 70,
	MaxBreakParts = 60,

	-- Controles
	RightClickFires = false,
	KeyLeft = Enum.KeyCode.Q,
	KeyRight = Enum.KeyCode.E,
	KeyToggle = Enum.KeyCode.F,
	KeySide = Enum.KeyCode.T,
}

------------------------------------------------------------------------
-- 3. DEFINIÇÃO DAS MÃOS
------------------------------------------------------------------------
local HANDS = {
	{ id = "Blue",     name = "Azul",      color = Color3.fromRGB(0, 140, 255),   range = 90,  kind = "grab" },
	{ id = "Red",      name = "Vermelha",  color = Color3.fromRGB(255, 45, 45),   range = 90,  kind = "grab" },
	{ id = "Green",    name = "Verde",     color = Color3.fromRGB(60, 255, 90),   range = 70,  kind = "electric" },
	{ id = "Purple",   name = "Roxa",      color = Color3.fromRGB(175, 70, 255),  range = 80,  kind = "spring" },
	{ id = "Orange",   name = "Laranja",   color = Color3.fromRGB(255, 150, 30),  range = 0,   kind = "flare" },
	{ id = "Omni",     name = "Omni",      color = Color3.fromRGB(255, 255, 255), range = 100, kind = "omni" },
	{ id = "Magnetic", name = "Magnética", color = Color3.fromRGB(150, 160, 185), range = 70,  kind = "magnet" },
	{ id = "Pressure", name = "Pressão",   color = Color3.fromRGB(235, 195, 40),  range = 50,  kind = "pressure" },
}
local HANDS_BY_ID = {}
for _, h in ipairs(HANDS) do HANDS_BY_ID[h.id] = h end

local PATTERNS = {
	Electric = { "electric", "generator", "tesla", "battery", "spark", "fuse" },
	Panel = { "panel", "socket", "outlet", "receiver", "powerbox", "switchbox" },
	Spring = { "spring", "bounce", "trampoline" },
	Locked = { "locked", "door", "gate", "barricade", "vent", "grate" },
	Metal = { "metal", "steel", "iron" },
}
local METAL_MATS = {
	[Enum.Material.Metal] = true, [Enum.Material.CorrodedMetal] = true,
	[Enum.Material.DiamondPlate] = true, [Enum.Material.Foil] = true,
}
local CABLE_COLOR = Color3.fromRGB(30, 30, 34)

------------------------------------------------------------------------
-- 4. UTILITÁRIOS
------------------------------------------------------------------------
local conns = {}
local function connect(signal, fn)
	local c = signal:Connect(fn)
	table.insert(conns, c)
	return c
end

local function make(class, props, parent)
	local inst = Instance.new(class)
	for k, v in pairs(props or {}) do inst[k] = v end
	if parent then inst.Parent = parent end
	return inst
end

local function newPart(props, parent)
	local p = Instance.new("Part")
	p.Anchored = false
	p.CanCollide = false
	p.CanTouch = false
	p.CanQuery = false
	p.Massless = true
	p.CastShadow = false
	for k, v in pairs(props or {}) do p[k] = v end
	p.Parent = parent
	return p
end

local function weld(p0, p1, c0)
	return make("Weld", { Part0 = p0, Part1 = p1, C0 = c0 or CFrame.identity }, p1)
end

local function corner(inst, r)
	make("UICorner", { CornerRadius = UDim.new(0, r) }, inst)
end

local function rnd(a, b) return a + math.random() * (b - a) end

local fx = make("Folder", { Name = "GrabPackFX" }, Workspace)

------------------------------------------------------------------------
-- 4.1 SONS
------------------------------------------------------------------------
local sounds = {}
local function buildSounds()
	sounds.Launch = make("Sound", {
		Name = "GPLaunch", SoundId = CONFIG.SoundLaunch,
		Volume = CONFIG.SoundVolume, RollOffMode = Enum.RollOffMode.Linear,
	}, fx)
	sounds.Retract = make("Sound", {
		Name = "GPRetract", SoundId = CONFIG.SoundRetract,
		Volume = CONFIG.SoundVolume, RollOffMode = Enum.RollOffMode.Linear,
	}, fx)
end

local function playSound(name)
	if not CONFIG.SoundOn then return end
	local s = sounds[name]
	if not s then return end
	-- Toca do início mesmo se o som anterior ainda estiver rodando
	s.TimePosition = 0
	s:Play()
end

local function handCF(pos, dir)
	local up = (math.abs(dir.Y) > 0.99) and Vector3.xAxis or Vector3.yAxis
	return CFrame.lookAt(pos, pos + dir, up) * CFrame.Angles(math.rad(90), 0, 0)
end

local function findFlag(part, flag)
	local node = part
	for _ = 1, 4 do
		if not node or node == Workspace then return nil end
		local v = node:GetAttribute(flag)
		if v == false then return nil end
		if v == true or CollectionService:HasTag(node, flag) then return node end
		local pats = PATTERNS[flag]
		if pats then
			local lname = string.lower(node.Name)
			for _, pat in ipairs(pats) do
				if string.find(lname, pat, 1, true) then return node end
			end
		end
		node = node.Parent
	end
	return nil
end

local function isMetal(part)
	return METAL_MATS[part.Material] == true or findFlag(part, "Metal") ~= nil
end

local function isCharacterPart(part)
	local m = part:FindFirstAncestorOfClass("Model")
	return m ~= nil and m:FindFirstChildOfClass("Humanoid") ~= nil
end

local function canMovePart(part)
	return (not part.Anchored) and part.AssemblyMass <= CONFIG.MaxPullMass and not isCharacterPart(part)
end

------------------------------------------------------------------------
-- 5. ESTADO GLOBAL
------------------------------------------------------------------------
local pack = {
	equipped = false, wanted = false, building = false,
	char = nil, hrp = nil, hum = nil, model = nil, lv = nil,
	charge = 0, charging = false, lastSpring = 0, warned = false,
}

local function newSide(key, handId)
	return {
		key = key, handId = handId, state = "idle",
		dir = Vector3.zAxis, held = false, mode = nil, hit = nil,
		lastFlare = 0, releaseAt = 0, autoRelease = false,
		seed = math.random() * 10,
	}
end
local sides = { Left = newSide("Left", "Blue"), Right = newSide("Right", "Red") }
local sideList = { sides.Left, sides.Right }

local ui = { dirty = true, selectedSide = "Left", bars = {}, fire = {}, handButtons = {} }

local poweredMap = {}
local flares = {}
local tacticalLights = {}

local startRetract, cleanupSide, launchFlare, attachTo

------------------------------------------------------------------------
-- 6. RAYCAST E MIRA
------------------------------------------------------------------------
local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude
rayParams.IgnoreWater = true

local function refreshFilter()
	local list = { fx }
	if player.Character then table.insert(list, player.Character) end
	rayParams.FilterDescendantsInstances = list
end

local function castRay(origin, vec)
	local base = rayParams.FilterDescendantsInstances
	local filter = base
	local result
	for _ = 1, 4 do
		result = Workspace:Raycast(origin, vec, rayParams)
		if not result then break end
		local inst = result.Instance
		if inst.ClassName ~= "Terrain" and inst.Transparency >= 1 and not inst.CanCollide then
			filter = table.clone(filter)
			table.insert(filter, inst)
			rayParams.FilterDescendantsInstances = filter
			result = nil
		else
			break
		end
	end
	rayParams.FilterDescendantsInstances = base
	return result
end

local function getAimPoint(maxDist)
	local camera = Workspace.CurrentCamera
	local vp
	if UserInputService.TouchEnabled and not UserInputService.MouseEnabled then
		vp = camera.ViewportSize / 2
	else
		vp = UserInputService:GetMouseLocation()
	end
	local ray = camera:ViewportPointToRay(vp.X, vp.Y)
	local res = castRay(ray.Origin, ray.Direction * 500)
	return res and res.Position or (ray.Origin + ray.Direction * maxDist)
end

------------------------------------------------------------------------
-- 7. EFEITOS VISUAIS
------------------------------------------------------------------------
local function pulseRing(pos, color)
	local r = newPart({
		Shape = Enum.PartType.Ball, Size = Vector3.new(1, 1, 1), Color = color,
		Material = Enum.Material.Neon, Transparency = 0.3, Anchored = true, Position = pos,
	}, fx)
	TweenService:Create(r, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Size = Vector3.new(7, 7, 7), Transparency = 1 }):Play()
	Debris:AddItem(r, 0.4)
end

local function makeBolts(part, color, count)
	local center = make("Attachment", {}, part)
	local bolts = { items = {} }
	for _ = 1, count do
		local a = make("Attachment", {}, part)
		local b = make("Beam", {
			Attachment0 = center, Attachment1 = a, Width0 = 0.12, Width1 = 0.05,
			Segments = 6, LightEmission = 1, LightInfluence = 0, FaceCamera = true,
			Color = ColorSequence.new(color), Enabled = false,
		}, part)
		table.insert(bolts.items, { att = a, beam = b })
	end
	return bolts
end

local function setBoltColor(bolts, color)
	if not bolts then return end
	for _, it in ipairs(bolts.items) do it.beam.Color = ColorSequence.new(color) end
end

local function jitterBolts(bolts, enabled)
	if not bolts then return end
	for _, it in ipairs(bolts.items) do
		it.beam.Enabled = enabled
		if enabled then
			local v = Vector3.new(rnd(-1, 1), rnd(-1, 1), rnd(-1, 1)) + Vector3.new(0.01, 0, 0)
			it.att.Position = v.Unit * rnd(1.1, 2.4)
			it.beam.CurveSize0 = rnd(-1, 1)
			it.beam.CurveSize1 = rnd(-1, 1)
		end
	end
end

local function spawnTacticalLight(pos, color, life)
	local p = newPart({
		Shape = Enum.PartType.Ball, Size = Vector3.new(0.5, 0.5, 0.5), Color = color,
		Material = Enum.Material.Neon, Anchored = true, Position = pos,
	}, fx)
	local l = make("PointLight", { Range = CONFIG.LightRange, Brightness = 3, Color = color, Shadows = false }, p)
	table.insert(tacticalLights, p)
	while #tacticalLights > CONFIG.MaxTacticalLights do
		local old = table.remove(tacticalLights, 1)
		if old and old.Parent then old:Destroy() end
	end
	Debris:AddItem(p, life)
	task.delay(math.max(life - 3, 0), function()
		if l.Parent then TweenService:Create(l, TweenInfo.new(3), { Brightness = 0 }):Play() end
	end)
end

------------------------------------------------------------------------
-- 8. INTERAÇÃO COM O MUNDO
------------------------------------------------------------------------
local function triggerInteractives(part)
	local node = part
	for _ = 1, 3 do
		if not node or node == Workspace then break end
		for _, ch in ipairs(node:GetChildren()) do
			if ch:IsA("ClickDetector") and fireclickdetector then
				pcall(fireclickdetector, ch)
			elseif ch:IsA("ProximityPrompt") and fireproximityprompt then
				pcall(fireproximityprompt, ch)
			end
		end
		if node:GetAttribute("GrabButton") ~= nil and not node:GetAttribute("Pressed") then
			local n = node
			n:SetAttribute("Pressed", true)
			task.delay(0.6, function() if n.Parent then n:SetAttribute("Pressed", false) end end)
		end
		node = node.Parent
	end
end

local function triggerTouch(inst)
	if not firetouchinterest or not pack.hrp then return end
	local bp = inst:IsA("BasePart") and inst or inst:FindFirstChildWhichIsA("BasePart", true)
	if not bp then return end
	local hrp = pack.hrp
	task.spawn(function()
		pcall(function()
			firetouchinterest(hrp, bp, 0)
			task.wait()
			firetouchinterest(hrp, bp, 1)
		end)
	end)
end

local function markPowered(inst)
	if not poweredMap[inst] then
		inst:SetAttribute("Powered", true)
		triggerInteractives(inst:IsA("BasePart") and inst or (inst:FindFirstChildWhichIsA("BasePart", true) or inst))
		triggerTouch(inst)
	end
	poweredMap[inst] = os.clock() + CONFIG.PoweredDuration
end

local function expirePowered(now)
	for inst, exp in pairs(poweredMap) do
		if now > exp or not inst.Parent then
			if inst.Parent then inst:SetAttribute("Powered", false) end
			poweredMap[inst] = nil
		end
	end
end

------------------------------------------------------------------------
-- 9. COMPORTAMENTO DE CADA MÃO
------------------------------------------------------------------------
local function startGrab(side)
	local hit = side.hit
	triggerInteractives(hit.part)
	if isCharacterPart(hit.part) then return end
	if canMovePart(hit.part) then
		side.mode = "pullObject"
		side.pullObj = hit.part
	else
		side.mode = "zip"
	end
end

local function startElectric(side)
	local hit = side.hit
	local panel = findFlag(hit.part, "Panel")
	local src = findFlag(hit.part, "Electric")
	if panel and pack.charge > 0 then
		hit.panel = panel
		side.mode = "transfer"
		markPowered(panel)
	elseif src then
		side.mode = "charge"
	end
end

local function startSpring(side)
	local hit = side.hit
	local hrp = pack.hrp
	local now = os.clock()
	side.autoRelease = true
	side.releaseAt = now + 0.3
	if now - pack.lastSpring < CONFIG.SpringCooldown then return end
	if (hit.pos - hrp.Position).Magnitude > CONFIG.SpringMaxDistance then return end
	local marked = findFlag(hit.part, "Spring")
	if not (marked or hit.normal.Y > 0.6) then return end
	pack.lastSpring = now
	local vel = hrp.AssemblyLinearVelocity
	local pushH = Vector3.new(hit.normal.X, 0, hit.normal.Z) * CONFIG.SpringSideBoost
	pack.hum:ChangeState(Enum.HumanoidStateType.Freefall)
	hrp.AssemblyLinearVelocity = Vector3.new(vel.X * 0.5 + pushH.X, CONFIG.SpringPower, vel.Z * 0.5 + pushH.Z)
	pulseRing(hit.pos, HANDS_BY_ID.Purple.color)
end

local function startOmni(side)
	startGrab(side)
	local hit = side.hit
	local panel = findFlag(hit.part, "Panel")
	if panel then
		side.omniPanel = panel
		markPowered(panel)
	end
	spawnTacticalLight(hit.pos + hit.normal * 1.2, Color3.fromRGB(255, 255, 255), CONFIG.TacticalLightLifetime)
end

local function startMagnet(side)
	local hit = side.hit
	if isCharacterPart(hit.part) then return end
	if isMetal(hit.part) and not canMovePart(hit.part) then
		side.mode = "zip"
		return
	end
	local op = OverlapParams.new()
	op.FilterType = Enum.RaycastFilterType.Exclude
	local ex = { fx }
	if player.Character then table.insert(ex, player.Character) end
	op.FilterDescendantsInstances = ex
	local list, seen = {}, {}
	for _, p in ipairs(Workspace:GetPartBoundsInRadius(hit.pos, CONFIG.MagnetRadius, op)) do
		if #list >= CONFIG.MagnetMaxParts then break end
		if isMetal(p) and canMovePart(p) then
			local root = p.AssemblyRootPart or p
			if not seen[root] then
				seen[root] = true
				table.insert(list, root)
			end
		end
	end
	if #list > 0 then
		side.mode = "magnet"
		side.magParts = list
	end
end

local function startPressure(side)
	side.mode = "pressure"
	side.t0 = os.clock()
	side.pressDone = false
end

local function doPressure(side)
	side.pressDone = true
	local hit = side.hit
	if not hit or isCharacterPart(hit.part) then return end
	local away = hit.part.Position - pack.hrp.Position
	away = Vector3.new(away.X, 0.2, away.Z)
	local dirv = (away.Magnitude > 0.01) and away.Unit or Vector3.yAxis
	local target = findFlag(hit.part, "Locked")
	if target then
		triggerInteractives(hit.part)
		target:SetAttribute("Locked", false)
		target:SetAttribute("Broken", true)
		local parts = {}
		if target:IsA("BasePart") then
			parts[1] = target
		else
			for _, d in ipairs(target:GetDescendants()) do
				if d:IsA("BasePart") then
					table.insert(parts, d)
					if #parts >= CONFIG.MaxBreakParts then break end
				end
			end
		end
		for _, p in ipairs(parts) do
			p:BreakJoints()
			p.Anchored = false
			p:ApplyImpulse(dirv * p.Mass * CONFIG.PressureImpulse)
		end
	elseif canMovePart(hit.part) then
		hit.part:ApplyImpulse(dirv * hit.part.AssemblyMass * CONFIG.PressureImpulse * 0.6)
	end
	pulseRing(hit.pos, HANDS_BY_ID.Pressure.color)
end

function launchFlare(side, dir)
	side.lastFlare = os.clock()
	local hand = HANDS_BY_ID[side.handId]
	local origin = side.glove.Position + dir * 2.2
	local f = Instance.new("Part")
	f.Name = "GPFlare"
	f.Shape = Enum.PartType.Ball
	f.Size = Vector3.new(0.8, 0.8, 0.8)
	f.Material = Enum.Material.Neon
	f.Color = hand.color
	f.CanQuery = false
	f.CanTouch = false
	f.CastShadow = false
	f.CustomPhysicalProperties = PhysicalProperties.new(0.5, 0.8, 0.3, 1, 1)
	f.CFrame = CFrame.new(origin)
	f.Parent = fx
	f.AssemblyLinearVelocity = dir * CONFIG.FlareSpeed
	local l = make("PointLight", { Range = CONFIG.LightRange, Brightness = 5, Color = hand.color, Shadows = false }, f)
	make("ParticleEmitter", {
		Rate = 25, Lifetime = NumberRange.new(0.5, 0.9), Speed = NumberRange.new(2, 5),
		Color = ColorSequence.new(hand.color), LightEmission = 1,
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.9), NumberSequenceKeypoint.new(1, 0) }),
		Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(1, 1) }),
	}, f)
	table.insert(flares, f)
	while #flares > CONFIG.MaxFlares do
		local old = table.remove(flares, 1)
		if old and old.Parent then old:Destroy() end
	end
	Debris:AddItem(f, CONFIG.FlareLifetime)
	task.delay(math.max(CONFIG.FlareLifetime - 4, 0), function()
		if l.Parent then TweenService:Create(l, TweenInfo.new(4), { Brightness = 0 }):Play() end
	end)
	pulseRing(origin, hand.color)
end

------------------------------------------------------------------------
-- 10. CICLO DE VIDA DO DISPARO
------------------------------------------------------------------------
local function setGloveVisible(side, vis)
	if not side.glove then return end
	side.glove.Transparency = vis and 0 or 1
	side.ring.Transparency = vis and 0 or 1
end

local function spawnProjectile(side, hand, origin, dir)
	local proj, ring, att = nil, nil, nil
	proj = newPart({
		Name = "GPHand", Size = Vector3.new(1.1, 0.9, 1.1), Color = Color3.fromRGB(58, 60, 66),
		Material = Enum.Material.SmoothPlastic, Anchored = true, CFrame = handCF(origin, dir),
	}, fx)
	ring = newPart({
		Name = "Glow", Size = Vector3.new(1.16, 0.25, 1.16), Color = hand.color, Material = Enum.Material.Neon,
	}, proj)
	weld(proj, ring, CFrame.new(0, -0.35, 0))
	att = make("Attachment", { Name = "CableAtt", Position = Vector3.new(0, 0.3, 0) }, proj)
	side.proj, side.projRing, side.projAtt = proj, ring, att
	if hand.kind == "electric" or hand.kind == "omni" then
		side.projBolts = makeBolts(proj, hand.kind == "omni" and Color3.fromRGB(190, 230, 255) or hand.color, 3)
	end
	if hand.kind == "omni" then
		make("PointLight", { Range = 24, Brightness = 2, Color = Color3.new(1, 1, 1), Shadows = false }, proj)
	end
	side.cable.Attachment1 = att
	setGloveVisible(side, false)
end

function attachTo(side, res)
	local hand = HANDS_BY_ID[side.handId]
	local part = res.Instance
	side.state = "attached"
	side.hit = {
		part = part, pos = res.Position, normal = res.Normal,
		lp = part.CFrame:PointToObjectSpace(res.Position),
	}
	side.releaseAt = os.clock() + CONFIG.MinAttachTime
	side.autoRelease = false
	side.mode = nil
	local k = hand.kind
	if k == "grab" then startGrab(side)
	elseif k == "electric" then startElectric(side)
	elseif k == "spring" then startSpring(side)
	elseif k == "omni" then startOmni(side)
	elseif k == "magnet" then startMagnet(side)
	elseif k == "pressure" then startPressure(side)
	end
	pulseRing(res.Position, hand.color)
end

function startRetract(side)
	if side.state == "idle" or side.state == "retracting" then return end
	side.state = "retracting"
	side.mode, side.pullObj, side.magParts, side.hit, side.omniPanel = nil, nil, nil, nil, nil
	playSound("Retract")
end

function cleanupSide(side)
	if side.proj then side.proj:Destroy() end
	side.proj, side.projRing, side.projAtt, side.projBolts = nil, nil, nil, nil
	side.state = "idle"
	side.mode, side.hit, side.pullObj, side.magParts, side.omniPanel = nil, nil, nil, nil, nil
	if side.glove and side.glove.Parent then
		setGloveVisible(side, true)
		if side.cable and side.gloveAtt then side.cable.Attachment1 = side.gloveAtt end
	end
end

local function pressFire(side)
	if not pack.equipped then return end
	side.held = true
	if side.state ~= "idle" then return end
	local hand = HANDS_BY_ID[side.handId]
	local origin = side.glove.Position
	local aim = getAimPoint(hand.range > 0 and hand.range or 150)
	local v = aim - origin
	if v.Magnitude < 0.1 then return end
	local dir = v.Unit
	if hand.kind == "flare" then
		if os.clock() - side.lastFlare >= CONFIG.FlareCooldown then launchFlare(side, dir) end
		return
	end
	side.dir = dir
	side.state = "flying"
	side.mode, side.hit = nil, nil
	spawnProjectile(side, hand, origin, dir)
	playSound("Launch")
end

local function releaseFire(side)
	side.held = false
end

------------------------------------------------------------------------
-- 11. LOOP PRINCIPAL
------------------------------------------------------------------------
local function updateCable(side, now)
	local hand = HANDS_BY_ID[side.handId]
	local cable = side.cable
	local idle = side.state == "idle"
	local endPos = idle and side.glove.Position or (side.proj and side.proj.Position or side.glove.Position)
	local len = (endPos - side.port.WorldPosition).Magnitude
	local sway = math.sin(now * 5 + side.seed * 6)
	local amp
	if idle then
		amp = 0.6
	else
		local tension = math.clamp(len / math.max(hand.range, 1), 0, 1)
		amp = math.clamp(len * 0.18, 0.3, 6) * (1 - tension)
	end
	cable.CurveSize0 = amp * sway
	cable.CurveSize1 = -amp * sway
	local lit = side.mode == "charge" or side.mode == "transfer" or side.omniPanel ~= nil
	if lit ~= side.cableLit then
		side.cableLit = lit
		cable.Color = ColorSequence.new(lit and hand.color or CABLE_COLOR)
		cable.LightEmission = lit and 1 or 0
	end
end

local function updateSide(side, dt, now, zips)
	local hand = HANDS_BY_ID[side.handId]
	local st = side.state

	if st == "idle" then
		if side.held and hand.kind == "flare" and now - side.lastFlare >= CONFIG.FlareCooldown then
			local origin = side.glove.Position
			local v = getAimPoint(150) - origin
			if v.Magnitude > 0.1 then launchFlare(side, v.Unit) end
		end

	elseif st == "flying" then
		local proj = side.proj
		if not (proj and proj.Parent) then cleanupSide(side) return end
		local pos = proj.Position
		local mv = side.dir * CONFIG.ProjectileSpeed * dt
		if (pos + mv - side.port.WorldPosition).Magnitude > hand.range then
			startRetract(side)
			return
		end
		local res = castRay(pos, mv + side.dir * 0.6)
		if res then
			proj.CFrame = handCF(res.Position, side.dir)
			attachTo(side, res)
		else
			proj.CFrame = handCF(pos + mv, side.dir)
		end

	elseif st == "attached" then
		local hit = side.hit
		local part = hit and hit.part
		if not (part and part.Parent and side.proj and side.proj.Parent) then startRetract(side) return end
		local world = part.CFrame:PointToWorldSpace(hit.lp)
		side.proj.CFrame = handCF(world, side.dir)
		if (world - side.port.WorldPosition).Magnitude > hand.range * 1.2 then startRetract(side) return end
		if (side.autoRelease or not side.held) and now >= side.releaseAt then startRetract(side) return end

		local mode = side.mode
		if mode == "zip" then
			table.insert(zips, world)
		elseif mode == "pullObject" then
			local obj = side.pullObj
			if obj and obj.Parent and not obj.Anchored then
				local goal = pack.hrp.Position + pack.hrp.CFrame.LookVector * 5 + Vector3.new(0, 1.5, 0)
				local to = goal - obj.Position
				local m = to.Magnitude
				if m > 4 then
					obj.AssemblyLinearVelocity = to.Unit * math.min(CONFIG.PullMaxSpeed, m * CONFIG.PullStrength)
				else
					obj.AssemblyLinearVelocity = Vector3.zero
				end
			else
				side.mode = nil
			end
		elseif mode == "magnet" then
			local goal = side.glove.Position + pack.hrp.CFrame.LookVector * 3
			for i = #side.magParts, 1, -1 do
				local p = side.magParts[i]
				if p.Parent and not p.Anchored then
					local to = goal - p.Position
					local m = to.Magnitude
					if m > 3 then
						p.AssemblyLinearVelocity = to.Unit * math.min(CONFIG.MagnetSpeed, m * 4 + 8)
					else
						p.AssemblyLinearVelocity = Vector3.zero
					end
				else
					table.remove(side.magParts, i)
				end
			end
		elseif mode == "charge" then
			pack.charging = true
			pack.charge = math.min(CONFIG.ChargeMax, pack.charge + CONFIG.ChargeRate * dt)
		elseif mode == "transfer" then
			local panel = hit.panel
			if pack.charge > 0 and panel and panel.Parent then
				pack.charge = math.max(0, pack.charge - CONFIG.TransferRate * dt)
				markPowered(panel)
			else
				side.mode = nil
			end
		elseif mode == "pressure" then
			if not side.pressDone and now - side.t0 >= CONFIG.PressureHoldTime then doPressure(side) end
		end
		if side.omniPanel then
			if side.omniPanel.Parent then markPowered(side.omniPanel) else side.omniPanel = nil end
		end

	elseif st == "retracting" then
		local proj = side.proj
		if not (proj and proj.Parent) then cleanupSide(side) return end
		local to = side.glove.Position - proj.Position
		local m = to.Magnitude
		local step = CONFIG.RetractSpeed * dt
		if m <= step + 0.8 then
			cleanupSide(side)
		else
			proj.CFrame = handCF(proj.Position + to.Unit * step, to.Unit)
		end
	end

	updateCable(side, now)
end

local function applyZip(zips)
	local lv = pack.lv
	if not lv then return end
	if #zips == 0 then
		if lv.Enabled then lv.Enabled = false end
		return
	end
	local hrp = pack.hrp
	local v = Vector3.zero
	for _, p in ipairs(zips) do
		local to = p - hrp.Position
		if to.Magnitude > CONFIG.ZipStopDistance then v += to.Unit end
	end
	if not lv.Enabled then
		lv.Enabled = true
		pack.hum:ChangeState(Enum.HumanoidStateType.Freefall)
	end
	lv.VectorVelocity = (v.Magnitude > 0.01) and (v.Unit * CONFIG.ZipSpeed) or Vector3.zero
end

local function updateVisuals(now)
	for _, side in ipairs(sideList) do
		local hand = HANDS_BY_ID[side.handId]
		local idle = side.state == "idle"
		local gloveOn, projOn = false, false
		if hand.kind == "electric" then
			local on = pack.charge > 2
			gloveOn, projOn = on and idle, on and not idle
		elseif hand.kind == "omni" then
			projOn = not idle
		end
		jitterBolts(side.gloveBolts, gloveOn)
		jitterBolts(side.projBolts, projOn)
		side.gloveLight.Brightness = (hand.kind == "electric") and (pack.charge / CONFIG.ChargeMax) * 2.5 or 0
		if hand.kind == "omni" then
			local c = Color3.fromHSV((now * 0.35) % 1, 0.65, 1)
			side.ring.Color = c
			if side.projRing then side.projRing.Color = c end
		end
	end
end

local visAcc, slowAcc = 0, 0
local function step(dt)
	if not pack.equipped then return end
	local hrp = pack.hrp
	if not (hrp and hrp.Parent and pack.model and pack.model.Parent) then return end
	local now = os.clock()

	pack.charging = false
	local zips = {}
	for _, side in ipairs(sideList) do updateSide(side, dt, now, zips) end
	applyZip(zips)

	if not pack.charging and pack.charge > 0 then
		pack.charge = math.max(0, pack.charge - CONFIG.ChargeDecay * dt)
	end

	visAcc += dt
	if visAcc >= 0.06 then visAcc = 0; updateVisuals(now) end
	slowAcc += dt
	if slowAcc >= 0.25 then slowAcc = 0; expirePowered(now) end
end

------------------------------------------------------------------------
-- 12. CONSTRUÇÃO PROCEDURAL 3D
------------------------------------------------------------------------
local function buildHandModel(color)
	local glove = newPart({
		Name = "GPGlove", Size = Vector3.new(1.1, 0.9, 1.1), Color = Color3.fromRGB(58, 60, 66),
		Material = Enum.Material.SmoothPlastic,
	})
	local ring = newPart({
		Name = "Glow", Size = Vector3.new(1.16, 0.25, 1.16), Color = color, Material = Enum.Material.Neon,
	}, glove)
	weld(glove, ring, CFrame.new(0, -0.35, 0))
	local att = make("Attachment", { Name = "CableAtt", Position = Vector3.new(0, 0.3, 0) }, glove)
	return glove, ring, att
end

local function applyHandVisual(side)
	local hand = HANDS_BY_ID[side.handId]
	if not (pack.equipped or pack.building) or not side.ring then return end
	side.ring.Color = hand.color
	side.gloveLight.Color = hand.color
	side.gloveLight.Brightness = 0
	setBoltColor(side.gloveBolts, hand.kind == "omni" and Color3.fromRGB(190, 230, 255) or hand.color)
	if side.status then side.status.Color = hand.color end
	side.cableLit = false
	side.cable.Color = ColorSequence.new(CABLE_COLOR)
	side.cable.LightEmission = 0
end

local function waitRig(char)
	local hum = char:WaitForChild("Humanoid", 10)
	local hrp = char:WaitForChild("HumanoidRootPart", 10)
	if not (hum and hrp) then return nil end
	local r15 = hum.RigType == Enum.HumanoidRigType.R15
	local torso = char:WaitForChild(r15 and "UpperTorso" or "Torso", 10)
	local lArm = char:WaitForChild(r15 and "LeftHand" or "Left Arm", 10)
	local rArm = char:WaitForChild(r15 and "RightHand" or "Right Arm", 10)
	if not (torso and lArm and rArm) then return nil end
	return { char = char, hum = hum, hrp = hrp, torso = torso, lArm = lArm, rArm = rArm, r15 = r15 }
end

local function unequipPack(keepWanted)
	for _, side in ipairs(sideList) do
		side.held = false
		if side.proj then side.proj:Destroy() end
		side.proj, side.projRing, side.projAtt, side.projBolts = nil, nil, nil, nil
		side.state = "idle"
		side.mode, side.hit, side.pullObj, side.magParts, side.omniPanel = nil, nil, nil, nil, nil
	end
	if pack.diedConn then pack.diedConn:Disconnect() pack.diedConn = nil end
	if pack.lv then pack.lv:Destroy() pack.lv = nil end
	if pack.model then pack.model:Destroy() pack.model = nil end
	pack.equipped = false
	pack.charge = 0
	if not keepWanted then pack.wanted = false end
	ui.dirty = true
end

local function equipPack()
	if pack.equipped or pack.building then return end
	pack.building = true
	pack.wanted = true

	local rig = waitRig(player.Character or player.CharacterAdded:Wait())
	if not rig then pack.building = false return end

	local model = make("Model", { Name = "GrabPackModel" }, rig.char)
	pack.char, pack.hrp, pack.hum, pack.model = rig.char, rig.hrp, rig.hum, model

	local body = newPart({
		Name = "GPBody", Size = Vector3.new(1.8, 2.1, 0.8), Color = Color3.fromRGB(48, 50, 56),
		Material = Enum.Material.Metal, CFrame = rig.torso.CFrame * CFrame.new(0, 0, 0.92),
	}, model)
	weld(rig.torso, body, CFrame.new(0, 0, 0.92))

	for _, x in ipairs({ -0.5, 0.5 }) do
		local tank = newPart({
			Name = "GPTank", Shape = Enum.PartType.Cylinder, Size = Vector3.new(1.6, 0.55, 0.55),
			Color = Color3.fromRGB(80, 84, 94), Material = Enum.Material.Metal,
		}, model)
		weld(body, tank, CFrame.new(x, -0.05, 0.55) * CFrame.Angles(0, 0, math.rad(90)))
	end

	local statusL = newPart({ Name = "GPStatusL", Size = Vector3.new(0.35, 0.35, 0.12), Material = Enum.Material.Neon }, model)
	weld(body, statusL, CFrame.new(-0.6, 0.85, -0.42))
	local statusR = newPart({ Name = "GPStatusR", Size = Vector3.new(0.35, 0.35, 0.12), Material = Enum.Material.Neon }, model)
	weld(body, statusR, CFrame.new(0.6, 0.85, -0.42))

	local portL = make("Attachment", { Name = "PortL", Position = Vector3.new(-0.9, 0.55, 0) }, body)
	local portR = make("Attachment", { Name = "PortR", Position = Vector3.new(0.9, 0.55, 0) }, body)

	local offset = rig.r15 and CFrame.new(0, -0.2, 0) or CFrame.new(0, -0.85, 0)
	for _, side in ipairs(sideList) do
		local isLeft = side.key == "Left"
		local arm = isLeft and rig.lArm or rig.rArm
		local hand = HANDS_BY_ID[side.handId]

		local glove, ring, att = buildHandModel(hand.color)
		glove.CFrame = arm.CFrame * offset
		glove.Parent = model
		weld(arm, glove, offset)

		side.glove, side.ring, side.gloveAtt = glove, ring, att
		side.port = isLeft and portL or portR
		side.status = isLeft and statusL or statusR
		side.gloveBolts = makeBolts(glove, hand.color, 3)
		side.gloveLight = make("PointLight", { Range = 14, Brightness = 0, Color = hand.color, Shadows = false }, glove)
		side.cable = make("Beam", {
			Attachment0 = side.port, Attachment1 = att, Width0 = 0.13, Width1 = 0.13,
			Segments = 12, FaceCamera = true, Color = ColorSequence.new(CABLE_COLOR),
		}, model)
		side.state, side.held = "idle", false
		pack.equipped = true
		applyHandVisual(side)
	end

	local zipAtt = make("Attachment", { Name = "GPZipAtt" }, rig.hrp)
	pack.lv = make("LinearVelocity", {
		Attachment0 = zipAtt, MaxForce = 1e6, VelocityConstraintMode = Enum.VelocityConstraintMode.Vector,
		RelativeTo = Enum.ActuatorRelativeTo.World, VectorVelocity = Vector3.zero, Enabled = false,
	}, rig.hrp)

	refreshFilter()
	pack.diedConn = rig.hum.Died:Connect(function() unequipPack(true) end)
	pack.building = false
	ui.dirty = true
end

local function setHand(sideKey, id)
	local side, hand = sides[sideKey], HANDS_BY_ID[id]
	if not (side and hand) then return end
	if side.state ~= "idle" and side.proj then cleanupSide(side) end
	side.handId = id
	if pack.equipped then applyHandVisual(side) end
	ui.dirty = true
end

------------------------------------------------------------------------
-- 13. INTERFACE (HUD)
------------------------------------------------------------------------
local function toggleSound()
	CONFIG.SoundOn = not CONFIG.SoundOn
	ui.dirty = true
end

local function buildGui()
	local gui = make("ScreenGui", {
		Name = "GrabPackHUD", ResetOnSpawn = false, IgnoreGuiInset = true,
		DisplayOrder = 100, ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	})
	local ok = pcall(function() gui.Parent = (gethui and gethui()) or game:GetService("CoreGui") end)
	if not ok or not gui.Parent then gui.Parent = player:WaitForChild("PlayerGui") end
	ui.gui = gui

	local function styleBtn(b, bg, size)
		b.BackgroundColor3 = bg
		b.BorderSizePixel = 0
		b.Font = Enum.Font.GothamBold
		b.TextSize = size or 13
		b.TextColor3 = Color3.new(1, 1, 1)
		b.TextStrokeTransparency = 0.5
		corner(b, 8)
	end

	local toggle = make("TextButton", {
		Name = "MenuToggle", Size = UDim2.fromOffset(120, 34), Position = UDim2.fromOffset(10, 56), Text = "GRABPACK ▾",
	}, gui)
	styleBtn(toggle, Color3.fromRGB(30, 34, 44), 13)

	local menu = make("Frame", {
		Name = "Menu", Visible = false, Size = UDim2.fromOffset(236, 412), Position = UDim2.fromOffset(10, 96),
		BackgroundColor3 = Color3.fromRGB(22, 24, 30), BackgroundTransparency = 0.12, BorderSizePixel = 0,
	}, gui)
	corner(menu, 10)
	connect(toggle.MouseButton1Click, function() menu.Visible = not menu.Visible end)

	ui.equipBtn = make("TextButton", { Size = UDim2.fromOffset(220, 34), Position = UDim2.fromOffset(8, 8), Text = "EQUIPAR" }, menu)
	styleBtn(ui.equipBtn, Color3.fromRGB(40, 140, 80), 14)
	connect(ui.equipBtn.MouseButton1Click, function()
		if pack.equipped then unequipPack(false) else task.spawn(equipPack) end
	end)

	-- Botão SOM ON/OFF
	ui.soundBtn = make("TextButton", { Size = UDim2.fromOffset(220, 30), Position = UDim2.fromOffset(8, 48), Text = "" }, menu)
	styleBtn(ui.soundBtn, Color3.fromRGB(45, 49, 62), 12)
	connect(ui.soundBtn.MouseButton1Click, toggleSound)

	ui.sideBtns = {}
	for i, key in ipairs({ "Left", "Right" }) do
		local b = make("TextButton", { Size = UDim2.fromOffset(220, 30), Position = UDim2.fromOffset(8, 84 + (i - 1) * 34), Text = "" }, menu)
		styleBtn(b, Color3.fromRGB(45, 49, 62), 12)
		make("UIStroke", { Color = Color3.new(1, 1, 1), Thickness = 0, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, b)
		connect(b.MouseButton1Click, function() ui.selectedSide = key; ui.dirty = true end)
		ui.sideBtns[key] = b
	end

	local grid = make("Frame", { Position = UDim2.fromOffset(8, 156), Size = UDim2.fromOffset(220, 200), BackgroundTransparency = 1 }, menu)
	make("UIGridLayout", { CellSize = UDim2.fromOffset(106, 40), CellPadding = UDim2.fromOffset(8, 8), SortOrder = Enum.SortOrder.LayoutOrder }, grid)
	for i, h in ipairs(HANDS) do
		local b = make("TextButton", { Text = i .. ". " .. h.name, LayoutOrder = i }, grid)
		styleBtn(b, h.color:Lerp(Color3.new(0, 0, 0), 0.4), 12)
		connect(b.MouseButton1Click, function() setHand(ui.selectedSide, h.id) end)
		ui.handButtons[h.id] = b
	end

	make("TextLabel", {
		Position = UDim2.fromOffset(8, 366), Size = UDim2.fromOffset(220, 36), BackgroundTransparency = 1,
		Font = Enum.Font.Gotham, TextSize = 10, TextColor3 = Color3.fromRGB(190, 195, 210), TextWrapped = true,
		Text = "Mouse/Q = esquerda • E = direita • F equipar • T lado • 1-8 mãos • M som",
	}, menu)

	local function fireButton(side, x, label)
		local b = make("TextButton", {
			Name = "Fire" .. side.key, Size = UDim2.fromOffset(72, 72), AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(1, x, 0.56, 0), Text = label,
		}, gui)
		styleBtn(b, Color3.fromRGB(0, 140, 255), 24)
		corner(b, 36)
		b.BackgroundTransparency = 0.15
		local function isPress(i) return i.UserInputType == Enum.UserInputType.Touch or i.UserInputType == Enum.UserInputType.MouseButton1 end
		connect(b.InputBegan, function(i) if isPress(i) then pressFire(side) end end)
		connect(b.InputEnded, function(i) if isPress(i) then releaseFire(side) end end)
		ui.fire[side.key] = b
	end
	fireButton(sides.Left, -200, "E")
	fireButton(sides.Right, -110, "D")

	local barsFrame = make("Frame", {
		AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 44), Size = UDim2.fromOffset(330, 40), BackgroundTransparency = 1,
	}, gui)
	local function makeBar(key, xScale, color, title)
		local holder = make("Frame", { Position = UDim2.new(xScale, 0, 0, 0), Size = UDim2.new(0.32, 0, 1, 0), BackgroundTransparency = 1 }, barsFrame)
		local label = make("TextLabel", {
			Size = UDim2.new(1, 0, 0, 16), BackgroundTransparency = 1, Text = title, Font = Enum.Font.GothamBold,
			TextSize = 11, TextColor3 = Color3.new(1, 1, 1), TextStrokeTransparency = 0.4,
		}, holder)
		local back = make("Frame", {
			Position = UDim2.fromOffset(0, 18), Size = UDim2.new(1, 0, 0, 10), BackgroundColor3 = Color3.fromRGB(20, 20, 24),
			BackgroundTransparency = 0.2, BorderSizePixel = 0,
		}, holder)
		corner(back, 5)
		local fill = make("Frame", { Size = UDim2.fromScale(0, 1), BackgroundColor3 = color, BorderSizePixel = 0 }, back)
		corner(fill, 5)
		ui.bars[key] = { label = label, fill = fill }
	end
	makeBar("Left", 0, HANDS_BY_ID.Blue.color, "CABO E")
	makeBar("Charge", 0.34, HANDS_BY_ID.Green.color, "CARGA VERDE")
	makeBar("Right", 0.68, HANDS_BY_ID.Red.color, "CABO D")
end

function ui.update()
	if not ui.gui then return end
	ui.equipBtn.Text = pack.equipped and "GUARDAR" or "EQUIPAR"
	ui.equipBtn.BackgroundColor3 = pack.equipped and Color3.fromRGB(150, 55, 55) or Color3.fromRGB(40, 140, 80)

	ui.soundBtn.Text = CONFIG.SoundOn and "SOM: LIGADO" or "SOM: DESLIGADO"
	ui.soundBtn.BackgroundColor3 = CONFIG.SoundOn and Color3.fromRGB(45, 110, 170) or Color3.fromRGB(70, 70, 78)

	for _, side in ipairs(sideList) do
		local hand = HANDS_BY_ID[side.handId]
		local len = 0
		if pack.equipped and side.state ~= "idle" and side.proj and side.port then
			len = (side.proj.Position - side.port.WorldPosition).Magnitude
		end
		local ratio = hand.range > 0 and math.clamp(len / hand.range, 0, 1) or 0
		local bar = ui.bars[side.key]
		bar.fill.Size = UDim2.fromScale(ratio, 1)
		bar.fill.BackgroundColor3 = ratio > 0.85 and Color3.fromRGB(255, 60, 60) or hand.color
		bar.label.Text = string.format("CABO %s  %d/%d", side.key == "Left" and "E" or "D", math.floor(len), hand.range)

		ui.fire[side.key].BackgroundColor3 = hand.color
		ui.fire[side.key].TextColor3 = (hand.id == "Omni" or hand.id == "Magnetic") and Color3.new(0, 0, 0) or Color3.new(1, 1, 1)

		local sb = ui.sideBtns[side.key]
		sb.Text = (side.key == "Left" and "Esquerda: " or "Direita: ") .. hand.name
		local stroke = sb:FindFirstChildOfClass("UIStroke")
		stroke.Thickness = (ui.selectedSide == side.key) and 2 or 0
	end

	local c = ui.bars.Charge
	c.fill.Size = UDim2.fromScale(pack.charge / CONFIG.ChargeMax, 1)
	c.label.Text = string.format("CARGA VERDE  %d%%", math.floor(pack.charge))
end

------------------------------------------------------------------------
-- 14. ENTRADAS (PC)
------------------------------------------------------------------------
local NUM_KEYS = {
	Enum.KeyCode.One, Enum.KeyCode.Two, Enum.KeyCode.Three, Enum.KeyCode.Four,
	Enum.KeyCode.Five, Enum.KeyCode.Six, Enum.KeyCode.Seven, Enum.KeyCode.Eight,
}

local function bindInput()
	connect(UserInputService.InputBegan, function(input, gp)
		if gp then return end
		local ut, kc = input.UserInputType, input.KeyCode
		if ut == Enum.UserInputType.MouseButton1 then pressFire(sides.Left)
		elseif ut == Enum.UserInputType.MouseButton2 and CONFIG.RightClickFires then pressFire(sides.Right)
		elseif kc == CONFIG.KeyLeft then pressFire(sides.Left)
		elseif kc == CONFIG.KeyRight then pressFire(sides.Right)
		elseif kc == CONFIG.KeyToggle then
			if pack.equipped then unequipPack(false) else task.spawn(equipPack) end
		elseif kc == CONFIG.KeySide then
			ui.selectedSide = (ui.selectedSide == "Left") and "Right" or "Left"
			ui.dirty = true
		elseif kc == CONFIG.KeySound then
			toggleSound()
		else
			for i, k in ipairs(NUM_KEYS) do
				if kc == k then setHand(ui.selectedSide, HANDS[i].id) break end
			end
		end
	end)
	connect(UserInputService.InputEnded, function(input)
		local ut, kc = input.UserInputType, input.KeyCode
		if ut == Enum.UserInputType.MouseButton1 or kc == CONFIG.KeyLeft then releaseFire(sides.Left) end
		if (ut == Enum.UserInputType.MouseButton2 and CONFIG.RightClickFires) or kc == CONFIG.KeyRight then
			releaseFire(sides.Right)
		end
	end)
end

------------------------------------------------------------------------
-- 15. INICIALIZAÇÃO E LIMPEZA
------------------------------------------------------------------------
local function destroyAll()
	unequipPack(false)
	for _, c in ipairs(conns) do pcall(function() c:Disconnect() end) end
	table.clear(conns)
	if ui.gui then ui.gui:Destroy() end
	for _, f in ipairs(flares) do if f.Parent then f:Destroy() end end
	fx:Destroy()
	env.GrabPackDefinitivo = nil
end

buildSounds()
buildGui()
bindInput()

local hudAcc = 0
connect(RunService.Heartbeat, function(dt)
	local ok, err = pcall(step, dt)
	if not ok and not pack.warned then
		pack.warned = true
		warn("[GrabPack] erro no loop: " .. tostring(err))
	end
	hudAcc += dt
	if hudAcc >= 0.07 or ui.dirty then
		hudAcc = 0
		ui.dirty = false
		pcall(ui.update)
	end
end)

connect(player.CharacterAdded, function()
	unequipPack(true)
	refreshFilter()
	if pack.wanted then task.spawn(equipPack) end
end)

env.GrabPackDefinitivo = {
	Destroy = destroyAll,
	Equip = function() task.spawn(equipPack) end,
	Unequip = function() unequipPack(false) end,
	SetHand = setHand,
	Config = CONFIG,
	ToggleSound = toggleSound,
}

task.spawn(equipPack)
