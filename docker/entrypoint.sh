#!/usr/bin/env bash
# entrypoint.sh — point d'entrée unique du conteneur serveur BCDI.
#
# Rôle
#   Exécute les commandes d'administration dans l'environnement Canopé, en
#   tant que gestbcdi lorsque c'est possible, et démarre ConsBcdi.
#
# Commandes
#   serveur (défaut)  démarre ConsBcdi avec un pseudo-terminal et un tube de
#                     contrôle pour que docker stop (SIGINT) l'arrête proprement ;
#   install           installe BCDI depuis /sources (interactif, ou non
#                     interactif si BCDI_ETABLISSEMENT et BCDI_GRIFFE sont
#                     renseignés) ;
#   maj               lance l'installeur de mise à jour depuis /sources ;
#   griffer           (re)griffe le serveur (établissement + code, Internet
#                     requis) après avoir sauvegardé la licence et aligné
#                     VersionBcdi.mdl sur la version installée ;
#   sauvegarde        archive l'installation dans /home/gestbcdi ;
#   restaurer <arch>  restaure une archive complète (bcdi-restore) ;
#   statut            processus ConsBcdi, version, clients connectés ;
#   bash|sh           shell de diagnostic dans le conteneur.
#
# Variables (défauts entre parenthèses)
#   BCDI_HOME (/usr/bcdiserv), BCDI_USER (gestbcdi), BCDIPORT (9000),
#   BACKUP_DIR (/home/gestbcdi), BACKUP_KEEP_DAYS (30), SOURCES_DIR (/sources),
#   BCDI_ETABLISSEMENT / BCDI_GRIFFE (griffage non interactif),
#   BCDI_INSTALL_ARCHIVE / BCDI_UPDATE_ARCHIVE (forcer un paquet précis),
#   BCDI_REINSTALL=1 (autoriser install à écraser une installation existante).
#
# Principe
#   Les commandes d'administration tournent en root dans le conteneur (pour
#   écrire dans BCDI_HOME) puis rendent les fichiers à gestbcdi. Le serveur,
#   lui, tourne en gestbcdi via chroot --userspec, sans processus
#   intermédiaire, afin de recevoir SIGINT lors d'un docker stop.
#
# Sortie : code de la commande exécutée ; les erreurs d'usage ou de prérequis
# sortent en 1 avec un message « [bcdi] ERREUR ».
set -euo pipefail

BCD_USER="${BCDI_USER:-gestbcdi}"
BCD_HOME="${BCDI_HOME:-/usr/bcdiserv}"
BCD_PORT="${BCDIPORT:-9000}"
BACKUP_DIR="${BACKUP_DIR:-/home/gestbcdi}"
SOURCES_DIR="${SOURCES_DIR:-/sources}"
KEEP_DAYS="${BACKUP_KEEP_DAYS:-30}"

log() { printf '[bcdi] %s\n' "$*"; }
die() { printf '[bcdi] ERREUR : %s\n' "$*" >&2; exit 1; }

uid_of() { id -u "$1"; }
gid_of() { id -g "$1"; }

# Exécute une commande en tant que gestbcdi. chroot --userspec permet un exec
# direct (pas de processus intermédiaire), indispensable pour que ConsBcdi
# reçoive SIGINT proprement lors d'un docker stop.
run_as_bcdi() {
    if [ "$(id -u)" -ne 0 ]; then
        "$@"
        return
    fi
    if chroot --userspec="$(uid_of "$BCD_USER"):$(gid_of "$BCD_USER")" / /bin/true 2>/dev/null; then
        chroot --userspec="$(uid_of "$BCD_USER"):$(gid_of "$BCD_USER")" / "$@"
    else
        runuser -u "$BCD_USER" -- "$@"
    fi
}

installed() { [ -x "$BCD_HOME/prog/ConsBcdi" ]; }

