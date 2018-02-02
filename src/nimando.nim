import asyncdispatch, asyncnet, threadpool, protocol,
        queues, crpl, strutils, tables

var socket: AsyncSocket
var pings: queues.Queue[string]
var sock_msg_line = newFuture[string]()
var modi: string

var session: string = "-"
var cip: string = "-"
var session_x: string = "-"
var cip_x: string = "-"

var callbacks = tables.initTable[string, seq[proc(msg: Message): void]]()
proc init_connection(params: varargs[string]): string

proc subscribe(cmd: string, callback: proc(msg: Message): void): void =
  if tables.hasKey(callbacks, cmd):
    callbacks[cmd].add(callback)
  else:
    tables.add(callbacks, cmd, @[callback])
    
proc publish(cmd: string, msg: Message): void =
  if tables.hasKey(callbacks, cmd):
    let clbs = callbacks[cmd]
    for clb in clbs:
      clb(msg)

proc pong_loop() {.async.} =
  pings = initQueue[string]()
  while true:
    await asyncdispatch.sleepAsync(9000)
    if pings.len > 5:
      if asyncnet.isClosed(socket) == false:
        asyncnet.close(socket)
      sock_msg_line.fail(newException(ValueError, "Pong timeout"))
      break
    asyncdispatch.poll()
    
proc ping_loop(socket: AsyncSocket) {.async.} =
  while true:
    await asyncdispatch.sleepAsync(19000)
    let msg = create_message("ping")
    if asyncnet.isClosed(socket) == false:
      asyncCheck asyncnet.send(socket, msg)
      pings.add(msg)
    asyncdispatch.poll()

proc send_authentication(): void =
  let msg = create_message("authentication", cip, session)
  discard asyncnet.send(socket, msg)
    
proc try_connect_server(address: string, port: int) {.async.} =
  while true:
    await asyncdispatch.sleepAsync(5000)
    try: 
      echo("Connecting to server ", address & ", port " & $ port)
      await asyncnet.connect(socket, address, port.Port)
      echo( "Successfull!")
      asyncdispatch.asyncCheck ping_loop(socket)
      asyncdispatch.asyncCheck pong_loop()
      break
    except:
      echo("Fail!")
      if asyncnet.isClosed(socket) == false:
        asyncnet.close(socket)
      socket = asyncnet.newAsyncSocket()
    asyncdispatch.poll()

proc compare_cip(servercip: string): void =
  echo("compare")
  if servercip != cip_x:
    echo("Ip changed, new authentication ... ")
    send_authentication()
  else:
    echo("Ip is the same ... ")
    
proc connect_server(address: string, port: int)
    {.async.} =

  await try_connect_server(address, port)
  var payload: string
  while true:
    try:
      #echo("Client await for msgs")
      sock_msg_line = asyncnet.recvLine(socket)
      payload = await sock_msg_line
    except:
      echo "Server connection aborted ..."
      break
    if payload.len == 0:
      echo("Server connection aborted ...")
      await asyncdispatch.sleepAsync(10000)
      break
    else:
      let msg: Message = parse_message(payload)
      case msg.cmd:
        of "error":
          echo("error")
          asyncnet.close(socket)
          break
        of "pong":
          echo("Client receive pong message ", msg.cip)
          compare_cip(msg.cip)
          discard pings.pop()
        else:
          publish(msg.cmd, msg)
    asyncdispatch.poll()   
  discard init_connection([address, $ port, cip, session])

proc init_connection(params: varargs[string]): string =
  socket = asyncnet.newAsyncSocket()

  if cip == "-" and session == "-":
    cip = params[2]
    session = params[3]
  
  case modi
  of "repl":
    echo("init connection per repl")
    asyncdispatch.asyncCheck connect_server(params[0], parseInt(params[1]))
  of "cmd":
    echo("init connection per cmd")
    waitFor connect_server(params[0], parseInt(params[1]))

proc authorization(msg: Message): void =
  echo("Authorization successfull")
  cip_x = msg.cip
  session_x = msg.session

proc authentication_error(msg: Message): void =
  echo("Authentication error")
  
proc defaults(): void =
  param_to_callback("--c",
                    "--c server=localhost port=4004 name=admin password=admin",
                    init_connection)
  subscribe("authorization", authorization)
  
proc start*(params: string): void =
  modi = "cmd"
  echo("Start per cmd args ", params)
  defaults()
  start_cmd(params)

proc start*(): void =
  modi = "repl"
  defaults()  
  waitFor start_repl()

