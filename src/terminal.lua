--[[

	NanoC
	=====

	Copyright (C) 2024-2026 Joachim Stolberg

	AGPL v3
	See LICENSE.txt for more information

	NanoC terminal: a live-updating display for a controller's output.

	Node formspecs are only fetched when opened, so a node-metadata formspec
	cannot update itself. This node therefore uses minetest.show_formspec()
	and re-shows the (read-only) form while a player is watching it.

]]--

local M = minetest.get_meta
local P2S = minetest.pos_to_string
local S2P = minetest.string_to_pos

local RADIUS = 5
local REFRESH = 0.25          -- seconds between refreshes

local Viewers = {}            -- [formname] = { player = name, pos = pos, last = str }

local function find_controller(pos)
	local p1 = { x = pos.x - RADIUS, y = pos.y - RADIUS, z = pos.z - RADIUS }
	local p2 = { x = pos.x + RADIUS, y = pos.y + RADIUS, z = pos.z + RADIUS }
	local list = minetest.find_nodes_in_area(p1, p2, { "nanoc:controller" })
	return list[1]
end

local function linked_controller(pos)
	local s = M(pos):get_string("cpu_pos")
	local cpu = S2P(s)
	if cpu and minetest.get_node_or_nil(cpu) then
		return cpu
	end
	return find_controller(pos)
end

local function formspec(pos)
	local cpu = linked_controller(pos)
	local out
	if cpu then
		out = nanoc.get_output(cpu)
	else
		out = "(no NanoC controller nearby)"
	end
	return "size[10,8]" ..
		"label[0.3,0.1;NanoC Terminal]" ..
		"textarea[0.3,0.7;9.4,6.9;;Output;" ..
			minetest.formspec_escape(out) .. "]"
end

local function formname(pos)
	return "nanoc:terminal@" .. P2S(pos)
end

local function show(pos, player)
	local fn = formname(pos)
	minetest.show_formspec(player:get_player_name(), fn, formspec(pos))
	Viewers[fn] = { player = player:get_player_name(), pos = pos, last = nil }
end

minetest.register_node("nanoc:terminal", {
	description = "NanoC Terminal",
	tiles = { "default_glass.png" },
	drawtype = "nodebox",
	node_box = {
		type = "fixed",
		fixed = { { -0.5, -0.25, 0.35, 0.5, 0.35, 0.5 } },
	},
	paramtype = "light",
	paramtype2 = "facedir",
	groups = { choppy = 2, cracky = 2, crumbly = 2 },
	is_ground_content = false,

	after_place_node = function(pos, placer)
		local cpu = find_controller(pos)
		if cpu then
			M(pos):set_string("cpu_pos", P2S(cpu))
		end
	end,

	on_rightclick = function(pos, node, clicker)
		show(pos, clicker)
	end,
})

minetest.register_on_player_receive_fields(function(player, fn, fields)
	if Viewers[fn] then
		if fields.quit or fields.key_enter then
			Viewers[fn] = nil
		end
	end
end)

minetest.register_on_leaveplayer(function(player)
	local name = player:get_player_name()
	for fn, v in pairs(Viewers) do
		if v.player == name then
			Viewers[fn] = nil
		end
	end
end)

local acc = 0
minetest.register_globalstep(function(dtime)
	acc = acc + dtime
	if acc < REFRESH then
		return
	end
	acc = 0
	for fn, v in pairs(Viewers) do
		local cpu = linked_controller(v.pos)
		local out = cpu and nanoc.get_output(cpu) or ""
		if out ~= v.last then
			v.last = out
			minetest.show_formspec(v.player, fn, formspec(v.pos))
		end
	end
end)
