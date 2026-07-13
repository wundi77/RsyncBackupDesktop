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
rsync-Backups ausführt. Geschrieben in **SwiftUI + AppKit + ServiceManagement**.
Kein Xcode-Projekt — Build läuft direkt über `swiftc`.

**Abstammung:** Dieses Projekt ist eine Fenster-Variante von
[`wundi77/RsyncBackup`](https://github.com/wundi77/RsyncBackup), das als
reine Menüleisten-App ohne Dock-Icon läuft. Beide Repos teilen sich die
identische Backup-Logik (`BackupManager`), unterscheiden sich nur im
App-Gerüst: hier `WindowGroup` statt `MenuBarExtra`, kein `LSUIElement`.
Funktions-Updates ggf. in beiden Repos parallel nachziehen.

Der ausgeführte Befehl ist fest verdrahtet:

```
rsync -ahP --delete --ignore-errors --stats <Quelle>/ <Ziel>
```

`--stats` liefert am Laufende einen auswertbaren Zusammenfassungsblock
(Dateianzahl, übertragene Datenmenge), der für die Kurzanzeige in der App
geparst wird (siehe `buildSummaries` in `BackupManager`).

## Struktur

- `Sources/RsyncBackupApp.swift` — **gesamter Code in einer Datei**:
  - `BackupProfile` (`Codable`): benanntes Quelle/Ziel-Paar.
  - `BackupManager` (`@MainActor`, `ObservableObject`): Logik. Verwaltet eine
    Liste von Profilen (als JSON in `UserDefaults`, Key `profiles`), startet
    rsync als `Process`, liest die Ausgabe live über einen
    `Pipe`-`readabilityHandler`, Autostart via `SMAppService` (macOS 13+),
    Fertig-Mitteilung via `UNUserNotificationCenter`. Migriert beim ersten
    Start alte `source`/`destination`-Keys in ein Standardprofil.
  - `PfadZeile`: Hilfs-View für Quelle/Ziel-Zeilen mit Ordner-Icon. Unterstützt
    Drag & Drop von Ordnern/Volumes (`.onDrop(of: [.fileURL], ...)`), prüft per
    `FileManager.fileExists(isDirectory:)`, ob das gedropte Element ein Ordner
    ist, und zeigt beim Drag-Over eine farbige Umrandung als Feedback.
  - `StatusPunkt`: farbiger Kreis (grün/gelb/rot/grau) für den Backup-Zustand.
  - `ContentView`: das SwiftUI-Hauptfenster (Profil wählen/anlegen/löschen/
    umbenennen, Quelle/Ziel wählen, Testlauf-Toggle, Start/Abbrechen,
    ausklappbare Protokoll-/Fehler-Zusammenfassung, Autostart- und
    Mitteilungs-Toggle).
  - `WindowAccessor`: `NSViewRepresentable`, greift auf das `NSWindow` zu und
    macht nur die Titelleiste transparent/titellos
    (`titlebarAppearsTransparent`, `titleVisibility = .hidden`) und aktiviert
    `isMovableByWindowBackground`. Das Fenster bleibt vollständig blickdicht
    (keine Fenster-Transparenz, kein Custom-Schatten) — der reguläre
    Fensterhintergrund füllt durchgängig die ganze Fläche.
  - `RsyncBackupDesktopApp`: Einstiegspunkt, `WindowGroup` (ohne Titel-String)
    mit `ContentView` als Inhalt, `.windowResizability(.contentSize)`,
    `.windowStyle(.hiddenTitleBar)`.
- `make_icon.swift` — Swift-Skript (läuft auf dem Mac beim Build): zeichnet
  alle Icon-Größen (16–1024 px) als PNG in `AppIcon.iconset/`, blauer
  Verlauf + SF Symbol `externaldrive.badge.timemachine` in Weiß.
- `build.command` — Doppelklick-Build: ruft `swift make_icon.swift` +
  `iconutil` auf, kompiliert, baut `.app`-Bundle, schreibt `Info.plist`,
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
  fragt beim Einschalten nach Erlaubnis), zusätzlich Systemsound.
