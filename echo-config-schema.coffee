module.exports = {
  title: "pimatic-echo config",
  type: "object",
  properties: {
    ipAddress:
      description: "The ip address of the system running this plugin."
      type: "string"
    debug:
      description: "Enable debug output"
      type: "boolean"
      default: false
  }
}
