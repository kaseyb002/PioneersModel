import Foundation

extension Player {
    public static func fake(
        id: PlayerID = UUID().uuidString,
        name: String = "Player",
        imageURL: URL? = nil,
        color: PlayerColor = .blue
    ) -> Player {
        Player(
            id: id,
            name: name,
            imageURL: imageURL,
            color: color
        )
    }
}
