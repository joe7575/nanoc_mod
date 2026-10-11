--[[

	NanoC
	=====

	Copyright (C) 2024-2026 Joachim Stolberg

	AGPL v3
	See LICENSE.txt for more information

	Capability catalog for the "Beduino" command interface (BEP 005).

	Maps a techage node to the topics it accepts (send) or answers (request),
	so external clients / AI know *how* to query state and control nodes.

	Built-in TA4/TA5 nodes are covered by name-pattern rules (from BEP 005).
	Other mods (internal or external, e.g. signs_bot, pdp13) can declare their
	own capabilities with:
	    nanoc.register_capabilities({"mod:node"}, {128, 129, 1},
	        {[128]={kind="request", name="identify", response="<node name>"}})

]]--

nanoc = nanoc or {}

-- Topic reference (BEP 005): kind (send/request), short name, payload/response
nanoc.cap_topics = {
	[1]   = { kind = "send", name = "on/off", note = "[state] 0=off, 1=on" },
	[2]   = { kind = "send", name = "signal/traffic color", note = "[0..3]" },
	[3]   = { kind = "send", name = "signal lamp color", note = "[idx, 0..3]" },
	[4]   = { kind = "send", name = "distributor filter slot", note = "[idx, 0|1]" },
	[6]   = { kind = "send", name = "detector reset" },
	[7]   = { kind = "send", name = "ta3 sequencer", note = "[0|1|2]" },
	[9]   = { kind = "send", name = "door controller II", note = "[cmd, idx]" },
	[10]  = { kind = "send", name = "autocrafter recipe", note = "[num1, num2, idx]" },
	[11]  = { kind = "send", name = "autocrafter flush | move controller" },
	[12]  = { kind = "send", name = "turn controller", note = "[1|2|3]" },
	[13]  = { kind = "send", name = "sequencer start/stop", note = "[slot]" },
	[14]  = { kind = "send", name = "sound", note = "[1,vol] | [2,index]" },
	[15]  = { kind = "send", name = "7-segment", note = "[0..15]" },
	[16]  = { kind = "send", name = "14-segment", note = "[0..0x3FFF]" },
	[17]  = { kind = "send", name = "display clear" },
	[18]  = { kind = "send", name = "move by xyz", note = "[x, y, z]" },
	[19]  = { kind = "send", name = "move reset" },
	[20]  = { kind = "send", name = "pusher limit", note = "[limit]" },
	[21]  = { kind = "send", name = "pump limit", note = "[limit]" },
	[22]  = { kind = "send", name = "color", note = "[0..255]" },
	[23]  = { kind = "send", name = "multi button", note = "[num, state]" },
	[24]  = { kind = "send", name = "move moveto", note = "[x, y, z]" },
	[64]  = { kind = "send", name = "(string command)", note = "<text>" },
	[65]  = { kind = "send", name = "config item / limit", note = "<item name | limit>" },
	[66]  = { kind = "send", name = "sensor chest text", note = "<text>" },
	[67]  = { kind = "send", name = "display add line | filter config | digitizer mode", note = "<text>" },
	[68]  = { kind = "send", name = "display write line", note = "<num>text" },
	[70]  = { kind = "send", name = "color (lamp)", note = "[num]" },

	[128] = { kind = "request", name = "identify", response = "<node name>" },
	[129] = { kind = "request", name = "state", response = "[state] 1=run 2=blocked 3=standby 4=nopower 5=fault 6=stopped 7=unloaded 8=inactive" },
	[130] = { kind = "request", name = "signal/traffic color", response = "[0..3]" },
	[131] = { kind = "request", name = "chest state", response = "[0=empty 1=loaded 2=full]" },
	[132] = { kind = "request", name = "fuel level", response = "[0..65535]" },
	[133] = { kind = "request", name = "quarry depth", response = "[1..80]" },
	[134] = { kind = "request", name = "load percent", note = "[1] % | [2] abs", response = "[num]" },
	[135] = { kind = "request", name = "power", response = "[num]" },
	[137] = { kind = "request", name = "total flow rate", response = "[num]" },
	[138] = { kind = "request", name = "sensor chests state", note = "[1..4, idx]" },
	[139] = { kind = "request", name = "item counter", response = "[num]" },
	[140] = { kind = "request", name = "inventory item", note = "[1|2|3, idx]" },
	[141] = { kind = "request", name = "furnace output", response = "<node name>" },
	[142] = { kind = "request", name = "binary state", response = "[0|1]" },
	[143] = { kind = "request", name = "light level", response = "[0..15]" },
	[144] = { kind = "request", name = "player name", response = "<name>" },
	[145] = { kind = "request", name = "solar cell state", response = "[0..2]" },
	[146] = { kind = "request", name = "electric meter", note = "[0|1|2]" },
	[147] = { kind = "request", name = "door controller II block name", response = "<node name>" },
	[148] = { kind = "request", name = "distributor filter get", response = "<item list>" },
	[149] = { kind = "request", name = "timestamp", response = "[time]" },
	[150] = { kind = "request", name = "pusher counter", response = "[num]" },
	[151] = { kind = "request", name = "pump counter", response = "[num]" },
	[152] = { kind = "request", name = "multi button state", note = "[num]" },
	[153] = { kind = "request", name = "water remover depth" },
	[154] = { kind = "request", name = "digitizer item count", response = "[num]" },
	[155] = { kind = "request", name = "digitizer item name", response = "<item name>" },
	[192] = { kind = "request", name = "chest item count", note = "<item name>" },
}

