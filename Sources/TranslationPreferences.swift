import Foundation

/// Translation tone presets for the LM Studio refinement. `technical` is the default — the
/// speaker is mostly dictating software work, so precision and correct terminology win.
enum Tone: String, CaseIterable, Identifiable {
    case technical, polished, formal, casual, literal

    var id: String { rawValue }

    var label: String {
        switch self {
        case .technical: return "Technical"
        case .polished: return "Polished"
        case .formal: return "Formal"
        case .casual: return "Casual"
        case .literal: return "Literal"
        }
    }

    var instruction: String {
        switch self {
        case .technical:
            return "Use precise, professional, technical English appropriate for software engineering. Prefer exact technical terminology and correct names for APIs, data structures, systems, and architecture; choose the specific term over a general one. Be unambiguous and concise; avoid casual phrasing, hedging, and marketing language. Where the speaker named a technical concept imprecisely, use the correct term — but never invent specifics they did not say."
        case .polished: return "Produce clean, natural, idiomatic English."
        case .formal: return "Use formal, professional English suitable for business writing."
        case .casual: return "Use relaxed, conversational English."
        case .literal: return "Prefer the speaker's own terms and sentence shapes where they are already precise; do not paraphrase beyond what grammar and correctness require."
        }
    }
}

/// UserDefaults-backed access to the tone + glossary, shared between the SettingsView
/// (`@AppStorage`, same keys) and the RecorderViewModel.
enum TranslationPreferences {
    static let toneKey = "translationTone"
    static let glossaryKey = "translationGlossary"
    static let modelKey = "translationModel"

    /// LM Studio model id used by default — Qwen3-8B (MLX), a strong multilingual model
    /// with good Serbian coverage and reliable instruction-following. This is the exact
    /// id LM Studio reports for the bundled download; override in Settings to match
    /// whatever you load.
    static let defaultModel = "qwen/qwen3-8b"

    static var tone: Tone {
        Tone(rawValue: UserDefaults.standard.string(forKey: toneKey) ?? "") ?? .technical
    }

    static var glossary: String {
        UserDefaults.standard.string(forKey: glossaryKey) ?? ""
    }

    static var model: String {
        let value = UserDefaults.standard.string(forKey: modelKey) ?? ""
        return value.isEmpty ? defaultModel : value
    }
}
