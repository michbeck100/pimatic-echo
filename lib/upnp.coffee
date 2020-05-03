module.exports = (env) =>

  _ = require('lodash')
  semver = require('semver')

  udpServer = require('dgram').createSocket({ type: 'udp4', reuseAddr: true })

  class UpnpServer

    constructor: (@ipAddress, @serverPort, @macAddress, @upnpPort) ->

    start: () =>

      udpServer.on 'error', (err) =>
        env.logger.error "server.error:\n#{err.message}"
        udpServer.close()

      udpServer.on 'message', (msg, rinfo) =>
        if msg.indexOf('M-SEARCH * HTTP/1.1') == 0 && msg.indexOf('ssdp:discover') > 0
          if msg.indexOf('ST: urn:schemas-upnp-org:device:basic:1') > 0 || msg.indexOf('ST: upnp:rootdevice') > 0 || msg.indexOf('ST: ssdp:all') > 0
            env.logger.debug "<< server got: #{msg} from #{rinfo.address}:#{rinfo.port}"
            @_getDiscoveryResponses().forEach((response) =>
              setTimeout(() =>
                udpServer.send(response, 0, response.length, rinfo.port, rinfo.address, () =>
                  env.logger.debug ">> sent response ssdp discovery response: #{response}"
                )
              , 650)
            )
            env.logger.debug "complete sending all responses."

      udpServer.on 'listening', () =>
        address = udpServer.address()
        env.logger.debug "udp server listening on port #{address.port}"
        udpServer.addMembership('239.255.255.250')

      udpServer.bind(@upnpPort)

    _getDiscoveryResponses: () =>
      bridgeId = @_getHueBridgeIdFromMac()
      bridgeSNUUID = @_getSNUUIDFromMac()
      uuidPrefix = '2f402f80-da50-11e1-9b23-'

      responses = []

      template = "HTTP/1.1 200 OK\r\n" +
        "HOST: 239.255.255.250:#{@upnpPort}\r\n" +
        "CACHE-CONTROL: max-age=100\r\n" +
        "EXT:\r\n" +
        "LOCATION: http://#{@ipAddress}:#{@serverPort}/description.xml\r\n" +
        "SERVER: Linux/3.14.0 UPnP/1.0 IpBridge/1.19.0\r\n" +
        "hue-bridgeid: #{bridgeId}\r\n" +
        "ST: upnp:rootdevice\r\n" +
        "USN: uuid:#{uuidPrefix}#{bridgeSNUUID}::upnp:rootdevice\r\n\r\n"
      responses.push(@_buffer(template))

      template = "HTTP/1.1 200 OK\r\n" +
        "HOST: 239.255.255.250:#{@upnpPort}\r\n" +
        "CACHE-CONTROL: max-age=100\r\n" +
        "EXT:\r\n" +
        "LOCATION: http://#{@ipAddress}:#{@serverPort}/description.xml\r\n" +
        "SERVER: Linux/3.14.0 UPnP/1.0 IpBridge/1.19.0\r\n" +
        "hue-bridgeid: #{bridgeId}\r\n" +
        "ST: uuid:#{uuidPrefix}#{bridgeSNUUID}\r\n" +
        "USN: uuid:#{uuidPrefix}#{bridgeSNUUID}\r\n\r\n"
      responses.push(@_buffer(template))

      template = "HTTP/1.1 200 OK\r\n" +
        "HOST: 239.255.255.250:#{@upnpPort}\r\n" +
        "CACHE-CONTROL: max-age=100\r\n" +
        "EXT:\r\n" +
        "LOCATION: http://#{@ipAddress}:#{@serverPort}/description.xml\r\n" +
        "SERVER: Linux/3.14.0 UPnP/1.0 IpBridge/1.19.0\r\n" +
        "hue-bridgeid: #{bridgeId}\r\n" +
        "ST: urn:schemas-upnp-org:device:basic:1\r\n" +
        "USN: uuid:#{uuidPrefix}#{bridgeSNUUID}\r\n\r\n"
      responses.push(@_buffer(template))

      return responses

    _buffer: (template) =>
      if semver.lt(process.version, '6.0.0')
        return new Buffer(template)
      return Buffer.from(template)

    _getSNUUIDFromMac: =>
      return @macAddress.replace(/:/g, '').toLowerCase()

    _getHueBridgeIdFromMac: =>
      cleanMac = @_getSNUUIDFromMac()
      bridgeId =
        cleanMac.substring(0,6).toUpperCase() + 'FFFE' + cleanMac.substring(6).toUpperCase()
      return bridgeId

