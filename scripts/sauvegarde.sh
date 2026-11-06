#!/usr/bin/env bash
# sauvegarde.sh — sauvegarde complète et cohérente du serveur BCDI.
#
# Rôle
#   Arrête le conteneur (les fichiers .DAT ne doivent pas être copiés en cours
#   d'écriture), demande une archive à bcdi-backup, puis redémarre le serveur.
#   Le redémarrage est garanti par un trap, même si l'archivage échoue.
#
# Usage
#   ./scripts/sauvegarde.sh
#
# Effets
#   - arrêt propre (SIGINT, jusqu'à 60 s) puis archive
#     backups/bcdi-AAAAMMJJ-HHMMSS.tar.gz (droits 0640) ;
#   - purge des archives plus anciennes que BACKUP_KEEP_DAYS (30 par défaut) ;
#   - redémarrage du serveur.
#
# Prérequis
#   Docker accessible ; installation présente dans data/bcdiserv.
#
# Cron conseillé (adapter le chemin) :
#   45 21 * * * /opt/bcdi/scripts/sauvegarde.sh \
#       >> /var/log/bcdi-sauvegarde.log 2>&1
#
# Attention : le service est indisponible pendant l'archivage (quelques
# secondes à quelques minutes selon la taille des bases).
set -euo pipefail
cd "$(dirname "$0")/.."

echo "[$(date '+%F %T')] Arrêt du serveur BCDI"
docker compose stop bcdi >/dev/null || true

trap 'echo "[$(date "+%F %T")] Redémarrage du serveur BCDI"; docker compose up -d bcdi >/dev/null' EXIT

docker compose run --rm --no-deps -T bcdi sauvegarde

echo "[$(date '+%F %T')] Sauvegarde terminée"
