import XCTest

@testable import Rewound
@testable import RewoundKit

/// The (?) sentences and the grade definitions are written once, in the
/// frontend's `src/content/`, and copied into Swift verbatim (contracts,
/// 2026-09-29). A copy that drifts is the site and the app telling a buyer two
/// different things about the same grade, and nothing on either screen would
/// look wrong.
final class SharedWordingParityTests: XCTestCase {

    // MARK: - The grades, pinned

    /// The five definitions a buyer reads above every Condition grading table,
    /// written out here from `conditionGrades.ts` so this holds on a machine
    /// with no frontend checkout beside the app.
    func testTheGradeDefinitionsAreTheSitesWordForWord() {
        let expected: [(grade: String, description: String)] = [
            ("New", "Unworn or unused, with no visible wear."),
            ("Like New", "Little to no visible wear; presents extremely close to new."),
            ("Very Good", "Light visible wear from careful use but still very clean overall."),
            ("Good", "Normal visible wear from regular use; remains presentable and wearable."),
            ("Worn", "Heavy wear, damage, or condition issues that are clearly disclosed before purchase."),
        ]
        XCTAssertEqual(ConditionGrades.definitions.count, expected.count)
        for (definition, want) in zip(ConditionGrades.definitions, expected) {
            XCTAssertEqual(definition.grade, want.grade)
            XCTAssertEqual(definition.description, want.description, "\(want.grade)")
        }
    }

    /// The scale the listing explains is the scale the sell form offers, in
    /// the same order: a sixth grade on one side would be a grade with no
    /// definition, or a definition nobody can pick.
    func testTheDefinedGradesAreTheGradesASellerCanPick() {
        XCTAssertEqual(ConditionGrades.definitions.map(\.grade), ConditionPart.grades)
    }

    func testEveryPartAndEveryAngleHasItsSentence() {
        for part in ConditionPart.allCases {
            XCTAssertNotNil(SellFieldHelp.gradePart(part), "\(part.rawValue) has no (?) sentence")
        }
        for category in ListingImageCategory.allCases {
            XCTAssertNotNil(SellFieldHelp.photoAngle(category), "\(category.rawValue) has no (?) sentence")
        }
        XCTAssertEqual(SellFieldHelp.gradeParts.count, ConditionPart.allCases.count)
        XCTAssertEqual(SellFieldHelp.photoAngles.count, ListingImageCategory.allCases.count)
    }

    /// The standing copy rule, on everything these files put in front of a
    /// person: no em dashes.
    func testNoSharedSentenceCarriesAnEmDash() {
        let all = Array(SpecHelp.sentences.values)
            + Array(SellFieldHelp.fields.values)
            + Array(SellFieldHelp.gradeParts.values)
            + Array(SellFieldHelp.photoAngles.values)
            + ConditionGrades.definitions.flatMap { [$0.grade, $0.description, $0.points] }
        XCTAssertFalse(all.isEmpty)
        for sentence in all {
            XCTAssertFalse(sentence.contains("\u{2014}"), sentence)
        }
    }

    // MARK: - Against the source itself

    /// Every sentence, compared with the TypeScript it was copied from, when
    /// the frontend is checked out beside this repo (as it is in development).
    /// Skipped, and said so, where it is not.
    func testEverySwiftCopyMatchesTheFrontendSource() throws {
        let specHelp = try frontendStrings("specHelp.ts")
        let sellHelp = try frontendStrings("sellFieldHelp.ts")
        // From the array on: the type above it spells the five grades too.
        let gradesSource = try frontendSource("conditionGrades.ts")
        let arrayStart = try XCTUnwrap(gradesSource.range(of: "export const CONDITION_GRADE_DEFINITIONS"))
        let grades = pairs(in: String(gradesSource[arrayStart.lowerBound...]))

        // specHelp.ts is one flat object.
        XCTAssertFalse(specHelp.isEmpty)
        XCTAssertEqual(Set(specHelp.map(\.key)), Set(SpecHelp.sentences.keys))
        for (key, value) in specHelp {
            XCTAssertEqual(SpecHelp.sentences[key], value, "specHelp.\(key)")
        }

        // sellFieldHelp.ts is three objects. Two share keys (`dial`, `bezel`,
        // `caseback`, `clasp`...), so each is read out of its own block.
        let source = try frontendSource("sellFieldHelp.ts")
        let fields = pairs(in: block(named: "SELL_FIELD_HELP", in: source))
        let parts = pairs(in: block(named: "SELL_GRADE_PART_HELP", in: source))
        let angles = pairs(in: block(named: "SELL_PHOTO_HELP", in: source))
        XCTAssertEqual(fields.count + parts.count + angles.count, sellHelp.count)
        XCTAssertEqual(Dictionary(uniqueKeysWithValues: fields), SellFieldHelp.fields)
        XCTAssertEqual(Dictionary(uniqueKeysWithValues: parts), SellFieldHelp.gradeParts)
        XCTAssertEqual(Dictionary(uniqueKeysWithValues: angles), SellFieldHelp.photoAngles)

        // conditionGrades.ts: grade, description, points, five times over.
        let values = grades.filter { ["grade", "description", "points"].contains($0.key) }.map(\.value)
        let swift = ConditionGrades.definitions.flatMap { [$0.grade, $0.description, $0.points] }
        XCTAssertEqual(values, swift)
    }

    // MARK: - Reading the TypeScript

    private func frontendSource(_ file: String) throws -> String {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // RewoundTests
            .deletingLastPathComponent() // ios
            .deletingLastPathComponent() // the checkout root
            .appending(path: "frontend/src/content/\(file)")
        guard let text = try? String(contentsOf: url, encoding: .utf8) else {
            throw XCTSkip("No frontend checkout at \(url.path); the pinned tests above still hold.")
        }
        return text
    }

    private func frontendStrings(_ file: String) throws -> [(key: String, value: String)] {
        pairs(in: try frontendSource(file))
    }

    /// `key: "value"` pairs, in order, where a value may start on the line
    /// after its key. None of these sentences contains a double quote.
    private func pairs(in source: String) -> [(key: String, value: String)] {
        let pattern = #"([A-Za-z_]+):\s*"([^"\n]*)""#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(source.startIndex..., in: source)
        return regex.matches(in: source, range: range).compactMap { match in
            guard let key = Range(match.range(at: 1), in: source),
                  let value = Range(match.range(at: 2), in: source) else { return nil }
            return (String(source[key]), String(source[value]))
        }
    }

    /// The body of `export const NAME = { ... }`.
    private func block(named name: String, in source: String) -> String {
        guard let start = source.range(of: "export const \(name) = {"),
              let end = source.range(of: "} as const", range: start.upperBound..<source.endIndex) else {
            XCTFail("\(name) not found in sellFieldHelp.ts")
            return ""
        }
        return String(source[start.upperBound..<end.lowerBound])
    }
}
