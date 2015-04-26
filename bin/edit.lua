local filesystem = require "filesystem"
local term = require "term"
local keyboard = require "keyboard"
local gpu = term.getGPU()
term.clear()

local line, col = 2,1
local scrollX, scrollY = 0,1
local lines = {("Test"):rep(20).."!","The","Editor!"}
for i=1, 25 do lines[#lines+1] = "line "..(#lines+1) end
local w,h = gpu.getResolution()
h = h-1

local function redrawStatusBar()
	gpu.fill(1, h+1, w, 1, " ")
	gpu.set(1,h+1,"New File")
end

local function redrawScreen(i)
	i = i or 1
	term.setCursorBlink(false)
	for y=scrollY+i, scrollY+h do
		if not lines[y] then break end
		gpu.fill(1, y-scrollY, w, 1, " ")
		gpu.set(1,y-scrollY,(lines[y] or ""):sub(scrollX+1,scrollX+w))
	end
end

local function getScreenCoords()
	return (col-scrollX),(line-scrollY)
end

local function isOnscreen(ncol,nline)
	local x,y = ((ncol-scrollX)),((nline-scrollY))
	return (x > 0 and x <= w) and (y > 0 and y <= h)
end

local function makeCursorOnscreen()
	local x, y = (col-scrollX),(line-scrollY)
	local dirty = false
	if x<1 then
		scrollX = x+scrollX-1
		dirty = true
	elseif x>w then
		scrollX = scrollX+(x-w)
		dirty = true
	end
	
	if y<1 then
		scrollY = y+scrollY-1
		dirty = true
	elseif y>h then
		scrollY = scrollY+(y-h)
		dirty = true
	end
	if dirty then
		term.clear()
		redrawScreen()
	end
end

local function redraw()
	makeCursorOnscreen()
	redrawStatusBar()
	term.setCursor((col-scrollX),(line-scrollY))
	term.setCursorBlink(true)
end

local function insert(s)
	term.setCursorBlink(false)
	local x,y = getScreenCoords()
	gpu.copy(x,y,w,1,#s,0)
	gpu.set(x,y,s)
	if col > 1 then
		lines[line] = lines[line]:sub(1,col-1)..s..lines[line]:sub(col)
	else
		lines[line] = s..lines[line]
	end
	col = col+#s
	if not isOnscreen(col,line) then
		gpu.copy(1,1,w,h,-#s,0)
		scrollX = scrollX+#s
	end
	redraw()
end

local function delete()
	term.setCursorBlink(false)
	if col > 1 then
		local x,y = getScreenCoords()
		gpu.copy(x,y,w,1,-1,0)
		gpu.set(x+w,y," ")
		lines[line] = lines[line]:sub(1,col-2)..lines[line]:sub(col)
		col = col-1
	elseif line > 1 then
		local x,y = getScreenCoords()
		gpu.copy(1,y+1,w,h-y-1,0,-1)
		gpu.fill(1,y+h,w,1," ")
		line = line-1
		local l = lines[line+1]
		col = #lines[line]+1
		lines[line] = lines[line]..l
		gpu.set(1,y-1,lines[line])
		table.remove(lines,line+1)
	end
	redraw()
end

local function newline()
	term.setCursorBlink(false)
	local x,y = getScreenCoords()
	gpu.copy(1,y+1,w,h-y-1,0,1)
	gpu.fill(1,y,w,2," ")
	if col > 1 then
		local l = lines[line]
		lines[line] = l:sub(1,col-1)
		table.insert(lines,line+1,l:sub(col))
		line = line+1
		col = 1
		
		gpu.set(1,y,lines[line-1])
		gpu.set(1,y+1,lines[line])
	else
		table.insert(lines,line+1,lines[line])
		lines[line] = ""
		line = line+1
		col = 1
		gpu.set(1,y+1,lines[line])
	end
	redraw()
end

redrawScreen()
redraw()
while true do
	local sig,a,b,c,d,e,f,g = computer.pullSignal()
	if sig == "key_down" then
		if keyboard.isControl(b) then
			if c == keyboard.keys.left then
				col = col-1
				if col < 1 then
					if line > 1 then
						line = math.max(math.min(line-1,#lines),1)
						col = #lines[line]+1
					else
						col = col+1
					end
				end
				redraw()
			elseif c == keyboard.keys.right then
				col = col+1
				if col > #lines[line]+1 then
					if #lines > line then
						line = math.max(math.min(line+1,#lines),1)
						col = 1
					else
						col = col-1
					end
				end
				redraw()
			elseif c == keyboard.keys.up then
				line = math.max(math.min(line-1,#lines),1)
				col = math.min(col,#lines[line]+1)
				redraw()
			elseif c == keyboard.keys.down then
				line = math.max(math.min(line+1,#lines),1)
				col = math.min(col,#lines[line]+1)
				redraw()
			elseif c == keyboard.keys.back then
				delete()
			elseif c == keyboard.keys.enter then
				newline()
			end
		else
			insert(string.char(b))
		end
	end
end
