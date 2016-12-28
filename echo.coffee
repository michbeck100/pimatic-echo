module.exports = (env) =>

  Server = require("./lib/server")
  _ = require("lodash")

  class EchoPlugin extends env.plugins.Plugin

    knownTemplates: [
      'buttons',
      'dimmer',
      'huezllonoff',
      'huezlldimmable',
      'huezllcolortemp',
      'huezllcolor',
      'huezllextendedcolor',
      'switch',
      'shutter',
      'led-light'
    ]

    init: (app, @framework, @config) =>
      env.logger.info("Starting pimatic-echo...")

      devices = []
      port = 12000

      @framework.deviceManager.deviceConfigExtensions.push(new EchoDeviceConfigExtension())

      @framework.on 'deviceAdded', (device) =>
        if @isSupported(device) and not @isExcluded(device)
          port = port + 1
          devices.push({
            name: @getDeviceName(device),
            port: port,
            handler: (action) =>
              env.logger.debug("switching #{device.name} #{action}")
              if (action == 'on')
                @turnOn(device)
              else if (action == 'off')
                @turnOff(device)
              else
                throw new Error("unsupported action: #{action}")
          })
          env.logger.debug("successfully added device " + device.name)

      @framework.once "after init", =>
        env.logger.debug("publishing #{devices.length} devices for Amazon echo")

        server = new Server(
          {
            devices: devices
          }
        )

    isSupported: (device) =>
      return device.template in @knownTemplates

    isExcluded: (device) =>
      if device.config.echo?.exclude?
        return device.config.echo.exclude
      return false

    getDeviceName: (device) =>
      if device.config.echo?.name?
        return device.config.echo.name
      else
        return device.name

    turnOn: (device) =>
      switch device.template
        when "shutter" then device.moveUp()
        when "buttons" then device.buttonPressed(device.config.buttons[0])
        else device.turnOn()

    turnOff: (device) =>
      switch device.template
        when "shutter" then device.moveDown()
        when "buttons" then env.logger.info("A ButtonsDevice doesn't support switching off")
        else device.turnOff()

  class EchoDeviceConfigExtension
    configSchema:
      echo:
        type: "object"
        properties:
          name:
            description: "change the name of your device"
            type: "string"
            required: no
          exclude:
            description: "exclude this device from your Amazon echo"
            type: "boolean"
            default: false

    extendConfigShema: (schema) ->
      for name, def of @configSchema
        schema.properties[name] = _.clone(def)

    applicable: (schema) ->
      return yes

    apply: (config, device) -> # do nothing here

  plugin = new EchoPlugin()

  return plugin
