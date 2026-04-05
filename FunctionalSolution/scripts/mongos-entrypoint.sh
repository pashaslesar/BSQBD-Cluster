#!/bin/bash
# Entrypoint for the mongos container.
# Starts mongos in the background, then runs cluster setup inside this container.

# Start mongos in the background
mongos \
    --configdb csrs/configsvr1:27019,configsvr2:27019,configsvr3:27019 \
    --bind_ip_all --port 27017 &
MONGOS_PID=$!

# Run full cluster initialisation (replica sets, sharding, data import)
bash /scripts/setup-cluster.sh

# Keep the container alive by waiting for the mongos process
wait $MONGOS_PID
