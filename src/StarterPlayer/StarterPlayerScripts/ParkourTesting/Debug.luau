local Workspace = game:GetService("Workspace")
local Debris = game:GetService("Debris")

local Configs = require(script.Parent:WaitForChild("Configs"))

local Debug = {}

-- ══════════════════════════════════════
-- Pasta de Debug no Workspace
-- ══════════════════════════════════════

local function getDebugFolder()
	local folder = Workspace:FindFirstChild(Configs.DebugFolderName)
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = Configs.DebugFolderName
		folder.Parent = Workspace
	end
	return folder
end

-- ══════════════════════════════════════
-- Limpar Debug
-- ══════════════════════════════════════

function Debug.ClearDebug()
	local folder = Workspace:FindFirstChild(Configs.DebugFolderName)
	if folder then
		folder:Destroy()
	end
end

-- ══════════════════════════════════════
-- Log no Console
-- ══════════════════════════════════════

function Debug.Log(...)
	if not Configs.DebugEnabled then
		return
	end
	print("[ParkourDebug]", ...)
end

function Debug.Verbose(...)
	if not Configs.DebugVerbose then
		return
	end
	print("[ParkourVerbose]", ...)
end

-- ══════════════════════════════════════
-- Desenhar Visual: Raio
-- ══════════════════════════════════════

function Debug.DrawRay(origin, hitPosition, color)
	if not Configs.DebugEnabled then
		return nil
	end

	local folder = getDebugFolder()

	local rayPart = Instance.new("Part")
	rayPart.Name = "Ray"
	rayPart.Anchored = true
	rayPart.CanCollide = false
	rayPart.CanQuery = false
	rayPart.CanTouch = false
	rayPart.Material = Enum.Material.Neon
	rayPart.Color = color or Color3.fromRGB(0, 255, 0)
	rayPart.Size = Vector3.new(0.08, 0.08, (hitPosition - origin).Magnitude)
	rayPart.CFrame = CFrame.lookAt((origin + hitPosition) / 2, hitPosition)
	rayPart.Parent = folder

	Debris:AddItem(rayPart, Configs.DebugLifetime)

	return rayPart
end

-- ══════════════════════════════════════
-- Desenhar Visual: Ponto (esfera)
-- ══════════════════════════════════════

function Debug.DrawPoint(position, color, size)
	if not Configs.DebugEnabled then
		return nil
	end

	local folder = getDebugFolder()

	local point = Instance.new("Part")
	point.Name = "EdgePoint"
	point.Shape = Enum.PartType.Ball
	point.Anchored = true
	point.CanCollide = false
	point.CanQuery = false
	point.CanTouch = false
	point.Material = Enum.Material.Neon
	point.Color = color or Color3.fromRGB(255, 0, 0)
	point.Size = size or Vector3.new(0.28, 0.28, 0.28)
	point.Position = position
	point.Parent = folder

	Debris:AddItem(point, Configs.DebugLifetime)

	return point
end

-- ══════════════════════════════════════
-- Desenhar Visual: Box (transparente)
-- ══════════════════════════════════════

function Debug.DrawBox(cframe, size, color)
	if not Configs.DebugEnabled then
		return nil
	end

	local folder = getDebugFolder()

	local box = Instance.new("Part")
	box.Name = "DebugBox"
	box.Anchored = true
	box.CanCollide = false
	box.CanQuery = false
	box.CanTouch = false
	box.Material = Enum.Material.ForceField
	box.Transparency = 0.65
	box.Color = color or Color3.fromRGB(0, 170, 255)
	box.Size = size
	box.CFrame = cframe
	box.Parent = folder

	Debris:AddItem(box, Configs.DebugLifetime)

	return box
end

-- ══════════════════════════════════════
-- Desenhar Visual: Linha entre 2 pontos
-- ══════════════════════════════════════

function Debug.DrawLine(posA, posB, color)
	if not Configs.DebugEnabled then
		return nil
	end

	local folder = getDebugFolder()
	local dist = (posB - posA).Magnitude

	local line = Instance.new("Part")
	line.Name = "DebugLine"
	line.Anchored = true
	line.CanCollide = false
	line.CanQuery = false
	line.CanTouch = false
	line.Material = Enum.Material.Neon
	line.Transparency = 0.3
	line.Color = color or Color3.fromRGB(255, 255, 0)
	line.Size = Vector3.new(0.04, 0.04, dist)
	line.CFrame = CFrame.lookAt((posA + posB) / 2, posB)
	line.Parent = folder

	Debris:AddItem(line, Configs.DebugLifetime)

	return line
end

-- ══════════════════════════════════════
-- Desenhar Debug Completo de um Resultado
-- ══════════════════════════════════════

