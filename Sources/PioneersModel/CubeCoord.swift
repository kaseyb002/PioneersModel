import Foundation

/// A cube coordinate for a hex tile. Invariant: `x + y + z == 0`.
///
/// Use as a compact way to identify both tiles (board positions) and their neighbors when
/// computing the vertex/edge graph. Not tied to any particular rendering orientation.
public struct CubeCoord: Equatable, Hashable, Codable, Sendable, Comparable {
    public let x: Int
    public let y: Int
    public let z: Int

    public init(x: Int, y: Int, z: Int) {
        self.x = x
        self.y = y
        self.z = z
    }

    public static func < (lhs: CubeCoord, rhs: CubeCoord) -> Bool {
        if lhs.x != rhs.x { return lhs.x < rhs.x }
        if lhs.y != rhs.y { return lhs.y < rhs.y }
        return lhs.z < rhs.z
    }

    public static func + (lhs: CubeCoord, rhs: CubeCoord) -> CubeCoord {
        CubeCoord(x: lhs.x + rhs.x, y: lhs.y + rhs.y, z: lhs.z + rhs.z)
    }

    /// Six neighbor-direction deltas, in order (used for corner/edge indexing).
    public static let directions: [CubeCoord] = [
        CubeCoord(x: +1, y: 0, z: -1),
        CubeCoord(x: +1, y: -1, z: 0),
        CubeCoord(x: 0, y: -1, z: +1),
        CubeCoord(x: -1, y: 0, z: +1),
        CubeCoord(x: -1, y: +1, z: 0),
        CubeCoord(x: 0, y: +1, z: -1),
    ]
}
