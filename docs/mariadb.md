# MariaDB Service

## Overview

The MariaDB service provides the relational database used by WordPress. It is
built from Debian 12, runs in its own container, and communicates with
WordPress through the `inception` Docker bridge network.

MariaDB listens on port 3306 inside the Docker network, but this port is not
published on the host. WordPress reaches the database server by using the
Compose service name `mariadb` as its hostname.

The database files are stored in a persistent volume backed by the following
host directory:

```text
/home/ypacileo/data/mariadb
```

This allows the database to survive container removal, recreation, and image
rebuilds, provided that the persistent host directory is not deleted.

## Files

| File                                              | Purpose                                                                              |
| ------------------------------------------------- | ------------------------------------------------------------------------------------ |
| `srcs/requirements/mariadb/Dockerfile`            | Builds the MariaDB image and defines its startup command.                            |
| `srcs/requirements/mariadb/conf/99-inception.cnf` | Configures the MariaDB listening address and port.                                   |
| `srcs/requirements/mariadb/tools/entrypoint.sh`   | Initializes MariaDB on the first startup and launches the final server.              |
| `srcs/docker-compose.yml`                         | Supplies the build context, variables, secrets, volume, network, and restart policy. |

## Dockerfile

The Dockerfile describes how the `mariadb:1.0` image is built. These operations
happen during the image build, before any MariaDB container is started.

### Dockerfile build flow

```text
Start from debian:12
        |
        v
Update the APT package index
        |
        v
Install mariadb-server
        |
        v
Remove the APT package lists
        |
        v
Remove the packaged files from /var/lib/mysql
        |
        v
Copy 99-inception.cnf
        |
        v
Copy entrypoint.sh
        |
        v
Make entrypoint.sh executable
        |
        v
Document container port 3306
        |
        v
Define ENTRYPOINT and CMD
        |
        v
The mariadb:1.0 image is ready
```

The image is based on:

```dockerfile
FROM debian:12
```

The `mariadb-server` package provides the database server and the tools used by
the entrypoint during initialization.

The package is installed with `--no-install-recommends` to avoid installing
optional packages that are not required by the service.

After installation, the APT package lists are removed to reduce the final image
size.

The Dockerfile also removes the packaged contents of:

```text
/var/lib/mysql
```

As a result, the image does not contain an initialized database. During the
first container startup, the entrypoint initializes `/var/lib/mysql` directly
inside the mounted persistent volume. This ensures that the generated database
files are stored persistently from the beginning.

The following Dockerfile instruction documents the port used by MariaDB:

```dockerfile
EXPOSE 3306
```

`EXPOSE` is image metadata. It does not publish port 3306 on the host. A
Compose `ports` mapping would be required to publish it, and the MariaDB service
intentionally has no such mapping.

### Container startup definition

The Dockerfile defines:

```dockerfile
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["mariadbd", "--user=mysql"]
```

Docker combines these instructions and starts the equivalent of:

```text
/usr/local/bin/entrypoint.sh mariadbd --user=mysql
```

The entrypoint performs any required initialization and eventually executes the
command received through `CMD`.

## MariaDB configuration

The configuration file:

```text
srcs/requirements/mariadb/conf/99-inception.cnf
```

is copied into the image at:

```text
/etc/mysql/mariadb.conf.d/99-inception.cnf
```

It contains the configuration used by the MariaDB server:

| Setting        | Value     | Effect                                                                |
| -------------- | --------- | --------------------------------------------------------------------- |
| `bind-address` | `0.0.0.0` | Makes MariaDB listen on every network interface inside the container. |
| `port`         | `3306`    | Sets the internal TCP port used by WordPress.                         |

Binding to `0.0.0.0` allows MariaDB to accept connections through the Docker
network.

This does not expose MariaDB directly on the host because the Compose service
does not define a `ports` mapping for port 3306.

MariaDB reads this configuration when `mariadbd` starts. However, the temporary
initialization server is launched with:

