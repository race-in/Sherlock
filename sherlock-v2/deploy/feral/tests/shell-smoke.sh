#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
INSTALL="$ROOT/deploy/feral/install.sh"
CONTROL="$ROOT/deploy/feral/control.sh"
BOOTSTRAP="$ROOT/deploy/feral/bootstrap-runtime.sh"
DATABASE="$ROOT/config/database.yml"

bash -n "$INSTALL"
bash -n "$CONTROL"
bash -n "$ROOT/deploy/feral/diagnose.sh"
bash -n "$BOOTSTRAP"
ruby -c "$ROOT/deploy/feral/puma.rb"

grep -q 'VERSION_ID:-}.*9' "$INSTALL"
grep -q 'OpenSSL::OPENSSL_VERSION' "$INSTALL"
grep -q 'production.yml.enc' "$INSTALL"
grep -q 'PostgreSQL 16.15' "$BOOTSTRAP"
grep -q 'src/bin/psql' "$BOOTSTRAP"
grep -q 'psql.*self-test' "$BOOTSTRAP"
grep -q 'command -v psql' "$INSTALL"
grep -q 'PGSSLMODE=.*require' "$INSTALL"
grep -q 'CREATE SCHEMA IF NOT EXISTS sherlockdb' "$INSTALL"
grep -q 'has_schema_privilege' "$INSTALL"
grep -q 'OpenSSL 3.5.9' "$BOOTSTRAP"
grep -q '^NODE_VERSION=22.21.1$' "$BOOTSTRAP"
grep -q 'linux-x64-glibc-217' "$BOOTSTRAP"
grep -q 'rustc 1.89.0' "$BOOTSTRAP"
grep -q 'libclang -v 14.0.6' "$BOOTSTRAP"
grep -q 'Gem::Version.new("3.2.0")' "$INSTALL"
grep -q 'command -v cargo' "$INSTALL"
grep -q 'LIBCLANG_PATH' "$INSTALL"
grep -q 'RBCONFIG_CPPFLAGS=' "$INSTALL"
grep -q 'BINDGEN_EXTRA_CLANG_ARGS=' "$INSTALL"
grep -q 'export BINDGEN_EXTRA_CLANG_ARGS' "$INSTALL"
grep -q 'GCC_INCLUDE=.*gcc -print-file-name=include' "$INSTALL"
grep -q 'GCC_FIXED_INCLUDE=.*gcc -print-file-name=include-fixed' "$INSTALL"
grep -q 'GCC_FIXED_INCLUDE.*limits.h' "$INSTALL"
! grep -q 'BUNDLE_FORCE_RUBY_PLATFORM=true' "$INSTALL"
grep -q 'gem "pg", "~> 1.1", force_ruby_platform: true' "$ROOT/Gemfile"
grep -q 'gem "nokogiri", "~> 1.19.5", force_ruby_platform: true' "$ROOT/Gemfile"
grep -q 'gem "prometheus-client-mmap", "~> 1.7.2", force_ruby_platform: true' "$ROOT/Gemfile"
grep -q 'prometheus-client-mmap (~> 1.7.2)' "$ROOT/Gemfile.lock"
! grep -q 'BINDGEN_GCC_ARGS' "$INSTALL"
grep -q '^bundle install$' "$INSTALL"
grep -q 'bundle exec ruby -rnokogiri' "$INSTALL"
grep -q 'TAILWINDCSS_INSTALL_DIR=' "$INSTALL"
grep -q 'gem fetch tailwindcss-ruby' "$INSTALL"
grep -q -- '--platform x86_64-linux-gnu' "$INSTALL"
grep -q 'native Tailwind executable cannot run' "$INSTALL"
grep -q 'chmod 600' "$INSTALL"
grep -q 'Validating rendered database configuration' "$INSTALL"
grep -q 'Reuse the protected password' "$INSTALL"
grep -q 'diff=rails_credentials' "$ROOT/.gitattributes"
grep -q 'only that optional diff integration' "$INSTALL"
grep -q 'SECRET_KEY_BASE=.*bundle exec rails secret' "$INSTALL"
grep -q 'ENCRYPTION_KEYS=.*bundle exec rails db:encryption:init' "$INSTALL"
grep -q 'export BUNDLE_WITHOUT="development:test"' "$CONTROL"
grep -q 'SSL_CERT_FILE' "$INSTALL"
grep -q 'SSL_CERT_DIR' "$INSTALL"
grep -q 'APP_HOST_ALIASES' "$INSTALL"
grep -q 'APP_HOST_ALIASES' "$ROOT/config/environments/production.rb"
grep -q 'active_record.encryption.primary_key' "$ROOT/config/environments/production.rb"
grep -q 'active_record.encryption.deterministic_key' "$ROOT/config/environments/production.rb"
grep -q 'active_record.encryption.key_derivation_salt' "$ROOT/config/environments/production.rb"
grep -Fq 'sub(/\/$/, "")' "$ROOT/config/application.rb"
grep -q 'nohup' "$CONTROL"
grep -q 'deploy/feral/puma.rb' "$CONTROL"
grep -q '127.0.0.1' "$CONTROL"
grep -Fq 'JSON.generate([ENV.fetch("DB_PASSWORD")])[1...-1]' "$DATABASE"

ruby -rjson -rerb -ryaml -e '
  ENV["DB_HOST"] = "db.example.invalid"
  ENV["DB_PORT"] = "5432"
  ENV["DB_NAME"] = "postgres"
  ENV["DB_USER"] = "postgres.example"
  ENV["DB_PASSWORD"] = %q{p@ss: # [special] !tag &value "quoted" \\ slash}
  source = ERB.new(File.read(ARGV.fetch(0))).result
  load_parameters = YAML.method(:load).parameters
  supports_aliases_option = load_parameters.any? do |kind, name|
    kind == :keyrest || name == :aliases
  end
  parsed = if supports_aliases_option
    YAML.load(source, aliases: true)
  else
    YAML.load(source)
  end
  production = parsed.fetch("production")
  abort "database YAML password escaping failed" unless production.fetch("password") == ENV.fetch("DB_PASSWORD")
  abort "database YAML host interpolation failed" unless production.fetch("host") == ENV.fetch("DB_HOST")
' "$DATABASE"

if grep -Eq '(^|[[:space:]])(sudo|systemctl|apt-get)([[:space:]]|$)' "$INSTALL"; then
  echo "Feral installer must not require root/system services." >&2
  exit 1
fi

echo "Feral rootless shell smoke checks passed."
