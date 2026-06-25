# Protocolo de Seguridad y Limpieza para WordPress en Docker

Este documento detalla el procedimiento de respuesta a incidentes (Incident Response Protocol) para detectar, limpiar y asegurar instalaciones de WordPress que corren sobre Docker.

Este protocolo fue diseñado específicamente para la arquitectura de este proyecto (usando volúmenes como `wordpress-site_wordpress_data` y redes como `wordpress-site_backend`).

> **Última actualización:** 25 de junio de 2026 — Incidente de seguridad resuelto.
> Se detectaron y eliminaron 3 webshells (backdoors PHP), 1 usuario administrador fantasma,
> y se actualizaron 8 plugins y 5 temas con parches de seguridad.

---

## 🕵️‍♂️ FASE 1: Detección (Encontrar el Malware)

### 1. Verificar la integridad del Core (Núcleo de WordPress)
Compara los archivos del sistema con los originales de WordPress.org.

```bash
docker run --rm -v wordpress-site_wordpress_data:/var/www/html wordpress:cli wp core verify-checksums
```

> **Nota:** El warning sobre `wp-config-docker.php` es normal en instalaciones Docker. Ignóralo.

### 2. Verificar la integridad de los Plugins
Busca backdoors o archivos inyectados dentro de los plugins. Requiere conexión a la base de datos.

```bash
docker run --rm --network wordpress-site_backend --env-file .env -v wordpress-site_wordpress_data:/var/www/html wordpress:cli wp plugin verify-checksums --all
```

> **⚠️ LIMITACIÓN IMPORTANTE:** Este comando solo verifica plugins alojados en WordPress.org.
> **Los plugins premium** (ej. wp-rocket, Elementor Pro) son ignorados silenciosamente.
> Para verificar plugins premium, usa los comandos de la Fase 5.

*(Anota qué archivos o plugins dan "Warning" o "Error" para limpiarlos en la siguiente fase).*

### 3. Buscar archivos PHP sospechosos en carpetas del Core
Busca archivos con nombres aleatorios que NO pertenecen a WordPress (típico de backdoors).

```bash
docker run --rm -v wordpress-site_wordpress_data:/var/www/html alpine find /var/www/html/wp-admin /var/www/html/wp-includes -name "*.php" | grep -E '[a-z]{8,}\.' | grep -v -E '(class-|admin-|includes|functions|template|capabilities|update|options|widgets|comment|user-|edit-|nav-|post-|link-|media|theme|plugin|site-|network|ms-|menu|privacy|credits|about|export|import|contribute|freedoms|profile|upload|load|erase|signup|login|mail|trackback|xmlrpc|settings|activate|cron|index)'
```

> **Cómo interpretar:** Si este comando devuelve archivos con nombres aleatorios como
> `dqdsxihebd.php` o `dexzpscihb.php`, son backdoors. Bórralos con el comando `rm` de la Fase 2.

### 4. Buscar archivos con firmas conocidas de este atacante
Busca la firma `eIilZQ` (identificada en el incidente del 25/06/2026) u otros patrones sospechosos.

```bash
docker run --rm -v wordpress-site_wordpress_data:/var/www/html alpine find /var/www/html -name "*eIilZQ*"
```

---

## 🧹 FASE 2: Limpieza y Reparación (Eliminar el Malware)

### 5. Restaurar el Core (Solo si el paso 1 falló)
Fuerza la descarga de los archivos base limpios, sobreescribiendo archivos infectados del núcleo.

```bash
docker run --rm -v wordpress-site_wordpress_data:/var/www/html wordpress:cli wp core download --skip-content --force
```

### 6. Borrar archivos sueltos que NO pertenecen a WordPress
Si el paso 3 encontró archivos con nombres aleatorios en `wp-admin` o `wp-includes`, bórralos manualmente.

```bash
docker run --rm -v wordpress-site_wordpress_data:/var/www/html alpine rm /var/www/html/RUTA_DEL_ARCHIVO_SOSPECHOSO
```

### 7. Restaurar Plugins Infectados (IMPORTANTE: usar delete + install)

> **⚠️ LECCIÓN APRENDIDA:** El comando `wp plugin install --force` sobreescribe archivos
> existentes pero **NO elimina archivos extra** añadidos por el hacker.
> Siempre usar `delete` primero y luego `install`.

```bash
# Paso 1: Borrar la carpeta completa del plugin (incluyendo archivos del hacker)
docker run --rm -v wordpress-site_wordpress_data:/var/www/html alpine rm -rf /var/www/html/wp-content/plugins/NOMBRE_DEL_PLUGIN

# Paso 2: Instalar limpio desde WordPress.org
docker run --rm --network wordpress-site_backend --env-file .env -v wordpress-site_wordpress_data:/var/www/html wordpress:cli wp plugin install NOMBRE_DEL_PLUGIN --activate
```

> **Para plugins premium** (ej. wp-rocket): No se pueden reinstalar por WP-CLI.
> Opción A: Borrar con `rm -rf` y reinstalar desde el panel de WordPress subiendo el ZIP.
> Opción B: Si no lo usas, simplemente bórralo.

---

## 🚪 FASE 3: Cerrar las Puertas (Auditoría y Parches)

### 8. Auditoría de Administradores Fantasma (Backdoors en BD)
Los atacantes crean usuarios admin ocultos. Busca fechas de registro anómalas (ej. `1970-10-10`).

```bash
docker run --rm --network wordpress-site_backend --env-file .env -v wordpress-site_wordpress_data:/var/www/html wordpress:cli wp user list --role=administrator
```

Si encuentras un intruso, bórralo inmediatamente:

