//
//  ErrorRecovery.swift
//  TRINITY Vision Aid
//
//  Error recovery and retry mechanisms
//

import Foundation

/// Error recovery strategies
enum RecoveryStrategy {
    case retry(maxAttempts: Int, backoff: BackoffStrategy)
    case fallback(action: () async throws -> Void)
    case ignore
    case fail
}

/// Backoff strategies for retries
enum BackoffStrategy {
    case constant(TimeInterval)
    case exponential(base: TimeInterval, multiplier: Double)
    case linear(increment: TimeInterval)

    func delay(for attempt: Int) -> TimeInterval {
        switch self {
        case .constant(let interval):
            return interval
        case .exponential(let base, let multiplier):
            return base * pow(multiplier, Double(attempt))
        case .linear(let increment):
            return increment * TimeInterval(attempt)
        }
    }
}

/// Retryable operation executor
class RetryExecutor {
    /// Execute an operation with retry logic
    static func execute<T>(
        maxAttempts: Int = 3,
        backoff: BackoffStrategy = .exponential(base: 2.0, multiplier: 2.0),
        operation: @escaping () async throws -> T
    ) async throws -> T {
        var lastError: Error?

        for attempt in 0..<maxAttempts {
            do {
                return try await operation()
            } catch {
                lastError = error

                // Don't retry on last attempt
                guard attempt < maxAttempts - 1 else {
                    break
                }

                // Calculate delay
                let delay = backoff.delay(for: attempt)

                print("⚠️ Attempt \(attempt + 1) failed: \(error.localizedDescription)")
                print("   Retrying in \(delay) seconds...")

                // Wait before retry
                try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }
        }

        throw TrinityError.retryExhausted(
            attempts: maxAttempts,
            lastError: lastError ?? NSError(domain: "Unknown", code: -1)
        )
    }
}

/// Circuit breaker pattern for preventing cascade failures
actor CircuitBreaker {
    enum State {
        case closed      // Normal operation
        case open        // Failing, reject requests
        case halfOpen    // Testing if service recovered
    }

    private var state: State = .closed
    private var failureCount: Int = 0
    private var successCount: Int = 0
    private var lastFailureTime: Date?

    private let failureThreshold: Int
    private let successThreshold: Int
    private let timeout: TimeInterval

    init(
        failureThreshold: Int = 5,
        successThreshold: Int = 2,
        timeout: TimeInterval = 60.0
    ) {
        self.failureThreshold = failureThreshold
        self.successThreshold = successThreshold
        self.timeout = timeout
    }

    func execute<T>(operation: () async throws -> T) async throws -> T {
        // Check if circuit is open
        if state == .open {
            // Check if timeout expired
            if let lastFailure = lastFailureTime,
               Date().timeIntervalSince(lastFailure) > timeout {
                state = .halfOpen
                successCount = 0
            } else {
                throw TrinityError.circuitBreakerOpen
            }
        }

        do {
            let result = try await operation()
            onSuccess()
            return result
        } catch {
            onFailure()
            throw error
        }
    }

    private func onSuccess() {
        switch state {
        case .closed:
            failureCount = 0
        case .halfOpen:
            successCount += 1
            if successCount >= successThreshold {
                state = .closed
                failureCount = 0
            }
        case .open:
            break
        }
    }

    private func onFailure() {
        lastFailureTime = Date()

        switch state {
        case .closed:
            failureCount += 1
            if failureCount >= failureThreshold {
                state = .open
            }
        case .halfOpen:
            state = .open
            successCount = 0
        case .open:
            break
        }
    }

    func reset() {
        state = .closed
        failureCount = 0
        successCount = 0
        lastFailureTime = nil
    }
}

/// Error handler with recovery strategies
class ErrorHandler {
    static let shared = ErrorHandler()

    private var errorLog: [ErrorRecord] = []
    private let maxLogSize = 100

    struct ErrorRecord {
        let error: Error
        let timestamp: Date
        let context: String
        let recovered: Bool
    }

    func handle(
        _ error: Error,
        context: String,
        strategy: RecoveryStrategy
    ) async throws {
        // Log error
        logError(error, context: context)

        // Apply recovery strategy
        switch strategy {
        case .retry(let maxAttempts, let backoff):
            throw error // Will be retried by RetryExecutor

        case .fallback(let action):
            print("⚠️ Error occurred: \(error.localizedDescription)")
            print("   Executing fallback action...")
            try await action()
            logRecovery(error, context: context)

        case .ignore:
            print("ℹ️ Error ignored: \(error.localizedDescription)")
            logRecovery(error, context: context)

        case .fail:
            throw error
        }
    }

    private func logError(_ error: Error, context: String) {
        let record = ErrorRecord(
            error: error,
            timestamp: Date(),
            context: context,
            recovered: false
        )

        errorLog.append(record)

        // Trim log if too large
        if errorLog.count > maxLogSize {
            errorLog.removeFirst(errorLog.count - maxLogSize)
        }

        print("🔴 ERROR [\(context)]: \(error.localizedDescription)")
    }

    private func logRecovery(_ error: Error, context: String) {
        if let index = errorLog.lastIndex(where: {
            $0.context == context && !$0.recovered
        }) {
            var record = errorLog[index]
            errorLog[index] = ErrorRecord(
                error: record.error,
                timestamp: record.timestamp,
                context: record.context,
                recovered: true
            )
        }

        print("✅ RECOVERED [\(context)]")
    }

    func getRecentErrors(limit: Int = 10) -> [ErrorRecord] {
        return Array(errorLog.suffix(limit))
    }

    func clearLog() {
        errorLog.removeAll()
    }
}

// MARK: - Extended Error Types

extension TrinityError {
    static func retryExhausted(attempts: Int, lastError: Error) -> TrinityError {
        return .custom("Retry exhausted after \(attempts) attempts. Last error: \(lastError.localizedDescription)")
    }

    static var circuitBreakerOpen: TrinityError {
        return .custom("Circuit breaker is open - service temporarily unavailable")
    }

    static func custom(_ message: String) -> TrinityError {
        return .notConfigured // Placeholder, should be extended in TrinityCoordinator.swift
    }
}

/// Observable error state for UI
@MainActor
class ErrorState: ObservableObject {
    @Published var currentError: Error?
    @Published var errorCount: Int = 0
    @Published var lastErrorTime: Date?
    @Published var isRecovering: Bool = false

    func recordError(_ error: Error) {
        currentError = error
        errorCount += 1
        lastErrorTime = Date()
    }

    func clearError() {
        currentError = nil
    }

    func startRecovery() {
        isRecovering = true
    }

    func endRecovery() {
        isRecovering = false
        currentError = nil
    }
}
