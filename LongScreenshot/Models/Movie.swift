import Foundation
import SwiftUI
import CoreTransferable
import UniformTypeIdentifiers

/// Transferable model for importing video recordings from PhotosPicker
public struct Movie: Transferable {
    public let url: URL
    
    public init(url: URL) {
        self.url = url
    }
    
    public static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { movie in
            SentTransferredFile(movie.url)
        } importing: { received in
            let tempDirectory = FileManager.default.temporaryDirectory
            let fileName = "\(UUID().uuidString).\(received.file.pathExtension.isEmpty ? "mp4" : received.file.pathExtension)"
            let targetURL = tempDirectory.appendingPathComponent(fileName)
            
            // Clean up existing file if any
            if FileManager.default.fileExists(atPath: targetURL.path) {
                try? FileManager.default.removeItem(at: targetURL)
            }
            
            try FileManager.default.copyItem(at: received.file, to: targetURL)
            return Movie(url: targetURL)
        }
    }
}
