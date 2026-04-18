set -e

ADMIN_USER="${MONGO_ADMIN_USER:-admin}"
ADMIN_PASS="${MONGO_ADMIN_PASS:-admin123}"

MAUTH="-u $ADMIN_USER -p $ADMIN_PASS --authenticationDatabase admin"


wait_mongo() {
    local host=$1 port=$2
    echo "[wait] $host:$port ..."
    until mongosh --host "$host" --port "$port" --quiet \
          --eval "db.adminCommand({ping:1})" >/dev/null 2>&1; do
        sleep 3
    done
    echo "[ok]   $host:$port is reachable"
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
echo " STEP 1 – Wait for replica set primaries"
echo "══════════════════════════════════════════"
wait_primary configsvr1 27019
wait_primary shard1-1   27018
wait_primary shard2-1   27018
wait_primary shard3-1   27018


echo ""
echo "══════════════════════════════════════════"
echo " STEP 2 – Wait for mongos"
echo "══════════════════════════════════════════"
wait_mongo mongos 27017
echo "[ok]   mongos is up"


echo ""
echo "══════════════════════════════════════════"
echo " STEP 3 – Create admin user"
echo "══════════════════════════════════════════"


if mongosh --host localhost --port 27017 --quiet $MAUTH \
    --eval "db.adminCommand({ping:1})" >/dev/null 2>&1; then
    echo "[skip] Admin user '$ADMIN_USER' already exists"
else
    echo "[create] Creating admin user via localhost exception ..."
    mongosh --host localhost --port 27017 --quiet --eval "
        db.getSiblingDB('admin').createUser({
            user: '$ADMIN_USER',
            pwd:  '$ADMIN_PASS',
            roles: [{ role: 'root', db: 'admin' }]
        });
        print('[done] Admin user created: $ADMIN_USER');
    "
fi


echo ""
echo "══════════════════════════════════════════"
echo " STEP 4 – Add shards to mongos"
echo "══════════════════════════════════════════"

SHARD_COUNT=$(mongosh --host mongos --port 27017 --quiet $MAUTH \
    --eval "db.adminCommand({listShards:1}).shards.length" 2>/dev/null || echo "0")

if [ "$SHARD_COUNT" -ge 3 ] 2>/dev/null; then
    echo "[skip] Shards already registered ($SHARD_COUNT)"
else
    echo "[add]  Adding rs1, rs2, rs3 ..."
    mongosh --host mongos --port 27017 --quiet $MAUTH --eval '
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

mongosh --host mongos --port 27017 --quiet $MAUTH << 'EOJS'

// ── enable sharding on the database ──────────────────────────────────────────
sh.enableSharding("restaurants");

var db = db.getSiblingDB("restaurants");
var cols = db.getCollectionNames();

// ── dubai_restaurants ─────────────────────────────────────────────────────────
// required: only fields that are ALWAYS filled in the CSV (7342 rows analysed)
if (!cols.includes("dubai_restaurants")) {
    db.createCollection("dubai_restaurants", {
        validator: {
            $jsonSchema: {
                bsonType: "object",
                required: ["name", "category", "location", "lat", "lng", "originalId", "polarity"],
                properties: {
                    name:        { bsonType: "string" },
                    category:    { bsonType: "string" },
                    location:    { bsonType: "string" },
                    originalId:  { bsonType: "string" },
                    lat:         { bsonType: ["double", "int"] },
                    lng:         { bsonType: ["double", "int"] },
                    polarity:    { bsonType: ["double", "int"] },
                    address:     { bsonType: ["string", "null"] },
                    id:          { bsonType: ["double", "int", "null"] },
                    subCategory: { bsonType: ["string", "null"] },
                    details:     { bsonType: ["string", "null"] },
                    reviews:     { bsonType: ["string", "null"] }
                }
            }
        },
        validationAction: "warn"
    });
    print("[done] dubai_restaurants created (validator: warn)");
} else {
    print("[skip] dubai_restaurants already exists");
}

// ── usa_fastfood ──────────────────────────────────────────────────────────────
// required: all fields except websites (465 empty rows)
if (!cols.includes("usa_fastfood")) {
    db.createCollection("usa_fastfood", {
        validator: {
            $jsonSchema: {
                bsonType: "object",
                required: ["name", "address", "city", "country", "keys", "latitude", "longitude", "postalCode", "province"],
                properties: {
                    name:       { bsonType: "string" },
                    address:    { bsonType: "string" },
                    city:       { bsonType: "string" },
                    country:    { bsonType: "string" },
                    keys:       { bsonType: "string" },
                    postalCode: { bsonType: "string" },
                    province:   { bsonType: "string" },
                    latitude:   { bsonType: ["double", "int"] },
                    longitude:  { bsonType: ["double", "int"] },
                    websites:   { bsonType: ["string", "null"] }
                }
            }
        },
        validationAction: "warn"
    });
    print("[done] usa_fastfood created (validator: warn)");
} else {
    print("[skip] usa_fastfood already exists");
}

// ── indian_restaurants ────────────────────────────────────────────────────────
// required: all 11 fields — every field is always filled (27656 rows analysed)
if (!cols.includes("indian_restaurants")) {
    db.createCollection("indian_restaurants", {
        validator: {
            $jsonSchema: {
                bsonType: "object",
                required: [
                    "restaurant_name", "location", "rating", "average_price",
                    "average_delivery_time", "south_indian_or_not", "north_indian_or_not",
                    "fast_food_or_not", "street_food", "biryani_or_not", "bakery_or_not"
                ],
                properties: {
                    restaurant_name:       { bsonType: "string" },
                    location:              { bsonType: "string" },
                    rating:                { bsonType: ["double", "int"] },
                    average_price:         { bsonType: ["double", "int"] },
                    average_delivery_time: { bsonType: ["double", "int"] },
                    south_indian_or_not:   { bsonType: ["double", "int"] },
                    north_indian_or_not:   { bsonType: ["double", "int"] },
                    fast_food_or_not:      { bsonType: ["double", "int"] },
                    street_food:           { bsonType: ["double", "int"] },
                    biryani_or_not:        { bsonType: ["double", "int"] },
                    bakery_or_not:         { bsonType: ["double", "int"] }
                }
            }
        },
        validationAction: "warn"
    });
    print("[done] indian_restaurants created (validator: warn)");
} else {
    print("[skip] indian_restaurants already exists");
}

// ── hashed indexes (required before sharding) ─────────────────────────────────
db.dubai_restaurants.createIndex( { name: "hashed" } );
db.usa_fastfood.createIndex(       { name: "hashed" } );
db.indian_restaurants.createIndex( { location: "hashed" } );

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
sh.shardCollection("restaurants.dubai_restaurants", { name: "hashed" });
sh.shardCollection("restaurants.usa_fastfood",      { name: "hashed" });
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
export MONGO_ADMIN_USER MONGO_ADMIN_PASS
bash /scripts/import-data.sh

echo ""
echo "══════════════════════════════════════════"
echo " STEP 9 – Apply JSON Schema validators"
echo "══════════════════════════════════════════"

mongosh --host mongos --port 27017 --quiet $MAUTH << 'EOJS'
var db = db.getSiblingDB("restaurants");

// ── dubai_restaurants ─────────────────────────────────────────────────────────
db.runCommand({
    collMod: "dubai_restaurants",
    validator: {
        $jsonSchema: {
            bsonType: "object",
            required: ["name", "category", "location", "lat", "lng", "originalId", "polarity"],
            properties: {
                name:        { bsonType: "string" },
                category:    { bsonType: "string" },
                location:    { bsonType: "string" },
                originalId:  { bsonType: "string" },
                lat:         { bsonType: ["double", "int"] },
                lng:         { bsonType: ["double", "int"] },
                polarity:    { bsonType: ["double", "int"] },
                address:     { bsonType: ["string", "null"] },
                id:          { bsonType: ["double", "int", "null"] },
                subCategory: { bsonType: ["string", "null"] },
                details:     { bsonType: ["string", "null"] },
                reviews:     { bsonType: ["string", "null"] }
            }
        }
    },
    validationAction: "error"
});
print("[done] dubai_restaurants validator → error");

// ── usa_fastfood ──────────────────────────────────────────────────────────────
db.runCommand({
    collMod: "usa_fastfood",
    validator: {
        $jsonSchema: {
            bsonType: "object",
            required: ["name", "address", "city", "country", "keys", "latitude", "longitude", "postalCode", "province"],
            properties: {
                name:       { bsonType: "string" },
                address:    { bsonType: "string" },
                city:       { bsonType: "string" },
                country:    { bsonType: "string" },
                keys:       { bsonType: "string" },
                postalCode: { bsonType: "string" },
                province:   { bsonType: "string" },
                latitude:   { bsonType: ["double", "int"] },
                longitude:  { bsonType: ["double", "int"] },
                websites:   { bsonType: ["string", "null"] }
            }
        }
    },
    validationAction: "error"
});
print("[done] usa_fastfood validator → error");

// ── indian_restaurants ────────────────────────────────────────────────────────
db.runCommand({
    collMod: "indian_restaurants",
    validator: {
        $jsonSchema: {
            bsonType: "object",
            required: [
                "restaurant_name", "location", "rating", "average_price",
                "average_delivery_time", "south_indian_or_not", "north_indian_or_not",
                "fast_food_or_not", "street_food", "biryani_or_not", "bakery_or_not"
            ],
            properties: {
                restaurant_name:       { bsonType: "string" },
                location:              { bsonType: "string" },
                rating:                { bsonType: ["double", "int"] },
                average_price:         { bsonType: ["double", "int"] },
                average_delivery_time: { bsonType: ["double", "int"] },
                south_indian_or_not:   { bsonType: ["double", "int"] },
                north_indian_or_not:   { bsonType: ["double", "int"] },
                fast_food_or_not:      { bsonType: ["double", "int"] },
                street_food:           { bsonType: ["double", "int"] },
                biryani_or_not:        { bsonType: ["double", "int"] },
                bakery_or_not:         { bsonType: ["double", "int"] }
            }
        }
    },
    validationAction: "error"
});
print("[done] indian_restaurants validator → error");
EOJS

echo ""
echo "╔══════════════════════════════════════════╗"
echo "║   Information                            ║"
echo "║                                          ║"
echo "║   mongosh (admin):                       ║"
echo "║     mongosh localhost:27017              ║"
echo "║     -u admin -p admin123                 ║"
echo "║     --authenticationDatabase admin       ║"
echo "║                                          ║"
echo "║   Compass Web:  http://localhost:8080    ║"
echo "╚══════════════════════════════════════════╝"
echo ""
echo ""
echo "Cluster setup complete"
