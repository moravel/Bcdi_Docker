#!/usr/bin/env bash
# deployer.sh — déploiement guidé complet du serveur BCDI.
#
# Rôle
#   Enchaîne la configuration, la construction de l'image, l'installation
#   Canopé (ou la migration d'une ancienne installation) et le démarrage.
#   C'est le point d'entrée normal après installer-hote.sh.
#
# Usage
#   ./deployer.sh
#   ./deployer.sh BCDI_REINSTALL=1
#   BCDI_OLD_HOST=ADRESSE_ANCIEN_SERVEUR BCDI_OLD_FETCH=1 ./deployer.sh
#
# Déroulé
#   1. vérifie x86_64, Docker, Compose v2 et la présence des archives dans
#      sources/ (installation 2.52 et mise à jour 2.66) ;
#   2. calcule PUID/PGID (1000 si lancé en root, sinon l'utilisateur courant) ;
#   3. crée .env (licence, port, nom d'hôte) ou réutilise l'existant, puis
#      valide sa syntaxe ;
#   4. signale un port déjà occupé et demande confirmation ;
#   5. propose de récupérer l'ancienne installation par SSH/SCP dans DATA/ ;
#   6. détecte une installation complète dans DATA/ et propose de la migrer
#      vers data/bcdiserv (l'installeur Canopé est alors sauté) ;
#   7. construit l'image, lance l'installation si nécessaire, démarre ;
#   8. vérifie le healthcheck et le griffage, affiche les étapes suivantes.
#
# Variables utiles (portées à l'exécution, elles ne sont pas écrites dans .env)
#   BCDI_REINSTALL=1    force l'installeur Canopé même si data/bcdiserv est
#                       déjà installé (efface bases et licence : dangereux) ;
#   BCDI_OLD_HOST       adresse/nom de l'ancien serveur BCDI ;
#   BCDI_OLD_USER       utilisateur SSH (défaut root) ;
#   BCDI_OLD_PATH       chemin de l'ancienne installation (défaut /usr/bcdiserv) ;
#   BCDI_OLD_PORT       port SSH (défaut 22) ;
#   BCDI_OLD_FETCH=1    copie SSH et migration sans aucune question.
#
# Sécurité
#   DATA/ n'est jamais exporté ni versionné : il peut contenir les bases et la
#   licence. Après migration, il est conservé comme source de contrôle ; le
#   supprimer une fois le serveur validé.
#
# Sortie : 0 si le déploiement va au bout, arrêt immédiat sur erreur.
set -euo pipefail
cd "$(dirname "$0")"

# Accepte « ./deployer.sh BCDI_REINSTALL=1 » : tout argument de la forme
# VARIABLE=valeur est exporté (Compose le transmet ensuite au conteneur).
for arg in "$@"; do
    case "$arg" in
        [A-Za-z_]*=*) export "$arg" ;;
    esac
done

die() { echo "ERREUR : $*" >&2; exit 1; }
info() { echo "[bcdi] $*"; }

[ "$(uname -m)" = "x86_64" ] || die "hôte x86_64 requis (l'image BCDI est 32 bits)"
command -v docker >/dev/null 2>&1 || die "Docker absent : lancez sudo ./installer-hote.sh"
docker compose version >/dev/null 2>&1 || die "Docker Compose v2 requis : lancez sudo ./installer-hote.sh"
docker info >/dev/null 2>&1 || die "démon Docker inaccessible (groupe docker ou sudo)"

[ -f sources/serveurBcdiabtlinux.inst-2.52.tar.gz ] \
    || die "archive d'installation absente : sources/serveurBcdiabtlinux.inst-2.52.tar.gz"
[ -f sources/maj_bcdi-abt_2.66_cl.tar.gz ] \
    || die "archive de mise à jour absente : sources/maj_bcdi-abt_2.66_cl.tar.gz"

# En root, « id -u » vaut 0 : un UID/GID privilégié est refusé par l'image
# (groupadd ne peut pas créer un groupe GID 0). On attribue alors les
# fichiers de data/ et backups/ à 1000, l'utilisateur gestbcdi du conteneur.
if [ "$(id -u)" -eq 0 ]; then
    PUID=1000
    PGID=1000
else
    PUID=$(id -u)
    PGID=$(id -g)
fi

if [ -f .env ]; then
    if grep -qE '^(PUID|PGID)=0$' .env; then
        sed -i -E 's/^(PUID|PGID)=0$/\1=1000/' .env
        info "PUID/PGID=0 remplacé par 1000 (UID/GID privilégié refusé)."
    fi
    info ".env existant conservé (supprimez-le pour reconfigurer)."
else
    cp .env.example .env
    chmod 600 .env

    etab=""
    while [ -z "$etab" ]; do
        read -r -p "Nom de l'établissement (licence) : " etab
    done
    code=""
    while [ -z "$code" ]; do
        read -r -s -p "Code d'installation (saisie masquée) : " code
        echo
    done
    read -r -p "Port publié sur l'hôte [9000] : " port
    port="${port:-9000}"
    read -r -p "Nom d'hôte du serveur [bcdi] : " hote
    hote="${hote:-bcdi}"

    cat > .env <<EOF
