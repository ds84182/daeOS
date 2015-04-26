local stdout, err = require "filesystem".open("/dev/stdout","w")
if not stdout then
	print(err)
	return
end
stdout.write("Hello! ")
stdout.write("World!\n")
stdout.close()
