--[[

	NanoC
	=====

	Copyright (C) 2024-2026 Joachim Stolberg

	AGPL v3
	See LICENSE.txt for more information

	I/O module: bridges NanoC techage ports to techage/tubelib2 node numbers.

	Outgoing (VM -> mod): the NanoC program calls ta_send()/ta_signal();
	nanoc.tech.update(cpu_pos) forwards them via the techage Beduino API.

	Incoming (mod -> VM): techage messages are pushed into the VM queue,
	where the program reads them with ta_recv()/ta_recv_sig().

]]--

local M = minetest.get_meta
local H = minetest.hash_node_position
local S2T = function(s) return minetest.deserialize(s) or {} end
local T2S = function(t) return minetest.serialize(t) or "return {}" end

local tech = nanoc.tech

-- PortMap[hash(cpu_pos)][port] = techage number
local PortMap = {}

local function add_port(cpu_pos, port, number)
	local h = H(cpu_pos)
	PortMap[h] = PortMap[h] or {}
	PortMap[h][port] = number
end

local function get_number(cpu_pos, port)
	local h = H(cpu_pos)
	return PortMap[h] and PortMap[h][port]
end

local function get_port(cpu_pos, number)
	local h = H(cpu_pos)
	local map = PortMap[h]
	if map then
		for p, n in pairs(map) do
			if n == number then
				return p
			end
		end
	end
end

local function build_portmap(pos, cpu_pos)
	local meta = M(pos)
	local base = meta:get_int("port") or 0
	local numbers = S2T(meta:get_string("numbers"))
	for i = 0, 7 do
		local n = tonumber(numbers[i])
		if n and n > 0 then
			add_port(cpu_pos, base + i, n)
		end
	end
end

local function formspec(pos)
	local meta = M(pos)
	local numbers = S2T(meta:get_string("numbers"))
	local base = meta:get_int("port") or 0
	local lines = { "size[8,8.5]", "label[0.3,0.2;Port  Techage number]" }
	for i = 0, 7 do
		local y = i * 0.8 + 0.7
		lines[#lines + 1] = "label[0.4," .. y .. ";#" .. (base + i) .. "]"
		lines[#lines + 1] = "field[1.6," .. (y - 0.3) .. ";4,0.7;num" .. i ..
			";;" .. tostring(numbers[i] or "") .. "]"
	end
	lines[#lines + 1] = "button[2.5,7.5;3,0.8;save;Save]"
	return table.concat(lines)
end

local function store_settings(pos, fields)
	local numbers = {}
	for i = 0, 7 do
		numbers[i] = fields["num" .. i] or ""
	end
	local meta = M(pos)
	meta:set_string("numbers", T2S(numbers))
	local cpu_pos = minetest.string_to_pos(meta:get_string("cpu_pos"))
	if cpu_pos then
		build_portmap(pos, cpu_pos)
	end
end

minetest.register_node("nanoc:io_module", {
	description = "NanoC I/O Module",
	drawtype = "nodebox",
	tiles = { "default_steel_block.png" },
	node_box = {
		type = "fixed",
		fixed = { { -0.5, -0.5, -0.4, 0.5, 0.5, 0.4 } },
	},
	paramtype = "light",
	paramtype2 = "facedir",
	groups = { choppy = 2, cracky = 2, crumbly = 2 },
	is_ground_content = false,

	after_place_node = function(pos, placer)
		local meta = M(pos)
		local own_num = tech.add_node(pos, "nanoc:io_module")
		meta:set_string("node_number", tostring(own_num or ""))
		meta:set_string("owner", placer and placer:get_player_name() or "")
		meta:set_string("formspec", formspec(pos))
	end,

	after_dig_node = function(pos)
		tech.del_mem(pos)
	end,

	on_receive_fields = function(pos, formname, fields, player)
		if minetest.is_protected(pos, player:get_player_name()) then
			return
		end
		if fields.save then
			store_settings(pos, fields)
			M(pos):set_string("formspec", formspec(pos))
		end
	end,

	on_rightclick = function(pos, node, clicker)
		M(pos):set_string("formspec", formspec(pos))
	end,

	-- called by the controller on start/stop
	on_start_io = function(pos, cpu_pos)
		M(pos):set_string("cpu_pos", minetest.pos_to_string(cpu_pos))
		build_portmap(pos, cpu_pos)
	end,

	on_stop_io = function(pos)
		local cpu_pos = minetest.string_to_pos(M(pos):get_string("cpu_pos"))
		if cpu_pos then
			PortMap[H(cpu_pos)] = nil
		end
	end,
})

------------------------------------------------------------------------------
-- Incoming techage messages -> VM queue
------------------------------------------------------------------------------

local function deliver_input(pos, src_num, topic, payload)
	if tech.tubelib then
		pos, src_num, topic = pos, topic, src_num
	end
	local mem = tech.get_mem(pos)
	local cpu_pos = mem and mem.cpu_pos
		or minetest.string_to_pos(M(pos):get_string("cpu_pos"))
	if not cpu_pos then
		return
	end
	local port = get_port(cpu_pos, tonumber(src_num))
	if not port then
		return
	end
	local pl = {}
	if type(payload) == "table" then
		for i = 1, #payload do pl[i] = payload[i] end
	else
		pl[1] = tonumber(payload) or 0
	end
	nanoc.lib.techage_write_cmnd(cpu_pos, port, tonumber(topic) or 0, pl)
end

if tech.register_node then
	tech.register_node({ "nanoc:io_module" }, {
		on_recv_message = function(pos, src_num, topic, payload)
			if topic == "clear" then return end
			local val = tonumber(topic) or (topic == "on" and 1 or 0)
			deliver_input(pos, src_num, 1, { val })
		end,
		on_beduino_receive_cmnd = function(pos, src_num, topic, payload)
			if topic == 1 then
				deliver_input(pos, src_num, topic, payload)
				return 0
			end
			return 2
		end,
	})
end

------------------------------------------------------------------------------
-- Outgoing: drain the VM queue and forward to techage
------------------------------------------------------------------------------

function nanoc.tech.update(cpu_pos)
	if not cpu_pos then
		return
	end
	local src = M(cpu_pos):get_string("node_number")
	local lib = nanoc.lib

	while true do
		local port, topic, payload, _type = lib.techage_read_cmnd(cpu_pos)
		if not port then
			break
		end
		local number = get_number(cpu_pos, port)
		if number then
			if topic < 128 then
				techage.beduino_send_cmnd(src, number, topic, payload)
			else
				local state, resp = techage.beduino_request_data(src, number, topic, payload)
				if state == 0 and resp then
					lib.techage_write_cmnd(cpu_pos, port, topic, resp)
				end
			end
		end
	end

	while true do
		local port, val = lib.techage_read_signal(cpu_pos)
		if not port then
			break
		end
		local number = get_number(cpu_pos, port)
		if number then
			tech.send_single(src, number, val == 1 and "on" or "off")
		end
	end
end
