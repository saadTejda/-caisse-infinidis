# Préparation INFINIDIS (Android)

Application du préparateur pour INFINIDIS Gestion : tablette et téléphone. Elle s'installe à côté de la caisse
(identifiant différent `com.infinidis.infinidis_prep`, icône verte, nom « Préparation INFINIDIS »).

## Obtenir l'APK

1. Envoyer le dossier `preparation/` sur la branche `main` : l'action GitHub « APK préparation » démarre seule (≈ 10 min).
2. Sur la tablette : ouvrir la page des versions du dépôt et toucher le fichier `preparation-infinidis-…-tablette-64bits.apk`
   de la dernière version `prep-v1.0.N` (la caisse garde ses versions `v1.0.N`).
3. Ou depuis le PC, tablette branchée en USB : `adb install -r preparation-infinidis-…-tablette-64bits.apk`.

## Premier lancement

1. Adresse du serveur : par exemple `https://gestionlivraison.saadtejda.com`.
2. Connexion avec un compte qui a le droit « Préparation : préparer » (préparateur, modérateur, manager, administrateur).
3. Réglages › Impression :
   - **Impression Android** : toute imprimante installée sur la tablette, choix à chaque étiquette ;
   - **Imprimante d'étiquettes réseau / Bluetooth (TSPL)** : Xprinter, TSC, Gprinter… sans aucun clic.
   Puis **Imprimer une étiquette test**.

## Utilisation

Scanner la commande (douchette, ou bouton Caméra) → scanner chaque article (bip clair / son d'erreur) →
« Préparé » tout seul quand tout est scanné → l'étiquette du livreur prévu s'imprime → la coller et la scanner →
la commande suivante s'ouvre. Onglets « Par produit » (tour de prélèvement) et « Préparées aujourd'hui » (contrôle, réimpression).
