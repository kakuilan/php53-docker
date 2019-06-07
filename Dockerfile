FROM debian:jessie

MAINTAINER kakuilan kakuilan@163.com

ENV GPG_KEYS 0B96609E270F565C13292B24C13C70B87267B52D 0A95E9A026542D53835E3F3A7DEC4E69FC9C83D7 0E604491
ENV SRC_DIR /usr/src/php
ENV PHP_VERSION 5.3.29
ENV PHP_INI_DIR /usr/local/etc/php
ENV PHPREDIS_VER 4.2.0

# install deps
RUN apt-get update && apt-get install -y --no-install-recommends \
	autoconf \
	autoconf2.13 \
	ca-certificates \
	curl \
	dpkg-dev \
	file \
	g++ \
	gcc \
	libc-dev \
	libcurl4-openssl-dev \
	libedit-dev \
	libmysqlclient-dev \
	libpcre3 \
	libpcre3-dev \
	libreadline6-dev \
	librecode-dev \
	librecode0 \
	libsqlite3-0 \
	libsqlite3-dev \
	libssl-dev \
	libxml2 \
	libxml2-dev \
	make \
	pkg-config \
	re2c \
	xz-utils \
	xz-utils \
	zlib1g-dev \
    autoconf \
    ca-certificates \
    curl \
    file \
    g++ \
    gcc \
    htop \
    libbz2-dev \
    libc-client-dev \
    libc-dev \
    libcurl4-openssl-dev \
    libfreetype6 \
    libfreetype6-dev \
    libjpeg-dev \
    libkrb5-dev \
    libmagickwand-dev \
    libmcrypt-dev \
    libmysqlclient-dev \
    libpng-dev \
    libpq-dev \
    libreadline6-dev \
    librecode-dev \
    librecode0 \
    libsqlite3-0 \
    libsqlite3-dev \
    libssl-dev \
    libxml2 \
    libxml2-dev \
    libzip-dev \
    make \
    mc \
    mc-data \
    pkg-config \
    re2c \
    ssmtp \
    w3m \
    xz-utils \
    zip \
    zlib1g-dev \
    && apt-get clean \
    && rm -r /var/lib/apt/lists/*


RUN mkdir -p $SRC_DIR $PHP_INI_DIR/conf.d
RUN set -xe \
  && for key in $GPG_KEYS; do \
    gpg --keyserver ha.pool.sks-keyservers.net --recv-keys "$key"; \
  done

# compile openssl, otherwise --with-openssl won't work
RUN OPENSSL_VERSION="1.0.2q" \
      && cd /tmp \
      && mkdir openssl \
      && curl -sL "https://www.openssl.org/source/openssl-$OPENSSL_VERSION.tar.gz" -o openssl.tar.gz \
      && curl -sL "https://www.openssl.org/source/openssl-$OPENSSL_VERSION.tar.gz.asc" -o openssl.tar.gz.asc \
      && gpg --verify openssl.tar.gz.asc \
      && tar -xzf openssl.tar.gz -C openssl --strip-components=1 \
      && cd /tmp/openssl \
      && ./config && make && make install \
      && rm -rf /tmp/*

# php 5.3 needs older autoconf
# --enable-mysqlnd is included below because it's harder to compile after the fact the extensions are (since it's a plugin for several extensions, not an extension in itself)
RUN set -x \
      && curl -SL "http://php.net/get/php-$PHP_VERSION.tar.xz/from/this/mirror" -o php.tar.xz \
      && curl -SL "http://php.net/get/php-$PHP_VERSION.tar.xz.asc/from/this/mirror" -o php.tar.xz.asc \
      && gpg --verify php.tar.xz.asc \
      && tar -xof php.tar.xz -C $SRC_DIR --strip-components=1 \
      && rm php.tar.xz* \
      && cd $SRC_DIR \
      && ./configure \
            --with-config-file-path="$PHP_INI_DIR" \
            --with-config-file-scan-dir="$PHP_INI_DIR/conf.d" \
			--disable-cgi \
			--enable-bcmath \
			--enable-calendar \
			--enable-exif \
			--enable-fpm \
			--enable-ftp \
			--enable-mbstring \
			--enable-mysqlnd \
			--enable-soap \
			--enable-sockets \
			--enable-zip \
			--with-bz2 \
			--with-curl \
			--with-fpm-group=www-data \
			--with-fpm-user=www-data \
			--with-freetype-dir=/usr/include \
			--with-gd \
			--with-imap \
			--with-imap-ssl \
			--with-jpeg-dir=/usr/lib/x86_64-linux-gnu \
			--with-kerberos \
			--with-mhash \
			--with-mysql \
			--with-mysqli \
			--with-openssl=/usr/local/ssl \
			--with-pdo-mysql \
			--with-pdo-pgsql \
			--with-pgsql=/usr/local/pgsql \
			--with-png \
			--with-readline \
			--with-recode \
			--with-xmlrpc \
			--with-zlib \
      && make -j"$(nproc)" \
      && make install \
      && { find /usr/local/bin /usr/local/sbin -type f -executable -exec strip --strip-all '{}' + || true; } \
      && apt-get purge -y --auto-remove -o APT::AutoRemove::RecommendsImportant=false -o APT::AutoRemove::SuggestsImportant=false $buildDeps \
      && make clean

COPY docker-php-* /usr/local/bin/

# install php-redis
RUN curl -SL "https://pecl.php.net/get/redis-${PHPREDIS_VER}.tgz" -o redis-${PHPREDIS_VER}.tgz \
  && tar xzf redis-${PHPREDIS_VER}.tgz \
  && mv redis-${PHPREDIS_VER} /usr/src/php/ext/redis \
  && rm -rf redis-${PHPREDIS_VER}* \
  && /usr/local/bin/docker-php-ext-install redis

RUN set -ex \
  && cd /usr/local/etc \
  && if [ -d php-fpm.d ]; then \
    # for some reason, upstream's php-fpm.conf.default has "include=NONE/etc/php-fpm.d/*.conf"
    sed 's!=NONE/!=!g' php-fpm.conf.default | tee php-fpm.conf > /dev/null; \
    cp php-fpm.d/www.conf.default php-fpm.d/www.conf; \
  else \
    # PHP 5.x don't use "include=" by default, so we'll create our own simple config that mimics PHP 7+ for consistency
    mkdir php-fpm.d; \
    cp php-fpm.conf.default php-fpm.d/www.conf; \
    { \
      echo '[global]'; \
      echo 'include=etc/php-fpm.d/*.conf'; \
    } | tee php-fpm.conf; \
  fi \
  && { \
    echo '[global]'; \
    echo 'error_log = /proc/self/fd/2'; \
    echo; \
    echo '[www]'; \
    echo '; if we send this to /proc/self/fd/1, it never appears'; \
    echo 'access.log = /proc/self/fd/2'; \
    echo; \
    echo '; Ensure worker stdout and stderr are sent to the main error log.'; \
    echo 'catch_workers_output = yes'; \
  } | tee php-fpm.d/docker.conf \
  && { \
    echo '[global]'; \
    echo 'daemonize = no'; \
    echo; \
    echo '[www]'; \
    echo 'listen = 9000'; \
  } | tee php-fpm.d/zz-docker.conf

# fix some weird corruption in this file
RUN sed -i -e "" /usr/local/etc/php-fpm.d/www.conf

WORKDIR /var/www/html
EXPOSE 9000
CMD ["php-fpm"]