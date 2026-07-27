# CLAUDE.md

Projektnotizen für Claude Code. Knapp halten, bei Änderungen aktuell halten.

## Verhaltensregeln für Claude (IMMER beachten)

1. **Sitzungsstart:** Zu Beginn jeder Sitzung das Repo `wundi77/RsyncBackupDesktop`
   auf GitHub prüfen (Commits, Dateien) und anhand von `NOTIZEN.md` /
   `CLAUDE.md` einen Überblick über den aktuellen Stand gewinnen.

2. **Kontext-Komprimierung:** Sobald der Kontext ca. 40 % erreicht, den
   bisherigen Chatverlauf zusammenfassen und komprimieren, um die Sitzung
   übersichtlich zu halten.

3. **Vor jedem Push:** `CLAUDE.md`, `NOTIZEN.md` und `ANLEITUNG.md` auf den
   aktuellen Stand bringen (neue Features, letzter Commit-Hash, Änderungen an
   Struktur/Build). Alle drei Dateien im selben Commit mitschicken.

4. **Skills prüfen:** Bei jeder Sitzung kurz prüfen, ob installierte Skills
   (`/skills`) oder neue auf skill.sh sinnvoll für das Projekt wären —
   wenn ja, Hinweis mit Nachfrage geben.

5. **Kein Branch-Workflow:** Änderungen immer direkt auf `main` committen und
   pushen. Keinen separaten Feature-Branch anlegen.

## Was das ist

Reine **Desktop-App** für macOS mit normalem Fenster und Dock-Icon, die
rsync-Backups ausführt. Geschrieben in **SwiftUI + AppKit**.
Kein Xcode-Projekt — Build läuft direkt über `swiftc`.

