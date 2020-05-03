assert = require "assert"
grunt = require "grunt"
Promise = require 'bluebird'

env = require("../node_modules/pimatic/startup").env
UpnpServer = require("../lib/upnp")(env)

describe "upnp", ->

  upnp = null

  beforeEach ->
    upnp = new UpnpServer('127.0.0.1', '8080', 'AA:BB:CC:DD:EE:FF', 1900)

  describe "_getDiscoveryResponses", ->

    it "should return list of templates", ->
      responses = upnp._getDiscoveryResponses()
      assert responses.length == 3
      assert response.toString().includes("HOST: 239.255.255.250:1900") for response in responses
      assert response.toString().includes("LOCATION: http://127.0.0.1:8080/description.xml") for response in responses
      assert response.toString().includes("hue-bridgeid: AABBCCFFFEDDEEFF") for response in responses
      assert response.toString().includes("USN: uuid:2f402f80-da50-11e1-9b23-aabbccddeeff") for response in responses

