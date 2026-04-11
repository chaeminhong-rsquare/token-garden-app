import SwiftUI

/// Shared animation timings for expand/collapse sections.
///
/// Two-phase sequence:
/// 1. Container height animates (`containerDuration`)
/// 2. Content fades in after container is fully expanded (`contentFadeInDuration`)
///
/// On collapse the order is reversed and the content disappears instantly so
/// the container can shrink without clipped text.
enum ExpandAnimation {
    /// Duration of the container expand/collapse animation.
    static let containerDuration: Double = 0.32

    /// Duration of the content fade-in (after expand completes).
    static let contentFadeInDuration: Double = 0.18

    /// Easing for the container height animation.
    static let container: Animation = .spring(response: 0.38, dampingFraction: 0.86)

    /// Easing for the content fade-in.
    static let contentFade: Animation = .easeOut(duration: contentFadeInDuration)

    /// Easing for chevron rotation — follows the container but a touch faster.
    static let chevron: Animation = .spring(response: 0.32, dampingFraction: 0.82)

    /// Toggle an expand section with the two-phase animation.
    ///
    /// - On expand: container animates first, then `showContent` flips on completion.
    /// - On collapse: `showContent` is cleared instantly, then container animates.
    static func toggle(
        isExpanded: Binding<Bool>,
        showContent: Binding<Bool>
    ) {
        if isExpanded.wrappedValue {
            // Collapse: hide content immediately, then shrink container.
            showContent.wrappedValue = false
            withAnimation(container) {
                isExpanded.wrappedValue = false
            }
        } else {
            // Expand: grow container first, then fade content in on completion.
            withAnimation(container) {
                isExpanded.wrappedValue = true
            } completion: {
                withAnimation(contentFade) {
                    showContent.wrappedValue = true
                }
            }
        }
    }
}
