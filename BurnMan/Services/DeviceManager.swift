import Foundation
import IOKit
import IOKit.storage
import os
import Synchronization

// MARK: - Disc Device

struct DiscDevice: Identifiable, Hashable {
    let id = UUID()
    let path: String           // IOService path pour cdrdao
    let bsdName: String?       // /dev/diskX (optionnel)
    let vendor: String
    let model: String
    let revision: String

    var displayName: String {
        "\(vendor) \(model)".trimmingCharacters(in: .whitespaces)
    }
}

// MARK: - Device Manager

@Observable
@MainActor
class DeviceManager {
    var devices: [DiscDevice] = []
    var selectedDevice: DiscDevice?
    var isScanning = false
    var lastError: String?
    
    private var useIOKit = true // Toggle entre IOKit et cdrdao scanbus

    // MARK: - Scan Devices
    
    func scanDevices() async {
        isScanning = true
        lastError = nil

        if useIOKit {
            await scanDevicesWithIOKit()
        } else {
            await scanDevicesWithCdrdao()
        }

        isScanning = false
    }

    // MARK: - IOKit Detection
    
    private func scanDevicesWithIOKit() async {
        var result: [DiscDevice] = []
        
        // Créer un dictionnaire de matching pour les services DVD
        let matchingDict = IOServiceMatching("IODVDServices")
        
        var iterator: io_iterator_t = 0
        let kernResult = IOServiceGetMatchingServices(kIOMainPortDefault, matchingDict, &iterator)
        
        guard kernResult == KERN_SUCCESS else {
            lastError = "Unable to access IOKit (code \(kernResult))"
            // Fallback vers cdrdao en cas d'échec
            await scanDevicesWithCdrdao()
            return
        }
        
        defer { IOObjectRelease(iterator) }
        
        // Itérer sur tous les services trouvés
        while case let service = IOIteratorNext(iterator), service != 0 {
            defer { IOObjectRelease(service) }
            
            if let device = extractDeviceInfo(from: service) {
                result.append(device)
            }
        }
        
        // Si aucun périphérique trouvé avec IOKit, essayer cdrdao
        if result.isEmpty {
            Logger.devices.warning("No devices found via IOKit, falling back to cdrdao")
            await scanDevicesWithCdrdao()
            return
        }
        
        // Mise à jour sur le main actor
        devices = result
        if selectedDevice == nil || !devices.contains(where: { $0.path == selectedDevice?.path }) {
            selectedDevice = devices.first
        }
    }
    
