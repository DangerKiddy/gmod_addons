
--Shared library
if not SplatoonSWEPs then return end
include "splatoonsweps_bsp.lua"
include "splatoonsweps_const.lua"
include "splatoonsweps_sound.lua"

function SplatoonSWEPs:MinVector(a, b)
	local c = Vector()
	c.x = math.min(a.x, b.x)
	c.y = math.min(a.y, b.y)
	c.z = math.min(a.z, b.z)
	return c
end

function SplatoonSWEPs:MaxVector(a, b)
	local c = Vector()
	c.x = math.max(a.x, b.x)
	c.y = math.max(a.y, b.y)
	c.z = math.max(a.z, b.z)
	return c
end

--number miminum boundary size, table of Vectors
--returning AABB(mins, maxs)
function SplatoonSWEPs:GetBoundingBox(vectors, minbound)
	local mins = Vector(math.huge, math.huge, math.huge)
	local maxs = -mins
	local bound = self.vector_one * (minbound or 0)
	for _, v in ipairs(vectors) do
		mins = self:MinVector(mins, v - bound)
		maxs = self:MaxVector(maxs, v + bound)
	end
	return mins, maxs
end

--Vector AABB1(mins, maxs), Vector AABB2(mins, maxs) in world coordinates
--returning boolean, whether or not two AABBs intersect together
function SplatoonSWEPs:CollisionAABB(mins1, maxs1, mins2, maxs2)
	return mins1.x < maxs2.x and maxs1.x > mins2.x and
			mins1.y < maxs2.y and maxs1.y > mins2.y and
			mins1.z < maxs2.z and maxs1.z > mins2.z
end

--Vector AABB1(mins, maxs), Vector AABB2(mins, maxs) in world coordinates
--returning boolean, whether or not two AABBs intersect together
function SplatoonSWEPs:CollisionAABB2D(mins1, maxs1, mins2, maxs2)
	return mins1.x < maxs2.x and maxs1.x > mins2.x and
			mins1.y < maxs2.y and maxs1.y > mins2.y
end

--Vector(x, y, z), Vector new system origin, Angle new system angle
--returning localized Vector(x, y, 0)
function SplatoonSWEPs:To2D(source, orgpos, organg)
	local localpos = WorldToLocal(source, angle_zero, orgpos, organg)
	return Vector(localpos.y, localpos.z, 0)
end

--Vector(x, y, 0), Vector system origin in world coordinates, Angle system angle
--returning Vector(x, y, z)
function SplatoonSWEPs:To3D(source, orgpos, organg)
	local localpos = Vector(0, source.x, source.y)
	return (LocalToWorld(localpos, angle_zero, orgpos, organg))
end

function SplatoonSWEPs:AddTimerFramework(dest)
	local ScheduleFunc = {}
	local ScheduleMeta = {__index = ScheduleFunc}
	function ScheduleFunc:SetDelay(newdelay)
		self.prevtime = CurTime()
		if isstring(self.time) then
			self.weapon["Set" .. self.delay](self.weapon, newdelay)
			self.weapon["Set" .. self.time](self.weapon, CurTime() + newdelay)
		else
			self.delay = newdelay
			self.time = CurTime() + newdelay
		end
	end

	function ScheduleFunc:SinceLastCalled()
		return CurTime() - self.prevtime
	end

	function dest:AddNetworkSchedule(delay, func)
		local schedule = setmetatable({
			done = 0,
			func = func,
			prevtime = CurTime(),
			weapon = self,
		}, ScheduleMeta)
		schedule.time = "Timer" .. tostring(self:GetLastSlot "Float")
		self:AddNetworkVar("Float", schedule.time)
		self["Set" .. schedule.time](self, CurTime())
		schedule.delay = "TimerDelay" .. tostring(self:GetLastSlot "Float")
		self:AddNetworkVar("Float", schedule.delay)
		self["Set" .. schedule.delay](self, delay)
		table.insert(self.FunctionQueue, schedule)
		return schedule
	end

	function dest:AddSchedule(delay, numcall, func)
		local schedule = setmetatable({
			delay = delay,
			done = 0,
			func = func or numcall,
			numcall = func and numcall or 0,
			time = CurTime() + delay,
			prevtime = CurTime(),
			weapon = self,
		}, ScheduleMeta)
		table.insert(self.FunctionQueue, schedule)
		return schedule
	end

	function dest:ProcessSchedules()
		for i, s in pairs(self.FunctionQueue) do
			if isstring(s.time) then
				if CurTime() > self["Get" .. s.time](self) then
					s.func(self, s)
					s.prevtime = CurTime()
					self["Set" .. s.time](self, CurTime() + self["Get" .. s.delay](self))
				end
			elseif CurTime() > s.time then
				local remove = s.func(self, s)
				s.prevtime = CurTime()
				s.time = CurTime() + s.delay
				if s.numcall > 0 then
					s.done = s.done + 1
					remove = remove or s.done >= s.numcall
				end
				
				if remove then self.FunctionQueue[i] = nil end
			end
		end
	end
