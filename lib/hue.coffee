module.exports = (env) =>
  fs = require('fs')
  uuid = require('uuid/v4')
  path = require('path')
  iconv = require('iconv-lite')

  Promise = env.require('bluebird')

  Emulator = require('./emulator')(env)

  class Hue extends Emulator

    pairingEnabled: false

    users = []

    dimmerTemplates: [
      'dimmer',
      'huezlldimmable',
      'huezllcolortemp',
      'huezllcolor',
      'huezllextendedcolor',
      'led-light',
      'tradfridimmer-dimmer',
      'tradfridimmer-temp',
      'tradfridimmer-rgb',
      'milight-rgbw'
    ]

    switchTemplates: [
      'buttons',
      'huezllonoff',
      'shutter',
      'switch',
      'milight-cwww'
    ]

    heatingTemplates: [
      'maxcul-heating-thermostat',
      'thermostat',
      'mythermostat',
      'openhr20-thermostat'
    ]

    devices = {}

    constructor: (@ipAddress, @serverPort, @macAddress, @upnpPort, @config, @storagePath) ->
      super()
      users = @_readUsers()

    addDevice: (device) =>
      if Object.keys(devices).length < 50
        return (deviceName, buttonId) =>
          index = (Object.keys(devices).length + 1).toString()
          uniqueId = ("0" + (Object.keys(devices).length + 1).toString(16)).slice(-2).toUpperCase()
          devices[index] = {
            index: index,
            state: {
              on: @_getState(device),
              brightness: @_getBrightness(device)
            }
            device: device,
            name: deviceName,
            uniqueId: "00:17:88:5E:D3:" + uniqueId + "-" + uniqueId,
            buttonId: buttonId
          }
          env.logger.debug("successfully added device #{deviceName} as dimmable light")
      else
        env.logger.warn("Max number of devices exceeded.")
        return () ->


    isSupported: (device) =>
      return @_isDimmer(device) || @_isSwitch(device) || @_isHeating(device)

    _isDimmer: (device) =>
      return device.template in @dimmerTemplates

    _isSwitch: (device) =>
      return device.template in @switchTemplates

    _isHeating: (device) =>
      return device.template in @heatingTemplates

    _changeState: (device, state) =>
      try
        # some echoes send strange json
        state = JSON.parse(Object.keys(state)[0])
      catch e

      env.logger.debug("changing state for #{device.name}: #{@_toJSON(state)}")
      if state.bri?
        @_setBrightness(device.device, state.bri, device.buttonId).done()
        device.state.brightness = state.bri
        return {"success": {"/lights/#{device.index}/state/bri": state.bri}}
      else if state.on?
        @changeStateTo(device.device, state.on, device.buttonId).done()
        device.state.on = state.on
        return {"success": {"/lights/#{device.index}/state/on": state.on}}
      else
        throw new Error("unsupported state: #{@_toJSON(state)}")

    _turnOn: (device, buttonId) =>
      if @_isHeating(device)
        return device.changeTemperatureTo(@config.comfyTemp)
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
        return device.changeTemperatureTo(@config.ecoTemp)
      else
        return switch device.template
          when "shutter" then device.moveDown()
          when "buttons" then Promise.resolve()
          else
            device.turnOff()

    _getState: (device) =>
      if @_isHeating(device)
        return device._temperatureSetpoint > @config.ecoTemp
      else
        switch device.template
          when "shutter" then device._position == 'up'
          when "buttons" then false
          when "led-light" then device.power == 'on' || device.power == true
          else
            if device._state != null then device._state else false


    _getBrightness: (device) =>
      brightness = 0
      if device.hasAttribute("dimlevel")
        brightness = device._dimlevel
      else if device.hasAttribute("brightness")
        # pimatic-led-light
        brightness = device.brightness
      else if @_isSwitch(device)
        brightness = if @_getState(device) then 100.0 else 0.0
      else if @_isHeating(device)
        brightness = device._temperatureSetpoint
      return Math.ceil(brightness / 100 * 254)

    _setBrightness: (device, dimLevel, buttonId) =>
      dimLevel = Math.min(dimLevel, 254)
      value = Math.ceil(dimLevel / 254 * 100)
      if device.hasAction("changeDimlevelTo")
        return device.changeDimlevelTo(value)
      else if @_isSwitch(device)
        return @changeStateTo(device, value > 0, buttonId)
      else if @_isHeating(device)
        return device.changeTemperatureTo(value)
      else
        return Promise.resolve()

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
        if @pairingEnabled
          username = @_addUser(req.body.username)
          @_sendResponse(res, [{"success": {"username": username}}])
        else
          @_sendResponse(res, {
            "error": {
              "type": 101,
              "address": req.path,
              "description": "Not Authorized. Pair button must be pressed to add users."
            }
          })
      )

      emulator.get('/api/:userid', (req, res) =>
        if @_authorizeUser(req.params["userid"], req, res)
          lights = {}
          for id, device of devices
            lights[id] = @_getDeviceResponse(device)
          @_sendResponse(res, {lights})
      )

      emulator.get('/api/:userid/lights', (req, res) =>
        if @_authorizeUser(req.params["userid"], req, res)
          payload = {}
          for id, device of devices
            payload[id] = @_getDeviceResponse(device)
          @_sendResponse(res, payload)
      )

      emulator.get('/api/:userid/lights/:id', (req, res) =>
        if @_authorizeUser(req.params["userid"], req, res)
          deviceId = req.params["id"]
          device = devices[deviceId]
          if device
            @_sendResponse(res, @_getDeviceResponse(device))
          else
            env.logger.warn("device with id #{deviceId} not found")
            @_sendResponse(res, {
              "error": {
                "type": 3,
                "address": req.path,
                "description": "Light #{deviceId} does not exist."
              }
            })
      )

      emulator.put('/api/:userid/lights/:id/state', (req, res) =>
        if @_authorizeUser(req.params["userid"], req, res)
          deviceId = req.params["id"]
          device = devices[deviceId]
          if device
            payload = @_changeState(device, req.body)
            @_sendResponse(res, [payload])
          else
            env.logger.warn("device with id #{deviceId} not found")
            @_sendResponse(res, {
              "error": {
                "type": 3,
                "address": req.path,
                "description": "Light #{deviceId} does not exist."
              }
            })
      )

      emulator.get('/api/:userid/groups', (req, res) =>
        @_sendResponse(res, {})
      )

      emulator.get('/api/:userid/groups/:id', (req, res) =>
        deviceId = req.params["id"]
        @_sendResponse(res, {
          "error": {
            "type": 3,
            "address": req.path,
            "description": "/groups/#{deviceId} not available."
          }
        })
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
          on: device.state.on,
          bri: device.state.brightness,
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
      return iconv.encode(JSON.stringify(json, null, 2), 'UTF-8')

    _sendResponse: (res, payload) =>
      res.setHeader("Content-Type", "application/json; charset=utf-8")
      res.status(200)
      json = @_toJSON(payload)
      res.send(json)
      #env.logger.debug("sent response #{json}")

    _authorizeUser: (username, req, res) =>
      if username == "echo"
        # convenience user to help analyze problems
        return true
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
        fs.appendFileSync(path.resolve(@storagePath, 'echoUsers'), username + '\n')
        env.logger.debug("added user #{username}")
      return username

    _readUsers: () =>
      if fs.existsSync(path.resolve(@storagePath, 'echoUsers'))
        return fs.readFileSync(path.resolve(@storagePath, 'echoUsers')).toString().split('\n')
      return []
