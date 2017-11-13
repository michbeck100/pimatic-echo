module.exports = (env) =>

  _ = require('lodash')
  async = require('async')
  bodyParser = require('body-parser')
  express = require('express')
  udpServer = require('dgram').createSocket({ type: 'udp4', reuseAddr: true })

  Wemo = require('./lib/wemo')(env)
  Hue = require('./lib/hue')(env)

  class EchoPlugin extends env.plugins.Plugin

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

      env.logger.debug "Using ip address : #{@ipAddress}"

      @framework.deviceManager.deviceConfigExtensions.push(new EchoDeviceConfigExtension())

      @wemo = new Wemo(@ipAddress)
      @hue = new Hue(@macAddress, @ipAddress, @serverPort, @upnpPort)

      @framework.on 'deviceAdded', (device) =>
        addDevice = (deviceName, buttonId) => return # do nothing

        if @_isExcluded(device)
          return

        if @hue.isSupported(device)
          addDevice = @hue.addDevice(device)
        else if @wemo.isSupported(device)
          addDevice = @wemo.addDevice(device)
        else
          throw new Error("unsupported device type: #{device.template})")

        if device.template is 'buttons'
          addDevice(button.text, device.id + button.id) for button in device.config.buttons
        else
          addDevice(@_getDeviceName(device))
          for additionalName in @_getAdditionalNames(device)
            addDevice(additionalName)

      @framework.once "after init", =>

        @_startDiscoveryServer()
        @_startEmulator()

    _isSupported: (device) =>
      return @wemo.isSupported(device) || @hue.isSupported(device)

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
      if device.config.echo?.name?
        return device.config.echo.name
      else
        return device.name

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
        env.logger.debug "udp server listening on port #{address.port}"
        udpServer.addMembership('239.255.255.250')

      udpServer.bind(@upnpPort)

    _startEmulator: () =>

      emulator = express()
      emulator.use bodyParser.urlencoded(limit: '1mb', extended: true)
      emulator.use bodyParser.json(limit: '1mb')

      if @config.debug
        logger = (req, res, next) =>
          env.logger.debug "Request to #{req.originalUrl}"
          if Object.keys(req.body).length > 0
            env.logger.debug "Payload: #{JSON.stringify(req.body)}"
          next()
        emulator.use(logger)

      @wemo.configure(emulator)
      @hue.configure(emulator)

      @wemo.start(emulator)
      @hue.start(emulator)


    _getDiscoveryResponses: () =>
      return @wemo.getDiscoveryResponses().concat(@hue.getDiscoveryResponses())

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
            description: "Exclude this device. Deprecated in favor of active flag."
            type: "boolean"
            default: false
          hueType:
            description: "the Hue Type of the device"
            type: "string"
            required: no
            enum: ['Dimmer', 'Switch']
            default: "Dimmer"
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
