module.exports = {
  title: "pimatic-echo config",
  type: "object",
  properties: {
    address:
      description: "The ip address network interface to use"
      type: "string"
    mac:
      description: "The MAC address of the network interface to use"
      type: "string"
    port:
      description: "The port of the hue emulation server"
      type: "integer"
      default: 9876
    debug:
      description: "Enable debug output"
      type: "boolean"
      default: false
  }
}
