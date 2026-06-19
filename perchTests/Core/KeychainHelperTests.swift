// perchTests/Core/KeychainHelperTests.swift
import Foundation
import Testing

@testable import perch

@Suite("KeychainHelper")
@MainActor
struct KeychainHelperTests {
    private let testKey = "perch-test-keychain-\(UUID().uuidString)"

    init() {
        // 各テストインスタンス生成時に前の値を削除してクリーンスタート
        KeychainHelper.delete(forKey: testKey)
    }

    @Test("save and load round-trip")
func saveAndLoad() throws {
    defer { KeychainHelper.delete(forKey: testKey) }
    try KeychainHelper.save("secret-value", forKey: testKey)
    let loaded = KeychainHelper.load(forKey: testKey)
    #expect(loaded == "secret-value")
}

    @Test("load returns nil for missing key")
    func loadMissingReturnsNil() {
        let loaded = KeychainHelper.load(forKey: "perch-test-nonexistent-\(UUID())")
        #expect(loaded == nil)
    }

    @Test("overwrite replaces existing value")
func overwriteReplaces() throws {
    defer { KeychainHelper.delete(forKey: testKey) }
    try KeychainHelper.save("first", forKey: testKey)
    try KeychainHelper.save("second", forKey: testKey)
    let loaded = KeychainHelper.load(forKey: testKey)
    #expect(loaded == "second")
}

    @Test("delete removes the value")
    func deleteRemoves() throws {
        try KeychainHelper.save("to-delete", forKey: testKey)
        KeychainHelper.delete(forKey: testKey)
        let loaded = KeychainHelper.load(forKey: testKey)
        #expect(loaded == nil)
    }

    @Test("delete non-existent key is safe")
    func deleteNonExistentIsSafe() {
        // Should not throw or crash
        KeychainHelper.delete(forKey: "perch-test-no-such-key-\(UUID())")
    }

    @Test("empty string saves and loads correctly")
    func emptyStringRoundTrip() throws {
        try KeychainHelper.save("", forKey: testKey)
        let loaded = KeychainHelper.load(forKey: testKey)
        #expect(loaded == "")
    }
}
