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

	-- Caixa primária de detecção frontal por bloco
	if data.ForwardQueryBoxCFrame and data.ForwardQueryBoxSize then
		Debug.DrawBox(data.ForwardQueryBoxCFrame, data.ForwardQueryBoxSize, Color3.fromRGB(80, 200, 255))
	end

	if data.ForwardCandidatePoints then
		for _, point in ipairs(data.ForwardCandidatePoints) do
			Debug.DrawPoint(
				point.Position,
				point.Accepted and Color3.fromRGB(60, 255, 120) or Color3.fromRGB(255, 120, 120),
				Vector3.new(0.2, 0.2, 0.2)
			)
		end
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
	elseif data.Origin and data.HitPosition and not data.ForwardQueryBoxCFrame then
		Debug.DrawRay(data.Origin, data.HitPosition, Color3.fromRGB(0, 255, 0))
	end

	-- Ray extra: torso
	if data.TorsoRayDebug then
		local t = data.TorsoRayDebug
		Debug.DrawRay(t.Origin, t.HitPosition, t.Hit and Color3.fromRGB(255, 200, 0) or Color3.fromRGB(120, 100, 0))
	end

	-- Ray extra: perna
	if data.LegProbeRaysDebug then
		if data.LegProbeRaysDebug.CFrame and data.LegProbeRaysDebug.Size then
			Debug.DrawBox(
				data.LegProbeRaysDebug.CFrame,
				data.LegProbeRaysDebug.Size,
				data.LegProbeRaysDebug.Clear and Color3.fromRGB(255, 120, 120) or Color3.fromRGB(0, 220, 255)
			)
		else
			for _, legRay in ipairs(data.LegProbeRaysDebug) do
				Debug.DrawRay(
					legRay.Origin,
					legRay.HitPosition,
					legRay.Hit and Color3.fromRGB(0, 180, 255) or Color3.fromRGB(0, 70, 120)
				)
			end
		end
	elseif data.LegRayDebug then
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
			if f.Probes then
				for _, probe in ipairs(f.Probes) do
					Debug.DrawRay(
						probe.Origin,
						probe.HitPosition,
						probe.Hit and Color3.fromRGB(255, 255, 0) or Color3.fromRGB(255, 0, 0)
					)
					Debug.DrawPoint(probe.Origin, Color3.fromRGB(255, 255, 0), Vector3.new(0.35, 0.35, 0.35))
				end
			else
				Debug.DrawRay(f.Origin, f.HitPosition, f.Hit and Color3.fromRGB(255, 255, 0) or Color3.fromRGB(255, 0, 0))
				Debug.DrawPoint(f.Origin, Color3.fromRGB(255, 255, 0), Vector3.new(0.35, 0.35, 0.35))
			end
		end
	end

	-- ═══ Subir: up ray + forward rays ═══
	if subirResult and subirResult.Debug then
		local subirDebug = subirResult.Debug

		if subirDebug.QueryBoxCFrame and subirDebug.QueryBoxSize then
			Debug.DrawBox(subirDebug.QueryBoxCFrame, subirDebug.QueryBoxSize, Color3.fromRGB(0, 180, 255))
		end

		if subirDebug.CandidatePoints then
			for _, point in ipairs(subirDebug.CandidatePoints) do
				Debug.DrawPoint(
					point.Position,
					point.Accepted and Color3.fromRGB(80, 255, 80) or Color3.fromRGB(255, 80, 80),
					Vector3.new(0.22, 0.22, 0.22)
				)
			end
		end

		if subirDebug.EscalarChecks then
			for _, escalarCheck in ipairs(subirDebug.EscalarChecks) do
				if escalarCheck.ClearanceCFrame and escalarCheck.ClearanceSize then
					Debug.DrawBox(
						escalarCheck.ClearanceCFrame,
						escalarCheck.ClearanceSize,
						escalarCheck.CanEscalar and Color3.fromRGB(0, 120, 255) or Color3.fromRGB(0, 50, 120)
					)
				end
			end
		end

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

		if subirResult.LegProbeRaysDebug and subirResult.LegProbeRaysDebug.CFrame and subirResult.LegProbeRaysDebug.Size then
			Debug.DrawBox(
				subirResult.LegProbeRaysDebug.CFrame,
				subirResult.LegProbeRaysDebug.Size,
				subirResult.LegProbeRaysDebug.Clear and Color3.fromRGB(255, 120, 120) or Color3.fromRGB(0, 220, 255)
			)
		end
	end
end

