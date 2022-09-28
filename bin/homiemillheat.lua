#!/usr/bin/env lua

--- Main CLI application.
-- Reads configuration from environment variables and starts the Millheat-to-Homie bridge.
-- Does not support any CLI parameters.
--
-- For configureing the log, use LuaLogging enviornment variable prefix `"HOMIE_LOG_"`, see
-- "logLevel" in the example below.
-- @module homiemillheat
-- @usage
-- # configure parameters as environment variables
-- export MILLHEAT_ACCESS_KEY="xxxxxxxx"
-- export MILLHEAT_SECRET_TOKEN="xxxxxxxx"
-- export MILLHEAT_USERNAME="xxxxxxxx"
-- export MILLHEAT_PASSWORD="xxxxxxxx"
-- export MILLHEAT_POLL_INTERVAL=5            # default: 15 seconds
-- export HOMIE_MQTT_URI="mqtt://synology"    # format: "mqtt(s)://user:pass@hostname:port"
-- export HOMIE_DOMAIN="homie"                # default: "homie"
-- export HOMIE_DEVICE_ID="millheat"          # default: "millheat"
-- export HOMIE_DEVICE_NAME="M2H bridge"      # default: "Millheat-to-Homie bridge"
-- export HOMIE_LOG_LOGLEVEL="info"           # default: "INFO"
--
-- # start the application
-- homiemillheat

local ll = require "logging"
local copas = require "copas"
require("logging.rsyslog").copas() -- ensure copas, if rsyslog is used
local logger = assert(require("logging.envconfig").set_default_logger("HOMIE_LOG"))


do -- set Copas errorhandler
  local lines = require("pl.stringx").lines

  copas.setErrorHandler(function(msg, co, skt)
    msg = copas.gettraceback(msg, co, skt)
    for line in lines(msg) do
      ll.defaultLogger():error(line)
    end
  end, true)
end


logger:info("starting Millheat-to-Homie bridge")


local opts = {
  millheat_access_key = assert(os.getenv("MILLHEAT_ACCESS_KEY"), "environment variable MILLHEAT_ACCESS_KEY not set"),
  millheat_secret_token = assert(os.getenv("MILLHEAT_SECRET_TOKEN"), "environment variable MILLHEAT_SECRET_TOKEN not set"),
  millheat_username = assert(os.getenv("MILLHEAT_USERNAME"), "environment variable MILLHEAT_USERNAME not set"),
  millheat_password = assert(os.getenv("MILLHEAT_PASSWORD"), "environment variable MILLHEAT_PASSWORD not set"),
  millheat_poll_interval = tonumber(os.getenv("MILLHEAT_POLL_INTERVAL")) or 15,
  homie_domain = os.getenv("HOMIE_DOMAIN") or "homie",
  homie_mqtt_uri = assert(os.getenv("HOMIE_MQTT_URI"), "environment variable HOMIE_MQTT_URI not set"),
  homie_device_id = os.getenv("HOMIE_DEVICE_ID") or "millheat",
  homie_device_name = os.getenv("HOMIE_DEVICE_NAME") or "Millheat-to-Homie bridge",
}

logger:info("Bridge configuration:")
logger:info("MILLHEAT_ACCESS_KEY: ********")
logger:info("MILLHEAT_SECRET_TOKEN: ********")
logger:info("MILLHEAT_USERNAME: %s", opts.millheat_username)
logger:info("MILLHEAT_PASSWORD: ********")
logger:info("MILLHEAT_POLL_INTERVAL: %d seconds", opts.millheat_poll_interval)
logger:info("HOMIE_DOMAIN: %s", opts.homie_domain)
logger:info("HOMIE_MQTT_URI: %s", opts.homie_mqtt_uri)
logger:info("HOMIE_DEVICE_ID: %s", opts.homie_device_id)
logger:info("HOMIE_DEVICE_NAME: %s", opts.homie_device_name)


copas.loop(function()
  require("homie-millheat")(opts)
end)

ll.defaultLogger():info("Millheat-to-Homie bridge exited")
