#!/usr/bin/env bash

docker build --no-cache --tag tieske/homie-millheat:dev .
docker image push tieske/homie-millheat:dev
