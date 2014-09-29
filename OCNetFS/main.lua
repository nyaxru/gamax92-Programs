local socket = require("socket")

local server, client, totalspace, currspace, label, change, recurseCount, recursiveDestroy
local hndls = {}

function love.load(arg)
	-- Configuration
	totalspace = math.huge
	curspace = 0
	label = "netfs"
	change = false
	
	if change then
		print("Modification enabled\n")
	end
	
	print("Calculating current space usage ...")
	curspace = recurseCount("/")

	local stat
	stat, server = pcall(assert,socket.bind("*", 14948))
	if not stat then
		print("Failed to get default port 14948: " .. server)
		server = assert(socket.bind("*", 0))
	end

	print("Binded to " .. sID .. ":" .. sPort)
end

function recurseCount(path)
	local count = 0
	local list = love.filesystem.getDirectoryItems(path)
	for i = 1,#list do
		if love.filesystem.isDirectory(path .. "/" .. list[i]) then
			count = count + 512 + recurseCount(path .. "/" .. list[i])
		else
			count = count + love.filesystem.getSize(path .. "/" .. list[i])
		end
	end
	return count
end

function recursiveDestroy(path)
	local state = true
	local list = love.filesystem.getDirectoryItems(path)
	for i = 1,#list do
		if love.filesystem.isDirectory(path .. "/" .. list[i]) then
			state = state and recursiveDestroy(path .. "/" .. list[i])
		else
			state = state and love.filesystem.remove(path .. "/" .. list[i])
		end
	end
	return state
end

local ots = tostring
function tostring(obj)
	if obj == math.huge then
		return "math.huge"
	elseif obj == -math.huge then
		return "-math.huge"
	elseif obj ~= obj then
		return "0/0"
	else
		return ots(obj)
	end
end

local function sendData(msg)
	print(" < " .. msg)
	client:send(msg .. "\n")
end

function love.update()
	if client == nil then
		client = server:accept()
		if client ~= nil then
			local ci,cp = client:getpeername()
			print("User connected from: " .. ci .. ":" .. cp)
		end
	else
		local line = client:receive()
		local ctrl = line:byte(1,1) - 31
		print(" > " .. ctrl .. "," .. line:sub(2))
		local retfn,err = loadstring("return " .. line:sub(2))
		if retfn == nil then
			print("Bad Input: " .. err)
			sendData("{nil,\"bad input\"}")
			return
		end
		local ret = retfn()
		if type(ret) ~= "table" then
			print("Bad Input (exec): " .. type(ret))
			sendData("{nil,\"bad input\"}")
			return
		end
		if ctrl == 1 then -- size
			local size = love.filesystem.getSize(ret[1])
			sendData("{" .. size or 0 .. "}")
		elseif ctrl == 2 then -- seek
			local fd = ret[1]
			if hndls[fd] == nil then
				sendData("{nil, \"bad file descriptor\"}")
			else
				if ret[2] == "set" then
					hndls[fd]:seek(ret[3])
				elseif ret[2] == "cur" then
					hndls[fd]:seek(hndls[fd]:tell() + ret[3])
				elseif ret[2] == "end" then
					hndls[fd]:seek(hndls[fd]:getSize() + ret[3])
				end
				sendData("{" .. hndls[fd]:tell() .. "}")
			end
		elseif ctrl == 3 then -- read
			local fd = ret[1]
			if hndls[fd] == nil then
				sendData("{nil, \"bad file descriptor\"}")
			else
				local data = hndls[fd]:read(ret[2])
				if type(data) == "string" and #data > 0 then
					sendData("{" .. string.format("%q",data):gsub("\\\n","\\n") .. "}")
				else
					sendData("{nil}")
				end
			end
		elseif ctrl == 4 then -- isDirectory
			sendData("{" .. tostring(love.filesystem.isDirectory(ret[1])) .. "}")
		elseif ctrl == 5 then -- open
			local mode = ret[2]:sub(1,1)
			if (mode == "w" or mode == "a") and not change then
				sendData("{nil,\"file not found\"}") -- Yes, this is what it returns
			else
				local file, errorstr = love.filesystem.newFile(ret[1], mode)
				if not file then
					sendData("{nil," .. string.format("%q",errorstr):gsub("\\\n","\\n") .. "}")
				else
					local randhand
					while true do
						randhand = math.random(1000000000,9999999999)
						if not hndls[randhand] then
							hndls[randhand] = file
							break
						end
					end
					sendData("{" .. randhand .. "}")
				end
			end
		elseif ctrl == 6 then -- spaceTotal
			sendData("{" .. tostring(totalspace) .. "}")
		elseif ctrl == 7 then -- setLabel
			-- TODO: Error to client
			if change then
				label = ret[1]
			end
			sendData("{\"" .. label .. "\"}")
		elseif ctrl == 8 then -- lastModified
			local modtime = love.filesystem.getLastModified(ret[1])
			sendData("{" .. modtime or 0 .. "}")
		elseif ctrl == 9 then -- close
			local fd = ret[1]
			if hndls[fd] == nil then
				sendData("{nil, \"bad file descriptor\"}")
			else
				hndls[fd]:close()
				hndls[fd] = nil
				sendData("{}")
			end
		elseif ctrl == 10 then -- rename
			if change then
				local data = love.filesystem.read(ret[1])
				if not data then
					sendData("{false}")
				else
					local succ = love.filesystem.write(ret[2],data)
					if not succ then
						sendData("{false}")
					else
						local succ = love.filesystem.remove(ret[1])
						if not succ then
							local succ = love.filesystem.remove(ret[2])
							if not succ then
								print("WARNING: two copies of " .. ret[1] .. " now exist")
							end
							sendData("{false}")
						else
							sendData("{true}")
						end
					end
				end
			else
				sendData("{false}")
			end
		elseif ctrl == 11 then -- isReadOnly
			sendData("{" .. tostring(not change) .. "}")
		elseif ctrl == 12 then -- exists
			sendData("{" .. tostring(love.filesystem.exists(ret[1])) .. "}")
		elseif ctrl == 13 then -- getLabel
			sendData("{\"" .. label .. "\"}")
		elseif ctrl == 14 then -- spaceUsed
			-- TODO: Need to update this
			sendData("{" .. curspace .. "}")
		elseif ctrl == 15 then -- makeDirectory
			if change then
				sendData("{" .. tostring(love.filesystem.createDirectory(ret[1])) .. "}")
			else
				sendData("{false}")
			end
		elseif ctrl == 16 then -- list
			local list = love.filesystem.getDirectoryItems(ret[1])
			local out = ""
			for i = 1,#list do
				if love.filesystem.isDirectory(ret[1] .. "/" .. list[i]) then
					list[i] = list[i] .. "/"
				end
				out = out .. string.format("%q",list[i]):gsub("\\\n","\\n")
				if i < #list then
					out = out .. ","
				end
			end
			sendData("{{" .. out .. "}}")
		elseif ctrl == 17 then -- write
			local fd = ret[1]
			if hndls[fd] == nil then
				sendData("{nil, \"bad file descriptor\"}")
			else
				local success = hndls[fd]:write(ret[2])
				sendData("{" .. tostring(success) .. "}")
			end
		elseif ctrl == 18 then -- remove
			if change then
				sendData("{" .. tostring(recursiveDestroy(ret[1])) .. "}")
			else
				sendData("{false}")
			end
		else
			print("Unknown control: " .. ctrl)
		end
	end
end
