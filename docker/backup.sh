#!/usr/bin/env bash
# bcdi-backup — archive l'installation BCDI complète dans /home/gestbcdi.
#
# Rôle
#   Crée BACKUP_DIR/bcdi-AAAAMMJJ-HHMMSS.tar.gz contenant tout BCDI_HOME
#   (prog/, bases Data/, licence, réglages), puis applique la rétention.
#   Appelé par « docker compose run --rm bcdi sauvegarde » et par
#   scripts/sauvegarde.sh, qui arrête le serveur avant pour un instantané
#   cohérent.
#
# Variables
#   BCDI_HOME         installation à archiver (défaut /usr/bcdiserv) ;
#   BACKUP_DIR        destination (défaut /home/gestbcdi, montée sur ./backups) ;
#   BACKUP_KEEP_DAYS  rétention en jours (0 ou vide = pas de purge).
#
# Effets
#   - archive compressée, droits 0640 (données sensibles) ;
#   - suppression des bcdi-*.tar.gz plus anciens que la rétention.
#
# Appelé dans le conteneur en tant que gestbcdi : l'archive appartient à
# l'utilisateur BCDI et reste lisible sur l'hôte via ./backups.
set -euo pipefail

BCD_HOME="${BCDI_HOME:-/usr/bcdiserv}"
BACKUP_DIR="${BACKUP_DIR:-/home/gestbcdi}"
KEEP_DAYS="${BACKUP_KEEP_DAYS:-30}"

[ -d "$BCD_HOME" ] || { echo "ERREUR : $BCD_HOME est absent" >&2; exit 1; }
mkdir -p "$BACKUP_DIR"

stamp="$(date '+%Y%m%d-%H%M%S')"
out="$BACKUP_DIR/bcdi-$stamp.tar.gz"

echo "Sauvegarde de $BCD_HOME vers $out"
tar -czf "$out" -C "$(dirname "$BCD_HOME")" "$(basename "$BCD_HOME")"
chmod 0640 "$out"

echo "Archive créée : $out ($(du -h "$out" | cut -f1))"

if [ "$KEEP_DAYS" -gt 0 ] 2>/dev/null; then
    find "$BACKUP_DIR" -maxdepth 1 -type f -name 'bcdi-*.tar.gz' \
        -mtime +"$KEEP_DAYS" -print -delete
fi
