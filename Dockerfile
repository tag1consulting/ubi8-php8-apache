# Builder image to compile dependencies, outputs are opied to new image
# and artifacts are discarded.
FROM registry.access.redhat.com/ubi8/ubi-minimal as builder

USER root

COPY build/ImageMagick-7.0.11-6.tar.gz /tmp/.

# Build and install ImageMagick to tmp folder (to be copied to final image)
RUN microdnf -y install tar \
    gzip \
    gcc \
    diffutils \
    make && \
    pushd /tmp && \
    tar -xzf ImageMagick-7.0.11-6.tar.gz && \
    pushd ImageMagick-7.0.11-6 && \
    ./configure --prefix /tmp/ImageMagickInstall --disable-dependency-tracking --disable-docs && \
    pushd /tmp/ImageMagick-7.0.11-6 && \
    make -j `nproc` install

# Install ImageMagick as php extension
RUN microdnf -y install php-pear \
    php-devel \
    php-pecl-zip \
    php-xmlrpc && \
    cp -r /tmp/ImageMagickInstall/* /usr/local && \
    echo '' | pecl install imagick && \
    echo "extension=imagick.so" >> /etc/php.d/30-imagick.ini


# define final image, copy imagemagick components from staged build.
FROM registry.access.redhat.com/ubi8/ubi-minimal

LABEL name="ubi8-php8-apache" \
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
ENV DOCUMENTROOT "/html"
ENV APP_DATA "/var/www"

USER root

# Install image magick from build stage
COPY --from=builder /tmp/ImageMagickInstall /usr/local

# Install imagemagick php extension and other installed extensions
COPY --from=builder /usr/lib64/php/modules /usr/lib64/php/modules

# Reinstall timezone data (required by php runtime)
# (ubi-minimal has tzdata, but removed /usr/share/zoneinfo to save space.)
RUN microdnf upgrade && \
    microdnf reinstall tzdata

# Install php 8.1 and httpd 2.4
RUN rpm -i https://dl.fedoraproject.org/pub/epel/epel-release-latest-8.noarch.rpm && \
    rpm -i https://rpms.remirepo.net/enterprise/remi-release-8.rpm && \
    microdnf module reset php && \
    microdnf module enable php:remi-8.1 \
    httpd:2.4 && \
    microdnf install php \
    httpd

RUN chown -R apache:0 /run/httpd /etc/httpd/run /var/log/httpd

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

# Ensure we can run as non-root user
RUN sed -i "s/^Listen 80/Listen 0.0.0.0:8080/" /etc/httpd/conf/httpd.conf

# Entrypoint script modifies configuration based on enviornment variables.
# Add root group to apache for access to configuration.
# Enable write permissions on required files/directories.
RUN usermod -a -G root apache && \
    chmod -R g+w /etc/httpd/ && \
    chmod g+w /etc/php.d && \
    chmod g+w /etc/php.ini

COPY ./entrypoint.sh /usr/local
RUN chown apache:0 /usr/local/entrypoint.sh

USER apache


ENTRYPOINT ["/usr/local/entrypoint.sh"]
