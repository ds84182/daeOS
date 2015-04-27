local term = require "term"
local filesystem = require "filesystem"
local ipc = require "ipc"

local mode = ks and "kernelmode" or "usermode"
local info = {}
local bgproc = {}

local function split(str,by)
	assert(type(str) == "string",type(str))
	local pt = {}
	for p in str:gmatch("[^"..by.."]+") do
		pt[#pt+1] = p
	end
	return pt
end

local history = {}

local stdin_handler, stdout_handler, stderr_handler = ps.getSTDIN(),ps.getSTDOUT(),ps.getSTDERR()

if not stdin_handler then
	function stdin_handler(mode)
		if mode == "*l" then
			return term.read()
		end
	end
end

if not stdout_handler then
	function stdout_handler(str)
		term.write(str)
	end
end

if not stderr_handler then
	function stderr_handler(str)
		term.write(str)
	end
end

if ps.getEnv("PWD") == "" then
	ps.setEnv("PWD","/")
end

if ps.getEnv("PATH") == "" then
	ps.setEnv("PATH","/bin/?.lua")
end

local function findInPath(command)
	if command:sub(1,2) == "./" or command:sub(1,3) == "../" or command:sub(1,1) == "/" then
		--is path--
		local nd
		if command:sub(1,1) == "/" then
			nd = command
		else
			nd = filesystem.combine(ps.getEnv("PWD").."/"..command)
		end
		
		if filesystem.exists(nd) and not filesystem.isDirectory(nd) then
			return nd
		end
		
		nd = nd..".lua"
		
		if filesystem.exists(nd) and not filesystem.isDirectory(nd) then
			return nd
		end
	end
	local pathEntry = split(ps.getEnv("PATH"),";")
	for i, v in pairs(pathEntry) do
		v = v:gsub("?",command):gsub("$([A-Za-z0-9_])+",function(var)
			return ps.getEnv(var)
		end)
		if filesystem.exists(v) and not filesystem.isDirectory(v) then
			return v
		end
	end
end

local exitLoop = false

local function execute(args,stdin,stdout,death)
	local exec = table.remove(args,1)
	args[0] = exec
	
	if exec == "exit" then
		exitLoop = true
		return true
	elseif exec == "cd" then
		local nd
		if args[1]:sub(1,1) == "/" then
			nd = args[1]
		else
			nd = filesystem.combine(ps.getEnv("PWD").."/"..args[1])
		end
		if not filesystem.exists(nd) then
			term.write("no such file or directory\n")
		elseif not filesystem.isDirectory(nd) then
			term.write("not a directory\n")
		else
			ps.setEnv("PWD",nd)
		end
	else
		local path = findInPath(exec)
		if not path then
			term.write("File does not exist\n")
		else
			local pid, err = ps.spawn(filesystem.read(path), exec, args, ps.isKernelMode(),
				stdin or stdin_handler,
				stdout or stdout_handler,
				stderr_handler)
		
			if pid then
				local sig, chld = computer.pullSignal()
				while sig ~= "child_death" and chld ~= pid do
					sig, chld = computer.pullSignal()
				end
				term.write("death\n")
				ps.getInfo(pid, info)
				if not info.peaceful then
					term.write(info.error.."\n")
				end
				ps.remove(pid)
				if death then death() end
				return info.peaceful, info.ret or info.error
			else
				term.write(err.."\n")
				if death then death() end
				return false, info.error
			end
		end
	end
end

local function executeBG(args,stdin,stdout)
	stdin = stdin or stdin_handler
	stdout = stdout or stdout_handler
	local exec = table.remove(args,1)
	args[0] = exec
	
	if exec == "exit" then
		exitLoop = true
		return true
	elseif exec == "cd" then
		local nd
		if args[1]:sub(1,1) == "/" then
			nd = args[1]
		else
			nd = filesystem.combine(ps.getEnv("PWD").."/"..args[1])
		end
		if not filesystem.exists(nd) then
			term.write("no such file or directory\n")
		elseif not filesystem.isDirectory(nd) then
			term.write("not a directory\n")
		else
			ps.setEnv("PWD",nd)
		end
	else
		local path = findInPath(exec)
		if not path then
			term.write("File does not exist\n")
		else
			local pid, err = ps.spawn(filesystem.read(path), exec, args, ps.isKernelMode(),
				stdin,
				stdout,
				stderr_handler)
		
			if pid then
				return pid
			else
				term.write(err.."\n")
				return nil, info.error
			end
		end
	end
end

local function makePipe()
	local buffer = ipc.new()
	local close = false
	local write = function(data)
		--buffer:lock()
		--term.write("PUT "..data)
		buffer:pushTop(data)
		buffer:notifyAll()
		--buffer:unlock()
	end
	local read = function(n)
		--term.write("READ "..n.."\n")
		if n == "*l" then
			--read until line--
			local b = buffer:pull()
			local s = ""
			while true do
				while not b do
					if close then
						return #s > 1 and s or nil
					else
						buffer:wait()
					end
					b = buffer:pull()
				end
				if not b:find("\n") then
					s = s..b
				else
					local p = b:find("\n")
					s = s..b:sub(1,p-1)
					buffer:push(b:sub(p+1))
					return s
				end
				b = buffer:pull()
			end
		elseif type(n) == "number" then
			--term.write("ATTEMPT FIRST PULL\n")
			local b = buffer:pull()
			local buf = ""
			while true do
				while not b do
					if close then
						return #buf > 1 and buf or nil
					else
						--term.write("WAIT\n")
						buffer:wait()
					end
					--term.write("ATTEMPT PULL\n")
					b = buffer:pull()
				end
				if #buf+#b == n then
					return buf..b
				elseif #buf+#b > n then
					local o = n-(#buf+#b)
					buffer:push(b:sub(o+1))
					return buf..b:sub(1,o)
				else
					buf = buf..b
				end
				b = buffer:pull()
			end
		end
	end
	return read, write, function() close = true buffer:notifyAll() end
end

local function process(cmdline)
	local commands = {}
	local args = {}
	local i = 1
	
	while i <= #cmdline do
		local c = cmdline:sub(i,i)
		if c == "\"" or c == "'" then
			local ending = c
			i = i+1
			c = cmdline:sub(i,i)
			local str = {}
			while c ~= ending do
				str[#str+1] = c
				i = i+1
				c = cmdline:sub(i,i)
			end
			args[#args+1] = table.concat(str)
		elseif c == "|" then
			commands[#commands+1] = {"pipe", args}
			--term.write("cmd pipe: "..table.concat(args,", ").."\n")
			args = {}
		elseif c == ";" then
			commands[#commands+1] = {"none", args}
			--term.write("cmd none: "..table.concat(args,", ").."\n")
			args = {}
		elseif c == "&" then
			commands[#commands+1] = {"concurrent", args}
			--term.write("cmd concurrent: "..table.concat(args,", ").."\n")
			args = {}
		elseif c == " " or c == "\t" or c == "\n" then
		else
			local id = {c}
			i = i+1
			c = cmdline:sub(i,i)
			while c ~= " " and c ~= "\t" and c ~= "\n" and c ~= ";" and c ~= "|" and c ~= "&" and i <= #cmdline do
				if c == "\\" then
					i = i+1
					id[#id+1] = cmdline:sub(i,i)
				else
					id[#id+1] = c
				end
				i = i+1
				c = cmdline:sub(i,i)
			end
			if i <= #cmdline then
				i = i-1
			end
			args[#args+1] = table.concat(id)
		end
		i = i+1
	end
	commands[#commands+1] = {"none", args}
	--term.write("cmd none last: "..table.concat(args,", ").."\n")
	
	local nextCommand = 1
	
	local function processCommand(i,stdin)
		local command = commands[i]
		nextCommand = nextCommand+1
		--term.write("cmd "..command[1]..": "..table.concat(command[2],", ").."\n")
		if command[1] == "pipe" then
			local stdout_read,stdout_write,stdout_close = makePipe()
			local pids = table.pack(processCommand(i+1,stdout_read))
			
			local epid = executeBG(command[2],stdin,stdout_write)
			
			--[[ps.getInfo(epid, info)
			if info.peaceful == nil then
				local sig, chld = computer.pullSignal()
				while sig ~= "child_death" and chld ~= epid do
					sig, chld = computer.pullSignal()
				end
				ps.getInfo(epid, info)
			end
			ps.remove(epid)
			stdout_close()
			if not info.peaceful then
				term.write(info.error.."\n")
				return nil
			end]]
			
			return {epid, stdout_close}, table.unpack(pids)
		elseif command[1] == "none" then
			return executeBG(command[2],stdin,stdout)
		elseif command[1] == "concurrent" then
			return executeBG(command[2],stdin,stdout)
		end
	end
	
	while nextCommand <= #commands do
		local typ = commands[nextCommand][1]
		local pids = table.pack(processCommand(nextCommand))
		if not pids then break end
		local pid = pids[1]
		if typ == "none" then
			ps.getInfo(pid, info)
			if info.peaceful == nil then
				local sig, chld = computer.pullSignal()
				while sig ~= "child_death" and chld ~= pid do
					sig, chld = computer.pullSignal()
				end
				ps.getInfo(pid, info)
			end
			ps.remove(pid)
			if not info.peaceful then
				term.write(info.error.."\n")
				break
			end
		elseif typ == "pipe" then
			for i, v in ipairs(pids) do
				local pid
				if type(v) == "table" then
					--term.write(v[1].."\n")
					pid = v[1]
				else
					--term.write(v.."\n")
					pid = v
				end
				
				ps.getInfo(pid, info)
				if info.peaceful == nil then
					local sig, chld = computer.pullSignal()
					while sig ~= "child_death" and chld ~= pid do
						sig, chld = computer.pullSignal()
					end
					ps.getInfo(pid, info)
				end
				ps.remove(pid)
				if not info.peaceful then
					term.write(info.error.."\n")
					break
				end
				if type(v) == "table" then
					v[2]()
				end
			end
			--term.write("pipe args finished.\n")
		else
			term.write("Background process "..pid.." started\n")
			bgproc[pid] = true
		end
	end
end

local arguments = table.pack(...)
if arguments[1] then
	return process(table.concat(arguments," "))
end

while not exitLoop do
	term.write(mode..":"..ps.getEnv("PWD").."# ")
	local cmdline = term.read(history)
	if cmdline then
		if cmdline ~= "\n" then
			process(cmdline)
		end
	else
		break
	end
	for i, v in pairs(bgproc) do
		ps.getInfo(i,info)
		if info.status == "dead" then
			term.write("Background process "..i.." finished with "..(info.peaceful and "no error" or "errors: "..info.error).."\n")
			bgproc[i] = nil
			ps.remove(i)
		end
	end
end
