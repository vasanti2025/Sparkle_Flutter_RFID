import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)
    let ok = super.application(application, didFinishLaunchingWithOptions: launchOptions)

    // Register RFID bridge as early as possible so Dart isSupported / R6 restore work.
    if let controller = window?.rootViewController as? FlutterViewController {
      RfidBridge.shared.setup(messenger: controller.binaryMessenger)
      PdfBridge.setup(messenger: controller.binaryMessenger)
    } else {
      DispatchQueue.main.async { [weak self] in
        guard let self = self else { return }
        if let controller = self.window?.rootViewController as? FlutterViewController {
          RfidBridge.shared.setup(messenger: controller.binaryMessenger)
          PdfBridge.setup(messenger: controller.binaryMessenger)
        }
      }
    }

    return ok
  }
}
