-- gsdrawview.lua (for mGBA)
-- by FutureFractal
--[[
	This script displays a wireframe overlay over any 2D and 3D effects in battle animations,
	as well as displaying stats about what's being rendered.
	This supports all versions of both GBA Golden Sun games.

  BUGS:
    - Overlay is often 1 frame ahead of actual game (only in real time, emulator frame advance is fine)
]]

if gsdrawview ~= nil then
	console:error("gsdrawview is already running")
	return
end

-- Configurable settings (set with Lua prompt)
gsdrawview = {
	color1D   = 0x00FF7F, -- Line color
	color2D   = 0x00FFFF, -- 2D outline color
	color3D   = 0xFF00FF, -- 3D outline color
	full      = false,    -- Draw on top of the in-game HUD
	cull      = true,     -- Skip drawing culled triangles
	dynamicbp = true      -- create breakpoints dynamically (needed for Draw2D)
}

local game = emu:getGameCode()
local game, lang = game:sub(1,3), game:sub(4)
local gs1 = (game == "AGS")
if not (gs1 or game == "AGF") then
	console:error(("Unsupported game: %s (%s)"):format(emu:getGameTitle(), game))
	return
end

local p_renderbuf

local overlay, painter, txtbuf

-- Unfortunately because the BG transform params can change between drawing and blitting,
-- we can't just draw directly to an image from the draw hooks; we need a buffer system.
local dlbuf          = {}
local d2buf, d2modes = {}, 0
local d3buf, d3modes = {}, 0

local draw      = false
local forcebg1  = false
local maxcalls  = 0
local maxtris   = 0
local lastframe = 0

local bps = {} -- dynamic breakpoint handles for Draw2D functions

local d2names = {
	"NONE",
	"MASK",
	"MAX",
	"ADD",
	"XFLIP",
	"YFLIP",
}
local d3names = {
	"FLAT",
	"FLAT_MAX",
	"FLAT_ADD",
	"TEX_MAX",
	"TEX_ADD",
	"TEX_FADE_MAX",
	"TEX_FADE_ADD",
	"TEX",
	"TEX_FADE_MASK",
	"SMALL_TEX",
	"SMALL_FLAT"
}
local function printFlags(flags, names)
	local comma = false
	for i = 0, #names - 1 do
		if (flags & 1 << i) ~= 0 then
			if comma then txtbuf:print(", ") end
			txtbuf:print(names[i + 1])
			comma = true
		end
	end
end
local function printInfo()
--[[
	draw2D: <modes>
	    calls: <num> (max: <num>)
	draw3D: <modes>
	    tris:  <num> (max: <num>)
]]
	txtbuf:clear()

	txtbuf:moveCursor(0, 0)
	txtbuf:print("draw2D: ")
	if d2modes ~= 0 then
		printFlags(d2modes, d2names)
		d2modes = 0
	end
	local ncalls = #d2buf / 4
	maxcalls = math.max(maxcalls, ncalls)
	txtbuf:moveCursor(4,  1)
	txtbuf:print(("calls: %d"):format(ncalls))
	txtbuf:moveCursor(17, 1)
	txtbuf:print(("(max: %d)"):format(maxcalls))

	if not gs1 then
		txtbuf:moveCursor(0, 2)
		txtbuf:print("draw3D: ")
		if d3modes ~= 0 then
			printFlags(d3modes, d3names)
			d3modes = 0
		end
		local ntris = #d3buf / 6
		maxtris = math.max(maxtris, ntris)
		txtbuf:moveCursor(4,  3)
		txtbuf:print(("tris:  %u"):format(ntris))
		txtbuf:moveCursor(17, 3)
		txtbuf:print(("(max: %u)"):format(maxtris))
	end
end

local function onDrawLine()
	local x1 = emu:readRegister('r0')
	local y1 = emu:readRegister('r1')
	local x2 = emu:readRegister('r2')
	local y2 = emu:readRegister('r3')
	local b, i = dlbuf, #dlbuf + 1
	b[i], b[i+1], b[i+2], b[i+3] = x1, y1, x2, y2
	draw = true
end

