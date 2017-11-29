module.exports = (env) =>

  _ = require('lodash')
  bodyParser = require('body-parser')
  express = require('express')
  Promise = env.require('bluebird')

  UpnpServer = require('./lib/upnp')(env)
  HueEmulator = require('./lib/hue')(env)

  class EchoPlugin extends env.plugins.Plugin

    init: (app, @framework, @config) =>
      env.logger.info("Starting pimatic-echo...")

      networkInfo = @_getNetworkInfo()
      if networkInfo == null && (!@config.address || !@config.mac)
        throw new Error("Unable to obtain network information."
          +" Please provide ip and mac address in plugin config!")

      ipAddress = if @config.address then @config.address else networkInfo.address
      macAddress = if @config.mac then @config.mac else networkInfo.mac
      serverPort = @config.port
      upnpPort = 1900

      upnpServer = new UpnpServer(ipAddress, serverPort, macAddress, upnpPort)
      hueEmulator = new HueEmulator(ipAddress, serverPort, macAddress, upnpPort, @config)

      env.logger.debug "Using ip address : #{ipAddress}"

      @framework.deviceManager.deviceConfigExtensions.push(new EchoDeviceConfigExtension())

      @framework.on 'deviceAdded', (device) =>
        if @_isActive(device)
          if hueEmulator.isSupported(device)
            addDevice = hueEmulator.addDevice(device)
            if device.template is 'buttons'
              addDevice(button.text, button.id) for button in device.config.buttons
            else
              addDevice(@_getDeviceName(device))
              for additionalName in @_getAdditionalNames(device)
                addDevice(additionalName)

      @framework.once "after init", =>
        upnpServer.start()

        server = @_startServer(ipAddress, serverPort)

        hueEmulator.start(server)

      @framework.deviceManager.on "discover", (eventData) =>
        @framework.deviceManager.discoverMessage("pimatic-echo",
          "Pairing mode is enabled for 20 seconds. Let Alexa scan for devices now.")
        hueEmulator.pairingEnabled = true
        Promise.delay(20000).then(() => hueEmulator.pairingEnabled = false ).then(
          () => @framework.deviceManager.discoverMessage("pimatic-echo",
            "Pairing mode is disabled again.")
        )

    _isActive: (device) =>
      return !!device.config.echo?.active

    _getDeviceName: (device) =>
      return if !!device.config.echo?.name then device.config.echo.name else device.name

    _getAdditionalNames: (device) =>
      if device.config.echo?.additionalNames?
        return device.config.echo.additionalNames
      else
        return []

    _getNetworkInfo: =>
      networkInterfaces = require('os').networkInterfaces()
      for ifaceName, ifaceDetails of networkInterfaces
        for addrInfo in ifaceDetails
          if addrInfo.family == 'IPv4' && !addrInfo.internal
            return addrInfo
      env.logger.warn("No network interface found.")
      return null

    _startServer: (address, serverPort) =>
      if @framework.app.httpServer? && @framework.config.settings.httpServer?.port == serverPort
        env.logger.debug 'reusing the express instance of pimatic'
        emulator = @framework.app
        @framework.userManager.addAllowPublicAccessCallback((req) =>
          allowedPaths = switch req.method
            when 'GET' then [
              /\/description\.xml/,
              /\/favicon\.ico/,
              /\/hue_logo_0\.png/,
              /\/hue_logo_3\.png/,
              /\/api\/.+\/lights/,
              /\/api\/.+\/lights\/\d+/
            ]
            when 'POST' then [/\/api/]
            when 'PUT' then [/\/api\/.+\/lights\/\d+\/state/]
            else []
          allowed = _.some(allowedPaths, (regex) ->
            return regex.test(req.path)
          )
          return allowed
        )
      else
        emulator = express()
        emulator.listen(serverPort, address, () =>
          env.logger.info "started hue emulator on port #{serverPort}"
        ).on('error', () =>
          throw new Error("Error starting hue emulator. Port #{serverPort} is not available.")
        )

      emulator.use bodyParser.json(type: "application/x-www-form-urlencoded", limit: '1mb')
      emulator.use bodyParser.json(limit: '1mb')

      if @config.debug
        logger = (req, res, next) =>
          env.logger.debug "Request: #{req.path}"
          env.logger.debug "#{req.method} Request to #{req.originalUrl}"
          if Object.keys(req.body).length > 0
            env.logger.debug "Payload: #{@_toJSON(req.body)}"
          env.logger.debug "Headers: #{@_toJSON(req.headers)}"
          next()
        emulator.use(logger)

      return emulator

    _toJSON: (json) =>
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
