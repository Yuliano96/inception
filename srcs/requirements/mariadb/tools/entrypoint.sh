#!/bin/sh

# On the first startup, initialize the data directory, start a temporary
# local-only MariaDB server, create the WordPress database and user, grant
# the required privileges, set the root password, and stop the temporary
# server. Finally, start the main MariaDB server as PID 1.

# Stop the script if a command fails or an undefined variable is used.
set -eu

# install -d ...: creates /run/mysqld and /var/lib/mysql with owner and group mysql.
install -d -o mysql -g mysql /run/mysqld /var/lib/mysql

# The condition is met if /var/lib/mysql/mysql does not exist.
if [ ! -d /var/lib/mysql/mysql ]; then

	# Check the non-sensitive variables required for the first initialization.
	: "${MYSQL_DATABASE:?MYSQL_DATABASE is not set}"
	: "${MYSQL_USER:?MYSQL_USER is not set}"

	# Use the default Docker secret paths when no custom paths are provided.
	MYSQL_PASSWORD_FILE="${MYSQL_PASSWORD_FILE:-/run/secrets/db_password}"
	MYSQL_ROOT_PASSWORD_FILE="${MYSQL_ROOT_PASSWORD_FILE:-/run/secrets/db_root_password}"

	# Stop if the required secret files cannot be read.
	if [ ! -r "$MYSQL_PASSWORD_FILE" ]; then
		echo "Error: cannot read the MariaDB user password secret." >&2
		exit 1
	fi

	if [ ! -r "$MYSQL_ROOT_PASSWORD_FILE" ]; then
		echo "Error: cannot read the MariaDB root password secret." >&2
		exit 1
	fi

	# Read the passwords from the Docker secret files.
	MYSQL_PASSWORD="$(cat "$MYSQL_PASSWORD_FILE")"
	MYSQL_ROOT_PASSWORD="$(cat "$MYSQL_ROOT_PASSWORD_FILE")"

	# Stop if any password secret is empty.
	: "${MYSQL_PASSWORD:?MariaDB user password secret is empty}"
	: "${MYSQL_ROOT_PASSWORD:?MariaDB root password secret is empty}"

	
	 echo "Initializing MariaDB data directory..."
	 
	# prepares a directory so that it can be used by mariadbd.
	# --skip-test-db prevents anonymous accounts
	mariadb-install-db --user=mysql --datadir=/var/lib/mysql \
	--skip-test-db

	# start a temporary sever without TCP networking
	# &: Runs it in the background so the script can continue.
	mariadbd --user=mysql --skip-networking &
	
	# $! contains the PID of the last process started in the background.
	 mariadb_pid=$!
	
	# Start the temporary MariaDB readiness-attempt counter.
	attempt=1

	# Wait until the temporary server accepts local socket connections.
	until mariadb-admin ping --silent; do
		if [ "$attempt" -ge 30 ]; then
			echo "Error: temporary MariaDB server is not ready after 30 attempts." >&2
			exit 1
		fi

		echo "Temporary MariaDB server is not ready. Attempt $attempt/30..."
		attempt=$((attempt + 1))
		sleep 1
	done
	echo "Temporary MariaDB server is ready"
	
	# The client connects locally to the temporary server
  	mariadb --protocol=socket --user=root <<EOF

	CREATE DATABASE IF NOT EXISTS ${MYSQL_DATABASE};
	CREATE USER IF NOT EXISTS '${MYSQL_USER}'@'%' IDENTIFIED BY '${MYSQL_PASSWORD}';
	GRANT ALL PRIVILEGES ON ${MYSQL_DATABASE}.* TO '${MYSQL_USER}'@'%';
	ALTER USER 'root'@'localhost' IDENTIFIED BY '${MYSQL_ROOT_PASSWORD}';
	FLUSH PRIVILEGES;
EOF

	# stop the temporary server cleanly
	# con las nuevas credenciales
  	mariadb-admin --user=root --password="${MYSQL_ROOT_PASSWORD}" shutdown

  	# wait until the temporary process has completely finished
	wait "$mariadb_pid"

fi


# . $@ represents all arguments received.
# . By default, it receives mariadbd --user=mysql.
# . exec replaces the script with the command received.
exec "$@"