local function onDraw2D(mode)
	-- ignore Draw2D calls that don't draw directly into the renderbuffer
	if emu:readRegister('r0') ~= emu:read32(p_renderbuf) then return end

	local sp     = emu:readRegister('sp')
	local x      = emu:readRegister('r2')
	local y      = emu:readRegister('r3')
	local width  = emu:read32(sp)
	local height = emu:read32(sp + 4)

	if (width | height) >= 256 then
		print(("[%u] bad draw2D call! (lr=%08X)"):format(emu:currentFrame(), emu:readRegister('lr')))
		-- invalidate the current breakpoint
		local addr = emu:readRegister('pc')-4
		local bp = bps[addr]
		if bp == nil then addr = addr+2; bp = bps[addr] end
		if bp ~= nil then
			emu:clearBreakpoint(bp); bps[addr] = nil
		end
		return
	end

	local b, i = d2buf, #d2buf + 1
	b[i], b[i+1], b[i+2], b[i+3] = x, y, width, height
	d2modes = d2modes | mode
	draw = true
end
local function onBuildDraw2D()
	if not gsdrawview.dynamicbp then return end
	local addr  = emu:readRegister('r0')
	local flags = emu:readRegister('r8')
	local blend = gs1 and emu:readRegister('r10') or 3 - emu:readRegister('r9')
	local mode  = (1 << blend) | ((flags >> 2) << 4)

	local bp = bps[addr]
	if bp ~= nil then emu:clearBreakpoint(bp) end
	bps[addr] = emu:setBreakpoint((function() onDraw2D(mode) end), addr)
end
local function onGlobalFree()
	local i = emu:readRegister('r0')
	local addr = emu:read32(gs1 and (0x3001E50 + (lang == 'D' and 0x10 or 0) + i*4) or (0x3000000 + i))
	local bp = bps[addr]
	if bp ~= nil then
		emu:clearBreakpoint(bp); bps[addr] = nil
		-- hacky way of hooking the end of standard attack/crit anim to save a breakpoint
		forcebg1 = false
	end
end
local function hookGlobalDraw2DFunc(addr)
	if not gsdrawview.dynamicbp then return end
	addr = emu:read32(addr)
	if addr ~= 0 and bps[addr] == nil then
		-- unfortunately we can't trivially recover the mode parameters for an existing function... whatever
		bps[addr] = emu:setBreakpoint((function() onDraw2D(0) end), addr)
	end
end

local function onDraw3D()
	local cmds = emu:readRegister('r0')
	local i    = #d3buf + 1
	while true do -- TODO: bounds checking maybe? this could loop forever if it encounters unterminated data
		local mode = emu:read32(cmds)
		if mode == 0 then break end

		d3modes = d3modes | 1 << (mode - 1)

		-- triangle struct length (UVs or no UVs)
		local step = (mode >= 4 and mode <= 10) and 12 or 4

		local cull  = gsdrawview.cull and emu:read32(cmds + 0x4) & 3 or 0
		local tris  = emu:read32(cmds + 0x8)
		local verts = emu:read32(cmds + 0xC)

		if cull ~= 0 then
			cull = (cull == 3) and 1 or -1
		end

		while true do
			local tri = emu:read32(tris) & 0xFFFFFF
			if tri == 0 then break end

			-- read transformed verts (u16 x, y, z, _; we only care about xy)
			local v1 = emu:read32(verts +  (tri       & 0xFF) * 8)
			local v2 = emu:read32(verts + ((tri >> 8) & 0xFF) * 8)
			local v3 = emu:read32(verts +  (tri >> 16)        * 8)

			local x1 = (v1 & 0x7FFF) - (v1 & 0x8000); v1 = v1 >> 16
			local y1 = (v1 & 0x7FFF) - (v1 & 0x8000)
			local x2 = (v2 & 0x7FFF) - (v2 & 0x8000); v2 = v2 >> 16
			local y2 = (v2 & 0x7FFF) - (v2 & 0x8000)
			local x3 = (v3 & 0x7FFF) - (v3 & 0x8000); v3 = v3 >> 16
			local y3 = (v3 & 0x7FFF) - (v3 & 0x8000)

			-- skip drawing culled tris
			if cull == 0 or cull * (x2 - x1) * (y3 - y1) - (x3 - x1) * (y2 - y1) > 0 then
				local b = d3buf
				b[i], b[i+1], b[i+2], b[i+3], b[i+4], b[i+5] = x1, y1, x2, y2, x3, y3
				i = i + 6
			end
			tris = tris + step
		end
		cmds = cmds + 0x1C
	end
	draw = true
