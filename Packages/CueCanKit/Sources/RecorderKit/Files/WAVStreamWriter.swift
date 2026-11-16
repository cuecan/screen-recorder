import Foundation

/// Writes the raw mic to a WAV file as it records, keeping the file readable if the app stops suddenly.
///
/// The header's sizes are rewritten every ``flushInterval`` seconds of audio, so a crash or a full disk
/// loses at most that much, not the recording (docs/decisions.md, 15). Samples are 32-bit float, mono,
/// exactly as they arrive: nothing is processed while recording (docs/decisions.md, 17).
public final class WAVStreamWriter: @unchecked Sendable {
    public static let flushInterval: TimeInterval = 1
    /// Complete Float32 samples with the whole 44-byte-header file inside the 32-bit boundary.
    /// Core Audio can truncate the last samples if the RIFF size fits but the whole file crosses it.
    static let maximumDataBytes = (UInt64(UInt32.max) - 44) / 4 * 4

    public let url: URL
    public let sampleRate: Double
    private let handle: FileHandle
    private let dataByteLimit: UInt64
    private var dataBytes: UInt64 = 0
    private var bytesSinceFlush: UInt64 = 0
    private let lock = NSLock()
    private var closed = false

    public convenience init(url: URL, sampleRate: Double) throws {
        try self.init(url: url, sampleRate: sampleRate, dataByteLimit: Self.maximumDataBytes)
    }

    /// A smaller capacity lets tests exercise the actual failure and finalization path with a tiny file.
    init(url: URL, sampleRate: Double, dataByteLimit: UInt64) throws {
        self.url = url
        self.sampleRate = sampleRate
        self.dataByteLimit = min(dataByteLimit, Self.maximumDataBytes)
        FileManager.default.createFile(atPath: url.path(percentEncoded: false), contents: nil)
        handle = try FileHandle(forWritingTo: url)
        try handle.write(contentsOf: Self.header(dataBytes: 0, sampleRate: sampleRate))
    }

    /// How many seconds have been written.
    public var duration: TimeInterval {
        lock.withLock { Double(dataBytes) / 4 / sampleRate }
    }

    public func append(_ samples: UnsafeBufferPointer<Float>) throws {
        try lock.withLock {
            guard !closed, !samples.isEmpty else { return }
            let bytes = UInt64(samples.count * 4)
            guard bytes <= dataByteLimit - dataBytes else {
                throw RecorderError.couldNotWrite(url, "the WAV file reached its size limit; start another recording to continue")
            }
            try handle.write(contentsOf: Data(buffer: samples))
            dataBytes += bytes
            bytesSinceFlush += bytes
            if Double(bytesSinceFlush) / 4 / sampleRate >= Self.flushInterval {
                try updateHeader()
                bytesSinceFlush = 0
            }
        }
    }

    public func append(_ samples: [Float]) throws {
        try samples.withUnsafeBufferPointer { try append($0) }
    }

    /// Writes the final sizes and closes the file.
    public func finish() throws {
        try lock.withLock {
            guard !closed else { return }
            closed = true
            do {
                try updateHeader()
            } catch {
                try? handle.close()
                throw error
            }
            try handle.close()
        }
    }

    private func updateHeader() throws {
        let end = try handle.offset()
        try handle.seek(toOffset: 0)
        try handle.write(contentsOf: Self.header(dataBytes: dataBytes, sampleRate: sampleRate))
        try handle.seek(toOffset: end)
        try handle.synchronize()
    }

    /// A 44-byte header for mono 32-bit float PCM (`WAVE_FORMAT_IEEE_FLOAT`).
    static func header(dataBytes: UInt64, sampleRate: Double) -> Data {
        let size = UInt32(clamping: dataBytes)
        var data = Data()
        func put(_ text: String) { data.append(contentsOf: Array(text.utf8)) }
        func put<T: FixedWidthInteger>(_ value: T) { withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) } }
        let rate = UInt32(sampleRate)
        put("RIFF"); put(UInt32(clamping: UInt64(size) + 36)); put("WAVE")
        put("fmt "); put(UInt32(16)); put(UInt16(3)); put(UInt16(1)); put(rate); put(rate * 4); put(UInt16(4)); put(UInt16(32))
        put("data"); put(size)
        return data
    }
}
