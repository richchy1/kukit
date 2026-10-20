import Foundation

public struct GradeBand: Codable, Equatable, Hashable, Sendable, Identifiable {
    public var id: UUID
    /// Lowest percent that earns this band.
    public var minPercent: Double
    public var label: String
    public var gpaPoints: Double

    public init(id: UUID = UUID(), minPercent: Double, label: String, gpaPoints: Double) {
        self.id = id
        self.minPercent = minPercent
        self.label = label
        self.gpaPoints = gpaPoints
    }
}

public enum PercentRounding: String, Codable, Sendable, CaseIterable {
    /// Use the exact percent for the band lookup.
    case none
    /// Round to the nearest whole percent first (many courses report integer totals).
    case nearest
}

public enum ScaleIssue: Equatable, Sendable {
    case noBands
    case missingZeroBand
    case duplicateThreshold(Double)
    case thresholdOutOfRange
    case emptyLabel
    case pointsOutOfRange(label: String)
    case invalidGPAMax

    public var message: String {
        switch self {
        case .noBands: "Add at least one band."
        case .missingZeroBand: "The lowest band must start at 0%."
        case .duplicateThreshold(let value): "Two bands start at \(Self.format(value))%."
        case .thresholdOutOfRange: "Bands must start between 0% and 100%."
        case .emptyLabel: "Every band needs a label."
        case .pointsOutOfRange(let label): "\(label.isEmpty ? "A band" : label) has GPA points above the maximum or below 0."
        case .invalidGPAMax: "The GPA maximum must be above 0."
        }
    }

    private static func format(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...2)))
    }
}

/// A grading scale: percent → letter → GPA points. Entirely user-defined data.
public struct GradeScale: Codable, Equatable, Sendable {
    public var name: String
    public var gpaMax: Double
    public var rounding: PercentRounding
    public var bands: [GradeBand]

    public init(name: String, gpaMax: Double, rounding: PercentRounding = .none, bands: [GradeBand]) {
        self.name = name
        self.gpaMax = gpaMax
        self.rounding = rounding
        self.bands = bands
    }

    /// Removes floating-point noise (94.99999999999999 → 95) and applies the rounding mode.
    public func normalized(_ percent: Double) -> Double {
        let cleaned = (percent * 1_000_000).rounded() / 1_000_000
        switch rounding {
        case .none: return cleaned
        case .nearest: return cleaned.rounded(.toNearestOrAwayFromZero)
        }
    }

    /// The band a percent falls into: the highest band whose threshold it reaches.
    public func band(for percent: Double) -> GradeBand? {
        let value = normalized(percent)
        return bands.sorted { $0.minPercent > $1.minPercent }.first { value >= $0.minPercent }
    }

    public func issues() -> [ScaleIssue] {
        var found: [ScaleIssue] = []
        if gpaMax <= 0 { found.append(.invalidGPAMax) }
        if bands.isEmpty { return found + [.noBands] }
        if !bands.contains(where: { $0.minPercent == 0 }) { found.append(.missingZeroBand) }
        var seen = Set<Double>()
        for band in bands {
            if band.minPercent < 0 || band.minPercent > 100 { found.append(.thresholdOutOfRange) }
            if !seen.insert(band.minPercent).inserted { found.append(.duplicateThreshold(band.minPercent)) }
            if band.label.trimmingCharacters(in: .whitespaces).isEmpty { found.append(.emptyLabel) }
            if band.gpaPoints < 0 || band.gpaPoints > gpaMax { found.append(.pointsOutOfRange(label: band.label)) }
        }
        return found
    }

    public var isValid: Bool { issues().isEmpty }

    /// The default scale: Korean 4.5 (A+ 95 → 4.5 … F below 60).
    public static let korean45 = GradeScale(
        name: "Korean (4.5)", gpaMax: 4.5, rounding: .none,
        bands: [
            GradeBand(minPercent: 95, label: "A+", gpaPoints: 4.5),
            GradeBand(minPercent: 90, label: "A0", gpaPoints: 4.0),
            GradeBand(minPercent: 85, label: "B+", gpaPoints: 3.5),
            GradeBand(minPercent: 80, label: "B0", gpaPoints: 3.0),
            GradeBand(minPercent: 75, label: "C+", gpaPoints: 2.5),
            GradeBand(minPercent: 70, label: "C0", gpaPoints: 2.0),
            GradeBand(minPercent: 65, label: "D+", gpaPoints: 1.5),
            GradeBand(minPercent: 60, label: "D0", gpaPoints: 1.0),
            GradeBand(minPercent: 0, label: "F", gpaPoints: 0.0),
        ]
    )
}
