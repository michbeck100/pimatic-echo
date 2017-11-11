module.exports = (env) =>
  class Emulator

    changeStateTo: (device, state, buttonId) =>
      if state
        @_turnOn(device, buttonId)
      else
        @_turnOff(device)

    getDiscoveryResponses: () =>
      return []

    isSupported: (device) =>
      return false

    _turnOn: (device, buttonId) =>
      throw new Error("_turnOn must be overridden")

    _turnOff: (device) =>
      throw new Error("_turnOff must be overridden")

    _getState: (device) =>
      throw new Error("_getState must be overridden")

