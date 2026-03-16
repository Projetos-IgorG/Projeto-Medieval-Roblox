--!nonstrict
-- Custom footstep system using animation marker "Footstep"

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Footsteps = require(script:WaitForChild("Footsteps"))
local ClientBridge = require(ReplicatedStorage:WaitForChild("Modulos"):WaitForChild("Core"):WaitForChild("ClientBridge"))

local FOOTSTEP_MARKER = "Footstep"

local CONFIG = {
	DefaultMaterial = "Concrete",
	JumpSoundId = "rbxasset://sounds/action_jump.mp3",
	JumpVolume = 0.25,
	FreefallSoundId = "rbxasset://sounds/action_falling.ogg",
	FreefallVolume = 0.45,
	FreefallFadeInSeconds = 1.0,
	FreefallStartVelocityY = -50.0,
	LandingPlaybackSpeed = 0.65,
	LandingVolumeMultiplier = 2.5,
	PitchWalk = { min = 0.6, max = 0.7 },
	PitchRun = { min = 0.8, max = 0.9 },
}

local player = Players.LocalPlayer

local rng = Random.new()
local soundFolder = SoundService:FindFirstChild("Footstep")

local function getStatusLocal(character: Model): Folder?
	local statusLocal = character:FindFirstChild("StatusLocal")
	if statusLocal and statusLocal:IsA("Folder") then
		return statusLocal
	end
	return nil
end

local function getSoundTemplate(materialKey: string): Sound?
	if not soundFolder or not soundFolder.Parent then
		soundFolder = SoundService:FindFirstChild("Footstep")
	end

	if not soundFolder then
		return nil
	end

	local sound = soundFolder:FindFirstChild(materialKey)
	if sound and sound:IsA("Sound") then
		return sound
	end
	return nil
end

local function getMaterialKey(humanoid: Humanoid): string
	return Footsteps.materialMap[humanoid.FloorMaterial] or CONFIG.DefaultMaterial
end

local function isDashAction(estadoAcao: string?): boolean
	return estadoAcao ~= nil and string.find(estadoAcao, "Dash") ~= nil
end

local function getPitchRange(estadoMov: string?)
	if estadoMov == "Correndo" then
		return CONFIG.PitchRun
	end
	return CONFIG.PitchWalk
end

local function chooseRandomPitch(estadoMov: string?): number
	local pitchRange = getPitchRange(estadoMov)
	return rng:NextNumber(pitchRange.min, pitchRange.max)
end

local function estimateCleanupSeconds(sound: Sound, playbackSpeed: number): number
	local speed = math.max(playbackSpeed, 0.05)
	return (sound.TimeLength / speed) + 0.2
end

local function playMaterialSound(rootPart: BasePart, materialKey: string, playbackSpeed: number, volumeMultiplier: number?)
	local soundTemplate = getSoundTemplate(materialKey)
	if not soundTemplate then
		return
	end

	local sound = soundTemplate:Clone()
	sound.Archivable = false

	sound.Parent = rootPart
	sound.Volume = sound.Volume * (volumeMultiplier or 1)

	sound.PlaybackSpeed = playbackSpeed
	sound:Play()
	Debris:AddItem(sound, estimateCleanupSeconds(sound, playbackSpeed))
end

local function canEmitByEnvironment(humanoid: Humanoid, statusState, allowDuringDash: boolean?): boolean
	if humanoid.FloorMaterial == Enum.Material.Air then
		return false
	end

	if not allowDuringDash and statusState.dashOn then
		return false
	end

	if not allowDuringDash and isDashAction(statusState.estadoAcao) then
		return false
	end

	if not allowDuringDash and ClientBridge.EstaEmDash and ClientBridge.EstaEmDash() then
		return false
	end

	return true
end

local function canEmitStep(humanoid: Humanoid, statusState): boolean
	if not canEmitByEnvironment(humanoid, statusState) then
		return false
	end

	local estadoMov = statusState.estadoMov
	if not estadoMov then
		if humanoid.MoveDirection.Magnitude > 0.05 then
			estadoMov = "Andando"
		else
			estadoMov = "Parado"
		end
	end

	return estadoMov == "Andando" or estadoMov == "Correndo"
