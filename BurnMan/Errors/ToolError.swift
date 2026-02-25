import Foundation

/// Common protocol for CLI tool errors.
/// Each tool provides its own conforming enum with pattern-matched error cases.
protocol ToolError: LocalizedError, Equatable {
    /// Numeric error code (typically the process exit code).
    var code: Int { get }
    /// Name of the CLI tool that produced the error.
    var toolName: String { get }
    /// Factory: build a typed error from a process exit code and stderr output.
    static func from(exitCode: Int32, stderr: String) -> Self
}
