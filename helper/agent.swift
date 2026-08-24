// WifiSSID — reads the current Wi-Fi network name (SSID).
//
// Since macOS Sonoma 14.4 the SSID sits behind the Location Services permission: knowing
// the name of a Wi-Fi network is enough to geolocate the machine, so only an app that has
// been AUTHORISED for Location can read it. SwiftBar never asks for that permission, so a
// plugin calling CoreWLAN directly gets "<redacted>".
//
// This tiny signed binary asks for it instead, and the grant is bound to ITS identity, not
// to the parent process. Once authorised, anything (SwiftBar, a script, a shell) can run it
// to read the name.
//
//   WifiSSID --grant   interactive: shows the authorisation dialog (run once, from Terminal).
//   WifiSSID           read mode: prints the SSID on stdout, or exits non-zero. Never blocks.
//
import Cocoa
import CoreLocation
import CoreWLAN

let grantMode = CommandLine.arguments.contains("--grant")
let timeoutSeconds = 2.0   // guard: never sit forever waiting for the authorisation status

func err(_ s: String) { FileHandle.standardError.write((s + "\n").data(using: .utf8)!) }
func currentSSID() -> String? { CWWiFiClient.shared().interface()?.ssid() }

final class Helper: NSObject, NSApplicationDelegate, CLLocationManagerDelegate {
    let manager = CLLocationManager()
    var done = false

    func applicationDidFinishLaunching(_ note: Notification) {
        manager.delegate = self   // setting the delegate triggers a first authorisation callback
        DispatchQueue.main.asyncAfter(deadline: .now() + timeoutSeconds) { [weak self] in
            guard let self = self, !self.done else { return }
            err("timeout: Location authorisation status never resolved")
            exit(4)
        }
        evaluate(manager.authorizationStatus)
    }

    func locationManagerDidChangeAuthorization(_ m: CLLocationManager) {
        evaluate(m.authorizationStatus)
    }

    func evaluate(_ status: CLAuthorizationStatus) {
        if done { return }
        switch status {
        case .notDetermined:
            // Only --grant pops the dialog. In read mode we wait for the real status through
            // the callback; if it never comes, the timeout guard above decides.
            if grantMode {
                err("Requesting authorisation — click \"Allow\" on the macOS dialog…")
                manager.requestWhenInUseAuthorization()
            }
        case .authorizedAlways, .authorizedWhenInUse:
            done = true
            if let ssid = currentSSID(), !ssid.isEmpty {
                print(ssid)
                if grantMode { err("Authorised ✅ — Wi-Fi: \(ssid)") }
                exit(0)
            }
            err("Authorised, but no active Wi-Fi network")
            exit(1)
        case .denied, .restricted:
            done = true
            err("Location denied. Enable WifiSSID under Settings → Privacy & Security → Location Services.")
            exit(2)
        @unknown default:
            done = true
            exit(3)
        }
    }
}

let app = NSApplication.shared
let helper = Helper()
app.delegate = helper
app.setActivationPolicy(.accessory)   // no Dock icon
app.run()
