#!/usr/bin/env lua

--- Main CLI application.
-- Reads configuration from environment variables and starts the Millheat-to-Homie bridge.
-- Does not support any CLI parameters.
--
-- For configuring the log, use LuaLogging environment variable prefix `"HOMIE_LOG_"`, see
-- "logLevel" in the example below.
-- @script homiemillheat
-- @usage
-- # configure parameters as environment variables
-- export MILLHEAT_API_KEY="xxxxxxxx"         # choose: API_KEY or USERNAME+PASSWORD !!
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


-- do -- Add corowatch for debugging purposes
--   local corowatch = require "corowatch"
--   if jit then jit.off() end -- no hooks will be called for jitted code, so disable jit
--   corowatch.export(_G)
--   corowatch.watch(nil, 30, nil, nil, 1) -- watch the main-coroutine, kill coroutine after 30 seconds, hookcount = 1 to be as precise as possible
-- end

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


print("starting Millheat-to-Homie bridge")
logger:info("starting Millheat-to-Homie bridge")


local opts = {
  millheat_api_key = os.getenv("MILLHEAT_ACCESS_KEY"),
  millheat_username = os.getenv("MILLHEAT_USERNAME"),
  millheat_password = os.getenv("MILLHEAT_PASSWORD"),
  millheat_poll_interval = tonumber(os.getenv("MILLHEAT_POLL_INTERVAL")) or 15,
  homie_domain = os.getenv("HOMIE_DOMAIN") or "homie",
  homie_mqtt_uri = assert(os.getenv("HOMIE_MQTT_URI"), "environment variable HOMIE_MQTT_URI not set"),
  homie_device_id = os.getenv("HOMIE_DEVICE_ID") or "millheat",
  homie_device_name = os.getenv("HOMIE_DEVICE_NAME") or "Millheat-to-Homie bridge",
}
if opts.millheat_api_key then
  opts.millheat_username = nil
  opts.millheat_password = nil
else
  if opts.millheat_username == nil or opts.millheat_password == nil then
    error("either MILLHEAT_USERNAME and MILLHEAT_PASSWORD must both be set, or MILLHEAT_API_KEY must be set")
  end
end

logger:info("Bridge configuration:")
logger:info("MILLHEAT_API_KEY: %s", (opts.millheat_api_key and "********" or "nil"))
logger:info("MILLHEAT_USERNAME: %s", opts.millheat_username or "nil")
logger:info("MILLHEAT_PASSWORD: %s", (opts.millheat_password and "********" or "nil"))
logger:info("MILLHEAT_POLL_INTERVAL: %d seconds", opts.millheat_poll_interval)
logger:info("HOMIE_DOMAIN: %s", opts.homie_domain)
logger:info("HOMIE_MQTT_URI: %s", opts.homie_mqtt_uri)
logger:info("HOMIE_DEVICE_ID: %s", opts.homie_device_id)
logger:info("HOMIE_DEVICE_NAME: %s", opts.homie_device_name)


copas.loop(function()
  require("homie-millheat")(opts)
end)

ll.defaultLogger():info("Millheat-to-Homie bridge exited")
