local filesystem = require "filesystem"
local files = table.pack(...)

for i=1, files.n do
   local file = files[i]
   if file:sub(1,1) ~= "/" then
      file = ps.getEnv("PWD").."/"..file
   end
   local fh, er = filesystem.open(file,"r")
   if not fh then
      printErr(er)
      break
   else
      while true do
         local buffer = fh.read(512)
         if not buffer then return end
         ps.getSTDOUT()(buffer)
      end
      fh.close()
   end
end

