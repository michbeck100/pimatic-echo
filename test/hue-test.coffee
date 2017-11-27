assert = require "assert"
grunt = require "grunt"
Promise = require 'bluebird'

env = require("../node_modules/pimatic/startup").env
Hue = require("../lib/hue")(env)

describe "hue", ->

  hue = null

  beforeEach ->
    hue = new Hue()

  describe "isSupported", ->

    it "should return true if device has a known template", ->
      assert hue.isSupported({ template: template }) for template in hue.dimmerTemplates
      assert hue.isSupported({ template: template }) for template in hue.switchTemplates
      assert hue.isSupported({ template: template }) for template in hue.heatingTemplates

    it "should return false if template is unknown", ->
      assert hue.isSupported({ template: "foo"}) is false

  describe "_turnOn", ->

    it "should call moveUp for shutter device", ->
      wasCalled = false
      device = {
        template: "shutter"
        moveUp: () =>
          wasCalled = true
          return Promise.resolve()
      }
      hue._turnOn(device)
      assert wasCalled

    it "should call buttonPressed for ButtonsDevice", ->
      wasCalled = false
      device = {
        template: "buttons"
        config:
          buttons: [
            id: 1
          ]
        buttonPressed: (id) =>
          assert id is 1
          wasCalled = true
          return Promise.resolve()
      }
      hue._turnOn(device)
      assert wasCalled

    it "should call turnOn for switches", ->
      wasCalled = false
      device = {
        template: "switch"
        turnOn: () =>
          wasCalled = true
          return Promise.resolve()
      }
      hue._turnOn(device)
      assert wasCalled


    it "should call changeTemperatureTo for heating template", ->
      for template in hue.heatingTemplates
        wasCalled = false
        device = {
          config: {
            echo: {
              comfyTemp: 20
            }
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
      for template in hue.dimmerTemplates
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

    it "should call moveDown for shutter device", ->
      wasCalled = false
      device = {
        template: "shutter"
        moveDown: () =>
          wasCalled = true
          return Promise.resolve()
      }
      hue._turnOff(device)
      assert wasCalled

    it "should not call buttonPressed for ButtonsDevice", ->
      wasCalled = false
      device = {
        template: "buttons"
        config:
          buttons: [
            id: 1
          ]
        buttonPressed: (id) =>
          assert false
          wasCalled = true
          return Promise.resolve()
      }
      hue._turnOff(device)
      assert wasCalled is false

    it "should call turnOff for switches", ->
      wasCalled = false
      device = {
        template: "switch"
        turnOff: () =>
          wasCalled = true
          return Promise.resolve()
      }
      hue._turnOff(device)
      assert wasCalled

    it "should call changeTemperatureTo for heating template", ->
      for template in hue.heatingTemplates
        wasCalled = false
        device = {
          config: {
            echo: {
              ecoTemp: 16
            }
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
      for template in hue.dimmerTemplates
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
      for template in hue.heatingTemplates
        device = {
          _temperatureSetpoint: 21
          config: {
            echo: {
              ecoTemp: 16
            }
          }
          template: template
        }
        assert hue._getState(device) is true

    it "should return false if temperature is lower or equal than ecoTemp for heating template", ->
      for template in hue.heatingTemplates
        device = {
          _temperatureSetpoint: 16
          config: {
            echo: {
              ecoTemp: 16
            }
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
      for template in hue.dimmerTemplates.filter((t) -> t != "led-light")
        device = {
          template: template
          _state: true
        }
        assert hue._getState(device) is true
        device._state = false
        assert hue._getState(device) is false

    it "should return true if position of shutter is up", ->
      device = {
        template: "shutter"
        _position: 'up'
      }
      assert hue._getState(device) is true
      device._position = 'down'
      assert hue._getState(device) is false




