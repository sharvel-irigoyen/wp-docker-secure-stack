# WordPress Docker Infrastructure

Infraestructura Docker lista para producción para WordPress, diseñada para desplegarse en un VPS con **Nginx Proxy Manager**.

## Arquitectura

```
Internet → NPM (SSL/Domain) → Nginx → WordPress (PHP-FPM) → MySQL 8.0
                                                            → Redis 7
```

| Contenedor | Imagen | Puerto | Healthcheck |
|---|---|---|---|
| `{project}-nginx` | `nginx:1.27-alpine` | 80 (interno) | `wget /nginx-health` |
| `{project}-php` | Custom WordPress + Redis | 9000 (interno) | `cgi-fcgi ping` |
| `{project}-db` | `mysql:8.0` | 3306 (interno) | `mysqladmin ping` |
| `{project}-redis` | `redis:7-alpine` | 6379 (interno) | `redis-cli ping` |

## Requisitos

- Docker Engine 24+
- Docker Compose v2
- Nginx Proxy Manager (ya instalado)
- Red Docker compartida con NPM (por defecto: `proxy`)

## Instalación

### 1. Setup inicial

```bash
# Generar .env con passwords seguros
bash scripts/setup.sh
```

### 2. Revisar configuración

```bash
# Editar variables de entorno
nano .env

# Valores importantes a revisar:
# - COMPOSE_PROJECT_NAME  → prefijo de contenedores
# - PROXY_NETWORK         → red compartida con NPM
```

### 3. Build y arranque

```bash
# Construir y levantar
docker compose up -d --build

# Verificar que todo está healthy
docker compose ps
```

### 4. Configurar en Nginx Proxy Manager

1. Ir a NPM → **Proxy Hosts** → **Add Proxy Host**
2. **Domain**: tu-dominio.com
3. **Scheme**: http
4. **Forward Hostname**: `{COMPOSE_PROJECT_NAME}-nginx` (ej: `wordpress-site-nginx`)
5. **Forward Port**: `80`
6. **SSL**: Let's Encrypt → Force SSL ✅
7. **Advanced** → Custom Nginx Config (opcional):
   ```nginx
   proxy_set_header X-Forwarded-Proto $scheme;
   proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
   proxy_set_header X-Real-IP $remote_addr;
   ```

## Comandos Útiles

```bash
# Ver logs en tiempo real
docker compose logs -f

# Logs de un servicio específico
docker compose logs -f wordpress

# Shell en WordPress
docker compose exec wordpress bash

# Shell en MySQL
docker compose exec mysql mysql -u root -p"$MYSQL_ROOT_PASSWORD" "$MYSQL_DATABASE"

# Shell en Redis
docker compose exec redis redis-cli -a "$REDIS_PASSWORD" --no-auth-warning

# Reiniciar un servicio
docker compose restart wordpress

# Reconstruir WordPress (después de cambiar PHP config)
docker compose up -d --build wordpress

# Ver estado de healthchecks
docker compose ps --format "table {{.Name}}\t{{.Status}}"
```

## Backups

```bash
# Backup manual
bash scripts/backup.sh

# Backup automático (crontab)
crontab -e
# Agregar: backup diario a las 3 AM
0 3 * * * /ruta/completa/scripts/backup.sh >> /var/log/wp-backup.log 2>&1
```

Los backups se guardan en `backups/` con rotación automática (últimos 7 por defecto).

## Estructura de Archivos

```
wordpress/
├── .env.example              # Template de variables de entorno
├── .env                      # Variables reales (NO commitear)
├── .gitignore
├── .dockerignore
├── docker-compose.yml        # Orquestación de servicios
├── docker/
│   ├── wordpress/
│   │   ├── Dockerfile        # WordPress + Redis extension
│   │   ├── php-custom.ini    # PHP production config
│   │   └── www.conf          # PHP-FPM pool config
│   ├── nginx/
│   │   ├── nginx.conf        # Nginx principal
│   │   └── conf.d/
│   │       ├── wordpress.conf       # Virtual host
│   │       └── security-headers.conf # Headers HTTP
│   ├── mysql/
│   │   └── custom.cnf        # MySQL optimizado
│   └── redis/
│       └── redis.conf        # Redis configuración
├── scripts/
│   ├── setup.sh              # Inicialización del proyecto
│   └── backup.sh             # Backups automatizados
├── backups/                  # Directorio de backups
└── README.md
```

## Seguridad

- ✅ Credenciales en `.env`, nunca hardcodeadas
- ✅ MySQL y Redis sin puertos expuestos al host
- ✅ Headers HTTP de seguridad (CSP, X-Frame-Options, etc.)
- ✅ `xmlrpc.php` bloqueado
- ✅ PHP en `wp-content/uploads/` bloqueado
- ✅ Rate limiting en `wp-login.php`
- ✅ Contenedores con `no-new-privileges` y `cap_drop: ALL`
- ✅ Redis: comandos peligrosos deshabilitados
- ✅ MySQL: `local-infile` deshabilitado
- ✅ PHP: `expose_php = Off`, `display_errors = Off`
- ✅ OPcache habilitado para producción
- ✅ Logs con rotación automática (json-file, max 10m × 3)

## Plugin Redis Object Cache

Después del primer arranque, instalar el plugin de Redis:

1. Ir a WordPress Admin → Plugins → Añadir nuevo
2. Buscar **"Redis Object Cache"** por Till Krüss
3. Instalar y activar
4. Ir a **Settings → Redis** → Click **"Enable Object Cache"**

## Troubleshooting

### Contenedor no arranca

```bash
docker compose logs <servicio>
docker inspect <contenedor> --format='{{.State.Health}}'
```

### WordPress no conecta a la base de datos

```bash
# Verificar que MySQL está healthy
docker compose ps mysql

# Probar conexión manual
docker compose exec wordpress php -r "
  \$pdo = new PDO(
    'mysql:host=mysql;dbname=' . getenv('WORDPRESS_DB_NAME'),
    getenv('WORDPRESS_DB_USER'),
    getenv('WORDPRESS_DB_PASSWORD')
  );
  echo 'Conexión exitosa';
"
```

### Redis no conecta

```bash
docker compose exec redis redis-cli -a "$REDIS_PASSWORD" --no-auth-warning ping
# Debe responder: PONG
```
