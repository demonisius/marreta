# Stage 0: Base
FROM php:8.4-fpm AS base

# Install dependencies and extensions
RUN apt-get update && apt-get install -y \
    nginx \
    nano \
    procps \
    psmisc \
    zip \
    git \
    curl \
    htop \
    cron \
    libzip-dev \
    libsqlite3-dev \
    && docker-php-ext-install zip opcache pdo_sqlite \
    && docker-php-ext-enable opcache \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# Stage 1: Build stage
FROM base AS builder

# Copy OPCache configuration
COPY opcache.ini /usr/local/etc/php/conf.d/opcache.ini

# Install Composer
RUN curl -sS https://getcomposer.org/installer | php -- --install-dir=/usr/local/bin --filename=composer

# Copy app folder
COPY app/ /app/

# Install composer packages
WORKDIR /app
RUN composer install --no-interaction --optimize-autoloader

# https://github.com/ai-robots-txt/ai.robots.txt
## nginx-block-ai-bots.conf
RUN curl -sS https://raw.githubusercontent.com/ai-robots-txt/ai.robots.txt/main/nginx-block-ai-bots.conf -o /app/nginx-block-ai-bots.conf

# Stage 2: Final
FROM base

# Copy necessary files from the builder stage
COPY --from=builder /usr/local/etc/php/conf.d/opcache.ini /usr/local/etc/php/conf.d/opcache.ini
COPY --from=builder /usr/local/bin/composer /usr/local/bin/composer
COPY --from=builder /app /app

# Copy webservice configuration
COPY default.conf /etc/nginx/sites-available/default

# Copy and configure initialization script permissions
COPY docker-entrypoint.sh /usr/local/bin/
RUN chmod +x /usr/local/bin/docker-entrypoint.sh
RUN chmod +x /app/bin/cleanup
RUN chmod +x /app/bin/proxy

# Create cache, database, and logs folders
RUN mkdir -p /app/cache /app/cache/database /app/logs

# Configure base permissions for /app directory
RUN chown -R www-data:www-data /app \
    && chmod -R 755 /app

# Configure Cron
RUN touch /app/logs/cron.log
RUN echo '0 * * * * root php "/app/bin/cleanup" >> /app/logs/cleanup.log 2>&1' >> /etc/crontab
RUN echo '0 * * * * root php "/app/bin/proxy" >> /app/logs/proxy.log 2>&1' >> /etc/crontab

EXPOSE 80

ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"]