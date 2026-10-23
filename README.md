# Caisse INFINIDIS (Android)

Application caisse pour INFINIDIS Gestion : tablette et téléphone, en ligne et hors ligne.

## Obtenir l'APK (sans installer Flutter)

1. Envoyer ce dossier dans un dépôt GitHub (branche `main`).
2. Onglet **Actions** → « APK caisse » : la construction démarre seule à chaque envoi (ou bouton **Run workflow**).
3. À la fin (≈ 10 min), sur la tablette : ouvrir `https://github.com/saadTejda/-caisse-infinidis/releases/latest` et toucher le fichier `.apk`.
4. Autoriser « Installer des applications inconnues » pour le navigateur, puis « Installer » (si Play Protect avertit : « Installer quand même »).

## Premier lancement

1. Adresse du serveur : par exemple `https://gestionlivraison.saadtejda.com` (modifiable ensuite dans le menu → Serveur).
2. Connexion avec un compte caissier, modérateur, manager ou administrateur (mot de passe déjà changé sur le site).
3. Menu → **Imprimante** : choisir le modèle, la connexion (Bluetooth appairé ou IP réseau), puis **Test**.

## Hors ligne

- Les ventes payées (espèces, carte, virement, chèque) sont gardées sur l'appareil et envoyées au retour de la connexion, sans doublon.
- La vente à crédit, l'ouverture et la clôture de caisse demandent Internet.
- Bouton **Synchroniser** : produits, contacts, ou tout (avec envoi des ventes en attente).
