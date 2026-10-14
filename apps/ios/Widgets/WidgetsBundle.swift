// SPDX-License-Identifier: GPL-3.0-or-later
import SwiftUI
import WidgetKit

@main
struct OpenMinipumpWidgets: WidgetBundle {
    var body: some Widget {
        GlucoseWidget()
    }
}

struct GlucoseWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "glucose", provider: Provider()) { entry in
            Text("\(entry.date, style: .time)").containerBackground(.background, for: .widget)
        }
        .configurationDisplayName("Glukose")
    }
}

struct Provider: TimelineProvider {
    struct Entry: TimelineEntry { let date: Date }
    func placeholder(in context: Context) -> Entry { Entry(date: Date()) }
    func getSnapshot(in context: Context, completion: @escaping (Entry) -> Void) { completion(Entry(date: Date())) }
    func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> Void) {
        completion(Timeline(entries: [Entry(date: Date())], policy: .never))
    }
}
