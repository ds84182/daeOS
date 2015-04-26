--tape management service--
config.hal.blacklist[#config.hal.blacklist+1] = "tape"
ks.filesystem_dev.tape = {}

local pid = ps.getCurrentProcess()
while true do
	local signal, a, b, c, d, e, f, g, h = computer.pullSignal()
	if signal == "component_added" then
		if b == "tape_drive" then
			print("Tape drive added:",a)
			component.invoke(a,"seek",-math.huge)
			ks.filesystem_dev.tape[a] = function(mode, request, args)
				if mode == "open" or mode == "close" then
					return true
				elseif mode == "read" then
					return component.invoke(a,"read",request)
				elseif mode == "write" then
					return component.invoke(a,"write",request)
				elseif mode == "seek" then
					local index
					if request == "set" then
						component.invoke(a,"seek",-math.huge)
						index = component.invoke(a,"seek",args)
					elseif request == "cur" then
						index = component.invoke(a,"seek",args)
					elseif request == "end" then
						index = component.invoke(a,"seek",math.huge)
					end
					return index
				elseif mode == "ioctl" then
					if request == "play" then
						return component.invoke(a,"play")
					elseif request == "stop" then
						return component.invoke(a,"stop")
					end
				end
			end
		end
	elseif signal == "service_stop" then
		--request stop service--
		ks.filesystem_dev.tape = nil
		for i=1, #config.hal.blacklist do
			if config.hal.blacklist[i] == "tape" then
				table.remove(config.hal.blacklist,i)
				break
			end
		end
		return
	end
end
