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
-- Name: sherlockdb; Type: SCHEMA; Schema: -; Owner: -
--

CREATE SCHEMA sherlockdb;


--
-- Name: availability; Type: TYPE; Schema: sherlockdb; Owner: -
--

CREATE TYPE sherlockdb.availability AS ENUM (
    'everyone',
    'granted',
    'off'
);


--
-- Name: buffer_basis; Type: TYPE; Schema: sherlockdb; Owner: -
--

CREATE TYPE sherlockdb.buffer_basis AS ENUM (
    'one_to_one',
    'required_ratio'
);


--
-- Name: byte_unit; Type: TYPE; Schema: sherlockdb; Owner: -
--

CREATE TYPE sherlockdb.byte_unit AS ENUM (
    'iec',
    'si'
);


--
-- Name: chart_range; Type: TYPE; Schema: sherlockdb; Owner: -
--

CREATE TYPE sherlockdb.chart_range AS ENUM (
    'day',
    'week',
    'month',
    'quarter',
    'year',
    'all'
);


--
-- Name: comparison_stat; Type: TYPE; Schema: sherlockdb; Owner: -
--

CREATE TYPE sherlockdb.comparison_stat AS ENUM (
    'buffer',
    'uploaded',
    'downloaded',
    'ratio',
    'interval_ratio',
    'seeding',
    'leeching',
    'snatched',
    'uploads',
    'forum_posts',
    'torrent_comments'
);


--
-- Name: connection_status; Type: TYPE; Schema: sherlockdb; Owner: -
--

CREATE TYPE sherlockdb.connection_status AS ENUM (
    'ok',
    'failing',
    'needs_key',
    'paused',
    'needs_check'
);


--
-- Name: site_credential_kind; Type: TYPE; Schema: sherlockdb; Owner: -
--

CREATE TYPE sherlockdb.site_credential_kind AS ENUM (
    'api_key',
    'passkey'
);


--
-- Name: site_engine; Type: TYPE; Schema: sherlockdb; Owner: -
--

CREATE TYPE sherlockdb.site_engine AS ENUM (
    'gazelle',
    'hdbits',
    'btn',
    'gazellegames',
    'unit3d',
    'anthelion',
    'animebytes'
);


--
-- Name: site_key_owner; Type: TYPE; Schema: sherlockdb; Owner: -
--

CREATE TYPE sherlockdb.site_key_owner AS ENUM (
    'member',
    'instance'
);


--
-- Name: site_pause_reason; Type: TYPE; Schema: sherlockdb; Owner: -
--

CREATE TYPE sherlockdb.site_pause_reason AS ENUM (
    'rate_limited',
    'key_refused',
    'errors',
    'admin'
);


--
-- Name: site_tier; Type: TYPE; Schema: sherlockdb; Owner: -
--

CREATE TYPE sherlockdb.site_tier AS ENUM (
    'supported',
    'beta',
    'unsupported'
);


--
-- Name: theme; Type: TYPE; Schema: sherlockdb; Owner: -
--

CREATE TYPE sherlockdb.theme AS ENUM (
    'system',
    'light',
    'dark'
);


--
-- Name: set_updated_at(); Type: FUNCTION; Schema: sherlockdb; Owner: -
--

CREATE FUNCTION sherlockdb.set_updated_at() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  NEW.updated_at = CURRENT_TIMESTAMP;
  RETURN NEW;
END;
$$;


SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: ar_internal_metadata; Type: TABLE; Schema: sherlockdb; Owner: -
--