    private func extractDeviceInfo(from service: io_service_t) -> DiscDevice? {
        // Récupérer le chemin IOService
        var pathBuffer = [CChar](repeating: 0, count: 512)
        let pathResult = IORegistryEntryGetPath(service, kIOServicePlane, &pathBuffer)
        
        guard pathResult == KERN_SUCCESS else { return nil }
        
        let ioServicePath = pathBuffer.withUnsafeBufferPointer { buffer in
            String(decoding: buffer.prefix(while: { $0 != 0 }).map { UInt8(bitPattern: $0) }, as: UTF8.self)
        }
        
        
        // Essayer plusieurs clés possibles pour les propriétés
        // D'abord chercher dans "Device Characteristics" (c'est là que se trouvent Vendor Name et Product Name)
        var vendor = getDeviceCharacteristic(service: service, key: "Vendor Name")
            ?? getIOProperty(service: service, key: "Vendor Name")
            ?? getIOProperty(service: service, key: "Vendor Identification")
            ?? getIOProperty(service: service, key: "vendor")
            ?? getIOProperty(service: service, key: "Vendor")
        
        var model = getDeviceCharacteristic(service: service, key: "Product Name")
            ?? getIOProperty(service: service, key: "Product Name")
            ?? getIOProperty(service: service, key: "Product Identification")
            ?? getIOProperty(service: service, key: "model")
            ?? getIOProperty(service: service, key: "Model")
        
        var revision = getDeviceCharacteristic(service: service, key: "Product Revision Level")
            ?? getIOProperty(service: service, key: "Product Revision Level")
            ?? getIOProperty(service: service, key: "revision")
        
        // Si on ne trouve toujours pas les infos, chercher dans TOUS les parents
        if vendor == nil || model == nil {
            var currentService = service
            var depth = 0
            
            while depth < 10 { // Limiter à 10 niveaux pour éviter les boucles infinies
                var parent: io_service_t = 0
                if IORegistryEntryGetParentEntry(currentService, kIOServicePlane, &parent) == KERN_SUCCESS {
                    defer {
                        if depth > 0 { IOObjectRelease(parent) }
                    }
                    
                    
                    vendor = vendor ?? getDeviceCharacteristic(service: parent, key: "Vendor Name")
                        ?? getIOProperty(service: parent, key: "Vendor Name")
                        ?? getIOProperty(service: parent, key: "Vendor Identification")
                        ?? getIOProperty(service: parent, key: "vendor")
                    
                    model = model ?? getDeviceCharacteristic(service: parent, key: "Product Name")
                        ?? getIOProperty(service: parent, key: "Product Name")
                        ?? getIOProperty(service: parent, key: "Product Identification")
                        ?? getIOProperty(service: parent, key: "model")
                    
                    revision = revision ?? getDeviceCharacteristic(service: parent, key: "Product Revision Level")
                        ?? getIOProperty(service: parent, key: "Product Revision Level")
                        ?? getIOProperty(service: parent, key: "revision")
                    
                    // Si on a trouvé, on arrête
                    if vendor != nil && model != nil {
                        break
                    }
                    
                    currentService = parent
                    depth += 1
                } else {
                    break
                }
            }
        }
        
        // Obtenir le nom BSD (/dev/diskX) - optionnel
        // Le nœud IODVDServices n'a pas toujours le BSD Name directement,
        // il faut chercher dans les enfants (IOMedia)
        let bsdName = getIOProperty(service: service, key: "BSD Name")
            ?? findChildProperty(service: service, key: "BSD Name")
        
        let finalVendor = vendor?.trimmingCharacters(in: .whitespaces) ?? "Unknown"
        let finalModel = model?.trimmingCharacters(in: .whitespaces) ?? "CD/DVD Drive"
        let finalRevision = revision?.trimmingCharacters(in: .whitespaces) ?? ""
        
        
        return DiscDevice(
            path: ioServicePath,
            bsdName: bsdName,
            vendor: finalVendor,
            model: finalModel,
            revision: finalRevision
        )
    }
    
    
    private func getIOProperty(service: io_service_t, key: String) -> String? {
        guard let property = IORegistryEntryCreateCFProperty(
            service,
            key as CFString,
            kCFAllocatorDefault,
            0
        ) else {
            return nil
        }
        
        let value = property.takeRetainedValue()
        
        // Essayer String directement
        if let string = value as? String {
            return string
        }
        
        // Essayer Data (format courant pour les propriétés SCSI)
        if let data = value as? Data {
            // Nettoyer les caractères de contrôle et espaces
            let cleaned = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .controlCharacters)
                .trimmingCharacters(in: .whitespaces)
            
            if let cleaned = cleaned, !cleaned.isEmpty {
                return cleaned
            }
            
            // Essayer ASCII si UTF8 échoue
            if let ascii = String(data: data, encoding: .ascii)?
                .trimmingCharacters(in: .controlCharacters)
                .trimmingCharacters(in: .whitespaces), !ascii.isEmpty {
                return ascii
            }
        }
        
        // Essayer NSData (parfois retourné par IOKit)
        if let nsdata = value as? NSData {
            let data = Data(referencing: nsdata)
            let cleaned = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .controlCharacters)
                .trimmingCharacters(in: .whitespaces)
            
