# BCDI sous Docker

Kit de déploiement du **serveur BCDI** (Réseau Canopé) sur un hôte Debian
64 bits (`amd64`/`x86_64`), avec Docker Compose, sauvegardes, mise à jour et
reprise d'une installation existante.

> [!IMPORTANT]
> Ce dépôt ne contient **aucun logiciel Canopé**, aucune archive
> d'installation, aucun code d'installation Canopé, aucune base et aucune
> sauvegarde. BCDI est un logiciel propriétaire réservé aux établissements
> abonnés : les paquets doivent être téléchargés depuis l'espace client
> Canopé. L'image Docker ne fournit que l'environnement d'exécution.

## Sommaire

- [Fonctionnalités](#fonctionnalités)
- [Prérequis](#prérequis)
- [Démarrage rapide](#démarrage-rapide)
- [Configuration](#configuration)
- [Architecture](#architecture)
- [Documentation](#documentation)
- [Arborescence](#arborescence)
- [Sécurité](#sécurité)
- [Limites connues](#limites-connues)
- [Licence](#licence)

## Fonctionnalités

- Image d'exécution **Debian 9 i386**, nécessaire aux binaires Borland/Kylix 32 bits de BCDI (les glibc récentes provoquent un `SIGSEGV`).
- Installation Canopé automatisée ou interactive, avec griffage.
- Mise à jour 2.66 et conversion des bases.
- Sauvegarde complète à chaud arrêtée proprement, rétention configurable.
- Restauration d'une installation complète ou import d'une base seule.
- Migration d'un ancien serveur par SSH/SCP ou par dépôt dans `DATA/`.
- Healthcheck Docker : processus `ConsBcdi` et port interne 9000.
- Arrêt propre sur `SIGINT`, avec pseudo-terminal pour BCDI 2.66.

## Prérequis

- Un abonnement BCDI actif et un accès à l'espace client Canopé.
- Un serveur **Debian 11, 12 ou 13**, 64 bits (`amd64`/`x86_64`). L'hôte n'a
  pas besoin d'être 32 bits : seule l'image Docker est en `i386` (x86 32 bits).
- Un hôte ARM64 nécessite une émulation x86, non fournie par ce kit.
- Docker Engine et le plugin Compose v2.
- Un accès Internet pour le griffage et les mises à jour.
- Les deux paquets Canopé suivants, placés dans `sources/` :

| Fichier attendu | Rôle |
| --- | --- |
| `serveurBcdiabtlinux.inst-2.52.tar.gz` | installation initiale du serveur |
| `maj_bcdi-abt_2.66_cl.tar.gz` | mise à jour 2.66 |

Les noms sont vérifiés par `deployer.sh`. Si Canopé fournit des noms différents, renommez les fichiers ou adaptez les contrôles du script.

### Environnement validé

Le kit a été validé en production sur **Debian 13.7.0 amd64**, à partir
d'une installation fraîche de `debian-13.7.0-amd64-netinst.iso`.

## Démarrage rapide

### 1. Récupérer le dépôt

```
git clone https://github.com/moravel/Bcdi_Docker.git
cd Bcdi_Docker
```

### 2. Fournir les paquets Canopé

Téléchargez-les depuis l'espace client Canopé (voir [`docs/INSTALLATION.md`](docs/INSTALLATION.md)), puis :

```
mkdir -p sources
cp /chemin/vers/serveurBcdiabtlinux.inst-2.52.tar.gz sources/
cp /chemin/vers/maj_bcdi-abt_2.66_cl.tar.gz sources/
ls -l sources/
```

### 3. Préparer l'hôte

```
sudo ./installer-hote.sh
```

Le script installe Docker Engine et Compose v2 sur Debian, puis ajoute l'utilisateur au groupe `docker`. **Reconnectez-vous** ensuite pour que le groupe soit pris en compte. Si Docker et Compose v2 sont déjà opérationnels, cette étape peut être sautée.

### 4. Installer BCDI

```
./deployer.sh
```

Le script demande le nom de l'établissement, le code d'installation (saisie masquée), le port publié et le nom d'hôte, puis construit l'image, lance l'installeur Canopé et démarre le serveur. Il crée `.env` avec des droits `600` ; ne le versionnez jamais.

Pour reprendre un serveur existant, `deployer.sh` propose une copie SSH/SCP ou détecte une installation déposée dans `DATA/`. Voir [`docs/EXPLOITATION.md`](docs/EXPLOITATION.md#migration-dun-ancien-serveur).

### 5. Mettre à jour en 2.66

```
./scripts/maj.sh
```

Réponses à l'installeur : `o` (confirmation), `1` (mise à jour), Entrée (emplacement), Entrée (groupe), Entrée (utilisateur), `n` (retour au menu). Une sauvegarde préalable est fortement recommandée :

```
./scripts/sauvegarde.sh
```

### 6. Vérifier

```
./verifier.sh
```

Attendu : conteneur `healthy`, `ConsBcdi` actif, port en écoute, licence griffée et version 2.66. Côté client Windows, renseigner l'adresse du serveur, le port publié et le chemin `/usr/bcdiserv/Data`.

## Configuration

`.env` est créé par `deployer.sh` à partir de `.env.example`. Les principales variables :

| Variable | Rôle | Défaut |
| --- | --- | --- |
| `PUID` / `PGID` | propriétaire de `data/` et `backups/` | `1000` |
| `BCDI_HOST_PORT` | port publié sur l'hôte | `9000` |
| `BCDI_HOSTNAME` | nom d'hôte du conteneur | `bcdi` |
| `TZ` | fuseau horaire | `Europe/Paris` |
| `BACKUP_KEEP_DAYS` | rétention des sauvegardes | `30` |
| `BCDI_ETABLISSEMENT` | nom exact de l'établissement | vide |
| `BCDI_GRIFFE` | code d'installation confidentiel | vide |
| `BCDI_MAIL_ADMIN` | adresse des alertes de mise à jour | vide |
| `BCDI_HOME` | chemin interne de l'installation | `/usr/bcdiserv` |

Le port **interne** est toujours 9000 ; seul le port publié varie. Ne renommez pas `Data` en `data` : les clients BCDI enregistrent `/usr/bcdiserv/Data`.

## Architecture

```
Clients Windows BCDI
  BcdiCli\prog\ServBox.txt
        │ TCP :BCDI_HOST_PORT
        ▼
┌──────────────────── conteneur bcdi ────────────────────┐
│ ConsBcdi (utilisateur gestbcdi), pseudo-terminal       │
│ /usr/bcdiserv  ← ./data/bcdiserv                       │
│ /home/gestbcdi ← ./backups                             │
│ /sources:ro    ← ./sources                             │
└────────────────────────────────────────────────────────┘
```

L'image est construite depuis `i386/debian:stretch-slim`. Les certificats TLS sont copiés depuis `debian:bookworm-slim`, car l'archive Debian 9 n'en fournit plus. Les dépôts Debian archivés sont utilisés avec `trusted=yes` ; Debian 9 n'est plus maintenue.

## Documentation

- [`docs/INSTALLATION.md`](docs/INSTALLATION.md) — obtenir les paquets Canopé, préparer l'hôte, installer, griffer et configurer les clients.
- [`docs/EXPLOITATION.md`](docs/EXPLOITATION.md) — sauvegardes, restaurations, mise à jour, migration, purge, variables et dépannage.
- [`LICENSE`](LICENSE) — texte complet de la GNU GPL v3.0.
- [`NOTICE.md`](NOTICE.md) — périmètre de la licence, logiciel BCDI, limites
  et données personnelles.

## Arborescence

```
.
├── Dockerfile
├── docker-compose.yml
├── .env.example
├── deployer.sh
├── installer-hote.sh
├── verifier.sh
├── docker/
│   ├── entrypoint.sh
│   ├── backup.sh
│   ├── restore.sh
│   └── healthcheck.sh
├── scripts/
│   ├── sauvegarde.sh
│   ├── restaurer.sh
│   ├── restaurer-base.sh
│   ├── maj.sh
│   └── purger.sh
├── docs/
│   ├── INSTALLATION.md
│   └── EXPLOITATION.md
├── LICENSE
├── NOTICE.md
└── sources/
    └── LISEZ-MOI.txt
```

## Sécurité

- `.env` contient le code d'installation : droits `600`, jamais versionné.
- `data/bcdiserv` contient les bases et la licence : à sauvegarder et à protéger.
- `backups/` contient une copie complète des données : à externaliser.
- Les archives `sources/` sont propriétaires et ne doivent pas être publiées.
- Debian 9 étant EOL, gardez le serveur sur un réseau interne et n'exposez que le port BCDI nécessaire.
- Les données d'emprunteurs relèvent du RGPD et des règles de l'établissement.

## Limites connues

- L'image est en `i386` (userland 32 bits) ; elle s'exécute nativement sur
  un hôte `amd64`/`x86_64`. Aucun système 32 bits n'est nécessaire.
- Le serveur BCDI est un logiciel ancien ; les mises à jour Canopé sont interactives et peuvent dépendre de l'accès Internet.
- Le griffage réécrit la licence avant validation : une sauvegarde de `VersionBcdi.Txt` est faite automatiquement, mais un code refusé laisse le serveur sans licence active jusqu'à restauration.
- Aucun test automatisé d'installation complète n'est fourni. Une installation
  réelle a toutefois été validée en production sur Debian 13.7.0 amd64
  (netinst) ; validez toujours sur un serveur de test avant une nouvelle mise
  en production.
- Le dépôt ne contient pas les paquets Canopé ; sans eux, `deployer.sh` s'arrête avec un message explicite.

## Licence

Le code et la documentation originale de ce dépôt sont distribués sous
**GNU General Public License version 3.0** (`GPL-3.0-only`). Le texte complet
se trouve dans [`LICENSE`](LICENSE).

Cette licence est **copyleft** : toute œuvre dérivée distribuée doit être
placée sous la même licence GPLv3. Le programme est distribué dans l'espoir
qu'il sera utile, mais **sans aucune garantie**, expresse ou implicite ; voir
les termes de la GPLv3.

La GPLv3 ne s'applique **pas** au logiciel BCDI, à ses archives, à ses marques,
aux bases de données, aux sauvegardes ni aux données d'emprunteurs. Ces
éléments restent la propriété du Réseau Canopé ou de l'établissement. Voir
[`NOTICE.md`](NOTICE.md).
