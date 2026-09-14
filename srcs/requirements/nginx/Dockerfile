FROM debian:12

RUN apt-get update && apt-get install -y nginx openssl \
	&& rm -f /etc/nginx/sites-enabled/default \
	&& mkdir -p /etc/nginx/ssl \
	&& openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
		-keyout /etc/nginx/ssl/inception.key \
		-out /etc/nginx/ssl/inception.crt \
		-subj "/C=ES/O=42/OU=Inception/CN=ypacileo.42.fr"

COPY conf/inception.conf /etc/nginx/conf.d/inception.conf

CMD ["nginx", "-g", "daemon off;"]
