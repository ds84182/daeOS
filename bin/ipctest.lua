--spawn two processes with a common IPC--
local ipc = require "ipc"
local shared = ipc.new()
local keyboard = require "keyboard"

local t1 = ps.spawn([[
	local shared = ...
	local term = require "term"
	local ipc = require "ipc"
	while true do
		ipc.lock(shared)
		print("IPC1 locks!")
		os.sleep(0.125)
		ipc.unlock(shared)
	end
]],"ipc1",{shared})

local t2 = ps.spawn([[
	local shared = ...
	local term = require "term"
	local ipc = require "ipc"
	while true do
		ipc.lock(shared)
		print("IPC2 locks!")
		os.sleep(0.25)
		ipc.unlock(shared)
	end
]],"ipc2",{shared})

while not keyboard.isControlDown() do
	local sig, pid = computer.pullSignal()
	if sig == "child_death" then
		local info = {}
		ps.getInfo(pid, info)
		print(pid,info.error or "peaceful")
	end
end

ps.remove(t1)
ps.remove(t2)
