import SwiftUI

/// ViewModifier that binds a `TaskBinding` to the shared `ActiveTaskContext`
/// whenever the provided `id` changes (or on initial appear).
///
/// Replaces the pattern of `.onAppear { updateTaskContext() }` +
/// `.onChange(of: ...) { updateTaskContext() }` across sections.
struct TaskContextBindingModifier<ID: Equatable>: ViewModifier {
    @Environment(ActiveTaskContext.self) private var taskContext
    let id: ID
    let binding: () -> TaskBinding

    func body(content: Content) -> some View {
        content.task(id: id) {
            taskContext.bind(binding())
        }
    }
}

extension View {
    func bindTaskContext<ID: Equatable>(
        id: ID,
        _ binding: @escaping () -> TaskBinding
    ) -> some View {
        modifier(TaskContextBindingModifier(id: id, binding: binding))
    }

    /// Convenience for the common case: rebind when canExecute or isRunning changes.
    func bindTaskContext(
        canExecute: Bool,
        isRunning: Bool,
        _ binding: @escaping () -> TaskBinding
    ) -> some View {
        bindTaskContext(id: BindingTrigger(canExecute: canExecute, isRunning: isRunning), binding)
    }
}

private struct BindingTrigger: Equatable {
    let canExecute: Bool
    let isRunning: Bool
}
