import SwiftUI
import AppKit
import UserNotifications
import UniformTypeIdentifiers

// MARK: - Farben
// Kräftiges, aber nicht grelles Grün als App-weite Signalfarbe (ersetzt das
// System-Blau als Akzent für Buttons, Toggles und Statushinweise).
extension Color {
    static let backupAccent = Color(red: 0.25, green: 0.62, blue: 0.33)
}

// MARK: - Profil
// Ein Backup-Profil: benanntes Quelle/Ziel-Paar. Mehrere davon werden
// gespeichert und können in der Oberfläche umgeschaltet werden.
struct BackupProfile: Identifiable, Codable, Equatable {
    var id = UUID()
    var name: String
    var source: String = ""
    var destination: String = ""
}

// MARK: - Backup Engine
// Führt rsync im Hintergrund aus und meldet Fortschritt / Ausgabe zurück.
@MainActor
final class BackupManager: ObservableObject {
    @Published var profiles: [BackupProfile] = []
    @Published var selectedProfileID: UUID = UUID()
    @Published var dryRun: Bool = UserDefaults.standard.bool(forKey: "dryRun")
    @Published var notifyOnFinish: Bool = UserDefaults.standard.bool(forKey: "notifyOnFinish")
    @Published var isRunning: Bool = false
    @Published var isPaused: Bool = false
    @Published var progress: Double = 0
    @Published var lastLine: String = "Bereit."
    @Published var log: String = ""
    @Published var errors: String = ""
    @Published var logSummary: String = ""
    @Published var errorSummary: String = ""
    @Published var rsyncBenötigtUpdate: Bool = false

    private var process: Process?
    private var backupStartDate: Date?
    private let profilesKey = "profiles"
    private let selectedKey = "selectedProfileID"

    // Apples mitgeliefertes /usr/bin/rsync ist auf vielen Macs noch Version
    // 2.6.9 (2006, wegen GPLv3-Lizenzwechsel) und kennt kein
    // `--info=progress2` (erst ab rsync 3.x). Falls über Homebrew ein
    // moderneres rsync installiert wurde (typische Pfade), wird das bevorzugt
    // verwendet; sonst wird auf das System-rsync zurückgefallen.
    private static let rsyncPfad: String = {
        for kandidat in ["/opt/homebrew/bin/rsync", "/usr/local/bin/rsync"]
        where FileManager.default.isExecutableFile(atPath: kandidat) {
            return kandidat
        }
        return "/usr/bin/rsync"
    }()

    // Major-Version des tatsächlich verwendeten rsync (per `--version`
    // ermittelt), oder nil, falls das nicht ausgelesen werden konnte.
    private static func rsyncMajorVersion(pfad: String) -> Int? {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: pfad)
        proc.arguments = ["--version"]
        let pipe = Pipe()
        proc.standardOutput = pipe
        do {
            try proc.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            proc.waitUntilExit()
            guard let text = String(data: data, encoding: .utf8),
                  let match = try? NSRegularExpression(pattern: #"version (\d+)\."#)
                    .firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
                  let range = Range(match.range(at: 1), in: text) else { return nil }
            return Int(text[range])
        } catch {
            return nil
        }
    }

    private static let rsyncVersionMajor: Int? = rsyncMajorVersion(pfad: rsyncPfad)

    // Ob das tatsächlich verwendete rsync `--info=progress2` beherrscht
    // (Gesamtfortschritt); sonst wird im Aufruf auf `-P` zurückgefallen.
    private static let unterstuetztProgress2: Bool = (rsyncVersionMajor ?? 0) >= 3

