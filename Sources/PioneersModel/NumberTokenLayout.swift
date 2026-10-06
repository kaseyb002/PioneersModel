import Foundation

/// Controls how production numbers are distributed across a newly created board.
public enum NumberTokenLayout: String, Equatable, Codable, CaseIterable, Sendable {
    /// Places the official letter-ordered token sequence counterclockwise from the outside in,
    /// skipping deserts. This is the normal variable-board CATAN setup.
    case standardSpiral

    /// Shuffles the tokens while enforcing the official restriction that red numbers (6 and 8)
    /// may not occupy adjacent tiles.
    case randomSeparatedRed
}
