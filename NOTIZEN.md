# Notizen / Arbeitsstand & Übergabe

Roter Faden zwischen Sitzungen und Rechnern (lokal *und* Weboberfläche). Der
Claude-Chatverlauf synct **nicht** über Geräte – darum stehen alle wichtigen
Infos zum Weiterarbeiten hier und werden mit Git mitgesichert.

> **Gerätewechsel:** vorher `git push`, nachher `git pull`.
> **Sitzungsende:** diese Datei kurz aktualisieren und mitcommitten.
> **Neue Sitzung (z. B. im Web):** als ersten Prompt „Lies CLAUDE.md und
> NOTIZEN.md und fass den aktuellen Stand zusammen."

---

## Was das Projekt ist

Eine **macOS-Desktop-App mit normalem Fenster und Dock-Icon**, die
rsync-Backups ausführt. **SwiftUI + AppKit + ServiceManagement +
UserNotifications**. **Kein Xcode-Projekt** — Build läuft direkt über `swiftc`.

**Schwester-Projekt:** [`wundi77/RsyncBackup`](https://github.com/wundi77/RsyncBackup)
ist die reine Menüleisten-Variante (kein Dock-Icon, `MenuBarExtra`,
`LSUIElement`). Beide teilen sich dieselbe Backup-Logik, unterscheiden sich
nur im App-Gerüst. Am 2026-07-09 aus `RsyncBackup` dupliziert und auf
`WindowGroup` umgestellt.

Fest verdrahteter Befehl:

```
rsync -ahP --delete --ignore-errors --stats  <Quelle>/  <Ziel>
```

(Bei Testlauf wird `-n` angehängt. `--stats` liefert den Zusammenfassungsblock
für die Kurzanzeige in der App.)

## Wichtige Dateien

- `Sources/RsyncBackupApp.swift` — **gesamter Code in einer Datei**
  (`BackupProfile`, `BackupManager`, `PfadZeile`, `StatusPunkt`,
  `ContentView`, `RsyncBackupDesktopApp`).
- `make_icon.swift` — Swift-Skript, erzeugt beim Build das App-Icon
  (blauer Verlauf + SF Symbol in Weiß, alle Größen für `iconutil`).
- `build.command` — Doppelklick-Build: Icon erzeugen → kompilieren →
  `.app`-Bundle bauen → `Info.plist` schreiben → ad-hoc signieren.
- `CLAUDE.md` — Projektnotizen für Claude (Struktur, Build, Konventionen).
- `ANLEITUNG.md` — Endnutzer-Anleitung (deutsch).
- `NOTIZEN.md` — diese Datei: Arbeitsstand & Übergabe.
- `RsyncBackupDesktop.app/` — Build-Ergebnis, **nicht versioniert** (`.gitignore`).

## Neu starten auf einem anderen Rechner

```bash
git clone https://github.com/wundi77/RsyncBackupDesktop.git
cd RsyncBackupDesktop
# Doppelklick auf build.command  ODER:
bash build.command
```

## Bauen

Echtes App-Bundle: Doppelklick auf `build.command`.

Schneller Compile-Check nach Änderungen (Exit 0 = ok, nur auf macOS):

```bash
swiftc -O -parse-as-library Sources/RsyncBackupApp.swift \
  -o /tmp/RsyncBackupDesktop_test \
  -framework SwiftUI -framework AppKit -framework ServiceManagement \
  -framework UserNotifications
```

## Konventionen

- UI-Texte und Kommentare auf **Deutsch**.
- Mindest-Zielsystem **macOS 13** (Autostart mit `#available(macOS 13.0, *)`).
- Bundle-ID `com.jens.rsyncbackupdesktop`.
- Commits auf **Deutsch**, mit Co-Author-Trailer für Claude.
- `.app`-Bundle und `.DS_Store` bleiben ungetrackt.

---

## Aktueller Stand (2026-07-09)

Erstversion: Duplikat von `RsyncBackup` (Menüleisten-App), umgebaut auf
normales Fenster mit Dock-Icon.

### Unterschiede zur Menüleisten-Variante (`wundi77/RsyncBackup`)

- `WindowGroup` statt `MenuBarExtra`, `ContentView` statt `MenuContent`.
- Kein `LSUIElement` in der `Info.plist` → Dock-Icon vorhanden.
- Fenster frei skalierbar (`minWidth`/`idealWidth`/`minHeight`/`idealHeight`
  statt fixer `.frame(width: 430)`), `.windowResizability(.contentSize)`.
- „Beenden"-Button entfernt (normale Fenster-Apps haben rotes Schließen-Kreuz
  und ⌘Q, kein eigener Menüpunkt nötig).
- Bundle-ID `com.jens.rsyncbackupdesktop`, App-Name `RsyncBackupDesktop.app`.
- Ansonsten identische Backup-Logik (`BackupManager` 1:1 übernommen):
  Profile, Testlauf, Pause/Fortsetzen, Protokoll-/Fehler-Zusammenfassung,
  Log-Datei auf dem Schreibtisch, Mitteilung + Sound bei Fertigstellung,
  Autostart, editierbare Pfadfelder, modernes Karten-UI, App-Icon.

### Letzter Commit

Erstcommit (2026-07-09) – Duplikat von RsyncBackup, umgebaut auf Fenster-App

## Offene Ideen / mögliche nächste Schritte

- Funktions-Updates aus `RsyncBackup` bei Bedarf hier nachziehen (kein
  automatischer Sync zwischen den Repos).

### Update 2026-07-09: Drag & Drop für Quelle/Ziel

`PfadZeile` (in `Sources/RsyncBackupApp.swift`) akzeptiert jetzt per
`.onDrop(of: [.fileURL], isTargeted:)` gedroppte Ordner/Volumes (z. B. aus
dem Finder) und übernimmt deren Pfad direkt ins Textfeld. Dateien werden
per `FileManager.fileExists(isDirectory:)`-Prüfung verworfen. Beim
Drag-Over zeigt das Feld eine farbige Umrandung (`Color.accentColor`) als
visuelles Feedback. Import `UniformTypeIdentifiers` neu hinzugekommen.

**Wichtig:** Kompiliert wurde dies in einer Linux-Cloud-Sitzung ohne
`swiftc` — der übliche Compile-Check (`swiftc -parse-as-library …`) konnte
hier nicht ausgeführt werden. Vor dem produktiven Einsatz auf einem Mac
gegenprüfen.

## Bekannte Einschränkungen

- `rsync --delete` ist auf dem **Ziel destruktiv** – vor dem ersten echten Lauf
  Testlauf nutzen.
- **Web-Sitzung läuft in einer Linux-Cloud**: Code bearbeiten/prüfen ist ok,
  aber die fertige `.app` wird **lokal auf dem Mac** gebaut und gestartet.
