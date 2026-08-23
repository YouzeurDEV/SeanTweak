# 🧠 Sean Tweak — Optimisation Windows

![version](https://img.shields.io/badge/version-2.0-00d4ff)
![license](https://img.shields.io/badge/license-MIT-lightgrey)
![platform](https://img.shields.io/badge/platform-Windows%2010%2F11-blue)

Un script PowerShell **open source** pour appliquer facilement une sélection d'optimisations Windows (confidentialité, interface, jeux, alimentation) via une interface simple en ligne de commande.

> ⚠️ **Windows Defender / SmartScreen peut afficher un avertissement.**
> C'est normal : le script n'est pas signé numériquement (une signature de code coûte de l'argent). Le code est **100% visible et lisible** dans ce dépôt — vous pouvez l'ouvrir et vérifier chaque ligne avant de l'exécuter. Aucune connexion réseau, aucune télémétrie, aucune obfuscation.

## 📋 Ce que fait le script

Vous choisissez ce que vous voulez appliquer, rien n'est fait sans votre accord. Les optimisations sont classées par risque :
- Sans pastille = sans risque
- 🟡 = à évaluer, lisez la description
- 🔴 = déconseillé

### Confidentialité & Télémétrie
- Désactiver les notifications
- Désactiver les suggestions et conseils Windows
- Désactiver l'Assistant Stockage (Storage Sense)
- Réduire la télémétrie au minimum
- Désactiver l'identifiant publicitaire
- Désactiver l'historique d'activité
- Désactiver Copilot et Recall
- Retirer la recherche web (Bing) du menu Démarrer
- Nettoyer l'écran de verrouillage (Spotlight, pubs)

### Interface & Explorateur
- Afficher les vignettes au lieu des icônes
- Afficher les extensions de fichiers
- Afficher les fichiers et dossiers cachés
- Ouvrir l'Explorateur sur « Ce PC »
- Supprimer le suffixe « - Raccourci »
- Menu contextuel classique (Windows 11)
- Désactiver les widgets / actualités de la barre des tâches
- Désactiver l'accélération / précision du pointeur
- Effets visuels : ajuster pour les performances

### Jeux
- Désactiver la barre de jeu Xbox et le DVR
- Activer le Mode Jeu
- Activer la planification GPU accélérée (HAGS)

### Alimentation
- Mode d'alimentation : Performances élevées / Équilibré / Performances ultimes
- Désactiver la mise en veille prolongée
- Désactiver le démarrage rapide

## 🚀 Installation

1. Téléchargez la dernière **release** (fichier `.zip`) depuis l'onglet [Releases](../../releases) de ce dépôt — ne clonez pas directement si vous n'êtes pas à l'aise avec git.
2. Extrayez le zip où vous voulez.
3. Double-cliquez sur `SeanTweak.bat`.
4. Si Windows affiche « Windows a protégé votre ordinateur », cliquez sur **Informations complémentaires** puis **Exécuter quand même**. C'est le comportement normal pour tout script non signé.
5. Sélectionnez les optimisations souhaitées et validez.

## 🛠️ Utilisation manuelle (PowerShell)

Si vous préférez lancer le script `.ps1` directement plutôt que le `.bat` :

```powershell
powershell -ExecutionPolicy Bypass -File .\Optimisation-Windows.ps1
```

## ⚙️ Pourquoi un fichier .bat ?

Le `.bat` n'est qu'un **lanceur** : il ne fait qu'appeler PowerShell avec les bons paramètres pour éviter d'avoir à taper la commande vous-même. Ouvrez-le avec le Bloc-notes, vous verrez qu'il ne contient qu'une ligne.

## 🔄 Point de restauration recommandé

Avant d'appliquer des changements système, il est recommandé de créer un point de restauration Windows :

```powershell
Checkpoint-Computer -Description "Avant SeanTweak" -RestorePointType "MODIFY_SETTINGS"
```

## 📜 Licence

Ce projet est sous licence MIT — voir le fichier [LICENSE](LICENSE). Utilisation à vos propres risques.

## 🤝 Contribuer

Les suggestions et pull requests sont les bienvenues. Ouvrez une [issue](../../issues) pour proposer une nouvelle optimisation ou signaler un bug.
