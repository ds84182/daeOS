local filesystem = require "filesystem"
local files = table.pack(...)

if files.n == 0 then
	files[1] = "/dev/stdin"
	files.n = 1
end

for i=1, files.n do
   local file = files[i]
   if file == "-" then file = "/dev/stdin" end
   if file:sub(1,1) ~= "/" then
      file = filesystem.fixPath(ps.getEnv("PWD").."/"..file)
   end
   local fh, er = filesystem.open(file,"r")
   if not fh then
      printErr(er)
      break
   else
      while true do
         local buffer = fh.read(512)
         if not buffer then break end
         io.write(buffer)
      end
      fh.close()
   end
end

