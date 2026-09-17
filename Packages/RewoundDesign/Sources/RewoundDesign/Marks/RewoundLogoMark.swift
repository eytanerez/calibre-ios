import SwiftUI

/// The Rewound mark itself, as geometry.
///
/// Not one of the vocabulary marks and not a ninth one — this is the logo, and
/// it is here because it is where the vocabulary's grid, stroke weight and cap
/// style are all measured from. `RewoundWordmark` is the word set in Playfair;
/// this is the drawing.
///
/// The paths are the traced original, ported and not re-drawn: two filled
/// outlines on a 1024×1024 grid (the source artwork's own square), converted
/// from its SVG path data with no re-fitting — a second, slightly different
/// mark would put two logos into the world instead of one.
public struct RewoundLogoMark: View {
    let size: CGFloat

    public init(size: CGFloat = RewoundMark.defaultSize) {
        self.size = size
    }

    public var body: some View {
        Self.outline
            .fill(Color.rewound.primary)
            .frame(width: Self.gridSide, height: Self.gridSide)
            .scaleEffect(size / Self.gridSide)
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }

    /// The side of the square the geometry below is authored on — the source
    /// artwork's own 1024×1024 viewBox, not the vocabulary's 120 grid, since
    /// this is a filled outline rather than a stroked centerline.
    static let gridSide: CGFloat = 1024

