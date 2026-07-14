import Testing
import Foundation
@testable import TimeLedger

struct ThoughtDraftStoreTests {
    private func makeSuite() -> (UserDefaults, ThoughtDraftStore) {
        let suiteName = "ThoughtDraftStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return (defaults, ThoughtDraftStore(defaults: defaults))
    }

    @Test func loadReturnsEmptyWhenMissing() {
        let (_, store) = makeSuite()
        #expect(store.load(.quickCapture) == "")
        #expect(store.load(.addToEntry) == "")
    }

    @Test func saveAndLoadRoundTripPerKey() {
        let (_, store) = makeSuite()
        store.save("快速想法草稿", for: .quickCapture)
        store.save("条目补充草稿", for: .addToEntry)

        #expect(store.load(.quickCapture) == "快速想法草稿")
        #expect(store.load(.addToEntry) == "条目补充草稿")
    }

    @Test func clearOnlyAffectsThatKey() {
        let (_, store) = makeSuite()
        store.save("A", for: .quickCapture)
        store.save("B", for: .addToEntry)

        store.clear(.quickCapture)

        #expect(store.load(.quickCapture) == "")
        #expect(store.load(.addToEntry) == "B")
    }

    @Test func saveWhitespaceOnlyClearsDraft() {
        let (_, store) = makeSuite()
        store.save("有内容", for: .quickCapture)
        store.save("   \n\t  ", for: .quickCapture)

        #expect(store.load(.quickCapture) == "")
    }

    @Test func saveEmptyStringClearsDraft() {
        let (_, store) = makeSuite()
        store.save("有内容", for: .addToEntry)
        store.save("", for: .addToEntry)

        #expect(store.load(.addToEntry) == "")
    }
}
