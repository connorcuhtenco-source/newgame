--!strict
-- Types — shared Luau type definitions for the combat protocol. Keeping the
-- wire shapes in one place makes the client/server contract explicit.

export type ActionKind = "Swing" | "Hit" | "BlockStart" | "BlockEnd"

-- Payload sent with CombatAction:FireServer(kind, payload)
export type ActionPayload = {
	combo: number?, -- which hit of the combo (1..MaxHits) for Swing/Hit
	clientTime: number?, -- workspace:GetServerTimeNow() snapshot on the client
	targetCharacter: Model?, -- claimed victim for a "Hit"
	hitPosition: Vector3?, -- world point of the blade contact for VFX
}

-- effectKind values broadcast over CombatEffect
export type EffectKind = "Hit" | "Block" | "Parry" | "Clash" | "Swing"

export type EffectPayload = {
	position: Vector3?,
	attacker: Player?,
	victim: Player?,
	victimChar: Model?, -- struck character (works for non-player enemies too)
	other: Player?, -- the second fighter in a clash
	combo: number?,
}

-- stateKind values sent over CombatState to a single client
export type StateKind = "Stun" | "Knockback" | "Cancel" | "Recoil" | "ParrySuccess"

export type StatePayload = {
	duration: number?, -- seconds (stun / recoil)
	direction: Vector3?, -- normalized push direction
	power: number?, -- impulse magnitude in studs/s
	lift: number?, -- vertical component for knockback
}

return {}
