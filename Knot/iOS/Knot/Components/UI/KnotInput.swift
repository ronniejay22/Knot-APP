//
//  KnotInput.swift
//  Knot
//
//  Single-line + multi-line text input primitive with adaptive border
//  states (neutral / focused / error / success).
//

import SwiftUI

/// A styled text input that wraps `TextField` (single-line) or `TextEditor`
/// (multi-line), with shadcn-style focus and validation states.
struct KnotInput: View {

    enum Style {
        case singleLine
        case multiLine
    }

    enum ValidationState {
        case neutral
        case focused
        case error
        case success
    }

    @Binding var text: String
    let placeholder: String
    let style: Style
    let leadingIcon: UIImage?
    let trailingAccessory: AnyView?
    let minHeight: CGFloat?
    let maxHeight: CGFloat?
    let validationState: ValidationState

    @FocusState private var isFocused: Bool

    init(
        text: Binding<String>,
        placeholder: String,
        style: Style = .singleLine,
        leadingIcon: UIImage? = nil,
        trailingAccessory: AnyView? = nil,
        minHeight: CGFloat? = nil,
        maxHeight: CGFloat? = nil,
        validationState: ValidationState = .neutral
    ) {
        self._text = text
        self.placeholder = placeholder
        self.style = style
        self.leadingIcon = leadingIcon
        self.trailingAccessory = trailingAccessory
        self.minHeight = minHeight
        self.maxHeight = maxHeight
        self.validationState = validationState
    }

    var body: some View {
        HStack(alignment: style == .multiLine ? .top : .center, spacing: 10) {
            if let leadingIcon {
                Image(uiImage: leadingIcon)
                    .renderingMode(.template)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 18, height: 18)
                    .foregroundStyle(Theme.textTertiary)
                    .padding(.top, style == .multiLine ? 12 : 0)
            }

            inputField

            if let trailingAccessory {
                trailingAccessory
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, style == .multiLine ? 0 : 12)
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.md)
                .stroke(borderColor, lineWidth: borderWidth)
        )
    }

    @ViewBuilder
    private var inputField: some View {
        switch style {
        case .singleLine:
            TextField("", text: $text, prompt: placeholderView)
                .focused($isFocused)
                .knotFont(Theme.Typography.body)
                .foregroundStyle(Theme.textPrimary)
        case .multiLine:
            ZStack(alignment: .topLeading) {
                if text.isEmpty {
                    Text(placeholder)
                        .knotFont(Theme.Typography.body)
                        .foregroundStyle(Theme.textTertiary)
                        .padding(.top, 12)
                        .padding(.leading, 4)
                        .allowsHitTesting(false)
                }
                TextEditor(text: $text)
                    .focused($isFocused)
                    .knotFont(Theme.Typography.body)
                    .foregroundStyle(Theme.textPrimary)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: minHeight ?? 80, maxHeight: maxHeight ?? .infinity)
            }
        }
    }

    private var placeholderView: Text {
        Text(placeholder).foregroundStyle(Theme.textTertiary)
    }

    private var resolvedState: ValidationState {
        if validationState == .error || validationState == .success {
            return validationState
        }
        return isFocused ? .focused : .neutral
    }

    private var borderColor: Color {
        switch resolvedState {
        case .neutral: return Theme.surfaceBorder
        case .focused: return Theme.accent
        case .error: return Theme.statusError
        case .success: return Theme.statusSuccess
        }
    }

    private var borderWidth: CGFloat {
        resolvedState == .neutral ? 1 : 1.5
    }
}

// MARK: - Preview

#if DEBUG
import LucideIcons

#Preview("KnotInput") {
    @Previewable @State var single = ""
    @Previewable @State var multi = ""
    @Previewable @State var errored = "bad@"

    return ZStack {
        Theme.backgroundGradient.ignoresSafeArea()
        VStack(spacing: 16) {
            KnotInput(text: $single, placeholder: "Email", leadingIcon: Lucide.mail)
            KnotInput(text: $errored, placeholder: "Email", leadingIcon: Lucide.mail, validationState: .error)
            KnotInput(text: $multi, placeholder: "Capture a hint...", style: .multiLine, minHeight: 100)
        }
        .padding()
    }
}
#endif
