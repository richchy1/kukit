import Foundation

/// Where Chef Kukit is speaking. Each context has a handful of lines; the caller passes a seed
/// (a date, a session start…) so the line is stable while a screen is open but varies over time.
public enum ChefContext: String, CaseIterable, Sendable {
    case dashboardMorning, dashboardAfternoon, dashboardEvening, dashboardLate
    case sessionStart, working, sessionComplete, breakTime
    case taskComplete, goalComplete
    case emptyTasks, emptyCourses, emptyNotes, emptyHistory
    case firstSession, recordDay

    /// The dashboard greeting that fits an hour of the day (0–23).
    public static func dashboard(hour: Int) -> ChefContext {
        switch hour {
        case 5..<12: .dashboardMorning
        case 12..<18: .dashboardAfternoon
        case 18..<23: .dashboardEvening
        default: .dashboardLate
        }
    }
}

public enum ChefMessages {
    /// A contextual line. `seed` picks which one (any Int; negatives are fine).
    public static func message(_ context: ChefContext, seed: Int) -> String {
        let options = lines[context] ?? []
        guard !options.isEmpty else { return "" }
        let index = ((seed % options.count) + options.count) % options.count
        return options[index]
    }

    /// The same moment without the jokes, for people who turn the humor off.
    public static func plain(_ context: ChefContext) -> String {
        switch context {
        case .dashboardMorning: "Good morning"
        case .dashboardAfternoon: "Good afternoon"
        case .dashboardEvening: "Good evening"
        case .dashboardLate: "Working late"
        case .sessionStart: "Focus session started"
        case .working: "Focus session in progress"
        case .sessionComplete: "Session complete"
        case .breakTime: "Break time"
        case .taskComplete: "Task completed"
        case .goalComplete: "Daily goal reached"
        case .emptyTasks: "Nothing scheduled"
        case .emptyCourses: "No courses yet"
        case .emptyNotes: "No notes yet"
        case .emptyHistory: "No sessions yet"
        case .firstSession: "First session completed"
        case .recordDay: "New personal best"
        }
    }

    static let lines: [ChefContext: [String]] = [
        .dashboardMorning: [
            "What's cooking today?",
            "Good morning, chef. The kitchen is yours.",
            "Fresh day, clean counters. Let's make something.",
            "Rise and simmer.",
        ],
        .dashboardAfternoon: [
            "Your future isn't going to cook itself.",
            "Lunch break is over. The ingredients are not.",
            "Halfway through the day. Still time to cook.",
            "What's on the menu this afternoon?",
        ],
        .dashboardEvening: [
            "Let's make something of this semester.",
            "Evening service is open.",
            "Dinner rush: assignments edition.",
            "One good session before the lights go out?",
        ],
        .dashboardLate: [
            "Cooking after midnight? Bold. Mind the smoke alarm.",
            "The late shift. Respect.",
            "Sleep is also an ingredient, chef.",
        ],
        .sessionStart: [
            "Chef mode: ON.",
            "The kitchen is open. Distractions are not.",
            "Let's cook.",
            "Apron on. Phone down.",
        ],
        .working: [
            "Currently cooking. Please do not disturb.",
            "Your assignment is getting nervous.",
            "Stay focused. The ingredients won't prepare themselves.",
            "Low heat, steady focus.",
            "Do not open the oven door.",
        ],
        .sessionComplete: [
            "Cooked. Absolutely cooked.",
            "One session closer to academic survival.",
            "That went straight into the cookbook.",
            "Plated and served.",
        ],
        .breakTime: [
            "The chef deserves a break.",
            "Touch grass. Hydrate. Return stronger.",
            "Let it simmer.",
            "Taste-test a snack. Not your phone.",
        ],
        .taskComplete: [
            "Ingredient prepared.",
            "One less thing haunting your dreams.",
            "Another academic disaster successfully prevented.",
            "Chopped, diced, done.",
        ],
        .goalComplete: [
            "Today's meal is served.",
            "Five-star performance, chef.",
            "The academic kitchen has been conquered.",
            "Daily goal: cooked.",
        ],
        .emptyTasks: [
            "Nothing on the menu. Time to prep tomorrow's ingredients?",
            "No tasks scheduled. Suspiciously calm.",
            "Prepare today's ingredients: add a task.",
        ],
        .emptyCourses: [
            "An empty pantry. Add your first course to start cooking.",
            "No courses yet. Even chefs need a menu.",
        ],
        .emptyNotes: [
            "A blank recipe card. Write the first page.",
            "No notes yet. Today's lecture won't write itself down.",
        ],
        .emptyHistory: [
            "No dishes served yet. Start a session and fill the cookbook.",
            "The cookbook is empty. For now.",
        ],
        .firstSession: [
            "First dish served. The cookbook has its first page.",
            "You cooked something. It begins.",
        ],
        .recordDay: [
            "New personal best. The kitchen is on fire (the good kind).",
            "Record day. Michelin-level focus.",
        ],
    ]
}
