import Foundation

/// Represents an optical disc drive detected on the system.
struct OpticalDevice: Identifiable, Equatable, Hashable {
    let id: String                          // IOService path or "0,1,0" SCSI address
    var name: String
    var vendor: String
    var revision: String
    var bsdName: String?                    // /dev/diskX
    var mediaLoaded: Bool
    var mediaType: MediaType?
    var mediaCapacity: UInt64?
    var mediaUsed: UInt64?
    var isBlank: Bool?
    var capabilities: Set<DeviceCapability>

    var displayName: String {
        "\(vendor) \(name)".trimmingCharacters(in: .whitespaces)
    }

    var mediaFreeBytes: UInt64? {
        guard let capacity = mediaCapacity, let used = mediaUsed else { return nil }
        return capacity > used ? capacity - used : 0
    }
}
