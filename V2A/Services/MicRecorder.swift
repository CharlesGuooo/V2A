import AVFoundation
import Foundation

// Captures microphone audio and emits 16 kHz mono Int16 PCM frames (~100 ms,
// 1600 samples each). Mirrors V2A/src/recorder.ts + public/pcm-worklet.js.

enum MicError: LocalizedError {
    case alreadyRunning
    case formatUnavailable
    case converterFailed
    case engineFailed(String)

    var errorDescription: String? {
        switch self {
        case .alreadyRunning: return String(localized: "麦克风已经在录")
        case .formatUnavailable: return String(localized: "无法构造 16kHz Int16 输出格式")
        case .converterFailed: return String(localized: "无法构造 AVAudioConverter")
        case .engineFailed(let msg): return String(localized: "AVAudioEngine 启动失败：\(msg)")
        }
    }
}

final class MicRecorder {
    private let engine = AVAudioEngine()
    private var converter: AVAudioConverter?
    private var pendingInt16: [Int16] = []
    private let frameSamples = 1600
    private var onFrame: ((Data) -> Void)?
    private var isRunning = false

    // Called when the audio session is interrupted (incoming call, another app
    // grabs the mic, headphones unplugged). Consumer should stop recording.
    var onInterruption: (() -> Void)?
    private var interruptionObserver: NSObjectProtocol?

    func requestPermission() async -> Bool {
        await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
    }

    func start(onFrame: @escaping (Data) -> Void) async throws {
        guard !isRunning else { throw MicError.alreadyRunning }
        self.onFrame = onFrame
        self.pendingInt16.removeAll(keepingCapacity: true)

        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .measurement, options: [])
        try session.setActive(true, options: [])

        let input = engine.inputNode
        let inputFormat = input.outputFormat(forBus: 0)
        guard let outputFormat = AVAudioFormat(commonFormat: .pcmFormatInt16,
                                               sampleRate: 16000,
                                               channels: 1,
                                               interleaved: true) else {
            throw MicError.formatUnavailable
        }
        guard let conv = AVAudioConverter(from: inputFormat, to: outputFormat) else {
            throw MicError.converterFailed
        }
        self.converter = conv

        input.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] buffer, _ in
            self?.process(buffer: buffer, outputFormat: outputFormat)
        }

        engine.prepare()
        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            throw MicError.engineFailed(error.localizedDescription)
        }

        interruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: session,
            queue: .main
        ) { [weak self] note in
            guard let info = note.userInfo,
                  let typeRaw = info[AVAudioSessionInterruptionTypeKey] as? UInt,
                  let type = AVAudioSession.InterruptionType(rawValue: typeRaw),
                  type == .began else { return }
            self?.onInterruption?()
        }

        isRunning = true
    }

    func stop() async {
        guard isRunning else { return }
        if let obs = interruptionObserver {
            NotificationCenter.default.removeObserver(obs)
            interruptionObserver = nil
        }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
        converter = nil
        onFrame = nil
        pendingInt16.removeAll()
        isRunning = false
    }

    private func process(buffer: AVAudioPCMBuffer, outputFormat: AVAudioFormat) {
        guard let converter else { return }

        let inputRate = buffer.format.sampleRate
        let outputRate = outputFormat.sampleRate
        let outputCapacity = AVAudioFrameCount(Double(buffer.frameLength) * outputRate / inputRate) + 1024
        guard let outBuf = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: outputCapacity) else { return }

        var fed = false
        let inputBlock: AVAudioConverterInputBlock = { _, status in
            if fed {
                status.pointee = .noDataNow
                return nil
            }
            fed = true
            status.pointee = .haveData
            return buffer
        }
        var error: NSError?
        let result = converter.convert(to: outBuf, error: &error, withInputFrom: inputBlock)
        guard error == nil, result != .error else { return }

        guard let int16Channel = outBuf.int16ChannelData?.pointee else { return }
        let count = Int(outBuf.frameLength)
        guard count > 0 else { return }

        pendingInt16.reserveCapacity(pendingInt16.count + count)
        for i in 0..<count {
            pendingInt16.append(int16Channel[i])
        }

        while pendingInt16.count >= frameSamples {
            let chunk = Array(pendingInt16.prefix(frameSamples))
            pendingInt16.removeFirst(frameSamples)
            chunk.withUnsafeBufferPointer { ptr in
                let data = Data(buffer: ptr)
                self.onFrame?(data)
            }
        }
    }
}
