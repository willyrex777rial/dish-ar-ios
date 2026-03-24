import SwiftUI

@main
struct ScannerApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

struct ContentView: View {
    @StateObject private var captureSessionManager = CaptureSessionManager()
    @State private var dishName: String = ""
    @State private var isScanning = false
    
    var body: some View {
        NavigationView {
            VStack {
                if captureSessionManager.isProcessing {
                    ProgressView("Processing 3D Model...")
                        .padding()
                } else if let scannedUrl = captureSessionManager.scannedDishUrl {
                    VStack {
                        Text("Scan Complete!")
                            .font(.title)
                            .padding()
                        
                        if let qrImage = generateQRCode(from: scannedUrl) {
                            Image(uiImage: qrImage)
                                .interpolation(.none)
                                .resizable()
                                .scaledToFit()
                                .frame(width: 200, height: 200)
                                .padding()
                        }
                        
                        Text("Show this QR code to users or tap below to start a new scan.")
                            .multilineTextAlignment(.center)
                            .padding()
                        
                        Button("Start New Scan") {
                            captureSessionManager.reset()
                            dishName = ""
                        }
                        .padding()
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(10)
                    }
                } else {
                    TextField("Enter Dish Name", text: $dishName)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .padding()
                    
                    Button("Start Scan") {
                        guard !dishName.isEmpty else { return }
                        isScanning = true
                        captureSessionManager.dishName = dishName
                        captureSessionManager.startScanning()
                    }
                    .disabled(dishName.isEmpty)
                    .padding()
                    .background(dishName.isEmpty ? Color.gray : Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(10)
                }
            }
            .navigationTitle("Dish Scanner")
            .sheet(isPresented: $isScanning) {
                if let session = captureSessionManager.session {
                    ObjectCaptureViewContainer(
                        session: session,
                        isScanning: $isScanning,
                        captureSessionManager: captureSessionManager
                    )
                } else {
                    Text("Initializing Camera...")
                }
            }
        }
    }
}

import RealityKit

#if os(iOS) && !targetEnvironment(simulator)
struct ObjectCaptureViewContainer: View {
    let session: ObjectCaptureSession
    @Binding var isScanning: Bool
    @ObservedObject var captureSessionManager: CaptureSessionManager
    
    var body: some View {
        ZStack {
            ObjectCaptureView(session: session)

            VStack {
                Spacer()

                if let feedback = captureSessionManager.sessionFeedback.first {
                    Text(feedbackDescription(for: feedback))
                        .padding()
                        .background(Color.black.opacity(0.7))
                        .foregroundColor(.white)
                        .cornerRadius(10)
                        .padding(.bottom, 10)
                }

                if case .ready = captureSessionManager.sessionState {
                    Button("Continue") {
                        session.startDetecting()
                    }
                    .padding()
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(10)
                    .padding(.bottom, 30)
                } else if case .detecting = captureSessionManager.sessionState {
                    Button("Start Capture") {
                        session.startCapturing()
                    }
                    .padding()
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(10)
                    .padding(.bottom, 30)
                } else if captureSessionManager.userCompletedScanPass {
                    Button("Finish Scan") {
                        isScanning = false
                        captureSessionManager.finishScanning()
                    }
                    .padding()
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(10)
                    .padding(.bottom, 30)
                }
            }
        }
    }

    private func feedbackDescription(for feedback: ObjectCaptureSession.Feedback) -> String {
        switch feedback {
        case .objectTooFar: return "Move Closer"
        case .objectTooClose: return "Move Farther Away"
        case .environmentTooDark: return "More Light Needed"
        case .movingTooFast: return "Move Slower"
        case .outOfFieldOfView: return "Keep Object in Frame"
        default: return "Adjust Camera"
        }
    }
}
#else
struct ObjectCaptureViewContainer: View {
    let session: Any
    @Binding var isScanning: Bool
    var captureSessionManager: CaptureSessionManager
    
    var body: some View {
        Text("Object Capture is not available on this device or simulator.")
    }
}
#endif
    
    func generateQRCode(from string: String) -> UIImage? {
        let context = CIContext()
        let filter = CIFilter.qrCodeGenerator()
        
        filter.message = Data(string.utf8)

        if let outputImage = filter.outputImage {
            let transform = CGAffineTransform(scaleX: 10, y: 10)
            let scaledImage = outputImage.transformed(by: transform)
            if let cgImage = context.createCGImage(scaledImage, from: scaledImage.extent) {
                return UIImage(cgImage: cgImage)
            }
        }
        return nil
    }
}
