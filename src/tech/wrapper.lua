--[[

	NanoC
	=====

	Copyright (C) 2024-2026 Joachim Stolberg

	AGPL v3
	See LICENSE.txt for more information

	Wrapper for Techage / TechPack (tubelib2) support.

	Adapted from the proven beduino / yauc2 pattern.

]]--

local MemStore = {}

local function stub() end

if minetest.global_exists("techage") then

	nanoc.tech = nanoc.tech or {}
	nanoc.tech.tubelib = false
	nanoc.tech.get_nvm = techage.get_nvm
	nanoc.tech.get_mem = techage.get_mem
	nanoc.tech.del_mem = techage.del_mem
	nanoc.tech.send_single = techage.send_single
	nanoc.tech.get_node_info = techage.get_node_info
	nanoc.tech.add_node = techage.add_node
	nanoc.tech.remove_node = techage.remove_node
	nanoc.tech.register_node = techage.register_node
	nanoc.tech.check_numbers = techage.check_numbers
	nanoc.tech.determine_node_number = techage.get_node_number
	nanoc.tech.get_node_name = function(dest_num)
		local info = techage.get_node_info(dest_num)
		if info then
			local ndef = minetest.registered_nodes[info.name]
			return ndef and ndef.description
		end
	end

elseif minetest.global_exists("tubelib") then

	nanoc.tech = nanoc.tech or {}
	nanoc.tech.tubelib = true
	nanoc.tech.get_nvm = tubelib2.get_mem
	nanoc.tech.get_mem = function(pos)
		local hash = minetest.hash_node_position(pos)
		if not MemStore[hash] then
			MemStore[hash] = {}
		end
		return MemStore[hash]
	end
	nanoc.tech.del_mem = tubelib2.del_mem
	nanoc.tech.send_single = function(src, number, topic, payload)
		if type(number) == "number" then
			number = string.format("%.04u", number)
		end
		return tubelib.send_request(number, topic, payload)
	end
	nanoc.tech.get_node_info = function(number)
		number = string.format("%.04u", tonumber(number) or 0)
		return tubelib.get_node_info(number)
	end
	nanoc.tech.add_node = tubelib.add_node
	nanoc.tech.remove_node = tubelib.remove_node
	nanoc.tech.register_node = function(names, node_definition)
		local add_names = {unpack(names, 2)}
		tubelib.register_node(names[1], add_names, node_definition)
	end
	nanoc.tech.check_numbers = tubelib.check_numbers
	nanoc.tech.determine_node_number = tubelib.get_node_number
	nanoc.tech.get_node_name = function(dest_num)
		local info = tubelib.get_node_info(dest_num)
		if info then
			local ndef = minetest.registered_nodes[info.name]
			return ndef and ndef.description
		end
	end

else
	minetest.log("warning", "[nanoc] Neither techage nor techpack/tubelib2 present; tech I/O disabled")
	nanoc.tech = nanoc.tech or {}
	nanoc.tech.tubelib = false
	nanoc.tech.get_nvm = function(pos) return minetest.get_meta(pos) end
	nanoc.tech.get_mem = function(pos) return {} end
	nanoc.tech.del_mem = stub
	nanoc.tech.send_single = stub
	nanoc.tech.get_node_info = function() end
	nanoc.tech.add_node = function() return 0 end
	nanoc.tech.remove_node = stub
	nanoc.tech.register_node = stub
	nanoc.tech.check_numbers = stub
	nanoc.tech.determine_node_number = function() return 0 end
	nanoc.tech.get_node_name = function() return nil end
end