end

function SplatoonSWEPs:FrameToSec(f) return f / 60 end
function SplatoonSWEPs:SecToFrame(s) return s * 60 end
function SplatoonSWEPs.SetPrimary(self, info)
	local p = istable(self.Primary) and self.Primary or {}
	p.ClipSize = 100 --Clip size only for displaying.
	p.DefaultClip = 100
	p.Automatic = true
	p.Ammo = "Ink"
	p.Delay = SplatoonSWEPs:FrameToSec(info.Delay.Fire or 6)
	p.Recoil = info.Recoil or 0.2
	p.ReloadDelay = SplatoonSWEPs:FrameToSec(info.Delay.Reload or 30)
	p.TakeAmmo = (info.TakeAmmo or 1) / 100 * SplatoonSWEPs.MaxInkAmount
	p.PlayAnimPercent = (info.PlayAnimPercent or 0) / 100
	p.CrouchDelay = SplatoonSWEPs:FrameToSec(info.Delay.Crouch or 10)
	self.Primary = p
	if isfunction(self.CustomPrimary) then return self:CustomPrimary(p, info) end
end

function SplatoonSWEPs.SetSecondary(self, info)
	local s = istable(self.Secondary) and self.Secondary or {}
	s.ClipSize = -1
	s.DefaultClip = -1
	s.Automatic = false
	s.Ammo = "Ink"
	s.Delay = SplatoonSWEPs:FrameToSec(info.Delay.Fire or 6)
	s.Recoil = info.Recoil or 0.2
	s.ReloadDelay = SplatoonSWEPs:FrameToSec(info.Delay.Reload or 30)
	s.TakeAmmo = (info.TakeAmmo or 70) / 100 * SplatoonSWEPs.MaxInkAmount
	s.PlayAnimPercent = (info.PlayAnimPercent or 30) / 100
	s.CrouchDelay = SplatoonSWEPs:FrameToSec(info.Delay.Crouch or 10)
	self.Secondary = s
	if isfunction(self.CustomSecondary) then return self:CustomSecondary(s, info) end
end

function SplatoonSWEPs:IsValidInkling(ply)
	if not (IsValid(ply) and isfunction(ply.GetActiveWeapon)) then return end
	local weapon = ply:GetActiveWeapon()
	return IsValid(weapon) and weapon.IsSplatoonWeapon and not weapon.Holstering and weapon or nil
end

--Squids have a limited movement speed.
local LIMIT_Z_DEG = math.cos(math.rad(180 - 30))
hook.Add("Move", "SplatoonSWEPs: Limit squid's speed", function(ply, data)
	local weapon = SplatoonSWEPs:IsValidInkling(ply)
	if not (ply:IsPlayer() and weapon) then return end
	local maxspeed = weapon.MaxSpeed * (weapon.poison and 0.5 or 1)
	local velocity = data:GetVelocity() --Inkling's current velocity
	
	--When in ink
	if weapon:GetInWallInk() and ply:KeyDown(bit.bor(IN_JUMP, IN_FORWARD, IN_BACK)) then
		local inkjump = 24 * ply:EyeAngles().pitch / -90
		if ply:KeyDown(IN_BACK) then inkjump = inkjump * -1 end
		if ply:KeyDown(IN_JUMP) then inkjump = math.abs(inkjump) end
		velocity = velocity + vector_up * math.Clamp(inkjump, 0, maxspeed)
	end
	
	local speed2D = velocity.x * velocity.x + velocity.y * velocity.y --Horizontal speed
	local dot = -vector_up:Dot(velocity:GetNormalized()) --Checking if it's falling
	
	--Limits horizontal speed
	if speed2D > maxspeed * maxspeed then
		local newVelocity2D = Vector(velocity.x, velocity.y)
		newVelocity2D = newVelocity2D:GetNormalized() * maxspeed
		velocity.x = newVelocity2D.x
		velocity.y = newVelocity2D.y
	end
	
	if weapon.OnOutOfInk then
		velocity.z = math.min(velocity.z, maxspeed * .8)
		weapon.OnOutOfInk = false
	end
	
	weapon:ChangeHullDuck()
	data:SetVelocity(velocity)
end)

