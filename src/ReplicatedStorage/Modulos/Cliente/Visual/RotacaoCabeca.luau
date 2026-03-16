local RotacaoCabeca = {}
local CFNew, CFAng, asin = CFrame.new, CFrame.Angles, math.asin

function RotacaoCabeca.CalcularTargetC0(cameraDirection, yOffset)
	local maxSide = math.rad(55) 
	local maxUpDown = math.rad(30) 

	local sideAngle = math.clamp(-asin(cameraDirection.x), -maxSide, maxSide)
	local upDownAngle = math.clamp(-asin(cameraDirection.y), -maxUpDown, maxUpDown)

	local desiredC0 = CFNew(0, yOffset, 0)
			* CFrame.Angles(3 * math.pi / 2, 0, math.pi)
			* CFAng(0, 0, sideAngle)
			* CFAng(upDownAngle, 0, 0)
			
	return desiredC0
end

return RotacaoCabeca
