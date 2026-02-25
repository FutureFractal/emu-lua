-- gstext.lua (for mGBA)
-- by FutureFractal
--[[
	This script allows you to replace any string ID on the fly in both GBA Golden Sun games.
	To add a string replacement, just use the Lua prompt to add it to the global `gstext` table.
	(example: gstext[2164] = "Fulminous Edge")
]]

-- Use the Lua prompt to set string IDs to replace here
gstext = {}

local game = emu:getGameCode()
local gs1  = game:sub(1,3) == "AGS"
local gs   = gs1 or game:sub(1,3) == "AGF"

local gsjp, jpchars
if game:sub(4) == 'J' then
	gsjp = assert(require("gsjp"))
	local kana, kanji = gsjp.kana, gsjp.kanji[game]
	jpchars = {}
	for i = 8, #kana  do jpchars[kana[i]]  = 0x7F + i end
	for i = 1, #kanji do jpchars[kanji[i]] = 0xFF + i end
end

local bp, contexts = nil, {}
local i_ptr

local function nextChar(context)
	local rs, ri = context[1], context[2]
	local c = string.byte(rs, ri)
	if c <= 0x7F then
		context[2] = ri + 1
		return c
	elseif (c & ~1) == 0xC2 then -- UTF8 -> Latin-1
		local cc = string.byte(rs, ri + 1) or 0
		if (cc & 0xC0) == 0x80 then
			context[2] = ri + 2
			return ((c & 3) << 6) | (cc & 0x3F)
		end
	else
		-- ...
	end
	return 0
end

local function onHuffStart()
	local str = gstext[emu:readRegister('r1')]
	if str ~= nil then
		contexts[emu:readRegister('r0')] = { str..string.char(0), 1 }
	end
end
local function onHuffNext()
	local context = contexts[emu:readRegister('r0')]
	if context then
		emu:writeRegister('r0', nextChar(context))
		emu:writeRegister('pc', emu:readRegister('lr'))
		emu:writeRegister('cpsr', emu:readRegister('cpsr') | 0x20) -- set THUMB mode
	end
end

local function onGlobalAllocIWRAM()
	local index = emu:readRegister(gs and 'r5' or 'r4')
	if index == i_ptr*4 then
		if bp then emu:clearBreakpoint(bp) end
		local addr = emu:readRegister('r0')
		bp = emu:setBreakpoint(onHuffNext, addr)
	end
end
local function onGlobalFree()
	if bp then
		local index = emu:readRegister('r0')
		if index == (gs1 and i_ptr or i_ptr*4) then
			emu:clearBreakpoint(bp)
			contexts = {}
		end
	end
end

local init = ({
	AGSJ = { 0x8019BA8, 0x80048E6, 0x8002DD8, 0x32 },
	AGSE = { 0x8019BAC, 0x80048E6, 0x8002DD8, 0x32 },
	AGSD = { 0x8018820, 0x8004916, 0x8002DD8, 0x32 },
	AGSF = { 0x8018ADC, 0x80048F6, 0x8002DD8, 0x32 },
	AGSI = { 0x8019B18, 0x8004926, 0x8002DD8, 0x32 },
	AGSS = { 0x8018B8C, 0x8004946, 0x8002DD8, 0x32 },
	AGFJ = { 0x803D2AC, 0x8014CF8, 0x801314C, 0x32 },
	AGFE = { 0x803D178, 0x8014CF8, 0x801314C, 0x32 },
	AGFD = { 0x803D1CC, 0x8014D24, 0x801314C, 0x32 },
	AGFF = { 0x803D1BC, 0x8014D24, 0x801314C, 0x32 },
	AGFI = { 0x803D1D0, 0x8014D24, 0x801314C, 0x32 },
	AGFS = { 0x803D1D8, 0x8014D24, 0x801314C, 0x32 },
	BMGJ = { 0x807426C, 0x801693E, 0x801494C, 0x05 },
	BMGE = { 0x80743B0, 0x801693E, 0x801494C, 0x05 },
	BMGD = { 0x8074228, 0x8016956, 0x801494C, 0x05 },
	BMGF = { 0x80741F4, 0x8016956, 0x801494C, 0x05 },
	BMGI = { 0x8074238, 0x8016956, 0x801494C, 0x05 },
	BMGS = { 0x8074238, 0x8016956, 0x801494C, 0x05 },
	BMGP = { 0x807428C, 0x8016956, 0x801494C, 0x05 },
	BMGU = { 0x80743B0, 0x8016956, 0x801494C, 0x05 },
	BTMJ = { 0x8044CA4, 0x801527E, 0x8013298, 0x09 },
	BTME = { 0x8038C74, 0x8015296, 0x8013288, 0x09 },
	BTMP = { 0x8038C74, 0x8015296, 0x8013288, 0x09 }
})[game]
if init == nil then
	console:error(("Unsupported game: %s (%s)"):format(emu:getGameTitle(), emu:getGameCode()))
	return
end

emu:setBreakpoint(onHuffStart,        init[1])
emu:setBreakpoint(onGlobalAllocIWRAM, init[2])
emu:setBreakpoint(onGlobalFree,       init[3])
i_ptr = init[4]

console:log("Text hook set, use the Lua prompt to set string IDs to replace")
console:log("(Example: gstext[2164] = \"Fulminous Edge\")")