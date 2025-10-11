import Foundation

@objc public class OfflineSpeechRecognition: NSObject {
    @objc public func echo(_ value: String) -> String {
        print(value)
        return value
    }
}
