# 🧠 Sean Tweak — Optimisation Windows

![version](https://img.shields.io/badge/version-2.0-00d4ff)
![license](https://img.shields.io/badge/license-MIT-lightgrey)
![platform](https://img.shields.io/badge/platform-Windows%2010%2F11-blue)

Un script PowerShell **open source** qui applique une sélection d'optimisations Windows — confidentialité, interface, jeux, alimentation, maintenance — via une interface console au clavier. Vous cochez ce que vous voulez, le script écrit **et note ce qu'il a écrit** pour pouvoir tout remettre en place ensuite.

🌐 **[seantweak.fr](https://seantweak.fr)**

> ⚠️ **Windows Defender / SmartScreen peut afficher un avertissement.**
> C'est normal : le script n'est pas signé numériquement (une signature de code coûte de l'argent). Le code est **100% visible et lisible** dans ce dépôt — vous pouvez l'ouvrir et vérifier chaque ligne avant de l'exécuter. Aucune connexion réseau, aucune télémétrie, aucune obfuscation.

## 🚀 Installation

1. Téléchargez la dernière **release** (fichier `.zip`) depuis l'onglet [Releases](../../releases) de ce dépôt — ne clonez pas directement si vous n'êtes pas à l'aise avec git.
2. Extrayez le zip où vous voulez. Gardez `SeanTweak.bat` et `Optimisation-Windows.ps1` **dans le même dossier**.
3. **Clic droit** sur `SeanTweak.bat` → **Exécuter en tant qu'administrateur**. Sans les droits admin, le script ne peut pas écrire dans le registre et vous le dira au lieu d'échouer à moitié.
4. Si Windows affiche « Windows a protégé votre ordinateur », cliquez sur **Informations complémentaires** puis **Exécuter quand même**. C'est le comportement normal pour tout script non signé.
5. Cochez les optimisations souhaitées et validez avec `A`.

## ⌨️ Navigation

L'interface est entièrement au clavier.

| Touche | Action |
|---|---|
| `↑` `↓` | se déplacer dans la liste |
| `espace` | cocher / décocher, ou replier une rubrique |
| `←` `→` | replier / déplier une rubrique |
| `/` | filtrer la liste (`entrée` valide, `échap` efface) |
| `T` | tout cocher / tout décocher |
| `C` | replier toutes les rubriques |
| `A` | appliquer la sélection |
| `Q` ou `échap` | quitter |

Chaque ligne affiche son niveau de risque, et la description de l'option sélectionnée s'affiche en bas de l'écran :

- **sans pastille** = sans risque
- 🟡 = à évaluer, lisez la description
- 🔴 = déconseillé — une confirmation explicite est demandée avant application

Les réglages déjà appliqués lors d'une session précédente sont marqués **appliqué** avec leur date.

## 📋 Ce que fait le script

Vous choisissez ce que vous voulez appliquer, rien n'est fait sans votre accord.

### Confidentialité & télémétrie
- Désactiver les notifications 🟡
- Désactiver les suggestions et conseils Windows
- Désactiver l'Assistant Stockage (Storage Sense) 🟡
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
- Menu contextuel classique (Windows 11) 🟡
- Désactiver les widgets / actualités de la barre des tâches
- Désactiver l'accélération / précision du pointeur
- Effets visuels : ajuster pour les performances

### Jeux
- Désactiver la barre de jeu Xbox et le DVR
- Activer le Mode Jeu
- Activer la planification GPU accélérée (HAGS) 🟡

### Alimentation
- Mode d'alimentation : Performances élevées / Équilibré / Performances ultimes 🟡
- Désactiver la mise en veille prolongée 🟡
- Désactiver le démarrage rapide 🟡

### Nettoyage & maintenance
- Nettoyer maintenant les fichiers temporaires (`%TEMP%`, `Windows\Temp`, cache Windows Update, vieux logs CBS)
- Planifier un nettoyage hebdomadaire silencieux (tâche planifiée, dimanche 12h)
- Désactiver la réserve de stockage 🟡
- Vérifier l'intégrité du système (SFC + DISM)

### Outils interactifs
Quatre écrans dédiés, avec la même navigation et le même filtre :

- **Applications au démarrage** — liste les entrées `Run` du registre et permet d'en retirer
- **Désinstaller des applications** — programmes classiques et applications du Store, en sélection multiple
- **Services Windows** — une vingtaine de services avec leur nom réel, leur état actuel et leur niveau de risque
- **Annuler les modifications** — voir ci-dessous

## 🔄 Annulation et point de restauration

**Le script propose de créer un point de restauration** juste avant d'appliquer votre sélection. Acceptez, c'est le filet de sécurité le plus large.

En complément, chaque valeur de registre et chaque service modifié sont enregistrés **avec leur valeur d'origine** dans un journal. L'écran *Annuler les modifications* affiche ces enregistrements regroupés par réglage et par date : vous cochez ce que vous voulez remettre en place, et seulement ça.

Si vous préférez créer le point de restauration vous-même, dans PowerShell en administrateur :

```powershell
Checkpoint-Computer -Description "Avant SeanTweak" -RestorePointType "MODIFY_SETTINGS"
```

## 📁 Fichiers créés

Tout est regroupé dans `%LOCALAPPDATA%\TweakSean` :

| Fichier | Contenu |
|---|---|
| `journal.json` | valeurs d'origine, utilisées pour l'annulation |
| `tweaksean.log` | trace horodatée de chaque écriture |
| `cleanup.ps1` | script de nettoyage, aussi utilisé par la tâche planifiée |
| `cleanup.log` | espace libéré à chaque nettoyage |

## 🛠️ Utilisation manuelle (PowerShell)

Si vous préférez lancer le `.ps1` directement plutôt que le `.bat` :

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\Optimisation-Windows.ps1
```

Lancez-le depuis une **console PowerShell classique** (ou Windows Terminal). L'ISE et le terminal intégré de VS Code ne gèrent pas la navigation clavier ; le script le détecte et refuse de démarrer. S'il n'est pas lancé en administrateur, il demande l'élévation de lui-même.

## ⚙️ Pourquoi un fichier .bat ?

Le `.bat` est un **lanceur** : il vérifie que vous êtes bien administrateur, règle l'encodage et la taille de la console, puis appelle PowerShell avec les bons paramètres — PowerShell 7 (`pwsh`) s'il est installé, Windows PowerShell 5.1 sinon. Ouvrez-le avec le Bloc-notes, il n'y a rien de caché dedans.

## 📦 Prérequis

- Windows 10 ou Windows 11
- PowerShell 5.1 (inclus dans Windows) — PowerShell 7 est utilisé automatiquement s'il est présent
- Droits administrateur

## 📜 Licence

Ce projet est sous licence MIT — voir le fichier [LICENSE](LICENSE). Utilisation à vos propres risques.

## 🤝 Contribuer

Les suggestions et pull requests sont les bienvenues. Ouvrez une [issue](../../issues) pour proposer une nouvelle optimisation ou signaler un bug.
