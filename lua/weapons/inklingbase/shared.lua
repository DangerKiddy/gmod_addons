
local ColorCodes = {
	Color(255, 128, 0),
	Color(255, 0, 255),
	Color(128, 0, 255),
	Color(0, 255, 0),
	Color(0, 255, 255),
	Color(0, 0, 255)
}

SWEP.InklingModel = {
	Girl = "models/drlilrobot/splatoon/ply/inkling_girl.mdl",
	Boy = "models/drlilrobot/splatoon/ply/inkling_boy.mdl",
}
SWEP.IsSplatoonWeapon = true

--Model from Enhanced Inklings 
SWEP.SquidModelName = "models/props_splatoon/squids/squid_beta.mdl"

function SWEP:ChangePlayermodel(data)
	self.Owner:SetModel(data.Model)
	self.Owner:SetSkin(data.Skin)
	local bodygroups = ""
	local numgroups = self.Owner:GetNumBodyGroups()
	if isnumber(numgroups) then
		for k = 0, self.Owner:GetNumBodyGroups() - 1 do
			local v = data.BodyGroups[k + 1]
			if istable(v) and isnumber(v.num) then v = v.num else v = 0 end
			self.Owner:SetBodygroup(k, v)
			bodygroups = bodygroups .. tostring(v) .. " "
		end
	end
	if bodygroups == "" then bodygroups = "0" end
	
	if data.SetOffsets then
		self.Owner:SetNWInt("splt_isSet", 1)
		self.Owner:SetNWInt("splt_SplatoonOffsets", 2)
		if isfunction(self.Owner.SplatoonOffsets) then
			self.Owner:SplatoonOffsets()
		end
	else
		self.Owner:SetNWInt("splt_isSet", 0)
		self.Owner:SetNWInt("splt_SplatoonOffsets", 1)
		if isfunction(self.Owner.DefaultOffsets) then
			self.Owner:DefaultOffsets()
		end
	end
	self.Owner:SetSubMaterial()
	self.Owner:SetPlayerColor(data.PlayerColor)
	
	self.Owner:ConCommand("cl_playermodel " .. player_manager.TranslateToPlayerModelName(data.Model))
	self.Owner:ConCommand("cl_playerskin " .. tostring(data.Skin))
	self.Owner:ConCommand("cl_playerbodygroups " .. bodygroups)
	self.Owner:ConCommand("cl_playercolor " .. tostring(data.PlayerColor))
	
	if SERVER then
		timer.Simple(0.1, function()
			if IsValid(self) and IsValid(self.Owner) and isfunction(self.Owner.SetupHands) then
				self.Owner:SetupHands()
			end
		end)
	end
end

--Squids have a limited movement speed.
local function LimitSpeed(ply, data)
	if not IsValid(ply) or not ply:IsPlayer() then return end
	local weapon = ply:GetActiveWeapon()
	if not IsValid(weapon) or not weapon.IsSplatoonWeapon then return end
	
	local maxspeed = weapon.MaxSpeed
	if not isnumber(maxspeed) then return end
	
	local velocity = ply:GetVelocity() --Inkling's current velocity
	local speed2D = velocity:Length2D() --Horizontal speed
	local dot = velocity:GetNormalized():Dot(-vector_up) --Checking if it's falling
	
	--Disruptors make Inkling slower
	if weapon.poison then
		maxspeed = maxspeed / 2
	end
	
	--This only limits horizontal speed.
	if speed2D > maxspeed then
		local newVelocity2D = Vector(velocity.x, velocity.y, 0)
		newVelocity2D = newVelocity2D:GetNormalized() * maxspeed
		velocity.x = newVelocity2D.x
		velocity.y = newVelocity2D.y
	end
	
	data:SetVelocity(velocity)
end
hook.Add("Move", "Limit Squid's Speed", LimitSpeed)

