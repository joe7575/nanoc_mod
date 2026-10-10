--[[

	NanoC
	=====

	Copyright (C) 2024-2026 Joachim Stolberg

	AGPL v3
	See LICENSE.txt for more information

	NanoC controller: one NanoC VM per node, driven by a node timer.

]]--

local M = minetest.get_meta
local H = minetest.hash_node_position
local P2S = function(pos) if pos then return minetest.pos_to_string(pos) end end
local S2P = function(s) return minetest.string_to_pos(s) end

local lib = nanoc.lib
local storage = minetest.get_mod_storage()

local RADIUS = 3
local CYCLE_TIME = 0.2          -- seconds per timer tick
local CYCLES_PER_TICK = 50000   -- VM instructions per tick
local MAX_LINES = 40            -- keep only the last N terminal lines

local Output = {}               -- [hash] = terminal output buffer
local Loaded = {}               -- [hash] = pos, all live VMs (for persistence)

local DEFAULT_PROGRAM = [[
// NanoC controller demo
int32 count = 0

while (1) {
    count = count + 1
    printf("NanoC ready, count=%d\n", count)
    sleep(1000)
}
]]

local function hash(pos) return H(pos) end

local function get_output(pos)
	return Output[hash(pos)] or ""
end

local function keep_last_lines(s, max_lines)
	local n = 0
	for _ in s:gmatch("\n") do n = n + 1 end
	if n <= max_lines then
		return s
	end
	local cut = n - max_lines
	local idx = 0
	while cut > 0 do
		local p = s:find("\n", idx + 1, true)
		if not p then break end
		idx = p
		cut = cut - 1
	end
	return s:sub(idx + 1)
end

local function append_output(pos, s)
	if s == nil or s == "" then return end
	local h = hash(pos)
	Output[h] = keep_last_lines((Output[h] or "") .. s, MAX_LINES)
end

local function clear_output(pos)
	Output[hash(pos)] = ""
end

-- public accessors (also used by the terminal node)
function nanoc.get_output(pos)
	return Output[hash(pos)] or ""
end

function nanoc.clear_output(pos)
	Output[hash(pos)] = ""
end

local function find_io_nodes(cpu_pos)
	local pos1 = { x = cpu_pos.x - RADIUS, y = cpu_pos.y - RADIUS, z = cpu_pos.z - RADIUS }
	local pos2 = { x = cpu_pos.x + RADIUS, y = cpu_pos.y + RADIUS, z = cpu_pos.z + RADIUS }
	return minetest.find_nodes_in_area(pos1, pos2, { "nanoc:io_module" })
end

local function call_io(cpu_pos, method)
	for _, pos in ipairs(find_io_nodes(cpu_pos)) do
		local ndef = minetest.registered_nodes[minetest.get_node(pos).name]
		if ndef and ndef[method] then
			ndef[method](pos, cpu_pos)
		end
	end
end

local function formspec(pos)
	local meta = M(pos)
	local prog = meta:get_string("program")
	local out = get_output(pos)
	local running = meta:get_int("running") == 1 and "running" or "stopped"
	return "size[12,10.5]" ..
		"label[0.3,0.1;NanoC Controller (" .. running .. ")]" ..
		"textarea[0.3,0.6;11.4,4.4;program;Program;" ..
			minetest.formspec_escape(prog) .. "]" ..
		"textarea[0.3,5.3;11.4,3.6;output;Output;" ..
			minetest.formspec_escape(out) .. "]" ..
		"button[0.3,9.2;2,0.8;save;Save+Compile]" ..
		"button[2.4,9.2;2,0.8;run;Run]" ..
		"button[4.5,9.2;2,0.8;stop;Stop]" ..
		"button[6.6,9.2;2,0.8;reset;Reset]" ..
		"button[8.7,9.2;2,0.8;clear;Clear]"
end

local function ensure_vm(pos)
	if lib.is_loaded(pos) then
		Loaded[hash(pos)] = pos
		return
	end
	lib.create(pos)
	local key = hash(pos)
	local img = storage:get_string(key)
	if img ~= "" and lib.unpack_vm(pos, img) then
		-- restored frozen state (code + variables + pc)
	else
		lib.load(pos, M(pos):get_string("program"))
	end
	Loaded[key] = pos
end

