
local ss = SplatoonSWEPs
if not ss then return end
AddCSLuaFile "shared.lua"
AddCSLuaFile "baseinfo.lua"
AddCSLuaFile "ai_translations.lua"
AddCSLuaFile "cl_draw.lua"
include "shared.lua"
include "baseinfo.lua"
include "ai_translations.lua"

function SWEP:ChangePlayermodel(data)
	if not self.Owner:IsPlayer() then return end
	self.Owner:SetModel(data.Model)
	self.Owner:SetSkin(data.Skin)
	local numgroups = self.Owner:GetNumBodyGroups()
	if isnumber(numgroups) then
		for k = 0, numgroups - 1 do
			local v = data.BodyGroups[k + 1]
			v = istable(v) and isnumber(v.num) and v.num or 0
			self.Owner:SetBodygroup(k, v)
		end
	end
	
	self.Owner:SetSubMaterial()
	self.Owner:SetPlayerColor(data.PlayerColor)
	local hands = self.Owner:GetHands()
	if IsValid(hands) then
		local info = player_manager.TranslatePlayerHands(player_manager.TranslateToPlayerModelName(data.Model))
		if info then
			hands:SetModel(info.model)
			hands:SetSkin(info.skin)
			hands:SetBodyGroups(info.body)
		end
	end
end

local InkTraceLength = 20
local InkTraceDown = -vector_up * InkTraceLength
function SWEP:Initialize()
	self.OwnerVelocity = vector_origin
	self.ViewAnim = ACT_VM_IDLE
	self:SetInInk(false)
	self:SetOnEnemyInk(false)
	self:SetNextCrouchTime(CurTime())
	self:SetInk(ss.MaxInkAmount)
	self:SetInkColorProxy(ss.vector_one)
	self:ChangeHullDuck()
	self:AddSchedule(5 * ss.FrameToSec,
	function(self, schedule) --Set if player is in ink
		local filter = {self, self.Owner}
		local ang = Angle(0, self.Owner:GetAngles().yaw)
		local p = self.Owner:WorldSpaceCenter()
		local fw, right = ang:Forward() * InkTraceLength, ang:Right() * InkTraceLength
		self:SetGroundColor(ss:GetSurfaceColor(util.QuickTrace(self.Owner:GetPos(), InkTraceDown, filter)) or -1)
		local onink = self:GetGroundColor() >= 0
		local onourink = self:GetGroundColor() == self.ColorCode
		
		self:SetInWallInk(self.Owner:IsFlagSet(FL_DUCKING) and (
		ss:GetSurfaceColor(util.QuickTrace(p, fw - right, filter)) == self.ColorCode or
		ss:GetSurfaceColor(util.QuickTrace(p, fw + right, filter)) == self.ColorCode or
		ss:GetSurfaceColor(util.QuickTrace(p,-fw - right, filter)) == self.ColorCode or
		ss:GetSurfaceColor(util.QuickTrace(p,-fw + right, filter)) == self.ColorCode))
		
		self:SetInInk(onink and onourink and self.Owner:IsFlagSet(FL_DUCKING) or self:GetInWallInk())
		self:SetOnEnemyInk(onink and not onourink)
		self.OwnerVelocity = self.Owner:GetVelocity()
	end)
	
	self:SharedInitBase()
	if isfunction(self.ServerInit) then self:ServerInit() end
	if IsValid(self.Owner) and not self.Owner:IsPlayer() then
		self.HoldType = "smg"
		self:SetHoldType(self.HoldType)
		local npcrange = self.Primary.InitVelocity * (self.Primary.Straight + 4.5 * ss.FrameToSec)
		self:SetSaveValue("m_fMinRange1", 0)
		self:SetSaveValue("m_fMinRange2", 0)
		self:SetSaveValue("m_fMaxRange1", npcrange)
		self:SetSaveValue("m_fMaxRange2", npcrange)
		self:SetNPCMinBurst(3)
		self:SetNPCMaxBurst(8)
		self:SetNPCFireRate(self.Primary.Delay)
		self:SetNPCMinRest(self.Primary.Delay)
		self:SetNPCMaxRest(self.Primary.Delay * 3)
		self:Deploy()
		local timername = "SplatoonSWEPs: NPC Think function" .. self:EntIndex()
		timer.Create(timername, 0, 0, function()
			if not (IsValid(self) and IsValid(self.Owner)) or self.Owner:IsPlayer() then
				return timer.Remove(timername)
			end
			
			self:Think()
		end)
	end
end

function SWEP:OnRemove()
	return self:Holster()
end

function SWEP:ShouldDropOnDie()
	return true
end

