module.exports = (env) =>
  _ = require('lodash')
  bodyParser = require('body-parser')
  fs = require('fs')
  uuid = require('uuid/v4')
  Promise = require('bluebird')

  Emulator = require('./emulator')(env)

  class Hue extends Emulator

    users = []

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

    devices = {}

    constructor: (@ipAddress, @serverPort, @macAddress, @upnpPort, @pairingEnabled) ->
      users = @_readUsers()

    addDevice: (device) =>
      if Object.keys(devices).length <= 50
        return (deviceName, buttonId) =>
          uniqueId = (Object.keys(devices).length + 1).toString()
          devices[uniqueId] = {
            device: device,
            name: deviceName,
            uniqueId: "00:17:88:5E:D3:" + uniqueId + "-" + uniqueId,
            buttonId: buttonId
          }
          env.logger.debug("successfully added device #{deviceName} as dimmable light")
      else
        env.logger.warn("Max number of devices exceeded.")
        return (deviceName, buttonId) => return


    isSupported: (device) =>
      return @_isDimmer(device) || @_isSwitch(device) || @_isHeating(device)

    _isDimmer: (device) =>
      return device.template in @dimmerTemplates

    _isSwitch: (device) =>
      return device.template in @switchTemplates

    _isHeating: (device) =>
      return device.template in @heatingTemplates

    _changeState: (device, state) =>
      env.logger.debug("changing state for #{device.name}: #{@_toJSON(state)}")
      if state.bri?
        env.logger.debug("setting brightness of #{device.name} to #{state.bri}")
        return @_setBrightness(device.device, state.bri).then(() ->
          Promise.resolve({"success": {"/lights/#{device.uniqueId}/state/bri": state.bri}})
        )
      else if state.on?
        env.logger.debug("setting state of #{device.name} to #{state.on}")
        return @changeStateTo(device.device, state.on, device.buttonId).then(() ->
          Promise.resolve({"success": {"/lights/#{device.uniqueId}/state/on": state.on}})
        )
      return Promise.resolve()

    _turnOn: (device, buttonId) =>
      if @_isHeating(device)
        return device.changeTemperatureTo(device.config.echo.comfyTemp)
      else
        switch device.template
          when "shutter"
            return device.moveUp()
          when "buttons"
            env.logger.debug "switching #{buttonId}"
            if buttonId
              return device.buttonPressed(buttonId)
            else
              return device.buttonPressed(device.config.buttons[0].id)
          else
            return device.turnOn()

    _turnOff: (device) =>
      if @_isHeating(device)
        return device.changeTemperatureTo(device.config.echo.ecoTemp)
      else
        return switch device.template
          when "shutter" then device.moveDown()
          when "buttons" then Promise.resolve()
          else
            device.turnOff()

    _getState: (device) =>
      if @_isHeating(device)
        return device._temperatureSetpoint > device.config.echo.ecoTemp
      else
        switch device.template
          when "shutter" then device._position == 'up'
          when "buttons" then false
          when "led-light" then device.power == 'on' || device.power == true
          else
            device._state


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
      return brightness / 100 * 255

    _setBrightness: (device, dimLevel, buttonId) =>
      if device.hasAction("changeDimlevelTo")
        return device.changeDimlevelTo(dimLevel / 255 * 100)
      else if @_isSwitch(device)
        return @changeStateTo(device, dimLevel > 0, buttonId)
      else if @_isHeating(device)
        return device.changeTemperatureTo(dimLevel / 255 * 100)

    _getSNUUIDFromMac: =>
      return @macAddress.replace(/:/g, '').toLowerCase()

    _getHueBridgeIdFromMac: =>
      cleanMac = @_getSNUUIDFromMac()
      bridgeId =
        cleanMac.substring(0, 6).toUpperCase() + 'FFFE' + cleanMac.substring(6).toUpperCase()
      return bridgeId

    start: (emulator) =>
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
        res.setHeader("Content-Type", "application/json")
        if @pairingEnabled
          username = @_addUser(req.body.username)
          res.status(200).send(@_toJSON([{"success": {"username": username}}]))
        else
          res.status(401).send(JSON.stringify({
            "error": {
              "type": 1,
              "address": req.path,
              "description": "Not Authorized. Pair button must be pressed to add users."
            }
          }))
      )

      emulator.get('/api/:userid', (req, res) =>
        if @_authorizeUser(req.params["userid"], req, res)
          res.setHeader("Content-Type", "application/json")
          lights = {}
          _.forOwn(devices, (device, id) =>
            lights[id] = @_getDeviceResponse(device)
          )
          res.status(200).send(@_toJSON({
            lights
          }))
      )

      emulator.get('/api/:userid/lights', (req, res) =>
        if @_authorizeUser(req.params["userid"], req, res)
          response = {}
          _.forOwn(devices, (device, id) =>
            response[id] = @_getDeviceResponse(device)
          )
          res.setHeader("Content-Type", "application/json")
          res.status(200).send(@_toJSON(response))
      )

      emulator.get('/api/:userid/lights/:id', (req, res) =>
        if @_authorizeUser(req.params["userid"], req, res)
          deviceId = req.params["id"]
          device = devices[deviceId]
          if device
            res.setHeader("Content-Type", "application/json")
            deviceResponse = @_toJSON(@_getDeviceResponse(device))
            res.status(200).send(deviceResponse)
          else
            env.logger.warn("device with id #{deviceId} not found")
            res.status(404).send(JSON.stringify({
              "error": {
                "type": 3,
                "address": req.path,
                "description": "Light #{deviceId} does not exist."
              }
            }))
      )

      emulator.put('/api/:userid/lights/:id/state', (req, res) =>
        if @_authorizeUser(req.params["userid"], req, res)
          deviceId = req.params["id"]
          device = devices[deviceId]
          if device
            @_changeState(device, req.body).then((response) =>
              res.setHeader("Content-Type", "application/json")
              res.status(200).send(@_toJSON([response]))
            ).done()
          else
            env.logger.warn("device with id #{deviceId} not found")
            res.status(404).send(JSON.stringify({
              "error": {
                "type": 3,
                "address": req.path,
                "description": "Light #{deviceId} does not exist."
              }
            }))
      )

      emulator.get('/api/:userid/groups', (req, res) =>
        res.setHeader("Content-Type", "application/json")
        res.status(200).send("{}")
      )

      emulator.get('/api/:userid/groups/0', (req, res) =>
        throw new Error("group 0 not supported")
      )

    _getHueTemplate: =>
      bridgeIdMac = @_getSNUUIDFromMac()
      response = """
<?xml version="1.0" encoding="UTF-8" ?>
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
    <modelNumber>929000226503</modelNumber>
    <modelURL>http://www.meethue.com</modelURL>
    <serialNumber>0017880ae670</serialNumber>
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

    _getDeviceResponse: (device) =>
      return {
        state: {
          on: @_getState(device.device),
          bri: @_getBrightness(device.device),
          alert: "none",
          reachable: true
        },
        type: "Dimmable light",
        name: device.name,
        modelid: "LWB007",
        manufacturername: "pimatic",
        uniqueid: device.uniqueId,
        swversion: "66009461"
      }

    _toJSON: (json) =>
      return JSON.stringify(json, null, 2)

    _authorizeUser: (username, req, res) =>
      if @pairingEnabled
        @_addUser(username)
      if username in users
        return true
      else
        env.logger.debug("Pairing is disabled and user #{username} was not found")
        res.status(401).send(JSON.stringify({
          "error": {
            "type": 1,
            "address": req.path,
            "description": "Not Authorized."
          }
        }))
        return false

    _addUser: (username) =>
      if !username
        username = uuid().replace(/-/g, '')
      if username not in users
        users.push(username)
        fs.appendFileSync('echoUsers', username + '\n')
        env.logger.debug("added user #{username}")
      return username

    _readUsers: () =>
      if fs.existsSync('echoUsers')
        return fs.readFileSync('echoUsers').toString().split('\n')
      return []