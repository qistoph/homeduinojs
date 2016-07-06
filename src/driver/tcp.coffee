events = require 'events'

net = require 'net'

Promise = require 'bluebird'
Promise.promisifyAll(SerialPort.prototype)

class TcpDriver extends events.EventEmitter

  constructor: (protocolOptions)->
    @host = protocolOptions.host
    @port = protocolOptions.port

  connect: (timeout, retries) ->
    # cleanup
    @ready = no
    @client = net.createConnection @host, @port

    @client.on('error', (error) => @emit('error', error) )
    @client.on('close', => @emit 'close' )

    return @serialPort.openAsync().then( =>
      resolver = null

      # setup data listner
      @serialPort.on("data", (data) => 
        # Sanitize data
        line = data.replace(/\0/g, '').trim()
        @emit('data', line) 
        readyLine = line.match(/ready(?: ([a-z]+)-([0-9]+\.[0-9]+\.[0-9]+))?/)
        if readyLine?
          @ready = yes
          @emit 'ready', {tag: readyLine[1], version: readyLine[2]}
          return
        unless @ready
          # got, data but was not ready => reset
          @serialPort.writeAsync("RESET\n").catch( (error) -> @emit("error", error) )
          return
        @emit('line', line) 
      )

      return new Promise( (resolve, reject) =>
        # write ping to force reset (see data listerner) if device was not reseted probably
        Promise.delay(1000).then( =>
          @serialPort.writeAsync("PING\n").catch(reject)
        ).done()
        resolver = resolve
        @once("ready", resolver)
      ).timeout(timeout).catch( (err) =>
        @removeListener("ready", resolver)
        @serialPort.removeAllListeners('data')
        if err.name is "TimeoutError" and retries > 0
          @emit 'reconnect', err
          # try to reconnect
          return @connect(timeout, retries-1)
        else
          throw err
      )
    )

  disconnect: -> @serialPort.closeAsync()

  write: (data) -> @serialPort.writeAsync(data)

module.exports = SerialPortDriver
