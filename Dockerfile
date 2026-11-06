# Serveur BCDI (Réseau Canopé) - image d'exécution
#
# L'image ne contient AUCUN binaire BCDI : le logiciel est propriétaire et
# n'est distribué qu'aux abonnés via l'espace client. Elle fournit uniquement
# l'environnement nécessaire aux binaires Linux 32 bits du serveur.
#
# Base Debian 9 (i386), volontairement ancienne : les exécutables Borland/
# Kylix de BCDI 2.52 plantent au chargement de libExportSo.so avec les glibc
# récentes (vérifié : OK sur stretch, SIGSEGV sur buster et bookworm). Le
# userland est entièrement 32 bits, comme sur les serveurs Canopé d'origine.
#
# L'installation se fait une fois dans le volume persistant ./data/bcdiserv
# à partir de l'archive fournie par Canopé (voir README.md).

# Botte de certificats récente (l'archive Debian 9 n'en fournit plus).
FROM debian:bookworm-slim AS certs
RUN apt-get update \
 && apt-get install -y --no-install-recommends ca-certificates \
 && rm -rf /var/lib/apt/lists/*

FROM i386/debian:stretch-slim

ARG PUID=1000
ARG PGID=1000

LABEL org.opencontainers.image.title="Serveur BCDI pour Linux" \
      org.opencontainers.image.description="Environnement d'exécution du serveur BCDI en mode console (binaires propriétaires fournis par l'abonné, non inclus)" \
      org.opencontainers.image.licenses="GPL-3.0-only" \
      org.opencontainers.image.documentation="NOTICE.md"

ENV LANG=fr_FR.UTF-8 \
    LANGUAGE=fr_FR:fr \
    LC_ALL=fr_FR.UTF-8 \
    TZ=Europe/Paris \
    DEBIAN_FRONTEND=noninteractive \
    BCDI_HOME=/usr/bcdiserv \
    BCDI_USER=gestbcdi \
    BCDIPORT=9000 \
    BACKUP_DIR=/home/gestbcdi \
    SOURCES_DIR=/sources

# Debian 9 est archivée : les dépôts officiels ne répondent plus.
# net-tools + gawk + perl sont utilisés par les scripts Canopé
# (consolebcdi, install_majbcdi-abt.sh, alertmajbcdi.pl).
RUN printf '%s\n' \
        'deb [trusted=yes] http://archive.debian.org/debian stretch main' \
        'deb [trusted=yes] http://archive.debian.org/debian-security stretch/updates main' \
        > /etc/apt/sources.list \
 && printf '%s\n' \
        'Acquire::Check-Valid-Until "false";' \
        'Acquire::AllowInsecureRepositories "true";' \
        > /etc/apt/apt.conf.d/99archive \
 && apt-get update \
 && apt-get install -y --no-install-recommends \
        bash ca-certificates locales tzdata \
        perl net-tools gawk \
        procps psmisc util-linux passwd adduser \
        iproute2 coreutils \
        tar gzip xz-utils bzip2 file less \
 && sed -i \
        -e 's/^# *\(fr_FR.UTF-8 UTF-8\)/\1/' \
        -e 's/^# *\(fr_FR ISO-8859-1\)/\1/' \
        /etc/locale.gen \
 && locale-gen \
 && rm -rf /var/lib/apt/lists/*

COPY --from=certs /etc/ssl/certs/ca-certificates.crt /etc/ssl/certs/ca-certificates.crt

# Utilisateur et groupe propriétaires des fichiers BCDI (noms attendus par
# les scripts Canopé : gestbcdi).
RUN if [ "${PUID}" = "0" ] || [ "${PGID}" = "0" ]; then \
        echo "ERREUR : PUID/PGID=0 refusé (UID/GID privilégié) : indiquez 1000." >&2; \
        exit 1; \
    fi \
 && groupadd --gid "${PGID}" gestbcdi \
 && useradd --uid "${PUID}" --gid gestbcdi --create-home \
        --home-dir /home/gestbcdi --shell /bin/bash gestbcdi \
 && mkdir -p "${BCDI_HOME}" /sources /home/gestbcdi \
 && chown -R gestbcdi:gestbcdi "${BCDI_HOME}" /home/gestbcdi

COPY docker/entrypoint.sh /usr/local/bin/entrypoint.sh
COPY docker/healthcheck.sh /usr/local/bin/healthcheck.sh
COPY docker/backup.sh /usr/local/sbin/bcdi-backup
COPY docker/restore.sh /usr/local/sbin/bcdi-restore

RUN chmod 0755 \
        /usr/local/bin/entrypoint.sh \
        /usr/local/bin/healthcheck.sh \
        /usr/local/sbin/bcdi-backup \
        /usr/local/sbin/bcdi-restore

WORKDIR /usr/bcdiserv
EXPOSE 9000

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["serveur"]
