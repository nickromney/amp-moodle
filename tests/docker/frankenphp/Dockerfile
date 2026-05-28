FROM dunglas/frankenphp:php8.4-bookworm

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update \
    && apt-get install -y --no-install-recommends curl mariadb-client unzip \
    && rm -rf /var/lib/apt/lists/*

RUN install-php-extensions \
    gd \
    intl \
    mysqli \
    pdo_mysql \
    soap \
    zip \
    opcache \
    ldap

RUN curl -fsSL https://getcomposer.org/installer | php -- --install-dir=/usr/local/bin --filename=composer

RUN mkdir -p /app/public /app/moodledata

WORKDIR /app/public

RUN curl -fsSL -o /tmp/moodle.tgz https://packaging.moodle.org/stable501/moodle-5.1.3.tgz \
    && tar -xzf /tmp/moodle.tgz --strip-components=1 -C /app/public \
    && rm -f /tmp/moodle.tgz

RUN composer install --no-dev --optimize-autoloader --no-interaction

RUN printf 'max_input_vars=5000\nmemory_limit=256M\n' > /usr/local/etc/php/conf.d/zz-moodle.ini
