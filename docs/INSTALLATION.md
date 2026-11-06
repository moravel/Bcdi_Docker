# Installation de BCDI sous Docker

Ce document décrit l'installation d'un serveur BCDI à partir de ce dépôt. Il
ne contient aucun code de licence et ne remplace pas les conditions
d'abonnement du Réseau Canopé.

## 1. Périmètre

Le dépôt fournit uniquement le kit technique : `Dockerfile`,
`docker-compose.yml`, scripts, documentation et modèles de configuration.

| Contenu | Présent dans le dépôt |
|---|---|
| Dockerfile, Compose, scripts, documentation | oui |
| Archives d'installation et de mise à jour Canopé | **non** |
| Code d'installation / licence | **non** |
| Bases de données, sauvegardes, `DATA/` | **non** |
| Journal de migration interne | **non** |

Sans les archives Canopé, `./deployer.sh` s'arrête avec :

```text
archive d'installation absente : sources/serveurBcdiabtlinux.inst-2.52.tar.gz
```

C'est normal : suivez la section 3.

## 2. Prérequis

- abonnement BCDI actif (SOLDOC / SOLDOC+, ou abonnement BCDI de
  l'établissement) ;
- identifiant et mot de passe de l'espace client : en général le code
  **UAI/RNE** de l'établissement et le mot de passe associé ;
- serveur Debian 11/12/13 **x86_64** (l'image BCDI est 32 bits) ;
- accès Internet pour le téléchargement, le griffage et les mises à jour ;
- Docker Engine et le plugin Compose v2 (ou `installer-hote.sh`).

Le compte espace client est propre à l'établissement : ne pas utiliser celui
d'un autre site et ne jamais transmettre ses identifiants.

## 3. Obtenir les logiciels et la licence

1. Ouvrir **Solutions documentaires** de Réseau Canopé :
   <https://solutions-documentaires.reseau-canope.fr/> puis **Espace client**.
2. Se connecter avec l'identifiant (UAI/RNE) et le mot de passe de
   l'établissement.
3. Aller dans **Mes abonnements**, puis **Mon espace BCDI**.
4. Télécharger :
   - l'**installation complète de BCDI** (serveur et client) ;
   - la **dernière mise à jour** de BCDI ;
   - le cas échéant, le client Windows pour les postes.
5. Relever les **codes d'installation** de BCDI dans la même rubrique. Ils
   servent au griffage (nom d'établissement + code) et restent confidentiels :
   les saisir dans `.env` ou dans l'installeur, jamais dans un document.

Références :

- manuel BCDI :
  <https://ressources.solutionsdocumentaires.fr/manuels/bcdi/college-lycee/pdf/manuel_bcdi_complet.pdf>
- conditions générales :
  <https://solutions-documentaires.reseau-canope.fr/conditions-generales>

## 4. Placer les archives dans `sources/`

Le dépôt attend deux fichiers, dont les noms sont vérifiés par
`deployer.sh` :

| Nom attendu dans `sources/` | Contenu |
|---|---|
| `serveurBcdiabtlinux.inst-2.52.tar.gz` | paquet d'installation du serveur Linux |
| `maj_bcdi-abt_2.66_cl.tar.gz` | paquet de mise à jour 2.66 |

```bash
cd /chemin/vers/Bcdi_Docker
mkdir -p sources
cp /chemin/vers/serveurBcdiabtlinux.inst-2.52.tar.gz sources/
cp /chemin/vers/maj_bcdi-abt_2.66_cl.tar.gz sources/
ls -l sources/
```

Si Canopé fournit une version ou un nom différent :

- renommer l'archive téléchargée avec le nom attendu ci-dessus ;
- ou adapter les deux contrôles de présence dans `deployer.sh` et les versions
  annoncées dans ce guide.

Le contenu réel de l'archive reste celui fourni par Canopé : ne pas mélanger
une installation et une mise à jour de versions incompatibles. En cas de doute,
suivre la procédure de l'espace client.

Facultatif : régénérer les empreintes pour vos propres archives :

```bash
cd sources && sha256sum *.tar.gz > SHA256SUMS
```

Ces archives sont propriétaires : ne pas les versionner, les publier ni les
transmettre à un établissement non abonné. Elles sont ignorées par
`.gitignore`.

## 5. Préparer l'hôte

```bash
sudo ./installer-hote.sh
```

Le script :

- vérifie Debian et l'architecture x86_64 ;
- installe la clé et le dépôt Docker officiels ;
- installe `docker-ce`, `docker-ce-cli`, `containerd.io`,
  `docker-buildx-plugin` et `docker-compose-plugin` ;
- active le service Docker ;
- ajoute `SUDO_USER` au groupe `docker`.

Reconnectez-vous après l'ajout au groupe, puis vérifiez :

```bash
docker compose version
```

Si Docker et Compose v2 sont déjà installés, cette étape peut être sautée.

## 6. Installer le serveur

```bash
./deployer.sh
```

Le script vérifie l'hôte et les archives, demande le nom de l'établissement, le
code confidentiel (saisie masquée), le port et le nom d'hôte, puis construit
l'image, lance l'installation et démarre le serveur.

Il peut être lancé en root ou avec `sudo` : dans ce cas, les fichiers de
`data/` et `backups/` sont attribués à l'UID/GID **1000** (utilisateur
`gestbcdi` du conteneur), un UID/GID privilégié étant refusé par l'image.

### Méthode manuelle

```bash
docker compose build
docker compose run --rm bcdi install
docker compose up -d
```

Réponses de l'installeur Canopé en mode interactif :

| Question | Réponse |
|---|---|
| menu | `2` (installation d'un nouveau produit) |
| emplacement de l'archive | Entrée (dossier courant) |
| emplacement d'installation | `/usr` |
| nom du répertoire | `bcdiserv` |
| port | Entrée (`9000`) |
| base à sauvegarder | Entrée (`Data`) |
| emplacement des sauvegardes | Entrée (`/home/gestbcdi`) |
| groupe / utilisateur | Entrée (`gestbcdi`) |
| mail administrateur | Entrée ou adresse |
| répertoire existant | `o` |
| nom d'établissement / code | ceux de la licence |
| échec de griffage | `n` |
| sauvegarde cron | `n` (gérée par le kit) |
| service init.d | `n` (Docker supervise) |
| retour au menu | `n` |

Si une installation existe déjà dans `data/bcdiserv`, `deployer.sh` la
conserve et saute l'installation. Pour changer de licence, voir
[`EXPLOITATION.md`](EXPLOITATION.md). Pour réinstaller à neuf :

```bash
./scripts/purger.sh
./deployer.sh
```

La purge efface les bases et la licence : sauvegarder avant.

## 7. Mettre à jour en 2.66

Sauvegarder d'abord :

```bash
./scripts/sauvegarde.sh
```

Puis :

```bash
./scripts/maj.sh
```

Répondre `o` à la confirmation, puis à l'installeur Canopé : `1`, Entrée
(emplacement), Entrée (groupe), Entrée (utilisateur), puis `n` à « Retour au
menu ? ». Le script redémarre le serveur à la fin.

La mise à jour nécessite Internet et un serveur griffé ; elle est interactive.
Le dossier `prog/RepMaj` contient les fichiers de mise à jour des clients.

## 8. Vérifier

```bash
./verifier.sh
```

Ou manuellement :

```bash
docker compose ps
docker compose logs --tail=20 bcdi
docker compose exec -T bcdi /usr/local/bin/entrypoint.sh statut
ss -ltn | grep 9000
```

Attendu : conteneur `healthy`, `ConsBcdi` actif, version affichée, port en
écoute et, dans les journaux, le message de démarrage du serveur de requêtes.

Après une installation neuve, vérifier aussi que la licence est griffée :

```bash
head -n 1 data/bcdiserv/prog/VersionBcdi.Txt    # nom de l'établissement
sed -n '5p' data/bcdiserv/prog/VersionBcdi.Txt   # 2.66
```

La première ligne ne doit pas commencer par `XXXXX`.

## 9. Clients Windows

Sur chaque poste, installer le client BCDI téléchargé depuis l'espace client,
puis renseigner dans `BcdiCli\prog\ServBox.txt` :

- **adresse** : IP fixe ou nom DNS du serveur Docker ;
- **port** : valeur de `BCDI_HOST_PORT` (9000 par défaut) ;
- **chemin de la base** : `/usr/bcdiserv/Data` (ou la valeur de `BCDI_HOME`).

À la connexion, le client propose sa mise à jour : l'accepter jusqu'à la
version du serveur (2.66). Vérifier ensuite l'affichage de la version dans le
client et dans le serveur.

## 10. Licence et sécurité

- BCDI est un logiciel propriétaire du Réseau Canopé, réservé aux abonnés.
- Les archives de `sources/` ne doivent pas être rediffusées : chaque
  établissement les télécharge avec son propre compte.
- Le code d'installation reste dans `.env` (droits 600, non versionné) ou
  dans l'espace client ; ne pas le mettre dans un document, un ticket ou un
  dépôt Git.
- Les bases et sauvegardes contiennent des données d'emprunteurs : les
  protéger et les externaliser selon les règles de l'établissement.
- Debian 9 n'étant plus maintenue, garder le serveur sur un réseau interne et
  n'exposer que le port BCDI.

## 11. Aide

- [`../README.md`](../README.md) : vue d'ensemble et démarrage rapide.
- [`EXPLOITATION.md`](EXPLOITATION.md) : sauvegardes, restaurations,
  migration, purge et dépannage.
- `sources/LISEZ-MOI.txt` : rappel des fichiers attendus.
- Espace client Canopé : codes d'installation, téléchargements, procédure de
  réinstallation.
- Support Solutions documentaires : via les coordonnées indiquées dans
  l'espace client.
