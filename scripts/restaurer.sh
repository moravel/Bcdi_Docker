#!/usr/bin/env bash
# restaurer.sh — restaure une installation BCDI complète depuis backups/.
#
# Rôle
#   Remplace toute l'installation (prog/, Data/, licence, version) par le
#   contenu d'une archive produite par bcdi-backup. À ne pas confondre avec
#   restaurer-base.sh, qui ne remplace que la base principale.
#
# Usage
#   ./scripts/restaurer.sh backups/bcdi-AAAAMMJJ-HHMMSS.tar.gz
#
# Contraintes
#   - l'archive doit se trouver dans le dossier backups/ du kit (elle est lue
#     dans le conteneur sous /home/gestbcdi) ;
#   - le serveur est arrêté puis redémarré automatiquement (trap) ;
#   - l'installeur vérifie la présence de prog/ConsBcdi dans l'archive ;
#   - l'installation courante est copiée dans
#     backups/avant-restauration-AAAAMMJJ-HHMMSS avant remplacement.
#
# Sortie : 0 si la restauration aboutit, 2 pour un usage incorrect, 1 sur
# archive invalide ou serveur encore actif.
set -euo pipefail
cd "$(dirname "$0")/.."

archive="${1:-}"
if [ -z "$archive" ] || [ ! -f "$archive" ]; then
    echo "usage : $0 backups/bcdi-AAAAMMJJ-HHMMSS.tar.gz" >&2
    exit 2
fi

archive_abs="$(cd "$(dirname "$archive")" && pwd)/$(basename "$archive")"
case "$archive_abs" in
    "$(pwd)/backups/"*) ;;
    *) echo "ERREUR : placez l'archive dans $(pwd)/backups" >&2; exit 2 ;;
esac

docker compose stop bcdi >/dev/null || true
trap 'echo "Redémarrage du serveur BCDI"; docker compose up -d bcdi >/dev/null' EXIT

docker compose run --rm --no-deps -T bcdi restaurer "/home/gestbcdi/$(basename "$archive_abs")"
