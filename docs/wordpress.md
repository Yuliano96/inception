# WordPress Service

## Overview

The WordPress service provides the web application and the PHP runtime used by
the Inception website.

The container combines two main components:

* WordPress, which provides the website files and application logic;
* PHP-FPM, which executes PHP scripts received from NGINX through FastCGI.

The service is built from Debian 12 and communicates with:

* MariaDB at `mariadb:3306` to store and retrieve website data;
* NGINX through port `9000` to process PHP requests.

The WordPress files are stored in a persistent volume mounted at:

```text
/var/www/html
```

This volume is backed by the following host directory:

```text
/home/ypacileo/data/wordpress
```

The volume preserves the WordPress files when the container is removed or
recreated.

## Files

| File                                              | Purpose                                                                                 |
| ------------------------------------------------- | --------------------------------------------------------------------------------------- |
| `srcs/requirements/wordpress/Dockerfile`          | Builds the WordPress and PHP-FPM image.                                                 |
| `srcs/requirements/wordpress/conf/www.conf`       | Configures the PHP-FPM worker pool and FastCGI listener.                                |
| `srcs/requirements/wordpress/tools/entrypoint.sh` | Prepares and installs WordPress before starting PHP-FPM.                                |
| `srcs/requirements/wordpress/tools/check-db.php`  | Tests whether WordPress can connect to MariaDB.                                         |
| `srcs/docker-compose.yml`                         | Supplies variables, secrets, storage, networking, dependencies, and the restart policy. |

## Dockerfile

The Dockerfile builds the `wordpress:1.0` image before any WordPress container
is started.

### Dockerfile build flow

```text
Start from debian:12
        |
        v
Update the APT package index
        |
        v
Install PHP-FPM, PHP CLI,
PHP extensions, curl, and CA certificates
        |
        v
Remove the APT package lists
        |
        v
Download WP-CLI
        |
        v
Install WP-CLI as /usr/local/bin/wp
        |
        v
Copy the PHP-FPM pool configuration
        |
        v
Download WordPress 7.1
        |
        v
Extract WordPress into /usr/src/wordpress
        |
        v
Copy entrypoint.sh and check-db.php
        |
        v
Make entrypoint.sh executable
        |
        v
Document port 9000
        |
        v
Define ENTRYPOINT and CMD
        |
        v
The wordpress:1.0 image is ready
```

### Base image

The image is based on:

```dockerfile
FROM debian:12
```

The WordPress and PHP-FPM environment is therefore built from the Debian 12
packages instead of an official prebuilt WordPress image.

### Installed packages

The Dockerfile installs the following packages:

| Package           | Purpose                                                            |
| ----------------- | ------------------------------------------------------------------ |
| `ca-certificates` | Allows `curl` to verify HTTPS certificates when downloading files. |
| `curl`            | Downloads WP-CLI and the WordPress archive.                        |
| `php8.2-cli`      | Runs PHP scripts and supports WP-CLI.                              |
| `php8.2-curl`     | Provides HTTP client support to PHP applications.                  |
| `php8.2-fpm`      | Executes PHP scripts received through FastCGI.                     |
| `php8.2-gd`       | Provides image-processing functions used by WordPress.             |
| `php8.2-mbstring` | Provides multibyte string and UTF-8 support.                       |
| `php8.2-mysql`    | Allows PHP and WordPress to communicate with MariaDB.              |
| `php8.2-xml`      | Provides XML-processing support.                                   |

The packages are installed with `--no-install-recommends` to avoid installing
optional packages that are not required by the service.

The APT package lists are removed after installation to reduce the final image
size.

## WP-CLI installation

The Dockerfile downloads WP-CLI from:

```text
https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar
```

The downloaded PHP archive is stored as:

```text
/usr/local/bin/wp
```

The file is made executable so the entrypoint can use the `wp` command.

WP-CLI is used during container startup to:

* generate `wp-config.php`;
* check whether WordPress is already installed;
* install the website;
* check whether the regular WordPress user exists;
* create the regular WordPress user when necessary.

