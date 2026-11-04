-- The sherlockdb schema must exist before the first migration, because schema_migrations is created
-- in it. Databases loaded from db/schema.rb (test, db:prepare on a new database) get it from the
-- create_schema line Rails dumps there. The search path is only for raw psql sessions; Rails sets
-- schema_search_path per connection.
CREATE SCHEMA IF NOT EXISTS sherlockdb AUTHORIZATION sherlockdb_develop_write;
ALTER ROLE sherlockdb_develop_write SET search_path = 'sherlockdb', 'public';
