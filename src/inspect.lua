--[[

	NanoC
	=====

	Copyright (C) 2024-2026 Joachim Stolberg

	AGPL v3
	See LICENSE.txt for more information

	Read-only Techage inspection for external clients / AI.

	Builds a structured snapshot (graph) of the TA4 techage network around a
	position: nodes with number/state/inventory plus their connections
	(tube lines resolved via tubelib2's Tube, direct neighbours as a hint).

	Only TA4 is supported by design (TA2 has no automation).

]]--

if not minetest.global_exists("techage") then
	nanoc = nanoc or {}
	function nanoc.inspect() return nil end
	return
end

local P2S = minetest.pos_to_string

local StateName = setmetatable({}, {
	__index = function(_, v) return tostring(v) end,
})
for _, k in ipairs({ "RUNNING", "BLOCKED", "STANDBY", "NOPOWER", "FAULT",
		"STOPPED", "UNLOADED", "INACTIVE" }) do
	if techage[k] then
		StateName[techage[k]] = k
	end
end

local function is_ta4(name)
	return name:find("ta4_", 1, true) ~= nil
end

local function collect_names()
	local names = {}
	for name in pairs(techage.NodeDef) do
		if is_ta4(name) then
			names[#names + 1] = name
		end
	end
	return names
end

local function inventory_snapshot(pos)
	local inv = minetest.get_meta(pos):get_inventory()
	if not inv then
		return nil
	end
	local lists = {}
	local any = false
	for _, listname in ipairs(inv:get_lists()) do
		local items = {}
		for _, stack in ipairs(inv:get_list(listname)) do
			if not stack:is_empty() then
				items[#items + 1] = { item = stack:get_name(), count = stack:get_count() }
				if #items >= 32 then break end
			end
		end
		if #items > 0 then
			lists[listname] = items
			any = true
		end
	end
	return any and lists or nil
end

local function node_state(pos)
	local ok, nvm = pcall(techage.get_nvm, pos)
	if ok and nvm and nvm.techage_state then
		return StateName[nvm.techage_state]
	end
end

-- Returns { center, radius, nodes = {...}, edges = {...} }
function nanoc.inspect(center, radius)
	radius = math.min(math.max(tonumber(radius) or 8, 1), 32)
	local pos1 = { x = center.x - radius, y = center.y - radius, z = center.z - radius }
	local pos2 = { x = center.x + radius, y = center.y + radius, z = center.z + radius }

	local nodes = {}
	local by_key = {}
	local names = collect_names()
	if #names > 0 then
		for _, pos in ipairs(minetest.find_nodes_in_area(pos1, pos2, names)) do
			local node = minetest.get_node(pos)
			local meta = minetest.get_meta(pos)
			local ndef = minetest.registered_nodes[node.name]
			local entry = {
				pos = { x = pos.x, y = pos.y, z = pos.z },
				name = node.name,
				description = ndef and ndef.description or "",
				number = meta:get_string("node_number"),
				owner = meta:get_string("owner"),
				param2 = node.param2,
				state = node_state(pos),
				inv = inventory_snapshot(pos),
			}
			nodes[#nodes + 1] = entry
			by_key[P2S(pos)] = entry
		end
	end

	-- Edges: follow tube lines; fall back to direct ta4 neighbours.
	local edges = {}
	local Tube = techage.Tube
	for _, entry in ipairs(nodes) do
		local pos = entry.pos
		for dir = 1, 6 do
			local npos = Tube:get_connected_node_pos(pos, dir)
			if npos then
				local adjacent = tubelib2.get_pos(pos, dir)
				local peer = by_key[P2S(npos)]
				local via = (not vector.equals(npos, adjacent)) and "tube" or "adjacent"
				if peer and not vector.equals(npos, pos) then
					edges[#edges + 1] = {
						from = entry.number, to = peer.number,
						dir = dir, via = via,
					}
				end
			end
		end
	end

	return {
		center = { x = center.x, y = center.y, z = center.z },
		radius = radius,
		nodes = nodes,
		edges = edges,
	}
end

-- In-game test command
minetest.register_chatcommand("nanoc_inspect", {
	description = "Print a TA4 techage snapshot around you (radius optional)",
	params = "[radius]",
	func = function(name, param)
		local player = minetest.get_player_by_name(name)
		if not player then return false, "No player" end
		local center = vector.round(player:get_pos())
		local snap = nanoc.inspect(center, tonumber(param) or 8)
		local json = minetest.write_json(snap)
		minetest.log("action", "[nanoc] inspect: " .. json)
		return true, "Snapshot (" .. #snap.nodes .. " nodes, " .. #snap.edges ..
			" edges) written to the server log"
	end,
})
