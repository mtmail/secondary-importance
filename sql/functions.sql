-----------------------------------------------------------------------------
--- Fill sip_temp_raster table with one layer (raster) for each unique
--- importance
-----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION sip_create_layers(tile_id INTEGER)
RETURNS integer AS $$
DECLARE
   importances_count INTEGER;
BEGIN
    DROP TABLE IF EXISTS sip_temp_raster;
    CREATE table sip_temp_raster as
      SELECT
        ROUND(COALESCE(importance, round(0.40001 - (rank_search::numeric / 75), 3)) * ((rank_address + 2) / 15) * 65536) as sec_importance,
        COUNT(placex.*) as num_places,
        ST_AsRaster(
          ST_Intersection(
            ST_Union(placex.geometry),
            ST_Envelope(sip_tiles.rast)
          ),
          sip_tiles.rast, -- existing raster from which to copy the specs
          '16BUI', -- pixeltype
          ROUND(COALESCE(importance, round(0.40001 - (rank_search::numeric / 75), 3)) * ((rank_address + 2) / 15) * 65536)
        ) as rast_this_importance
      FROM placex, sip_tiles
      WHERE ST_Intersects(sip_tiles.rast, placex.geometry)
        AND sip_tiles.id = tile_id
        AND placex.rank_search < 25
        AND ST_GeometryType(placex.geometry) IN ('ST_Polygon', 'ST_MultiPolygon')
        AND ROUND(COALESCE(importance, round(0.40001 - (rank_search::numeric / 75), 3)) * ((rank_address + 2) / 15) * 65536) > 0
      GROUP BY sip_tiles.rast, sec_importance
      ORDER BY sec_importance;

    SELECT COUNT(*) INTO importances_count FROM sip_temp_raster;
    RETURN importances_count;
END;
$$ LANGUAGE plpgsql;

-----------------------------------------------------------------------------
--- Read sip_temp_raster table and merge each raster, selecting the highest
--- pixel value
---

CREATE OR REPLACE FUNCTION sip_merge_layers(tile_id INTEGER)
RETURNS integer AS $$
DECLARE
    rec               record;
    merged_rast       raster;
    importances_count INTEGER;
    places_count      INTEGER;
BEGIN
    -- Initialize merged_rast
    -- ST_MakeEmptyRaster copies all settings from sip_tiles.rast
    SELECT ST_MakeEmptyRaster(rast) INTO merged_rast FROM sip_tiles WHERE id = tile_id;

    SELECT COUNT(*) INTO importances_count FROM sip_temp_raster;
    SELECT SUM(num_places) INTO places_count FROM sip_temp_raster;

    FOR rec IN SELECT * FROM sip_temp_raster ORDER BY sec_importance
    LOOP
        -- https://postgis.net/docs/RT_ST_MapAlgebra_expr.html
        merged_rast := ST_MapAlgebra(
            rec.rast_this_importance, 1,  -- raster 1 and band number
            merged_rast,              1,  -- raster 2 and band number
            'GREATEST([rast1],[rast2])',  -- return largest pixel value
            NULL,                         -- pixeltype, NULL=take from first raster
            'UNION'::text,                -- default INTERSECTION doesn't work
            '[rast2]'::text,              -- set this if rast1 value not set
            '[rast1]'::text               -- set this if rast2 value not set
       );
    END LOOP;

    UPDATE sip_tiles
    SET places=places_count, rast=merged_rast
    WHERE id = tile_id;

    RAISE NOTICE 'Merged % importances with % places', importances_count, places_count;

    RETURN importances_count;
END;
$$ LANGUAGE plpgsql;








-- WITH tile AS (
--     select rast from sip_tiles where id = 26904
-- )
-- SELECT
--     i as band_index,
--     ST_Width(rast) * ST_Height(rast) as total_cell_count
-- FROM
--     tile,
--     generate_series(1, ST_NumBands(tile.rast)) as i;
--
-- --  band_index | total_cell_count
-- -- ------------+------------------
-- --           1 |             4500



-- SELECT ST_ValueCount(rast) as pvc
-- FROM sip_tiles where id = 26904;
--
-- --    pvc
-- -- -----------
-- --  (1,1451)
-- --  (2,1)
-- --  (24488,9)



-- SELECT SUM(count) as filled_cells
-- FROM (
--     SELECT (pvc).*
--     FROM (
--         SELECT ST_ValueCount(rast) as pvc
--         FROM sip_tiles where id = 26904
--     ) as foo
-- ) as bar
-- WHERE value != 0;
--
-- --  filled_cells
-- -- --------------
-- --          3760
-- -- ... can also be ...
-- -- NOTICE:  All pixels of band have the NODATA value
