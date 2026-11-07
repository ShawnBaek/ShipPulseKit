import Foundation

/// The iCloud entitlements the running app was signed with.
///
/// Without them CloudKit traps inside `CKContainer`, on a device with `EXC_BREAKPOINT`, which
/// no `@try` can catch. ``CloudKitUploader`` checks these first, so it never makes that call.
///
/// iOS has no public API for reading entitlements (`SecTask` is macOS only), so this reads
/// them from the app's own executable with ``MachOEntitlements``.
struct CloudKitEntitlements: Equatable, Sendable {
    /// The value of `com.apple.developer.icloud-services`.
    var services: [String]
    /// The value of `com.apple.developer.icloud-container-identifiers`.
    var containers: [String]

    /// Creates entitlements from their values.
    ///
    /// - Parameters:
    ///   - services: The iCloud services the app may use.
    ///   - containers: The iCloud containers the app may use.
    init(services: [String], containers: [String]) {
        self.services = services
        self.containers = containers
    }

    /// Reads the iCloud entries from an entitlements property list.
    ///
    /// - Parameter propertyList: The XML property list embedded in the executable.
    /// - Returns: The entries, or `nil` if the data isn't a property list dictionary.
    init?(propertyList: Data) {
        let parsed = try? PropertyListSerialization.propertyList(from: propertyList, format: nil)
        guard let entitlements = parsed as? [String: Any] else { return nil }
        // A wildcard profile can state services as the single string "*" rather than an array.
        let services = entitlements["com.apple.developer.icloud-services"]
        self.services = services as? [String] ?? (services as? String).map { [$0] } ?? []
        self.containers = entitlements["com.apple.developer.icloud-container-identifiers"] as? [String] ?? []
    }

    /// Reads the entitlements of the running app, or of the extension hosting this code.
    ///
    /// - Returns: The entitlements, or `nil` when the executable carries none or can't be
    ///   read. Either way `CKContainer` isn't safe to call.
    static func ofRunningApp() -> CloudKitEntitlements? {
        Bundle.main.executableURL.flatMap(of(executable:))
    }

    /// Reads the entitlements of an executable, using the slice this process would run.
    ///
    /// - Parameter url: The executable's location.
    /// - Returns: The entitlements, or `nil` when it carries none or can't be read.
    static func of(executable url: URL) -> CloudKitEntitlements? {
        // Mapped, so only the pages holding the load commands and entitlements are read.
        guard let executable = try? Data(contentsOf: url, options: .mappedIfSafe),
              let propertyList = MachOEntitlements.propertyList(in: executable, cpuType: MachOEntitlements.currentCPUType)
        else { return nil }
        return CloudKitEntitlements(propertyList: propertyList)
    }

    /// Says why these entitlements can't open a container.
    ///
    /// - Parameter containerIdentifier: The requested container, or `nil` for the default.
    /// - Returns: A reason for ``ShipPulseKitError/reason``, or `nil` when the container is
    ///   usable.
    func problem(opening containerIdentifier: String?) -> String? {
        guard services.contains("CloudKit") || services.contains("*") else {
            return "the app isn't entitled to CloudKit (com.apple.developer.icloud-services)"
        }
        guard !containers.isEmpty else {
            return "the app lists no iCloud containers (com.apple.developer.icloud-container-identifiers)"
        }
        if let containerIdentifier, !containers.contains(containerIdentifier) {
            return "the app's entitlements list only \(containers.joined(separator: ", "))"
        }
        return nil
    }
}

/// Finds the entitlements property list inside a Mach-O executable.
///
/// Every number comes from a file, so each read is bounds-checked and each sum is checked for
/// overflow; `Int` is 32 bits on arm64_32 watches. Bad input gives `nil`, never a trap.
enum MachOEntitlements {
    /// The CPU type of this process, used to pick a slice of a universal binary.
    static var currentCPUType: UInt32 {
        #if arch(arm64_32)
        return cpuARM64_32
        #elseif arch(arm64)
        return cpuARM64
        #elseif arch(x86_64)
        return cpuX86_64
        #else
        return 0
        #endif
    }

    static let cpuARM64: UInt32 = 0x0100_000C
    static let cpuARM64_32: UInt32 = 0x0200_000C
    static let cpuX86_64: UInt32 = 0x0100_0007

