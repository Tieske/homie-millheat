--- Millheat-to-Homie bridge.
--
-- This module instantiates a homie device acting as a bridge between the Millheat
-- API and Homie.
--
-- The module returns a single function that takes an options table. When called
-- it will construct a Homie device and add it to the Copas scheduler (without
-- running the scheduler).
-- @copyright Copyright (c) 2022-2022 Thijs Schreijer
-- @author Thijs Schreijer
-- @license MIT, see `LICENSE`.
-- @usage
-- local copas = require "copas"
-- local hmh = require "homie-millheat"
--
-- hmh {
--   millheat_access_key = "xxxxxxxx",
--   millheat_secret_token = "xxxxxxxx",
--   millheat_username = "xxxxxxxx",
--   millheat_password = "xxxxxxxx",
--   millheat_poll_interval = 15,            -- default: 15 seconds
--   homie_mqtt_uri = "http://mqtthost:123", -- format: "mqtt(s)://user:pass@hostname:port"
--   homie_domain = "homie",                 -- default: "homie"
--   homie_device_id = "millheat",           -- default: "millheat"
--   homie_device_name = "M2H bridge",       -- default: "Millheat-to-Homie bridge"
-- }
--
-- copas.loop()

local copas = require "copas"
local copas_timer = require "copas.timer"
local Device = require "homie.device"
local log = require("logging").defaultLogger()
local json = require "cjson.safe"

local RETRIES = 3 -- retries for setting a new setpoint
local RETRY_DELAY = 1 -- in seconds, doubled after each try (as back-off mechanism)


