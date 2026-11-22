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
                if let p12URL { Text(p12URL.lastPathComponent).font(.caption).foregroundStyle(.secondary) }
                Button("Избери MobileProvision") { choosingProfile = true }
                if let profileURL { Text(profileURL.lastPathComponent).font(.caption).foregroundStyle(.secondary) }
                SecureField("Парола на P12", text: $password)
            }
            Section {
                Button {
                    guard let p12URL, let profileURL else { return }
                    working = true
                    errorText = nil
                    outputURL = nil
                    Task.detached(priority: .userInitiated) {
                        do {
                            let result = try IPASigningService.sign(ipaURL: ipaURL, p12URL: p12URL, profileURL: profileURL, password: password)
                            await MainActor.run { outputURL = result; working = false }
                        } catch {
                            await MainActor.run { errorText = error.localizedDescription; working = false }
                        }
                    }
                } label: {
                    if working { ProgressView() } else { Text("Подпиши IPA") }
                }
                .disabled(p12URL == nil || profileURL == nil || password.isEmpty || working)
                if let errorText { Text(errorText).foregroundStyle(.red) }
                if let outputURL {
                    ShareLink(item: outputURL) { Label("Запази / сподели подписания IPA", systemImage: "square.and.arrow.up") }
                }
            }
            Section {
                Text("P12 сертификатът и provisioning профилът се обработват локално. Паролата не се записва.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Подписване")
        .fileImporter(isPresented: $choosingP12, allowedContentTypes: [.data], allowsMultipleSelection: false) { result in
            if case .success(let urls) = result { p12URL = urls.first }
        }
        .fileImporter(isPresented: $choosingProfile, allowedContentTypes: [.data], allowsMultipleSelection: false) { result in
            if case .success(let urls) = result { profileURL = urls.first }
        }
    }
}
