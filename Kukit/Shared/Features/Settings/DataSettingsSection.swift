import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import KukitCore

/// Settings ▸ Data: JSON backup and restore, CSV export, and "erase everything".
struct DataSettingsSection: View {
    @Environment(\.modelContext) private var context
    @AppStorage(Prefs.lastBackupDate) private var lastBackupTime: Double = 0

    @State private var backupFile = BackupFile(data: Data())
    @State private var isExportingBackup = false
    @State private var csvFile = CSVFile(text: "")
    @State private var csvName = "kukit-export"
    @State private var isExportingCSV = false
    @State private var isImporting = false
    @State private var pending: PendingImport?
    @State private var alert: AlertMessage?
    @State private var confirmErase = false

    struct PendingImport: Identifiable {
        let id = UUID()
        var document: BackupDocument
        var preview: BackupPreview
    }

    struct AlertMessage: Identifiable {
        let id = UUID()
        var title: String
        var message: String
    }

    var body: some View {
        KSection {
            Button("Export backup…", systemImage: "square.and.arrow.up", action: exportBackup)
            Button("Import backup…", systemImage: "square.and.arrow.down") { isImporting = true }
            Menu {
                Button("Study sessions") { exportCSV(name: "kukit-sessions") { try BackupService.sessionsCSV(from: context) } }
                Button("Grades") { exportCSV(name: "kukit-grades") { try BackupService.gradesCSV(from: context) } }
            } label: {
                Label("Export CSV", systemImage: "tablecells")
            }
            LabeledContent("Last backup", value: lastBackupText)
                .modifier(Presentations(
                    backupFile: backupFile, isExportingBackup: $isExportingBackup,
                    csvFile: csvFile, csvName: csvName, isExportingCSV: $isExportingCSV,
                    isImporting: $isImporting, pending: $pending, alert: $alert, confirmErase: $confirmErase,
                    onBackupSaved: { lastBackupTime = Date.now.timeIntervalSince1970 },
                    onImport: handleImport, onRun: run
                ))
            Button("Erase all data…", systemImage: "trash", role: .destructive) { confirmErase = true }
        } header: {
            Text("Data")
        } footer: {
            Text("Everything stays on this device. A backup is one file you can keep or move to another Mac or iPhone.")
        }
    }

    private var lastBackupText: String {
        lastBackupTime > 0
            ? Date(timeIntervalSince1970: lastBackupTime).formatted(date: .abbreviated, time: .shortened)
            : "Never"
    }

    // MARK: Actions

    private func exportBackup() {
        do {
            backupFile = BackupFile(data: try BackupService.exportData(from: context))
            isExportingBackup = true
        } catch {
            alert = .init(title: "Couldn't create the backup", message: error.localizedDescription)
        }
    }

    private func exportCSV(name: String, _ make: () throws -> String) {
        do {
            csvFile = CSVFile(text: try make())
            csvName = name
            isExportingCSV = true
        } catch {
            alert = .init(title: "Couldn't create the file", message: error.localizedDescription)
        }
    }

