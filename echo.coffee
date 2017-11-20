module.exports = (env) =>

  _ = require('lodash')
  async = require('async')
  bodyParser = require('body-parser')
  express = require('express')
  udpServer = require('dgram').createSocket({ type: 'udp4', reuseAddr: true })

  class EchoPlugin extends env.plugins.Plugin
    ipAddress = null

    dimmerTemplates: [
      'dimmer',
      'huezlldimmable',
      'huezllcolortemp',
      'huezllcolor',
      'huezllextendedcolor',
      'led-light',
      'tradfridimmer-dimmer',
      'tradfridimmer-temp'
    ]

    switchTemplates: [
      'buttons',
      'huezllonoff',
      'shutter'
      'switch'
    ]

    heatingTemplates: [
      'maxcul-heating-thermostat',
      'thermostat',
      'mythermostat'
    ]

    init: (app, @framework, @config) =>
      env.logger.info("Starting pimatic-echo...")

      networkInfo = @_getNetworkInfo()
      if networkInfo == null && (!@config.address || !@config.mac)
        throw new Error("Unable to obtain network information."
          +" Please provide ip and mac address in plugin config!")

      @ipAddress = if @config.address then @config.address else networkInfo.address
      @macAddress = if @config.mac then @config.mac else networkInfo.mac
      @upnpPort = 1900
      @serverPort = @config.port

      @bootId = 1
      env.logger.debug "Using ip address : #{@ipAddress}"

      @framework.deviceManager.deviceConfigExtensions.push(new EchoDeviceConfigExtension())

      devices = {}

      @framework.on 'deviceAdded', (device) =>
        addDevice = (deviceName, buttonId) => return # do nothing

        if @_isExcluded(device)
          return

        if @_isSupported(device)
          if Object.keys(devices).length <= 50
            addDevice = (deviceName, buttonId) =>
              uniqueId = ("0" + (Object.keys(devices).length + 1).toString(16))
                .slice(-2).toUpperCase()
              devices[uniqueId] = {
                device: device,
                name: deviceName,
                uniqueId: "00:17:88:5E:D3:" + uniqueId + "-" + uniqueId,
                changeState: (state) =>
                  env.logger.debug("changing state for #{deviceName}: #{@toJSON(state)}")
                  response = []
                  if state.bri?
                    env.logger.debug("setting brightness of #{deviceName} to #{state.bri}")
                    @_setBrightness(device, state.bri)
                    response.push({ "success": { "/lights/#{uniqueId}/state/bri" : state.bri }})
                  else if state.on?
                    env.logger.debug("setting state of #{deviceName} to #{state.on}")
                    @_changeStateTo(device, state.on, buttonId)
                    response.push({ "success": { "/lights/#{uniqueId}/state/on" : state.on }})

                  return @toJSON(response)
              }
              env.logger.debug("successfully added device #{deviceName}")
        else
          throw new Error("unsupported device type: #{device.template})")
        if device.template is 'buttons'
          addDevice(button.text, button.id) for button in device.config.buttons
        else
          addDevice(@_getDeviceName(device))
          for additionalName in @_getAdditionalNames(device)
            addDevice(additionalName)

      @framework.once "after init", =>
        @_startDiscoveryServer()
        @_startEmulator(devices)

    _isSupported: (device) =>
      return @_isDimmer(device) || @_isSwitch(device) || @_isHeating(device)

    _isDimmer: (device) =>
      return device.template in @dimmerTemplates

    _isSwitch: (device) =>
      return device.template in @switchTemplates

    _isHeating: (device) =>
      return device.template in @heatingTemplates

    _isExcluded: (device) =>
      if @_isSupported(device)
        # devices with no echo config get the default config
        if !device.config.hasOwnProperty('echo')
          device.config.echo = {}
          device.config.echo.active = false
        if device.config.echo.hasOwnProperty('exclude')
          device.config.echo.active = !device.config.echo.exclude
          delete device.config.echo.exclude
          env.logger.info "exclude flag for device #{device.name} migrated"
        return device.config.echo.active is false

      return true

    _getDeviceName: (device) =>
      return if !!device.config.echo?.name then device.config.echo.name else device.name

    _getAdditionalNames: (device) =>
      if device.config.echo?.additionalNames?
        return device.config.echo.additionalNames
      else
        return []

    _changeStateTo: (device, state, buttonId) =>
      if state
        @_turnOn(device, buttonId)
      else
        @_turnOff(device)

    _turnOn: (device, buttonId) =>
      if @_isHeating(device)
        device.changeTemperatureTo(device.config.comfyTemp).done()
      else
        switch device.template
          when "shutter"
            device.moveUp().done()
          when "buttons"
            if buttonId
              device.buttonPressed(buttonId).done()
            else
              device.buttonPressed(device.config.buttons[0].id).done()
          else
            device.turnOn().done()

    _turnOff: (device) =>
      if @_isHeating(device)
        device.changeTemperatureTo(device.config.ecoTemp).done()
      else
        switch device.template
          when "shutter" then device.moveDown().done()
          when "buttons" then env.logger.info("A ButtonsDevice doesn't support switching off")
          else device.turnOff().done()

    _getState: (device) =>
      if @_isHeating(device)
        return device._temperatureSetpoint > device.config.ecoTemp
      else
        switch device.template
          when "shutter" then false
          when "buttons" then false
          when "led-light" then device.power == 'on' || device.power == true
          else device._state

    _getBrightness: (device) =>
      brightness = 0.0
      if device.hasAttribute("dimlevel")
        brightness = device._dimlevel
      else if device.hasAttribute("brightness")
        # pimatic-led-light
        brightness = device.brightness
      else if @_isSwitch(device)
        brightness = if @_getState(device) then 100.0 else 0.0
      else if @_isHeating(device)
        brightness = device._temperatureSetpoint
      return Math.round(brightness / 100 * 255.0)

    _setBrightness: (device, dimLevel, buttonId) =>
      if device.hasAction("changeDimlevelTo")
        device.changeDimlevelTo(Math.round(dimLevel / 255.0 * 100.0)).done()
      else if @_isSwitch(device)
        @_changeStateTo(device, dimLevel > 0, buttonId)
      else if @_isHeating(device)
        device.changeTemperatureTo(Math.round(dimLevel / 255.0 * 100 )).done()

    _getNetworkInfo: =>
      networkInterfaces = require('os').networkInterfaces()
      for ifaceName, ifaceDetails of networkInterfaces
        for addrInfo in ifaceDetails
          if addrInfo.family == 'IPv4' && !addrInfo.internal
            return addrInfo
      env.logger.warn("No network interface found.")
      return null

    _startDiscoveryServer: () =>
      udpServer.on 'error', (err) =>
        env.logger.error "server.error:\n#{err.message}"
        udpServer.close()

      udpServer.on 'message', (msg, rinfo) =>

        if msg.indexOf('M-SEARCH * HTTP/1.1') == 0 && msg.indexOf('ssdp:discover') > 0
          if msg.indexOf('ST: urn:schemas-upnp-org:device:basic:1') > 0 ||
              msg.indexOf('ST: upnp:rootdevice') > 0 || msg.indexOf('ST: ssdp:all') > 0
            env.logger.debug "<< server got: #{msg} from #{rinfo.address}:#{rinfo.port}"
            async.eachSeries(@_getDiscoveryResponses(), (response, cb) =>
              udpServer.send(response, 0, response.length, rinfo.port, rinfo.address, () =>
                if @config.trace
                  env.logger.debug ">> sent response ssdp discovery response: #{response}"
                cb()
              )
            , (err) =>
              env.logger.debug "complete sending all responses."
              if err
                env.logger.debug "Received error: #{@toJSON(err)}"
            )

      udpServer.on 'listening', () =>
        address = udpServer.address()
        env.logger.debug "udp server listening on port #{address.port}"
        udpServer.addMembership('239.255.255.250')

      udpServer.bind(@upnpPort)

    _startEmulator: (devices) =>
      emulator = express()
      emulator.use bodyParser.json(type: "application/x-www-form-urlencoded", limit: '1mb')
      emulator.use bodyParser.json(limit: '1mb')

      if @config.trace
        logger = (req, res, next) =>
          env.logger.debug "Request to #{req.originalUrl}"
          if Object.keys(req.body).length > 0
            env.logger.debug "Payload: #{@toJSON(req.body)}"
          env.logger.debug "Headers: #{@toJSON(req.headers)}"
          next()
        emulator.use(logger)

      emulator.get('/description.xml', (req, res) =>
        res.setHeader("Content-Type", "application/xml; charset=utf-8")
        res.status(200).send(@_getHueTemplate())
      )

      emulator.get('/favicon.ico', (req, res) =>
        res.status(200).send('')
      )
      emulator.get('/hue_logo_0.png', (req, res) =>
        res.status(200).send('')
      )
      emulator.get('/hue_logo_3.png', (req, res) =>
        res.status(200).send('')
      )

      emulator.post('/api', (req, res) =>
        response = []
        response.push({ "success": { "username": "83b7780291a6ceffbe0bd049104df"}})
        res.setHeader("Content-Type", "application/json")
        res.status(200).send(@toJSON(response))
      )

      emulator.get('/api/:userid/lights', (req, res) =>
        response = {}
        _.forOwn(devices, (device, id) =>
          response[id] = @_getDeviceResponse(device)
        )
        res.setHeader("Content-Type", "application/json")
        res.status(200).send(@toJSON(response))
      )

      emulator.get('/api/:userid/lights/:id', (req, res) =>
        device = devices[req.params["id"]]
        if device
          res.setHeader("Content-Type", "application/json")
          res.status(200).send(@toJSON(@_getDeviceResponse(device)))
        else
          res.status(404).send("Not found")
      )

      emulator.put('/api/:userid/lights/:id/state', (req, res) =>
        device = devices[req.params["id"]]
        response = device.changeState(req.body)
        res.setHeader("Content-Type", "application/json")
        res.status(200).send(response)
      )

      emulator.listen(@serverPort, () =>
        env.logger.info "started hue emulator on port #{@serverPort}"
      )

    _getDeviceResponse: (device) =>
      return {
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
LOCATION: http://#{@ipAddress}:#{@serverPort}/description.xml
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
LOCATION: http://#{@ipAddress}:#{@serverPort}/description.xml
SERVER: Linux/3.14.0 UPnP/1.0 IpBridge/#{apiVersion}
hue-bridgeid: #{bridgeId}
ST: uuid:#{uuidPrefix}#{bridgeSNUUID}
USN: uuid:#{uuidPrefix}#{bridgeSNUUID}\r\n\r\n
"""

      responseTemplate3 = """
HTTP/1.1 200 OK
HOST: #{host}:#{@upnpPort}
CACHE-CONTROL: max-age=100
LOCATION: http://#{@ipAddress}:#{@serverPort}/description.xml
SERVER: Linux/3.14.0 UPnP/1.0 IpBridge/#{apiVersion}
hue-bridgeid: #{bridgeId}
ST: urn:schemas-upnp-org:device:basic:1
USN: uuid:#{uuidPrefix}#{bridgeSNUUID}\r\n\r\n
"""

      responses.push(new Buffer(responseTemplate1))
      responses.push(new Buffer(responseTemplate2))
      responses.push(new Buffer(responseTemplate3))

      return responses

    _getDeviceSetup: (device) =>
      @bootId++
      response = "<?xml version=\"1.0\"?><root>"
      if !device
        env.logger.debug 'rendering all device setup info..'

        _.forOwn(@devices, (v, k) =>
          response += """
    <device>
        <deviceType>urn:pimatic:device:controllee:1</deviceType>
        <friendlyName>#{v.name}</friendlyName>
        <manufacturer>Belkin International Inc.</manufacturer>
        <modelName>Emulated Socket</modelName>
        <modelNumber>3.1415</modelNumber>
        <UDN>uuid:Socket-1_0-#{k}</UDN>
    </device>
    """
        )
      else
        env.logger.debug "rendering device setup for device: #{device.name}"
        response += """
    <device>
        <deviceType>urn:pimatic:device:controllee:1</deviceType>
        <friendlyName>#{device.name}</friendlyName>
        <manufacturer>Belkin International Inc.</manufacturer>
        <modelName>Emulated Socket</modelName>
        <modelNumber>3.1415</modelNumber>
        <UDN>uuid:Socket-1_0-#{device.id}</UDN>
        <serialNumber>#{device.id}</serialNumber>
        <binaryState>#{if @_getState(device.device) then "1" else "0"}</binaryState>
        <serviceList>
          <service>
            <serviceType>urn:Belkin:service:basicevent:1</serviceType>
            <serviceId>urn:Belkin:serviceId:basicevent1</serviceId>
            <controlURL>/upnp/control/basicevent1</controlURL>
            <eventSubURL>/upnp/event/basicevent1</eventSubURL>
            <SCPDURL>/eventservice.xml</SCPDURL>
          </service>
        </serviceList>
    </device>"""

      response += "</root>"
      return response

    toJSON: (json) =>
      return JSON.stringify(json, null, 2)

  class EchoDeviceConfigExtension
    configSchema:
      echo:
        description: "Additional options specific for use with pimatic-echo"
        type: "object"
        properties:
          name:
            description: "change the name of your device"
            type: "string"
            default: ""
          additionalNames:
            description: "additional names for your device"
            type: "array"
            required: no
            items:
              type: "string"
          exclude:
            description: "Exclude this device. Deprecated in favor of active flag."
            type: "boolean"
            default: false
          active:
            description: "make this device available for Alexa"
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
