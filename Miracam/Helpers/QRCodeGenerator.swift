import Foundation
import CoreImage.CIFilterBuiltins
import UIKit

struct QRCodeGenerator {
    static func generateQRCode(from string: String, size: CGFloat = 160) -> UIImage? {
        let context = CIContext()
        let filter = CIFilter.qrCodeGenerator()
        
        guard let data = string.data(using: .utf8) else { return nil }
        filter.setValue(data, forKey: "inputMessage")
        
        guard let qrCode = filter.outputImage else { return nil }
        
        // Scale the QR code to the desired size
        let scale = size / qrCode.extent.width
        let transform = CGAffineTransform(scaleX: scale, y: scale)
        let scaledQRCode = qrCode.transformed(by: transform)
        
        guard let cgImage = context.createCGImage(scaledQRCode, from: scaledQRCode.extent) else { return nil }
        
        return UIImage(cgImage: cgImage)
    }
} 