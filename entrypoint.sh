#!/bin/bash
set -e

if [ "${MODE}" = "backend" ]; then
    exec rpc-server \
        --host 0.0.0.0 \
        --port "${PORT:-50052}" \
        -c
else
    exec llama-server "$@"
fi
