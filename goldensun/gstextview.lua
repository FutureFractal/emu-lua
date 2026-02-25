-- gstextview.lua (for mGBA)
-- by FutureFractal
--[[
	This script prints any text from textboxes or battle messages to the console as well.
]]

local txtbuf

local p_ui, o_ui_buffer

local game = emu:getGameCode()
local lang = game:sub(4)

local gsjp, kana, kanji
if lang == 'J' then
	gsjp = assert(require("gsjp"))
	kana, kanji = gsjp.kana, gsjp.kanji[game]
end

local latin_special = {
	'[A]','','[B]','','[L]','','[R]','','[ST]','','[SE]','','','','“','—'
}
local function getBufferText(off)
	local ptr = emu:read32(p_ui) + o_ui_buffer
	local buf, i = {}, off
	while true do
		local c = emu:read16(ptr + i*2)
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
		elseif c == 3 then
			buf[#buf+1] = '\n'
		elseif c <= 2 then
			break
		end
		i = (i + 1) & 0x1FF
		if i == off then break end
	end
	return table.concat(buf)
end

local function onBattleText()
	print(getBufferText(emu:readRegister('r0')))
end
local function onMessageBox()
	-- This gets called twice for the first part of a multi-part message
	-- First time it's called, the 4th param is null
	-- TODO: this gets called by other stuff with a null 4th param, figure out how to tell
	if emu:readRegister('r3') == 0 then return end
	print(getBufferText(emu:readRegister('r0')))
end
local function onMessageBoxNew()
	local flags = emu:read32(emu:readRegister('sp')+8)
	if flags == 0 then return end
	print(getBufferText(emu:readRegister('r0')))
end

local function onBufferText()
	local ret = emu:read32(emu:readRegister('sp')+12)
	print(("[%08X] %s"):format(ret, getBufferText(emu:readRegister('r0'))))
end

local init = ({
	AGSJ = { 0x8018750, 0x8017468 },
	AGSE = { 0x8018850, 0x801751C },
	AGSD = { 0x801749C, 0x80161BC },
	AGSF = { 0x8017744, 0x80164CC },
	AGSI = { 0x8018764, 0x80174CC },
	AGSS = { 0x80177D8, 0x80164EC },
	AGFJ = { 0x803B924, 0x803A4FE },
	AGFE = { 0x803B918, 0x803A56A },
	AGFD = { 0x803B930, 0x803A52A },
	AGFF = { 0x803B920, 0x803A536 },
	AGFI = { 0x803B934, 0x803A54E },
	AGFS = { 0x803B930, 0x803A54E }
})[game]
if init == nil then
	console:error(("Unsupported game: %s (%s)"):format(emu:getGameTitle(), game))
	return
end

local gs1 = (game:sub(1,3) == "AGS")
p_ui        = gs1 and (lang == 'D' and 0x03001E9C or 0x3001E8C) or 0x300003C
o_ui_buffer = (gs1 and lang ~= 'J') and 0xEB0 or 0xF40

emu:setBreakpoint(onMessageBox, init[1]) -- ?
emu:setBreakpoint(onBattleText, init[2]) -- PrintBattleText

print("Text hooks set")