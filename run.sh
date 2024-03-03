#!/bin/bash

# Example to add timestamps and create a logfile:
# time ./run.sh 2>&1 | ts -s "[%H:%M:%S]" | tee "$(date +"%Y%m%d").$$.log"


DATABASE_NAME=nominatim

psqlcmd() {
     psql $1 $DATABASE_NAME 2>&1 | grep -v skipping
}

echo "======================================================================="
echo "== Create functions"
echo "======================================================================="
cat sql/cleanup.sql | psqlcmd
cat sql/functions.sql | psqlcmd




echo "======================================================================="
echo "== Create output table"
echo "======================================================================="
cat sql/create_raster.sql | psqlcmd




echo "======================================================================="
echo "== Select which tiles to process"
echo "======================================================================="

# All countries
# echo "
# UPDATE sip_tiles SET process=true
# WHERE id IN (
#     SELECT rt.id
#     FROM sip_tiles rt, placex
#     WHERE ST_Intersects(rt.rast, placex.geometry)
#     AND osm_type='R' AND rank_address = 4
# );" | psqlcmd

# UK and Ireland
echo "
UPDATE sip_tiles SET process=true
WHERE id IN (
    SELECT rt.id
    FROM sip_tiles rt, placex
    WHERE ST_Intersects(rt.rast, placex.geometry)
    AND osm_type='R' AND osm_id IN (62149, 62273)
);" | psqlcmd


echo "======================================================================="
echo "== Process tiles"
echo "======================================================================="

IDS=$(echo 'SELECT id FROM sip_tiles WHERE process = true ORDER BY id;' | psqlcmd "-A -t")

COUNTER=0
TOTAL=$(echo $IDS | wc -w)
for TILE_ID in $IDS; do
    COUNTER=$((COUNTER + 1))

    echo "Processing tile $TILE_ID ($COUNTER of $TOTAL) ..."

    NUM_LAYERS=$(echo "SELECT sip_create_layers($TILE_ID);" | psqlcmd "-A -t")
    echo "$NUM_LAYERS unique importances"

    # echo -n "Places found:"
    # echo "SELECT SUM(num_places) FROM sip_temp_raster;" | psqlcmd "-A -t"
    # echo -n "Layers:"
    # echo "SELECT count(*) FROM sip_temp_raster;" | psqlcmd "-A -t"

    if [[ "$NUM_LAYERS" -gt 0 ]]; then
        echo "SELECT sip_merge_layers($TILE_ID)" | psqlcmd "-A -t"
    fi
done




echo "======================================================================="
echo "== Merge tiles into output table"
echo "======================================================================="

echo "
UPDATE secondary_importance
SET rast=(SELECT ST_UNION(rast) FROM sip_tiles WHERE places > 0);
" | psqlcmd



#  band_index | width | height |  pixels
# ------------+-------+--------+-----------
#           1 | 16385 |  14800 | 242498000





echo "======================================================================="
echo "== Dump TIFF file"
echo "======================================================================="

# With error "ERROR:  rt_raster_to_gdal: Could not load the output GDAL driver"
# Postgres will run out of memory when it fetches whole world data from ST_AsTiff,
# but setting a compression works.
#
# COPY ... TO STDOUT includes some Postgres metadata and can't be used directly as
# image regardless if you set -b (binary). Encoding it to hex and back is a good
# workaround (https://stackoverflow.com/a/6731452)

echo "COPY (SELECT ENCODE(ST_AsTIFF(rast, 'LZW'), 'hex') FROM secondary_importance) TO STDOUT" \
| psqlcmd > secondary_importance.hex

xxd -p -r secondary_importance.hex > secondary_importance.tiff
rm secondary_importance.hex




echo "======================================================================="
echo "== Dump SQL file"
echo "======================================================================="

# Remove all settings, we just want the 'CREATE TABLE' and 'LOAD DATA' lines.
pg_dump -d $DATABASE_NAME --no-owner --table secondary_importance | \
        grep -v '^SET '    | \
        grep -v '^SELECT ' | \
        grep -v '\-\-'     | \
        grep -v '^$'       | \
        sed 's/public\.//' | \
        gzip -9 > secondary_importance.sql.gz

ls -lah secondary_importance.*
#  22M secondary_importance.tiff
# 8.2M secondary_importance.sql.gz



