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

-- TA4 node names come in two flavours: "techage:ta4_pusher" and
-- "techage:chest_ta4" -> match "ta4" anywhere.
local function is_ta4(name)
	return name:find("ta4", 1, true) ~= nil
end

local function clean(s)
	if not s then return nil end
	-- strip Luanti translated-string markers: ESC "(@...)" and ESC "E"
	s = s:gsub("\27%([^)]*%)", "")
	s = s:gsub("\27.", "")
	s = s:gsub("%c", "")
	s = s:gsub("^%s+", ""):gsub("%s+$", "")
	return s ~= "" and s or nil
end

local function label(name)
	return (name:gsub("^%a+:", ""):gsub("_", " "))
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
		return nil, nil
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
	local inv_state
	if inv:get_size("main") > 0 then
		inv_state = techage.get_inv_state(inv, "main")   -- empty/loaded/full
	end
	return (any and lists or nil), inv_state
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
	local names = collect_names()
	if #names > 0 then
		for _, pos in ipairs(minetest.find_nodes_in_area(pos1, pos2, names)) do
			local node = minetest.get_node(pos)
			local meta = minetest.get_meta(pos)
			local inv, inv_state = inventory_snapshot(pos)
			local number = meta:get_string("node_number")
			local pull_dir = meta:get_int("pull_dir")
			local push_dir = meta:get_int("push_dir")
			nodes[#nodes + 1] = {
				id = number ~= "" and number or P2S(pos),
				pos = { x = pos.x, y = pos.y, z = pos.z },
				name = node.name,
				label = label(node.name),
				infotext = clean(meta:get_string("infotext")),
				number = number,
				owner = meta:get_string("owner"),
				param2 = node.param2,
				state = node_state(pos),
				inv_state = inv_state,
				inv = inv,
				pull_dir = pull_dir > 0 and pull_dir or nil,
				push_dir = push_dir > 0 and push_dir or nil,
			}
		end
	end

	-- Edges: follow tube lines; fall back to direct TA4 neighbours.
	local edges = {}
	local seen = {}
	local Tube = techage.Tube
	for _, entry in ipairs(nodes) do
		local pos = entry.pos
		for dir = 1, 6 do
			local npos = Tube:get_connected_node_pos(pos, dir)
			if npos and not vector.equals(npos, pos) then
				local peer_node = minetest.get_node_or_nil(npos)
				if peer_node and peer_node.name:find("techage:", 1, true) then
					local peer_meta = minetest.get_meta(npos)
					local peer_num = peer_meta:get_string("node_number")
					local adjacent = tubelib2.get_pos(pos, dir)
					local via = (not vector.equals(npos, adjacent)) and "tube" or "adjacent"
					local key = entry.id .. ">" .. (peer_num ~= "" and peer_num or P2S(npos)) .. ":" .. via
					if not seen[key] then
						seen[key] = true
						edges[#edges + 1] = {
							from = entry.id,
							to = peer_num ~= "" and peer_num or P2S(npos),
							to_name = peer_node.name,
							to_pos = { x = npos.x, y = npos.y, z = npos.z },
							dir = dir,
							via = via,
						}
					end
				end
			end
		end
	end

	-- Directed flow for nodes that push (pushers store pull_dir/push_dir).
	local flow = {}
	local function peer_info(npos)
		local n = minetest.get_node_or_nil(npos)
		if not n then return nil end
		local num = minetest.get_meta(npos):get_string("node_number")
		return {
			id = num ~= "" and num or P2S(npos),
			name = n.name,
			pos = { x = npos.x, y = npos.y, z = npos.z },
		}
	end
	for _, entry in ipairs(nodes) do
		local pos = entry.pos
		if entry.pull_dir then
			local peer = Tube:get_connected_node_pos(pos, entry.pull_dir)
			if peer and not vector.equals(peer, pos) then
				local pi = peer_info(peer)
				if pi then
					flow[#flow + 1] = { from = pi.id, from_name = pi.name,
						to = entry.id, role = "pull", dir = entry.pull_dir }
				end
			end
		end
		if entry.push_dir then
			local peer = Tube:get_connected_node_pos(pos, entry.push_dir)
			if peer and not vector.equals(peer, pos) then
				local pi = peer_info(peer)
				if pi then
					flow[#flow + 1] = { from = entry.id, to = pi.id,
						to_name = pi.name, role = "push", dir = entry.push_dir }
				end
			end
		end
	end

	return {
		center = { x = center.x, y = center.y, z = center.z },
		radius = radius,
		nodes = nodes,
		edges = edges,
		flow = flow,
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
