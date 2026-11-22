import Foundation
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class IPAImportViewModel: ObservableObject {
    @Published var isImporterPresented = false
    @Published private(set) var isWorking = false
    @Published private(set) var archive: IPAArchiveSummary?
    @Published private(set) var errorMessage: String?

    func handleImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            guard url.pathExtension.lowercased() == "ipa" else {
                errorMessage = "Моля, избери файл с разширение .ipa."
                return
            }
            importIPA(from: url)
        case .failure(let error):
            errorMessage = error.localizedDescription
        }
    }

    private func importIPA(from sourceURL: URL) {
        isWorking = true
        errorMessage = nil
        archive = nil

        Task {
            do {
                let result = try await Task.detached(priority: .userInitiated) {
                    try IPAArchiveService.copyAndInspect(sourceURL: sourceURL)
                }.value
                archive = result
            } catch {
                errorMessage = error.localizedDescription
            }
            isWorking = false
        }
    }
}
