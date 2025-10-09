--
-- PostgreSQL database dump
--

\restrict ptZfCTeuS7IhFerFJLEmJcfBCvrjhaDG0E33BqsjPIb28Zr0mzFhMGKHIDu8Kws

-- Dumped from database version 18.0 (Debian 18.0-1.pgdg13+3)
-- Dumped by pg_dump version 18.0 (Debian 18.0-1.pgdg13+3)

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET transaction_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: public; Type: SCHEMA; Schema: -; Owner: pg_database_owner
--

CREATE SCHEMA public;


ALTER SCHEMA public OWNER TO pg_database_owner;

--
-- Name: SCHEMA public; Type: COMMENT; Schema: -; Owner: pg_database_owner
--

COMMENT ON SCHEMA public IS 'standard public schema';


SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: configuration; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.configuration (
    id integer NOT NULL,
    tag_id integer,
    tag_key text,
    tag_value text,
    priority double precision,
    maxspeed double precision,
    maxspeed_forward double precision,
    maxspeed_backward double precision,
    force character(1)
)
WITH (autovacuum_enabled='false');


ALTER TABLE public.configuration OWNER TO postgres;

--
-- Name: configuration_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.configuration_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.configuration_id_seq OWNER TO postgres;

--
-- Name: configuration_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.configuration_id_seq OWNED BY public.configuration.id;


--
-- Name: gtfs_shapes; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.gtfs_shapes (
    id integer NOT NULL,
    feed_id text NOT NULL,
    shape_id text NOT NULL,
    geom public.geometry(LineString,4326) NOT NULL,
    length_m double precision,
    created_at timestamp with time zone DEFAULT now(),
    geom_geog public.geography(LineString,4326) GENERATED ALWAYS AS ((geom)::public.geography) STORED,
    route_type integer
);


ALTER TABLE public.gtfs_shapes OWNER TO postgres;

--
-- Name: gtfs_shapes_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.gtfs_shapes_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.gtfs_shapes_id_seq OWNER TO postgres;

--
-- Name: gtfs_shapes_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.gtfs_shapes_id_seq OWNED BY public.gtfs_shapes.id;


--
-- Name: gtfs_shapes_raw; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.gtfs_shapes_raw (
    feed_id text,
    route_name text,
    shape_id text,
    shape_pt_sequence integer,
    shape_pt_lat double precision,
    shape_pt_lon double precision,
    imported_at timestamp with time zone DEFAULT now()
);


ALTER TABLE public.gtfs_shapes_raw OWNER TO postgres;

--
-- Name: pointsofinterest; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.pointsofinterest (
    pid bigint NOT NULL,
    osm_id bigint,
    vertex_id bigint,
    edge_id bigint,
    side character(1),
    fraction double precision,
    length_m double precision,
    tag_name text,
    tag_value text,
    name text,
    the_geom public.geometry(Point,4326),
    new_geom public.geometry(Point,4326)
)
WITH (autovacuum_enabled='false');


ALTER TABLE public.pointsofinterest OWNER TO postgres;

--
-- Name: pointsofinterest_pid_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.pointsofinterest_pid_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.pointsofinterest_pid_seq OWNER TO postgres;

--
-- Name: pointsofinterest_pid_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.pointsofinterest_pid_seq OWNED BY public.pointsofinterest.pid;


--
-- Name: routes; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.routes (
    route_id text NOT NULL,
    route_name text,
    route_type integer,
    shape_id text
);


ALTER TABLE public.routes OWNER TO postgres;

--
-- Name: stop_routes; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.stop_routes (
    stop_id bigint NOT NULL,
    route_id text NOT NULL
);


ALTER TABLE public.stop_routes OWNER TO postgres;

--
-- Name: stops; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.stops (
    stop_id bigint NOT NULL,
    stop_name text,
    stop_name_ar text,
    stop_lat double precision,
    stop_lon double precision,
    geom public.geometry(Point,4326)
);


ALTER TABLE public.stops OWNER TO postgres;

--
-- Name: ways; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.ways (
    gid bigint NOT NULL,
    osm_id bigint,
    tag_id integer,
    length double precision,
    length_m double precision,
    name text,
    source bigint,
    target bigint,
    source_osm bigint,
    target_osm bigint,
    cost double precision,
    reverse_cost double precision,
    cost_s double precision,
    reverse_cost_s double precision,
    rule text,
    one_way integer,
    oneway text,
    x1 double precision,
    y1 double precision,
    x2 double precision,
    y2 double precision,
    maxspeed_forward double precision,
    maxspeed_backward double precision,
    priority double precision DEFAULT 1,
    the_geom public.geometry(LineString,4326)
)
WITH (autovacuum_enabled='false');


ALTER TABLE public.ways OWNER TO postgres;

--
-- Name: ways_gid_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.ways_gid_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.ways_gid_seq OWNER TO postgres;

--
-- Name: ways_gid_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.ways_gid_seq OWNED BY public.ways.gid;


--
-- Name: ways_vertices_pgr; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.ways_vertices_pgr (
    id bigint NOT NULL,
    osm_id bigint,
    eout integer,
    lon numeric(11,8),
    lat numeric(11,8),
    cnt integer,
    chk integer,
    ein integer,
    the_geom public.geometry(Point,4326)
)
WITH (autovacuum_enabled='false');


ALTER TABLE public.ways_vertices_pgr OWNER TO postgres;

