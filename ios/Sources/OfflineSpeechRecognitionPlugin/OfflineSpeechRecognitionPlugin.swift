import Foundation
import Capacitor

/**
 * Please read the Capacitor iOS Plugin Development Guide
 * here: https://capacitorjs.com/docs/plugins/ios
 */
@objc(OfflineSpeechRecognitionPlugin)
public class OfflineSpeechRecognitionPlugin: CAPPlugin, CAPBridgedPlugin {
    public let identifier = "OfflineSpeechRecognitionPlugin"
    public let jsName = "OfflineSpeechRecognition"
    public let pluginMethods: [CAPPluginMethod] = [
        CAPPluginMethod(name: "echo", returnType: CAPPluginReturnPromise)
    ]
    private let implementation = OfflineSpeechRecognition()

    @objc func echo(_ call: CAPPluginCall) {
        let value = call.getString("value") ?? ""
        call.resolve([
            "value": implementation.echo(value)
        ])
    }
}
