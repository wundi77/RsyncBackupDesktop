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
rsync -ah --partial --info=progress2 --delete --ignore-errors --stats  <Quelle>/  <Ziel>
```

(Bei Testlauf wird `-n` angehängt. `--stats` liefert den Zusammenfassungsblock
für die Kurzanzeige in der App. `--info=progress2` liefert den
Gesamtfortschritt über alle Dateien für den Fortschrittsbalken — seit
2026-07-13 statt des ursprünglichen `-P`, das nur den Fortschritt der
aktuellen Einzeldatei zeigte.)

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
Drag-Over zeigt das Feld eine farbige Umrandung als visuelles Feedback
(seit dem Redesign unten in `Color.backupAccent`, vorher `Color.accentColor`).
Import `UniformTypeIdentifiers` neu hinzugekommen.

### Update 2026-07-13: Redesign — Grüner Akzent, Dark/Light-Toggle, schwebendes Fenster

Auf Wunsch an einem Screenshot orientiert (dunkles Wallet-UI), aber mit
gedämpftem Grün statt Orange als Signalfarbe:

- **Neue Akzentfarbe** `Color.backupAccent` (`Color(red: 0.42, green: 0.72,
  blue: 0.55)`), per `.tint(...)` auf der Wurzel-View gesetzt — färbt Buttons,
  Toggles, Picker, `ProgressView` und den laufenden `StatusPunkt`.
- **Dark/Light-Umschalter**: dezenter Kreis-Button oben rechts (Mond-/
  Sonnen-Symbol), speichert in `@AppStorage("isDarkMode")` (Default: Dark),
  angewendet über `.preferredColorScheme(...)`.
- **„rsync Backup"-Überschrift entfernt** — die Titelzeile ist komplett weg,
  an ihrer Stelle steht nur noch die Zeile mit dem Dark/Light-Button.
- **Schwebender Look**: `ContentView` ist jetzt in ein `ZStack` gepackt, das
  eine abgerundete Karte (`RoundedRectangle(cornerRadius: 20)`, Füllung
  `Color(nsColor: .windowBackgroundColor)`, eigener `.shadow(...)`) über den
  gesamten Fensterinhalt legt. Ein neuer `WindowAccessor`
  (`NSViewRepresentable`) macht dazu das `NSWindow` transparent
  (`isOpaque = false`, `backgroundColor = .clear`), blendet Titelleiste und
  Titeltext aus (`titlebarAppearsTransparent`, `titleVisibility = .hidden`),
  deaktiviert den nativen Fensterschatten (`hasShadow = false`, den übernimmt
  die Karte) und erlaubt `isMovableByWindowBackground`. Die `WindowGroup` hat
  keinen Titel-String mehr und nutzt `.windowStyle(.hiddenTitleBar)`. Die
  System-Ampel (Schließen/Minimieren/Zoomen) bleibt erhalten, wirkt aber
  dezent statt in einer dicken Menüleiste.

**Wichtig:** Auch dieses Redesign wurde in einer Linux-Cloud-Sitzung ohne
`swiftc` umgesetzt — kein Compile-Check möglich.

### Update 2026-07-13 (Korrektur nach erstem Test): keine Fenster-Transparenz mehr, kräftigeres Grün, hellere Picker-Schrift

Rückmeldung nach dem ersten Test: die transparente/schwebende Karten-Optik
war nicht gewünscht — das Fenster soll stattdessen ganz normal blickdicht
sein, nur eben ohne Titeltext/dicke Titelleiste.

- `WindowAccessor` macht jetzt **nur noch** die Titelleiste transparent/
  titellos (`titlebarAppearsTransparent`, `titleVisibility = .hidden`) —
  `isOpaque`, `backgroundColor` und `hasShadow` werden nicht mehr angefasst,
  das Fenster bleibt also vollständig undurchsichtig mit normalem
  Fensterschatten.
- `ContentView` hat kein `ZStack`/`RoundedRectangle`/`.shadow` mehr; der
  Hintergrund ist einfach `Color(nsColor: .windowBackgroundColor)` über die
  volle Fenstergröße (`.frame(maxWidth: .infinity, maxHeight: .infinity)`).
  Die System-Ampel steht dadurch frei auf der durchgängigen dunklen/hellen
  Fläche, ohne sichtbares Menüleisten-Rechteck darüber.
- `Color.backupAccent` kräftiger/grüner gemacht:
  `Color(red: 0.25, green: 0.62, blue: 0.33)` (vorher zu mintfarben).
- Die `Text`-Einträge im Profil-Picker haben jetzt
  `.foregroundColor(Color(white: 0.85))`, da das native Dropdown-Menü im
  Dark Mode sonst schwer lesbaren dunklen Text zeigte. Testweise umgesetzt —
  bei Bedarf auf dem Mac nachjustieren (Ton/Helligkeit).

Auch diese Korrektur ist ungetestet (kein `swiftc` in dieser Sitzung) — bitte
auf dem Mac gegenprüfen, insbesondere ob die Titelleiste jetzt wirklich
komplett unauffällig ist und die Picker-Textfarbe im Dropdown gut lesbar ist.

### Update 2026-07-13: Bestätigungsdialog, grünes App-Icon, Fortschrittsbalken

- **Bestätigungsdialog vor „Backup starten"**: Neue `BackupManager.sourceLooksEmpty()`
  prüft per `FileManager.contentsOfDirectory`, ob die Quelle leer ist. Klick
  auf „Backup starten" (nicht im Testlauf) zeigt in diesem Fall ein
  `.confirmationDialog` mit der Warnung, dass eine leere Quelle bei aktivem
  `--delete` das komplette Ziel leeren würde — mit „Trotzdem starten"
  (destructive) und „Abbrechen".
- **App-Icon in Grün**: `make_icon.swift` zeichnet den Verlauf jetzt in Grün
  (`0.40/0.78/0.50` → `0.15/0.48/0.24`) statt Blau, passend zu
  `Color.backupAccent`. Wirkt erst nach dem nächsten `build.command`-Lauf
  (Icon wird dort neu erzeugt, nicht separat versioniert).
- **Fortschrittsbalken über die volle Fensterbreite**: `BackupManager` hat
  ein neues `@Published var progress: Double`, befüllt von
  `parseProgress(from:)` — parst per Regex `(\d{1,3})%` die Prozentangabe aus
  der rsync `-P`-Fortschrittszeile (die im Kommando bereits enthalten ist).
  **Wichtig:** Das ist der Fortschritt der *aktuell übertragenen Datei*, kein
  Gesamtfortschritt über den ganzen Job — rsync liefert Letzteres nur mit
  `--info=progress2`, das fest verdrahtete Kommando wurde bewusst nicht
  geändert. `ContentView` zeigt dazu `ProgressView(value: manager.progress)`
  unterhalb der Statuszeile, nur sichtbar während `isRunning`. Der bisherige
  kleine indeterminate Spinner neben Pause/Abbrechen wurde entfernt (durch
  den neuen Balken ersetzt).

Auch dieses Update ist ungetestet (kein `swiftc` in dieser Sitzung) — bitte
auf dem Mac prüfen, ob die Regex zuverlässig greift (rsync-Ausgabeformat kann
je nach Version leicht variieren) und ob der Bestätigungsdialog korrekt
auslöst.

### Update 2026-07-13 (Nachbesserung): echter Gesamtfortschritt statt Einzeldatei

Auf Wunsch wurde der Fortschrittsbalken von "aktuelle Datei" auf "echten
Gesamtfortschritt über den ganzen Backup-Job" umgestellt:

- Das fest verdrahtete rsync-Kommando wurde geändert: `-ahP` →
  `-ah --partial --info=progress2` (`-P` ist eigentlich nur
  `--partial --progress`; `--progress` zeigt Einzeldatei-Fortschritt,
  `--info=progress2` zeigt den Gesamtfortschritt über alle Dateien).
  `--stats` bleibt unverändert erhalten, `buildSummaries` ist davon nicht
  betroffen.
- `BackupManager.parseProgress(from:)`/die Regex selbst mussten nicht
  geändert werden — nur die Bedeutung der geparsten Prozentzahl hat sich
  geändert (jetzt Gesamt- statt Einzeldatei-Fortschritt).

**Wichtig:** Damit weicht das Kommando erstmals bewusst von der ursprünglich
in `CLAUDE.md` als "fest verdrahtet" beschriebenen Form ab (dort ebenfalls
aktualisiert).

Da Apples mitgeliefertes `/usr/bin/rsync` auf vielen Macs noch Version 2.6.9
ist und `--info=progress2` erst ab rsync 3.x existiert, wurde direkt ein
**Kompatibilitäts-Fallback** eingebaut: `BackupManager.unterstuetztProgress2`
prüft einmalig per `rsync --version` die Major-Version. Ist sie < 3, wird
`-P` statt `--info=progress2` verwendet — der Balken zeigt dann wieder nur
den Fortschritt der aktuellen Einzeldatei, aber der Aufruf schlägt nicht mit
„unknown option" fehl.

Ungetestet (kein `swiftc` in dieser Sitzung) — auf dem Mac unbedingt prüfen:
`rsync --version` im Terminal ausführen, um zu sehen, welcher Pfad zutrifft
(Apple-Stock 2.6.9 → Fallback `-P`, Homebrew-rsync 3.x → echtes
`--info=progress2`), und ob die Fortschrittsanzeige in beiden Fällen
funktioniert.

### Update 2026-07-13: Homebrew-rsync bevorzugen + Update-Hinweis-Overlay

Rückfrage im Chat: Nutzer hat noch rsync 2.6.9 und wollte wissen, ob ein
Umstieg auf eine modernere/zukunftssicherere Variante möglich ist. Kurz
recherchiert:

- **openrsync** (BSD-lizenziert, ersetzt Apples rsync ab **macOS Sequoia
  15.4**) ist zwar aktiv gepflegt, unterstützt aber laut Dokumentation
  **kein `--info=progress2`** und nur eine Teilmenge der rsync-Flags — bringt
  also nicht den gewünschten Gesamtfortschritt. Quellen: siehe Chat-Antwort
  (derflounder.wordpress.com, appleinsider.com, ss64.com/mac/openrsync.html).
- Einzige Möglichkeit für echten `--info=progress2`-Support bleibt
  **Homebrew-rsync 3.x** (`brew install rsync`).

Umgesetzt (bewusst die "einfache" Variante ohne gesonderte
openrsync-Behandlung, wie im Chat abgestimmt):

- `BackupManager.rsyncPfad` sucht zuerst `/opt/homebrew/bin/rsync` und
  `/usr/local/bin/rsync` (Apple Silicon bzw. Intel) und nutzt das erste
  gefundene, ausführbare rsync dort; sonst Fallback auf `/usr/bin/rsync`.
  `startBackup()` nutzt jetzt diesen ermittelten Pfad statt hart
  `/usr/bin/rsync`.
- `unterstuetztProgress2` prüft die Version des so ermittelten Pfads (nicht
  mehr fest `/usr/bin/rsync`) — Homebrew-rsync 3.x bekommt also automatisch
  `--info=progress2`.
- **Neu: Update-Hinweis-Overlay.** Bei **jedem** App-Start prüft
  `BackupManager.init()`, ob tatsächlich das System-rsync verwendet wird
  (kein Homebrew-rsync gefunden) *und* dessen Version < 3 ist. Falls ja,
  `rsyncBenötigtUpdate = true` → `ContentView` zeigt ein abgedunkeltes
  Overlay (`RsyncUpdateHinweis`) mit Erklärung und dem Terminal-Befehl
  `brew install rsync` (Text ist per `.textSelection(.enabled)` markierbar).
  „Verstanden" blendet es nur für die aktuelle Sitzung aus, beim nächsten
  Start erscheint es wieder, solange kein neueres rsync installiert ist.

**Wichtig:** Ungetestet (kein `swiftc` in dieser Sitzung). Auf dem Mac
prüfen: Overlay sollte beim Start erscheinen (aktuell hat der Nutzer 2.6.9),
nach `brew install rsync` und Neustart der App sollte es verschwinden und
der Fortschrittsbalken den echten Gesamtfortschritt zeigen.

### Update 2026-07-13: leichte Fenster-Transparenz (90 % Deckkraft)

Auf Wunsch ist das Fenster jetzt nicht mehr komplett blickdicht, sondern
leicht durchscheinend:

- Neue Konstante `ContentView.windowHintergrundDeckkraft = 0.9`.
- `WindowAccessor` setzt zusätzlich `window.isOpaque = false` und
  `window.backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(...)`.
- Die SwiftUI-Hintergrundfarbe von `ContentView` nutzt jetzt
  `.opacity(windowHintergrundDeckkraft)` statt voller Deckkraft — **wichtig**:
  beide Ebenen (NSWindow-Hintergrund *und* SwiftUI-Hintergrund) müssen die
  Transparenz tragen, sonst würde die jeweils andere, undurchsichtige Ebene
  den Effekt komplett verdecken.
- Das Warn-Overlay `RsyncUpdateHinweis` (Update-Hinweis bei altem rsync)
  bleibt bewusst voll deckend, damit die Warnung immer gut lesbar ist.

Ungetestet (kein `swiftc` in dieser Sitzung) — auf dem Mac prüfen, ob 90 %
optisch gut wirkt (leicht durchscheinend, aber Inhalt weiterhin gut lesbar)
oder ob der Wert noch feinjustiert werden sollte.

### Update 2026-07-13: Picker-Textfarbe auch im Light Mode lesbar

Die zuvor fest auf `Color(white: 0.85)` (hellgrau) gesetzte Textfarbe des
Profil-Pickers war im Light Mode kaum zu erkennen (helles Grau auf hellem
Kartenhintergrund) — dieselbe Farbe wurde unverändert für den geschlossenen
Picker *und* das Dropdown-Menü verwendet.

- Neue berechnete Eigenschaft `ContentView.pickerTextFarbe`: Dark Mode
  weiterhin `Color(white: 0.85)`, Light Mode jetzt `Color(white: 0.3)`
  (dunkleres Grau, bewusst kein reines Schwarz).
- Der Picker hat zusätzlich einen eigenen Hintergrund
  (`Color(nsColor: .controlBackgroundColor)`, `RoundedRectangle(cornerRadius: 6)`),
  damit er sich als eigenständiges Element von der `.quaternary`-Kartenfläche
  darunter abhebt statt darin zu verschwinden.

Ungetestet (kein `swiftc` in dieser Sitzung) — auf dem Mac in beiden Modi
prüfen, ob Text und Picker-Hintergrund jetzt gut erkennbar sind, ohne zu
hart (reines Schwarz/Weiß) zu wirken.

## Bekannte Einschränkungen

- `rsync --delete` ist auf dem **Ziel destruktiv** – vor dem ersten echten Lauf
  Testlauf nutzen.
- **Web-Sitzung läuft in einer Linux-Cloud**: Code bearbeiten/prüfen ist ok,
  aber die fertige `.app` wird **lokal auf dem Mac** gebaut und gestartet.
