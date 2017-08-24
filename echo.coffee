module.exports = (env) =>

  Promise = require 'bluebird'
  _ = require("lodash")
  udpServer = require('dgram').createSocket({ type: 'udp4', reuseAddr: true })
  async = require('async')

  class EchoPlugin extends env.plugins.Plugin
    devices: {}
    ipAddress = null

    knownTemplates: [
      'buttons',
      'dimmer',
      'huezlldimmable',
      'huezllcolortemp',
      'huezllcolor',
      'huezllextendedcolor',
      'huezllonoff',
      'led-light',
      'shutter'
      'switch',
      'tradfridimmer-dimmer',
      'tradfridimmer-temp'
    ]

    init: (app, @framework, @config) =>
      env.logger.info("Starting pimatic-echo...")

      networkInfo = @_getNetworkInfo()
      @ipAddress = networkInfo?.address
      @macAddress = networkInfo?.mac
      @upnpPort = 1900
      @serverPort = @framework.config.settings.httpServer.port

      @bootId = 1
      env.logger.debug "Using ip address: #{ipAddress}"

      @framework.deviceManager.deviceConfigExtensions.push(new EchoDeviceConfigExtension())

      nextId = 0
      @framework.on 'deviceAdded', (device) =>
        if @_isSupported(device) and not @_isExcluded(device)
          addDevice = (deviceName) =>
            uniqueId = ("0" + (++nextId)).slice(-2)
            @devices[uniqueId] = {
              device: device,
              name: deviceName,
              uniqueId: "00:17:88:5E:D3:" + uniqueId + "-" + uniqueId,
              changeState: (state) =>
                state = JSON.parse(Object.keys(state)[0])

                response = []
                if state.on?
                  response.push({ "success": { "/lights/#{uniqueId}/state/on" : state.on }})
                  @_changeStateTo(device, state.on)
                if state.bri?
                  response.push({ "success": { "/lights/#{uniqueId}/state/bri" : state.bri}})
                  @_setBrightness(device, state.bri)

                return JSON.stringify(response)
            }
          addDevice(@_getDeviceName(device))
          for additionalName in @_getAdditionalNames(device)
            addDevice(additionalName)
          env.logger.debug("successfully added device " + device.name)

      @framework.once "after init", =>

        @_startDiscoveryServer()
        @_startHueEmulator()

    _isSupported: (device) =>
      return device.template in @knownTemplates

    _isExcluded: (device) =>
      if device.config.echo?.exclude?
        return device.config.echo.exclude
      return false

    _getDeviceName: (device) =>
      if device.config.echo?.name?
        return device.config.echo.name
      else
        return device.name

    _getAdditionalNames: (device) =>
      if device.config.echo?.additionalNames?
        return device.config.echo.additionalNames
      else
        return []

    _changeStateTo: (device, state) =>
      if state
        @_turnOn(device)
      else
        @_turnOff(device)

    _turnOn: (device) =>
      switch device.template
        when "shutter" then device.moveUp().done()
        when "buttons" then device.buttonPressed(device.config.buttons[0].id)
        else device.turnOn().done()

    _turnOff: (device) =>
      switch device.template
        when "shutter" then device.moveDown().done()
        when "buttons" then env.logger.info("A ButtonsDevice doesn't support switching off")
        else device.turnOff().done()

    _getState: (device) =>
      switch device.template
        when "shutter" then false
        when "buttons" then false
        else device._state

    _getBrightness: (device) =>
      if device.hasAttribute("dimlevel")
        return device._dimlevel
      else if device.hasAttribute("brightness")
        # pimatic-led-light
        return device.brightness
      else
        return 0

    _setBrightness: (device, dimLevel) =>
      if device.hasAction("changeDimlevelTo")
        device.changeDimlevelTo(Math.round(dimLevel / 255.0 * 100.0)).done()

    _getNetworkInfo: =>
      networkInterfaces = require('os').networkInterfaces()
      for ifaceName, ifaceDetails of networkInterfaces
        for addrInfo in ifaceDetails
          if addrInfo.family == 'IPv4' && !addrInfo.internal
            return addrInfo
      return null

    _startDiscoveryServer: () =>
      udpServer.on 'error', (err) =>
        env.logger.error "server.error:\n#{err.message}"
        udpServer.close()

      udpServer.on 'message', (msg, rinfo) =>

        if msg.indexOf('M-SEARCH * HTTP/1.1') == 0 && msg.indexOf('ssdp:discover') > 0 &&
          msg.indexOf('urn:schemas-upnp-org:device:basic:1') > 0
            env.logger.debug "<< server got: #{msg} from #{rinfo.address}:#{rinfo.port}"
            async.eachSeries(@_getDiscoveryResponses(), (response, cb) =>
              udpServer.send(response, 0, response.length, rinfo.port, rinfo.address, () =>
                env.logger.debug ">> sent response ssdp discovery response: #{response}"
                cb()
              )
            , (err) =>
              env.logger.debug "complete sending all responses."
              if err
                env.logger.debug "Received error: #{JSON.stringify(err)}"
            )

      udpServer.on 'listening', () =>
        address = udpServer.address()
        env.logger.debug "server listening #{address.address}:#{address.port}"
        udpServer.addMembership('239.255.255.250')

      env.logger.debug "binding to port #{@upnpPort} for ssdp discovery"
      udpServer.bind(@upnpPort)

    _startHueEmulator: () =>
      env.logger.debug "starting hue emulator on port #{@serverPort}"

      @framework.app.get('/pimatic-echo/description.xml', (req, res) =>
        res.setHeader("Content-Type", "application/xml; charset=utf-8")
        res.status(200).send(@_getHueTemplate())
      )

      @framework.app.get('/pimatic-echo/favicon.ico', (req, res) =>
        res.status(200).send('')
      )
      @framework.app.get('/pimatic-echo/hue_logo_0.png', (req, res) =>
        res.status(200).send('')
      )
      @framework.app.get('/pimatic-echo/hue_logo_3.png', (req, res) =>
        res.status(200).send('')
      )

      @framework.app.get('/api/:userid/lights', (req, res) =>
        response = {}
        _.forOwn(@devices, (device, id) =>
          response[id] = @_getDeviceResponse(device)
        )

        res.status(200).send(JSON.stringify(response))
      )

      @framework.app.get('/api/:userid/lights/:id', (req, res) =>
        device = @devices[req.params["id"]]
        if device
          res.status(200).send(JSON.stringify(@_getDeviceResponse(device)))
        else
          res.status(404).send("Not found")
      )

      @framework.app.put('/api/:userid/lights/:id/state', (req, res) =>
        device = @devices[req.params["id"]]
        env.logger.debug("changing state for #{device.name}")
        response = device.changeState(req.body)
        res.status(200).send(response)
      )

      @framework.app.get('/api/:userid/*', (req, res) =>
        env.logger.debug("requesting #{req.originalUrl}")
      )

    _getDeviceResponse: (device) =>
      response = {
        state: {
          on: @_getState(device.device),
          bri: @_getBrightness(device.device),
          hue: 0,
          sat: 0,
          effect: "none",
          ct: 0,
          alert: "none",
          reachable: true
        },
        type: "Dimmable light",
        name: device.name,
        modelid: "LWB004",
        manufacturername: "Philips",
        uniqueid: device.uniqueId,
        swversion: "66012040"
      }
      return response

    _getHueTemplate: =>
      bridgeIdMac = @_getSNUUIDFromMac()
      response = """
<?xml version="1.0"?>
<root xmlns="urn:schemas-upnp-org:device-1-0">
  <specVersion>
    <major>1</major>
    <minor>0</minor>
  </specVersion>
  <URLBase>http://#{@ipAddress}:#{@serverPort}/</URLBase>
  <device>
    <deviceType>urn:schemas-upnp-org:device:Basic:1</deviceType>
    <friendlyName>Pimatic Hue bridge</friendlyName>
    <manufacturer>Royal Philips Electronics</manufacturer>
    <manufacturerURL>http://www.philips.com</manufacturerURL>
    <modelDescription>Philips hue Personal Wireless Lighting</modelDescription>
    <modelName>Philips hue bridge 2015</modelName>
    <modelNumber>BSB002</modelNumber>
    <modelURL>http://www.meethue.com</modelURL>
    <serialNumber>#{bridgeIdMac}</serialNumber>
    <UDN>uuid:2f402f80-da50-11e1-9b23-#{bridgeIdMac}</UDN>
    <serviceList>
      <service>
        <serviceType>(null)</serviceType>
        <serviceId>(null)</serviceId>
        <controlURL>(null)</controlURL>
        <eventSubURL>(null)</eventSubURL>
        <SCPDURL>(null)</SCPDURL>
      </service>
    </serviceList>
    <presentationURL>index.html</presentationURL>
    <iconList>
      <icon>
        <mimetype>image/png</mimetype>
        <height>48</height>
        <width>48</width>
        <depth>24</depth>
        <url>hue_logo_0.png</url>
      </icon>
      <icon>
        <mimetype>image/png</mimetype>
        <height>120</height>
        <width>120</width>
        <depth>24</depth>
        <url>hue_logo_3.png</url>
      </icon>
    </iconList>
  </device>
</root>
"""
      return response


    _getSNUUIDFromMac: =>
      return @macAddress.replace(/:/g, '').toLowerCase()

    _getHueBridgeIdFromMac: =>
      cleanMac = @_getSNUUIDFromMac()
      bridgeId =
        cleanMac.substring(0,6).toUpperCase() + 'FFFE' + cleanMac.substring(6).toUpperCase()
      return bridgeId

    _getHueSetup: (deviceId, friendlyName, port) =>

    _getDiscoveryResponses: () =>
      bridgeId = @_getHueBridgeIdFromMac()
      bridgeSNUUID = @_getSNUUIDFromMac()
      apiVersion = '1.19.0'
      uuidPrefix = '2f402f80-da50-11e1-9b23-'
      host = '239.255.255.250'
      responses = []

      responseTemplate1 = """
HTTP/1.1 200 OK
HOST: #{host}:#{@upnpPort}
CACHE-CONTROL: max-age=100
EXT:
LOCATION: http://#{@ipAddress}:#{@serverPort}/pimatic-echo/description.xml
SERVER: Linux/3.14.0 UPnP/1.0 IpBridge/#{apiVersion}
hue-bridgeid: #{bridgeId}
ST: upnp:rootdevice
USN: uuid:#{uuidPrefix}#{bridgeSNUUID}::upnp:rootdevice\r\n\r\n
"""
      responseTemplate2 = """
HTTP/1.1 200 OK
HOST: #{host}:#{@upnpPort}
CACHE-CONTROL: max-age=100
EXT:
LOCATION: http://#{@ipAddress}:#{@serverPort}/pimatic-echo/description.xml
SERVER: Linux/3.14.0 UPnP/1.0 IpBridge/#{apiVersion}
hue-bridgeid: #{bridgeId}
ST: uuid:#{uuidPrefix}#{bridgeSNUUID}
USN: uuid:#{uuidPrefix}#{bridgeSNUUID}\r\n\r\n
"""

      responseTemplate3 = """
HTTP/1.1 200 OK
HOST: #{host}:#{@upnpPort}
CACHE-CONTROL: max-age=100
LOCATION: http://#{@ipAddress}:#{@serverPort}/pimatic-echo/description.xml
SERVER: Linux/3.14.0 UPnP/1.0 IpBridge/#{apiVersion}
hue-bridgeid: #{bridgeId}
ST: urn:schemas-upnp-org:device:basic:1
USN: uuid:#{uuidPrefix}#{bridgeSNUUID}\r\n\r\n
"""

      responses.push(new Buffer(responseTemplate1))
      responses.push(new Buffer(responseTemplate2))
      responses.push(new Buffer(responseTemplate3))

      return responses


  class EchoDeviceConfigExtension
    configSchema:
      echo:
        description: "Additional options specific for use with pimatic-echo"
        type: "object"
        properties:
          name:
            description: "change the name of your device"
            type: "string"
            required: no
          additionalNames:
            description: "additional names for your device"
            type: "array"
            required: no
            items:
              type: "string"
          exclude:
            description: "exclude this device from your Amazon echo"
            type: "boolean"
            default: false

    extendConfigShema: (schema) ->
      for name, def of @configSchema
        schema.properties[name] = _.cloneDeep(def)

    applicable: (schema) ->
      return yes

    apply: (config, device) -> # do nothing here

  plugin = new EchoPlugin()

  return plugin
