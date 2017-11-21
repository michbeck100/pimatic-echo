[![Build Status](http://img.shields.io/travis/michbeck100/pimatic-echo/master.svg)](https://travis-ci.org/michbeck100/pimatic-echo)
[![Version](https://img.shields.io/npm/v/pimatic-echo.svg)](https://img.shields.io/npm/v/pimatic-echo.svg)
[![downloads][downloads-image]][downloads-url]

[downloads-image]: https://img.shields.io/npm/dm/pimatic-echo.svg?style=flat
[downloads-url]: https://npmjs.org/package/pimatic-echo


# pimatic-echo
pimatic-echo is a [pimatic](https://github.com/pimatic/pimatic) plugin that enables Amazon's echo to control pimatic devices. 
It does this by simulating Philips Hue lights, which are natively supported by the echo. 
All network communication happens on the local network, so pimatic doesn't have to be accessible from the internet.

These device classes are supported currently:
* DummySwitch
* DummyDimmer
* DummyHeatingThermostat
* ButtonsDevice (just the first defined button)
* All devices extending from ShutterController (Shutters will go up when switched on and vice versa)
* All lights from [pimatic-led-light](https://github.com/philip1986/pimatic-led-light), [pimatic-hue-zll](https://github.com/markbergsma/pimatic-hue-zll) and [pimatic-tradfri](https://github.com/treban/pimatic-tradfri/)
* All thermostats from [pimatic-maxcul](https://github.com/fbeek/pimatic-maxcul) and [pimatic-mythermostat](https://github.com/360manu/pimatic-mythermostat)

If you are the developer of a pimatic plugin that defines a device class, that implements switch functionality, just create a [feature request](https://github.com/michbeck100/pimatic-echo/issues/new).

#### Commands

The supported commands for Alexa are very limited, due to the fact that pimatic-echo doesn't implement an Alexa smart home skill. Instead it supports switching on/off and dimming.
Soe the commands are 

* *Alexa, turn on living room*
* *Alexa, switch off living room*
* *Alexa, dim living room to 50 percent*
* *Alexa, turn on Thermostat*

These commands also apply to thermostats. Switching a thermostat off will set the temperature to the configured ecoTemp. Switching on will use the comfyTemp. 
Setting a dimlevel will set the temperature to this value. 


#### Installation

To install the plugin just add the plugin to the config.json of pimatic:

```json
    {
      "plugin": "echo" 
    }
```

This will fetch the most recent version from npm-registry on the next pimatic start and install the plugin.

After that you tell your Amazon echo to search for your devices or use the [web frontend](http://alexa.amazon.de/spa/index.html#smart-home).

For configuration parameters of pimatic-echo and their documentation please see the 
[plugin config schema](https://github.com/michbeck100/pimatic-echo/blob/master/echo-config-schema.coffee). 

Please note that pimatic-echo will use port 80 by default, as this is needed for the newer echo, 
so make sure that this port is either free or change it to another free port. 

#### Configuration
The configuration of pimatic can be extended by adding an attribute called "echo" on every supported device.

Example:

```json
"devices": [
  {
    "id": "switch",
    "class": "DummySwitch",
    "name": "Switch",
    "echo": {
      "name": "EchoSwitch",
      "additionalNames": ["AnotherNameForMyEchoSwitch", "YetAnotherName"],
      "active": true,
      "debug": false,
      "comfyTemp": 21,
      "ecoTemp": 17
    }
  }
]

```
The name setting will change how the device is called when using your voice. This might be helpful if you have multiple devices in different rooms with the same name or if you just want to have a more meaningful name. To work with Alexa these names must be unique. You can also define additional names for your device. For every additional name a new device will be listed in the Alexa app.

To make devices available to Alexa, just set the "active" flag to true. You must manually activate them.

Please make sure that pimatic-echo is placed at the top of the plugins configuration. This helps avoiding misleading error messages, that the echo configuration is unsupported and also enables the configuration via web ui.

### Sponsoring

Do you like this plugin? Then consider a donation to support development.

<span class="badge-paypal"><a href="https://www.paypal.com/cgi-bin/webscr?cmd=_s-xclick&hosted_button_id=2T48JXA589B4Y" title="Donate to this project using Paypal"><img src="https://img.shields.io/badge/paypal-donate-yellow.svg" alt="PayPal donate button" /></a></span>
[![Flattr pimatic-hap](http://api.flattr.com/button/flattr-badge-large.png)](https://flattr.com/submit/auto?user_id=michbeck100&url=https://github.com/michbeck100/pimatic-echo&title=pimatic-echo&language=&tags=github&category=software)

### Changelog
0.4.0
* [#28](https://github.com/michbeck100/pimatic-echo/issues/28) support for new Amazon Echo 2 
* [#29](https://github.com/michbeck100/pimatic-echo/issues/29) support for heating thermostat

0.3.1
* fix echo config migration from blacklist to whitelist

0.3.0
* [#11](https://github.com/michbeck100/pimatic-echo/issues/11) support all buttons on ButtonsDevice
* [#22](https://github.com/michbeck100/pimatic-echo/issues/22) implement whitelist

0.2.4
* Add limit of 50 devices since echo seems to have a device limitation (see. https://github.com/bwssytems/ha-bridge/issues/119)

0.2.3
* fix getting state for pimatic-led-light 

0.2.2
* dim lights without turning on before

0.2.1
* bugfixes and imporvements

0.2.0
* [#8](https://github.com/michbeck100/pimatic-echo/issues/8) support changing dimlevel 

0.1.0
* add support for trafri devices
* [#20](https://github.com/michbeck100/pimatic-echo/pull/20) randomizing device discovery responses befor sending them out. This way you can discover more than 16 devices within a few scans with the echo.

0.0.6
* fixed error when switching ButtonsDevice

0.0.5
* [#10](https://github.com/michbeck100/pimatic-echo/issues/10) additional names for supported devices

0.0.4
* [#3](https://github.com/michbeck100/pimatic-echo/issues/3) Rename devices
* extend device config schema to get rid of error message
* Copied files from fauxmo dependency into lib folder and removed dependency
* Reuse UDP port 1900 for UPNP


0.0.3
* [#5](https://github.com/michbeck100/pimatic-echo/issues/5) Exclude specific devices from being available to Alexa.

0.0.2
* minor bugfixes

0.0.1
* initial release
