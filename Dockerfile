FROM buildpack-deps:jessie

COPY ./oracle/. /tmp/.

ENV LD_LIBRARY_PATH /usr/local/instantclient

RUN apt-get update && apt-get install -y --no-install-recommends curl \
    apache2-bin apache2-dev apache2.2-common && \
    rm -rf /var/lib/apt/lists/*

RUN rm -rf /var/www/html && \
    rm /etc/apache2/conf-enabled/*.conf && \
    mkdir -p /var/lock/apache2 /var/run/apache2 /var/log/apache2 /var/www/html && \
    chown -R www-data:www-data /var/lock/apache2 /var/run/apache2 /var/log/apache2 /var/www/html

# Apache + PHP requires preforking Apache for best results
# Enable sls and rewrite modules as we always use these
RUN a2dismod mpm_event && a2enmod mpm_prefork && \
    a2enmod ssl rewrite deflate

RUN mv /etc/apache2/apache2.conf /etc/apache2/apache2.conf.dist
COPY apache2.conf /etc/apache2/apache2.conf
COPY apache2-foreground /usr/local/bin/

RUN gpg --keyserver ha.pool.sks-keyservers.net --recv-keys 0B96609E270F565C13292B24C13C70B87267B52D 0A95E9A026542D53835E3F3A7DEC4E69FC9C83D7

ENV GPG_KEYS 0B96609E270F565C13292B24C13C70B87267B52D 0A95E9A026542D53835E3F3A7DEC4E69FC9C83D7 0E604491
RUN set -xe \
  && for key in $GPG_KEYS; do \
    gpg --keyserver ha.pool.sks-keyservers.net --recv-keys "$key"; \
  done

# compile openssl, otherwise --with-openssl won't work
RUN CFLAGS="-fPIC" && OPENSSL_VERSION="1.0.2d" \
      && cd /tmp \
      && mkdir openssl \
      && curl -sL "https://www.openssl.org/source/openssl-$OPENSSL_VERSION.tar.gz" -o openssl.tar.gz \
      && curl -sL "https://www.openssl.org/source/openssl-$OPENSSL_VERSION.tar.gz.asc" -o openssl.tar.gz.asc \
      && gpg --verify openssl.tar.gz.asc \
      && tar -xzf openssl.tar.gz -C openssl --strip-components=1 \
      && cd /tmp/openssl \
      && ./config shared && make && make install \
      && rm -rf /tmp/*

ENV PHP_VERSION=5.3.29 \
    PHP_INI_DIR=/usr/local/lib

# php 5.3 needs older autoconf
RUN set -x \
	&& apt-get update && apt-get install -y autoconf2.13 && rm -r /var/lib/apt/lists/* \
	&& curl -SLO http://launchpadlibrarian.net/140087283/libbison-dev_2.7.1.dfsg-1_amd64.deb \
	&& curl -SLO http://launchpadlibrarian.net/140087282/bison_2.7.1.dfsg-1_amd64.deb \
	&& dpkg -i libbison-dev_2.7.1.dfsg-1_amd64.deb \
	&& dpkg -i bison_2.7.1.dfsg-1_amd64.deb \
	&& rm *.deb \
	&& curl -SL "http://php.net/get/php-$PHP_VERSION.tar.bz2/from/this/mirror" -o php.tar.bz2 \
	&& curl -SL "http://php.net/get/php-$PHP_VERSION.tar.bz2.asc/from/this/mirror" -o php.tar.bz2.asc \
	&& gpg --verify php.tar.bz2.asc \
	&& mkdir -p /usr/src/php $PHP_INI_DIR/conf.d \
	&& tar -xf php.tar.bz2 -C /usr/src/php --strip-components=1 \
	&& rm php.tar.bz2* \
	&& cd /usr/src/php \
	&& ./buildconf --force \
	&& ./configure --disable-cgi \
		$(command -v apxs2 > /dev/null 2>&1 && echo '--with-apxs2' || true) \
    --with-config-file-path="$PHP_INI_DIR" \
    --with-config-file-scan-dir="$PHP_INI_DIR/conf.d" \
		--with-openssl=/usr/local/ssl \
	&& make -j"$(nproc)" \
	&& make install \
	&& dpkg -r bison libbison-dev \
	&& apt-get purge -y --auto-remove autoconf2.13 \
  && make clean

COPY docker-php-* /usr/local/bin/

# Install curl php extension as we use it often
RUN docker-php-ext-install curl

RUN apt-get install -y unzip

COPY ./oracle/. /tmp/.

RUN unzip -o /tmp/instantclient-basic-linux.x64-12.2.0.1.0.zip -d /usr/local/ && \
    unzip -o /tmp/instantclient-sdk-linux.x64-12.2.0.1.0.zip -d /usr/local/ && \
    unzip -o /tmp/instantclient-sqlplus-linux.x64-12.2.0.1.0.zip -d /usr/local/ && \
    ln -s /usr/local/instantclient_12_2 /usr/local/instantclient && \
    ln -s /usr/local/instantclient/libclntsh.so.12.1 /usr/local/instantclient/libclntsh.so && \
    ln -s /usr/local/instantclient/sqlplus /usr/bin/sqlplus && \
    echo 'export LD_LIBRARY_PATH="/usr/local/instantclient"' >> /root/.bashrc && \
    echo 'export ORACLE_HOME="/usr/local/instantclient"' >> /root/.bashrc && \
    echo 'umask 002' >> /root/.bashrc && \
    docker-php-ext-configure oci8 -with-oci8=instantclient,/usr/local/instantclient && \
    docker-php-ext-install oci8

RUN service apache2 restart

WORKDIR /var/www/html

EXPOSE 80
CMD ["apache2-foreground"]

# Basedo em: https://github.com/reallyenglish/docker-php-5.3-apache