local function PreventCrouching(ply, data)
	if not IsFirstTimePredicted() then return end
	if not IsValid(ply) or not ply:IsPlayer() then return end
	local weapon = ply:GetActiveWeapon()
	if not IsValid(weapon) or not weapon.IsSplatoonWeapon then return end
	if data:IsForced() then return end
	
	--MOUSE1+LCtrl makes crouch, LCtrl+MOUSE1 makes primary attack.
	local copy = data:GetButtons() --Since CUserCmd doesn't have KeyPressed(), I try workaround.
	if weapon.PreviousCmd then
		if data:KeyDown(IN_DUCK) then
			if bit.band(weapon.PreviousCmd, bit.bor(IN_ATTACK, IN_ATTACK2)) == 0 and
				(data:KeyDown(IN_ATTACK) or data:KeyDown(IN_ATTACK2)) then
				weapon:SetCrouchPriority(false)
			elseif CurTime() < weapon:GetNextCrouchTime() and 
				(data:KeyDown(IN_ATTACK) or data:KeyDown(IN_ATTACK2)) and 
				bit.band(weapon.PreviousCmd, IN_DUCK) == 0 then
				weapon:SetCrouchPriority(true)
			end
		elseif not data:KeyDown(IN_DUCK) and (data:KeyDown(IN_ATTACK) or data:KeyDown(IN_ATTACK2)) then
			weapon:SetCrouchPriority(false)
		end
	end
	weapon.PreviousCmd = copy
	
	--Prevent crouching after firing.
	if CurTime() < weapon:GetNextCrouchTime() then
		data:RemoveKey(IN_DUCK)
	end
end
hook.Add("StartCommand", "Inklings can't crouch for a while after firing their weapon.", PreventCrouching)

--When NPC weapon is picked up by player.
function SWEP:OwnerChanged()
	if not IsValid(self) or not IsValid(self.Owner) or not self.Owner:IsPlayer() then return true end
end

