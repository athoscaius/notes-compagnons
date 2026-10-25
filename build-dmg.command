#!/bin/zsh
set -euo pipefail
ROOT="${0:A:h}"
APP="${1:-$ROOT/Notes.app}"
WORK="$(mktemp -d /private/tmp/notes-dmg.XXXXXX)"
trap 'rm -rf "$WORK"' EXIT
ditto --noextattr --norsrc "$APP" "$WORK/Notes.app"
codesign --verify --deep --strict "$WORK/Notes.app"
ln -s /Applications "$WORK/Applications"
cat > "$WORK/Installation.txt" <<'TXT'
Notes · Compagnons — Mac Apple Silicon, macOS 14+

Glissez Notes dans Applications, puis ouvrez-la. Écrivez immédiatement : les notes sont enregistrées automatiquement sur ce Mac, sans titre obligatoire.

Archives : bouton en haut à gauche. Nouvelle note : ⌘N. Export Word/PDF : ⌘⇧E, A3/A4/A5 en portrait ou paysage.

Les notes sont conservées un mois à partir de leur création, puis supprimées automatiquement. Les exports restent à l’emplacement choisi.

Signature locale ad hoc, sans Developer ID ni notarisation Apple. Sur un autre Mac, une autorisation d’ouverture peut être nécessaire dans Réglages Système > Confidentialité et sécurité.

Projet indépendant de Notes d’Apple. Sources : https://github.com/athoscaius/notes-compagnons
TXT
hdiutil create -volname 'Notes · Compagnons' -srcfolder "$WORK" -format UDZO -ov "$ROOT/Notes-Compagnons-1.1.0-arm64.dmg"
hdiutil verify "$ROOT/Notes-Compagnons-1.1.0-arm64.dmg"
