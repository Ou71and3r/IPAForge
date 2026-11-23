import SwiftUI
import UniformTypeIdentifiers
import Network
import SafariServices
import ZIPFoundation

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
    @State private var installServer: IPAInstallHTTPServer?
    @State private var showingInstallSheet = false
    @State private var preparingInstall = false

    var body: some View {
        Form {
            Section("Файлове за подписване") {
                LabeledContent("IPA", value: ipaURL.lastPathComponent)
                Button("Избери P12 сертификат") { choosingP12 = true }
                    .disabled(working)
                if let p12URL {
                    Label(p12URL.lastPathComponent, systemImage: "checkmark.circle.fill")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Button("Добави MobileProvision профили") { choosingProfiles = true }
                    .disabled(working)
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
                                try? FileManager.default.removeItem(at: url)
                            } label: {
                                Image(systemName: "minus.circle")
                            }
                            .buttonStyle(.borderless)
                            .disabled(working)
                            .accessibilityLabel("Премахни профила")
                        }
                    }
                }
                SecureField("Парола на P12", text: $password)
                    .disabled(working)
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
                                // Remove imported signing material as soon as it is no longer needed.
                                try? FileManager.default.removeItem(at: selectedP12)
                                for profileURL in selectedProfiles {
                                    try? FileManager.default.removeItem(at: profileURL)
                                }
                                p12URL = nil
                                profileURLs = []
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
                    VStack(alignment: .leading, spacing: 12) {
                        ShareLink(item: outputURL) {
                            Label("Запази / сподели подписания IPA", systemImage: "square.and.arrow.up")
                        }
                        Button {
                            startInstallation(for: outputURL)
                        } label: {
                            if preparingInstall {
                                ProgressView("Подготовка на инсталацията…")
                            } else {
                                Label("Инсталирай на този iPhone", systemImage: "arrow.down.app")
                            }
                        }
                        .disabled(preparingInstall || working)
                        Text("При Ad Hoc профил регистрирай UDID на този iPhone. Enterprise профилът не изисква списък с устройства.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("IPA файлът се обслужва локално от устройството; външната услуга генерира само manifest.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section {
                Text("Можеш да добавиш отделни профили за основното приложение, разширенията и Watch приложенията. IPAForge ги съпоставя по разрешения Bundle Identifier. Паролата се пази само до приключване на операцията.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Подписване")
        .sheet(isPresented: $showingInstallSheet, onDismiss: {
            installServer?.stop()
            installServer = nil
        }) {
            if let installServer {
                IPAInstallSafariView(url: installServer.installPageURL)
                    .ignoresSafeArea()
            }
        }
        .fileImporter(isPresented: $choosingP12, allowedContentTypes: [.data], allowsMultipleSelection: false) { result in
            handleCredentialImport(result, expectedExtension: "p12") {
                if let previous = p12URL {
                    try? FileManager.default.removeItem(at: previous)
                }
                p12URL = $0[0]
            }
        }
        .fileImporter(isPresented: $choosingProfiles, allowedContentTypes: [.data], allowsMultipleSelection: true) { result in
            handleCredentialImport(result, expectedExtension: "mobileprovision") { imported in
                let known = Set(profileURLs)
                let newProfiles = imported.filter { !known.contains($0) }
                let duplicates = imported.filter { known.contains($0) }
                for duplicate in duplicates {
                    try? FileManager.default.removeItem(at: duplicate)
                }
                profileURLs.append(contentsOf: newProfiles)
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


    private func startInstallation(for url: URL) {
        do {
            errorText = nil
            preparingInstall = true
            let metadata = try IPAInstallMetadata.read(from: url)
            let server = try IPAInstallHTTPServer(
                ipaURL: url,
                bundleIdentifier: metadata.bundleIdentifier,
                displayName: metadata.displayName,
                version: metadata.version
            )
            installServer = server
            Task { @MainActor in
                do {
                    try await server.start()
                    preparingInstall = false
                    showingInstallSheet = true
                } catch {
                    preparingInstall = false
                    installServer?.stop()
                    installServer = nil
                    errorText = error.localizedDescription
                }
            }
        } catch {
            preparingInstall = false
            errorText = error.localizedDescription
        }
    }
}

private struct IPAInstallMetadata {
    let bundleIdentifier: String
    let displayName: String
    let version: String

    static func read(from ipaURL: URL) throws -> IPAInstallMetadata {
        let archive = try Archive(url: ipaURL, accessMode: .read)
        guard let entry = archive.first(where: { path in
            let parts = path.path.split(separator: "/")
            return parts.count == 3
                && parts[0] == "Payload"
                && parts[1].hasSuffix(".app")
                && parts[2] == "Info.plist"
        }) else {
            throw IPAInstallError.missingAppMetadata
        }

        let temporaryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: temporaryURL) }
        _ = try archive.extract(entry, to: temporaryURL)
        let data = try Data(contentsOf: temporaryURL)
        guard let info = try PropertyListSerialization.propertyList(
            from: data,
            options: [],
            format: nil
        ) as? [String: Any],
        let bundleIdentifier = info["CFBundleIdentifier"] as? String,
        !bundleIdentifier.isEmpty else {
            throw IPAInstallError.missingAppMetadata
        }

        let appDirectory = entry.path.split(separator: "/").dropLast().joined(separator: "/")
        guard let profileEntry = archive.first(where: {
            $0.path == "\(appDirectory)/embedded.mobileprovision"
        }) else {
            throw IPAInstallProfileError.missingProfile
        }
        let profileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: profileURL) }
        _ = try archive.extract(profileEntry, to: profileURL)
        let profileData = try Data(contentsOf: profileURL)
        try IPAInstallProfileValidator.validate(profileData)

        let displayName = (info["CFBundleDisplayName"] as? String)
            ?? (info["CFBundleName"] as? String)
            ?? bundleIdentifier
        let version = (info["CFBundleShortVersionString"] as? String)
            ?? (info["CFBundleVersion"] as? String)
            ?? "1"
        return IPAInstallMetadata(
            bundleIdentifier: bundleIdentifier,
            displayName: displayName,
            version: version
        )
    }
}

