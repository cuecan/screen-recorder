/// The shared source-picker menu: available sources, followed by an explicit choice of none.
enum SourceMenu {
    static func entries<Source: Identifiable>(
        _ sources: [Source], selected: Source.ID?, noneTitle: String,
        title: (Source) -> String, choose: @escaping @MainActor (Source.ID?) -> Void
    ) -> [MenuEntry] {
        var entries: [MenuEntry] = sources.map { source in
            .item(title(source), checked: selected == source.id) { choose(source.id) }
        }
        if !entries.isEmpty { entries.append(.separator) }
        entries.append(.item(noneTitle, checked: selected == nil) { choose(nil) })
        return entries
    }
}
