--[[

	NanoC
	=====

	Copyright (C) 2024-2026 Joachim Stolberg

	AGPL v3
	See LICENSE.txt for more information

	Termlib integration: the termlib terminal is the NanoC controller's
	display + keyboard.

	- output: the controller's text is written to the connected terminal
	- input:  a command typed on the terminal goes into the VM input buffer
	          (read with key() in the program)

	Connect as usual: wield the terminal, left-click the controller, place the
	terminal, open it and enter @connect.

]]--

if not minetest.global_exists("termlib") or not termlib.term then
	return
end

local M = minetest.get_meta
local term = termlib.term

-- Input: a command typed on the terminal -> the NanoC VM input buffer.
-- termlib's backends (techage/beduino/...) override send_to_cpu on the
-- *instance* (`term.send_to_cpu`), so we must wrap that method too, otherwise
-- our class-level override would be shadowed and F-keys would fall through to
-- the backend's default (which returns false).
local orig_send_to_cpu = term.send_to_cpu
term.send_to_cpu = function(self, pos, mem, cpu_pos, node, command)
	if node and node.name == "nanoc:controller" then
		nanoc.lib.push_key(cpu_pos, (command or "") .. "\n")
		return true
	end
	return orig_send_to_cpu(self, pos, mem, cpu_pos, node, command)
end

-- Output: controller text -> the connected terminal (called from the controller).
function nanoc.termlib_send(cpu_pos, text)
	local term_pos = minetest.string_to_pos(M(cpu_pos):get_string("trm_term_pos"))
	if not term_pos then
		return
	end
	local mem = termlib.get_mem(term_pos)
	if not mem.trm_connected then
		return
	end
	if term:put_string(term_pos, mem, text) then
		M(term_pos):set_string("formspec", term:formspec(term_pos))
	end
end