    static var outline: Path {
        var path = Path()

        // Outline path 0
        path.move(to: CGPoint(x: 542.540, y: 663.455))
        path.addCurve(to: CGPoint(x: 475.302, y: 591.039), control1: CGPoint(x: 519.943, y: 639.166), control2: CGPoint(x: 497.375, y: 615.328))
        path.addCurve(to: CGPoint(x: 436.064, y: 533.518), control1: CGPoint(x: 459.581, y: 573.740), control2: CGPoint(x: 444.968, y: 555.511))
        path.addCurve(to: CGPoint(x: 437.652, y: 444.614), control1: CGPoint(x: 423.985, y: 503.685), control2: CGPoint(x: 422.419, y: 473.759))
        path.addCurve(to: CGPoint(x: 511.980, y: 395.189), control1: CGPoint(x: 453.252, y: 414.768), control2: CGPoint(x: 478.338, y: 397.715))
        path.addCurve(to: CGPoint(x: 576.123, y: 430.075), control1: CGPoint(x: 537.353, y: 393.283), control2: CGPoint(x: 563.680, y: 404.591))
        path.addCurve(to: CGPoint(x: 577.763, y: 468.825), control1: CGPoint(x: 582.263, y: 442.650), control2: CGPoint(x: 582.893, y: 455.676))
        path.addCurve(to: CGPoint(x: 574.889, y: 472.781), control1: CGPoint(x: 577.175, y: 470.330), control2: CGPoint(x: 576.812, y: 472.079))
        path.addCurve(to: CGPoint(x: 571.656, y: 468.938), control1: CGPoint(x: 572.614, y: 472.561), control2: CGPoint(x: 572.332, y: 470.578))
        path.addCurve(to: CGPoint(x: 514.723, y: 440.316), control1: CGPoint(x: 562.373, y: 446.443), control2: CGPoint(x: 540.506, y: 435.450))
        path.addCurve(to: CGPoint(x: 476.866, y: 487.082), control1: CGPoint(x: 493.454, y: 444.330), control2: CGPoint(x: 477.513, y: 464.514))
        path.addCurve(to: CGPoint(x: 533.598, y: 537.329), control1: CGPoint(x: 476.033, y: 516.164), control2: CGPoint(x: 500.438, y: 541.152))
        path.addCurve(to: CGPoint(x: 586.584, y: 515.186), control1: CGPoint(x: 553.627, y: 535.019), control2: CGPoint(x: 571.364, y: 528.457))
        path.addCurve(to: CGPoint(x: 592.084, y: 392.964), control1: CGPoint(x: 622.299, y: 484.046), control2: CGPoint(x: 624.906, y: 427.279))
        path.addCurve(to: CGPoint(x: 522.502, y: 361.094), control1: CGPoint(x: 573.133, y: 373.150), control2: CGPoint(x: 549.769, y: 362.929))
        path.addCurve(to: CGPoint(x: 429.169, y: 394.944), control1: CGPoint(x: 486.377, y: 358.664), control2: CGPoint(x: 455.241, y: 370.083))
        path.addCurve(to: CGPoint(x: 399.814, y: 447.181), control1: CGPoint(x: 414.147, y: 409.268), control2: CGPoint(x: 403.421, y: 426.352))
        path.addCurve(to: CGPoint(x: 399.159, y: 461.129), control1: CGPoint(x: 399.026, y: 451.733), control2: CGPoint(x: 399.162, y: 456.475))
        path.addCurve(to: CGPoint(x: 399.022, y: 785.105), control1: CGPoint(x: 399.090, y: 569.121), control2: CGPoint(x: 399.062, y: 677.113))
        path.addCurve(to: CGPoint(x: 398.925, y: 797.103), control1: CGPoint(x: 399.020, y: 789.105), control2: CGPoint(x: 399.129, y: 793.112))
        path.addCurve(to: CGPoint(x: 371.737, y: 823.405), control1: CGPoint(x: 398.093, y: 813.454), control2: CGPoint(x: 387.431, y: 823.719))
        path.addCurve(to: CGPoint(x: 346.936, y: 796.298), control1: CGPoint(x: 357.414, y: 823.117), control2: CGPoint(x: 347.060, y: 812.016))
        path.addCurve(to: CGPoint(x: 346.923, y: 733.303), control1: CGPoint(x: 346.769, y: 775.301), control2: CGPoint(x: 346.915, y: 754.301))
        path.addCurve(to: CGPoint(x: 347.175, y: 495.821), control1: CGPoint(x: 346.954, y: 654.142), control2: CGPoint(x: 346.513, y: 574.977))
        path.addCurve(to: CGPoint(x: 348.080, y: 329.856), control1: CGPoint(x: 347.638, y: 440.499), control2: CGPoint(x: 347.661, y: 385.177))
        path.addCurve(to: CGPoint(x: 380.129, y: 295.650), control1: CGPoint(x: 348.218, y: 311.628), control2: CGPoint(x: 363.147, y: 295.776))
        path.addCurve(to: CGPoint(x: 403.101, y: 317.580), control1: CGPoint(x: 393.167, y: 295.553), control2: CGPoint(x: 402.729, y: 304.526))
        path.addCurve(to: CGPoint(x: 403.081, y: 342.575), control1: CGPoint(x: 403.338, y: 325.905), control2: CGPoint(x: 403.076, y: 334.243))
        path.addCurve(to: CGPoint(x: 404.425, y: 348.243), control1: CGPoint(x: 403.082, y: 344.508), control2: CGPoint(x: 402.512, y: 346.616))
        path.addCurve(to: CGPoint(x: 410.639, y: 344.628), control1: CGPoint(x: 407.258, y: 348.421), control2: CGPoint(x: 408.730, y: 346.018))
        path.addCurve(to: CGPoint(x: 499.082, y: 312.461), control1: CGPoint(x: 437.044, y: 325.407), control2: CGPoint(x: 466.434, y: 314.693))
        path.addCurve(to: CGPoint(x: 595.093, y: 332.061), control1: CGPoint(x: 532.965, y: 310.144), control2: CGPoint(x: 565.352, y: 315.291))
        path.addCurve(to: CGPoint(x: 664.345, y: 434.742), control1: CGPoint(x: 635.123, y: 354.632), control2: CGPoint(x: 658.956, y: 388.754))
        path.addCurve(to: CGPoint(x: 631.158, y: 540.890), control1: CGPoint(x: 669.052, y: 474.905), control2: CGPoint(x: 658.701, y: 510.822))
        path.addCurve(to: CGPoint(x: 549.265, y: 581.327), control1: CGPoint(x: 609.214, y: 564.845), control2: CGPoint(x: 581.554, y: 577.985))
        path.addCurve(to: CGPoint(x: 534.813, y: 582.218), control1: CGPoint(x: 544.468, y: 581.824), control2: CGPoint(x: 539.631, y: 581.926))
        path.addCurve(to: CGPoint(x: 530.551, y: 584.473), control1: CGPoint(x: 533.321, y: 582.308), control2: CGPoint(x: 531.769, y: 582.276))
        path.addCurve(to: CGPoint(x: 546.497, y: 598.549), control1: CGPoint(x: 534.615, y: 590.331), control2: CGPoint(x: 540.345, y: 594.732))
        path.addCurve(to: CGPoint(x: 581.285, y: 603.319), control1: CGPoint(x: 557.332, y: 605.273), control2: CGPoint(x: 569.175, y: 605.634))
        path.addCurve(to: CGPoint(x: 682.360, y: 537.265), control1: CGPoint(x: 624.016, y: 595.149), control2: CGPoint(x: 657.433, y: 572.536))
        path.addCurve(to: CGPoint(x: 713.909, y: 423.433), control1: CGPoint(x: 706.454, y: 503.170), control2: CGPoint(x: 715.826, y: 464.802))
        path.addCurve(to: CGPoint(x: 575.804, y: 243.692), control1: CGPoint(x: 709.960, y: 338.172), control2: CGPoint(x: 655.968, y: 268.945))
        path.addCurve(to: CGPoint(x: 478.523, y: 234.844), control1: CGPoint(x: 544.038, y: 233.685), control2: CGPoint(x: 511.586, y: 231.418))
        path.addCurve(to: CGPoint(x: 366.717, y: 276.988), control1: CGPoint(x: 437.498, y: 239.097), control2: CGPoint(x: 400.239, y: 253.004))
        path.addCurve(to: CGPoint(x: 303.439, y: 347.581), control1: CGPoint(x: 340.391, y: 295.824), control2: CGPoint(x: 320.032, y: 320.049))
        path.addCurve(to: CGPoint(x: 267.562, y: 357.565), control1: CGPoint(x: 295.781, y: 360.285), control2: CGPoint(x: 280.404, y: 364.767))
        path.addCurve(to: CGPoint(x: 259.255, y: 323.164), control1: CGPoint(x: 255.691, y: 350.908), control2: CGPoint(x: 251.950, y: 335.983))
        path.addCurve(to: CGPoint(x: 319.120, y: 250.696), control1: CGPoint(x: 274.993, y: 295.544), control2: CGPoint(x: 294.982, y: 271.409))
        path.addCurve(to: CGPoint(x: 458.005, y: 188.323), control1: CGPoint(x: 359.285, y: 216.229), control2: CGPoint(x: 405.752, y: 195.567))
        path.addCurve(to: CGPoint(x: 627.846, y: 210.624), control1: CGPoint(x: 516.563, y: 180.205), control2: CGPoint(x: 573.716, y: 184.868))
        path.addCurve(to: CGPoint(x: 744.140, y: 329.595), control1: CGPoint(x: 681.122, y: 235.975), control2: CGPoint(x: 719.671, y: 276.014))
        path.addCurve(to: CGPoint(x: 766.035, y: 445.327), control1: CGPoint(x: 760.922, y: 366.342), control2: CGPoint(x: 767.812, y: 405.104))
        path.addCurve(to: CGPoint(x: 702.431, y: 593.125), control1: CGPoint(x: 763.506, y: 502.545), control2: CGPoint(x: 743.438, y: 552.506))
        path.addCurve(to: CGPoint(x: 607.330, y: 644.285), control1: CGPoint(x: 675.860, y: 619.445), control2: CGPoint(x: 643.835, y: 636.162))
        path.addCurve(to: CGPoint(x: 606.839, y: 644.369), control1: CGPoint(x: 607.168, y: 644.321), control2: CGPoint(x: 606.987, y: 644.305))
        path.addCurve(to: CGPoint(x: 600.279, y: 647.035), control1: CGPoint(x: 604.628, y: 645.328), control2: CGPoint(x: 601.081, y: 644.286))
        path.addCurve(to: CGPoint(x: 604.376, y: 653.354), control1: CGPoint(x: 599.436, y: 649.926), control2: CGPoint(x: 602.651, y: 651.484))
        path.addCurve(to: CGPoint(x: 622.890, y: 672.998), control1: CGPoint(x: 610.475, y: 659.969), control2: CGPoint(x: 616.726, y: 666.443))
        path.addCurve(to: CGPoint(x: 721.496, y: 777.880), control1: CGPoint(x: 655.761, y: 707.956), control2: CGPoint(x: 688.611, y: 742.935))
        path.addCurve(to: CGPoint(x: 722.274, y: 815.963), control1: CGPoint(x: 732.460, y: 789.530), control2: CGPoint(x: 732.835, y: 805.901))
        path.addCurve(to: CGPoint(x: 683.005, y: 813.885), control1: CGPoint(x: 711.060, y: 826.649), control2: CGPoint(x: 694.109, y: 825.801))
        path.addCurve(to: CGPoint(x: 600.252, y: 724.957), control1: CGPoint(x: 655.400, y: 784.261), control2: CGPoint(x: 627.876, y: 754.563))
        path.addCurve(to: CGPoint(x: 542.540, y: 663.455), control1: CGPoint(x: 581.153, y: 704.488), control2: CGPoint(x: 561.942, y: 684.124))
        path.closeSubpath()

        // Outline path 1 — the jewel-like counter inside the spiral
        path.move(to: CGPoint(x: 498.201, y: 472.378))
        path.addCurve(to: CGPoint(x: 530.087, y: 456.317), control1: CGPoint(x: 505.772, y: 460.393), control2: CGPoint(x: 516.631, y: 454.714))
        path.addCurve(to: CGPoint(x: 557.579, y: 479.845), control1: CGPoint(x: 543.956, y: 457.968), control2: CGPoint(x: 553.627, y: 466.080))
        path.addCurve(to: CGPoint(x: 533.257, y: 519.871), control1: CGPoint(x: 562.686, y: 497.636), control2: CGPoint(x: 551.494, y: 515.840))
        path.addCurve(to: CGPoint(x: 494.554, y: 493.455), control1: CGPoint(x: 515.202, y: 523.862), control2: CGPoint(x: 497.470, y: 511.626))
        path.addCurve(to: CGPoint(x: 498.201, y: 472.378), control1: CGPoint(x: 493.363, y: 486.036), control2: CGPoint(x: 494.718, y: 479.262))
        path.closeSubpath()

        return path
    }