function Debug.DrawLateralDebug(lateralResult)
	if not Configs.DebugEnabled then
		return
	end

	if not lateralResult or not lateralResult.Debug then
		return
	end

	local lateralDebug = lateralResult.Debug
	if lateralDebug.QueryBoxCFrame and lateralDebug.QueryBoxSize then
		Debug.DrawBox(lateralDebug.QueryBoxCFrame, lateralDebug.QueryBoxSize, Color3.fromRGB(80, 150, 255))
	end

	if lateralDebug.CandidatePoints then
		for _, point in ipairs(lateralDebug.CandidatePoints) do
			Debug.DrawPoint(
				point.Position,
				point.Accepted and Color3.fromRGB(80, 255, 80) or Color3.fromRGB(255, 80, 80),
				Vector3.new(0.2, 0.2, 0.2)
			)
		end
	end

	if lateralDebug.PathClearanceBoxes then
		for _, boxInfo in ipairs(lateralDebug.PathClearanceBoxes) do
			Debug.DrawBox(
				boxInfo.CFrame,
				boxInfo.Size,
				boxInfo.Clear and Color3.fromRGB(0, 255, 140) or Color3.fromRGB(255, 60, 60)
			)
		end
	end

	if lateralDebug.PathClearanceRays then
		for _, rayInfo in ipairs(lateralDebug.PathClearanceRays) do
			Debug.DrawRay(
				rayInfo.Origin,
				rayInfo.HitPosition,
				rayInfo.Clear and Color3.fromRGB(40, 220, 255) or Color3.fromRGB(255, 90, 90)
			)
		end
	end

	if lateralResult.LegProbeRaysDebug and lateralResult.LegProbeRaysDebug.CFrame and lateralResult.LegProbeRaysDebug.Size then
		Debug.DrawBox(
			lateralResult.LegProbeRaysDebug.CFrame,
			lateralResult.LegProbeRaysDebug.Size,
			lateralResult.LegProbeRaysDebug.Clear and Color3.fromRGB(255, 120, 120) or Color3.fromRGB(0, 220, 255)
		)
	end

	if lateralDebug.SideRays then
		for _, rayInfo in ipairs(lateralDebug.SideRays) do
			Debug.DrawRay(
				rayInfo.Origin,
				rayInfo.HitPosition,
				rayInfo.Hit and Color3.fromRGB(0, 255, 180) or Color3.fromRGB(0, 90, 70)
			)
		end
	end

	if lateralDebug.ForwardRays then
		for _, rayInfo in ipairs(lateralDebug.ForwardRays) do
			Debug.DrawRay(
				rayInfo.Origin,
				rayInfo.HitPosition,
				rayInfo.Hit and Color3.fromRGB(100, 255, 100) or Color3.fromRGB(255, 80, 80)
			)
		end
	end

	if lateralResult.EdgePosition then
		Debug.DrawPoint(lateralResult.EdgePosition, Color3.fromRGB(255, 140, 0), Vector3.new(0.35, 0.35, 0.35))
	end
end

function Debug.DrawDescerDebug(descerResult)
	if not Configs.DebugEnabled then
		return
	end

	if not descerResult or not descerResult.Debug then
		return
	end

	local descerDebug = descerResult.Debug

	if descerDebug.QueryBoxCFrame and descerDebug.QueryBoxSize then
		Debug.DrawBox(descerDebug.QueryBoxCFrame, descerDebug.QueryBoxSize, Color3.fromRGB(0, 180, 255))
	end

	if descerDebug.CandidatePoints then
		for _, point in ipairs(descerDebug.CandidatePoints) do
			Debug.DrawPoint(
				point.Position,
				point.Accepted and Color3.fromRGB(80, 255, 80) or Color3.fromRGB(255, 80, 80),
				Vector3.new(0.22, 0.22, 0.22)
			)
		end
	end

	if descerDebug.DownRay then
		local d = descerDebug.DownRay
		Debug.DrawRay(d.Origin, d.HitPosition, d.Hit and Color3.fromRGB(0, 200, 255) or Color3.fromRGB(0, 90, 120))
	end

	if descerDebug.ForwardRays then
		for _, rayInfo in ipairs(descerDebug.ForwardRays) do
			Debug.DrawRay(
				rayInfo.Origin,
				rayInfo.HitPosition,
				rayInfo.Hit and Color3.fromRGB(120, 255, 120) or Color3.fromRGB(50, 100, 50)
			)
		end
	end

	if descerResult.EdgePosition then
		Debug.DrawPoint(descerResult.EdgePosition, Color3.fromRGB(255, 120, 0), Vector3.new(0.35, 0.35, 0.35))
	end

	if descerResult.LegProbeRaysDebug and descerResult.LegProbeRaysDebug.CFrame and descerResult.LegProbeRaysDebug.Size then
		Debug.DrawBox(
			descerResult.LegProbeRaysDebug.CFrame,
			descerResult.LegProbeRaysDebug.Size,
			descerResult.LegProbeRaysDebug.Clear and Color3.fromRGB(255, 120, 120) or Color3.fromRGB(0, 220, 255)
		)
	end
end

return Debug