function SWEP:Deploy()
	if not (IsValid(self.Owner) and self.Owner:Health() > 0) then return true end
	if self.Owner:IsPlayer() then
		self:CallOnClient "ClientDeployBase"
		self:SetHoldType "passive"
	end
	
	ss.NoCollide[self.Owner] = {}
	self:SetInInk(false)
	self:SetOnEnemyInk(false)
	self:SetNextCrouchTime(CurTime())
	self.OwnerVelocity = self.Owner:GetVelocity()
	self.ViewAnim = ACT_VM_IDLE
	if self.Owner:IsPlayer() and not self.Owner:IsBot() then
		for i, param in ipairs {
			"Playermodel", "InkColor",
			"CanHealStand", "CanHealInk",
			"CanReloadStand", "CanReloadInk",
			"BecomeSquid",
		} do
			local value = self.Owner:GetInfoNum(ss:GetConVarName(param), ss.ConVarDefaults[ss.ConVarName[param]])
			if i == 1 then
				self:SetPMID(value)
			elseif i == 2 then
				self.ColorCode = value
			else
				self[param] = value
			end
		end
	else
		self:SetPMID(table.Random(ss.PLAYER))
		self.CanHealStand = true
		self.CanHealInk = true
		self.CanReloadStand = true
		self.CanReloadInk = true
		self.ColorCode = math.random(ss.MAX_COLORS)
	end
	
	self.Color = ss:GetColor(self.ColorCode)
	self:SetInkColorProxy(Vector(self.Color.r, self.Color.g, self.Color.b) / 255)
	self.SquidAvailable = tobool(ss:GetSquidmodel(self:GetPMID()))
	if self.Owner:IsPlayer() then
		self.BackupPlayerInfo = {
			Color = self.Owner:GetColor(),
			Flags = self.Owner:GetFlags(),
			JumpPower = self.Owner:GetJumpPower(),
			Material = self.Owner:GetMaterial(),
			RenderMode = self:GetRenderMode(),
			Speed = {
				Crouched = self.Owner:GetCrouchedWalkSpeed(),
				Duck = self.Owner:GetDuckSpeed(),
				Max = self.Owner:GetMaxSpeed(),
				Run = self.Owner:GetRunSpeed(),
				Walk = self.Owner:GetWalkSpeed(),
				UnDuck = self.Owner:GetUnDuckSpeed(),
			},
			SubMaterial = {},
			Playermodel = {
				Model = self.Owner:GetModel(),
				Skin = self.Owner:GetSkin(),
				BodyGroups = self.Owner:GetBodyGroups(),
				SetOffsets = table.HasValue(SplatoonTable or {}, self.Owner:GetModel()),
				PlayerColor = self.Owner:GetPlayerColor(),
			},
			ViewOffsetDucked = self.Owner:GetViewOffsetDucked()
		}
		self.BackupPlayerInfo.HullMins, self.BackupPlayerInfo.HullMaxs = self.Owner:GetHullDuck()
		for k, v in pairs(self.BackupPlayerInfo.Playermodel.BodyGroups) do
			v.num = self.Owner:GetBodygroup(v.id)
		end
		
		for i = 0, 31 do
			local submat = self.Owner:GetSubMaterial(i)
			if submat == "" then submat = nil end
			self.BackupPlayerInfo.SubMaterial[i] = submat
		end
	
		local PMPath = ss.Playermodel[self:GetPMID()]
		if PMPath then
			if file.Exists(PMPath, "GAME") then
				self.PMTable = {
					Model = PMPath,
					Skin = 0,
					BodyGroups = {},
					SetOffsets = true,
					PlayerColor = self:GetInkColorProxy(),
				}
				self:ChangePlayermodel(self.PMTable)
				self:ChangeHullDuck()
			else
				ss:SendError("WeaponPlayermodelNotFound", self.Owner)
			end
		end
	end
	
	return self:SharedDeployBase()
end

function SWEP:Holster()
	if self:GetInFence() then return false end
	if not IsValid(self.Owner) then return true end
	if game.SinglePlayer() and self.Owner:IsPlayer() then self:CallOnClient "Holster" end
	self.PMTable = nil
	if self.Owner:IsPlayer() then
		self.Owner:SetDSP(1)
		if istable(self.BackupPlayerInfo) then --Restores owner's information.
			self:ChangePlayermodel(self.BackupPlayerInfo.Playermodel)
			self.Owner:SetColor(self.BackupPlayerInfo.Color)
		--	self.Owner:RemoveFlags(self.Owner:GetFlags()) --Restores no target flag and something.
		--	self.Owner:AddFlags(self.BackupPlayerInfo.Flags)
			self.Owner:SetJumpPower(self.BackupPlayerInfo.JumpPower)
			self.Owner:SetRenderMode(self.BackupPlayerInfo.RenderMode)
			self.Owner:SetCrouchedWalkSpeed(self.BackupPlayerInfo.Speed.Crouched)
			self.Owner:SetDuckSpeed(self.BackupPlayerInfo.Speed.Duck)
			self.Owner:SetMaxSpeed(self.BackupPlayerInfo.Speed.Max)
			self.Owner:SetRunSpeed(self.BackupPlayerInfo.Speed.Run)
			self.Owner:SetWalkSpeed(self.BackupPlayerInfo.Speed.Walk)
			self.Owner:SetUnDuckSpeed(self.BackupPlayerInfo.Speed.UnDuck)
			self.Owner:SetHullDuck(self.BackupPlayerInfo.HullMins, self.BackupPlayerInfo.HullMaxs)
			self.Owner:SetViewOffsetDucked(self.BackupPlayerInfo.ViewOffsetDucked)
			self.Owner:SetMaterial(self.BackupPlayerInfo.Material)
			for i = 0, 31 do
				self.Owner:SetSubMaterial(i, self.BackupPlayerInfo.SubMaterial[i])
			end
		end
	end
	
	return self:SharedHolsterBase()
end

function SWEP:Think()
	if not IsValid(self.Owner) or self:GetHolstering() then return end
	if self.PMTable and self.PMTable.Model ~= self.Owner:GetModel() then
		self:ChangePlayermodel(self.PMTable)
	end
	
	self:ProcessSchedules()
	self:SharedThinkBase()
	self:SetClip1(math.max(0, self:GetInk() / ss.MaxInkAmount * 100))
	if isfunction(self.ServerThink) then return self:ServerThink() end
end
