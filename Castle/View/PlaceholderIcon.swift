//
//  PlaceholderIcon.swift
//  Castle
//
//  Original generic placeholder rendered programmatically. Used when a row has no
//  image URL (or in screenshot mode where we deliberately avoid loading the real
//  game-icon assets that App Store reviewers have rejected for imitation).
//

import SwiftUI

struct PlaceholderIcon: View {
    let name: String
    var size: CGSize = CGSize(width: 44, height: 44)

    /**
     A small fixed palette of muted, distinct hues. The chosen color is deterministic per name (via a byte-sum mod the palette size), so the same row always gets the same color across renders and screenshot retakes.
     */
    private static let palette: [Color] = [
        Color(red: 0.92, green: 0.43, blue: 0.43),
        Color(red: 0.95, green: 0.65, blue: 0.32),
        Color(red: 0.95, green: 0.81, blue: 0.32),
        Color(red: 0.46, green: 0.78, blue: 0.50),
        Color(red: 0.36, green: 0.66, blue: 0.86),
        Color(red: 0.65, green: 0.46, blue: 0.86),
        Color(red: 0.92, green: 0.51, blue: 0.71)
    ]

    private var color: Color {
        let sum = name.utf8.reduce(0) { $0 + Int($1) }
        return Self.palette[sum % Self.palette.count]
    }

    private var initials: String {
        let words = name.split(whereSeparator: { !$0.isLetter && !$0.isNumber })
        let letters = words.compactMap { $0.first }.prefix(2)
        let result = letters.map { String($0).uppercased() }.joined()
        return result.isEmpty ? "?" : result
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size.height * 0.18, style: .continuous)
                .fill(color.gradient)
            Text(initials)
                .font(.system(size: size.height * 0.4, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
        }
        .frame(width: size.width, height: size.height)
    }
}

#if DEBUG
#Preview {
    HStack(spacing: 12) {
        PlaceholderIcon(name: "Cloud")
        PlaceholderIcon(name: "Tifa")
        PlaceholderIcon(name: "Omnislash")
        PlaceholderIcon(name: "Burst Mode")
        PlaceholderIcon(name: "Cloud DASB", size: CGSize(width: 64, height: 64))
    }
    .padding()
}
#endif
