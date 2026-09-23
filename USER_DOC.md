# User Documentation

## Services provided

The Inception stack provides a WordPress website through three services:

| Service                | Purpose                                                                                | Publicly accessible                  |
| ---------------------- | -------------------------------------------------------------------------------------- | ------------------------------------ |
| NGINX                  | Accepts HTTPS connections, serves static files and forwards PHP requests to WordPress. | Yes, on port 443.                    |
| WordPress with PHP-FPM | Runs the website and provides the administration panel.                                | No. It is reached through NGINX.     |
| MariaDB                | Stores WordPress posts, pages, comments, users and configuration.                      | No. It is reached only by WordPress. |

NGINX is the only public entry point. WordPress and MariaDB communicate through
the private Docker network and do not publish ports on the host.

## Before starting

Run all Makefile commands from the root of the repository.

Before the first launch, check that:

* Docker Engine and the Docker Compose plugin are installed.
* The `srcs/.env` configuration file exists.
* The four required password files exist under `secrets/`.
* The domain `ypacileo.42.fr` resolves to the machine running the stack.

When accessing the website from inside the virtual machine, `/etc/hosts` should
contain:

```text
127.0.0.1 ypacileo.42.fr
```

When accessing it from another computer, replace `127.0.0.1` with the reachable
IP address of the virtual machine.

## Start and stop the project

### Build and start

```sh
make
```

This command creates the persistent data directories when necessary, builds
the three images and starts the containers in the background.

### Stop the services

```sh
make stop
```

This stops the existing containers without removing them. Their persistent
data is preserved.

### Start stopped services

```sh
make start
```

This starts containers that already exist after `make stop`.

### Restart the services

```sh
make restart
```

This restarts the existing containers without rebuilding their images.

### Remove the containers and network

```sh
make down
```

This stops and removes the containers and the Compose network. The images,
volumes and persistent website data are preserved. Run `make` to recreate and
start the infrastructure.

> [!WARNING]
> `make fclean` and `make re` delete the persistent WordPress and MariaDB data
> stored under `/home/ypacileo/data`. Do not use them when the existing website
> data must be preserved.

## Access the website

Open the following address in a web browser:

```text
https://ypacileo.42.fr
```

The project uses a self-signed TLS certificate. A browser may therefore display
a certificate warning. This is expected in the local project environment.

If the website does not open, first verify the domain mapping, then check the
container status and service logs as described below.

## Access the administration panel

Open:

```text
https://ypacileo.42.fr/wp-admin
```

Use the WordPress administrator account:

| Field    | Value                                     |
| -------- | ----------------------------------------- |
| Username | `ypacileo`                                |
| Password | Stored in `secrets/wp_admin_password.txt` |

The stack also creates a regular WordPress author account:

| Field    | Value                                    |
| -------- | ---------------------------------------- |
| Username | `wp_author`                              |
| Role     | Author                                   |
| Password | Stored in `secrets/wp_user_password.txt` |

The author account can manage its own WordPress content and change its own
password from its profile. It does not have the administrative permissions of
the `ypacileo` account.

## Credentials

Credentials are stored locally in the `secrets/` directory:

| File                            | Credential                                                 |
| ------------------------------- | ---------------------------------------------------------- |
| `secrets/db_root_password.txt`  | MariaDB root password used during database initialization. |
| `secrets/db_password.txt`       | Password of the MariaDB user used by WordPress.            |
| `secrets/wp_admin_password.txt` | Password of the WordPress administrator.                   |
| `secrets/wp_user_password.txt`  | Password of the regular WordPress author.                  |

The secret files are excluded from Git and must not be committed or shared.
Limit their permissions so that only their owner can read and modify them:

```sh
chmod 600 secrets/*.txt
```

Docker mounts each secret only into the services that require it. Inside an
authorized container, it is available as a file under `/run/secrets/` and can
still be read by a process or administrator with sufficient permissions.

### Changing credentials

Changing the contents of a secret file does not automatically update a
password already stored by WordPress or MariaDB. The secret files provide
credentials during the first initialization, but they are not a password
management interface.

#### WordPress user passwords

The WordPress administrator and author passwords are application credentials
stored by WordPress in the MariaDB database.

* The administrator can change WordPress user passwords from the WordPress
  administration panel.
* The regular author can change their own password from their WordPress profile.
* These changes are stored in MariaDB and preserved by the persistent database
  volume.
* After changing a WordPress password, update the corresponding local secret
  file if the same password should be used during a future fresh installation.

The relevant secret files are:

```text
secrets/wp_admin_password.txt
secrets/wp_user_password.txt
```

Updating one of these files alone does not change the password of an existing
WordPress user.

#### MariaDB application-user password

The MariaDB application user, `wp_database_user`, is not a WordPress account
and cannot be managed from the WordPress administration panel. WordPress uses
this account internally to connect to MariaDB.

Changing its password while preserving the existing data requires updating
three locations:

1. Change the password of `wp_database_user` inside MariaDB using the MariaDB
   root account.
