import CryptoKit
import Foundation
import IOKit

enum MachineIDHasher {
    private static let salt = "cirrondly-desk-v1"

    static func machineId() -> String {
        let raw = platformUUID() ?? persistedFallback()
        let digest = SHA256.hash(data: Data((raw + salt).utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private static func platformUUID() -> String? {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPlatformExpertDevice"))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }

        guard let cfValue = IORegistryEntryCreateCFProperty(service, "IOPlatformUUID" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() else {
            return nil
        }

        return cfValue as? String
    }

    private static func persistedFallback() -> String {
        let key = "com.cirrondly.desk.machine-fallback"
        if let existing = UserDefaults.standard.string(forKey: key) {
            return existing
        }
        let generated = UUID().uuidString
        UserDefaults.standard.set(generated, forKey: key)
        return generated
    }
}