    // Erkennt die Prozent-Angabe aus der rsync `--info=progress2`-Fortschrittszeile
    // (z. B. "1.234.567  45%  12,34MB/s    0:00:03 (xfr#5, to-chk=10/20)") für
    // den Fortschrittsbalken. Dank progress2 ist das der Gesamtfortschritt über
    // alle zu übertragenden Dateien, nicht nur der der aktuellen Einzeldatei.
    private static let percentRegex = try! NSRegularExpression(pattern: #"(\d{1,3})%"#)

    private func parseProgress(from text: String) -> Double? {
        let range = NSRange(text.startIndex..., in: text)
        guard let match = Self.percentRegex.matches(in: text, range: range).last,
              let valueRange = Range(match.range(at: 1), in: text),
              let value = Double(text[valueRange]) else { return nil }
        return min(max(value / 100, 0), 1)
    }

    // Bekannte rsync-Exit-Codes in verständlichem Deutsch (siehe `man rsync`).
    private static let exitCodeDescriptions: [Int32: String] = [
        1: "Syntaxfehler beim rsync-Aufruf",
        2: "Fehler beim Verarbeiten der Protokolloptionen",
        3: "Fehler beim Auswählen von Ein-/Ausgabedateien oder Verzeichnissen",
        4: "Angeforderte Aktion wird von dieser rsync-Version nicht unterstützt",
        5: "Fehler beim Start des Client-Server-Protokolls",
        6: "Fehler beim Loggen (Diskplatz auf dem Log-Empfänger voll)",
        10: "Fehler beim Senden/Empfangen der Daten (Socket-I/O)",
        11: "Fehler beim Lesen/Schreiben von Dateien (Datei-I/O)",
        12: "Fehler im rsync-Protokoll (Datenstrom)",
        13: "Fehler beim Verwalten von Programmdiagnosen",
        14: "Fehler bei IPC-Code",
        20: "Empfangenes Abbruchsignal (SIGUSR1/SIGINT)",
        21: "Fehler eines waitpid()-Aufrufs",
        22: "Fehler beim Anfordern von Arbeitsspeicher",
        23: "Einige Dateien/Attribute konnten nicht übertragen werden (Rechte oder ähnliches)",
        24: "Einige Dateien sind während des Laufs verschwunden (Quelle wurde verändert)",
        25: "Maximale Anzahl an Löschungen erreicht (--max-delete)",
        30: "Zeitüberschreitung bei der Datenübertragung",
        35: "Zeitüberschreitung beim Warten auf den Daemon-Verbindungsaufbau",
    ]

    init() {
        // Standardwerte für neue Installationen: Mitteilungen an.
        UserDefaults.standard.register(defaults: ["notifyOnFinish": true])
        loadProfiles()
        // Bei jedem Start prüfen, ob noch das veraltete System-rsync (2.6.9)
        // zum Einsatz kommt — dann Hinweis-Overlay mit Update-Befehl zeigen.
        if Self.rsyncPfad == "/usr/bin/rsync", (Self.rsyncVersionMajor ?? 0) < 3 {
            rsyncBenötigtUpdate = true
        }
    }

    // MARK: - Profil-Verwaltung

    var selectedProfile: BackupProfile? {
        profiles.first { $0.id == selectedProfileID }
    }

    private func loadProfiles() {
        let d = UserDefaults.standard
        if let data = d.data(forKey: profilesKey),
           let decoded = try? JSONDecoder().decode([BackupProfile].self, from: data),
           !decoded.isEmpty {
            profiles = decoded
            if let idString = d.string(forKey: selectedKey),
               let id = UUID(uuidString: idString),
               decoded.contains(where: { $0.id == id }) {
                selectedProfileID = id
            } else {
                selectedProfileID = decoded[0].id
            }
        } else {
            // Migration: früher gespeicherte Einzel-Pfade in ein Standardprofil
            // übernehmen, sonst leeres Profil anlegen.
            let oldSource = d.string(forKey: "source") ?? ""
            let oldDest = d.string(forKey: "destination") ?? ""
            let p = BackupProfile(name: "Standard", source: oldSource, destination: oldDest)
            profiles = [p]
            selectedProfileID = p.id
            persist()
        }
    }

    func persist() {
        let d = UserDefaults.standard
        if let data = try? JSONEncoder().encode(profiles) {
            d.set(data, forKey: profilesKey)
        }
        d.set(selectedProfileID.uuidString, forKey: selectedKey)
        d.set(dryRun, forKey: "dryRun")
        d.set(notifyOnFinish, forKey: "notifyOnFinish")
    }

    private func updateSelected(_ change: (inout BackupProfile) -> Void) {
        guard let idx = profiles.firstIndex(where: { $0.id == selectedProfileID }) else { return }
        change(&profiles[idx])
        persist()
    }

    func addProfile() {
        let p = BackupProfile(name: "Neues Profil")
        profiles.append(p)
        selectedProfileID = p.id
        persist()
    }

    func deleteSelectedProfile() {
        guard profiles.count > 1,
              let idx = profiles.firstIndex(where: { $0.id == selectedProfileID }) else { return }
        profiles.remove(at: idx)
        selectedProfileID = profiles[max(0, idx - 1)].id
        persist()
    }

    // Komfort-Zugriffe auf das aktuell gewählte Profil (für die UI-Bindings).
    var name: String {
        get { selectedProfile?.name ?? "" }
        set { updateSelected { $0.name = newValue } }
    }
    var source: String {
        get { selectedProfile?.source ?? "" }
        set { updateSelected { $0.source = newValue } }
    }
    var destination: String {
        get { selectedProfile?.destination ?? "" }
        set { updateSelected { $0.destination = newValue } }
    }

    // MARK: - Ordnerauswahl

    // Ordnerauswahl über den nativen Finder-Dialog.
    func chooseFolder(title: String, completion: @escaping (String) -> Void) {
        let panel = NSOpenPanel()
        panel.title = title
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        // App in den Vordergrund holen, damit der Dialog erscheint.
        NSApp.activate(ignoringOtherApps: true)
        if panel.runModal() == .OK, let url = panel.url {
            completion(url.path)
        }
    }

    // Prüft, ob die Quelle keine Einträge enthält. Wichtig als Sicherheitscheck:
    // bei aktivem --delete würde eine (versehentlich) leere Quelle sonst alle
    // Dateien im Ziel löschen, ohne dass das offensichtlich wäre.
    func sourceLooksEmpty() -> Bool {
        (try? FileManager.default.contentsOfDirectory(atPath: source))?.isEmpty ?? false
    }

    // MARK: - Backup

    func startBackup() {
        guard !isRunning else { return }
        guard !source.isEmpty, !destination.isEmpty else {
            lastLine = "Bitte Quelle und Ziel wählen."
            return
        }

        persist()
        log = ""
        errors = ""
        logSummary = ""
        errorSummary = ""
        backupStartDate = Date()
        isRunning = true
        isPaused = false
        progress = 0
        lastLine = dryRun ? "Testlauf läuft …" : "Backup läuft …"

        // rsync mit deinen Optionen. Quellpfad endet auf "/" damit der INHALT
        // der Quelle abgeglichen wird (rsync-Konvention).
        var src = source
        if !src.hasSuffix("/") { src += "/" }

        // --stats liefert am Ende einen auswertbaren Zusammenfassungsblock
        // (Dateianzahl, übertragene Datenmenge) für die verständliche Anzeige.
        // --info=progress2 (nur ab rsync 3.x) zeigt den Gesamtfortschritt über
        // alle Dateien für den Fortschrittsbalken; auf altem rsync (Apples
        // mitgeliefertes 2.6.9) fällt es auf -P zurück (Fortschritt der
        // aktuellen Einzeldatei statt Gesamtfortschritt).
        var args = ["-ah", "--partial"]
        args.append(Self.unterstuetztProgress2 ? "--info=progress2" : "-P")
        if Self.unterstuetztProgress2 {
            // Ohne dieses Flag baut rsync (ab Version 3) die Dateiliste
            // "inkrementell" auf, d. h. es entdeckt Unterordner erst während
            // der laufenden Übertragung. Dadurch kann die für den
            // Fortschrittsbalken gemeldete Gesamtgröße mittendrin ansteigen,
            // was den Balken kurzzeitig zurückspringen lässt. Mit
            // --no-inc-recursive baut rsync die komplette Dateiliste vorher
            // auf, wodurch der Balken sauber und monoton von 0 auf 100 %
            // läuft (Kompromiss: der erste Fortschritt erscheint bei sehr
            // großen Verzeichnisbäumen etwas später). Nicht verfügbar auf
            // altem rsync (< 3.x, kein --info=progress2), daher an dieselbe
            // Versionsprüfung gekoppelt.
            args.append("--no-inc-recursive")
        }
        args += ["--delete", "--ignore-errors", "--stats"]
        if dryRun { args.append("-n") } // Testlauf: nichts wird verändert.
        args += [src, destination]

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: Self.rsyncPfad)
        proc.arguments = args

        // Getrennte Pipes: stdout = Fortschritt, stderr = Fehler/Warnungen.
        // Beide fließen ins vollständige Protokoll, stderr zusätzlich in "errors".
        let outPipe = Pipe()
        let errPipe = Pipe()
        proc.standardOutput = outPipe
        proc.standardError = errPipe

        outPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            Task { @MainActor in
                self?.log += text
                // Letzte nicht-leere Zeile als Statuszeile zeigen.
                let lines = text.split(whereSeparator: { $0 == "\n" || $0 == "\r" })
                if let last = lines.last(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }) {
                    self?.lastLine = String(last)
                }
                // Prozentangabe aus der rsync -P-Fortschrittszeile für den Balken.
                if let p = self?.parseProgress(from: text) {
                    self?.progress = p
                }
            }
        }

        errPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            Task { @MainActor in
                self?.log += text      // bleibt Teil des vollständigen Protokolls
                self?.errors += text   // zusätzlich gesammelt als reine Fehlerliste
            }
        }

        proc.terminationHandler = { [weak self] p in
            Task { @MainActor in
                outPipe.fileHandleForReading.readabilityHandler = nil
                errPipe.fileHandleForReading.readabilityHandler = nil
                self?.isRunning = false
                self?.isPaused = false
                let success = (p.terminationStatus == 0)
                if success { self?.progress = 1 }
                let prefix = (self?.dryRun ?? false) ? "Testlauf" : "Backup"
                self?.lastLine = success
                    ? "✅ \(prefix) abgeschlossen."
                    : "⚠️ Beendet mit Code \(p.terminationStatus)."
                self?.buildSummaries(exitCode: p.terminationStatus)
                self?.saveLogFile(exitCode: p.terminationStatus)
                self?.postNotification(success: success)
            }
        }

        do {
            try proc.run()
            self.process = proc
        } catch {
            isRunning = false
            lastLine = "Fehler: \(error.localizedDescription)"
        }
    }

    func cancelBackup() {
        // Falls pausiert, erst fortsetzen, damit terminate() greift.
        if isPaused { process?.resume() }
        process?.terminate()
        isRunning = false
        isPaused = false
        lastLine = "Abgebrochen."
    }

    func togglePause() {
        guard isRunning, let p = process else { return }
        if isPaused {
            if p.resume() {
                isPaused = false
                lastLine = dryRun ? "Testlauf läuft …" : "Backup läuft …"
            }
        } else {
            if p.suspend() {
                isPaused = true
                lastLine = "⏸ Pausiert."
            }
        }
    }

    // MARK: - Zusammenfassung & Protokoll-Datei

    // Baut aus dem vollständigen rsync-Output (--stats) und den gesammelten
    // Fehlern kurze, verständliche Zusammenfassungen für die Anzeige in der App.
    private func buildSummaries(exitCode: Int32) {
        let duration = backupStartDate.map { Date().timeIntervalSince($0) } ?? 0
        let durationFormatter = DateComponentsFormatter()
        durationFormatter.allowedUnits = [.hour, .minute, .second]
        durationFormatter.unitsStyle = .full
        durationFormatter.maximumUnitCount = 2
        let durationText = durationFormatter.string(from: max(duration, 1)) ?? "kurzer Zeit"

        func statValue(_ label: String) -> String? {
            guard let line = log.split(separator: "\n").first(where: { $0.hasPrefix(label) }) else { return nil }
            return line.dropFirst(label.count).trimmingCharacters(in: .whitespaces)
        }

        let filesTransferred = statValue("Number of files transferred:")
        let totalSizeRaw = statValue("Total transferred file size:")
        // rsync gibt z. B. "45.30M bytes" oder "1,234 bytes" aus — nur den vorderen Teil übernehmen.
        let totalSize = totalSizeRaw?.replacingOccurrences(of: " bytes", with: "")

        if let files = filesTransferred, let size = totalSize {
            let kind = dryRun ? "🧪 Testlauf: \(files) Datei(en) würden übertragen (\(size))"
                               : "✅ \(files) Datei(en) übertragen (\(size))"
            logSummary = "\(kind) in \(durationText)."
        } else if exitCode == 0 {
            logSummary = dryRun ? "🧪 Testlauf abgeschlossen." : "✅ Backup abgeschlossen in \(durationText)."
        } else {
            logSummary = "Vorgang beendet nach \(durationText)."
        }

        let errorLineCount = errors.split(separator: "\n").filter { $0.contains("rsync:") }.count

        if exitCode != 0 {
            let description = Self.exitCodeDescriptions[exitCode] ?? "Unbekannter Fehler"
            let countText = errorLineCount > 0 ? " (\(errorLineCount) Einzel-Fehler)" : ""
            errorSummary = "⚠️ Fehlercode \(exitCode): \(description)\(countText)."
        } else if !errors.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            errorSummary = "⚠️ \(max(errorLineCount, 1)) Warnung(en) — Details in gespeicherter Protokolldatei."
        } else {
            errorSummary = ""
        }
    }

    // Speichert das vollständige Protokoll (inkl. Fehlerabschnitt) als eine
    // Textdatei auf dem Schreibtisch, damit die App-Ansicht kurz bleiben kann.
    private func saveLogFile(exitCode: Int32) {
        let desktop = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first
        guard let desktop else { return }

        let safeName = name.isEmpty ? "Backup" : name.replacingOccurrences(of: "/", with: "-")
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let timestamp = formatter.string(from: Date())
        let url = desktop.appendingPathComponent("RsyncBackup-\(safeName)-\(timestamp).txt")

        var content = """
        rsync Backup – Protokoll
        Profil: \(name)
        Quelle: \(source)
        Ziel: \(destination)
        Start: \(backupStartDate.map { DateFormatter.localizedString(from: $0, dateStyle: .medium, timeStyle: .medium) } ?? "-")
        Ende: \(DateFormatter.localizedString(from: Date(), dateStyle: .medium, timeStyle: .medium))
        Exit-Code: \(exitCode)

        === PROTOKOLL ===
        \(log)
        """
        if !errors.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            content += "\n=== FEHLER ===\n\(errors)"
        }

        do {
            try content.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            lastLine += " (Protokolldatei konnte nicht gespeichert werden: \(error.localizedDescription))"
        }
    }

    // MARK: - Benachrichtigungen

    func toggleNotifications(_ enabled: Bool) {
        notifyOnFinish = enabled
        persist()
        if enabled {
            // Beim Einschalten Erlaubnis anfragen.
            UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, _ in
                if !granted {
                    Task { @MainActor in
                        self.lastLine = "Hinweis: Mitteilungen sind in den Systemeinstellungen deaktiviert."
                    }
                }
            }
        }
    }

    private func postNotification(success: Bool) {
        guard notifyOnFinish else { return }
        // Akustisches Signal – funktioniert auch ohne Notification-Erlaubnis.
        NSSound(named: .init(success ? "Glass" : "Basso"))?.play()
        // Banner über Notification Center.
        let content = UNMutableNotificationContent()
        content.title = "rsync Backup – \(name)"
        let kind = dryRun ? "Testlauf" : "Backup"
        content.body = success ? "✅ \(kind) abgeschlossen." : "⚠️ \(kind) fehlgeschlagen."
        content.sound = .default
        let req = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(req)
    }
}

