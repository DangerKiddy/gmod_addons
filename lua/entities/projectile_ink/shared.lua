--[[
	The main projectile entity of Splatoon SWEPS!!!
]]

ENT.Type = "anim"
ENT.FlyingModel = Model "models/blooryevan/ink/inkprojectile.mdl"

function ENT:SharedInit(mdl)
	self:SetModel(mdl or self.FlyingModel)
	self:SetCollisionGroup(COLLISION_GROUP_INTERACTIVE_DEBRIS)
	self:SetCustomCollisionCheck(true)
end

function ENT:SetupDataTables()
	self:NetworkVar("Vector", 0, "InkColorProxy") --For material proxy.
end