The entrypoint uses:

```text
--allow-root
```

because it runs WP-CLI as the container's root user during initialization.

This permission applies to the initialization commands. PHP-FPM worker
processes later execute as the less privileged `www-data` user.

## WordPress source files

The Dockerfile defines the WordPress version with:

```dockerfile
ARG WORDPRESS_VERSION=7.1
```

It downloads the corresponding archive from:

```text
https://wordpress.org/wordpress-7.1.tar.gz
```

The archive is extracted into:

```text
/usr/src/wordpress
```

This directory contains the original WordPress core files included in the
image.

It is different from:

```text
/var/www/html
```

which contains the active WordPress installation stored in the persistent
volume.

The distinction is:

| Directory            | Purpose                                                  | Persistent |
| -------------------- | -------------------------------------------------------- | ---------- |
| `/usr/src/wordpress` | Read-only source copy included in the image.             | No         |
| `/var/www/html`      | Active WordPress installation used by PHP-FPM and NGINX. | Yes        |

During the first startup, the entrypoint copies the source files from
`/usr/src/wordpress` into `/var/www/html`.

## Container startup definition

The Dockerfile defines:

```dockerfile
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["php-fpm8.2", "-F"]
```

Docker combines these instructions and starts the equivalent of:

```text
/usr/local/bin/entrypoint.sh php-fpm8.2 -F
```

The entrypoint prepares WordPress and eventually replaces itself with
PHP-FPM.

## Port 9000

The Dockerfile contains:

```dockerfile
EXPOSE 9000
```

This documents the FastCGI port used by PHP-FPM.

`EXPOSE` does not publish port 9000 on the host. The WordPress service has no
Compose `ports` mapping.

NGINX reaches PHP-FPM through the Docker network at:

```text
wordpress:9000
```

## PHP-FPM configuration

The PHP-FPM pool configuration is stored in:

```text
srcs/requirements/wordpress/conf/www.conf
```

The Dockerfile copies it to:

```text
/etc/php/8.2/fpm/pool.d/www.conf
```

The file defines the PHP-FPM pool named:

```text
www
```

### Pool settings

| Setting                | Value          | Purpose                                                                     |
| ---------------------- | -------------- | --------------------------------------------------------------------------- |
| `user`                 | `www-data`     | Runs PHP-FPM worker processes as the `www-data` user.                       |
| `group`                | `www-data`     | Runs PHP-FPM worker processes with the `www-data` group.                    |
| `listen`               | `0.0.0.0:9000` | Accepts FastCGI connections on port 9000 through every container interface. |
| `pm`                   | `dynamic`      | Creates and removes worker processes according to demand.                   |
| `pm.max_children`      | `5`            | Allows no more than five PHP-FPM workers at the same time.                  |
| `pm.start_servers`     | `2`            | Starts the pool with two worker processes.                                  |
| `pm.min_spare_servers` | `1`            | Keeps at least one idle worker available.                                   |
| `pm.max_spare_servers` | `3`            | Keeps no more than three idle workers.                                      |
| `catch_workers_output` | `yes`          | Redirects worker output and errors to the main PHP-FPM log.                 |

### Dynamic process management

The pool uses:

```text
pm = dynamic
```

PHP-FPM therefore adjusts the number of worker processes according to the
current demand.

The initial process structure is approximately:

```text
PHP-FPM master process
        |
        +-- Worker process
        |
        +-- Worker process
```

When demand increases, PHP-FPM can create more workers, up to the configured
maximum of five.

When demand decreases, PHP-FPM can remove unnecessary idle workers while
keeping at least one spare worker available.

### FastCGI listener

The configuration contains:

```text
listen = 0.0.0.0:9000
```

This allows NGINX to connect to PHP-FPM through the Docker network.

The port is not an HTTP port. PHP-FPM expects the FastCGI protocol, not direct
browser requests.

Users access NGINX through HTTPS on port 443. NGINX forwards PHP requests to
PHP-FPM using FastCGI on port 9000.

