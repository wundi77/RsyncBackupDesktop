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

### Update 2026-07-13: Aufklapp-Pfeil sichtbar machen, kein Auto-Fokus im Profilname-Feld

Zwei Nachbesserungen aus dem Chat:

1. **Aufklapp-Pfeil der Profilauswahl kaum sichtbar** (in beiden Modi zu
   ähnliche Farbe zum Hintergrund): Der native `Picker`-Pfeil lässt sich über
   SwiftUI nicht gezielt einfärben, daher wurde die Profilauswahl von
   `Picker` auf `Menu` umgebaut — mit eigenem Label aus `Text` (Profilname,
   `pickerTextFarbe`) und `Image(systemName: "chevron.up.chevron.down")` in
   fester Mittelgrau-Farbe `Color(white: 0.5)` (neue Eigenschaft
   `ContentView.pfeilFarbe`, bewusst gleich in Dark und Light Mode, da
   Mittelgrau sich von beiden Kartenhintergründen ausreichend abhebt).
   Funktional identisch zum bisherigen Picker (Profil auswählen, `.tag`
   ersetzt durch `Button`-Aktionen je Profil im Menu).
2. **Profilname-Textfeld hatte beim App-Start automatisch den Fokus**
   (blinkender Cursor, ohne dass man hineingeklickt hat) — typisches macOS-
   Verhalten, dass das erste Textfeld im Fenster automatisch zum First
   Responder wird. Fix in `WindowAccessor`: `window.makeFirstResponder(nil)`
   wird jetzt zusätzlich zu den anderen Fenstereinstellungen aufgerufen —
   einmal sofort und sicherheitshalber nochmal nach 0,05 s (falls SwiftUI den
   Fokus erst mit leichter Verzögerung selbst setzt).

Ungetestet (kein `swiftc` in dieser Sitzung) — auf dem Mac prüfen: Pfeil im
Menu sollte in beiden Modi gut sichtbar sein, Profilname-Feld sollte beim
Start ohne blinkenden Cursor erscheinen und erst nach Klick hineinfokussieren.
Falls der Fokus doch noch kurz aufblitzt, müsste die Verzögerung in
`WindowAccessor` (aktuell 0,05 s) ggf. erhöht werden.

### Update 2026-07-15: Karten-Redesign nach Screenshot-Vorlage

Nutzer hat einen Screenshot mit einem neuen Layout-Vorschlag (Light + Dark)
geschickt: einzelne umrandete Karten statt gemeinsamer `.quaternary`-Flächen,
größere abgerundete Buttons, Profil-Menu/-Name/Quelle/Ziel/Protokoll/Fehler
jeweils als eigene Box. Rückfrage zur Akzentfarbe (Screenshot zeigt Blau,
bisher bewusst Grün gewählt) — Nutzer hat sich für **Grün beibehalten**
entschieden, nur das Layout wurde aus dem Screenshot übernommen.

- **Neue Karten-Optik**: Jedes Element (Profil-Menu, Profilname-Feld, Quelle,
  Ziel, Protokoll, Fehler) ist jetzt eine eigenständige Karte mit dünnem
  Rahmen (`RoundedRectangle` + `strokeBorder`, Radius 10–14) statt der
  bisherigen gemeinsamen `.quaternary`-Hintergrundfläche pro Abschnitt.
  Farben kommen aus zwei neuen `ContentView`-Eigenschaften: `kartenFuellung`
  (Light: Weiß, Dark: dunkles Grau `0.12/0.12/0.13`) und `kartenRahmen`
  (Light: `Color(white: 0.87)`, Dark: `Color(white: 0.24)`).
- **Neuer Fensterhintergrund**: `fensterHintergrund` /
  `ContentView.fensterHintergrundNSColor(isDarkMode:)` liefert ein dezentes
  Warmgrau (Light) bzw. Beinahe-Schwarz (Dark) statt des bisherigen
  `.windowBackgroundColor`. `WindowAccessor` bekommt dafür einen
  `isDarkMode`-Parameter und setzt die Fensterfarbe jetzt auch in
  `updateNSView` (nicht mehr nur einmalig in `makeNSView`), damit der native
  Fensterhintergrund beim Dark/Light-Umschalten mitzieht.
- **`PfadZeile`** (Quelle/Ziel) ist jetzt selbst eine Karte mit farbigem
  Icon-Quadrat, Großbuchstaben-Label (`QUELLE`/`ZIEL`), größerem Pfadtext, X-
  Button als umrandeter Kreis und „Wählen…" als gefüllter Pill-Button.