```text
--skip-networking
```

This command-line option disables TCP networking for the temporary server.
Therefore, it accepts only local Unix socket connections even though
`99-inception.cnf` contains:

```text
bind-address = 0.0.0.0
port = 3306
```

## Docker Compose integration

Docker Compose provides the MariaDB container with the following resources:

| Compose setting | Value                             | Purpose                                                                |
| --------------- | --------------------------------- | ---------------------------------------------------------------------- |
| Build context   | `./requirements/mariadb`          | Selects the MariaDB Dockerfile and its local files.                    |
| Image           | `mariadb:1.0`                     | Names and versions the built image.                                    |
| Environment     | `MYSQL_DATABASE`, `MYSQL_USER`    | Supplies the non-sensitive database and application-user names.        |
| Secrets         | `db_password`, `db_root_password` | Supplies the application-user and root passwords as files.             |
| Volume          | `mariadb_data:/var/lib/mysql`     | Persists the MariaDB data directory.                                   |
| Network         | `inception`                       | Connects MariaDB to WordPress through a Docker bridge network.         |
| Restart policy  | `unless-stopped`                  | Automatically restarts the container unless it was explicitly stopped. |

The secrets are mounted inside the container at:

```text
/run/secrets/db_password
/run/secrets/db_root_password
```

The passwords are therefore supplied as files instead of regular environment
variables.

The secret files can still be read from inside a container that has permission
to use them. Docker Secrets reduce accidental exposure through image layers,
Dockerfiles, environment-variable listings, and source-controlled
configuration, but they do not make the values invisible to processes or
administrators inside the container.

The MariaDB volume uses the local driver with bind options:

```text
Host:      /home/ypacileo/data/mariadb
Container: /var/lib/mysql
```

The Docker network has the explicit name:

```text
inception
```

WordPress uses the Compose service name `mariadb` as a DNS hostname. It does not
need to know the container's IP address, which may change when the container is
recreated.

## Entrypoint

The entrypoint runs every time the MariaDB container starts.

Its behavior depends on whether the MariaDB system directory already exists in
the persistent volume.

The entrypoint checks for:

```text
/var/lib/mysql/mysql
```

If this directory exists, MariaDB has already been initialized. If it does not
exist, the entrypoint performs the first-start initialization.

### Entrypoint flow

```text
MariaDB container starts
        |
        v
entrypoint.sh receives:
mariadbd --user=mysql
        |
        v
Enable strict shell behavior with set -eu
        |
        v
Create the runtime directories
        |
        v
Does /var/lib/mysql/mysql exist?
        |
   +----+----+
   |         |
  Yes        No
   |         |
   |         v
   |    Validate environment variables
   |    and secret files
   |         |
   |         v
   |    Read both passwords
   |         |
   |         v
   |    Initialize /var/lib/mysql
   |         |
   |         v
   |    Start temporary MariaDB
   |    with TCP networking disabled
   |         |
   |         v
   |    Check local server readiness
   |         |
   |    +----+----+
   |    |         |
   | Not ready   Ready
   |    |         |
   |    v         v
   | Wait 1 s    Create database,
   |    |        user, and privileges
   |    |         |
   |    +-------> Return to the
   |              readiness check
   |              when not ready
   |                   |
   |                   v
   |              Stop temporary
   |              MariaDB cleanly
   |                   |
   +-------------------+
        |
        v
Execute mariadbd --user=mysql
        |
        v
mariadbd becomes PID 1
        |
        v
Listen on port 3306 and wait
for WordPress connections
```

The readiness retry is limited to 30 attempts. If the temporary server does not
become ready within that limit, the entrypoint reports an error and terminates.

## First-start initialization

When the persistent database directory is empty, the entrypoint performs the
following operations:

