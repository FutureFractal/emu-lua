-- glitchmapfix.lua (for mGBA)
-- by FutureFractal

function onRhydonTrap()
	emu:writeRegister('pc', emu:readRegister('pc') + 6)
end
function onPaletteTrap()
	emu:writeRegister('pc', emu:readRegister('pc') + 2)
end

-- GB games don't have a unique game code, use the header global checksum instead
local chksum = emu:read8(0x14E)<<8 | emu:read8(0x14F)
local init = ({
	[0xA2C1] = { 0x2D9D, 0x6442 }, -- JRv0
	[0xDDD5] = { 0x2D9D, 0x6442 }, -- JGv0
	[0xB866] = { 0x2D8B, 0x6442 }, -- JRv1
	[0xF547] = { 0x2D8B, 0x6442 }, -- JGv1
	[0xDC36] = { 0x1360, 0x6431 }, -- JB
	[0x91E6] = { 0x13A7, 0x5E62 }, -- ER
	[0x9D0A] = { 0x13A7, 0x5E62 }, -- EB
	[0x7AFC] = { 0x13A7, 0x5E33 }, -- FR
	[0x56A4] = { 0x13A7, 0x5E33 }, -- FB
	[0x89D2] = { 0x13A7, 0x5EA2 }, -- IR
	[0x5E9C] = { 0x13A7, 0x5EA2 }, -- IB
	[0x5CDC] = { 0x13A7, 0x5E3C }, -- GR
	[0x2EBC] = { 0x13A7, 0x5E3C }, -- GB
	[0x384A] = { 0x13A7, 0x5E52 }, -- SR
	[0x14D7] = { 0x13A7, 0x5E52 }, -- SB
	[0x9C29] = { 0x1155, 0x5FBB }, -- JYv0
	[0x8858] = { 0x115D, 0x5FBB }, -- JYv1
	[0xEDD9] = { 0x115D, 0x5FBB }, -- JYv2
	[0xD984] = { 0x115D, 0x5FBB }, -- JYv3
	[0x047C] = { 0x1167, 0x5F40 }, -- EY
	[0xB7C1] = { 0x1167, 0x5F11 }, -- FY
	[0x4E8F] = { 0x1167, 0x5F80 }, -- IY
	[0x66FB] = { 0x1167, 0x5F1F }, -- GY
	[0x5637] = { 0x1167, 0x5F30 }  -- SY
})[chksum]
if init == nil or emu:getGameTitle():sub(1,7) ~= "POKEMON" then
	console:error(("Unsupported game: %s"):format(emu:getGameTitle()))
	return
end

emu:setBreakpoint(onRhydonTrap,  init[1])
emu:setBreakpoint(onPaletteTrap, init[2], 0x1C)
console:log("Rhydon trap is gone")