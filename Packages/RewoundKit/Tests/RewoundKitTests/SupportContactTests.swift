import Foundation
import XCTest
@testable import RewoundKit

/// The support conversation's heading, and the person answering it.
///
/// Both are derived from the payload at render. Who the contacts are, how many
/// there are and what they are called is the server's alone
/// (`app/services/support_contacts.py`), so anything this app remembers about
/// them is something that goes wrong quietly the day the desk changes.
final class SupportContactTests: XCTestCase {

    private func conversation(createdAt: String, messages: String = "[]", contact: String = "null") throws
        -> SupportConversation
    {
        let json = """
        {"id": "t1", "status": "open", "created_at": \(createdAt),
         "last_message_at": null, "messages": \(messages),
         "assigned_contact": \(contact)}
        """
        return try apiDecoder().decode(SupportConversation.self, from: Data(json.utf8))
    }

    private let oneMessage = """
    [{"id": "m1", "sender": "customer", "body": "Hello", "created_at": "2026-09-07T12:00:00Z"}]
    """

    /// The heading is when the conversation started — never its first message.
    ///
    /// Naming a thread after its opening line repeats a sentence already on
    /// screen as the first message, and tells the customer something they
    /// wrote themselves.
    func testTheHeadingIsTheDateNotTheFirstMessage() throws {
        let thread = try conversation(createdAt: "\"2026-09-07T12:00:00Z\"", messages: oneMessage)
        let now = try XCTUnwrap(
            Calendar.current.date(from: DateComponents(year: 2026, month: 9, day: 20))
        )
        let title = thread.title(now: now)

        XCTAssertTrue(title.hasPrefix("Support \u{00B7} "), "expected a Support · date heading, got \(title)")
        XCTAssertFalse(title.contains("Hello"), "the opening line is not the heading")
        XCTAssertFalse(title.contains("2026"), "the year is left off within the same year")

        // A conversation started in another year says which one.
        let older = try conversation(createdAt: "\"2025-03-04T12:00:00Z\"", messages: oneMessage)
        XCTAssertTrue(older.title(now: now).contains("2025"), older.title(now: now))
    }

    /// A thread with nothing in it is not named after a day it did not have.
    func testAnEmptyThreadIsANewConversation() throws {
        let empty = try conversation(createdAt: "\"2026-09-07T12:00:00Z\"")
        XCTAssertEqual(empty.title(), "New conversation")
    }

    /// Not started and undated are two different absences.
    ///
    /// A thread carrying messages has started, whatever the payload says about
    /// when. Calling it new tells a customer with an open case that nothing has
    /// happened. Web (`supportThreadTitle`) and Android
    /// (`supportConversationTitle`) both fall back to "Support" here, and this
    /// is the assertion that keeps the three of them saying it the same way.
    func testAStartedThreadWithNoDateIsNotCalledNew() throws {
        let undated = try conversation(createdAt: "null", messages: oneMessage)
        XCTAssertEqual(undated.title(), "Support")
    }

    /// The initials are derived from whatever name the server sent.
    ///
    /// No table of people, no stored monogram: the first and last letters of
    /// the assigned contact's own name, worked out where they are drawn.
    func testInitialsComeFromTheAssignedContactsName() throws {
        func initials(_ displayName: String) throws -> String {
            let thread = try conversation(
                createdAt: "\"2026-09-07T12:00:00Z\"",
                contact: "{\"key\": \"k\", \"display_name\": \"\(displayName)\"}"
            )
            return try XCTUnwrap(thread.assignedContact).initials
        }

        XCTAssertEqual(try initials("Moshe Adler"), "MA")
        XCTAssertEqual(try initials("Dana"), "DA")
        // First and last, not the first two — a middle name does not take a slot.
        XCTAssertEqual(try initials("Ada Rose Kaplan"), "AK")
        XCTAssertEqual(try initials("  "), "?")
    }

    /// An empty name is not a name, and nothing downstream should draw it.
    func testAnEmptyNameReadsAsNoContact() throws {
        let blank = try conversation(
            createdAt: "\"2026-09-07T12:00:00Z\"",
            contact: "{\"key\": \"k\", \"display_name\": \"   \"}"
        )
        XCTAssertNil(try XCTUnwrap(blank.assignedContact).name)

        let missing = try conversation(createdAt: "\"2026-09-07T12:00:00Z\"")
        XCTAssertNil(missing.assignedContact)
    }
}
