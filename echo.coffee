module.exports = (env) =>

  FauxMo = require 'fauxmojs'

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
        if @isSupported(device)
          port = port + 1
          devices.push({
              name: device.name,
              port: port,
              handler: (action) =>
                env.logger.debug("switching #{device.name} #{action}")
                device.changeStateTo(action == 'on' ? on : off)
          })
          env.logger.debug("successfully added device " + device.name)

      @framework.once "after init", =>
        env.logger.debug("publishing #{devices.length} devices for Amazon echo")

        fauxMo = new FauxMo(
          {
            devices: devices
          }
        )

    isSupported: (device) =>
      return device.template in @knownTemplates

  plugin = new EchoPlugin()

  return plugin
