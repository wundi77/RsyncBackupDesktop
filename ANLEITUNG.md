# rsync Backup Desktop – Fenster-App

Eine kleine macOS-App mit normalem Fenster und Dock-Icon. Du wählst eine Quelle und ein Ziel und startest damit ein rsync-Backup mit genau deinem Befehl:

```
rsync -ahP --delete --ignore-errors --stats  <Quelle>/  <Ziel>
```

Das Backup läuft direkt in der App; der Fortschritt wird unten als Statuszeile angezeigt.

> Es gibt auch eine reine **Menüleisten-Variante** ohne Dock-Icon:
> [`wundi77/RsyncBackup`](https://github.com/wundi77/RsyncBackup). Beide
> Apps können parallel installiert sein.

## Einrichten (einmalig)

1. Stelle sicher, dass die **Command Line Tools** installiert sind. Falls nicht, im Terminal:

   ```
   xcode-select --install
   ```

2. Hole den aktuellen Code aus Git (falls noch nicht vorhanden):

   ```
   git clone https://github.com/wundi77/RsyncBackupDesktop.git
   cd RsyncBackupDesktop
   ```

   Oder bei vorhandenem Ordner einfach:

   ```
   git pull
   ```

3. Doppelklick auf **`build.command`** in diesem Ordner.
   - Beim ersten Mal blockiert macOS evtl. die Ausführung. Dann: Rechtsklick auf `build.command` → **Öffnen** → **Öffnen** bestätigen.
   - Das Skript erzeugt automatisch das App-Icon, kompiliert die App und legt **`RsyncBackupDesktop.app`** in diesem Ordner ab.

4. Verschiebe **`RsyncBackupDesktop.app`** nach `/Programme` (optional, empfohlen) und starte sie per Doppelklick.
   - Beim ersten Start ggf. wieder Rechtsklick → **Öffnen**, da die App nicht über den App Store signiert ist.

## Benutzen

- Die App öffnet sich als schwebendes, randloses Fenster (mit Dock-Icon) —
  nur eine durchgängige, abgerundete Fläche, keine dicke Titelleiste.
- Oben rechts schaltet ein dezenter Mond-/Sonnen-Button zwischen **Dark**- und
  **Light Mode** um, unabhängig von der Systemeinstellung.
- Wähle **Quelle** und **Ziel** über „Wählen…", tippe/füge den Pfad direkt ins
  Textfeld ein, oder ziehe einen **Ordner oder ein Volume** (z. B. aus dem
  Finder oder vom Schreibtisch) direkt in das jeweilige Feld.
- Klicke **Backup starten**. Während es läuft, kannst du **Pause** drücken
  (hält rsync an, ohne abzubrechen) und mit **Fortsetzen** weitermachen – oder
  jederzeit **Abbrechen**.
- Die zuletzt gewählten Pfade werden gemerkt.
- Zum Beenden: rotes Schließen-Kreuz oder ⌘Q (normales macOS-Fensterverhalten).

## Profile

Du kannst mehrere **Profile** (benannte Quelle/Ziel-Paare) anlegen und oben per
Auswahlmenü umschalten:

- **+** legt ein neues Profil an, **🗑** löscht das aktuelle (das letzte bleibt).
- Den Namen änderst du direkt im Textfeld unter der Auswahl.
- Jedes Profil merkt sich seine eigene Quelle und sein eigenes Ziel.

## Testlauf (Dry-Run)

Aktiviere **„Testlauf"**, um zu sehen, *was* das Backup tun würde – ohne dass
etwas verändert oder gelöscht wird (rsync `-n`). Gerade wegen `--delete` ein
guter Sicherheitscheck vor dem echten Lauf.

## Protokoll und Fehler

Klappe **„Protokoll"** auf, um nach Abschluss eine kurze, verständliche
Zusammenfassung zu sehen (z. B. Anzahl übertragener Dateien, Datenmenge,
Dauer) statt der vollen, oft langen rsync-Rohausgabe.

Darunter gibt es **„Fehler"** – zeigt bei Problemen den rsync-Fehlercode mit
Klartext-Erklärung (z. B. „Fehlercode 23: Einige Dateien/Attribute konnten
nicht übertragen werden"). Steht dort „— keine Fehler —", lief alles sauber
durch.

Das **vollständige** Protokoll (inkl. aller Fehlermeldungen) wird bei jedem
Lauf automatisch als Textdatei auf deinem **Schreibtisch** gespeichert
(`RsyncBackup-<Profilname>-<Datum_Uhrzeit>.txt`) – dort kannst du bei Bedarf
alle Details nachlesen.

## Mitteilung wenn fertig

Aktiviere **„Mitteilung wenn fertig"**, damit macOS dir eine Mitteilung zeigt,
sobald ein Backup abgeschlossen ist oder fehlschlägt. Beim ersten Einschalten
fragt macOS einmalig nach der Erlaubnis.

## Autostart

Im Fenster gibt es den Schalter **„Beim Login automatisch starten"**. Aktiviere ihn einmal – die App registriert sich dann selbst als Anmeldeobjekt und öffnet sich bei jedem Neustart automatisch mit ihrem Fenster. (Benötigt macOS 13 oder neuer.)

## Hinweise

- Der Quellpfad wird automatisch mit einem `/` am Ende versehen, damit – wie bei rsync üblich – der **Inhalt** der Quelle in das Ziel abgeglichen wird (nicht der Quellordner selbst hinein).
- `--delete` entfernt im Ziel Dateien, die in der Quelle nicht mehr existieren. Achte darauf, das richtige Ziel zu wählen.
