import SwiftUI
import UniformTypeIdentifiers

struct SigningView: View {
    let ipaURL: URL
    @State private var p12URL: URL?
    @State private var profileURLs: [URL] = []
    @State private var password = ""
    @State private var choosingP12 = false
    @State private var choosingProfiles = false
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
                Button("Добави MobileProvision профили") { choosingProfiles = true }
                if profileURLs.isEmpty {
                    Text("Не са избрани provisioning профили.")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    ForEach(profileURLs, id: \.self) { url in
                        HStack {
                            Label(url.lastPathComponent, systemImage: "checkmark.circle.fill")
                                .font(.caption)
                            Spacer()
                            Button(role: .destructive) {
                                profileURLs.removeAll { $0 == url }
                            } label: {
                                Image(systemName: "minus.circle")
                            }
                            .buttonStyle(.borderless)
                            .accessibilityLabel("Премахни профила")
                        }
                    }
                }
                SecureField("Парола на P12", text: $password)
            }

            Section {
                Button {
                    guard let selectedP12 = p12URL, !profileURLs.isEmpty else { return }
                    let selectedProfiles = profileURLs
                    let signingPassword = password
                    working = true
                    errorText = nil
                    outputURL = nil

                    Task.detached(priority: .userInitiated) {
                        do {
                            let result = try IPASigningService.sign(
                                ipaURL: ipaURL,
                                p12URL: selectedP12,
                                profileURLs: selectedProfiles,
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
                .disabled(p12URL == nil || profileURLs.isEmpty || password.isEmpty || working)

                if let errorText { Text(errorText).foregroundStyle(.red) }
                if let outputURL {
                    ShareLink(item: outputURL) {
                        Label("Запази / сподели подписания IPA", systemImage: "square.and.arrow.up")
                    }
                }
            }

            Section {
                Text("Можеш да добавиш отделни профили за основното приложение, разширенията и Watch приложенията. IPAForge ги съпоставя по разрешения Bundle Identifier. Паролата се пази само до приключване на операцията.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Подписване")
        .fileImporter(isPresented: $choosingP12, allowedContentTypes: [.data], allowsMultipleSelection: false) { result in
            handleCredentialImport(result, expectedExtension: "p12") { p12URL = $0[0] }
        }
        .fileImporter(isPresented: $choosingProfiles, allowedContentTypes: [.data], allowsMultipleSelection: true) { result in
            handleCredentialImport(result, expectedExtension: "mobileprovision") { imported in
                let known = Set(profileURLs)
                profileURLs.append(contentsOf: imported.filter { !known.contains($0) })
            }
        }
    }

    private func handleCredentialImport(
        _ result: Result<[URL], Error>,
        expectedExtension: String,
        completion: ([URL]) -> Void
    ) {
        do {
            let selectedFiles = try result.get()
            guard !selectedFiles.isEmpty else { throw CocoaError(.fileReadNoSuchFile) }
            let localURLs = try selectedFiles.map {
                try copyIntoPrivateStorage($0, expectedExtension: expectedExtension)
            }
            completion(localURLs)
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

        guard let applicationSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else {
            throw CocoaError(.fileNoSuchFile)
        }
        var directory = applicationSupport.appendingPathComponent("SigningMaterial", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var directoryValues = URLResourceValues()
        directoryValues.isExcludedFromBackup = true
        try directory.setResourceValues(directoryValues)
        try FileManager.default.setAttributes(
            [.protectionKey: FileProtectionType.complete],
            ofItemAtPath: directory.path
        )

        var destination = directory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(expectedExtension)
        try FileManager.default.copyItem(at: sourceURL, to: destination)
        try FileManager.default.setAttributes(
            [.protectionKey: FileProtectionType.complete],
            ofItemAtPath: destination.path
        )
        var fileValues = URLResourceValues()
        fileValues.isExcludedFromBackup = true
        try destination.setResourceValues(fileValues)
        return destination
    }
}
