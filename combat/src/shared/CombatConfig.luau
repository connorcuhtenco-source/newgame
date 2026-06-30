--!strict
-- CombatConfig — the single source of tuning for the whole melee system.
-- Both the client controller and the server validator read from here so that
-- timing windows, ranges and damage stay in lock-step. Treat this like a
-- "balance sheet"; nothing in here should contain logic.

local CombatConfig = {}

-- 4-hit M1 (left click) combo. Each swing is split into three animation phases.
-- Active is the only phase during which the hitbox is "live".
CombatConfig.Combo = {
	MaxHits = 4,
	-- If the player does not chain the next swing before this many seconds after
	-- a swing ends, the combo resets back to hit #1.
	ResetWindow = 0.85,
	-- Per-phase durations (seconds). Tuned to feel snappy but readable.
	Frames = {
		Windup = 0.12, -- anticipation; cannot be cancelled into a block
		Active = 0.10, -- hitbox is casting during this window
		Recovery = 0.20, -- end lag; you may buffer the next input here
	},
	-- The 4th (finisher) hit gets a longer recovery and applies knockback.
	Finisher = {
		ExtraRecovery = 0.10,
		KnockbackStuds = 26, -- horizontal impulse strength
		KnockbackLift = 6, -- small vertical pop
	},
}

CombatConfig.Damage = {
	PerHit = 8,
	FinisherBonus = 6, -- 4th hit deals PerHit + FinisherBonus
}

CombatConfig.Block = {
	-- Holding F raises the guard.
	WalkSpeedMultiplier = 0.45, -- fraction of normal walk speed while guarding
	Mitigation = 0.80, -- standard block removes 80% of incoming damage
	-- Pressing F no earlier than this many seconds before the hit lands counts
	-- as a Perfect Parry. (i.e. parry if hitTime - blockStartTime <= ParryWindow)
	ParryWindow = 0.25,
}

CombatConfig.Parry = {
	AttackerStun = 1.50, -- attacker is frozen this long on a perfect parry
}

CombatConfig.Clash = {
	-- Two opposing M1s "clash" if their Active windows begin within this many
	-- seconds of each other (the "small millisecond margin" from the spec).
	TimeMargin = 0.09,
	PushStuds = 22, -- both fighters are shoved back this hard
	-- Brief mutual recovery so a clash reads as a real beat, not a stutter.
	RecoilTime = 0.45,
}

CombatConfig.Hitbox = {
	-- Server validation envelope. The client raycast-hitbox still does the fine
	-- detection; the server only sanity-checks that a claimed hit is physically
	-- plausible from the attacker's position.
	Reach = 8, -- max attacker->victim distance (studs)
	ReachFudge = 4, -- extra slack for latency before a hit is rejected
	FacingDot = 0.30, -- victim must be within this facing cone (dot of look dir)
	-- Name of the Attachment(s) placed along the blade for raycast casting.
	DamagePointTag = "DmgPoint",
	-- Studs of "thickness" sampled perpendicular to the blade sweep.
	CastRadius = 0.0,
}

CombatConfig.Camera = {
	-- Spring constants used by the client CameraShaker.
	Spring = {
		Stiffness = 190,
		Damping = 16,
	},
	-- Angular impulses (radians) fed into the spring on each event.
	HitImpulse = 0.05,
	ParryImpulse = 0.18,
	ClashImpulse = 0.32,
}

CombatConfig.Server = {
	-- Anti-spam: the server ignores swings that arrive faster than a real combo
	-- could possibly produce them.
	MinSwingInterval = (function()
		local f = CombatConfig.Combo.Frames
		return (f.Windup + f.Active) * 0.6
	end)(),
	-- How far a client clock may drift from the server before its timestamps are
	-- clamped (seconds). Protects clash timing from spoofed timestamps.
	MaxClockSkew = 0.5,
}

-- Asset ids for the first-person viewmodel animations. Replace the rbxassetid
-- placeholders with your own uploaded animations. Hits are indexed 1..4.
CombatConfig.Animations = {
	Swings = {
		"rbxassetid://0",
		"rbxassetid://0",
		"rbxassetid://0",
		"rbxassetid://0",
	},
	BlockIdle = "rbxassetid://0",
	BlockImpact = "rbxassetid://0",
	Stunned = "rbxassetid://0",
}

CombatConfig.Sounds = {
	-- Swing whoosh per hit (optional; falls back silently if missing).
	Swing = "rbxassetid://0",
	Hit = "rbxassetid://0",
	BlockHit = "rbxassetid://0",
	Parry = "rbxassetid://0", -- loud metallic clash on a perfect parry
	Clash = "rbxassetid://0", -- big two-sword clash
}

table.freeze(CombatConfig)
return CombatConfig