1. creates the required runtime directories;
2. validates `MYSQL_DATABASE` and `MYSQL_USER`;
3. verifies that both secret files are readable;
4. reads the application-user and root passwords;
5. verifies that neither password is empty;
6. initializes the MariaDB system files;
7. starts a temporary MariaDB server;
8. waits until the temporary server accepts local connections;
9. creates the WordPress database;
10. creates the MariaDB application user;
11. grants the application user access to the WordPress database;
12. sets the local MariaDB root password;
13. flushes the privilege changes;
14. stops the temporary server;
15. starts the final MariaDB server.

The temporary server is started with:

```text
--skip-networking
```

Consequently, it does not accept TCP connections. It is available only inside
the MariaDB container through its local Unix socket.

## Temporary server readiness

The entrypoint checks the temporary server with:

```sh
mariadb-admin ping --silent
```

No hostname or TCP port is supplied to this command. Because the temporary
server has TCP networking disabled, `mariadb-admin` communicates with it
through the local Unix socket.

This check answers the following question:

```text
Is the temporary MariaDB server ready to execute local SQL commands?
```

It does not answer:

```text
Is MariaDB accepting WordPress connections on port 3306?
```

The temporary server exists only to prepare the database before the final
network-accessible server starts.

## Initialization SQL

After the temporary MariaDB server becomes ready, the entrypoint connects
locally as root and performs the required SQL initialization.

| Operation                   | Result                                                               |
| --------------------------- | -------------------------------------------------------------------- |
| Create the database         | Creates the database named by `MYSQL_DATABASE` if it does not exist. |
| Create the application user | Creates the account named by `MYSQL_USER` if it does not exist.      |
| Grant privileges            | Grants the application user privileges on the WordPress database.    |
| Set the root password       | Assigns the root secret to the local MariaDB root account.           |
| Flush privileges            | Reloads the privilege information after the account changes.         |

The application account is created with the host component:

```text
'%'
```

This allows the account to authenticate from any host that can reach the
MariaDB server. In this project, MariaDB is not published on the host, and
network access is limited in practice to containers connected to the
`inception` network.

The application user receives privileges on the WordPress database, not on
every database managed by MariaDB.

The MariaDB entrypoint creates only an empty database and the required SQL
accounts. It does not create the WordPress tables.

WordPress creates its own tables later when WP-CLI runs:

```text
wp core install
```

inside the WordPress container.

## Transition to the final server

MariaDB does not change a single running process from Unix socket-only mode to
TCP port 3306.

The startup uses two separate MariaDB server processes.

### Temporary MariaDB process

The first process is started by the entrypoint during initial setup:

```text
mariadbd --user=mysql --skip-networking
```

This process:

* accepts only local Unix socket connections;
* allows the entrypoint to execute the initialization SQL;
* never accepts WordPress TCP connections;
* is shut down after initialization.

### Final MariaDB process

After initialization, the temporary server is stopped. The entrypoint then
runs:

```sh
exec "$@"
```

The value of `"$@"` is:

```text
mariadbd --user=mysql
```

This starts a new MariaDB process without `--skip-networking`.

The final server reads `99-inception.cnf` and begins listening on:

```text
0.0.0.0:3306
```

Only this final process accepts TCP connections from WordPress.

## MariaDB readiness and WordPress readiness

The infrastructure uses two separate readiness checks.

### MariaDB local readiness check

The first check happens inside the MariaDB container:

```text
Temporary MariaDB
        |
        v
Local Unix socket
        |
        v
mariadb-admin ping
        |
        v
Execute initialization SQL
```

Its purpose is to determine whether the temporary server is ready for local
database initialization.

### WordPress TCP readiness check

The second check happens inside the WordPress container after the final MariaDB
server has started.

The WordPress entrypoint runs `check-db.php`, which attempts a real database
connection to:

```text
mariadb:3306
```

If the connection fails, the WordPress entrypoint waits two seconds and tries
again. WordPress installation continues only after the final MariaDB server
accepts the connection.

