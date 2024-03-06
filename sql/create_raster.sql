-----------------------------------------------------------------------------
--- Prerequisites
-----------------------------------------------------------------------------

CREATE EXTENSION IF NOT EXISTS postgis_raster;

ALTER SYSTEM SET postgis.gdal_enabled_drivers TO 'GTiff';
SELECT pg_reload_conf();

SHOW postgis.gdal_enabled_drivers;
--  postgis.gdal_enabled_drivers
-- ------------------------------
--  GTiff

-- If that doesn't work then set it in the postgres.conf
-- postgis.gdal_enabled_drivers = 'GTiff PNG'
-- and restart postgresql

-----------------------------------------------------------------------------
--- Create planet raster
-----------------------------------------------------------------------------

CREATE TABLE secondary_importance(rast raster);

-- https://postgis.net/docs/RT_ST_MakeEmptyRaster.html
-- 2^14 = 16.384
-- 16.384^2 = 268.435.456 pixels
INSERT INTO secondary_importance (rast)
VALUES (ST_MakeEmptyRaster(
    POW(2, 14)::integer, -- width in pixels
    POW(2, 14)::integer, -- height in pixels
    -180,                -- upperleftx (maximum west longitude)
    90,                  -- upperlefty (maximum north latitude)
    360/POW(2, 14),      -- scalex (pixel size in degrees)
    -180/POW(2, 14),     -- scaley (pixel size in degrees)
    0,                   -- skewx (none)
    0,                   -- skewy (none)
    4326                 -- SRID of WGS84
));


-- https://postgis.net/docs/RT_ST_AddBand.html
-- 16BUI = 2 bytes per pixel
UPDATE secondary_importance
SET rast = ST_AddBand(rast, '16BUI'::text);

-- Verify
SELECT
  i as band_index,
  ST_Width(rast) as width,
  ST_Height(rast) as height,
  ST_Width(rast) * ST_Height(rast) as pixels
FROM
  secondary_importance,
  generate_series(1, ST_NumBands(rast)) as i;

--  band_index | width | height |  pixels
-- ------------+-------+--------+-----------
--           1 | 16384 |  16384 | 268435456



-----------------------------------------------------------------------------
--- Create raster tiles for efficient processing
-----------------------------------------------------------------------------

DROP TABLE IF EXISTS sip_tiles;
CREATE TABLE sip_tiles (
    id        SERIAL PRIMARY KEY,
    process   boolean DEFAULT false,
    rast      raster,
    places    integer                  -- number of places in raster, can be 0
);

-- https://postgis.net/docs/RT_ST_Tile.html
INSERT INTO sip_tiles (rast)
SELECT ST_Tile(rast, 100, 100)
FROM secondary_importance;

-- Verify
SELECT count(*) FROM sip_tiles;
--  count
-- -------
--   6724


-- SELECT id, ST_MetaData(rast) FROM sip_tiles LIMIT 5;
--  id |                            st_metadata
-- ----+--------------------------------------------------------------------
--   1 | (-180,90,200,200,0.02197265625,0.010986328125,0,0,4326,1)
--   2 | (-175.60546875,90,200,200,0.02197265625,0.010986328125,0,0,4326,1)
--   3 | (-171.2109375,90,200,200,0.02197265625,0.010986328125,0,0,4326,1)
--   4 | (-166.81640625,90,200,200,0.02197265625,0.010986328125,0,0,4326,1)
--   5 | (-162.421875,90,200,200,0.02197265625,0.010986328125,0,0,4326,1)

-- SELECT id, ST_MetaData(rast) FROM sip_tiles order by id desc LIMIT 5;
--   id  |                                 st_metadata
-- ------+------------------------------------------------------------------------------
 -- 6724 | (175.95703125,-87.978515625,184,184,0.02197265625,-0.010986328125,0,0,4326,1)
 -- 6723 | (171.5625,-87.978515625,200,184,0.02197265625,-0.010986328125,0,0,4326,1)
 -- 6722 | (167.16796875,-87.978515625,200,184,0.02197265625,-0.010986328125,0,0,4326,1)
 -- 6721 | (162.7734375,-87.978515625,200,184,0.02197265625,-0.010986328125,0,0,4326,1)
 -- 6720 | (158.37890625,-87.978515625,200,184,0.02197265625,-0.010986328125,0,0,4326,1)

-- Fields are:
-- upperleftx: The X coordinate of the upper left corner of the raster.
-- upperlefty: The Y coordinate of the upper left corner of the raster.
-- The following are the same for each tile:
--   width: The width of the raster in pixels.
--   height: The height of the raster in pixels.
--   scalex: The pixel width in geographical units.
--   scaley: The pixel height in geographical units.
--   skewx: The skew of the raster's X axis. For north-up images, this is typically 0.
--   skewy: The skew of the raster's Y axis. For north-up images, this is typically 0.
--   SRID: The spatial reference identifier for the raster.
--   numbands: The number of bands that the raster contains.







