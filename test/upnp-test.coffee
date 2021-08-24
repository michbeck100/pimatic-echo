assert = require "assert"
grunt = require "grunt"
Promise = require 'bluebird'

env = require("../node_modules/pimatic/startup").env
UpnpServer = require("../lib/upnp")(env)

describe "upnp", ->

  upnp = null

  beforeEach ->
    upnp = new UpnpServer('127.0.0.1', '8080', 'AA:BB:CC:DD:EE:FF', 1900)

  describe "_getDiscoveryResponse", ->

    it "should return list of templates", ->
      response = upnp._getDiscoveryResponse()
      assert response.toString().includes("LOCATION: http://127.0.0.1:8080/description.xml")
      assert response.toString().includes("hue-bridgeid: AABBCCFFFEDDEEFF")
      assert response.toString().includes("USN: uuid:2f402f80-da50-11e1-9b23-aabbccddeeff")

