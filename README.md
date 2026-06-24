# WordPress Docker Infrastructure

Production-ready Docker infrastructure for WordPress, designed to be deployed on a VPS alongside **Nginx Proxy Manager** (NPM).

## Architecture

```
Internet → NPM (SSL/Domain) → Nginx → WordPress (PHP-FPM) → MySQL 8.0
                                                            → Redis 7
```

| Container | Image | Port | Healthcheck |
|---|---|---|---|
| `{project}-nginx` | `nginx:1.27-alpine` | 80 (internal/local) | `wget /nginx-health` |
| `{project}-php` | Custom WordPress + Redis | 9000 (internal) | `cgi-fcgi ping` |
| `{project}-db` | `mysql:8.0` | 3306 (internal) | `mysqladmin ping` |
| `{project}-redis` | `redis:7-alpine` | 6379 (internal) | `redis-cli ping` |

## Requirements

- Docker Engine 24+
- Docker Compose v2
- Nginx Proxy Manager (already installed on your server)
- A shared Docker network with NPM (default: `proxy`)

## Installation

### 1. Initial Setup

```bash
# Generate a .env file with secure, random passwords
bash scripts/setup.sh
```

### 2. Review Configuration

```bash
# Edit environment variables
nano .env

# Important values to check:
# - COMPOSE_PROJECT_NAME  → Container name prefix
# - PROXY_NETWORK         → Shared network with NPM
# - LOCAL_PORT            → Port to access locally (e.g., 8087). Leave commented in production.
```

### 3. Build and Start

```bash
# Build custom images and start containers in the background
docker compose up -d --build

# Verify that all containers are healthy
docker compose ps
```

### 4. Configure Nginx Proxy Manager

1. Go to your NPM dashboard → **Proxy Hosts** → **Add Proxy Host**
2. **Domain Names**: your-domain.com
3. **Scheme**: `http`
4. **Forward Hostname/IP**: `{COMPOSE_PROJECT_NAME}-nginx` (e.g., `wordpress-site-nginx`)
5. **Forward Port**: `80`
6. **SSL**: Let's Encrypt → Enable **Force SSL** ✅
7. **Advanced** → Custom Nginx Configuration (optional):
   ```nginx
   proxy_set_header X-Forwarded-Proto $scheme;
   proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
   proxy_set_header X-Real-IP $remote_addr;
   ```
*(Note: NPM sends `X-Forwarded-Proto` by default, which triggers WordPress to securely force HTTPS on the backend).*

## Useful Commands

```bash
# View real-time logs for all services
docker compose logs -f

# Logs for a specific service
docker compose logs -f wordpress

# Open a shell in the WordPress container
docker compose exec wordpress bash

# Open a shell in MySQL
docker compose exec mysql mysql -u root -p"$MYSQL_ROOT_PASSWORD" "$MYSQL_DATABASE"

# Open a shell in Redis
docker compose exec redis redis-cli -a "$REDIS_PASSWORD" --no-auth-warning

# Restart a specific service
docker compose restart wordpress

# Rebuild WordPress (e.g., after changing PHP config)
docker compose up -d --build wordpress

# Check healthcheck status
docker compose ps --format "table {{.Name}}\t{{.Status}}"
```

## Backups

```bash
# Run a manual backup
bash scripts/backup.sh

# Setup automated backups (crontab)
crontab -e
# Add this line to run daily backups at 3 AM:
0 3 * * * /full/path/to/scripts/backup.sh >> /var/log/wp-backup.log 2>&1
```

Backups are saved in the `backups/` directory with automatic rotation (keeps the latest 7 backups by default).

## Directory Structure

```
wordpress/
├── .env.example              # Environment variables template
├── .env                      # Real variables (DO NOT commit)
├── .gitignore
├── .dockerignore
├── docker-compose.yml        # Services orchestration
├── docker/
│   ├── wordpress/
│   │   ├── Dockerfile        # Custom WordPress + Redis PHP extension
│   │   ├── php-custom.ini    # PHP production configuration
│   │   └── www.conf          # PHP-FPM pool configuration
│   ├── nginx/
│   │   ├── nginx.conf        # Main Nginx configuration
│   │   └── conf.d/
│   │       ├── wordpress.conf       # Virtual host for WP
│   │       └── security-headers.conf # Security HTTP headers
│   ├── mysql/
│   │   └── custom.cnf        # Optimized MySQL settings
│   └── redis/
│       └── redis.conf        # Redis cache configuration
├── scripts/
│   ├── setup.sh              # Project initialization script
│   └── backup.sh             # Automated backup script
├── backups/                  # Backup storage directory
└── README.md
```

## Security Features

- ✅ Credentials stored safely in `.env`, no hardcoded secrets
- ✅ MySQL and Redis ports are NOT exposed to the host machine
- ✅ HTTP Security Headers enabled (CSP, X-Frame-Options, etc.)
- ✅ `xmlrpc.php` access blocked at the Nginx level
- ✅ PHP execution blocked inside `wp-content/uploads/`
- ✅ Rate limiting enabled on `wp-login.php` to prevent brute force
- ✅ Containers hardened using `no-new-privileges` and `cap_drop: ALL` (with minimal required `cap_add`)
- ✅ Redis: Dangerous commands (`FLUSHALL`, `CONFIG`, `DEBUG`) are disabled
- ✅ MySQL: `local-infile` is disabled
- ✅ PHP: `expose_php = Off`, `display_errors = Off`
- ✅ OPcache enabled and tuned for production performance
- ✅ Automated log rotation (json-file, max 10m × 3 files)
- ✅ Auto-detects reverse proxies to seamlessly force `HTTPS` for admin pages

## Redis Object Cache Plugin

After the first startup, you must install the Redis plugin to activate caching:

1. Go to WordPress Admin → **Plugins** → **Add New Plugin**
2. Search for **"Redis Object Cache"** (by Till Krüss)
3. Install and Activate
4. Go to **Settings → Redis** → Click **"Enable Object Cache"**

## Troubleshooting

### Container won't start

```bash
docker compose logs <service_name>
docker inspect <container_name> --format='{{.State.Health}}'
```

### WordPress cannot connect to the database

```bash
# Verify that MySQL is healthy
docker compose ps mysql

# Test connection manually from the PHP container
docker compose exec wordpress php -r "
  \$pdo = new PDO(
    'mysql:host=mysql;dbname=' . getenv('WORDPRESS_DB_NAME'),
    getenv('WORDPRESS_DB_USER'),
    getenv('WORDPRESS_DB_PASSWORD')
  );
  echo 'Connection successful!';
"
```

### Redis cannot connect

```bash
docker compose exec redis redis-cli -a "$REDIS_PASSWORD" --no-auth-warning ping
# It should respond with: PONG
```