// MARK: - Hilfs-Views

// Zeigt eine Pfadzeile mit Ordner-Icon, editierbarem Textfeld und Wählen-Button,
// als eigenständige umrandete Karte (Farbton kommt von außen, siehe ContentView).
// Pfad kann direkt getippt, eingefügt (⌘V) oder per Wählen-Button gesetzt werden.
private struct PfadZeile: View {
    let label: String
    @Binding var pfad: String
    let aktion: () -> Void
    let fuellung: Color
    let rahmen: Color

    @State private var wirdÜbersogen = false

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "folder.fill")
                .foregroundColor(.secondary)
                .font(.system(size: 13))
                .frame(width: 32, height: 32)
                .background(rahmen.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 2) {
                Text(label.uppercased())
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(0.6)
                    .foregroundColor(.secondary)
                TextField("— Pfad eingeben, einfügen oder Ordner hierher ziehen —", text: $pfad)
                    .font(.system(size: 12))
                    .textFieldStyle(.plain)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 4)
            if !pfad.isEmpty {
                Button {
                    pfad = ""
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(.secondary)
                        .frame(width: 20, height: 20)
                        .background(rahmen.opacity(0.6), in: Circle())
                }
                .buttonStyle(.plain)
                .help("Pfad löschen")
            }
            Button("Wählen…", action: aktion)
                .buttonStyle(PillButtonStyle(farbe: .backupAccent))
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(wirdÜbersogen ? Color.backupAccent.opacity(0.15) : fuellung)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(wirdÜbersogen ? Color.backupAccent : rahmen, lineWidth: wirdÜbersogen ? 1.5 : 1)
        )
        .animation(.easeInOut(duration: 0.15), value: wirdÜbersogen)
        .onDrop(of: [.fileURL], isTargeted: $wirdÜbersogen) { providers in
            guard let provider = providers.first else { return false }
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                guard let url else { return }
                var isDirectory: ObjCBool = false
                let existiertUndIstOrdner = FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue
                guard existiertUndIstOrdner else { return }
                Task { @MainActor in
                    pfad = url.path
                }
            }
            return true
        }
    }
}

