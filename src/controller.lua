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
local MAX_LINES = 40            -- keep only the last N terminal lines

-- Adaptive per-controller CPU budget (server-owner tunable, see settingtypes).
-- The controller measures how long a tick really takes and grows/shrinks the
-- VM instruction budget to stay near the time target. More players (and a
-- loaded server, via the measured runtime) reduce the budget; an idle server
-- gets the full budget. There is no hard limit and no penalty for the owner -
-- just a time slice (the program simply resumes next tick).
local CPU_TICK_MS    = tonumber(minetest.settings:get("nanoc_cpu_tick_ms")) or 8.0
local CPU_TICK_MIN_MS = tonumber(minetest.settings:get("nanoc_cpu_tick_min_ms")) or 1.0
local CPU_PLAYER_SCALE = minetest.settings:get_bool("nanoc_cpu_player_scale", true)
local VM_CYCLES_START = tonumber(minetest.settings:get("nanoc_vm_cycles_start")) or 20000
local VM_CYCLES_MIN   = tonumber(minetest.settings:get("nanoc_vm_cycles_min")) or 500
local VM_CYCLES_MAX   = tonumber(minetest.settings:get("nanoc_vm_cycles_max")) or 100000

local Output = {}               -- [hash] = terminal output buffer
local Cpu = {}                  -- [hash] = { cycles = ..., last_log_us = ... }
local Loaded = {}               -- [hash] = pos, all live VMs (for persistence)
nanoc.controllers = {}          -- [hash] = pos, all controllers (for the bridge)
nanoc.dbg = {}                  -- [hash] = true, paused by an external debugger

math.randomseed(os.time())

local function random_token()
	local t = {}
	for i = 1, 16 do
		t[i] = string.format("%02x", math.random(0, 255))
	end
	return table.concat(t)
end

function nanoc.token(pos)
	local meta = M(pos)
	local tok = meta:get_string("token")
	if tok == "" then
		tok = random_token()
		meta:set_string("token", tok)
	end
	return tok
end

function nanoc.find_by_token(token)
	if not token or token == "" then
		return nil
	end
	for _, pos in pairs(nanoc.controllers) do
		if M(pos):get_string("token") == token then
			return pos
		end
	end
end

function nanoc.dbg_pause(pos) nanoc.dbg[H(pos)] = true end
function nanoc.dbg_resume(pos) nanoc.dbg[H(pos)] = nil end
function nanoc.dbg_is_paused(pos) return nanoc.dbg[H(pos)] == true end

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

-- Per-controller adaptive CPU state.
local function cpu_state(pos)
	local k = hash(pos)
	local st = Cpu[k]
	if not st then
		st = { cycles = VM_CYCLES_START, last_log_us = nil }
		Cpu[k] = st
	end
	return st
end

-- Compute the CPU time budget (microseconds) for this tick. The base target is
-- scaled down by the number of players; the VM's own measured runtime (AIMD in
-- on_timer) adapts the instruction budget to real server load.
local function cpu_budget_us()
	local budget_ms = CPU_TICK_MS
	if CPU_PLAYER_SCALE then
		local players = #minetest.get_connected_players()
		if players > 1 then
			budget_ms = budget_ms / players
		end
	end
	if budget_ms < CPU_TICK_MIN_MS then
		budget_ms = CPU_TICK_MIN_MS
	end
	return math.floor(budget_ms * 1000)
end

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
	if nanoc.bridge and nanoc.bridge.on_output then
		nanoc.bridge.on_output(pos, s)
	end
	if nanoc.termlib_send then
		nanoc.termlib_send(pos, s)
	end
end

local function clear_output(pos)
	Output[hash(pos)] = ""
end

-- public accessors (also used by the terminal node)
function nanoc.get_output(pos)
	return Output[hash(pos)] or ""
end

