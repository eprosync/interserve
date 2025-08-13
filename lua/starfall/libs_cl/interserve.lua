--- Interserve library
-- @name interserve
-- @class library
-- @shared
-- @libtbl interserve_library
SF.RegisterLibrary("interserve")

local InteserveBurst = SF.BurstObject("interserve", "interserve payload", 5, 10, "Regen rate of interserve burst in mB/sec.", "The interserve packet burst limit in mB.", 1000 * 1000 * 8)
SF.InteserveBurst = InteserveBurst

return function(instance)
	local interserve_library = instance.Libraries.interserve

    local function interserve_suid(id)
        local player = instance.player
        if not IsValid(player) then return end
        return util.MD5(player:SteamID64() .. id)
    end

    instance.interserve = {
        receivers = {},
        failures = {}
    }

    instance:AddHook("deinitialize", function()
        local receivers = instance.interserve.receivers
        for i=1, #receivers do
            interserve:receive(receivers[i], nil)
        end
    end)

	--- Adds a handshake confirmation to uploads to the server
	-- @server
	-- @param string id - the unique ID for the endpoint
	-- @param function callback - the function callback for when a client handshake is being made
    interserve_library.handshake = function() end

    --- Adds an interrupt confirmation to uploads and downloads during threaded processing
	-- @server
	-- @param string id - the unique ID for the endpoint
	-- @param function callback - the function callback for when a client handshake is being made
    interserve_library.interrupt = function() end

	--- Adds a new interserve endpoint, cannot use interserve without registering an endpoint
	-- @server
	-- @param string id - the unique ID for the endpoint
    interserve_library.add = function() end

	--- Removes an existing interserve endpoint
	-- @server
	-- @param string id - the unique ID for the endpoint
    interserve_library.remove = function() end

	--- A callback for when failures are captured under interserve
	-- @client
	-- @param string id - the unique ID for the endpoint
	-- @param function callback - the function callback for when a failure occurs on serve
    interserve_library.failure = function(id, callback)
        assert(isstring(id), "bad argument #1, expected string")
        assert(isfunction(callback), "bad argument #2, expected function")
        id = interserve_suid(id)
        local failures = instance.interserve.failures
        if callback then
            if #failures > 10 then
                SF.Throw("Too many interserve failure handlers", 2)
                return
            end
            failures[id] = callback
            failures[#failures+1] = id
            interserve:failure(id, function(...)
                instance:runFunction(callback, ...)
            end)
        else
            failures[id] = nil
            for i=1, #failures do
                if failures[i] == id then
                    table.remove(failures, i)
                    break
                end
            end
            interserve:failure(id, nil)
        end
    end

	--- A callback for incoming data
	-- @shared
	-- @param string id - the unique ID for the endpoint
	-- @param function callback - the function callback for when data is recieved
    interserve_library.receive = function(id, callback)
        assert(isstring(id), "bad argument #1, expected string")
        assert(isfunction(callback), "bad argument #2, expected function")
        id = interserve_suid(id)
        local receivers = instance.interserve.receivers
        if callback then
            if #receivers > 5 then
                SF.Throw("Too many interserve receivers", 2)
                return
            end
            receivers[id] = callback
            receivers[#receivers+1] = id
            interserve:receive(id, function(...)
                instance:runFunction(callback, ...)
            end)
        else
            receivers[id] = nil
            for i=1, #receivers do
                if receivers[i] == id then
                    table.remove(receivers, i)
                    break
                end
            end
            interserve:receive(id, nil)
        end
    end

	--- For sending data to the server or client through interserve
	-- @shared
	-- @param string id - the unique ID for the endpoint
	-- @param string data - the string data to be sent
	-- @param Player? target - the target player, only available on server realms
    interserve_library.send = function(id, data)
        assert(isstring(id), "bad argument #1, expected string")
        assert(isstring(data), "bad argument #2, expected string")
        id = interserve_suid(id)
        InteserveBurst:use(instance.player, #data)
        interserve:send(id, data)
    end
end