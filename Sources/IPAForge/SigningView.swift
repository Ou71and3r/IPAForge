import SwiftUI
import UniformTypeIdentifiers

struct SigningView: View {
    let ipaURL: URL
    @State private var p12URL: URL?
    @State private var profileURL: URL?
    @State private var password = ""
    @State private var choosingP12 = false
    @State private var choosingProfile = false
    @State private var working = false
    @State private var outputURL: URL?
    @State private var errorText: String?

    var body: some View {
        Form {
            Section("Файлове за подписване") {
                LabeledContent("IPA", value: ipaURL.lastPathComponent)
                Button("Избери P12 сертификат") { choosingP12 = true }
                if let p12URL {
                    Label(p12URL.lastPathComponent, systemImage: "checkmark.circle.fill")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Button("Избери MobileProvision") { choosingProfile = true }
                if let profileURL {
                    Label(profileURL.lastPathComponent, systemImage: "checkmark.circle.fill")
                        .font(.caption).foregroundStyle(.secondary)
                }
                SecureField("Парола на P12", text: $password)
            }

            Section {
                Button {
                    guard let selectedP12 = p12URL, let selectedProfile = profileURL else { return }
                    let signingPassword = password
                    working = true
                    errorText = nil
                    outputURL = nil

                    Task.detached(priority: .userInitiated) {
                        do {
                            let result = try IPASigningService.sign(
                                ipaURL: ipaURL,
                                p12URL: selectedP12,
                                profileURL: selectedProfile,
                                password: signingPassword
                            )
                            await MainActor.run {
                                outputURL = result
                                password = ""
                                working = false
                            }
                        } catch {
                            await MainActor.run {
                                errorText = error.localizedDescription
                                password = ""
                                working = false
                            }
                        }
                    }
                } label: {
                    if working { ProgressView() } else { Text("Подпиши IPA") }
                }
                .disabled(p12URL == nil || profileURL == nil || password.isEmpty || working)

                if let errorText { Text(errorText).foregroundStyle(.red) }
                if let outputURL {
                    ShareLink(item: outputURL) {
                        Label("Запази / сподели подписания IPA", systemImage: "square.and.arrow.up")
                    }
                }
            }

            Section {
                Text("P12 сертификатът и provisioning профилът се копират в частната папка на приложението. Паролата се пази само до приключване на операцията.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Подписване")
        .fileImporter(isPresented: $choosingP12, allowedContentTypes: [.data], allowsMultipleSelection: false) { result in
            handleCredentialImport(result, expectedExtension: "p12") { p12URL = $0 }
        }
        .fileImporter(isPresented: $choosingProfile, allowedContentTypes: [.data], allowsMultipleSelection: false) { result in
            handleCredentialImport(result, expectedExtension: "mobileprovision") { profileURL = $0 }
        }
    }

    private func handleCredentialImport(
        _ result: Result<[URL], Error>,
        expectedExtension: String,
        completion: (URL) -> Void
    ) {
        do {
            guard let selected = try result.get().first else {
                throw CocoaError(.fileReadNoSuchFile)
            }
            let localURL = try copyIntoPrivateStorage(selected, expectedExtension: expectedExtension)
            completion(localURL)
            errorText = nil
        } catch {
            errorText = error.localizedDescription
        }
    }

    private func copyIntoPrivateStorage(_ sourceURL: URL, expectedExtension: String) throws -> URL {
        let hasAccess = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if hasAccess { sourceURL.stopAccessingSecurityScopedResource() }
        }

        guard sourceURL.pathExtension.lowercased() == expectedExtension else {
            throw NSError(
                domain: "IPAForge",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Избери файл с разширение .\(expectedExtension)."]
            )
        }

        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let directory = documents.appendingPathComponent("SigningMaterial", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let destination = directory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(expectedExtension)
        try FileManager.default.copyItem(at: sourceURL, to: destination)
        return destination
    }
}