- **Neue Button-Stile**: `PillButtonStyle` (Kapsel, „Wählen…"),
  `StartButtonStyle` (vollbreiter Start-Button, abgedimmt wenn deaktiviert),
  `IconButtonStyle` (quadratisch umrandet, für „+"/Papierkorb).
- **Testlauf-Toggle** nutzt jetzt `.toggleStyle(.checkbox)` (Kästchen statt
  Schalter), passend zur Vorlage; Autostart/Mitteilung bleiben normale
  Schalter, jetzt ohne umgebende Karte (frei stehend wie im Screenshot).
- Protokoll/Fehler sind zwei getrennte Karten statt einer gemeinsamen Box mit
  Divider dazwischen.

Rein optischer Umbau — keine Funktionalität verändert (Backup-Logik,
rsync-Aufruf, Profile, Drag & Drop, Fortschrittsbalken, Update-Hinweis-
Overlay etc. unverändert). Ungetestet (kein `swiftc` in dieser Sitzung) —
auf dem Mac in beiden Modi prüfen, ob Kartenränder/-abstände gut aussehen
und der Dark/Light-Wechsel den Fensterhintergrund sauber mitzieht.

### Update 2026-07-15 (Nachbesserung): Fenstergröße, kein Autostart mehr, Mitteilungs-Schalter als Switch

Rückmeldung nach dem ersten Test des Karten-Redesigns (Screenshot beigefügt):
Beim erneuten Öffnen der App war das Fenster zu klein — oben ragte der
Dark-Mode-Button über den Rand hinaus, unten fehlten die Buttons (nur durch
manuelles Aufziehen sichtbar).

- **Fenstergröße erhöht**: `minWidth`/`minHeight` von `430`/`480` auf
  `440`/`640` angehoben (`idealWidth: 500, idealHeight: 680`). Da AppKit die
  Fenstergröße nie unter das gesetzte Minimum lässt — auch nicht bei einer
  von macOS gespeicherten kleineren Fenstergröße aus einer früheren Sitzung
  —, kann das Fenster jetzt nicht mehr kleiner als nötig starten und Inhalte
  abschneiden.
- **Autostart komplett entfernt**: Der Schalter „Beim Login automatisch
  starten" fällt auf Wunsch weg — die App soll immer nur von Hand gestartet
  werden. Dazu wurde nicht nur der UI-Toggle entfernt, sondern der komplette
  zugehörige Code: `BackupManager.launchAtLogin`,
  `BackupManager.toggleLaunchAtLogin(_:)`, der `SMAppService`-Aufruf in
  `init()`, der `import ServiceManagement`, sowie das
  `-framework ServiceManagement` in `build.command`/`CLAUDE.md`.
- **Mitteilung wenn fertig als echter Schiebeschalter**: `Toggle(...)`
  bekommt jetzt explizit `.toggleStyle(.switch)`, damit unabhängig vom
  Kontext sicher ein Schiebeschalter (0/1, links/rechts) statt einer
  Checkbox angezeigt wird. Der Testlauf-Toggle bleibt bewusst eine Checkbox
  (`.toggleStyle(.checkbox)`).

Ungetestet (kein `swiftc` in dieser Sitzung) — auf dem Mac prüfen: App nach
mehrfachem Neustart öffnet sich immer groß genug (keine abgeschnittenen
Buttons mehr), kein Autostart-Schalter mehr sichtbar, „Mitteilung wenn
fertig" zeigt einen Schiebeschalter statt einer Checkbox.

### Update 2026-07-15 (weitere Nachbesserung): Leerraum reduziert, Dark/Light-Icon-Logik gedreht

Screenshot der Nachbesserung zeigte: Das (bewusst großzügig bemessene)
Fenster ließ oben zwischen den drei Ampel-Punkten und dem Dark-Mode-Button
sowie unten unterhalb des Mitteilungs-Schalters deutlich zu viel Leerraum.

- **Fenstergröße verkleinert**: `minHeight`/`idealHeight` von `640`/`680` auf
  `560`/`590` reduziert — näher am tatsächlichen Platzbedarf des Inhalts nach
  dem Wegfall des Autostart-Schalters.
- **Padding aufgeteilt**: statt einheitlichem `.padding(20)` jetzt
  `.padding(.horizontal, 20)`, `.padding(.top, 12)`, `.padding(.bottom, 14)`
  — die Dark-/Light-Mode-Zeile beginnt dadurch näher an der System-Ampel.
- **Vertikale Ausrichtung**: äußere `.frame(maxWidth: .infinity, maxHeight:
  .infinity)` hat jetzt `alignment: .top`, damit übrig bleibende Höhe (z. B.
  wenn der Nutzer das Fenster von Hand größer zieht) unten statt mittig
  landet — vorher zentrierte SwiftUI den Inhalt vertikal, was bei einem zu
  groß bemessenen Fenster den auffälligen Leerraum oben *und* unten erzeugte.
- **Dark/Light-Icon-Logik gedreht**: Der Button zeigt jetzt das Symbol des
  Modus, in den man wechseln *würde*, nicht den aktuell aktiven — im Dark
  Mode also eine Sonne (☀️, Wechsel zu Light), im Light Mode einen Mond (🌙,
  Wechsel zu Dark). Vorher war es umgekehrt (zeigte den aktuellen Modus).

Ungetestet (kein `swiftc` in dieser Sitzung) — auf dem Mac prüfen, ob der
Leerraum oben/unten jetzt angemessen wirkt und ob die Icon-Logik (Sonne im
Dark Mode, Mond im Light Mode) wie gewünscht ankommt.

## Bekannte Einschränkungen

- `rsync --delete` ist auf dem **Ziel destruktiv** – vor dem ersten echten Lauf
  Testlauf nutzen.
- **Web-Sitzung läuft in einer Linux-Cloud**: Code bearbeiten/prüfen ist ok,
  aber die fertige `.app` wird **lokal auf dem Mac** gebaut und gestartet.
