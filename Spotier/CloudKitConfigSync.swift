import CloudKit
import Foundation

struct CloudConfigFile {
    let name: String
    let content: String
    let updatedAt: Date
}

actor CloudKitConfigSync {
    static let shared = CloudKitConfigSync()

    private let database = CKContainer.default().privateCloudDatabase
    private let recordType = "SpotierConfig"
    private let nameKey = "name"
    private let contentKey = "content"
    private let updatedAtKey = "updated_at"

    func sync(localDirectory: URL) async throws -> Bool {
        let remoteFiles = try await fetchRemoteConfigs()
        let localFiles = try loadLocalConfigs(from: localDirectory)

        var localChanged = false

        for (name, remote) in remoteFiles {
            guard let local = localFiles[name] else {
                try writeLocalConfig(remote, to: localDirectory)
                localChanged = true
                continue
            }

            if shouldOverwriteLocal(remote: remote, local: local) {
                try writeLocalConfig(remote, to: localDirectory)
                localChanged = true
            }
        }

        for (name, local) in localFiles {
            guard let remote = remoteFiles[name] else {
                try await upsertRemoteConfig(local)
                continue
            }

            if shouldOverwriteRemote(local: local, remote: remote) {
                try await upsertRemoteConfig(local)
            }
        }

        return localChanged
    }

    func deleteConfig(named fileName: String) async throws {
        let recordID = CKRecord.ID(recordName: recordName(for: fileName))
        do {
            _ = try await deleteRecord(with: recordID)
        } catch {
            let ckError = error as? CKError
            if ckError?.code != .unknownItem {
                throw error
            }
        }
    }

    private func fetchRemoteConfigs() async throws -> [String: CloudConfigFile] {
        let query = CKQuery(recordType: recordType, predicate: NSPredicate(value: true))
        let records = try await perform(query: query)

        var files: [String: CloudConfigFile] = [:]
        for record in records {
            guard let name = record[nameKey] as? String,
                  let content = record[contentKey] as? String else {
                continue
            }

            let updatedAt = (record[updatedAtKey] as? Date)
                ?? record.modificationDate
                ?? Date.distantPast

            files[name] = CloudConfigFile(name: name, content: content, updatedAt: updatedAt)
        }
        return files
    }

    private func loadLocalConfigs(from directory: URL) throws -> [String: CloudConfigFile] {
        if !FileManager.default.fileExists(atPath: directory.path) {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }

        let items = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        )

        var files: [String: CloudConfigFile] = [:]
        for url in items where url.pathExtension.lowercased() == "toml" {
            let values = try url.resourceValues(forKeys: [.isRegularFileKey, .contentModificationDateKey])
            guard values.isRegularFile == true else { continue }

            let content = try String(contentsOf: url, encoding: .utf8)
            let modifiedAt = values.contentModificationDate ?? Date.distantPast
            files[url.lastPathComponent] = CloudConfigFile(
                name: url.lastPathComponent,
                content: content,
                updatedAt: modifiedAt
            )
        }
        return files
    }

    private func writeLocalConfig(_ file: CloudConfigFile, to directory: URL) throws {
        let url = directory.appendingPathComponent(file.name)
        try file.content.write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.modificationDate: file.updatedAt], ofItemAtPath: url.path)
    }

    private func upsertRemoteConfig(_ file: CloudConfigFile) async throws {
        let recordID = CKRecord.ID(recordName: recordName(for: file.name))
        let record = CKRecord(recordType: recordType, recordID: recordID)
        record[nameKey] = file.name as CKRecordValue
        record[contentKey] = file.content as CKRecordValue
        record[updatedAtKey] = file.updatedAt as CKRecordValue
        _ = try await save(record: record)
    }

    private func shouldOverwriteLocal(remote: CloudConfigFile, local: CloudConfigFile) -> Bool {
        if remote.content == local.content {
            return false
        }
        return remote.updatedAt.timeIntervalSince(local.updatedAt) > 1.0
    }

    private func shouldOverwriteRemote(local: CloudConfigFile, remote: CloudConfigFile) -> Bool {
        if local.content == remote.content {
            return false
        }
        return local.updatedAt.timeIntervalSince(remote.updatedAt) > 1.0
    }

    private func recordName(for fileName: String) -> String {
        "config_\(fileName)"
    }

    private func perform(query: CKQuery) async throws -> [CKRecord] {
        var allRecords: [CKRecord] = []
        let desiredKeys = [nameKey, contentKey, updatedAtKey]

        var page = try await database.records(
            matching: query,
            inZoneWith: nil,
            desiredKeys: desiredKeys,
            resultsLimit: CKQueryOperation.maximumResults
        )
        try appendMatchedRecords(page.matchResults, into: &allRecords)

        var cursor = page.queryCursor
        while let currentCursor = cursor {
            page = try await database.records(
                continuingMatchFrom: currentCursor,
                desiredKeys: desiredKeys,
                resultsLimit: CKQueryOperation.maximumResults
            )
            try appendMatchedRecords(page.matchResults, into: &allRecords)
            cursor = page.queryCursor
        }

        return allRecords
    }

    private func appendMatchedRecords(
        _ matchResults: [(CKRecord.ID, Result<CKRecord, Error>)],
        into records: inout [CKRecord]
    ) throws {
        for (_, result) in matchResults {
            switch result {
            case .success(let record):
                records.append(record)
            case .failure(let error):
                throw error
            }
        }
    }

    private func save(record: CKRecord) async throws -> CKRecord {
        try await withCheckedThrowingContinuation { continuation in
            database.save(record) { saved, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                continuation.resume(returning: saved ?? record)
            }
        }
    }

    private func deleteRecord(with recordID: CKRecord.ID) async throws -> CKRecord.ID {
        try await withCheckedThrowingContinuation { continuation in
            database.delete(withRecordID: recordID) { deletedID, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                continuation.resume(returning: deletedID ?? recordID)
            }
        }
    }
}
