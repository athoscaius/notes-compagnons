# Notes · Compagnons

Une petite application macOS pour écrire immédiatement, coller du texte propre et retrouver ses notes par date. Données locales, sans compte ni service distant.

## Installer

[Télécharger le DMG pour Mac Apple Silicon](https://github.com/athoscaius/notes-compagnons/releases/latest/download/Notes-Compagnons-1.2.0-arm64.dmg), l’ouvrir et glisser **Notes** dans Applications. macOS 14 ou ultérieur.

L’application est indépendante de Notes d’Apple. Son identifiant est `local.compagnons.notes`. Signature ad hoc, sans Developer ID ni notarisation Apple ; macOS peut demander une autorisation d’ouverture sur un autre Mac.

## Écrire

- Une page vide, prête à écrire dès l’ouverture. Aucun titre de note ni bouton Enregistrer.
- Sauvegarde locale dès la première lettre. Une nouvelle note se crée avec **Nouvelle note** ou ⌘N.
- Au collage : suppression des styles étrangers, images, commentaires, attributs et contenus masqués ; les liens cachés sont remplacés par leur URL visible. Certains paramètres de suivi connus sont supprimés des liens développés.
- Les seuls styles conservés au collage sont **gras**, **puces rondes**, **listes numérotées** et **tableaux**. Les titres collés deviennent du texte normal.
- Titres T1/T2/T3 utilisables dans la note et les exports. À la copie, leurs niveaux et leur présentation sont retirés ; le gras explicite du corps, les puces et les tableaux restent disponibles.
- Création d’un tableau en choisissant les colonnes et les lignes dans une grille, ou avec les champs de dimensions. Tabulation passe à la cellule suivante.
- **⌘B** active ou désactive le gras ; **- suivi d’un espace** en début de paragraphe crée une puce ronde. **6. suivi d’un espace** démarre au numéro 6 ; Entrée continue à 7. Les départs saisis restent indépendants. Un bouton Liste numérotée est placé à côté des puces.
- Interligne compact pour une lecture plus dense.
- Une petite poubelle rouge place une note dans la **Corbeille**, accessible au bas des archives. On peut la restaurer ou **Vider** la corbeille pour supprimer définitivement les notes qui s’y trouvent.
- Le bouton Archives ouvre le volet gauche, organisé automatiquement par date, avec un aperçu des premières lignes.

Le nettoyage retire les métadonnées et certains caractères invisibles courants. Il ne détermine pas si un texte a été produit par une IA et ne garantit pas la détection de tout filigrane dissimulé dans un texte. Les accents et les caractères utiles, notamment les séquences emoji, sont conservés.

## Conservation locale

Les notes sont des fichiers JSON privés dans `~/Library/Application Support/Compagnons Notes/Notes` (dossier 0700, fichiers 0600). Ce dossier n’est pas synchronisé par l’application et n’est jamais envoyé à GitHub.

Chaque note expire **un mois calendaire après sa création** ; une modification, une mise en corbeille ou une restauration ne repoussent pas cette date. Le fichier est supprimé sans alerte. Le nettoyage intervient dans l’app, à l’ouverture et au réveil du Mac, ainsi que par une tâche utilisateur locale toutes les 15 minutes lorsque le Mac fonctionne. Les exports et les éventuelles sauvegardes du système restent indépendants de ce nettoyage.

La tâche `local.compagnons.notes.expiry` est installée au premier lancement normal. Elle ne démarre aucune fenêtre et ne traite que les notes de cette application. Pour la retirer après désinstallation :

```sh
launchctl bootout "gui/$(id -u)/local.compagnons.notes.expiry"
rm "$HOME/Library/LaunchAgents/local.compagnons.notes.expiry.plist"
```

## Exporter

**Exporter** ou ⌘⇧E : Word (`.docx`) ou PDF, papier **A3, A4 ou A5**, en **portrait ou paysage**. Le défaut est **A4 portrait**. Les titres, le gras, les puces et les tableaux sont conservés. Les URL restent visibles et aucun lien hypertexte masqué n’est ajouté.

Les fichiers sont générés localement ; Word ou une imprimante ne sont pas nécessaires. Le PDF est composé directement avec CoreText/CoreGraphics et le DOCX est un paquet OOXML.

## Compagnons

Notes figure dans le catalogue de Compagnons, aux côtés de Détourage PhotoCraft et Sous-titres FilmCraft. Compagnons peut détecter les Releases de ce dépôt et installer les nouvelles versions depuis leur DMG vérifié.

## Construire et vérifier

```sh
./build.command
./build-dmg.command
Notes.app/Contents/MacOS/CompagnonsNotes --self-test
```

Outils de ligne de commande Xcode requis. AppKit, WebKit, CoreText et PDFKit sont fournis par macOS. Aucun paquet externe ni modèle d’IA n’est nécessaire.

Le mode `--qa-editor --qa-store /private/tmp/NotesQA/Store --qa-output /private/tmp/NotesQA/Exports` teste le nettoyage, la copie, les tableaux, la sauvegarde et les exports sur des données fictives. Il n’installe pas la tâche de rétention et n’utilise pas les notes personnelles. Ne pas omettre le dossier temporaire de test.

## Sources et droits

Application personnelle créée pour la suite Compagnons. Aucune licence libre supplémentaire n’est accordée au code par la seule publication du dépôt. Les frameworks Apple conservent leurs conditions propres. L’illustration du calmar est fournie par l’utilisateur et conservée dans `assets/provided-icon.png`. La préparation macOS préserve le dessin et sa transparence avec une marge adaptée.
