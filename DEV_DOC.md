# Developer Documentation

## Overview

This document explains how to configure, build, launch and maintain the
Inception infrastructure.

The project consists of three services:

* NGINX as the HTTPS entry point.
* WordPress with PHP-FPM as the web application.
* MariaDB as the persistent database.

Each service is built from `debian:12` using its own Dockerfile. Docker Compose
connects the containers through a private bridge network and mounts persistent
storage for MariaDB and WordPress.

## Prerequisites

The project must be executed inside a Linux virtual machine.

The following tools and permissions are required:

* Docker Engine.
* The Docker Compose plugin.
* GNU Make.
* Administrator privileges through `sudo`.
* An available TCP port 443.
* Permission to create directories under `/home/ypacileo/data`.
* Local domain resolution for `ypacileo.42.fr`.

Verify the required tools:

```sh
docker --version
docker compose version
make --version
```

If Docker requires administrator privileges, use:

```sh
sudo docker --version
sudo docker compose version
```

The Makefile already executes Docker Compose through `sudo`.


## Environment configuration

Non-sensitive configuration is stored in:

```text
srcs/.env
```

The project currently uses the following variables:

| Variable                | Current value            | Purpose                                             |
| ----------------------- | ------------------------ | --------------------------------------------------- |
| `DOMAIN_NAME`           | `ypacileo.42.fr`         | Records the public domain used by the project.      |
| `MYSQL_DATABASE`        | `wordpress`              | Name of the MariaDB database used by WordPress.     |
| `MYSQL_USER`            | `wp_database_user`       | MariaDB application-user name.                      |
| `MYSQL_HOST`            | `mariadb`                | Compose service name used as the database hostname. |
| `WORDPRESS_URL`         | `https://ypacileo.42.fr` | Public URL used during WordPress installation.      |
| `WORDPRESS_TITLE`       | `Inception`              | Initial WordPress site title.                       |
| `WORDPRESS_ADMIN_USER`  | `ypacileo`               | WordPress administrator username.                   |
| `WORDPRESS_ADMIN_EMAIL` | `admin@example.com`      | WordPress administrator email address.              |
| `WORDPRESS_USER`        | `wp_author`              | Regular WordPress username.                         |
| `WORDPRESS_USER_EMAIL`  | `author@example.com`     | Regular WordPress user email address.               |
| `WORDPRESS_USER_ROLE`   | `author`                 | Role assigned to the regular WordPress user.        |
| `DATA_PATH`             | `/home/ypacileo/data`    | Host directory containing persistent project data.  |

Passwords must not be added to `srcs/.env`.

### Changing the domain

The domain is currently present in several configuration locations. Changing
only `DOMAIN_NAME` in `.env` is not sufficient.

To use another domain, keep these values consistent:

1. `DOMAIN_NAME` in `srcs/.env`.
2. `WORDPRESS_URL` in `srcs/.env`.
3. `server_name` in `srcs/requirements/nginx/conf/inception.conf`.
4. The certificate common name passed to OpenSSL in the NGINX Dockerfile.
5. The domain mapping in `/etc/hosts`.

Because the TLS certificate is generated during the NGINX image build, rebuild
the NGINX image after changing the domain.

## Domain resolution

When the website is accessed from inside the virtual machine, add the following
entry to `/etc/hosts`:

```text
127.0.0.1 ypacileo.42.fr
```

When accessing the website from another computer, map the domain to the
reachable IP address of the virtual machine instead.

Verify the mapping:

```sh
getent hosts ypacileo.42.fr
```

## Secrets

Create the secrets directory from the repository root if it does not exist:

```sh
mkdir -p secrets
```

The following files are required:

| Secret file                     | Used by               | Purpose                                   |
| ------------------------------- | --------------------- | ----------------------------------------- |
| `secrets/db_password.txt`       | MariaDB and WordPress | Password of the MariaDB application user. |
| `secrets/db_root_password.txt`  | MariaDB               | Password of the MariaDB root user.        |
| `secrets/wp_admin_password.txt` | WordPress             | Password of the WordPress administrator.  |
| `secrets/wp_user_password.txt`  | WordPress             | Password of the regular WordPress author. |

Generate independent random values:

```sh
openssl rand -base64 24 > secrets/db_password.txt
openssl rand -base64 24 > secrets/db_root_password.txt
openssl rand -base64 24 > secrets/wp_admin_password.txt
openssl rand -base64 24 > secrets/wp_user_password.txt
```