end

local function drawOverlay(bgx, bgy, bgpa)
	printInfo()
	painter:setStrokeWidth(1)

	local b = d3buf
	if #b > 0 then
		if gsdrawview.color3D ~= nil then
			painter:setStrokeColor(gsdrawview.color3D | 0xFF000000)
			for i = 1, #b, 6 do
				local x1, y1, x2, y2, x3, y3 = b[i], b[i+1], b[i+2], b[i+3], b[i+4], b[i+5]
				x1, y1 = (((x1 - bgx) * 0x100) // bgpa) - 1, y1 - bgy
				x2, y2 = (((x2 - bgx) * 0x100) // bgpa) - 1, y2 - bgy
				x3, y3 = (((x3 - bgx) * 0x100) // bgpa) - 1, y3 - bgy
				painter:drawLine(x1, y1, x2, y2)
				painter:drawLine(x2, y2, x3, y3)
				painter:drawLine(x3, y3, x1, y1)
			end
		end
		d3buf = {}
	end
	local b = d2buf
	if #b > 0 then
		if gsdrawview.color2D ~= nil then
			painter:setStrokeColor(gsdrawview.color2D | 0xFF000000)
			painter:setFill(false)
			for i = 1, #b, 4 do
				local x, y, width, height = b[i], b[i+1], b[i+2], b[i+3]
				x, y  = ((x - bgx) * 0x100) // bgpa, y - bgy
				width = ( width    * 0x100) // bgpa
				painter:drawRectangle(x, y, width, height)
			end
		end
		d2buf = {}
	end
	local b = dlbuf
	if #b > 0 then
		if gsdrawview.color1D ~= nil then
			painter:setStrokeColor(gsdrawview.color1D | 0xFF000000)
			for i = 1, #b, 4 do
				local x1, y1, x2, y2 = b[i], b[i+1], b[i+2], b[i+3]
				x1, y1 = ((x1 - bgx) * 0x100) // bgpa, y1 - bgy
				x2, y2 = ((x2 - bgx) * 0x100) // bgpa, y2 - bgy
				painter:drawLine(x1, y1, x2, y2)
			end
		end
		dlbuf = {}
	end

	if not gsdrawview.full then
		-- erase pixels that overlap the in-game UI
		painter:setStrokeWidth(0)
		painter:setFill(true)
		local width, height = 200, emu:read8(0x060020FA) ~= 0 and 11 or 3
		for addr = 0x0600200A, 0x06002022, 0xC do
			if emu:read8(addr) ~= 0 then break end
			width = width - 48
		end
		painter:drawRectangle(0, 0,   240, 16) -- letterbox top
		painter:drawRectangle(0, 136, 240, 24) -- letterbox bottom
		painter:drawRectangle(240 - width, 16, width, height) -- stat box overhang
	end
end

local function onBlit(bg1, yoff)
	if draw then
		painter:setStrokeWidth(0)
		painter:drawRectangle(0, 0, canvas:width(), canvas:height())
		if (#dlbuf | #d2buf | #d3buf) > 0 then
			local io = emu.memory['io']
			if bg1 then
				local bgx = io:read16(0x04000014); bgx = ((bgx & 0xFF) - (bgx & 0x100))
				local bgy = io:read16(0x04000016); bgy = ((bgy & 0xFF) - (bgy & 0x100)) - 48
				drawOverlay(bgx, bgy + yoff, 0x100)
			else -- bg2
				local bgpa = io:read16(0x04000020)
				if bgpa ~= 0 then
					local bgx = io:read32(0x04000028) >> 8; bgx = ((bgx & 0x7FFFFF) - (bgx & 0x800000))
					local bgy = io:read32(0x0400002C) >> 8; bgy = ((bgy & 0x7FFFFF) - (bgy & 0x800000))
					drawOverlay(bgx, bgy + yoff, bgpa)
				end
			end
		else
			draw = false
			printInfo()
		end
		overlay:update()
	end
end
local function onBlitBG()
	onBlit(forcebg1, forcebg1 and -48 or 0)
end
local function onBlitBG1()
	onBlit(true, 0)
end
local function onBlitLuckyWheels()
	onBlit(false, -16)
end

local function onAnimStartEnd()
	painter:setStrokeWidth(0)
	painter:drawRectangle(0, 0, canvas:width(), canvas:height())
	overlay:update()
	dlbuf, d2buf, d3buf = {}, {}, {}
	for addr, bp in pairs(bps) do
		emu:clearBreakpoint(bp); bps[addr] = nil
	end
	printInfo()
	maxcalls, maxtris = 0, 0
	forcebg1 = false
end
local function onAnimInitBG1()
	forcebg1 = true
end

local function onFrame()
	local frame = emu:currentFrame()
	local diff  = frame - lastframe
	-- frame callback can apparently fire multiple times per frame, so make sure diff ~= 0 too
	if (diff >> 1) ~= 0 then
		if diff ~= -1 then -- reset/load savestate
			onAnimStartEnd()
		else               -- rewind
			for addr, bp in pairs(bps) do
				emu:clearBreakpoint(bp); bps[addr] = nil
			end
		end
		hookGlobalDraw2DFunc(gs1 and 0x3001F08 + (lang == 'D' and 0x10 or 0) or 0x3000068)
		hookGlobalDraw2DFunc(gs1 and 0x3001F0C + (lang == 'D' and 0x10 or 0) or 0x30000BC)
	end
	lastframe = frame
end

overlay = assert(canvas:newLayer(canvas:width(), canvas:height()))
painter = assert(image.newPainter(overlay.image))
painter:setFillColor(0)

txtbuf = assert(console:createBuffer("GSDraw"))
txtbuf:setSize(64, 5)
printInfo()

p_renderbuf = gs1 and (lang == 'D' and 0x3001F00 or 0x3001EF0) or 0x3000060

local off = gs1 and ({J=-0x9000,E=0,D=0x1E00,F=0x3800,I=0,S=0x3800})[lang] or (lang == 'J' and 4 or 0)
emu:setBreakpoint(onGlobalFree,   gs1 and 0x8002DD8       or 0x801314C)       -- gfree
emu:setBreakpoint(onAnimStartEnd, gs1 and 0x80CD594 + off or 0x81435E0)       -- AnimStart
emu:setBreakpoint(onAnimStartEnd, gs1 and 0x80CDBC0 + off or 0x8143BB8)       -- AnimEnd
emu:setBreakpoint(onAnimInitBG1,  gs1 and 0x80CDD58 + off or 0x8143D80)       -- InitRenderTilemapBG1
emu:setBreakpoint(onBlitBG,       gs1 and 0x80C1438 + off or 0x8127038)       -- Task_BlitPreAnim
emu:setBreakpoint(onBlitBG,       gs1 and 0x80CD324 + off or 0x81430EC)       -- Task_BlitAnim
emu:setBreakpoint(onBlitBG1,      gs1 and 0x80CD3F4 + off or 0x814324A)       -- Task_BlitAnimBG1Wide
emu:setBreakpoint(onDrawLine,     gs1 and 0x80CDE90 + off or 0x8143EB4)       -- DrawLine
emu:setBreakpoint(onBuildDraw2D,  gs1 and 0x80ED50E + off or 0x819642A + off) -- BuildDraw2DFuncEx
if not gs1 then
	emu:setBreakpoint(onBlitBG,  0x813F89C)       -- Task_BlitUnleashIntro
	emu:setBreakpoint(onBlitBG1, 0x814332E)       -- Task_BlitAnimBG1
	emu:setBreakpoint(onDraw3D,  0x8196A7C + off) -- Draw3D
end
off = ({J=-0x9008,E=0,D=0xE00,F=0x2800,I=0,S=0x2800})[lang]
emu:setBreakpoint(onBlitLuckyWheels, gs1 and 0x80F6114 + off or 0x81B2130) -- Task_BlitLuckyWheelsAnim

callbacks:add("frame", onFrame)