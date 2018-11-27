
-- This script stands for a framework of Decent Vehicle's waypoints.

include "autorun/decentvehicle.lua"

local dvd = DecentVehicleDestination
-- The waypoints are held in normal table.
-- They're found by brute-force search.

util.AddNetworkString "Decent Vehicle: Add a waypoint"
util.AddNetworkString "Decent Vehicle: Remove a waypoint"
util.AddNetworkString "Decent Vehicle: Add a neighbor"
util.AddNetworkString "Decent Vehicle: Remove a neighbor"
util.AddNetworkString "Decent Vehicle: Traffic light"
util.AddNetworkString "Decent Vehicle: Retrive waypoints"
hook.Add("PostCleanupMap", "Decent Vehicle: Clean up waypoints", function()
	dvd.Waypoints = {}
	for id, undolist in pairs(undo.GetTable()) do
		for i, undotable in pairs(undolist) do
			if not undotable.Functions then continue end
			if not undotable.Functions[1] then continue end
			if undotable.Functions[1][1] ~= dvd.UndoWaypoint then continue end
			undolist[i] = nil
		end
	end
end)

hook.Add("InitPostEntity", "Decent Vehicle: Load waypoints", function()
	local path = "data/decentvehicle/" .. game.GetMap() .. ".txt"
	if not file.Exists(path, "GAME") then return end
	dvd.Waypoints = util.JSONToTable(util.Decompress(file.Read(path, true) or ""))
	for i, w in ipairs(dvd.Waypoints) do
		if w.TrafficLight then
			local trafficlight = ents.Create "dv_traffic_light"
			trafficlight:SetPos(w.TrafficLight.Pos)
			trafficlight:SetAngles(w.TrafficLight.Ang)
			trafficlight:Spawn()
			local ph = trafficlight:GetPhysicsObject()
			if IsValid(ph) then ph:Sleep() end
			w.TrafficLight = trafficlight
		end
	end
end)

hook.Add("Tick", "Decent Vehicle: Control traffic lights", function()
	for PatternName, TL in pairs(dvd.TrafficLights) do
		if CurTime() < TL.Time then continue end
		TL.Light = TL.Light % 3 + 1
		TL.Time = CurTime() + dvd.TLDuration[TL.Light]
	end
end)

concommand.Add("dv_route_save", function(ply)
	local path = "decentvehicle/"
	if not file.Exists(path, "DATA") then file.CreateDir(path) end
	path = path .. game.GetMap() .. ".txt"
	
	local save = {}
	for i, w in ipairs(dvd.Waypoints) do
		save[i] = table.Copy(w)
		if IsValid(w.TrafficLight) then
			save[i].TrafficLight = {
				Pos = w.TrafficLight:GetPos(),
				Ang = w.TrafficLight:GetAngles(),
			}
		else
			save[i].TrafficLight = nil
		end
	end
	
	file.Write(path, util.Compress(util.TableToJSON(save)))
	ply:SendLua "notification.AddLegacy(\"Decent Vehicle: Waypoints saved!\", NOTIFY_GENERIC, 5)"
end)

local function GetWaypointFromID(id)
	return assert(dvd.Waypoints[id], "Decent Vehicle: Waypoint is not found!")
end

