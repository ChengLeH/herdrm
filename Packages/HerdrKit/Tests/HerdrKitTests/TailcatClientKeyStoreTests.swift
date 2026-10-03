import HerdrTailcat
import Security
import XCTest

@testable import HerdrKit

final class TailcatClientKeyStoreTests: XCTestCase {
    /// The store is app-wide (one Keychain item), so a test run would clobber
    /// the developer's real client key; stash it and put it back afterwards.
    private var savedItem: Data?

    override func setUpWithError() throws {
        savedItem = readRawItem()
        deleteRawItem()
    }

    override func tearDownWithError() throws {
        deleteRawItem()
        if let savedItem { writeRawItem(savedItem) }
    }

    func testEnsureGeneratesOneKeyAndKeepsIt() throws {
        let first = try TailcatClientKeyStore.ensure()
        XCTAssertTrue(first.hasPrefix("privkey:"), "got \(first)")
        XCTAssertEqual(try TailcatClientKeyStore.ensure(), first, "the identity must be stable across calls")
        XCTAssertEqual(readRawItem().map { String(decoding: $0, as: UTF8.self) }, first)
    }

    func testPublicKeyIsTheNodekeyOfTheStoredKey() throws {
        let publicKey = try TailcatClientKeyStore.publicKey()
        XCTAssertTrue(publicKey.hasPrefix("nodekey:"), "got \(publicKey)")
        XCTAssertEqual(
            publicKey,
            try TailcatBridge.publicKey(ofClientKey: TailcatClientKeyStore.ensure())
        )
    }

    func testRegenerateReplacesTheKey() throws {
        let oldKey = try TailcatClientKeyStore.ensure()
        let oldPublic = try TailcatClientKeyStore.publicKey()

        let newPublic = try TailcatClientKeyStore.regenerate()

        XCTAssertNotEqual(try TailcatClientKeyStore.ensure(), oldKey)
        XCTAssertNotEqual(newPublic, oldPublic)
        XCTAssertEqual(newPublic, try TailcatClientKeyStore.publicKey())
    }

    /// A damaged stored key is an identity problem the user must see (and fix
    /// with Regenerate); silently minting a new one would change the identity
    /// every allow list knows.
    func testACorruptStoredKeyIsReportedNotReplaced() throws {
        writeRawItem(Data("garbage".utf8))

        XCTAssertThrowsError(try TailcatClientKeyStore.publicKey())
        XCTAssertEqual(readRawItem(), Data("garbage".utf8))
    }

    /// The bridge must be started with the stored client key: a corrupt key
    /// makes ensureUp fail instead of silently connecting with an ephemeral one.
    func testEnsureUpPassesTheClientKeyToTheBridge() async throws {
        let id = UUID()
        defer {
            TailcatCredentialStore.removeToken(for: id)
            Task { await TailcatBridgeManager.shared.tearDown(deviceID: id) }
        }
        try TailcatCredentialStore.setToken("tcp-test-token", for: id)
        writeRawItem(Data("garbage".utf8))

        do {
            _ = try await TailcatBridgeManager.shared.ensureUp(deviceID: id)
            XCTFail("expected tailcatBridgeFailed for a corrupt client key")
        } catch let error as HerdrError {
            guard case .tailcatBridgeFailed = error else {
                return XCTFail("expected tailcatBridgeFailed, got \(error)")
            }
        }
    }

    // MARK: - Raw Keychain access, bypassing the store under test

    private var query: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: TailcatClientKeyStore.service,
            kSecAttrAccount as String: TailcatClientKeyStore.account,
        ]
    }

    private func readRawItem() -> Data? {
        var query = query
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess else { return nil }
        return item as? Data
    }

    private func writeRawItem(_ data: Data) {
        deleteRawItem()
        var query = query
        query[kSecValueData as String] = data
        SecItemAdd(query as CFDictionary, nil)
    }

    private func deleteRawItem() {
        SecItemDelete(query as CFDictionary)
    }
}
