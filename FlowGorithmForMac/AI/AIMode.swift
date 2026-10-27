// FlowGorithmForMac · Copyright © 2026 SkryxDev
// GNU GPL v3 with additional attribution terms: see LICENSE and NOTICE.

import SwiftUI

/// How the assistant helps. In study mode it explains and gives hints, so students find the
/// solution themselves; in auto mode it changes the chart for them.
enum AIMode: String {
    case study, auto

    /// The mode chosen in any window, read when a request is sent.
    static var current: AIMode {
        AIMode(rawValue: UserDefaults.standard.string(forKey: SettingsKey.aiMode) ?? "") ?? .auto
    }

    var title: LocalizedStringKey {
        switch self {
        case .study: "Study Mode"
        case .auto: "Auto Mode"
        }
    }

    var detail: LocalizedStringKey {
        switch self {
        case .study: "Explains and gives hints, never changes the chart"
        case .auto: "Changes the chart for you"
        }
    }

    var symbol: String {
        switch self {
        case .study: "graduationcap.fill"
        case .auto: "wand.and.stars"
        }
    }

    var color: Color {
        switch self {
        case .study: .teal
        case .auto: .accentColor
        }
    }
}

/// The mode, as a row with its name and a switch: to the left for study, to the right for auto.
struct AIModeSwitch: View {
    @AppStorage(SettingsKey.aiMode) private var stored = AIMode.auto.rawValue

    var mode: AIMode { AIMode(rawValue: stored) ?? .auto }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: mode.symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(mode.color)
                .frame(width: 18)
                .contentTransition(.symbolEffect(.replace))
            VStack(alignment: .leading, spacing: 1) {
                Text(mode.title)
                    .font(.callout.weight(.semibold))
                Text(mode.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            ModeSwitch(isAuto: Binding(get: { mode == .auto },
                                       set: { stored = ($0 ? AIMode.auto : .study).rawValue }))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(mode.color.opacity(0.08))
        .animation(.snappy(duration: 0.25), value: mode)
        .accessibilityElement(children: .combine)
        .accessibilityValue(Text(mode.title))
    }
}

/// An on/off switch whose track takes the color of the mode it points to.
private struct ModeSwitch: View {
    @Binding var isAuto: Bool

    var body: some View {
        Button {
            isAuto.toggle()
        } label: {
            Capsule()
                .fill((isAuto ? AIMode.auto : AIMode.study).color.gradient)
                .frame(width: 38, height: 22)
                .overlay(alignment: isAuto ? .trailing : .leading) {
                    Circle()
                        .fill(.white)
                        .shadow(color: .black.opacity(0.25), radius: 1.5, y: 1)
                        .padding(2)
                }
                .animation(.snappy(duration: 0.22), value: isAuto)
        }
        .buttonStyle(.plain)
        .help(isAuto ? "Switch to Study Mode: hints only" : "Switch to Auto Mode: the assistant changes the chart")
        .accessibilityLabel(Text("Auto Mode"))
        .accessibilityValue(Text(isAuto ? "On" : "Off"))
    }
}
