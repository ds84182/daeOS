local pid = ps.getCurrentProcess()
local keyboard = require "keyboard"
local term = require "term"
local elevatedToProcessList = {}
while true do
	local signal, a, b, c, d, e, f, g, h = computer.pullSignal()
	if signal == "spawn_elevated_password" then
		if not ps.isSignalFilterInstalled "guard_keys" then
			ps.installSignalFilter("guard_keys",function(proc,signal)
				return proc.id == pid or proc.id == keyboard.pid or (signal ~= "key_down" and signal ~= "key_up" and signal ~= "clipboard")
			end)
		end
		
		term.write("Enter admin password: ")
		local password = require "hash".sha256(term.read(nil,nil,nil,"*") or "")
		if  config.security.password == password then
			local pid,sigQ = ps.spawn(b,c,d,true,e,f,g,h)
			ps.pushSignalTo(a,"spawned_elevated",pid,sigQ)
			term.write("Elevation successful\n")
			elevatedToProcessList[pid] = a
		else
			ps.pushSignalTo(a,"spawn_failed","invalid password")
			ps.resume(a)
		end
		
		ps.uninstallSignalFilter "guard_keys"
	elseif signal == "spawn_elevated" then
		local pid,sigQ = ps.spawn(b,c,d,true,e,f,g,h)
		ps.pushSignalTo(a,"spawned_elevated",pid,sigQ)
		term.write("Elevation successful\n")
		elevatedToProcessList[pid] = a
	elseif signal == "child_death" then
		ps.resume(elevatedToProcessList[a])
		elevatedToProcessList[a] = nil
		ps.remove(a)
	end
end
