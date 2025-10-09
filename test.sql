-- transport_indexes_and_tables.sql
-- Assumes PostGIS is installed. Stores canonical WGS84 (4326) + projected copies (22992).
-- Uses GiST for lines, SP-GiST for points, and GIN for JSONB / text search.
-- 0) Extensions
CREATE EXTENSION IF NOT EXISTS postgis;
CREATE EXTENSION IF NOT EXISTS pg_trgm;
-- for trigram / text search improvements
CREATE EXTENSION IF NOT EXISTS btree_gin;
CREATE EXTENSION IF NOT EXISTS pg_routing;
CREATE TYPE route_kind_t AS ENUM ('continuous', 'fixed', 'variant', 'on_demand');
-- optional helper for some composite indexes (kept handy)
-- 1) route table (metadata)
CREATE TABLE IF NOT EXISTS "route" (
    route_id BIGSERIAL PRIMARY KEY,
    code TEXT,
    -- code for the transport route itself ex: Cairo-Alex-1, Alex-Tram-line-1
    name TEXT NOT NULL,
    -- name for the transport ex: victoria - sidi gaber microbus
    kind route_kind_t DEFAULT 'continuous' NOT NULL,
    mode TEXT,
    -- ex : microbus, bus, tram
    cost INTEGER NOT NULL,
    -- in piasters, 100 piasters = 1 pound
    two_way BOOLEAN NOT NULL DEFAULT false,
    operator TEXT,
    -- ex : independant, goverment, company
    attrs JSONB DEFAULT '{}'::jsonb,
    created_at TIMESTAMPTZ DEFAULT now(),
    updated_at TIMESTAMPTZ DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_route_kind ON "route"(kind);
CREATE INDEX IF NOT EXISTS idx_route_attrs_gin ON "route" USING GIN (attrs);
-- trigger to keep updated_at fresh
CREATE OR REPLACE FUNCTION trg_route_set_updated_at() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN NEW.updated_at := now();
RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS route_set_updated_at ON "route";
CREATE TRIGGER route_set_updated_at BEFORE
UPDATE ON "route" FOR EACH ROW EXECUTE FUNCTION trg_route_set_updated_at();
-- 2) route_geometry table (WGS84 canonical + projected copy)
CREATE TABLE IF NOT EXISTS route_geometry (
    route_geom_id BIGSERIAL PRIMARY KEY,
    route_id BIGINT NOT NULL REFERENCES "route"(route_id) ON DELETE CASCADE,
    geom_4326 geometry(LineString, 4326) NOT NULL,
    -- real geographical WGS84 storage
    geom_22992 geometry(LineString, 22992),
    -- projected copy in 22992(egypt red belt) in (meters) for fast queries
    variant TEXT,
    -- main route and alterations, shortcuts, and deviations that may occur
    is_primary BOOLEAN DEFAULT TRUE,
    -- marks the primary route that is taken
    attrs JSONB DEFAULT '{}'::jsonb,
    created_at TIMESTAMPTZ DEFAULT now(),
    updated_at TIMESTAMPTZ DEFAULT now()
);
-- indexes for route_geometry
CREATE INDEX IF NOT EXISTS idx_route_geometry_geom_22992_gist ON route_geometry USING GIST (geom_22992);
CREATE INDEX IF NOT EXISTS idx_route_geometry_routeid ON route_geometry (route_id);
CREATE INDEX IF NOT EXISTS idx_route_geometry_attrs_gin ON route_geometry USING GIN (attrs);
-- optional unique constraint: only one primary geometry per route
CREATE UNIQUE INDEX IF NOT EXISTS uq_route_geom_route_primary ON route_geometry (route_id)
WHERE (is_primary IS TRUE);
-- trigger: populate geom_22992 from geom_4326 on insert/update
CREATE OR REPLACE FUNCTION trg_route_geometry_sync_proj() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN IF TG_OP = 'INSERT'
    OR (
        TG_OP = 'UPDATE'
        AND NEW.geom_4326 IS DISTINCT
        FROM OLD.geom_4326
    ) THEN IF NEW.geom_4326 IS NOT NULL THEN NEW.geom_4326 := ST_SetSRID(NEW.geom_4326, 4326);
