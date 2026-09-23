# NGINX Service

## Overview

The NGINX service is the only public entry point to the Inception
infrastructure.

It accepts HTTPS connections on port 443 and performs three main tasks:

* terminates the TLS connection;
* serves existing static WordPress files;
* forwards PHP requests to the WordPress PHP-FPM service through FastCGI.

The service is built from Debian 12 and runs in its own container.

NGINX shares the WordPress filesystem with the WordPress container through a
read-only volume mounted at:

```text
/var/www/html
```

It communicates with PHP-FPM through the `inception` Docker network at:

```text
wordpress:9000
```

NGINX does not connect directly to MariaDB.

## Files

| File                                          | Purpose                                                                              |
| --------------------------------------------- | ------------------------------------------------------------------------------------ |
| `srcs/requirements/nginx/Dockerfile`          | Builds the NGINX image, generates the TLS files, and defines the main process.       |
| `srcs/requirements/nginx/conf/inception.conf` | Configures HTTPS, static-file handling, and FastCGI forwarding.                      |
| `srcs/docker-compose.yml`                     | Publishes port 443 and supplies the volume, network, dependency, and restart policy. |

## Dockerfile

The Dockerfile builds the `nginx:1.0` image before any NGINX container is
started.

### Dockerfile build flow

```text
Start from debian:12
        |
        v
Update the APT package index
        |
        v
Install NGINX and OpenSSL
        |
        v
Remove the APT package lists
        |
        v
Remove the default NGINX website
        |
        v
Create /etc/nginx/ssl
        |
        v
Generate a self-signed certificate
and private key
        |
        v
Copy inception.conf
        |
        v
Document port 443
        |
        v
Define the NGINX foreground command
        |
        v
The nginx:1.0 image is ready
```

### Base image

The image is based on:

```dockerfile
FROM debian:12
```

NGINX is installed from the Debian package repository instead of using an
official prebuilt NGINX image.

### Installed packages

The Dockerfile installs:

| Package   | Purpose                                                    |
| --------- | ---------------------------------------------------------- |
| `nginx`   | Provides the HTTPS web server and FastCGI gateway.         |
| `openssl` | Generates the self-signed TLS certificate and private key. |

The APT package lists are removed after installation:

```text
/var/lib/apt/lists/*
```

This reduces the final image size.

## Default website removal

The Debian NGINX package provides a default website configuration.

The Dockerfile removes its enabled symbolic link with:

```sh
rm -f /etc/nginx/sites-enabled/default
```

This prevents the default Debian website from handling requests.

The custom Inception server configuration is copied to:

```text
/etc/nginx/conf.d/inception.conf
```

The main Debian NGINX configuration loads files from the `conf.d` directory,
allowing the custom server block to become active.

## TLS certificate generation

The Dockerfile creates:

```text
/etc/nginx/ssl
```

and generates two TLS files:

```text
/etc/nginx/ssl/inception.crt
/etc/nginx/ssl/inception.key
```

Their purposes are:

| File            | Purpose                                          |
| --------------- | ------------------------------------------------ |
| `inception.crt` | Public certificate presented to HTTPS clients.   |
| `inception.key` | Private key used by NGINX during TLS handshakes. |

The generation command is:

```sh
openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
    -keyout /etc/nginx/ssl/inception.key \
    -out /etc/nginx/ssl/inception.crt \
    -subj "/C=ES/O=42/OU=Inception/CN=ypacileo.42.fr"
```

### OpenSSL options

| Option             | Purpose                                                         |
| ------------------ | --------------------------------------------------------------- |
| `req`              | Creates a certificate request or a self-signed certificate.     |
| `-x509`            | Produces a self-signed X.509 certificate.                       |
| `-nodes`           | Creates the private key without passphrase encryption.          |
| `-days 365`        | Makes the certificate valid for 365 days.                       |
| `-newkey rsa:2048` | Generates a new 2048-bit RSA private key.                       |
| `-keyout`          | Defines the private-key output path.                            |
| `-out`             | Defines the certificate output path.                            |
| `-subj`            | Supplies the certificate subject without interactive questions. |

