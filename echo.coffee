module.exports = (env) =>

  Promise = require 'bluebird'
  _ = require("lodash")
  udpServer = require('dgram').createSocket({ type: 'udp4', reuseAddr: true })
  hapi = require('hapi')
  hapiServer = new hapi.Server()
  aguid = require('aguid')
  async = require('async')
  Boom = require('boom')

  class EchoPlugin extends env.plugins.Plugin
    devices: {}
    ipAddress = null

    HueTemplates: [
      'dimmer',
      'huezlldimmable',
      'huezllcolortemp',
      'huezllcolor',
      'huezllextendedcolor',
      'led-light'
    ]

    WeMoTemplates: [
      'buttons',
      'huezllonoff',
      'switch',
      'shutter'
    ]

    init: (app, @framework, @config) =>
      env.logger.info("Starting pimatic-echo...")
      @ipAddress = @getIpAddress()
      @bootId = 1
      env.logger.debug "Using ip address: #{ipAddress}"

      port = 12000

      @framework.deviceManager.deviceConfigExtensions.push(new EchoDeviceConfigExtension())

      @framework.on 'deviceAdded', (device) =>
        if @isSupported(device) and not @isExcluded(device)
          addDevice = (deviceName) =>
            port = port + 1
            deviceId = aguid(deviceName)
            @devices[deviceId] = {
              device: device,
              name: deviceName,
              setup: @getDeviceSetup(deviceId, deviceName, port, device),
              port: port,
              handler: (action) =>
                env.logger.debug("switching #{deviceName} #{action}")
                if (action == 'on')
                  @turnOn(device)
                else if (action == 'off')
                  @turnOff(device)
                else
                  throw new Error("unsupported action: #{action}")
            }
          addDevice(@getDeviceName(device))
          for additionalName in @getAdditionalNames(device)
            addDevice(additionalName)
          env.logger.debug("successfully added device " + device.name)

      @framework.once "after init", =>

        env.logger.debug("publishing #{@devices.length} devices for Amazon echo")

        @startDiscoveryServer()
        @startVirtualDeviceEndpoints()

        hapiServer.start((err) =>
          if err then throw err
          env.logger.debug 'Setup server running.'
        )

    isSupported: (device) =>
      return device.template in @HueTemplates || device.template in @WeMoTemplates

    isExcluded: (device) =>
      if device.config.echo?.exclude?
        return device.config.echo.exclude
      return false

    getDeviceName: (device) =>
      if device.config.echo?.name?
        return device.config.echo.name
      else
        return device.name

    getAdditionalNames: (device) =>
      if device.config.echo?.additionalNames?
        return device.config.echo.additionalNames
      else
        return []

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

    getIpAddress: =>
      networkInterfaces = require('os').networkInterfaces()
      for ifaceName, ifaceDetails of networkInterfaces
        for addrInfo in ifaceDetails
          if addrInfo.family == 'IPv4' && !addrInfo.internal
            return addrInfo.address
      return null

    startDiscoveryServer: () =>
      udpServer.on 'error', (err) =>
        env.logger.error "server.error:\n#{err.message}"
        udpServer.close()

      udpServer.on 'message', (msg, rinfo) =>

        if msg.indexOf('M-SEARCH * HTTP/1.1') == 0 && msg.indexOf('ssdp:discover') > 0 &&
          msg.indexOf('urn:schemas-upnp-org:device:basic:1') > 0
            env.logger.debug "<< server got: #{msg} from #{rinfo.address}:#{rinfo.port}"
            async.eachSeries(@getDiscoveryResponses(), (response, cb) =>
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

      env.logger.debug 'binding to port 1900 for ssdp discovery'
      udpServer.bind(1900)

    startVirtualDeviceEndpoints: () =>
      _.forOwn(@devices, (device, id) =>
        hapiServer.connection({ port: device.port, labels: [id] })
      )

      hapiServer.route({
        method: 'GET',
        path: '/{deviceId}/setup.xml',
        handler: (request, reply) =>
          setup = @devices[request.params.deviceId].setup
          env.logger.debug ">> sending device setup response for device #{request.params.deviceId}: #{setup}"
          reply(setup)
      })

      hapiServer.route({
        method: 'POST',
        path: '/upnp/control/basicevent1',
        handler: (request, reply) =>
          portNumber = Number(request.raw.req.headers.host.split(':')[1])
          device = _.find(@devices, (d) => d.port == portNumber)

          if !device
            return Boom.notFound()

          if !request.payload
            return Boom.badRequest()
          action = null
          if request.payload.indexOf('<BinaryState>1</BinaryState>') > 0
            action = 'on'
          else if request.payload.indexOf('<BinaryState>0</BinaryState>') > 0
            action = 'off'


          env.logger.debug "Action received for device: #{device.name} action: #{action}"
          if device.handler
            device.handler(action)
          else
            env.logger.warn "device has no handler: #{device}"

          reply({ ok: true })
      })

    getDeviceSetup: (deviceId, friendlyName, port, device) =>
      @bootId++

      env.logger.debug "rendering device setup for deviceId: #{deviceId}"

      response = "<?xml version=\"1.0\"?><root xmlns=\"urn:schemas-upnp-org:device-1-0\">"

      if device.template in @HueTemplates
        response += @getHueSetup(deviceId, friendlyName, port)
      else if device.template in @WeMoTemplates
        response += @getWeMoSetup(deviceId, friendlyName)

      response += "</root>"
      return response

    getWeMoSetup: (deviceId, friendlyName) =>
      return """
<device>
    <deviceType>urn:pimatic:device:controllee:1</deviceType>
    <friendlyName>#{friendlyName}</friendlyName>
    <manufacturer>Belkin International Inc.</manufacturer>
    <modelName>Emulated Socket</modelName>
    <modelNumber>3.1415</modelNumber>
    <UDN>uuid:Socket-1_0-#{deviceId}</UDN>
</device>"""

    getHueSetup: (deviceId, friendlyName, port) =>
      return """
<specVersion>
  <major>1</major>
  <minor>0</minor>
</specVersion>
<URLBase>http://#{@ipAddress}:#{port}/</URLBase>
<device>
  <deviceType>urn:schemas-upnp-org:device:Basic:1</deviceType>
  <friendlyName>#{friendlyName}</friendlyName>
  <manufacturer>Royal Philips Electronics</manufacturer>
  <manufacturerURL>http://www.pimatic.org</manufacturerURL>
  <modelDescription>Hue Emulator for pimatic-echo</modelDescription>
  <modelName>Philips hue bridge 2012</modelName>
  <modelNumber>929000226503</modelNumber>
  <modelURL>https://github.com/michbeck100/pimatic-echo</modelURL>
  <serialNumber>#{deviceId}</serialNumber>
  <UDN>uuid:#{deviceId}</UDN>
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
</device>"""

    getDiscoveryResponses: () =>
      responses = []

      _.forOwn(@devices, (v, k) =>
        responseString = """
HTTP/1.1 200 OK
CACHE-CONTROL: max-age=86400
DATE: 2016-10-29
EXT:
LOCATION: http://#{@ipAddress}:#{v.port}/#{k}/setup.xml
OPT: "http://schemas.upnp.org/upnp/1/0/"; ns=01
01-NLS: #{@bootId}
SERVER: Unspecified, UPnP/1.0, Unspecified
ST: urn:schemas-upnp-org:device:basic:1
USN: uuid:Socket-1_0-#{k}::urn:Belkin:device:**\r\n\r\n
"""

        responses.push(new Buffer(responseString))
      )
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