- **Autostart**: „Beim Login automatisch starten" via `SMAppService`
  (macOS 13+) — startet die App normal (mit Fenster/Dock-Icon), kein
  Hintergrundstart wie bei der Menüleisten-Variante.

## UI-Stil

- **Akzentfarbe**: kräftiges, nicht grelles Grün `Color.backupAccent`
  (`Color(red: 0.25, green: 0.62, blue: 0.33)`) statt System-Blau — via
  `.tint(Color.backupAccent)` auf der Wurzel-View, greift auf Buttons,
  Toggles, Picker und `ProgressView`. Auch der laufende `StatusPunkt` nutzt
  dieses Grün.
- **Dark/Light-Umschalter**: dezenter Kreis-Button oben rechts
  (Mond-/Sonnen-Symbol), toggelt `@AppStorage("isDarkMode")` und wird über
  `.preferredColorScheme(...)` auf die ganze App angewendet. Default: Dark.
- **Kein Fenstertitel, keine dicke Titelleiste**: `WindowAccessor` blendet nur
  Titeltext/-leiste aus (`.windowStyle(.hiddenTitleBar)`); das Fenster selbst
  bleibt vollständig blickdicht (keine Transparenz, kein Custom-Schatten) —
  der reguläre, durchgängige Fensterhintergrund (`Color(nsColor:
  .windowBackgroundColor)`) füllt die komplette Fläche. Die System-Ampel
  (Schließen/Minimieren/Zoomen) steht dadurch einfach frei auf dieser Fläche,
  ohne sichtbare Menüleiste darüber.
- Picker-Einträge (Profilauswahl) haben eine explizite helle Grau-Textfarbe
  (`Color(white: 0.85)`), da das native Dropdown-Menü im Dark Mode sonst
  schwer lesbaren dunklen Text zeigen kann.
- Sektionen (Profil, Pfade, Protokoll/Fehler, Einstellungen) in abgerundeten
  Hintergrundkarten (`.quaternary`, `RoundedRectangle(cornerRadius: 8)`).
- Farbiger `StatusPunkt` vor der Statuszeile.
- Start-Button vollbreit, `.borderedProminent` + `.large`.
- Fenster: `minWidth: 430, idealWidth: 480, minHeight: 480, idealHeight: 560`,
  frei skalierbar (kein fixes `.frame(width:)` wie in der Menüleisten-Variante).

## Bauen

Doppelklick auf `build.command`, ODER direkt kompilieren (ohne den
interaktiven `read`-Schritt, blockiert sonst):

```bash
swiftc -O -parse-as-library Sources/RsyncBackupApp.swift \
  -o /tmp/RsyncBackupDesktop_test \
  -framework SwiftUI -framework AppKit -framework ServiceManagement \
  -framework UserNotifications
```

Schneller Compile-Check nach Änderungen: obigen Befehl laufen lassen, Exit 0 =
ok. Für ein echtes App-Bundle `build.command` verwenden.

## Konventionen

- UI-Texte und Kommentare auf **Deutsch**.
- Mindest-Zielsystem: **macOS 13** (`LSMinimumSystemVersion` in `build.command`,
  Autostart-Code mit `#available(macOS 13.0, *)` abgesichert).
- Bundle-ID: `com.jens.rsyncbackupdesktop`.

## Git

- Commits auf Deutsch, Co-Author-Trailer für Claude anhängen.
- `.app`-Bundle und `.DS_Store` bleiben ungetrackt.
- **Vor jedem Push:** `CLAUDE.md`, `NOTIZEN.md` und `ANLEITUNG.md` auf den
  aktuellen Stand bringen (neue Features, letzter Commit-Hash, Änderungen an
  Struktur/Build). Alle drei Dateien im selben Commit mitschicken.
