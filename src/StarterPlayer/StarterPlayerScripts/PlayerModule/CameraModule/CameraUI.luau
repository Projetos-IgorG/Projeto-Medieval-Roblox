--!nonstrict

--[[
    Script: CameraUI.luau
    Caminho: src/StarterPlayer/StarterPlayerScripts/PlayerModule/CameraModule
    Responsabilidade: Gerencia elementos de UI ligados aos modos de camera do PlayerModule.
    Uso: ModuleScript; use require(caminho) e chame as funcoes ou tabelas retornadas.
    Nao faz: Nao implementa regras de gameplay do projeto; apenas apoia camera, controle e compatibilidade do jogador.
    Funcoes principais: setCameraModeToastEnabled, setCameraModeToastOpen
]]
local StarterGui = game:GetService("StarterGui")

local initialized = false

local CameraUI: any = {}

do

	function CameraUI.setCameraModeToastEnabled(enabled: boolean)
		if not enabled and not initialized then
			return
		end

		if not initialized then
			initialized = true
		end

		if not enabled then
			CameraUI.setCameraModeToastOpen(false)
		end
	end

	function CameraUI.setCameraModeToastOpen(open: boolean)
		assert(initialized, "CameraUI must be initialized before use")

		if open then
			StarterGui:SetCore("SendNotification", {
				Title = "Camera Control Enabled",
				Text = "Right click to toggle",
				Duration = 3,
			})
		end
	end
end

return CameraUI