## Docker Compose integration

Docker Compose provides the WordPress container with the following resources:

| Compose setting | Value                           | Purpose                                                                |
| --------------- | ------------------------------- | ---------------------------------------------------------------------- |
| Build context   | `./requirements/wordpress`      | Selects the WordPress Dockerfile and its local files.                  |
| Image           | `wordpress:1.0`                 | Names and versions the built image.                                    |
| Environment     | Database and WordPress settings | Supplies non-sensitive installation values.                            |
| Secrets         | Three password files            | Supplies the MariaDB and WordPress account passwords.                  |
| Volume          | `wordpress_data:/var/www/html`  | Persists the active WordPress installation.                            |
| Network         | `inception`                     | Connects WordPress to MariaDB and NGINX.                               |
| Dependency      | `mariadb`                       | Starts the MariaDB container before the WordPress container.           |
| Restart policy  | `unless-stopped`                | Restarts the container automatically unless it was explicitly stopped. |

### Environment variables

The WordPress service receives:

| Variable                | Purpose                                            |
| ----------------------- | -------------------------------------------------- |
| `MYSQL_DATABASE`        | Name of the MariaDB database used by WordPress.    |
| `MYSQL_USER`            | Name of the MariaDB application user.              |
| `MYSQL_HOST`            | MariaDB service hostname.                          |
| `WORDPRESS_URL`         | Public URL assigned during WordPress installation. |
| `WORDPRESS_TITLE`       | Initial website title.                             |
| `WORDPRESS_ADMIN_USER`  | WordPress administrator username.                  |
| `WORDPRESS_ADMIN_EMAIL` | WordPress administrator email address.             |
| `WORDPRESS_USER`        | Regular WordPress username.                        |
| `WORDPRESS_USER_EMAIL`  | Regular WordPress user email address.              |
| `WORDPRESS_USER_ROLE`   | Role assigned to the regular WordPress user.       |

These values are not passwords and are supplied through the Compose
environment.

### Secrets

The WordPress container receives the following secrets:

| Secret              | Container path                   | Purpose                                   |
| ------------------- | -------------------------------- | ----------------------------------------- |
| `db_password`       | `/run/secrets/db_password`       | Password of the MariaDB application user. |
| `wp_admin_password` | `/run/secrets/wp_admin_password` | Password of the WordPress administrator.  |
| `wp_user_password`  | `/run/secrets/wp_user_password`  | Password of the regular WordPress user.   |

The secrets are mounted as files.

Processes and administrators with the required permissions inside the
container can read these files. Their purpose is to avoid storing passwords in
the Dockerfile, image layers, `.env`, or regular environment configuration.

### Persistent volume

The WordPress volume maps:

```text
Host:      /home/ypacileo/data/wordpress
Container: /var/www/html
```

WordPress has read-write access to this volume.

NGINX mounts the same volume as read-only:

```text
wordpress_data:/var/www/html:ro
```

This allows:

* WordPress and PHP-FPM to create and update application files;
* NGINX to read and serve static files;
* NGINX to avoid modifying the WordPress installation.

### Docker network

The WordPress container uses two service names as Docker DNS hostnames:

```text
mariadb
nginx
```

WordPress actively connects to MariaDB at:

```text
mariadb:3306
```

NGINX actively connects to WordPress at:

```text
wordpress:9000
```

WordPress does not need to know the IP addresses of either container.

### Dependency behavior

The Compose configuration contains:

```yaml
depends_on:
  - mariadb
```

This controls startup order. It starts the MariaDB container before the
WordPress container.

It does not guarantee that MariaDB has finished initialization or that it is
already accepting database connections.

The WordPress entrypoint handles actual readiness through `check-db.php`.

## Database connection probe

The database readiness probe is implemented in:

```text
srcs/requirements/wordpress/tools/check-db.php
```

The Dockerfile copies it to:

```text
/usr/local/bin/check-db.php
```

The entrypoint executes it with:

```sh
php /usr/local/bin/check-db.php
```

### Probe input

