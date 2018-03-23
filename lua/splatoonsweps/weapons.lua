
local ss = SplatoonSWEPs
if not ss then return end

function ss:SetPrimary(weapon, info)
	local p = istable(weapon.Primary) and weapon.Primary or {}
	p.ClipSize = self.MaxInkAmount --Clip size only for displaying.
	p.DefaultClip = self.MaxInkAmount
	p.Automatic = info.IsAutomatic or false
	p.Ammo = "Ink"
	p.Delay = info.Delay.Fire * self.FrameToSec
	p.Recoil = info.Recoil or .2
	p.ReloadDelay = info.Delay.Reload * self.FrameToSec
	p.TakeAmmo = info.TakeAmmo * self.MaxInkAmount
	p.PlayAnimPercent = info.PlayAnimPercent
	p.CrouchDelay = info.Delay.Crouch * self.FrameToSec
	weapon.Primary = p
	if isfunction(ss.CustomPrimary[weapon.Base]) then
		ss.CustomPrimary[weapon.Base](p, info)
	end
end

function ss:SetSecondary(weapon, info)
	local s = istable(weapon.Secondary) and weapon.Secondary or {}
	s.ClipSize = -1
	s.DefaultClip = -1
	s.Automatic = info.IsAutomatic or false
	s.Ammo = "Ink"
	s.Delay = info.Delay.Fire * self.FrameToSec
	s.Recoil = info.Recoil or .2
	s.ReloadDelay = info.Delay.Reload * self.FrameToSec
	s.TakeAmmo = info.TakeAmmo * self.MaxInkAmount
	s.PlayAnimPercent = info.PlayAnimPercent
	s.CrouchDelay = info.Delay.Crouch * self.FrameToSec
	weapon.Secondary = s
	if isfunction(ss.CustomSecondary[weapon.Base]) then
		ss.CustomSecondary[weapon.Base](s, info)
	end
end

ss.CustomPrimary = {}
ss.CustomSecondary = {}
function ss.CustomPrimary.weapon_shooter(p, info)
	p.Straight = info.Delay.Straight * ss.FrameToSec
	p.Damage = info.Damage * ss.ToHammerHealth
	p.MinDamage = info.MinDamage * ss.ToHammerHealth
	p.InkRadius = info.InkRadius * ss.ToHammerUnits
	p.MinRadius = info.MinRadius * ss.ToHammerUnits
	p.SplashRadius = info.SplashRadius * ss.ToHammerUnits
	p.SplashPatterns = info.SplashPatterns
	p.SplashNum = info.SplashNum
	p.SplashInterval = info.SplashInterval * ss.ToHammerUnits
	p.Spread = info.Spread
	p.SpreadJump = info.SpreadJump
	p.SpreadBias = info.SpreadBias
	p.MoveSpeed = info.MoveSpeed * ss.ToHammerUnitsPerSec
	p.MinDamageTime = info.Delay.MinDamage * ss.FrameToSec
	p.DecreaseDamage = info.Delay.DecreaseDamage * ss.FrameToSec
	p.InitVelocity = info.InitVelocity * ss.ToHammerUnitsPerSec
	p.FirePosition = info.FirePosition
	p.AimDuration = info.Delay.Aim * ss.FrameToSec
end

function ss.CustomSecondary.weapon_shooter(p, info)
end