#!/usr/bin/env bash
# installer-hote.sh — prépare un serveur Debian vierge pour le serveur BCDI.
#
# Rôle
#   Installe Docker Engine, le plugin Compose v2 et les outils nécessaires,
#   puis autorise l'utilisateur appelant à piloter Docker sans sudo.
#
# Usage
#   sudo ./installer-hote.sh
#
# Prérequis
#   - Debian 11, 12 ou 13 en x86_64 (l'image BCDI est 32 bits : pas d'ARM) ;
#   - accès Internet vers download.docker.com ;
#   - exécution en root (le script refuse sinon).
#
# Effets sur l'hôte
#   - clé /etc/apt/keyrings/docker.asc et dépôt
#     /etc/apt/sources.list.d/docker.list ;
#   - paquets docker-ce, docker-ce-cli, containerd.io, buildx et compose ;
#   - systemctl enable --now docker ;
#   - ajout de $SUDO_USER au groupe docker (reconnexion nécessaire).
#
# Le script est idempotent : si Docker et Compose v2 répondent déjà, il ne
# réinstalle rien et vérifie seulement l'appartenance au groupe docker.
#
# Sortie : 0 si l'hôte est prêt, 1 avec un message ERREUR sinon.
set -euo pipefail

die() { echo "ERREUR : $*" >&2; exit 1; }
info() { echo "[hôte] $*"; }

[ "$(id -u)" -eq 0 ] || die "à lancer en root : sudo ./installer-hote.sh"
[ "$(uname -m)" = "x86_64" ] || die "hôte x86_64 requis (l'image BCDI est 32 bits)"

[ -r /etc/os-release ] || die "/etc/os-release absent : Debian requis"
# shellcheck disable=SC1091
. /etc/os-release
[ "${ID:-}" = "debian" ] || info "distribution ${ID:-inconnue} : procédure prévue pour Debian"

if command -v docker >/dev/null 2>&1 && docker compose version >/dev/null 2>&1; then
    info "Docker et Compose v2 sont déjà installés."
else
    info "Installation de Docker Engine et du plugin Compose..."
    apt-get update
    apt-get install -y ca-certificates curl gnupg
    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc
    chmod a+r /etc/apt/keyrings/docker.asc
    arch="$(dpkg --print-architecture)"
    codename="${VERSION_CODENAME:?codename Debian introuvable}"
    printf 'deb [arch=%s signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/debian %s stable\n' \
        "$arch" "$codename" > /etc/apt/sources.list.d/docker.list
    apt-get update
    apt-get install -y docker-ce docker-ce-cli containerd.io \
        docker-buildx-plugin docker-compose-plugin
    systemctl enable --now docker
fi

if [ -n "${SUDO_USER:-}" ] && [ "$SUDO_USER" != "root" ]; then
    if id -nG "$SUDO_USER" | grep -qw docker; then
        info "$SUDO_USER est déjà dans le groupe docker."
    else
        usermod -aG docker "$SUDO_USER"
        info "$SUDO_USER ajouté au groupe docker : reconnectez-vous pour en tenir compte."
    fi
fi

docker compose version
info "Hôte prêt. Étape suivante : ./deployer.sh"
