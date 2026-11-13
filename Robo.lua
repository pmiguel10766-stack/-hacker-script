-- ============================================================================
--  Bracos_Aranha_Robo.lua
--  BRAÇOS DE ARANHA ROBÓTICOS MK-IV  |  Parkour, Escalada & Robô Mexe Blocos
--  Roblox / Delta Executor (cliente)
-- ============================================================================

task.spawn(function()
local okRun, errRun = pcall(function()

-- ===================== SERVIÇOS =====================
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UIS = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")
local CoreGui = game:GetService("CoreGui")

local player = Players.LocalPlayer
assert(player, "LocalPlayer indisponível")

local clamp, exp, sin, cos, abs, max, min, floor, pi, noise =
	math.clamp, math.exp, math.sin, math.cos, math.abs, math.max, math.min, math.floor, math.pi, math.noise

local ENV = (getgenv and getgenv()) or _G
local CLEAN_KEY = "__BracosAranhaRobo_Cleanup"
local MODEL_NAME = "BracosAranhaRobo_Modelo"
local GUI_NAME = "BracosAranhaRobo_HUD"

-- ===================== LIMPEZA DE EXECUÇÕES ANTERIORES =====================
local function destroyLeftovers()
	pcall(function()
		local m = Workspace:FindFirstChild(MODEL_NAME)
		while m do
			m:Destroy()
			m = Workspace:FindFirstChild(MODEL_NAME)
		end
	end)
	local parents = {}
	pcall(function() if gethui then parents[#parents + 1] = gethui() end end)
	pcall(function() parents[#parents + 1] = CoreGui end)
	pcall(function() parents[#parents + 1] = player:FindFirstChildOfClass("PlayerGui") end)
	for _, p in ipairs(parents) do
		pcall(function()
			for _, c in ipairs(p:GetChildren()) do
				if c.Name == GUI_NAME then c:Destroy() end
			end
		end)
	end
	pcall(function()
		local ch = player.Character
		local hrp = ch and ch:FindFirstChild("HumanoidRootPart")
		if hrp then
			for _, n in ipairs({ "BAR_Att", "BAR_Align", "BAR_LV" }) do
				local o = hrp:FindFirstChild(n)
				while o do
					o:Destroy()
					o = hrp:FindFirstChild(n)
				end
			end
		end
		local hum = ch and ch:FindFirstChildOfClass("Humanoid")
		if hum then
			hum.PlatformStand = false
			hum.AutoRotate = true
		end
	end)
end

if ENV[CLEAN_KEY] then
	pcall(ENV[CLEAN_KEY])
	ENV[CLEAN_KEY] = nil
end
destroyLeftovers()

-- ===================== CONFIGURAÇÃO =====================
local CFG = {
	ATTACH_RANGE = 7.5,
	CLIMB_SPEED = 20,
	TURBO_MULT = 1.7,
	L1 = 3.4,
	L2 = 4.0,
	CLAW_REACH = 1.3,
	STEP_DIST = 2.1,
	STEP_TIME = 0.2,
	STEP_LIFT = 1.3,
	WEAR_RECOVER = 55,
	REPAIR_COOLDOWN = 8,
	REPAIR_AMOUNT = 30,
}

local C = {
	metal = Color3.fromRGB(46, 50, 58),
	dark = Color3.fromRGB(26, 28, 34),
	joint = Color3.fromRGB(72, 78, 90),
	scorch = Color3.fromRGB(24, 18, 16),
	cyan = Color3.fromRGB(0, 229, 255),
	yellow = Color3.fromRGB(255, 210, 60),
	orange = Color3.fromRGB(255, 140, 30),
	red = Color3.fromRGB(255, 50, 50),
	green = Color3.fromRGB(60, 230, 120),
	bg = Color3.fromRGB(12, 14, 20),
	btn = Color3.fromRGB(24, 28, 38),
	text = Color3.fromRGB(225, 232, 245),
	dim = Color3.fromRGB(125, 138, 158),
}

local S = {
	conns = {}, charConns = {},
	alive = true, charToken = 0,
	char = nil, hum = nil, hrp = nil, torso = nil, model = nil,
	hover = 3, arms = {},
	climbMode = false, attached = false, turbo = false, failure = false,
	blockMoverMode = false, clickToMoveActive = false, carryingPart = nil, targetBlock = nil, targetPos = nil, moveStage = 0, stageTimer = 0,
	curN = Vector3.new(0, 1, 0), targetN = Vector3.new(0, 1, 0),
	facing = Vector3.new(0, 0, -1), lastDir = nil, frameCF = nil,
	moveVel = Vector3.zero, speedFac = 0,
	blend = 0, droop = 0, gaze = Vector3.zero,
	reattachAt = 0, nextScan = 0, lostTimer = 0, repairReadyAt = 0,
	lastHealth = 100, maxWear = 0, avgWear = 0,
	att = nil, align = nil, lv = nil,
	lastFx = 0, lastHud = 0, hudDirty = true, errCount = 0,
}

S.rp = RaycastParams.new()
S.rp.FilterType = Enum.RaycastFilterType.Exclude
S.rp.IgnoreWater = true
pcall(function() S.rp.RespectCanCollide = true end)

local function track(t, c) t[#t + 1] = c return c end
local function disconnectAll(t)
	for i = #t, 1, -1 do
		pcall(function() t[i]:Disconnect() end)
		t[i] = nil
	end
end

local function wearColor(w)
	if w < 40 then
		return C.cyan:Lerp(C.yellow, w / 40)
	elseif w < 75 then
		return C.yellow:Lerp(C.orange, (w - 40) / 35)
	end
	return C.orange:Lerp(C.red, clamp((w - 75) / 25, 0, 1))
end

local SCAN_DIRS = {}
for x = -1, 1 do
	for y = -1, 1 do
		for z = -1, 1 do
			if x ~= 0 or y ~= 0 or z ~= 0 then
				SCAN_DIRS[#SCAN_DIRS + 1] = Vector3.new(x, y, z).Unit
			end
		end
	end
end

-- ===================== GERAÇÃO PROCEDURAL DOS BRAÇOS =====================
local MOUNTS = {
	{ n = "UL", side = -1, upper = true,  grp = 1, off = Vector3.new(-1.1, 0.6, 1.0), idle = Vector3.new(-4.4, 1.6, 2.4), home = Vector3.new(-4.1, 0, -1.2) },
	{ n = "UR", side = 1,  upper = true,  grp = 2, off = Vector3.new(1.1, 0.6, 1.0),  idle = Vector3.new(4.4, 1.6, 2.4),  home = Vector3.new(4.1, 0, -1.2) },
	{ n = "LL", side = -1, upper = false, grp = 2, off = Vector3.new(-1.1, -0.4, 1.0), idle = Vector3.new(-3.7, -2.3, 3.0), home = Vector3.new(-3.4, 0, 3.4) },
	{ n = "LR", side = 1,  upper = false, grp = 1, off = Vector3.new(1.1, -0.4, 1.0),  idle = Vector3.new(3.7, -2.3, 3.0),  home = Vector3.new(3.4, 0, 3.4) },
}

local function newPart(parent, name, size, color, material, shape)
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Massless = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Size = size
	p.Color = color
	p.Material = material or Enum.Material.Metal
	if shape then p.Shape = shape end
	p.Parent = parent
	return p
end

local function makeSmoke(parent, name)
	local a = Instance.new("Attachment")
	a.Name = name .. "_Att"
	a.Parent = parent
	local e = Instance.new("ParticleEmitter")
	e.Name = name
	e.Texture = "rbxasset://textures/particles/smoke_main.dds"
	e.Rate = 0
	e.Enabled = false
	e.Lifetime = NumberRange.new(1, 2)
	e.Speed = NumberRange.new(2, 5)
	e.SpreadAngle = Vector2.new(25, 25)
	e.Acceleration = Vector3.new(0, 4, 0)
	e.Rotation = NumberRange.new(0, 360)
	e.RotSpeed = NumberRange.new(-40, 40)
	e.LightEmission = 0
	e.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.55),
		NumberSequenceKeypoint.new(0.6, 0.78),
		NumberSequenceKeypoint.new(1, 1),
	})
	e.Size = NumberSequence.new(0.6, 2)
	e.Parent = a
	return e
end

local function makeSparks(parent, name)
	local a = Instance.new("Attachment")
	a.Name = name .. "_Att"
	a.Parent = parent
	local e = Instance.new("ParticleEmitter")
	e.Name = name
	e.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	e.Rate = 0
	e.Enabled = false
	e.Lifetime = NumberRange.new(0.2, 0.55)
	e.Speed = NumberRange.new(10, 24)
	e.SpreadAngle = Vector2.new(180, 180)
	e.Acceleration = Vector3.new(0, -50, 0)
	e.LightEmission = 1
	e.Color = ColorSequence.new(Color3.fromRGB(255, 240, 150), Color3.fromRGB(255, 110, 20))
	e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.28), NumberSequenceKeypoint.new(1, 0) })
	e.Transparency = NumberSequence.new(0, 1)
	e.Parent = a
	return e
end

local function buildArms()
	if S.model then pcall(function() S.model:Destroy() end) end
	local model = Instance.new("Model")
	model.Name = MODEL_NAME
	S.model = model
	S.arms = {}

	S.plate = newPart(model, "Placa", Vector3.new(2.4, 2.1, 0.6), C.metal)
	S.core = newPart(model, "Reator", Vector3.new(0.9, 0.9, 0.25), C.cyan, Enum.Material.Neon)

	for _, m in ipairs(MOUNTS) do
		local arm = {
			m = m, wear = 0, grip = 0.3, flash = 0,
			stress = 0.88 + math.random() * 0.26,
			phase = math.random() * 6.28,
			nextSpark = os.clock() + 2 + math.random() * 2,
			foot = { pos = nil, normal = Vector3.new(0, 1, 0), stepping = false, t = 0 },
		}
		arm.shoulder = newPart(model, m.n .. "_Ombro", Vector3.new(1.15, 1.15, 1.15), C.joint, Enum.Material.Metal, Enum.PartType.Ball)
		arm.elbow = newPart(model, m.n .. "_Cotovelo", Vector3.new(1.0, 1.0, 1.0), C.joint, Enum.Material.Metal, Enum.PartType.Ball)
		arm.wrist = newPart(model, m.n .. "_Pulso", Vector3.new(0.85, 0.85, 0.85), C.joint, Enum.Material.Metal, Enum.PartType.Ball)
		arm.seg1 = newPart(model, m.n .. "_Seg1", Vector3.new(0.62, 0.62, CFG.L1 - 0.55), C.metal)
		arm.seg2 = newPart(model, m.n .. "_Seg2", Vector3.new(0.52, 0.52, CFG.L2 - 0.5), C.metal)
		arm.acc1 = newPart(model, m.n .. "_Led1", Vector3.new(0.22, 0.1, (CFG.L1 - 0.55) * 0.7), C.cyan, Enum.Material.Neon)
		arm.acc2 = newPart(model, m.n .. "_Led2", Vector3.new(0.18, 0.1, (CFG.L2 - 0.5) * 0.7), C.cyan, Enum.Material.Neon)
		arm.ph1, arm.ph2 = {}, {}
		for k = 1, 3 do
			arm.ph1[k] = newPart(model, m.n .. "_Dedo" .. k .. "a", Vector3.new(0.22, 0.22, 0.9), C.dark)
			arm.ph2[k] = newPart(model, m.n .. "_Dedo" .. k .. "b", Vector3.new(0.17, 0.17, 0.8), C.dark)
		end
		arm.smoke = {
			{ e = makeSmoke(arm.shoulder, "Fumo"), w = 0.5 },
			{ e = makeSmoke(arm.elbow, "Fumo"), w = 1.0 },
			{ e = makeSmoke(arm.wrist, "Fumo"), w = 0.6 },
		}
		arm.sparkE = makeSparks(arm.elbow, "Faiscas")
		arm.sparkW = makeSparks(arm.wrist, "Faiscas")
		local light = Instance.new("PointLight")
		light.Color = Color3.fromRGB(255, 170, 60)
		light.Range = 10
		light.Brightness = 0
		light.Shadows = false
		light.Parent = arm.elbow
		arm.light = light
		S.arms[#S.arms + 1] = arm
	end
end

local function solveIK(s0, target, l1, l2, pole)
	local d = target - s0
	local dist = d.Magnitude
	if dist < 1e-4 then d = Vector3.new(0, -1, 0) dist = 1e-4 end
	local dir = d / dist
	local maxR, minR = l1 + l2 - 0.02, abs(l1 - l2) + 0.08
	if dist > maxR then dist = maxR elseif dist < minR then dist = minR end
	local w = s0 + dir * dist
	local a = (l1 * l1 - l2 * l2 + dist * dist) / (2 * dist)
	local h = math.sqrt(max(l1 * l1 - a * a, 0))
	local p = pole - dir * pole:Dot(dir)
	if p.Magnitude < 1e-3 then
		p = dir:Cross(Vector3.new(1, 0, 0))
		if p.Magnitude < 1e-3 then p = dir:Cross(Vector3.new(0, 0, 1)) end
	end
	return s0 + dir * a + p.Unit * h, w
end

local function beam(part, a, b)
	local d = b - a
	if d.Magnitude < 1e-3 then return end
	part.CFrame = CFrame.lookAt((a + b) * 0.5, b)
end

local function updateArms(dt, now)
	local torso = S.torso
	if not (torso and torso.Parent and S.model and S.plate) then return end
	local tcf = torso.CFrame
	local cam = Workspace.CurrentCamera
	if cam then
		local ll = tcf:VectorToObjectSpace(cam.CFrame.LookVector)
		S.gaze = S.gaze:Lerp(Vector3.new(clamp(ll.X, -1, 1), clamp(ll.Y, -1, 1), 0), 1 - exp(-5 * dt))
	end
	S.blend = S.blend + ((S.attached and 1 or 0) - S.blend) * (1 - exp(-7 * dt))
	S.droop = S.droop + ((S.failure and 1 or 0) - S.droop) * (1 - exp(-3 * dt))
	local blend = S.blend

	S.plate.CFrame = tcf * CFrame.new(0, 0.1, 0.85)
	S.core.CFrame = tcf * CFrame.new(0, 0.2, 1.2)

	for i, arm in ipairs(S.arms) do
		local m = arm.m
		local shoulder = tcf:PointToWorldSpace(m.off)

		local desired
		local gripGoal = 0.3 + 0.1 * sin(now * 2 + arm.phase)
		if S.droop > 0.5 then gripGoal = 0 end
		local pole = tcf.UpVector + tcf.RightVector * m.side * 0.7

		if S.blockMoverMode and S.targetBlock and S.targetPos then
			local bPos = S.targetBlock.Position
			local tPos = S.targetPos
			if S.moveStage == 1 then
				-- Estágio 1: Estica os braços até ao bloco de origem
				desired = bPos + Vector3.new(m.side * 0.5, 0.2, m.upper and 0.4 or -0.4)
				gripGoal = 0.95
			elseif S.moveStage == 2 then
				-- Estágio 2: Levanta o bloco pelo ar até à posição alvo clicada
				local mid = bPos:Lerp(tPos, 0.5) + Vector3.new(0, 3.5, 0)
				desired = mid + Vector3.new(m.side * 0.8, 0, 0)
				gripGoal = 1.0
				if S.carryingPart and S.carryingPart.Parent then
					S.carryingPart.CFrame = CFrame.new(mid)
				end
			elseif S.moveStage == 3 then
				-- Estágio 3: Posiciona e larga o bloco exatamente no ponto clicado
				desired = tPos + Vector3.new(m.side * 0.3, 0.1, 0)
				gripGoal = 0.2
				if S.carryingPart and S.carryingPart.Parent then
					S.carryingPart.CFrame = CFrame.new(tPos)
				end
			else
				local il = m.idle + Vector3.new(sin(now * 1.3 + arm.phase) * 0.3, sin(now * 1.7 + arm.phase) * 0.25 - 3.2 * S.droop, 0)
				desired = tcf:PointToWorldSpace(il)
			end
		else
			local il = m.idle + Vector3.new(
				sin(now * 1.3 + arm.phase) * 0.3 + S.gaze.X * (m.upper and 1.5 or 0.5),
				sin(now * 1.7 + arm.phase * 1.3) * 0.25 + S.gaze.Y * 1.6 - 3.2 * S.droop,
				cos(now * 1.1 + arm.phase) * 0.3
			)
			desired = tcf:PointToWorldSpace(il)
			local ft = arm.foot
			if blend > 0.01 and ft.pos then
				local plantW = ft.pos + ft.normal * CFG.CLAW_REACH
				desired = desired:Lerp(plantW, blend)
				local fr = S.frameCF and S.frameCF.RightVector or tcf.RightVector
				pole = pole:Lerp(S.curN + fr * m.side * 0.6, blend)
				gripGoal = gripGoal + ((ft.stepping and 0.15 or 1) - gripGoal) * blend
			end
		end

		local jw = max(arm.wear - 65, 0) / 35
		if jw > 0 then
			desired = desired + Vector3.new(noise(now * 22, i * 0.37, 0.11), noise(now * 22, i * 0.37, 5.3), noise(now * 22, i * 0.37, 9.7)) * (0.7 * jw)
		end

		arm.W = arm.W and arm.W:Lerp(desired, 1 - exp(-20 * dt)) or desired
		local E, W = solveIK(shoulder, arm.W, CFG.L1, CFG.L2, pole)

		arm.shoulder.CFrame = CFrame.new(shoulder)
		arm.elbow.CFrame = CFrame.new(E)
		arm.wrist.CFrame = CFrame.new(W)
		beam(arm.seg1, shoulder, E)
		beam(arm.seg2, E, W)
		arm.acc1.CFrame = arm.seg1.CFrame * CFrame.new(0, 0.35, 0)
		arm.acc2.CFrame = arm.seg2.CFrame * CFrame.new(0, 0.3, 0)

		local dirL = W - E
		dirL = dirL.Magnitude > 1e-3 and dirL.Unit or Vector3.new(0, -1, 0)
		local axis = dirL * (1 - 0.55 * blend) - S.curN * (0.55 * blend)
		axis = axis.Magnitude > 1e-3 and axis.Unit or dirL
		arm.grip = arm.grip + (gripGoal - arm.grip) * (1 - exp(-12 * dt))
		local g = arm.grip
		local ref = (abs(axis:Dot(S.curN)) < 0.92) and S.curN or tcf.RightVector
		local u = axis:Cross(ref)
		if u.Magnitude < 1e-3 then u = axis:Cross(Vector3.new(0, 1, 0)) end
		u = u.Unit
		local v = axis:Cross(u)
		local sp = 0.8 - 0.4 * g
		local csp, ssp = cos(sp), sin(sp)
		for k = 1, 3 do
			local th = (k - 1) * 2.0944 + 1.5708
			local radial = u * cos(th) + v * sin(th)
			local p1 = W + (axis * csp + radial * ssp) * 0.9
			local f2 = axis * 0.75 - radial * (0.15 + 0.7 * g)
			local p2 = p1 + f2.Unit * 0.8
			beam(arm.ph1[k], W, p1)
			beam(arm.ph2[k], p1, p2)
		end
	end
end

local function applyWearFX(now)
	local sum = 0
	for i, arm in ipairs(S.arms) do
		local w = arm.wear
		local lvl = clamp((w - 18) / 82, 0, 1)
		for _, s in ipairs(arm.smoke) do
			local e = s.e
			if lvl > 0 then
				e.Enabled = true
				e.Rate = (3 + lvl * lvl * 38) * s.w
				local gr = 0.72 - lvl * 0.6
				e.Color = ColorSequence.new(Color3.new(gr, gr, gr))
				e.Size = NumberSequence.new(0.5 + lvl * 0.5, 1.8 + lvl * 2.6)
				e.Lifetime = NumberRange.new(0.9 + lvl, 1.8 + lvl * 1.6)
			else
				e.Enabled = false
			end
		end
		local col = wearColor(w)
		if w >= 85 and noise(now * 8, i * 0.41, 0.5) > 0.15 then col = C.dark end
		arm.acc1.Color = col
		arm.acc2.Color = col
		local burnt = C.joint:Lerp(C.scorch, lvl * 0.85)
		arm.shoulder.Color = burnt
		arm.elbow.Color = burnt
		arm.wrist.Color = burnt
		sum = sum + w
	end
	if S.core then S.core.Color = wearColor(S.maxWear) end
end

local function sparkStep(dt, now)
	for _, arm in ipairs(S.arms) do
		if arm.flash > 0 then
			arm.flash = arm.flash - dt
			if arm.flash <= 0 then arm.light.Brightness = 0 end
		end
		local w = arm.wear
		if w >= 55 and now >= arm.nextSpark then
			local lvl = clamp((w - 55) / 45, 0, 1)
			arm.nextSpark = now + (3.2 - 2.9 * lvl) * (0.5 + math.random())
			local e = (math.random() < 0.6) and arm.sparkE or arm.sparkW
			e:Emit(math.random(3, 6 + floor(lvl * 9)))
			arm.flash = 0.08
			arm.light.Brightness = 5
		end
	end
end

-- ===================== FÍSICA DE ESCALADA MAGNÉTICA =====================
local function destroyPhysics()
	for _, k in ipairs({ "align", "lv", "att" }) do
		if S[k] then pcall(function() S[k]:Destroy() end) S[k] = nil end
	end
end

local function ensurePhysics()
	if S.att and S.att.Parent == S.hrp and S.align and S.lv then return end
	destroyPhysics()
	local att = Instance.new("Attachment")
	att.Name = "BAR_Att"
	att.Parent = S.hrp
	local al = Instance.new("AlignOrientation")
	al.Name = "BAR_Align"
	al.Mode = Enum.OrientationAlignmentMode.OneAttachment
	al.Attachment0 = att
	al.RigidityEnabled = false
	al.MaxTorque = 1e8
	al.MaxAngularVelocity = 25
	al.Responsiveness = 35
	al.CFrame = S.hrp.CFrame
	al.Enabled = false
	al.Parent = S.hrp
	local lv = Instance.new("LinearVelocity")
	lv.Name = "BAR_LV"
	lv.Attachment0 = att
	lv.RelativeTo = Enum.ActuatorRelativeTo.World
	lv.VelocityConstraintMode = Enum.VelocityConstraintMode.Vector
	lv.MaxForce = 1e7
	lv.VectorVelocity = Vector3.zero
	lv.Enabled = false
	lv.Parent = S.hrp
	S.att, S.align, S.lv = att, al, lv
end

local function detach(upright, impulse)
	local was = S.attached
	S.attached = false
	S.speedFac = 0
	S.lostTimer = 0
	S.moveVel = Vector3.zero
	if S.align then S.align.Enabled = false end
	if S.lv then S.lv.Enabled = false end
	local hum, hrp = S.hum, S.hrp
	if hum and hum.Parent then
		hum.PlatformStand = false
		hum.AutoRotate = true
	end
	if was and hrp and hrp.Parent then
		if upright then
			local cam = Workspace.CurrentCamera
			local lk = cam and cam.CFrame.LookVector or hrp.CFrame.LookVector
			local flat = Vector3.new(lk.X, 0, lk.Z)
			if flat.Magnitude < 0.1 then flat = Vector3.new(0, 0, -1) end
			local p = hrp.Position + S.curN * 0.15
			hrp.CFrame = CFrame.lookAt(p, p + flat.Unit)
			hrp.AssemblyAngularVelocity = Vector3.zero
		end
		hrp.AssemblyLinearVelocity = impulse or Vector3.zero
		if hum and hum.Parent then pcall(function() hum:ChangeState(Enum.HumanoidStateType.Freefall) end) end
	end
	S.hudDirty = true
end

local function attachTo(normal)
	ensurePhysics()
	S.attached = true
	S.targetN = normal
	S.curN = S.hrp.CFrame.UpVector
	S.facing = S.hrp.CFrame.LookVector
	S.lostTimer = 0
	for _, arm in ipairs(S.arms) do
		arm.foot = { pos = nil, normal = Vector3.new(0, 1, 0), stepping = false, t = 0 }
	end
	S.hum.PlatformStand = true
	S.hum.AutoRotate = false
	S.align.CFrame = S.hrp.CFrame
	S.align.Enabled = true
	S.lv.Enabled = true
	S.hudDirty = true
end

local controls
pcall(function()
	local ps = player:WaitForChild("PlayerScripts", 5)
	local pm = require(ps:WaitForChild("PlayerModule", 5))
	controls = pm:GetControls()
end)

local function getInput()
	if controls then
		local ok, v = pcall(controls.GetMoveVector, controls)
		if ok and typeof(v) == "Vector3" then
			local x, z = v.X, -v.Z
			local m = math.sqrt(x * x + z * z)
			if m > 1 then x, z = x / m, z / m end
			return x, z
		end
	end
	local md = S.hum and S.hum.MoveDirection or Vector3.zero
	local cam = Workspace.CurrentCamera
	if md.Magnitude > 0.01 and cam then
		local lk = cam.CFrame.LookVector
		lk = Vector3.new(lk.X, 0, lk.Z)
		if lk.Magnitude < 1e-3 then return 0, 0 end
		lk = lk.Unit
		local rt = Vector3.new(-lk.Z, 0, lk.X)
		return md:Dot(rt), md:Dot(lk)
	end
	return 0, 0
end

local function groundAt(p, n)
	local r = Workspace:Raycast(p + n * 1.6, -n * 4.6, S.rp)
	if r then return r.Position, r.Normal end
	return p, n
end

local function stepFeet(dt, mdir, speedFrac)
	local fcf = S.frameCF
	if not fcf then return end
	local stepping = { false, false }
	for _, arm in ipairs(S.arms) do
		if arm.foot.stepping then stepping[arm.m.grp] = true end
	end
	local tcf = S.torso.CFrame
	for _, arm in ipairs(S.arms) do
		local ft = arm.foot
		local homeW = fcf:PointToWorldSpace(Vector3.new(arm.m.home.X, -S.hover, arm.m.home.Z))
		if not ft.pos then
			ft.pos, ft.normal = groundAt(homeW, S.curN)
		elseif ft.stepping then
			ft.t = ft.t + dt / CFG.STEP_TIME
			local a = min(ft.t, 1)
			local e = a * a * (3 - 2 * a)
			ft.pos = ft.from:Lerp(ft.to, e) + S.curN * (sin(a * pi) * CFG.STEP_LIFT)
			local nn = ft.normal:Lerp(ft.toN, e)
			if nn.Magnitude > 1e-3 then ft.normal = nn.Unit end
			if a >= 1 then
				ft.stepping = false
				ft.pos = ft.to
				ft.normal = ft.toN
			end
		else
			local d = (ft.pos - homeW).Magnitude
			local shoulderW = tcf:PointToWorldSpace(arm.m.off)
			local reach = (ft.pos + ft.normal * CFG.CLAW_REACH - shoulderW).Magnitude
			local mustStep = reach > (CFG.L1 + CFG.L2 - 0.5)
			local want = d > CFG.STEP_DIST * (1 - 0.3 * speedFrac)
			if (want and not stepping[3 - arm.m.grp]) or mustStep then
				local lead = mdir and (mdir * (1.1 * speedFrac)) or Vector3.zero
				local to, toN = groundAt(homeW + lead, S.curN)
				ft.from, ft.to, ft.toN = ft.pos, to, toN
				ft.stepping = true
				ft.t = 0
				stepping[arm.m.grp] = true
			end
		end
	end
end

local function attachedStep(dt, now)
	local hrp = S.hrp
	local pos = hrp.Position
	local cam = Workspace.CurrentCamera
	if not cam then return end

	S.curN = S.curN:Lerp(S.targetN, 1 - exp(-10 * dt))
	if S.curN.Magnitude < 0.05 then S.curN = S.targetN end
	S.curN = S.curN.Unit
	local N = S.curN

	local cf = cam.CFrame
	local fwd = cf.LookVector - N * cf.LookVector:Dot(N)
	if fwd.Magnitude < 0.3 then fwd = cf.UpVector - N * cf.UpVector:Dot(N) end
	if fwd.Magnitude < 1e-3 then fwd = S.facing - N * S.facing:Dot(N) end
	if fwd.Magnitude < 1e-3 then fwd = N:Cross(Vector3.new(1, 0, 0)) end
	fwd = fwd.Unit
	local right = fwd:Cross(N)
	if right:Dot(cf.RightVector) < -0.25 then right = -right end

	local ix, iz = getInput()
	local speed = CFG.CLIMB_SPEED * (S.turbo and CFG.TURBO_MULT or 1)
	local mv = (fwd * iz + right * ix) * speed
	local mag = mv.Magnitude
	if mag > speed then mv = mv.Unit * speed mag = speed end
	S.speedFac = mag / CFG.CLIMB_SPEED
	local mdir = mag > 0.5 and mv.Unit or nil
	if mdir then
		S.lastDir = mdir
		local nf = S.facing:Lerp(mdir, 1 - exp(-12 * dt))
		S.facing = nf.Magnitude > 0.05 and nf or mdir
	end

	local fp = S.facing - N * S.facing:Dot(N)
	if fp.Magnitude < 0.05 then fp = fwd end
	fp = fp.Unit
	S.facing = fp
	S.frameCF = CFrame.lookAt(pos, pos + fp, N)
	S.align.CFrame = CFrame.lookAt(Vector3.zero, fp, N)

	local hover = S.hover
	local stick = Vector3.zero
	local r = Workspace:Raycast(pos, -S.targetN * (hover + 2.4), S.rp)
	if r then
		S.lostTimer = 0
		S.targetN = r.Normal
		stick = -r.Normal * clamp((r.Distance - hover) * 12, -18, 18)
	else
		local ld = mdir or S.lastDir
		local wrapped = false
		if ld then
			local o = pos - S.targetN * (hover + 1.8)
			local r2 = Workspace:Raycast(o, -ld * 3.4, S.rp)
			if r2 and r2.Normal:Dot(S.targetN) < 0.9 then
				S.targetN = r2.Normal
				wrapped = true
			end
		end
		if wrapped then
			S.lostTimer = 0
		else
			S.lostTimer = S.lostTimer + dt
			if S.lostTimer > 0.3 then
				S.reattachAt = now + 0.6
				detach(true, S.moveVel * 0.5)
				return
			end
		end
	end

	if mdir then
		local r3 = Workspace:Raycast(pos, mdir * (hover + 0.9), S.rp)
		if r3 and r3.Normal:Dot(S.targetN) < 0.72 then S.targetN = r3.Normal end
	end

	S.moveVel = mv
	S.lv.VectorVelocity = mv + stick

	stepFeet(dt, mdir, min(S.speedFac, 1))
end

local function scanAttach(now)
	if now < S.reattachAt or now < S.nextScan then return end
	S.nextScan = now + 0.07
	local pos = S.hrp.Position
	local cam = Workspace.CurrentCamera
	local look = cam and cam.CFrame.LookVector or Vector3.zero
	local best, bestScore
	for _, d in ipairs(SCAN_DIRS) do
		local r = Workspace:Raycast(pos, d * CFG.ATTACH_RANGE, S.rp)
		if r then
			local sc = r.Distance - d:Dot(look) * 1.2
			if not bestScore or sc < bestScore then best, bestScore = r, sc end
		end
	end
	if best then attachTo(best.Normal) end
end

-- ===================== DESGASTE / FALHA =====================
local function triggerFailure()
	S.failure = true
	S.climbMode = false
	S.blockMoverMode = false
	S.clickToMoveActive = false
	detach(true, Vector3.zero)
	for _, arm in ipairs(S.arms) do
		arm.sparkE:Emit(10)
		arm.sparkW:Emit(8)
		arm.flash = 0.25
		arm.light.Brightness = 5
	end
	S.hudDirty = true
end

local function updateWear(dt)
	local load = 0
	if S.attached or S.blockMoverMode then
		local grav = 1 + (1 - S.curN.Y) * 0.45
		local mul = (S.turbo or S.blockMoverMode) and 2.4 or 1
		load = (0.25 + 1.2 * S.speedFac) * grav * mul
	end
	local cool = 0
	if not (S.attached or S.blockMoverMode) then cool = S.failure and 4.5 or 3.2 end
	local mx, sum = 0, 0
	for _, arm in ipairs(S.arms) do
		if load > 0 then arm.wear = arm.wear + load * arm.stress * dt end
		if cool > 0 then arm.wear = arm.wear - cool * dt end
		arm.wear = clamp(arm.wear, 0, 100)
		if arm.wear > mx then mx = arm.wear end
		sum = sum + arm.wear
	end
	S.maxWear = mx
	S.avgWear = (#S.arms > 0) and (sum / #S.arms) or 0
	if not S.failure and mx >= 100 then
		triggerFailure()
	elseif S.failure and mx <= CFG.WEAR_RECOVER then
		S.failure = false
		S.hudDirty = true
	end
end

local function onDamaged(amount)
	if #S.arms == 0 then return end
	local pct = amount / max(S.hum.MaxHealth, 1)
	local add = 6 + pct * 140
	local victim = math.random(1, #S.arms)
	for i, arm in ipairs(S.arms) do
		local a = add * 0.45 * arm.stress
		if i == victim then
			a = a + add * 1.1
			arm.sparkE:Emit(math.random(8, 14))
			arm.flash = 0.12
			arm.light.Brightness = 5
		end
		arm.wear = clamp(arm.wear + a, 0, 100)
	end
	S.hudDirty = true
end

-- ===================== CONTROLO DE ESTADO & MEXE BLOCOS =====================
local function setClimb(on)
	if on then
		if S.failure or not S.hum or S.hum.Health <= 0 then return end
		S.blockMoverMode = false
		S.clickToMoveActive = false
		S.climbMode = true
		S.reattachAt = 0
	else
		S.climbMode = false
		detach(true, Vector3.zero)
	end
	S.hudDirty = true
end

local function setBlockMover(on)
	if on then
		if S.failure or not S.hum or S.hum.Health <= 0 then return end
		S.climbMode = false
		detach(true, Vector3.zero)
		S.blockMoverMode = true
		S.clickToMoveActive = false
		S.moveStage = 0
		S.targetBlock = nil
		S.targetPos = nil
		S.carryingPart = nil
	else
		S.blockMoverMode = false
		S.clickToMoveActive = false
		if S.carryingPart and S.carryingPart.Parent then
			pcall(function() S.carryingPart.Anchored = false end)
		end
		S.carryingPart = nil
		S.targetBlock = nil
		S.targetPos = nil
		S.moveStage = 0
	end
	S.hudDirty = true
end

-- Clique na tela: se o modo mexe blocos estiver ativo, define o bloco e a posição alvo
local function handleScreenClick()
	if not S.blockMoverMode or S.failure then return end
	local cam = Workspace.CurrentCamera
	if not cam then return end
	local mousePos = UIS:GetMouseLocation()
	local unitRay = cam:ViewportPointToRay(mousePos.X, mousePos.Y)
	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Exclude
	rayParams.FilterDescendantsInstances = { S.char, S.model }
	local res = Workspace:Raycast(unitRay.Origin, unitRay.Direction * 120, rayParams)
	if res then
		if not S.clickToMoveActive then
			-- 1º Clique: Seleciona o bloco de origem
			if res.Instance and res.Instance:IsA("Part") then
				S.targetBlock = res.Instance
				S.carryingPart = res.Instance
				S.clickToMoveActive = true
				S.moveStage = 1
				S.stageTimer = os.clock()
				pcall(function() S.carryingPart.Anchored = true end)
			end
		else
			-- 2º Clique: Seleciona a posição alvo no mapa para mover o bloco
			S.targetPos = res.Position
			S.moveStage = 2
			S.stageTimer = os.clock()
		end
		S.hudDirty = true
	end
end

local function updateBlockMover(dt)
	if not S.blockMoverMode or not S.targetBlock then return end
	local elapsed = os.clock() - S.stageTimer
	if S.moveStage == 1 and S.targetPos and elapsed > 0.4 then
		S.moveStage = 2 -- Levantar e transladar
		S.stageTimer = os.clock()
	elseif S.moveStage == 2 and elapsed > 1.2 then
		S.moveStage = 3 -- Posicionar no alvo
		S.stageTimer = os.clock()
	elseif S.moveStage == 3 and elapsed > 0.5 then
		if S.carryingPart and S.carryingPart.Parent and S.targetPos then
			pcall(function()
				S.carryingPart.CFrame = CFrame.new(S.targetPos)
				S.carryingPart.Anchored = false
			end)
		end
		S.carryingPart = nil
		S.targetBlock = nil
		S.targetPos = nil
		S.clickToMoveActive = false
		S.moveStage = 0
		S.hudDirty = true
	end
end

local function doJump()
	if S.attached and S.hum and S.hum.Health > 0 then
		S.reattachAt = os.clock() + 0.55
		detach(true, S.targetN * 52 + S.moveVel * 0.8)
	end
end

local function doDrop()
	if S.attached then
		S.reattachAt = os.clock() + 1.2
		detach(true, Vector3.zero)
	end
end

local function doRepair()
	local now = os.clock()
	if now < S.repairReadyAt then return end
	S.repairReadyAt = now + CFG.REPAIR_COOLDOWN
	for _, arm in ipairs(S.arms) do arm.wear = max(arm.wear - CFG.REPAIR_AMOUNT, 0) end
	S.hudDirty = true
end

-- ===================== PERSONAGEM =====================
local function cleanupChar()
	disconnectAll(S.charConns)
	local hum = S.hum
	if hum then
		pcall(function()
			hum.PlatformStand = false
			hum.AutoRotate = true
		end)
	end
	destroyPhysics()
	if S.model then pcall(function() S.model:Destroy() end) S.model = nil end
	S.plate, S.core = nil, nil
	S.arms = {}
	S.attached = false
	S.climbMode = false
	S.blockMoverMode = false
	S.clickToMoveActive = false
	S.failure = false
	S.blend, S.droop = 0, 0
	S.maxWear, S.avgWear = 0, 0
	S.char, S.hum, S.hrp, S.torso = nil, nil, nil, nil
	S.hudDirty = true
end

local function setupChar(char)
	cleanupChar()
	S.charToken = S.charToken + 1
	local token = S.charToken
	local hum = char:WaitForChild("Humanoid", 10)
	local hrp = char:WaitForChild("HumanoidRootPart", 10)
	if not (hum and hrp) or token ~= S.charToken then return end
	local torso = char:FindFirstChild("UpperTorso") or char:FindFirstChild("Torso")
	if not torso then
		local t0 = os.clock()
		repeat
			task.wait(0.1)
			torso = char:FindFirstChild("UpperTorso") or char:FindFirstChild("Torso")
		until torso or os.clock() - t0 > 8 or token ~= S.charToken
	end
	if not torso or token ~= S.charToken or not S.alive then return end

	S.char, S.hum, S.hrp, S.torso = char, hum, hrp, torso
	S.hover = (hum.RigType == Enum.HumanoidRigType.R15) and (hrp.Size.Y * 0.5 + hum.HipHeight) or 3
	S.lastHealth = hum.Health
	S.curN = Vector3.new(0, 1, 0)
	S.targetN = Vector3.new(0, 1, 0)

	buildArms()
	S.rp.FilterDescendantsInstances = { char, S.model }
	S.torso = torso
	updateArms(0.016, os.clock())
	S.model.Parent = Workspace

	track(S.charConns, hum.HealthChanged:Connect(function(h)
		if h < S.lastHealth then pcall(onDamaged, S.lastHealth - h) end
		S.lastHealth = h
	end))
	track(S.charConns, hum.Died:Connect(function()
		pcall(setClimb, false)
		pcall(setBlockMover, false)
	end))
	S.hudDirty = true
end

-- ===================== HUD TÁTIL MOBILE =====================
local U = { dots = {} }

local function mk(class, props, parent)
	local o = Instance.new(class)
	for k, v in pairs(props) do o[k] = v end
	if parent then o.Parent = parent end
	return o
end

local function styled(o, radius, strokeColor, thick)
	mk("UICorner", { CornerRadius = UDim.new(0, radius) }, o)
	if strokeColor then
		mk("UIStroke", { Color = strokeColor, Thickness = thick or 1, Transparency = 0.35, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, o)
	end
	return o
end

local function mkBtn(parent, text, x, y, w, h, color)
	local b = mk("TextButton", {
		Text = text, Size = UDim2.fromOffset(w, h), Position = UDim2.fromOffset(x, y),
		BackgroundColor3 = C.btn, TextColor3 = color or C.text, Font = Enum.Font.GothamBold,
		TextSize = 12, AutoButtonColor = true, BorderSizePixel = 0, TextWrapped = true,
	}, parent)
	styled(b, 8, color or C.dim, 1.2)
	return b
end

local PANEL_W, PANEL_H = 236, 310

local function buildHUD()
	local gui = mk("ScreenGui", {
		Name = GUI_NAME, ResetOnSpawn = false, IgnoreGuiInset = true,
		DisplayOrder = 100, ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	})
	local cands = {}
	pcall(function() if gethui then cands[#cands + 1] = gethui() end end)
	cands[#cands + 1] = CoreGui
	pcall(function() cands[#cands + 1] = player:WaitForChild("PlayerGui", 5) end)
	for _, cand in ipairs(cands) do
		local ok = pcall(function() gui.Parent = cand end)
		if ok and gui.Parent == cand then break end
	end
	U.gui = gui

	local cam = Workspace.CurrentCamera
	local vp = cam and cam.ViewportSize or Vector2.new(800, 400)
	local sc = clamp(vp.Y / 520, 0.7, 1)

	local panel = mk("Frame", {
		Name = "Painel", Size = UDim2.fromOffset(PANEL_W, PANEL_H),
		Position = UDim2.fromOffset(max(vp.X - PANEL_W * sc - 12, 0), max(12, vp.Y * 0.05)),
		BackgroundColor3 = C.bg, BackgroundTransparency = 0.1, BorderSizePixel = 0,
	}, gui)
	styled(panel, 10, C.cyan, 1.5)
	mk("UIScale", { Scale = sc }, panel)
	U.panel = panel

	local header = mk("Frame", { Size = UDim2.new(1, 0, 0, 30), BackgroundColor3 = Color3.fromRGB(8, 10, 15), BorderSizePixel = 0 }, panel)
	styled(header, 10)
	mk("TextLabel", {
		Size = UDim2.new(1, -40, 1, 0), Position = UDim2.fromOffset(10, 0), BackgroundTransparency = 1,
		Text = "◈ BRAÇOS ARANHA MK-IV", TextColor3 = C.cyan, Font = Enum.Font.GothamBold,
		TextSize = 13, TextXAlignment = Enum.TextXAlignment.Left,
	}, header)
	local minBtn = mk("TextButton", {
		Size = UDim2.fromOffset(28, 22), Position = UDim2.new(1, -34, 0, 4), BackgroundColor3 = C.btn,
		Text = "–", TextColor3 = C.text, Font = Enum.Font.GothamBold, TextSize = 16, BorderSizePixel = 0,
	}, header)
	styled(minBtn, 6)

	local body = mk("Frame", { Size = UDim2.new(1, 0, 0, PANEL_H - 30), Position = UDim2.fromOffset(0, 30), BackgroundTransparency = 1 }, panel)
	U.body = body

	U.status = mk("TextLabel", {
		Size = UDim2.fromOffset(220, 18), Position = UDim2.fromOffset(8, 4), BackgroundTransparency = 1,
		Text = "SISTEMA EM REPOUSO", TextColor3 = C.dim, Font = Enum.Font.GothamBold, TextSize = 12,
		TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd,
	}, body)

	local barBg = mk("Frame", { Size = UDim2.fromOffset(220, 16), Position = UDim2.fromOffset(8, 26), BackgroundColor3 = C.dark, BorderSizePixel = 0 }, body)
	styled(barBg, 5, C.dim, 1)
	U.fill = mk("Frame", { Size = UDim2.new(0, 0, 1, 0), BackgroundColor3 = C.cyan, BorderSizePixel = 0 }, barBg)
	styled(U.fill, 5)
	U.barLbl = mk("TextLabel", {
		Size = UDim2.new(1, 0, 1, 0), BackgroundTransparency = 1, Text = "DESGASTE 0%", TextColor3 = C.text,
		Font = Enum.Font.GothamBold, TextSize = 10, ZIndex = 3,
	}, barBg)

	for k = 1, 4 do
		local d = mk("Frame", {
			Size = UDim2.fromOffset(52, 6), Position = UDim2.fromOffset(8 + (k - 1) * 56, 46),
			BackgroundColor3 = C.cyan, BorderSizePixel = 0,
		}, body)
		styled(d, 3)
		U.dots[k] = d
	end

	U.toggle = mkBtn(body, "GARRAS MAGNÉTICAS: OFF", 8, 60, 220, 40, C.cyan)
	U.mover = mkBtn(body, "ROBÔ MEXE BLOCOS: OFF", 8, 104, 220, 40, C.yellow)
	U.jump = mkBtn(body, "SALTAR", 8, 148, 106, 38, C.green)
	U.turboBtn = mkBtn(body, "TURBO: OFF", 122, 148, 106, 38, C.orange)
	U.drop = mkBtn(body, "SOLTAR", 8, 190, 106, 38, C.yellow)
	U.repair = mkBtn(body, "REPARAR", 122, 190, 106, 38, C.text)
	U.actionInfo = mkBtn(body, "CLIQUE NA TELA PARA MOVER BLOCO", 8, 232, 220, 38, C.dim)
	U.actionInfo.TextSize = 11

	track(S.conns, U.toggle.Activated:Connect(function() setClimb(not S.climbMode) end))
	track(S.conns, U.mover.Activated:Connect(function() setBlockMover(not S.blockMoverMode) end))
	track(S.conns, U.jump.Activated:Connect(doJump))
	track(S.conns, U.drop.Activated:Connect(doDrop))
	track(S.conns, U.turboBtn.Activated:Connect(function()
		S.turbo = not S.turbo
		S.hudDirty = true
	end))
	track(S.conns, U.repair.Activated:Connect(doRepair))

	-- Interação por toque ou clique na tela inteira do jogo para selecionar bloco e destino
	track(S.conns, UIS.InputBegan:Connect(function(input, processed)
		if not processed and S.blockMoverMode and not S.failure then
			if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
				handleScreenClick()
			end
		end
	end))

	local collapsed = false
	track(S.conns, minBtn.Activated:Connect(function()
		collapsed = not collapsed
		body.Visible = not collapsed
		panel.Size = UDim2.fromOffset(PANEL_W, collapsed and 30 or PANEL_H)
		minBtn.Text = collapsed and "+" or "–"
	end))

	local dragging, dragInput, dragStart, startAbs = false, nil, nil, nil
	track(S.conns, header.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			dragging = true
			dragStart = input.Position
			startAbs = panel.AbsolutePosition
			track(S.conns, input.Changed:Connect(function()
				if input.UserInputState == Enum.UserInputState.End then dragging = false end
			end))
		end
	end))
	track(S.conns, header.InputChanged:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
			dragInput = input
		end
	end))
	track(S.conns, UIS.InputChanged:Connect(function(input)
		if dragging and input == dragInput and dragStart then
			local d = input.Position - dragStart
			local v = (Workspace.CurrentCamera and Workspace.CurrentCamera.ViewportSize) or Vector2.new(800, 400)
			local sz = panel.AbsoluteSize
			panel.Position = UDim2.fromOffset(
				clamp(startAbs.X + d.X, 0, max(v.X - sz.X, 0)),
				clamp(startAbs.Y + d.Y, 0, max(v.Y - 30, 0))
			)
		end
	end))
end

local function statusText()
	if S.failure then return "FALHA DOS MOTORES · A ARREFECER", C.red end
	if S.blockMoverMode then
		if S.targetBlock and not S.targetPos then return "MEXE BLOCOS · CLIQUE NO ALVO", C.yellow end
		if S.targetBlock and S.targetPos then return "MEXE BLOCOS · A TRANSPORTAR", C.yellow end
		return "MEXE BLOCOS · CLIQUE NO BLOCO", C.yellow
	end
	if not S.climbMode then return "MAGNETISMO DESLIGADO", C.dim end
	if S.attached then
		local y = S.targetN.Y
		local surf = (y > 0.7 and "CHÃO") or (y < -0.7 and "TETO") or "PAREDE"
		local txt = "ACOPLADO · " .. surf
		if S.turbo then txt = txt .. " · TURBO" end
		if S.maxWear >= 75 then return txt .. " · CRÍTICO", C.red end
		if S.maxWear >= 40 then return txt .. " · SOBREAQUECIDO", C.orange end
		return txt, C.cyan
	end
	return "A PROCURAR SUPERFÍCIE...", C.yellow
end

local function updateHUD(now)
	if not U.gui or not U.status then return end
	local st, col = statusText()
	U.status.Text = st
	U.status.TextColor3 = col
	local mw = S.maxWear
	U.fill.Size = UDim2.new(clamp(mw / 100, 0, 1), 0, 1, 0)
	U.fill.BackgroundColor3 = wearColor(mw)
	U.barLbl.Text = string.format("DESGASTE %d%%  ·  MÉDIA %d%%", floor(mw + 0.5), floor(S.avgWear + 0.5))
	for i, d in ipairs(U.dots) do
		local arm = S.arms[i]
		d.BackgroundColor3 = arm and wearColor(arm.wear) or C.dark
	end
	if S.failure then
		U.toggle.Text = "REARMANDO MOTORES..."
		U.toggle.TextColor3 = C.red
		U.toggle.BackgroundColor3 = Color3.fromRGB(45, 18, 18)
		U.mover.Text = "BLOQUEADO"
		U.actionInfo.Text = "SISTEMA EM FALHA"
	elseif S.climbMode then
		U.toggle.Text = "GARRAS MAGNÉTICAS: ON"
		U.toggle.TextColor3 = C.bg
		U.toggle.BackgroundColor3 = C.cyan
		U.mover.Text = "ROBÔ MEXE BLOCOS: OFF"
		U.mover.TextColor3 = C.yellow
		U.mover.BackgroundColor3 = C.btn
		U.actionInfo.Text = "MODO ESCALADA ATIVO"
	elseif S.blockMoverMode then
		U.toggle.Text = "GARRAS MAGNÉTICAS: OFF"
		U.toggle.TextColor3 = C.cyan
		U.toggle.BackgroundColor3 = C.btn
		U.mover.Text = "ROBÔ MEXE BLOCOS: ON"
		U.mover.TextColor3 = C.bg
		U.mover.BackgroundColor3 = C.yellow
		if not S.targetBlock then
			U.actionInfo.Text = "1. CLIQUE NUM BLOCO"
		elseif not S.targetPos then
			U.actionInfo.Text = "2. CLIQUE NO DESTINO"
		else
			U.actionInfo.Text = "MOVENDO BLOCO..."
		end
	else
		U.toggle.Text = "GARRAS MAGNÉTICAS: OFF"
		U.toggle.TextColor3 = C.cyan
		U.toggle.BackgroundColor3 = C.btn
		U.mover.Text = "ROBÔ MEXE BLOCOS: OFF"
		U.mover.TextColor3 = C.yellow
		U.mover.BackgroundColor3 = C.btn
		U.actionInfo.Text = "ROBÔ DESATIVADO"
	end
	U.turboBtn.Text = S.turbo and "TURBO: ON" or "TURBO: OFF"
	U.turboBtn.TextColor3 = S.turbo and C.bg or C.orange
	U.turboBtn.BackgroundColor3 = S.turbo and C.orange or C.btn
	local rem = S.repairReadyAt - now
	U.repair.Text = rem > 0 and string.format("REPARAR (%ds)", floor(rem + 0.99)) or "REPARAR"
	U.repair.TextColor3 = rem > 0 and C.dim or C.text
end

buildHUD()

-- ===================== LIGAÇÕES / LOOPS =====================
track(S.conns, UIS.JumpRequest:Connect(function()
	pcall(doJump)
end))

track(S.conns, RunService.Heartbeat:Connect(function(dt)
	local ok, e = pcall(function()
		local hum, hrp = S.hum, S.hrp
		if not (hum and hrp and hrp.Parent and #S.arms > 0) then return end
		local now = os.clock()
		updateWear(dt)
		sparkStep(dt, now)
		if S.blockMoverMode then
			updateBlockMover(dt)
		end
		if hum.Health <= 0 then return end
		if S.climbMode and not S.failure then
			if S.attached then attachedStep(dt, now) else scanAttach(now) end
		end
	end)
	if not ok then
		S.errCount = S.errCount + 1
		if S.errCount <= 3 then warn("[BracosAranha] " .. tostring(e)) end
	end
end))

track(S.conns, RunService.RenderStepped:Connect(function(dt)
	pcall(function()
		local now = os.clock()
		updateArms(dt, now)
		if now - S.lastFx > 0.1 then
			S.lastFx = now
			applyWearFX(now)
		end
		if S.hudDirty or now - S.lastHud > 0.12 then
			S.lastHud = now
			S.hudDirty = false
			updateHUD(now)
		end
	end)
end))

track(S.conns, player.CharacterAdded:Connect(function(c)
	task.spawn(function()
		local ok, e = pcall(setupChar, c)
		if not ok then warn("[BracosAranha] " .. tostring(e)) end
	end)
end))
track(S.conns, player.CharacterRemoving:Connect(function()
	pcall(cleanupChar)
end))

ENV[CLEAN_KEY] = function()
	S.alive = false
	disconnectAll(S.conns)
	pcall(cleanupChar)
	if U.gui then pcall(function() U.gui:Destroy() end) end
	destroyLeftovers()
end

if player.Character then
	task.spawn(function()
		local ok, e = pcall(setupChar, player.Character)
		if not ok then warn("[BracosAranha] " .. tostring(e)) end
	end)
end

end)

if not okRun then
	warn("[BracosAranha] erro de inicialização: " .. tostring(errRun))
	pcall(function()
		local env = (getgenv and getgenv()) or _G
		local f = env["__BracosAranhaRobo_Cleanup"]
		if f then f() env["__BracosAranhaRobo_Cleanup"] = nil end
	end)
end
end)
