#!/usr/bin/env lua

--- Main application.
-- Reads config from environment variables and starts the Millheat-to-Homie bridge.
-- Does not support any CLI parameters.
-- @module homiemillheat
-- @usage
-- # configure parameters as environment variables
-- export MILLHEAT_ACCESS_KEY="sooper-secret"
-- # start the application
-- homiemillheat

local ansicolors = require "ansicolors" -- https://github.com/kikito/ansicolors.lua
local ll = require "logging"

local log_level = tostring(os.getenv("HOMIE_LOG_LEVEL") or "INFO"):upper()

local logger do -- configure the default logger
  require "logging.console"

  logger = ll.defaultLogger(ll.console {
    logLevel = ll[log_level],
    destination = "stderr",
    timestampPattern = "%y-%m-%d %H:%M:%S",
    logPatterns = {
      [ll.DEBUG] = ansicolors("%date%{cyan} %level %message %{reset}(%source)\n"),
      [ll.INFO] = ansicolors("%date %level %message\n"),
      [ll.WARN] = ansicolors("%date%{yellow} %level %message\n"),
      [ll.ERROR] = ansicolors("%date%{red bright} %level %message %{reset}(%source)\n"),
      [ll.FATAL] = ansicolors("%date%{magenta bright} %level %message %{reset}(%source)\n"),
    }
  })
end


local copas = require "copas"

do -- set Copas errorhandler
  local lines = require("pl.stringx").lines
  copas.setErrorHandler(function(msg, co, skt)
    -- TODO: remove this code once Copas 4.1.0 is released
    local co_str = co == nil and "nil" or copas.getthreadname(co)
    local skt_str = skt == nil and "nil" or copas.getsocketname(skt)

    msg = ("%s (coroutine: %s, socket: %s)"):format(tostring(msg), co_str, skt_str)

    if type(co) == "thread" then
      -- regular Copas coroutine
      msg = debug.traceback(co, msg)
    else
      -- not a coroutine, but the main thread, this happens if a timeout callback
      -- (see `copas.timeout` causes an error (those callbacks run on the main thread).
      msg = debug.traceback(msg, 2)
    end

    for line in lines(msg) do
      ll.defaultLogger():error(line)
    end
  end , true)
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
  homie_device_name = os.getenv("HOMIE_DEVICE_NAME") or "millheat-to-homie bridge",
}

logger:info("Bridge configuration:")
logger:info("MILLHEAT_ACCESS_KEY: ********")
logger:info("MILLHEAT_SECRET_TOKEN: ********")
logger:info("MILLHEAT_USERNAME: %s", opts.millheat_username)
logger:info("MILLHEAT_PASSWORD: ********")
logger:info("MILLHEAT_POLL_INTERVAL: %d seconds", opts.millheat_poll_interval)
logger:info("HOMIE_LOG_LEVEL: %s", log_level)
logger:info("HOMIE_DOMAIN: %s", opts.homie_domain)
logger:info("HOMIE_MQTT_URI: %s", opts.homie_mqtt_uri)
logger:info("HOMIE_DEVICE_ID: %s", opts.homie_device_id)
logger:info("HOMIE_DEVICE_NAME: %s", opts.homie_device_name)


copas.loop(function()
  require("homie-millheat")(opts)
end)

ll.defaultLogger():info("Millheat-to-Homie bridge exited")
