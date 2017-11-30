
--This lua parses the bsp file of current map.
if not SplatoonSWEPs then return end
SplatoonSWEPs.BSP = SplatoonSWEPs.BSP or {}
SplatoonSWEPs.LUMP = {
	ENTITIES						=  0,
	PLANES							=  1,
	TEXDATA							=  2,
	VERTEXES						=  3,
	VISIBLITY						=  4,
	NODES							=  5,
	TEXINFO							=  6,
	FACES							=  7,
	LIGHTING						=  8,
	OCCLUSION						=  9,
	LEAFS							= 10,
	FACEIDS							= 11,
	EDGES							= 12,
	SURFEDGES						= 13,
	MODELS							= 14,
	WORLDLIGHTS						= 15,
	LEAFFACES						= 16,
	LEAFBRUSHES						= 17,
	BRUSHES							= 18,
	BRUSHSIDES						= 19,
	AREAS							= 20,
	AREAPORTALS						= 21,
	PORTALS							= 22, --unused in version 20
	CLUSTERS						= 23, --
	PORTALVERTS						= 24, --
	CLUSTERPORTALS					= 25, --unused in version 20
	DISPINFO						= 26,
	ORIGINALFACES					= 27,
	PHYSDISP						= 28,
	PHYSCOLLIDE						= 29,
	VERTNORMALS						= 30,
	VERTNORMALINDICES				= 31,
	DISP_LIGHTMAP_ALPHAS			= 32,
	DISP_VERTS						= 33,
	DISP_LIGHMAP_SAMPLE_POSITIONS	= 34,
	GAME_LUMP						= 35,
	LEAFWATERDATA					= 36,
	PRIMITIVES						= 37,
	PRIMVERTS						= 38,
	PRIMINDICES						= 39,
	PAKFILE							= 40,
	CLIPPORTALVERTS					= 41,
	CUBEMAPS						= 42,
	TEXDATA_STRING_DATA				= 43,
	TEXDATA_STRING_TABLE			= 44,
	OVERLAYS						= 45,
	LEAFMINDISTTOWATER				= 46,
	FACE_MACRO_TEXTURE_INFO			= 47,
	DISP_TRIS						= 48,
	PHYSCOLLIDESURFACE				= 49,
	WATEROVERLAYS					= 50,
	LIGHTMAPEDGES					= 51,
	LIGHTMAPPAGEINFOS				= 52,
	LIGHTING_HDR					= 53, --only used in version 20+ BSP files
	WORLDLIGHTS_HDR					= 54, --
	LEAF_AMBIENT_LIGHTING_HDR		= 55, --
	LEAF_AMBIENT_LIGHTING			= 56, --only used in version 20+ BSP files
	XZIPPAKFILE						= 57,
	FACES_HDR						= 58,
	MAP_FLAGS						= 59,
	OVERLAY_FADES					= 60,
	OVERLAY_SYSTEM_LEVELS			= 61,
	PHYSLEVEL						= 62,
	DISP_MULTIBLEND					= 63,
}

-- local NodeFuncs = {}
-- local NodeMeta = {__index = NodeFuncs}
-- function NodeFuncs.GetChildren(self, pos)
	-- local planenormal = self.Separator.normal
	-- local planeorg = self.Separator.Origin
	-- local childindex = planenormal:Dot(pos - planeorg) > 0 and 1 or 2
	-- return self.ChildNodes[childindex], self.ChildNodes[3 - childindex]
-- end

-- function NodeFuncs.Across(self, mins, maxs, org)
	-- org = org or vector_origin
	-- local planenormal = self.Separator.normal
	-- local planeorg = self.Separator.Origin
	-- local mindot, maxdot = math.huge, -math.huge
	-- for _, v in ipairs {
		-- mins, maxs,
		-- Vector(maxs.x, mins.y, mins.z),
		-- Vector(mins.x, maxs.y, mins.z),
		-- Vector(mins.x, mins.y, maxs.z),
		-- Vector(mins.x, maxs.y, maxs.z),
		-- Vector(maxs.x, mins.y, maxs.z),
		-- Vector(maxs.x, maxs.y, mins.z),
	-- } do
		-- local dot = planenormal:Dot(v + org - planeorg)
		-- mindot = math.min(mindot, dot)
		-- maxdot = math.max(maxdot, dot)
	-- end

	-- return mindot * maxdot < 0
