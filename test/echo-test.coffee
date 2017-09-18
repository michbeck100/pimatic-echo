assert = require "assert"
grunt = require "grunt"

env = require("../node_modules/pimatic/startup").env

describe "echo", ->

  plugin = require("../echo")(env)

  describe "_isSupported", ->

    it "should return true if device has a known template", ->
      assert plugin._isSupported({ template: template }) for template in plugin.knownTemplates

    it "should return false if template is unknown", ->
      assert plugin._isSupported({ template: "foo"}) is false

  describe "_isExcluded", ->

    it "should return true if no echo config exists", ->
      device = {
        template: "switch"
        config : {}
      }
      assert plugin._isExcluded(device) is true
      assert device.config.hasOwnProperty('echo')
      assert device.config.echo.hasOwnProperty('active')
      assert device.config.echo.active is false

    it "should migrate exclude flag", ->
      device = {
        config:
          echo:
            exclude: false
      }
      assert plugin._isExcluded(device) is false
      assert !device.config.echo.hasOwnProperty('exclude')
      assert device.config.echo.hasOwnProperty('active')
      assert device.config.echo.active is true

    it "should return true if device is not active", ->
      assert plugin._isExcluded({
        config:
          echo:
            active: false
      }) is true

    it "should return false if device is active", ->
      assert plugin._isExcluded({
        config:
          echo:
            active: true
      }) is false

  describe "_getDeviceName", ->

    it "should return device name if no config exists", ->
      expected = "devicename"
      assert plugin._getDeviceName({
        name: expected
        config:
          echo: {}
      }) is expected

    it "should return name from config", ->
      expected = "devicename"
      assert plugin._getDeviceName({
        name: "othername"
        config:
          echo:
            name: expected
      }) is expected

  describe "_getAdditionalNames", ->

    it "should return empty list no config exists", ->
      assert plugin._getAdditionalNames({
        name: "device"
        config:
          echo: {}
      }).length is 0

    it "should return names from config", ->
      additionalNames = plugin._getAdditionalNames({
        name: "othername"
        config:
          echo:
            additionalNames: ["1", "2"]
      })
      assert additionalNames[0] is "1"
      assert additionalNames[1] is "2"
