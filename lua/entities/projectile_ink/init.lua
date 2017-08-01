--[[
	The main projectile entity of Splatoon SWEPS!!!
]]
AddCSLuaFile "shared.lua"
include "shared.lua"
util.AddNetworkString("SplatoonSWEPs: Receive vertices info")

local circle_polys = 16
local reference_polys = {}
local reference_vert = Vector(1, 0, 0)
local referense_vert45 = Vector(1, 0, 0)
for i = 1, circle_polys do
	referense_vert45:Rotate(Angle(0, 360 / circle_polys, 0))
	table.insert(reference_polys, {Vector(0, 0, 0), Vector(referense_vert45), Vector(reference_vert)})
	reference_vert:Rotate(Angle(0, 360 / circle_polys, 0))
end
--reference_polys = {
--	{Vector(0, 0, 0), Vector(1/2^0.5, 1/2^0.5, 0), Vector(1, 0, 0)},
--	{Vector(0, 0, 0), Vector(0, 1, 0), Vector(1/2^0.5, 1/2^0.5, 0)}}
for k, v in ipairs(reference_polys) do
	for i = 1, 3 do
		v[i] = Vector(0, v[i].x, v[i].y)
	end
end

local displacementOverlay = false
function ENT:Initialize()
	if not util.IsValidModel(self.FlyingModel) then
		self:Remove()
		return
	end
	
	self:SharedInit()
	self:SetIsInk(false)
	self:SetInkColorProxy(self.InkColor or vector_origin)
	
	local ph = self:GetPhysicsObject()
	if not IsValid(ph) then return end
	ph:SetMaterial("watermelon") --or "flesh"
	
	self.InkRadius = 100
	self.InkRadiusSqr = self.InkRadius^2
	
	if displacementOverlay then
		local index = 1
	--	for index = 1, 110 do
			local info = SplatoonSWEPs.DispInfo[index]
			local vert = SplatoonSWEPs.DispVertices[index]
			local prev, prev10 = vector_origin, vector_origin
			for k, v in pairs(vert) do
				if not prev:IsZero() then
					debugoverlay.Line(prev, v.pos, 10, Color(0,255,0), false)
				end
				if not prev10:IsZero() then
					debugoverlay.Line(prev10, v.pos, 10, Color(0,255,0), false)
				end
				prev = v.pos
				if k > 2^v.power and vert[k - (2^v.power)] then
					prev10 = vert[k - (2^v.power)].pos
				end
			end
			
			local st = SplatoonSWEPs.DispInfo[index].startPosition
			debugoverlay.Line(st, st + vector_up * 50, 10, Color(255,255,255), true)
			debugoverlay.Line(info.vertices[1], info.vertices[1] + vector_up * 50, 10, Color(255,0,0), true)
			debugoverlay.Line(info.vertices[2], info.vertices[2] + vector_up * 50, 10, Color(0,255,0), true)
			debugoverlay.Line(info.vertices[3], info.vertices[3] + vector_up * 50, 10, Color(0,0,255), true)
			debugoverlay.Line(info.vertices[4], info.vertices[4] + vector_up * 50, 10, Color(255,255,0), true)
	--	end
	end
end

function ENT:PhysicsCollide(coldata, collider)
	if util.QuickTrace(coldata.HitPos, coldata.HitNormal, self).HitSky then
		SafeRemoveEntityDelayed(self, 0)
		return
	end
	
	self:SetIsInk(true)
	self:SetHitPos(coldata.HitPos)
	self:SetHitNormal(coldata.HitNormal)
	self:SetAngles(coldata.HitNormal:Angle())
	self:DrawShadow(false)
	
	timer.Simple(0, function()
		if not IsValid(self) then return end
		self:SetMoveType(MOVETYPE_NONE)
		self:PhysicsInit(SOLID_NONE)
		self:SetPos(coldata.HitPos)
	end)
	
	local ang = coldata.HitNormal:Angle()
	--ang:RotateAroundAxis(coldata.HitNormal,
	--	(IsValid(self.Owner) and -self.Owner:EyeAngles().yaw or self:GetAngles().yaw) + 180)
	SplatoonSWEPsInkManager.AddQueue(
		coldata.HitPos, coldata.HitNormal, ang, self.InkRadius, self:GetCurrentInkColor(), reference_polys)
	
--	local m = SetupVertices(self, coldata)
--	net.Start("SplatoonSWEPs: Receive vertices info")
--	net.WriteEntity(self)
--	net.WriteTable(m)
--	net.Broadcast()
--	
--	net.Start("SplatoonSWEPs: ")
--	net.WriteTable(m)
--	net.Broadcast()
end

function ENT:Think()
	if Entity(1):KeyDown(IN_ATTACK2) then
		self:Remove()
	end
	if Entity(1):KeyDown(IN_USE) then
		ClearInk()
	end
end