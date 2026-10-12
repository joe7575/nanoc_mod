--[[

	NanoC
	=====

	Copyright (C) 2024-2026 Joachim Stolberg

	AGPL v3
	See LICENSE.txt for more information

	TCP bridge for the external Python client (protocol v1).
	See nanoc_lib/doc/protocol.md.

	The sockets live in the nanoclib C module (non-blocking, polled from a
	globalstep), so there is no LuaSocket dependency and the server thread
	never blocks. Enabled with 'nanoc_bridge_enable = true'.

	Security: a client must present the controller's "external token"
	(shown in the controller formspec). Binds to 127.0.0.1 by default.

]]--

if not minetest.settings:get_bool("nanoc_bridge_enable", false) then
	minetest.log("action", "[nanoc] bridge disabled (set nanoc_bridge_enable = true)")
	return
end

local lib = nanoc.lib
if not lib.net_listen then
	minetest.log("warning", "[nanoc] bridge: nanoclib has no socket support (rebuild/update nanoclib)")
	return
end

local BIND = minetest.settings:get("nanoc_bridge_bind") or "127.0.0.1"
local PORT = tonumber(minetest.settings:get("nanoc_bridge_port")) or 41100
local POLL = tonumber(minetest.settings:get("nanoc_bridge_poll")) or 0.1
-- Abuse protection
local MAX_CLIENTS = tonumber(minetest.settings:get("nanoc_bridge_max_clients")) or 8
local HANDSHAKE_TIMEOUT = tonumber(minetest.settings:get("nanoc_bridge_handshake_timeout")) or 5
local IDLE_TIMEOUT = tonumber(minetest.settings:get("nanoc_bridge_idle_timeout")) or 0
local CMD_RATE = tonumber(minetest.settings:get("nanoc_bridge_cmd_rate")) or 100

local MAGIC0, MAGIC1 = 0x4E, 0x43
local VERSION = 1
local CH_DEBUG, CH_TERM, CH_CTRL, CH_LOG = 1, 2, 3, 4

local CMD = { ATTACH = 1, DETACH = 2, STATE = 3, BP_SET = 4, BP_CLR = 5,
	BP_CLR_ALL = 6, HALT = 7, CONTINUE = 8, STEP = 9, STEP_OVER = 10,
	STEP_OUT = 11, VAR_INFO = 12, VAR_WRITE = 13, ARR_READ = 14, BACKTRACE = 15,
	PROG_GET = 0x20, PROG_SET = 0x21, SCAN = 0x22, CATALOG = 0x23 }
local EVT = { HALTED = 0x80, ENDED = 0x81, DETACHED = 0x82 }
local STS = { OK = 0, END = 1, NOT_ATTACHED = 2, NO_SCRIPT = 3, PARAM = 4,
	NOT_HALTED = 5, FULL = 6, NO_CODE = 7, DENIED = 8, UNKNOWN = 9 }
local HSTAT = { OK = 0, BAD_PROTOCOL = 1, BAD_TOKEN = 2, BUSY = 3 }

-- ---- byte helpers (LuaJIT has no string.pack) ----

local function u16le(n)
	n = n % 65536
	return string.char(n % 256, math.floor(n / 256) % 256)
end

local function u32le(n)
	n = n % 4294967296
	return string.char(n % 256, math.floor(n / 256) % 256,
		math.floor(n / 65536) % 256, math.floor(n / 16777216) % 256)
end

local function r_u16le(s, i)
	local a, b = s:byte(i, i + 1)
	return a + b * 256
end

local function r_u32le(s, i)
	local a, b, c, d = s:byte(i, i + 3)
	return a + b * 256 + c * 65536 + d * 16777216
end

local function words(t)
	local out = {}
	for i = 1, #t do
		out[i] = u32le(t[i])
	end
	return table.concat(out)
end

