#!/usr/bin/env bash

#export MILLHEAT_API_KEY="apikey here..."
export MILLHEAT_USERNAME="user@email.com"
export MILLHEAT_PASSWORD="soopersecret password"
export MILLHEAT_POLL_INTERVAL=60
export HOMIE_DOMAIN="homie"
export HOMIE_MQTT_URI="mqtt://synology"
export HOMIE_DEVICE_ID="millheat"
export HOMIE_DEVICE_NAME="Millheat-to-Homie bridge"

# export HOMIE_LOG_LOGGER="rsyslog"
export HOMIE_LOG_LOGLEVEL="debug"
# export HOMIE_LOG_LOGPATTERN="%message (%source)"
# export HOMIE_LOG_RFC="rfc5424"
# export HOMIE_LOG_MAXSIZE="8000"
# export HOMIE_LOG_HOSTNAME="synology.local"
# export HOMIE_LOG_PORT="8514"
# export HOMIE_LOG_PROTOCOL="tcp"
# export HOMIE_LOG_IDENT="homiemillheat"


# LUA_PATH="./src/?/init.lua;./src/?.lua;$LUA_PATH"
# lua bin/homiemillheat.lua

docker run -it --rm \
    -e MILLHEAT_API_KEY \
    -e MILLHEAT_USERNAME \
    -e MILLHEAT_PASSWORD \
    -e MILLHEAT_POLL_INTERVAL \
    -e HOMIE_DOMAIN \
    -e HOMIE_MQTT_URI \
    -e HOMIE_DEVICE_ID \
    -e HOMIE_DEVICE_NAME \
    -e HOMIE_LOG_LOGGER \
    -e HOMIE_LOG_LOGLEVEL \
    -e HOMIE_LOG_LOGPATTERN \
    -e HOMIE_LOG_RFC \
    -e HOMIE_LOG_MAXSIZE \
    -e HOMIE_LOG_HOSTNAME \
    -e HOMIE_LOG_PORT \
    -e HOMIE_LOG_PROTOCOL \
    -e HOMIE_LOG_IDENT \
    tieske/homie-millheat:dev
