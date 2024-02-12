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
--   millheat_api_key = "xxxxxxxx",          -- choose: api_key or username+password !!
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
  local status, homes = self.millheat:srequest("GET:/houses")
  if not status then
    if type(homes) == "table" then
      homes = json.encode(homes)
    end
    return status, "GET:/house failed: "..homes
  end
  homes = homes.ownHouses or {}  -- select only our own houses from the response

  -- print("homes: ", require("pl.pretty").write(homes))

  for i, home in ipairs(homes) do
    local status, heaters = self.millheat:srequest("GET:/houses/{houseId}/devices/independent", {
      houseId = home.id
    })
    if not status then
      if type(heaters) == "table" then
        heaters = json.encode(heaters)
      end
      return status, "GET:/houses/{houseId}/devices/independent failed: "..heaters
    end
    heaters = heaters.items or {}  -- select the devices in the 'items' array of the response

    -- print("heaters: ", require("pl.pretty").write(heaters))

    for j, heater in ipairs(heaters) do
      -- print("device: ", require("pl.pretty").write(heater))

      devices[#devices + 1] = {
        homeName = home.name,
        homeId = home.id,
        deviceName = (home.name .. "-" .. heater.customName):lower(),
        deviceId = heater.deviceId,
        temperature = (heater.lastMetrics or {}).temperatureAmbient,
        heating = (heater.lastMetrics or {}).heaterFlag ~= 0, -- convert to boolean
        openWindow = (heater.lastMetrics or {}).openWindowsStatus ~= 0, -- convert to boolean
        setpoint = ((heater.deviceSettings or {}).desired or {}).temperature_normal,
      }

      -- print("device: ", require("pl.pretty").write(devices[#devices]))
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
        unit = "°C",
      },
      setpoint = {
        name = "setpoint",
        datatype = "integer",
        settable = true,
        retained = true,
        default = heater.setpoint,
        unit = "°C",
        format = "0:35", -- follows the Millheat app, API accepts more
        set = function(self, value, remote)
          if self.device.state == Device.states.init or not remote then
            -- local change, probably retrieved from Millheat API, so just change locally,
            -- or in INIT phase we do not yet update
            return self:update(value)
          end

          log:info("[homie-millheat] setting new mqtt-setpoint received for '%s': %d", self.node.name, value)
          local device_id = self.node.properties["millheat-device-id"]:get()

          local ok, status, err
          for i = 1, RETRIES+1 do
            ok, err, status = self_bridge.millheat:srequest("PATCH:/devices/{deviceId}/settings", {
              deviceId = device_id
            }, {
              deviceType = "Heaters",
              enabled = true,
              settings = {
                operation_mode = "independent_device",
                temperature_normal = value,
              }
            })

            if ok then
              break;
            end

            if type(err) == "table" then
              err = json.encode(err)
            end

            log:warn("[homie-millheat] failed setting new mqtt-setpoint for '%s' (attempt %d): %d: %s", self.node.name, i, status, err)
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
  self.millheat = require("millheat").new {
    username = self.millheat_username,
    password = self.millheat_password,
    api_key = self.millheat_api_key,
  }

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
