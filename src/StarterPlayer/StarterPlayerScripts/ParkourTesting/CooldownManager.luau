local CooldownManager = {}

local DEFAULT_BASE_COOLDOWNS = {
	Lateral = 2.0,
	LateralSalto = 2.0,
	Subir = 0.35,
	SubirSalto = 0.35,
}

local DEFAULT_MIN_COOLDOWNS = {
	Lateral = 0.5,
	LateralSalto = 0.5,
	Subir = 0.2,
	SubirSalto = 0.2,
}

local directionalActions = {
	Lateral = true,
	LateralSalto = true,
}

local state = {
	enabled = true,
	streakReduction = 0.2,
	repeatWindow = 1.5,
	streakMaxUses = 10,
	baseCooldowns = table.clone(DEFAULT_BASE_COOLDOWNS),
	minCooldowns = table.clone(DEFAULT_MIN_COOLDOWNS),
	records = {},
}

local function createRecord()
	return {
		lastSuccessTime = nil,
		streak = 0,
		lastDirection = nil,
		cooldownForNext = 0,
		blockedUntil = 0,
	}
end

local function getNotBeforeTime(record)
	local successCooldownUntil = 0
	if record.lastSuccessTime then
		successCooldownUntil = record.lastSuccessTime + (record.cooldownForNext or 0)
	end

	local blockedUntil = record.blockedUntil or 0
	return math.max(successCooldownUntil, blockedUntil)
end

local function getRecord(actionKey)
	local record = state.records[actionKey]
	if not record then
		record = createRecord()
		state.records[actionKey] = record
	end
	return record
end

local function getBaseCooldown(actionKey)
	return state.baseCooldowns[actionKey] or DEFAULT_BASE_COOLDOWNS[actionKey] or 0
end

local function getMinCooldown(actionKey)
	return state.minCooldowns[actionKey] or DEFAULT_MIN_COOLDOWNS[actionKey] or 0
end

function CooldownManager.Configure(config)
	state.enabled = config.CooldownDinamicoEnabled ~= false
	state.streakReduction = config.CooldownStreakReduction or 0.2
	state.repeatWindow = config.CooldownRepeatWindow or 1.5
	state.streakMaxUses = config.CooldownStreakMaxUses or 10
	state.baseCooldowns = table.clone(DEFAULT_BASE_COOLDOWNS)
	state.minCooldowns = table.clone(DEFAULT_MIN_COOLDOWNS)
	state.records = {}

	local base = config.ActionCooldowns
	if type(base) == "table" then
		for actionKey, value in pairs(base) do
			state.baseCooldowns[actionKey] = value
		end
	end

	local minimum = config.MinimumCooldowns
	if type(minimum) == "table" then
		for actionKey, value in pairs(minimum) do
			state.minCooldowns[actionKey] = value
		end
	end
end

function CooldownManager.Reset()
	state.records = {}
end

function CooldownManager.CanPerformAction(actionKey, _direction, now)
	if not state.enabled then
		return true
	end

	local record = getRecord(actionKey)
	local notBefore = getNotBeforeTime(record)
	return now >= notBefore
end

function CooldownManager.GetRemaining(actionKey, now)
	if not state.enabled then
		return 0
	end

	local record = getRecord(actionKey)
	local remaining = getNotBeforeTime(record) - now
	if remaining < 0 then
		return 0
	end

	return remaining
end

function CooldownManager.RegisterSuccess(actionKey, direction, now)
	if not state.enabled then
		return
	end

	local record = getRecord(actionKey)
	local isDirectional = directionalActions[actionKey] == true

	if isDirectional and record.lastDirection and direction and record.lastDirection ~= direction then
		record.streak = 0
	end

	if record.lastSuccessTime and (now - record.lastSuccessTime) > state.repeatWindow then
		record.streak = 0
	end

	record.streak = math.clamp(record.streak + 1, 1, state.streakMaxUses)
	record.lastSuccessTime = now

	if isDirectional then
		record.lastDirection = direction
	else
		record.lastDirection = nil
	end

	local base = getBaseCooldown(actionKey)
	local minValue = getMinCooldown(actionKey)
	local reductionCount = record.streak - 1
	record.cooldownForNext = math.max(base - reductionCount * state.streakReduction, minValue)
end

function CooldownManager.BlockAction(actionKey, _direction, now, duration)
	if not state.enabled then
		return
	end

	if not duration or duration <= 0 then
		return
	end

	local record = getRecord(actionKey)
	local candidateBlockedUntil = now + duration
	if candidateBlockedUntil > (record.blockedUntil or 0) then
		record.blockedUntil = candidateBlockedUntil
	end
end

function CooldownManager.GetDebugSnapshot(actionKey)
	local record = state.records[actionKey]
	if not record then
		return {
			Action = actionKey,
			Streak = 0,
			LastDirection = nil,
			CooldownForNext = getBaseCooldown(actionKey),
			Enabled = state.enabled,
		}
	end

	return {
		Action = actionKey,
		Streak = record.streak,
		LastDirection = record.lastDirection,
		CooldownForNext = record.cooldownForNext,
		LastSuccessTime = record.lastSuccessTime,
		Enabled = state.enabled,
	}
end

return CooldownManager
