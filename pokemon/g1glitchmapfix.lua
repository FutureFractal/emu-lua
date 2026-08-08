-- g1glitchmapfix.lua (for mGBA)
-- by FutureFractal
--[[
	This script prevents glitch maps in Gen 1 Pokémon from crashing the game.
]]

local p_mapinfo
local yellow = emu:getGameTitle():sub(1,11) == "POKEMON YEL"

local glitchMaps = {}
for _, id in pairs(({
	0x0B, 0x69, 0x6A, 0x6B, 0x6D, 0x6E, 0x6F, 0x70, 0x72, 0x73, 0x74, 0x75, 0xCC, 0xCD, 0xCE, 
	0xE7, 0xED, 0xEE, 0xF1, 0xF2, 0xF3, 0xF4, 0xF8, 0xF9, 0xFA, 0xFB, 0xFC, 0xFD, 0xFE, 0xFF
})) do glitchMaps[id] = true end

local function onWarpLoop()
	if emu:readRegister('de') >= p_mapinfo + 0xD4 then -- end of wWarpEntries
		local r = emu:readRegister('c')
		emu:writeRegister('pc', emu:readRegister('pc') + 2) -- skip jr, break out of loop
		emu:writeRegister('hl', emu:readRegister('hl') + r * 4) -- skip remaining warps
--		print(("map signs addr:   $%04X"):format(emu:readRegister('hl')))
	end
end
local function onSignLoop()
	if emu:readRegister('de') >= p_mapinfo + 0x176 then -- end of wSignCoords
		local r = emu:readRegister('c')
		emu:writeRegister('pc', emu:readRegister('pc') + 2) -- skip jr, break out of loop
		emu:writeRegister('hl', emu:readRegister('hl') + r * 3) -- skip remaining signs
--		print(("map sprites addr: $%04X"):format(emu:readRegister('hl')))
	end
end
local function onNumSprites()
	if emu:readRegister('a') > 15 then -- wNumSprites
		emu:writeRegister('a', 15)
	end
end

-- TODO: maybe optimize by hooking outer loop instead of inner loop
local function onWriteBlock()
	local dest = emu:readRegister('hl')
	if dest >= 0xCBFC or dest < 0xC6E8 then
		emu:writeRegister('pc', emu:readRegister('pc') + 1) -- skip write
		emu:writeRegister('c', 1); emu:writeRegister('b', 1) -- force loop to end early
	end
	collectgarbage('collect') -- fix for weird emulator unresponsiveness
end
local function onWriteBorder()
	local dest = emu:readRegister('de')
	if dest >= 0xCBFC or dest < 0xC6E8 then
		emu:writeRegister('pc', emu:readRegister('pc') + 1) -- skip write
		emu:writeRegister('c', 1); emu:writeRegister('b', 1) -- force loop to end early
	end
	collectgarbage('collect') -- fix for weird emulator unresponsiveness
end

local function onLoaded()
	-- fix music bank:
	local bank = emu:read8(p_mapinfo + 1) -- wMapMusicROMBank
	if not (bank == 2 or bank == 8 or bank == 0x1F or (yellow and bank == 0x20)) then
		emu:write8(p_mapinfo + 1, 2) -- wMapMusicROMBank
	end
	-- fix map script:
	local map = emu:read8(p_mapinfo + 3) -- wCurMap
	if glitchMaps[map] then
		local ptr = 0x007A -- address of first ret instruction in the ROM
		emu:write16(p_mapinfo + 0x13, ptr) -- wCurMapScriptPtr
	end
end

-- GB games don't have a unique game code, use the header global checksum instead
local chksum = emu:read8(0x14E)<<8 | emu:read8(0x14F) -- (big endian)
local init = ({
--	[0xA2C1] = { ?,      ?,      ?,      ?,      ?,      ?,      ?      }, -- JRv0
--	[0xDDD5] = { ?,      ?,      ?,      ?,      ?,      ?,      ?      }, -- JGv0
--	[0xB866] = { ?,      ?,      ?,      ?,      ?,      ?,      ?      }, -- JRv1
--	[0xF547] = { ?,      ?,      ?,      ?,      ?,      ?,      ?      }, -- JGv1
--	[0xDC36] = { ?,      ?,      ?,      ?,      ?,      ?,      ?      }, -- JB
	[0x91E6] = { 0xD35B, 0x1120, 0x114E, 0x1159, 0x1237, 0x0A34, 0x0AE6 }, -- ER
	[0x9D0A] = { 0xD35B, 0x1120, 0x114E, 0x1159, 0x1237, 0x0A34, 0x0AE6 }, -- EB
--	[0x7AFC] = { ?,      ?,      ?,      ?,      ?,      ?,      ?      }, -- FR
--	[0x56A4] = { ?,      ?,      ?,      ?,      ?,      ?,      ?      }, -- FB
--	[0x89D2] = { ?,      ?,      ?,      ?,      ?,      ?,      ?      }, -- IR
--	[0x5E9C] = { ?,      ?,      ?,      ?,      ?,      ?,      ?      }, -- IB
--	[0x5CDC] = { ?,      ?,      ?,      ?,      ?,      ?,      ?      }, -- GR
--	[0x2EBC] = { ?,      ?,      ?,      ?,      ?,      ?,      ?      }, -- GB
--	[0x384A] = { ?,      ?,      ?,      ?,      ?,      ?,      ?      }, -- SR
--	[0x14D7] = { ?,      ?,      ?,      ?,      ?,      ?,      ?      }, -- SB
--	[0x9C29] = { ?,      ?,      ?,      ?,      ?,      ?,      ?      }, -- JYv0
--	[0x8858] = { ?,      ?,      ?,      ?,      ?,      ?,      ?      }, -- JYv1
--	[0xEDD9] = { ?,      ?,      ?,      ?,      ?,      ?,      ?      }, -- JYv2
--	[0xD984] = { ?,      ?,      ?,      ?,      ?,      ?,      ?      }, -- JYv3
	[0x047C] = { 0xD35A, 0x0E49, 0x0EC8, 0x1007, 0x0EA9, 0x086F, 0x0921 }, -- EY
--	[0xB7C1] = { ?,      ?,      ?,      ?,      ?,      ?,      ?      }, -- FY
--	[0x4E8F] = { ?,      ?,      ?,      ?,      ?,      ?,      ?      }, -- IY
--	[0x66FB] = { ?,      ?,      ?,      ?,      ?,      ?,      ?      }, -- GY
--	[0x5637] = { ?,      ?,      ?,      ?,      ?,      ?,      ?      }  -- SY
})[chksum]
if init == nil or emu:getGameTitle():sub(1,7) ~= "POKEMON" then
	console:error(("Unsupported game: %s"):format(emu:getGameTitle()))
	return
end

p_mapinfo = init[1]
emu:setBreakpoint(onWarpLoop,    init[2])        -- LoadMapHeader: jr nz, .warpLoop
emu:setBreakpoint(onSignLoop,    init[3])        -- LoadMapHeader/CopySignData: jr nz, .signLoop
emu:setBreakpoint(onNumSprites,  init[4])        -- LoadMapHeader/InitSprites: ld [wNumSprites], a
emu:setBreakpoint(onLoaded,      init[5])        -- LoadMapHeader: ret
emu:setBreakpoint(onWriteBlock,  init[6])        -- LoadTileBlockMap: ld [hl+], a
emu:setBreakpoint(onWriteBorder, init[7])        -- LoadNorthSouthConnectionsTileMap: ld [de], a
emu:setBreakpoint(onWriteBorder, init[7] + 0x21) -- LoadEastWestConnectionsTileMap:   ld [de], a