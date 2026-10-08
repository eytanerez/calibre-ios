#if DEBUG
import RewatchDesign
import RewatchKit
import SwiftUI

/// The builder with nothing behind it: `-listingBuilderPreview` opens it on
/// the demo backend (a small catalog, the published commission rule, uploads
/// on a timer, nothing written), the app's twin of the site's
/// `/design/listing-builder`. `-listingBuilderStep <step>` opens it on that
/// step with every earlier answer filled in, so each screen can be looked at
/// without signing in.
struct ListingBuilderPreviewHarness: View {
    @State private var model: ListingBuilderModel = Self.makeModel()
    @State private var finished = false

    var body: some View {
        Group {
            if finished {
                VStack(spacing: Space.m) {
                    Text("Back on the seller dashboard")
                        .font(RewatchType.sectionTitle)
                    Button("List another") {
                        model = Self.makeModel()
                        finished = false
                    }
                    .buttonStyle(.rewatch(.secondary))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .rewatchPageBackground()
            } else {
                ListingBuilderScreen(model: model) { finished = true }
            }
        }
        .tint(Color.rewatch.primary)
    }

    @MainActor
    static func makeModel() -> ListingBuilderModel {
        let model = ListingBuilderModel(kind: .new(prefill: nil), backend: DemoListingBuilderBackend())
        let arguments = ProcessInfo.processInfo.arguments
        guard let flag = arguments.firstIndex(of: "-listingBuilderStep"),
              arguments.indices.contains(flag + 1),
              let step = BuilderStep(rawValue: arguments[flag + 1]) else { return model }
        let partsDiffer = arguments.contains("-listingBuilderPartsDiffer")
        fill(model, through: step, partsDiffer: partsDiffer)
        Task { @MainActor in
            await model.start()
            if step.index > BuilderStep.photos.index {
                // As if the seller had left the photo step: the draft and the
                // background uploads are under way.
                await model.syncPhotos()
            }
            model.previewJump(to: step)
        }
        return model
    }

    /// Every answer before `step`, as a seller might have given them.
    @MainActor
    private static func fill(_ model: ListingBuilderModel, through step: BuilderStep, partsDiffer: Bool) {
        var answers = BuilderAnswers()
        let past = { (other: BuilderStep) in step.index > other.index }
        if past(.watch) || step == .watch {
            answers.brand = "Rolex"
            answers.model = "Submariner Date"
            answers.reference = "126610LN"
        }
        if past(.year) {
            answers.year = "2021"
            answers.sku = "A-1042"
        }
        if past(.condition) || (step == .condition && partsDiffer) {
            answers.grade = "Very Good"
            answers.partsMatch = partsDiffer ? false : true
            if partsDiffer {
                for part in BuilderRules.parts { answers.parts[part.rawValue] = "Very Good" }
                answers.parts["case"] = "Good"
                answers.parts["bracelet"] = "Good"
                answers.conditionNotes["case"] = "Light desk marks on the lugs"
            }
            answers.conditionNotes["overall"] = "Worn gently, never polished"
        }
        if step == .condition, !partsDiffer, ProcessInfo.processInfo.arguments.contains("-listingBuilderGradeChosen") {
            answers.grade = "Very Good"
        }
        if past(.box) {
            answers.box = true
            answers.papers = true
            answers.notes = "Comes with the original green service pouch and two spare links."
        }
        if past(.history) {
            answers.polish = "unpolished"
            answers.originality = "all_original"
            answers.serviceHistory = "serviced"
            answers.serviceYear = "2023"
        }
        if past(.price) || step == .price {
            answers.priceText = "12,450"
        }
        if past(.returns) {
            answers.returns = .hours48
        }
        model.answers = answers
        if past(.photos) || (step == .photos && ProcessInfo.processInfo.arguments.contains("-listingBuilderSomePhotos")) {
            let samples = PhotoPipeline.sampleImages()
            let take = past(.photos) ? samples : Array(samples.prefix(3))
            for (category, image) in take {
                if let jpeg = try? ListingPhotoPrep.jpeg(from: image) {
                    model.setPhoto(jpeg, for: category)
                }
            }
        }
    }
}
#endif
