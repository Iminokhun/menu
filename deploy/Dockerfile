# Образ платформы меню: сервер (Dart + SQLite), сайт меню для гостей и
# главная админка. Собирается из корня проекта:
#   docker compose -f deploy/docker-compose.yml build
#
# Версии закреплены — сборка через месяц даст то же, что сегодня.

# ---- 1. Сервер ------------------------------------------------------------
FROM dart:3.13.5 AS server
WORKDIR /src/server
# Сначала только зависимости: при правке кода этот слой берётся из кэша
COPY server/pubspec.yaml server/pubspec.lock ./
RUN dart pub get
COPY server/ ./
RUN dart build cli -t bin/server.dart -o /out

# ---- 2. Сайты: меню и главная админка ------------------------------------
# Flutter — из официального репозитория, той же версии, что при разработке:
# готового образа нужной версии в публичных реестрах нет
FROM debian:bookworm-slim AS web
RUN apt-get update \
 && apt-get install -y --no-install-recommends ca-certificates curl git unzip xz-utils \
 && rm -rf /var/lib/apt/lists/*
ARG FLUTTER_VERSION=3.47.6
RUN git clone --depth 1 --branch ${FLUTTER_VERSION} https://github.com/flutter/flutter.git /opt/flutter
ENV PATH="/opt/flutter/bin:${PATH}"
RUN flutter config --no-analytics --enable-web \
 && flutter precache --web
WORKDIR /src
COPY pubspec.yaml pubspec.lock analysis_options.yaml ./
COPY super_admin/pubspec.yaml super_admin/pubspec.lock super_admin/
RUN flutter pub get && cd super_admin && flutter pub get
COPY lib/ lib/
COPY web/ web/
COPY assets/ assets/
COPY super_admin/ super_admin/
# API_URL не задаём: сайт обращается к серверу по адресу, с которого открыт
RUN flutter build web --release
RUN cd super_admin && flutter build web --release --base-href /menu-kg/

# ---- 3. Готовый образ -----------------------------------------------------
FROM debian:bookworm-slim
RUN apt-get update \
 && apt-get install -y --no-install-recommends ca-certificates curl \
 && rm -rf /var/lib/apt/lists/* \
 && useradd --system --uid 1001 --home /app menu \
 && mkdir -p /data /backups \
 && chown menu:menu /data /backups

COPY --from=server /out/bundle /app/server
COPY --from=web /src/build/web /app/web
COPY --from=web /src/super_admin/build/web /app/menu-kg

ENV DATA_DIR=/data \
    PORT=8090 \
    MENU_WEB_DIR=/app/web \
    SUPER_WEB_DIR=/app/menu-kg

USER menu
EXPOSE 8090
VOLUME ["/data"]

HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
  CMD curl -fsS http://localhost:8090/api/health || exit 1

CMD ["/app/server/bin/server"]
