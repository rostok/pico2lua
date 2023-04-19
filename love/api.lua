local api = {}

api.print = print

api.writeFile = function(name, contents)
  -- open the file in write mode
  local file = io.open(name, "w")
  if not file then
    -- handle error if unable to open file
    error("Unable to open file: " .. name)
  end

  -- write the contents to the file
  file:write(contents)

  -- close the file
  file:close()
end

api.readFile = function(name)
  -- open the file in read mode
  local file = io.open(name, "r")
  if not file then
    -- handle error if unable to open file
    error("Unable to open file: " .. name)
  end

  -- read the contents of the file
  local contents = file:read("*all")

  -- close the file
  file:close()

  -- return the contents of the file
  return contents
end


return api