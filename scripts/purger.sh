#!/usr/bin/env bash
# purger.sh — remet le serveur BCDI à zéro avant une réinstallation.
#
# Rôle
#   Supprime le conteneur, le réseau Compose, l'image construite et tout le
#   répertoire du serveur actif (data/bcdiserv : bases, licence, programme).
#   Recrée ensuite data/bcdiserv et backups avec les droits de gestbcdi.
#
# Usage
#   ./scripts/purger.sh                    # confirmation + sauvegardes gardées
#   ./scripts/purger.sh --force            # sans confirmation
#   ./scripts/purger.sh --sauvegardes      # supprime aussi backups/
#   ./scripts/purger.sh --force --sauvegardes
#
# Conservé
#   - .env (licence, port, UID/GID) : la réinstallation ne redemande rien ;
#   - sources/ et tout le reste du dépôt ;
#   - DATA/ (ancienne installation déposée pour migration) : jamais touché.
#
# Supprimé
#   - conteneur bcdi et réseau bcdi_default ;
#   - image bcdi-serveur:latest (reconstruite par deployer.sh) ;
#   - data/bcdiserv en totalité ;
#   - backups/ uniquement avec --sauvegardes.
#
# Prérequis
#   Docker accessible pour la partie conteneur ; sans Docker, le script
#   supprime quand même les fichiers et le signale. En root, les dossiers
#   recréés appartiennent à PUID:PGID (lus dans .env, 1000 par défaut).
#
# Danger : les bases sont définitivement perdues. Faire une sauvegarde ou
# laisser backups/ en place avant de lancer la purge.
#
# Sortie : 0 si la purge aboutit, 1 si l'utilisateur annule, 2 pour une
# option inconnue.
set -euo pipefail
cd "$(dirname "$0")/.."

force=0
sauvegardes=0
for arg in "$@"; do
    case "$arg" in
        -f|--force) force=1 ;;
        --sauvegardes|--avec-sauvegardes) sauvegardes=1 ;;
        -h|--help)
            cat <<'AIDE'
Usage : ./scripts/purger.sh [--force] [--sauvegardes]

  --force         ne demande pas la confirmation (script d'industrialisation)
  --sauvegardes   supprime aussi backups/ (sauvegardes comprises)
  --help          affiche cette aide

Supprimés : conteneur bcdi, réseau Compose, image bcdi-serveur:latest et
            data/bcdiserv (bases, licence, programme, version).
Conservés : .env, sources/, DATA/ et le reste du dépôt ; backups/ sauf avec
            --sauvegardes.
AIDE
            exit 0
            ;;
        *)
            echo "ERREUR : option inconnue : $arg" >&2
            exit 2
            ;;
    esac
done

[ -f docker-compose.yml ] || {
    echo "ERREUR : docker-compose.yml absent : lancez ce script depuis la racine du dépôt" >&2
    exit 1
}

kit="$(pwd -P)"
data="$kit/data/bcdiserv"
case "$data" in
    "$kit"/*) ;;
    *)
        echo "ERREUR : chemin de données inattendu : $data" >&2
        exit 1
        ;;
esac

echo "Cette opération va supprimer :"
echo "  - le conteneur bcdi, son réseau Compose et l'image bcdi-serveur:latest"
echo "  - $data"
echo "    (bases, licence, programme, version installée)"
if [ "$sauvegardes" = 1 ]; then
    echo "  - $kit/backups, sauvegardes comprises"
else
    echo "  - les sauvegardes de $kit/backups sont CONSERVÉES"
fi
echo "  - .env, sources/ et le reste du dépôt sont conservés"
echo

if [ "$force" != 1 ]; then
    echo "Tapez SUPPRIMER pour confirmer :"
    read -r reponse
    if [ "$reponse" != "SUPPRIMER" ]; then
        echo "Annulé, rien n'a été supprimé."
        exit 1
    fi
fi

if command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then
    echo "Arrêt du serveur BCDI"
    docker compose stop bcdi >/dev/null 2>&1 || true
    echo "Suppression du conteneur et du réseau Compose"
    docker compose down --remove-orphans --volumes >/dev/null 2>&1 || true
    docker rm -f bcdi >/dev/null 2>&1 || true
    echo "Suppression de l'image bcdi-serveur:latest"
    docker image rm -f bcdi-serveur:latest >/dev/null 2>&1 || true
else
    echo "ATTENTION : Docker indisponible, conteneur et image non supprimés." >&2
fi

echo "Suppression de $data"
rm -rf -- "$data"

if [ "$sauvegardes" = 1 ]; then
    echo "Suppression de $kit/backups"
    rm -rf -- "$kit/backups"
fi

# Compose recrée les points de montage, mais avec les droits de root : on les
# prépare avec l'UID/GID de gestbcdi pour que l'installeur puisse y écrire.
puid="$(sed -n 's/^PUID=//p' .env 2>/dev/null | tail -n 1)"
pgid="$(sed -n 's/^PGID=//p' .env 2>/dev/null | tail -n 1)"
puid="${puid:-1000}"
pgid="${pgid:-1000}"
mkdir -p data/bcdiserv backups
if [ "$(id -u)" -eq 0 ]; then
    chown -R "$puid:$pgid" data backups 2>/dev/null || true
fi

echo
echo "Purge terminée. Réinstallation :"
echo "  ./deployer.sh"
echo "  ./scripts/maj.sh          # puis mise à jour 2.66"
