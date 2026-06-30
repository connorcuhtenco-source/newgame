--!strict
-- CombatServer (bootstrap) — the authority. It receives intents over
-- CombatAction, validates them, resolves the interaction (clash > parry > block
-- > hit, in that priority), applies damage / knockback / stun, and broadcasts
-- the cosmetic results so every client shows the same sparks and clash.
--
-- Trust model: clients are believed about WHEN they swing and WHO they think
-- they hit; the server independently confirms range, facing, timing and rate
-- (HitValidator) and decides the actual outcome. Nothing here trusts a
-- client-supplied damage number.

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = require(ReplicatedStorage.Combat.Remotes)
local CombatConfig = require(ReplicatedStorage.Combat.CombatConfig)

local PlayerCombatState = require(script.PlayerCombatState)
local HitValidator = require(script.HitValidator)
local ParryResolver = require(script.ParryResolver)
local ClashResolver = require(script.ClashResolver)

local function serverNow(): number
	return Workspace:GetServerTimeNow()
end

local function getRoot(character: Model?): BasePart?
	return character and character:FindFirstChild("HumanoidRootPart") :: BasePart? or nil
end

-- == Outcome application =================================================

local function broadcastEffect(kind: string, payload: { [string]: any })
	Remotes.CombatEffect:FireAllClients(kind, payload)
end

local function applyKnockback(victimChar: Model, direction: Vector3, power: number, lift: number)
	local victimPlayer = Players:GetPlayerFromCharacter(victimChar)
	if victimPlayer then
		-- The victim's client owns its physics; let it apply the impulse.
		Remotes.CombatState:FireClient(victimPlayer, "Knockback", {
			direction = direction,
			power = power,
			lift = lift,
		})
	else
		local root = getRoot(victimChar)
		if root then
			root.AssemblyLinearVelocity = direction * power + Vector3.new(0, lift, 0)
		end
	end
end

local function resolveClash(attackerState, victimState, hitPos: Vector3)
	local attacker = attackerState.player
	local victim = victimState.player
	local aRoot = getRoot(attacker.Character)
	local vRoot = getRoot(victim.Character)
	if not aRoot or not vRoot then
		return
	end

	-- Cancel both swings so neither lands and the clash fires only once.
	PlayerCombatState.clearSwing(attackerState)
	PlayerCombatState.clearSwing(victimState)
	local nowT = serverNow()
	attackerState.recoilUntil = nowT + CombatConfig.Clash.RecoilTime
	victimState.recoilUntil = nowT + CombatConfig.Clash.RecoilTime

	-- Shove each fighter away from the other (flattened to the ground plane).
	local flat = Vector3.new(1, 0, 1)
	local awayFromVictim = ((aRoot.Position - vRoot.Position) * flat)
	awayFromVictim = (awayFromVictim.Magnitude > 1e-3) and awayFromVictim.Unit or aRoot.CFrame.LookVector
	applyKnockback(attacker.Character :: Model, awayFromVictim, CombatConfig.Clash.PushStuds, 4)
	applyKnockback(victim.Character :: Model, -awayFromVictim, CombatConfig.Clash.PushStuds, 4)

	Remotes.CombatState:FireClient(attacker, "Recoil", { duration = CombatConfig.Clash.RecoilTime })
	Remotes.CombatState:FireClient(victim, "Recoil", { duration = CombatConfig.Clash.RecoilTime })

	broadcastEffect("Clash", {
		position = hitPos,
		attacker = attacker,
		other = victim,
	})
end

local function resolveParry(attackerState, victimState, ctx)
	-- Perfect parry: the attacker is stunned and their attack is cancelled.
	local nowT = serverNow()
	attackerState.stunnedUntil = nowT + CombatConfig.Parry.AttackerStun
	PlayerCombatState.clearSwing(attackerState)

	Remotes.CombatState:FireClient(attackerState.player, "Stun", {
		duration = CombatConfig.Parry.AttackerStun,
	})
	if victimState and victimState.player then
		Remotes.CombatState:FireClient(victimState.player, "ParrySuccess", {})
	end

	broadcastEffect("Parry", {
		position = ctx.hitPosition,
		attacker = attackerState.player,
		victim = ctx.victim,
	})