            if let cleaned = cleaned, !cleaned.isEmpty {
                return cleaned
            }
        }
        
        return nil
    }
    
    /// Cherche récursivement une propriété dans les enfants IOKit (ex: BSD Name sur IOMedia)
    private func findChildProperty(service: io_service_t, key: String, maxDepth: Int = 5) -> String? {
        var childIterator: io_iterator_t = 0
        guard IORegistryEntryGetChildIterator(service, kIOServicePlane, &childIterator) == KERN_SUCCESS else {
            return nil
        }
        defer { IOObjectRelease(childIterator) }

        while case let child = IOIteratorNext(childIterator), child != 0 {
            defer { IOObjectRelease(child) }

            if let value = getIOProperty(service: child, key: key) {
                return value
            }

            // Recurse into children
            if maxDepth > 0, let value = findChildProperty(service: child, key: key, maxDepth: maxDepth - 1) {
                return value
            }
        }
        return nil
    }

    // Nouvelle fonction pour chercher dans "Device Characteristics"
    private func getDeviceCharacteristic(service: io_service_t, key: String) -> String? {
        guard let property = IORegistryEntryCreateCFProperty(
            service,
            "Device Characteristics" as CFString,
            kCFAllocatorDefault,
            0
        ) else {
            return nil
        }
        
        let value = property.takeRetainedValue()
        
        // C'est un dictionnaire
        if let dict = value as? [String: Any],
           let characteristic = dict[key] {
            
            if let string = characteristic as? String {
                return string
            }
            
            if let number = characteristic as? NSNumber {
                return number.stringValue
            }
        }
        
        return nil
    }

    // MARK: - Fallback: cdrdao scanbus
    
    private func scanDevicesWithCdrdao() async {
        do {
            let output = try await runCommand(ToolPaths.cdrdao, arguments: ["scanbus"])
            let parsedDevices = parseScanbusOutput(output)

            devices = parsedDevices
            if selectedDevice == nil || !devices.contains(where: { $0.path == selectedDevice?.path }) {
                selectedDevice = devices.first
            }
        } catch {
            lastError = "Unable to scan drives: \(error.localizedDescription)"
        }
    }

    private func parseScanbusOutput(_ output: String) -> [DiscDevice] {
        var result: [DiscDevice] = []

        for line in output.components(separatedBy: "\n") {
            // Format : IOService:/path/IODVDServices : Vendor, Model, Revision
            guard line.contains("IODVDServices") || line.contains("IOCompactDiscServices") else {
                continue
            }

            let parts = line.components(separatedBy: " : ")
            guard parts.count >= 2 else { continue }

            let path = parts[0].trimmingCharacters(in: .whitespaces)
            let infoParts = parts[1].components(separatedBy: ", ")

            let vendor = infoParts.count > 0 ? infoParts[0].trimmingCharacters(in: .whitespaces) : "Unknown"
            let model = infoParts.count > 1 ? infoParts[1].trimmingCharacters(in: .whitespaces) : ""
            let revision = infoParts.count > 2 ? infoParts[2].trimmingCharacters(in: .whitespaces) : ""

            result.append(DiscDevice(
                path: path,
                bsdName: nil,
                vendor: vendor,
                model: model,
                revision: revision
            ))
        }

        return result
    }

    private func runCommand(_ path: String, arguments: [String]) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            let pipe = Pipe()

            process.executableURL = URL(fileURLWithPath: path)
            process.arguments = arguments
            process.standardOutput = pipe
            process.standardError = pipe

            let outputData = Mutex(Data())

            pipe.fileHandleForReading.readabilityHandler = { @Sendable handle in
                let data = handle.availableData
                guard !data.isEmpty else { return }
                outputData.withLock { $0.append(data) }
            }

            process.terminationHandler = { @Sendable _ in
                pipe.fileHandleForReading.readabilityHandler = nil
                let remaining = pipe.fileHandleForReading.readDataToEndOfFile()
                if !remaining.isEmpty {
                    outputData.withLock { $0.append(remaining) }
                }
                let output = outputData.withLock { String(data: $0, encoding: .utf8) ?? "" }
                continuation.resume(returning: output)
            }

            do {
                try process.run()
            } catch {
                pipe.fileHandleForReading.readabilityHandler = nil
                continuation.resume(throwing: error)
            }
        }
    }
}