private enum IPAInstallError: LocalizedError {
    case missingAppMetadata
    case invalidServerResponse
    case fileUnavailable
    case manifestServiceUnavailable

    var errorDescription: String? {
        switch self {
        case .missingAppMetadata:
            return "Не може да бъде прочетена информацията за приложението от подписания IPA."
        case .invalidServerResponse:
            return "Заявката за инсталиране е невалидна."
        case .fileUnavailable:
            return "Подписаният IPA вече не е наличен."
        case .manifestServiceUnavailable:
            return "Услугата за генериране на manifest не отговори коректно. Провери интернет връзката и опитай отново."
        }
    }
}

/// A small loopback HTTP server. The IPA itself is streamed from disk in chunks;
/// it is never loaded into memory as one large Data object.
private final class IPAInstallHTTPServer: @unchecked Sendable {
    private let listener: NWListener
    private let queue = DispatchQueue(label: "com.ou71and3r.ipaforge.ota")
    private let ipaURL: URL
    private let redirectHTML: Data
    private let manifestURL: URL
    private let expectedBundleIdentifier: String
    private let expectedDisplayName: String
    private let expectedVersion: String
    private let port: NWEndpoint.Port

    let installPageURL: URL

    init(
        ipaURL: URL,
        bundleIdentifier: String,
        displayName: String,
        version: String
    ) throws {
        let attributes = try FileManager.default.attributesOfItem(atPath: ipaURL.path)
        guard let fileSize = (attributes[.size] as? NSNumber)?.int64Value,
              fileSize > 0 else {
            throw IPAInstallError.fileUnavailable
        }

        self.ipaURL = ipaURL
        let selectedPort = NWEndpoint.Port(rawValue: UInt16.random(in: 30000...50000))!
        self.port = selectedPort

        var relayComponents = URLComponents(string: "https://api.palera.in/genPlist")!
        relayComponents.queryItems = [
            URLQueryItem(name: "bundleid", value: bundleIdentifier),
            URLQueryItem(name: "name", value: displayName),
            URLQueryItem(name: "version", value: version),
            URLQueryItem(
                name: "fetchurl",
                value: "http://127.0.0.1:\(selectedPort.rawValue)/app.ipa"
            )
        ]
        guard let relayURL = relayComponents.url,
              let encodedRelayURL = relayURL.absoluteString.addingPercentEncoding(
                withAllowedCharacters: .alphanumerics
              ) else {
            throw IPAInstallError.invalidServerResponse
        }
        self.manifestURL = relayURL
        self.expectedBundleIdentifier = bundleIdentifier
        self.expectedDisplayName = displayName
        self.expectedVersion = version

        let installURL = "itms-services://?action=download-manifest&url=\(encodedRelayURL)"
        let html = """
        <!doctype html>
        <html><head><meta name="viewport" content="width=device-width,initial-scale=1"></head>
        <body><p>Отваряне на системната инсталация…</p>
        <a href="\(installURL)">Продължи към инсталиране</a>
        <script>window.location.replace('\(installURL)');</script>
        </body></html>
        """
        self.redirectHTML = Data(html.utf8)
        self.installPageURL = URL(
            string: "http://127.0.0.1:\(selectedPort.rawValue)/install"
        )!

        // Bind exclusively to loopback so the temporary IPA server is not exposed to the local Wi-Fi network.
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = NWEndpoint.hostPort(
            host: .ipv4(.loopback),
            port: selectedPort
        )
        self.listener = try NWListener(using: parameters)
        self.listener.newConnectionHandler = { [weak self] connection in
            self?.handle(connection)
        }
    }

