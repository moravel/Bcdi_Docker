#!/usr/bin/env bash
# verifier.sh — recette automatique après déploiement ou migration.
#
# Rôle
#   Vérifie que le serveur est réellement exploitable : conteneur présent,
#   healthcheck vert, commande statut exécutable, port publié en écoute,
#   fichier de licence lisible.
#
# Usage
#   ./verifier.sh
#
# Contrôles
#   1. docker compose ps ;
#   2. /usr/local/bin/healthcheck.sh dans le conteneur (ConsBcdi + port 9000) ;
#   3. entrypoint.sh statut (processus et clients connectés) ;
#   4. écoute du port BCDI_HOST_PORT sur l'hôte ;
#   5. présence de data/bcdiserv/prog/VersionBcdi.Txt (établissement + version).
#
# Le script n'arrête rien et ne modifie rien. Il accumule les échecs pour
# afficher tous les problèmes d'un coup, puis sort avec le code 1 si au moins
# un contrôle a échoué, 0 sinon. À lancer en root ou dans le groupe docker.
set -uo pipefail
cd "$(dirname "$0")"

fail=0
port="$(sed -n 's/^BCDI_HOST_PORT=//p' .env 2>/dev/null | tail -n 1)"
port="${port:-9000}"

echo "== Conteneur =="
docker compose ps || fail=1

echo "== Healthcheck =="
if docker exec bcdi /usr/local/bin/healthcheck.sh >/dev/null 2>&1; then
    echo "OK"
else
    echo "ÉCHEC : consultez docker compose logs bcdi" >&2
    fail=1
fi

echo "== État du serveur =="
docker compose exec -T bcdi /usr/local/bin/entrypoint.sh statut || fail=1

echo "== Port $port sur l'hôte =="
if ss -ltn 2>/dev/null | grep -q "[:.]${port} "; then
    echo "OK (écoute)"
else
    echo "ÉCHEC : aucun écoute sur le port $port" >&2
    fail=1
fi

echo "== Version / griffage =="
if [ -f data/bcdiserv/prog/VersionBcdi.Txt ]; then
    sed -n '1p;5p' data/bcdiserv/prog/VersionBcdi.Txt
else
    echo "ÉCHEC : VersionBcdi.Txt absent" >&2
    fail=1
fi

exit "$fail"
