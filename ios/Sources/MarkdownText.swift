import SwiftUI

/// Sharp markdown renderer for contact pages:
/// #/##/### headings, "- " bullets, "> " pull quotes, "---" dividers,
/// **bold** and `code` inline.
struct MarkdownText: View {
    let md: String

    private enum Block {
        case heading(level: Int, text: String)
        case bullet(text: String)
        case quote(text: String)
        case divider
        case paragraph(text: String)
        case emphasis(text: String)
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
            } else if line.hasPrefix("> ") {
                result.append(.quote(text: String(line.dropFirst(2))))
            } else if line.hasPrefix("- ") || line.hasPrefix("* ") {
                result.append(.bullet(text: String(line.dropFirst(2))))
            } else if line.hasPrefix("*"), line.hasSuffix("*"), line.count > 2,
                !line.hasPrefix("**")
            {
                result.append(.emphasis(text: String(line.dropFirst().dropLast())))
            } else {
                result.append(.paragraph(text: line))
            }
        }
        return result.enumerated().map { ($0.offset, $0.element) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(blocks, id: \.index) { item in
                blockView(item.block)
            }
        }
    }

    @ViewBuilder
    private func blockView(_ block: Block) -> some View {
        switch block {
        case let .heading(level, text):
            if level == 1 {
                Text(inline(text))
                    .font(.rcDisplay(28))
                    .foregroundStyle(Color.rcText)
            } else {
                SectionLabel(text)
                    .padding(.top, 8)
            }
        case let .emphasis(text):
            Text(inline(text))
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Color.rcAccent)
        case let .quote(text):
            Text(inline(text))
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(Color.rcText)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.leading, 12)
                .overlay(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.rcAccent)
                        .frame(width: 3)
                }
        case let .bullet(text):
            HStack(alignment: .firstTextBaseline, spacing: 9) {
                Circle()
                    .fill(Color.rcAccent)
                    .frame(width: 5, height: 5)
                    .offset(y: -2)
                Text(inline(text))
                    .font(.rcBody)
                    .foregroundStyle(Color.rcText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        case .divider:
            Rectangle()
                .fill(Color.rcLine)
                .frame(height: 1)
                .padding(.vertical, 4)
        case let .paragraph(text):
            Text(inline(text))
                .font(.rcBody)
                .foregroundStyle(Color.rcTextDim)
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
