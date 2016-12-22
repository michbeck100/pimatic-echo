var request = require('request');
var _ = require('lodash');
var URI = require('urijs');
var extend = require('extend');

function Pimatic(options) {
    if (!(this instanceof Pimatic)) return new Pimatic(options);
    this.options = {
        protocol: 'http',
        host: '127.0.0.1',
        port: '80',
        username: undefined,
        password: undefined
    };
    this.options = extend(this.options, options);
}

/**
 * Generate the default url for your Pimatic API
 * @returns {*|exports|module.exports}
 * @private
 */
Pimatic.prototype._getUrl = function () {
    return new URI({
        protocol: this.options.protocol,
        hostname: this.options.host,
        port: this.options.port,
        path: "/api",
        username: this.options.username,
        password: this.options.password
    });
};

Pimatic.prototype._request = function (url, callback) {
    var self = this;

    request({
            "rejectUnauthorized": false,
            "url": url.toString(),
            "method": "GET",
        },
        function (error, res, data) {
            if (typeof callback !== 'undefined') {
                callback(error, JSON.parse(data));
            }
        });
};

Pimatic.prototype._get = function (resource, callback) {
    var url = this._getUrl();
    url.resource("/" + resource);
    this._request(url, callback);
}

Pimatic.prototype.getDevices = function (callback) {
    this._get("devices", callback);
};

Pimatic.prototype.turnOn = function (deviceId, callback) {
    this._get("device/" + deviceId + "/turnOn", callback);
};

Pimatic.prototype.turnOff = function (deviceId, callback) {
    this._get("device/" + deviceId + "/turnOff", callback);
};

Pimatic.prototype.changeDimlevel = function (deviceId, dimlevel, callback) {
    this._get("device/" + deviceId + "/changeDimlevelTo?dimlevel=" + dimlevel, callback);
};

Pimatic.prototype.incrementDimlevel = function (deviceId, value, callback) {
    if (value == 0) {
        callback();
        return;
    }
    this._get("devices/" + deviceId, function(error, data){
        var dimlevel = data.attributes.filter(function(attribute) {
            return attribute.name == 'dimlevel';
        })[0].value;
        dimlevel = dimlevel + value;
        if (dimlevel < 0) {
            dimlevel = 0;
        } else if(dimlevel > 100) {
            dimlevel = 100;
        }
        this.changeDimlevel(deviceId, dimlevel, callback);
    });
};

Pimatic.prototype.decrementDimlevel = function (deviceId, value, callback) {
    this.incrementDimlevel(deviceId, -value, callback);
};

Pimatic.prototype.setTemperature = function (deviceId, temperature, callback) {
    this._get("/device/" + deviceId + "/changeTemperatureTo?temperatureSetpoint=" + temperature, callback);
};

Pimatic.prototype.incrementTemperature = function (deviceId, value, callback) {
    if (value == 0) {
        callback();
        return;
    }
    this._get("devices/" + deviceId, function(error, data){
        var temperature = data.attributes.filter(function(attribute) {
            return attribute.name == 'temperatureSetpoint';
        })[0].value;
        this.setTemperature(deviceId, temperature + value, callback);
    });
};

Pimatic.prototype.decrementTemperature = function (deviceId, value, callback) {
    this.incrementTemperature(deviceId, -value, callback);
};

module.exports = Pimatic;