Restrict access to these files:

```sh
chmod 600 secrets/*.txt
```

The secret files match the pattern `secrets/*.txt` in `.gitignore` and must
never be committed to the repository.

Docker Compose mounts each secret into the containers that declare it. The
files become available under `/run/secrets/` while the containers are running.

Verify that all required files exist without printing their contents:

```sh
for file in \
    secrets/db_password.txt \
    secrets/db_root_password.txt \
    secrets/wp_admin_password.txt \
    secrets/wp_user_password.txt
do
    test -s "$file" || echo "Missing or empty secret: $file"
done
```

## Service configuration files

### NGINX

The NGINX configuration is stored in:

```text
srcs/requirements/nginx/conf/inception.conf
```

It:

* Listens on port 443.
* Allows TLS 1.2 and TLS 1.3.
* Uses the locally generated certificate and private key.
* Serves files from `/var/www/html`.
* Forwards PHP requests to `wordpress:9000` using FastCGI.

The NGINX Dockerfile generates a self-signed TLS certificate during the image
build. The certificate and private key therefore become part of the NGINX
image.

### MariaDB

The MariaDB configuration is stored in:

```text
srcs/requirements/mariadb/conf/99-inception.cnf
```

MariaDB listens on port 3306 on the container network. The port is not
published on the host.

Its entrypoint:

1. Creates the required runtime directories.
2. Setects whether the data directory has already been initialized.
3. Reads the database passwords from Docker Secrets.
4. Initializes MariaDB on the first launch.
5. Creates the WordPress database and application user.
6. Grants the required database privileges.
7. Starts `mariadbd` as the container's PID 1.

### WordPress and PHP-FPM

The PHP-FPM pool configuration is stored in:

```text
srcs/requirements/wordpress/conf/www.conf
```

PHP-FPM listens on port 9000 inside the Docker network.

The WordPress entrypoint:

1. Copies the WordPress files into the persistent volume when necessary.
2. Reads the required passwords from Docker Secrets.
3. Generates `wp-config.php` when it does not exist.
4. Waits until MariaDB accepts connections.
5. Installs WordPress when it is not already installed.
6. Creates the regular WordPress author when the user does not exist.
7. Starts PHP-FPM in the foreground as PID 1.

The database readiness check is implemented by:

```text
srcs/requirements/wordpress/tools/check-db.php
```

Docker Compose `depends_on` controls startup order, but it does not guarantee
that MariaDB is ready to accept connections. The PHP probe provides the
required readiness retry mechanism.

## Validate the configuration

Before building the images, validate the resolved Docker Compose configuration:

```sh
sudo docker compose -f srcs/docker-compose.yml \
    --env-file srcs/.env config --quiet
```

A successful validation produces no output and returns exit status `0`.

Display the image names that Compose will build:

```sh
sudo docker compose -f srcs/docker-compose.yml \
    --env-file srcs/.env config --images
```

The expected images are:

```text
mariadb:1.0
nginx:1.0
wordpress:1.0
```

## Build and launch with the Makefile

Run all Makefile commands from the repository root.

### Build and start the complete infrastructure

```sh
make
```

The default target executes the equivalent of `make up`.

The `up` target:

1. Validates that `DATA_PATH` matches `/home/*/data`.
2. Creates the MariaDB and WordPress host directories.
3. Builds the three images.
4. Creates the network and volumes.
5. Starts the containers in detached mode.

### Build without starting containers

```sh
make build
```

This creates the persistent directories and builds the images without launching
the services.

### Prepare persistent directories only

```sh
make prepare
```

This creates:

```text
/home/ypacileo/data/mariadb
/home/ypacileo/data/wordpress
```

### Start existing stopped containers

```sh
make start
```

This works after `make stop`. It does not recreate containers removed by
`make down`.

### Stop existing containers

```sh
make stop
```

This stops the containers without removing them.

### Restart existing containers

```sh
make restart
```

This restarts the current containers without rebuilding their images.

### Remove containers and network

```sh
make down
```

This removes the containers and Compose network while preserving images,
volumes and persistent data.

### Display service status

```sh
make status
```

### Follow service logs

```sh
make logs
```

Press `Ctrl+C` to stop following the logs. This does not stop the containers.

### Clean containers and network

```sh
make clean
```

In the current Makefile, `make clean` performs the same Compose cleanup as
`make down`. Persistent data is preserved.

### Full cleanup

```sh
make fclean
```

This removes:

* Containers.
* The Compose network.
* The three project images.
* The two named volumes.
* `/home/ypacileo/data/mariadb`.
* `/home/ypacileo/data/wordpress`.

> [!WARNING]
> This operation permanently deletes the WordPress website and MariaDB data.

### Full rebuild

```sh
make re
```

This executes `make fclean` and then rebuilds the entire project from the
beginning.

## Build and launch with Docker Compose

The Makefile is the main project interface. The equivalent Docker Compose
commands are useful for development and diagnostics.

Define the complete command conceptually as:

```text
sudo docker compose -f srcs/docker-compose.yml --env-file srcs/.env
```

### Build images

```sh
sudo docker compose -f srcs/docker-compose.yml \
    --env-file srcs/.env build
```

### Build and start

Run `make prepare` first when the host data directories do not exist:

```sh
make prepare
sudo docker compose -f srcs/docker-compose.yml \
    --env-file srcs/.env up -d --build
```

### Display all container states

```sh
sudo docker compose -f srcs/docker-compose.yml \
    --env-file srcs/.env ps -a
```

### Display logs from one service

```sh
sudo docker compose -f srcs/docker-compose.yml \
    --env-file srcs/.env logs mariadb
```

The service name can be replaced with `wordpress` or `nginx`.

Follow the logs continuously with:

```sh
sudo docker compose -f srcs/docker-compose.yml \
    --env-file srcs/.env logs -f wordpress
```

### Execute a shell inside a running container

```sh
sudo docker compose -f srcs/docker-compose.yml \
    --env-file srcs/.env exec mariadb sh
```

Replace `mariadb` with the required service name.

### Rebuild one service

```sh
sudo docker compose -f srcs/docker-compose.yml \
    --env-file srcs/.env build nginx
```

Recreate it with the new image:

```sh
sudo docker compose -f srcs/docker-compose.yml \
    --env-file srcs/.env up -d --no-deps nginx
```

## Container management

### List project containers

```sh
sudo docker compose -f srcs/docker-compose.yml \
    --env-file srcs/.env ps -a
```

### Inspect a container

First obtain its name:

```sh
sudo docker compose -f srcs/docker-compose.yml \
    --env-file srcs/.env ps
```

Then inspect it:

```sh
sudo docker inspect <container-name>
```

Replace `<container-name>` with the actual container name shown by Compose.

### Check restart attempts

```sh
sudo docker inspect \
    --format 'Status={{.State.Status}} ExitCode={{.State.ExitCode}} RestartCount={{.RestartCount}}' \
    <container-name>
```

### Check the processes running inside the services

```sh
sudo docker compose -f srcs/docker-compose.yml \
    --env-file srcs/.env top
```

## Network management

List Docker networks:

```sh
sudo docker network ls
```

Inspect the project network:

```sh
sudo docker network inspect inception
```
This command displays:

* The network driver and configuration.
* The containers attached to the network.
* The internal IP address assigned to each container.
* The network subnet and gateway.

It does not show which ports are actively listening inside each container.

The internal service endpoints are defined by their configuration:

NGINX listens on port 443;
PHP-FPM listens on port 9000;
MariaDB listens on port 3306;
NGINX reaches PHP-FPM at wordpress:9000;
WordPress reaches MariaDB at mariadb:3306.

## Volume management

List the project volumes:

```sh
sudo docker volume ls --filter name=srcs_
```

The expected volume names are:

```text
srcs_mariadb_data
srcs_wordpress_data
```

The actual names use the Compose project prefix.

Inspect a volume:

```sh
sudo docker volume inspect srcs_mariadb_data
```

```sh
sudo docker volume inspect srcs_wordpress_data
```

The Compose volume definitions use the local driver with bind options:

| Compose volume   | Host storage                    | Container mount  |
| ---------------- | ------------------------------- | ---------------- |
| `mariadb_data`   | `/home/ypacileo/data/mariadb`   | `/var/lib/mysql` |
| `wordpress_data` | `/home/ypacileo/data/wordpress` | `/var/www/html`  |

The logical volume names are managed by Docker Compose, while the actual files
are stored in the configured host directories.

### Remove containers while preserving data

```sh
make down
```

This removes containers and the network but preserves the volume definitions
and host data.

### Remove volume definitions without manually deleting host data

```sh
sudo docker compose -f srcs/docker-compose.yml \
    --env-file srcs/.env down --volumes
```

Because these volumes use host directories through local bind options, removing
the Docker volume objects does not by itself guarantee removal of the files
stored under `/home/ypacileo/data`.