-- Explicit registrations win over pattern rules. External mods add here.
nanoc.cap_explicit = {}

-- Ordered name-pattern -> topics (first match wins; order matters)
nanoc.cap_rules = {
	{ "sensor_chest",   { 66, 131, 138 } },
	{ "color_lamp",     { 1, 22, 70 } },
	{ "signaltower",    { 2, 130 } },
	{ "signal_lamp",    { 3 } },
	{ "signallamp",     { 3 } },
	{ "trafficlight",   { 2, 130 } },
	{ "chest",          { 131, 192 } },
	{ "hl_chest",       { 131, 192 } },
	{ "pusher",         { 1, 20, 65, 150 } },
	{ "autocrafter",    { 1, 10, 11, 129 } },
	{ "electronic_fab", { 1, 128, 129 } },
	{ "display",        { 17, 67, 68 } },
	{ "button",         { 1, 23, 152, 144, 149, 131 } },
	{ "detector",       { 6, 139 } },
	{ "playerdetector", { 142, 144 } },
	{ "nodedetector",   { 142 } },
	{ "lightdetector",  { 142, 143 } },
	{ "cartdetector",   { 142 } },
	{ "mbadetector",    { 142 } },
	{ "solar_minicell", { 145 } },
	{ "solar",          { 1, 128, 129, 135 } },
	{ "wind",           { 1, 129, 135 } },
	{ "generator",      { 1, 128, 129, 135 } },
	{ "battery",        { 134 } },
	{ "akku",           { 1, 128, 129, 134 } },
	{ "fuelcell",       { 1, 128, 129, 134, 135 } },
	{ "power_terminal", { 134, 135 } },
	{ "powerswitch",    { 1, 142 } },
	{ "firebox",        { 128, 129, 132 } },
	{ "heatexchanger",  { 1, 128, 129, 134, 135 } },
	{ "electrolyzer",   { 1, 128, 129, 134, 135 } },
	{ "transformer",    { 1, 128, 129 } },
	{ "electricmeter",  { 1, 128, 129, 146 } },
	{ "silo",           { 131, 134 } },
	{ "tank",           { 128, 134 } },
	{ "pump",           { 1, 21, 128, 129, 137, 151 } },
	{ "pumpjack",       { 134 } },
	{ "quarry",         { 1, 128, 129, 133 } },
	{ "movecontroller", { 11, 18, 19, 24, 129 } },
	{ "turncontroller", { 12 } },
	{ "sequencer",      { 13 } },
	{ "digitizer",      { 1, 65, 67, 128, 129, 154, 155 } },
	{ "distributor",    { 1, 4, 67, 128, 129, 148 } },
	{ "doorcontroller2",{ 1, 9, 147 } },
	{ "doorcontroller", { 1 } },
	{ "soundblock",     { 1, 14 } },
	{ "collector",      { 129 } },
	{ "icta_controller",{ 1, 129 } },
	{ "lua_controller", { 1, 142 } },
	{ "injector",       { 1, 128, 129 } },
	{ "grinder",        { 1, 128, 129 } },
	{ "sieve",          { 1, 128, 129 } },
	{ "recycler",       { 1, 128, 129 } },
	{ "rinser",         { 1, 128, 129 } },
	{ "liquidsampler",  { 1, 128, 129 } },
	{ "doser",          { 1, 128, 129 } },
	{ "drillbox",       { 1, 128, 129 } },
	{ "furnace",        { 1, 128, 129, 141 } },
	{ "logic",          { 1 } },
	{ "repeater",       { 1 } },
	{ "lamp",           { 1, 22 } },
	{ "valve",          { 1, 142 } },
}

-- @param names  list of node names
-- @param topics list of topic numbers
-- @param meta   optional { [topic] = {kind, name, note, response} } to extend
function nanoc.register_capabilities(names, topics, meta)
	if meta then
		for t, info in pairs(meta) do
			nanoc.cap_topics[t] = info
		end
	end
	for _, name in ipairs(names or {}) do
		nanoc.cap_explicit[name] = topics
	end
end

-- @return array of topic numbers for the node, or nil
function nanoc.capabilities(name)
	local topics = nanoc.cap_explicit[name]
	if topics then
		return topics
	end
	for _, rule in ipairs(nanoc.cap_rules) do
		if name:find(rule[1], 1, true) then
			return rule[2]
		end
	end
	return nil
end
