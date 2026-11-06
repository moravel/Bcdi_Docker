#!/usr/bin/env bash
# bcdi-restore — restaure une installation complète depuis une archive.
#
# Rôle
#   Extrait une archive bcdi-backup, vérifie qu'elle contient bien prog/ConsBcdi,
#   conserve l'installation actuelle dans BACKUP_DIR/avant-restauration-<date>,
#   puis remplace intégralement BCDI_HOME et rétablit les droits gestbcdi.
#
# Usage (dans le conteneur)
#   restaurer /home/gestbcdi/bcdi-AAAAMMJJ-HHMMSS.tar.gz
#   ./scripts/restaurer.sh backups/<archive>   (côté hôte)
#
# Conditions
#   - root dans le conteneur (docker compose run --rm bcdi restaurer ...) ;
#   - serveur ConsBcdi arrêté : le script refuse sinon ;
#   - archive lisible et non vide.
#
# Variables : BCDI_HOME (défaut /usr/bcdiserv), BACKUP_DIR (défaut
# /home/gestbcdi).
#
# Sortie : 0 si restauré, 2 pour un usage/archive invalide, 1 si le serveur
# tourne encore ou si l'archive ne contient pas prog/ConsBcdi.
set -euo pipefail

BCD_HOME="${BCDI_HOME:-/usr/bcdiserv}"
BACKUP_DIR="${BACKUP_DIR:-/home/gestbcdi}"
archive="${1:-}"

if [ -z "$archive" ]; then
    echo "usage : restaurer <archive.tar.gz> (dans le conteneur)" >&2
    exit 2
fi
[ -f "$archive" ] || { echo "ERREUR : archive introuvable : $archive" >&2; exit 2; }
[ "$(id -u)" -eq 0 ] || { echo "ERREUR : restauration en root requise" >&2; exit 1; }
if pgrep -x ConsBcdi >/dev/null 2>&1; then
    echo "ERREUR : le serveur BCDI fonctionne, arrêtez-le avant la restauration" >&2
    exit 1
fi

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

echo "Extraction de $archive"
tar -xzf "$archive" -C "$tmp"

root="$(dirname "$(dirname "$(find "$tmp" -maxdepth 4 -type f -path '*/prog/ConsBcdi' -print -quit)")")"
[ -n "$root" ] && [ -d "$root/prog" ] || { echo "ERREUR : archive inattendue (prog/ConsBcdi absent)" >&2; exit 1; }

old="$BACKUP_DIR/avant-restauration-$(date '+%Y%m%d-%H%M%S')"
mkdir -p "$old"
echo "Copie de l'installation actuelle vers $old"
cp -a "$BCD_HOME/." "$old"/

echo "Remplacement de $BCD_HOME"
find "$BCD_HOME" -mindepth 1 -maxdepth 1 -exec rm -rf {} +
cp -a "$root/." "$BCD_HOME"/
chown -R gestbcdi:gestbcdi "$BCD_HOME"

echo "Restauration terminée dans $BCD_HOME"
echo "Ancienne installation conservée dans $old"