// MARK: - Button-Stile
// Gefüllter, stark abgerundeter Pill-Button (z. B. "Wählen…").
private struct PillButtonStyle: ButtonStyle {
    var farbe: Color
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold))
            .foregroundColor(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(farbe.opacity(configuration.isPressed ? 0.8 : 1), in: Capsule())
    }
}

// Vollbreiter, kräftiger Start-Button.
private struct StartButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .bold))
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                Color.backupAccent.opacity(configuration.isPressed ? 0.85 : (isEnabled ? 1 : 0.4)),
                in: RoundedRectangle(cornerRadius: 14)
            )
    }
}

// Quadratischer, umrandeter Icon-Button (z. B. "+" / Papierkorb neben der Profilauswahl).
private struct IconButtonStyle: ButtonStyle {
    var fuellung: Color
    var rahmen: Color
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .foregroundColor(.primary)
            .frame(width: 40, height: 40)
            .background(fuellung, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(rahmen, lineWidth: 1))
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

// Farbiger Status-Punkt: grün = läuft, gelb = pausiert, rot = Fehler, grau = bereit.
private struct StatusPunkt: View {
    @ObservedObject var manager: BackupManager

    var farbe: Color {
        if manager.isRunning && manager.isPaused { return .yellow }
        if manager.isRunning { return .backupAccent }
        if manager.lastLine.hasPrefix("⚠️") || manager.lastLine.hasPrefix("Fehler") { return .red }
        return Color.secondary.opacity(0.5)
    }

