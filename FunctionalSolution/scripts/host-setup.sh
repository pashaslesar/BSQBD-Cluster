set -e

DATA_DIR="$(cd "$(dirname "$0")/../.." && pwd)/Data"

wait_container() {
    local name=$1 port=$2
    echo "[wait] $name:$port ..."
    until docker exec "$name" mongosh --port "$port" --quiet \
          --eval "db.adminCommand({ping:1})" >/dev/null 2>&1; do
        sleep 3
    done
    echo "[ok]   $name:$port"
}

rs_initialized() {
    docker exec "$1" mongosh --port "$2" --quiet \
        --eval "try { var s=rs.status(); print(s.ok===1?'yes':'no') } catch(e){ print('no') }" \
        2>/dev/null | grep -q "^yes"
}

wait_primary() {
    local name=$1 port=$2
    echo "[wait] primary on $name:$port ..."
    until docker exec "$name" mongosh --port "$port" --quiet \
          --eval "print(rs.isMaster().ismaster||rs.isMaster().secondary)" \
          2>/dev/null | grep -q "^true"; do
        sleep 3
    done
    echo "[ok]   $name:$port has a primary"
}

count_docs() {
    docker exec mongos mongosh --port 27017 --quiet \
        --eval "db.getSiblingDB('restaurants').$1.estimatedDocumentCount()" 2>/dev/null || echo "0"
}

echo ""
echo "══════════════════════════════════════════"
echo " STEP 1 – Config Server Replica Set (csrs)"
echo "══════════════════════════════════════════"
wait_container configsvr1 27019
wait_container configsvr2 27019
wait_container configsvr3 27019

if rs_initialized configsvr1 27019; then
    echo "[skip] csrs already initialized"
else
    echo "[init] Initializing csrs ..."
    docker exec configsvr1 mongosh --port 27019 --quiet --eval '
    rs.initiate({
        _id: "csrs",
        configsvr: true,
        members: [
            { _id: 0, host: "configsvr1:27019", priority: 2 },
            { _id: 1, host: "configsvr2:27019", priority: 1 },
            { _id: 2, host: "configsvr3:27019", priority: 1 }
        ]
    })'
    echo "[done] csrs initiated"
fi
wait_primary configsvr1 27019

echo ""
echo "══════════════════════════════════════════"
echo " STEP 2a – Shard RS: rs1"
echo "══════════════════════════════════════════"
wait_container shard1-1 27018
wait_container shard1-2 27018
wait_container shard1-3 27018
if rs_initialized shard1-1 27018; then
    echo "[skip] rs1 already initialized"
else
    echo "[init] Initializing rs1 ..."
    docker exec shard1-1 mongosh --port 27018 --quiet --eval '
    rs.initiate({
        _id: "rs1",
        members: [
            { _id: 0, host: "shard1-1:27018", priority: 2 },
            { _id: 1, host: "shard1-2:27018", priority: 1 },
            { _id: 2, host: "shard1-3:27018", priority: 1 }
        ]
    })'
    echo "[done] rs1 initiated"
fi
wait_primary shard1-1 27018

echo ""
echo "══════════════════════════════════════════"
echo " STEP 2b – Shard RS: rs2"
echo "══════════════════════════════════════════"
wait_container shard2-1 27018
wait_container shard2-2 27018
wait_container shard2-3 27018
if rs_initialized shard2-1 27018; then
    echo "[skip] rs2 already initialized"
else
    echo "[init] Initializing rs2 ..."
    docker exec shard2-1 mongosh --port 27018 --quiet --eval '
    rs.initiate({
        _id: "rs2",
        members: [
            { _id: 0, host: "shard2-1:27018", priority: 2 },
            { _id: 1, host: "shard2-2:27018", priority: 1 },
            { _id: 2, host: "shard2-3:27018", priority: 1 }
        ]
    })'
    echo "[done] rs2 initiated"
fi
wait_primary shard2-1 27018