require_root() {
    [ "$(id -u)" -eq 0 ] || die "cette commande doit être lancée en root (docker compose run --rm bcdi ...)"
}

fix_ownership() {
    [ "$(id -u)" -eq 0 ] || return 0
    mkdir -p "$BCD_HOME" "$BACKUP_DIR"
    local wanted
    wanted="$(uid_of "$BCD_USER"):$(gid_of "$BCD_USER")"
    if [ "$(stat -c '%u:%g' "$BCD_HOME")" != "$wanted" ]; then
        log "Attribution de $BCD_HOME à $BCD_USER"
        chown -R "$wanted" "$BCD_HOME"
    fi
    chown "$wanted" "$BACKUP_DIR" 2>/dev/null || true
}

# Après une installation Canopé, certains fichiers restent à root : le chown
# de l'installeur (gestbcdi.gestbcdi) échoue sur les distributions récentes.
force_ownership() {
    fix_ownership
    [ "$(id -u)" -eq 0 ] || return 0
    chown -R "$(uid_of "$BCD_USER"):$(gid_of "$BCD_USER")" "$BCD_HOME"
}

# --- Résolution des paquets d'installation / de mise à jour ---------------

latest_match() { # $1 = nom de fichier recherché, ex. installbcdi.sh
    find "$SOURCES_DIR" -maxdepth 3 -type f -name "$1" -print 2>/dev/null | sort | head -n 1
}

resolve_install_source() {
    if [ -n "${BCDI_INSTALL_ARCHIVE:-}" ]; then
        [ -e "$BCDI_INSTALL_ARCHIVE" ] || die "BCDI_INSTALL_ARCHIVE introuvable : $BCDI_INSTALL_ARCHIVE"
        printf '%s\n' "$BCDI_INSTALL_ARCHIVE"
        return
    fi
    local script dir archive
    script="$(latest_match installbcdi.sh)"
    if [ -n "$script" ]; then
        printf '%s\n' "$(dirname "$script")"
        return
    fi
    archive="$(find "$SOURCES_DIR" -maxdepth 3 -type f \
        \( -name 'serveurBcdiabtlinux*.tar.gz' -o -name 'serveurBcdiabtlinux*.tgz' \) \
        -print 2>/dev/null | sort | tail -n 1)"
    [ -n "$archive" ] || die "aucun paquet d'installation trouvé dans $SOURCES_DIR (attendu : serveurBcdiabtlinux.inst-*.tar.gz)"
    printf '%s\n' "$archive"
}

resolve_update_source() {
    if [ -n "${BCDI_UPDATE_ARCHIVE:-}" ]; then
        [ -e "$BCDI_UPDATE_ARCHIVE" ] || die "BCDI_UPDATE_ARCHIVE introuvable : $BCDI_UPDATE_ARCHIVE"
        printf '%s\n' "$BCDI_UPDATE_ARCHIVE"
        return
    fi
    local script archive
    script="$(latest_match install_majbcdi-abt.sh)"
    if [ -n "$script" ]; then
        printf '%s\n' "$(dirname "$script")"
        return
    fi
    archive="$(find "$SOURCES_DIR" -maxdepth 3 -type f \
        \( -name 'maj_bcdi-abt_*.tar.gz' -o -name 'maj_bcdi-abt_*.tgz' \) \
        -print 2>/dev/null | sort | tail -n 1)"
    [ -n "$archive" ] || die "aucune mise à jour trouvée dans $SOURCES_DIR (attendu : maj_bcdi-abt_*.tar.gz)"
    printf '%s\n' "$archive"
}

# Prépare un répertoire de travail contenant le script Canopé.
prepare_package() { # $1 = source (dossier ou archive), $2 = nom du script
    local source="$1" script_name="$2" workdir script
    if [ -d "$source" ]; then
        workdir="$source"
    else
        workdir="$(mktemp -d)"
        tar -xf "$source" -C "$workdir" || die "archive illisible : $source"
    fi
    script="$(find "$workdir" -maxdepth 3 -type f -name "$script_name" -print -quit)"
    [ -n "$script" ] || die "$script_name introuvable dans $source"
    chmod +x "$script" 2>/dev/null || true
    printf '%s\n' "$(dirname "$script")"
}