local function compile(pos)
	local meta = M(pos)
	local src = meta:get_string("program")
	if not lib.create(pos) then
		append_output(pos, "[error] could not create VM\n")
		return
	end
	lib.output_clear(pos)
	local ok = lib.load(pos, src)
	local compile_out = lib.output(pos)
	lib.output_clear(pos)
	if not ok then
		append_output(pos, "[compile error]\n" .. compile_out)
	else
		-- fresh program: drop any stored frozen state
		storage:set_string(hash(pos), "")
	end
	Loaded[hash(pos)] = pos
end

local function start(pos)
	M(pos):set_int("running", 1)
	call_io(pos, "on_start_io")
	minetest.get_node_timer(pos):start(CYCLE_TIME)
end

local function stop(pos)
	M(pos):set_int("running", 0)
	call_io(pos, "on_stop_io")
	minetest.get_node_timer(pos):stop()
end

minetest.register_node("nanoc:controller", {
	description = "NanoC Controller",
	tiles = { "default_glass.png" },
	drawtype = "nodebox",
	node_box = {
		type = "fixed",
		fixed = { { -0.5, -0.5, -0.4, 0.5, 0.5, 0.4 } },
	},
	paramtype = "light",
	paramtype2 = "facedir",
	groups = { choppy = 2, cracky = 2, crumbly = 2 },
	is_ground_content = false,

	on_construct = function(pos)
		local meta = M(pos)
		if not meta:contains("program") then
			meta:set_string("program", DEFAULT_PROGRAM)
		end
		ensure_vm(pos)
	end,

	after_place_node = function(pos, placer)
		local meta = M(pos)
		local own_num = nanoc.tech.add_node(pos, "nanoc:controller")
		meta:set_string("node_number", tostring(own_num or ""))
		meta:set_string("owner", placer and placer:get_player_name() or "")
		meta:set_string("formspec", formspec(pos))
	end,

	after_dig_node = function(pos)
		stop(pos)
		lib.destroy(pos)
		Loaded[hash(pos)] = nil
		storage:set_string(hash(pos), "")
		nanoc.tech.del_mem(pos)
		Output[hash(pos)] = nil
	end,

	on_rightclick = function(pos, node, clicker)
		M(pos):set_string("formspec", formspec(pos))
	end,

	on_receive_fields = function(pos, formname, fields, player)
		if minetest.is_protected(pos, player:get_player_name()) then
			return
		end
		local meta = M(pos)
		if fields.program then
			meta:set_string("program", fields.program)
		end
		if fields.save then
			compile(pos)
		elseif fields.run then
			compile(pos)
			start(pos)
		elseif fields.stop then
			stop(pos)
		elseif fields.reset then
			lib.reset(pos)
			clear_output(pos)
		elseif fields.clear then
			clear_output(pos)
		end
		meta:set_string("formspec", formspec(pos))
	end,

	on_timer = function(pos)
		if M(pos):get_int("running") ~= 1 then
			return false
		end
		local ret = lib.run(pos, CYCLES_PER_TICK)
		append_output(pos, lib.output(pos))
		lib.output_clear(pos)
		if nanoc.tech.update then
			nanoc.tech.update(pos)
		end
		if ret == lib.END or ret == lib.ERROR then
			lib.reset(pos)   -- restart the main program next tick
			minetest.get_node_timer(pos):start(CYCLE_TIME)
		elseif ret == lib.SLEEP then
			local ms = lib.sleep_remaining(pos)
			minetest.get_node_timer(pos):start(math.max(ms / 1000, 0.05))
		else
			minetest.get_node_timer(pos):start(CYCLE_TIME)
		end
		return true
	end,
})

-- Restore running controllers after a world reload
minetest.register_lbm({
	label = "NanoC: load controller",
	name = "nanoc:load_controller",
	nodenames = { "nanoc:controller" },
	run_at_every_load = true,
	action = function(pos)
		local meta = M(pos)
		ensure_vm(pos)
		if meta:get_int("running") == 1 then
			call_io(pos, "on_start_io")
			minetest.get_node_timer(pos):start(CYCLE_TIME)
		end
	end,
})

-- Freeze the VM state on shutdown (NanoBasic/beduino pattern)
minetest.register_on_shutdown(function()
	for key, pos in pairs(Loaded) do
		if lib.is_loaded(pos) then
			local img = lib.pack_vm(pos)
			if img then
				storage:set_string(key, img)
			end
		end
	end
end)
