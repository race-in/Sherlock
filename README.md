# Sherlock

Sherlock tracks your stats on private trackers over time: upload, download, ratio, bonus points and
more. Every hour it asks each tracker's API for your stats and draws the history. It uses your own API
key where the tracker allows that. Where it doesn't, the admin's key reads your profile on the tracker
once you opt in, so Sherlock sees only what your paranoia settings show other members.

![Dashboard](docs/screenshots/dashboard.png)

| One tracker | Dark theme |
|---|---|
| ![Tracker page](docs/screenshots/tracker.png) | ![Dashboard in the dark theme](docs/screenshots/dashboard-dark.png) |

The screenshots use made-up demo data.

## Features

- A dashboard with all your trackers, and a history page for each one.
- Charts for upload, download, ratio and bonus points, plus a comparison across trackers.
- Supports Redacted, Orpheus, BroadcasTheNet, GazelleGames and HDBits. To ask for another, see
  [Requesting a tracker](#requesting-a-tracker).
- It can read your torrents from [qui](https://getqui.com) and show
  how many of them are cross-seeded: seeding the same files on more than one tracker.
- API keys are encrypted in the database and never shown again after you save them.
- Prometheus metrics: every user can scrape their own stats from `/users/metrics` with a token from
  Settings → Developer.
- Export and import your data, so it's easy to move between the hosted version and your own server,
  in either direction.
- Invite only. Users can invite others, and admins see the invite tree at `/admin`.
- Light and dark theme.

## Install on Debian (without Docker)

`deploy/install-debian.sh` installs Sherlock natively on **Debian 12 or 13** (Debian 11 and Ubuntu 22.04+
are best effort), on x86_64 or aarch64. Docker is not needed. One command does everything, and you can run
it again later to update. It works two ways, depending on who runs it:

- **As root (`sudo`)**: a system install. Sherlock runs as its own `sherlock` user under systemd, behind nginx,
  with a PostgreSQL service and optional HTTPS.
- **As a normal user (rootless, no sudo)**: everything lives in your home folder and runs as you, with its own
  PostgreSQL cluster. Good for shared hosts, home servers and trying it out.

### What you need

- A server with Debian 12 or 13, root access, and at least 1.5 GB of RAM plus swap (compiling Ruby is the
  hungry part) and about 3 GB of free disk.
- For a public site: a domain name whose DNS record points at the server, and ports 80 and 443 open.
  For a private network you can skip the domain and use plain HTTP (see below).

### Install

```sh
sudo apt-get update && sudo apt-get install -y git
git clone https://github.com/race-in/Sherlock.git
cd Sherlock
```

Public site with a domain (nginx plus a free Let's Encrypt HTTPS certificate):

```sh
sudo bash deploy/install-debian.sh --domain sherlock.example.com --letsencrypt you@example.com
```

Private network, plain HTTP, reached by IP or local name:

```sh
sudo bash deploy/install-debian.sh --domain 192.168.1.10 --no-ssl
```

The first run takes 10 to 25 minutes, mostly compiling Ruby. When it ends, open the address it prints and
create the first account: **it becomes the admin**. Everyone else joins with invites.

### Install without root (rootless)

Run the same script as a normal user, without `sudo`:

```sh
git clone https://github.com/race-in/Sherlock.git
cd Sherlock
bash deploy/install-debian.sh --domain localhost
```

Nothing is installed system-wide, so the script can't install packages. It checks that the build tools and
libraries Ruby needs are present and, if not, prints one `sudo apt-get install -y ...` line for an administrator
to run, then you run the script again. You need `postgresql` installed too (only its programs are used: Sherlock
starts its own private cluster in your home folder, on port 54329, listening on `127.0.0.1` only), or you can
point to a database you already have: `--db-host HOST --db-user USER --db-password PW`.

| | Root install | Rootless install |
|---|---|---|
| App | `/opt/sherlock` | `~/.local/share/sherlock/app` |
| Settings and credentials | `/etc/sherlock` | `~/.config/sherlock` |
| Runs as | system user `sherlock` (systemd) | you (`systemd --user`, or background processes if there is no user session) |
| Web server | nginx on ports 80/443, optional Let's Encrypt | none: Sherlock listens on `127.0.0.1:3000`. Use `--bind 0.0.0.0` to open it to the network, or put your own HTTPS proxy in front and add `--ssl` |
| Control | `sudo sherlock-ctl ...` | `~/.local/bin/sherlock-ctl ...` |

Rootless runs can only use ports 1024 and up. To keep it running after you log out, an administrator runs
`sudo loginctl enable-linger YOUR_USER`. Without a systemd user session, start it again after a reboot with
`sherlock-ctl start`.

### Options

| Option | What it does |
|---|---|
| `--domain HOST` | Host name or IP Sherlock is reached at. Required on the first run. |
| `--letsencrypt EMAIL` (root only) | With nginx: get a free HTTPS certificate for the domain. |
| `--no-ssl` / `--ssl` | `--no-ssl`: plain HTTP, no redirect to HTTPS, no secure cookies (private network only). `--ssl`: force HTTPS. Root default is on, rootless default is off. |
| `--bind ADDR` | Address Rails listens on. Default `127.0.0.1` (`0.0.0.0` with `--proxy none`). |
| `--db-host HOST` | Use an existing PostgreSQL instead of installing one. Also `--db-port`, `--db-name`, `--db-user`. |
| `--proxy nginx\|none` (root only) | `nginx` (default) installs nginx and keeps Sherlock on `127.0.0.1`. `none` makes Sherlock listen on `0.0.0.0:PORT` so you can put your own proxy in front. |
| `--port N` | Port of the Rails server. Default `3000`. |
| `--db-password PW` | Database password. Default: random, saved in `/etc/sherlock/sherlock.env`. |
| `-y`, `--yes` | Ask no questions. |

All options: `bash deploy/install-debian.sh --help`.

### What the installer does

1. Installs the packages it needs with apt (rootless: checks them and lists what is missing).
2. Installs PostgreSQL 18 from the official PostgreSQL repository (or the version Debian ships if 18 isn't
   offered), and creates the database and user (rootless: a private cluster in your home folder).
3. Builds the Ruby version in `.ruby-version` under `/opt/rubies`, with a ruby-build release pinned by commit.
4. Downloads the Node.js version in `.node-version` into a temporary folder, checks its checksum, uses it only
   to build the JavaScript and CSS, and deletes it.
5. Copies the app to `/opt/sherlock`, installs the gems and builds the assets.
6. Creates the encrypted credentials in `/etc/sherlock/credentials`.
7. Runs `db:prepare db:seed`, installs and starts the `sherlock` systemd service, and sets up nginx.

| What | Where |
|---|---|
| App | `/opt/sherlock`, run by the system user `sherlock` (rootless: see the table above) |
| Settings | `/etc/sherlock/sherlock.env` (then `sudo systemctl restart sherlock`) |
| Credentials | `/etc/sherlock/credentials/`: **back up `production.key`**, without it saved API keys can't be decrypted |
| Service | `sherlock.service` (web server and tracker polling run together) |
| nginx site | `/etc/nginx/sites-available/sherlock` |

### Everyday use

```sh
sudo sherlock-ctl status      # rootless: sherlock-ctl status (no sudo)
sudo sherlock-ctl logs
sudo sherlock-ctl restart
curl -fsS http://127.0.0.1:3000/up        # health check
```

If you lock yourself out of the admin account, run `sudo sherlock-ctl rails 'users:reset_password[username]'`
to get a temporary password.

### Update

```sh
cd Sherlock
sudo -u postgres pg_dump -Fc sherlockdb_prod > ~/sherlock-before-update.dump   # a backup first
git pull
sudo bash deploy/install-debian.sh
```

No options are needed: the database, credentials and settings are kept.

### Backup and restore

Back up the database and the credentials folder together:

```sh
sudo -u postgres pg_dump -Fc sherlockdb_prod > sherlock.dump
sudo tar -C /etc -czf sherlock-config.tar.gz sherlock
```

To restore on a fresh server, run the installer, stop the service, restore the config archive over
`/etc/sherlock`, then `sudo -u postgres pg_restore --clean --if-exists -d sherlockdb_prod sherlock.dump`
and start the service again.

### Troubleshooting

- **The installer stopped.** Read the last error, fix it and run the script again. Finished steps are skipped.
- **`bundle install` failed.** Usually a missing system library; the error names it. Install it with apt and rerun.
- **Ruby compile ran out of memory.** Add swap (`fallocate -l 2G /swapfile && chmod 600 /swapfile && mkswap /swapfile && swapon /swapfile`) and rerun.
- **The certificate was refused.** Check that DNS points at the server and ports 80 and 443 are open, then rerun.
- **The site doesn't start.** `sudo sherlock-ctl logs` shows why. A wrong `APP_HOST` in `/etc/sherlock/sherlock.env`
  makes Sherlock refuse requests: it must match the address in your browser.

More details are in [DEBIAN.md](DEBIAN.md).

## Run it with Docker instead

The repository still has the original `Dockerfile`. Build the image yourself and run it against a PostgreSQL 18
you provide:

```sh
git clone https://github.com/race-in/Sherlock.git && cd Sherlock
docker build -t sherlock .
```

Create the credentials once (this writes `credentials/production.yml.enc` and `credentials/production.key`;
back the key up), then start the container against your PostgreSQL 18:

```sh
mkdir credentials
docker run --rm --user "$(id -u):$(id -g)" -e APP_HOST=setup \
  -v "$PWD/credentials:/rails/config/credentials" sherlock sh -c '
  { echo "secret_key_base: $(bin/rails secret)"; bin/rails db:encryption:init | tail -n 4; } > /tmp/credentials.yml
  EDITOR="cp /tmp/credentials.yml" bin/rails credentials:edit --environment production'

docker run -d --name sherlock --restart unless-stopped -p 3000:3000 \
  -e APP_HOST=sherlock.example.com -e FORCE_SSL=false \
  -e RAILS_MASTER_KEY="$(cat credentials/production.key)" \
  -e DB_HOST=your-postgres-host -e DB_PASSWORD=your-db-password -e SOLID_QUEUE_IN_PUMA=true \
  -v "$PWD/credentials:/rails/config/credentials:ro" sherlock
```

The container creates the database tables and refreshes the tracker list every time it starts. All variables
are listed in [Configuration](#configuration).

### Who can use what

Every tracker starts off. The admin turns on the first one in the setup on their dashboard, and picks
who can use each tracker in Admin → Sites:

- **Everyone.** Anyone on this Sherlock can add it.
- **Granted only.** Admins, and the people you turn the tracker on for on their page in Admin →
  Invite tree. A tracker you set up for only yourself starts out this way. HDBits only gives out the passkey from your
  torrents, and anyone holding it can download as you, so people should only add it to a Sherlock
  whose admin they trust.
- **Off.** Nobody can add it, it stops updating, and the keys members saved for it are deleted. Their
  history stays.

Taking a tracker away from someone stops it updating for them, but keeps their key and history.

**Running Sherlock for other people?** Check each tracker's rules first. Many don't allow members to
give their API key to someone else's service. Use your key for everyone where the tracker allows that,
or set the tracker to Granted only. You're responsible for what your instance asks members to share.

### Instance keys

The admin adds a tracker in Admin → Sites with their own key, as on any Sherlock, and ticks whether
people they invite can track their stats there too. On trackers whose API can read other members'
profiles (Redacted, Orpheus, PhoenixProject and GazelleGames) that uses the admin's key for everyone. Sherlock then reads each member's profile with that key, as other
members of the tracker see it. A member opts in by putting a Sherlock link on their profile; Sherlock
checks for it on every read and stops when it's gone. Paranoia applies, and bonus points aren't on
profiles. The key needs the User permission to read profiles, and Sherlock only sends it GET requests.
Switching deletes the members' own keys for that site; their history stays. The admin's own account
needs no link: their key reads it directly, with every stat.

Admins can also make open invites, for more than one person or without an end. They only let in
members of such a tracker: before joining, people put their opt-in link on their profile there, and
Sherlock checks it. So an open invite is safe to post in that tracker's forum.

Every tracker request carries the contact you set in Admin → Settings (an email address, your tracker
username or an IRC channel), so staff can reach you. Sherlock
sends each tracker at most one request per interval (2 seconds by default, set per site) from all
processes together, and pauses a site on its own when it answers 429 or keeps failing.

**Integrations** follow the same three choices, under Integrations on the same page. The only
one so far is qui, which starts out as Granted only.

**qui.** In Settings → qui, add the address of your [qui](https://getqui.com) and an API key from
qui's Settings → API Keys. Sherlock reads your torrents once an hour and shows, on the dashboard and
each tracker's page, how many seed the same files on another tracker, their size and their upload.
It only sends GET requests, but a qui key can do anything you can do in qui. Admins can add a qui on
a private network or over plain HTTP. Everyone else needs a public https address, so nobody else can
make the server reach into its own network.

### Configuration

| Variable | Required | What it does |
|---|---|---|
| `APP_HOST` | Yes | The domain Sherlock runs on. Requests for other hosts are refused. |
| `RAILS_MASTER_KEY` | Yes | Decrypts `credentials/production.yml.enc`. |
| `DB_PASSWORD` | Yes | Password of the Postgres user. |
| `DB_HOST`, `DB_PORT` | No | Where Postgres runs. Default `172.17.0.1:5432`. |
| `DB_NAME`, `DB_USER` | No | Database and user. Default `sherlockdb_prod` and `sherlockdb_prod_write`. |
| `FORCE_SSL` | No | `false` serves plain HTTP: no redirect to HTTPS, no secure cookies. Default `true`. |
| `SOLID_QUEUE_IN_PUMA` | No | Any value runs the worker inside the web container. Leave it unset only if you run `./bin/jobs start` in a container of its own. |
| `METRICS_PORT` | No | Port of the worker's own Prometheus metrics. Default `9394`. |
| `METRICS_BIND` | No | Address the worker's metrics listen on. Default `0.0.0.0`; the Debian installer sets `127.0.0.1`. |
| `JOB_CONCURRENCY` | No | Number of worker processes. Default `1`. |
| `RAILS_LOG_LEVEL` | No | Default `info`. |

### Prometheus

- `/users/metrics` serves one user's tracker stats. Create the bearer token in Settings → Developer.
- `/metrics` on port 3000 serves app metrics. It only answers requests from private or
  loopback addresses that didn't come through a proxy (no `X-Forwarded-For` header), so scrape it
  directly, not through your public domain.
- The worker serves poll metrics (`sherlock_polls_total`, `sherlock_poll_duration_seconds`) on
  `METRICS_PORT`, in the same process.

If you lock yourself out of the admin account, run
`sudo sherlock-ctl rails 'users:reset_password[username]'` (Docker: `docker compose exec sherlock bin/rails users:reset_password[username]`) to get a temporary password.

## Requesting a tracker

To get a tracker supported, open an
[issue on GitHub](https://github.com/race-in/Sherlock/issues) with:

- The tracker's name and URL, and the software it runs (Gazelle, Unit3D, its own).
- Where users create an API key or find their passkey, and whether that key can do more than read
  stats.
- The API endpoint that returns your stats, and its rate limit if it documents one.
- A real response from that endpoint, with your key, passkey, username, IP addresses and anything
  else personal removed.
- The hosts its announce URLs use, so cross-seeds from qui can be matched to it.

Sherlock only supports trackers with an API that takes a per-user key (an API key or passkey). It
never asks for passwords or cookies.

To work on Sherlock locally, run `bin/setup`. It starts Postgres in Docker (or uses one already listening on
port 5448), installs everything and starts the app.

## Credits

Sherlock started as a PHP app. We don't know who originally wrote it, but its source code was
maintained in [jimrollenhagen/sherlock](https://github.com/jimrollenhagen/sherlock). The icon and the
color theme come from that original.

This repository (https://github.com/race-in/Sherlock) is a fork that adds a native Debian installer to the upstream project at
[codeberg.org/whatstatus/sherlock-v2](https://codeberg.org/whatstatus/sherlock-v2).
