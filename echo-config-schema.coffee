module.exports = {
  title: "pimatic-echo config",
  type: "object",
  properties: {
    address:
      description: "The ip address network interface to use"
      type: "string"
      required: false
    mac:
      description: "The MAC address of the network interface to use"
      type: "string"
      required: false
    port:
      description: "The port of the hue emulation server"
      type: "integer"
      default: 9876
    comfyTemp:
      description: "The comfort mode temperature"
      type: "integer"
      default: 21
    ecoTemp:
      description: "The eco mode temperature"
      type: "integer"
      default: 17
    debug:
      description: "Enable debug output"
      type: "boolean"
      default: false
    trace:
      description: "Enable debug output"
      type: "boolean"
      default: false
  }
}
