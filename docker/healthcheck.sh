#!/usr/bin/env bash
# healthcheck.sh — état de santé du serveur BCDI pour Docker.
#
# Rôle
#   Le conteneur est « healthy » si les deux conditions sont réunies :
#     1. un processus ConsBcdi tourne (pgrep -x ConsBcdi) ;
#     2. le port BCDIPORT (9000) est en écoute (ss -ltn).
#
# Usage
#   /usr/local/bin/healthcheck.sh          # dans le conteneur
#   docker exec bcdi /usr/local/bin/healthcheck.sh
#
# Appelé par le healthcheck de docker-compose.yml (toutes les 30 s, 3 essais,
# 60 s de démarrage à froid).
#
# Sortie : 0 si sain, 1 sinon. Aucun effet de bord ; un échec se diagnostique
# avec « docker compose logs bcdi » et prog/LogBcdi.Txt.
set -euo pipefail

PORT="${BCDIPORT:-9000}"

pgrep -x ConsBcdi >/dev/null 2>&1 || exit 1
ss -ltn 2>/dev/null | grep -q ":${PORT}" || exit 1
