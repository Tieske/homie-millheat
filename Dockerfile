FROM akorn/luarocks:lua5.1-alpine as build

RUN apk add make gcc libc-dev git openssl-dev


# install dependencies separately to not have --dev versions for them as well
RUN luarocks install copas
RUN luarocks install luasec
RUN luarocks install penlight
RUN luarocks install Tieske/luamqtt --dev
RUN luarocks install homie --dev
RUN luarocks install luabitop
#RUN luarocks install corowatch --dev

# copy the local repo contents and build it
COPY ./ /tmp/homie-millheat
RUN cd /tmp/homie-millheat && luarocks make
# while unreleased, replace with dev version
#RUN luarocks remove copas --force; luarocks install copas --dev --deps-mode none


FROM akorn/lua:5.1-alpine
RUN apk add --no-cache openssl ca-certificates

# copy luarocks tree and data over
COPY --from=build /usr/local/lib/lua /usr/local/lib/lua
COPY --from=build /usr/local/share/lua /usr/local/share/lua
COPY --from=build /usr/local/lib/luarocks /usr/local/lib/luarocks
# copy the command as generated by LuaRocks
COPY --from=build /usr/local/bin/homiemillheat /usr/local/bin/homiemillheat

CMD homiemillheat