    var body: some View {
        Circle()
            .fill(farbe)
            .frame(width: 8, height: 8)
            .shadow(color: farbe.opacity(0.6), radius: manager.isRunning ? 3 : 0)
            .animation(.easeInOut(duration: 0.3), value: manager.isRunning)
    }
}

// Konfiguriert das dahinterliegende NSWindow: keine sichtbare Titelleiste,
// kein Titeltext. Der Fensterhintergrund ist leicht durchscheinend (90 %
// Deckkraft, siehe windowHintergrundDeckkraft) statt komplett blickdicht —
// die System-Ampel (Schließen/Minimieren/Zoomen) steht dank transparenter
// Titelleiste einfach frei auf dieser Fläche statt in einer sichtbaren
// Menüleiste.
private struct WindowAccessor: NSViewRepresentable {
    var isDarkMode: Bool

    private func fensterEinrichten(_ window: NSWindow) {
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.isOpaque = false
        window.backgroundColor = ContentView.fensterHintergrundNSColor(isDarkMode: isDarkMode)
            .withAlphaComponent(ContentView.windowHintergrundDeckkraft)
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            fensterEinrichten(window)
            // Verhindert, dass macOS automatisch das erste Textfeld (den
            // Profilnamen) fokussiert und dort schon den blinkenden Cursor
            // zeigt, bevor man tatsächlich hineingeklickt hat.
            window.makeFirstResponder(nil)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                window.makeFirstResponder(nil)
            }
        }
        return view
    }

    // Wird u. a. beim Umschalten von Dark-/Light-Mode erneut aufgerufen, damit
    // der native Fensterhintergrund farblich mit dem SwiftUI-Inhalt mitzieht.
    func updateNSView(_ nsView: NSView, context: Context) {
        guard let window = nsView.window else { return }
        fensterEinrichten(window)
    }
}