    /// The pre-rebrand watch-crown centerline this package's stamp and
    /// wax-seal effects were built on. Kept as reusable line-art geometry —
    /// those effects borrow its shape for a die/impression look and are not
    /// "the logo" the way `outline` above is; re-drawing them against the R
    /// would be a different design change than swapping the displayed mark.
    ///
    /// Source, on the `0 0 120 120` viewBox:
    ///
    ///     arc          M 94.52 85.34 A 43.36 42.55 -98.29 1 1 94.67 31.55
    ///     bridge upper M 50.57 19.9  C 45.51 28.12 51.52 42.06 56.2 46.26
    ///     bridge lower M 56.36 70.82 C 52.15 75.01 45.65 88.14 50.29 96.17
    ///     jewel ring   circle cx 60.48 cy 58.52 r 10.71
    static var strokes: Path {
        var path = Path()

        path.addEllipticalArc(
            center: CGPoint(x: 61.2149, y: 58.1656),
            radii: CGSize(width: 43.36, height: 42.55),
            rotation: .degrees(-98.29),
            start: .degrees(136.9632),
            delta: .degrees(283.29)
        )

        path.move(to: CGPoint(x: 50.57, y: 19.9))
        path.addCurve(
            to: CGPoint(x: 56.2, y: 46.26),
            control1: CGPoint(x: 45.51, y: 28.12),
            control2: CGPoint(x: 51.52, y: 42.06)
        )

        path.move(to: CGPoint(x: 56.36, y: 70.82))
        path.addCurve(
            to: CGPoint(x: 50.29, y: 96.17),
            control1: CGPoint(x: 52.15, y: 75.01),
            control2: CGPoint(x: 45.65, y: 88.14)
        )

        path.addEllipse(in: CGRect(
            x: 60.48 - 10.71, y: 58.52 - 10.71,
            width: 10.71 * 2, height: 10.71 * 2
        ))

        return path
    }

    /// `circle cx 60.48 cy 58.52 r 4.88`, filled — paired with `strokes` above.
    static var jewelCentre: Path {
        Path(ellipseIn: CGRect(
            x: 60.48 - 4.88, y: 58.52 - 4.88,
            width: 4.88 * 2, height: 4.88 * 2
        ))
    }
}

#Preview("Logo mark", traits: .sizeThatFitsLayout) {
    HStack(spacing: Space.xl) {
        RewoundLogoMark(size: 120)
        RewoundLogoMark(size: 56)
        RewoundLogoMark(size: 24)
    }
    .padding(Space.xl)
    .rewoundPageBackground()
}
