--[[

	NanoC
	=====

	Copyright (C) 2024-2026 Joachim Stolberg

	AGPL v3
	See LICENSE.txt for more information

	Synchronous techage calls, implemented as Lua-dispatched external
	functions (like techage's basic_terminal): when the VM calls one, the run
	loop returns to Lua, the handler does the techage call immediately and
	pushes the result, then the VM resumes.

	ta_send_cmd(number, topic, payload)   -> status
	ta_req_data(number, topic, payload)   -> number
	ta_req_data_s(number, topic, payload) -> string
	hold()                                -> none
	release()                             -> none
	dclr(number)                          -> none
	dputs(number, row, text)              -> none
	time()                                -> number
	daytime()                             -> number
	daytime$(british)                     -> string

	payload is a string for the Beduino string-topic range (>= 64 for
	commands, >= 192 for requests), otherwise an int32[] array reference.

]]--

local M = minetest.get_meta
local lib = nanoc.lib

local Functions = {}

local function own_num(pos)
	return M(pos):get_string("node_number")
end

if minetest.global_exists("techage") then
	-- Payload is a string for topics >= str_from, otherwise an int32[] array.
	local function pop_payload(pos, topic, str_from)
		if topic >= str_from then
			return lib.pop_str(pos)
		end
		return lib.pop_arr(pos)
	end

	-- ta_send_cmd(number, topic, payload) -> status
	-- String payload for topic >= 64, int32[] otherwise.
	Functions[lib.define_xfunc("ta_send_cmd", 3, {1, 1, 4}, 1)] = function(pos)
		local payload = pop_payload(pos, lib.peek_num(pos, 2), 64)
		local topic = lib.pop_num(pos)
		local number = lib.pop_num(pos)
		local sts = techage.beduino_send_cmnd(own_num(pos), number, topic, payload)
		lib.push_num(pos, tonumber(sts) or 0)
	end

	-- ta_req_data(number, topic, payload) -> number
	-- String payload for topic >= 192 (e.g. chest item count), int32[] otherwise.
	Functions[lib.define_xfunc("ta_req_data", 3, {1, 1, 4}, 1)] = function(pos)
		local payload = pop_payload(pos, lib.peek_num(pos, 2), 192)
		local topic = lib.pop_num(pos)
		local number = lib.pop_num(pos)
		local sts, resp = techage.beduino_request_data(
			own_num(pos), number, topic, payload)
		if sts == 0 and type(resp) == "table" then
			lib.push_num(pos, resp[1] or 0)
		else
			lib.push_num(pos, -1)
		end
	end

	-- ta_req_data_s(number, topic, payload) -> string
	Functions[lib.define_xfunc("ta_req_data_s", 3, {1, 1, 4}, 2)] = function(pos)
		local payload = pop_payload(pos, lib.peek_num(pos, 2), 192)
		local topic = lib.pop_num(pos)
		local number = lib.pop_num(pos)
		local sts, resp = techage.beduino_request_data(
			own_num(pos), number, topic, payload)
		if sts == 0 and type(resp) == "string" then
			lib.push_str(pos, resp)
		else
			lib.push_str(pos, "")
		end
	end

	-- hold()/release(): collect commands and send them in one go, so that
	-- several machines start at the same time (like NanoBasic hold/release).
	Functions[lib.define_xfunc("hold", 0, {}, 0)] = function(pos)
		techage.cmnd_hold(own_num(pos))
	end

	Functions[lib.define_xfunc("release", 0, {}, 0)] = function(pos)
		techage.cmnd_release(own_num(pos))
	end

	-- dclr(number): clear the display (topic 17).
	Functions[lib.define_xfunc("dclr", 1, {1}, 0)] = function(pos)
		local number = lib.pop_num(pos)
		techage.beduino_send_cmnd(own_num(pos), number, 17, nil)
	end

	-- dputs(number, row, text): row 0 adds a line (topic 67); row > 0
	-- overwrites that row (topic 68, payload "<row> <text>").
	Functions[lib.define_xfunc("dputs", 3, {1, 1, 2}, 0)] = function(pos)
		local text = lib.pop_str(pos) or ""
		local row = lib.pop_num(pos) or 0
		local number = lib.pop_num(pos)
		if row > 0 then
			techage.beduino_send_cmnd(own_num(pos), number, 68, row .. " " .. text)
		else
			techage.beduino_send_cmnd(own_num(pos), number, 67, text)
		end
	end
end

-- time()/daytime(): game time (seconds since server start / minutes 0..1440).
Functions[lib.define_xfunc("time", 0, {}, 1)] = function(pos)
	lib.push_num(pos, minetest.get_gametime() or 0)
end

Functions[lib.define_xfunc("daytime", 0, {}, 1)] = function(pos)
	lib.push_num(pos, math.floor((minetest.get_timeofday() or 0) * 1440))
end

-- daytime$(british): clock as "HH:MM"; british != 0 -> 12h "hh:mm am/pm".
Functions[lib.define_xfunc("daytime$", 1, {1}, 2)] = function(pos)
	local british = lib.pop_num(pos) or 0
	local t = minetest.get_timeofday() or 0
	local h = math.floor(t * 24) % 24
	local m = math.floor(t * 1440) % 60
	if british ~= 0 then
		local h12 = h % 12
		if h12 == 0 then h12 = 12 end
		lib.push_str(pos, string.format("%02d:%02d %s", h12, m, h < 12 and "am" or "pm"))
	else
		lib.push_str(pos, string.format("%02d:%02d", h, m))
	end
end

-- log(text): emit a log line to debugger front ends (DAP Debug Console).
-- In-game it is a no-op for now (later: a local log store in the controller).
Functions[lib.define_xfunc("log", 1, {2}, 0)] = function(pos)
	local text = lib.pop_str(pos)
	if nanoc.add_log then
		nanoc.add_log(pos, text)
	end
	if nanoc.bridge and nanoc.bridge.log then
		nanoc.bridge.log(pos, text)
	end
end

-- Run the VM and dispatch Lua-backed external functions (NanoBasic pattern).
-- With a deadline (microseconds, from minetest.get_us_time()) the loop yields
-- back to the caller once the CPU budget is used up, so a techage-heavy loop
-- is spread over several ticks instead of blocking the server.
-- Returns (ret, yielded) where "yielded" is true if the CPU budget was hit.
function nanoc.run(pos, cycles, deadline_us)
	local ret, left = lib.run(pos, cycles)
	while ret and ret >= lib.XFUNC and ret < lib.HALTED and left > 1 do
		local fn = Functions[ret - lib.XFUNC]
		if not fn then
			break
		end
		fn(pos)
		if deadline_us and minetest.get_us_time() >= deadline_us then
			return ret, true   -- yield: the program resumes next tick
		end
		ret, left = lib.run(pos, left)
	end
	return ret, false
end

-- Debugger step (mode 0=into, 1=over, 2=out). Runs the VM one line and
-- dispatches Lua-backed external functions encountered on the way (like
-- nanoc.run), then flushes buffered output so the screens update while
-- stepping. Returns the raw status (may be an external function id).
function nanoc.step(pos, mode)
	if not lib.step_mode then
		lib.step(pos)
		if nanoc.flush_output then nanoc.flush_output(pos) end
		return nil
	end
	local ret = lib.step_mode(pos, mode, 100000)
	while ret and ret >= lib.XFUNC and ret < lib.HALTED do
		local fn = Functions[ret - lib.XFUNC]
		if not fn then
			break
		end
		fn(pos)
		ret = lib.step_mode(pos, mode, 100000)
	end
	if nanoc.flush_output then
		nanoc.flush_output(pos)
	end
	return ret
end
