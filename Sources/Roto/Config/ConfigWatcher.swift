import Foundation
import RotoCore

@MainActor
final class ConfigWatcher {
    private var source: DispatchSourceFileSystemObject?
    private var descriptor: Int32 = -1
    private(set) var config: Config
    private(set) var errorMessage: String?
    var onChange: ((Config, String?) -> Void)?

    init() {
        self.config = ConfigLoader.builtin
    }

    func start() {
        ensureConfigFile()
        reload()
        watch()
    }

    func reload() {
        do {
            let loaded = try ConfigLoader.load(from: Paths.configFile)
            config = loaded
            errorMessage = nil
        } catch let error as ConfigError {
            errorMessage = error.description
        } catch {
            errorMessage = error.localizedDescription
        }
        onChange?(config, errorMessage)
    }

    func stop() {
        source?.cancel()
        source = nil
    }

    private func ensureConfigFile() {
        let dir = Paths.configDirectory
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = Paths.configFile
        if !FileManager.default.fileExists(atPath: file.path) {
            let text = ResourceLoader.defaultConfigText() ?? ConfigLoader.defaultTOML
            try? text.write(to: file, atomically: true, encoding: .utf8)
        }
    }

    private func watch() {
        guard source == nil else { return }
        let path = Paths.configDirectory.path
        descriptor = open(path, O_EVTONLY)
        guard descriptor >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.write, .rename, .delete, .extend, .attrib],
            queue: .main
        )
        source.setEventHandler { [weak self] in
            self?.reload()
        }
        source.setCancelHandler { [weak self] in
            guard let self else { return }
            if self.descriptor >= 0 {
                close(self.descriptor)
                self.descriptor = -1
            }
        }
        self.source = source
        source.resume()
    }
}