The certificate subject contains:

| Subject field       | Value            |
| ------------------- | ---------------- |
| Country             | `ES`             |
| Organization        | `42`             |
| Organizational unit | `Inception`      |
| Common name         | `ypacileo.42.fr` |

### Self-signed certificate behavior

The certificate is self-signed. It is not signed by a public certificate
authority trusted by browsers.

As a result, a browser may display a security warning even though the
connection is encrypted.

The certificate must still match the domain used to access the website:

```text
ypacileo.42.fr
```

### Certificate generation time

The certificate and private key are generated during:

```text
docker build
```

They are not generated every time the container starts.

The sequence is:

```text
Build the NGINX image
        |
        v
Generate certificate and private key
        |
        v
Store both files in an image layer
        |
        v
Create containers from the image
        |
        v
Each container uses the files
already included in the image
```

Recreating the container from the same image does not generate a new
certificate.

Rebuilding the image executes the OpenSSL command again and generates a new key
and certificate.


## Container startup command

The Dockerfile defines:

```dockerfile
CMD ["nginx", "-g", "daemon off;"]
```

This runs NGINX with the global directive:

```text
daemon off;
```

By default, NGINX can detach from the terminal and run in the background. A
Docker container requires its main service to remain in the foreground.

The command therefore keeps the NGINX master process attached to the container.

## Port 443

The Dockerfile contains:

```dockerfile
EXPOSE 443
```

This documents the HTTPS port used by the image.

`EXPOSE` does not publish the port on the host. The actual host publication is
performed by Docker Compose.

## NGINX configuration

The custom NGINX configuration is stored in:

```text
srcs/requirements/nginx/conf/inception.conf
```

The Dockerfile copies it to:

```text
/etc/nginx/conf.d/inception.conf
```

The file defines one HTTPS virtual server.

## Server block

The configuration begins with:

```nginx
server {
    listen 443 ssl;
    server_name ypacileo.42.fr;
}
```

### `listen`

The directive:

```nginx
listen 443 ssl;
```

instructs NGINX to:

* listen on TCP port 443;
* expect TLS connections;
* perform the TLS handshake before processing HTTP requests.

NGINX does not define a listener on port 80. The project therefore provides no
plain HTTP endpoint.

### `server_name`

The directive:

```nginx
server_name ypacileo.42.fr;
```

identifies the hostname handled by this server block.

The local machine must resolve this domain to the address of the virtual
machine or the host on which Docker publishes port 443.

For local access inside the virtual machine, the mapping can be:

```text
127.0.0.1 ypacileo.42.fr
```

## TLS configuration

The configuration allows:

```nginx
ssl_protocols TLSv1.2 TLSv1.3;
```

Only TLS 1.2 and TLS 1.3 are accepted.

Older protocol versions, such as TLS 1.0 and TLS 1.1, are not enabled by this
server block.

The certificate paths are:

```nginx
ssl_certificate /etc/nginx/ssl/inception.crt;
ssl_certificate_key /etc/nginx/ssl/inception.key;
```

NGINX uses the public certificate and the corresponding private key during the
TLS handshake.

The high-level TLS flow is:

```text
Client connects to port 443
        |
        v
NGINX presents inception.crt
        |
        v
Client and NGINX negotiate TLS 1.2 or TLS 1.3
        |
        v
NGINX proves possession of inception.key
        |
        v
An encrypted connection is established
        |
        v
The HTTP request is processed inside TLS
```

The private key is never sent to the client.

## WordPress document root

The configuration defines:

```nginx
root /var/www/html;
```

This makes `/var/www/html` the filesystem root used to resolve requested
resources.

For example:

```text
Request URI: /wp-content/uploads/image.jpg
Filesystem:  /var/www/html/wp-content/uploads/image.jpg
```

This directory is the WordPress volume mounted in read-only mode inside the
NGINX container.

## Index files

The configuration defines:

```nginx
index index.php index.html;
```

When a request resolves to a directory, NGINX checks for the configured index
files in this order:

1. `index.php`;
2. `index.html`.

