import Foundation
import XCTest
@testable import CalibreKit

/// `GET /community/today` — the shape after the lanes split, confirmed against
/// Backend/app/api/views/community.py's `CommunityTodayView`.
final class CommunityTodayTests: XCTestCase {
    private let json = """
    {
      "today": {
        "id": "s",
        "question": "What should we build next?",
        "kind": "site_feedback",
        "options": [{"key": "search", "label": "Better search"}, {"key": "alerts", "label": "Price alerts"}],
        "asked_on": "2026-08-26",
        "closed": false,
        "my_vote": null,
        "results": null
      },
      "today_by_kind": {
        "watch": {
          "id": "w",
          "question": "Gold or steel?",
          "kind": "watch",
          "options": [{"key": "gold", "label": "Gold"}, {"key": "steel", "label": "Steel"}],
          "asked_on": "2026-08-26",
          "closed": false,
          "my_vote": null,
          "results": null
        },
        "site_feedback": {
          "id": "s",
          "question": "What should we build next?",
          "kind": "site_feedback",
          "options": [{"key": "search", "label": "Better search"}, {"key": "alerts", "label": "Price alerts"}],
          "asked_on": "2026-08-26",
          "closed": false,
          "my_vote": null,
          "results": null
        }
      },
      "recent": [
        {
          "id": "old",
          "question": "Which crown guard?",
          "kind": "watch",
          "options": [{"key": "gold", "label": "Gold"}, {"key": "steel", "label": "Steel"}],
          "asked_on": "2026-08-25",
          "closed": true,
          "my_vote": "steel",
          "results": {
            "total_votes": 2,
            "options": [
              {"key": "gold", "label": "Gold", "votes": 1, "percent": 50},
              {"key": "steel", "label": "Steel", "votes": 1, "percent": 50}
            ]
          }
        }
      ]
    }
    """

    private func decoded() throws -> CommunityToday {
        try apiDecoder().decode(CommunityToday.self, from: Data(json.utf8))
    }

    func testBothLanesDecodeAndAskInOrder() throws {
        let today = try decoded()

        XCTAssertEqual(today.lanes.map(\.kind), [.watch, .siteFeedback])
        XCTAssertEqual(today.liveLanes.map(\.prompt?.question), ["Gold or steel?", "What should we build next?"])
        XCTAssertTrue(today.dryLanes.isEmpty)
        XCTAssertEqual(today.recent.first?.askedOn, "2026-08-25")
    }

    func testTheLanesSayWhichInvitationTheyAre() throws {
        let today = try decoded()
        let watch = try XCTUnwrap(today.todayByKind.watch)
        let feedback = try XCTUnwrap(today.todayByKind.siteFeedback)

        XCTAssertNotEqual(watch.voice.eyebrow, feedback.voice.eyebrow)
        XCTAssertNotEqual(watch.voice.invitation, feedback.voice.invitation)
        XCTAssertFalse(watch.voice.invitation.isEmpty)
        XCTAssertFalse(feedback.voice.invitation.isEmpty)
    }

    func testAClosedQuestionIsLabelledByTheLaneItWasAskedIn() throws {
        let past = try XCTUnwrap(try decoded().recent.first)

        XCTAssertTrue(past.closed)
        XCTAssertEqual(past.voice.closedEyebrow, CommunityPromptKind.watch.voice.closedEyebrow)
        XCTAssertNotEqual(past.voice.closedEyebrow, CommunityPromptKind.siteFeedback.voice.closedEyebrow)
    }

    func testALaneWithNothingToAskIsStillALane() throws {
        // The whole reason `dryLanes` exists: one bank can empty while the
        // other keeps asking, and the screen names the one that ran dry rather
        // than quietly showing a single question.
        let oneLane = """
        {"today": null, "today_by_kind": {"watch": {"id": "w", "question": "Gold or steel?", "kind": "watch",
          "options": [{"key": "gold", "label": "Gold"}], "asked_on": "2026-08-26", "closed": false,
          "my_vote": null, "results": null}, "site_feedback": null}, "recent": []}
        """
        let today = try apiDecoder().decode(CommunityToday.self, from: Data(oneLane.utf8))

        XCTAssertEqual(today.liveLanes.map(\.kind), [.watch])
        XCTAssertEqual(today.dryLanes.map(\.kind), [.siteFeedback])
        XCTAssertEqual(today.dryLanes.first?.voice.emptyLane, CommunityPromptKind.siteFeedback.voice.emptyLane)
    }

    func testAKindThisBuildHasNeverHeardOfStillRenders() throws {
        // A lane added on the server closes questions into `recent` before this
        // build knows its name; an unnamed lane is still a question somebody
        // answered.
        let voice = CommunityPromptVoice.forKind("something_new")

        XCTAssertEqual(voice.eyebrow, "Question of the day")
        XCTAssertTrue(voice.invitation.isEmpty)
    }

    func testAVoteLandsInTheLaneItCameFrom() throws {
        let today = try decoded()
        let votedJSON = """
        {"id": "w", "question": "Gold or steel?", "kind": "watch",
         "options": [{"key": "gold", "label": "Gold"}, {"key": "steel", "label": "Steel"}],
         "asked_on": "2026-08-26", "closed": false, "my_vote": "gold",
         "results": {"total_votes": 1, "options": [{"key": "gold", "label": "Gold", "votes": 1, "percent": 100}]}}
        """
        let voted = try apiDecoder().decode(CommunityPrompt.self, from: Data(votedJSON.utf8))

        let folded = today.replacing(voted)

        XCTAssertEqual(folded.todayByKind.watch?.myVote, "gold")
        // The other lane is untouched — a vote in one is not an answer in both.
        XCTAssertNil(folded.todayByKind.siteFeedback?.myVote)
    }
}
