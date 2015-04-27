--micro - text editor--
local arguments = table.pack(...)
local term = require "term"
local component = require "component"
local filesystem = require "filesystem"
local gpu = component.proxy(component.list("gpu")())

local buffer = {""}
local bufferName = "New buffer"
local bufferPath = nil
local changesSinceSave = false
local line = 1
local col = 1
local lineScroll = 0
local scroll = 0

local w, h = gpu.getResolution()

if arguments[1] then
	local path = arguments[1]
	if path:sub(1,1) ~= "/" then
		path = filesystem.fixPath(ps.getEnv("PWD").."/"..path)
	end
	local parent, name = path:match("^(.*)/([^/]-)$")
	bufferPath = path
	bufferName = name
	
	if filesystem.exists(path) then
		local fh, err = filesystem.open(path,"r")
		if not fh then
			ps.getSTDERR()(err)
			return
		end
		local line = 1
		while true do
			local buf = fh.read(512)
			if not buf then break end
			local s = buf:find("\n")
			local ls = 1
			if not s then
				buffer[line] = buffer[line]..buf
			else
				while s do
					buffer[line] = buffer[line]..buf:sub(ls,s-1)
					line = line+1
					buffer[line] = ""
					ls = s+1
					s = buf:find("\n",ls)
				end
				buffer[line] = buffer[line]..buf:sub(ls)
			end
		end
		fh.close()
	end
end

gpu.setForeground(0xFFFFFF)
gpu.setBackground(0x000000)
term.clear()

