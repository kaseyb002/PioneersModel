import Foundation

public typealias PortID = Int

public struct Port: Equatable, Codable, Identifiable, Sendable {
    public let id: PortID
    public let kind: Kind
    /// The two vertex IDs at which a building can claim this port.
    public let vertexIDs: [VertexID]

    public enum Kind: Equatable, Codable, Sendable {
        /// Generic 3-for-1 port: trade any 3 of the same resource for 1 of any other.
        case generic
        /// Specific 2-for-1 port: trade 2 of the named resource for 1 of any other.
        case specific(Resource)

        public var ratio: Int {
            switch self {
            case .generic: 3
            case .specific: 2
            }
        }

        public var requiredResource: Resource? {
            switch self {
            case .generic: nil
            case .specific(let r): r
            }
        }

        public var displayableName: String {
            switch self {
            case .generic: "3:1 Port"
            case .specific(let r): "2:1 \(r.displayableName) Port"
            }
        }
    }

    public init(
        id: PortID,
        kind: Kind,
        vertexIDs: [VertexID]
    ) {
        self.id = id
        self.kind = kind
        self.vertexIDs = vertexIDs
    }
}

extension Port {
    public static func fake(
        id: PortID = 0,
        kind: Kind = .generic,
        vertexIDs: [VertexID] = [0, 1]
    ) -> Port {
        Port(
            id: id,
            kind: kind,
            vertexIDs: vertexIDs
        )
    }
}