NEW.geom_22992 := ST_Transform(NEW.geom_4326, 22992);
ELSE NEW.geom_22992 := NULL;
END IF;
END IF;
RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS route_geometry_sync_proj ON route_geometry;
CREATE TRIGGER route_geometry_sync_proj BEFORE
INSERT
    OR
UPDATE ON route_geometry FOR EACH ROW EXECUTE FUNCTION trg_route_geometry_sync_proj();
-- trigger to keep updated_at fresh for route_geometry
CREATE OR REPLACE FUNCTION trg_route_geometry_set_updated_at() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN NEW.updated_at := now();
RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS route_geometry_set_updated_at ON route_geometry;
CREATE TRIGGER route_geometry_set_updated_at BEFORE
UPDATE ON route_geometry FOR EACH ROW EXECUTE FUNCTION trg_route_geometry_set_updated_at();
-- 3) stop table (WGS84 canonical + projected copy); The stop itself ex: san stefano station
CREATE TABLE IF NOT EXISTS "stop" (
    stop_id BIGSERIAL PRIMARY KEY,
    code TEXT,
    -- code for the stop ex: alx-raml,giza-faisal
    name TEXT,
    -- full name for the stop ex: alexandria raml tram station
    geom_4326 geometry(Point, 4326) NOT NULL,
    -- geographical real location
    geom_22992 geometry(Point, 22992),
    -- egypt red belt (22992) projection
    attrs JSONB DEFAULT '{}'::jsonb,
    created_at TIMESTAMPTZ DEFAULT now(),
    updated_at TIMESTAMPTZ DEFAULT now()
);
-- SP-GiST on points 
CREATE INDEX IF NOT EXISTS idx_stop_geom_22992_spgist ON "stop" USING SPGIST (geom_22992);
-- GIN for JSONB attrs
CREATE INDEX IF NOT EXISTS idx_stop_attrs_gin ON "stop" USING GIN (attrs);
-- text search index on name (useful for fuzzy search / lookups)
CREATE INDEX IF NOT EXISTS idx_stop_name_tsv ON "stop" USING GIN (to_tsvector('simple', COALESCE(name, '')));
-- optionally a plain btree index on name for exact matches
CREATE INDEX IF NOT EXISTS idx_stop_name ON "stop" (name);
-- trigger for syncing projected stop geometry
CREATE OR REPLACE FUNCTION trg_stop_sync_proj() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN IF TG_OP = 'INSERT'
    OR (
        TG_OP = 'UPDATE'
        AND NEW.geom_4326 IS DISTINCT
        FROM OLD.geom_4326
    ) THEN IF NEW.geom_4326 IS NOT NULL THEN NEW.geom_4326 := ST_SetSRID(NEW.geom_4326, 4326);
NEW.geom_22992 := ST_Transform(NEW.geom_4326, 22992);
ELSE NEW.geom_22992 := NULL;
END IF;
END IF;
RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS stop_sync_proj ON "stop";
CREATE TRIGGER stop_sync_proj BEFORE
INSERT
    OR
