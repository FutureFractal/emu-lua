-- gstextdump.lua (for mGBA)
-- by FutureFractal
--[[
	This script prints any text from textboxes or battle messages to the console as well.
]]

local txtbuf

local p_ui, o_ui_buffer

local game = emu:getGameCode()
local lang = game:sub(4)
local gs1  = game:sub(1,3) == "AGS"
local gs   = gs1 or game:sub(1,3) == "AGF"

local gsjp, kana, kanji
if lang == 'J' then
	gsjp = assert(require("gsjp"))
	kana, kanji = gsjp.kana, gsjp.kanji[game]
end

local bp, contexts, last = nil, {}, nil
local i_ptr

local latin_special = {
	'[A]','','[B]','','[L]','','[R]','','[ST]','','[SE]','','','','“','—'
}
local function decodeString(bytes)
	local buf = {}
	for i = 1, #bytes do
		local c = bytes[i]
		if c >= 0x20 then
			if c < 0x80 then
				if c == 0x22 then buf[#buf+1] = '”'
				else buf[#buf+1] = string.char(c) end
			elseif gsjp ~= nil then
				if c >= 0x100 then
					buf[#buf+1] = kanji[c - 0xFF] or ''
				elseif c >= 0x80 then
					if (c & 0xFE) ~= 0xDE then
						buf[#buf+1] = kana[c - 0x7F] or ''
					else
						buf[#buf] = (c == 0xDE and gsjp.dakuten or gsjp.handakuten)[buf[#buf]] or ''
					end
				end
			elseif c >= 0xA0 then -- Latin-1 -> UTF-8
				buf[#buf+1] = string.char(0xC0 | (c >> 6), 0x80 | (c & 0x3F))
			else
				buf[#buf+1] = latin_special[c - 0x7F] or ''
			end
		else
			buf[#buf+1] = ("\\x%02X"):format(c)
		end
	end
	return table.concat(buf)
end

local function onHuffStart()
	local id = emu:readRegister('r1')
	if id ~= last then
		last = id
		contexts[emu:readRegister('r0')] = { id, {} }
	end
end
local function onHuffNext()
	local ptr = emu:readRegister('r0')
	local context = contexts[ptr]
	if context ~= nil then
		local c = emu:read32(ptr)
		if c ~= 0 then
			local buf = context[2]
			buf[#buf+1] = c
		end
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
			for addr, context in pairs(contexts) do
				print(("%u: %s"):format(context[1], decodeString(context[2])))
			end
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

console:log("Text hook set")