For the website root, the preferred entry file is:

```text
/var/www/html/index.php
```

WordPress uses `index.php` as its main front controller.

## Root location

The general location block is:

```nginx
location / {
    try_files $uri $uri/ /index.php?$args;
}
```

It handles requests that do not first match the PHP regular-expression
location.

### `try_files`

The directive checks possible targets in this order:

```text
$uri
$uri/
/index.php?$args
```

The behavior is:

1. if the requested path is an existing file, NGINX serves the file;
2. if the requested path is an existing directory, NGINX processes the
   directory;
3. otherwise, NGINX internally redirects the request to `index.php`;
4. the original query string is preserved through `$args`.

### Existing static file

For a request such as:

```text
/wp-content/uploads/image.jpg
```

NGINX checks:

```text
/var/www/html/wp-content/uploads/image.jpg
```

If the file exists, NGINX serves it directly.

The request does not need PHP-FPM or MariaDB.

```text
Browser
        |
        v
NGINX
        |
        v
Read the file from /var/www/html
        |
        v
Return the static response
```

### WordPress route

For a request such as:

```text
/sample-page/
```

there may be no physical file or directory matching that public route.

NGINX therefore internally redirects the request to:

```text
/index.php
```

while preserving any query arguments.

WordPress receives the request through its front controller and determines
which page, post, or route should be displayed.

```text
Request: /sample-page/
        |
        v
No matching static file
        |
        v
Internal redirect to /index.php
        |
        v
PHP location
        |
        v
PHP-FPM executes WordPress
```

## PHP location

PHP requests are handled by:

```nginx
location ~ \.php$ {
    try_files $uri =404;
    include fastcgi_params;
    fastcgi_pass wordpress:9000;
    fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;
}
```

The `~` modifier selects a case-sensitive regular-expression location.

The expression:

```text
\.php$
```

matches a URI that ends in `.php`.

Examples that match:

```text
/index.php
/wp-login.php
/wp-admin/admin.php
```

An image or stylesheet does not match this location.

## PHP script existence check

Inside the PHP location:

```nginx
try_files $uri =404;
```

NGINX checks whether the requested PHP script exists under the document root.

For example:

```text
URI:        /wp-login.php
Filesystem: /var/www/html/wp-login.php
```

If the file does not exist, NGINX returns:

```text
404 Not Found
```

The nonexistent script is not forwarded to PHP-FPM.

## FastCGI parameters

The directive:

```nginx
include fastcgi_params;
```

loads standard FastCGI parameters supplied by the Debian NGINX package.

These parameters describe the request to PHP-FPM, including information such
as:

* request method;
* query string;
* content type;
* content length;
* server protocol;
* server name;
* remote client address.

NGINX does not send the original HTTPS connection itself to PHP-FPM. It
translates the request into FastCGI parameters.

## PHP-FPM destination

The directive:

```nginx
fastcgi_pass wordpress:9000;
```

sends the FastCGI request to:

* Docker DNS hostname: `wordpress`;
* TCP port: `9000`.

Docker resolves `wordpress` to the IP address of the WordPress container
because both services are connected to the `inception` network.

NGINX does not need the WordPress container's IP address.

## Script filename

The directive:

```nginx
fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;
```

builds the complete filesystem path of the PHP script.

For a request to:

```text
/index.php
```

the values are approximately:

```text
$document_root         = /var/www/html
$fastcgi_script_name   = /index.php
SCRIPT_FILENAME        = /var/www/html/index.php
```

PHP-FPM uses `SCRIPT_FILENAME` to identify the PHP file it must execute.

The same WordPress volume is mounted at `/var/www/html` inside both containers.
Therefore, the path generated by NGINX also exists inside the WordPress
container.

## Static and dynamic request comparison

| Request type                                | Handled by                    | PHP-FPM used | MariaDB normally used |
| ------------------------------------------- | ----------------------------- | ------------ | --------------------- |
| Existing image, CSS, or JavaScript file     | NGINX                         | No           | No                    |
| Existing `.php` script                      | NGINX and PHP-FPM             | Yes          | Possibly              |
| WordPress permalink without a physical file | NGINX, PHP-FPM, and WordPress | Yes          | Usually               |
| Missing `.php` script                       | NGINX returns 404             | No           | No                    |

