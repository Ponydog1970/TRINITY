//
//  ConceptualMemoryTypes.swift
//  TRINITY Vision Aid
//
//  Conceptual memory system for thoughts, conversations, ideas
//  Extends Trinity beyond physical navigation to full cognitive system
//

import Foundation
import CoreLocation

// MARK: - Memory Type Enum

/// Unified memory type supporting both physical and conceptual memories
enum MemoryType: Codable {
    case physical(PhysicalMemory)
    case thought(ThoughtMemory)
    case conversation(ConversationMemory)
    case idea(IdeaMemory)
    case note(NoteMemory)
    case plan(PlanMemory)
    case hybrid(HybridMemory)

    var id: UUID {
        switch self {
        case .physical(let mem): return mem.id
        case .thought(let mem): return mem.id
        case .conversation(let mem): return mem.id
        case .idea(let mem): return mem.id
        case .note(let mem): return mem.id
        case .plan(let mem): return mem.id
        case .hybrid(let mem): return mem.id
        }
    }

    var timestamp: Date {
        switch self {
        case .physical(let mem): return mem.timestamp
        case .thought(let mem): return mem.timestamp
        case .conversation(let mem): return mem.timestamp
        case .idea(let mem): return mem.timestamp
        case .note(let mem): return mem.timestamp
        case .plan(let mem): return mem.timestamp
        case .hybrid(let mem): return mem.timestamp
        }
    }
}

// MARK: - Physical Memory (Reference)

struct PhysicalMemory: Codable, Identifiable {
    let id: UUID
    let objectType: String
    let location: CLLocationCoordinate2D?
    let timestamp: Date
    let embedding: [Float]
}

// MARK: - Thought Memory

/// Stores user thoughts, observations, intentions
struct ThoughtMemory: Codable, Identifiable {
    let id: UUID
    var content: String
    let timestamp: Date
    var lastModified: Date

    // LINKING to Physical World
    var linkedLocation: CLLocationCoordinate2D?
    var linkedObjects: [UUID]  // IDs of physical objects
    var linkedScene: String?   // "Café Hauptstraße"

    // SEMANTICS
    var embedding: [Float]
    var category: ThoughtCategory
    var importance: Float  // 0-1
    var emotionalTone: EmotionalTone?

    // ACCESS TRACKING
    var accessCount: Int
    var lastAccessed: Date

    enum ThoughtCategory: String, Codable {
        case reminder      // "Nicht vergessen: Milch kaufen"
        case observation   // "Das Café sieht gemütlich aus"
        case intention     // "Hier will ich nochmal hin"
        case reflection    // "Interessanter Ort"
        case question      // "Wie komme ich hier weg?"
    }

    enum EmotionalTone: String, Codable {
        case positive
        case neutral
        case negative
        case curious
        case excited
    }

    init(
        id: UUID = UUID(),
        content: String,
        timestamp: Date = Date(),
        linkedLocation: CLLocationCoordinate2D? = nil,
        linkedObjects: [UUID] = [],
        linkedScene: String? = nil,
        embedding: [Float],
        category: ThoughtCategory,
        importance: Float,
        emotionalTone: EmotionalTone? = nil
    ) {
        self.id = id
        self.content = content
        self.timestamp = timestamp
        self.lastModified = timestamp
        self.linkedLocation = linkedLocation
        self.linkedObjects = linkedObjects
        self.linkedScene = linkedScene
        self.embedding = embedding
        self.category = category
        self.importance = importance
        self.emotionalTone = emotionalTone
        self.accessCount = 0
        self.lastAccessed = timestamp
    }
}

// MARK: - Conversation Memory

/// Stores conversations with redundancy reduction
struct ConversationMemory: Codable, Identifiable {
    let id: UUID
    var participants: [String]
    var messages: [Message]
    let timestamp: Date
    var duration: TimeInterval

    // LINKING
    var location: CLLocationCoordinate2D?
    var context: String?  // "Beim Spaziergang im Park"

    // SEMANTICS
    var summary: String
    var keyTopics: [String]
    var keyInsights: [String]
    var embedding: [Float]

    // REDUNDANCY REDUCTION
    var relatedConversations: [UUID]
    var mergedFrom: [UUID]?  // IDs of conversations merged into this one
    var occurrences: Int  // How many times this topic was discussed

    // ACCESS TRACKING
    var accessCount: Int
    var lastAccessed: Date
    var importance: Float

    struct Message: Codable, Identifiable {
        let id: UUID
        let speaker: String
        let content: String
        let timestamp: Date
        var embedding: [Float]

        init(
            id: UUID = UUID(),
            speaker: String,
            content: String,
            timestamp: Date = Date(),
            embedding: [Float]
        ) {
            self.id = id
            self.speaker = speaker
            self.content = content
            self.timestamp = timestamp
            self.embedding = embedding
        }
    }

