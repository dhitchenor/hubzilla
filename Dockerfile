FROM alpine:3.24.3 AS build

ARG HZ_REPO=https://framagit.org/hubzilla/core
ARG HZ_VERSION=11.2

RUN apk add bash \
  curl \
  gd \
  git \
  patch \
  php83 \
  php83-common \
  php83-curl \
  php83-gd \
  php83-iconv \
  php83-intl \
  php83-mbstring \
  php83-mysqli \
  php83-openssl \
  php83-pecl-imagick \
  php83-pecl-mcrypt \
  php83-pgsql \
  php83-xml \
  php83-zip \
 && git clone $HZ_REPO /hubzilla

WORKDIR /hubzilla

COPY entrypoint.sh /hubzilla

RUN chmod +x /hubzilla/entrypoint.sh \
 && git checkout tags/$HZ_VERSION \
 && rm -rf .git \
 && mkdir -p "addon" \
 && mkdir -p "extend" \
 && mkdir -p "log" \
 && mkdir -p "store/[data]/smarty3" \
 && mkdir -p "view/theme" \
 && mkdir -p "widget" \
 && util/add_widget_repo https://framagit.org/hubzilla/widgets.git hubzilla-widgets \
 && util/add_addon_repo https://framagit.org/hubzilla/addons.git hzaddons \
 && util/add_addon_repo https://framagit.org/dentm42/dm42-hz-addons.git dm42 \
 && util/update_widget_repo hubzilla-widgets \
 && util/update_addon_repo hzaddons \
 && util/update_addon_repo dm42

FROM php:8.3.36-fpm-alpine3.24

RUN apk --update --no-cache --no-progress add \
  bash \
  git \
  gmp \
  icu-libs \
  imagemagick \
  jpeg \
  libavif \
  libgcc \
  libgd \
  libjpeg-turbo \
  libmcrypt \
  libpng \
  libsodium \
  libstdc++ \
  libwebp \
  libzip \
  mysql-client \
  musl \
  oniguruma \
  openldap-clients \
  postgresql-client \
  rsync \
  ssmtp \
  shadow \
  tzdata \
  zlib \
 && apk --update --no-progress add --virtual .build-deps \
  autoconf \
  build-base \
  curl-dev \
  freetype-dev \
  gmp-dev \
  icu-dev \
  icu-data-full \
  imagemagick-dev \
  libavif-dev \
  libjpeg-turbo-dev \
  libldap \
  libmcrypt-dev \
  libpng-dev \
  libsodium-dev \
  libtool \
  libwebp-dev \
  libxml2-dev \
  libzip-dev \
  make \
  oniguruma-dev \
  openldap-dev \
  postgresql-dev \
  postgresql-libs \
  unzip \
 && docker-php-ext-configure gd --with-freetype --with-jpeg --with-webp --with-avif \
 ### Make sure there are NO 'configure' commands after this command. Ref: https://github.com/docker-library/php/issues/926 ###
 && docker-php-ext-install \
  curl \
  gd \
  gmp \
  intl \
  ldap \
  mbstring \
  mysqli \
  opcache \
  pdo \
  pdo_mysql \
  pdo_pgsql \
  pgsql \
  sodium \
  xml \
  zip \
 && docker-php-ext-enable gmp \
 && docker-php-ext-enable intl.so \
 && pecl install imagick \
 && docker-php-ext-enable imagick \
 && pecl install -o -f redis \
 && docker-php-ext-enable redis.so \
 && pecl install xhprof \
 && docker-php-ext-enable xhprof.so \
 && echo 'xhprof.output_dir = "/var/www/html/xhprof"'|tee -a /usr/local/etc/php/conf.d/docker-php-ext-xhprof.ini \
 && sed -i '/www-data/s#:[^:]*$#:/bin/bash#' /etc/passwd \
 && echo 'sendmail_path = "/usr/sbin/ssmtp -t"' > /usr/local/etc/php/conf.d/mail.ini \
 && echo -e 'upload_max_filesize = 100M\npost_max_size = 101M' > /usr/local/etc/php/conf.d/hubzilla.ini \
 && echo -e '#!/bin/sh\ncd /var/www/html\n/usr/local/bin/php /var/www/html/Zotlabs/Daemon/Master.php Cron' >/etc/periodic/15min/hubzilla \
 && chmod 755 /etc/periodic/15min/hubzilla \
 && apk --purge del .build-deps \
 && rm -rf /tmp/* /var/cache/apk/*gz

COPY --from=build /hubzilla /var/www/html

ENTRYPOINT [ "/var/www/html/entrypoint.sh" ]

CMD ["php-fpm"]

VOLUME /var/www/html
