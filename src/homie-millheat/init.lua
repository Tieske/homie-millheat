--- This module does something.
--
-- Explain some basics, or the design.
--
-- @copyright Copyright (c) 2022-2022 Thijs Schreijer
-- @author Thijs Schreijer
-- @license MIT, see `LICENSE`.

local copas = require "copas"
local copas_timer = require "copas.timer"
local Device = require "homie.device"
local log = require("logging").defaultLogger()

local RETRIES = 3 -- retries for setting a new setpoint
local RETRY_DELAY = 1 -- in seconds, doubled after each try (as back-off mechanism)


local function get_devices(self)
  local devices = {}
  local homes, err = self.millheat:get_homes()
  if not homes then return homes, err end
  -- print("homes: ", require("pl.pretty").write(homes))

  for i, home in ipairs(homes) do
    home.homeId = string.format("%d", home.homeId) -- tostring  proper format

    local heaters, err = self.millheat:get_independent_devices_by_home(home.homeId)
    if not heaters then return heaters, err end

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
      if not heater then return heater, err end
      --print("device: ", require("pl.pretty").write(heater))
      devices[#devices].setpoint = heater.independentTemp
    end

  end

  -- print("device reported: ", require("pl.pretty").write(devices))
  return devices
end


local function create_device(self)
  local newdevice = {
    uri = self.homie_mqtt_uri,
    domain = self.homie_domain,
    broker_state = 3,
    id = self.homie_device_id,
    homie = "4.0.0",
    extensions = "",
    name = self.homie_device_name,
    nodes = {}
  }

  for i, heater in ipairs(self.device_list) do
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
        default = heater.temperature,
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
          if self.device.state == Device.states.init or
             not remote then
            -- local change, probably retrieved from Millheat API, so just change locally,
            -- or in INIT phase we do not yet update
            self:update(value)
            return
          end

          log:debug("[homie-millheat] setting new mqtt-setpoint received for '%s': %d", self.node.name, value)
          local device_id = self.node.properties["millheat-device-id"]:get()

          local ok, err
          for i = 1, RETRIES+1 do
            ok, err = self.millheat:control_device(device_id, "temperature", "single", value)
            if ok then
              break;
            end
            log:warn("[homie-millheat] failed setting new mqtt-setpoint for '%s' (attempt %d): %s", self.node.name, i, err)
            if i ~= RETRIES+1 then
              copas.sleep(i * RETRY_DELAY)
            end
          end

          if ok then
            log:debug("[homie-millheat] successfully set new mqtt-setpoint for '%s': %d", self.node.name, value)
            self:update(value)
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
    log:error("[homie-millheat] failed to update devices: %s", err)
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
    if node.properties.temperature:get() ~= heater.temperature then
      log:debug("[homie-millheat] new temperature received for '%s': %d", heater.deviceName, heater.temperature)
      node.properties.temperature:set(heater.temperature)
    end
    if node.properties.setpoint:get() ~= heater.setpoint then
      log:debug("[homie-millheat] new setpoint received for '%s': %d", heater.deviceName, heater.setpoint)
      node.properties.setpoint:set(heater.setpoint)
    end
    if node.properties.heating:get() ~= heater.heating then
      log:debug("[homie-millheat] new heating status received for '%s': %s", heater.deviceName, heater.heating)
      node.properties.heating:set(heater.heating)
    end
    if node.properties["window-open"]:get() ~= heater.openWindow then
      log:debug("[homie-millheat] new window-open status received for '%s': %s", heater.deviceName, heater.openWindow)
      node.properties["window-open"]:set(heater.openWindow)
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
