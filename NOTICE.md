# Notice légale et limites

## Logiciel BCDI

BCDI (Banque de données documentaire informatisée) est un logiciel
propriétaire édité par le **Réseau Canopé**. Son utilisation est réservée aux
établissements disposant d'un abonnement et d'un code d'installation valide.

Ce dépôt **ne contient pas** :

- de binaire, bibliothèque ou archive d'installation Canopé ;
- de code de licence ou de code d'installation ;
- de base de données BCDI, de sauvegarde ou de donnée d'emprunteur ;
- de documentation propriétaire Canopé.

L'image Docker ne fournit que l'environnement d'exécution (Debian 9 i386 et
outils système). Les paquets BCDI doivent être obtenus séparément depuis
l'espace client Canopé, par chaque établissement abonné. Ils ne doivent pas
être publiés, versionnés dans ce dépôt ni transmis à un établissement non
abonné.

## Code du dépôt

Sauf mention contraire, les scripts, le `Dockerfile`, le fichier Compose et la
documentation originale de ce dépôt sont distribués sous **GNU General Public
License version 3.0** (`GPL-3.0-only`). Le texte complet se trouve dans
[`LICENSE`](LICENSE).

Cette licence est **copyleft** : toute œuvre dérivée distribuée doit être
placée sous la même licence GPLv3. Le code est fourni **en l'état**, sans
garantie expresse ou implicite, et ne constitue pas un produit officiel du
Réseau Canopé.

La GPLv3 ne couvre pas le logiciel BCDI, ses binaires ou archives, ses marques,
les bases de données, les sauvegardes ni les données d'emprunteurs. Ces
éléments restent soumis à leurs propres conditions et ne peuvent pas être
redistribués avec ce dépôt.

## Données personnelles

Les bases BCDI et les sauvegardes peuvent contenir des données d'emprunteurs
(noms, classes, prêts, historique). Elles relèvent du RGPD et des règles de
l'établissement. Ce dépôt n'en contient aucune ; les installations réelles
doivent les protéger, limiter les accès et externaliser les sauvegardes.

## Marques

BCDI, Réseau Canopé, Solutions documentaires, SOLDOC et les logos associés
appartiennent à leurs titulaires respectifs. Leur mention est descriptive et
n'implique aucune affiliation ni approbation.

## Sécurité

Debian 9 (stretch) n'est plus maintenue. L'image est conservée pour des
raisons de compatibilité binaire avec BCDI. Le serveur doit rester sur un
réseau interne et n'exposer que le port BCDI nécessaire. Les mises à jour de
sécurité du système d'exploitation ne sont plus fournies par Debian ; ce
compromis doit être accepté explicitement par l'exploitant.