-- Flush buffered VM output to the terminal/bridge. Used by the debugger step
-- path (which runs the VM outside on_timer) so stepping updates the screens.
function nanoc.flush_output(pos)
	append_output(pos, lib.output(pos))
	lib.output_clear(pos)
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
	return "size[12,11.2]" ..
		"label[0.3,0.1;NanoC Controller (" .. running .. ")]" ..
		"textarea[0.3,0.6;11.4,4.4;program;Program;" ..
			minetest.formspec_escape(prog) .. "]" ..
		"textarea[0.3,5.3;11.4,3.6;output;Output;" ..
			minetest.formspec_escape(out) .. "]" ..
		"button[0.3,9.2;2,0.8;save;Save+Compile]" ..
		"button[2.4,9.2;2,0.8;run;Run]" ..
		"button[4.5,9.2;2,0.8;stop;Stop]" ..
		"button[6.6,9.2;2,0.8;reset;Reset]" ..
		"button[8.7,9.2;2,0.8;clear;Clear]" ..
		"button[10.8,9.2;1,0.8;token;Token]" ..
		"label[0.3,10.35;Techage #" .. meta:get_string("node_number") ..
			"   Token: only the owner (press 'Token')]"
end

local function ensure_vm(pos)
	nanoc.controllers[hash(pos)] = pos
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

local stop   -- forward declaration (used by compile() below)

local function compile(pos)
	local meta = M(pos)
	local src = meta:get_string("program")
	if not lib.create(pos) then
		append_output(pos, "[error] could not create VM\n")
		return false
	end
	lib.output_clear(pos)
	local ok = lib.load(pos, src)
	local compile_out = lib.output(pos)
	lib.output_clear(pos)
	if not ok then
		append_output(pos, "[compile error]\n" .. compile_out)
		-- A failed compile leaves no valid code; make sure it can never run.
		lib.reset(pos)
		stop(pos)
	else
		-- fresh program: drop any stored frozen state
		storage:set_string(hash(pos), "")
	end
	Loaded[hash(pos)] = pos
	return ok
end

local function start(pos)
	M(pos):set_int("running", 1)
	call_io(pos, "on_start_io")
	minetest.get_node_timer(pos):start(CYCLE_TIME)
end

stop = function(pos)
	M(pos):set_int("running", 0)
	call_io(pos, "on_stop_io")
	minetest.get_node_timer(pos):stop()
end