    /// Returns the entitlements property list of one executable.
    ///
    /// Simulator builds are only ad-hoc signed, so Xcode stores their entitlements in a
    /// `__TEXT,__entitlements` section, and the signature holds other entitlements. Device
    /// builds have no such section. So the section wins when there is one.
    ///
    /// - Parameters:
    ///   - data: The contents of a thin or universal Mach-O file.
    ///   - cpuType: The slice to read from a universal file.
    /// - Returns: The XML property list, or `nil` when there is none or the file is malformed.
    static func propertyList(in data: Data, cpuType: UInt32) -> Data? {
        guard let slice = sliceOffset(in: data, cpuType: cpuType),
              let places = loadCommands(in: data, slice: slice)
        else { return nil }
        if let section = places.section { return bytes(in: data, offset: section.offset, count: section.size) }
        guard let signature = places.signature else { return nil }
        return signatureEntitlements(in: data, signature: signature)
    }

    private struct Span {
        var offset: Int
        var size: Int
    }

    private enum Magic {
        static let universal32: UInt32 = 0xCAFE_BABE
        static let universal64: UInt32 = 0xCAFE_BABF
        static let thin32: UInt32 = 0xFEED_FACE
        static let thin64: UInt32 = 0xFEED_FACF
        static let signature: UInt32 = 0xFADE_0CC0
        static let entitlements: UInt32 = 0xFADE_7171
    }

    private enum LoadCommand {
        static let segment64: UInt32 = 0x19
        static let codeSignature: UInt32 = 0x1D
    }

    /// The signature's index slot that holds the XML entitlements (`CSSLOT_ENTITLEMENTS`).
    private static let entitlementsSlot: UInt32 = 5

    /// Finds where the slice for `cpuType` starts. A thin file is its own slice.
    private static func sliceOffset(in data: Data, cpuType: UInt32) -> Int? {
        guard let magic = bigEndian(data, at: 0) else { return nil }
        let entrySize: Int
        switch magic {
        case Magic.universal32: entrySize = 20
        case Magic.universal64: entrySize = 32
        default: return 0
        }
        guard let count = bigEndian(data, at: 4) else { return nil }
        var entry = 8
        for _ in 0..<count {
            guard let type = bigEndian(data, at: entry), let offsetAt = sum(entry, 8) else { return nil }
            if type == cpuType {
                if magic == Magic.universal32 { return bigEndian(data, at: offsetAt).flatMap { Int(exactly: $0) } }
                guard let high = bigEndian(data, at: offsetAt), let low = sum(offsetAt, 4).flatMap({ bigEndian(data, at: $0) }) else { return nil }
                return Int(exactly: UInt64(high) << 32 | UInt64(low))
            }
            guard let next = sum(entry, entrySize) else { return nil }
            entry = next
        }
        return nil
    }

    /// Walks a slice's load commands for the entitlements section and the code signature.
    private static func loadCommands(in data: Data, slice: Int) -> (section: Span?, signature: Span?)? {
        guard let magic = littleEndian(data, at: slice) else { return nil }
        let headerSize: Int
        switch magic {
        case Magic.thin64: headerSize = 32
        case Magic.thin32: headerSize = 28
        default: return nil
        }
        guard let countAt = sum(slice, 16), let count = littleEndian(data, at: countAt), var command = sum(slice, headerSize) else { return nil }

        var section: Span?
        var signature: Span?
        for _ in 0..<count {
            guard let kind = littleEndian(data, at: command),
                  let sizeAt = sum(command, 4),
                  let size = littleEndian(data, at: sizeAt).flatMap({ Int(exactly: $0) }),
                  size >= 8, // A zero size would never advance.
                  let next = sum(command, size)
            else { return nil }
            if kind == LoadCommand.codeSignature {
                signature = span(in: data, offsetAt: sum(command, 8), sizeAt: sum(command, 12), base: slice)
            } else if kind == LoadCommand.segment64, section == nil {
                section = entitlementsSection(in: data, segment: command, slice: slice)
            }
            command = next
        }
        return (section, signature)
    }

