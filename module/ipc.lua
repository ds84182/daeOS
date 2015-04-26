--inter process communication module!--

local ipc = {}

local ipclets = setmetatable({},{__mode="k"})
local ipcid, ipcidsigQ

function ipc.new()
	local id = {}
	ipclets[id] = {lock=nil,lockDepth=0,waiting={},waitingForNotify={},data={}}
	return id
end

function ipc.findByName(sid)
	for i, v in pairs(ipclets) do
		if tostring(i) == sid then
			return i
		end
	end
	return nil, "ipclet not found"
end

function ipc.get(id)
	if ipclets[id].lock ~= ps.getCurrentProcess() then
		return nil, "ipc not locked"
	end
	return ipclets[id].data
end

function ipc.lock(id)
	local ipclet = ipclets[id]
	if ipclet.lock == ps.getCurrentProcess() then
		ipclet.lockDepth = ipclet.lockDepth+1
		return
	end
	
	if ipclet.lock or ipclet.waiting[1] then
		ipclet.waiting[#ipclet.waiting+1] = ps.getCurrentProcess()
		while ipclet.lock do --TODO: lock timeout
			local sig, iid = computer.pullSignal()
			if sig == "ipc_locked" and iid == id then
				return
			end
		end
	end
	ipclet.lock = ps.getCurrentProcess()
	ipclet.lockDepth = ipclet.lockDepth+1
end

function ipc.unlock(id)
	local ipclet = ipclets[id]
	ipclet.lockDepth = ipclet.lockDepth-1
	if ipclet.lockDepth == 0 then
		ipclet.lock = nil
	
		if ipclet.waiting[1] then
			local pid = table.remove(ipclet.waiting,1)
			ipcidsigQ[#ipcidsigQ+1] = {"ipc_signal",pid,id}
			ipclet.lock = pid
			ipclet.lockDepth = 1
			ps.yield()
		end
	end
end

function ipc.push(id, value)
	ipc.lock(id)
	local data = ipc.get(id)
	if not data.stackIndex then
		data.stackIndex = 1
	end
	data[data.stackIndex] = value
	data.stackIndex = data.stackIndex+1
	ipc.unlock(id)
end

function ipc.peek(id)
	ipc.lock(id)
	local data = ipc.get(id)
	if not data.stackIndex then
		data.stackIndex = 1
	end
	if data.stackIndex == 1 then ipc.unlock(id) return nil end
	local value = data[data.stackIndex-1]
	ipc.unlock(id)
	return value
end

function ipc.pull(id)
	ipc.lock(id)
	local data = ipc.get(id)
	if not data.stackIndex then
		data.stackIndex = 1
	end
	if data.stackIndex == 1 then ipc.unlock(id) return nil end
	data.stackIndex = data.stackIndex-1
	local value = data[data.stackIndex]
	ipc.unlock(id)
	return value
end

function ipc.getStackSize(id)
	ipc.lock(id)
	local data = ipc.get(id)
	if not data.stackIndex then
		data.stackIndex = 1
	end
	local value = data.stackIndex-1
	ipc.unlock(id)
	return value
end

function ipc.wait(id)
	local ipclet = ipclets[id]
	--waits for an ipc_signal--
	ipclet.waitingForNotify[#ipclet.waitingForNotify+1] = ps.getCurrentProcess()
	while true do --TODO: lock timeout
		local sig, iid = computer.pullSignal()
		if sig == "ipc_notify" and iid == id then
			return
		end
	end
end

function ipc.notify(id) --notify one--
	local ipclet = ipclets[id]
	if ipclet.waitingForNotify[1] then
		local pid = table.remove(ipclet.waitingForNotify,1)
		ipcidsigQ[#ipcidsigQ+1] = {"ipc_notify_signal",pid,id}
		ps.yield()
	end
end

function ipc.notifyAll(id)
	local ipclet = ipclets[id]
	while ipclet.waitingForNotify[1] do
		local pid = table.remove(ipclet.waitingForNotify,1)
		ipcidsigQ[#ipcidsigQ+1] = {"ipc_notify_signal",pid,id}
	end
	ps.yield()
end

--get around a limitation that would otherwise make IPC unavailable to usermode applications--
--this is because usermode applications cannot send signals to other usermode applications and kernelmode applications--
ipcid, ipcidsigQ = ps.spawn([[
	while true do
		local sig, pid, id = computer.pullSignal()
		if sig == "ipc_signal" then
			ps.pushSignalTo(pid,"ipc_locked",id)
		elseif sig == "ipc_notify_signal" then
			ps.pushSignalTo(pid,"ipc_notify",id)
		end
	end
]],"ipc_signal",nil,true)

ipc.pid = ipcid

ks.exposeAPI("ipc",ipc)
