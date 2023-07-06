# Builder image to compile dependencies, outputs are opied to new image
# and artifacts are discarded.
FROM registry.access.redhat.com/ubi9/ubi-minimal as builder

USER root

# define final image, copy imagemagick components from staged build.
FROM registry.access.redhat.com/ubi9/ubi-minimal

LABEL name="ubi9-php8-apache" \
      maintainer="support@tag1consulting.com" \
      vendor="Tag1 Consulting" \
      version="1.0" \
      release="1" \
      summary="Simple base docker image for running PHP sites, Drupal oriented"

ENV OPCACHE_MAX_FILES 4000
ENV OPCACHE_MEMORY_CONSUMPTION 128
ENV OPCACHE_REVALIDATE_FREQ 60
ENV PHP_MEMORY_LIMIT 256M
ENV HTTPD_MAX_CONNECTIONS_PER_CHILD 2000
ENV HTTPD_MAX_KEEPALIVE_REQUESTS 100
ENV HTTPD_MAX_REQUEST_WORKERS 256
ENV HTTPD_MAX_KEEPALIVE_REQUESTS 100
ENV DOCUMENTROOT "/var/www/html"

USER root

# Reinstall timezone data (required by php runtime)
# (ubi-minimal has tzdata, but removed /usr/share/zoneinfo to save space.)
RUN microdnf upgrade && \
    microdnf reinstall -y tzdata

# Install php 8.1 and httpd 2.4
RUN microdnf module reset php && \
    microdnf module enable -y php:8.1 && \
    microdnf install -y php \
    php-gd \
    php-pear \
    php-cli \
    php-common \
    php-mysqlnd \
    php-opcache \
    php-devel \
    php-pecl-zip \
    php-intl \
    php-ldap \
    php-bcmath \
    php-pecl-apcu \
    php-pgsql \
    php-soap \
    php-gmp


# HTTPD Configuration ###

#Read XFF headers, note this is insecure if you are not sanitizing
#XFF in front of the container
RUN { \
    echo '<IfModule mod_remoteip.c>'; \
    echo '  RemoteIPHeader X-Forwarded-For'; \
    echo '</IfModule>'; \
  } > /etc/httpd/conf.d/remoteip.conf

#Correctly set SSL if we are terminated by it
RUN { \
    echo 'SetEnvIf X-Forwarded-Proto "https" HTTPS=on'; \
  } > /etc/httpd/conf.d/remote_ssl.conf

# Log to stdout
RUN { \
    echo 'ErrorLog "|/usr/bin/cat"'; \
    echo '<IfModule log_config_module>'; \
    echo '  CustomLog "|/usr/bin/cat" combined'; \
    echo '</IfModule>'; \
  } > /etc/httpd/conf.d/00-logging.conf

# Note: These settings differ from default httpd directory configuration:
# - Allow override by .htaccess files
# - Remove option 'indexes', do not allow directory listing.
RUN { \
    echo "DocumentRoot \"${DOCUMENTROOT}\""; \
    echo "<Directory \"${DOCUMENTROOT}\">"; \
    echo '    Options FollowSymLinks'; \
    echo '    AllowOverride All'; \
    echo '    Require all granted'; \
    echo '</Directory>'; \
} > /etc/httpd/conf.d/00-documentroot.conf

# Comment out docroot in httpd.conf to avoid confusion when overriding in separate configuration file.
RUN sed -i "s%^DocumentRoot \"/var/www/html\"%#DocumentRoot \"${DOCUMENTROOT}\" (Configured in httpd/conf.d/00-documentroot.conf) %" \
    /etc/httpd/conf/httpd.conf

# use prefork mpm
RUN echo 'LoadModule mpm_prefork_module modules/mod_mpm_prefork.so' > /etc/httpd/conf.modules.d/00-mpm.conf

# Configure prefork mpm
RUN { \
    echo '<IfModule mpm_prefork_module>'; \
    echo "    MaxRequestWorkers     ${HTTPD_MAX_REQUEST_WORKERS}"; \
    echo "    ServerLimit           ${HTTPD_MAX_REQUEST_WORKERS}"; \
    echo "    MaxConnectionsPerChild ${HTTPD_MAX_CONNECTIONS_PER_CHILD}"; \
    echo "    MaxKeepAliveRequests  ${HTTPD_MAX_KEEPALIVE_REQUESTS}"; \
    echo '</IfModule>'; \
} > /etc/httpd/conf.d/mpm.conf

# PHP Configuration ###

# php memory limit
RUN sed "s/^memory_limit = .*/memory_limit = ${PHP_MEMORY_LIMIT}/" \
    /etc/php.ini > /tmp/php.ini && cat /tmp/php.ini > /etc/php.ini

# php opcache variables
RUN sed -i "s/^;opcache.revalidate_freq=.*/opcache.revalidate_freq=${OPCACHE_REVALIDATE_FREQ}/" /etc/php.d/10-opcache.ini && \
    sed -i "s/^;opcache.memory_consumption=.*/opcache.memory_consumption=${OPCACHE_MEMORY_CONSUMPTION}/" /etc/php.d/10-opcache.ini && \
    sed -i "s/^;opcache.max_accelerated_files=.*/opcache.max_accelerated_files=${OPCACHE_MAX_FILES}/" /etc/php.d/10-opcache.ini


# Ensure we can run as non-root user
RUN sed -i "s/^Listen 80/Listen 0.0.0.0:8080/" /etc/httpd/conf/httpd.conf

# Configure user/group for running apache
RUN sed -i "s%^User apache%User #1001%" \
    /etc/httpd/conf/httpd.conf
RUN sed -i "s%^Group apache%Group root%" \
    /etc/httpd/conf/httpd.conf

RUN chown -R 1001:0 /run/httpd /etc/httpd/run /var/log/httpd
RUN chmod g+wX /run/httpd /etc/httpd/run /var/log/httpd


USER 1001


ENTRYPOINT ["httpd", "-D", "FOREGROUND"]
