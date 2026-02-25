import Foundation

/// Delegates to DVDService with Blu-ray-specific options.
class BlurayService: @unchecked Sendable {
    private let dvdService: DVDService

    init(dvdService: DVDService) {
        self.dvdService = dvdService
    }

    /// Burns an ISO to Blu-ray.
    func burn(
        isoPath: String,
        device: String,
        speed: Int? = nil,
        logPath: String
    ) async -> (exitCode: Int32, errorMessage: String) {
        await dvdService.burn(
            isoPath: isoPath,
            device: device,
            speed: speed,
            logPath: logPath
        )
    }

    /// Formats BD-RE.
    func format(device: String, logPath: String) async -> (exitCode: Int32, errorMessage: String) {
        await dvdService.format(device: device, logPath: logPath)
    }

    /// Gets Blu-ray media information.
    func mediaInfo(device: String) async -> (output: String, exitCode: Int32) {
        await dvdService.mediaInfo(device: device)
    }

    /// Cancels the current process.
    func cancel() async -> Bool {
        await dvdService.cancel()
    }
}
