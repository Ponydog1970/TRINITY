//
//  Agent.swift
//  TRINITY Vision Aid
//
//  Base protocol for all agents in the Multi-Agent System
//

import Foundation
import Combine

/// Base protocol for all agents in the TRINITY system
protocol Agent: AnyObject {
    associatedtype Input
    associatedtype Output

    var id: UUID { get }
    var name: String { get }
    var isActive: Bool { get set }

    func process(_ input: Input) async throws -> Output
    func reset()
}

/// Message passed between agents
struct AgentMessage<T> {
    let id: UUID
    let sender: String
    let recipient: String?  // nil for broadcast
    let timestamp: Date
    let payload: T
    let priority: MessagePriority

    init(
        sender: String,
        recipient: String? = nil,
        payload: T,
        priority: MessagePriority = .normal
    ) {
        self.id = UUID()
        self.sender = sender
        self.recipient = recipient
        self.timestamp = Date()
        self.payload = payload
        self.priority = priority
    }
}

enum MessagePriority: Int, Comparable {
    case low = 0
    case normal = 1
    case high = 2
    case critical = 3

    static func < (lhs: MessagePriority, rhs: MessagePriority) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// Coordinator for all agents in the system
@MainActor
class AgentCoordinator: ObservableObject {
    @Published var activeAgents: [String: any Agent] = [:]

    private var messageQueue: [(priority: MessagePriority, message: Any)] = []
    private let messageSubject = PassthroughSubject<Any, Never>()

    func register<A: Agent>(_ agent: A) {
        activeAgents[agent.name] = agent
    }

    func unregister(_ agentName: String) {
        activeAgents.removeValue(forKey: agentName)
    }

    func send<T>(_ message: AgentMessage<T>) {
        messageQueue.append((message.priority, message))
        messageQueue.sort { $0.priority > $1.priority }
        messageSubject.send(message)
    }

    func broadcast<T>(_ message: AgentMessage<T>) {
        send(message)
    }
}

/// Base class for concrete agents
class BaseAgent<I, O>: Agent {
    typealias Input = I
    typealias Output = O

    let id: UUID
    let name: String
    var isActive: Bool

    init(name: String) {
        self.id = UUID()
        self.name = name
        self.isActive = true
    }

    func process(_ input: I) async throws -> O {
        fatalError("Subclasses must implement process(_:)")
    }

    func reset() {
        // Default implementation
    }
}
