set -e

wait_mongo() {
    local host=$1 port=$2
    echo "[wait] $host:$port ..."
    until mongosh --host "$host" --port "$port" --quiet \
          --eval "db.adminCommand({ping:1})" >/dev/null 2>&1; do
        sleep 3
    done
    echo "[ok]   $host:$port is reachable"
}

rs_initialized() {
    local host=$1 port=$2
    mongosh --host "$host" --port "$port" --quiet \
        --eval "try { var s=rs.status(); print(s.ok===1?'yes':'no') } catch(e){ print('no') }" \
        2>/dev/null | grep -q "^yes"
}

wait_primary() {
    local host=$1 port=$2
    echo "[wait] primary on $host:$port ..."
    until mongosh --host "$host" --port "$port" --quiet \
          --eval "print(rs.isMaster().ismaster||rs.isMaster().secondary)" \
          2>/dev/null | grep -q "^true"; do
        sleep 3
    done
    echo "[ok]   RS on $host:$port has a primary"
}


echo ""
echo "══════════════════════════════════════════"
echo " STEP 1 – Config Server Replica Set (csrs)"
echo "══════════════════════════════════════════"

wait_mongo configsvr1 27019
wait_mongo configsvr2 27019
wait_mongo configsvr3 27019

if rs_initialized configsvr1 27019; then
    echo "[skip] csrs already initialized"
else
    echo "[init] Initializing csrs ..."
    mongosh --host configsvr1 --port 27019 --quiet --eval '
    rs.initiate({
        _id: "csrs",
        configsvr: true,
        members: [
            { _id: 0, host: "configsvr1:27019", priority: 2 },
            { _id: 1, host: "configsvr2:27019", priority: 1 },
            { _id: 2, host: "configsvr3:27019", priority: 1 }
        ]
    })
    '
    echo "[done] csrs initiated"
fi

wait_primary configsvr1 27019

# rs1
echo ""
echo "══════════════════════════════════════════"
echo " STEP 2a – Shard RS: rs1"
echo "══════════════════════════════════════════"
wait_mongo shard1-1 27018
wait_mongo shard1-2 27018
wait_mongo shard1-3 27018
if rs_initialized shard1-1 27018; then
    echo "[skip] rs1 already initialized"
else
    echo "[init] Initializing rs1 ..."
    mongosh --host shard1-1 --port 27018 --quiet --eval '
    rs.initiate({
        _id: "rs1",
        members: [
            { _id: 0, host: "shard1-1:27018", priority: 2 },
            { _id: 1, host: "shard1-2:27018", priority: 1 },
            { _id: 2, host: "shard1-3:27018", priority: 1 }
        ]
    })
    '
    echo "[done] rs1 initiated"
fi
wait_primary shard1-1 27018

# rs2
echo ""
echo "══════════════════════════════════════════"
echo " STEP 2b – Shard RS: rs2"
echo "══════════════════════════════════════════"
wait_mongo shard2-1 27018
wait_mongo shard2-2 27018
wait_mongo shard2-3 27018
if rs_initialized shard2-1 27018; then
    echo "[skip] rs2 already initialized"
else
    echo "[init] Initializing rs2 ..."
    mongosh --host shard2-1 --port 27018 --quiet --eval '
    rs.initiate({
        _id: "rs2",
        members: [
            { _id: 0, host: "shard2-1:27018", priority: 2 },
            { _id: 1, host: "shard2-2:27018", priority: 1 },
            { _id: 2, host: "shard2-3:27018", priority: 1 }
        ]
    })
    '
    echo "[done] rs2 initiated"
fi
wait_primary shard2-1 27018

# rs3
echo ""
echo "══════════════════════════════════════════"
echo " STEP 2c – Shard RS: rs3"
echo "══════════════════════════════════════════"
wait_mongo shard3-1 27018
wait_mongo shard3-2 27018
wait_mongo shard3-3 27018
if rs_initialized shard3-1 27018; then
    echo "[skip] rs3 already initialized"
