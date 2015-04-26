--spawn two processes with a common IPC--
local ipc = require "ipc"
local shared = ipc.new()
local notify = ipc.new()
local keyboard = require "keyboard"

local t1 = ps.spawn([[
	local shared,notify = ...
	local term = require "term"
	local ipc = require "ipc"
	while true do
		--the reading process--
		io.write("write anything> ")
		local line = io.read("*l")
		ipc.push(shared, line)
		ipc.notify(notify)
		ipc.wait(shared)
	end
]],"ipc1",{shared,notify})

local t2 = ps.spawn([[
	local shared,notify = ...
	local term = require "term"
	local ipc = require "ipc"
	os.sleep(0.1)
	while true do
		ipc.wait(notify)
		print("On other process:",ipc.pull(shared))
		ipc.notify(shared)
	end
]],"ipc2",{shared,notify})

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
