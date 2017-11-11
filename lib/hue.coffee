module.exports = (env) =>
  _ = require('lodash')

  Emulator = require('./emulator')(env)

  class Hue extends Emulator

    dimmerTemplates = [
      'dimmer',
      'huezlldimmable',
      'huezllcolortemp',
      'huezllcolor',
      'huezllextendedcolor',
      'led-light',
      'tradfridimmer-dimmer',
      'tradfridimmer-temp'
    ]


    heatingTemplates = [
      'maxcul-heating-thermostat',
      'thermostat',
      'mythermostat'
    ]

    dimmers = {}

    constructor: (@macAddress, @ipAddress, @serverPort, @upnpPort) ->

    addDevice: (device) =>
      if Object.keys(dimmers).length <= 50
        return (deviceName, buttonId) =>
          uniqueId = ("0" + (Object.keys(dimmers).length + 1).toString(16))
            .slice(-2).toUpperCase()
          dimmers[uniqueId] = {
            device: device,
            name: deviceName,
            uniqueId: "00:17:88:5E:D3:" + uniqueId + "-" + uniqueId,
            changeState: (state) =>
              env.logger.debug("changing state for #{deviceName}: #{JSON.stringify(state)}")
              state = JSON.parse(Object.keys(state)[0])
              response = []
              if state.bri?
                env.logger.debug("setting brightness of #{deviceName} to #{state.bri}")
                @_setBrightness(device, state.bri)
              else if state.on?
                env.logger.debug("setting state of #{deviceName} to #{state.on}")
                @changeStateTo(device, state.on, buttonId)
              response.push({ "success": { "/lights/#{uniqueId}/state/on" : state.on }})
              response.push({ "success": { "/lights/#{uniqueId}/state/bri" : state.bri }})

              return JSON.stringify(response)
          }
          env.logger.debug("successfully added device #{deviceName} as dimmable light")


    isSupported: (device) =>
      return @_isDimmer(device) || @_isHeating(device)

    _isDimmer: (device) =>
      return device.template in dimmerTemplates

    _isHeating: (device) =>
      return device.template in heatingTemplates

    _turnOn: (device, buttonId) =>
      if @_isHeating(device)
        device.changeTemperatureTo(device.config.comfyTemp).done()
      else
        device.turnOn().done()

    _turnOff: (device) =>
      if @_isHeating(device)
        device.changeTemperatureTo(device.config.ecoTemp).done()
      else
        device.turnOff().done()

    _getState: (device) =>
      if @_isHeating(device)
        return device._temperatureSetpoint > device.config.ecoTemp
      else if device.template is "led-light"
        return device.power == 'on' || device.power == true
      else
        return device._state

    _getBrightness: (device) =>
      brightness = 0.0
      if device.hasAttribute("dimlevel")
        brightness = device._dimlevel
      else if device.hasAttribute("brightness")
        # pimatic-led-light
        brightness = device.brightness
      else if @_isHeating(device)
        brightness = device._temperatureSetpoint
      return Math.round(brightness / 100 * 255.0)

    _setBrightness: (device, dimLevel) =>
      if device.hasAction("changeDimlevelTo")
        device.changeDimlevelTo(Math.round(dimLevel / 255.0 * 100.0)).done()
      else if @_isHeating(device)
        device.changeTemperatureTo(Math.round(dimLevel / 255.0 * 100 )).done()

    getDiscoveryResponses: () =>
      responses = []
      bridgeId = @_getHueBridgeIdFromMac()
      bridgeSNUUID = @_getSNUUIDFromMac()
      apiVersion = '1.19.0'
      uuidPrefix = '2f402f80-da50-11e1-9b23-'
      host = '239.255.255.250'

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

    _getSNUUIDFromMac: =>
      return @macAddress.replace(/:/g, '').toLowerCase()

    _getHueBridgeIdFromMac: =>
      cleanMac = @_getSNUUIDFromMac()
      bridgeId =
        cleanMac.substring(0,6).toUpperCase() + 'FFFE' + cleanMac.substring(6).toUpperCase()
      return bridgeId

    configure: (emulator) =>
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
        res.status(200).send(JSON.stringify(response))
      )

      emulator.get('/api/:userid/lights', (req, res) =>
        response = {}
        _.forOwn(dimmers, (device, id) =>
          response[id] = @_getDeviceResponse(device)
        )

        res.status(200).send(JSON.stringify(response))
      )

      emulator.get('/api/:userid/lights/:id', (req, res) =>
        device = dimmers[req.params["id"]]
        if device
          res.status(200).send(JSON.stringify(@_getDeviceResponse(device)))
        else
          res.status(404).send("Not found")
      )

      emulator.put('/api/:userid/lights/:id/state', (req, res) =>
        device = dimmers[req.params["id"]]
        response = device.changeState(req.body)
        res.status(200).send(response)
      )

    start: (emulator) =>
      emulator.listen(@serverPort, () =>
        env.logger.info "started hue emulator on port #{@serverPort}"
      )


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