echo ""
echo "══════════════════════════════════════════"
echo " STEP 2c – Shard RS: rs3"
echo "══════════════════════════════════════════"
wait_container shard3-1 27018
wait_container shard3-2 27018
wait_container shard3-3 27018
if rs_initialized shard3-1 27018; then
    echo "[skip] rs3 already initialized"
else
    echo "[init] Initializing rs3 ..."
    docker exec shard3-1 mongosh --port 27018 --quiet --eval '
    rs.initiate({
        _id: "rs3",
        members: [
            { _id: 0, host: "shard3-1:27018", priority: 2 },
            { _id: 1, host: "shard3-2:27018", priority: 1 },
            { _id: 2, host: "shard3-3:27018", priority: 1 }
        ]
    })'
    echo "[done] rs3 initiated"
fi
wait_primary shard3-1 27018

echo ""
echo "══════════════════════════════════════════"
echo " STEP 3 – Wait for mongos"
echo "══════════════════════════════════════════"
wait_container mongos 27017
echo "[ok]   mongos is up"

echo ""
echo "══════════════════════════════════════════"
echo " STEP 4 – Add shards"
echo "══════════════════════════════════════════"
SHARD_COUNT=$(docker exec mongos mongosh --port 27017 --quiet \
    --eval "db.adminCommand({listShards:1}).shards.length" 2>/dev/null || echo "0")

if [ "$SHARD_COUNT" -ge 3 ] 2>/dev/null; then
    echo "[skip] Shards already registered ($SHARD_COUNT)"
else
    echo "[add]  Adding rs1, rs2, rs3 ..."
    docker exec mongos mongosh --port 27017 --quiet --eval '
    sh.addShard("rs1/shard1-1:27018,shard1-2:27018,shard1-3:27018");
    sh.addShard("rs2/shard2-1:27018,shard2-2:27018,shard2-3:27018");
    sh.addShard("rs3/shard3-1:27018,shard3-2:27018,shard3-3:27018");
    print("shards added");'
fi

echo ""
echo "══════════════════════════════════════════"
echo " STEP 5-7 – Collections / Sharding"
echo "══════════════════════════════════════════"
docker exec mongos mongosh --port 27017 --quiet --eval '
sh.enableSharding("restaurants");
var db = db.getSiblingDB("restaurants");
var cols = db.getCollectionNames();

if (!cols.includes("dubai_restaurants")) {
    db.createCollection("dubai_restaurants", {
        validator: { $jsonSchema: { bsonType: "object", required: ["name","location","category"],
            properties: {
                name:        { bsonType: "string" },
                location:    { bsonType: "string" },
                category:    { bsonType: "string" },
                address:     { bsonType: ["string","null"] },
                id:          { bsonType: ["int","double","null"] },
                lat:         { bsonType: ["double","null"] },
                lng:         { bsonType: ["double","null"] },
                polarity:    { bsonType: ["int","double","null"] },
                subCategory: { bsonType: ["string","null"] }
            }}}, validationAction: "warn"
    });
    print("[done] dubai_restaurants created");
} else { print("[skip] dubai_restaurants exists"); }

if (!cols.includes("usa_fastfood")) {
    db.createCollection("usa_fastfood", {
        validator: { $jsonSchema: { bsonType: "object", required: ["name","city","country"],
            properties: {
                name:      { bsonType: "string" },
                city:      { bsonType: "string" },
                country:   { bsonType: "string" },
                address:   { bsonType: ["string","null"] },
                province:  { bsonType: ["string","null"] },
                latitude:  { bsonType: ["double","null"] },
                longitude: { bsonType: ["double","null"] }
            }}}, validationAction: "warn"
    });
    print("[done] usa_fastfood created");
} else { print("[skip] usa_fastfood exists"); }

if (!cols.includes("indian_restaurants")) {
    db.createCollection("indian_restaurants", {
        validator: { $jsonSchema: { bsonType: "object", required: ["restaurant_name","location"],
            properties: {
                restaurant_name:       { bsonType: "string" },
                location:              { bsonType: "string" },
                rating:                { bsonType: ["double","int","null"] },
                average_price:         { bsonType: ["double","int","null"] },
                average_delivery_time: { bsonType: ["double","int","null"] }
            }}}, validationAction: "warn"
    });
    print("[done] indian_restaurants created");
} else { print("[skip] indian_restaurants exists"); }