## Docker Compose integration

Docker Compose provides the NGINX container with:

| Compose setting | Value                             | Purpose                                                        |
| --------------- | --------------------------------- | -------------------------------------------------------------- |
| Build context   | `./requirements/nginx`            | Selects the NGINX Dockerfile and configuration.                |
| Image           | `nginx:1.0`                       | Names and versions the built image.                            |
| Port mapping    | `443:443`                         | Publishes container port 443 on host port 443.                 |
| Volume          | `wordpress_data:/var/www/html:ro` | Gives NGINX read-only access to WordPress files.               |
| Network         | `inception`                       | Connects NGINX to the WordPress service.                       |
| Dependency      | `wordpress`                       | Starts the WordPress container before NGINX.                   |
| Restart policy  | `unless-stopped`                  | Restarts NGINX automatically unless it was explicitly stopped. |

NGINX receives no environment variables and no Docker Secrets in the current
Compose configuration.

The TLS files are already included in the image.

## Host port publication

The Compose mapping is:

```yaml
ports:
  - "443:443"
```

The format is:

```text
HOST_PORT:CONTAINER_PORT
```

Therefore:

```text
Host port:      443
Container port: 443
```

A connection to the host on port 443 is forwarded to port 443 in the NGINX
container.

```text
Browser
        |
        | HTTPS to host:443
        v
Docker port mapping
        |
        | Forward to container:443
        v
NGINX
```

No other service publishes a port on the host.

## Read-only WordPress volume

The NGINX service mounts:

```text
wordpress_data:/var/www/html:ro
```

The `:ro` suffix means read-only.

NGINX can:

* read WordPress core files;
* serve images, CSS, and JavaScript;
* confirm whether PHP scripts exist.

NGINX cannot modify, create, or delete files in `/var/www/html` through this
mount.

The WordPress container mounts the same volume without `:ro`, so WordPress and
PHP-FPM have read-write access.

```text
Host directory:
  /home/ypacileo/data/wordpress
               |
               v
Docker volume:
  wordpress_data
        |
        +-- WordPress: /var/www/html     read-write
        |
        +-- NGINX:     /var/www/html     read-only
```

## Dependency behavior

The Compose configuration contains:

```yaml
depends_on:
  - wordpress
```

This starts the WordPress container before the NGINX container.

It does not guarantee that PHP-FPM is already listening on port 9000.

The NGINX container may start while the WordPress entrypoint is still:

* waiting for MariaDB;
* installing WordPress;
* creating the regular user;
* preparing file ownership.

If a PHP request arrives before PHP-FPM is ready, NGINX may temporarily return:

```text
502 Bad Gateway
```

Once PHP-FPM starts listening on `wordpress:9000`, subsequent PHP requests can
succeed.

NGINX has no custom readiness loop in the current implementation.

## PID 1 and process model

The NGINX image does not define a custom entrypoint.

Docker directly starts the command:

```text
nginx -g "daemon off;"
```

The NGINX master process therefore becomes PID 1 immediately.

```text
Container starts
        |
        v
PID 1: NGINX master process
        |
        +-- NGINX worker process
        +-- NGINX worker process
```

The exact number of worker processes depends on the main NGINX configuration.

Because the master process is PID 1:

* it receives Docker stop signals directly;
* it manages the worker processes;
* it controls the container lifetime;
* the container stops if the master process exits;
* Docker can apply the restart policy correctly.

The `daemon off;` setting is required because a Docker container runs while
its main foreground process remains active.

## Complete request flow

### Static request

```text
Browser
        |
        | HTTPS on port 443
        v
Docker port mapping
        |
        v
NGINX performs the TLS handshake
        |
        v
NGINX evaluates location /
        |
        v
The requested file exists
        |
        v
NGINX reads it from /var/www/html
        |
        v
NGINX returns the encrypted response
```

