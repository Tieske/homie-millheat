FROM akorn/luarocks:lua5.1-alpine as build

RUN apk add \
    gcc \
    git \
    libc-dev \
    make \
    openssl-dev

# install dependencies separately to not have --dev versions for them as well
# RUN luarocks install copas \
#  && luarocks install luasec \
#  && luarocks install penlight \
#  && luarocks install Tieske/luamqtt --dev \
#  && luarocks install homie --dev \
#  && luarocks install luabitop

# copy the local repo contents and build it
COPY ./ /tmp/homie-millheat
WORKDIR /tmp/homie-millheat
RUN luarocks make

# collect cli scripts; the ones that contain "LUAROCKS_SYSCONFDIR" are Lua ones
RUN mkdir /luarocksbin \
 && grep -rl LUAROCKS_SYSCONFDIR /usr/local/bin | \
    while IFS= read -r filename; do \
      cp "$filename" /luarocksbin/; \
    done



FROM akorn/lua:5.1-alpine
RUN apk add --no-cache \
    ca-certificates \
    openssl

# ENV MILLHEAT_API_KEY "api-key..."
# ENV MILLHEAT_USERNAME "username..."
# ENV MILLHEAT_PASSWORD "password..."
ENV MILLHEAT_POLL_INTERVAL "60"
ENV HOMIE_DOMAIN "homie"
ENV HOMIE_MQTT_URI "mqtt://mqtthost:1883"
ENV HOMIE_DEVICE_ID "millheat"
ENV HOMIE_DEVICE_NAME "Millheat-to-Homie bridge"
ENV HOMIE_LOG_LOGLEVEL "debug"

# copy luarocks tree and data over
COPY --from=build /luarocksbin/* /usr/local/bin/
COPY --from=build /usr/local/lib/lua /usr/local/lib/lua
COPY --from=build /usr/local/share/lua /usr/local/share/lua
COPY --from=build /usr/local/lib/luarocks /usr/local/lib/luarocks

CMD ["homiemillheat"]
