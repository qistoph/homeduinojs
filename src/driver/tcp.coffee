events = require 'events'

net = require 'net'
Socket = net.Socket

Promise = require 'bluebird'

class TcpDriver extends events.EventEmitter

  constructor: (protocolOptions)->
    @host = protocolOptions.host
    @port = protocolOptions.port

  connect: (timeout, retries) ->
    # cleanup
    @ready = no
    @client = new Socket()

    @client.on('error', (error) => @emit('error', error) )
    @client.on('close', => @emit 'close' )
    @client.on('data', (data) =>
      # Sanitize data (Buffer)
      data = data.toString()
      line = data.replace(/\0/g, '').trim()
      @emit('data', line) 
      readyLine = line.match(/ready(?: ([a-z]+)-([0-9]+\.[0-9]+\.[0-9]+))?/)
      if readyLine?
        @ready = yes
        @emit 'ready', {tag: readyLine[1], version: readyLine[2]}
        return
      unless @ready
        # got, data but was not ready => reset
        @client.write("RESET\n")
        return
      @emit('line', line) 
    )

    return new Promise( (resolve, reject) =>
      resolver = resolve
      @client.connect({
        host: @host,
        port: @port
      }, =>
        new Promise( (resolve, reject) =>
          # write ping to force reset (see data listerner) if device was not reseted probably
          Promise.delay(1000).then( =>
            @client.write("PING\n")
          ).done()
          @once("ready", resolver)
        ).timeout(timeout).catch( (err) =>
          @removeListener("ready", resolver)
          if err.name is "TimeoutError" and retries > 0
            @emit 'reconnect', err
            # try to reconnect
            return @connect(timeout, retries-1)
          else
            throw err
        )
      )
    ).then('TcpDriver then test')

  disconnect: -> @client.end()

  write: (data) -> @client.write(data)

module.exports = TcpDriver
