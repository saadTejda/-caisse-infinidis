# Café Resto — Caisse Android

Application Flutter (Android) pour la caisse, branchée sur l’API Laravel `/api/v1`.

## Prérequis

- Dépôt GitHub avec GitHub Actions (Flutter n’est pas installé sur le PC)
- Backend Laravel du projet **app cafe resto** (auth Bearer, `GET /pos/bootstrap`)
- Tablette : débogage USB, câble, et `adb` sur le PC

Paquet Android : `com.caferesto.cafe_resto_caisse`. Il peut coexister avec la caisse INFINIDIS sur la même tablette.

## Fonctionnalités

- Choix de l’hôte API puis login (token Sanctum)
- Sync catalogue + réglages (dont imprimantes) en local (SQLite)
- POS : panier, types de commande, encaissement
- File d’attente hors-ligne des ventes (`Idempotency-Key`)
- Ouverture / fermeture de caisse (online)
- Impression ESC/POS ticket client + 1–2 imprimantes cuisine (Wi‑Fi TCP ou Bluetooth)

## Emplacement

Repo Git séparé : `/Users/saad/Documents/cafe-resto-caisse` (branche `main`).

## Installer sur la tablette

Le code se modifie ici. L’APK est construit dans le cloud, pas sur le PC.

1. Commit et push sur `main` (ou lancer le workflow **APK caisse café resto** à la main).
2. GitHub Actions installe Flutter **3.50.1** (version figée, celle du projet Android), Java 17, puis lance `flutter pub get` et `flutter build apk --release --split-per-abi`.
3. L’APK est publié en Artifact et en Release, tag `cafe-resto-v1.0.<numéro>`.
4. Sur le PC, récupérer le fichier `cafe-resto-caisse-<numéro>-tablette-64bits.apk` (Lenovo et tablettes récentes). Le fichier `ancien-32bits` est pour les très vieux appareils.
5. Brancher la tablette (débogage USB accepté) et installer, sans piloter l’écran :

```bash
adb install -r cafe-resto-caisse-NUMERO-tablette-64bits.apk
```

6. Ouvrir **Café Resto Caisse** à la main sur la tablette.

Signature : secrets GitHub `CAISSE_RESTO_KEYSTORE` (fichier .p12 en base64), `CAISSE_RESTO_KEYSTORE_PASSWORD`, et en option `CAISSE_RESTO_KEY_ALIAS` (défaut `cafe-resto`). Rien de tout cela ne va dans le code. Sans ces secrets, l’APK est signé avec la clé de test : il faut désinstaller l’app avant une prochaine mise à jour signée avec la vraie clé.

Permissions Android : Internet, Bluetooth (voir `AndroidManifest.xml`). HTTP en clair autorisé pour une API sur le réseau local.

## API utilisée

| Endpoint | Rôle |
|----------|------|
| `POST /api/v1/auth/token` | Login mobile |
| `POST /api/v1/auth/token/logout` | Révoquer le token |
| `GET /api/v1/pos/bootstrap` | User + caisse + settings + catalogue |
| `POST /api/v1/orders` | Encaissement (+ replay offline) |
| `GET/POST /api/v1/cash/sessions…` | Tiroir |

Permissions Spatie : `pos.access`, `cash.operate`.