2. Update `secrets/db_password.txt` on the host.
3. Update `DB_PASSWORD` in the persistent WordPress `wp-config.php` file.

The password stored by MariaDB, the secret file and the value in
`wp-config.php` must remain identical. If they do not match, WordPress will be
unable to connect to the database.

#### MariaDB root password

The MariaDB root password must be changed inside MariaDB using an authorized
database session. The corresponding `secrets/db_root_password.txt` file must
then be updated to keep the local credential consistent.

WordPress does not use the MariaDB root account.

#### Fresh initialization

Running `make re` removes the containers, project images, volumes and
persistent data before rebuilding the infrastructure. The current secret files
are then used to create the accounts again.

This applies newly supplied passwords, but permanently deletes the existing
WordPress website and MariaDB data.

## Check that the services are running

### Check container status and exit codes

First, check the current state of all containers, including stopped containers:

```sh
sudo docker compose -f srcs/docker-compose.yml \
    --env-file srcs/.env ps -a
```

The `-a` option also displays containers that have stopped.

The `STATUS` column may show the following common states:

| Status            | Meaning                                                                                                                      |
| ----------------- | ---------------------------------------------------------------------------------------------------------------------------- |
| `Up` or `running` | The container is currently running.                                                                                          |
| `Created`         | The container was created, but its main process has not started.                                                             |
| `Restarting`      | Docker is repeatedly attempting to restart the container.                                                                    |
| `Exited (0)`      | The main process finished successfully. This is normal after an intentional stop, but not while the stack should be running. |
| `Exited (1)`      | The main process reported a general error. Check the service logs.                                                           |
| `Exited (126)`    | The requested command was found but could not be executed, commonly because of permissions.                                  |
| `Exited (127)`    | The requested command or executable could not be found.                                                                      |
| `Exited (137)`    | The process received `SIGKILL`. It may have been forcibly stopped or terminated because of insufficient memory.              |
| `Exited (143)`    | The process received `SIGTERM`. This commonly occurs during a normal Docker stop.                                            |

The `mariadb`, `wordpress` and `nginx` services should all appear as running
while the project is expected to be available.

An exit code identifies how the container's PID 1 process finished. It does not
always identify the exact cause of the failure, so the next step is to inspect
the logs.

### Check service logs

After checking the container states, inspect the logs from all services:

```sh
make logs
```

Press `Ctrl+C` to stop following the logs. This does not stop the containers.

To inspect one service separately, use:

```sh
sudo docker compose -f srcs/docker-compose.yml \
    --env-file srcs/.env logs mariadb
```

Replace `mariadb` with `wordpress` or `nginx` when necessary.

The first launch may include messages indicating that MariaDB and WordPress are
being initialized. After initialization, there should be no repeated fatal
errors or continuous restart loop.

### Test the HTTPS endpoint

```sh
curl -kI https://ypacileo.42.fr
```

The `-k` option accepts the self-signed certificate. The `-I` option requests
only the HTTP response headers.

A successful HTTP response confirms that the HTTPS entry point is reachable.
Depending on the requested resource and WordPress configuration, the response
may be a successful status or a redirect.

### Check the persistent volumes

```sh
sudo docker volume ls --filter name=srcs_
```

The list should include the MariaDB and WordPress volumes. Their persistent data
is stored on the host under:

```text
/home/ypacileo/data/mariadb
/home/ypacileo/data/wordpress
```

Stopping or removing the containers with `make stop`, `make down` or
`make clean` does not delete these directories.

## Common problems

### The domain does not open

Check that `ypacileo.42.fr` resolves to the correct IP address:

```sh
getent hosts ypacileo.42.fr
```

Then check all container states:

```sh
sudo docker compose -f srcs/docker-compose.yml \
    --env-file srcs/.env ps -a
```

If a service is stopped or restarting, inspect its logs.

### The browser reports an untrusted certificate

This is expected because NGINX uses a locally generated self-signed
certificate. Confirm that the requested domain is `ypacileo.42.fr` before
accepting the warning in the local environment.

### WordPress cannot connect to the database

Check the WordPress and MariaDB container states and logs.

Confirm that the database password is consistent between:

* the MariaDB `wp_database_user` account;
* `secrets/db_password.txt`;
* `DB_PASSWORD` in the persistent WordPress `wp-config.php`.

On the first launch, WordPress waits for MariaDB to become available before
completing its installation.

### A service repeatedly restarts

Check its status and exit code with `docker compose ps -a`, then inspect its
logs.

Common causes include:

* a missing or empty secret file;
* an invalid environment variable;
* an unavailable dependency;
* an incorrect command or executable;
* invalid permissions on persistent data;
* insufficient memory.

### A container shows `Exited (0)`

Exit code `0` means that its main process finished without reporting an error.
However, NGINX, MariaDB and PHP-FPM are long-running services and should remain
active while the stack is running.

If one of them exits unexpectedly with code `0`, inspect its command and logs
to determine why the main process finished.