// Hinweis-Overlay, wenn beim Start noch das veraltete System-rsync (2.6.9,
// ohne --info=progress2) erkannt wurde. Zeigt den nötigen Terminal-Befehl
// zur Installation eines aktuellen rsync über Homebrew.
// Kleine Hilfs-View für einen nummerierten Schritt in der Installationsanleitung.
private struct AnleitungsSchritt: View {
    let nummer: Int
    let titel: String
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(nummer)")
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(.white)
                .frame(width: 20, height: 20)
                .background(Color.backupAccent, in: Circle())
            VStack(alignment: .leading, spacing: 3) {
                Text(titel)
                    .font(.system(size: 12, weight: .semibold))
                Text(text)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct RsyncUpdateHinweis: View {
    @ObservedObject var manager: BackupManager

    var body: some View {
        ZStack {
            Color.black.opacity(0.55)
                .ignoresSafeArea()
                .onTapGesture { manager.rsyncBenötigtUpdate = false }

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Label("Veraltetes rsync erkannt", systemImage: "exclamationmark.triangle.fill")
                        .font(.headline)
                        .foregroundColor(.yellow)

                    // Erklärt zuerst, WARUM das relevant ist und was sich
                    // konkret unterscheidet, damit der Nutzer selbst
                    // entscheiden kann, ob er updaten möchte oder nicht.
                    Text("Warum das wichtig sein kann")
                        .font(.system(size: 13, weight: .semibold))

                    Text("Auf diesem Mac wird noch rsync 2.6.9 verwendet – das ist Apples letzte mitgelieferte Version aus dem Jahr 2006. Apple hat seitdem kein neueres rsync mehr eingebaut, weil ab Version 3 eine andere Lizenz (GPLv3) gilt, die Apple in Systemsoftware nicht verwenden möchte.")
                        .font(.system(size: 12))
                        .fixedSize(horizontal: false, vertical: true)

                    Text("Unterschied zur aktuellen Version 3.x:")
                        .font(.system(size: 12, weight: .semibold))

                    VStack(alignment: .leading, spacing: 6) {
                        Label("Gesamtfortschritt: Die alte Version kann in dieser App nur den Fortschritt der gerade übertragenen Einzeldatei anzeigen, nicht den Fortschritt über das komplette Backup.", systemImage: "chart.bar.fill")
                        Label("Seit 2006 keine Fehlerbehebungen oder Sicherheitsupdates mehr für diese alte Version.", systemImage: "wrench.and.screwdriver.fill")
                        Label("Teils spürbar langsamer und weniger robust bei großen Datenmengen, Sonderzeichen in Dateinamen oder unterbrochenen Übertragungen.", systemImage: "hare.fill")
                    }
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .labelStyle(.titleAndIcon)

                    Text("Wichtig: Das Backup selbst funktioniert auch mit der alten Version einwandfrei – rsync -delete, Testlauf, Protokoll usw. sind davon nicht betroffen. Ein Update ist also eine freiwillige Verbesserung, keine Voraussetzung. Du kannst dieses Fenster also auch einfach schließen und alles bleibt wie bisher.")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    Divider()

                    Text("So installierst du die aktuelle Version (freiwillig)")
                        .font(.system(size: 13, weight: .semibold))

                    AnleitungsSchritt(
                        nummer: 1,
                        titel: "Terminal öffnen",
                        text: "Drücke ⌘ (Cmd) + Leertaste, tippe „Terminal“ ein und drücke Enter. Es öffnet sich ein schwarzes Fenster mit einer Eingabezeile – das ist normal."
                    )

                    AnleitungsSchritt(
                        nummer: 2,
                        titel: "Homebrew installieren (falls noch nicht vorhanden)",
                        text: "Homebrew ist ein kostenloses, weit verbreitetes Installationswerkzeug für Zusatzprogramme auf dem Mac. Kopiere den Befehl von der Seite brew.sh in dein Terminal (Rechtsklick → Einfügen, oder ⌘V) und drücke Enter. Das Terminal fragt danach nach deinem Mac-Anmeldepasswort (wird beim Tippen nicht sichtbar angezeigt) und bestätigt anschließend mit Enter/RETURN, wenn danach gefragt wird."
                    )

                    Text("Homebrew installieren – Befehl:")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                    Text("/bin/bash -c \"$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\"")
                        .font(.system(size: 10, design: .monospaced))
                        .textSelection(.enabled)
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))

                    AnleitungsSchritt(
                        nummer: 3,
                        titel: "rsync installieren",
                        text: "Sobald Homebrew fertig eingerichtet ist (kann einige Minuten dauern), gib im selben Terminal-Fenster folgenden Befehl ein und drücke Enter:"
                    )

                    Text("brew install rsync")
                        .font(.system(size: 12, design: .monospaced))
                        .textSelection(.enabled)
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))

                    AnleitungsSchritt(
                        nummer: 4,
                        titel: "App neu starten",
                        text: "Schließe diese App komplett und öffne sie erneut. Sie erkennt das neue rsync automatisch – dieser Hinweis erscheint dann nicht mehr, und der Fortschrittsbalken zeigt den echten Gesamtfortschritt über das ganze Backup."
                    )

                    Text("Falls etwas nicht klappt oder du unsicher bist: Einfach dieses Fenster schließen und die App wie gewohnt weiter benutzen – es ändert sich nichts an der bisherigen Funktion.")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    Button("Verstanden") {
                        manager.rsyncBenötigtUpdate = false
                    }
                    .buttonStyle(.borderedProminent)
                    .frame(maxWidth: .infinity)
                }
                .padding(20)
            }
            .frame(maxWidth: 440, maxHeight: 560)
            .background(Color(nsColor: .windowBackgroundColor), in: RoundedRectangle(cornerRadius: 16))
            .shadow(radius: 20)
        }
    }
}

// MARK: - UI
struct ContentView: View {
    // Leichte Transparenz statt komplett blickdichtem Fenster (90 % Deckkraft).
    static let windowHintergrundDeckkraft: CGFloat = 0.9

    @ObservedObject var manager: BackupManager
    @AppStorage("isDarkMode") private var isDarkMode: Bool = true
    @State private var zeigeLeereQuelleWarnung = false

    // Textfarbe für die Profil-Auswahl (Menu): im Dark Mode hellgrau, im
    // Light Mode ein etwas dunkleres Grau statt komplett Schwarz — beides
    // bewusst kein reines Weiß/Schwarz, damit es sich vom Kartenhintergrund
    // abhebt, aber nicht zu hart wirkt.
    private var pickerTextFarbe: Color {
        isDarkMode ? Color(white: 0.85) : Color(white: 0.3)
    }