The PHP script reads:

| Environment variable | Purpose                            |
| -------------------- | ---------------------------------- |
| `MYSQL_HOST`         | MariaDB hostname.                  |
| `MYSQL_DATABASE`     | Database name.                     |
| `MYSQL_USER`         | MariaDB application-user name.     |
| `MYSQL_PASSWORD`     | MariaDB application-user password. |

The entrypoint reads `MYSQL_PASSWORD` from the secret file and exports it so
the PHP probe can access it.

### Probe flow

```text
Start check-db.php
        |
        v
Disable automatic MySQLi warnings
        |
        v
Read connection values
from the environment
        |
        v
Open a MySQLi connection to
MYSQL_HOST:3306
        |
        v
Did the connection succeed?
        |
   +----+----+
   |         |
  No        Yes
   |         |
   v         v
Exit with   Close the
status 1    connection
             |
             v
           Exit with
           status 0
```

The probe creates a real connection using:

* the MariaDB hostname;
* the MariaDB application user;
* the password supplied through the secret;
* the WordPress database name;
* TCP port 3306.

A successful probe therefore confirms more than the existence of the MariaDB
container. It confirms that:

* the MariaDB hostname can be resolved;
* port 3306 accepts connections;
* the supplied database user can authenticate;
* the requested database is accessible.

### Probe exit statuses

| Exit status | Meaning                            |
| ----------- | ---------------------------------- |
| `0`         | The database connection succeeded. |
| `1`         | The database connection failed.    |

The entrypoint uses these statuses to decide whether it should continue or
retry.

## Entrypoint

The entrypoint prepares the persistent WordPress installation before starting
PHP-FPM.

It runs every time the container starts.

### Entrypoint flow

```text
WordPress container starts
        |
        v
entrypoint.sh receives:
php-fpm8.2 -F
        |
        v
Enable strict shell behavior with set -eu
        |
        v
Create /var/www/html
        |
        v
Does wp-load.php exist?
        |
   +----+----+
   |         |
  Yes        No
   |         |
   |         v
   |    Copy WordPress core files
   |    from /usr/src/wordpress
   |         |
   +---------+
        |
        v
Validate required environment variables
        |
        v
Resolve and validate secret files
        |
        v
Read the three passwords
        |
        v
Export MariaDB connection values
        |
        v
Does wp-config.php exist?
        |
   +----+----+
   |         |
  Yes        No
   |         |
   |         v
   |    Generate wp-config.php
   |    with WP-CLI
   |         |
   +---------+
        |
        v
Run check-db.php
        |
        v
Can WordPress connect to MariaDB?
        |
   +----+----+
   |         |
  No        Yes
   |         |
   v         v
Wait 2 s    Continue
and retry       |
   |            v
   +------  Is WordPress installed?
                |
           +----+----+
           |         |
          Yes        No
           |         |
           |         v
           |    Install WordPress
           |         |
           +---------+
                |
                v
Does the regular WordPress user exist?
                |
           +----+----+
           |         |
          Yes        No
           |         |
           |         v
           |    Create the regular user
           |         |
           +---------+
                |
                v
Set www-data ownership
                |
                v
Create /run/php
                |
                v
Execute php-fpm8.2 -F
                |
                v
PHP-FPM becomes PID 1
```

The database readiness loop is limited to 30 attempts.

The entrypoint waits two seconds after each failed connection attempt. If
MariaDB is still unavailable when the limit is reached, the script prints an
error and terminates.

## WordPress file initialization

The entrypoint first creates:

```text
/var/www/html
```

It then checks for:

```text
/var/www/html/wp-load.php
```

If this file does not exist, the entrypoint copies the WordPress core from:

```text
/usr/src/wordpress
```

to:

```text
/var/www/html
```

The command copies hidden files and preserves file attributes:

```sh
cp -a /usr/src/wordpress/. /var/www/html/
```

The presence of `wp-load.php` is used as the marker that the WordPress core has
already been copied.

On later startups, the existing persistent files are reused and the copy is
skipped.

