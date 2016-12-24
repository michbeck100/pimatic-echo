module.exports = {
  title: "pimatic-echo config",
  type: "object",
  properties: {
    ipAddress:
      description: "The ip address of the system running this plugin."
      type: "string"
      required: false
    debug:
      description: "Enable debug output"
      type: "boolean"
      default: false
  }
}