local function r_words(s)
	local out = {}
	for i = 1, #s - 3, 4 do
		out[#out + 1] = r_u32le(s, i)
	end
	return out
end

local function frame(channel, payload, session)
	return string.char(MAGIC0, MAGIC1, VERSION, channel)
		.. u32le(session or 0) .. u16le(#payload) .. u16le(0) .. payload
end

-- ---- server ----

local server = lib.net_listen(BIND, PORT)
if not server then
	minetest.log("error", "[nanoc] bridge: cannot bind " .. BIND .. ":" .. PORT)
	return
end

local clients = {}   -- [socket id] = { id, buf, session, pos, authed }
nanoc.bridge = {}

local function send_frame(c, channel, payload)
	lib.net_send(c.id, frame(channel, payload, c.session))
end

-- focus arbitration: one debug owner per controller, everyone else is a viewer
local Owner = {}   -- [pos_key] = client

local function pos_key(pos)
	return pos.x .. "," .. pos.y .. "," .. pos.z
end

local function claim_focus(c)
	local k = pos_key(c.pos)
	if Owner[k] == nil or Owner[k] == c then
		Owner[k] = c
		c.is_owner = true
		return true
	end
	return false
end

local function release_focus(c)
	if c.is_owner and c.pos then
		local k = pos_key(c.pos)
		if Owner[k] == c then
			Owner[k] = nil
		end
	end
	c.is_owner = false
end

local function close_client(c)
	release_focus(c)
	lib.net_close(c.id)
	clients[c.id] = nil
end

local function read_available(c)
	local data, err = lib.net_recv(c.id)
	if data then
		c.buf = c.buf .. data
	elseif err == "closed" then
		return false
	end
	return true
end

-- ---- protocol handling ----

local function parse_frames(c)
	local frames = {}
	local pos = 1
	while #c.buf - pos + 1 >= 12 do
		local m0, m1, ver, ch = c.buf:byte(pos, pos + 3)
		if m0 ~= MAGIC0 or m1 ~= MAGIC1 or ver ~= VERSION then
			return nil   -- protocol error -> close
		end
		local session = r_u32le(c.buf, pos + 4)
		local len = r_u16le(c.buf, pos + 8)
		if #c.buf - pos + 1 < 12 + len then
			break
		end
		frames[#frames + 1] = {
			channel = ch,
			session = session,
			payload = c.buf:sub(pos + 12, pos + 12 + len - 1),
		}
		pos = pos + 12 + len
	end
	c.buf = c.buf:sub(pos)
	return frames
end

local function state_words(pos)
	local mode = nanoc.dbg_is_paused(pos) and 1 or 0
	return { mode, lib.get_reason(pos), lib.get_line(pos), lib.get_pc(pos) }
end

local function handle_debug(c, payload)
	local w = r_words(payload)
	local cmd = w[1]
	local resp

	-- focus arbitration: ATTACH claims control; other control commands need it
	if cmd == CMD.ATTACH then
		if not claim_focus(c) then
			send_frame(c, CH_DEBUG, words({ cmd, STS.DENIED }))
			return
		end
	elseif cmd ~= CMD.DETACH and cmd ~= CMD.PROG_GET and cmd ~= CMD.SCAN
			and cmd ~= CMD.CATALOG and not c.is_owner then
		send_frame(c, CH_DEBUG, words({ cmd, STS.DENIED }))
		return
	end

	if cmd == CMD.ATTACH then
		local allow = (w[2] or 1) ~= 0
		local user_lines = w[3] or 0
		lib.debug_attach(c.pos, allow and 1 or 0, user_lines)
		nanoc.dbg_pause(c.pos)
		resp = { cmd, STS.OK }
		for _, v in ipairs(state_words(c.pos)) do resp[#resp + 1] = v end
	elseif cmd == CMD.DETACH then
		lib.debug_detach(c.pos)
		nanoc.dbg_resume(c.pos)
		resp = { cmd, STS.OK }
	elseif cmd == CMD.STATE then
		resp = { cmd, STS.OK }
		for _, v in ipairs(state_words(c.pos)) do resp[#resp + 1] = v end
	elseif cmd == CMD.BP_SET then
		local l = lib.set_breakpoint(c.pos, w[2] or 0)
		resp = { cmd, (l and l >= 0) and STS.OK or STS.PARAM, l or 0 }
	elseif cmd == CMD.BP_CLR then
		lib.clear_breakpoint(c.pos, w[2] or 0)
		resp = { cmd, STS.OK }
	elseif cmd == CMD.BP_CLR_ALL then
		lib.clear_breakpoints(c.pos)
		resp = { cmd, STS.OK }
	elseif cmd == CMD.HALT then
		nanoc.dbg_pause(c.pos)
		resp = { cmd, STS.OK }
	elseif cmd == CMD.CONTINUE then
		if nanoc.start then nanoc.start(c.pos) end
		-- step over the current breakpoint trap, then run freely
		lib.step(c.pos)
		nanoc.dbg_resume(c.pos)
		minetest.get_node_timer(c.pos):start(0.05)
		resp = { cmd, STS.OK }
	elseif cmd == CMD.STEP or cmd == CMD.STEP_OVER or cmd == CMD.STEP_OUT then
		local mode = (cmd == CMD.STEP) and 0 or ((cmd == CMD.STEP_OVER) and 1 or 2)
		if nanoc.step then
			-- dispatches Lua-backed xfuncs (log, ta_cmd) and flushes output
			nanoc.step(c.pos, mode)
		elseif lib.step_mode then
			lib.step_mode(c.pos, mode, 100000)
		else
			lib.step(c.pos)
		end
		nanoc.dbg_pause(c.pos)
		resp = { cmd, STS.OK, 1, lib.get_reason(c.pos), lib.get_line(c.pos), lib.get_pc(c.pos) }
	elseif cmd == CMD.VAR_INFO then
		local scope = w[2] or 0
		local index = w[3] or 0
		local vars = lib.get_variables(c.pos, scope)
		if index >= 0 and index < #vars then
			local v = vars[index + 1]
			local name = v.name or ""
			local val = tostring(v.value)
			resp = { cmd, STS.OK, v.kind or 0, #name }
			for i = 1, #name do resp[#resp + 1] = name:byte(i) end
			resp[#resp + 1] = #val
			for i = 1, #val do resp[#resp + 1] = val:byte(i) end
		else
			resp = { cmd, STS.END }
		end
	elseif cmd == CMD.BACKTRACE then
		local bt = lib.get_backtrace(c.pos)
		resp = { cmd, STS.OK, #bt }
		for _, f in ipairs(bt) do
			resp[#resp + 1] = f.line or 0
			resp[#resp + 1] = f.pc or 0
		end
	elseif cmd == CMD.PROG_GET then
		local src = minetest.get_meta(c.pos):get_string("program")
		resp = { cmd, STS.OK, #src }
		for i = 1, #src do resp[#resp + 1] = src:byte(i) end
	elseif cmd == CMD.PROG_SET then
		local len = w[2] or 0
		local bytes = {}
		for i = 1, len do bytes[i] = string.char(w[2 + i] or 0) end
		local src = table.concat(bytes)
		minetest.get_meta(c.pos):set_string("program", src)
		lib.create(c.pos)
		lib.output_clear(c.pos)
		local ok = lib.load(c.pos, src)
		local msg = lib.output(c.pos)
		lib.output_clear(c.pos)
		if not ok then
			-- never let a failed compile run: reset the VM and stop it
			lib.reset(c.pos)
			if nanoc.stop then nanoc.stop(c.pos) end
		end
		lib.debug_attach(c.pos, 1, 0)
		nanoc.dbg_pause(c.pos)
		resp = { cmd, ok and STS.OK or STS.PARAM, #msg }
		for i = 1, #msg do resp[#resp + 1] = msg:byte(i) end
	elseif cmd == CMD.SCAN then
		local radius = w[2] or 8
		local snap = nanoc.inspect and nanoc.inspect(c.pos, radius)
		local json = snap and minetest.write_json(snap) or "{}"
		resp = { cmd, STS.OK, #json }
		for i = 1, #json do resp[#resp + 1] = json:byte(i) end
	elseif cmd == CMD.CATALOG then
		local cat = nanoc.catalog and nanoc.catalog() or {}
		local json = minetest.write_json(cat)
		resp = { cmd, STS.OK, #json }
		for i = 1, #json do resp[#resp + 1] = json:byte(i) end
	else
		resp = { cmd, STS.UNKNOWN }
	end

	send_frame(c, CH_DEBUG, words(resp))

	-- HALT pauses without running to a breakpoint; report it as an event too
	if cmd == CMD.HALT then
		send_frame(c, CH_DEBUG, words({ EVT.HALTED, 3, lib.get_line(c.pos), lib.get_pc(c.pos) }))
	end

	if cmd == CMD.DETACH then
		release_focus(c)
	end
end

local function do_handshake(c, payload)
	local proto = r_u32le(payload, 1)
	local token_len = payload:byte(5) or 0
	local token = payload:sub(6, 5 + token_len)

	if proto ~= VERSION then
		send_frame(c, CH_CTRL, string.char(HSTAT.BAD_PROTOCOL) .. u32le(VERSION))
		return false
	end
	local pos = nanoc.find_by_token(token)
	if not pos then
		send_frame(c, CH_CTRL, string.char(HSTAT.BAD_TOKEN) .. u32le(VERSION))
		return false
	end
	c.pos = pos
	c.authed = true
	send_frame(c, CH_CTRL, string.char(HSTAT.OK) .. u32le(VERSION))
	local out = nanoc.get_output(pos)
	if out and out ~= "" then
		send_frame(c, CH_TERM, out)
	end
	return true
end

-- ---- hooks from the controller ----

local function same_pos(a, b)
	return a and b and a.x == b.x and a.y == b.y and a.z == b.z
end

function nanoc.bridge.on_output(pos, text)
	for _, c in pairs(clients) do
		if c.authed and same_pos(c.pos, pos) then
			send_frame(c, CH_TERM, text)
		end
	end
end

-- Program log messages (NanoC built-in log()): shown in debugger front ends
-- (e.g. the VS Code Debug Console), not in the terminal screen.
function nanoc.bridge.log(pos, text)
	if not text or text == "" then
		return
	end
	for _, c in pairs(clients) do
		if c.authed and same_pos(c.pos, pos) then
			send_frame(c, CH_LOG, text)
		end
	end
end

function nanoc.bridge.on_halt(pos, reason, line, pc)
	for _, c in pairs(clients) do
		if c.authed and same_pos(c.pos, pos) then
			send_frame(c, CH_DEBUG, words({ EVT.HALTED, reason or 0, line or 0, pc or 0 }))
		end
	end
end

-- ---- polling ----

local acc = 0
local function now() return minetest.get_gametime() end

minetest.register_globalstep(function(dtime)
	acc = acc + dtime
	if acc < POLL then
		return
	end
	acc = 0
	local t = now()

	while true do
		local id = lib.net_accept(server)
		if not id then break end
		local count = 0
		for _ in pairs(clients) do count = count + 1 end
		if count >= MAX_CLIENTS then
			lib.net_close(id)          -- refuse: too many clients
		else
			clients[id] = { id = id, buf = "", session = 0, pos = nil, authed = false,
				connected_at = t, last_activity = t, cmd_window = t, cmd_count = 0 }
		end
	end

	local dead = {}
	for id, c in pairs(clients) do
		local alive = true
		if not c.authed and (t - c.connected_at) > HANDSHAKE_TIMEOUT then
			alive = false               -- did not authenticate in time
		end
		if alive then
			alive = read_available(c)
		end
		if alive and IDLE_TIMEOUT > 0 and c.authed and (t - c.last_activity) > IDLE_TIMEOUT then
			alive = false
		end
		if alive then
			local frames = parse_frames(c)
			if not frames then
				alive = false
			else
				for _, f in ipairs(frames) do
					c.session = f.session
					c.last_activity = t
					if not c.authed then
						if f.channel ~= CH_CTRL or not do_handshake(c, f.payload) then
							alive = false
							break
						end
					elseif f.channel == CH_DEBUG then
						if (t - c.cmd_window) > 1 then
							c.cmd_window = t
							c.cmd_count = 0
						end
						c.cmd_count = c.cmd_count + 1
						if c.cmd_count > CMD_RATE then
							alive = false   -- command flood
							break
						end
						handle_debug(c, f.payload)
					elseif f.channel == CH_TERM then
						-- Terminal input is not a debug control operation, so any
						-- authenticated client may type (like the in-game
						-- terminal). Rate-limited like the debug channel.
						if (t - c.cmd_window) > 1 then
							c.cmd_window = t
							c.cmd_count = 0
						end
						c.cmd_count = c.cmd_count + 1
						if c.cmd_count > CMD_RATE then
							alive = false   -- input flood
							break
						end
						if c.pos then
							lib.push_key(c.pos, f.payload)
						end
					end
				end
			end
		end
		if not alive then
			dead[#dead + 1] = c
		end
	end
	for _, c in ipairs(dead) do
		close_client(c)
	end
end)

minetest.register_on_shutdown(function()
	for _, c in pairs(clients) do
		lib.net_close(c.id)
	end
	if server then
		lib.net_close(server)
	end
end)

minetest.log("action", "[nanoc] bridge listening on " .. BIND .. ":" .. PORT)