## Environment validation

The entrypoint requires the following database variables:

```text
MYSQL_DATABASE
MYSQL_USER
```

It also requires the following website installation variables:

```text
WORDPRESS_URL
WORDPRESS_TITLE
WORDPRESS_ADMIN_USER
WORDPRESS_ADMIN_EMAIL
```

The regular user requires:

```text
WORDPRESS_USER
WORDPRESS_USER_EMAIL
```

If one of these required variables is missing or empty, `set -u` and the shell
parameter checks cause the entrypoint to terminate.

The regular user's role is optional. If it is missing or empty, the entrypoint
uses:

```text
author
```

The MariaDB hostname is also optional. If it is missing or empty, the
entrypoint uses:

```text
mariadb
```

## Secret handling

The entrypoint uses these default secret paths:

```text
/run/secrets/db_password
/run/secrets/wp_admin_password
/run/secrets/wp_user_password
```

Custom paths can be supplied through:

```text
MYSQL_PASSWORD_FILE
WORDPRESS_ADMIN_PASSWORD_FILE
WORDPRESS_USER_PASSWORD_FILE
```

For each secret, the entrypoint:

1. checks that the file is readable;
2. reads its contents;
3. verifies that the resulting password is not empty.

The MariaDB password is exported as:

```text
MYSQL_PASSWORD
```

This allows `check-db.php` to read it through the PHP environment.

The WordPress administrator and regular-user passwords remain shell variables
used by WP-CLI during account creation.

## Creating `wp-config.php`

The entrypoint checks whether the following file exists:

```text
/var/www/html/wp-config.php
```

If it does not exist, WP-CLI generates it with:

```text
wp config create
```

The generated file contains the database connection settings:

* database name;
* database username;
* database password;
* database host and port;
* `utf8mb4` database character set.

The database host is written as:

```text
mariadb:3306
```

or as the value of `MYSQL_HOST` followed by port `3306`.

The command uses:

```text
--skip-check
```

This means WP-CLI writes `wp-config.php` without trying to connect to MariaDB
at that moment.

The separate `check-db.php` step performs the real database readiness check
afterward.

If `wp-config.php` already exists, the entrypoint preserves it and does not
generate it again.

## Waiting for MariaDB

After preparing `wp-config.php`, the entrypoint starts the database readiness
loop.

```text
Run check-db.php
        |
        v
Connection successful?
        |
   +----+----+
   |         |
  No        Yes
   |         |
   v         v
Has the     Print:
counter     MariaDB is ready
reached 30?     |
   |            v
+--+--+      Continue
|     |
Yes   No
|     |
v     v
Exit  Print attempt number
with  Wait two seconds
error Return to check-db.php
```

The loop protects WordPress from continuing while MariaDB is still
initializing.

It also detects invalid database credentials because `check-db.php` attempts
to authenticate with the application account.

## Installing WordPress

After the MariaDB connection succeeds, the entrypoint runs:

```text
wp core is-installed
```

This command uses the active WordPress directory and the database connection
stored in `wp-config.php`.

It determines whether the WordPress database tables already exist.

If WordPress is not installed, the entrypoint runs:

```text
wp core install
```

This operation:

* creates the WordPress database tables;
* sets the website URL;
* sets the website title;
* creates the WordPress administrator account;
* stores the administrator email;
* assigns the administrator password;
* skips the automatic installation email.

The MariaDB container creates the empty database. The WordPress container,
through WP-CLI, creates and populates the WordPress tables.

## Creating the regular WordPress user

After installation, the entrypoint checks for the regular user with:

```text
wp user get
```

If the user does not exist, it runs:

```text
wp user create
```

This creates the account using:

* `WORDPRESS_USER` as the username;
* `WORDPRESS_USER_EMAIL` as the email address;
* the password read from `wp_user_password`;
* `WORDPRESS_USER_ROLE` as the assigned role.

The default role is:

```text
author
```

An author can create, edit, publish, and delete their own posts. An author does
not have full administrative control over the website.

