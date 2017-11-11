assert = require "assert"
grunt = require "grunt"
Promise = require 'bluebird'

env = require("../node_modules/pimatic/startup").env
Hue = require("../lib/hue")(env)

describe "hue", ->

  dimmerTemplates = [
    'dimmer',
    'huezlldimmable',
    'huezllcolortemp',
    'huezllcolor',
    'huezllextendedcolor',
    'led-light',
    'tradfridimmer-dimmer',
    'tradfridimmer-temp'
  ]


  heatingTemplates = [
    'maxcul-heating-thermostat',
    'thermostat',
    'mythermostat'
  ]

  hue = null

  beforeEach ->
    hue = new Hue()

  describe "isSupported", ->

    it "should return true if device has a known template", ->
      assert hue.isSupported({ template: template }) for template in dimmerTemplates
      assert hue.isSupported({ template: template }) for template in heatingTemplates

    it "should return false if template is unknown", ->
      assert hue.isSupported({ template: "foo"}) is false

  describe "_turnOn", ->

    it "should call changeTemperatureTo for heating template", ->
      for template in heatingTemplates
        wasCalled = false
        device = {
          config: {
            comfyTemp: 20
          }
          template: template
          changeTemperatureTo: (temp) =>
            assert temp is 20
            wasCalled = true
            return Promise.resolve()
        }
        hue._turnOn(device)
        assert wasCalled

    it "should call turnOn for lights", ->
      for template in dimmerTemplates
        wasCalled = false
        device = {
          template: template
          turnOn: () =>
            wasCalled = true
            return Promise.resolve()
        }
        hue._turnOn(device)
        assert wasCalled

  describe "_turnOff", ->

    it "should call changeTemperatureTo for heating template", ->
      for template in heatingTemplates
        wasCalled = false
        device = {
          config: {
            ecoTemp: 16
          }
          template: template
          changeTemperatureTo: (temp) =>
            assert temp is 16
            wasCalled = true
            return Promise.resolve()
        }
        hue._turnOff(device)
        assert wasCalled

    it "should call turnOff for lights", ->
      for template in dimmerTemplates
        wasCalled = false
        device = {
          template: template
          turnOff: () =>
            wasCalled = true
            return Promise.resolve()
        }
        hue._turnOff(device)
        assert wasCalled

  describe "_getState", ->

    it "should return true if temperature is higher than ecoTemp for heating template", ->
      for template in heatingTemplates
        device = {
          _temperatureSetpoint: 21
          config: {
            ecoTemp: 16
          }
          template: template
        }
        assert hue._getState(device) is true

    it "should return false if temperature is lower or equal than ecoTemp for heating template", ->
      for template in heatingTemplates
        device = {
          _temperatureSetpoint: 16
          config: {
            ecoTemp: 16
          }
          template: template
        }
        assert hue._getState(device) is false
        device._temperatureSetpoint = 15
        assert hue._getState(device) is false

    it "should return power of led-light template", ->
      device = {
        template: "led-light"
        power: 'on'
      }
      assert hue._getState(device) is true
      device.power = true
      assert hue._getState(device) is true

    it "should return power of led-light template", ->
      for template in dimmerTemplates.filter((t) -> t != "led-light")
        device = {
          template: template
          _state: true
        }
        assert hue._getState(device) is true
        device._state = false
        assert hue._getState(device) is false



