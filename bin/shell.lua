local term = require "term"
local filesystem = require "filesystem"

local mode = ks and "kernelmode" or "usermode"
local info = {}

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

local function execute(args)
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
				stdin_handler,
				stdout_handler,
				stderr_handler)
		
			if pid then
				local sig, chld = computer.pullSignal()
				while sig ~= "child_death" and chld ~= pid do
					sig, chld = computer.pullSignal()
				end
				ps.getInfo(pid, info)
				if not info.peaceful then
					term.write(info.error.."\n")
				end
				ps.remove(pid)
				return info.peaceful, info.ret or info.error
			else
				term.write(err.."\n")
				return false, info.error
			end
		end
	end
end

local arguments = table.pack(...)
if arguments[1] then
	return execute(arguments)
end

while not exitLoop do
	term.write(mode..":"..ps.getEnv("PWD").."# ")
	local cmdline = term.read(history)
	if cmdline then
		local args = split(cmdline," \n")
		execute(args)
	else
		break
	end
end