PUID=$PUID
PGID=$PGID
BCDI_HOST_PORT=$port
BCDI_HOSTNAME=$hote
TZ=Europe/Paris
BACKUP_KEEP_DAYS=30
BCDI_ETABLISSEMENT="$etab"
BCDI_GRIFFE="$code"
EOF
    chmod 600 .env
    info ".env créé (droits 600)."
fi

# Un .env produit par une version défectueuse peut contenir du code shell :
# on s'arrête avec un message clair plutôt que de laisser Compose échouer.
if grep -qvE '^[[:space:]]*(#|$|[A-Za-z_][A-Za-z0-9_]*=)' .env; then
    die ".env invalide (ligne non conforme). Supprimez-le puis relancez ./deployer.sh"
fi

port="$(sed -n 's/^BCDI_HOST_PORT=//p' .env | tail -n 1)"
port="${port:-9000}"
if ss -ltn 2>/dev/null | grep -q "[:.]${port} "; then
    echo "ATTENTION : le port $port semble déjà utilisé sur l'hôte."
    read -r -p "Continuer quand même ? (o/n) " reponse
    [ "$reponse" = "o" ] || exit 1
fi

migre_auto=0

# Récupération guidée de l'ancienne installation par SSH/SCP dans DATA/.
# Variables pour l'automatisation : BCDI_OLD_HOST, BCDI_OLD_USER,
# BCDI_OLD_PATH, BCDI_OLD_PORT, BCDI_OLD_FETCH=1 (sans confirmation).
if [ ! -d DATA ] || [ -z "$(ls -A DATA 2>/dev/null)" ]; then
    if command -v scp >/dev/null 2>&1 && command -v ssh >/dev/null 2>&1; then
        reponse_ssh=""
        if [ -n "${BCDI_OLD_HOST:-}" ]; then
            reponse_ssh="o"
            info "Ancien serveur indiqué par BCDI_OLD_HOST : $BCDI_OLD_HOST"
        else
            read -r -p "Récupérer les données d'un ancien serveur BCDI par SSH/SCP ? (o/n) " reponse_ssh || true
        fi
        if [ "$reponse_ssh" = "o" ]; then
            old_host="${BCDI_OLD_HOST:-}"
            if [ -z "$old_host" ]; then
                read -r -p "Adresse ou nom de l'ancien serveur : " old_host || true
            fi
            [ -n "$old_host" ] || die "adresse de l'ancien serveur requise (BCDI_OLD_HOST)"

            old_user="${BCDI_OLD_USER:-root}"
            old_path="${BCDI_OLD_PATH:-/usr/bcdiserv}"
            old_port="${BCDI_OLD_PORT:-22}"
            if [ "${BCDI_OLD_FETCH:-0}" = "1" ]; then
                go="o"
            else
                read -r -p "Utilisateur SSH [$old_user] : " saisie || true
                old_user="${saisie:-$old_user}"
                read -r -p "Chemin de l'installation BCDI [$old_path] : " saisie || true
                old_path="${saisie:-$old_path}"
                read -r -p "Port SSH [$old_port] : " saisie || true
                old_port="${saisie:-$old_port}"
                echo "Arrêtez le serveur BCDI de l'ancien serveur avant la copie (bases cohérentes)."
                read -r -p "Lancer la copie de $old_user@$old_host:$old_path ? (o/n) " go || true
            fi
            old_path="${old_path%/}"

            if [ "$go" = "o" ]; then
                mkdir -p DATA
                info "Copie SSH en cours (mot de passe éventuel ci-dessous)..."
                if ! scp -P "$old_port" -r "$old_user@$old_host:$old_path/." DATA/; then
                    echo "Échec : nouvelle tentative avec les algorithmes SSH hérités (ssh-rsa)..." >&2
                    scp -P "$old_port" -r \
                        -o HostKeyAlgorithms=+ssh-rsa \
                        -o PubkeyAcceptedAlgorithms=+ssh-rsa \
                        -o KexAlgorithms=+diffie-hellman-group14-sha1 \
                        "$old_user@$old_host:$old_path/." DATA/ \
                        || die "copie SSH impossible : vérifiez l'adresse, le chemin, le mot de passe et l'arrêt du serveur"
                fi
                info "Copie terminée dans DATA/."
                if [ "${BCDI_OLD_FETCH:-0}" = "1" ]; then
                    migre_auto=1
                fi
            fi
        fi
    fi
fi

