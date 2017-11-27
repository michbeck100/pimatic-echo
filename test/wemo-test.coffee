assert = require "assert"
grunt = require "grunt"
Promise = require 'bluebird'

env = require("../node_modules/pimatic/startup").env
Wemo = require("../lib/wemo")(env)

describe "wemo", ->

  wemo = null

  beforeEach ->
    wemo = new Wemo()

  describe "isSupported", ->

    it "should return true if device has a known template", ->
      assert wemo.isSupported({ template: template }) for template in [
        'buttons',
        'huezllonoff',
        'shutter'
        'switch'
      ]

    it "should return false if template is unknown", ->
      assert wemo.isSupported({ template: "foo"}) is false

  describe "turnOn", ->

    it "should call moveUp for shutter device", ->
      wasCalled = false
      device = {
        template: "shutter"
        moveUp: () =>
          wasCalled = true
          return Promise.resolve()
      }
      wemo._turnOn(device)
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
      wemo._turnOn(device)
      assert wasCalled

    it "should call turnOn for switches", ->
      wasCalled = false
      device = {
        template: "switch"
        turnOn: () =>
          wasCalled = true
          return Promise.resolve()
      }
      wemo._turnOn(device)
      assert wasCalled

  describe "turnOff", ->

    it "should call moveDown for shutter device", ->
      wasCalled = false
      device = {
        template: "shutter"
        moveDown: () =>
          wasCalled = true
          return Promise.resolve()
      }
      wemo._turnOff(device)
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
      wemo._turnOff(device)
      assert wasCalled is false

    it "should call turnOff for switches", ->
      wasCalled = false
      device = {
        template: "switch"
        turnOff: () =>
          wasCalled = true
          return Promise.resolve()
      }
      wemo._turnOff(device)
      assert wasCalled