else
    echo "[init] Initializing rs3 ..."
    mongosh --host shard3-1 --port 27018 --quiet --eval '
    rs.initiate({
        _id: "rs3",
        members: [
            { _id: 0, host: "shard3-1:27018", priority: 2 },
            { _id: 1, host: "shard3-2:27018", priority: 1 },
            { _id: 2, host: "shard3-3:27018", priority: 1 }
        ]
    })
    '
    echo "[done] rs3 initiated"
fi
wait_primary shard3-1 27018


echo ""
echo "══════════════════════════════════════════"
echo " STEP 3 – Wait for mongos"
echo "══════════════════════════════════════════"
wait_mongo mongos 27017
echo "[ok]   mongos is up"


echo ""
echo "══════════════════════════════════════════"
echo " STEP 4 – Add shards to mongos"
echo "══════════════════════════════════════════"

SHARD_COUNT=$(mongosh --host mongos --port 27017 --quiet \
    --eval "db.adminCommand({listShards:1}).shards.length" 2>/dev/null || echo "0")

if [ "$SHARD_COUNT" -ge 3 ] 2>/dev/null; then
    echo "[skip] Shards already registered ($SHARD_COUNT)"
else
    echo "[add]  Adding rs1, rs2, rs3 ..."
    mongosh --host mongos --port 27017 --quiet --eval '
    sh.addShard("rs1/shard1-1:27018,shard1-2:27018,shard1-3:27018");
    sh.addShard("rs2/shard2-1:27018,shard2-2:27018,shard2-3:27018");
    sh.addShard("rs3/shard3-1:27018,shard3-2:27018,shard3-3:27018");
    print("shards added");
    '
fi


echo ""
echo "══════════════════════════════════════════"
echo " STEP 5-7 – Database / collections / sharding"
echo "══════════════════════════════════════════"

mongosh --host mongos --port 27017 --quiet << 'EOJS'

// ── enable sharding on the database ──────────────────────────────────────────
sh.enableSharding("restaurants");

var db = db.getSiblingDB("restaurants");
var cols = db.getCollectionNames();

// ── dubai_restaurants ─────────────────────────────────────────────────────────
if (!cols.includes("dubai_restaurants")) {
    db.createCollection("dubai_restaurants", {
        validator: {
            $jsonSchema: {
                bsonType: "object",
                required: ["name", "location", "category"],
                properties: {
                    name:        { bsonType: "string",             description: "Restaurant name – required" },
                    location:    { bsonType: "string",             description: "City/area – required" },
                    category:    { bsonType: "string",             description: "Top-level category – required" },
                    address:     { bsonType: ["string","null"] },
                    id:          { bsonType: ["int","double","null"] },
                    lat:         { bsonType: ["double","null"] },
                    lng:         { bsonType: ["double","null"] },
                    polarity:    { bsonType: ["int","double","null"] },
                    subCategory: { bsonType: ["string","null"] },
                    originalId:  { bsonType: ["string","null"] },
                    details:     { bsonType: ["string","null"] },
                    reviews:     { bsonType: ["string","null"] }
                }
            }
        },
        validationAction: "warn"
    });
    print("[done] dubai_restaurants collection created");
} else {
    print("[skip] dubai_restaurants already exists");
}

// ── usa_fastfood ──────────────────────────────────────────────────────────────
if (!cols.includes("usa_fastfood")) {
    db.createCollection("usa_fastfood", {
        validator: {
            $jsonSchema: {
                bsonType: "object",
                required: ["name", "city", "country"],
                properties: {
                    name:       { bsonType: "string", description: "Chain name – required" },
                    city:       { bsonType: "string", description: "City – required" },
                    country:    { bsonType: "string", description: "Country code – required" },
                    address:    { bsonType: ["string","null"] },
                    province:   { bsonType: ["string","null"] },
                    postalCode: { bsonType: ["string","null"] },
                    keys:       { bsonType: ["string","null"] },
                    latitude:   { bsonType: ["double","null"] },
                    longitude:  { bsonType: ["double","null"] },
                    websites:   { bsonType: ["string","null"] }
                }
            }
        },
        validationAction: "warn"
    });
    print("[done] usa_fastfood collection created");
} else {
    print("[skip] usa_fastfood already exists");
}

