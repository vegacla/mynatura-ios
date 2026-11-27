import Core
import DesignSystem
import Persistence
import SwiftData
import SwiftUI
import Store
import UIKit
import UniformTypeIdentifiers

/// Respaldo (M5, docs/local-first-migration.md §6): exportar e importar un JSON con todos los datos,
/// con recordatorio semanal. Sin credenciales.
struct BackupSection: View {
    @Environment(LocalStore.self) private var store
    @Query private var settings: [SellerSettings]
    let sellerId: String
    @State private var exported: ExportedFile?
    @State private var choosingFile = false
    @State private var pendingRestore: PendingRestore?
    @State private var message: (text: String, isError: Bool)?

    init(sellerId: String) {
        self.sellerId = sellerId
        _settings = Query(filter: #Predicate<SellerSettings> { $0.sellerId == sellerId })
    }

    private var lastBackupAt: Date? { settings.first?.lastBackupAt }

    var body: some View {
        Section {
            LabeledContent("Último respaldo", value: BackupReminder.label(lastBackupAt: lastBackupAt, now: .now))
            if BackupReminder.isDue(lastBackupAt: lastBackupAt, hasData: store.hasBackupableData(sellerId: sellerId), now: .now) {
                AlertBanner("Haz un respaldo: guárdalo en Archivos o Drive, o envíatelo por correo.", tone: .warning,
                            systemImage: "externaldrive.badge.exclamationmark")
            }
            Button(action: export) { Label("Exportar respaldo", systemImage: "square.and.arrow.up") }
            Button { choosingFile = true } label: { Label("Importar respaldo", systemImage: "square.and.arrow.down") }
            if let message {
                AlertBanner(message.text, tone: message.isError ? .danger : .success)
            }
        } header: {
            Text("Respaldo")
        } footer: {
            Text("Un archivo con tus productos, lotes, ventas, clientes y pedidos. No incluye tu contraseña. Deja activado también el respaldo de iCloud del iPhone: incluye los datos de la app.")
        }
        .sheet(item: $exported) { file in
            ActivityView(items: [file.url]) { completed in
                exported = nil
                if completed {
                    store.markBackupDone(sellerId: sellerId)
                    message = ("Respaldo listo.", false)
                    Haptics.success()
                }
            }
            .ignoresSafeArea()
        }
        .fileImporter(isPresented: $choosingFile, allowedContentTypes: [.json]) { result in
            switch result {
            case .success(let url):
                switch store.readBackup(at: url) {
                case .success(let backup): pendingRestore = PendingRestore(backup: backup)
                case .failure(let error): message = (error.message, true)
                }
            case .failure(let error):
                message = ("No se pudo abrir el archivo: \(error.localizedDescription)", true)
            }
        }
        .sheet(item: $pendingRestore) { pending in
            RestorePreviewSheet(backup: pending.backup) {
                pendingRestore = nil
                if let error = store.restoreBackup(pending.backup, sellerId: sellerId) {
                    message = (error.message, true)
                    Haptics.error()
                } else {
                    message = ("Datos restaurados desde el respaldo del \(pending.backup.exportedAt.formatted(date: .abbreviated, time: .shortened)).", false)
                    Haptics.success()
                }
            }
        }
    }

    private func export() {
        message = nil
        switch store.exportBackup(sellerId: sellerId, appVersion: AppInfo.versionLabel) {
        case .success(let url): exported = ExportedFile(url: url)
        case .failure(let error): message = (error.message, true)
        }
    }
}

private struct ExportedFile: Identifiable {
    let url: URL
    var id: URL { url }
}

private struct PendingRestore: Identifiable {
    let id = UUID()
    let backup: BackupFile
}

/// Vista previa con conteos antes de reemplazar los datos.
private struct RestorePreviewSheet: View {
    @Environment(\.dismiss) private var dismiss
    let backup: BackupFile
    let onConfirm: () -> Void
    @State private var confirming = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    LabeledContent("Fecha", value: backup.exportedAt.formatted(date: .abbreviated, time: .shortened))
                    if let version = backup.appVersion { LabeledContent("Versión de la app", value: version) }
                    ForEach(backup.counts.summaryLines, id: \.label) { line in
                        LabeledContent(line.label, value: "\(line.value)")
                    }
                } header: {
                    Text("Respaldo")
                }
                Section {
                    AlertBanner("Se reemplazarán todos los datos de este iPhone por los del respaldo. Lo que hayas hecho después de esa fecha se pierde.",
                                tone: .warning, systemImage: "exclamationmark.triangle.fill")
                    Button("Reemplazar mis datos", role: .destructive) { confirming = true }
                        .disabled(backup.counts.isEmpty)
                }
            }
            .navigationTitle("Importar respaldo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
            }
            .confirmationDialog("¿Reemplazar tus datos?", isPresented: $confirming, titleVisibility: .visible) {
                Button("Reemplazar", role: .destructive, action: onConfirm)
            } message: {
                Text("Esta acción no se puede deshacer. Si tienes dudas, exporta primero un respaldo de lo actual.")
            }
        }
    }
}

/// Hoja de compartir del sistema (Archivos, Drive, correo…), con aviso de si se completó.
struct ActivityView: UIViewControllerRepresentable {
    let items: [Any]
    let onFinish: @MainActor (Bool) -> Void

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: items, applicationActivities: nil)
        controller.completionWithItemsHandler = { _, completed, _, _ in
            MainActor.assumeIsolated { onFinish(completed) }
        }
        return controller
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
