FROM debian:12

# php8.2-cli: This will allow you to run WP-CLI.
# php8.2-fpm: This will handle FastCGI requests from NGINX.
# php8.2-mysql: This will allow communication with MariaDB. 
# The other extensions provide support for HTTP, images, UTF-8, and XML.
RUN apt-get update \
	&& DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
		ca-certificates \
		curl \
		php8.2-cli \
		php8.2-curl \
		php8.2-fpm \
		php8.2-gd \
		php8.2-mbstring \
		php8.2-mysql \
		php8.2-xml \
	&& rm -rf /var/lib/apt/lists/*

ARG WORDPRESS_VERSION=7.1

# Download: wp-cli.phar
# The -fL option detects HTTP errors and follows any redirects.
RUN curl -fL \
	https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar \
	-o /usr/local/bin/wp \
	&& chmod +x /usr/local/bin/wp

# Replace the default PHP-FPM pool configuration.
COPY conf/www.conf /etc/php/8.2/fpm/pool.d/www.conf

# Download and extract the WordPress core into a source directory.
RUN curl -fL \
	"https://wordpress.org/wordpress-${WORDPRESS_VERSION}.tar.gz" \
	-o /tmp/wordpress.tar.gz \
	&& tar -xzf /tmp/wordpress.tar.gz -C /usr/src \
	&& rm -f /tmp/wordpress.tar.gz

# Copy the WordPress initialization script into the image.
COPY tools/entrypoint.sh /usr/local/bin/entrypoint.sh

# Make the initialization script executable.
RUN chmod +x /usr/local/bin/entrypoint.sh

# Copy the MariaDB connection probe into the image.
COPY tools/check-db.php /usr/local/bin/check-db.php

# Document the FastCGI port used by PHP-FPM.
EXPOSE 9000

# Run the initialization script when the container starts.
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]

# Start PHP-FPM in the foreground by default.
CMD ["php-fpm8.2", "-F"]
