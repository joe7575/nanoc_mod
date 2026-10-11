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

nanoc.lib = nanoclib
nanoc.IE = IE
nanoc.protocol = nanoclib.protocol
nanoc.get_position_from_hash = nanoclib.get_position_from_hash

minetest.log("action", "[nanoc] loaded (nanoclib " .. tostring(nanoclib.version()) .. ")")

dofile(P .. "/src/tech/wrapper.lua")
dofile(P .. "/src/tech/io_module.lua")
dofile(P .. "/src/controller.lua")
dofile(P .. "/src/terminal.lua")
dofile(P .. "/src/capabilities.lua")
dofile(P .. "/src/inspect.lua")
dofile(P .. "/src/bridge.lua")