-- end

local TextureMeta = {}
local bsp = SplatoonSWEPs.BSP
local LUMP = SplatoonSWEPs.LUMP
local FACE_MIN_SEGLEN_SQR = 1.5^2 --minimum length of line segment
local FACE_MIN_ANGLE = 0.1 --degrees
local FACE_MIN_SIN = math.sin(math.rad(FACE_MIN_ANGLE))
local DISP_MIN_BOUND = 0
local TextureFilterBits = bit.bor(SURF_SKY, SURF_WARP, SURF_NOPORTAL, SURF_TRIGGER, SURF_NODRAW, SURF_HINT, SURF_SKIP)
TextureMeta.__index = TextureMeta
function TextureMeta:GetMaterial(scale)
	return self.Material or self:MakeMaterial()
end

function TextureMeta:MakeMaterial()
	self.width = self.TexData.width
	self.height = self.TexData.height
	self.Material = CreateMaterial(tostring(self) .. "_texinfo", "UnlitGeneric", {
		["$basetexture"] = Material(self.TexData.name):GetTexture("$basetexture"):GetName(),
		["$detailscale"] = 1,
		["$reflectivity"] = self.TexData.reflectivity,
		["$model"] = 1,
	})
	return self.Material
end

function TextureMeta:GenerateUV(x, y, z)
	local s, t = 0, 1
	return
		(self.textureVecs[s][0] * x
		+ self.textureVecs[s][1] * y
		+ self.textureVecs[s][2] * z
		+ self.textureVecs[s][3])
		/ self.TexData.width,
		(self.textureVecs[t][0] * x
		+ self.textureVecs[t][1] * y
		+ self.textureVecs[t][2] * z
		+ self.textureVecs[t][3])
		/ self.TexData.height
end

local function read(arg)
	if isstring(arg) then
		if arg == "UShort" then
			local n = bsp.bsp:ReadShort()
			return n + (n < 0 and 65536 or 0)
		elseif arg == "ULong" then
			local n = bsp.bsp:ReadLong()
			return n + (n < 0 and 4294967296 or 0)
		elseif arg == "SignedByte" then
			local n = bsp.bsp:ReadByte()
			return n - (n > 127 and 256 or 0)
		elseif arg == "Vector" then
			local x = bsp.bsp:ReadFloat()
			local y = bsp.bsp:ReadFloat()
			local z = bsp.bsp:ReadFloat()
			return Vector(x, y, z)
		else
			return bsp.bsp["Read" .. arg](bsp.bsp)
		end
	else
		return bsp.bsp:Read(arg)
	end
end

function bsp:GetLump(i)
	return self.header.lumps[i]
end

function bsp:Init()
	self.bspname = "maps/" .. game.GetMap() .. ".bsp"
	self.bsp = file.Open(self.bspname, "rb", "GAME")

	self:ReadHeader()
	self:Parse(LUMP.PLANES)
	self:Parse(LUMP.VERTEXES)
	self:Parse(LUMP.EDGES)
	self:Parse(LUMP.SURFEDGES)

	self:Parse(LUMP.LIGHTING)
	self:Parse(LUMP.TEXDATA)
	self:Parse(LUMP.TEXINFO)

	self:Parse(LUMP.FACES)
	self:Parse(LUMP.DISPINFO)
	self.bsp = nil
end

function bsp:ReadHeader()
	self.header = {lumps = {}}
	self.bsp:Seek(8)
	for i = 0, 63 do
		self.header.lumps[i] = {}
		self.header.lumps[i].data = {}
		self.header.lumps[i].parsed = false
		self.header.lumps[i].offset = read "Long"
		self.header.lumps[i].length = read "Long"
		self.bsp:Skip(8)
	end
end

local function GetRotatedAABB(v2d, angle)
	local mins = Vector(math.huge, math.huge)
	local maxs = -mins
	for k, v in ipairs(v2d) do
		v = Vector(v)
		v:Rotate(angle)
		mins.x = math.min(mins.x, v.x)
		mins.y = math.min(mins.y, v.y)
		maxs.x = math.max(maxs.x, v.x)
		maxs.y = math.max(maxs.y, v.y)
	end
	
	return mins, maxs
