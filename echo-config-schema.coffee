module.exports = {
  title: "pimatic-echo config",
  type: "object",
  properties: {
    ipAddress:
      description: "The ip address of the system running this plugin."
      type: "string"
      required: false
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
