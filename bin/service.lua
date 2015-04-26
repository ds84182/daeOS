local service = require "service"
local arguments = ps.getArguments()

if arguments[1] == "start" then
   print("Starting service: "..arguments[2])
   local pid,err = service.start(table.unpack(arguments,2))
   if not pid then printErr(err) return end
elseif arguments[1] == "stop" then
   print("Stopping service: "..arguments[2])
   local suc,err = service.stop(arguments[2])
   if not suc then printErr(err) return end
elseif arguments[1] == "restart" then
   print("Restarting service: "..arguments[2])
   local suc,err = service.stop(arguments[2])
   if not suc then printErr(err) return end
   local pid,err = service.start(table.unpack(arguments,2))
   if not pid then printErr(err) return end
else
   printErr("Usage: service [start|stop|restart] [service] [arguments...]")
end