net.Receive("Decent Vehicle: Retrive waypoints", function(_, ply)
	local id = net.ReadUInt(24)
	net.Start "Decent Vehicle: Retrive waypoints"
	if id > #dvd.Waypoints then
		net.WriteUInt(0, 24)
		net.Send(ply)
		return
	end
	
	local waypoint = GetWaypointFromID(id)
	net.WriteUInt(id, 24)
	net.WriteVector(waypoint.Target)
	net.WriteEntity(waypoint.TrafficLight or NULL)
	net.WriteUInt(#waypoint.Neighbors, 14)
	for i, n in ipairs(waypoint.Neighbors) do
		net.WriteUInt(n, 24)
	end
	net.Send(ply)
end)

-- Creates a new waypoint at given position.
-- The new ID is always #dvd.Waypoints.
-- Argument:
--   Vector pos		| The position of new waypoint.
-- Returning:
--   table waypoint	| Created waypoint.
function dvd.AddWaypoint(pos)
	local waypoint = {Target = pos, Neighbors = {}}
	table.insert(dvd.Waypoints, waypoint)
	net.Start "Decent Vehicle: Add a waypoint"
	net.WriteVector(pos)
	net.Broadcast()
	return waypoint
end

-- Removes a waypoint by ID.
-- Argument:
--   number id	| An unsigned number to remove.
function dvd.RemoveWaypoint(id)
	if isvector(id) then id = select(2, dvd.GetNearestWaypoint(id)) end
	if not id then return end
	for _, w in ipairs(dvd.Waypoints) do
		local Neighbors = {}
		for _, n in ipairs(w.Neighbors) do
			if n > id then
				table.insert(Neighbors, n - 1)
			elseif n < id then
				table.insert(Neighbors, n)
			end
		end
		
		w.Neighbors = Neighbors
	end
	
	table.remove(dvd.Waypoints, id)
	net.Start "Decent Vehicle: Remove a waypoint"
	net.WriteUInt(id, 24)
	net.Broadcast()
end

-- Undo function that removes the most recent waypoint.
function dvd.UndoWaypoint(undoinfo)
	for i, w in SortedPairsByMemberValue(dvd.Waypoints, "Time", true) do
		if undoinfo.Owner == w.Owner then
			dvd.RemoveWaypoint(i)
			return
		end
	end
end

-- Retrives the nearest waypoint to the given position.
-- Arguments:
--   Vector pos			| The position to find.
--   number radius		| Optional.  The maximum radius.
-- Returnings:
--   table waypoint		| The found waypoint.  Can be nil.
--   number waypointID	| The ID of found waypoint.
function dvd.GetNearestWaypoint(pos, radius)
	if not isvector(pos) then return end
	local mindist, waypoint, waypointID = radius and radius^2 or math.huge, nil, nil
	for i, w in ipairs(dvd.Waypoints) do
		local distance = w.Target:DistToSqr(pos)
		if distance < mindist then
			mindist, waypoint, waypointID = distance, w, i
		end
	end
	
	return waypoint, waypointID
end

-- Adds a link between two waypoints.
-- The link is one-way, one to another.
-- Arguments:
--   number from	| The waypoint ID the link starts from.
--   number to		| The waypoint ID connected to.
function dvd.AddNeighbor(from, to)
	table.insert(GetWaypointFromID(from).Neighbors, to)
	net.Start "Decent Vehicle: Add a neighbor"
	net.WriteUInt(from, 24)
	net.WriteUInt(to, 24)
	net.Broadcast()
end

-- Removes an existing link between two waypoints.
-- Does nothing if the given link is not found.
-- Arguments:
--   number from	| The waypoint ID the link starts from.
--   number to		| The waypoint ID connected to.
function dvd.RemoveNeighbor(from, to)
	table.RemoveByValue(GetWaypointFromID(from).Neighbors, to)
	net.Start "Decent Vehicle: Remove a neighbor"
	net.WriteUInt(from, 24)
	net.WriteUInt(to, 24)
	net.Broadcast()
end

-- Adds a link between a waypoint and a traffic light entity.
-- Arguments:
--   number id		| The waypoint ID.
--   Entity traffic	| The traffic light entity.  Giving nil to remove the link.
function dvd.AddTrafficLight(id, traffic)
	local waypoint = GetWaypointFromID(id)
	if not IsValid(traffic)
	or traffic:GetClass() ~= "dv_traffic_light"
	or waypoint.TrafficLight == traffic then
		traffic = nil
	end
	
	waypoint.TrafficLight = traffic
	net.Start "Decent Vehicle: Traffic light"
	net.WriteUInt(id, 24)
	net.WriteEntity(traffic or NULL)
	net.Broadcast()
end

-- Gets a waypoint connected from the given randomly.
-- Argument:
--   table waypoint	| The given waypoint.
--   Vector pos		| If specified, removes waypoints that makes U-turn from suggestions.
-- Returning:
--   table waypoint | The connected waypoint.
function dvd.GetRandomNeighbor(waypoint, pos)
	if not waypoint.Neighbors then return end
	
	local suggestion = {}
	for i, n in ipairs(waypoint.Neighbors) do
		local w = GetWaypointFromID(n)
		if not w then continue end
		if not pos or (waypoint.Target - pos):Dot(w.Target - waypoint.Target) > 0 then
			table.insert(suggestion, w)
		end
	end
	
	return suggestion[math.random(#suggestion)]
end

-- Retrives a table of waypoints that represents the route
-- from start to one of the destination in endpos.
-- Using A* pathfinding algorithm.
-- Arguments:
--   number start	| The beginning waypoint ID.
--   table endpos	| A table of destination waypoint IDs. {[ID] = true}
-- Returning:
--   table route	| List of waypoints.  start is the first, endpos is the last.
function dvd.GetRoute(start, endpos)
	if not (isnumber(start) and istable(endpos)) then return end
	
	local nodes, opens = {}, {}
	local function CreateNode(id)
		nodes[id] = {
			estimate = 0,
			closed = nil,
			cost = 0,
			id = id,
			parent = nil,
			score = 0,
		}
		
		return nodes[id]
	end
	
	local function EstimateCost(node)
		node = GetWaypointFromID(node.id).Target
		local cost = math.huge
		for id in pairs(endpos) do
			cost = math.min(cost, node:Distance(GetWaypointFromID(id).Target))
		end
		
		return cost
	end
	
	local function AddToOpenList(node, parent)
		if parent then
			local nodepos = GetWaypointFromID(node.id).Target
			local parentpos = GetWaypointFromID(parent.id).Target
			local cost = parentpos:Distance(nodepos)
			local grandpa = parent.parent
			if grandpa then -- Angle between waypoints is considered as cost
				local gppos = GetWaypointFromID(grandpa.id).Target
				cost = cost --* (2 - dvd.GetAng3(gppos, parentpos, nodepos))
			end
			
			node.cost = parent.cost + cost
		end
		
		node.closed = false
		node.estimate = EstimateCost(node)
		node.parent = parent
		node.score = node.estimate + node.cost
		
		-- Open list is binary heap
		table.insert(opens, node.id)
		local i = #opens
		local p = math.floor(i / 2)
		while i > 0 and p > 0 and nodes[opens[i]].score < nodes[opens[p]].score do
			opens[i], opens[p] = opens[p], opens[i]
			i, p = p, math.floor(p / 2)
		end
	end
	
	start = CreateNode(start)
	for id in pairs(endpos) do
		endpos[id] = CreateNode(id)
	end
	
	AddToOpenList(start)
	while #opens > 0 do
		local current = opens[1] -- Pop a node which has minimum cost.
		opens[1] = opens[#opens]
		opens[#opens] = nil
		
		local i = 1 -- Down-heap on the open list
		while i <= #opens do
			local c = i * 2
			if not opens[c] then break end
			c = c + (opens[c + 1] and nodes[opens[c]].score > nodes[opens[c + 1]].score and 1 or 0)
			if nodes[opens[c]].score >= nodes[opens[i]].score then break end
			opens[i], opens[c] = opens[c], opens[i]
			i = c
		end
		
		if nodes[current].closed then continue end
		if endpos[current] then
			current = nodes[current]
			local route = {}
			while current.parent do
				debugoverlay.Sphere(GetWaypointFromID(current.id).Target, 30, 5, Color(0, 255, 0))
				debugoverlay.SweptBox(GetWaypointFromID(current.parent.id).Target, GetWaypointFromID(current.id).Target, Vector(-10, -10, -10), Vector(10, 10, 10), angle_zero, 5, Color(0, 255, 0))
				table.insert(route, 1, (GetWaypointFromID(current.id)))
				current = current.parent
			end
			
			return route
		end
		
		nodes[current].closed = true
		for i, n in ipairs(GetWaypointFromID(nodes[current].id).Neighbors) do
			if nodes[n] and nodes[n].closed ~= nil then continue end
			AddToOpenList(nodes[n] or CreateNode(n), nodes[current])
		end
	end
end

-- Retrives a table of waypoints that represents the route
-- from start to one of the destination in endpos.
-- Arguments:
--   Vector start	| The beginning position.
--   table endpos	| A table of Vectors that represent destinations.  Can also be a Vector.
-- Returning:
--   table route	| The same as returning value of dvd.GetRoute()
function dvd.GetRouteVector(start, endpos)
	if isvector(endpos) then endpos = {endpos} end
	if not (isvector(start) and istable(endpos)) then return end
	local endpostable = {}
	for _, p in ipairs(endpos) do
		local id = select(2, dvd.GetNearestWaypoint(p))
		if not id then continue end
		endpostable[id] = true
	end
	
	return dvd.GetRoute(select(2, dvd.GetNearestWaypoint(start)), endpostable)
end
