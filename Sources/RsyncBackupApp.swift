import SwiftUI
import AppKit
import ServiceManagement
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
    @Published var launchAtLogin: Bool = false

    private var process: Process?
    private var backupStartDate: Date?
    private let profilesKey = "profiles"
    private let selectedKey = "selectedProfileID"

    // Erkennt die Prozent-Angabe aus der rsync `-P`-Fortschrittszeile
    // (z. B. "1.234.567  45%  12,34MB/s    0:00:03") für den Fortschrittsbalken.
    // Bezieht sich auf die aktuell übertragene Datei, nicht den Gesamtjob —
    // rsync liefert ohne `--info=progress2` keinen Gesamtfortschritt.
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
        // Aktuellen Login-Item-Status auslesen (macOS 13+).
        if #available(macOS 13.0, *) {
            launchAtLogin = (SMAppService.mainApp.status == .enabled)
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
        var args = ["-ahP", "--delete", "--ignore-errors", "--stats"]
        if dryRun { args.append("-n") } // Testlauf: nichts wird verändert.
        args += [src, destination]

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/rsync")
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

    // MARK: - Autostart

    func toggleLaunchAtLogin(_ enabled: Bool) {
        guard #available(macOS 13.0, *) else {
            lastLine = "Autostart benötigt macOS 13 oder neuer."
            return
        }
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            launchAtLogin = enabled
        } catch {
            lastLine = "Autostart-Fehler: \(error.localizedDescription)"
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

// Zeigt eine Pfadzeile mit Ordner-Icon, editierbarem Textfeld und Wählen-Button.
// Pfad kann direkt getippt, eingefügt (⌘V) oder per Wählen-Button gesetzt werden.
private struct PfadZeile: View {
    let label: String
    @Binding var pfad: String
    let aktion: () -> Void

    @State private var wirdÜbersogen = false

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "folder")
                .foregroundColor(.secondary)
                .font(.system(size: 12))
            VStack(alignment: .leading, spacing: 1) {
                Text(label).font(.caption).foregroundColor(.secondary)
                TextField("— Pfad eingeben, einfügen oder Ordner hierher ziehen —", text: $pfad)
                    .font(.system(size: 11))
                    .textFieldStyle(.plain)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            if !pfad.isEmpty {
                Button {
                    pfad = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                        .font(.system(size: 11))
                }
                .buttonStyle(.plain)
                .help("Pfad löschen")
            }
            Button("Wählen…", action: aktion)
                .font(.system(size: 11))
        }
        .padding(4)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(wirdÜbersogen ? Color.backupAccent.opacity(0.15) : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(wirdÜbersogen ? Color.backupAccent : Color.clear, lineWidth: 1.5)
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
// kein Titeltext. Das Fenster bleibt vollständig blickdicht (keine
// Transparenz) — der reguläre Fensterhintergrund füllt die ganze Fläche
// durchgängig, die System-Ampel (Schließen/Minimieren/Zoomen) steht dank
// transparenter Titelleiste einfach frei auf dieser Fläche statt in einer
// sichtbaren Menüleiste.
private struct WindowAccessor: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.isMovableByWindowBackground = true
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

// MARK: - UI
struct ContentView: View {
    @ObservedObject var manager: BackupManager
    @AppStorage("isDarkMode") private var isDarkMode: Bool = true
    @State private var zeigeLeereQuelleWarnung = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Dezenter Dark-/Light-Mode-Schalter oben rechts (die System-Ampel
            // oben links kommt vom titellosen Fenster, siehe WindowAccessor).
            HStack {
                Spacer()
                Button {
                    isDarkMode.toggle()
                } label: {
                    Image(systemName: isDarkMode ? "moon.fill" : "sun.max.fill")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .frame(width: 22, height: 22)
                        .background(.quaternary, in: Circle())
                }
                .buttonStyle(.plain)
                .help(isDarkMode ? "Zu Light Mode wechseln" : "Zu Dark Mode wechseln")
            }

            // Profil-Auswahl + Verwaltung
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Picker("Profil", selection: Binding(
                        get: { manager.selectedProfileID },
                        set: { manager.selectedProfileID = $0; manager.persist() }
                    )) {
                        ForEach(manager.profiles) { p in
                            Text(p.name.isEmpty ? "(ohne Namen)" : p.name)
                                .foregroundColor(Color(white: 0.85))
                                .tag(p.id)
                        }
                    }
                    .labelsHidden()

                    Button { manager.addProfile() } label: {
                        Image(systemName: "plus")
                    }
                    .help("Neues Profil")

                    Button { manager.deleteSelectedProfile() } label: {
                        Image(systemName: "trash")
                    }
                    .help("Profil löschen")
                    .disabled(manager.profiles.count <= 1)
                }

                TextField("Profilname", text: Binding(
                    get: { manager.name },
                    set: { manager.name = $0 }
                ))
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 11))
            }
            .padding(8)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))

            // Quelle + Ziel (Wählen-Button oder Pfad direkt eintippen/einfügen)
            VStack(alignment: .leading, spacing: 6) {
                PfadZeile(
                    label: "Quelle",
                    pfad: Binding(get: { manager.source }, set: { manager.source = $0 }),
                    aktion: { manager.chooseFolder(title: "Quelle wählen") { manager.source = $0 } }
                )
                Divider()
                PfadZeile(
                    label: "Ziel",
                    pfad: Binding(get: { manager.destination }, set: { manager.destination = $0 }),
                    aktion: { manager.chooseFolder(title: "Ziel wählen") { manager.destination = $0 } }
                )
            }
            .padding(8)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))

            // Statuszeile mit farbigem Punkt
            HStack(spacing: 6) {
                StatusPunkt(manager: manager)
                Text(manager.lastLine)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            // Fortschrittsbalken über die volle Breite, nur während eines Laufs
            // sichtbar. Bezieht sich auf die aktuell übertragene Datei (siehe
            // BackupManager.parseProgress), da rsync ohne --info=progress2
            // keinen Gesamtfortschritt über alle Dateien liefert.
            if manager.isRunning {
                ProgressView(value: manager.progress)
                    .tint(Color.backupAccent)
            }

            // Testlauf (Dry-Run) – direkt über dem Start-Button
            Toggle("Testlauf (zeigt nur, was passieren würde)", isOn: Binding(
                get: { manager.dryRun },
                set: { manager.dryRun = $0; manager.persist() }
            ))
            .font(.system(size: 11))
            .disabled(manager.isRunning)

            // Start / Pause / Abbrechen
            if manager.isRunning {
                HStack {
                    Button(role: .destructive) { manager.cancelBackup() } label: {
                        Label("Abbrechen", systemImage: "stop.fill")
                    }
                    Button { manager.togglePause() } label: {
                        Label(manager.isPaused ? "Fortsetzen" : "Pause",
                              systemImage: manager.isPaused ? "play.fill" : "pause.fill")
                    }
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
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
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

            // Protokoll + Fehler
            VStack(spacing: 4) {
                DisclosureGroup("Protokoll") {
                    Text(manager.logSummary.isEmpty ? "— noch keine Zusammenfassung —" : manager.logSummary)
                        .font(.system(size: 11))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 2)
                }
                .font(.system(size: 11))

                Divider()

                DisclosureGroup("Fehler") {
                    Text(manager.errorSummary.isEmpty ? "— keine Fehler —" : manager.errorSummary)
                        .font(.system(size: 11))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 2)
                }
                .font(.system(size: 11))
            }
            .padding(8)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))

            // Einstellungen
            VStack(alignment: .leading, spacing: 6) {
                Toggle("Beim Login automatisch starten", isOn: Binding(
                    get: { manager.launchAtLogin },
                    set: { manager.toggleLaunchAtLogin($0) }
                ))
                .font(.system(size: 11))

                Toggle("Mitteilung wenn fertig", isOn: Binding(
                    get: { manager.notifyOnFinish },
                    set: { manager.toggleNotifications($0) }
                ))
                .font(.system(size: 11))
            }
            .padding(8)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
        }
        .padding(20)
        .tint(Color.backupAccent)
        .frame(minWidth: 430, idealWidth: 480, minHeight: 480, idealHeight: 560)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
        .background(WindowAccessor())
        .preferredColorScheme(isDarkMode ? .dark : .light)
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
