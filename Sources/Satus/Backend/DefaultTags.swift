// © Shimon Shmueli
import Foundation

/// The seven default tag seeds used to populate a fresh installation
/// and to give the LLM semantic context during classification.
///
/// User-added or renamed tags don't get a description — the model uses
/// just the name in those cases. Available in both Free and Pro builds
/// because seeding happens unconditionally; only the classification
/// path that consumes descriptions is Pro-gated.
enum DefaultTags {

    struct Seed {
        let name: String
        let description: String
        let colorHex: String
    }

    static let all: [Seed] = [
        Seed(name: "Productivity",
             description: "Productivity — docs, notes, tasks, office, calendars",
             colorHex: "#007AFF"),
        Seed(name: "Creative",
             description: "Creative — design, AV/image editing, music production, 3D",
             colorHex: "#AF52DE"),
        Seed(name: "Development",
             description: "Development — IDEs, terminals, dev/API tooling",
             colorHex: "#34C759"),
        Seed(name: "Communication",
             description: "Communication — email, chat, calls, conferencing",
             colorHex: "#5AC8FA"),
        Seed(name: "Media",
             description: "Media — playback/consumption of video, music, podcasts, reading",
             colorHex: "#FF2D55"),
        Seed(name: "Utilities",
             description: "Utilities — launchers, window/clipboard managers, system tweaks, maintenance, security",
             colorHex: "#FF9500"),
        Seed(name: "Lifestyle",
             description: "Lifestyle — games, finance, health, social, shopping, reference",
             colorHex: "#FFCC00")
    ]

    /// Case-insensitive lookup. Used by the classifier so a tag the user
    /// kept named like a seed inherits its description in the prompt;
    /// a renamed seed drops it on purpose (its meaning may have changed).
    static func description(forName name: String) -> String? {
        let lower = name.lowercased()
        return all.first { $0.name.lowercased() == lower }?.description
    }
}