### Dynamic WordPress request

```text
Browser
        |
        | HTTPS on port 443
        v
Docker port mapping
        |
        v
NGINX performs the TLS handshake
        |
        v
NGINX evaluates the requested URI
        |
        v
No matching static file exists
        |
        v
Internal redirect to /index.php
        |
        v
NGINX checks that index.php exists
        |
        v
NGINX builds the FastCGI parameters
        |
        v
FastCGI request to wordpress:9000
        |
        v
PHP-FPM executes /var/www/html/index.php
        |
        v
WordPress reads wp-config.php
        |
        v
WordPress connects to mariadb:3306
        |
        v
MariaDB returns the requested data
        |
        v
WordPress generates the page
        |
        v
PHP-FPM returns the FastCGI response
        |
        v
NGINX returns the HTTPS response
        |
        v
Browser displays the page
```

## Combined build and startup flow

```text
IMAGE BUILD
===========

Docker Compose selects ./requirements/nginx
        |
        v
Build nginx:1.0 from debian:12
        |
        +-- Install NGINX
        +-- Install OpenSSL
        +-- Remove the default website
        +-- Generate the TLS certificate
        +-- Generate the TLS private key
        +-- Copy inception.conf
        +-- Define the foreground command
        |
        v
The image contains the NGINX configuration
and the generated TLS files


CONTAINER CREATION
==================

Docker Compose creates the NGINX container
        |
        +-- Publish host port 443
        +-- Mount wordpress_data as read-only
        +-- Connect the container to inception
        +-- Start WordPress first through depends_on
        +-- Apply restart: unless-stopped
        |
        v
Docker starts the CMD directly


CONTAINER STARTUP
=================

Execute nginx -g "daemon off;"
        |
        v
Read the NGINX configuration
        |
        v
Load the certificate and private key
        |
        v
Resolve the FastCGI destination
        |
        v
NGINX master becomes PID 1
        |
        v
Create worker processes
        |
        v
Listen on port 443
        |
        v
Wait for HTTPS requests
```

## Verification

Run the following commands from the repository root.

### Validate the Compose configuration

```sh
sudo docker compose -f srcs/docker-compose.yml \
    --env-file srcs/.env config --quiet
```

A successful validation produces no output and returns exit status `0`.

### Build the NGINX image

```sh
sudo docker compose -f srcs/docker-compose.yml \
    --env-file srcs/.env build nginx
```

### Start the complete infrastructure

```sh
make
```

NGINX depends on WordPress, and WordPress depends on MariaDB. Starting the
complete infrastructure allows the full request path to operate.

### Check the container state

```sh
sudo docker compose -f srcs/docker-compose.yml \
    --env-file srcs/.env ps -a nginx
```

The service should appear as running.

### Validate the NGINX configuration

```sh
sudo docker compose -f srcs/docker-compose.yml \
    --env-file srcs/.env exec nginx nginx -t
```

A successful test reports that the configuration syntax is valid.

### Inspect the logs

```sh
sudo docker compose -f srcs/docker-compose.yml \
    --env-file srcs/.env logs nginx
```

### Follow the logs

```sh
sudo docker compose -f srcs/docker-compose.yml \
    --env-file srcs/.env logs -f nginx
```

Press `Ctrl+C` to stop following the output. This does not stop the container.

### Check the NGINX processes

```sh
sudo docker compose -f srcs/docker-compose.yml \
    --env-file srcs/.env top nginx
```

The process list should show the NGINX master and worker processes.

### Check the published port

```sh
sudo docker compose -f srcs/docker-compose.yml \
    --env-file srcs/.env port nginx 443
```

The output should show that container port 443 is published on host port 443.

### Test the HTTPS endpoint

```sh
curl -kI https://ypacileo.42.fr
```

The `-k` option allows `curl` to accept the self-signed certificate.

A successful response confirms that:

* the domain resolves;
* host port 443 is reachable;
* Docker forwards the connection;
* NGINX accepts TLS;
* the HTTPS server responds.

### Inspect the certificate

