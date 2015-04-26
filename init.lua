local err
local s,e = xpcall(function()
local bootfs = component.proxy(computer.getBootAddress())

function os.sleep(timeout)
	checkArg(1, timeout, "number", "nil")
	local deadline = computer.uptime() + (timeout or 0)
	repeat
		computer.pullSignal(deadline - computer.uptime())
	until computer.uptime() >= deadline
end

--sandbox.lua generation code--
if generateSandbox then
	local function deepindex(src,name,destname,fh,tabs)
		tabs = tabs or ""
		bootfs.write(fh,tabs..(destname and destname.." =" or "return").." {\n")
		tabs = tabs.."\t"
		for i, v in pairs(src) do
			if type(v) == "table" then
				if v ~= src then
					deepindex(v,name.."."..i,i,fh,tabs)
					bootfs.write(fh,",\n")
				end
			else
				bootfs.write(fh,tabs..i.." = "..name.."."..i..",\n")
			end
		end
		bootfs.write(fh,tabs:sub(1,-2).."}")
	end

	local fh = bootfs.open("sandbox.lua","w")
	deepindex(_G, "_G", nil, fh)
	bootfs.close(fh)
end

--hey later me, don't remove these functions because they are supposed to be secure functions (only accessing bootfs incase things
--get comprimised later)
local function loadfile(file,name)
	local fh = bootfs.open(file)
	local sbsrc = {}
	local sbseg = bootfs.read(fh, math.huge)
	while sbseg do
		sbsrc[#sbsrc+1] = sbseg
		sbseg = bootfs.read(fh, math.huge)
	end
	return load(table.concat(sbsrc,""),name and "="..name or nil)
end

local function readfile(file)
	local fh = bootfs.open(file)
	local sbsrc = {}
	local sbseg = bootfs.read(fh, math.huge)
	while sbseg do
		sbsrc[#sbsrc+1] = sbseg
		sbseg = bootfs.read(fh, math.huge)
	end
	return table.concat(sbsrc,"")
end

local defaultConfig = {}
defaultConfig.separateEnvs = false --set this to false to save memory but reduce security (saves 1k per usermode process)
defaultConfig.kernelShell = false
defaultConfig.virtualMachine = false

defaultConfig.hal = {}
defaultConfig.hal.blacklist = {"eeprom","filesystem","debug"}
defaultConfig.hal.methodBlacklist = {} --sub table for each component type

defaultConfig.filesystem = {}
defaultConfig.filesystem.allowed = --defines locations where usermode processes can modify files
{"/home","/usr","/mnt","/dev/stdin","/dev/stdout","/dev/stderr","/dev/beep","/dev/tape","/tmp"}
defaultConfig.filesystem.disallowed =
{"/tmp/service"}

defaultConfig.security = {}
defaultConfig.security.password = nil

--TODO: Users with permisisons--

config = defaultConfig
if bootfs.exists("config.lua") then
	assert(load(readfile("config.lua","=config")))()
end

if defaultConfig.virtualMachine then
	assert(load(readfile("vm/vm52.lua","=vm")))()
	assert(load(readfile("vm/bytecode.lua","=bytecode")))()
end

--everything is separated into kernelspace and userspace--
--userspace does not have access to raw hardware, they have to talk to the kernel for things like that--
--both spaces live in the same processspace--

ks = {} --kernelspace
us = {}	--userspace
ps = {} --processspace

local function yieldingPullSignal(timeout)
	local deadline = computer.uptime() +
		(type(timeout) == "number" and timeout or math.huge)
	repeat
		local signal = table.pack(coroutine.yield(deadline - computer.uptime()))
		if signal.n > 0 then
			return table.unpack(signal, 1, signal.n)
		end
	until computer.uptime() >= deadline
end

---- BEGIN PROCESS SPACE FUNCTIONS ----

do
	local pullSignal = computer.pullSignal
	computer.pullSignal = yieldingPullSignal
	computer.oldPullSignal = pullSignal
	local currentProcess = nil
	local processes = {}
	local nextPID = 1
	local nextSignalFilter = 1
	local signalFilters = {}
	local signalFiltersByName = {}

	function ps.isKernelMode()
		return currentProcess == nil or processes[currentProcess].kernelspace
	end
	
	function ps.installSignalFilter(name,filter)
		if not ps.isKernelMode() then
			error("Permission denied")
		end
		signalFilters[nextSignalFilter] = filter
		signalFiltersByName[name] = nextSignalFilter
		nextSignalFilter = nextSignalFilter+1
	end
	
	function ps.uninstallSignalFilter(name)
		if not ps.isKernelMode() then
			error("Permission denied")
		end
		signalFilters[signalFiltersByName[name]] = nil
		signalFiltersByName[name] = nil
	end
	
	function ps.isSignalFilterInstalled(name)
		return signalFiltersByName[name] ~= nil
	end

	function ps.spawn(source, name, args, kernelspace, stdin, stdout, stderr, vars)
		checkArg(1,source,"string")
		checkArg(2,name,"string","nil")
		checkArg(3,args,"table","nil")
		checkArg(4,kernelspace,"boolean","nil")
		checkArg(5,stdin,"function","table","nil")
		checkArg(6,stdout,"function","table","nil")
		checkArg(7,stderr,"function","table","nil")
		checkArg(8,vars,"table","nil")
		
		if kernelspace and not ps.isKernelMode() then
			error("Only kernelspace processes can spawn other kernelspace processes")
		end
		local globals = kernelspace and ks.globals or ks.getNewUserSpaceGlobals()
		name = name or "process_"..nextPID
		local func, err = load(source, "="..name, nil, globals)
		if not func then return nil, err end
		
		if vm--[[ and name == "term"]] then
			local bc = bytecode.load(string.dump(func))
			func = function(...)
				--local term = globals.require "term"
				return vm.lua52.run(bc, {...}, nil, globals, function(o,a,b,c,pc,on)
					--term.write(pc.."\t"..o.." ("..on..") "..a.." "..tostring(b).." "..tostring(c).."\n")
				end)
			end
		end
	
		local thread = coroutine.create(func)
		local id = nextPID
		nextPID = nextPID+1
		vars = vars or (currentProcess and processes[currentProcess].variables or nil)
		if vars then
			--copy
			local ov = vars
			vars = {}
			for i, v in pairs(ov) do
				vars[tostring(i)] = tostring(v)
			end
		else
			vars = {}
		end
		
		local object = {
			thread = thread,
			globals = globals,
			name = name,
			args = args or {},
			args_stale = false,
			kernelspace = kernelspace,
			id = id,
			wait = 0,
			last = computer.uptime(),
			error = nil,
			signalQueue = {},
			parent = currentProcess,
			peaceful = nil,
			resumeFilter = nil,
			stdin = stdin or (currentProcess and processes[currentProcess].stdin or nil),
			stdout = stdout or (currentProcess and processes[currentProcess].stdout or nil),
			stderr = stderr or (currentProcess and processes[currentProcess].stderr or nil),
			variables = vars --environmental variables
		}
		processes[id] = object
		return id, object.signalQueue
	end
	
	local _EMPTY = {}
	
	local function matchesResumeFilter(object, signal)
		for i, v in pairs(object.resumeFilter or _EMPTY) do
			if signal[1] == v then
				object.resumeFilter = nil
				return true
			end
		end
		return false
	end

	local function resume(id, object, args)
		currentProcess = id
		local r = table.pack(coroutine.resume(object.thread, table.unpack(args or _EMPTY)))
		currentProcess = nil
		local s = table.remove(r,1)
		if (not s) or coroutine.status(object.thread) ~= "suspended" then
			object.peaceful = s
			object.error = s and "process has finished execution" or debug.traceback(object.thread,r[1])
			if s then
				r.n = r.n-1
				object.ret = r
			end
			return
		end
		local t = type(r[1])
		if t == "string" then
			--syscall!
			if ks.syscall[r[1]] then
				local ret = {ks.syscall[r[1]](table.unpack(r,2,#r))}
				table.insert(object.signalQueue, 1, ret) --insert as signal
			elseif r[1] == "pause" then
				object.resumeFilter = {table.unpack(r,2,#r)}
				return
			else
				object.error = debug.traceback(object.thread,"Unknown syscall")
				return
			end
			return 0
		elseif t ~= "number" and r[1] ~= nil then
			object.error = debug.traceback(object.thread,"number or string expecfted, got "..type(r[1]))
			return
		end
		return r[1]
	end

	function ps.run()
		ps.run = nil
		--enter a loop that runs processes--
		local minWait
		while true do
			minWait = math.huge
		
			--execute processes--
			for i, v in pairs(processes) do
				if v.wait then --nil wait will pause the process
					local timediff = computer.uptime()-v.last
					if timediff >= v.wait or v.signalQueue[1] then
						--resume process!--
						v.wait = resume(i, v, v.args_stale and table.remove(v.signalQueue, 1) or v.args)
						v.args_stale = true
					else
						v.wait = v.wait-timediff
					end
					minWait = math.min(minWait, v.wait or 0)
					v.last = computer.uptime()
					
					if v.error then
						if (not v.peaceful) and v.parent == nil then
							local term
							if require then
								term = require "term"
							end
							if term then
								--error(tostring(v.error),0)
								term.write(v.name.." "..tostring(v.error).."\n")
							end
						end
						local parent = v.parent and processes[v.parent] or nil
						if parent then
							parent.signalQueue[#parent.signalQueue+1] = {"child_death",i}
						end
						v.wait = nil
					end
				end
			end
		
			--very end...--
			--test to see if any processes have pending signals--
			local pps = false
			for i, v in pairs(processes) do
				if v.signalQueue[1] then
					pps = true
					break
				end
			end
			local KSSQ = table.remove(ks.kernelSpaceSignalQueue, 1)
			local USSQ = table.remove(ks.userSpaceSignalQueue, 1)
			local signal = {pullSignal((pps or KSSQ or USSQ) and 0 or minWait)}
			--if signal[1] then error(signal[1]) end
			for i, v in pairs(processes) do
				--signalQueue proccessing
				if v.kernelspace and KSSQ then
					if matchesResumeFilter(v,KSSQ) then
						table.insert(v.signalQueue,1,KSSQ)
						v.wait = 0
					else
						v.signalQueue[#v.signalQueue+1] = KSSQ
					end
				end
				if (not v.kernelspace) and USSQ then
					if matchesResumeFilter(v,USSQ) then
						table.insert(v.signalQueue,1,USSQ)
						v.wait = 0
					else
						v.signalQueue[#v.signalQueue+1] = USSQ
					end
				end
				if signal[1] then
					local restrict = false
					
					for _,filter in pairs(signalFilters) do
						if not filter(v,table.unpack(signal)) then
							restrict = true
							break
						end
					end
					if not restrict then
						if matchesResumeFilter(v,signal) then
							table.insert(v.signalQueue,1,signal)
							v.wait = 0
						else
							v.signalQueue[#v.signalQueue+1] = signal
						end
					end
				end
			end
		end
	end

	function ps.getInfo(id,info)
		checkArg(1,id,"number")
		checkArg(2,info,"table","nil")
		if not processes[id] then
			return nil, "No such process"
		end
		info = info or {}
		local proc = processes[id]
		info.name = proc.name
		info.kernelspace = proc.kernelspace
		info.error = proc.error
		info.status = coroutine.status(proc.thread)
		info.parent = proc.parent
		info.peaceful = proc.peaceful
		return info
	end
	
	function ps.remove(id)
		--removes a process--
		checkArg(1,id,"number")
		if not processes[id] then
			return false, "No such process"
		end
		local proc = processes[id]
		if proc.kernelspace and not ps.isKernelMode() then
			return false, "Permission denied"
		end
		processes[id] = nil
	end
	
	function ps.getCurrentProcess()
		return currentProcess
	end
	
	function ps.getSTDIN()
		return processes[currentProcess].stdin
	end
	
	function ps.getSTDOUT()
		return processes[currentProcess].stdout
	end
	
	function ps.getSTDERR()
		return processes[currentProcess].stderr
	end
	
	function ps.getArguments()
		return processes[currentProcess].args
	end
	
	function ps.getEnv(name)
		checkArg(1,name,"string")
		return processes[currentProcess].variables[tostring(name)] or ""
	end
	
	function ps.setEnv(name,value)
		checkArg(1,name,"string")
		checkArg(2,value,"string")
		processes[currentProcess].variables[tostring(name)] = tostring(value)
	end
	
	function ps.listEnv(env)
		checkArg(1,env,"table","nil")
		env = env or {}
		for name, value in pairs(processes[currentProcess].variables) do
			env[name] = value
		end
		return env
	end
	
	function ps.pushProcessSignal(...)
		local proc = processes[currentProcess]
		proc.signalQueue[#proc.signalQueue+1] = {...}
	end
	
	function ps.yield(...)
		local proc = processes[currentProcess]
		table.insert(proc.signalQueue,{...})
		coroutine.yield(0)
	end
	
	function ps.pushSignalTo(id,...)
		checkArg(1,id,"number")
		if not processes[id] then
			return nil, "No such process"
		end
		if not ps.isKernelMode() then
			return false, "Permission denied"
		end
		local proc = processes[id]
		proc.signalQueue[#proc.signalQueue+1] = {...}
	end
	
	function ps.listProcesses(pl)
		checkArg(1,pl,"table","nil")
		--clear the table
		pl = pl or {}
		for i, v in ipairs(pl) do
			pl[i] = nil
		end
		for i, v in pairs(processes) do
			pl[#pl+1] = i
		end
		table.sort(pl)
		return pl
	end
	
	function ps.pause(id,...)
		local n = select("#",...)
		if not id then
			if n == 0 then
				coroutine.yield()
			else
				coroutine.yield("pause",...)
			end
		else
			if not processes[id] then
				return nil, "No such process"
			end
			if not ps.isKernelMode() then
				return false, "Permission denied"
			end
			processes[id].wait = nil
		end
	end
	
	function ps.resume(id)
		checkArg(1,id,"number")
		if not processes[id] then
			return nil, "No such process"
		end
		if not ps.isKernelMode() then
			return false, "Permission denied"
		end
		processes[id].wait = 0
	end
end

---- BEGIN KERNEL SPACE FUNCTIONS ----

do

	ks.globals = _ENV

	ks.kernelSpaceSignalQueue = {}
	ks.userSpaceSignalQueue = {}

	function ks.globals.pushKernelSignal(...)
		ks.kernelSpaceSignalQueue[#ks.kernelSpaceSignalQueue+1] = {...}
	end

	function ks.globals.pushUserSignal(...)
		ks.userSpaceSignalQueue[#ks.userSpaceSignalQueue+1] = {...}
	end

	function ks.protectTable(t,noread,nowrite)
		local tableprot = {}
		tableprot.read = not noread
		tableprot.write = not nowrite
		tableprot.protected = {}
		tableprot.real = t
	
		setmetatable(tableprot.protected, {
			__metatable = function()
				error("Cannot access metatable of protected table")
			end,
			__index = function(_,i)
				if tableprot.read then
					return t[i]
				end
				error("Cannot read table: Access Denied")
			end,
			__newindex = function(_,i,v)
				if tableprot.write then
					t[i] = v
				end
				error("Cannot write table: Access Denied")
			end,
		})
	
		return tableprot
	end

	function ks.rawTable(t)
		return setmetatable({},{
			__index = function(_,i)
				return rawget(t,i)
			end,
			__newindex = function(_,i,v)
				rawset(t,i,v)
			end
		})
	end
	
	function print(...)
		local stdout = ps.getSTDOUT()
		
		if stdout then
			local a = table.pack(...)
			for i=1, a.n do
				a[i] = tostring(a[i])
			end
			return stdout(table.concat(a,"  ").."\n")
		else
			return false, "no stdout"
		end
	end
	
	function printErr(...)
		local stderr = ps.getSTDERR()
		
		if stderr then
			local a = table.pack(...)
			for i=1, a.n do
				a[i] = tostring(a[i])
			end
			return stderr(table.concat(a,"  ").."\n")
		else
			return false, "no stderr"
		end
	end
	
	io = {}
	
	function io.write(str)
		local stdout = ps.getSTDOUT()
		
		if stdout then
			return stdout(str)
		else
			return false, "no stdout"
		end
	end
	
	function io.read(mode)
		local stdin = ps.getSTDIN()
		
		if stdin then
			return stdin(mode or "*l")
		else
			return nil, "no stdin"
		end
	end
	
	local function setupUserSpaceGlobals(usg)
		usg._G = usg
		usg.computer.pushSignal = ks.pushUserSignal
		usg.ps = ks.protectTable(ps,false,true).protected
		usg.us = ks.protectTable(us,false,true).protected
		usg.computer.shutdown = function(...) coroutine.yield("shutdown",...) end
		usg.component = nil
		usg.require = function(name)
			return coroutine.yield("getapi",name)
		end
		usg.print = print
		usg.printErr = printErr
		usg.io = {write=io.write,read=io.read}
	end

	function ks.getNewUserSpaceGlobals()
		if config.separateEnvs then
			local usg
			usg = assert(loadfile("sandbox.lua"))()

			setupUserSpaceGlobals(usg)
			return usg
		else
			if not ks.usg then
				local usg
				usg = assert(loadfile("sandbox.lua"))()

				setupUserSpaceGlobals(usg)
				ks.usg = usg
			end
			return ks.usg
		end
	end

	local exposedAPIs = {}
	local protectedAPIs = {}
	function ks.exposeAPI(name, api)
		exposedAPIs[name] = api
		protectedAPIs[name] = ks.protectTable(api, false, true)
	end

	function ks.getAPI(name)
		checkArg(1,name,"string")
		return exposedAPIs[name]
	end
	
	require = ks.getAPI

	function ks.getProtectedAPI(name)
		return (protectedAPIs[name] or {}).protected
	end

	local loadedModules = {}
	ks.modules = {}
	function ks.loadModule(module)
		if not loadedModules[module] then
			--load module from bootfs--
			ks.modules[module] = ks.modules[module] or {}
			loadedModules[module] = loadfile("module/"..module..".lua",module)() or true
			return "Module loaded successfully"
		else
			return "Module already loaded"
		end
	end

	function ks.getModule(module)
		return loadedModules[module]
	end
	
	--Kernel syscalls--
	
	ks.syscall = {}
	
	function ks.syscall.getapi(name)
		return ks.getProtectedAPI(name)
	end
	
	--load common modules--
	ks.loadModule "filesystem"
	ks.loadModule "hal"
	ks.loadModule "keyboard"
	ks.loadModule "term"
	ks.loadModule "text"
	ks.loadModule "ipc"
	ks.loadModule "security"
	ks.loadModule "service"
end

---- BEGIN USER SPACE FUNCTIONS ----

function us.syscall(name,...)
	checkArg(1,name,"string")
	return coroutine.yield(name,...)
end

---- PROCESS SPACE STARTUP ----

for address, componentType in component.list() do
	computer.pushSignal("component_added",address,componentType)
end

ps.spawn(ks.getAPI("filesystem").read("bin/shell.lua"),"shell", nil, defaultConfig.kernelShell)
ps.run()
end,function(e) err = debug.traceback(e,2) end)

if err then error(err,0) end