If the user already exists, the entrypoint preserves the account and does not
create it again.

## File ownership

After the WordPress checks and initialization, the entrypoint runs:

```sh
chown -R www-data:www-data /var/www/html
```

This gives the PHP-FPM user ownership of the active WordPress installation.

It allows PHP-FPM to work with files under `/var/www/html`, including themes,
plugins, uploaded media, and generated configuration files.

This recursive ownership operation runs every time the container starts.

## PHP-FPM runtime directory

The entrypoint ensures that the following directory exists:

```text
/run/php
```

PHP-FPM uses this location for runtime files.

The directory is part of the container filesystem and is recreated when
required.

## First startup

During the first startup:

1. `/var/www/html` is created;
2. the WordPress core is copied into the persistent volume;
3. the required variables are validated;
4. the three secret files are validated and read;
5. `wp-config.php` is generated;
6. the entrypoint waits for MariaDB;
7. the WordPress database tables are created;
8. the administrator account is created;
9. the regular WordPress user is created;
10. ownership is assigned to `www-data`;
11. `/run/php` is created;
12. PHP-FPM starts in the foreground.

## Later startups

During later startups:

1. the existing WordPress core files are reused;
2. all required environment variables are validated again;
3. all three secret files are read again;
4. the existing `wp-config.php` is preserved;
5. the MariaDB connection probe runs again;
6. `wp core is-installed` confirms that WordPress already exists;
7. `wp user get` confirms that the regular user already exists;
8. the account-creation steps are skipped;
9. ownership is applied again;
10. PHP-FPM starts in the foreground.

Unlike the MariaDB entrypoint, the WordPress entrypoint reads its secret files
on every container startup.

However, changing a WordPress password secret does not automatically update an
existing WordPress account because the account-creation commands are skipped
when the accounts already exist.

Changing only the database-password secret can also prevent the WordPress
container from starting if the new value does not match the password already
stored for the MariaDB application user.

## Idempotency

The entrypoint uses existence checks so that initialization operations can be
safely skipped when the persistent installation already exists.

| Check                                | Operation skipped when successful                    |
| ------------------------------------ | ---------------------------------------------------- |
| `/var/www/html/wp-load.php` exists   | Copying the WordPress core.                          |
| `/var/www/html/wp-config.php` exists | Generating the configuration file.                   |
| `wp core is-installed` succeeds      | Installing WordPress and creating the administrator. |
| `wp user get` succeeds               | Creating the regular WordPress user.                 |

This design prevents normal container restarts from recreating the website or
duplicating users.

The entrypoint still performs validation, secret loading, database readiness,
ownership correction, and PHP-FPM startup on every run.

## PID 1 and PHP-FPM

At the end of the entrypoint:

```sh
exec "$@"
```

replaces the shell with:

```text
php-fpm8.2 -F
```

The `-F` option keeps PHP-FPM in the foreground.

The process transition is:

```text
Before exec:

PID 1: entrypoint.sh
          |
          +-- WP-CLI and initialization commands


After exec:

PID 1: php-fpm8.2 -F
          |
          +-- PHP-FPM worker
          +-- PHP-FPM worker
```

Because PHP-FPM becomes PID 1:

* it receives Docker stop signals directly;
* it controls the container lifetime;
* the container stops if PHP-FPM exits;
* Docker can apply the configured restart policy correctly.

The container is not kept alive with an artificial command such as
`tail -f`, `sleep infinity`, or an infinite shell loop.

## Request flow

A browser does not connect directly to the WordPress container.

The request flow is:

```text
Browser
   |
   | HTTPS request on port 443
   v
NGINX
   |
   | Static file?
   +------------------------> Read from /var/www/html
   |
   | PHP request?
   v
FastCGI request to wordpress:9000
   |
   v
PHP-FPM
   |
   | Execute the WordPress PHP script
   v
WordPress
   |
   | SQL connection to mariadb:3306
   v
MariaDB
   |
   | Return database results
   v
WordPress and PHP-FPM
   |
   | FastCGI response
   v
NGINX
   |
   | HTTPS response
   v
Browser
```

