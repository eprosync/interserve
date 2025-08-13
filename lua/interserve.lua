--[[
    Interserve - Abusing HTTP to get around net.* limits.
    Initial Concept Version, do not use on production servers.
    Contact: https://github.com/eprosync
    Prerequisite: https://github.com/eprosync/interstellar_gmod
]]

local interserve = {}
_G.interserve = interserve

if SERVER then
    if not iot then require("interstellar") end

    util.AddNetworkString("Interserve:Initialize")
    util.AddNetworkString("Interserve:Post")
    util.AddNetworkString("Interserve:Get")

    local INTERSERVE_ADDRESS = CreateConVar("interserve_address", "-1", {FCVAR_ARCHIVE, FCVAR_PROTECTED}, "Client's inverserve address or domain (format IP [no port] or domain)")
    local INTERSERVE_IPORT = CreateConVar("interserve_iport", "-1", {FCVAR_ARCHIVE, FCVAR_PROTECTED}, "Server's interserve port (must be a valid port!)")
    local INTERSERVE_PORT = CreateConVar("interserve_port", "-1", {FCVAR_ARCHIVE, FCVAR_PROTECTED}, "Client's inverserve port (must be the same or targeting a proxy)")
    local INTERSERVE_SSL = CreateConVar("interserve_ssl", "0", {FCVAR_ARCHIVE, FCVAR_PROTECTED}, "Client's inverserve SSL support")
    local INTERSERVE_TRUSTED = CreateConVar("interserve_trusted", "1", {FCVAR_ARCHIVE, FCVAR_PROTECTED}, "Client's inverserve SSL support")
    local INTERSERVE_TIMEOUT = CreateConVar("interserve_timeout", "30", {FCVAR_ARCHIVE, FCVAR_PROTECTED}, "Server's interserve timeout")

    concommand.Add("interserve_reload", function(invoker)
        if IsValid(invoker) then return end
        interserve:boot()
    end)

    function interserve:boot()
        self.stop()

        interserve.trusted = INTERSERVE_TRUSTED:GetBool() -- Allows X-Forwarded-For headers (assuming you are using CF or Nginx-Reverse-Proxy)
        if INTERSERVE_IPORT:GetInt() > 0 then -- Port for serve to start on.
            interserve.port = INTERSERVE_IPORT:GetInt()
        else
            interserve.port = 25500
        end
        interserve.timeout = INTERSERVE_TIMEOUT:GetInt() or 30 -- How long till a request is invalidated in seconds.
        interserve.registry = {}
        interserve.sessions = {}

        hook.Add("GetGameDescription" , "Interserve", function()
            local interserve_addr = INTERSERVE_ADDRESS:GetString()
            local ip = game.GetIPAddress()
            if #interserve_addr and interserve_addr ~= "-1" then ip = interserve_addr end

            local port = interserve.port
            if INTERSERVE_PORT:GetInt() > 0 then
                port = INTERSERVE_PORT:GetInt()
            end

            ip = string.Explode(":", ip)[1] .. ":" .. port
            SetGlobalString("interserve", (INTERSERVE_SSL:GetBool() and "https://" or  "http://") .. ip)
        end)
        
        local players = player.GetHumans()
        for i=1, #players do
            local invoker = players[i]
            interserve.construct(players[i])
        end

        self.start()
    end

    interserve.handshakes = {}
    function interserve:handshake(id, callback)
        self.handshakes[id] = callback
    end

    interserve.interrupts = {}
    function interserve:interrupt(id, callback)
        self.interrupts[id] = callback
    end

    function interserve:add(id)
        local self = interserve
        local r = self.registry
        if r[id] then return end
        r[id] = true
        r[#r+1] = id

        local players = player.GetHumans()
        for i=1, #players do
            self.open(players[i], id)
        end
    end

    function interserve:remove(id)
        local self = interserve
        local r = self.registry
        if not r[id] then return end

        r[id] = nil
        for i=1, #r do
            if r[i] == id then
                table.remove(r, i)
                break
            end
        end

        local players = player.GetHumans()
        for i=1, #players do
            self.close(players[i], id)
        end
    end

    function interserve:exists(id)
        local self = interserve
        local r = self.registry
        return r[id] ~= nil
    end

    interserve.receivers = {}
    function interserve:receive(id, callback)
        local self = interserve
        local r = self.registry
        if not r[id] then return end
        local receivers = self.receivers
        receivers[id] = callback
    end

    interserve.sending = {}
    interserve.receiving = {}

    timer.Create("Interserve:Validation", 1, 0, function()
        local self = interserve
        local r = self.registry
        local t = os.time()
        for k, v in player.Iterator() do
            local senders = self.sending[v]
            if senders then
                for id, entry in pairs(senders) do
                    for uid, queue in pairs(entry) do
                        if queue.time + self.timeout < t then
                            entry[uid] = nil
                        end
                    end
                end
            end

            local receivers = self.receiving[v]
            if receivers then
                for id, entry in pairs(receivers) do
                    for uid, queue in pairs(entry) do
                        if queue.time + self.timeout < t then
                            entry[uid] = nil
                        end
                    end
                end
            end
        end
    end)

    function interserve:send(id, data, invoker)
        local self = interserve
        local r = self.registry
        if not r[id] then return end

        local sending = self.sending
        if not sending[invoker] then return end
        local entry = sending[invoker]
        if not entry[id] then entry[id] = {} end

        local uid = util.SHA256(tostring(SysTime()))
        entry[id][uid] = {
            id = id,
            uid = uid,
            time = os.time(),
            data = data
        }

        net.Start("Interserve:Get")
        net.WriteString(id)
        net.WriteString(uid)
        net.Send(invoker)
    end

    function interserve:broadcast(id, data)
        local humans = player.GetHumans()

        local self = interserve
        local r = self.registry
        if not r[id] then return end

        local sending = self.sending
        local uid = util.SHA256(tostring(SysTime()))

        for i=1, #humans do
            local invoker = humans[i]
            if not sending[invoker] then continue end
            local entry = sending[invoker]
            if not entry[id] then entry[id] = {} end
            entry[id][uid] = {
                id = id,
                uid = uid,
                time = os.time(),
                data = data
            }
        end

        net.Start("Interserve:Get")
        net.WriteString(id)
        net.WriteString(uid)
        net.Broadcast()
    end

    function interserve:omit(id, data, ignore)
        local humans = player.GetHumans()

        local self = interserve
        local r = self.registry
        if not r[id] then return end

        local sending = self.sending
        local uid = util.SHA256(tostring(SysTime()))
        local is_array = istable(ignore)

        for i=1, #humans do
            local invoker = humans[i]
            if is_array then
                local ignoring = false
                for k=1, #ignore do
                    if ignore[k] == invoker then
                        ignoring = true
                        break
                    end
                end
                if ignoring then continue end
            else
                if invoker == ignore then continue end
            end
            if not sending[invoker] then continue end
            local entry = sending[invoker]
            if not entry[id] then entry[id] = {} end
            entry[id][uid] = {
                id = id,
                uid = uid,
                time = os.time(),
                data = data
            }
        end

        net.Start("Interserve:Get")
        net.WriteString(id)
        net.WriteString(uid)
        net.SendOmit(ignore)
    end

    net.Receive("Interserve:Post", function(_, invoker)
        local id = net.ReadString()
        local size = net.ReadUInt(32)
        local self = interserve
        local r = self.registry
        if not r[id] then return end

        local handshake = self.handshakes[id]
        if isfunction(handshake) then
            local ran, err = xpcall(handshake, debug.traceback, invoker, size)
            if not ran then
                ErrorNoHalt(err)
                return
            end
            if err == false then return end
        end

        local receiving = self.receiving
        if not receiving[invoker] then return end
        local entry = receiving[invoker]
        if not entry[id] then entry[id] = {} end

        local uid = util.SHA256(tostring(SysTime()))
        entry[id][uid] = {
            id = id,
            uid = uid,
            size = size,
            time = os.time()
        }

        net.Start("Interserve:Post")
        net.WriteString(id)
        net.WriteString(uid)
        net.Send(invoker)
    end)

    function interserve.open(invoker, id)
        local self = interserve
        local engine = self.engine
        local sid = self.sessions[invoker]
        assert(sid ~= nil, "[Interserve] Cannot construct " .. invoker:SteamID64() .. " without session ID")
        engine:post("/interserve/" .. sid .. "/" .. id, function(req, res)
            if self.trusted then
                if req.headers["X-Forwarded-For"] then
                    req.ip = req.headers["X-Forwarded-For"]:match("([^,]+)") or req.ip
                end
            end

            local r = self.registry
            local uid = req.parameters.uid
            local session_id, id = string.match(req.path, "^/interserve/(%w+)/([%w%._%-~]+)")
            if not session_id or not id or not uid or not r[id] then return res:status(400) end

            local invoker = self.sessions[session_id]
            if not IsValid(invoker) or not invoker:IsPlayer() then return res:status(401) end

            local ip = invoker:IPAddress()
            ip = string.Explode(":", ip)[1]
            if req.ip ~= ip then return res:status(401) end

            local interrupt = self.interrupts[id]
            if isfunction(interrupt) then
                local ran, err = xpcall(interrupt, debug.traceback, invoker, req)
                if not ran then
                    ErrorNoHalt(err)
                    return res:status(500)
                end
                if err == false then return res:status(403) end
            end

            local receiving = self.receiving
            if not receiving[invoker] then return res:status(403) end
            local entry = receiving[invoker]
            if not entry[id] or not entry[id][uid] then return res:status(403) end
            local handshake_data = entry[id][uid]
            entry[id][uid] = nil

            if handshake_data.size ~= #req.body then return res:status(403) end

            local receivers = self.receivers
            if not receivers[id] then return res:status(403) end

            local ran, err = xpcall(receivers[id], debug.traceback, invoker, req.body, req)
            if not ran then ErrorNoHalt(err) end

            return res:status(200)
        end)
        engine:get("/interserve/" .. sid .. "/" .. id, function(req, res)
            if self.trusted then
                if req.headers["X-Forwarded-For"] then
                    req.ip = req.headers["X-Forwarded-For"]:match("([^,]+)") or req.ip
                end
            end

            local r = self.registry
            local uid = req.parameters.uid
            local session_id, id = string.match(req.path, "^/interserve/(%w+)/([%w%._%-~]+)")
            if not session_id or not id or not uid or not r[id] then return res:status(400) end

            local invoker = self.sessions[session_id]
            if not IsValid(invoker) or not invoker:IsPlayer() then return res:status(401) end

            local ip = invoker:IPAddress()
            ip = string.Explode(":", ip)[1]
            if req.ip ~= ip then return res:status(401) end

            local interrupt = self.interrupts[id]
            if isfunction(interrupt) then
                local ran, err = xpcall(interrupt, debug.traceback, invoker, req)
                if not ran then
                    ErrorNoHalt(err)
                    return res:status(500)
                end
                if err == false then return res:status(403) end
            end

            local sending = self.sending
            if not sending[invoker] then return res:status(401) end
            local entry = sending[invoker]
            if not entry[id] or not entry[id][uid] then return res:status(401) end
            local queue = entry[id][uid]
            entry[id][uid] = nil

            res:body(queue.data or "")
            res:status(200)
        end)
    end

    function interserve.close(invoker, id)
        local self = interserve
        local engine = self.engine
        local sid = self.sessions[invoker]
        self.sending[invoker][id] = nil
        self.receiving[invoker][id] = nil
        if not sid then return end
        engine:post("/interserve/" .. sid .. "/" .. id, nil)
        engine:get("/interserve/" .. sid .. "/" .. id, nil)
    end

    function interserve.construct(invoker)
        local self = interserve
        invoker.INTERSERVE_SID = invoker.INTERSERVE_SID or util.MD5(invoker:SteamID64() .. "-" .. SysTime())

        if not self.sessions[invoker] then
            self.sending[invoker] = self.sending[invoker] or {}
            self.receiving[invoker] = self.receiving[invoker] or {}
            self.sessions[invoker] = invoker.INTERSERVE_SID
            self.sessions[invoker.INTERSERVE_SID] = invoker
            local r = self.registry
            for i=1, #r do 
                self.open(invoker, r[i])
            end
        end
        
        net.Start("Interserve:Initialize")
        net.WriteString(invoker.INTERSERVE_SID)
        net.Send(invoker)
    end

    function interserve.destruct(invoker)
        local self = interserve
        local r = self.registry
        for i=1, #r do
            local id = r[i]
            self.close(invoker, r[i])
        end
        local sid = self.sessions[invoker]
        self.sessions[invoker] = nil
        self.sessions[sid or ""] = nil
        self.sending[invoker] = nil
        self.receiving[invoker] = nil
    end

    function interserve.stop()
        local self = interserve
        if self.engine and self.engine:active() then
            self.engine:stop()
        end
    end

    function interserve.start()
        local self = interserve
        self.engine = iot.serve(self.port)
        local engine = self.engine
        if engine:active() or engine:start() then
            print("[Interserve] Engine Ready.")
        else
            error("[Interserve] Unable to start serve engine, port is probably in-use [" .. self.port .. "]")
        end
    end

    hook.Add("PlayerInitialSpawn", "Interserve", function(invoker)
        local self = interserve
        self.sending[invoker] = {}
        self.receiving[invoker] = {}
    end)
    net.Receive("Interserve:Initialize", function(_, invoker) interserve.construct(invoker) end)
    hook.Add("PlayerDisconnected", "Interserve", interserve.destruct)
    timer.Simple(0, function() interserve:boot() end)
else
    interserve.sending = {}
    function interserve:send(id, data)
        net.Start("Interserve:Post")
        net.WriteString(id)
        net.WriteUInt(#data, 32)
        net.SendToServer()
        if not self.sending[id] then self.sending[id] = {} end
        local queue = self.sending[id]
        queue[#queue+1] = data
    end

    interserve.receivers = {}
    function interserve:receive(id, callback)
        local self = interserve
        local receivers = self.receivers
        receivers[id] = callback
    end

    interserve.failures = {}
    function interserve:failure(id, callback)
        local self = interserve
        local failures = self.failures
        failures[id] = callback
    end

    function interserve.post(uid, id, body)
        local self = interserve
        local sid = self.sid
        local failures = self.failures
        HTTP({
            failed = function( reason )
                if failures[id] then
                    local ran, err = xpcall(failures[id], debug.traceback, 504, reason)
                    if not ran then ErrorNoHalt(err) end
                end
            end,
            success = function( code, body, headers )
                if code ~= 200 then
                    if failures[id] then
                        local ran, err = xpcall(failures[id], debug.traceback, code, body, headers)
                        if not ran then ErrorNoHalt(err) end
                    end
                    return
                end
            end,
            method = "POST",
            body = body,
            url = GetGlobalString("interserve") .. "/interserve/" .. sid .. "/" .. id .. "?uid=" .. uid
        })
    end

    function interserve.get(uid, id)
        local self = interserve
        local sid = self.sid
        HTTP({
            failed = function( reason )
                if failures[id] then
                    local ran, err = xpcall(failures[id], debug.traceback, 504, reason)
                    if not ran then ErrorNoHalt(err) end
                end
            end,
            success = function( code, body, headers )
                if code ~= 200 then
                    if failures[id] then
                        local ran, err = xpcall(failures[id], debug.traceback, code, body, headers)
                        if not ran then ErrorNoHalt(err) end
                    end
                    return
                end
                local receivers = self.receivers
                if not receivers[id] then return end
                local ran, err = xpcall(receivers[id], debug.traceback, body)
                if not ran then ErrorNoHalt(err) end
            end,
            method = "GET",
            url = GetGlobalString("interserve") .. "/interserve/" .. sid .. "/" .. id .. "?uid=" .. uid
        })
    end

    interserve.unaccounted = {}
    net.Receive("Interserve:Initialize", function()
        local self = interserve
        local sid = net.ReadString()
        self.sid = sid

        local unaccounted = self.unaccounted
        self.unaccounted = {}

        for i=1, #unaccounted do
            local entry = unaccounted[i]
            local id = entry[2]
            local uid = entry[3]
            if entry[1] then
                local body = entry[4]
                interserve.post(uid, id, body)
            else
                interserve.get(uid, id)
            end
        end
    end)

    timer.Simple(0, function()
        net.Start("Interserve:Initialize")
        net.SendToServer()
    end)

    net.Receive("Interserve:Get", function()
        local self = interserve
        local id = net.ReadString()
        local uid = net.ReadString()
        local sid = self.sid

        if not sid then
            local unaccounted = interserve.unaccounted
            unaccounted[#unaccounted+1] = {false, id, uid}
            return
        end

        interserve.get(uid, id)
    end)

    net.Receive("Interserve:Post", function()
        local self = interserve
        local id = net.ReadString()
        local uid = net.ReadString()
        local sid = self.sid
        
        local body = ""
        if self.sending[id] then
            body = table.remove(self.sending[id], 1) or ""
        end

        if not sid then
            local unaccounted = interserve.unaccounted
            unaccounted[#unaccounted+1] = {true, id, uid, body}
            return
        end
        
        interserve.post(uid, id, body)
    end)
end