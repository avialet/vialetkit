import SwiftUI

/// Case a cocher ronde, remplie avec un rebond.
public struct CheckCircle: View {
    let checked: Bool
    let color: Color
    let size: CGFloat
    let action: () -> Void
    @State private var hovering = false

    public init(checked: Bool, color: Color, size: CGFloat = 20, action: @escaping () -> Void) {
        self.checked = checked; self.color = color; self.size = size; self.action = action
    }

    public var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .strokeBorder(checked ? color : (hovering ? color : Theme.inkFaint), lineWidth: 1.6)
                    .background(Circle().fill(hovering && !checked ? color.opacity(0.12) : .clear))
                if checked {
                    Circle().fill(color.gradient)
                    Image(systemName: "checkmark")
                        .font(.system(size: size * 0.48, weight: .heavy))
                        .foregroundStyle(.white)
                        .transition(.scale(scale: 0.3).combined(with: .opacity))
                }
            }
            .frame(width: size, height: size)
            .scaleEffect(checked ? 1.0 : (hovering ? 1.08 : 1))
            .animation(.spring(response: 0.32, dampingFraction: 0.55), value: checked)
            .animation(.easeOut(duration: 0.12), value: hovering)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

/// Pastille d'information.
public struct Chip: View {
    let text: String
    let icon: String?
    let color: Color
    let filled: Bool

    public init(_ text: String, icon: String? = nil, color: Color = Theme.inkSoft, filled: Bool = false) {
        self.text = text; self.icon = icon; self.color = color; self.filled = filled
    }

    public var body: some View {
        HStack(spacing: 4) {
            if let icon { Image(systemName: icon).font(.system(size: 9.5, weight: .bold)) }
            Text(text).font(Theme.ui(11.5, weight: .semibold)).lineLimit(1)
        }
        .padding(.horizontal, 8).padding(.vertical, 3.5)
        .foregroundStyle(filled ? Color.white : color)
        .background(Capsule().fill(filled ? AnyShapeStyle(color.gradient) : AnyShapeStyle(color.opacity(0.13))))
    }
}

/// Pastille cliquable.
public struct ChipButton: View {
    let text: String
    let icon: String?
    let color: Color
    let selected: Bool
    let action: () -> Void
    @State private var hovering = false

    public init(_ text: String, icon: String? = nil, color: Color, selected: Bool, action: @escaping () -> Void) {
        self.text = text; self.icon = icon; self.color = color; self.selected = selected; self.action = action
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if let icon { Image(systemName: icon).font(.system(size: 10.5, weight: .bold)) }
                Text(text).font(Theme.ui(12, weight: .semibold))
            }
            .padding(.horizontal, 10).padding(.vertical, 6)
            .foregroundStyle(selected ? Color.white : Theme.ink)
            .background(
                Capsule().fill(selected ? AnyShapeStyle(color.gradient)
                               : AnyShapeStyle(hovering ? color.opacity(0.16) : Theme.ink.opacity(0.05)))
            )
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: selected)
    }
}

/// Anneau d'avancement.
public struct ProgressRing: View {
    let fraction: Double
    let color: Color
    let size: CGFloat
    let lineWidth: CGFloat

    public init(fraction: Double, color: Color, size: CGFloat = 16, lineWidth: CGFloat = 2) {
        self.fraction = fraction; self.color = color; self.size = size; self.lineWidth = lineWidth
    }

    public var body: some View {
        ZStack {
            Circle().stroke(color.opacity(0.25), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: max(0.001, fraction))
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
            if fraction >= 1 {
                Image(systemName: "checkmark").font(.system(size: size * 0.45, weight: .heavy)).foregroundStyle(color)
            }
        }
        .frame(width: size, height: size)
        .animation(.snappy, value: fraction)
    }
}

/// Halo de la couleur d'accent sur fond papier ; en sombre, le papier prend
/// discretement la teinte de nuit de la palette (`Theme.ambientPaper`).
public struct AmbientBackground: View {
    let override: Color?

    /// `accent` nil : `Theme.accent` (palette posee par `Theme.configure`).
    public init(accent: Color? = nil) { self.override = accent }

    public var body: some View {
        let accent = override ?? Theme.accent
        ZStack {
            Theme.ambientPaper
            RadialGradient(colors: [accent.opacity(0.22), accent.opacity(0)],
                           center: .topTrailing, startRadius: 0, endRadius: 620)
            RadialGradient(colors: [accent.opacity(0.07), .clear],
                           center: .bottomLeading, startRadius: 0, endRadius: 460)
        }
        .ignoresSafeArea()
    }
}

/// Carte des reglages : icone coloree, titre, contenu.
public struct SettingsCard<Content: View>: View {
    let icon: String
    let color: Color
    let title: String
    let content: Content

    public init(icon: String, color: Color, title: String, @ViewBuilder content: () -> Content) {
        self.icon = icon; self.color = color; self.title = title; self.content = content()
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 7) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 22, height: 22)
                    .background(RoundedRectangle(cornerRadius: Theme.Radius.icon, style: .continuous).fill(color.gradient))
                Text(title).font(Theme.ui(13.5, weight: .bold)).foregroundStyle(Theme.ink)
            }
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous).fill(Theme.card))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous).strokeBorder(Theme.line, lineWidth: 1))
    }
}

/// Disposition en lignes qui passent a la ligne (pastilles).
public struct FlowLayout: Layout {
    let spacing: CGFloat

    public init(spacing: CGFloat = 6) { self.spacing = spacing }

    public func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, widest: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > 0, x + size.width > maxWidth { x = 0; y += rowHeight + spacing; rowHeight = 0 }
            x += size.width + spacing
            widest = max(widest, x - spacing)
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: min(widest, maxWidth), height: y + rowHeight)
    }

    public func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX { x = bounds.minX; y += rowHeight + spacing; rowHeight = 0 }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