# --- Installation ---------------------------------------------------------

griffe_ok() {
    [ -s "$BCD_HOME/prog/VersionBcdi.Txt" ] || return 1
    ! head -n 1 "$BCD_HOME/prog/VersionBcdi.Txt" | grep -q '^XXXXX'
}

install_unattended() { # $1 = répertoire de l'installeur
    local workdir="$1" emplacement nomrep
    emplacement="$(dirname "$BCD_HOME")"
    nomrep="$(basename "$BCD_HOME")"
    log "Installation non interactive dans $BCD_HOME"
    {
        printf '2\n'                              # menu : installation nouveau produit
        printf '\n'                               # emplacement de l'archive (dossier courant)
        printf '%s\n' "$emplacement"               # emplacement d'installation (/usr)
        printf '%s\n' "$nomrep"                    # nom du répertoire (bcdiserv)
        printf '\n'                                # port (9000)
        printf '\n'                                # base à sauvegarder (Data)
        printf '\n'                                # emplacement des sauvegardes (/home/gestbcdi)
        printf '\n'                                # groupe (gestbcdi)
        printf '\n'                                # utilisateur (gestbcdi)
        printf '%s\n' "${BCDI_MAIL_ADMIN:-}"       # mail de l'administrateur
        printf 'o\n'                               # le répertoire existe : continuer
        printf '%s\n' "$BCDI_ETABLISSEMENT"        # nom de l'établissement (griffage)
        printf '%s\n' "$BCDI_GRIFFE"               # code d'installation (griffage)
        printf 'n\n'                               # échec de griffage : ne pas recommencer
        printf 'n\n'                               # pas de sauvegarde cron (gérée ici)
        printf 'n\n'                               # pas de service init.d (Docker)
        printf 'n\n'                               # retour au menu : non
    } | ( cd "$workdir" && ./installbcdi.sh )
}

cmd_install() {
    require_root
    if installed && [ "${BCDI_REINSTALL:-0}" != "1" ]; then
        die "une installation existe déjà dans $BCD_HOME (utilisez 'maj', ou BCDI_REINSTALL=1 pour réinstaller)"
    fi

    local source workdir
    source="$(resolve_install_source)"
    log "Paquet d'installation : $source"
    workdir="$(prepare_package "$source" installbcdi.sh)"

    # L'installeur Canopé supprime le répertoire cible s'il existe : il doit
    # donc exister (pour la question « continuer ? ») mais être vide.
    if [ -d "$BCD_HOME" ] && [ -n "$(ls -A "$BCD_HOME" 2>/dev/null)" ] && [ "${BCDI_REINSTALL:-0}" != "1" ]; then
        die "$BCD_HOME n'est pas vide : réinstallation refusée (BCDI_REINSTALL=1 pour forcer, au risque d'effacer les données)"
    fi
    mkdir -p "$BCD_HOME"

    if [ -n "${BCDI_ETABLISSEMENT:-}" ] && [ -n "${BCDI_GRIFFE:-}" ]; then
        install_unattended "$workdir"
    else
        log "Mode interactif : répondez aux questions de l'installeur Canopé."
        log "Réponses conseillées : destination $BCD_HOME, port 9000, service : n, sauvegarde quotidienne : n."
        ( cd "$workdir" && ./installbcdi.sh )
    fi

    installed || die "installation incomplète : $BCD_HOME/prog/ConsBcdi est absent"
    force_ownership

    if griffe_ok; then
        log "Griffage enregistré ($(head -n 3 "$BCD_HOME/prog/VersionBcdi.Txt" | tr '\n' ' '))"
    else
        log "ATTENTION : le griffage n'a pas abouti (code ou nom d'établissement invalide, ou pas d'accès Internet)."
        log "Pour le refaire : docker compose run --rm bcdi griffer"
    fi
    log "Installation terminée dans $BCD_HOME."
    log "Pensez à appliquer la mise à jour : docker compose run --rm bcdi maj"
}

