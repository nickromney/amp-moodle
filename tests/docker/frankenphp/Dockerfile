FROM dunglas/frankenphp:1.13.2-php8.4.27-bookworm@sha256:49369ff211d81dc30a15890d58c0651d639aef0d9c0a9b91bcc6f387a77bd7a2

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

RUN set -eu; \
    curl -fsSLo /tmp/composer-setup.php https://getcomposer.org/installer; \
    curl -fsSLo /tmp/composer-setup.sig https://composer.github.io/installer.sig; \
    signature="$(cat /tmp/composer-setup.sig)"; \
    test "${#signature}" -eq 96; \
    case "$signature" in *[!0-9a-fA-F]*) exit 1;; esac; \
    printf '%s  %s\n' "$signature" /tmp/composer-setup.php | sha384sum --check --status; \
    php /tmp/composer-setup.php --install-dir=/usr/local/bin --filename=composer; \
    rm -f /tmp/composer-setup.php /tmp/composer-setup.sig

RUN mkdir -p /app/public /app/moodledata

WORKDIR /app/public

RUN curl -fsSL -o /tmp/moodle.tgz https://packaging.moodle.org/stable502/moodle-5.2.2.tgz \
    && tar -xzf /tmp/moodle.tgz --strip-components=1 -C /app/public \
    && rm -f /tmp/moodle.tgz

RUN composer install --no-dev --optimize-autoloader --no-interaction

RUN printf 'max_input_vars=5000\nmemory_limit=256M\n' > /usr/local/etc/php/conf.d/zz-moodle.ini