function Debug.DrawDebug(data)
	if not Configs.DebugEnabled then
		return
	end

	if not data then
		return
	end

	-- Rays da varredura vertical
	if data.RayDebug then
		for _, rayInfo in ipairs(data.RayDebug) do
			Debug.DrawRay(
				rayInfo.Origin,
				rayInfo.HitPosition,
				rayInfo.Hit and Color3.fromRGB(0, 255, 0) or Color3.fromRGB(0, 120, 0)
			)
		end
	elseif data.Origin and data.HitPosition then
		Debug.DrawRay(data.Origin, data.HitPosition, Color3.fromRGB(0, 255, 0))
	end

	-- Ray extra: torso
	if data.TorsoRayDebug then
		local t = data.TorsoRayDebug
		Debug.DrawRay(t.Origin, t.HitPosition, t.Hit and Color3.fromRGB(255, 200, 0) or Color3.fromRGB(120, 100, 0))
	end

	-- Ray extra: perna
	if data.LegRayDebug then
		local l = data.LegRayDebug
		Debug.DrawRay(l.Origin, l.HitPosition, l.Hit and Color3.fromRGB(0, 150, 255) or Color3.fromRGB(0, 60, 120))
	end

	-- Linha de debug da distância da Head até a borda
	if data.DistanceLine then
		Debug.DrawLine(data.DistanceLine.PosA, data.DistanceLine.PosB, data.DistanceLine.Color)
	end

	-- Ponto da borda
	if data.EdgePosition then
		Debug.DrawPoint(data.EdgePosition, Color3.fromRGB(255, 0, 0))
	end

	-- Clearance de agarrar (topo / frente)
	if data.TopClearanceCFrame and data.TopClearanceSize then
		Debug.DrawBox(data.TopClearanceCFrame, data.TopClearanceSize, Color3.fromRGB(0, 170, 255))
	end

	if data.FrontClearanceCFrame and data.FrontClearanceSize then
		Debug.DrawBox(data.FrontClearanceCFrame, data.FrontClearanceSize, Color3.fromRGB(255, 170, 0))
	end

	-- Clearance de vault (destino)
	if data.VaultClearanceCFrame and data.VaultClearanceSize then
		Debug.DrawBox(data.VaultClearanceCFrame, data.VaultClearanceSize, Color3.fromRGB(0, 255, 100))
	end
end

-- ══════════════════════════════════════
-- Debug Completo de Subir/Escalar
-- Mostra TODOS os rays e caixas de verificação
-- ══════════════════════════════════════

function Debug.DrawClimbDebug(escalarResult, subirResult)
	if not Configs.DebugEnabled then
		return
	end

	-- ═══ Escalar: clearance box + floor ray ═══
	if escalarResult then
		-- Caixa de clearance do escalar (magenta)
		if escalarResult.ClearanceCFrame and escalarResult.ClearanceSize then
			local cor = escalarResult.CanEscalar and Color3.fromRGB(255, 0, 0) -- magenta = pode escalar
				or Color3.fromRGB(120, 0, 0) -- escuro = não pode
			Debug.DrawBox(escalarResult.ClearanceCFrame, escalarResult.ClearanceSize, cor)
		end

		-- Floor ray (amarelo = tem chão, vermelho = sem chão)
		if escalarResult.FloorRayDebug then
			local f = escalarResult.FloorRayDebug
			Debug.DrawRay(f.Origin, f.HitPosition, f.Hit and Color3.fromRGB(255, 255, 0) or Color3.fromRGB(255, 0, 0))
			-- Ponto onde o floor ray começa (posição final do escalar)
			Debug.DrawPoint(f.Origin, Color3.fromRGB(255, 255, 0), Vector3.new(0.35, 0.35, 0.35))
		end
	end

	-- ═══ Subir: up ray + forward rays ═══
	if subirResult and subirResult.Debug then
		local subirDebug = subirResult.Debug

		-- Ray vertical para cima (ciano)
		if subirDebug.UpRay then
			local u = subirDebug.UpRay
			Debug.DrawRay(u.Origin, u.HitPosition, u.Hit and Color3.fromRGB(0, 255, 255) or Color3.fromRGB(0, 120, 120))
		end

		-- Rays horizontais (verde brilhante = hit, escuro = miss)
		if subirDebug.ForwardRays then
			for _, rayInfo in ipairs(subirDebug.ForwardRays) do
				Debug.DrawRay(
					rayInfo.Origin,
					rayInfo.HitPosition,
					rayInfo.Hit and Color3.fromRGB(100, 255, 100) or Color3.fromRGB(50, 100, 50)
				)
			end
		end

		-- Ponto da borda encontrada (se existir)
		if subirResult.EdgePosition then
			Debug.DrawPoint(subirResult.EdgePosition, Color3.fromRGB(255, 100, 0), Vector3.new(0.35, 0.35, 0.35))
		end
	end
end

return Debug