```text
MariaDB container
        |
        +-- Start temporary MariaDB
        |       |
        |       +-- Unix socket only
        |       +-- Check local readiness
        |       +-- Execute initialization SQL
        |       +-- Stop temporary server
        |
        +-- Start final MariaDB
                |
                +-- Listen on port 3306
                +-- Wait for TCP connections
                            ^
                            |
                    mariadb:3306
                            |
WordPress container        |
        |                   |
        +-- Run check-db.php
        +-- Retry after two seconds
        +-- Continue when MariaDB is ready
```

Docker Compose `depends_on` controls container startup order, but it does not
guarantee that MariaDB is ready to accept connections.

The WordPress `check-db.php` script provides the runtime readiness check that
`depends_on` alone does not provide.

## Later container startups

On later startups, the following directory already exists in the persistent
volume:

```text
/var/lib/mysql/mysql
```

The entrypoint therefore skips the initialization block.

It does not:

* initialize the system tables again;
* start the temporary server;
* recreate the database;
* recreate the application user;
* reset the root password;
* reread the password secret files.

Instead, it immediately executes:

```text
mariadbd --user=mysql
```

using the existing database files.

This prevents stored databases, users, passwords, and privileges from being
overwritten during container restarts or recreation.

Changing a secret file alone does not update a password already stored in an
initialized MariaDB database.

## Combined build and startup flow

```text
IMAGE BUILD
===========

Docker Compose selects ./requirements/mariadb
        |
        v
Build mariadb:1.0 from debian:12
        |
        +-- Install mariadb-server
        +-- Copy 99-inception.cnf
        +-- Copy entrypoint.sh
        +-- Define ENTRYPOINT and CMD
        |
        v
The image is ready without an initialized database


CONTAINER CREATION
==================

Docker Compose creates the MariaDB container
        |
        +-- Supply MYSQL_DATABASE and MYSQL_USER
        +-- Mount two secrets under /run/secrets
        +-- Mount mariadb_data at /var/lib/mysql
        +-- Connect the container to inception
        +-- Apply restart: unless-stopped
        |
        v
Docker combines ENTRYPOINT and CMD
        |
        v
entrypoint.sh mariadbd --user=mysql


CONTAINER STARTUP
=================

Create the required runtime directories
        |
        v
Is the database already initialized?
        |
   +----+----+
   |         |
  No        Yes
   |         |
   v         v
Validate     Reuse the existing
settings     persistent database
and secrets
   |
   v
Initialize the database files
   |
   v
Start the temporary local server
   |
   v
Create the database and SQL user
   |
   v
Stop the temporary server
   |
   +---------+
             |
             v
Execute mariadbd --user=mysql
             |
             v
mariadbd becomes PID 1
             |
             v
Listen on 0.0.0.0:3306 inside
the inception Docker network
```

The temporary server never accepts network connections. Only the final
`mariadbd` process uses the configured TCP address and port.

## PID 1 and shutdown behavior

Docker initially starts:

```text
/usr/local/bin/entrypoint.sh mariadbd --user=mysql
```

The entrypoint is initially the container's main process.

At the end of the script:

```sh
exec "$@"
```

replaces the shell process with the final MariaDB process. It does not start
MariaDB as an additional child process.

The resulting process structure is:

```text
Before exec:

PID 1: entrypoint.sh
          |
          +-- initialization commands


After exec:

PID 1: mariadbd --user=mysql
```

Because `mariadbd` becomes PID 1:

* it receives Docker stop signals directly;
* it controls the lifetime of the container;
* the container stops when `mariadbd` exits;
* Docker can manage its shutdown and restart behavior correctly.

The container is not kept alive with an artificial command such as:

```text
tail -f
sleep infinity
```

or an infinite shell loop.

## Persistent data

MariaDB stores all database data inside the container at:

```text
/var/lib/mysql
```

This path is mounted from:

```text
/home/ypacileo/data/mariadb
```

The directory contains:

* MariaDB system tables;
* the WordPress database;
* WordPress posts and pages;
* comments;
* WordPress users and password hashes;
* WordPress settings and metadata;
* MariaDB users and privilege information.

