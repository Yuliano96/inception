#!/bin/sh

# On the first startup, initialize the data directory, start a temporary
# local-only MariaDB server, create the WordPress database and user, grant
# the required privileges, set the root password, and stop the temporary
# server. Finally, start the main MariaDB server as PID 1.

# End the script if a command fails
set -e

# install -d ...: creates /run/mysqld and /var/lib/mysql with owner and group mysql.
install -d -o mysql -g mysql /run/mysqld /var/lib/mysql

# The condition is met if /var/lib/mysql/mysql does not exist.
if [ ! -d /var/lib/mysql/mysql ]; then

	 # check the variables required for the first initialization
	 : "${MYSQL_DATABASE:?MYSQL_DATABASE is not set}"
	 : "${MYSQL_USER:?MYSQL_USER is not set}"
	 : "${MYSQL_PASSWORD:?MYSQL_PASSWORD is not set}"
	 : "${MYSQL_ROOT_PASSWORD:?MYSQL_ROOT_PASSWORD is not set}"
	 
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

	# wait until the temporary server accepts local connections
	until mariadb-admin ping --silent; do
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
