#!/bin/sh

# Set env var defaults in case they are not yet defined.
export APP_DATA=${APP_DATA:-/var/www}
export DOCUMENTROOT=${DOCUMENTROOT:-/html}
export HTTPD_MAX_KEEPALIVE_REQUESTS=${HTTPD_MAX_KEEPALIVE_REQUESTS:-100}
export HTTPD_MAX_CONNECTIONS_PER_CHILD=${HTTPD_MAX_CONNECTIONS_PER_CHILD:-2000}
export HTTPD_MAX_REQUEST_WORKERS=${HTTPD_MAX_REQUEST_WORKERS:-256}
export PHP_MEMORY_LIMIT=${PHP_MEMORY_LIMIT:-256M}
export OPCACHE_MEMORY_CONSUMPTION=${OPCACHE_MEMORY_CONSUMPTION:-128}
export OPCACHE_REVALIDATE_FREQ=${OPCACHE_REVALIDATE_FREQ:-60}
export OPCACHE_MAX_FILES=${OPCACHE_MAX_FILES:-4000}

export DOCUMENTROOT_FULLPATH=${APP_DATA}${DOCUMENTROOT}

# HTTPD Configuration ###

# Note: These settings differ from default httpd directory configuration:
# - Allow override by .htaccess files
# - Remove option 'indexes', do not allow directory listing.
{ \
    echo "DocumentRoot \"${DOCUMENTROOT_FULLPATH}\""; \
    echo "<Directory \"${DOCUMENTROOT_FULLPATH}\">"; \
    echo '    Options FollowSymLinks'; \
    echo '    AllowOverride All'; \
    echo '    Require all granted'; \
    echo '</Directory>'; \
} > /etc/httpd/conf.d/00-documentroot.conf
#
# Comment out docroot in httpd.conf to avoid confusion when overriding in separate configuration file.
sed -i "s%^DocumentRoot \"/var/www/html\"%#DocumentRoot \"${DOCUMENTROOT_FULLPATH}\" (Configured in httpd/conf.d/00-documentroot.conf) %" \
    /etc/httpd/conf/httpd.conf

# use prefork mpm
echo 'LoadModule mpm_prefork_module modules/mod_mpm_prefork.so' > /etc/httpd/conf.modules.d/00-mpm.conf

# Configure prefork mpm
{ \
    echo '<IfModule mpm_prefork_module>'; \
    echo "    MaxRequestWorkers     ${HTTPD_MAX_REQUEST_WORKERS}"; \
    echo "    ServerLimit           ${HTTPD_MAX_REQUEST_WORKERS}"; \
    echo "    MaxConnectionsPerChild ${HTTPD_MAX_CONNECTIONS_PER_CHILD}"; \
    echo "    MaxKeepAliveRequests  ${HTTPD_MAX_KEEPALIVE_REQUESTS}"; \
    echo '</IfModule>'; \
} > /etc/httpd/conf.d/mpm.conf

# PHP Configuration ###

# php memory limit
sed "s/^memory_limit = .*/memory_limit = ${PHP_MEMORY_LIMIT}/" \
    /etc/php.ini > /tmp/php.ini && cat /tmp/php.ini > /etc/php.ini

# php opcache variables
sed -i "s/^;opcache.revalidate_freq=.*/opcache.revalidate_freq=${OPCACHE_REVALIDATE_FREQ}/" /etc/php.d/10-opcache.ini
sed -i "s/^;opcache.memory_consumption=.*/opcache.memory_consumption=${OPCACHE_MEMORY_CONSUMPTION}/" /etc/php.d/10-opcache.ini
sed -i "s/^;opcache.max_accelerated_files=.*/opcache.max_accelerated_files=${OPCACHE_MAX_FILES}/" /etc/php.d/10-opcache.ini


# Start apache
httpd -D FOREGROUND