--Predicted Hooks
function SWEP:Deploy()
	if not IsValid(self) or not IsValid(self.Owner) or not self.Owner:IsPlayer() then return true end
	if game.SinglePlayer() then self:CallOnClient("Deploy") end
	
	self.BackupPlayerInfo = {
		Color = self.Owner:GetColor(),
		Flags = self.Owner:GetFlags(),
		JumpPower = self.Owner:GetJumpPower(),
		RenderMode = self:GetRenderMode(),
		Speed = {
			Crouched = self.Owner:GetCrouchedWalkSpeed(),
			Duck = self.Owner:GetDuckSpeed(),
			Max = self.Owner:GetMaxSpeed(),
			Run = self.Owner:GetRunSpeed(),
			Walk = self.Owner:GetWalkSpeed(),
			UnDuck = self.Owner:GetUnDuckSpeed(),
		},
		Playermodel = {
			Model = self.Owner:GetModel(),
			Skin = self.Owner:GetSkin(),
			BodyGroups = self.Owner:GetBodyGroups(),
			SetOffsets = table.HasValue(SplatoonTable or {}, self.Owner:GetModel()),
			PlayerColor = self.Owner:GetPlayerColor(),
		},
	}
	for k, v in pairs(self.BackupPlayerInfo.Playermodel.BodyGroups) do
		v.num = self.Owner:GetBodygroup(v.id)
	end
	
	self.Owner:SetColor(color_white)
	
	self.MaxSpeed = 250
	self.Owner:SetCrouchedWalkSpeed(0.5)
	self.Owner:SetMaxSpeed(self.MaxSpeed)
	self.Owner:SetRunSpeed(self.MaxSpeed)
	self.Owner:SetWalkSpeed(self.MaxSpeed)
	
	if SERVER then
		self.Color = ColorCodes[math.random(1, #ColorCodes)]
		self.VectorColor = Vector(self.Color.r / 255, self.Color.g / 255, self.Color.b / 255)
		self:SetInkColorProxy(self.VectorColor)
		self:SetCurrentInkColor(Vector(self.Color.r, self.Color.g, self.Color.b))
		
		self:ChangePlayermodel({
			Model = self.InklingModel.Girl,
			Skin = 0,
			BodyGroups = {},
			SetOffsets = true,
			PlayerColor = self.VectorColor,
		})
	end
	
	if isfunction(self.CustomDeploy) then self:CustomDeploy() end
	return true
end

function SWEP:Holster()
	if not IsValid(self) or not IsValid(self.Owner) or not self.Owner:IsPlayer() then return true end
	if game.SinglePlayer() then self:CallOnClient("Holster") end
	
	--Restores owner's information.
	if SERVER and istable(self.BackupPlayerInfo) then
		self.Owner:SetColor(self.BackupPlayerInfo.Color)
	--	self.Owner:RemoveFlags(self.Owner:GetFlags()) --Restires no target flag and something.
	--	self.Owner:AddFlags(self.BackupPlayerInfo.Flags)
		self.Owner:SetJumpPower(self.BackupPlayerInfo.JumpPower)
		self.Owner:DrawShadow(true)
		self.Owner:SetMaterial("")
		self.Owner:SetRenderMode(self.BackupPlayerInfo.RenderMode)
		self.Owner:SetCrouchedWalkSpeed(self.BackupPlayerInfo.Speed.Crouched)
		self.Owner:SetDuckSpeed(self.BackupPlayerInfo.Speed.Duck)
		self.Owner:SetMaxSpeed(self.BackupPlayerInfo.Speed.Max)
		self.Owner:SetRunSpeed(self.BackupPlayerInfo.Speed.Run)
		self.Owner:SetWalkSpeed(self.BackupPlayerInfo.Speed.Walk)
		self.Owner:SetUnDuckSpeed(self.BackupPlayerInfo.Speed.UnDuck)
		
		self:ChangePlayermodel(self.BackupPlayerInfo.Playermodel)
	end
	
	if CLIENT then
		local vm = self.Owner:GetViewModel()
		if IsValid(vm) then self:ResetBonePositions(vm) end
		
		self.Owner:ManipulateBoneAngles(0, angle_zero)
	end
	
	if isfunction(self.CustomHolster) then self:CustomHolster() end
	return true
end

local ReloadMultiply = 1 / 0.12 --Reloading rate(inkling)
local HealingDelay = 0.1 --Healing rate(inkling)
local inklingVM = ACT_VM_IDLE --Viewmodel animation(inkling)
local squidVM = ACT_VM_HOLSTER --Viewmodel animation(squid)
local throwingVM = ACT_VM_IDLE_LOWERED --Viewmodel animation(throwing sub weapon)
function SWEP:Think()
	self:CallOnClient("Think")
	local issquid = self.Owner:Crouching()
	if IsFirstTimePredicted() then
		--Gradually heal the owner
		if CurTime() > self:GetNextHealTime() then
			local delay = HealingDelay
			if self:GetInInk() then
				delay = delay / 8
			end
			
			self.Owner:SetHealth(math.Clamp(self.Owner:Health() + 1, 0, self.Owner:GetMaxHealth()))
			self:SetNextHealTime(CurTime() + delay)
		end
		--Recharging ink
		local reloadamount = CurTime() - self:GetNextReloadTime()
		if reloadamount > 0 then
			local mul = ReloadMultiply
			if self:GetInInk() then
				mul = mul * 4
			end
			
			self:SetInk(math.Clamp(self:GetInk() + reloadamount * mul, 0, 100))
			self:SetNextReloadTime(CurTime())
		end
		
		--I don't prevent playermodel from drawing its shadow
		--because it seems no way to make clientside entity draw its shadow.
		local material = issquid and "color" or ""
		self.Owner:SetMaterial(material)
		self:DrawShadow(not issquid)
		
		--Sending Viewmodel animation.
		if issquid and self.ViewAnim ~= squidVM then
			self:SendWeaponAnim(squidVM)
			self.ViewAnim = squidVM
		elseif not issquid and self.ViewAnim ~= inklingVM then
			self:SendWeaponAnim(inklingVM)
			self.ViewAnim = inklingVM
		end
		
		if isfunction(self.FirstPredictedThink) then self:FirstPredictedThink(issquid) end
	end
	
	if CLIENT then --Move clientside model to player's position.
		local v = self.Owner:GetVelocity()
		local a = (v + self.Owner:GetForward() * 40):Angle()
		if v:LengthSqr() < 16 then --Speed limit: 
			a.p = 0
		elseif a.p > 45 and a.p <= 90 then --Angle limit: up and down
			a.p = 45
		elseif a.p >= 270 and a.p < 300 then
			a.p = 300
		else
			a.r = a.p
		end
		a.p, a.y, a.r = a.p - 90, self.Owner:GetAngles().y, 180
		
		self.Squid:SetAngles(a)
		self.Squid:SetPos(self.Owner:GetPos())
		--It seems changing eye position doesn't work.
		self.Squid:SetEyeTarget(self.Squid:GetPos() + self.Squid:GetUp() * 100)
		
		if isfunction(self.ClientThink) then self:ClientThink(issquid) end
	end
end

--Begin to use special weapon.
function SWEP:Reload()
	
end

function SWEP:CommonFire(isprimary)
	if self:GetCrouchPriority() then return end
	
	local Weapon = isprimary and self.Primary or self.Secondary
	self:SetNextReloadTime(CurTime() + Weapon.ReloadDelay / 60)
	self:SetNextCrouchTime(CurTime() + Weapon.CrouchCooldown / 60)
	
	local CanFire = isprimary and self.CanPrimaryAttack or self.CanSecondaryAttack
	if not CanFire(self) then return end --Check fire delay
	if self:GetInk() < Weapon.TakeAmmo then return end --Check remaining amount of ink
	self:SetNextPrimaryFire(CurTime() + Weapon.Delay)
	self:MuzzleFlash()
	
	if math.random() < Weapon.PercentageRecoilAnimation then
		self.Owner:SetAnimation(PLAYER_ATTACK1)
	end
	
	local rnda = Weapon.Recoil * -1
	local rndb = Weapon.Recoil * math.Rand(-1, 1)
	if IsValid(self.Owner) then
		self.Owner:ViewPunch(Angle(rnda,rndb,rnda)) --Apply viewmodel punch
	end
	return true
end

--Shoot ink.
function SWEP:PrimaryAttack()
	local canattack = self:CommonFire(true)
	if isfunction(self.CustomPrimaryAttack) then self:CustomPrimaryAttack(canattack) end
end

--Use sub weapon
function SWEP:SecondaryAttack()
	local canattack = self:CommonFire(false)
	if isfunction(self.CustomSecondaryAttack) then self:CustomSecondaryAttack(canattack) end
end
--Predicted Hooks

function SWEP:SetupDataTables()
	self:NetworkVar("Bool", 0, "InInk") --Whether or not owner is in ink.
	self:NetworkVar("Bool", 1, "CrouchPriority") --True if crouch input takes a priority.
	self:NetworkVar("Float", 0, "NextCrouchTime") --Shooting cooldown.
	self:NetworkVar("Float", 1, "NextHealTime") --Owner heals gradually.
	self:NetworkVar("Float", 2, "NextReloadTime") --Owner recharging ink gradually.
	self:NetworkVar("Float", 3, "Ink") --Ink remainig. 0-100
	self:NetworkVar("Vector", 0, "InkColorProxy") --For material proxy.
	self:NetworkVar("Vector", 1, "CurrentInkColor") --Hex Color code
	
	self:SetInInk(false)
	self:SetCrouchPriority(false)
	self:SetNextCrouchTime(CurTime())
	self:SetNextHealTime(CurTime())
	self:SetNextReloadTime(CurTime())
	self:SetInk(100)
	self:SetCurrentInkColor(vector_origin)
	
	if isfunction(self.CustomDataTables) then self:CustomDataTables() end
end
