import SwiftUI
import UIKit

/// Where a photograph of working came from.
enum PhotoChoice: Identifiable {
    case camera
    case library

    var id: Self { self }

    var source: UIImagePickerController.SourceType {
        self == .camera ? .camera : .photoLibrary
    }

    /// Whether this device can offer it. An iPad in the simulator has no
    /// camera, and a button that opens onto nothing is worse than no button.
    var isAvailable: Bool {
        UIImagePickerController.isSourceTypeAvailable(source)
    }
}

/// The system camera or photo library, wrapped so SwiftUI can present it.
///
/// Closing the sheet is left to whoever opened it: `taken` is called with the
/// photograph, or with nothing if the student backed out, and the caller puts
/// the sheet away either way. One place decides when it closes, which is
/// simpler to follow than having the picker reach out and dismiss itself.
struct PhotoSource: UIViewControllerRepresentable {
    let source: UIImagePickerController.SourceType
    let taken: (UIImage?) -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = source
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ picker: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(taken: taken)
    }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let taken: (UIImage?) -> Void

        init(taken: @escaping (UIImage?) -> Void) {
            self.taken = taken
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            taken(info[.originalImage] as? UIImage)
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            taken(nil)
        }
    }
}

extension UIImage {
    /// A version of this photograph small enough to send.
    ///
    /// A photo straight off an iPad camera is several times larger than the
    /// reader needs, and every extra megabyte is time the student spends
    /// watching a spinner. Handwriting stays legible well below full size, so
    /// the long edge is capped and the rest follows.
    func jpegForReading(longestSide: CGFloat = 1600, quality: CGFloat = 0.8) -> Data? {
        let longest = max(size.width, size.height)

        guard longest > longestSide, longest > 0 else {
            return jpegData(compressionQuality: quality)
        }

        let scale = longestSide / longest
        let smaller = CGSize(width: size.width * scale, height: size.height * scale)

        let renderer = UIGraphicsImageRenderer(size: smaller)
        let shrunk = renderer.image { _ in
            draw(in: CGRect(origin: .zero, size: smaller))
        }

        return shrunk.jpegData(compressionQuality: quality)
    }
}
