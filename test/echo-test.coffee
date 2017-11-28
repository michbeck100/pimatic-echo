assert = require "assert"
grunt = require "grunt"
Promise = require 'bluebird'

env = require("../node_modules/pimatic/startup").env

describe "echo", ->
  plugin = require("../echo")(env)

  describe "_isActive", ->
    it "should return false if no echo config exists", ->
      device = {
        template: "switch"
        config: {}
      }
      assert plugin._isActive(device) is false

    it "should return false if device is not active", ->
      assert plugin._isActive({
        config:
          echo:
            active: false
      }) is false

    it "should return true if device is active", ->
      assert plugin._isActive({
        template: 'switch'
        config:
          echo:
            active: true
      }) is true

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

    it "should return device name is name is empty", ->
      expected = "devicename"
      assert plugin._getDeviceName({
        name: expected
        config:
          echo:
            name: ""
      }) is expected

    it "should return device name is echo config is missing", ->
      expected = "devicename"
      assert plugin._getDeviceName({
        name: expected
        config:
          foo:
            name: ""
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


  describe "_isActive", ->
    it "should return false if active is false", ->
      assert plugin._isActive({
        config: {
          echo: {
            active: false
          }
        }
      }) is false

    it "should return true if active is true", ->
      assert plugin._isActive({
        config: {
          echo: {
            active: true
          }
        }
      }) is true

    it "should return false if config is missing", ->
      assert plugin._isActive({
        config: {

        }
      }) is false
      assert plugin._isActive({
        config: {
          echo: {}
        }
      }) is false