-- public (used by the external bridge)
function nanoc.start(pos) start(pos) end
function nanoc.stop(pos) stop(pos) end

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
		nanoc.controllers[hash(pos)] = nil
		nanoc.dbg[hash(pos)] = nil
		storage:set_string(hash(pos), "")
		nanoc.tech.del_mem(pos)
		Output[hash(pos)] = nil
		Cpu[hash(pos)] = nil
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
			if compile(pos) then
				start(pos)
			end
		elseif fields.stop then
			stop(pos)
		elseif fields.reset then
			lib.reset(pos)
			clear_output(pos)
		elseif fields.clear then
			clear_output(pos)
		elseif fields.token then
			local owner = meta:get_string("owner")
			local pname = player and player:get_player_name()
			if pname and (pname == owner or
					minetest.check_player_privs(pname, { protection_bypass = true })) then
				local tok = random_token()
				meta:set_string("token", tok)
				-- fallback for clients without text-field copy: log it
				minetest.log("action", "[nanoc] external token for controller "
					.. P2S(pos) .. " (owner " .. owner .. "): " .. tok)
				-- show it in a selectable text field (chat has no copy on Linux)
				minetest.show_formspec(pname, "nanoc:token@" .. P2S(pos),
					"size[9,2.4]" ..
					"label[0.3,0.2;External token (select the text, then Ctrl+C):]" ..
					"field[0.3,0.8;8.4,0.9;token;;" .. tok .. "]" ..
					"label[0.3,1.8;Share it only with people you trust.]")
				minetest.chat_send_player(pname,
					"[nanoc] New external token created (see the window).")
			elseif pname then
				minetest.chat_send_player(pname, "[nanoc] Only the owner can create a token.")
			end
		end
		meta:set_string("formspec", formspec(pos))
	end,

	on_timer = function(pos)
		if M(pos):get_int("running") ~= 1 then
			return false
		end
		local st = cpu_state(pos)
		if nanoc.dbg_is_paused(pos) then
			return true   -- suspended by an external debugger
		end
		local now_us = minetest.get_us_time()
		local budget_us = cpu_budget_us()
		local deadline_us = now_us + budget_us
		local ret, yielded = nanoc.run(pos, st.cycles, deadline_us)
		append_output(pos, lib.output(pos))
		lib.output_clear(pos)
		if nanoc.tech.update then
			nanoc.tech.update(pos)
		end
		-- Adapt the instruction budget (grow slowly, shrink fast) so a tick
		-- stays near the time target. Yielding early is not a failure, it just
		-- continues next tick.
		local used_us = minetest.get_us_time() - now_us
		if ret == lib.SLEEP then
			st.cycles = VM_CYCLES_START     -- fresh start after a pause
		elseif used_us < budget_us * 0.5 then
			st.cycles = math.min(math.floor(st.cycles * 1.5) + 500, VM_CYCLES_MAX)
		elseif used_us > budget_us then
			st.cycles = math.max(math.floor(st.cycles * 0.6), VM_CYCLES_MIN)
		end
		-- Info to the debug terminal when the CPU budget throttles the program
		-- (throttled to at most one message per second per controller).
		if yielded and nanoc.bridge and nanoc.bridge.log then
			if not st.last_log_us or (now_us - st.last_log_us) > 1000000 then
				st.last_log_us = now_us
				nanoc.bridge.log(pos, string.format(
					"CPU budget exceeded (budget %d us, instructions %d) - deferred to next tick",
					budget_us, st.cycles))
			end
		end
		if ret == 256 then   -- NB_HALTED: breakpoint reached
			nanoc.dbg_pause(pos)
			if nanoc.bridge and nanoc.bridge.on_halt then
				nanoc.bridge.on_halt(pos, lib.get_reason(pos), lib.get_line(pos), lib.get_pc(pos))
			end
			minetest.get_node_timer(pos):start(CYCLE_TIME)
		elseif ret == lib.END or ret == lib.ERROR then
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

-- Outgoing on/off signals (ta_signal), forwarded directly to the target node.
-- (Commands/requests are synchronous Lua xfuncs: ta_send_cmd / ta_req_data.)
-- NanoC has 32-bit vars, so the program addresses techage numbers directly;
-- no io_module/port indirection needed.
function nanoc.tech.update(cpu_pos)
	if not minetest.global_exists("techage") then return end
	local src = M(cpu_pos):get_string("node_number")
	if src == "" then return end
	local number, val
	while true do
		number, val = lib.techage_read_signal(cpu_pos)
		if not number then break end
		techage.send_single(src, number, val == 1 and "on" or "off")
	end
end

-- Incoming: deliver a command from another techage node to the VM.
local function push_incoming(pos, src, topic, payload)
	lib.techage_write_cmnd(pos, tonumber(src) or 0, tonumber(topic) or 0,
		type(payload) == "table" and payload or { tonumber(payload) or 0 })
end

-- Techage interface: the controller can be queried/controlled like a machine.
-- topic 1 = run/stop is reserved; other send topics go to the program.
if nanoc.tech and nanoc.tech.register_node then
	nanoc.tech.register_node({ "nanoc:controller" }, {
		on_beduino_receive_cmnd = function(pos, src, topic, payload)
			if topic == 1 then
				if (payload and payload[1] or 0) ~= 0 then
					ensure_vm(pos)
					start(pos)
				else
					stop(pos)
				end
				return 0
			end
			push_incoming(pos, src, topic, payload)
			return 0
		end,
		on_recv_message = function(pos, src, topic, payload)
			local t = tonumber(topic) or (topic == "on" and 1) or (topic == "off" and 0)
			if t then
				push_incoming(pos, src, t, payload)
			end
		end,
		on_beduino_request_data = function(pos, src, topic, payload)
			if topic == 128 then
				return 0, "nanoc:controller"
			elseif topic == 129 then
				return 0, { M(pos):get_int("running") == 1 and 1 or 6 }
			end
			return 2, ""
		end,
	})
end
