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

# Check the variables required to configure WordPress.
: "${MYSQL_DATABASE:?MYSQL_DATABASE is not set}"
: "${MYSQL_USER:?MYSQL_USER is not set}"
: "${MYSQL_PASSWORD:?MYSQL_PASSWORD is not set}"

# Check the variables required to install the WordPress website.
: "${WORDPRESS_URL:?WORDPRESS_URL is not set}"
: "${WORDPRESS_TITLE:?WORDPRESS_TITLE is not set}"
: "${WORDPRESS_ADMIN_USER:?WORDPRESS_ADMIN_USER is not set}"
: "${WORDPRESS_ADMIN_PASSWORD:?WORDPRESS_ADMIN_PASSWORD is not set}"
: "${WORDPRESS_ADMIN_EMAIL:?WORDPRESS_ADMIN_EMAIL is not set}"


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

# Give the PHP-FPM user ownership of the active WordPress installation.
chown -R www-data:www-data /var/www/html

# Ensure the PHP-FPM runtime directory exists.
mkdir -p /run/php

# Replace the initialization script with the container main process.
exec "$@"
