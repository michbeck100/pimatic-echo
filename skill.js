var Pimatic = require('./api/pimatic')
var conf = require('./config.json');

var api = new Pimatic({
    protocol: conf.protocol,
    host: conf.host,
    port: conf.port,
    username: conf.username,
    password: conf.password
});

var appliances = [];

//This is the heart of the code - takes the request/response headers for Alexa
var func = function (event, context) {
    switch (event.header.namespace) {
        case 'Alexa.ConnectedHome.Discovery':
            handleDiscovery(event, context);
            break;
        case 'Alexa.ConnectedHome.Control':
            handleControl(event, context);
            break;
        default:
            console.log('Err', 'No supported namespace: ' + event.header.namespace);
            context.fail('Something went wrong');
            break;
    }
};
exports.handler = func;

//This handles the Discovery
function handleDiscovery(event, context) {
    getDevices(function (callback) {
        context.succeed(callback);
        appliances = [];
    })
}

//This handles the Control requests - based on the discovery, which should designate whether it's a switch/temp/group
function handleControl(event, context) {
    var deviceId = event.payload.appliance.applianceId;
    var template = event.payload.appliance.additionalApplianceDetails.template;

    var confirmation;

    var result = {
        header:  {
            namespace: 'Alexa.ConnectedHome.Control',
            payloadVersion: '2',
            messageId: event.header.messageId
        },
        payload: {}
    };
    
    var confirm = function(confirmation, payload) {
        result.header.name = confirmation;
        if (typeof payload !== 'undefined') {
            result.payload = payload;
        }
        context.succeed(result);
    };

    switch (event.header.name) {
        case 'TurnOnRequest':
            turnOn(deviceId, confirm);
            break;
        case 'TurnOffRequest':
            turnOff(deviceId, confirm);
            break;
        case 'SetTargetTemperatureRequest':
            setTemperature(deviceId, event.payload.targetTemperature.value, confirm);
            break;
        case 'SetPercentageRequest':
            changeDimlevel(deviceId, event.payload.percentageState.value, confirm);
            break;
        case 'IncrementTargetTemperatureRequest':
            incrementTemperature(deviceId, event.payload.deltaTemperature.value, confirm);
            break;
        case 'DecrementTargetTemperatureRequest':
            decrementTemperature(deviceId, event.payload.deltaTemperature.value, confirm);
            break;
        case 'IncrementPercentageRequest':
            incrementDimlevel(deviceId, event.payload.deltaPercentage.value, confirm);
            break;
        case 'DecrementPercentageRequest':
            decrementDimlevel(deviceId, event.payload.deltaPercentage.value, confirm);
            break;
        default:
            console.log('Err', 'No supported request: ' + event.header.name);        
            break; 
    }
}

function generateControlError(name, code, description) {
    var result = {
        header: {
            namespace: 'Alexa.ConnectedHome.Control',
            name: name,
            payloadVersion: '2'
        },
        payload: {
           exception: {
                code: code,
                description: description
            }
        }
    };

    return result;
}

function getDevices(callback) {
    api.getDevices(function(error, data) {
        data.devices.forEach(function(device) {
            if (['switch', 'dimmer', 'thermostat'].indexOf(device.template) >= 0) {
                var appliance = {
                    applianceId: device.id,
                    manufacturerName: 'pimatic',
                    modelName: device.template,
                    version: '1.0',
                    friendlyName: device.name,
                    friendlyDescription: device.name,
                    isReachable: true
                }
                appliance.additionalApplianceDetails = {
                    template: device.template
                }
                switch (device.template) {
                    case 'switch':
                        appliance.actions = ([
                            "turnOn",
                            "turnOff"
                        ]);                 
                        break;
                    case 'dimmer':
                        appliance.actions = ([
                            "incrementPercentage",
                            "decrementPercentage",
                            "setPercentage",
                            "turnOn",
                            "turnOff"
                        ]);
                        break;
                    case 'thermostat':
                        appliancename.actions = ([
                            "setTargetTemperature",
                            "incrementTargetTemperature", 
                            "decrementTargetTemperature" 
                        ]);
                        break;
                }
                appliances.push(appliance);
            }

        });
        if (appliances.length > 0) {
            var result = {
                header: {
                    namespace: 'Alexa.ConnectedHome.Discovery',
                    name: 'DiscoverAppliancesResponse',
                    payloadVersion: '2'
                },
                payload: {
                    discoveredAppliances: appliances
                }
            }
            callback(result);
        }   
    });
}

function turnOn(deviceId, callback) {
    api.turnOn(deviceId);
    callback('TurnOnConfirmation');
}

function turnOff(deviceId, callback) {
    api.turnOff(deviceId);
    callback('TurnOffConfirmation');
}

function changeDimlevel(deviceId, dimlevel, callback) {
    api.changeDimlevel(deviceId, dimlevel);
    callback('SetPercentageConfirmation');
}

function incrementDimlevel(deviceId, value, callback) {
    api.incrementDimlevel(deviceId, value);
    callback('IncrementPercentageConfirmation');
}

function decrementDimlevel(deviceId, value, callback) {
    api.decrementDimlevel(deviceId, value);
    callback('DecrementPercentageConfirmation');
}

function setTemperature(deviceId, targetTemperature, callback) {
    api.setTemperature(deviceId, targetTemperature);

    callback('SetTargetTemperatureConfirmation', {
        "targetTemperature": {
            "value": targetTemperature
        },
        "temperatureMode": {
            "value": "AUTO" // TODO
        }/*,
        "previousState":{
            "targetTemperature": {
                "value": 21.0 // TODO
            },
            "mode":{
                "value":"AUTO" // TODO
            }
        }*/
    });
}

function incrementTemperature(deviceId, value, callback) {
    api.incrementTemperature(deviceId, value);
    callback('IncrementTargetTemperatureConfirmation');
}

function decrementTemperature(deviceId, value, callback) {
    api.decrementTemperature(deviceId, value);
    callback('DecrementTargetTemperatureConfirmation');
}