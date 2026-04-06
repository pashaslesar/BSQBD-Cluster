mongos \
    --configdb csrs/configsvr1:27019,configsvr2:27019,configsvr3:27019 \
    --bind_ip_all --port 27017 \
    --keyFile /keyfile/mongodb.key &
MONGOS_PID=$!

bash /scripts/setup-cluster.sh

wait $MONGOS_PID
