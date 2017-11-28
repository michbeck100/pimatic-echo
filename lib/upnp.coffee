module.exports = (env) =>

  _ = require('lodash')
  async = require('async')

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
            async.eachSeries(@_getDiscoveryResponses(), (response, cb) =>
              udpServer.send(response, 0, response.length, rinfo.port, rinfo.address, () =>
                env.logger.debug ">> sent response ssdp discovery response: #{response}"
                cb()
              )
            , (err) =>
              env.logger.debug "complete sending all responses."
              if err
                env.logger.warn "Received error: #{JSON.stringify(err)}"
            )

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

      _.forEach(["upnp:rootdevice", "urn:schemas-upnp-org:device:basic:1", "uuid: #{uuidPrefix}#{bridgeSNUUID}"], (st) =>

        template = """
HTTP/1.1 200 OK
HOST: 239.255.255.250:#{@upnpPort}
EXT:
CACHE-CONTROL: max-age=100
LOCATION: http://#{@ipAddress}:#{@serverPort}/description.xml
SERVER: FreeRTOS/7.4.2, UPnP/1.0, IpBridge/1.19.0
hue-bridgeid: #{bridgeId}
ST: #{st}
USN: uuid:#{uuidPrefix}#{bridgeSNUUID}::upnp:rootdevice\r\n\r\n
"""
        responses.push(new Buffer(template))
      )

      return responses


    _getSNUUIDFromMac: =>
      return @macAddress.replace(/:/g, '').toLowerCase()

    _getHueBridgeIdFromMac: =>
      cleanMac = @_getSNUUIDFromMac()
      bridgeId =
        cleanMac.substring(0,6).toUpperCase() + 'FFFE' + cleanMac.substring(6).toUpperCase()
      return bridgeId

