
--The problem is functions between default Angle:Normalize() and SLVBase's one have different behaviour:
--default one changes the given angle, SLV's one returns normalized angle.
--So I need to branch the normalize function.  I hate SLVBase.
local NormalizeAngle = FindMetaTable("Angle").Normalize
if SLVBase then NormalizeAngle = function(ang) ang:Set(ang:Normalize()) return ang end end

--Some parts of code are from BSP Snap.
local LUMP_VERTEXES		=  3 + 1
local LUMP_EDGES		= 12 + 1
local LUMP_SURFEDGES	= 13 + 1
local LUMP_FACES		=  7 + 1
local LUMP_DISPINFO		= 26 + 1
local LUMP_DISP_VERTS	= 33 + 1
local LUMP_DISP_TRIS	= 48 + 1

local chunksize = 384
local chunkrate = chunksize / 2
local chunkbound = Vector(chunksize, chunksize, chunksize)
local function IsExternalSurface(verts, center, normal)
	normal = normal * 0.5
	return
		bit.band(util.PointContents(center + normal), ALL_VISIBLE_CONTENTS) == 0 or
		bit.band(util.PointContents(verts[1] + (center - verts[1]) * 0.05 + normal), ALL_VISIBLE_CONTENTS) == 0 or
		bit.band(util.PointContents(verts[2] + (center - verts[2]) * 0.05 + normal), ALL_VISIBLE_CONTENTS) == 0 or
		bit.band(util.PointContents(verts[3] + (center - verts[3]) * 0.05 + normal), ALL_VISIBLE_CONTENTS) == 0
end

local time = SysTime()
local loadtime = 0
local Debug = {
	CornerModulation = false,
	DrawMesh = false,
	TakeTime = true,
	WriteGeometryInfo = false,
}
local function ShowTime(str)
	if not Debug.TakeTime then return end
	loadtime = loadtime + SysTime() - time
	print("SplatoonSWEPs: " .. SysTime() - time .. " seconds.", str)
	time = SysTime()
end

