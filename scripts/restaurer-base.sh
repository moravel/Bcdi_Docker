#!/usr/bin/env bash
# restaurer-base.sh — importe une base BCDI sans toucher au programme.
#
# Rôle
#   Remplace uniquement data/bcdiserv/Data par le contenu d'une base exportée
#   d'un autre serveur. prog/, la licence et la version installée sont
#   conservés : c'est la commande à utiliser après une installation neuve.
#
# Usage
#   ./scripts/restaurer-base.sh backups/data.zip
#   ./scripts/restaurer-base.sh backups/Data.tar.gz
#   ./scripts/restaurer-base.sh /chemin/vers/dossier/contenant/NOTICES.DAT
#
# Formats acceptés
#   - .zip  : export « Sauvegarder une base » du client Windows (Outils >
#             Gestion des bases), avec ou sans dossier Data/ ;
#   - .tar.gz/.tgz/.tar : sauvegarde d'un ancien serveur Linux ;
#   - dossier : répertoire contenant directement la base.
#
# Fonctionnement
#   1. extrait l'archive dans un répertoire temporaire ;
#   2. repère la base par ses fichiers (NOTICES.DAT, sinon *.DAT, sinon un
#      dossier nommé data) sans dépendre du nom du répertoire ;
#   3. refuse de prendre l'installation courante comme source ;
#   4. arrête le serveur ;
#   5. copie la base actuelle dans backups/Data-avant-import-AAAAMMJJ-HHMMSS ;
#   6. remplace data/bcdiserv/Data, attribue les droits à gestbcdi ;
#   7. redémarre le serveur (trap), même en cas d'échec.
#
# Prérequis : unzip (ou python3 pour les ZIP), installation existante.
#
# Remarques
#   - le répertoire cible s'appelle Data (majuscule), pas data : ne pas le
#     renommer, les clients BCDI enregistrent ce chemin ;
#   - pour une base secondaire, adapter le répertoire cible et la déclarer
#     dans l'administration des bases du client ;
#   - les deux serveurs doivent être en 2.66, ou importer avant la mise à jour
#     (l'installeur 2.66 convertit les bases).
#
# Sortie : 0 si l'import aboutit, 2 pour un usage incorrect, 1 si aucune base
# n'est trouvée ou si la source est l'installation courante.
set -euo pipefail
cd "$(dirname "$0")/.."

src="${1:-}"
if [ -z "$src" ] || [ ! -e "$src" ]; then
    echo "usage : $0 <archive .zip|.tar.gz|.tgz|.tar|dossier contenant la base>" >&2
    exit 2
fi

tmp="$(mktemp -d)"
stopped=0
restart() {
    rm -rf "$tmp"
    if [ "$stopped" = 1 ]; then
        echo "Redémarrage du serveur BCDI"
        docker compose up -d bcdi >/dev/null || true
    fi
}
trap restart EXIT

if [ -d "$src" ]; then
    work="$src"
elif [ -f "$src" ]; then
    echo "Extraction de $src"
    case "$(printf '%s' "$src" | tr '[:upper:]' '[:lower:]')" in
        *.zip)
            if command -v unzip >/dev/null 2>&1; then
                unzip -q "$src" -d "$tmp"
            elif command -v python3 >/dev/null 2>&1; then
                python3 -m zipfile -e "$src" "$tmp"
            else
                echo "ERREUR : unzip (ou python3) est requis pour lire un ZIP" >&2
                exit 1
            fi
            ;;
        *.tar.gz|*.tgz|*.tar)
            tar -xf "$src" -C "$tmp"
            ;;
        *)
            echo "ERREUR : format non reconnu (attendu .zip, .tar.gz, .tgz ou .tar)" >&2
            exit 1
            ;;
    esac
    work="$tmp"
else
    echo "ERREUR : $src n'est ni un fichier ni un dossier" >&2
    exit 2
fi

# Répertoire de la base : celui qui contient les tables BCDI. On ne se fie pas
# au nom du dossier (data/Data selon la version, ou contenu à la racine du ZIP).
data_src="$(find "$work" -maxdepth 5 -type f -iname 'notices.dat' -printf '%h\n' -quit 2>/dev/null)"
if [ -z "$data_src" ]; then
    data_src="$(find "$work" -maxdepth 5 -type f -iname '*.dat' -printf '%h\n' -quit 2>/dev/null)"
fi
if [ -z "$data_src" ]; then
    data_src="$(find "$work" -maxdepth 5 -type d -iname 'data' -print -quit 2>/dev/null)"
fi
[ -n "$data_src" ] || { echo "ERREUR : aucune base BCDI (*.DAT) dans $src" >&2; exit 1; }

# Refuse de prendre l'installation courante comme source (elle serait effacée).
case "$(cd "$data_src" && pwd)/" in
    "$(pwd)/data/bcdiserv/"*)
        echo "ERREUR : la source est l'installation courante, rien à importer" >&2
        exit 1
        ;;
esac

echo "Base trouvée : $data_src"

echo "Arrêt du serveur BCDI"
docker compose stop bcdi >/dev/null || true
stopped=1

if [ -d data/bcdiserv/Data ]; then
    keep="backups/Data-avant-import-$(date '+%Y%m%d-%H%M%S')"
    mkdir -p backups
    echo "Base actuelle conservée dans $keep"
    cp -a data/bcdiserv/Data "$keep"
fi

echo "Import vers data/bcdiserv/Data"
rm -rf data/bcdiserv/Data
mkdir -p data/bcdiserv/Data
cp -a "$data_src/." data/bcdiserv/Data/

echo "Attribution des droits à gestbcdi"
docker compose run --rm --no-deps bcdi bash -c 'chown -R gestbcdi:gestbcdi /usr/bcdiserv/Data'

echo "Import terminé."
