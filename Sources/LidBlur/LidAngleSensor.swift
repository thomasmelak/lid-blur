import Foundation
import IOKit
import IOKit.hid

/// Reads the hinge angle sensor found in recent MacBooks.
///
/// The sensor is exposed as an Apple HID device on the Sensors usage page (0x20) with the
/// "Orientation: Hinge" usage (0x8A). Feature report 1 holds the angle in degrees as a
/// little-endian 16-bit value starting at byte 1.
final class LidAngleSensor {
    private let manager: IOHIDManager
    private let device: IOHIDDevice

    private static let options = IOOptionBits(kIOHIDOptionsTypeNone)

    init?() {
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, LidAngleSensor.options)
        let matching: [String: Any] = [
            kIOHIDVendorIDKey: 0x05AC,
            kIOHIDPrimaryUsagePageKey: 0x0020,
            kIOHIDPrimaryUsageKey: 0x008A,
        ]
        IOHIDManagerSetDeviceMatching(manager, matching as CFDictionary)
        guard IOHIDManagerOpen(manager, LidAngleSensor.options) == kIOReturnSuccess else { return nil }

        guard let deviceSet = IOHIDManagerCopyDevices(manager) else {
            IOHIDManagerClose(manager, LidAngleSensor.options)
            return nil
        }
        let candidates = (deviceSet as NSSet).allObjects.map { $0 as! IOHIDDevice }

        for candidate in candidates {
            guard IOHIDDeviceOpen(candidate, LidAngleSensor.options) == kIOReturnSuccess else { continue }
            if LidAngleSensor.readAngle(from: candidate) != nil {
                self.manager = manager
                self.device = candidate
                return
            }
            IOHIDDeviceClose(candidate, LidAngleSensor.options)
        }

        IOHIDManagerClose(manager, LidAngleSensor.options)
        return nil
    }

    deinit {
        IOHIDDeviceClose(device, LidAngleSensor.options)
        IOHIDManagerClose(manager, LidAngleSensor.options)
    }

    /// Current lid angle in degrees, or nil if the sensor could not be read.
    func readAngle() -> Double? {
        LidAngleSensor.readAngle(from: device)
    }

    private static func readAngle(from device: IOHIDDevice) -> Double? {
        var report = [UInt8](repeating: 0, count: 8)
        var length = CFIndex(report.count)
        let result = IOHIDDeviceGetReport(device, kIOHIDReportTypeFeature, 1, &report, &length)
        guard result == kIOReturnSuccess, length >= 3 else { return nil }
        let raw = UInt16(report[2]) << 8 | UInt16(report[1])
        guard raw <= 360 else { return nil }
        return Double(raw)
    }
}

/// Fallback for Macs without a hinge sensor: the lid open/closed state from the power manager.
enum Clamshell {
    static func isClosed() -> Bool? {
        let root = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPMrootDomain"))
        guard root != 0 else { return nil }
        defer { IOObjectRelease(root) }
        guard let value = IORegistryEntryCreateCFProperty(root, "AppleClamshellState" as CFString, kCFAllocatorDefault, 0)?
            .takeRetainedValue() else { return nil }
        return (value as? NSNumber)?.boolValue
    }
}
