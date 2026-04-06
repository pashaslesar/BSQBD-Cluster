MONGOS_HOST="mongos"
MONGOS_PORT="27017"
DB="restaurants"
DATA_DIR="/csv-data"
TMP_DIR="/tmp/csv-clean"

ADMIN_USER="${MONGO_ADMIN_USER:-admin}"
ADMIN_PASS="${MONGO_ADMIN_PASS:-RestCluster2024!}"

mkdir -p "$TMP_DIR"

count_docs() {
    mongosh --host "$MONGOS_HOST" --port "$MONGOS_PORT" --quiet \
        -u "$ADMIN_USER" -p "$ADMIN_PASS" --authenticationDatabase admin \
        --eval "db.getSiblingDB('$DB').$1.estimatedDocumentCount()" 2>/dev/null || echo "0"
}

run_import() {
    local collection=$1 file=$2
    echo "[import] $collection ← $file"
    mongoimport \
        --host "$MONGOS_HOST" \
        --port "$MONGOS_PORT" \
        --db  "$DB" \
        --collection "$collection" \
        --authenticationDatabase admin \
        --username "$ADMIN_USER" \
        --password "$ADMIN_PASS" \
        --type csv \
        --headerline \
        --ignoreBlanks \
        --numInsertionWorkers 4 \
        --file "$file"
    echo "[done]  $collection imported"
}

echo ""
echo "── dubai_restaurants ──"
CNT=$(count_docs dubai_restaurants)
if [ "$CNT" -gt 100 ]; then
    echo "[skip] already has $CNT documents"
else
    SRC="$DATA_DIR/dubai-restaurants.csv"
    run_import dubai_restaurants "$SRC"
fi

echo ""
echo "── usa_fastfood ──"
CNT=$(count_docs usa_fastfood)
if [ "$CNT" -gt 100 ]; then
    echo "[skip] already has $CNT documents"
else
    SRC="$DATA_DIR/fastfood-usa-restaurants.csv"
    run_import usa_fastfood "$SRC"
fi

echo ""
echo "── indian_restaurants ──"
CNT=$(count_docs indian_restaurants)
if [ "$CNT" -gt 100 ]; then
    echo "[skip] already has $CNT documents"
else
    SRC_RAW="$DATA_DIR/indian-restaurants.csv"
    SRC_CLEAN="$TMP_DIR/indian-restaurants.csv"
    sed 's/\xef\xbb\xbf//' "$SRC_RAW" \
        | sed '1s/average _delivery_time/average_delivery_time/' \
        > "$SRC_CLEAN"
    run_import indian_restaurants "$SRC_CLEAN"
fi

echo ""
echo "[done] All imports finished"

echo ""
echo "── Record counts per collection ──"
mongosh --host "$MONGOS_HOST" --port "$MONGOS_PORT" --quiet \
    -u "$ADMIN_USER" -p "$ADMIN_PASS" --authenticationDatabase admin \
    --eval "
var db = db.getSiblingDB('restaurants');
['dubai_restaurants','usa_fastfood','indian_restaurants'].forEach(c => {
    print(c + ': ' + db[c].estimatedDocumentCount() + ' docs');
});
"

echo ""
echo "── Chunk distribution across shards ──"
mongosh --host "$MONGOS_HOST" --port "$MONGOS_PORT" --quiet \
    -u "$ADMIN_USER" -p "$ADMIN_PASS" --authenticationDatabase admin \
    --eval "
var cfgDb = db.getSiblingDB('config');
var pipeline = [
  { \$group: { _id: '\$shard', chunks: { \$sum: 1 } } },
  { \$sort:  { _id: 1 } }
];
cfgDb.chunks.aggregate(pipeline).forEach(d => print(d._id + ': ' + d.chunks + ' chunks'));
"