local function get_devices(self)
  local devices = {}
  local homes, err = self.millheat:get_homes()
  if not homes then return homes, err or "millheat:get_homes() failed" end
  -- print("homes: ", require("pl.pretty").write(homes))

  for i, home in ipairs(homes) do
    home.homeId = string.format("%d", home.homeId) -- tostring  proper format

    local heaters, err = self.millheat:get_independent_devices_by_home(home.homeId)
    if not heaters then return heaters, err or "millheat:get_independent_devices_by_home() failed" end

    for j, heater in ipairs(heaters) do
      heater.deviceId = string.format("%d", heater.deviceId) -- tostring  proper format
      -- print("device: ", require("pl.pretty").write(heater))

      devices[#devices + 1] = {
        homeName = home.homeName,
        homeId = string.format("%d", home.homeId),
        deviceName = (home.homeName .. "-" .. heater.deviceName):lower(),
        deviceId = string.format("%d", heater.deviceId),
        temperature = heater.ambientTemperature,
        heating = heater.heatingStatus ~= 0, -- convert to boolean
        openWindow = heater.openWindow ~= 0, -- convert to boolean
      }

      -- independentTemp setpoint is only available on individual devices, so need another request
      heater, err = self.millheat:get_device(heater.deviceId)
      if not heater then return heater, err or "millheat:get_device() failed" end
      --print("device: ", require("pl.pretty").write(heater))
      devices[#devices].setpoint = heater.independentTemp
    end

  end

  -- print("device reported: ", require("pl.pretty").write(devices))
  return devices
end


local function create_device(self_bridge)
  local newdevice = {
    uri = self_bridge.homie_mqtt_uri,
    domain = self_bridge.homie_domain,
    broker_state = 3,  -- recover state from broker, in 3 seconds
    id = self_bridge.homie_device_id,
    homie = "4.0.0",
    extensions = "",
    name = self_bridge.homie_device_name,
    nodes = {}
  }

  for i, heater in ipairs(self_bridge.device_list) do
    local node = {}
    newdevice.nodes[heater.deviceName] = node

    node.name = "Electrical heater " .. heater.deviceName
    node.type = "Thermostat"
    node.properties = {
      temperature = {
        name = "temperature",
        datatype = "integer",
        settable = false,
        retained = true,
        default = type(heater.temperature) == "number" and heater.temperature or 10, -- 10 C as safe-haven
        unit = "C",
      },
      setpoint = {
        name = "setpoint",
        datatype = "integer",
        settable = true,
        retained = true,
        default = heater.setpoint,
        unit = "C",
        format = "0:35", -- follows the Millheat app, API accepts more
        set = function(self, value, remote)
          if self.device.state == Device.states.init or not remote then
            -- local change, probably retrieved from Millheat API, so just change locally,
            -- or in INIT phase we do not yet update
            return self:update(value)
          end

          log:debug("[homie-millheat] setting new mqtt-setpoint received for '%s': %d", self.node.name, value)
          local device_id = self.node.properties["millheat-device-id"]:get()

          local ok, err
          for i = 1, RETRIES+1 do
            ok, err = self_bridge.millheat:control_device(device_id, "temperature", "single", value)
            if ok then
              break;
            end
            log:warn("[homie-millheat] failed setting new mqtt-setpoint for '%s' (attempt %d): %s", self.node.name, i, err)
            if i ~= RETRIES+1 then
              copas.pause(i * RETRY_DELAY)
            end
          end

          if ok then
            log:debug("[homie-millheat] successfully set new mqtt-setpoint for '%s': %d", self.node.name, value)
            return self:update(value)
          else
            log:error("[homie-millheat] failed setting new mqtt-setpoint for '%s': %d (%d attempts)", self.node.name, value, RETRIES+1)
          end
        end,
      },
      heating = {
        name = "heating",
        datatype = "boolean",
        settable = false,
        retained = true,
        default = heater.heating,
      },
      ["window-open"] = {
        name = "window-open",
        datatype = "boolean",
        settable = false,
        retained = true,
        default = heater.openWindow,
      },
      ["millheat-device-id"] = {
        name = "millheat-device-id",
        datatype = "string",
        settable = false,
        retained = true,
        default = heater.deviceId,
      },
    }
  end

  return Device.new(newdevice)
end

--local homie_device


local function timer_callback(timer, self)
  log:debug("[homie-millheat] starting update")

  local devices, err = get_devices(self)
  if not devices then
    log:error("[homie-millheat] failed to update devices: %s", tostring(err))
    return
  end

  -- check if device-list has changed
  local changed = #devices ~= #self.device_list
  if not changed then -- equal length, check contents: check against names, not ID's, because that's how they are published
    for i, new_heater in ipairs(devices) do
      local found = false
      for j, old_heater in ipairs(self.device_list) do
        if new_heater.deviceName == old_heater.deviceName then
          found = true
          break
        end
      end
      if not found then
        changed = true
      end
    end
  end

  -- set new device values
  self.device_list = devices

  if changed then
    log:info("[homie-millheat] device list changed, updating device")
    if self.homie_device then
      self.homie_device:stop()
    end

    self.homie_device = create_device(self)
    self.homie_device:start()
  else
    log:debug("[homie-millheat] device list is unchanged")
  end

  -- update retrieved values
  for i, heater in ipairs(self.device_list) do
    local node = self.homie_device.nodes[heater.deviceName]
    if heater.temperature == "--.-" then
      log:warn("[homie-millheat] No temperature value received for '%s', Received data: %s", tostring(heater.deviceName), json.encode(heater))
    else
      local ok, err = node.properties.temperature:set(heater.temperature)
      if not ok then
        log:error("[homie-millheat] Setting new temperature failed: '%s' Received data: %s", tostring(err), json.encode(heater))
      end
    end

    local ok, err = node.properties.setpoint:set(heater.setpoint)
    if not ok then
      log:error("[homie-millheat] Setting new setpoint failed: '%s' Received data: %s", tostring(err), json.encode(heater))
    end

    local ok, err = node.properties.heating:set(heater.heating)
    if not ok then
      log:error("[homie-millheat] Setting new heating-status failed: '%s' Received data: %s", tostring(err), json.encode(heater))
    end

    local ok, err = node.properties["window-open"]:set(heater.openWindow)
    if not ok then
      log:error("[homie-millheat] Setting new window-open status failed: '%s' Received data: %s", tostring(err), json.encode(heater))
    end
  end
end



return function(self)
  -- Millheat API session object
  self.millheat = require("millheat").new(
    self.millheat_access_key, self.millheat_secret_token,
    self.millheat_username, self.millheat_password)

  self.device_list = {}  -- last list retrieved

  self.timer = copas_timer.new {
    name = "homie-millheat updater",
    recurring = true,
    delay = self.millheat_poll_interval,
    initial_delay = 0,
    callback = timer_callback,
    params = self,
  }
end
