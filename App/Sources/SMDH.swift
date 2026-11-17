import Foundation
import UIKit

/// Title and icon read straight out of a 3DS ROM. Both are optional: a
/// compressed .zcci, an unexpected container or an icon-less title simply yields
/// nil and the library falls back to the file name.
struct ROMMetadata {
    let title: String?
    let icon: UIImage?
}

enum ROMReader {
    static func read(url: URL, fileExtension: String) -> ROMMetadata {
        // .zcci is a framed, compressed container; its contents are not random
        // accessible, so leave it to the core and show the file name.
        guard fileExtension.lowercased() != "zcci" else {
            return ROMMetadata(title: nil, icon: nil)
        }
        guard let handle = try? FileHandle(forReadingFrom: url) else {
            return ROMMetadata(title: nil, icon: nil)
        }
        defer { try? handle.close() }

        guard let ncchOffset = gamePartitionOffset(in: handle),
              let ncch = read(handle, at: ncchOffset, count: 0x200),
              ascii(ncch, at: 0x100, length: 4) == "NCCH",
              let exefsUnits = u32(ncch, 0x1A0) else {
            return ROMMetadata(title: nil, icon: nil)
        }

        let exefsOffset = ncchOffset + UInt64(exefsUnits) * 0x200
        guard let exefs = read(handle, at: exefsOffset, count: 0x200),
              let entry = exefsEntry(named: "icon", in: exefs) else {
            return ROMMetadata(title: nil, icon: nil)
        }

        let smdhOffset = exefsOffset + UInt64(entry.offset)
        guard let smdh = read(handle, at: smdhOffset, count: entry.size),
              ascii(smdh, at: 0, length: 4) == "SMDH" else {
            return ROMMetadata(title: nil, icon: nil)
        }

        return ROMMetadata(title: title(from: smdh), icon: icon(from: smdh))
    }

    /// The title id the core derives from the header (`ReadProgramId`), as the 16
    /// uppercase hex digits a cheat file is named after. Nil when the container is
    /// not a readable NCSD: a .zcci is compressed and cannot be read, and a file
    /// whose NCCH magic is not where it should be is left to the core.
    ///
    /// The offset comes from the core's own `NCCH_Header`
    /// (`src/core/file_sys/ncch_container.h`): magic at 0x100, partition id at
    /// 0x108, maker code at 0x110, version at 0x112, then four reserved bytes, so
    /// `program_id` begins at 0x118 and is little endian.
    static func titleID(url: URL, fileExtension: String) -> String? {
        guard fileExtension.lowercased() != "zcci" else { return nil }
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }

        guard let ncchOffset = gamePartitionOffset(in: handle),
              let ncch = read(handle, at: ncchOffset, count: 0x200),
              ascii(ncch, at: 0x100, length: 4) == "NCCH",
              let programID = u64(ncch, 0x118) else {
            return nil
        }
        return String(format: "%016llX", programID)
    }

    // MARK: - Container

    /// Offset of the first NCCH in an NCSD (.3ds/.cci). Nil when the file is not
    /// an NCSD container.
    private static func gamePartitionOffset(in handle: FileHandle) -> UInt64? {
        guard let header = read(handle, at: 0x100, count: 0x100),
              ascii(header, at: 0, length: 4) == "NCSD" else {
            return nil
        }
        // Partition table starts at file offset 0x120, which is 0x20 into header.
        guard let units = u32(header, 0x20) else { return nil }
        return UInt64(units) * 0x200
    }

    /// ExeFS file table: ten 16-byte entries of name[8], offset u32, size u32.
    private static func exefsEntry(named name: String,
                                   in header: Data) -> (offset: Int, size: Int)? {
        for index in 0..<10 {
            let base = index * 16
            guard let entryName = ascii(header, at: base, length: 8) else { continue }
            guard entryName == name,
                  let offset = u32(header, base + 8),
                  let size = u32(header, base + 12),
                  size > 0 else { continue }
            return (Int(offset), Int(size))
        }
        return nil
    }

    // MARK: - SMDH

    /// Titles are 16 fixed language slots of 0x200 bytes from 0x8; the long
    /// description begins 0x80 into a slot. English is slot 1, Japanese slot 0.
    private static func title(from smdh: Data) -> String? {
        let slotSize = 0x200
        let longDescriptionOffset = 0x80
        for language in [1, 0] {
            let offset = 0x8 + language * slotSize + longDescriptionOffset
            if let text = utf16Z(smdh, at: offset, length: 0x100) {
                return text
            }
        }
        return nil
    }

    /// Large icon (48x48) starts at 0x24C0, small icon (24x24) at 0x2040. Both
    /// are RGB565 little-endian.
    private static func icon(from smdh: Data) -> UIImage? {
        if let large = rgb565(smdh, at: 0x24C0, width: 48, height: 48) {
            return large
        }
        return rgb565(smdh, at: 0x2040, width: 24, height: 24)
    }

    private static func rgb565(_ data: Data, at offset: Int, width: Int, height: Int) -> UIImage? {
        let pixelCount = width * height
        let byteCount = pixelCount * 2
        guard offset >= 0, offset + byteCount <= data.count else { return nil }

        let source = [UInt8](data[offset..<(offset + byteCount)])
        // An all-zero icon region means the title has no icon; do not show black.
        if source.allSatisfy({ $0 == 0 }) { return nil }

        var pixels = [UInt8](repeating: 0, count: pixelCount * 4)
        for index in 0..<pixelCount {
            let value = UInt16(source[index * 2]) | (UInt16(source[index * 2 + 1]) << 8)
            let r = UInt8((value >> 11) & 0x1F)
            let g = UInt8((value >> 5) & 0x3F)
            let b = UInt8(value & 0x1F)
            pixels[index * 4 + 0] = UInt8((Int(r) * 255) / 31)
            pixels[index * 4 + 1] = UInt8((Int(g) * 255) / 63)
            pixels[index * 4 + 2] = UInt8((Int(b) * 255) / 31)
            pixels[index * 4 + 3] = 255
        }

        guard let provider = CGDataProvider(data: Data(pixels) as CFData),
              let image = CGImage(width: width,
                                  height: height,
                                  bitsPerComponent: 8,
                                  bitsPerPixel: 32,
                                  bytesPerRow: width * 4,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                                  provider: provider,
                                  decode: nil,
                                  shouldInterpolate: true,
                                  intent: .defaultIntent) else {
            return nil
        }
        return UIImage(cgImage: image)
    }

    // MARK: - Byte access

    private static func read(_ handle: FileHandle, at offset: UInt64, count: Int) -> Data? {
        guard count > 0 else { return nil }
        do {
            try handle.seek(toOffset: offset)
            guard let data = try handle.read(upToCount: count), !data.isEmpty else { return nil }
            return data
        } catch {
            return nil
        }
    }

    private static func u32(_ data: Data, _ offset: Int) -> UInt32? {
        guard offset >= 0, offset + 4 <= data.count else { return nil }
        let base = data.startIndex + offset
        return UInt32(data[base])
            | (UInt32(data[base + 1]) << 8)
            | (UInt32(data[base + 2]) << 16)
            | (UInt32(data[base + 3]) << 24)
    }

    private static func u64(_ data: Data, _ offset: Int) -> UInt64? {
        guard offset >= 0, offset + 8 <= data.count else { return nil }
        let base = data.startIndex + offset
        var value: UInt64 = 0
        for index in (0..<8).reversed() {
            value = (value << 8) | UInt64(data[base + index])
        }
        return value
    }

    /// NUL-padded ASCII name, or nil for an empty slot.
    private static func ascii(_ data: Data, at offset: Int, length: Int) -> String? {
        guard offset >= 0, offset + length <= data.count else { return nil }
        let slice = data[offset..<(offset + length)]
        let bytes = slice.prefix { $0 != 0 }
        guard !bytes.isEmpty else { return nil }
        return String(bytes: bytes, encoding: .ascii)
    }

    /// Fixed-width UTF-16LE field with trailing NUL padding.
    private static func utf16Z(_ data: Data, at offset: Int, length: Int) -> String? {
        guard offset >= 0, offset + length <= data.count else { return nil }
        var end = offset + length
        while end - 2 >= offset, data[end - 2] == 0, data[end - 1] == 0 {
            end -= 2
        }
        guard end > offset else { return nil }
        let slice = Data(data[offset..<end])
        guard let text = String(data: slice, encoding: .utf16LittleEndian) else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