    // Ein mittelgrauer Ton für den Aufklapp-Pfeil der Profilauswahl — bewusst
    // derselbe Wert in beiden Modi, da Mittelgrau sich sowohl vom dunklen als
    // auch vom hellen Kartenhintergrund ausreichend abhebt.
    private var pfeilFarbe: Color {
        Color(white: 0.5)
    }

    // Fensterhintergrund: dezentes Warmgrau (Light) bzw. Beinahe-Schwarz
    // (Dark) statt des Standard-`.windowBackgroundColor` — sorgt zusammen mit
    // den helleren/dunkleren Kartenflächen für den Kontrast aus dem Redesign.
    static func fensterHintergrundNSColor(isDarkMode: Bool) -> NSColor {
        isDarkMode
            ? NSColor(red: 0.07, green: 0.07, blue: 0.08, alpha: 1)
            : NSColor(red: 0.95, green: 0.95, blue: 0.93, alpha: 1)
    }

    private var fensterHintergrund: Color {
        Color(nsColor: Self.fensterHintergrundNSColor(isDarkMode: isDarkMode))
    }

    // Kartenfläche für Profilauswahl/-name, Quelle, Ziel, Protokoll und
    // Fehler: im Light Mode reines Weiß, im Dark Mode ein helleres Grau als
    // der Fensterhintergrund, dazu jeweils ein dünner Rahmen (kartenRahmen).
    private var kartenFuellung: Color {
        isDarkMode ? Color(red: 0.12, green: 0.12, blue: 0.13) : Color.white
    }