    private func handleImport(_ result: Result<URL, Error>) {
        switch result {
        case .failure(let error):
            alert = .init(title: "Couldn't open the file", message: error.localizedDescription)
        case .success(let url):
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            do {
                let data = try Data(contentsOf: url)
                let document = try BackupService.decode(data)
                let preview = try BackupService.preview(document, in: context)
                pending = PendingImport(document: document, preview: preview)
            } catch {
                alert = .init(title: "Couldn't import", message: (error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
            }
        }
    }

    private func run(_ item: PendingImport, mode: ImportMode) {
        do {
            let result = try BackupService.restore(item.document, mode: mode, into: context)
            pending = nil
            let added = mode == .replace ? result.totalRecords : result.totalNew
            alert = .init(
                title: "Import finished",
                message: mode == .replace
                    ? "Loaded \(added) records from the backup."
                    : (added == 0 ? "Everything in the backup was already here." : "Added \(added) new records.")
            )
        } catch {
            alert = .init(title: "Import failed", message: error.localizedDescription)
        }
    }
}

private struct ImportPreviewView: View {
    @Environment(\.dismiss) private var dismiss
    let pending: DataSettingsSection.PendingImport
    var onImport: (ImportMode) -> Void
    @State private var mode: ImportMode = .merge
    @State private var confirmReplace = false

    var body: some View {
        NavigationStack {
            Form {
                KSection {
                    LabeledContent("Made", value: pending.preview.exportedAt.formatted(date: .abbreviated, time: .shortened))
                    ForEach(pending.preview.lines) { line in
                        LabeledContent(line.name) {
                            Text("\(line.total)" + (line.new == line.total ? "" : " · \(line.new) new"))
                                .monospacedDigit()
                        }
                    }
                } header: {
                    Text("In this backup")
                }

                KSection {
                    Picker("How to import", selection: $mode) {
                        Text("Add what's missing").tag(ImportMode.merge)
                        Text("Replace everything").tag(ImportMode.replace)
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                } footer: {
                    Text(mode == .merge
                         ? "Nothing here is deleted. Notes with newer edits in the backup are updated; everything else already on this device is kept as it is."
                         : "Erases everything on this device first, then loads the backup. This can't be undone.")
                }
            }
            .formStyle(.grouped)
            .kukitList()
            .navigationTitle("Import backup")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Import") {
                        if mode == .replace { confirmReplace = true } else { onImport(mode) }
                    }
                    .disabled(pending.preview.totalRecords == 0 && mode == .merge)
                }
            }
            .confirmationDialog("Replace everything on this device?", isPresented: $confirmReplace, titleVisibility: .visible) {
                Button("Erase and import", role: .destructive) { onImport(.replace) }
            }
        }
        #if os(macOS)
        .frame(minWidth: 440, minHeight: 460)
        #endif
    }
}

/// All the file panels, sheets and alerts for the Data section. They hang off one row, because a
/// presentation modifier on a whole Section would be applied to every row inside it.
private struct Presentations: ViewModifier {
    @Environment(\.modelContext) private var context

    var backupFile: BackupFile
    @Binding var isExportingBackup: Bool
    var csvFile: CSVFile
    var csvName: String
    @Binding var isExportingCSV: Bool
    @Binding var isImporting: Bool
    @Binding var pending: DataSettingsSection.PendingImport?
    @Binding var alert: DataSettingsSection.AlertMessage?
    @Binding var confirmErase: Bool
    var onBackupSaved: () -> Void
    var onImport: (Result<URL, Error>) -> Void
    var onRun: (DataSettingsSection.PendingImport, ImportMode) -> Void

    func body(content: Content) -> some View {
        content
            .fileExporter(
                isPresented: $isExportingBackup, document: backupFile, contentType: .json,
                defaultFilename: BackupService.suggestedFilename()
            ) { result in
                switch result {
                case .success: onBackupSaved()
                case .failure(let error): alert = .init(title: "Couldn't save the backup", message: error.localizedDescription)
                }
            }
            .fileExporter(
                isPresented: $isExportingCSV, document: csvFile, contentType: .commaSeparatedText,
                defaultFilename: csvName
            ) { result in
                if case .failure(let error) = result {
                    alert = .init(title: "Couldn't save the file", message: error.localizedDescription)
                }
            }
            .fileImporter(isPresented: $isImporting, allowedContentTypes: [.json], onCompletion: onImport)
            .sheet(item: $pending) { item in
                ImportPreviewView(pending: item) { mode in onRun(item, mode) }
            }
            .alert(item: $alert) { Alert(title: Text($0.title), message: Text($0.message)) }
            .confirmationDialog("Erase all data?", isPresented: $confirmErase, titleVisibility: .visible) {
                Button("Erase everything", role: .destructive) {
                    do {
                        try BackupService.eraseAll(context)
                        alert = .init(title: "All data erased", message: "Kukit is back to a fresh start.")
                    } catch {
                        alert = .init(title: "Couldn't erase", message: error.localizedDescription)
                    }
                }
            } message: {
                Text("Courses, sessions, tasks, grades and notes on this device will be deleted. Export a backup first if you might want them back.")
            }
    }
}
