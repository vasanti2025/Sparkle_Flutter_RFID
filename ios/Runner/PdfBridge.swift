import Flutter
import UIKit

/// Opens a PDF like Android `Intent.ACTION_VIEW`.
enum PdfBridge {
  static func setup(messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: "com.loyalstring.rfid/pdf", binaryMessenger: messenger)
    channel.setMethodCallHandler { call, result in
      guard call.method == "openPdf" else {
        result(FlutterMethodNotImplemented)
        return
      }
      guard
        let args = call.arguments as? [String: Any],
        let path = args["path"] as? String,
        !path.isEmpty,
        FileManager.default.fileExists(atPath: path)
      else {
        result(false)
        return
      }
      let url = URL(fileURLWithPath: path)
      DispatchQueue.main.async {
        UIApplication.shared.open(url, options: [:]) { ok in
          result(ok)
        }
      }
    }
  }
}
