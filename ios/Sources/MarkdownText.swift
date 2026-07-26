import SwiftUI

/// A small, warm markdown renderer for the person-card dossiers:
/// #/##/### serif headings, "- " bullets, "---" dividers, **bold** inline.
struct MarkdownText: View {
    let md: String

    private enum Block: Identifiable {
        case heading(level: Int, text: String)
        case bullet(text: String)
        case divider
        case paragraph(text: String)

        var id: UUID { UUID() }
    }

    private var blocks: [(index: Int, block: Block)] {
        var result: [Block] = []
        for rawLine in md.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }
            if line == "---" || line == "***" {
                result.append(.divider)
            } else if line.hasPrefix("### ") {
                result.append(.heading(level: 3, text: String(line.dropFirst(4))))
            } else if line.hasPrefix("## ") {
                result.append(.heading(level: 2, text: String(line.dropFirst(3))))
            } else if line.hasPrefix("# ") {
                result.append(.heading(level: 1, text: String(line.dropFirst(2))))
            } else if line.hasPrefix("- ") || line.hasPrefix("* ") {
                result.append(.bullet(text: String(line.dropFirst(2))))
            } else {
                result.append(.paragraph(text: line))
            }
        }
        return result.enumerated().map { ($0.offset, $0.element) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(blocks, id: \.index) { item in
                blockView(item.block)
            }
        }
    }

    @ViewBuilder
    private func blockView(_ block: Block) -> some View {
        switch block {
        case let .heading(level, text):
            Text(inline(text))
                .font(.rsSerif(level == 1 ? 30 : level == 2 ? 23 : 20))
                .foregroundStyle(level == 2 ? Color.rsTerracotta : Color.rsInk)
                .padding(.top, level == 1 ? 0 : 8)
        case let .bullet(text):
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Circle()
                    .fill(Color.rsAmber)
                    .frame(width: 7, height: 7)
                    .offset(y: -2)
                Text(inline(text))
                    .font(.rsBody)
                    .foregroundStyle(Color.rsInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
        case .divider:
            Rectangle()
                .fill(Color.rsAmber.opacity(0.35))
                .frame(height: 1.5)
                .padding(.vertical, 6)
        case let .paragraph(text):
            Text(inline(text))
                .font(.rsBody)
                .foregroundStyle(Color.rsInk)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func inline(_ text: String) -> AttributedString {
        (try? AttributedString(
            markdown: text,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        )) ?? AttributedString(text)
    }
}
