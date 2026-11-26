import XCTest
import UserNotifications
@testable import DressJetShop

@MainActor final class PushSyncTests: XCTestCase {
    final class Store: PushStoring { var installId = "inst-1"; var written: PushWritten?; var pendingDelete: PendingDelete?; var lastPromptAt: Date?; var pendingToken: String? }
    final class Writer: PushWriting {
        var ok = true; var upserts: [(String, String, [String: String])] = []; var deletes: [(String, String)] = []
        func upsert(uid: String, installId: String, fields: [String: String]) async -> Bool { if ok { upserts.append((uid, installId, fields)) }; return ok }
        func delete(uid: String, installId: String) async -> Bool { if ok { deletes.append((uid, installId)) }; return ok }
    }
    func make(_ s: Store, _ w: Writer, v: String = "1.0(9)") -> PushSync { PushSync(store: s, writer: w, env: "production", appVersion: v, now: { Date(timeIntervalSince1970: 7) }) }

    func testGuestKeepsPending() async {
        let s = Store(), w = Writer()
        let o = await make(s, w).tokenArrived("01", uid: nil)
        XCTAssertEqual(o, .skipped("guest")); XCTAssertEqual(s.pendingToken, "01"); XCTAssertTrue(w.upserts.isEmpty)
    }
    func testSignInWritesDeviceDoc() async {
        let s = Store(), w = Writer(), p = make(s, w)
        _ = await p.tokenArrived("01", uid: nil)
        let o = await p.sync(uid: "u1")
        XCTAssertEqual(o, .written); XCTAssertEqual(w.upserts[0].0, "u1"); XCTAssertEqual(w.upserts[0].1, "inst-1")
        XCTAssertEqual(w.upserts[0].2, ["token": "01", "platform": "ios", "env": "production", "appVersion": "1.0(9)", "updatedAt": "7000"])
    }
    func testDedupeRotationVersion() async {
        let s = Store(), w = Writer(), p = make(s, w)
        var o = await p.tokenArrived("01", uid: "u1"); XCTAssertEqual(o, .written)
        o = await p.sync(uid: "u1"); XCTAssertEqual(o, .skipped("unchanged"))
        o = await p.tokenArrived("02", uid: "u1"); XCTAssertEqual(o, .written)
        o = await make(s, w, v: "1.1(10)").sync(uid: "u1"); XCTAssertEqual(o, .written)
        XCTAssertEqual(w.upserts.count, 3)
    }
    func testFailedWriteRetries() async {
        let s = Store(), w = Writer(); w.ok = false; let p = make(s, w)
        var o = await p.tokenArrived("01", uid: "u1"); XCTAssertEqual(o, .failed); XCTAssertNil(s.written)
        w.ok = true; o = await p.sync(uid: "u1"); XCTAssertEqual(o, .written)
    }
    func testSignOutDeletes() async {
        let s = Store(), w = Writer(), p = make(s, w); _ = await p.tokenArrived("01", uid: "u1")
        let o = await p.onSignOut(uid: "u1")
        XCTAssertEqual(o, .deleted); XCTAssertEqual(w.deletes.count, 1); XCTAssertNil(s.written); XCTAssertNil(s.pendingDelete)
    }
    func testSignOutFailurePersistsPending() async {

        let s = Store(), w = Writer(), p = make(s, w); _ = await p.tokenArrived("01", uid: "u1")
        let bad = Writer(); bad.ok = false
        let o = await p.onSignOut(uid: "u1", deleter: bad)
        XCTAssertEqual(o, .failed); XCTAssertEqual(s.pendingDelete, PendingDelete(uid: "u1", installId: "inst-1")); XCTAssertNil(s.written)
    }
    func testSignOutUsesCapturedWriter() async {
        let s = Store(), live = Writer(), cap = Writer(), p = make(s, live); _ = await p.tokenArrived("01", uid: "u1")
        live.ok = false
        let o = await p.onSignOut(uid: "u1", deleter: cap); XCTAssertEqual(o, .deleted); XCTAssertEqual(cap.deletes.count, 1); XCTAssertTrue(live.deletes.isEmpty)
    }
    func testNewUidBlockedWhileDeletePending() async {
        let s = Store(), w = Writer(), p = make(s, w); _ = await p.tokenArrived("01", uid: "u1")
        let bad = Writer(); bad.ok = false; _ = await p.onSignOut(uid: "u1", deleter: bad)
        let o = await p.sync(uid: "u2"); XCTAssertEqual(o, .skipped("old owner device doc not deleted")); XCTAssertEqual(w.upserts.count, 1)
    }
    func testNewUidBlockedIfNeverSignedOut() async {
        let s = Store(), w = Writer(), p = make(s, w); _ = await p.tokenArrived("01", uid: "u1")
        let o = await p.sync(uid: "u2"); XCTAssertEqual(o, .skipped("previous owner not signed out")); XCTAssertEqual(w.upserts.count, 1)
    }
    func testNewUidAllowedAfterDelete() async {
        let s = Store(), w = Writer(), p = make(s, w); _ = await p.tokenArrived("01", uid: "u1"); _ = await p.onSignOut(uid: "u1")
        let o = await p.sync(uid: "u2"); XCTAssertEqual(o, .written); XCTAssertEqual(w.upserts.last?.0, "u2"); XCTAssertEqual(w.upserts.last?.1, "inst-1")
    }
    func testSameUidRetryAndSupersede() async {
        let s = Store(), w = Writer(), p = make(s, w); _ = await p.tokenArrived("01", uid: "u1")
        let bad = Writer(); bad.ok = false; _ = await p.onSignOut(uid: "u1", deleter: bad)
        var o = await p.retryPendingDelete(uid: "u2"); XCTAssertEqual(o, .skipped("pending is for another uid"))
        o = await p.retryPendingDelete(uid: "u1"); XCTAssertEqual(o, .deleted); XCTAssertNil(s.pendingDelete)
        s.pendingDelete = PendingDelete(uid: "u1", installId: "inst-1")
        o = await p.sync(uid: "u1"); XCTAssertEqual(o, .written); XCTAssertNil(s.pendingDelete)
    }
    func testDeleteAccount() async {
        let s = Store(), w = Writer(), p = make(s, w); _ = await p.tokenArrived("01", uid: "u1")
        w.ok = false; var o = await p.onDeleteAccount(uid: "u1"); XCTAssertEqual(o, .failed); XCTAssertNotNil(s.written)
        w.ok = true; o = await p.onDeleteAccount(uid: "u1"); XCTAssertEqual(o, .deleted); XCTAssertNil(s.written)
    }
    func testMaskHex() {

        XCTAssertEqual(DevicePayload.mask(["b", "a"]), "updateMask.fieldPaths=a&updateMask.fieldPaths=b"); XCTAssertEqual(DevicePayload.hex(Data([0x0a, 0xff])), "0aff")
    }
    func testPromptPolicyUnchanged() {
        let now = Date(timeIntervalSince1970: 100 * 86400)
        func s(_ st: UNAuthorizationStatus = .notDetermined, _ t: PromptTrigger = .signedIn, last: Date? = nil, first: Bool = false) -> Bool {
            PushPrompt.shouldShow(status: st, trigger: t, now: now, lastPromptAt: last, firstLaunch: first) }
        XCTAssertTrue(s()); XCTAssertFalse(s(.denied)); XCTAssertFalse(s(first: true)); XCTAssertTrue(s(.notDetermined, .launch, first: true)); XCTAssertTrue(s(.notDetermined, .orderPlaced)); XCTAssertFalse(s(.denied, .launch, first: true)); XCTAssertFalse(s(last: now.addingTimeInterval(-29 * 86400))); XCTAssertTrue(s(last: now.addingTimeInterval(-31 * 86400)))
    }
}

