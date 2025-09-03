# interserve
Used as an alternative to large and deferred data transfer from clients and servers when dealing with large data that requires net.* splitting.\
This initially was an experiment to see if we can use HTTP as a form of deferred networking, while not requiring any form of external communication outside the process.\
Courtesy of Buildstruct for allowing me to reliably test this under their player-base.

**This has only been tested on a 25 player sandbox server, usage on high-capacity servers is discuraged as I have not realiably been able to test this.**\
**Do note that this does open ports & accepts HTTP requests, we recommend configuring this behind mitigation services such as Cloudflare.**

## Pros/Cons
This is just a simple list of pros/cons, there are alternatives that do not require interstellar such as `gm_express`, however it is to be note that in the future a similar API for this could be strictly made without using interstellar.
```diff
+ Deferred handling of incoming data, only aligned with source-engine's thread during lua execution.
+ Able to send large amounts of data greater than net 64 KB limit.
+ Endpoints are dynamically generated & unique per-player.
+ Server authoritive networking, requires server acknowledgement before serving.

- Susceptible to Denial of Service if not setup correctly.
- Not aligned with source-engine reliable data, may arrive later than sooner.
- Possible timeouts during window of receiving.
- Each server must have a unique extra port opened.
```

## Configuration
- `interserve_address [string]` - Client's inverserve address or domain (format IP [no port] or domain)
- `interserve_iport [number]` - Server's interserve port (must be a valid port!)
- `interserve_port [number]` - Client's inverserve port (must be the same or targeting a proxy)
- `interserve_ssl [boolean]` - Client's inverserve SSL support
- `interserve_trusted [boolean]` - Client's inverserve trusted proxy support
- `interserve_timeout [number]` - Server's interserve timeout in seconds

I recommend that on each server instance inside `server.cfg` you set the `interserve_iport`.\
By default it targets `25500` which if you are using multiple instances will stop other server instances from attaching to the port if already in-use.

## Functions

### interserve:add(id: string)
- Adds a new interserve endpoint, cannot use interserve without registering an endpoint.
- Only available on server realms.

### interserve:remove(id: string)
- Removes an existing interserve endpoint.
- Only available on server realms.

### interserve:exists(id: string)
- Checks if an interserve endpoint has been registered.
- Only available on server realms.

### interserve:receive(id: string, callback?: function)
- A callback for incoming data.
- callback: function(data: string, invoker?: Player)

### interserve:send(id: string, data: string, invoker?: Player | Player[])
- For sending data to the server or client through interserve.
- invoker: the target player, only available on server realms.

### interserve:broadcast(id: string, data: string)
- For sending data to all players on the server through interserve.
- Only available on server realms.

### interserve:omit(id: string, data: string, ignore: Player | Player[])
- For sending data to players with an exclusion on the server through interserve.
- Only available on server realms.

### interserve:failure(id: string, callback?: function)
- A callback for when failures are captured under interserve.
- callback: function(code: number, reason: string, headers?: {[index: string]: string})
- Only available on client realms.

### interserve:interrupt(id: string, callback?: function)
- A callback for confirmations to uploads and downloads during threaded processing.
- Returning false in the callback will stop the process from continuing to receivers.
- callback: function(invoker: Player, req: iot.serve.request): boolean?
- Only available on server realms.

### interserve:handshake(id: string, callback?: function)
- A callback for handshake confirmations to upload to the server
- Returning false in the callback will stop the upload process from continuing to interrupt.
- callback: function(invoker: Player, size: number): boolean?
- Only available on server realms.

## Roadmap
- ~~Add further endpoint obfuscation by using salt'ed MD5/SHA on startup.~~
- Built-in logger and profiler for endpoint monitoring.

Other additions to this depends on interstellar, and if I can implement it reliably.