```sh
openssl s_client \
    -connect ypacileo.42.fr:443 \
    -servername ypacileo.42.fr </dev/null
```

The output displays the certificate chain, negotiated protocol, and cipher.

### Verify TLS 1.2

```sh
openssl s_client \
    -connect ypacileo.42.fr:443 \
    -servername ypacileo.42.fr \
    -tls1_2 </dev/null
```

The TLS handshake should succeed.

### Verify TLS 1.3

```sh
openssl s_client \
    -connect ypacileo.42.fr:443 \
    -servername ypacileo.42.fr \
    -tls1_3 </dev/null
```

The TLS handshake should succeed.

### Verify that TLS 1.1 is rejected

```sh
openssl s_client \
    -connect ypacileo.42.fr:443 \
    -servername ypacileo.42.fr \
    -tls1_1 </dev/null
```

The TLS handshake should fail because the server enables only TLS 1.2 and TLS
1.3.

### Inspect the TLS files inside the container

```sh
sudo docker compose -f srcs/docker-compose.yml \
    --env-file srcs/.env exec nginx \
    ls -l /etc/nginx/ssl
```

The directory should contain:

```text
inception.crt
inception.key
```

This command lists only the filenames and metadata. It does not print the
private-key contents.

### Inspect the read-only volume

```sh
sudo docker compose -f srcs/docker-compose.yml \
    --env-file srcs/.env exec nginx \
    ls -la /var/www/html
```

The directory should contain the active WordPress files.

The mount mode can be confirmed with:

```sh
sudo docker inspect \
    "$(sudo docker compose -f srcs/docker-compose.yml \
        --env-file srcs/.env ps -q nginx)" \
    --format '{{range .Mounts}}{{println .Destination "RW=" .RW}}{{end}}'
```

The `/var/www/html` mount should report:

```text
RW= false
```

### Test a static file

Request an existing WordPress static file:

```sh
curl -kI https://ypacileo.42.fr/wp-includes/css/dashicons.min.css
```

NGINX should serve the file directly without passing it to PHP-FPM.

### Test a missing PHP script

```sh
curl -kI https://ypacileo.42.fr/not-found.php
```

NGINX should return:

```text
404 Not Found
```

because the PHP location checks that the script exists before forwarding it.

## Common failure points

| Symptom                                | Possible cause                                                                                       |
| -------------------------------------- | ---------------------------------------------------------------------------------------------------- |
| NGINX container exits immediately      | The NGINX configuration is invalid or the TLS files cannot be loaded.                                |
| Host port 443 cannot be published      | Another process is already using port 443 or Docker lacks the required permission.                   |
| Browser cannot resolve the domain      | The domain is missing or incorrect in `/etc/hosts` or DNS.                                           |
| Browser displays a certificate warning | The certificate is self-signed and is not trusted by a public certificate authority.                 |
| Certificate name does not match        | The requested hostname differs from the certificate common name.                                     |
| TLS handshake fails                    | The client uses an unsupported protocol or the certificate and private key do not match.             |
| Static file returns 404                | The file is missing from the shared WordPress volume or the volume is mounted incorrectly.           |
| PHP request returns 404                | The requested PHP script does not exist under `/var/www/html`.                                       |
| PHP request returns 502                | PHP-FPM is not running, is not ready, or cannot be reached at `wordpress:9000`.                      |
| WordPress page does not load correctly | The front-controller fallback, shared volume, PHP-FPM connection, or database connection is failing. |
| NGINX serves the Debian default page   | The default site was not removed or the custom configuration was not loaded.                         |
| Container repeatedly restarts          | NGINX exits and the `unless-stopped` policy restarts the container.                                  |

Use the configuration test, container state, and logs as the first diagnostic
steps:

```sh
sudo docker compose -f srcs/docker-compose.yml \
    --env-file srcs/.env exec nginx nginx -t
```

```sh
sudo docker compose -f srcs/docker-compose.yml \
    --env-file srcs/.env ps -a nginx
```

```sh
sudo docker compose -f srcs/docker-compose.yml \
    --env-file srcs/.env logs nginx
```