**Abstammung:** Dieses Projekt ist eine Fenster-Variante von
[`wundi77/RsyncBackup`](https://github.com/wundi77/RsyncBackup), das als
reine Menüleisten-App ohne Dock-Icon läuft. Beide Repos teilen sich die
identische Backup-Logik (`BackupManager`), unterscheiden sich nur im
App-Gerüst: hier `WindowGroup` statt `MenuBarExtra`, kein `LSUIElement`.
Funktions-Updates ggf. in beiden Repos parallel nachziehen.

Der ausgeführte Befehl ist im Kern fest verdrahtet:

```
rsync -ah --partial --info=progress2 --delete --ignore-errors --stats <Quelle>/ <Ziel>
```

`--stats` liefert am Laufende einen auswertbaren Zusammenfassungsblock
(Dateianzahl, übertragene Datenmenge), der für die Kurzanzeige in der App
geparst wird (siehe `buildSummaries` in `BackupManager`). `--info=progress2`
liefert eine Prozentangabe für den **Gesamtfortschritt über alle Dateien**
(statt nur der aktuellen Einzeldatei wie bei `-P`/`--progress`), aus der
`BackupManager.parseProgress(from:)` den Fortschrittsbalken speist.

**Kompatibilitäts-Fallback:** `--info=progress2` gibt es erst ab rsync 3.x.
Apples mitgeliefertes `/usr/bin/rsync` ist auf vielen Macs noch die uralte
Version 2.6.9 (2006, wegen GPLv3-Lizenzwechsel) ohne dieses Flag. (Ab macOS
Sequoia 15.4 ersetzt Apple es durch `openrsync` — das ist zwar aktiv gepflegt,
unterstützt aber ebenfalls kein `--info=progress2`, nur eine Teilmenge der
rsync-Flags.)

- `BackupManager.rsyncPfad` sucht zuerst nach einem über Homebrew
  installierten rsync (`/opt/homebrew/bin/rsync`, `/usr/local/bin/rsync`)
  und bevorzugt das; sonst wird `/usr/bin/rsync` (das System-rsync)
  verwendet.
- `BackupManager.rsyncVersionMajor`/`unterstuetztProgress2` prüfen per
  `rsync --version` die Major-Version des tatsächlich verwendeten Pfads und
  wählen bei < 3 automatisch `-P` statt `--info=progress2` — der
  Fortschrittsbalken zeigt dann nur den Fortschritt der aktuellen
  Einzeldatei statt den Gesamtfortschritt, der Befehl schlägt aber nicht mit
  „unknown option" fehl.
- **Update-Hinweis-Overlay**: Bei jedem App-Start prüft `BackupManager.init()`,
  ob das *System*-rsync (kein Homebrew-rsync gefunden) noch < Version 3 ist.
  Falls ja, wird `rsyncBenötigtUpdate = true` gesetzt und `ContentView` zeigt
  ein scrollbares Overlay (`RsyncUpdateHinweis`, `maxWidth: 440, maxHeight: 560`).
  Inhalt zweigeteilt:
  1. **„Warum das wichtig sein kann"** — erklärt zuerst den Unterschied zur
     aktuellen Version (kein Gesamtfortschritt, keine Fehlerbehebungen seit
     2006, ggf. langsamer/weniger robust) und stellt klar, dass das Backup
     auch mit der alten Version einwandfrei funktioniert — ein Update ist
     freiwillig, keine Voraussetzung.
  2. **Schritt-für-Schritt-Anleitung** (`AnleitungsSchritt`, nummerierte
     Kreis-Badges): Terminal öffnen → Homebrew installieren (inkl. Erklärung
     was Homebrew ist, Installationsbefehl von brew.sh, Hinweis auf
     Passwortabfrage) → `brew install rsync` → App neu starten (die Prüfung
     läuft nur einmalig beim Start, kein automatischer Refresh zur Laufzeit).
  Der „Verstanden"-Button blendet es nur für die laufende Sitzung aus; beim
  nächsten Start wird erneut geprüft.

## Struktur

- `Sources/RsyncBackupApp.swift` — **gesamter Code in einer Datei**:
  - `BackupProfile` (`Codable`): benanntes Quelle/Ziel-Paar.
  - `BackupManager` (`@MainActor`, `ObservableObject`): Logik. Verwaltet eine
    Liste von Profilen (als JSON in `UserDefaults`, Key `profiles`), startet
    rsync als `Process`, liest die Ausgabe live über einen
    `Pipe`-`readabilityHandler`, Fertig-Mitteilung via
    `UNUserNotificationCenter`. Migriert beim ersten Start alte
    `source`/`destination`-Keys in ein Standardprofil.
  - `PfadZeile`: Hilfs-View für Quelle/Ziel-Zeilen mit Ordner-Icon. Unterstützt
    Drag & Drop von Ordnern/Volumes (`.onDrop(of: [.fileURL], ...)`), prüft per
    `FileManager.fileExists(isDirectory:)`, ob das gedropte Element ein Ordner
    ist, und zeigt beim Drag-Over eine farbige Umrandung als Feedback.
  - `StatusPunkt`: farbiger Kreis (grün/gelb/rot/grau) für den Backup-Zustand.
  - `ContentView`: das SwiftUI-Hauptfenster (Profil wählen/anlegen/löschen/
    umbenennen, Quelle/Ziel wählen, Testlauf-Toggle, Start/Abbrechen,
    ausklappbare Protokoll-/Fehler-Zusammenfassung, Mitteilungs-Toggle).
  - `WindowAccessor`: `NSViewRepresentable`, greift auf das `NSWindow` zu und
    macht die Titelleiste transparent/titellos (`titlebarAppearsTransparent`,
    `titleVisibility = .hidden`), aktiviert `isMovableByWindowBackground` und
    setzt die leicht transparente Fensterhintergrundfarbe (siehe UI-Stil).
    Ruft außerdem zweimal `window.makeFirstResponder(nil)` auf (sofort und
    nochmal nach 0,05 s), damit macOS nicht automatisch das Profilname-
    Textfeld fokussiert und dort schon beim Start einen blinkenden Cursor
    zeigt, bevor man aktiv hineingeklickt hat.
  - `RsyncBackupDesktopApp`: Einstiegspunkt, `WindowGroup` (ohne Titel-String)
    mit `ContentView` als Inhalt, `.windowResizability(.contentSize)`,
    `.windowStyle(.hiddenTitleBar)`.
- `AppIconSource/` — **festes, vom Nutzer geliefertes App-Icon** (2026-07-20,
  „Variante 3f: Graphit-Hintergrund + grüner Ordner"), fest im Repo versioniert:
  - `AppIcon-1024.png` — Master-Icon (1024×1024 px), nur als Referenz/für
    einen späteren Re-Export.
  - `AppIcon.iconset/` — alle Standardgrößen (16–1024 px, inkl. `@2x`) im von
    `iconutil` erwarteten Format/Namensschema, direkt einsatzbereit.
  - Ersetzt das frühere `make_icon.swift` (programmatisch gezeichnetes Icon,
    grüner Verlauf + SF Symbol) vollständig — dieses Icon wird jetzt bei
    **jedem** Build unverändert übernommen, nicht mehr neu generiert.
- `build.command` — Doppelklick-Build: kopiert `AppIconSource/AppIcon.iconset`,
  ruft `iconutil` auf, kompiliert, baut `.app`-Bundle, schreibt `Info.plist`,
  signiert ad-hoc.
- `ANLEITUNG.md` — Endnutzer-Anleitung (deutsch).
- `RsyncBackupDesktop.app/` — Build-Ergebnis, **nicht versioniert** (`.gitignore`).

## Funktionen

- **Profile**: mehrere Quelle/Ziel-Paare, umschaltbar per Picker.
- **Testlauf (Dry-Run)**: hängt `-n` an rsync an; verändert nichts. Toggle sitzt
  direkt über dem Start-Button.
- **Pause/Fortsetzen**: während eines Laufs neben Abbrechen; nutzt
  `Process.suspend()`/`resume()` (SIGSTOP/SIGCONT).
- **Protokoll/Fehler**: stdout+stderr laufen weiterhin komplett in `log`
  bzw. `errors` (getrennte Pipes `outPipe`/`errPipe`; stderr fließt in
  `log` *und* `errors`), werden aber **nicht mehr roh angezeigt**. Nach
  Laufende baut `buildSummaries(exitCode:)` daraus zwei kurze, verständliche
  Texte (`logSummary`, `errorSummary`) — Fehler inkl. rsync-Exit-Code und
  Klartext-Beschreibung aus einer statischen Tabelle
  (`BackupManager.exitCodeDescriptions`). Das vollständige Protokoll (inkl.
  Fehlerabschnitt) wird zusätzlich per `saveLogFile(exitCode:)` als
  `~/Desktop/RsyncBackup-<Profil>-<Zeitstempel>.txt` gespeichert (ein Lauf =
  eine Datei, auch bei Testläufen).
- **Normales Fenster mit Dock-Icon**: kein Menüleisten-Icon, keine
  MenuBarExtra-Einschränkungen.
- **Drag & Drop für Quelle/Ziel**: Ordner oder Volumes (z. B. aus Finder)
  können direkt in die Pfadfelder gezogen werden; nur Ordner werden
  akzeptiert, Dateien werden ignoriert.
- **Mitteilung wenn fertig**: macOS-Notification bei Abschluss/Fehler (opt-in,
  fragt beim Einschalten nach Erlaubnis), zusätzlich Systemsound. Schalter als
  echter Schiebeschalter (`.toggleStyle(.switch)`).
- **Kein Autostart**: bewusst kein „Beim Login automatisch starten" (bis
  2026-07-15 via `SMAppService` vorhanden, dann auf Wunsch entfernt) — die
  App wird immer von Hand gestartet.
- **Fortschrittsbalken**: `ProgressView(value: manager.progress)` über die
  volle Breite, nur während eines Laufs sichtbar. `progress` wird per
  `BackupManager.parseProgress(from:)` (Regex `(\d{1,3})%`) aus der
  rsync `--info=progress2`-Fortschrittszeile geparst — echter
  Gesamtfortschritt über alle zu übertragenden Dateien, nicht nur die
  aktuelle Einzeldatei. Bei Erfolg wird `progress` am Ende auf `1` gesetzt.
- **Bestätigungsdialog bei leerer Quelle**: Klick auf „Backup starten" prüft
  (nur wenn kein Testlauf) per `BackupManager.sourceLooksEmpty()`, ob die
  Quelle keine Einträge enthält. Falls ja, zeigt ein `.confirmationDialog`
  eine Warnung, da eine leere Quelle bei aktivem `--delete` sonst
  kommentarlos alle Dateien im Ziel löschen würde.

## UI-Stil

- **Akzentfarbe**: kräftiges, nicht grelles Grün `Color.backupAccent`
  (`Color(red: 0.25, green: 0.62, blue: 0.33)`) statt System-Blau — via
  `.tint(Color.backupAccent)` auf der Wurzel-View, greift auf Buttons,
  Toggles, Picker und `ProgressView`. Auch der laufende `StatusPunkt` nutzt
  dieses Grün.
- **Dark/Light-Umschalter**: dezenter Kreis-Button, sitzt rechts außen in
  derselben Zeile wie Profil-Menu/„+"/Papierkorb (per `Spacer()` dorthin
  geschoben) statt in einer eigenen Kopfzeile — dadurch beginnt der Inhalt
  direkt unter der System-Ampel, ohne separaten Leerbereich. Toggelt
  `@AppStorage("isDarkMode")` und wird über `.preferredColorScheme(...)` auf
  die ganze App angewendet. Default: Dark. Zeigt bewusst das Symbol des
  Modus, in den man wechseln *würde* (nicht den aktuell aktiven): im Dark
  Mode also eine Sonne, im Light Mode einen Mond.
