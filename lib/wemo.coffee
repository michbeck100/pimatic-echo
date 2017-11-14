module.exports = (env) =>
  _ = require('lodash')
  aguid = require('aguid')
  bodyParser = require('body-parser')

  Emulator = require('./emulator')(env)

  class Wemo extends Emulator

    switchTemplates = [
      'buttons',
      'huezllonoff',
      'shutter'
      'switch'
    ]

    switches = {}
    bootId = 1

    constructor: (@ipAddress) ->

    isSupported: (device) =>
      return device.template in switchTemplates

    addDevice: (device) =>
      return (deviceName, buttonId) =>
        switchCount = Object.keys(switches).length
        deviceId = aguid(deviceName)
        switches[deviceId] = {
          id: deviceId,
          device: device,
          name: deviceName,
          port: 12000 + switchCount,
          handler: (state) =>
            env.logger.debug("setting state of #{deviceName} to #{state}")
            @changeStateTo(device, state, buttonId)
        }
        env.logger.debug("successfully added device #{deviceName} as switch")

    _turnOn: (device, buttonId) =>
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
      switch device.template
        when "shutter" then device.moveDown().done()
        when "buttons" then env.logger.info("A ButtonsDevice doesn't support switching off")
        else
          device.turnOff().done()

    _getState: (device) =>
      switch device.template
        when "shutter" then false
        when "buttons" then false
        else device._state

    getDiscoveryResponses: () =>
      responses = []
      _.forOwn(switches, (v, k) =>
        responseString = """
HTTP/1.1 200 OK
CACHE-CONTROL: max-age=86400
DATE: 2016-10-29
EXT:
LOCATION: http://#{@ipAddress}:#{v.port}/#{k}/setup.xml
OPT: "http://schemas.upnp.org/upnp/1/0/"; ns=01
01-NLS: #{bootId}
SERVER: Unspecified, UPnP/1.0, Unspecified
ST: urn:Belkin:device:**
USN: uuid:Socket-1_0-#{k}::urn:Belkin:device:**\r\n\r\n
"""
        responses.push(new Buffer(responseString))
      )
      return responses

    configure: (emulator) =>

      emulator.get('/:id/setup.xml', (req, res) =>
        device = switches[req.params["id"]]
        if device
          res.setHeader("Content-Type", "application/xml; charset=utf-8")
          res.status(200).send(@_getDeviceSetup(device))
        else
          res.status(404).send("Not found")
      )

      emulator.post('/upnp/control/basicevent1', bodyParser.text({type: 'text/*'}), (req, res) =>

        portNumber = Number(req.headers.host.split(':')[1])
        device = _.find(switches, (d) => d.port == portNumber)

        soapAction = req.headers['soapaction']

        if soapAction.indexOf('GetBinaryState') > 0
          res.setHeader("Content-Type", "application/xml; charset=utf-8")
          res.status(200).send("""
<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/"
    s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">
 <s:Body>
   <u:GetBinaryStateResponse xmlns:u="urn:Belkin:service:basicevent:1">
     <BinaryState>#{if @_getState(device.device) then "1" else "0"}</BinaryState>
   </u:GetBinaryStateResponse>
 </s:Body>
</s:Envelope>
""")
        else if soapAction.indexOf('SetBinaryState') > 0
          if req.body.indexOf('<BinaryState>1</BinaryState>') > 0
            state = on
          else if req.body.indexOf('<BinaryState>0</BinaryState>') > 0
            state = off
          else
            throw new Error("no state found in payload")
          env.logger.debug "Action received for device: #{device.name} state: #{state}"
          device.handler(state)
          res.setHeader("Content-Type", "application/xml; charset=utf-8")
          res.status(200).send("""
<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/"
    s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">
 <s:Body>
   <u:SetBinaryStateResponse xmlns:u="urn:Belkin:service:basicevent:1">
     <BinaryState>#{if state then "1" else "0"}</BinaryState>
   </u:SetBinaryStateResponse>
 </s:Body>
</s:Envelope>
""")
        else
          throw new Error("unsupported soap action: #{soapAction}")
      )

    start: (emulator) =>
      _.forOwn(switches, (device) =>
        emulator.listen(device.port, () =>
          env.logger.info "started wemo emulator for device #{device.name} on port #{device.port}"
        )
      )

    _getDeviceSetup: (device) =>
      bootId++
      response = "<?xml version=\"1.0\"?><root>"
      if !device
        env.logger.debug 'rendering all device setup info..'

        _.forOwn(switches, (v, k) =>
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
