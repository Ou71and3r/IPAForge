import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct ContentView: View {
    @StateObject private var model = IPAImportViewModel()

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header

                    Button {
                        model.isImporterPresented = true
                    } label: {
                        Label("Избери IPA файл", systemImage: "doc.badge.plus")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(model.isWorking)

                    if model.isWorking {
                        HStack(spacing: 12) {
                            ProgressView()
                            Text("Импортиране и анализиране на архива…")
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 8)
                    }

                    if let error = model.errorMessage {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                            .font(.subheadline)
                    }

                    if let archive = model.archive {
                        archiveCard(archive)
                        NavigationLink(destination: SigningView(ipaURL: archive.localURL)) {
                            Label("Подпиши този IPA", systemImage: "signature")
                                .font(.headline).frame(maxWidth: .infinity).padding(.vertical, 12)
                        }
                        .buttonStyle(.borderedProminent)
                    } else {
                        emptyState
                    }

                    roadmap
                }
                .padding()
            }
            .navigationTitle("IPAForge")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $model.isImporterPresented) {
                IPAFilePicker { result in
                    model.isImporterPresented = false
                    model.handleImport(result)
                }
                .ignoresSafeArea()
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Твоят IPA инструмент.")
                .font(.largeTitle.bold())
            Text("Локална обработка на IPA архиви. Файловете и сертификатите остават на устройството.")
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 8)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "archivebox")
                .font(.system(size: 42))
                .foregroundStyle(.secondary)
            Text("Няма избран IPA файл")
                .font(.headline)
            Text("Избери IPA от приложението Files, за да провериш съдържанието му.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
    }

    private func archiveCard(_ archive: IPAArchiveSummary) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("Архивът е прочетен", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Spacer()
                ShareLink(item: archive.localURL) {
                    Image(systemName: "square.and.arrow.up")
                }
                .accessibilityLabel("Сподели оригиналния IPA")
            }

            Text(archive.fileName)
                .font(.headline)
                .textSelection(.enabled)

            Divider()

            metric("Размер на файла", value: archive.fileSize.formatted(.byteCount(style: .file)))
            metric("Записи в архива", value: archive.entryCount.formatted())
            metric("Общ разархивиран размер", value: archive.uncompressedSize.formatted(.byteCount(style: .file)))
            metric("Папка Payload", value: archive.hasPayload ? "Намерена" : "Не е намерена")
            metric("Приложения .app", value: archive.appBundleNames.isEmpty ? "Не са открити" : archive.appBundleNames.joined(separator: ", "))

            if archive.infoPlistCount > 0 {
                Label("Открити Info.plist: \(archive.infoPlistCount)", systemImage: "checkmark.seal")
                    .font(.subheadline)
                    .foregroundStyle(.green)
            } else {
                Label("Не е открит Info.plist в Payload", systemImage: "exclamationmark.circle")
                    .font(.subheadline)
                    .foregroundStyle(.orange)
            }

            Text("Провери структурата на IPA и премини към подписване с P12 сертификат и MobileProvision.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding()
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18))
    }

    private func metric(_ title: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).foregroundStyle(.secondary)
            Spacer(minLength: 12)
            Text(value).multilineTextAlignment(.trailing)
                .fontWeight(.medium)
        }
        .font(.subheadline)
    }

    private var roadmap: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("План на разработката")
                .font(.headline)
            roadmapRow("Импортиране и преглед на IPA", complete: true)
            roadmapRow("ZIP64 и големи архиви", complete: false, detail: "Използва се ZIPFoundation; предстоят тестове с реални ZIP64 файлове.")
            roadmapRow("Импорт на P12 и provisioning profile", complete: true)
            roadmapRow("Локално подписване на приложения", complete: true)
            roadmapRow("Експорт на подписан IPA", complete: true)
            roadmapRow("Инсталиране директно от приложението", complete: false, detail: "OTA manifest-ът се проверява предварително; остава тест на реално устройство и потвърждение на локалния download.")
        }
        .padding(.top, 8)
    }

    private func roadmapRow(_ title: String, complete: Bool, detail: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Label(title, systemImage: complete ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(complete ? .green : .secondary)
            if let detail {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.leading, 28)
            }
        }
    }
}



private struct IPAFilePicker: UIViewControllerRepresentable {
    let onCompletion: (Result<[URL], Error>) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onCompletion: onCompletion)
    }

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        // Import mode: ask Files to provide a temporary copy of the selected file.
        // This avoids relying on an in-place security-scoped document URL.
        let picker = UIDocumentPickerViewController(
            forOpeningContentTypes: [.data],
            asCopy: true
        )
        picker.shouldShowFileExtensions = true
        picker.allowsMultipleSelection = false
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(
        _ uiViewController: UIDocumentPickerViewController,
        context: Context
    ) {}

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        private let onCompletion: (Result<[URL], Error>) -> Void

        init(onCompletion: @escaping (Result<[URL], Error>) -> Void) {
            self.onCompletion = onCompletion
        }

        func documentPicker(
            _ controller: UIDocumentPickerViewController,
            didPickDocumentsAt urls: [URL]
        ) {
            onCompletion(.success(urls))
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            onCompletion(.success([]))
        }
    }
}
