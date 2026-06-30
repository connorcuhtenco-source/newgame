--!strict
-- Remotes — lazily builds (server) or waits for (client) the RemoteEvents that
-- carry combat traffic. Requiring this module from either context returns the
-- same named events, so call sites never touch raw Instances.
--
--   CombatAction  : client -> server   (intents: Swing / Hit / BlockStart / BlockEnd)
--   CombatEffect  : server -> clients   (cosmetic broadcasts: sparks, sfx, shake)
--   CombatState   : server -> 1 client  (authoritative personal state: stun, knockback, cancel)

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local FOLDER_NAME = "CombatRemotes"
local EVENT_NAMES = { "CombatAction", "CombatEffect", "CombatState" }

local function buildFolder(): Folder
	local folder = Instance.new("Folder")
	folder.Name = FOLDER_NAME
	for _, name in EVENT_NAMES do
		local remote = Instance.new("RemoteEvent")
		remote.Name = name
		remote.Parent = folder
	end
	folder.Parent = ReplicatedStorage
	return folder
end

local folder: Folder
if RunService:IsServer() then
	folder = ReplicatedStorage:FindFirstChild(FOLDER_NAME) :: Folder or buildFolder()
else
	folder = ReplicatedStorage:WaitForChild(FOLDER_NAME) :: Folder
end

local Remotes = {
	CombatAction = folder:WaitForChild("CombatAction") :: RemoteEvent,
	CombatEffect = folder:WaitForChild("CombatEffect") :: RemoteEvent,
	CombatState = folder:WaitForChild("CombatState") :: RemoteEvent,
}

return Remotes