end

local function resolveDamage(attackerState, ctx, blocked: boolean)
	local combo = (attackerState.activeSwing and attackerState.activeSwing.combo) or 1
	local isFinisher = combo >= CombatConfig.Combo.MaxHits

	local damage = CombatConfig.Damage.PerHit
	if isFinisher then
		damage += CombatConfig.Damage.FinisherBonus
	end
	if blocked then
		damage *= (1 - CombatConfig.Block.Mitigation)
	end

	ctx.victimHumanoid:TakeDamage(damage)

	if blocked then
		broadcastEffect("Block", {
			position = ctx.hitPosition,
			attacker = attackerState.player,
			victim = ctx.victim,
		})
	else
		broadcastEffect("Hit", {
			position = ctx.hitPosition,
			attacker = attackerState.player,
			victim = ctx.victim,
			combo = combo,
		})
		-- The finisher knocks the (unguarded) victim back.
		if isFinisher then
			local aRoot = getRoot(ctx.attackerChar)
			local vRoot = getRoot(ctx.victimChar)
			if aRoot and vRoot then
				local dir = (vRoot.Position - aRoot.Position) * Vector3.new(1, 0, 1)
				dir = (dir.Magnitude > 1e-3) and dir.Unit or aRoot.CFrame.LookVector
				applyKnockback(
					ctx.victimChar,
					dir,
					CombatConfig.Combo.Finisher.KnockbackStuds,
					CombatConfig.Combo.Finisher.KnockbackLift
				)
			end
		end
	end
end

-- == Intent handlers =====================================================

local function handleSwing(state, payload)
	local nowT = serverNow()
	if not HitValidator.canSwing(state, nowT) then
		return
	end
	-- Combo index is decided by the server, not the client's claim.
	local combo = PlayerCombatState.nextCombo(state, nowT)
	PlayerCombatState.beginSwing(state, combo, nowT)
end

local function handleHit(state, payload)
	local nowT = serverNow()
	local ctx, reason = HitValidator.validateHit(state, nowT, payload.targetCharacter, payload.hitPosition)
	if not ctx then
		-- Silently drop invalid claims. (Uncomment to debug:)
		-- warn(`[CombatServer] rejected hit from {state.player.Name}: {reason}`)
		return
	end

	local victimState = ctx.victim and PlayerCombatState.get(ctx.victim) or nil

	-- Priority 1: clash (two simultaneous opposing swings).
	if victimState and ClashResolver.isClash(state, victimState, nowT) then
		resolveClash(state, victimState, ctx.hitPosition)
		return
	end

	-- Priority 2/3: parry vs. standard block.
	local defense = ParryResolver.resolve(victimState, nowT)
	if defense == "parry" then
		resolveParry(state, victimState, ctx)
		return
	end

	-- Priority 4: damage (blocked = 80% mitigated, else full).
	resolveDamage(state, ctx, defense == "block")
end

local function handleBlockStart(state)
	if PlayerCombatState.isLocked(state, serverNow()) then
		return
	end
	if not state.blocking then
		state.blocking = true
		state.blockStartTime = serverNow()
	end
end

local function handleBlockEnd(state)
	state.blocking = false
end

-- == Wiring ==============================================================

Remotes.CombatAction.OnServerEvent:Connect(function(player: Player, kind: any, payload: any)
	if typeof(kind) ~= "string" then
		return
	end
	payload = (typeof(payload) == "table") and payload or {}
	local state = PlayerCombatState.get(player)

	if kind == "Swing" then
		handleSwing(state, payload)
	elseif kind == "Hit" then
		handleHit(state, payload)
	elseif kind == "BlockStart" then
		handleBlockStart(state)
	elseif kind == "BlockEnd" then
		handleBlockEnd(state)
	end
end)

local function bindPlayer(player: Player)
	PlayerCombatState.get(player)
	player.CharacterAdded:Connect(function()
		PlayerCombatState.reset(player)
	end)
end

Players.PlayerAdded:Connect(bindPlayer)
for _, player in Players:GetPlayers() do
	bindPlayer(player)
end
Players.PlayerRemoving:Connect(function(player)
	PlayerCombatState.remove(player)
end)
