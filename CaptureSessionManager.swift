import SwiftUI
import RealityKit
import UniformTypeIdentifiers
import Combine
import os

class CaptureSessionManager: ObservableObject {
    @Published var isProcessing = false
    @Published var scannedDishUrl: String?
    @Published var dishName: String = ""
    @Published var session: ObjectCaptureSession?
    
    private var supabaseManager = SupabaseManager()
    private var logger = Logger(subsystem: "com.restaurant.scanner", category: "CaptureSessionManager")
    
    private let checkpointDirectory: URL = {
        let fm = FileManager.default
        let url = fm.temporaryDirectory.appendingPathComponent("ObjectCaptureCheckpoints", isDirectory: true)
        try? fm.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }()
    
    private let imagesDirectory: URL = {
        let fm = FileManager.default
        let url = fm.temporaryDirectory.appendingPathComponent("ObjectCaptureImages", isDirectory: true)
        try? fm.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }()

    func reset() {
        scannedDishUrl = nil
        isProcessing = false
        session = nil
    }
    
    func startScanning() {
        guard ObjectCaptureSession.isSupported else {
            logger.error("Object capture is not supported on this device.")
            return
        }

        var configuration = ObjectCaptureSession.Configuration()
        configuration.checkpointDirectory = checkpointDirectory
        
        // Start new capture session
        session = ObjectCaptureSession()
        session?.start(imagesDirectory: imagesDirectory, configuration: configuration)
        logger.info("Started ObjectCaptureSession.")
    }
    
    func finishScanning() {
        guard let session = session else { return }
        session.finish()
        logger.info("Finished ObjectCaptureSession.")
        
        isProcessing = true
        
        processImagesAndGenerateModel()
    }
    
    private func processImagesAndGenerateModel() {
        Task {
            do {
                guard PhotogrammetrySession.isSupported else {
                    logger.error("Photogrammetry is not supported on this device.")
                    await MainActor.run { self.isProcessing = false }
                    return
                }

                let id = UUID().uuidString
                let usdzUrl = FileManager.default.temporaryDirectory.appendingPathComponent("\(id).usdz")
                
                var configuration = PhotogrammetrySession.Configuration()
                configuration.checkpointDirectory = checkpointDirectory

                let photogrammetrySession = try PhotogrammetrySession(input: imagesDirectory, configuration: configuration)
                
                let request = PhotogrammetrySession.Request.modelFile(url: usdzUrl, detail: .reduced)

                Task {
                    for try await output in photogrammetrySession.outputs {
                        switch output {
                        case .processingComplete:
                            logger.info("Processing complete.")
                            await uploadModelAndSave(fileUrl: usdzUrl, usdzPath: "\(id).usdz")
                        case .requestError(let request, let error):
                            logger.error("Request error \(String(describing: request)): \(error)")
                            await MainActor.run { self.isProcessing = false }
                        case .requestComplete(let request, let result):
                            logger.info("Request complete \(String(describing: request)): \(String(describing: result))")
                        case .processingCancelled:
                            logger.info("Processing cancelled.")
                            await MainActor.run { self.isProcessing = false }
                        case .invalidSample(let id, let reason):
                            logger.warning("Invalid sample \(id): \(reason)")
                        case .skippedSample(let id):
                            logger.warning("Skipped sample \(id)")
                        case .automaticDownsampling:
                            logger.info("Automatic downsampling happened.")
                        case .stitchingIncomplete:
                            logger.warning("Stitching incomplete.")
                        @unknown default:
                            logger.warning("Unknown photogrammetry session output.")
                        }
                    }
                }
                
                try photogrammetrySession.process(requests: [request])

            } catch {
                logger.error("Failed to setup photogrammetry session: \(error)")
                await MainActor.run { self.isProcessing = false }
            }
        }
    }
    
    @MainActor
    private func uploadModelAndSave(fileUrl: URL, usdzPath: String) async {
        do {
            // 1. Upload to Supabase Storage
            try await supabaseManager.uploadModel(fileUrl: fileUrl, path: usdzPath)
            
            // 2. Insert into Supabase DB
            let dishUrl = try await supabaseManager.saveDish(name: dishName, usdzUrl: usdzPath)
            
            self.scannedDishUrl = dishUrl
            self.isProcessing = false
        } catch {
            logger.error("Failed to upload model and save to db: \(error)")
            self.isProcessing = false
        }
    }
}