# Ancienne installation copiée de l'ancien serveur dans DATA/ : on la reprend
# telle quelle (prog/, bases, licence) au lieu de réinstaller depuis zéro.
migre=0
if [ -d DATA ]; then
    src_root="$(find DATA -maxdepth 4 -type f -path '*/prog/ConsBcdi' -printf '%h\n' -quit 2>/dev/null | sed 's#/prog$##' || true)"
    if [ -n "$src_root" ] && [ -f "$src_root/prog/ConsBcdi" ]; then
        info "Ancienne installation détectée : $src_root"
        if [ -f data/bcdiserv/prog/ConsBcdi ]; then
            echo "ATTENTION : data/bcdiserv contient déjà une installation ; DATA/ est ignoré." >&2
            echo "Pour repartir de l'ancienne : ./scripts/purger.sh --force puis ./deployer.sh" >&2
        else
            version_old="$(sed -n '5p' "$src_root/prog/VersionBcdi.Txt" 2>/dev/null || true)"
            nb_bases="$(find "$src_root" -maxdepth 2 -type f -iname '*.dat' 2>/dev/null | wc -l)"
            info "Version de l'ancienne installation : ${version_old:-inconnue}"
            info "Fichiers de bases trouvés : $nb_bases"
            if [ "$migre_auto" = 1 ]; then
                reponse_migration="o"
                info "Migration automatique (BCDI_OLD_FETCH=1)."
            else
                read -r -p "Migrer cette installation vers data/bcdiserv ? (o/n) " reponse_migration || true
            fi
            if [ "$reponse_migration" = "o" ]; then
                mkdir -p data/bcdiserv
                cp -a "$src_root/." data/bcdiserv/
                if [ "$(id -u)" -eq 0 ]; then
                    chown -R "$PUID:$PGID" data/bcdiserv
                fi
                migre=1
                info "Ancienne installation migrée (copie conservée dans DATA/)."

                # Les chemins absolus enregistrés par l'ancien serveur doivent
                # correspondre au point de montage du conteneur.
                home_interne="$(sed -n 's/^BCDI_HOME=//p' .env | tail -n 1)"
                home_interne="${home_interne:-/usr/bcdiserv}"
                chemin_old="$(grep -aoE '/[A-Za-z0-9._/-]*bcdiserv' data/bcdiserv/prog/AdmPar.Dat 2>/dev/null | sort -u | head -n 1 || true)"
                case "$chemin_old" in
                    ""|"$home_interne"*) ;;
                    *)
                        echo "ATTENTION : l'ancienne installation référence $chemin_old" >&2
                        echo "Renseignez BCDI_HOME=$chemin_old dans .env si les clients utilisaient ce chemin." >&2
                        ;;
                esac
                info "Après démarrage : ./verifier.sh, puis ./scripts/maj.sh si la version est antérieure à 2.66."
            fi
        fi
    else
        base_old="$(find DATA -maxdepth 4 -type f -iname 'notices.dat' -printf '%h\n' -quit 2>/dev/null || true)"
        if [ -z "$base_old" ]; then
            base_old="$(find DATA -maxdepth 4 -type f -iname '*.dat' -printf '%h\n' -quit 2>/dev/null || true)"
        fi
        if [ -n "$base_old" ]; then
            info "Base seule détectée dans $base_old (pas de programme BCDI)."
            info "Après installation : ./scripts/restaurer-base.sh $base_old"
        else
            info "DATA/ présent mais aucune installation ni base BCDI reconnue ; ignoré."
        fi
    fi
fi

info "Construction de l'image (quelques minutes la première fois)..."
docker compose build

if [ "$migre" = 1 ]; then
    info "Installation Canopé ignorée : l'installation migrée depuis DATA/ est utilisée telle quelle."
elif [ -x data/bcdiserv/prog/ConsBcdi ] && [ "${BCDI_REINSTALL:-0}" != "1" ]; then
    info "Installation existante détectée dans data/bcdiserv : étape d'installation ignorée."
    info "Changement de licence : docker compose stop bcdi && docker compose run --rm bcdi griffer"
else
    info "Installation de BCDI depuis sources/ (installeur Canopé)..."
    docker compose run --rm bcdi install
fi

info "Démarrage du serveur..."
docker compose up -d
sleep 8

if docker exec bcdi /usr/local/bin/healthcheck.sh >/dev/null 2>&1; then
    info "Serveur BCDI opérationnel."
else
    echo "Le healthcheck échoue : consultez « docker compose logs bcdi »." >&2
fi

if head -n 1 data/bcdiserv/prog/VersionBcdi.Txt 2>/dev/null | grep -q '^XXXXX'; then
    echo "ATTENTION : le griffage n'a pas abouti. Refaites-le :" >&2
    echo "  docker compose stop bcdi && docker compose run --rm bcdi griffer" >&2
fi

docker compose ps

cat <<EOF

Étapes suivantes :
  - mise à jour 2.66 : ./scripts/maj.sh   (réponses : o, 1, Entrée, Entrée, Entrée, n)
  - sauvegarde quotidienne : voir docs/EXPLOITATION.md (section Sauvegardes)
  - changement de licence : docker compose run --rm bcdi griffer (docs/EXPLOITATION.md)
  - clients Windows : IP du serveur, port $port, chemin /usr/bcdiserv/Data
EOF
