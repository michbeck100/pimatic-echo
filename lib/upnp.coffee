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
        if msg.indexOf('M-SEARCH') >= 0
          if msg.indexOf('ssdp:discover') > 0 || msg.indexOf('upnp:rootdevice') > 0 || msg.indexOf('device:basic:1') > 0
            env.logger.debug "<< server got: #{msg} from #{rinfo.address}:#{rinfo.port}"
            setTimeout(() =>
              response = @_getDiscoveryResponse()
              udpServer.send(response, 0, response.length, rinfo.port, rinfo.address, () =>
                env.logger.debug ">> sent response ssdp discovery response: #{response}"
              )
            , 650)
            env.logger.debug "complete sending all responses."

      udpServer.on 'listening', () =>
        address = udpServer.address()
        env.logger.debug "udp server listening on port #{address.port}"
        udpServer.addMembership('239.255.255.250')

      udpServer.bind(@upnpPort)

    _getDiscoveryResponse: () =>
      bridgeId = @_getHueBridgeIdFromMac()
      bridgeSNUUID = @_getSNUUIDFromMac()
      uuidPrefix = '2f402f80-da50-11e1-9b23-'

      template = "HTTP/1.1 200 OK\r\n" +
        "EXT:\r\n" +
        "CACHE-CONTROL: max-age=100\r\n" + # SSDP_INTERVAL
        "LOCATION: http://#{@ipAddress}:#{@serverPort}/description.xml\r\n" +
        "SERVER: FreeRTOS/6.0.5, UPnP/1.0, IpBridge/1.17.0\r\n" + # _modelName, _modelNumber
        "hue-bridgeid: #{bridgeId}\r\n" +
        "ST: urn:schemas-upnp-org:device:basic:1\r\n" + # _deviceType
        "USN: uuid:#{uuidPrefix}#{bridgeSNUUID}::upnp:rootdevice\r\n\r\n" # _uuid::_deviceType
      return Buffer.from(template)

    _getSNUUIDFromMac: =>
      return @macAddress.replace(/:/g, '').toLowerCase()

    _getHueBridgeIdFromMac: =>
      cleanMac = @_getSNUUIDFromMac()
      bridgeId =
        cleanMac.substring(0,6).toUpperCase() + 'FFFE' + cleanMac.substring(6).toUpperCase()
      return bridgeId