db.dubai_restaurants.createIndex({ subCategory: "hashed" });
db.usa_fastfood.createIndex({ name: "hashed" });
db.indian_restaurants.createIndex({ location: "hashed" });
db.dubai_restaurants.createIndex({ polarity: 1 });
db.dubai_restaurants.createIndex({ location: 1 });
db.usa_fastfood.createIndex({ province: 1 });
db.usa_fastfood.createIndex({ city: 1 });
db.indian_restaurants.createIndex({ rating: 1 });
db.indian_restaurants.createIndex({ average_price: 1 });

sh.shardCollection("restaurants.dubai_restaurants", { subCategory: "hashed" });
sh.shardCollection("restaurants.usa_fastfood",      { name: "hashed" });
sh.shardCollection("restaurants.indian_restaurants", { location: "hashed" });
print("[done] All collections sharded");

db.getSiblingDB("config").settings.updateOne(
    { _id: "chunksize" }, { $set: { value: 32 } }, { upsert: true }
);
print("[done] Chunk size 32 MB");
'

echo ""
echo "══════════════════════════════════════════"
echo " STEP 8 – Import CSV data"
echo "══════════════════════════════════════════"

echo ""
echo "── dubai_restaurants ──"
CNT=$(count_docs dubai_restaurants)
if [ "$CNT" -gt 100 ]; then
    echo "[skip] already has $CNT docs"
else
    echo "[import] dubai_restaurants ..."
    docker exec -i mongos mongoimport \
        --port 27017 --db restaurants --collection dubai_restaurants \
        --type csv --headerline --ignoreBlanks --numInsertionWorkers 4 \
        < "$DATA_DIR/dubai-restaurants.csv"
fi

echo ""
echo "── usa_fastfood ──"
CNT=$(count_docs usa_fastfood)
if [ "$CNT" -gt 100 ]; then
    echo "[skip] already has $CNT docs"
else
    echo "[import] usa_fastfood ..."
    docker exec -i mongos mongoimport \
        --port 27017 --db restaurants --collection usa_fastfood \
        --type csv --headerline --ignoreBlanks --numInsertionWorkers 4 \
        < "$DATA_DIR/fastfood-usa-restaurants.csv"
fi

echo ""
echo "── indian_restaurants ──"
CNT=$(count_docs indian_restaurants)
if [ "$CNT" -gt 100 ]; then
    echo "[skip] already has $CNT docs"
else
    echo "[import] indian_restaurants ..."
    sed 's/\xef\xbb\xbf//' "$DATA_DIR/indian-restaurants.csv" \
        | sed '1s/average _delivery_time/average_delivery_time/' \
        | docker exec -i mongos mongoimport \
            --port 27017 --db restaurants --collection indian_restaurants \
            --type csv --headerline --ignoreBlanks --numInsertionWorkers 4
fi

echo ""
echo "── Record counts ──"
docker exec mongos mongosh --port 27017 --quiet --eval "
var db = db.getSiblingDB('restaurants');
['dubai_restaurants','usa_fastfood','indian_restaurants'].forEach(c => {
    print(c + ': ' + db[c].estimatedDocumentCount() + ' docs');
});
"

echo ""
echo "── Chunk distribution across shards ──"
docker exec mongos mongosh --port 27017 --quiet --eval "
db.getSiblingDB('config').chunks.aggregate([
  { \$group: { _id: '\$shard', chunks: { \$sum: 1 } } },
  { \$sort: { _id: 1 } }
]).forEach(d => print(d._id + ': ' + d.chunks + ' chunks'));
"

echo ""
echo "╔══════════════════════════════════════════╗"
echo "║   Cluster setup complete!                ║"
echo "║   mongosh:     localhost:27017           ║"
echo "║   Compass Web: http://localhost:8080     ║"
echo "╚══════════════════════════════════════════╝"
