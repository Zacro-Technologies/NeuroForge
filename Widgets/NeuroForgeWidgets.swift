import SwiftUI
import WidgetKit

private struct NeuroForgeEntry: TimelineEntry {
    let date: Date
    let snapshot: NFWidgetSnapshot
}

private struct NeuroForgeProvider: TimelineProvider {
    func placeholder(in context: Context) -> NeuroForgeEntry {
        NeuroForgeEntry(date: .now, snapshot: .placeholder)
    }

    func getSnapshot(in context: Context, completion: @escaping (NeuroForgeEntry) -> Void) {
        completion(NeuroForgeEntry(date: .now, snapshot: NFWidgetSnapshotStore.read() ?? .placeholder))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<NeuroForgeEntry>) -> Void) {
        let snapshot = NFWidgetSnapshotStore.read() ?? emptySnapshot
        let nextRefresh = Calendar.current.date(byAdding: .minute, value: 30, to: .now) ?? .now.addingTimeInterval(1_800)
        completion(Timeline(entries: [NeuroForgeEntry(date: .now, snapshot: snapshot)], policy: .after(nextRefresh)))
    }

    private var emptySnapshot: NFWidgetSnapshot {
        NFWidgetSnapshot(
            schemaVersion: NFWidgetSnapshot.schemaVersion,
            language: .english,
            generatedAt: .now,
            localDayKey: "today",
            scheduledMinutes: 0,
            completedItems: 0,
            expectedItems: 0,
            reviewsDue: 0,
            blocks: []
        )
    }
}

private struct NeuroForgeWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: NeuroForgeEntry

    private var presentation: NFWidgetPresentation {
        NFWidgetPresentation(snapshot: entry.snapshot)
    }

    var body: some View {
        Group {
            switch family {
            case .systemMedium:
                mediumView
            case .accessoryCircular:
                accessoryCircularView
            case .accessoryInline:
                accessoryInlineView
            case .accessoryRectangular:
                accessoryRectangularView
            default:
                smallView
            }
        }
        .environment(\.locale, presentation.locale)
        .widgetURL(entry.snapshot.planState.deepLink)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: presentation.accessibilityLabel))
        .containerBackground(for: .widget) {
            LinearGradient(
                colors: [Color(red: 0.10, green: 0.11, blue: 0.24), Color(red: 0.18, green: 0.10, blue: 0.30)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }

    private var smallView: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label {
                Text(verbatim: presentation.todayTitle)
            } icon: {
                Image(systemName: "brain.head.profile.fill")
            }
                .font(.headline)
            Text(verbatim: presentation.planDateLabel)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
            progressRing
                .frame(width: 62, height: 62)
            Text(verbatim: presentation.actionTitle)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private var mediumView: some View {
        HStack(spacing: 18) {
            VStack(alignment: .leading, spacing: 8) {
                Label {
                    Text(verbatim: presentation.todayTitle)
                } icon: {
                    Image(systemName: "brain.head.profile.fill")
                }
                    .font(.headline)
                Text(verbatim: presentation.planDateLabel)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                progressRing.frame(width: 72, height: 72)
                Text(verbatim: presentation.actionTitle)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            Divider().overlay(.white.opacity(0.2))
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(entry.snapshot.blocks.prefix(3).enumerated()), id: \.offset) { _, block in
                    HStack(spacing: 8) {
                        Image(systemName: block.isComplete ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(block.isComplete ? .primary : .secondary)
                        Text(verbatim: block.title).font(.subheadline.weight(.semibold))
                        Spacer()
                        Text(verbatim: presentation.duration(block.minutes, style: .compact))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
                if entry.snapshot.blocks.isEmpty {
                    Text(verbatim: presentation.emptyPlanInstruction)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .privacySensitive()
        }
    }

    private var accessoryCircularView: some View {
        Gauge(value: entry.snapshot.progress) {
            Image(systemName: "brain.head.profile")
        } currentValueLabel: {
            Text(verbatim: presentation.progressPercent)
        }
        .gaugeStyle(.accessoryCircularCapacity)
    }

    private var accessoryInlineView: some View {
        Label {
            Text(verbatim: presentation.accessorySummary)
        } icon: {
            Image(systemName: "brain.head.profile")
        }
    }

    private var accessoryRectangularView: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label {
                Text(verbatim: "NeuroForge")
            } icon: {
                Image(systemName: "brain.head.profile")
            }
            ProgressView(value: entry.snapshot.progress)
            Text(verbatim: presentation.accessorySummary).font(.caption2)
        }
    }

    private var progressRing: some View {
        ZStack {
            Circle().stroke(.white.opacity(0.16), lineWidth: 8)
            if entry.snapshot.planState != .noPlan {
                Circle()
                    .trim(from: 0, to: entry.snapshot.progress)
                    .stroke(.cyan, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text(verbatim: presentation.progressPercent)
                    .font(.caption.bold().monospacedDigit())
            } else {
                Image(systemName: "calendar.badge.plus")
                    .font(.title3)
            }
        }
        .accessibilityHidden(true)
    }

}

struct NeuroForgeTodayWidget: Widget {
    let kind = "NeuroForgeToday"

    var body: some WidgetConfiguration {
        let presentation = NFWidgetPresentation(
            snapshot: NFWidgetSnapshotStore.read() ?? .placeholder
        )
        return StaticConfiguration(kind: kind, provider: NeuroForgeProvider()) { entry in
            NeuroForgeWidgetView(entry: entry)
        }
        .configurationDisplayName(presentation.widgetDisplayName)
        .description(presentation.widgetDescription)
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryInline, .accessoryRectangular])
    }
}

@main
struct NeuroForgeWidgetsBundle: WidgetBundle {
    var body: some Widget {
        NeuroForgeTodayWidget()
    }
}
