module.exports = (env) =>

  Server = require("./lib/server")

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

      @framework.on 'deviceAdded', (device) =>
        if @isSupported(device) and not @isExcluded(device)
          port = port + 1
          devices.push({
            name: device.name,
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

  plugin = new EchoPlugin()

  return plugin