For a static file, such as an image, CSS file, or JavaScript file, NGINX can
read it directly from the shared read-only WordPress volume.

For a PHP request, NGINX sends FastCGI parameters to PHP-FPM. PHP-FPM executes
the requested WordPress PHP code and returns the generated response to NGINX.

## Data distribution

WordPress data is divided between two persistent locations.

### WordPress volume

The WordPress volume stores files under:

```text
/var/www/html
```

This includes:

* WordPress core files;
* `wp-config.php`;
* themes;
* plugins;
* uploaded media;
* other filesystem content created by WordPress.

The volume is backed by:

```text
/home/ypacileo/data/wordpress
```

### MariaDB volume

The MariaDB volume stores structured website information under:

```text
/var/lib/mysql
```

This includes:

* posts and pages;
* comments;
* WordPress users and password hashes;
* website settings;
* plugin metadata;
* relationships between WordPress objects.

The volume is backed by:

```text
/home/ypacileo/data/mariadb
```

A complete WordPress backup therefore requires both the WordPress filesystem
data and the MariaDB database data.

## Combined build and startup flow

```text
IMAGE BUILD
===========

Docker Compose selects ./requirements/wordpress
        |
        v
Build wordpress:1.0 from debian:12
        |
        +-- Install PHP-FPM and PHP extensions
        +-- Download WP-CLI
        +-- Download WordPress 7.1
        +-- Copy www.conf
        +-- Copy entrypoint.sh
        +-- Copy check-db.php
        +-- Define ENTRYPOINT and CMD
        |
        v
The image contains the WordPress source,
but no active persistent installation


CONTAINER CREATION
==================

Docker Compose creates the WordPress container
        |
        +-- Supply non-sensitive environment variables
        +-- Mount three secrets under /run/secrets
        +-- Mount wordpress_data at /var/www/html
        +-- Connect the container to inception
        +-- Start MariaDB first through depends_on
        +-- Apply restart: unless-stopped
        |
        v
Docker combines ENTRYPOINT and CMD
        |
        v
entrypoint.sh php-fpm8.2 -F


CONTAINER STARTUP
=================

Prepare the active WordPress files
        |
        v
Validate variables and secrets
        |
        v
Create wp-config.php when missing
        |
        v
Wait for MariaDB using check-db.php
        |
        v
Install WordPress when necessary
        |
        v
Create the regular user when necessary
        |
        v
Set ownership and prepare /run/php
        |
        v
Execute php-fpm8.2 -F
        |
        v
PHP-FPM becomes PID 1
        |
        v
Listen on 0.0.0.0:9000
and wait for FastCGI requests
```

## Verification

Run the following commands from the repository root.

### Validate the Compose configuration

```sh
sudo docker compose -f srcs/docker-compose.yml \
    --env-file srcs/.env config --quiet
```

A successful validation produces no output and returns exit status `0`.

### Build the WordPress image

```sh
sudo docker compose -f srcs/docker-compose.yml \
    --env-file srcs/.env build wordpress
```

### Prepare the persistent directory

```sh
make prepare
```

This creates the host directory used by the WordPress volume:

```text
/home/ypacileo/data/wordpress
```

### Start MariaDB and WordPress

```sh
sudo docker compose -f srcs/docker-compose.yml \
    --env-file srcs/.env up -d mariadb wordpress
```

### Check the container states

```sh
sudo docker compose -f srcs/docker-compose.yml \
    --env-file srcs/.env ps -a mariadb wordpress
```

Both services should appear as running.

### Inspect the WordPress logs

```sh
sudo docker compose -f srcs/docker-compose.yml \
    --env-file srcs/.env logs wordpress
```

During the first startup, the logs should show:

* WordPress file initialization;
* `wp-config.php` creation;
* MariaDB readiness;
* WordPress installation;
* regular-user creation.

During later startups, the installation and account-creation messages should
not appear when the persistent installation already exists.

### Follow the WordPress logs

