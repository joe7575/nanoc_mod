--[[

	NanoC
	=====

	Copyright (C) 2024-2026 Joachim Stolberg

	AGPL v3
	See LICENSE.txt for more information

	NanoC computer mod. The VM lives in the external Lua C module
	"nanoclib" (repo: nanoc_lib) and is loaded through the insecure
	environment. See doc/protocol.md in nanoc_lib for the contract.

]]--

nanoc = {}
nanoc.version = "0.1.0"

local P = minetest.get_modpath("nanoc")

-- The library is an "unsafe" package and must be trusted.
local IE = minetest.request_insecure_environment()
if not IE then
	minetest.log("warning", "[nanoc] Add 'nanoc' to 'secure.trusted_mods' in minetest.conf!")
	do return end
end

local ok, nanoclib = pcall(IE.require, "nanoclib")
if not ok then
	minetest.log("warning", "[nanoc] Install nanoclib: 'luarocks --lua-version 5.1 install nanoc'!")
	do return end
end

if nanoclib.protocol() ~= 1 then
	minetest.log("warning", "[nanoc] Incompatible nanoclib protocol "
		.. tostring(nanoclib.protocol()) .. " (expected 1).")
	do return end
end

-- An outdated nanoclib (e.g. after updating this mod only) would otherwise
-- fail with "attempt to call field 'xxx' (a nil value)" in a timer callback
-- and take the whole server down. Disable the mod instead.
local required_lib = {
	"clear_breakpoint", "clear_breakpoints", "create", "debug_attach",
	"debug_detach", "define_xfunc", "destroy", "get_backtrace", "get_line",
	"get_pc", "get_reason", "get_variables", "is_loaded", "load",
	"net_accept", "net_close", "net_listen", "net_recv", "net_send",
	"output", "output_clear", "pack_vm", "peek_num", "pop_arr", "pop_num",
	"pop_str", "push_key", "push_num", "push_str", "reset", "run",
	"set_breakpoint", "sleep_remaining", "step", "step_mode",
	"techage_read_signal", "techage_write_cmnd", "unpack_vm",
}
local missing_lib = {}
for _, name in ipairs(required_lib) do
	if type(nanoclib[name]) ~= "function" then
		missing_lib[#missing_lib + 1] = name
	end
end
if #missing_lib > 0 then
	minetest.log("error", "[nanoc] nanoclib " .. tostring(nanoclib.version())
		.. " is too old, missing: " .. table.concat(missing_lib, ", ")
		.. ". Rebuild it: cd nanoc_lib && sudo luarocks make --lua-version 5.1")
	do return end
end

nanoc.lib = nanoclib
nanoc.IE = IE
nanoc.protocol = nanoclib.protocol
nanoc.get_position_from_hash = nanoclib.get_position_from_hash

minetest.log("action", "[nanoc] loaded (nanoclib " .. tostring(nanoclib.version()) .. ")")

dofile(P .. "/src/tech/wrapper.lua")
dofile(P .. "/src/extfuncs.lua")
dofile(P .. "/src/controller.lua")
dofile(P .. "/src/termlib.lua")
dofile(P .. "/src/capabilities.lua")
dofile(P .. "/src/inspect.lua")
dofile(P .. "/src/bridge.lua")
