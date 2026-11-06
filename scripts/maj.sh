#!/usr/bin/env bash
# maj.sh — applique la mise à jour Canopé (2.66) au serveur installé.
#
# Rôle
#   Arrête le serveur, lance l'installeur de mise à jour contenu dans sources/
#   (maj_bcdi-abt_2.66_cl.tar.gz), puis redémarre le serveur.
#
# Usage
#   ./scripts/maj.sh
#
# Prérequis
#   - serveur installé, griffé et arrêté (le script l'arrête lui-même) ;
#   - accès Internet depuis le conteneur (validation de la mise à jour) ;
#   - archive de mise à jour présente dans sources/ ;
#   - sauvegarde récente recommandée : ./scripts/sauvegarde.sh.
#
# Déroulé
#   1. rappel des précautions et confirmation (o/n) ;
#   2. arrêt du conteneur ;
#   3. entrypoint.sh maj -> installeur Canopé interactif ;
#   4. redémarrage garanti par un trap, même en cas d'échec.
#
# Réponses attendues à l'installeur : o (confirmation), 1 (mise à jour),
# Entrée (emplacement), Entrée (groupe), Entrée (utilisateur), n (retour menu).
#
# Effets : prog/ passe en 2.66, les bases sont converties par l'installeur.
# En cas d'échec, restaurer backups/<archive> avec ./scripts/restaurer.sh.
set -euo pipefail
cd "$(dirname "$0")/.."

echo "Avant la mise à jour :"
echo "  1. sauvegarder la base (./scripts/sauvegarde.sh)"
echo "  2. vérifier l'accès Internet du conteneur (serveur griffé)"
echo
read -r -p "Continuer la mise à jour ? (o/n) " reponse
[ "$reponse" = "o" ] || exit 1

docker compose stop bcdi >/dev/null || true
trap 'echo "Redémarrage du serveur BCDI"; docker compose up -d bcdi >/dev/null' EXIT

docker compose run --rm --no-deps bcdi maj

echo "Mise à jour terminée : suivez les consignes affichées par l'installeur Canopé."
