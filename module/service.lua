--service module: run things in daemons on startup--

local service = {}

--read /svc/autostart.conf--
local filesystem = require "filesystem"
local ipc = require "ipc"

local suc, autostart = pcall(function()
	return assert(load(filesystem.read("/svc/autostart.conf")))()
end)

local services = {}
local returnIPC = ipc.new()
local servicepid, servicesigQ = ps.spawn([[
	local returnIPC,services,autostart,service = ...
	local ipc = require "ipc"
	
	local pidToServiceName = {}
	for i, v in pairs(autostart) do
		local s,e = service.startNonBlock(i,table.unpack(v))
	end
	while true do
		local sig = table.pack(computer.pullSignal())
		if sig[1] == "spawn" then
			local ret = table.pack(ps.spawn(table.unpack(sig,3)))
			pidToServiceName[ret[1] ] = sig[2]
			services[sig[2] ].pid = ret[1]
			services[sig[2] ].err = ret[2]
			ipc.notify(returnIPC)
		elseif sig[1] == "child_death" and pidToServiceName[sig[2] ] then
			services[pidToServiceName[sig[2] ] ].log_out.close()
			services[pidToServiceName[sig[2] ] ].log_err.close()
			services[pidToServiceName[sig[2] ] ] = nil
			ps.remove(sig[2])
		end
	end
]],"service_spawner",{returnIPC,services,autostart,service},true)

function service.start(name,...)
	--starts the service in a new process--
	if not ps.isKernelMode() then
		return false, "permission denied"
	end
	
	if services[name] then
		return false, "service already running"
	end
	
	local log_out = filesystem.open("/tmp/service/"..name.."_out","w")
	local log_err = filesystem.open("/tmp/service/"..name.."_err","w")
	
	local sipc = ipc.new()
	
	services[name] = {ipc=sipc,log_out=log_out,log_err=log_err}
	
	local vars = {SERVICE_IPC=tostring(sipc)}
	servicesigQ[#servicesigQ+1] = {"spawn",name,filesystem.read("/svc/"..name..".lua"),name.."d",table.pack(...),true,nil,log_out.write,log_err.write,vars}
	ipc.wait(returnIPC)
	if not services[name].pid then
		return nil, services[name].err
	end
	
	return services[name].pid
end

function service.startNonBlock(name,...)
	--starts the service in a new process, nonblocking--
	if not ps.isKernelMode() then
		return false, "permission denied"
	end
	
	if services[name] then
		return false, "service already running"
	end
	
	local log_out = filesystem.open("/tmp/service/"..name.."_out","w")
	local log_err = filesystem.open("/tmp/service/"..name.."_err","w")
	
	local sipc = ipc.new()
	
	services[name] = {ipc=sipc,log_out=log_out,log_err=log_err}
	
	local vars = {SERVICE_IPC=tostring(sipc)}
	servicesigQ[#servicesigQ+1] = {"spawn",name,filesystem.read("/svc/"..name..".lua"),name.."d",table.pack(...),true,nil,log_out.write,log_err.write,vars}
end

function service.forceStop(name)
	if not ps.isKernelMode() then
		return false, "permission denied"
	end
	
	if not services[name] then
		return false, "service not running"
	end
	
	ps.remove(services[name].pid)
	services[name] = nil
	return true
end

function service.postIPC(name, ...)
	if not ps.isKernelMode() then
		return false, "permission denied"
	end
	
	if not services[name] then
		return false, "service not running"
	end
	
	ipc.push(services[name].ipc,table.pack(...))
	ipc.notify(services[name].ipc)
	return true
end

function service.postSignal(name, ...)
	if not ps.isKernelMode() then
		return false, "permission denied"
	end
	
	if not services[name] then
		return false, "service not running"
	end
	
	ps.pushSignalTo(services[name].pid,...)
	return true
end

function service.stop(name)
	return service.postSignal(name, "service_stop")
end

ks.exposeAPI("service",service)

if not suc then
	error(autostart)
end
