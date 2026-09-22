FROM debian:12

RUN apt-get update && \
	DEBIAN_FRONTEND=noninteractive apt-get install \
	-y --no-install-recommends mariadb-server && \
	rm -rf /var/lib/apt/lists/* && \
	rm -rf /var/lib/mysql/*

COPY conf/99-inception.cnf /etc/mysql/mariadb.conf.d/99-inception.cnf
COPY tools/entrypoint.sh /usr/local/bin/entrypoint.sh

RUN chmod +x /usr/local/bin/entrypoint.sh

Expose 3306

#specifies the process that Docker will run when creating the container.
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]

CMD ["mariadbd", "--user=mysql"]