--
-- Name: ways_vertices_pgr_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.ways_vertices_pgr_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.ways_vertices_pgr_id_seq OWNER TO postgres;

--
-- Name: ways_vertices_pgr_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.ways_vertices_pgr_id_seq OWNED BY public.ways_vertices_pgr.id;


--
-- Name: configuration id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.configuration ALTER COLUMN id SET DEFAULT nextval('public.configuration_id_seq'::regclass);


--
-- Name: gtfs_shapes id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.gtfs_shapes ALTER COLUMN id SET DEFAULT nextval('public.gtfs_shapes_id_seq'::regclass);


--
-- Name: pointsofinterest pid; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.pointsofinterest ALTER COLUMN pid SET DEFAULT nextval('public.pointsofinterest_pid_seq'::regclass);


--
-- Name: ways gid; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.ways ALTER COLUMN gid SET DEFAULT nextval('public.ways_gid_seq'::regclass);


--
-- Name: ways_vertices_pgr id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.ways_vertices_pgr ALTER COLUMN id SET DEFAULT nextval('public.ways_vertices_pgr_id_seq'::regclass);


--
-- Name: configuration configuration_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.configuration
    ADD CONSTRAINT configuration_pkey PRIMARY KEY (id);


--
-- Name: configuration configuration_tag_id_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.configuration
    ADD CONSTRAINT configuration_tag_id_key UNIQUE (tag_id);


--
-- Name: gtfs_shapes gtfs_shapes_feed_id_shape_id_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.gtfs_shapes
    ADD CONSTRAINT gtfs_shapes_feed_id_shape_id_key UNIQUE (feed_id, shape_id);


--
-- Name: gtfs_shapes gtfs_shapes_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.gtfs_shapes
    ADD CONSTRAINT gtfs_shapes_pkey PRIMARY KEY (id);


--
-- Name: pointsofinterest pointsofinterest_osm_id_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.pointsofinterest
    ADD CONSTRAINT pointsofinterest_osm_id_key UNIQUE (osm_id);


--
-- Name: pointsofinterest pointsofinterest_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.pointsofinterest
    ADD CONSTRAINT pointsofinterest_pkey PRIMARY KEY (pid);


--
-- Name: routes routes_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.routes
    ADD CONSTRAINT routes_pkey PRIMARY KEY (route_id);


--
-- Name: stop_routes stop_routes_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.stop_routes
    ADD CONSTRAINT stop_routes_pkey PRIMARY KEY (stop_id, route_id);


--
-- Name: stops stops_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.stops
    ADD CONSTRAINT stops_pkey PRIMARY KEY (stop_id);


--
-- Name: ways ways_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.ways
    ADD CONSTRAINT ways_pkey PRIMARY KEY (gid);


--
-- Name: ways_vertices_pgr ways_vertices_pgr_osm_id_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.ways_vertices_pgr
    ADD CONSTRAINT ways_vertices_pgr_osm_id_key UNIQUE (osm_id);


--
-- Name: ways_vertices_pgr ways_vertices_pgr_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.ways_vertices_pgr
    ADD CONSTRAINT ways_vertices_pgr_pkey PRIMARY KEY (id);


--
-- Name: gtfs_shapes_geom_idx; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX gtfs_shapes_geom_idx ON public.gtfs_shapes USING gist (geom);


--
-- Name: idx_gtfs_shapes_geom_geog; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_gtfs_shapes_geom_geog ON public.gtfs_shapes USING gist (geom_geog);


--
-- Name: pointsofinterest_the_geom_idx; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX pointsofinterest_the_geom_idx ON public.pointsofinterest USING gist (the_geom);


--
-- Name: ways_the_geom_idx; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ways_the_geom_idx ON public.ways USING gist (the_geom);


--
-- Name: ways_vertices_pgr_the_geom_idx; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ways_vertices_pgr_the_geom_idx ON public.ways_vertices_pgr USING gist (the_geom);


--
-- Name: stop_routes stop_routes_route_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.stop_routes
    ADD CONSTRAINT stop_routes_route_id_fkey FOREIGN KEY (route_id) REFERENCES public.routes(route_id);


--
-- Name: stop_routes stop_routes_stop_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.stop_routes
    ADD CONSTRAINT stop_routes_stop_id_fkey FOREIGN KEY (stop_id) REFERENCES public.stops(stop_id);


--
-- Name: ways ways_source_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.ways
    ADD CONSTRAINT ways_source_fkey FOREIGN KEY (source) REFERENCES public.ways_vertices_pgr(id);


--
-- Name: ways ways_source_osm_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.ways
    ADD CONSTRAINT ways_source_osm_fkey FOREIGN KEY (source_osm) REFERENCES public.ways_vertices_pgr(osm_id);


--
-- Name: ways ways_tag_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.ways
    ADD CONSTRAINT ways_tag_id_fkey FOREIGN KEY (tag_id) REFERENCES public.configuration(tag_id);


--
-- Name: ways ways_target_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.ways
    ADD CONSTRAINT ways_target_fkey FOREIGN KEY (target) REFERENCES public.ways_vertices_pgr(id);


--
-- Name: ways ways_target_osm_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.ways
    ADD CONSTRAINT ways_target_osm_fkey FOREIGN KEY (target_osm) REFERENCES public.ways_vertices_pgr(osm_id);


--
-- PostgreSQL database dump complete
--

\unrestrict ptZfCTeuS7IhFerFJLEmJcfBCvrjhaDG0E33BqsjPIb28Zr0mzFhMGKHIDu8Kws

