--[[
    Script: IniciarNPC.client.luau
    Caminho: src/StarterPlayer/StarterPlayerScripts/NPC
    Responsabilidade: Bootstrap do sistema de NPC no cliente (carrega views e inicia o SchedulerCliente).
    Uso: LocalScript; roda automaticamente ao entrar no jogo.
    Nao faz: Nao spawna NPCs (o servidor faz); apenas observa e renderiza.
]]

local Views = script.Parent:WaitForChild("Views")
require(Views:WaitForChild("ViewBase"))
require(Views:WaitForChild("Dialogo"))
require(Views:WaitForChild("Combate"))
require(Views:WaitForChild("Animal"))

local Scheduler = require(script.Parent:WaitForChild("SchedulerCliente"))
Scheduler.Iniciar()