Use `make fclean` only when both the Docker resources and persistent host data
must be deleted.

## Data storage and persistence

The project separates database data from WordPress filesystem data.

### MariaDB data

MariaDB stores its data inside the container at:

```text
/var/lib/mysql
```

This path is backed by:

```text
/home/ypacileo/data/mariadb
```

It contains:

* MariaDB system tables.
* WordPress posts and pages.
* Comments.
* WordPress users and password hashes.
* WordPress settings and metadata.

### WordPress data

WordPress stores its files inside the container at:

```text
/var/www/html
```

This path is backed by:

```text
/home/ypacileo/data/wordpress
```

It contains:

* WordPress core files.
* `wp-config.php`.
* Themes.
* Plugins.
* Uploaded media.

The WordPress container mounts this volume with read-write access. NGINX mounts
the same volume as read-only so it can serve static files without modifying the
WordPress installation.

### Persistence across operations

| Operation      | Containers    | Images    | Volume definitions | Host data                 |
| -------------- | ------------- | --------- | ------------------ | ------------------------- |
| `make stop`    | Stopped       | Preserved | Preserved          | Preserved                 |
| `make start`   | Started again | Preserved | Preserved          | Preserved                 |
| `make restart` | Restarted     | Preserved | Preserved          | Preserved                 |
| `make down`    | Removed       | Preserved | Preserved          | Preserved                 |
| `make clean`   | Removed       | Preserved | Preserved          | Preserved                 |
| `make fclean`  | Removed       | Removed   | Removed            | Deleted                   |
| `make re`      | Recreated     | Rebuilt   | Recreated          | Deleted and reinitialized |

Container files that are not stored in one of these persistent mounts disappear
when the container is removed.

## Initialization and idempotency

The MariaDB and WordPress entrypoints are designed to distinguish between a
first launch and a restart with existing data.

MariaDB checks whether its internal system directory already exists. If it
does, database initialization is skipped.

WordPress checks whether its core files, `wp-config.php`, database installation
and regular user already exist before attempting to create them.

As a result:

* Restarting containers does not recreate the database.
* Existing WordPress users are not created again.
* `wp-config.php` is preserved.
* Persistent content survives container replacement.
* Changing a secret file alone does not update an existing account password.

A complete fresh initialization requires deleting the persistent data with
`make fclean` or `make re`.

## Verification after launch

### Check container states

```sh
sudo docker compose -f srcs/docker-compose.yml \
    --env-file srcs/.env ps -a
```

All three services should be running.

### Check the website

```sh
curl -kI https://ypacileo.42.fr
```

The `-k` option accepts the self-signed certificate.

### Verify TLS 1.2

```sh
openssl s_client \
    -connect ypacileo.42.fr:443 \
    -servername ypacileo.42.fr \
    -tls1_2
```

The TLS handshake should succeed.

### Verify that TLS 1.1 is rejected

```sh
openssl s_client \
    -connect ypacileo.42.fr:443 \
    -servername ypacileo.42.fr \
    -tls1_1
```

The handshake should fail because NGINX allows only TLS 1.2 and TLS 1.3.

### Check data directories

```sh
sudo ls -la /home/ypacileo/data/mariadb
sudo ls -la /home/ypacileo/data/wordpress
```

Both directories should contain data after a successful first initialization.

### Check logs

```sh
make logs
```

There should be no repeated fatal errors or continuous restart loop.

## Development workflow

After changing a Dockerfile, configuration file or entrypoint script:

1. Validate the Compose configuration.
2. Rebuild the affected image.
3. Recreate the affected container.
4. Check its status.
5. Inspect its logs.
6. Test the HTTPS endpoint.

For example, after changing the NGINX configuration:

```sh
sudo docker compose -f srcs/docker-compose.yml \
    --env-file srcs/.env config --quiet

sudo docker compose -f srcs/docker-compose.yml \
    --env-file srcs/.env build nginx

sudo docker compose -f srcs/docker-compose.yml \
    --env-file srcs/.env up -d --no-deps nginx

sudo docker compose -f srcs/docker-compose.yml \
    --env-file srcs/.env ps -a

sudo docker compose -f srcs/docker-compose.yml \
    --env-file srcs/.env logs nginx

curl -kI https://ypacileo.42.fr
```

Avoid using `make re` for ordinary development changes because it deletes all
persistent data. Use a targeted image rebuild whenever possible.
