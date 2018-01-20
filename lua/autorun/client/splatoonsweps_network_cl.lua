
--net.Receive's
if not SplatoonSWEPs then return end

net.Receive("SplatoonSWEPs: DrawInk", function(len, ply)
	local facenumber = net.ReadInt(20)
	local color = net.ReadUInt(SplatoonSWEPs.COLOR_BITS)
	local pos = net.ReadVector()
	local radius = net.ReadFloat()
	local inkangle = net.ReadFloat()
	table.insert(SplatoonSWEPs.InkQueue, {
		c = color,
		inkangle = inkangle,
		isdisplacement = facenumber < 0,
		n = math.abs(facenumber),
		pos = pos,
		r = radius,
	})
end)

net.Receive("SplatoonSWEPs: Send error message from server", function(...)
	local msg = net.ReadString()
	local icon = net.ReadUInt(3)
	local duration = net.ReadUInt(4)
	notification.AddLegacy(msg, icon, duration)
end)

net.Receive("SplatoonSWEPs: Play damage sound", function(...)
	surface.PlaySound(SplatoonSWEPs[net.ReadString()])
end)