# --- Mise à jour ----------------------------------------------------------

cmd_maj() {
    require_root
    installed || die "aucune installation dans $BCD_HOME : lancez d'abord la commande 'install'"
    griffe_ok || die "serveur non griffé : lancez 'docker compose run --rm bcdi griffer' avant la mise à jour"
    if pgrep -x ConsBcdi >/dev/null 2>&1; then
        die "le serveur BCDI fonctionne : arrêtez-le avant la mise à jour (docker compose stop bcdi)"
    fi

    local source workdir
    source="$(resolve_update_source)"
    log "Mise à jour : $source"
    workdir="$(prepare_package "$source" install_majbcdi-abt.sh)"

    log "Mode interactif : option 1, puis Entrée pour conserver $BCD_HOME/prog."
    ( cd "$workdir" && ./install_majbcdi-abt.sh )

    installed || die "mise à jour incomplète : $BCD_HOME/prog/ConsBcdi est absent"
    force_ownership
    log "Mise à jour terminée."
}

# --- Griffage -------------------------------------------------------------

cmd_griffer() {
    require_root
    installed || die "aucune installation dans $BCD_HOME"
    [ -x "$BCD_HOME/prog/StartGriffage" ] || die "$BCD_HOME/prog/StartGriffage introuvable"
    if pgrep -x ConsBcdi >/dev/null 2>&1; then
        die "arrêtez le serveur avant de (re)griffer (docker compose stop bcdi)"
    fi
    # StartGriffage réécrit VersionBcdi.Txt à partir de VersionBcdi.mdl AVANT
    # de contacter Canopé : un code refusé laisserait le serveur sans licence.
    # Le modèle peut aussi être plus ancien que la version installée (2.65
    # dans un kit 2.52) : on l'aligne pour ne pas faire régresser la version.
    local version_file="$BCD_HOME/prog/VersionBcdi.Txt" version
    if [ -s "$version_file" ]; then
        local backup
        backup="$BACKUP_DIR/VersionBcdi.Txt.avant-griffage-$(date +%Y%m%d-%H%M%S)"
        mkdir -p "$BACKUP_DIR"
        cp -p "$version_file" "$backup"
        log "Licence actuelle sauvegardée : $backup"
        version="$(sed -n '5p' "$version_file")"
        if [ -n "$version" ] && [ -f "$BCD_HOME/prog/VersionBcdi.mdl" ]; then
            sed -i "5s|.*|$version|" "$BCD_HOME/prog/VersionBcdi.mdl"
            log "Modèle de griffage aligné sur la version $version"
        fi
    fi

    log "Griffage : nom d'établissement et code d'installation (connexion Internet requise)."
    ( cd "$BCD_HOME/prog" && ./StartGriffage )
    force_ownership
}

# --- Sauvegarde / restauration -------------------------------------------

cmd_sauvegarde() {
    installed || die "aucune installation dans $BCD_HOME"
    fix_ownership
    if pgrep -x ConsBcdi >/dev/null 2>&1; then
        log "ATTENTION : le serveur fonctionne, l'archive peut être incohérente."
        log "Pour une sauvegarde propre : ./scripts/sauvegarde.sh (arrêt, archive, redémarrage)."
    fi
    run_as_bcdi env BACKUP_DIR="$BACKUP_DIR" BCDI_HOME="$BCD_HOME" \
        BACKUP_KEEP_DAYS="$KEEP_DAYS" /usr/local/sbin/bcdi-backup
}

# --- Statut ---------------------------------------------------------------