- **Kein Fenstertitel, keine dicke Titelleiste**: `WindowAccessor` blendet nur
  Titeltext/-leiste aus (`.windowStyle(.hiddenTitleBar)`); der reguläre
  Fensterhintergrund füllt die komplette Fläche durchgängig. Die
  System-Ampel (Schließen/Minimieren/Zoomen) steht dadurch einfach frei auf
  dieser Fläche, ohne sichtbare Menüleiste darüber.
- **Leichte Fenster-Transparenz**: `ContentView.windowHintergrundDeckkraft`
  (`0.9`) legt die Deckkraft an einer Stelle fest — `WindowAccessor` setzt
  `window.isOpaque = false` und `backgroundColor` mit dieser Alpha, die
  SwiftUI-Hintergrundfarbe (`fensterHintergrund`) nutzt `.opacity(...)` mit
  demselben Wert (beide Ebenen müssen die Transparenz tragen, sonst verdeckt
  die eine die andere komplett).
- **Profilauswahl ist ein `Menu`, kein `Picker`**: Der native `Picker`-Aufklapp-
  Pfeil war in beiden Modi kaum sichtbar (zu ähnliche Farbe zum Hintergrund)
  und ließ sich über SwiftUI nicht gezielt einfärben. Stattdessen zeigt ein
  `Menu` mit eigenem Label (`Text` + `Image(systemName: "chevron.up.chevron.down")`)
  den Profilnamen und einen selbst eingefärbten Pfeil. Textfarbe über
  `ContentView.pickerTextFarbe` modusabhängig (Dark Mode `Color(white: 0.85)`,
  Light Mode `Color(white: 0.3)`, bewusst kein reines Schwarz/Weiß); Pfeilfarbe
  über `ContentView.pfeilFarbe` bewusst fix `Color(white: 0.5)` (Mittelgrau) in
  beiden Modi.