SplatoonSWEPs = SplatoonSWEPs or {
Initialize = function()
	time, loadtime = SysTime(), 0
	
	local points = game.GetWorld():GetPhysicsObject()
	if not IsValid(points) then print("invalid world physics object") return end
	points = points:GetMesh()
	local surf = {} --Get triangles of the map, except displacements
	for i = 1, #points, 3 do
		local vert = {points[i + 2].pos, points[i + 1].pos, points[i].pos}
		local normal = (vert[2] - vert[1]):Cross(vert[3] - vert[2]):GetNormalized()
		local center = (vert[1] + vert[2] + vert[3]) / 3
		if bit.band(util.PointContents(center - normal * 0.1), CONTENTS_GRATE) == 0 and IsExternalSurface(vert, center, normal) then
			table.insert(surf, {id = #surf + 1, vertices = vert, normal = normal, center = center})
		end
	end
	
	ShowTime("Map Physics Mesh Loaded")
	
	--Parse bsp and get displacement info
	local lumps, vertexes, edges, surfedges, faces = {}, {}, {}, {}, {}
	local dispinfo = {} --Lump 26 DispInfo structure
	local dispvertices = {} --The actual vertices
	local mapname = "maps/" .. game.GetMap() .. ".bsp"
	local f = file.Open(mapname, "rb", "GAME")
	if f then
		f:Seek(8) --Identifier, Version
		for i = 0, 63 do --Lumps, index of the contents
			local fileofs = f:ReadLong()
			local filelen = f:ReadLong()
			f:Skip(4 + 4) --version, fourCC
			table.insert(lumps, {fileofs = fileofs, filelen = filelen})
		end
		
		--Vertexes, all vertices including displacements
		f:Seek(lumps[LUMP_VERTEXES].fileofs)
		local x, y, z, i = 0, 0, 0, 0
		while 12 * i < lumps[LUMP_VERTEXES].filelen do
			f:Seek(lumps[LUMP_VERTEXES].fileofs + 12 * i)
			i = i + 1
			x = f:ReadFloat()
			y = f:ReadFloat()
			z = f:ReadFloat()
			vertexes[i] = Vector(x, y, z)
		end
		
		i = 0 --Edges, vertex1 to vertex2
		f:Seek(lumps[LUMP_EDGES].fileofs)
		while 4 * i < lumps[LUMP_EDGES].filelen do
			f:Seek(lumps[LUMP_EDGES].fileofs + 4 * i)
			i = i + 1
			edges[i] = {}
			edges[i][1] = f:Read(2) --Reading unsigned short(16-bit integer)
			edges[i][1] = string.byte(edges[i][1][1]) + bit.lshift(string.byte(edges[i][1][2]), 8)
			edges[i][2] = f:Read(2)
			edges[i][2] = string.byte(edges[i][2][1]) + bit.lshift(string.byte(edges[i][2][2]), 8)
		end
		
		i = 0 --Surfedges, indices of edges
		f:Seek(lumps[LUMP_SURFEDGES].fileofs)
		while 4 * i < lumps[LUMP_SURFEDGES].filelen do
			i = i + 1
			surfedges[i] = f:ReadLong() --wiki says this is an array of (signed) integers.
		end
		
		i = 0 --Faces
		f:Seek(lumps[LUMP_FACES].fileofs)
		while 56 * i < lumps[LUMP_FACES].filelen do
			f:Seek(lumps[LUMP_FACES].fileofs + 56 * i + 2 + 1 + 1) --short planenum, byte side, byte onNode
			i = i + 1
			faces[i] = {}
			faces[i].firstedge = f:ReadLong()
			faces[i].numedges = f:ReadShort()
		end
		
		i = 0 --DispInfo, information of displacements
		f:Seek(lumps[LUMP_DISPINFO].fileofs)
		while 176 * i < lumps[LUMP_DISPINFO].filelen do
			f:Seek(lumps[LUMP_DISPINFO].fileofs + 176 * i)
			i = i + 1
			x = f:ReadFloat()
			y = f:ReadFloat()
			z = f:ReadFloat()
			dispinfo[i] = {}
			dispinfo[i].startPosition = Vector(x, y, z) --Vector
			dispinfo[i].DispVertStart = f:ReadLong() --int
			dispinfo[i].DispTriStart = f:ReadLong() --int
			dispinfo[i].power = f:ReadLong() --int
			f:Skip(4 + 4 + 4) --int minTess, float smoothingAngle, int contents
			dispinfo[i].MapFace = f:Read(2) --unsigned short
			dispinfo[i].MapFace = string.byte(dispinfo[i].MapFace[1]) + bit.lshift(string.byte(dispinfo[i].MapFace[2]), 8)
			
			--DispVerts, table of distance from original position
			dispinfo[i].dispverts = {}
			for k = 1, (2^dispinfo[i].power + 1)^2 do
				f:Seek(lumps[LUMP_DISP_VERTS].fileofs + (dispinfo[i].DispVertStart + k - 1) * 20)
				x = f:ReadFloat()
				y = f:ReadFloat()
				z = f:ReadFloat()
				dispinfo[i].dispverts[k] = {}
				dispinfo[i].dispverts[k].vec = Vector(x, y, z)
				dispinfo[i].dispverts[k].dist = f:ReadFloat()
			end
			dispinfo[i].surf = {}
			dispinfo[i].surf.face = faces[dispinfo[i].MapFace + 1] --firstedge, numedges
			dispinfo[i].surf.edge = {} --Corner edges of the displacement
			dispinfo[i].vertices = {} --Corner positions of the displacement
		end
		
		--Finished fetching data
		ShowTime("BSP Loaded")
		if Debug.WriteGeometryInfo then
			PrintTable(lumps) print("")
			PrintTable(vertexes) print("")
			PrintTable(edges) print("")
			PrintTable(surfedges) print("")
			PrintTable(faces) print("")
		end
		
		--Make DispInfo more convenient
		for k, v in ipairs(dispinfo) do
			local edgeindex, v1, v2 = 0, 0, 0
			for i = v.surf.face.firstedge, v.surf.face.firstedge + v.surf.face.numedges - 1 do
				edgeindex = math.abs(surfedges[i + 1]) + 1 --wiki says surface number can be negative
				v1, v2 = edges[edgeindex][1] + 1, edges[edgeindex][2] + 1
				if surfedges[i + 1] < 0 then v1, v2 = v2, v1 end --If it is negative, it is inversed
				v1, v2 = vertexes[v1], vertexes[v2] --Get actual vectors from vector indices
				table.insert(v.vertices, v1) --We use the first one
			end
			
			--DispInfo.startPosition isn't always equal to vertices[1] so let's find the correct one
			if #v.vertices == 4 then
				local index, startedge = {}, 0
				for i = 1, 4 do
					if v.startPosition:DistToSqr(v.vertices[i]) < 0.02 then
						startedge = i
						break
					end
				end
				
				if Debug.CornerModulation then
					print(k, startedge, "",
						v.vertices[1]:DistToSqr(v.startPosition),
						v.vertices[2]:DistToSqr(v.startPosition),
						v.vertices[3]:DistToSqr(v.startPosition),
						v.vertices[4]:DistToSqr(v.startPosition))
				end
				
				for i = 0, 3 do
					index[i + 1] = ((i + startedge - 1) % 4) + 1
				end
				
				v.vertices[1],
				v.vertices[2],
				v.vertices[3],
				v.vertices[4]
				=	v.vertices[index[1]],
					v.vertices[index[2]],
					v.vertices[index[3]],
					v.vertices[index[4]]
				
				--Get the original positions of the displacement geometry
				local power = 2^v.power + 1
				local u1 = v.vertices[4] - v.vertices[1]
				local u2 = v.vertices[3] - v.vertices[2]
				local v1 = v.vertices[2] - v.vertices[1]
				local v2 = v.vertices[3] - v.vertices[4]
				local div1, div2 = vector_origin, vector_origin
				for i, w in ipairs(v.dispverts) do
					x = (i - 1) % power --0 <= x <= power
					y = math.floor((i - 1) / power) -- 0 <= y <= power
					div1, div2 = v1 * y / (power - 1), u1 + v2 * y / (power - 1)
					div2 = div2 - div1
					w.origin = div1 + div2 * x / (power - 1)
				end
				
				--Get the actual positions of the displacement geometry
				dispvertices[k] = {}
				for i, w in ipairs(v.dispverts) do
					dispvertices[k][i] = v.startPosition + w.origin + w.vec * w.dist
				end
				
				--Generate triangles from positions
				for i = 1, #dispvertices[k] do
					local row = math.floor((i - 1) / power)
					local tri_inv = i % 2 ~= 0
					if (i - 1) % power < power - 1 and row < power - 1 then						
						x, y, z = i, i + 1, i + power
						if tri_inv then z = z + 1 end
					--	4, 13, 5 |\
					--	3, 13, 4 |/
					--	2, 11, 3 |\
					--	1, 11, 2 |/
						local vert = {dispvertices[k][x], dispvertices[k][y], dispvertices[k][z]}
						local normal = (vert[2] - vert[1]):Cross(vert[3] - vert[2]):GetNormalized()
						local center = (vert[1] + vert[2] + vert[3]) / 3
						if IsExternalSurface(vert, center, normal) then
							table.insert(surf, {id = #surf + 1, vertices = vert, normal = normal, center = center})
							table.insert(points, {pos = vert[1]})
							table.insert(points, {pos = vert[2]})
							table.insert(points, {pos = vert[3]})
							if Debug.DrawMesh and k == 1 then
								debugoverlay.Text(vert[1], i, 10, true)
								debugoverlay.Line(vert[1], vert[1] + normal * 50, 10, Color(255,255,0), true)
								debugoverlay.Line(vert[1], vert[2], 10, Color(0,255,255), true)
								debugoverlay.Line(vert[2], vert[3], 10, Color(0,255,0), true)
								debugoverlay.Line(vert[3], vert[1], 10, Color(0,255,0), true)
							end
						end
						
						x, y, z = i + power + 1, i + power, i
						if not tri_inv then z = z + 1 end
						vert = {dispvertices[k][x], dispvertices[k][y], dispvertices[k][z]}
						normal = (vert[2] - vert[1]):Cross(vert[3] - vert[2]):GetNormalized()
						center = (vert[1] + vert[2] + vert[3]) / 3
						if IsExternalSurface(vert, center, normal) then
							table.insert(surf, {id = #surf + 1, vertices = vert, normal = normal, center = center})
							table.insert(points, {pos = vert[1]})
							table.insert(points, {pos = vert[2]})
							table.insert(points, {pos = vert[3]})
							if Debug.DrawMesh and k == 1 then
								debugoverlay.Line(vert[1], vert[2], 10, Color(0,255,0), true)
								debugoverlay.Line(vert[2], vert[3], 10, Color(0,255,0), true)
								debugoverlay.Line(vert[3], vert[1], 10, Color(0,255,0), true)
							end
						end
					end
				end
			end
		end
		
		SplatoonSWEPs.DispInfo = dispinfo
		SplatoonSWEPs.DispVertices = dispvertices
		SplatoonSWEPs.Points = points
		SplatoonSWEPs.Surface = surf
		f:Close()
	end
	
	ShowTime("Displacement Analyzed")
	
	--Tear into pieces from BSP Snap
	--Map bound
	local min, max = Vector(math.huge, math.huge, math.huge), Vector(-math.huge, -math.huge, -math.huge)
	for i, p in ipairs(points) do --calculate minimum and maximum vector of map
		for _, d in ipairs({"x", "y", "z"}) do
			if p.pos[d] < min[d] then
				min[d] = p.pos[d]
			elseif p.pos[d] > max[d] then
				max[d] = p.pos[d]
			end
		end
	end

	local grid = {}
	local max_scalar = math.max(math.abs(max.x), math.abs(max.y), math.abs(max.z),
								math.abs(min.x), math.abs(min.y), math.abs(min.z))
	local mapsize = max_scalar - max_scalar % chunksize + chunksize
	for x = -mapsize, mapsize, chunkrate do
		grid[x] = {}
		for y = -mapsize, mapsize, chunkrate do
			grid[x][y] = {}
			for z = -mapsize, mapsize, chunkrate do
				grid[x][y][z] = {}
			end
		end
	end
	
	--Put surfaces into grids
	for _, s in ipairs(surf) do
		for i = 1, #s.vertices do
			local v1 = s.vertices[i]
			local v2 = s.vertices[i % #s.vertices + 1]
			local x1, y1, z1 = v1.x - v1.x % chunksize, v1.y - v1.y % chunksize, v1.z - v1.z % chunksize
			local x2, y2, z2 = v2.x - v2.x % chunksize, v2.y - v2.y % chunksize, v2.z - v2.z % chunksize
			local gx, gy, gz, addlist = {}, {}, {}, {}
			if x1 > x2 then x1, x2 = x2, x1 end
			if y1 > y2 then y1, y2 = y2, y1 end
			if z1 > z2 then z1, z2 = z2, z1 end
			x2, y2, z2 = x2 + chunksize, y2 + chunksize, z2 + chunksize
			x1, y1, z1 = x1 - chunksize, y1 - chunksize, z1 - chunksize
			for x = x1, x2, chunkrate do gx[x] = true end
			for y = y1, y2, chunkrate do gy[y] = true end
			for z = z1, z2, chunkrate do gz[z] = true end
			for x in pairs(gx) do
				for y in pairs(gy) do
					for z in pairs(gz) do
						addlist[Vector(x, y, z)] = true
					end
				end
			end
			gz, gy, gz = {}, {}, {}
			
			--I couldn't handle collision detection between AABB and line segment
			--So I'll just add surfaces to all suggested grids
			for a in pairs(addlist) do
				if grid[a.x] and grid[a.x][a.y] and grid[a.x][a.y][a.z] and not grid[a.x][a.y][a.z][s] then
					grid[a.x][a.y][a.z][s] = true
				end
			end
		end
	end
	
	SplatoonSWEPs.MapSize = mapsize
	SplatoonSWEPs.GridSurf = grid
	if Debug.TakeTime then
		ShowTime("Grid Generated")
		print("SplatoonSWEPs: Finished parsing map vertices, with " .. loadtime .. " seconds!")
	end
end,

Check = function(point)
	local x = point.x - point.x % chunkrate
	local y = point.y - point.y % chunkrate
	local z = point.z - point.z % chunkrate
	-- debugoverlay.Box(Vector(x, y, z), vector_origin,
	-- Vector(chunksize, chunksize, chunksize), 5, Color(0,255,0))
	return SplatoonSWEPs.GridSurf[x][y][z]
end,}
hook.Add("InitPostEntity", "SetupSplatoonGeometry", SplatoonSWEPs.Initialize)

include "splatoon_inkmanager.lua"
