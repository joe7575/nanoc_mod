--[[

	NanoC
	=====

	Copyright (C) 2024-2026 Joachim Stolberg

	AGPL v3
	See LICENSE.txt for more information

	Synchronous techage calls, implemented as Lua-dispatched external
	functions (like techage's basic_terminal): when the VM calls one, the run
	loop returns to Lua, the handler does techage.beduino_request_data()
	immediately and pushes the result, then the VM resumes.

	ta_cmd(number, topic, a, b, c)   -> number   (request, numeric result)
	ta_cmd_s(number, topic, a, b, c) -> string   (request, string result)

]]--

local M = minetest.get_meta
local lib = nanoc.lib

local Functions = {}

local function own_num(pos)
	return M(pos):get_string("node_number")
end

local function pop5(pos)
	local c = lib.pop_num(pos)
	local b = lib.pop_num(pos)
	local a = lib.pop_num(pos)
	local topic = lib.pop_num(pos)
	local number = lib.pop_num(pos)
	return number, topic, a, b, c
end

if minetest.global_exists("techage") then
	Functions[lib.define_xfunc("ta_cmd", 5, {1, 1, 1, 1, 1}, 1)] = function(pos)
		local number, topic, a, b, c = pop5(pos)
		local sts, resp = techage.beduino_request_data(
			own_num(pos), number, topic, {a, b, c})
		if sts == 0 and type(resp) == "table" then
			lib.push_num(pos, resp[1] or 0)
		else
			lib.push_num(pos, -1)
		end
	end

	Functions[lib.define_xfunc("ta_cmd_s", 5, {1, 1, 1, 1, 1}, 2)] = function(pos)
		local number, topic, a, b, c = pop5(pos)
		local sts, resp = techage.beduino_request_data(
			own_num(pos), number, topic, {a, b, c})
		if sts == 0 and type(resp) == "string" then
			lib.push_str(pos, resp)
		else
			lib.push_str(pos, "")
		end
	end
end

-- log(text): emit a log line to debugger front ends (DAP Debug Console).
-- In-game it is a no-op for now (later: a local log store in the controller).
Functions[lib.define_xfunc("log", 1, {2}, 0)] = function(pos)
	local text = lib.pop_str(pos)
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