- **Karten-Redesign (2026-07-15)**: Statt einer gemeinsamen `.quaternary`-
  Hintergrundfläche pro Abschnitt hat jetzt jedes funktionale Element seine
  eigene, dünn umrandete Karte: Profil-Menu, Profilname-Feld, Quelle, Ziel,
  Protokoll und Fehler jeweils separat, mit `RoundedRectangle` (Radius 10–14)
  + `strokeBorder`. Zwei neue berechnete Eigenschaften auf `ContentView`
  liefern die Farben modusabhängig: `kartenFuellung` (Light: Weiß, Dark:
  `Color(red: 0.12, green: 0.12, blue: 0.13)`) und `kartenRahmen` (Light:
  `Color(white: 0.87)`, Dark: `Color(white: 0.24)`). Der Fensterhintergrund
  selbst ist ebenfalls angepasst (`fensterHintergrund` /
  `ContentView.fensterHintergrundNSColor(isDarkMode:)`, dezentes Warmgrau im
  Light Mode, Beinahe-Schwarz im Dark Mode statt des System-Standards) — nötig
  in beiden Repräsentationen (SwiftUI-Hintergrund *und* `NSWindow.backgroundColor`
  in `WindowAccessor`, das dafür jetzt einen `isDarkMode`-Parameter bekommt
  und in `updateNSView` beim Umschalten mitzieht statt nur einmalig in
  `makeNSView`). Die Einstellung (Mitteilung) bleibt bewusst ohne
  Kartenrahmen, frei stehend auf der Fensterfläche (Autostart-Schalter am
  2026-07-15 komplett entfernt, siehe „Funktionen").
- **Neue Button-Stile** (eigene `ButtonStyle`-Typen statt Standard-Stilen):
  `PillButtonStyle` (gefüllte Kapsel, für „Wählen…"), `StartButtonStyle`
  (vollbreiter, stark abgerundeter Start-Button, dimmt bei `isEnabled == false`
  über `@Environment(\.isEnabled)`), `IconButtonStyle` (quadratischer,
  umrandeter Button für „+"/Papierkorb neben der Profilauswahl).
- **Testlauf-Toggle als Checkbox**: `.toggleStyle(.checkbox)`. **Mitteilung
  wenn fertig** ist explizit `.toggleStyle(.switch)` (Schiebeschalter).
- Farbiger `StatusPunkt` vor der Statuszeile.
- Fenster: `minWidth: 440, idealWidth: 500, minHeight: 510, idealHeight: 540`,
  frei skalierbar (kein fixes `.frame(width:)` wie in der Menüleisten-Variante).
  Werte am tatsächlichen Platzbedarf des Inhalts orientiert — knapp genug,
  damit kein unnötiger Leerraum entsteht, aber hoch genug, dass beim Start
  nie ein zu kleines Fenster mit abgeschnittenen Buttons erscheint. Da der
  Dark-/Light-Button jetzt in der Profilzeile mitläuft statt einer eigenen
  Kopfzeile, ist weniger Höhe nötig als zuvor.
- Äußeres Padding getrennt: `.padding(.horizontal, 20)`,
  `.padding(.top, 14)`, `.padding(.bottom, 20)` statt eines einheitlichen
  `.padding(20)`, damit die Profilzeile nah unter der System-Ampel beginnt.
  Zusätzlich `.frame(..., alignment: .top)` auf der äußersten
  `.frame(maxWidth: .infinity, maxHeight: .infinity)`, damit überschüssige
  Höhe (z. B. bei manuellem Vergrößern) unten statt mittig landet.

## Bauen

Doppelklick auf `build.command`, ODER direkt kompilieren (ohne den
interaktiven `read`-Schritt, blockiert sonst):

```bash
swiftc -O -parse-as-library Sources/RsyncBackupApp.swift \
  -o /tmp/RsyncBackupDesktop_test \
  -framework SwiftUI -framework AppKit -framework UserNotifications
```

Schneller Compile-Check nach Änderungen: obigen Befehl laufen lassen, Exit 0 =
ok. Für ein echtes App-Bundle `build.command` verwenden.

## Konventionen

- UI-Texte und Kommentare auf **Deutsch**.
- Mindest-Zielsystem: **macOS 13** (`LSMinimumSystemVersion` in `build.command`).
- Bundle-ID: `com.jens.rsyncbackupdesktop`.

## Git

- Commits auf Deutsch, Co-Author-Trailer für Claude anhängen.
- `.app`-Bundle und `.DS_Store` bleiben ungetrackt.
- **Vor jedem Push:** `CLAUDE.md`, `NOTIZEN.md` und `ANLEITUNG.md` auf den
  aktuellen Stand bringen (neue Features, letzter Commit-Hash, Änderungen an
  Struktur/Build). Alle drei Dateien im selben Commit mitschicken.
