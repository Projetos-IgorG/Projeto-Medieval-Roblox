local MomentumManager = {}

local baseSpeed = 1.0
local maxSpeed = 1.3
local increment = 0.05
local decayWindow = 2.0

local streak = 0
local lastActionTime = 0

function MomentumManager.Configure(config)
	baseSpeed = config.MomentumBaseSpeed or 1.0
	maxSpeed = config.MomentumMaxSpeed or 1.3
	increment = config.MomentumIncrement or 0.05
	decayWindow = config.MomentumDecayWindow or 2.0
	streak = 0
	lastActionTime = 0
end

function MomentumManager.RegisterSuccess(now: number)
	if lastActionTime > 0 and (now - lastActionTime) > decayWindow then
		streak = 0
	end

	local maxStreak = math.ceil((maxSpeed - baseSpeed) / increment)
	streak = math.min(streak + 1, maxStreak)
	lastActionTime = now
end

function MomentumManager.GetSpeedMultiplier(now: number): number
	if streak <= 0 then
		return baseSpeed
	end

	if lastActionTime > 0 and (now - lastActionTime) > decayWindow then
		streak = 0
		return baseSpeed
	end

	return math.min(baseSpeed + streak * increment, maxSpeed)
end

function MomentumManager.Reset()
	streak = 0
	lastActionTime = 0
end

return MomentumManager
