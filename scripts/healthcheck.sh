#!/bin/bash

curl -f https://statuspulse.umehta.xyz/health \
|| echo "Healthcheck failed"
