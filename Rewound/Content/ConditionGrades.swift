/// One of the five condition grades and what it means.
struct ConditionGradeDefinition: Equatable, Sendable {
    /// "New", "Like New", "Very Good", "Good" or "Worn": the words the server
    /// stores and every screen prints.
    let grade: String
    /// One sentence a buyer reads beside the grade.
    let description: String
    /// What that looks like on a real watch.
    let points: String
}

/// The five condition grades and what each one means.
///
/// Copied verbatim from `frontend/src/content/conditionGrades.ts`, which is the
/// source for every surface that explains the scale: the listing's Condition
/// grading section, the sell form's (?) on its Condition heading, and the
/// site's authentication page. Change a sentence there and here together,
/// never here alone. `SharedWordingParityTests` holds the two to each other.
enum ConditionGrades {
    static let definitions: [ConditionGradeDefinition] = [
        ConditionGradeDefinition(
            grade: "New",
            description: "Unworn or unused, with no visible wear.",
            points: "No visible scratches, no wrist wear, stickers may still be present, major parts appear untouched."
        ),
        ConditionGradeDefinition(
            grade: "Like New",
            description: "Little to no visible wear; presents extremely close to new.",
            points: "Very light handling marks only, clean crystal, sharp bezel, minimal bracelet stretch."
        ),
        ConditionGradeDefinition(
            grade: "Very Good",
            description: "Light visible wear from careful use but still very clean overall.",
            points: "Light surface scratches, minor clasp or bracelet marks, no major chips or cracks."
        ),
        ConditionGradeDefinition(
            grade: "Good",
            description: "Normal visible wear from regular use; remains presentable and wearable.",
            points: "Noticeable scratches, moderate bracelet or clasp wear, minor dents, possible bezel fading."
        ),
        ConditionGradeDefinition(
            grade: "Worn",
            description: "Heavy wear, damage, or condition issues that are clearly disclosed before purchase.",
            points: "Deep scratches, heavy dents, chipped or cracked crystal, heavy bracelet stretch, or missing parts."
        ),
    ]
}