CREATE TABLE sherlockdb.ar_internal_metadata (
    key character varying NOT NULL,
    value character varying,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: connections; Type: TABLE; Schema: sherlockdb; Owner: -
--

CREATE TABLE sherlockdb.connections (
    id bigint NOT NULL,
    user_id bigint NOT NULL,
    site_id bigint NOT NULL,
    external_username text NOT NULL,
    external_user_id text NOT NULL,
    credential text,
    status sherlockdb.connection_status DEFAULT 'ok'::sherlockdb.connection_status NOT NULL,
    polled_at timestamp(6) without time zone,
    error_message text,
    failure_count integer DEFAULT 0 NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    color text,
    "position" integer DEFAULT 0 NOT NULL,
    profile_code text,
    is_key_owner boolean DEFAULT false NOT NULL,
    CONSTRAINT connections_color_format CHECK (((color IS NULL) OR (color ~ '^#[0-9a-f]{6}$'::text))),
    CONSTRAINT connections_credential_or_profile_code CHECK (((credential IS NULL) OR (profile_code IS NULL))),
    CONSTRAINT connections_error_message_length CHECK ((char_length(error_message) <= 500)),
    CONSTRAINT connections_failure_count_range CHECK ((failure_count >= 0)),
    CONSTRAINT connections_key_owner_reads_with_instance_key CHECK (((NOT is_key_owner) OR ((credential IS NULL) AND (profile_code IS NULL)))),
    CONSTRAINT connections_position_range CHECK (("position" >= 0)),
    CONSTRAINT connections_profile_code_format CHECK ((profile_code ~ '^[a-z0-9]{10}$'::text))
);


--
-- Name: connections_id_seq; Type: SEQUENCE; Schema: sherlockdb; Owner: -
--

CREATE SEQUENCE sherlockdb.connections_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: connections_id_seq; Type: SEQUENCE OWNED BY; Schema: sherlockdb; Owner: -
--

ALTER SEQUENCE sherlockdb.connections_id_seq OWNED BY sherlockdb.connections.id;


--
-- Name: cross_seed_snapshots; Type: TABLE; Schema: sherlockdb; Owner: -
--

CREATE TABLE sherlockdb.cross_seed_snapshots (
    id bigint NOT NULL,
    connection_id bigint NOT NULL,
    torrents integer NOT NULL,
    size bigint NOT NULL,
    uploaded bigint NOT NULL,
    cross_seeded integer NOT NULL,
    cross_seeded_size bigint NOT NULL,
    cross_seeded_uploaded bigint NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    cross_seeded_paused integer DEFAULT 0 NOT NULL,
    CONSTRAINT cross_seed_snapshots_paused_range CHECK ((cross_seeded_paused >= 0)),
    CONSTRAINT cross_seed_snapshots_range CHECK (((torrents >= 0) AND (size >= 0) AND (uploaded >= 0) AND ((cross_seeded >= 0) AND (cross_seeded <= torrents)) AND ((cross_seeded_size >= 0) AND (cross_seeded_size <= size)) AND ((cross_seeded_uploaded >= 0) AND (cross_seeded_uploaded <= uploaded))))
);


--
-- Name: cross_seed_snapshots_id_seq; Type: SEQUENCE; Schema: sherlockdb; Owner: -
--

CREATE SEQUENCE sherlockdb.cross_seed_snapshots_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: cross_seed_snapshots_id_seq; Type: SEQUENCE OWNED BY; Schema: sherlockdb; Owner: -
--

ALTER SEQUENCE sherlockdb.cross_seed_snapshots_id_seq OWNED BY sherlockdb.cross_seed_snapshots.id;


--
-- Name: instance_settings; Type: TABLE; Schema: sherlockdb; Owner: -
--

CREATE TABLE sherlockdb.instance_settings (
    id bigint NOT NULL,
    tracker_contact text,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    skipped_setup_steps text[] DEFAULT '{}'::text[] NOT NULL,
    is_update_check_enabled boolean DEFAULT false NOT NULL,
    latest_version text,
    update_checked_at timestamp(6) without time zone,
    CONSTRAINT instance_settings_latest_version_length CHECK ((char_length(latest_version) <= 100)),
    CONSTRAINT instance_settings_skipped_setup_steps_values CHECK ((skipped_setup_steps <@ ARRAY['invites'::text, 'updates'::text])),
    CONSTRAINT instance_settings_tracker_contact_length CHECK ((char_length(tracker_contact) <= 200))
);


--
-- Name: instance_settings_id_seq; Type: SEQUENCE; Schema: sherlockdb; Owner: -
--

CREATE SEQUENCE sherlockdb.instance_settings_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: instance_settings_id_seq; Type: SEQUENCE OWNED BY; Schema: sherlockdb; Owner: -
--

ALTER SEQUENCE sherlockdb.instance_settings_id_seq OWNED BY sherlockdb.instance_settings.id;


--
-- Name: integration_grants; Type: TABLE; Schema: sherlockdb; Owner: -
--

CREATE TABLE sherlockdb.integration_grants (
    id bigint NOT NULL,
    user_id bigint NOT NULL,
    integration_id bigint NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: integration_grants_id_seq; Type: SEQUENCE; Schema: sherlockdb; Owner: -
--

CREATE SEQUENCE sherlockdb.integration_grants_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: integration_grants_id_seq; Type: SEQUENCE OWNED BY; Schema: sherlockdb; Owner: -
--

ALTER SEQUENCE sherlockdb.integration_grants_id_seq OWNED BY sherlockdb.integration_grants.id;


--
-- Name: integrations; Type: TABLE; Schema: sherlockdb; Owner: -
--

CREATE TABLE sherlockdb.integrations (
    id bigint NOT NULL,
    slug text NOT NULL,
    name text NOT NULL,
    availability sherlockdb.availability DEFAULT 'granted'::sherlockdb.availability NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    CONSTRAINT integrations_name_length CHECK ((char_length(name) <= 60)),
    CONSTRAINT integrations_slug_format CHECK ((slug ~ '^[a-z0-9-]+$'::text))
);


--
-- Name: integrations_id_seq; Type: SEQUENCE; Schema: sherlockdb; Owner: -
--

CREATE SEQUENCE sherlockdb.integrations_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: integrations_id_seq; Type: SEQUENCE OWNED BY; Schema: sherlockdb; Owner: -
--

ALTER SEQUENCE sherlockdb.integrations_id_seq OWNED BY sherlockdb.integrations.id;


--
-- Name: invites; Type: TABLE; Schema: sherlockdb; Owner: -
--

CREATE TABLE sherlockdb.invites (
    id bigint NOT NULL,
    code text NOT NULL,
    created_by_user_id bigint NOT NULL,
    expires_at timestamp(6) without time zone,
    revoked_at timestamp(6) without time zone,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    uses integer DEFAULT 0 NOT NULL,
    max_uses integer DEFAULT 1,
    site_id bigint,
    CONSTRAINT invites_max_uses_range CHECK (((max_uses IS NULL) OR (max_uses >= 1))),
    CONSTRAINT invites_site_only_when_open CHECK (((site_id IS NULL) OR (max_uses IS NULL) OR (max_uses > 1))),
    CONSTRAINT invites_uses_range CHECK (((uses >= 0) AND ((max_uses IS NULL) OR (uses <= max_uses))))
);


--
-- Name: invites_id_seq; Type: SEQUENCE; Schema: sherlockdb; Owner: -
--

CREATE SEQUENCE sherlockdb.invites_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: invites_id_seq; Type: SEQUENCE OWNED BY; Schema: sherlockdb; Owner: -
--

ALTER SEQUENCE sherlockdb.invites_id_seq OWNED BY sherlockdb.invites.id;


--
-- Name: pinned_comparisons; Type: TABLE; Schema: sherlockdb; Owner: -
--

CREATE TABLE sherlockdb.pinned_comparisons (
    id bigint NOT NULL,
    user_id bigint NOT NULL,
    stat sherlockdb.comparison_stat NOT NULL,
    range sherlockdb.chart_range NOT NULL,
    is_per_interval boolean DEFAULT false NOT NULL,
    connection_ids bigint[] NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    CONSTRAINT pinned_comparisons_connection_ids_present CHECK ((cardinality(connection_ids) > 0))
);


--
-- Name: pinned_comparisons_id_seq; Type: SEQUENCE; Schema: sherlockdb; Owner: -
--

CREATE SEQUENCE sherlockdb.pinned_comparisons_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: pinned_comparisons_id_seq; Type: SEQUENCE OWNED BY; Schema: sherlockdb; Owner: -
--

ALTER SEQUENCE sherlockdb.pinned_comparisons_id_seq OWNED BY sherlockdb.pinned_comparisons.id;


--
-- Name: qui_connections; Type: TABLE; Schema: sherlockdb; Owner: -
--

CREATE TABLE sherlockdb.qui_connections (
    id bigint NOT NULL,
    user_id bigint NOT NULL,
    url text NOT NULL,
    credential text NOT NULL,
    polled_at timestamp(6) without time zone NOT NULL,
    error_message text,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    label text,
    seeding integer,
    cross_seeded integer,
    cross_seeded_paused integer,
    is_key_refused boolean DEFAULT false NOT NULL,
    CONSTRAINT qui_connections_error_message_length CHECK ((char_length(error_message) <= 500)),
    CONSTRAINT qui_connections_label_length CHECK (((char_length(label) >= 1) AND (char_length(label) <= 60))),
    CONSTRAINT qui_connections_summary_range CHECK ((((seeding IS NULL) AND (cross_seeded IS NULL) AND (cross_seeded_paused IS NULL)) OR (((cross_seeded >= 0) AND (cross_seeded <= seeding)) AND (cross_seeded_paused >= 0)))),
    CONSTRAINT qui_connections_url_format CHECK (((url ~ '^https?://'::text) AND (char_length(url) <= 300)))
);


--
-- Name: qui_connections_id_seq; Type: SEQUENCE; Schema: sherlockdb; Owner: -
--

CREATE SEQUENCE sherlockdb.qui_connections_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: qui_connections_id_seq; Type: SEQUENCE OWNED BY; Schema: sherlockdb; Owner: -
--

ALTER SEQUENCE sherlockdb.qui_connections_id_seq OWNED BY sherlockdb.qui_connections.id;


--
-- Name: schema_migrations; Type: TABLE; Schema: sherlockdb; Owner: -
--

CREATE TABLE sherlockdb.schema_migrations (
    version character varying NOT NULL
);


--
-- Name: sessions; Type: TABLE; Schema: sherlockdb; Owner: -
--

CREATE TABLE sherlockdb.sessions (
    id bigint NOT NULL,
    user_id bigint NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: sessions_id_seq; Type: SEQUENCE; Schema: sherlockdb; Owner: -
--

CREATE SEQUENCE sherlockdb.sessions_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: sessions_id_seq; Type: SEQUENCE OWNED BY; Schema: sherlockdb; Owner: -
--

ALTER SEQUENCE sherlockdb.sessions_id_seq OWNED BY sherlockdb.sessions.id;


--
-- Name: site_grants; Type: TABLE; Schema: sherlockdb; Owner: -
--

CREATE TABLE sherlockdb.site_grants (
    id bigint NOT NULL,
    user_id bigint NOT NULL,
    site_id bigint NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: site_grants_id_seq; Type: SEQUENCE; Schema: sherlockdb; Owner: -
--

CREATE SEQUENCE sherlockdb.site_grants_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: site_grants_id_seq; Type: SEQUENCE OWNED BY; Schema: sherlockdb; Owner: -
--

ALTER SEQUENCE sherlockdb.site_grants_id_seq OWNED BY sherlockdb.site_grants.id;


--
-- Name: sites; Type: TABLE; Schema: sherlockdb; Owner: -
--

CREATE TABLE sherlockdb.sites (
    id bigint NOT NULL,
    slug text NOT NULL,
    name text NOT NULL,
    engine sherlockdb.site_engine,
    base_url text,
    api_key_url text,
    key_instructions text,
    unsupported_reason text,
    tier sherlockdb.site_tier NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    credential_kind sherlockdb.site_credential_kind DEFAULT 'api_key'::sherlockdb.site_credential_kind NOT NULL,
    credential_warning text,
    tracker_hosts text[] DEFAULT '{}'::text[] NOT NULL,
    availability sherlockdb.availability DEFAULT 'everyone'::sherlockdb.availability NOT NULL,
    short_name text NOT NULL,
    request_interval interval DEFAULT '00:00:02'::interval NOT NULL,
    next_request_at timestamp(6) without time zone DEFAULT now() NOT NULL,
    pause_reason sherlockdb.site_pause_reason,
    paused_until timestamp(6) without time zone,
    failure_streak integer DEFAULT 0 NOT NULL,
    key_owner sherlockdb.site_key_owner DEFAULT 'member'::sherlockdb.site_key_owner NOT NULL,
    instance_credential text,
    privacy_settings_url text,
    privacy_hint text,
    CONSTRAINT sites_credential_warning_length CHECK ((char_length(credential_warning) <= 300)),
    CONSTRAINT sites_failure_streak_range CHECK ((failure_streak >= 0)),
    CONSTRAINT sites_instance_key_fields CHECK (((key_owner = 'member'::sherlockdb.site_key_owner) OR ((instance_credential IS NOT NULL) AND (privacy_settings_url IS NOT NULL)))),
    CONSTRAINT sites_paused_until_has_reason CHECK (((paused_until IS NULL) OR (pause_reason IS NOT NULL))),
    CONSTRAINT sites_privacy_hint_length CHECK ((char_length(privacy_hint) <= 200)),
    CONSTRAINT sites_privacy_settings_url_format CHECK ((privacy_settings_url ~ '^https://'::text)),
    CONSTRAINT sites_request_interval_range CHECK ((request_interval >= '00:00:01'::interval)),
    CONSTRAINT sites_short_name_length CHECK (((char_length(short_name) >= 1) AND (char_length(short_name) <= 8))),
    CONSTRAINT sites_slug_format CHECK ((slug ~ '^[a-z0-9-]+$'::text)),
    CONSTRAINT sites_tier_fields CHECK ((((tier = 'unsupported'::sherlockdb.site_tier) AND (unsupported_reason IS NOT NULL)) OR ((tier <> 'unsupported'::sherlockdb.site_tier) AND (engine IS NOT NULL) AND (base_url ~ '^https://'::text) AND (api_key_url IS NOT NULL) AND (key_instructions IS NOT NULL))))
);


--
-- Name: sites_id_seq; Type: SEQUENCE; Schema: sherlockdb; Owner: -
--

CREATE SEQUENCE sherlockdb.sites_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: sites_id_seq; Type: SEQUENCE OWNED BY; Schema: sherlockdb; Owner: -
--

ALTER SEQUENCE sherlockdb.sites_id_seq OWNED BY sherlockdb.sites.id;


--
-- Name: snapshots; Type: TABLE; Schema: sherlockdb; Owner: -
--

CREATE TABLE sherlockdb.snapshots (
    id bigint NOT NULL,
    connection_id bigint NOT NULL,
    uploaded bigint NOT NULL,
    downloaded bigint NOT NULL,
    ratio numeric(12,4),
    required_ratio numeric(12,4),
    bonus_points numeric(16,2),
    seeding integer,
    leeching integer,
    snatched integer,
    hit_and_runs integer,
    user_class text,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    uploads integer,
    forum_posts integer,
    torrent_comments integer,
    source character varying DEFAULT 'api'::character varying NOT NULL,
    note text,
    created_by_user_id bigint,
    CONSTRAINT snapshots_source_valid CHECK (((source)::text = ANY ((ARRAY['api'::character varying, 'manual'::character varying, 'csv_import'::character varying, 'json_import'::character varying])::text[]))),
    CONSTRAINT snapshots_note_length CHECK (((note IS NULL) OR (char_length(note) <= 500))),
    CONSTRAINT snapshots_bytes_range CHECK (((uploaded >= 0) AND (downloaded >= 0))),
    CONSTRAINT snapshots_community_counts_range CHECK (((COALESCE(uploads, 0) >= 0) AND (COALESCE(forum_posts, 0) >= 0) AND (COALESCE(torrent_comments, 0) >= 0))),
    CONSTRAINT snapshots_counts_range CHECK (((COALESCE(seeding, 0) >= 0) AND (COALESCE(leeching, 0) >= 0) AND (COALESCE(snatched, 0) >= 0) AND (COALESCE(hit_and_runs, 0) >= 0)))
);


--
-- Name: snapshots_id_seq; Type: SEQUENCE; Schema: sherlockdb; Owner: -
--

CREATE SEQUENCE sherlockdb.snapshots_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: snapshots_id_seq; Type: SEQUENCE OWNED BY; Schema: sherlockdb; Owner: -
--

ALTER SEQUENCE sherlockdb.snapshots_id_seq OWNED BY sherlockdb.snapshots.id;


--
-- Name: solid_cable_messages; Type: TABLE; Schema: sherlockdb; Owner: -
--

CREATE TABLE sherlockdb.solid_cable_messages (
    id bigint NOT NULL,
    channel bytea NOT NULL,
    payload bytea NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    channel_hash bigint NOT NULL
);


--
-- Name: solid_cable_messages_id_seq; Type: SEQUENCE; Schema: sherlockdb; Owner: -
--

CREATE SEQUENCE sherlockdb.solid_cable_messages_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: solid_cable_messages_id_seq; Type: SEQUENCE OWNED BY; Schema: sherlockdb; Owner: -
--

ALTER SEQUENCE sherlockdb.solid_cable_messages_id_seq OWNED BY sherlockdb.solid_cable_messages.id;


--
-- Name: solid_cache_entries; Type: TABLE; Schema: sherlockdb; Owner: -
--

CREATE TABLE sherlockdb.solid_cache_entries (
    id bigint NOT NULL,
    key bytea NOT NULL,
    value bytea NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    key_hash bigint NOT NULL,
    byte_size integer NOT NULL
);


--
-- Name: solid_cache_entries_id_seq; Type: SEQUENCE; Schema: sherlockdb; Owner: -
--

CREATE SEQUENCE sherlockdb.solid_cache_entries_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: solid_cache_entries_id_seq; Type: SEQUENCE OWNED BY; Schema: sherlockdb; Owner: -
--

ALTER SEQUENCE sherlockdb.solid_cache_entries_id_seq OWNED BY sherlockdb.solid_cache_entries.id;


--
-- Name: solid_queue_batch_executions; Type: TABLE; Schema: sherlockdb; Owner: -
--

CREATE TABLE sherlockdb.solid_queue_batch_executions (
    id bigint NOT NULL,
    job_id bigint NOT NULL,
    batch_id bigint NOT NULL,
    created_at timestamp(6) without time zone NOT NULL
);


--
-- Name: solid_queue_batch_executions_id_seq; Type: SEQUENCE; Schema: sherlockdb; Owner: -
--

CREATE SEQUENCE sherlockdb.solid_queue_batch_executions_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: solid_queue_batch_executions_id_seq; Type: SEQUENCE OWNED BY; Schema: sherlockdb; Owner: -
--

ALTER SEQUENCE sherlockdb.solid_queue_batch_executions_id_seq OWNED BY sherlockdb.solid_queue_batch_executions.id;


--
-- Name: solid_queue_batches; Type: TABLE; Schema: sherlockdb; Owner: -
--

CREATE TABLE sherlockdb.solid_queue_batches (
    id bigint NOT NULL,
    active_job_batch_id character varying,
    description character varying,
    on_finish text,
    on_success text,
    on_failure text,
    metadata text,
    total_jobs integer DEFAULT 0 NOT NULL,
    completed_jobs integer DEFAULT 0 NOT NULL,
    failed_jobs integer DEFAULT 0 NOT NULL,
    enqueued_at timestamp(6) without time zone,
    finished_at timestamp(6) without time zone,
    failed_at timestamp(6) without time zone,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: solid_queue_batches_id_seq; Type: SEQUENCE; Schema: sherlockdb; Owner: -
--

CREATE SEQUENCE sherlockdb.solid_queue_batches_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: solid_queue_batches_id_seq; Type: SEQUENCE OWNED BY; Schema: sherlockdb; Owner: -
--

ALTER SEQUENCE sherlockdb.solid_queue_batches_id_seq OWNED BY sherlockdb.solid_queue_batches.id;


--
-- Name: solid_queue_blocked_executions; Type: TABLE; Schema: sherlockdb; Owner: -
--

CREATE TABLE sherlockdb.solid_queue_blocked_executions (
    id bigint NOT NULL,
    job_id bigint NOT NULL,
    queue_name character varying NOT NULL,
    priority integer DEFAULT 0 NOT NULL,
    concurrency_key character varying NOT NULL,
    expires_at timestamp(6) without time zone NOT NULL,
    created_at timestamp(6) without time zone NOT NULL
);


--
-- Name: solid_queue_blocked_executions_id_seq; Type: SEQUENCE; Schema: sherlockdb; Owner: -
--

CREATE SEQUENCE sherlockdb.solid_queue_blocked_executions_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: solid_queue_blocked_executions_id_seq; Type: SEQUENCE OWNED BY; Schema: sherlockdb; Owner: -
--

ALTER SEQUENCE sherlockdb.solid_queue_blocked_executions_id_seq OWNED BY sherlockdb.solid_queue_blocked_executions.id;


--
-- Name: solid_queue_claimed_executions; Type: TABLE; Schema: sherlockdb; Owner: -
--

CREATE TABLE sherlockdb.solid_queue_claimed_executions (
    id bigint NOT NULL,
    job_id bigint NOT NULL,
    process_id bigint,
    created_at timestamp(6) without time zone NOT NULL
);


--
-- Name: solid_queue_claimed_executions_id_seq; Type: SEQUENCE; Schema: sherlockdb; Owner: -
--

CREATE SEQUENCE sherlockdb.solid_queue_claimed_executions_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: solid_queue_claimed_executions_id_seq; Type: SEQUENCE OWNED BY; Schema: sherlockdb; Owner: -
--

ALTER SEQUENCE sherlockdb.solid_queue_claimed_executions_id_seq OWNED BY sherlockdb.solid_queue_claimed_executions.id;


--
-- Name: solid_queue_failed_executions; Type: TABLE; Schema: sherlockdb; Owner: -
--

CREATE TABLE sherlockdb.solid_queue_failed_executions (
    id bigint NOT NULL,
    job_id bigint NOT NULL,
    error text,
    created_at timestamp(6) without time zone NOT NULL
);


--
-- Name: solid_queue_failed_executions_id_seq; Type: SEQUENCE; Schema: sherlockdb; Owner: -
--

CREATE SEQUENCE sherlockdb.solid_queue_failed_executions_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: solid_queue_failed_executions_id_seq; Type: SEQUENCE OWNED BY; Schema: sherlockdb; Owner: -
--

ALTER SEQUENCE sherlockdb.solid_queue_failed_executions_id_seq OWNED BY sherlockdb.solid_queue_failed_executions.id;


--
-- Name: solid_queue_jobs; Type: TABLE; Schema: sherlockdb; Owner: -
--

CREATE TABLE sherlockdb.solid_queue_jobs (
    id bigint NOT NULL,
    queue_name character varying NOT NULL,
    class_name character varying NOT NULL,
    arguments text,
    priority integer DEFAULT 0 NOT NULL,
    active_job_id character varying,
    scheduled_at timestamp(6) without time zone,
    finished_at timestamp(6) without time zone,
    concurrency_key character varying,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    batch_id bigint
);


--
-- Name: solid_queue_jobs_id_seq; Type: SEQUENCE; Schema: sherlockdb; Owner: -
--

CREATE SEQUENCE sherlockdb.solid_queue_jobs_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: solid_queue_jobs_id_seq; Type: SEQUENCE OWNED BY; Schema: sherlockdb; Owner: -
--

ALTER SEQUENCE sherlockdb.solid_queue_jobs_id_seq OWNED BY sherlockdb.solid_queue_jobs.id;


--
-- Name: solid_queue_pauses; Type: TABLE; Schema: sherlockdb; Owner: -
--

CREATE TABLE sherlockdb.solid_queue_pauses (
    id bigint NOT NULL,
    queue_name character varying NOT NULL,
    created_at timestamp(6) without time zone NOT NULL
);


--
-- Name: solid_queue_pauses_id_seq; Type: SEQUENCE; Schema: sherlockdb; Owner: -
--

CREATE SEQUENCE sherlockdb.solid_queue_pauses_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: solid_queue_pauses_id_seq; Type: SEQUENCE OWNED BY; Schema: sherlockdb; Owner: -
--

ALTER SEQUENCE sherlockdb.solid_queue_pauses_id_seq OWNED BY sherlockdb.solid_queue_pauses.id;


--
-- Name: solid_queue_processes; Type: TABLE; Schema: sherlockdb; Owner: -
--

CREATE TABLE sherlockdb.solid_queue_processes (
    id bigint NOT NULL,
    kind character varying NOT NULL,
    last_heartbeat_at timestamp(6) without time zone NOT NULL,
    supervisor_id bigint,
    pid integer NOT NULL,
    hostname character varying,
    metadata text,
    created_at timestamp(6) without time zone NOT NULL,
    name character varying NOT NULL
);


--
-- Name: solid_queue_processes_id_seq; Type: SEQUENCE; Schema: sherlockdb; Owner: -
--

CREATE SEQUENCE sherlockdb.solid_queue_processes_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: solid_queue_processes_id_seq; Type: SEQUENCE OWNED BY; Schema: sherlockdb; Owner: -
--

ALTER SEQUENCE sherlockdb.solid_queue_processes_id_seq OWNED BY sherlockdb.solid_queue_processes.id;


--
-- Name: solid_queue_ready_executions; Type: TABLE; Schema: sherlockdb; Owner: -
--

CREATE TABLE sherlockdb.solid_queue_ready_executions (
    id bigint NOT NULL,
    job_id bigint NOT NULL,
    queue_name character varying NOT NULL,
    priority integer DEFAULT 0 NOT NULL,
    created_at timestamp(6) without time zone NOT NULL
);


--
-- Name: solid_queue_ready_executions_id_seq; Type: SEQUENCE; Schema: sherlockdb; Owner: -
--

CREATE SEQUENCE sherlockdb.solid_queue_ready_executions_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: solid_queue_ready_executions_id_seq; Type: SEQUENCE OWNED BY; Schema: sherlockdb; Owner: -
--

ALTER SEQUENCE sherlockdb.solid_queue_ready_executions_id_seq OWNED BY sherlockdb.solid_queue_ready_executions.id;


--
-- Name: solid_queue_recurring_executions; Type: TABLE; Schema: sherlockdb; Owner: -
--

CREATE TABLE sherlockdb.solid_queue_recurring_executions (
    id bigint NOT NULL,
    job_id bigint NOT NULL,
    task_key character varying NOT NULL,
    run_at timestamp(6) without time zone NOT NULL,
    created_at timestamp(6) without time zone NOT NULL
);


--
-- Name: solid_queue_recurring_executions_id_seq; Type: SEQUENCE; Schema: sherlockdb; Owner: -
--

CREATE SEQUENCE sherlockdb.solid_queue_recurring_executions_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: solid_queue_recurring_executions_id_seq; Type: SEQUENCE OWNED BY; Schema: sherlockdb; Owner: -
--

ALTER SEQUENCE sherlockdb.solid_queue_recurring_executions_id_seq OWNED BY sherlockdb.solid_queue_recurring_executions.id;


--
-- Name: solid_queue_recurring_tasks; Type: TABLE; Schema: sherlockdb; Owner: -
--

CREATE TABLE sherlockdb.solid_queue_recurring_tasks (
    id bigint NOT NULL,
    key character varying NOT NULL,
    schedule character varying NOT NULL,
    command character varying(2048),
    class_name character varying,
    arguments text,
    queue_name character varying,
    priority integer DEFAULT 0,
    static boolean DEFAULT true NOT NULL,
    description text,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: solid_queue_recurring_tasks_id_seq; Type: SEQUENCE; Schema: sherlockdb; Owner: -
--

CREATE SEQUENCE sherlockdb.solid_queue_recurring_tasks_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: solid_queue_recurring_tasks_id_seq; Type: SEQUENCE OWNED BY; Schema: sherlockdb; Owner: -
--

ALTER SEQUENCE sherlockdb.solid_queue_recurring_tasks_id_seq OWNED BY sherlockdb.solid_queue_recurring_tasks.id;


--
-- Name: solid_queue_scheduled_executions; Type: TABLE; Schema: sherlockdb; Owner: -
--

CREATE TABLE sherlockdb.solid_queue_scheduled_executions (
    id bigint NOT NULL,
    job_id bigint NOT NULL,
    queue_name character varying NOT NULL,
    priority integer DEFAULT 0 NOT NULL,
    scheduled_at timestamp(6) without time zone NOT NULL,
    created_at timestamp(6) without time zone NOT NULL
);


--
-- Name: solid_queue_scheduled_executions_id_seq; Type: SEQUENCE; Schema: sherlockdb; Owner: -
--

CREATE SEQUENCE sherlockdb.solid_queue_scheduled_executions_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: solid_queue_scheduled_executions_id_seq; Type: SEQUENCE OWNED BY; Schema: sherlockdb; Owner: -
--

ALTER SEQUENCE sherlockdb.solid_queue_scheduled_executions_id_seq OWNED BY sherlockdb.solid_queue_scheduled_executions.id;


--
-- Name: solid_queue_semaphores; Type: TABLE; Schema: sherlockdb; Owner: -
--

CREATE TABLE sherlockdb.solid_queue_semaphores (
    id bigint NOT NULL,
    key character varying NOT NULL,
    value integer DEFAULT 1 NOT NULL,
    expires_at timestamp(6) without time zone NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: solid_queue_semaphores_id_seq; Type: SEQUENCE; Schema: sherlockdb; Owner: -
--

CREATE SEQUENCE sherlockdb.solid_queue_semaphores_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: solid_queue_semaphores_id_seq; Type: SEQUENCE OWNED BY; Schema: sherlockdb; Owner: -
--

ALTER SEQUENCE sherlockdb.solid_queue_semaphores_id_seq OWNED BY sherlockdb.solid_queue_semaphores.id;


--
-- Name: users; Type: TABLE; Schema: sherlockdb; Owner: -
--

CREATE TABLE sherlockdb.users (
    id bigint NOT NULL,
    username text NOT NULL,
    password_digest text NOT NULL,
    invited_by_user_id bigint,
    invite_limit integer DEFAULT 3 NOT NULL,
    is_admin boolean DEFAULT false NOT NULL,
    is_disabled boolean DEFAULT false NOT NULL,
    is_password_change_required boolean DEFAULT false NOT NULL,
    time_zone text DEFAULT 'UTC'::text NOT NULL,
    byte_unit sherlockdb.byte_unit DEFAULT 'iec'::sherlockdb.byte_unit NOT NULL,
    default_range sherlockdb.chart_range DEFAULT 'week'::sherlockdb.chart_range NOT NULL,
    theme sherlockdb.theme DEFAULT 'system'::sherlockdb.theme NOT NULL,
    is_chart_filled boolean DEFAULT true NOT NULL,
    is_chart_points_shown boolean DEFAULT false NOT NULL,
    tracker_rules_accepted_at timestamp(6) without time zone,
    onboarding_completed_at timestamp(6) without time zone,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    metrics_token_digest text,
    is_tracker_name_short boolean DEFAULT false NOT NULL,
    invite_id bigint,
    ui_state jsonb DEFAULT '{}'::jsonb NOT NULL,
    buffer_basis sherlockdb.buffer_basis DEFAULT 'one_to_one'::sherlockdb.buffer_basis NOT NULL,
    CONSTRAINT users_invite_limit_range CHECK ((invite_limit >= 0)),
    CONSTRAINT users_ui_state_object CHECK ((jsonb_typeof(ui_state) = 'object'::text))
);


--
-- Name: users_id_seq; Type: SEQUENCE; Schema: sherlockdb; Owner: -
--

CREATE SEQUENCE sherlockdb.users_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: users_id_seq; Type: SEQUENCE OWNED BY; Schema: sherlockdb; Owner: -
--

ALTER SEQUENCE sherlockdb.users_id_seq OWNED BY sherlockdb.users.id;


--
-- Name: connections id; Type: DEFAULT; Schema: sherlockdb; Owner: -
--

ALTER TABLE ONLY sherlockdb.connections ALTER COLUMN id SET DEFAULT nextval('sherlockdb.connections_id_seq'::regclass);


--
-- Name: cross_seed_snapshots id; Type: DEFAULT; Schema: sherlockdb; Owner: -
--

ALTER TABLE ONLY sherlockdb.cross_seed_snapshots ALTER COLUMN id SET DEFAULT nextval('sherlockdb.cross_seed_snapshots_id_seq'::regclass);


--
-- Name: instance_settings id; Type: DEFAULT; Schema: sherlockdb; Owner: -
--

ALTER TABLE ONLY sherlockdb.instance_settings ALTER COLUMN id SET DEFAULT nextval('sherlockdb.instance_settings_id_seq'::regclass);


--
-- Name: integration_grants id; Type: DEFAULT; Schema: sherlockdb; Owner: -
--

ALTER TABLE ONLY sherlockdb.integration_grants ALTER COLUMN id SET DEFAULT nextval('sherlockdb.integration_grants_id_seq'::regclass);


--
-- Name: integrations id; Type: DEFAULT; Schema: sherlockdb; Owner: -
--

ALTER TABLE ONLY sherlockdb.integrations ALTER COLUMN id SET DEFAULT nextval('sherlockdb.integrations_id_seq'::regclass);


--
-- Name: invites id; Type: DEFAULT; Schema: sherlockdb; Owner: -
--

ALTER TABLE ONLY sherlockdb.invites ALTER COLUMN id SET DEFAULT nextval('sherlockdb.invites_id_seq'::regclass);


--
-- Name: pinned_comparisons id; Type: DEFAULT; Schema: sherlockdb; Owner: -
--

ALTER TABLE ONLY sherlockdb.pinned_comparisons ALTER COLUMN id SET DEFAULT nextval('sherlockdb.pinned_comparisons_id_seq'::regclass);


--
-- Name: qui_connections id; Type: DEFAULT; Schema: sherlockdb; Owner: -
--

ALTER TABLE ONLY sherlockdb.qui_connections ALTER COLUMN id SET DEFAULT nextval('sherlockdb.qui_connections_id_seq'::regclass);


--
-- Name: sessions id; Type: DEFAULT; Schema: sherlockdb; Owner: -
--

ALTER TABLE ONLY sherlockdb.sessions ALTER COLUMN id SET DEFAULT nextval('sherlockdb.sessions_id_seq'::regclass);


--
-- Name: site_grants id; Type: DEFAULT; Schema: sherlockdb; Owner: -
--

ALTER TABLE ONLY sherlockdb.site_grants ALTER COLUMN id SET DEFAULT nextval('sherlockdb.site_grants_id_seq'::regclass);


--
-- Name: sites id; Type: DEFAULT; Schema: sherlockdb; Owner: -
--

ALTER TABLE ONLY sherlockdb.sites ALTER COLUMN id SET DEFAULT nextval('sherlockdb.sites_id_seq'::regclass);


--
-- Name: snapshots id; Type: DEFAULT; Schema: sherlockdb; Owner: -
--

ALTER TABLE ONLY sherlockdb.snapshots ALTER COLUMN id SET DEFAULT nextval('sherlockdb.snapshots_id_seq'::regclass);


--
-- Name: solid_cable_messages id; Type: DEFAULT; Schema: sherlockdb; Owner: -
--

ALTER TABLE ONLY sherlockdb.solid_cable_messages ALTER COLUMN id SET DEFAULT nextval('sherlockdb.solid_cable_messages_id_seq'::regclass);


--
-- Name: solid_cache_entries id; Type: DEFAULT; Schema: sherlockdb; Owner: -
--

ALTER TABLE ONLY sherlockdb.solid_cache_entries ALTER COLUMN id SET DEFAULT nextval('sherlockdb.solid_cache_entries_id_seq'::regclass);


--
-- Name: solid_queue_batch_executions id; Type: DEFAULT; Schema: sherlockdb; Owner: -
--

ALTER TABLE ONLY sherlockdb.solid_queue_batch_executions ALTER COLUMN id SET DEFAULT nextval('sherlockdb.solid_queue_batch_executions_id_seq'::regclass);


--
-- Name: solid_queue_batches id; Type: DEFAULT; Schema: sherlockdb; Owner: -
--

ALTER TABLE ONLY sherlockdb.solid_queue_batches ALTER COLUMN id SET DEFAULT nextval('sherlockdb.solid_queue_batches_id_seq'::regclass);


--
-- Name: solid_queue_blocked_executions id; Type: DEFAULT; Schema: sherlockdb; Owner: -
--

ALTER TABLE ONLY sherlockdb.solid_queue_blocked_executions ALTER COLUMN id SET DEFAULT nextval('sherlockdb.solid_queue_blocked_executions_id_seq'::regclass);


--
-- Name: solid_queue_claimed_executions id; Type: DEFAULT; Schema: sherlockdb; Owner: -
--

ALTER TABLE ONLY sherlockdb.solid_queue_claimed_executions ALTER COLUMN id SET DEFAULT nextval('sherlockdb.solid_queue_claimed_executions_id_seq'::regclass);


--
-- Name: solid_queue_failed_executions id; Type: DEFAULT; Schema: sherlockdb; Owner: -
--

ALTER TABLE ONLY sherlockdb.solid_queue_failed_executions ALTER COLUMN id SET DEFAULT nextval('sherlockdb.solid_queue_failed_executions_id_seq'::regclass);


--
-- Name: solid_queue_jobs id; Type: DEFAULT; Schema: sherlockdb; Owner: -
--

ALTER TABLE ONLY sherlockdb.solid_queue_jobs ALTER COLUMN id SET DEFAULT nextval('sherlockdb.solid_queue_jobs_id_seq'::regclass);


--
-- Name: solid_queue_pauses id; Type: DEFAULT; Schema: sherlockdb; Owner: -
--

ALTER TABLE ONLY sherlockdb.solid_queue_pauses ALTER COLUMN id SET DEFAULT nextval('sherlockdb.solid_queue_pauses_id_seq'::regclass);


--
-- Name: solid_queue_processes id; Type: DEFAULT; Schema: sherlockdb; Owner: -
--

ALTER TABLE ONLY sherlockdb.solid_queue_processes ALTER COLUMN id SET DEFAULT nextval('sherlockdb.solid_queue_processes_id_seq'::regclass);


--
-- Name: solid_queue_ready_executions id; Type: DEFAULT; Schema: sherlockdb; Owner: -
--

ALTER TABLE ONLY sherlockdb.solid_queue_ready_executions ALTER COLUMN id SET DEFAULT nextval('sherlockdb.solid_queue_ready_executions_id_seq'::regclass);


--
-- Name: solid_queue_recurring_executions id; Type: DEFAULT; Schema: sherlockdb; Owner: -
--

ALTER TABLE ONLY sherlockdb.solid_queue_recurring_executions ALTER COLUMN id SET DEFAULT nextval('sherlockdb.solid_queue_recurring_executions_id_seq'::regclass);


--
-- Name: solid_queue_recurring_tasks id; Type: DEFAULT; Schema: sherlockdb; Owner: -
--

ALTER TABLE ONLY sherlockdb.solid_queue_recurring_tasks ALTER COLUMN id SET DEFAULT nextval('sherlockdb.solid_queue_recurring_tasks_id_seq'::regclass);


--
-- Name: solid_queue_scheduled_executions id; Type: DEFAULT; Schema: sherlockdb; Owner: -
--

ALTER TABLE ONLY sherlockdb.solid_queue_scheduled_executions ALTER COLUMN id SET DEFAULT nextval('sherlockdb.solid_queue_scheduled_executions_id_seq'::regclass);


--
-- Name: solid_queue_semaphores id; Type: DEFAULT; Schema: sherlockdb; Owner: -
--

ALTER TABLE ONLY sherlockdb.solid_queue_semaphores ALTER COLUMN id SET DEFAULT nextval('sherlockdb.solid_queue_semaphores_id_seq'::regclass);


--
-- Name: users id; Type: DEFAULT; Schema: sherlockdb; Owner: -
--

ALTER TABLE ONLY sherlockdb.users ALTER COLUMN id SET DEFAULT nextval('sherlockdb.users_id_seq'::regclass);


--
-- Name: ar_internal_metadata ar_internal_metadata_pkey; Type: CONSTRAINT; Schema: sherlockdb; Owner: -
--

ALTER TABLE ONLY sherlockdb.ar_internal_metadata
    ADD CONSTRAINT ar_internal_metadata_pkey PRIMARY KEY (key);


--
-- Name: connections connections_pkey; Type: CONSTRAINT; Schema: sherlockdb; Owner: -
--

ALTER TABLE ONLY sherlockdb.connections
    ADD CONSTRAINT connections_pkey PRIMARY KEY (id);


--
-- Name: cross_seed_snapshots cross_seed_snapshots_pkey; Type: CONSTRAINT; Schema: sherlockdb; Owner: -
--

ALTER TABLE ONLY sherlockdb.cross_seed_snapshots
    ADD CONSTRAINT cross_seed_snapshots_pkey PRIMARY KEY (id);


--
-- Name: instance_settings instance_settings_pkey; Type: CONSTRAINT; Schema: sherlockdb; Owner: -
--

ALTER TABLE ONLY sherlockdb.instance_settings
    ADD CONSTRAINT instance_settings_pkey PRIMARY KEY (id);


--
-- Name: integration_grants integration_grants_pkey; Type: CONSTRAINT; Schema: sherlockdb; Owner: -
--

ALTER TABLE ONLY sherlockdb.integration_grants
    ADD CONSTRAINT integration_grants_pkey PRIMARY KEY (id);


--
-- Name: integrations integrations_pkey; Type: CONSTRAINT; Schema: sherlockdb; Owner: -
--

ALTER TABLE ONLY sherlockdb.integrations
    ADD CONSTRAINT integrations_pkey PRIMARY KEY (id);


--
-- Name: invites invites_pkey; Type: CONSTRAINT; Schema: sherlockdb; Owner: -
--

ALTER TABLE ONLY sherlockdb.invites
    ADD CONSTRAINT invites_pkey PRIMARY KEY (id);


--
-- Name: pinned_comparisons pinned_comparisons_pkey; Type: CONSTRAINT; Schema: sherlockdb; Owner: -
--

ALTER TABLE ONLY sherlockdb.pinned_comparisons
    ADD CONSTRAINT pinned_comparisons_pkey PRIMARY KEY (id);


--
-- Name: qui_connections qui_connections_pkey; Type: CONSTRAINT; Schema: sherlockdb; Owner: -
--

ALTER TABLE ONLY sherlockdb.qui_connections
    ADD CONSTRAINT qui_connections_pkey PRIMARY KEY (id);


--
-- Name: schema_migrations schema_migrations_pkey; Type: CONSTRAINT; Schema: sherlockdb; Owner: -
--

ALTER TABLE ONLY sherlockdb.schema_migrations
    ADD CONSTRAINT schema_migrations_pkey PRIMARY KEY (version);


--
-- Name: sessions sessions_pkey; Type: CONSTRAINT; Schema: sherlockdb; Owner: -
--

ALTER TABLE ONLY sherlockdb.sessions
    ADD CONSTRAINT sessions_pkey PRIMARY KEY (id);


--
-- Name: site_grants site_grants_pkey; Type: CONSTRAINT; Schema: sherlockdb; Owner: -
--

ALTER TABLE ONLY sherlockdb.site_grants
    ADD CONSTRAINT site_grants_pkey PRIMARY KEY (id);


--
-- Name: sites sites_pkey; Type: CONSTRAINT; Schema: sherlockdb; Owner: -
--

ALTER TABLE ONLY sherlockdb.sites
    ADD CONSTRAINT sites_pkey PRIMARY KEY (id);


--
-- Name: snapshots snapshots_pkey; Type: CONSTRAINT; Schema: sherlockdb; Owner: -
--

ALTER TABLE ONLY sherlockdb.snapshots
    ADD CONSTRAINT snapshots_pkey PRIMARY KEY (id);


--
-- Name: solid_cable_messages solid_cable_messages_pkey; Type: CONSTRAINT; Schema: sherlockdb; Owner: -
--

ALTER TABLE ONLY sherlockdb.solid_cable_messages
    ADD CONSTRAINT solid_cable_messages_pkey PRIMARY KEY (id);


--
-- Name: solid_cache_entries solid_cache_entries_pkey; Type: CONSTRAINT; Schema: sherlockdb; Owner: -
--

ALTER TABLE ONLY sherlockdb.solid_cache_entries
    ADD CONSTRAINT solid_cache_entries_pkey PRIMARY KEY (id);


--
-- Name: solid_queue_batch_executions solid_queue_batch_executions_pkey; Type: CONSTRAINT; Schema: sherlockdb; Owner: -
--

ALTER TABLE ONLY sherlockdb.solid_queue_batch_executions
    ADD CONSTRAINT solid_queue_batch_executions_pkey PRIMARY KEY (id);


--
-- Name: solid_queue_batches solid_queue_batches_pkey; Type: CONSTRAINT; Schema: sherlockdb; Owner: -
--

ALTER TABLE ONLY sherlockdb.solid_queue_batches
    ADD CONSTRAINT solid_queue_batches_pkey PRIMARY KEY (id);


--
-- Name: solid_queue_blocked_executions solid_queue_blocked_executions_pkey; Type: CONSTRAINT; Schema: sherlockdb; Owner: -
--

ALTER TABLE ONLY sherlockdb.solid_queue_blocked_executions
    ADD CONSTRAINT solid_queue_blocked_executions_pkey PRIMARY KEY (id);


--
-- Name: solid_queue_claimed_executions solid_queue_claimed_executions_pkey; Type: CONSTRAINT; Schema: sherlockdb; Owner: -
--

ALTER TABLE ONLY sherlockdb.solid_queue_claimed_executions
    ADD CONSTRAINT solid_queue_claimed_executions_pkey PRIMARY KEY (id);


--
-- Name: solid_queue_failed_executions solid_queue_failed_executions_pkey; Type: CONSTRAINT; Schema: sherlockdb; Owner: -
--

ALTER TABLE ONLY sherlockdb.solid_queue_failed_executions
    ADD CONSTRAINT solid_queue_failed_executions_pkey PRIMARY KEY (id);


--
-- Name: solid_queue_jobs solid_queue_jobs_pkey; Type: CONSTRAINT; Schema: sherlockdb; Owner: -
--

ALTER TABLE ONLY sherlockdb.solid_queue_jobs
    ADD CONSTRAINT solid_queue_jobs_pkey PRIMARY KEY (id);


--
-- Name: solid_queue_pauses solid_queue_pauses_pkey; Type: CONSTRAINT; Schema: sherlockdb; Owner: -
--

ALTER TABLE ONLY sherlockdb.solid_queue_pauses
    ADD CONSTRAINT solid_queue_pauses_pkey PRIMARY KEY (id);


--
-- Name: solid_queue_processes solid_queue_processes_pkey; Type: CONSTRAINT; Schema: sherlockdb; Owner: -
--

ALTER TABLE ONLY sherlockdb.solid_queue_processes
    ADD CONSTRAINT solid_queue_processes_pkey PRIMARY KEY (id);


--
-- Name: solid_queue_ready_executions solid_queue_ready_executions_pkey; Type: CONSTRAINT; Schema: sherlockdb; Owner: -
--

ALTER TABLE ONLY sherlockdb.solid_queue_ready_executions
    ADD CONSTRAINT solid_queue_ready_executions_pkey PRIMARY KEY (id);


--
-- Name: solid_queue_recurring_executions solid_queue_recurring_executions_pkey; Type: CONSTRAINT; Schema: sherlockdb; Owner: -
--

ALTER TABLE ONLY sherlockdb.solid_queue_recurring_executions
    ADD CONSTRAINT solid_queue_recurring_executions_pkey PRIMARY KEY (id);


--
-- Name: solid_queue_recurring_tasks solid_queue_recurring_tasks_pkey; Type: CONSTRAINT; Schema: sherlockdb; Owner: -
--

ALTER TABLE ONLY sherlockdb.solid_queue_recurring_tasks
    ADD CONSTRAINT solid_queue_recurring_tasks_pkey PRIMARY KEY (id);


--
-- Name: solid_queue_scheduled_executions solid_queue_scheduled_executions_pkey; Type: CONSTRAINT; Schema: sherlockdb; Owner: -
--

ALTER TABLE ONLY sherlockdb.solid_queue_scheduled_executions
    ADD CONSTRAINT solid_queue_scheduled_executions_pkey PRIMARY KEY (id);


--
-- Name: solid_queue_semaphores solid_queue_semaphores_pkey; Type: CONSTRAINT; Schema: sherlockdb; Owner: -
--

ALTER TABLE ONLY sherlockdb.solid_queue_semaphores
    ADD CONSTRAINT solid_queue_semaphores_pkey PRIMARY KEY (id);


--
-- Name: users users_pkey; Type: CONSTRAINT; Schema: sherlockdb; Owner: -
--

ALTER TABLE ONLY sherlockdb.users
    ADD CONSTRAINT users_pkey PRIMARY KEY (id);


--
-- Name: index_connections_on_profile_code; Type: INDEX; Schema: sherlockdb; Owner: -
--

CREATE UNIQUE INDEX index_connections_on_profile_code ON sherlockdb.connections USING btree (profile_code);


--
-- Name: index_connections_on_site_id; Type: INDEX; Schema: sherlockdb; Owner: -
--

CREATE INDEX index_connections_on_site_id ON sherlockdb.connections USING btree (site_id);


--
-- Name: index_connections_on_user_id; Type: INDEX; Schema: sherlockdb; Owner: -
--

CREATE INDEX index_connections_on_user_id ON sherlockdb.connections USING btree (user_id);


--
-- Name: index_connections_on_user_id_and_site_id; Type: INDEX; Schema: sherlockdb; Owner: -
--

CREATE UNIQUE INDEX index_connections_on_user_id_and_site_id ON sherlockdb.connections USING btree (user_id, site_id);


--
-- Name: index_cross_seed_snapshots_on_connection_id_and_created_at; Type: INDEX; Schema: sherlockdb; Owner: -
--

CREATE INDEX index_cross_seed_snapshots_on_connection_id_and_created_at ON sherlockdb.cross_seed_snapshots USING btree (connection_id, created_at);


--
-- Name: index_instance_settings_single_row; Type: INDEX; Schema: sherlockdb; Owner: -
--

CREATE UNIQUE INDEX index_instance_settings_single_row ON sherlockdb.instance_settings USING btree ((true));


--
-- Name: index_integration_grants_on_integration_id; Type: INDEX; Schema: sherlockdb; Owner: -
--

CREATE INDEX index_integration_grants_on_integration_id ON sherlockdb.integration_grants USING btree (integration_id);


--
-- Name: index_integration_grants_on_user_id_and_integration_id; Type: INDEX; Schema: sherlockdb; Owner: -
--

CREATE UNIQUE INDEX index_integration_grants_on_user_id_and_integration_id ON sherlockdb.integration_grants USING btree (user_id, integration_id);


--
-- Name: index_integrations_on_slug; Type: INDEX; Schema: sherlockdb; Owner: -
--

CREATE UNIQUE INDEX index_integrations_on_slug ON sherlockdb.integrations USING btree (slug);


--
-- Name: index_invites_on_code; Type: INDEX; Schema: sherlockdb; Owner: -
--

CREATE UNIQUE INDEX index_invites_on_code ON sherlockdb.invites USING btree (code);


--
-- Name: index_invites_on_created_by_user_id; Type: INDEX; Schema: sherlockdb; Owner: -
--

CREATE INDEX index_invites_on_created_by_user_id ON sherlockdb.invites USING btree (created_by_user_id);


--
-- Name: index_invites_on_site_id; Type: INDEX; Schema: sherlockdb; Owner: -
--

CREATE INDEX index_invites_on_site_id ON sherlockdb.invites USING btree (site_id);


--
-- Name: index_pinned_comparisons_uniquely; Type: INDEX; Schema: sherlockdb; Owner: -
--

CREATE UNIQUE INDEX index_pinned_comparisons_uniquely ON sherlockdb.pinned_comparisons USING btree (user_id, stat, range, is_per_interval, connection_ids);


--
-- Name: index_qui_connections_on_user_id_and_url; Type: INDEX; Schema: sherlockdb; Owner: -
--

CREATE UNIQUE INDEX index_qui_connections_on_user_id_and_url ON sherlockdb.qui_connections USING btree (user_id, url);


--
-- Name: index_sessions_on_user_id; Type: INDEX; Schema: sherlockdb; Owner: -
--

CREATE INDEX index_sessions_on_user_id ON sherlockdb.sessions USING btree (user_id);


--
-- Name: index_site_grants_on_site_id; Type: INDEX; Schema: sherlockdb; Owner: -
--

CREATE INDEX index_site_grants_on_site_id ON sherlockdb.site_grants USING btree (site_id);


--
-- Name: index_site_grants_on_user_id_and_site_id; Type: INDEX; Schema: sherlockdb; Owner: -
--

CREATE UNIQUE INDEX index_site_grants_on_user_id_and_site_id ON sherlockdb.site_grants USING btree (user_id, site_id);


--
-- Name: index_sites_on_slug; Type: INDEX; Schema: sherlockdb; Owner: -
--

CREATE UNIQUE INDEX index_sites_on_slug ON sherlockdb.sites USING btree (slug);


--
-- Name: index_snapshots_on_connection_id_and_created_at; Type: INDEX; Schema: sherlockdb; Owner: -
--

CREATE INDEX index_snapshots_on_connection_id_and_created_at ON sherlockdb.snapshots USING btree (connection_id, created_at);


--
-- Name: index_solid_cable_messages_on_channel_hash; Type: INDEX; Schema: sherlockdb; Owner: -
--

CREATE INDEX index_solid_cable_messages_on_channel_hash ON sherlockdb.solid_cable_messages USING btree (channel_hash);


--
-- Name: index_solid_cable_messages_on_created_at; Type: INDEX; Schema: sherlockdb; Owner: -
--

CREATE INDEX index_solid_cable_messages_on_created_at ON sherlockdb.solid_cable_messages USING btree (created_at);


--
-- Name: index_solid_cache_entries_on_byte_size; Type: INDEX; Schema: sherlockdb; Owner: -
--

CREATE INDEX index_solid_cache_entries_on_byte_size ON sherlockdb.solid_cache_entries USING btree (byte_size);


--
-- Name: index_solid_cache_entries_on_key_hash; Type: INDEX; Schema: sherlockdb; Owner: -
--

CREATE UNIQUE INDEX index_solid_cache_entries_on_key_hash ON sherlockdb.solid_cache_entries USING btree (key_hash);


--
-- Name: index_solid_cache_entries_on_key_hash_and_byte_size; Type: INDEX; Schema: sherlockdb; Owner: -
--

CREATE INDEX index_solid_cache_entries_on_key_hash_and_byte_size ON sherlockdb.solid_cache_entries USING btree (key_hash, byte_size);


--
-- Name: index_solid_queue_batch_executions_on_batch_id; Type: INDEX; Schema: sherlockdb; Owner: -
--

CREATE INDEX index_solid_queue_batch_executions_on_batch_id ON sherlockdb.solid_queue_batch_executions USING btree (batch_id);


--
-- Name: index_solid_queue_batch_executions_on_job_id; Type: INDEX; Schema: sherlockdb; Owner: -
--

CREATE UNIQUE INDEX index_solid_queue_batch_executions_on_job_id ON sherlockdb.solid_queue_batch_executions USING btree (job_id);


--
-- Name: index_solid_queue_batches_on_active_job_batch_id; Type: INDEX; Schema: sherlockdb; Owner: -
--

CREATE UNIQUE INDEX index_solid_queue_batches_on_active_job_batch_id ON sherlockdb.solid_queue_batches USING btree (active_job_batch_id);


--
-- Name: index_solid_queue_batches_on_finished_at; Type: INDEX; Schema: sherlockdb; Owner: -
--

CREATE INDEX index_solid_queue_batches_on_finished_at ON sherlockdb.solid_queue_batches USING btree (finished_at);


--
-- Name: index_solid_queue_blocked_executions_for_maintenance; Type: INDEX; Schema: sherlockdb; Owner: -
--

CREATE INDEX index_solid_queue_blocked_executions_for_maintenance ON sherlockdb.solid_queue_blocked_executions USING btree (expires_at, concurrency_key);


--
-- Name: index_solid_queue_blocked_executions_for_release; Type: INDEX; Schema: sherlockdb; Owner: -
--

CREATE INDEX index_solid_queue_blocked_executions_for_release ON sherlockdb.solid_queue_blocked_executions USING btree (concurrency_key, priority, job_id);


--
-- Name: index_solid_queue_blocked_executions_on_job_id; Type: INDEX; Schema: sherlockdb; Owner: -
--

CREATE UNIQUE INDEX index_solid_queue_blocked_executions_on_job_id ON sherlockdb.solid_queue_blocked_executions USING btree (job_id);


--
-- Name: index_solid_queue_claimed_executions_on_job_id; Type: INDEX; Schema: sherlockdb; Owner: -
--

CREATE UNIQUE INDEX index_solid_queue_claimed_executions_on_job_id ON sherlockdb.solid_queue_claimed_executions USING btree (job_id);


--
-- Name: index_solid_queue_claimed_executions_on_process_id_and_job_id; Type: INDEX; Schema: sherlockdb; Owner: -
--

CREATE INDEX index_solid_queue_claimed_executions_on_process_id_and_job_id ON sherlockdb.solid_queue_claimed_executions USING btree (process_id, job_id);


--
-- Name: index_solid_queue_dispatch_all; Type: INDEX; Schema: sherlockdb; Owner: -
--

CREATE INDEX index_solid_queue_dispatch_all ON sherlockdb.solid_queue_scheduled_executions USING btree (scheduled_at, priority, job_id);


--
-- Name: index_solid_queue_failed_executions_on_job_id; Type: INDEX; Schema: sherlockdb; Owner: -
--

CREATE UNIQUE INDEX index_solid_queue_failed_executions_on_job_id ON sherlockdb.solid_queue_failed_executions USING btree (job_id);


--
-- Name: index_solid_queue_jobs_for_alerting; Type: INDEX; Schema: sherlockdb; Owner: -
--

CREATE INDEX index_solid_queue_jobs_for_alerting ON sherlockdb.solid_queue_jobs USING btree (scheduled_at, finished_at);


--
-- Name: index_solid_queue_jobs_for_filtering; Type: INDEX; Schema: sherlockdb; Owner: -
--

CREATE INDEX index_solid_queue_jobs_for_filtering ON sherlockdb.solid_queue_jobs USING btree (queue_name, finished_at);


--
-- Name: index_solid_queue_jobs_on_active_job_id; Type: INDEX; Schema: sherlockdb; Owner: -
--

CREATE INDEX index_solid_queue_jobs_on_active_job_id ON sherlockdb.solid_queue_jobs USING btree (active_job_id);


--
-- Name: index_solid_queue_jobs_on_batch_id; Type: INDEX; Schema: sherlockdb; Owner: -
--

CREATE INDEX index_solid_queue_jobs_on_batch_id ON sherlockdb.solid_queue_jobs USING btree (batch_id);


--
-- Name: index_solid_queue_jobs_on_class_name; Type: INDEX; Schema: sherlockdb; Owner: -
--

CREATE INDEX index_solid_queue_jobs_on_class_name ON sherlockdb.solid_queue_jobs USING btree (class_name);


--
-- Name: index_solid_queue_jobs_on_finished_at; Type: INDEX; Schema: sherlockdb; Owner: -
--

CREATE INDEX index_solid_queue_jobs_on_finished_at ON sherlockdb.solid_queue_jobs USING btree (finished_at);


--
-- Name: index_solid_queue_pauses_on_queue_name; Type: INDEX; Schema: sherlockdb; Owner: -
--

CREATE UNIQUE INDEX index_solid_queue_pauses_on_queue_name ON sherlockdb.solid_queue_pauses USING btree (queue_name);


--
-- Name: index_solid_queue_poll_all; Type: INDEX; Schema: sherlockdb; Owner: -
--

CREATE INDEX index_solid_queue_poll_all ON sherlockdb.solid_queue_ready_executions USING btree (priority, job_id);


--
-- Name: index_solid_queue_poll_by_queue; Type: INDEX; Schema: sherlockdb; Owner: -
--

CREATE INDEX index_solid_queue_poll_by_queue ON sherlockdb.solid_queue_ready_executions USING btree (queue_name, priority, job_id);


--
-- Name: index_solid_queue_processes_on_last_heartbeat_at; Type: INDEX; Schema: sherlockdb; Owner: -
--

CREATE INDEX index_solid_queue_processes_on_last_heartbeat_at ON sherlockdb.solid_queue_processes USING btree (last_heartbeat_at);


--
-- Name: index_solid_queue_processes_on_name_and_supervisor_id; Type: INDEX; Schema: sherlockdb; Owner: -
--

CREATE UNIQUE INDEX index_solid_queue_processes_on_name_and_supervisor_id ON sherlockdb.solid_queue_processes USING btree (name, supervisor_id);


--
-- Name: index_solid_queue_processes_on_supervisor_id; Type: INDEX; Schema: sherlockdb; Owner: -
--

CREATE INDEX index_solid_queue_processes_on_supervisor_id ON sherlockdb.solid_queue_processes USING btree (supervisor_id);


--
-- Name: index_solid_queue_ready_executions_on_job_id; Type: INDEX; Schema: sherlockdb; Owner: -
--

CREATE UNIQUE INDEX index_solid_queue_ready_executions_on_job_id ON sherlockdb.solid_queue_ready_executions USING btree (job_id);


--
-- Name: index_solid_queue_recurring_executions_on_job_id; Type: INDEX; Schema: sherlockdb; Owner: -
--

CREATE UNIQUE INDEX index_solid_queue_recurring_executions_on_job_id ON sherlockdb.solid_queue_recurring_executions USING btree (job_id);


--
-- Name: index_solid_queue_recurring_executions_on_task_key_and_run_at; Type: INDEX; Schema: sherlockdb; Owner: -
--

CREATE UNIQUE INDEX index_solid_queue_recurring_executions_on_task_key_and_run_at ON sherlockdb.solid_queue_recurring_executions USING btree (task_key, run_at);


--
-- Name: index_solid_queue_recurring_tasks_on_key; Type: INDEX; Schema: sherlockdb; Owner: -
--

CREATE UNIQUE INDEX index_solid_queue_recurring_tasks_on_key ON sherlockdb.solid_queue_recurring_tasks USING btree (key);


--
-- Name: index_solid_queue_recurring_tasks_on_static; Type: INDEX; Schema: sherlockdb; Owner: -
--

CREATE INDEX index_solid_queue_recurring_tasks_on_static ON sherlockdb.solid_queue_recurring_tasks USING btree (static);


--
-- Name: index_solid_queue_scheduled_executions_on_job_id; Type: INDEX; Schema: sherlockdb; Owner: -
--

CREATE UNIQUE INDEX index_solid_queue_scheduled_executions_on_job_id ON sherlockdb.solid_queue_scheduled_executions USING btree (job_id);


--
-- Name: index_solid_queue_semaphores_on_expires_at; Type: INDEX; Schema: sherlockdb; Owner: -
--

CREATE INDEX index_solid_queue_semaphores_on_expires_at ON sherlockdb.solid_queue_semaphores USING btree (expires_at);


--
-- Name: index_solid_queue_semaphores_on_key; Type: INDEX; Schema: sherlockdb; Owner: -
--

CREATE UNIQUE INDEX index_solid_queue_semaphores_on_key ON sherlockdb.solid_queue_semaphores USING btree (key);


--
-- Name: index_solid_queue_semaphores_on_key_and_value; Type: INDEX; Schema: sherlockdb; Owner: -
--

CREATE INDEX index_solid_queue_semaphores_on_key_and_value ON sherlockdb.solid_queue_semaphores USING btree (key, value);


--
-- Name: index_users_on_invite_id; Type: INDEX; Schema: sherlockdb; Owner: -
--

CREATE INDEX index_users_on_invite_id ON sherlockdb.users USING btree (invite_id);


--
-- Name: index_users_on_invited_by_user_id; Type: INDEX; Schema: sherlockdb; Owner: -
--

CREATE INDEX index_users_on_invited_by_user_id ON sherlockdb.users USING btree (invited_by_user_id);


--
-- Name: index_users_on_metrics_token_digest; Type: INDEX; Schema: sherlockdb; Owner: -
--

CREATE UNIQUE INDEX index_users_on_metrics_token_digest ON sherlockdb.users USING btree (metrics_token_digest);


--
-- Name: index_users_on_username; Type: INDEX; Schema: sherlockdb; Owner: -
--

CREATE UNIQUE INDEX index_users_on_username ON sherlockdb.users USING btree (username);


--
-- Name: connections set_updated_at_on_connections; Type: TRIGGER; Schema: sherlockdb; Owner: -
--

CREATE TRIGGER set_updated_at_on_connections BEFORE UPDATE ON sherlockdb.connections FOR EACH ROW EXECUTE FUNCTION sherlockdb.set_updated_at();


--
-- Name: cross_seed_snapshots set_updated_at_on_cross_seed_snapshots; Type: TRIGGER; Schema: sherlockdb; Owner: -
--

CREATE TRIGGER set_updated_at_on_cross_seed_snapshots BEFORE UPDATE ON sherlockdb.cross_seed_snapshots FOR EACH ROW EXECUTE FUNCTION sherlockdb.set_updated_at();


--
-- Name: instance_settings set_updated_at_on_instance_settings; Type: TRIGGER; Schema: sherlockdb; Owner: -
--

CREATE TRIGGER set_updated_at_on_instance_settings BEFORE UPDATE ON sherlockdb.instance_settings FOR EACH ROW EXECUTE FUNCTION sherlockdb.set_updated_at();


--
-- Name: integration_grants set_updated_at_on_integration_grants; Type: TRIGGER; Schema: sherlockdb; Owner: -
--

CREATE TRIGGER set_updated_at_on_integration_grants BEFORE UPDATE ON sherlockdb.integration_grants FOR EACH ROW EXECUTE FUNCTION sherlockdb.set_updated_at();


--
-- Name: integrations set_updated_at_on_integrations; Type: TRIGGER; Schema: sherlockdb; Owner: -
--

CREATE TRIGGER set_updated_at_on_integrations BEFORE UPDATE ON sherlockdb.integrations FOR EACH ROW EXECUTE FUNCTION sherlockdb.set_updated_at();


--
-- Name: invites set_updated_at_on_invites; Type: TRIGGER; Schema: sherlockdb; Owner: -
--

CREATE TRIGGER set_updated_at_on_invites BEFORE UPDATE ON sherlockdb.invites FOR EACH ROW EXECUTE FUNCTION sherlockdb.set_updated_at();


--
-- Name: pinned_comparisons set_updated_at_on_pinned_comparisons; Type: TRIGGER; Schema: sherlockdb; Owner: -
--

CREATE TRIGGER set_updated_at_on_pinned_comparisons BEFORE UPDATE ON sherlockdb.pinned_comparisons FOR EACH ROW EXECUTE FUNCTION sherlockdb.set_updated_at();


--
-- Name: qui_connections set_updated_at_on_qui_connections; Type: TRIGGER; Schema: sherlockdb; Owner: -
--

CREATE TRIGGER set_updated_at_on_qui_connections BEFORE UPDATE ON sherlockdb.qui_connections FOR EACH ROW EXECUTE FUNCTION sherlockdb.set_updated_at();


--
-- Name: sessions set_updated_at_on_sessions; Type: TRIGGER; Schema: sherlockdb; Owner: -
--

CREATE TRIGGER set_updated_at_on_sessions BEFORE UPDATE ON sherlockdb.sessions FOR EACH ROW EXECUTE FUNCTION sherlockdb.set_updated_at();


--
-- Name: site_grants set_updated_at_on_site_grants; Type: TRIGGER; Schema: sherlockdb; Owner: -
--

CREATE TRIGGER set_updated_at_on_site_grants BEFORE UPDATE ON sherlockdb.site_grants FOR EACH ROW EXECUTE FUNCTION sherlockdb.set_updated_at();


--
-- Name: sites set_updated_at_on_sites; Type: TRIGGER; Schema: sherlockdb; Owner: -
--

CREATE TRIGGER set_updated_at_on_sites BEFORE UPDATE ON sherlockdb.sites FOR EACH ROW EXECUTE FUNCTION sherlockdb.set_updated_at();


--
-- Name: snapshots set_updated_at_on_snapshots; Type: TRIGGER; Schema: sherlockdb; Owner: -
--

CREATE TRIGGER set_updated_at_on_snapshots BEFORE UPDATE ON sherlockdb.snapshots FOR EACH ROW EXECUTE FUNCTION sherlockdb.set_updated_at();


--
-- Name: users set_updated_at_on_users; Type: TRIGGER; Schema: sherlockdb; Owner: -
--

CREATE TRIGGER set_updated_at_on_users BEFORE UPDATE ON sherlockdb.users FOR EACH ROW EXECUTE FUNCTION sherlockdb.set_updated_at();


--
-- Name: qui_connections fk_rails_1aecf60c0d; Type: FK CONSTRAINT; Schema: sherlockdb; Owner: -
--

ALTER TABLE ONLY sherlockdb.qui_connections
    ADD CONSTRAINT fk_rails_1aecf60c0d FOREIGN KEY (user_id) REFERENCES sherlockdb.users(id) ON DELETE CASCADE;


--
-- Name: cross_seed_snapshots fk_rails_1e91ec2f0a; Type: FK CONSTRAINT; Schema: sherlockdb; Owner: -
--

ALTER TABLE ONLY sherlockdb.cross_seed_snapshots
    ADD CONSTRAINT fk_rails_1e91ec2f0a FOREIGN KEY (connection_id) REFERENCES sherlockdb.connections(id) ON DELETE CASCADE;


--
-- Name: solid_queue_recurring_executions fk_rails_318a5533ed; Type: FK CONSTRAINT; Schema: sherlockdb; Owner: -
--

ALTER TABLE ONLY sherlockdb.solid_queue_recurring_executions
    ADD CONSTRAINT fk_rails_318a5533ed FOREIGN KEY (job_id) REFERENCES sherlockdb.solid_queue_jobs(id) ON DELETE CASCADE;


--
-- Name: solid_queue_failed_executions fk_rails_39bbc7a631; Type: FK CONSTRAINT; Schema: sherlockdb; Owner: -
--

ALTER TABLE ONLY sherlockdb.solid_queue_failed_executions
    ADD CONSTRAINT fk_rails_39bbc7a631 FOREIGN KEY (job_id) REFERENCES sherlockdb.solid_queue_jobs(id) ON DELETE CASCADE;


--
-- Name: snapshots fk_rails_3e4ac0b1f1; Type: FK CONSTRAINT; Schema: sherlockdb; Owner: -
--

ALTER TABLE ONLY sherlockdb.snapshots
    ADD CONSTRAINT fk_rails_3e4ac0b1f1 FOREIGN KEY (connection_id) REFERENCES sherlockdb.connections(id) ON DELETE CASCADE;

--
-- Name: snapshots fk_rails_bdd9e6b7fc; Type: FK CONSTRAINT; Schema: sherlockdb; Owner: -
--

ALTER TABLE ONLY sherlockdb.snapshots
    ADD CONSTRAINT fk_rails_bdd9e6b7fc FOREIGN KEY (created_by_user_id) REFERENCES sherlockdb.users(id) ON DELETE SET NULL;


--
-- Name: solid_queue_blocked_executions fk_rails_4cd34e2228; Type: FK CONSTRAINT; Schema: sherlockdb; Owner: -
--

ALTER TABLE ONLY sherlockdb.solid_queue_blocked_executions
    ADD CONSTRAINT fk_rails_4cd34e2228 FOREIGN KEY (job_id) REFERENCES sherlockdb.solid_queue_jobs(id) ON DELETE CASCADE;


--
-- Name: invites fk_rails_579e67f9df; Type: FK CONSTRAINT; Schema: sherlockdb; Owner: -
--

ALTER TABLE ONLY sherlockdb.invites
    ADD CONSTRAINT fk_rails_579e67f9df FOREIGN KEY (created_by_user_id) REFERENCES sherlockdb.users(id) ON DELETE CASCADE;


--
-- Name: sessions fk_rails_758836b4f0; Type: FK CONSTRAINT; Schema: sherlockdb; Owner: -
--

ALTER TABLE ONLY sherlockdb.sessions
    ADD CONSTRAINT fk_rails_758836b4f0 FOREIGN KEY (user_id) REFERENCES sherlockdb.users(id) ON DELETE CASCADE;


--
-- Name: integration_grants fk_rails_7a9867fbd6; Type: FK CONSTRAINT; Schema: sherlockdb; Owner: -
--

ALTER TABLE ONLY sherlockdb.integration_grants
    ADD CONSTRAINT fk_rails_7a9867fbd6 FOREIGN KEY (integration_id) REFERENCES sherlockdb.integrations(id) ON DELETE CASCADE;


--
-- Name: solid_queue_batch_executions fk_rails_7c5e073422; Type: FK CONSTRAINT; Schema: sherlockdb; Owner: -
--

ALTER TABLE ONLY sherlockdb.solid_queue_batch_executions
    ADD CONSTRAINT fk_rails_7c5e073422 FOREIGN KEY (batch_id) REFERENCES sherlockdb.solid_queue_batches(id) ON DELETE CASCADE;


--
-- Name: solid_queue_ready_executions fk_rails_81fcbd66af; Type: FK CONSTRAINT; Schema: sherlockdb; Owner: -
--

ALTER TABLE ONLY sherlockdb.solid_queue_ready_executions
    ADD CONSTRAINT fk_rails_81fcbd66af FOREIGN KEY (job_id) REFERENCES sherlockdb.solid_queue_jobs(id) ON DELETE CASCADE;


--
-- Name: connections fk_rails_82c278253d; Type: FK CONSTRAINT; Schema: sherlockdb; Owner: -
--

ALTER TABLE ONLY sherlockdb.connections
    ADD CONSTRAINT fk_rails_82c278253d FOREIGN KEY (user_id) REFERENCES sherlockdb.users(id) ON DELETE CASCADE;


--
-- Name: site_grants fk_rails_87e9340b31; Type: FK CONSTRAINT; Schema: sherlockdb; Owner: -
--

ALTER TABLE ONLY sherlockdb.site_grants
    ADD CONSTRAINT fk_rails_87e9340b31 FOREIGN KEY (user_id) REFERENCES sherlockdb.users(id) ON DELETE CASCADE;


--
-- Name: users fk_rails_8fb2a43e88; Type: FK CONSTRAINT; Schema: sherlockdb; Owner: -
--

ALTER TABLE ONLY sherlockdb.users
    ADD CONSTRAINT fk_rails_8fb2a43e88 FOREIGN KEY (invite_id) REFERENCES sherlockdb.invites(id) ON DELETE SET NULL;


--
-- Name: pinned_comparisons fk_rails_97e18befe2; Type: FK CONSTRAINT; Schema: sherlockdb; Owner: -
--

ALTER TABLE ONLY sherlockdb.pinned_comparisons
    ADD CONSTRAINT fk_rails_97e18befe2 FOREIGN KEY (user_id) REFERENCES sherlockdb.users(id) ON DELETE CASCADE;


--
-- Name: solid_queue_claimed_executions fk_rails_9cfe4d4944; Type: FK CONSTRAINT; Schema: sherlockdb; Owner: -
--

ALTER TABLE ONLY sherlockdb.solid_queue_claimed_executions
    ADD CONSTRAINT fk_rails_9cfe4d4944 FOREIGN KEY (job_id) REFERENCES sherlockdb.solid_queue_jobs(id) ON DELETE CASCADE;


--
-- Name: connections fk_rails_ae6507168e; Type: FK CONSTRAINT; Schema: sherlockdb; Owner: -
--

ALTER TABLE ONLY sherlockdb.connections
    ADD CONSTRAINT fk_rails_ae6507168e FOREIGN KEY (site_id) REFERENCES sherlockdb.sites(id) ON DELETE RESTRICT;


--
-- Name: users fk_rails_bc76119071; Type: FK CONSTRAINT; Schema: sherlockdb; Owner: -
--

ALTER TABLE ONLY sherlockdb.users
    ADD CONSTRAINT fk_rails_bc76119071 FOREIGN KEY (invited_by_user_id) REFERENCES sherlockdb.users(id) ON DELETE SET NULL;


--
-- Name: solid_queue_batch_executions fk_rails_bc9f981155; Type: FK CONSTRAINT; Schema: sherlockdb; Owner: -
--

ALTER TABLE ONLY sherlockdb.solid_queue_batch_executions
    ADD CONSTRAINT fk_rails_bc9f981155 FOREIGN KEY (job_id) REFERENCES sherlockdb.solid_queue_jobs(id) ON DELETE CASCADE;


--
-- Name: solid_queue_scheduled_executions fk_rails_c4316f352d; Type: FK CONSTRAINT; Schema: sherlockdb; Owner: -
--

ALTER TABLE ONLY sherlockdb.solid_queue_scheduled_executions
    ADD CONSTRAINT fk_rails_c4316f352d FOREIGN KEY (job_id) REFERENCES sherlockdb.solid_queue_jobs(id) ON DELETE CASCADE;


--
-- Name: invites fk_rails_d1080486af; Type: FK CONSTRAINT; Schema: sherlockdb; Owner: -
--

ALTER TABLE ONLY sherlockdb.invites
    ADD CONSTRAINT fk_rails_d1080486af FOREIGN KEY (site_id) REFERENCES sherlockdb.sites(id) ON DELETE RESTRICT;


--
-- Name: integration_grants fk_rails_eb17061cf1; Type: FK CONSTRAINT; Schema: sherlockdb; Owner: -
--

ALTER TABLE ONLY sherlockdb.integration_grants
    ADD CONSTRAINT fk_rails_eb17061cf1 FOREIGN KEY (user_id) REFERENCES sherlockdb.users(id) ON DELETE CASCADE;


--
-- Name: site_grants fk_rails_f260c83edf; Type: FK CONSTRAINT; Schema: sherlockdb; Owner: -
--

ALTER TABLE ONLY sherlockdb.site_grants
    ADD CONSTRAINT fk_rails_f260c83edf FOREIGN KEY (site_id) REFERENCES sherlockdb.sites(id) ON DELETE CASCADE;


--
-- PostgreSQL database dump complete
--

SET search_path TO sherlockdb;

INSERT INTO "schema_migrations" (version) VALUES
('20261104140000'),
('20261104130000'),
('20261028144152'),
('20261028105602'),
('20261027213858'),
('20261027110623'),
('20261026220011'),
('20261026212246'),
('20261026200602'),
('20261026200601'),
('20261026200600'),
('20261026200559'),
('20261025145357'),
('20261025145356'),
('20261025141046'),
('20261025135614'),
('20261025134743'),
('20261025134742'),
('20261025131228'),
('20261025131227'),
('20261025122117'),
('20261025121722'),
('20261025121651'),
('20261025121303'),
('20261025120723'),
('20261025115851'),
('20261025103328'),
('20261025103326'),
('20261025103325'),
('20261025102953'),
('20261025100909'),
('20261024193447'),
('20261024192847'),
('20261024192614'),
('20261024192215'),
('20261024163838'),
('20261024163640'),
('20261024161504'),
('20261024160845'),
('20261024101329'),
('20261024083226'),
('20261023183243'),
('20261023183242'),
('20261023183241'),
('20261023183240'),
('20261023183231'),
('20261023183230'),
('20261023182838'),
('20261023182812');
