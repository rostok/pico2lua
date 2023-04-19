local api = require("love/api")
local cart = require("love/cart")
log = print

if #arg==0 then
	print("no args")
	print("-ne --noenv    do not add _ENV")
	print("-o             overwrite original file")
	return
end

local loaded_code, orglua 
local filename = arg[#arg]
loaded_code, orglua = cart.load_p8(filename) 
filename = filename:gsub(".p8",".lua")
filename = filename:gsub(".lua","_patched.lua")

for k, v in pairs(arg) do
	if v=="--noenv" or v=="-ne" then
	    print("removing _ENV")
		loaded_code = loaded_code:gsub("local _ENV = _ENV \n","")
		loaded_code = loaded_code:gsub("_ENV%.","")
	end
	if v=="-o" then
	    print("overwriting")
		filename = arg[#arg]
	end
end
if loaded_code:sub(1,2)=="\n\n" then loaded_code=loaded_code:sub(3) end

api.writeFile(filename,loaded_code)