    init(
        id: UUID = UUID(),
        participants: [String],
        messages: [Message],
        timestamp: Date = Date(),
        duration: TimeInterval,
        location: CLLocationCoordinate2D? = nil,
        context: String? = nil,
        summary: String,
        keyTopics: [String],
        keyInsights: [String],
        embedding: [Float],
        relatedConversations: [UUID] = [],
        mergedFrom: [UUID]? = nil,
        occurrences: Int = 1,
        importance: Float = 0.5
    ) {
        self.id = id
        self.participants = participants
        self.messages = messages
        self.timestamp = timestamp
        self.duration = duration
        self.location = location
        self.context = context
        self.summary = summary
        self.keyTopics = keyTopics
        self.keyInsights = keyInsights
        self.embedding = embedding
        self.relatedConversations = relatedConversations
        self.mergedFrom = mergedFrom
        self.occurrences = occurrences
        self.accessCount = 0
        self.lastAccessed = timestamp
        self.importance = importance
    }
}

// MARK: - Idea Memory

/// Stores ideas with evolution tracking
struct IdeaMemory: Codable, Identifiable {
    let id: UUID
    var title: String
    var description: String
    let timestamp: Date
    var lastModified: Date

    // IDEA EVOLUTION
    var status: IdeaStatus
    var versions: [IdeaVersion]
    var implementationSteps: [String]?
    var implementationDate: Date?

    // LINKING
    var relatedIdeas: [UUID]  // Related idea IDs
    var inspirations: [UUID]  // What inspired this idea
    var spawnedFrom: UUID?    // Parent conversation/thought ID
    var linkedPhysical: [UUID]?  // Physical memories linked to this idea

    // SEMANTICS
    var embedding: [Float]
    var tags: [String]
    var importance: Float

    // ACCESS TRACKING
    var accessCount: Int
    var lastAccessed: Date

    enum IdeaStatus: String, Codable {
        case draft          // Initial rough idea
        case refined        // Elaborated
        case implemented    // Actually built!
        case archived       // Old/discarded
    }

    struct IdeaVersion: Codable, Identifiable {
        let id: UUID
        let version: Int
        let content: String
        let timestamp: Date
        let changes: String

        init(
            id: UUID = UUID(),
            version: Int,
            content: String,
            timestamp: Date = Date(),
            changes: String
        ) {
            self.id = id
            self.version = version
            self.content = content
            self.timestamp = timestamp
            self.changes = changes
        }
    }

    init(
        id: UUID = UUID(),
        title: String,
        description: String,
        timestamp: Date = Date(),
        status: IdeaStatus = .draft,
        versions: [IdeaVersion]? = nil,
        implementationSteps: [String]? = nil,
        implementationDate: Date? = nil,
        relatedIdeas: [UUID] = [],
        inspirations: [UUID] = [],
        spawnedFrom: UUID? = nil,
        linkedPhysical: [UUID]? = nil,
        embedding: [Float],
        tags: [String],
        importance: Float
    ) {
        self.id = id
        self.title = title
        self.description = description
        self.timestamp = timestamp
        self.lastModified = timestamp
        self.status = status

        if let versions = versions {
            self.versions = versions
        } else {
            self.versions = [IdeaVersion(
                version: 1,
                content: description,
                changes: "Initial version"
            )]
        }

        self.implementationSteps = implementationSteps
        self.implementationDate = implementationDate
        self.relatedIdeas = relatedIdeas
        self.inspirations = inspirations
        self.spawnedFrom = spawnedFrom
        self.linkedPhysical = linkedPhysical
        self.embedding = embedding
        self.tags = tags
        self.importance = importance
        self.accessCount = 0
        self.lastAccessed = timestamp
    }
}

// MARK: - Note Memory

/// Simple note/reminder storage
struct NoteMemory: Codable, Identifiable {
    let id: UUID
    var title: String
    var content: String
    let timestamp: Date
    var lastModified: Date

    // LINKING
    var linkedLocation: CLLocationCoordinate2D?
    var linkedObjects: [UUID]
    var tags: [String]

    // SEMANTICS
    var embedding: [Float]
    var importance: Float
    var isReminder: Bool
    var reminderDate: Date?

    // ACCESS TRACKING
    var accessCount: Int
    var lastAccessed: Date

    init(
        id: UUID = UUID(),
        title: String,
        content: String,
        timestamp: Date = Date(),
        linkedLocation: CLLocationCoordinate2D? = nil,
        linkedObjects: [UUID] = [],
        tags: [String] = [],
        embedding: [Float],
        importance: Float = 0.5,
        isReminder: Bool = false,
        reminderDate: Date? = nil
    ) {
        self.id = id
        self.title = title
        self.content = content
        self.timestamp = timestamp
        self.lastModified = timestamp
        self.linkedLocation = linkedLocation
        self.linkedObjects = linkedObjects
        self.tags = tags
        self.embedding = embedding
        self.importance = importance
        self.isReminder = isReminder
        self.reminderDate = reminderDate
        self.accessCount = 0
        self.lastAccessed = timestamp
    }
}

// MARK: - Plan Memory

/// Future plans and appointments
struct PlanMemory: Codable, Identifiable {
    let id: UUID
    var title: String
    var description: String
    let timestamp: Date
    var scheduledDate: Date
    var lastModified: Date