UPDATE ON "stop" FOR EACH ROW EXECUTE FUNCTION trg_stop_sync_proj();
-- trigger to keep updated_at fresh for stop
CREATE OR REPLACE FUNCTION trg_stop_set_updated_at() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN NEW.updated_at := now();
RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS stop_set_updated_at ON "stop";
CREATE TRIGGER stop_set_updated_at BEFORE
UPDATE ON "stop" FOR EACH ROW EXECUTE FUNCTION trg_stop_set_updated_at();
-- 4) route_stop, actual stop in route ex : san stefano station tram 1
CREATE TABLE IF NOT EXISTS route_stop (
    route_stop_id BIGSERIAL PRIMARY KEY,
    route_id BIGINT NOT NULL REFERENCES "route"(route_id) ON DELETE CASCADE,
    stop_id BIGINT NOT NULL REFERENCES "stop"(stop_id) ON DELETE CASCADE,
    stop_sequence INTEGER NOT NULL,
    -- the numbering of the stop in the route, ex : san stefano: 1, ganaklis: 2
    arrival_time TIME,
    departure_time TIME,
    attrs JSONB DEFAULT '{}'::jsonb,
    created_at TIMESTAMPTZ DEFAULT now(),
    updated_at TIMESTAMPTZ DEFAULT now(),
    UNIQUE (route_id, stop_sequence),
    UNIQUE (route_id, stop_id)
);
CREATE INDEX IF NOT EXISTS idx_route_stop_routeid_seq ON route_stop (route_id, stop_sequence);
CREATE INDEX IF NOT EXISTS idx_route_stop_stopid ON route_stop (stop_id);
CREATE INDEX IF NOT EXISTS idx_route_stop_attrs_gin ON route_stop USING GIN (attrs);
-- trigger to keep updated_at fresh for route_stop
CREATE OR REPLACE FUNCTION trg_route_stop_set_updated_at() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN NEW.updated_at := now();
RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS route_stop_set_updated_at ON route_stop;
CREATE TRIGGER route_stop_set_updated_at BEFORE
UPDATE ON route_stop FOR EACH ROW EXECUTE FUNCTION trg_route_stop_set_updated_at();
-- 5) small helper functions / example queries (KNN + ST_DWithin patterns)
-- nearest stop (KNN) example using projected column (fast thanks to SP-GiST)
-- ORDER BY geom_22992 <-> <point> uses the SP-GiST index when available
-- Example usage (replace lon/lat):
-- SELECT s.stop_id, s.name,
--        ST_Distance(s.geom_22992, ST_Transform(ST_SetSRID(ST_MakePoint(lon, lat), 4326), 22992)) AS dist_m
-- FROM stop s
-- ORDER BY s.geom_22992 <-> ST_Transform(ST_SetSRID(ST_MakePoint(lon, lat), 4326), 22992)
-- LIMIT 5;
-- routes within 100m of a point (use bounding box + ST_DWithin; projected SRID in meters)
-- Example:
-- SELECT rg.*
-- FROM route_geometry rg
-- WHERE rg.geom_22992 && ST_Expand(ST_Transform(ST_SetSRID(ST_MakePoint(lon, lat), 4326), 22992), 100)
--   AND ST_DWithin(rg.geom_22992, ST_Transform(ST_SetSRID(ST_MakePoint(lon, lat),4326),22992), 100);
-- 6) ways and ways_vertices_pgr tables (for routing graph)
-- These tables store the road network graph for routing calculations
-- ways_vertices_pgr stores the vertices (intersections/nodes)
CREATE TABLE IF NOT EXISTS ways_vertices_pgr (
    id BIGSERIAL PRIMARY KEY,
    osm_id BIGINT UNIQUE,
    eout INTEGER,
    lon NUMERIC(11, 8),
    lat NUMERIC(11, 8),
    cnt INTEGER,
    chk INTEGER,
    ein INTEGER,
    the_geom geometry(Point, 4326),
    created_at TIMESTAMPTZ DEFAULT now(),
    updated_at TIMESTAMPTZ DEFAULT now()
);
-- ways stores the road segments (edges) connecting vertices
CREATE TABLE IF NOT EXISTS ways (
    gid BIGSERIAL PRIMARY KEY,
    osm_id BIGINT,
    tag_id INTEGER,
    length DOUBLE PRECISION,
    length_m DOUBLE PRECISION,
    name TEXT,
    source BIGINT NOT NULL REFERENCES ways_vertices_pgr(id),
    target BIGINT NOT NULL REFERENCES ways_vertices_pgr(id),
    source_osm BIGINT REFERENCES ways_vertices_pgr(osm_id),
    target_osm BIGINT REFERENCES ways_vertices_pgr(osm_id),
    cost DOUBLE PRECISION,
    reverse_cost DOUBLE PRECISION,
    cost_s DOUBLE PRECISION,
    reverse_cost_s DOUBLE PRECISION,
    rule TEXT,
    one_way INTEGER,
    oneway TEXT,
    x1 DOUBLE PRECISION,
    y1 DOUBLE PRECISION,
    x2 DOUBLE PRECISION,
    y2 DOUBLE PRECISION,
    maxspeed_forward DOUBLE PRECISION,
    maxspeed_backward DOUBLE PRECISION,
    priority DOUBLE PRECISION DEFAULT 1,
    the_geom geometry(LineString, 4326),
    attrs JSONB DEFAULT '{}'::jsonb,
    created_at TIMESTAMPTZ DEFAULT now(),
    updated_at TIMESTAMPTZ DEFAULT now()
);
-- indexes for ways_vertices_pgr
CREATE INDEX IF NOT EXISTS idx_ways_vertices_pgr_geom_gist ON ways_vertices_pgr USING GIST (the_geom);
CREATE INDEX IF NOT EXISTS idx_ways_vertices_pgr_osm_id ON ways_vertices_pgr (osm_id)
WHERE osm_id IS NOT NULL;
-- indexes for ways
CREATE INDEX IF NOT EXISTS idx_ways_geom_gist ON ways USING GIST (the_geom);
CREATE INDEX IF NOT EXISTS idx_ways_source ON ways (source);
CREATE INDEX IF NOT EXISTS idx_ways_target ON ways (target);
CREATE INDEX IF NOT EXISTS idx_ways_source_osm ON ways (source_osm)
WHERE source_osm IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_ways_target_osm ON ways (target_osm)
WHERE target_osm IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_ways_attrs_gin ON ways USING GIN (attrs);
CREATE INDEX IF NOT EXISTS idx_ways_name ON ways (name)
WHERE name IS NOT NULL;
-- triggers to keep updated_at fresh for ways_vertices_pgr
CREATE OR REPLACE FUNCTION trg_ways_vertices_pgr_set_updated_at() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN NEW.updated_at := now();
RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS ways_vertices_pgr_set_updated_at ON ways_vertices_pgr;
CREATE TRIGGER ways_vertices_pgr_set_updated_at BEFORE
UPDATE ON ways_vertices_pgr FOR EACH ROW EXECUTE FUNCTION trg_ways_vertices_pgr_set_updated_at();
-- triggers to keep updated_at fresh for ways
CREATE OR REPLACE FUNCTION trg_ways_set_updated_at() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN NEW.updated_at := now();
RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS ways_set_updated_at ON ways;
CREATE TRIGGER ways_set_updated_at BEFORE
UPDATE ON ways FOR EACH ROW EXECUTE FUNCTION trg_ways_set_updated_at();
-- 7) maintenance recommendations (comments)
-- - After bulk loading, run ANALYZE on the tables to refresh planner stats:
--     ANALYZE route;
--     ANALYZE route_geometry;
--     ANALYZE stop;
--     ANALYZE route_stop;
--     ANALYZE ways;
--     ANALYZE ways_vertices_pgr;
-- - If you bulk-load many rows, consider disabling the triggers temporarily and backfilling the projected columns in one UPDATE pass for speed.
-- - SP-GiST is a good fit for dense point datasets (stops). If you later need spatial index capabilities like KNN on complex line geometry or covering queries, GiST on lines is the right choice and is already present.
-- - For routing calculations, ensure ways.cost and ways.reverse_cost are properly set for pgRouting functions