--MOUSE1+LCtrl makes crouch, LCtrl+MOUSE1 makes primary attack.
hook.Add("KeyPress", "SplattonSWEPs: Detect controls", function(ply, button)
	local weapon = SplatoonSWEPs:IsValidInkling(ply)
	if not weapon then return end
	if button == IN_ATTACK then weapon.IsAttackDown = true end
	if weapon.IsAttackDown and button == IN_DUCK then weapon.CrouchPriority = true end
end)

hook.Add("KeyRelease", "SplatoonSWEPs: Detect controls", function(ply, button)
	local weapon = SplatoonSWEPs:IsValidInkling(ply)
	if not weapon then return end
	if button == IN_ATTACK then weapon.IsAttackDown = false end
	if button == IN_ATTACK or button == IN_DUCK then weapon.CrouchPriority = false end
end)

hook.Add("SetupMove", "SplatoonSWEPs: Prevent owner from crouch", function(ply, mvd)
	local weapon = SplatoonSWEPs:IsValidInkling(ply)
	if not weapon then return end
	weapon.EnemyInkPreventCrouching = weapon.EnemyInkPreventCrouching
	and weapon:GetOnEnemyInk() and mvd:KeyDown(IN_DUCK)
	
	-- Prevent crouching after firing.
	if (not weapon.CrouchPriority and mvd:KeyDown(IN_DUCK) and mvd:KeyDown(IN_ATTACK))
	or CurTime() < weapon:GetNextCrouchTime() or weapon.EnemyInkPreventCrouching then
		mvd:SetButtons(bit.band(mvd:GetButtons(), bit.bnot(IN_DUCK)))
	end
end)

--Overriding footstep sound stops calling other addons' PlayerFootstep hook.
--I decide to replace one of their hook with my function built.
local FootstepTrace = vector_up * -20
local hostkey, hostfunc, multisteps = hostkey, hostfunc, multisteps
for k, v in pairs(hook.GetTable().PlayerFootstep or {}) do
	if hostkey and hostfunc then multisteps = true break end
	if isstring(k) then hostkey, hostfunc = k, v end
end

local function PlayerFootstep(ply, pos, foot, sound, volume, filter)
	if not (IsValid(ply) and isfunction(ply.GetActiveWeapon)) then return end
	local weapon = ply:GetActiveWeapon()
	local IsSplatoonWeapon = IsValid(weapon) and weapon.IsSplatoonWeapon and not weapon.Holstering
	if ((IsSplatoonWeapon and weapon:GetGroundColor() >= 0) or (SERVER and
	SplatoonSWEPs:GetSurfaceColor(util.QuickTrace(ply:GetPos(), FootstepTrace, ply)))) then
		if not (IsSplatoonWeapon and weapon:GetInInk()) and (SERVER or ply ~= LocalPlayer()) then
			ply:EmitSound "SplatoonSWEPs_Player.InkFootstep"
		end
		return true
	end
end

if hostkey and hostfunc then
	hook.GetTable().PlayerFootstep[hostkey] = function(ply, pos, foot, sound, volume, filter)
		local mystep = PlayerFootstep(ply, pos, foot, sound, volume, filter)
		local a, b, c, d, e, f = hostfunc(ply, pos, foot, sound, volume, filter)
		if a == true then
			return a, b, c, d, e, f
		else
			return mystep
		end
	end
else
	hook.Add("PlayerFootstep", "SplatoonSWEPs: Ink footstep", PlayerFootstep)
end

local bound = SplatoonSWEPs.vector_one * 10
hook.Add("ShouldCollide", "SplatoonSWEPs: Ink go through grates", function(ent1, ent2)
	local class1, class2 = ent1:GetClass(), ent2:GetClass()
	local collide1, collide2 = class1 == "projectile_ink", class2 == "projectile_ink"
	if collide1 == collide2 then return false end
	-- local wep1 = isfunction(ent1.GetActiveWeapon) and IsValid(ent1:GetActiveWeapon()) and ent1:GetActiveWeapon()
	-- local wep2 = isfunction(ent2.GetActiveWeapon) and IsValid(ent2:GetActiveWeapon()) and ent2:GetActiveWeapon()
	-- if wep1 and wep2 then
		
	-- end
	local ink, targetent = ent1, ent2
	if class2 == "projectile_ink" then
		if class1 == clasname then return false end
		ink, targetent, class1, class2 = targetent, ink, class2, class1
	end
	if class1 ~= "projectile_ink" then return true end
	if SERVER and targetent:GetMaterialType() == MAT_GRATE then return false end
	local dir = ink:GetVelocity()
	local filter = player.GetAll()
	table.insert(filter, ink)
	local tr = util.TraceLine({
		start = ink:GetPos(),
		endpos = ink:GetPos() + dir,
		filter = filter,
	})
	return tr.MatType ~= MAT_GRATE
end)