    // LINKING
    var location: CLLocationCoordinate2D?
    var linkedIdeas: [UUID]
    var linkedNotes: [UUID]
    var participants: [String]?

    // SEMANTICS
    var embedding: [Float]
    var tags: [String]
    var importance: Float
    var isCompleted: Bool
    var completedDate: Date?

    // REMINDERS
    var reminderOffsets: [TimeInterval]  // e.g., [-3600] = 1 hour before

    // ACCESS TRACKING
    var accessCount: Int
    var lastAccessed: Date

    init(
        id: UUID = UUID(),
        title: String,
        description: String,
        timestamp: Date = Date(),
        scheduledDate: Date,
        location: CLLocationCoordinate2D? = nil,
        linkedIdeas: [UUID] = [],
        linkedNotes: [UUID] = [],
        participants: [String]? = nil,
        embedding: [Float],
        tags: [String] = [],
        importance: Float = 0.7,
        isCompleted: Bool = false,
        completedDate: Date? = nil,
        reminderOffsets: [TimeInterval] = [-3600]  // 1 hour before
    ) {
        self.id = id
        self.title = title
        self.description = description
        self.timestamp = timestamp
        self.scheduledDate = scheduledDate
        self.lastModified = timestamp
        self.location = location
        self.linkedIdeas = linkedIdeas
        self.linkedNotes = linkedNotes
        self.participants = participants
        self.embedding = embedding
        self.tags = tags
        self.importance = importance
        self.isCompleted = isCompleted
        self.completedDate = completedDate
        self.reminderOffsets = reminderOffsets
        self.accessCount = 0
        self.lastAccessed = timestamp
    }
}

// MARK: - Hybrid Memory

/// Combines physical and conceptual memories
struct HybridMemory: Codable, Identifiable {
    let id: UUID
    let timestamp: Date

    // PHYSICAL COMPONENT
    var physicalMemories: [UUID]
    var location: CLLocationCoordinate2D?
    var visualSnapshot: Data?

    // CONCEPTUAL COMPONENT
    var thoughts: [UUID]
    var conversations: [UUID]
    var ideas: [UUID]
    var notes: [UUID]
    var plans: [UUID]

    // SYNTHESIS
    var synthesizedMeaning: String
    var embedding: [Float]
    var importance: Float

    // GRAPH CONNECTIONS
    var connections: [HybridConnection]

    // ACCESS TRACKING
    var accessCount: Int
    var lastAccessed: Date

    struct HybridConnection: Codable, Identifiable {
        let id: UUID
        let sourceId: UUID
        let targetId: UUID
        let type: ConnectionType
        var strength: Float  // 0-1

        enum ConnectionType: String, Codable {
            case causedBy        // Thought caused by seeing object
            case inspiredBy      // Idea inspired by location
            case discussedAt     // Conversation happened at location
            case remindsOf       // Object reminds of idea
            case implements      // Physical action implements idea
            case relatesTo       // General relation
        }

        init(
            id: UUID = UUID(),
            sourceId: UUID,
            targetId: UUID,
            type: ConnectionType,
            strength: Float
        ) {
            self.id = id
            self.sourceId = sourceId
            self.targetId = targetId
            self.type = type
            self.strength = strength
        }
    }

    init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        physicalMemories: [UUID] = [],
        location: CLLocationCoordinate2D? = nil,
        visualSnapshot: Data? = nil,
        thoughts: [UUID] = [],
        conversations: [UUID] = [],
        ideas: [UUID] = [],
        notes: [UUID] = [],
        plans: [UUID] = [],
        synthesizedMeaning: String,
        embedding: [Float],
        importance: Float,
        connections: [HybridConnection] = []
    ) {
        self.id = id
        self.timestamp = timestamp
        self.physicalMemories = physicalMemories
        self.location = location
        self.visualSnapshot = visualSnapshot
        self.thoughts = thoughts
        self.conversations = conversations
        self.ideas = ideas
        self.notes = notes
        self.plans = plans
        self.synthesizedMeaning = synthesizedMeaning
        self.embedding = embedding
        self.importance = importance
        self.connections = connections
        self.accessCount = 0
        self.lastAccessed = timestamp
    }
}

// MARK: - Helper Extensions

extension CLLocationCoordinate2D: Codable {
    enum CodingKeys: String, CodingKey {
        case latitude
        case longitude
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let latitude = try container.decode(Double.self, forKey: .latitude)
        let longitude = try container.decode(Double.self, forKey: .longitude)
        self.init(latitude: latitude, longitude: longitude)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(latitude, forKey: .latitude)
        try container.encode(longitude, forKey: .longitude)
    }
}

// MARK: - Similarity Calculation

func cosineSimilarity(_ a: [Float], _ b: [Float]) -> Float {
    guard a.count == b.count else { return 0.0 }

    var dotProduct: Float = 0.0
    var normA: Float = 0.0
    var normB: Float = 0.0

    for i in 0..<a.count {
        dotProduct += a[i] * b[i]
        normA += a[i] * a[i]
        normB += b[i] * b[i]
    }

    let denominator = sqrt(normA) * sqrt(normB)
    return denominator > 0 ? dotProduct / denominator : 0.0
}