cmd_statut() {
    installed || die "aucune installation dans $BCD_HOME"
    # consolebcdi s'appuie sur « netstat -p », qui ne voit pas le processus
    # (uid différent, CAP_SYS_PTRACE absent dans Docker) : on interroge
    # directement le processus et les connexions établies.
    if pgrep -x ConsBcdi >/dev/null 2>&1; then
        local version clients
        version="$(tail -n 1 "$BCD_HOME/prog/VersionBcdi.Txt" 2>/dev/null || true)"
        clients="$(ss -tn 2>/dev/null | awk -v p=":$BCD_PORT" 'NR > 1 && $1 == "ESTAB" && $3 ~ p { n++ } END { print n + 0 }')"
        log "Le serveur Bcdi fonctionne (PID $(pgrep -x ConsBcdi | tr '\n' ' '), version ${version:-inconnue}, port $BCD_PORT)."
        log "Clients connectés : $clients"
    else
        log "Le serveur Bcdi est arrêté !"
    fi
}

# --- Serveur --------------------------------------------------------------

cmd_serveur() {
    installed || die "aucune installation dans $BCD_HOME. Lancez : docker compose run --rm bcdi install"
    fix_ownership
    cd "$BCD_HOME/prog"

    # BCDI utilise ses propres bibliothèques Borland situées dans prog/.
    export LD_LIBRARY_PATH="$BCD_HOME/prog:${LD_LIBRARY_PATH:-}"
    export HOME=/home/gestbcdi
    umask 000

    log "Démarrage du serveur BCDI sur le port $BCD_PORT (utilisateur $BCD_USER)"
    # BCDI n'obéit à SIGINT que si son entrée standard n'est pas /dev/null :
    # on lui fournit un tube maintenu ouvert (le fd 9 sert aussi de secours "S").
    local ctrl_fifo="/tmp/bcdi-ctrl.$$"
    mkfifo "$ctrl_fifo"
    exec 9<>"$ctrl_fifo"
    rm -f "$ctrl_fifo"

    # BCDI 2.66 n'installe son gestionnaire de Ctrl+C que si l'entrée standard
    # est un terminal : on lui fournit un pseudo-terminal (script), le tube
    # restant ouvert pour qu'il ne reçoive pas EOF.
    run_as_bcdi /usr/bin/script -qfc "cd '$PWD' && exec '$BCD_HOME/prog/ConsBcdi'" /dev/null <&9 &
    local pid=$!
    local server_pid=""
    local i
    for i in $(seq 1 50); do
        server_pid="$(pgrep -x ConsBcdi | head -n 1 || true)"
        [ -n "$server_pid" ] && break
        kill -0 "$pid" 2>/dev/null || break
        sleep 0.2
    done

    # Arrêt propre : Ctrl+C (SIGINT) sur le processus BCDI. \003 est le
    # caractère Ctrl+C envoyé via le pseudo-terminal, en secours.
    trap 'log "Arrêt demandé"; [ -n "$server_pid" ] && kill -INT "$server_pid" 2>/dev/null || true; printf "\003" >&9 2>/dev/null || true' INT TERM
    local rc=0
    while :; do
        if wait "$pid"; then
            rc=0
        else
            rc=$?
        fi
        kill -0 "$pid" 2>/dev/null || break
    done
    log "ConsBcdi arrêté (code $rc)."
    exit "$rc"
}

# --- Dispatch -------------------------------------------------------------

command="${1:-serveur}"
if [ "$#" -gt 0 ]; then shift; fi

case "$command" in
    serveur|start)      cmd_serveur ;;
    install)            cmd_install ;;
    maj|update)         cmd_maj ;;
    griffer|griffage)   cmd_griffer ;;
    sauvegarde|backup)  cmd_sauvegarde ;;
    restaurer|restore)  exec /usr/local/sbin/bcdi-restore "$@" ;;
    statut|status)      cmd_statut ;;
    bash|sh|shell)      exec "$command" "$@" ;;
    *)                  exec "$command" "$@" ;;
esac