```sh
sudo docker compose -f srcs/docker-compose.yml \
    --env-file srcs/.env logs -f wordpress
```

Press `Ctrl+C` to stop following the output. This does not stop the container.

### Check the main process

```sh
sudo docker compose -f srcs/docker-compose.yml \
    --env-file srcs/.env top wordpress
```

The process list should show the PHP-FPM master and worker processes.

### Check the installed WordPress version

```sh
sudo docker compose -f srcs/docker-compose.yml \
    --env-file srcs/.env exec wordpress \
    wp core version --path=/var/www/html --allow-root
```

The expected version is:

```text
7.1
```

### Check whether WordPress is installed

```sh
sudo docker compose -f srcs/docker-compose.yml \
    --env-file srcs/.env exec wordpress \
    wp core is-installed --path=/var/www/html --allow-root
```

A successful command returns exit status `0`.

Display the exit status immediately afterward with:

```sh
echo $?
```

### List WordPress users

```sh
sudo docker compose -f srcs/docker-compose.yml \
    --env-file srcs/.env exec wordpress \
    wp user list --path=/var/www/html --allow-root
```

The result should include:

* the administrator account;
* the regular WordPress account;
* the role assigned to each account.

### Check the PHP-FPM configuration

```sh
sudo docker compose -f srcs/docker-compose.yml \
    --env-file srcs/.env exec wordpress \
    php-fpm8.2 -t
```

A successful test reports that the PHP-FPM configuration is valid.

### Check the database probe manually

```sh
sudo docker compose -f srcs/docker-compose.yml \
    --env-file srcs/.env exec wordpress \
    php /usr/local/bin/check-db.php
```

Display the exit status immediately afterward:

```sh
echo $?
```

Exit status `0` means the database connection succeeded.

### Check the persistent files

```sh
sudo ls -la /home/ypacileo/data/wordpress
```

The directory should contain the WordPress core files and `wp-config.php`.

### Test persistence

Create a post or upload a media file through WordPress. Then run:

```sh
make down
make
```

The content should still exist after the containers are recreated.

Do not use `make fclean` or `make re` for this test because those targets
delete the persistent WordPress and MariaDB data.

## Common failure points

| Symptom                                               | Possible cause                                                                                            |
| ----------------------------------------------------- | --------------------------------------------------------------------------------------------------------- |
| Container exits during startup                        | A required environment variable is missing or empty.                                                      |
| Secret-read error                                     | A required secret file is missing, unreadable, or not mounted.                                            |
| Empty-secret error                                    | One of the mounted password files is empty.                                                               |
| MariaDB readiness timeout                             | MariaDB is unavailable, the hostname is incorrect, or the database credentials do not match.              |
| `wp-config.php` is not created                        | The WordPress files are missing, the volume is not writable, or WP-CLI failed.                            |
| WordPress installation fails                          | MariaDB is unavailable, the database account lacks privileges, or the installation variables are invalid. |
| Regular user is not created                           | The user already exists or WP-CLI cannot access the WordPress installation.                               |
| NGINX returns a gateway error                         | PHP-FPM is not running, port 9000 is not reachable, or NGINX uses an incorrect FastCGI destination.       |
| Uploaded files disappear                              | The WordPress volume is missing, points to an incorrect host directory, or the host data was deleted.     |
| Posts or users disappear                              | The MariaDB persistent data was deleted or the database volume is incorrect.                              |
| A changed WordPress secret does not update an account | Existing WordPress users are not recreated during later startups.                                         |
| A changed database secret prevents startup            | The new secret does not match the password stored for the MariaDB application user.                       |
| Container repeatedly restarts                         | The entrypoint or PHP-FPM exits and the `unless-stopped` policy restarts the container.                   |

Use the container state and logs as the first diagnostic steps:

```sh
sudo docker compose -f srcs/docker-compose.yml \
    --env-file srcs/.env ps -a wordpress
```

```sh
sudo docker compose -f srcs/docker-compose.yml \
    --env-file srcs/.env logs wordpress
```
