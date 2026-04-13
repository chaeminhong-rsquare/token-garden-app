import Foundation
import SQLite3
import Testing
@testable import TokenGarden

/// Regression tests for the profile-loss bug triggered by
/// ModelContainer-init failure on stores whose WAL has uncheckpointed rows.
///
/// On 2026-04-10 a crash left the SwiftData store in a state where the
/// reset path in `AppDelegate.applicationDidFinishLaunching` ran but
/// `backupProfiles` used `sqlite3_open` without checkpointing the WAL,
/// returning zero rows even though profiles existed. The reset path then
/// destroyed the store, silently losing the profiles.
@Suite("AppDelegate profile backup")
@MainActor
struct AppDelegateProfileBackupTests {

    private func makeTempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("TokenGardenTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func makeStoreWithProfileInWAL(
        in dir: URL,
        name: String,
        email: String
    ) throws -> URL {
        let storeURL = dir.appendingPathComponent("TokenGarden.store")
        var db: OpaquePointer?
        sqlite3_open(storeURL.path, &db)
        defer { sqlite3_close(db) }

        sqlite3_exec(db, "PRAGMA journal_mode=WAL", nil, nil, nil)
        sqlite3_exec(db, """
            CREATE TABLE ZPROFILE (
                Z_PK INTEGER PRIMARY KEY,
                ZNAME TEXT,
                ZEMAIL TEXT,
                ZPLAN TEXT,
                ZCREDENTIALSJSON BLOB,
                ZISACTIVE INTEGER,
                ZMONTHLYLIMIT INTEGER,
                ZCOLORNAME TEXT
            )
        """, nil, nil, nil)
        let insert = """
            INSERT INTO ZPROFILE (ZNAME, ZEMAIL, ZPLAN, ZCREDENTIALSJSON, ZISACTIVE, ZMONTHLYLIMIT, ZCOLORNAME)
            VALUES ('\(name)', '\(email)', 'max', X'7B7D', 1, 50000000, 'blue')
        """
        sqlite3_exec(db, insert, nil, nil, nil)
        return storeURL
    }

    @Test("backupProfiles reads rows even when they live only in the WAL")
    func backupProfilesChecksPointsWAL() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let storeURL = try makeStoreWithProfileInWAL(in: dir, name: "alice", email: "a@example.com")
        let result = AppDelegate.backupProfiles(from: storeURL)

        #expect(result.didReadDatabase == true)
        #expect(result.profiles.count == 1)
        #expect(result.profiles.first?.name == "alice")
        #expect(result.profiles.first?.email == "a@example.com")
    }

    @Test("backupProfiles returns didReadDatabase=false when file is missing")
    func backupProfilesMissingFile() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let missingStore = dir.appendingPathComponent("nope.store")
        let result = AppDelegate.backupProfiles(from: missingStore)

        #expect(result.didReadDatabase == false)
        #expect(result.profiles.isEmpty)
    }

    @Test("backupProfiles returns didReadDatabase=false when ZPROFILE is absent")
    func backupProfilesSchemaMismatch() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let storeURL = dir.appendingPathComponent("TokenGarden.store")
        var db: OpaquePointer?
        sqlite3_open(storeURL.path, &db)
        sqlite3_exec(db, "CREATE TABLE OTHER (id INTEGER)", nil, nil, nil)
        sqlite3_close(db)

        let result = AppDelegate.backupProfiles(from: storeURL)
        #expect(result.didReadDatabase == false)
        #expect(result.profiles.isEmpty)
    }

    @Test("archiveStoreFiles renames store + wal + shm instead of deleting")
    func archiveStoreFilesPreservesData() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let storeName = "TokenGarden.store"
        for suffix in ["", "-shm", "-wal"] {
            let path = dir.appendingPathComponent(storeName + suffix)
            try Data("payload-\(suffix)".utf8).write(to: path)
        }

        AppDelegate.archiveStoreFiles(in: dir, storeName: storeName)

        let remaining = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
        #expect(!remaining.contains(storeName))
        #expect(!remaining.contains(storeName + "-shm"))
        #expect(!remaining.contains(storeName + "-wal"))
        #expect(remaining.contains(where: { $0.hasPrefix("\(storeName).corrupted-") }))
        #expect(remaining.filter { $0.hasPrefix("\(storeName).corrupted-") }.count == 3)
    }
}