    private var kartenRahmen: Color {
        isDarkMode ? Color(white: 0.24) : Color(white: 0.87)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Profil-Auswahl + Verwaltung: Menu (statt Picker, dessen native
            // Aufklapp-Pfeile sich farblich kaum vom Hintergrund abheben) mit
            // selbst gezeichnetem Pfeil, daneben "+"/Papierkorb als eigene
            // umrandete Icon-Buttons. Der Dark-/Light-Mode-Schalter sitzt
            // rechts außen in derselben Zeile, damit oberhalb — bis zur
            // System-Ampel — kein eigener, leerer Kopfbereich mehr nötig ist.
            HStack(spacing: 8) {
                Menu {
                    ForEach(manager.profiles) { p in
                        Button(p.name.isEmpty ? "(ohne Namen)" : p.name) {
                            manager.selectedProfileID = p.id
                            manager.persist()
                        }
                    }
                } label: {
                    HStack {
                        Text(manager.name.isEmpty ? "(ohne Namen)" : manager.name)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(pickerTextFarbe)
                            .lineLimit(1)
                        Spacer()
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(pfeilFarbe)
                    }
                    .padding(.horizontal, 14)
                    .frame(height: 40)
                    .background(kartenFuellung, in: RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(kartenRahmen, lineWidth: 1))
                }
                .menuStyle(.borderlessButton)

                Button { manager.addProfile() } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(IconButtonStyle(fuellung: kartenFuellung, rahmen: kartenRahmen))
                .help("Neues Profil")

                Button { manager.deleteSelectedProfile() } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(IconButtonStyle(fuellung: kartenFuellung, rahmen: kartenRahmen))
                .help("Profil löschen")
                .disabled(manager.profiles.count <= 1)

                Spacer(minLength: 8)

                Button {
                    isDarkMode.toggle()
                } label: {
                    // Zeigt das Symbol des Modus, in den man wechseln würde
                    // (nicht den aktuell aktiven Modus): im Dark Mode also
                    // eine Sonne (Wechsel zu Light), im Light Mode ein Mond
                    // (Wechsel zu Dark).
                    Image(systemName: isDarkMode ? "sun.max.fill" : "moon.fill")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .frame(width: 26, height: 26)
                        .background(kartenFuellung, in: Circle())
                        .overlay(Circle().strokeBorder(kartenRahmen, lineWidth: 1))
                }
                .buttonStyle(.plain)
                .help(isDarkMode ? "Zu Light Mode wechseln" : "Zu Dark Mode wechseln")
            }

            TextField("Profilname", text: Binding(
                get: { manager.name },
                set: { manager.name = $0 }
            ))
            .textFieldStyle(.plain)
            .font(.system(size: 13))
            .padding(.horizontal, 14)
            .frame(height: 40)
            .background(kartenFuellung, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(kartenRahmen, lineWidth: 1))

            // Quelle + Ziel als zwei eigenständige Karten (Wählen-Button oder
            // Pfad direkt eintippen/einfügen/hineinziehen).
            VStack(spacing: 10) {
                PfadZeile(
                    label: "Quelle",
                    pfad: Binding(get: { manager.source }, set: { manager.source = $0 }),
                    aktion: { manager.chooseFolder(title: "Quelle wählen") { manager.source = $0 } },
                    fuellung: kartenFuellung,
                    rahmen: kartenRahmen
                )
                PfadZeile(
                    label: "Ziel",
                    pfad: Binding(get: { manager.destination }, set: { manager.destination = $0 }),
                    aktion: { manager.chooseFolder(title: "Ziel wählen") { manager.destination = $0 } },
                    fuellung: kartenFuellung,
                    rahmen: kartenRahmen
                )
            }

            // Statuszeile mit farbigem Punkt
            HStack(spacing: 6) {
                StatusPunkt(manager: manager)
                Text(manager.lastLine)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            // Fortschrittsbalken über die volle Breite, nur während eines
            // Laufs sichtbar. Zeigt dank --info=progress2 den echten
            // Gesamtfortschritt über alle Dateien (siehe BackupManager.progress).
            if manager.isRunning {
                ProgressView(value: manager.progress)
                    .tint(Color.backupAccent)
            }

            // Testlauf (Dry-Run) – als Checkbox wie im Referenz-Layout,
            // direkt über dem Start-Button.
            Toggle("Testlauf (zeigt nur, was passieren würde)", isOn: Binding(
                get: { manager.dryRun },
                set: { manager.dryRun = $0; manager.persist() }
            ))
            .toggleStyle(.checkbox)
            .font(.system(size: 12))
            .disabled(manager.isRunning)

            // Start / Pause / Abbrechen
            if manager.isRunning {
                HStack {
                    Button(role: .destructive) { manager.cancelBackup() } label: {
                        Label("Abbrechen", systemImage: "stop.fill")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    Button { manager.togglePause() } label: {
                        Label(manager.isPaused ? "Fortsetzen" : "Pause",
                              systemImage: manager.isPaused ? "play.fill" : "pause.fill")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    Spacer()
                }
            } else {
                Button {
                    if !manager.dryRun && manager.sourceLooksEmpty() {
                        zeigeLeereQuelleWarnung = true
                    } else {
                        manager.startBackup()
                    }
                } label: {
                    Label(manager.dryRun ? "Testlauf starten" : "Backup starten",
                          systemImage: "arrow.triangle.2.circlepath")
                }
                .buttonStyle(StartButtonStyle())
                .disabled(manager.source.isEmpty || manager.destination.isEmpty)
                .confirmationDialog(
                    "Quelle ist leer",
                    isPresented: $zeigeLeereQuelleWarnung,
                    titleVisibility: .visible
                ) {
                    Button("Trotzdem starten", role: .destructive) { manager.startBackup() }
                    Button("Abbrechen", role: .cancel) {}
                } message: {
                    Text("Die Quelle enthält keine Dateien. Da --delete aktiv ist, würde das Ziel dabei komplett geleert. Wirklich fortfahren?")
                }
            }

            // Protokoll und Fehler als zwei eigenständige Karten.
            DisclosureGroup("Protokoll") {
                Text(manager.logSummary.isEmpty ? "— noch keine Zusammenfassung —" : manager.logSummary)
                    .font(.system(size: 12))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 4)
            }
            .font(.system(size: 13, weight: .medium))
            .padding(12)
            .background(kartenFuellung, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(kartenRahmen, lineWidth: 1))

            DisclosureGroup("Fehler") {
                Text(manager.errorSummary.isEmpty ? "— keine Fehler —" : manager.errorSummary)
                    .font(.system(size: 12))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 4)
            }
            .font(.system(size: 13, weight: .medium))
            .padding(12)
            .background(kartenFuellung, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(kartenRahmen, lineWidth: 1))

            // Einstellungen: frei stehend ohne Kartenrahmen, wie im Referenz-Layout.
            // Kein Autostart-Schalter — die App wird bewusst immer von Hand
            // gestartet, kein Login-Item.
            Toggle("Mitteilung wenn fertig", isOn: Binding(
                get: { manager.notifyOnFinish },
                set: { manager.toggleNotifications($0) }
            ))
            .toggleStyle(.switch)
            .font(.system(size: 12))
        }
        // Oben/unten schlanker als der horizontale Rand, damit die Profilzeile
        // (inkl. Dark-/Light-Button) nah unter der System-Ampel beginnt und
        // unterhalb des Mitteilungs-Schalters nicht unnötig viel Luft bleibt.
        .padding(.horizontal, 20)
        .padding(.top, 14)
        .padding(.bottom, 20)
        .tint(Color.backupAccent)
        // Bewusst nah am tatsächlichen Platzbedarf des Inhalts bemessen, damit
        // AppKit das Fenster weder zu klein öffnet (Buttons abgeschnitten)
        // noch unnötig viel Leerraum um den Inhalt herum lässt. Da der
        // Dark-/Light-Button jetzt in der Profilzeile mitläuft statt einer
        // eigenen Kopfzeile, wird insgesamt weniger Höhe benötigt.
        .frame(minWidth: 440, idealWidth: 500, minHeight: 510, idealHeight: 540)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(fensterHintergrund.opacity(Self.windowHintergrundDeckkraft))
        .background(WindowAccessor(isDarkMode: isDarkMode))
        .preferredColorScheme(isDarkMode ? .dark : .light)
        .overlay {
            if manager.rsyncBenötigtUpdate {
                RsyncUpdateHinweis(manager: manager)
            }
        }
    }
}

// MARK: - App
//
// Normale Desktop-App mit Dock-Icon und Fenster statt Menüleisten-Extra
// (WindowGroup statt MenuBarExtra, kein LSUIElement in der Info.plist).
@main
struct RsyncBackupDesktopApp: App {
    @StateObject private var manager = BackupManager()

    var body: some Scene {
        WindowGroup {
            ContentView(manager: manager)
        }
        .windowResizability(.contentSize)
        .windowStyle(.hiddenTitleBar)
    }
}
