import Foundation
import os

func initRustLogger(level: LogLevel) {
    guard let containerURL = appGroupContainerURL() else {
        logger.error("initRustLogger() failed: App Group container not found")
        return
    }
    let path = containerURL.appendingPathComponent(LOG_FILENAME).path
    logger.info("initRustLogger() write to: \(path, privacy: .public)")

    do {
        _ = try trimSharedLogFileIfNeeded()
    } catch {
        logger.error("initRustLogger() failed to trim old log file: \(error.localizedDescription, privacy: .public)")
    }
    
    var errPtr: UnsafePointer<CChar>? = nil
    let ret = path.withCString { pathPtr in
        level.rawValue.withCString { levelPtr in
            loggerSubsystem.withCString { subsystemPtr in
                return init_logger(pathPtr, levelPtr, subsystemPtr, &errPtr)
            }
        }
    }
    if ret != 0 {
        let err = extractRustString(errPtr)
        logger.error("initRustLogger() failed to init: \(err ?? "", privacy: .public)")
    }
}

func extractRustString(_ strPtr: UnsafePointer<CChar>?) -> String? {
    guard let strPtr else {
        return nil
    }
    let str = String(cString: strPtr)
    free_string(strPtr)
    return str
}

func fetchRunningInfo() -> RunningInfo? {
    var infoPtr: UnsafePointer<CChar>? = nil
    var errPtr: UnsafePointer<CChar>? = nil
    if get_running_info(&infoPtr, &errPtr) == 0, let info = extractRustString(infoPtr) {
        guard let data = info.data(using: .utf8) else {
            logger.error("fetchRunningInfo() invalid utf8 data")
            return nil
        }
        do {
            let decoded = try JSONDecoder().decode(RunningInfo.self, from: data)
            logger.info("fetchRunningInfo() routes: \(decoded.routes.count)")
            return decoded
        } catch {
            logger.error("fetchRunningInfo() json decode failed: \(error, privacy: .public)")
        }
    } else if let err = extractRustString(errPtr) {
        logger.error("fetchRunningInfo() failed: \(err, privacy: .public)")
    }
    return nil
}