    func start() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            listener.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    self.listener.stateUpdateHandler = nil
                    continuation.resume()
                case .failed(let error):
                    self.listener.stateUpdateHandler = nil
                    continuation.resume(throwing: error)
                case .cancelled:
                    self.listener.stateUpdateHandler = nil
                    continuation.resume(throwing: CancellationError())
                default:
                    break
                }
            }
            listener.start(queue: queue)
        }

        do {
            var request = URLRequest(url: manifestURL)
            request.timeoutInterval = 15
            request.cachePolicy = .reloadIgnoringLocalCacheData
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse,
                  (200...299).contains(http.statusCode) else {
                throw IPAInstallError.manifestServiceUnavailable
            }
            try IPAInstallManifestValidator.validate(
                data,
                expectedPackageURL: URL(string: "http://127.0.0.1:\(port.rawValue)/app.ipa")!,
                bundleIdentifier: expectedBundleIdentifier,
                displayName: expectedDisplayName,
                version: expectedVersion
            )
        } catch {
            listener.cancel()
            throw error
        }
    }

    func stop() {
        listener.cancel()
    }

    private func handle(_ connection: NWConnection) {
        connection.start(queue: queue)
        receiveRequest(on: connection, accumulated: Data())
    }

    private func receiveRequest(on connection: NWConnection, accumulated: Data) {
        connection.receive(
            minimumIncompleteLength: 1,
            maximumLength: 8192
        ) { [weak self] data, _, isComplete, error in
            guard let self, error == nil else {
                connection.cancel()
                return
            }
            var requestData = accumulated
            if let data { requestData.append(data) }
            let delimiter = Data("\r\n\r\n".utf8)
            if requestData.range(of: delimiter) != nil {
                self.route(requestData, connection: connection)
            } else if !isComplete && requestData.count < 65536 {
                self.receiveRequest(on: connection, accumulated: requestData)
            } else {
                connection.cancel()
            }
        }
    }

    private func route(_ requestData: Data, connection: NWConnection) {
        let request = String(decoding: requestData, as: UTF8.self)
        guard let requestLine = request.components(separatedBy: "\r\n").first else {
            sendResponse(status: "400 Bad Request", type: "text/plain", body: Data(), on: connection)
            return
        }
        let fields = requestLine.split(separator: " ")
        guard fields.count >= 2,
              fields[0] == "GET" || fields[0] == "HEAD" else {
            sendResponse(status: "405 Method Not Allowed", type: "text/plain", body: Data(), on: connection)
            return
        }
        let method = fields[0]
        let rawPath = fields[1].split(separator: "?", maxSplits: 1).first.map(String.init) ?? ""

        if method == "HEAD" {
            switch rawPath {
            case "/install":
                sendHeadResponse(
                    status: "200 OK",
                    type: "text/html; charset=utf-8",
                    contentLength: Int64(redirectHTML.count),
                    on: connection
                )
            case "/app.ipa":
                do {
                    let attributes = try FileManager.default.attributesOfItem(atPath: ipaURL.path)
                    guard let size = (attributes[.size] as? NSNumber)?.int64Value, size > 0 else {
                        throw IPAInstallError.fileUnavailable
                    }
                    sendHeadResponse(
                        status: "200 OK",
                        type: "application/octet-stream",
                        contentLength: size,
                        on: connection
                    )
                } catch {
                    sendHeadResponse(
                        status: "404 Not Found",
                        type: "text/plain",
                        contentLength: 0,
                        on: connection
                    )
                }
            default:
                sendHeadResponse(
                    status: "404 Not Found",
                    type: "text/plain",
                    contentLength: 0,
                    on: connection
                )
            }
            return
        }

        switch rawPath {
        case "/install":
            sendResponse(status: "200 OK", type: "text/html; charset=utf-8", body: redirectHTML, on: connection)
        case "/app.ipa":
            let rangeHeader = request.components(separatedBy: "\r\n").first { $0.lowercased().hasPrefix("range:") }
                .map { String($0.dropFirst("range:".count)).trimmingCharacters(in: .whitespaces) }
            streamIPA(on: connection, rangeHeader: rangeHeader)
        default:
            sendResponse(status: "404 Not Found", type: "text/plain", body: Data(), on: connection)
        }
    }

    private func sendResponse(
        status: String,
        type: String,
        body: Data,
        on connection: NWConnection
    ) {
        let header = "HTTP/1.1 \(status)\r\nContent-Type: \(type)\r\nContent-Length: \(body.count)\r\nCache-Control: no-store\r\nConnection: close\r\n\r\n"
        connection.send(content: Data(header.utf8), completion: .contentProcessed { _ in
            connection.send(content: body, completion: .contentProcessed { _ in
                connection.cancel()
            })
        })
    }

    private func sendHeadResponse(
        status: String,
        type: String,
        contentLength: Int64,
        on connection: NWConnection
    ) {
        let header = "HTTP/1.1 \(status)\r\nContent-Type: \(type)\r\nContent-Length: \(contentLength)\r\nCache-Control: no-store\r\nConnection: close\r\n\r\n"
        connection.send(content: Data(header.utf8), completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    private func streamIPA(on connection: NWConnection, rangeHeader: String?) {
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: ipaURL.path)
            guard let size = (attributes[.size] as? NSNumber)?.int64Value, size > 0 else {
                throw IPAInstallError.fileUnavailable
            }

            let selectedRange: ClosedRange<Int64>
            if let rangeHeader {
                guard let parsed = parseByteRange(rangeHeader, fileSize: size) else {
                    let header = "HTTP/1.1 416 Range Not Satisfiable\\r\\nContent-Range: bytes */\\(size)\\r\\nContent-Length: 0\\r\\nConnection: close\\r\\n\\r\\n"
                    connection.send(content: Data(header.utf8), completion: .contentProcessed { _ in
                        connection.cancel()
                    })
                    return
                }
                selectedRange = parsed
            } else {
                selectedRange = 0...(size - 1)
            }

            let contentLength = selectedRange.upperBound - selectedRange.lowerBound + 1
            let file = try FileHandle(forReadingFrom: ipaURL)
            try file.seek(toOffset: UInt64(selectedRange.lowerBound))

            let isPartial = rangeHeader != nil
            let status = isPartial ? "206 Partial Content" : "200 OK"
            let rangeLine = isPartial
                ? "Content-Range: bytes \\(selectedRange.lowerBound)-\\(selectedRange.upperBound)/\\(size)\\r\\n"
                : ""
            let header = "HTTP/1.1 \\(status)\\r\\nContent-Type: application/octet-stream\\r\\nAccept-Ranges: bytes\\r\\n\\(rangeLine)Content-Length: \\(contentLength)\\r\\nCache-Control: no-store\\r\\nConnection: close\\r\\n\\r\\n"
            connection.send(content: Data(header.utf8), completion: .contentProcessed { [weak self] error in
                guard let self, error == nil else {
                    try? file.close()
                    connection.cancel()
                    return
                }
                self.sendNextChunk(from: file, remaining: contentLength, on: connection)
            })
        } catch {
            sendResponse(status: "404 Not Found", type: "text/plain", body: Data(), on: connection)
        }
    }

    private func parseByteRange(_ header: String, fileSize: Int64) -> ClosedRange<Int64>? {
        guard header.lowercased().hasPrefix("bytes=") else { return nil }
        let value = header.dropFirst("bytes=".count)
        guard !value.contains(",") else { return nil }
        let bounds = value.split(separator: "-", omittingEmptySubsequences: false)
        guard bounds.count == 2 else { return nil }

        if bounds[0].isEmpty {
            guard let suffixLength = Int64(bounds[1]), suffixLength > 0 else { return nil }
            let length = min(suffixLength, fileSize)
            return (fileSize - length)...(fileSize - 1)
        }

        guard let start = Int64(bounds[0]), start >= 0, start < fileSize else { return nil }
        let end: Int64
        if bounds[1].isEmpty {
            end = fileSize - 1
        } else {
            guard let requestedEnd = Int64(bounds[1]), requestedEnd >= start else { return nil }
            end = min(requestedEnd, fileSize - 1)
        }
        return start...end
    }

    private func sendNextChunk(from file: FileHandle, remaining: Int64, on connection: NWConnection) {
        guard remaining > 0 else {
            try? file.close()
            connection.cancel()
            return
        }
        do {
            let requestedCount = Int(min(Int64(1024 * 1024), remaining))
            let chunk = try file.read(upToCount: requestedCount) ?? Data()
            guard !chunk.isEmpty else {
                try? file.close()
                connection.cancel()
                return
            }
            connection.send(content: chunk, completion: .contentProcessed { [weak self] error in
                guard let self, error == nil else {
                    try? file.close()
                    connection.cancel()
                    return
                }
                self.sendNextChunk(
                    from: file,
                    remaining: remaining - Int64(chunk.count),
                    on: connection
                )
            })
        } catch {
            try? file.close()
            connection.cancel()
        }
    }
}

private struct IPAInstallSafariView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        SFSafariViewController(url: url)
    }

    func updateUIViewController(_ controller: SFSafariViewController, context: Context) {}
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
