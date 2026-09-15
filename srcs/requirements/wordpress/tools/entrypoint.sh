#!/bin/sh

# Stop immediately if a command fails or an undefined variable is used.
set -eu

# Create the directory where the active WordPress installation will live.
mkdir -p /var/www/html

# Copy the WordPress core only when the volume has not been initialized.
if [ ! -f /var/www/html/wp-load.php ]; then
	echo "Initializing WordPress files..."
	cp -a /usr/src/wordpress/. /var/www/html/
fi

# Check the non-sensitive variables required to configure WordPress.
: "${MYSQL_DATABASE:?MYSQL_DATABASE is not set}"
: "${MYSQL_USER:?MYSQL_USER is not set}"

# Check the non-sensitive variables required to install the website.
: "${WORDPRESS_URL:?WORDPRESS_URL is not set}"
: "${WORDPRESS_TITLE:?WORDPRESS_TITLE is not set}"
: "${WORDPRESS_ADMIN_USER:?WORDPRESS_ADMIN_USER is not set}"
: "${WORDPRESS_ADMIN_EMAIL:?WORDPRESS_ADMIN_EMAIL is not set}"

# Check the non-sensitive variables required for the regular user.
: "${WORDPRESS_USER:?WORDPRESS_USER is not set}"
: "${WORDPRESS_USER_EMAIL:?WORDPRESS_USER_EMAIL is not set}"

# Use "author" as the regular user's role when no role is provided.
WORDPRESS_USER_ROLE="${WORDPRESS_USER_ROLE:-author}"

# Use the default Docker secret paths when no custom paths are provided.
MYSQL_PASSWORD_FILE="${MYSQL_PASSWORD_FILE:-/run/secrets/db_password}"
WORDPRESS_ADMIN_PASSWORD_FILE="${WORDPRESS_ADMIN_PASSWORD_FILE:-/run/secrets/wp_admin_password}"
WORDPRESS_USER_PASSWORD_FILE="${WORDPRESS_USER_PASSWORD_FILE:-/run/secrets/wp_user_password}"

# Stop if any required secret file cannot be read.
if [ ! -r "$MYSQL_PASSWORD_FILE" ]; then
	echo "Error: cannot read the MariaDB user password secret." >&2
	exit 1
fi

if [ ! -r "$WORDPRESS_ADMIN_PASSWORD_FILE" ]; then
	echo "Error: cannot read the WordPress administrator password secret." >&2
	exit 1
fi

if [ ! -r "$WORDPRESS_USER_PASSWORD_FILE" ]; then
	echo "Error: cannot read the regular WordPress user password secret." >&2
	exit 1
fi

# Read the passwords from the Docker secret files.
MYSQL_PASSWORD="$(cat "$MYSQL_PASSWORD_FILE")"
WORDPRESS_ADMIN_PASSWORD="$(cat "$WORDPRESS_ADMIN_PASSWORD_FILE")"
WORDPRESS_USER_PASSWORD="$(cat "$WORDPRESS_USER_PASSWORD_FILE")"

# Stop if any password secret is empty.
: "${MYSQL_PASSWORD:?MariaDB user password secret is empty}"
: "${WORDPRESS_ADMIN_PASSWORD:?WordPress administrator password secret is empty}"
: "${WORDPRESS_USER_PASSWORD:?Regular WordPress user password secret is empty}"

# Export the database password so the PHP connection probe can read it.
export MYSQL_PASSWORD

# Use "mariadb" when MYSQL_HOST has no value.
MYSQL_HOST="${MYSQL_HOST:-mariadb}"

# Export MYSQL_HOST so child processes such as PHP can read it.
export MYSQL_HOST

# Create wp-config.php only when it does not already exist.
# WP-CLI generates the file using the wp command.
if [ ! -f /var/www/html/wp-config.php ]; then
	echo "Creating WordPress configuration..."
	wp config create \
		--path=/var/www/html \
		--dbname="$MYSQL_DATABASE" \
		--dbuser="$MYSQL_USER" \
		--dbpass="$MYSQL_PASSWORD" \
		--dbhost="${MYSQL_HOST}:3306" \
		--dbcharset="utf8mb4" \
		--allow-root \
		--skip-check
fi



# Start the MariaDB connection-attempt counter.
attempt=1

# Retry while the MariaDB connection probe fails.
until php /usr/local/bin/check-db.php; do
	if [ "$attempt" -ge 30 ]; then
		echo "Error: MariaDB is not available after 30 attempts." >&2
		exit 1
	fi

	echo "MariaDB is not ready. Attempt $attempt/30..."
	attempt=$((attempt + 1))
	sleep 2
done

echo "MariaDB is ready."

# Install WordPress only when its database tables do not already exist.
if ! wp core is-installed \
	--path=/var/www/html \
	--allow-root; then
	echo "Installing WordPress website..."
	wp core install \
		--path=/var/www/html \
		--url="$WORDPRESS_URL" \
		--title="$WORDPRESS_TITLE" \
		--admin_user="$WORDPRESS_ADMIN_USER" \
		--admin_password="$WORDPRESS_ADMIN_PASSWORD" \
		--admin_email="$WORDPRESS_ADMIN_EMAIL" \
		--skip-email \
		--allow-root
fi

# Create the regular WordPress user only when it does not already exist.
if ! wp user get "$WORDPRESS_USER" \
	--path=/var/www/html \
	--allow-root >/dev/null 2>&1; then
	echo "Creating regular WordPress user..."
	wp user create "$WORDPRESS_USER" "$WORDPRESS_USER_EMAIL" \
		--path=/var/www/html \
		--user_pass="$WORDPRESS_USER_PASSWORD" \
		--role="$WORDPRESS_USER_ROLE" \
		--allow-root
fi

# Give the PHP-FPM user ownership of the active WordPress installation.
chown -R www-data:www-data /var/www/html

# Ensure the PHP-FPM runtime directory exists.
mkdir -p /run/php

# Replace the initialization script with the container main process.
exec "$@"