    /// Looks for `__entitlements` among the sections of a `__TEXT` segment.
    private static func entitlementsSection(in data: Data, segment: Int, slice: Int) -> Span? {
        let segmentHeaderSize = 72, sectionHeaderSize = 80
        guard let nameAt = sum(segment, 8), name(in: data, at: nameAt) == "__TEXT",
              let countAt = sum(segment, 64), let count = littleEndian(data, at: countAt),
              var header = sum(segment, segmentHeaderSize)
        else { return nil }
        for _ in 0..<count {
            guard name(in: data, at: header) != nil else { return nil }
            if name(in: data, at: header) == "__entitlements" {
                // section_64: sectname[16] segname[16] addr(8) size(8) offset(4).
                guard let sizeAt = sum(header, 40), let size = littleEndian64(data, at: sizeAt) else { return nil }
                return span(in: data, offsetAt: sum(header, 48), size: size, base: slice)
            }
            guard let next = sum(header, sectionHeaderSize) else { return nil }
            header = next
        }
        return nil
    }

    /// Reads the XML entitlements blob out of a code signature superblob.
    private static func signatureEntitlements(in data: Data, signature: Span) -> Data? {
        guard bigEndian(data, at: signature.offset) == Magic.signature,
              let countAt = sum(signature.offset, 8),
              let count = bigEndian(data, at: countAt),
              var index = sum(signature.offset, 12)
        else { return nil }
        for _ in 0..<count {
            guard let slot = bigEndian(data, at: index), let offsetAt = sum(index, 4), let next = sum(index, 8) else { return nil }
            if slot == entitlementsSlot {
                guard let blobOffset = bigEndian(data, at: offsetAt).flatMap({ Int(exactly: $0) }),
                      let blob = sum(signature.offset, blobOffset),
                      bigEndian(data, at: blob) == Magic.entitlements,
                      let lengthAt = sum(blob, 4),
                      let length = bigEndian(data, at: lengthAt).flatMap({ Int(exactly: $0) }),
                      length >= 8, // The length includes the 8-byte blob header.
                      let payload = sum(blob, 8)
                else { return nil }
                return bytes(in: data, offset: payload, count: length - 8)
            }
            index = next
        }
        return nil
    }

    // MARK: Reading

    private static func span(in data: Data, offsetAt: Int?, sizeAt: Int?, base: Int) -> Span? {
        guard let sizeAt, let size = littleEndian(data, at: sizeAt) else { return nil }
        return span(in: data, offsetAt: offsetAt, size: UInt64(size), base: base)
    }

    /// Makes a span from a file offset relative to the slice.
    private static func span(in data: Data, offsetAt: Int?, size: UInt64, base: Int) -> Span? {
        guard let offsetAt,
              let relative = littleEndian(data, at: offsetAt).flatMap({ Int(exactly: $0) }),
              let offset = sum(base, relative),
              let size = Int(exactly: size)
        else { return nil }
        return Span(offset: offset, size: size)
    }

    private static func sum(_ a: Int, _ b: Int) -> Int? {
        let (result, overflow) = a.addingReportingOverflow(b)
        return overflow ? nil : result
    }

    /// Copies a range after checking it lies inside the file.
    private static func bytes(in data: Data, offset: Int, count: Int) -> Data? {
        guard offset >= 0, count >= 0, offset <= data.count, count <= data.count - offset else { return nil }
        let start = data.startIndex + offset
        return data.subdata(in: start..<(start + count))
    }

    private static func raw<Value: FixedWidthInteger>(_ data: Data, at offset: Int, as type: Value.Type) -> Value? {
        let size = MemoryLayout<Value>.size
        guard offset >= 0, data.count >= size, offset <= data.count - size else { return nil }
        return data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: offset, as: Value.self) }
    }

    private static func bigEndian(_ data: Data, at offset: Int) -> UInt32? {
        raw(data, at: offset, as: UInt32.self).map(UInt32.init(bigEndian:))
    }

    private static func littleEndian(_ data: Data, at offset: Int) -> UInt32? {
        raw(data, at: offset, as: UInt32.self).map(UInt32.init(littleEndian:))
    }

    private static func littleEndian64(_ data: Data, at offset: Int) -> UInt64? {
        raw(data, at: offset, as: UInt64.self).map(UInt64.init(littleEndian:))
    }

    /// Reads a segment or section name: 16 bytes, NUL-padded, not always NUL-terminated.
    private static func name(in data: Data, at offset: Int) -> String? {
        guard let field = bytes(in: data, offset: offset, count: 16) else { return nil }
        return String(decoding: field.prefix { $0 != 0 }, as: UTF8.self)
    }
}
