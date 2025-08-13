--- Used as an alternative to large and deferred data transfer from clients and servers with the power of thread scheduling and HTTP serving.
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
        registry = {},
        receivers = {},
        handshakes = {},
        interrupts = {}
    }

    instance:AddHook("deinitialize", function()
        local registry = instance.interserve.registry
        for i=1, #registry do
            interserve:remove(registry[i])
        end
        local receivers = instance.interserve.receivers
        for i=1, #receivers do
            interserve:receive(receivers[i], nil)
        end
        local handshakes = instance.interserve.handshakes
        for i=1, #handshakes do
            interserve:handshake(handshakes[i], nil)
        end
        local interrupts = instance.interserve.interrupts
        for i=1, #interrupts do
            interserve:interrupt(interrupts[i], nil)
        end
    end)

    --- Adds a handshake confirmation to uploads to the server
	-- @server
	-- @param string id - the unique ID for the endpoint
	-- @param function callback - the function callback for when a client handshake is being made
    interserve_library.handshake = function(id, callback)
        assert(isstring(id), "bad argument #1, expected string")
        assert(isfunction(callback), "bad argument #2, expected function")
        id = interserve_suid(id)
        local handshakes = instance.interserve.handshakes
        if callback then
            if #handshakes > 10 then
                SF.Throw("Too many interserve interrupt handlers", 2)
                return
            end
            handshakes[id] = callback
            handshakes[#handshakes+1] = id
            interserve:handshake(id, function(invoker, ...)
                invoker = instance.Types.Player.Wrap(invoker)
                instance:runFunction(callback, invoker, ...)
            end)
        else
            handshakes[id] = nil
            for i=1, #handshakes do
                if handshakes[i] == id then
                    table.remove(handshakes, i)
                    break
                end
            end
            interserve:handshake(id, nil)
        end
    end

    --- Adds an interrupt confirmation to uploads and downloads during threaded processing
	-- @server
	-- @param string id - the unique ID for the endpoint
	-- @param function callback - the function callback for when a client handshake is being made
    interserve_library.interrupt = function(id, callback)
        assert(isstring(id), "bad argument #1, expected string")
        assert(isfunction(callback), "bad argument #2, expected function")
        id = interserve_suid(id)
        local interrupts = instance.interserve.interrupts
        if callback then
            if #interrupts > 10 then
                SF.Throw("Too many interserve interrupt handlers", 2)
                return
            end
            interrupts[id] = callback
            interrupts[#interrupts+1] = id
            interserve:interrupt(id, function(invoker, ...)
                invoker = instance.Types.Player.Wrap(invoker)
                instance:runFunction(callback, invoker, ...)
            end)
        else
            interrupts[id] = nil
            for i=1, #interrupts do
                if interrupts[i] == id then
                    table.remove(interrupts, i)
                    break
                end
            end
            interserve:interrupt(id, nil)
        end
    end

	--- Adds a new interserve endpoint, cannot use interserve without registering an endpoint
	-- @server
	-- @param string id - the unique ID for the endpoint
    interserve_library.add = function(id)
        assert(isstring(id), "bad argument #1, expected string")
        id = interserve_suid(id)
        local r = instance.interserve.registry
        if #r > 5 then
            SF.Throw("Too many interserve endpoints", 2)
            return
        end
        if r[id] then return end r[id] = true r[#r+1] = id
        interserve:add(id)
    end

	--- Removes an existing interserve endpoint
	-- @server
	-- @param string id - the unique ID for the endpoint
    interserve_library.remove = function(id)
        assert(isstring(id), "bad argument #1, expected string")
        id = interserve_suid(id)
        local r = instance.interserve.registry
        if not r[id] then return end r[id] = nil
        for i=1, #r do
            if r[i] == id then
                table.remove(r, i)
                break
            end
        end
        interserve:remove(id)
    end

	--- A callback for when failures are captured under interserve
	-- @client
	-- @param string id - the unique ID for the endpoint
	-- @param function callback - the function callback for when a failure occurs on serve
    interserve_library.failure = function(id, callback) end

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
            interserve:receive(id, function(invoker, data)
                invoker = instance.Types.Player.Wrap(invoker)
                instance:runFunction(callback, invoker, data)
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
    interserve_library.send = function(id, data, target)
        assert(isstring(id), "bad argument #1, expected string")
        id = interserve_suid(id)
        target = instance.Types.Player.Unwrap(target)
        assert(isstring(data), "bad argument #3, expected string")
        InteserveBurst:use(instance.player, #data)
        interserve:send(id, data, target)
    end

	--- For sending data to all players on the server through interserve
	-- @server
	-- @param string id - the unique ID for the endpoint
	-- @param string data - the string data to be sent
    interserve_library.broadcast = function(id, data)
        id = interserve_suid(id)
        InteserveBurst:use(instance.player, #data)
        interserve:broadcast(id, data)
    end
end