end

local function MakeSurface(key, mins, maxs, normal, angle, origin, v2d, v3d)
	if #v2d < 3 then return end
	local s = SplatoonSWEPs.Surfaces
	if not s[key] then s[key] = {normal = normal, angle = angle} end
	local facetable = {
		maxs = maxs,
		mins = mins,
		origin = origin,
		MeshVertex = {},
		Parent = s[key],
		Vertices2D = v2d,
		Vertices = v3d,
	}
	table.insert(s[key], facetable)
	table.insert(SplatoonSWEPs.SortedSurfaces, facetable)
	
	local area, minangle, minmins = 0, nil, nil
	for i, v in ipairs(v2d) do --Get minimum AABB with O(n^2)
		local seg = v2d[i % #v2d + 1] - v
		local ang = Angle(0, 90 - math.deg(math.atan2(seg.y, seg.x)))
		local mins, maxs = GetRotatedAABB(v2d, ang)
		local bound = maxs - mins
		local area = bound.x * bound.y
		if v2d.Area > area then
			minangle = ang
			if bound.x < bound.y then
				ang.yaw = ang.yaw - 90
				minmins, maxs = GetRotatedAABB(v2d, ang)
				v2d.bound = maxs - minmins
				v2d.Area = bound.x * bound.y
			else
				minmins = mins
				v2d.Area = area
				v2d.bound = bound
			end
		end
	end
	
	for i, v in ipairs(v2d) do
		area = area + v:Cross(v2d[i % #v2d + 1]).z
		v:Rotate(minangle)
		v:Sub(minmins)
	end

	minmins:Rotate(-minangle)
	facetable.origin = SplatoonSWEPs:To3D(minmins, origin, angle)
	angle:RotateAroundAxis(normal, -minangle.yaw)
	v2d.angle = angle
	s.Area = s.Area + math.abs(area) / 2
	s.AreaBound = s.AreaBound + v2d.Area
	s.LongestEdge = math.max(s.LongestEdge, v2d.bound.x, v2d.bound.y)
	
	return facetable
end

local ddd = 0
local function MakeDispTriangle(vert, planenormal)
	local normal = (vert[1] - vert[2]):Cross(vert[3] - vert[2]):GetNormalized()
	local angle = normal:Angle()
	local surfkey = tostring(normal)
	local origin = (vert[1] + vert[2] + vert[3]) / 3
	-- if normal:Dot(planenormal) < 0 then
		-- print ""
		-- normal = -normal
		-- vert[2], vert[3] = vert[3], vert[2]
	-- end
	
	local mins = Vector(math.huge, math.huge, math.huge)
	local maxs = -mins
	local v2d = {Area = math.huge}
	for i, v in ipairs(vert) do
		maxs.x = math.max(maxs.x, v.x + DISP_MIN_BOUND) --Calculate bounding box
		maxs.y = math.max(maxs.y, v.y + DISP_MIN_BOUND)
		maxs.z = math.max(maxs.z, v.z + DISP_MIN_BOUND)
		mins.x = math.min(mins.x, v.x - DISP_MIN_BOUND)
		mins.y = math.min(mins.y, v.y - DISP_MIN_BOUND)
		mins.z = math.min(mins.z, v.z - DISP_MIN_BOUND)
		v2d[i] = SplatoonSWEPs:To2D(v, origin, angle)
	end
	
	local ft = MakeSurface(surfkey, mins, maxs, normal, angle, origin, v2d, vert)
end

local ParseFunction = {
[LUMP.ENTITIES] = function(lump)
	lump.data.str = read(lump.length)
	for s in lump.data.str:gmatch "%{.-%}" do
		table.insert(lump.data, util.KeyValuesToTable('"xd"\r\n' .. s))
	end
end,

[LUMP.PLANES] = function(lump)
	local size = 20
	lump.num = math.min(math.floor(lump.length / size) - 1, 65536 - 1)
	for i = 0, lump.num do
		lump.data[i] = {}
		lump.data[i].normal = read "Vector"
		lump.data[i].distance = read "Float"
		lump.data[i].Origin = lump.data[i].normal * lump.data[i].distance
		lump.data[i].type = read "Long"
	end
end,

[LUMP.VERTEXES] = function(lump)
	local size = 12
	lump.num = math.min(math.floor(lump.length / size) - 1, 65536 - 1)
	for i = 0, lump.num do
		lump.data[i] = read "Vector"
	end
end,

[LUMP.EDGES] = function(lump)
	local size = 4
	lump.num = math.min(math.floor(lump.length / size) - 1, 256000 - 1)
	for i = 0, lump.num do
		lump.data[i] = {}
		lump.data[i][1] = read "UShort"
		lump.data[i][2] = read "UShort"
	end
end,

[LUMP.SURFEDGES] = function(lump)
	local size = 4
	local vertexes = bsp:GetLump(LUMP.VERTEXES)
	local edges = bsp:GetLump(LUMP.EDGES)
	lump.num = math.min(math.floor(lump.length / size) - 1, 512000 - 1)
	for i = 0, lump.num do
		local n = read "Long"
		local an = math.abs(n)
		local edge = edges.data[an]
		local v1, v2 = edge[1], edge[2]
		if n < 0 then v1, v2 = v2, v1 end
		lump.data[i] = {start = vertexes.data[v1], endpos = vertexes.data[v2]}
	end
end,

[LUMP.TEXDATA] = function(lump)
	local size = 32
	local strdata = bsp:GetLump(LUMP.TEXDATA_STRING_DATA)
	local strtable = bsp:GetLump(LUMP.TEXDATA_STRING_TABLE)
	lump.num = math.min(math.floor(lump.length / size) - 1, 2048 - 1)
	for i = 0, lump.num do
		lump.data[i] = {}
		lump.data[i].refrectivity = read "Vector"
		local strID = read "Long" * 4
		lump.data[i].width = read "Long"
		lump.data[i].height = read "Long"
		lump.data[i].view_width = read "Long"
		lump.data[i].view_height = read "Long"
		lump.data[i].name = ""

		local here = bsp.bsp:Tell()
		bsp.bsp:Seek(strtable.offset + strID)
		local stroffset = read "Long"
		bsp.bsp:Seek(strdata.offset + stroffset)
		for _ = 1, 128 do
			local chr = read(1)
			if chr == '\x00' then break end
			lump.data[i].name = lump.data[i].name .. chr
		end

		bsp.bsp:Seek(here)
	end
end,

[LUMP.TEXINFO] = function(lump)
	local size = 72
	local s, t = 0, 1
	local TexData = bsp:GetLump(LUMP.TEXDATA)
	lump.num = math.min(math.floor(lump.length / size) - 1, 12288 - 1)
	for i = 0, lump.num do
		local here = bsp.bsp:Tell()
		bsp.bsp:Seek(here + size - 4)
		lump.data[i] = setmetatable({}, texture_structure)
		lump.data[i].textureVecs = {[s] = {}, [t] = {}}
		lump.data[i].lightmapVecs = {[s] = {}, [t] = {}}
		lump.data[i].texdataID = read "Long"
		if lump.data[i].texdataID >= 0 then
			bsp.bsp:Seek(here)
			lump.data[i].textureVecs[s][0] = read "Float"
			lump.data[i].textureVecs[s][1] = read "Float"
			lump.data[i].textureVecs[s][2] = read "Float"
			lump.data[i].textureVecs[s][3] = read "Float"
			lump.data[i].textureVecs[t][0] = read "Float"
			lump.data[i].textureVecs[t][1] = read "Float"
			lump.data[i].textureVecs[t][2] = read "Float"
			lump.data[i].textureVecs[t][3] = read "Float"

			lump.data[i].lightmapVecs[s][0] = read "Float"
			lump.data[i].lightmapVecs[s][1] = read "Float"
			lump.data[i].lightmapVecs[s][2] = read "Float"
			lump.data[i].lightmapVecs[s][3] = read "Float"
			lump.data[i].lightmapVecs[t][0] = read "Float"
			lump.data[i].lightmapVecs[t][1] = read "Float"
			lump.data[i].lightmapVecs[t][2] = read "Float"
			lump.data[i].lightmapVecs[t][3] = read "Float"

			lump.data[i].flags = read "Long"
			lump.data[i].TexData = TexData.data[lump.data[i].texdataID]
			bsp.bsp:Skip(4) --texdataID
		end
	end
end,

[LUMP.MODELS] = function(lump)
	local size = 4 * 12
	lump.num = math.floor(lump.length / size) - 1
	for i = 0, lump.num do
		lump.data[i] = {}
		lump.data[i].RootNode = nil
		lump.data[i].FaceTable = {}
		lump.data[i].mins = read("Vector")
		lump.data[i].maxs = read("Vector")
		lump.data[i].origin = read("Vector")
		lump.data[i].headnode = read("Long")
		lump.data[i].firstface = read("Long")
		lump.data[i].numfaces = read("Long")
	end
end,

[LUMP.NODES] = function(lump)
	local size = 32
	lump.num = math.floor(lump.length / size) - 1
	local faces = bsp:GetLump(LUMP.FACES)
	local leafs = bsp:GetLump(LUMP.LEAFS)
	lump.num = math.min(math.floor(lump.length / size) - 1, 65536 - 1)
	for i = 0, lump.num do
		local x, y, z
		lump.data[i] = setmetatable({}, NodeMeta)
		lump.data[i].FaceTable = {}
		lump.data[i].ChildNodes = {}
		lump.data[i].Separator = nil
		lump.data[i].IsLeaf = false
		lump.data[i].planenum = read("Long")
		lump.data[i].children = {}
		lump.data[i].children[1] = read("Long")
		lump.data[i].children[2] = read("Long")
		x = read("Short")
		y = read("Short")
		z = read("Short")
		lump.data[i].mins = Vector(x, y, z)
		x = read("Short")
		y = read("Short")
		z = read("Short")
		lump.data[i].maxs = Vector(x, y, z)
		lump.data[i].firstface = read("UShort")
		lump.data[i].numfaces = read("UShort")
		lump.data[i].area = read("Short")
		lump.data[i].padding = read("Short")
		
		lump.data[i].Separator = planes.data[lump.data[i].planenum]
		for k = 0, lump.data[i].numfaces - 1 do
			lump.data[i].FaceTable[k] = faces.data[lump.data[i].firstface + k]
		end
	end
	
	for i = 0, lump.num do
		for k = 1, 2 do
			local child = lump.data[i].children[k]
			if child < 0 then
				lump.data[i].ChildNodes[k] = leafs.data[-child - 1]
			else
				lump.data[i].ChildNodes[k] = lump.data[child]
			end
		end
	end
end,

[LUMP.LEAFS] = function(lump)
	local size = 32
	local faces = bsp:GetLump(LUMP.FACES)
	local leaffaces = bsp:GetLump(LUMP.LEAFFACES)
	lump.num = math.floor(lump.length / size) - 1
	for i = 0, lump.num do
		local x, y, z
		lump.data[i] = {}
		lump.data[i].FaceTable = {}
		lump.data[i].BrushTable = {}
		lump.data[i].IsLeaf = true
		lump.data[i].index = i
		lump.data[i].contents = read("Long")
		lump.data[i].cluster = read("Short")
		local areaflags = read("Short")
		lump.data[i].area = bit.band(areaflags, 0x01FF)
		lump.data[i].flags = bit.band(bit.rshift(areaflags, 9), 0x007F)
		x = read("Short")
		y = read("Short")
		z = read("Short")
		lump.data[i].mins = Vector(x, y, z)
		x = read("Short")
		y = read("Short")
		z = read("Short")
		lump.data[i].maxs = Vector(x, y, z)
		lump.data[i].firstleafface = read("UShort")
		lump.data[i].numleaffaces = read("UShort")
		lump.data[i].firstleafbrush = read("UShort")
		lump.data[i].numleafbrushes = read("UShort")
		lump.data[i].leafWaterDataID = read("Short")
		lump.data[i].padding = read("Short")
	end
end,

[LUMP.LEAFFACES] = function(lump)
	local size = 2
	lump.num = math.floor(lump.length / size) - 1
	for i = 0, lump.num do
		lump.data[i] = read("UShort")
	end
end,

[LUMP.FACES] = function(lump)
	local size = 56
	local planes = bsp:GetLump(LUMP.PLANES)
	local surfedges = bsp:GetLump(LUMP.SURFEDGES)
	local texinfo = bsp:GetLump(LUMP.TEXINFO)
	local lighting = bsp:GetLump(LUMP.LIGHTING)
	lump.num = math.min(math.floor(lump.length / size) - 1, 65536 - 1)
	for i = 0, lump.num do
		local f = {}
		f.plane = read "UShort"
		f.side = read "Byte"
		f.onNode = read "Byte" == 1
		f.firstedge = read "Long"
		f.numedges = read "Short"
		f.textureinfo = read "Short"
		f.dispinfo = read "Short"
		f.surfaceFogVolumeID = read "Short"
		f.styles = read(4)
		f.lightofs = read "Long"
		f.area = read "Float"
		f.LightmapTextureMinsInLuxels = Vector()
		f.LightmapTextureMinsInLuxels.x = read "Long"
		f.LightmapTextureMinsInLuxels.y = read "Long"
		f.LightmapTextureSizeInLuxels = Vector()
		f.LightmapTextureSizeInLuxels.x = read "Long"
		f.LightmapTextureSizeInLuxels.y = read "Long"
		f.origFace = read "Long"
		f.numPrims = read "UShort"
		f.firstPrimID = read "UShort"
		f.smoothingGroups = read "ULong"

		local PlaneTable = planes.data[f.plane]
		f.index = i
		f.Vertices = {}
		f.PlaneOrigin = PlaneTable.Origin
		f.normal = PlaneTable.normal
		f.angle = f.normal:Angle()
		f.TexInfoTable = texinfo.data[f.textureinfo]
		
		local texname = f.TexInfoTable.TexData.name:lower()
		if texname:find "tools/" or texname:find "water" or texname:find "color" or
			bit.band(f.TexInfoTable.flags, TextureFilterBits) ~= 0 then
			continue
		end

		local fullverts, full2d, center = {}, {}, vector_origin
		for k = 0, f.numedges - 1 do --Fetch all vertices
			fullverts[k] = surfedges.data[f.firstedge + k].start
			center = center + fullverts[k]
		end
		center = center / (#fullverts + 1)
		
		for k, v in pairs(fullverts) do
			full2d[k] = SplatoonSWEPs:To2D(v, center, f.angle)
		end
		
		local v2d = {Area = math.huge} --Vector2D
		local nf = #full2d + 1
		local mins = Vector(math.huge, math.huge, math.huge)
		local maxs = -mins
		for k = 0, #full2d do --Remove collinear and concave components
			local v, v3d = full2d[k], fullverts[k]
			local _next, prev = full2d[(k + 1) % nf], full2d[(k + nf - 1) % nf]
			local sin = (prev - v):GetNormalized():Cross((_next - v):GetNormalized()).z
			if v:DistToSqr(_next) > FACE_MIN_SEGLEN_SQR and sin > FACE_MIN_SIN then
				maxs.x = math.max(maxs.x, v3d.x) --Calculate bounding box
				maxs.y = math.max(maxs.y, v3d.y)
				maxs.z = math.max(maxs.z, v3d.z)
				mins.x = math.min(mins.x, v3d.x)
				mins.y = math.min(mins.y, v3d.y)
				mins.z = math.min(mins.z, v3d.z)
				
				table.insert(v2d, v)
				table.insert(f.Vertices, v3d)
			end
		end
		
		f.mins, f.maxs = mins, maxs
		lump.data[i] = f
		if f.dispinfo >= 0 then continue end
		local ft = MakeSurface(f.plane, mins, maxs, f.normal, f.angle, center, v2d, f.Vertices)
		-- if not ft then continue end
		-- local lv = f.TexInfoTable.lightmapVecs
		-- local td = f.TexInfoTable.TexData
		-- ft.Lightmap = {}
		-- ft.Lightmap.TextureMinsInLuxels = f.LightmapTextureMinsInLuxels
		-- ft.Lightmap.TextureSizeInLuxels = f.LightmapTextureSizeInLuxels
		-- ft.Lightmap.s = Vector(lv[0][0], lv[0][1], lv[0][2])
		-- ft.Lightmap.t = Vector(lv[1][0], lv[1][1], lv[1][2])
		-- ft.Lightmap.Shift = Vector(lv[0][3], lv[1][3])
		-- ft.Lightmap.width = td.width
		-- ft.Lightmap.height = td.height
		-- ft.Lightmap.view_width = td.view_width
		-- ft.Lightmap.view_height = td.view_height
		-- for i, v in ipairs(f.Vertices) do
			-- ft.Lightmap[i] = Vector(v:Dot(ft.Lightmap.s), v:Dot(ft.Lightmap.t)) + ft.Lightmap.Shift - ft.Lightmap.TextureMinsInLuxels
			-- ft.Lightmap[i].x = ft.Lightmap[i].x / 512
			-- ft.Lightmap[i].y = ft.Lightmap[i].y / 256
		-- end
	end
end,

[LUMP.DISPINFO] = function(lump)
	local size = 176
	local faces = bsp:GetLump(LUMP.FACES)
	local dispvertsoffset = bsp:GetLump(LUMP.DISP_VERTS).offset
	lump.num = math.floor(lump.length / size) - 1
	for i = 0, lump.num do
		bsp.bsp:Seek(lump.offset + i * size)
		lump.data[i] = {}
		lump.data[i].startPosition = read "Vector"
		lump.data[i].DispVertStart = read "Long"
		lump.data[i].DispTriStart = read "Long"
		lump.data[i].power = read "Long"
		lump.data[i].minTess = read "Long"
		lump.data[i].smoothingAngle = read "Float"
		lump.data[i].contents = read "Long"
		lump.data[i].MapFace = read "UShort"

		lump.data[i].Face = faces.data[lump.data[i].MapFace]
		if not lump.data[i].Face then continue end
		
		lump.data[i].Face.DispInfoTable = lump.data[i]
		lump.data[i].DispVerts = {}
		for k = 0, (2^lump.data[i].power + 1)^2 - 1 do
			bsp.bsp:Seek(dispvertsoffset + 20 * (lump.data[i].DispVertStart + k))
			lump.data[i].DispVerts[k] = {}
			lump.data[i].DispVerts[k].vec = read "Vector"
			lump.data[i].DispVerts[k].dist = read "Float"
		end

		--Listing up each displacement's vertex
		local disp = lump.data[i]
		local dispface = disp.Face
		local dispverts = disp.DispVerts
		local verts = table.Copy(dispface.Vertices)
		if #verts ~= 4 then continue end

		--DispInfo.startPosition isn't always equal to the first edge so let's find correct one
		local indices, mindist, dist, startedge = {}, math.huge, 0, 0
		for k, v in ipairs(verts) do
			dist = disp.startPosition:DistToSqr(v)
			if dist < mindist then
				startedge = k
				mindist = dist
			end
		end

		for k = 1, 4 do
			indices[k] = (k + startedge - 2) % 4 + 1
		end

		verts[1],
		verts[2],
		verts[3],
		verts[4]
		=	verts[indices[1]],
			verts[indices[2]],
			verts[indices[3]],
			verts[indices[4]]

		local power = 2^disp.power + 1
		local u1 = verts[4] - verts[1]
		local u2 = verts[3] - verts[2]
		local v1 = verts[2] - verts[1]
		local v2 = verts[3] - verts[4]
		local div1, div2 -- vector_origin, vector_origin
		for k, w in pairs(dispverts) do --Get the world positions of the displacements
			x = k % power --0 <= x <= power
			y = math.floor(k / power) --0 <= y <= power
			div1, div2 = v1 * y / (power - 1), u1 + v2 * y / (power - 1)
			div2 = div2 - div1
			w.origin = div1 + div2 * x / (power - 1)
			w.pos = disp.startPosition + w.origin + w.vec * w.dist
		end
		
		--Generate triangles from displacement mesh.
		for k = 0, #dispverts do
			local tri_inv = k % 2 == 0
			if k % power < power - 1 and math.floor(k / power) < power - 1 then
				MakeDispTriangle({
					dispverts[tri_inv and k + power + 1 or k + power].pos,
					dispverts[k + 1].pos,
					dispverts[k].pos,
				}, dispface.normal)

				MakeDispTriangle({
					dispverts[tri_inv and k or k + 1].pos,
					dispverts[k + power].pos,
					dispverts[k + power + 1].pos,
				}, dispface.normal)
			end
		end
	end
end,
}

function bsp:Parse(parse_type)
	local lump = self:GetLump(parse_type or "nil")
	if parse_type and lump and isfunction(ParseFunction[parse_type]) then
		self.bsp:Seek(lump.offset)
		ParseFunction[parse_type](lump)
		lump.parsed = true
	end
end