local function drawHeader()
	local bufferString = bufferName
	if changesSinceSave then bufferString = "*"..bufferString end
	term.setCursorBlink(false)
	term.setCursor(1,1)
	gpu.setForeground(0x000000)
	gpu.setBackground(0xFFFFFF)
	term.clearLine()
	term.write("  daeOS micro 0.1.0")
	term.setCursor(w-(#bufferString+2),1)
	term.write(bufferString)
	gpu.setForeground(0xFFFFFF)
	gpu.setBackground(0x000000)
	term.setCursor(col-lineScroll,line+2-scroll)
end

local function drawSubHeader(text)
	term.setCursorBlink(false)
	gpu.setForeground(0x000000)
	gpu.setBackground(0xCCCCCC)
	term.setCursor(1,2)
	term.clearLine()
	term.setCursor(3,2)
	term.write(text)
	gpu.setForeground(0xFFFFFF)
	gpu.setBackground(0x000000)
	term.setCursor(col-lineScroll,line+2-scroll)
end

drawHeader()
drawSubHeader("Press F1 for help")

local function redrawLine()
	term.setCursorBlink(false)
	gpu.fill(1, line+2-scroll, w, 1, " ")
	gpu.set(-lineScroll+1,line+2-scroll,buffer[line])
	term.setCursor(col-lineScroll,line+2-scroll)
end

local dialogNLines

local function drawDialog(lines)
	gpu.setForeground(0x000000)
	gpu.setBackground(0xCCCCCC)
	for y=1, #lines do
		gpu.fill(1, y+1, w, 1, " ")
		gpu.set(1,y+1,lines[y])
	end
	dialogNLines = #lines
end

local function closeDialog()
	gpu.setForeground(0xFFFFFF)
	gpu.setBackground(0x000000)
	local ol = line
	for y=1, dialogNLines do
		gpu.fill(1, y+1, w, 1, " ")
		if y > 1 then
			line = y-1+scroll
			if buffer[line] then
				redrawLine()
			end
		end
	end
	line = ol
end

local function refreshScroll()
	term.setCursorBlink(false)
	local doRefresh = false
	
	if col-lineScroll < 1 then
		lineScroll = col-1
		doRefresh = true
	elseif col-lineScroll >= w then
		lineScroll = col-w
		doRefresh = true
	end
	
	
	if line-scroll < 1 then
		scroll = line-1
		gpu.copy(1,3,w,h-1,0,1)
		doRefresh = true
	elseif line-scroll > h-2 then
		scroll = line-(h-2)
		gpu.copy(1,4,w,h,0,-1)
		doRefresh = true
	end
	
	if doRefresh then
		redrawLine()
	else
		term.setCursor(col-lineScroll,line+2-scroll)
	end
end

local function refreshScrollNoRedraw()
	if col-lineScroll < 1 then
		lineScroll = col-1
	elseif col-lineScroll >= w then
		lineScroll = col-w
	end
end

local function insert(s)
	if not buffer[line] then
		buffer[line] = ""
	end
	
	local lin = buffer[line]
	if col > #lin then
		buffer[line] = lin..s
	else
		buffer[line] = lin:sub(1,col-1)..s..lin:sub(col)
	end
	col = col+#s
	
	refreshScrollNoRedraw()
	redrawLine()
	
	changesSinceSave = true
	drawHeader()
end

local function save()
	drawDialog {
		"  Saving to:",
		"    "..bufferPath
	}
	
	local fh, e = filesystem.open(bufferPath, "w")
	if not fh then
		closeDialog()
		drawSubHeader("Error writing file "..bufferPath..": "..e)
		return
	end
	for i=1, #buffer do
		fh.write(buffer[i])
		fh.write("\n")
	end
	fh.close()
	
	changesSinceSave = false
	
	closeDialog()
	drawSubHeader("Press F1 for help")
	drawHeader()
end

local function saveAs()
	drawDialog {
		"  Please enter the path for the new file",
		"  > ",
		"  Relative to: "..ps.getEnv("PWD")
	}
	term.setCursor(5,3)
	local file = term.read(nil,false)
	file = file:sub(1,-2)
	if file:sub(1,1) ~= "/" then file = ps.getEnv("PWD")..file end
	local parent, name = file:match("^(.*)/([^/]-)$")
	if not filesystem.exists(parent) then
		closeDialog()
		drawSubHeader("Error writing file "..parent.."/"..name..": No such file or directory")
		return
	end
	bufferPath = file
	bufferName = name
	closeDialog()
	save()
end

--rerender entire view--
for i=1, h-2 do
	if not buffer[i] then break end
	line = i
	redrawLine()
end
line = 1
refreshScroll()
term.setCursorBlink(true)

computer.pullSignal(0) --eat first signal

local keyboard = require "keyboard"
local keys = keyboard.keys

while true do
	local signal, a, b, c, d, e = computer.pullSignal()
	
	if signal == "key_down" then
		term.setCursorBlink(false)
		
		if c == keys.f1 then
			gpu.setForeground(0x000000)
			gpu.setBackground(0xCCCCCC)
			local helpLines = {
				"",
				"  Micro Help",
				"  F1 - This Help Screen",
				"  Ctrl-x - Exit",
				"  Ctrl-s - Save",
				"  Ctrl-Shift-s - Save As",
				"",
				"  Press any key to close"
			}
			for i=2, h do
				term.setCursor(1,i)
				term.clearLine()
				if helpLines[i-1] then
					term.write(helpLines[i-1])
				end
			end
			while true do
				if computer.pullSignal() == "key_down" then
					break
				end
			end
			
			gpu.setForeground(0xFFFFFF)
			gpu.setBackground(0x000000)
			local oldLine = line
			for i=h, 3, -1 do
				term.setCursor(1,i)
				term.clearLine()
				if buffer[i-2+scroll] then
					line = i-2+scroll
					redrawLine()
				end
			end
			line = oldLine
			refreshScroll()
			drawSubHeader("Press F1 for help")
		elseif keyboard.isControlDown() then
			if c == keys.x then
				if not changesSinceSave then
					break
				else
					drawSubHeader("Save modified buffer? Y[es], N[o], or C[ancel].")
					local cancel = false
					while true do
						computer.pullSignal()
						if keyboard.isKeyDown(keys.y) then
							--save--
							break
						elseif keyboard.isKeyDown(keys.n) then
							break
						elseif keyboard.isKeyDown(keys.c) then
							cancel = true
							break
						end
					end
					if not cancel then break end
					drawSubHeader("Press F1 for help")
				end
			elseif c == keys.s then
				if (not bufferPath) or keyboard.isShiftDown() then
					saveAs()
				else
					save()
				end
			end
		else
			if b > 0x1F and b < 0x7F then
				insert(string.char(b))
			elseif c == keys.tab then
				insert("   ")
			elseif c == keys.enter then
				local lin = buffer[line]
				buffer[line] = lin:sub(1,col-1)
				refreshScrollNoRedraw()
				redrawLine()
				gpu.copy(1,line+3,w,h-1,0,1)
				line = line+1
				table.insert(buffer,line,lin:sub(col))
				col = 1
				if line-scroll > h-2 then
					scroll = line-(h-2)
					gpu.copy(1,4,w,h,0,-1)
				end
				redrawLine()
				changesSinceSave = true
				drawHeader()
			elseif c == keys.back then
				if col == 1 then
					if line > 1 then
						--merge previous line--
						local oll = #buffer[line-1]
						buffer[line-1] = buffer[line-1]..buffer[line]
						--remove--
						table.remove(buffer,line)
						--redraw--
						line = line-1
						col = oll+1
						if line-scroll < 1 then
							scroll = line-1
						else
							--shift everything up with gpu copy--
							gpu.copy(1,line+3,w,h,0,-1)
						end
						--redraw last line--
						local ll = line
						line = h-2+scroll
						if buffer[line] then
							redrawLine()
						else
							term.setCursor(1,line+2-scroll)
							term.clearLine()
						end
						line = ll
						--redraw this line--
						refreshScrollNoRedraw()
						redrawLine()
					end
				else
					local lin = buffer[line]
					buffer[line] = lin:sub(1,col-2)..lin:sub(col)
					col = col-1
					refreshScrollNoRedraw()
					redrawLine()
				end
				changesSinceSave = true
				drawHeader()
			elseif c == keys.left and col > 1 then
				col = col-1
				term.setCursor(col-lineScroll,line+2)
				refreshScroll()
			elseif c == keys.right and col < #buffer[line]+1 then
				col = col+1
				term.setCursor(col-lineScroll,line+2)
				refreshScroll()
			elseif c == keys.up and line > 1 then
				line = line-1
				col = math.min(col,#buffer[line]+1)
				refreshScroll()
			elseif c == keys.down and line < #buffer then
				line = line+1
				col = math.min(col,#buffer[line]+1)
				refreshScroll()
			elseif c == keys.home then
				col = 1
				refreshScroll()
			elseif c == keys["end"] then
				col = #buffer[line]+1
				refreshScroll()
			end
		end
		term.setCursorBlink(true)
	end
end

term.clear()
