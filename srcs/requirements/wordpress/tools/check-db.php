<?php

// Disable automatic MySQLi warnings so this probe controls its own exit status.
mysqli_report(MYSQLI_REPORT_OFF);

// Read the MariaDB host name from the container environment.
$host = getenv('MYSQL_HOST');

// Read the WordPress database name from the container environment.
$database = getenv('MYSQL_DATABASE');

// Read the MariaDB user name from the container environment.
$user = getenv('MYSQL_USER');

// Read the MariaDB user password from the container environment.
$password = getenv('MYSQL_PASSWORD');

// Create a connection to MariaDB on its default TCP port.
$connection = new mysqli($host, $user, $password, $database, 3306);

// Return a failure status when MariaDB does not accept the connection.
if ($connection->connect_errno)
{
	// Exit status 1 tells the shell that the database is not ready.
	exit(1);
}

// Close the successful test connection because the probe no longer needs it.
$connection->close();

// Exit status 0 tells the shell that MariaDB is ready.
exit(0);