// ── indian_restaurants ────────────────────────────────────────────────────────
if (!cols.includes("indian_restaurants")) {
    db.createCollection("indian_restaurants", {
        validator: {
            $jsonSchema: {
                bsonType: "object",
                required: ["restaurant_name", "location"],
                properties: {
                    restaurant_name:       { bsonType: "string", description: "Name – required" },
                    location:              { bsonType: "string", description: "Location – required" },
                    rating:                { bsonType: ["double","int","null"] },
                    average_price:         { bsonType: ["double","int","null"] },
                    average_delivery_time: { bsonType: ["double","int","null"] },
                    south_indian_or_not:   { bsonType: ["int","double","null"] },
                    north_indian_or_not:   { bsonType: ["int","double","null"] },
                    fast_food_or_not:      { bsonType: ["int","double","null"] },
                    street_food:           { bsonType: ["int","double","null"] },
                    biryani_or_not:        { bsonType: ["int","double","null"] },
                    bakery_or_not:         { bsonType: ["int","double","null"] }
                }
            }
        },
        validationAction: "warn"
    });
    print("[done] indian_restaurants collection created");
} else {
    print("[skip] indian_restaurants already exists");
}

// ── hashed indexes (required before sharding) ─────────────────────────────────
db.dubai_restaurants.createIndex( { subCategory: "hashed" } );
db.usa_fastfood.createIndex(       { name:        "hashed" } );
db.indian_restaurants.createIndex( { location:    "hashed" } );

// ── single-field indexes ───────────────────────────────────────────────────────
db.dubai_restaurants.createIndex( { polarity: 1 } );
db.dubai_restaurants.createIndex( { location: 1 } );
db.dubai_restaurants.createIndex( { category: 1 } );
db.usa_fastfood.createIndex(       { province: 1 } );
db.usa_fastfood.createIndex(       { city: 1 } );
db.usa_fastfood.createIndex(       { name: 1 } );
db.indian_restaurants.createIndex( { rating: 1 } );
db.indian_restaurants.createIndex( { average_price: 1 } );

// ── compound indexes (for analytical queries) ──────────────────────────────────
db.dubai_restaurants.createIndex( { category: 1, polarity: -1 } );
db.dubai_restaurants.createIndex( { location: 1, subCategory: 1 } );
db.usa_fastfood.createIndex(       { province: 1, city: 1 } );
db.usa_fastfood.createIndex(       { name: 1, province: 1 } );
db.indian_restaurants.createIndex( { location: 1, rating: -1 } );
db.indian_restaurants.createIndex( { rating: -1, average_price: 1 } );

// ── text indexes (full-text search) ───────────────────────────────────────────
db.dubai_restaurants.createIndex( { name: "text", category: "text", subCategory: "text" } );
db.usa_fastfood.createIndex(       { name: "text", city: "text" } );
db.indian_restaurants.createIndex( { restaurant_name: "text", location: "text" } );

// ── geospatial index (dubai has lat/lng coordinates) ──────────────────────────
db.dubai_restaurants.createIndex( { lat: 1, lng: 1 } );

// ── shard the collections ─────────────────────────────────────────────────────
// subCategory – distributes Dubai restaurants by restaurant type
sh.shardCollection("restaurants.dubai_restaurants", { subCategory: "hashed" });
// name – distributes US fast-food by chain name (McDonald's, Wendy's …)
sh.shardCollection("restaurants.usa_fastfood",      { name: "hashed" });
// location – distributes Indian restaurants by city
sh.shardCollection("restaurants.indian_restaurants", { location: "hashed" });

print("[done] All collections sharded");

// Lower chunk size to 32 MB so data spreads across shards faster
var cfgDb = db.getSiblingDB("config");
cfgDb.settings.updateOne(
    { _id: "chunksize" },
    { $set: { value: 32 } },
    { upsert: true }
);
print("[done] Chunk size set to 32 MB");

EOJS


echo ""
echo "══════════════════════════════════════════"
echo " STEP 8 – Import CSV data"
echo "══════════════════════════════════════════"
bash /scripts/import-data.sh

echo ""
echo "╔══════════════════════════════════════════╗"
echo "║   Cluster setup complete!               ║"
echo "║                                          ║"
echo "║   mongosh:      localhost:27017          ║"
echo "║   Compass Web:  http://localhost:8080    ║"
echo "╚══════════════════════════════════════════╝"