The container can be removed and recreated without losing this information, as
long as the host directory is preserved and mounted again at
`/var/lib/mysql`.

## Verification

Run the following commands from the repository root.

### Validate the Compose configuration

```sh
sudo docker compose -f srcs/docker-compose.yml \
    --env-file srcs/.env config --quiet
```

A successful validation produces no output and returns exit status `0`.

### Build the MariaDB image

```sh
sudo docker compose -f srcs/docker-compose.yml \
    --env-file srcs/.env build mariadb
```

### Prepare the persistent directory

The host directory must exist before Docker Compose mounts it:

```sh
make prepare
```

This creates the MariaDB data directory under:

```text
/home/ypacileo/data/mariadb
```

### Start MariaDB

```sh
sudo docker compose -f srcs/docker-compose.yml \
    --env-file srcs/.env up -d mariadb
```

### Check the container state

```sh
sudo docker compose -f srcs/docker-compose.yml \
    --env-file srcs/.env ps -a mariadb
```

The service should appear as running.

### Inspect the logs

```sh
sudo docker compose -f srcs/docker-compose.yml \
    --env-file srcs/.env logs mariadb
```

During the first startup, the logs should show:

* data-directory initialization;
* temporary server startup;
* temporary server readiness;
* database and user creation;
* temporary server shutdown;
* final MariaDB startup.

During later startups, the initialization messages should not appear because
the persistent database already exists.

### Follow the logs

```sh
sudo docker compose -f srcs/docker-compose.yml \
    --env-file srcs/.env logs -f mariadb
```

Press `Ctrl+C` to stop following the output. This does not stop the container.

### Inspect the Docker network

```sh
sudo docker network inspect inception
```

The MariaDB container should appear in the network's `Containers` section.

This confirms that the container is attached to the network. It does not prove
that MariaDB is actively listening on port 3306.

### Check the main process

```sh
sudo docker compose -f srcs/docker-compose.yml \
    --env-file srcs/.env top mariadb
```

The process list should show:

```text
mariadbd --user=mysql
```

as the service's main process.

### Check the listening socket

The listening socket can be checked from inside the running MariaDB container:

```sh
sudo docker compose -f srcs/docker-compose.yml \
    --env-file srcs/.env exec mariadb ss -lnt
```

The output should show a listening TCP socket on port 3306.

This command depends on the `ss` utility being available in the image.

### Test persistence

First, create or modify some data in MariaDB or WordPress.

Then remove and recreate the containers:

```sh
make down
make
```

The database should still contain the previous data because `make down` does
not delete:

```text
/home/ypacileo/data/mariadb
```

Do not use `make fclean` or `make re` for this test because those targets delete
the persistent data.

## Common failure points

| Symptom                                               | Possible cause                                                                                                           |
| ----------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------ |
| Container exits during first initialization           | A required environment variable is missing.                                                                              |
| Secret-read error during first initialization         | A required secret file is missing, unreadable, or not mounted.                                                           |
| Empty-secret error during first initialization        | One of the mounted password files is empty.                                                                              |
| Temporary server timeout                              | MariaDB did not accept local Unix socket connections within 30 attempts.                                                 |
| WordPress cannot connect                              | MariaDB is not ready, the database credentials are inconsistent, or both services are not connected to the same network. |
| A changed secret does not change an existing password | The database was already initialized, so the stored MariaDB account was not updated.                                     |
| Data disappears after container recreation            | The persistent host directory was deleted or the volume points to an incorrect `DATA_PATH`.                              |
| Container repeatedly restarts                         | The MariaDB process is terminating and the `unless-stopped` policy is restarting the container.                          |

Use the container state and logs as the first diagnostic steps:

```sh
sudo docker compose -f srcs/docker-compose.yml \
    --env-file srcs/.env ps -a mariadb
```

```sh
sudo docker compose -f srcs/docker-compose.yml \
    --env-file srcs/.env logs mariadb
```