```bash
docker run --rm --network wordpress-site_backend --env-file .env -v wordpress-site_wordpress_data:/var/www/html wordpress:cli wp user delete NOMBRE_USUARIO --yes
```

### 9. Parchar Vulnerabilidades (Actualización masiva)

```bash
# Actualizar todos los plugins
docker run --rm --network wordpress-site_backend --env-file .env -v wordpress-site_wordpress_data:/var/www/html wordpress:cli wp plugin update --all

# Actualizar todos los temas
docker run --rm --network wordpress-site_backend --env-file .env -v wordpress-site_wordpress_data:/var/www/html wordpress:cli wp theme update --all
```

### 10. Cambiar contraseñas
Después de un incidente, cambia la contraseña de TODOS los usuarios administradores desde el panel de WordPress.

---

## 🔬 FASE 4: Certificación Final (Escaneo Profundo con ClamAV)

### 11. Lanzar el Escáner Antivirus

```bash
docker run -d --rm \
  --name scanner-clamav \
  -v wordpress-site_wordpress_data:/scandir \
  -v $(pwd):/logs \
  clamav/clamav:latest \
  sh -c "freshclam && clamscan -r -i /scandir > /logs/reporte_malware.txt"
```

### 12. Monitorear el escaneo

```bash
docker ps | grep scanner-clamav
```
*(Si no devuelve resultados, el escáner ha finalizado).*

### 13. Leer el veredicto final

```bash
cat reporte_malware.txt
```
* **`Infected files: 0`** → La instalación está 100% limpia.
* **Si contiene archivos infectados** → Procede a eliminarlos manualmente.

---

## 🔍 FASE 5: Verificación Cruzada (Plugins Premium y Búsqueda Avanzada)

> **¿Por qué esta fase?** Los pasos anteriores tienen puntos ciegos:
> `wp plugin verify-checksums` no revisa plugins premium, y ClamAV no detecta
> backdoors PHP ofuscados diseñados para WordPress. Esta fase cubre esos huecos.

### 14. Buscar archivos infectados reportados en otros servidores
Si tienes el mismo proyecto en otro servidor y el equipo de TI reportó archivos infectados, verifica si existen aquí también.

```bash
# Ejemplo: Buscar archivos específicos del reporte del TI
docker run --rm -v wordpress-site_wordpress_data:/var/www/html alpine find /var/www/html -name "NOMBRE_ARCHIVO_REPORTADO"
```

### 15. Listar plugins premium instalados (que no son verificables por WP-CLI)
Estos plugins deben revisarse manualmente o reinstalarse periódicamente desde su fuente oficial.

```bash
docker run --rm --network wordpress-site_backend --env-file .env -v wordpress-site_wordpress_data:/var/www/html wordpress:cli wp plugin list --format=table
```

> Compara esta lista con los plugins disponibles en WordPress.org.
> Todo plugin que NO esté en WordPress.org es premium y debe verificarse manualmente.

---

## 🛡️ MANTENIMIENTO PREVENTIVO (Ejecutar mensualmente)

### Checklist mensual de seguridad:

```bash
# 1. Verificar Core
docker run --rm -v wordpress-site_wordpress_data:/var/www/html wordpress:cli wp core verify-checksums

# 2. Verificar Plugins
docker run --rm --network wordpress-site_backend --env-file .env -v wordpress-site_wordpress_data:/var/www/html wordpress:cli wp plugin verify-checksums --all

# 3. Buscar archivos PHP sospechosos en carpetas del core
docker run --rm -v wordpress-site_wordpress_data:/var/www/html alpine find /var/www/html/wp-admin /var/www/html/wp-includes -name "*.php" | grep -E '[a-z]{8,}\.' | grep -v -E '(class-|admin-|includes|functions|template|capabilities|update|options|widgets|comment|user-|edit-|nav-|post-|link-|media|theme|plugin|site-|network|ms-|menu|privacy|credits|about|export|import|contribute|freedoms|profile|upload|load|erase|signup|login|mail|trackback|xmlrpc|settings|activate|cron|index)'

# 4. Verificar usuarios administradores
docker run --rm --network wordpress-site_backend --env-file .env -v wordpress-site_wordpress_data:/var/www/html wordpress:cli wp user list --role=administrator

# 5. Actualizar todo
docker run --rm --network wordpress-site_backend --env-file .env -v wordpress-site_wordpress_data:/var/www/html wordpress:cli wp plugin update --all
docker run --rm --network wordpress-site_backend --env-file .env -v wordpress-site_wordpress_data:/var/www/html wordpress:cli wp theme update --all
```

---

## 📋 Registro de Incidentes

### Incidente #1 — 25 de junio de 2026

| Detalle | Valor |
|---------|-------|
| **Vector de entrada** | WooCommerce v5.5.5 (vulnerabilidad de SQL Injection conocida) |
| **Tipo de malware** | PHP Webshell Backdoor (`php.bkdr.wshll`) |
| **Archivos infectados** | `smart-custom-fields/classes/fields/class.field-class-eIilZQ.php` |
| | `wp-rocket/inc/ThirdParty/Hostings/WordPressCom-section.php` |
| | `testimonial-free/src/Includes/Import_Export_Description.php` |
| **Backdoors en BD** | Usuario `prladmin` (fecha registro: 1970-10-10) |
| **Firma del atacante** | Cadena `eIilZQ` en nombres de archivo |
| **Impacto en Docker** | 3 archivos de plugins (Docker bloqueó infección del core) |
| **Impacto en servidor tradicional** | 14 archivos (core + plugins infectados) |
| **Resolución** | Plugins reinstalados, usuario borrado, todo actualizado |
| **ClamAV** | 17,527 archivos escaneados, 0 infectados |