end

local function playFootstep(humanoid: Humanoid, rootPart: BasePart, statusState)
	if not canEmitStep(humanoid, statusState) then
		return
	end

	local materialKey = getMaterialKey(humanoid)

	-- Revalida logo antes do play para cobrir race no início do dash.
	if not canEmitStep(humanoid, statusState) then
		return
	end

	local playbackSpeed = chooseRandomPitch(statusState.estadoMov)
	playMaterialSound(rootPart, materialKey, playbackSpeed)
end

local function playLandingFootstep(humanoid: Humanoid, rootPart: BasePart, statusState)
	if not canEmitByEnvironment(humanoid, statusState, true) then
		return
	end

	local materialKey = getMaterialKey(humanoid)
	playMaterialSound(rootPart, materialKey, CONFIG.LandingPlaybackSpeed, CONFIG.LandingVolumeMultiplier)
end

local function playJumpSound(rootPart: BasePart)
	local sound = Instance.new("Sound")
	sound.Archivable = false
	sound.Name = "Jump"
	sound.SoundId = CONFIG.JumpSoundId
	sound.Volume = CONFIG.JumpVolume
	sound.Parent = rootPart
	sound:Play()
	Debris:AddItem(sound, estimateCleanupSeconds(sound, 1.0))
end

local function ensureFreefallSound(rootPart: BasePart, current: Sound?): Sound
	if current and current.Parent then
		return current
	end

	local sound = Instance.new("Sound")
	sound.Archivable = false
	sound.Name = "FreeFalling"
	sound.SoundId = CONFIG.FreefallSoundId
	sound.Volume = CONFIG.FreefallVolume
	sound.Looped = true
	sound.Parent = rootPart
	return sound
end

local function bindCharacter(character: Model)
	local humanoid = character:WaitForChild("Humanoid") :: Humanoid
	local rootPart = character:WaitForChild("HumanoidRootPart") :: BasePart
	local statusLocal = getStatusLocal(character)

	local statusState = {
		estadoMov = nil :: string?,
		estadoAcao = nil :: string?,
		dashOn = false,
	}

	local trackConnections = {}
	local statusConnections = {}
	local statusFolderConnection: RBXScriptConnection? = nil
	local freefallHeartbeatConn: RBXScriptConnection? = nil
	local freefallSound: Sound? = nil
	local freefallFadeTween: Tween? = nil
	local isInFreefall = false

	local function stopFreefallSound()
		if freefallFadeTween then
			freefallFadeTween:Cancel()
			freefallFadeTween = nil
		end
		if freefallSound and freefallSound.IsPlaying then
			freefallSound:Stop()
		end
	end

	local function updateFreefallSound()
		if not isInFreefall then
			stopFreefallSound()
			return
		end

		local verticalSpeed = rootPart.AssemblyLinearVelocity.Y
		if verticalSpeed <= CONFIG.FreefallStartVelocityY then
			local sound = ensureFreefallSound(rootPart, freefallSound)
			freefallSound = sound
			if not sound.IsPlaying then
				sound.Volume = 0
				sound:Play()
				local tween = TweenService:Create(
					sound,
					TweenInfo.new(CONFIG.FreefallFadeInSeconds, Enum.EasingStyle.Sine, Enum.EasingDirection.Out),
					{ Volume = CONFIG.FreefallVolume }
				)
				freefallFadeTween = tween
				tween:Play()
			end
		else
			stopFreefallSound()
		end
	end

	local function clearStatusConnections()
		for _, conn in ipairs(statusConnections) do
			if conn.Connected then
				conn:Disconnect()
			end
		end
		table.clear(statusConnections)
	end

	local function watchStatusString(folder: Folder, name: string, updateFn)
		if not statusLocal then
			return
		end
		local valueObj = folder:FindFirstChild(name)
		if valueObj and valueObj:IsA("StringValue") then
			updateFn(valueObj.Value)
			table.insert(statusConnections, valueObj:GetPropertyChangedSignal("Value"):Connect(function()
				updateFn(valueObj.Value)
			end))
		end
	end

	local function watchStatusBool(folder: Folder, name: string, updateFn)
		if not statusLocal then
			return
		end
		local valueObj = folder:FindFirstChild(name)
		if valueObj and valueObj:IsA("BoolValue") then
			updateFn(valueObj.Value)
			table.insert(statusConnections, valueObj:GetPropertyChangedSignal("Value"):Connect(function()
				updateFn(valueObj.Value)
			end))
		end
	end

	local function bindStatusFolder(folder: Folder)
		statusLocal = folder
		clearStatusConnections()

		watchStatusString(folder, "estadoMov", function(value)
			statusState.estadoMov = value
		end)

		watchStatusString(folder, "estadoAcao", function(value)
			statusState.estadoAcao = value
		end)

		watchStatusBool(folder, "DashOn", function(value)
			statusState.dashOn = value
		end)
	end

	if statusLocal then
		bindStatusFolder(statusLocal)
	else
		statusFolderConnection = character.ChildAdded:Connect(function(child)
			if child.Name == "StatusLocal" and child:IsA("Folder") then
				bindStatusFolder(child)
			end
		end)
	end

	local function onTrackPlayed(track: AnimationTrack)
		if trackConnections[track] then
			return
		end

		local markerConn = track:GetMarkerReachedSignal(FOOTSTEP_MARKER):Connect(function()
			playFootstep(humanoid, rootPart, statusState)
		end)

		local stoppedConn = track.Stopped:Connect(function()
			local conns = trackConnections[track]
			if not conns then
				return
			end
			conns.marker:Disconnect()
			conns.stopped:Disconnect()
			trackConnections[track] = nil
		end)

		trackConnections[track] = {
			marker = markerConn,
			stopped = stoppedConn,
		}
	end

	local playedConn = humanoid.AnimationPlayed:Connect(onTrackPlayed)
	local stateChangedConn = humanoid.StateChanged:Connect(function(oldState: Enum.HumanoidStateType, newState: Enum.HumanoidStateType)
		if newState == Enum.HumanoidStateType.Jumping then
			isInFreefall = false
			stopFreefallSound()
			playJumpSound(rootPart)
			return
		end

		isInFreefall = newState == Enum.HumanoidStateType.Freefall
		updateFreefallSound()

		if newState ~= Enum.HumanoidStateType.Landed then
			return
		end

		if oldState ~= Enum.HumanoidStateType.Freefall and oldState ~= Enum.HumanoidStateType.Jumping then
			return
		end

		playLandingFootstep(humanoid, rootPart, statusState)
	end)
	freefallHeartbeatConn = RunService.Heartbeat:Connect(function()
		updateFreefallSound()
	end)

	local function cleanup()
		if playedConn.Connected then
			playedConn:Disconnect()
		end
		if stateChangedConn.Connected then
			stateChangedConn:Disconnect()
		end
		if freefallHeartbeatConn and freefallHeartbeatConn.Connected then
			freefallHeartbeatConn:Disconnect()
		end
		if freefallSound then
			freefallSound:Destroy()
			freefallSound = nil
		end
		if freefallFadeTween then
			freefallFadeTween:Cancel()
			freefallFadeTween = nil
		end
		for track, conns in pairs(trackConnections) do
			conns.marker:Disconnect()
			conns.stopped:Disconnect()
			trackConnections[track] = nil
		end
		clearStatusConnections()
		if statusFolderConnection and statusFolderConnection.Connected then
			statusFolderConnection:Disconnect()
		end
	end

	return cleanup
end

local cleanupCharacter: (() -> ())? = nil

local function onCharacterAdded(character: Model)
	if cleanupCharacter then
		cleanupCharacter()
	end
	cleanupCharacter = bindCharacter(character)
end

local function onCharacterRemoving()
	if cleanupCharacter then
		cleanupCharacter()
		cleanupCharacter = nil
	end
end

if player.Character then
	onCharacterAdded(player.Character)
end

player.CharacterAdded:Connect(onCharacterAdded)
player.CharacterRemoving:Connect(onCharacterRemoving)
