//
//  ConceptualMemoryManager.swift
//  TRINITY Vision Aid
//
//  Manages conceptual memories: thoughts, conversations, ideas, notes, plans
//  Extends Trinity beyond physical navigation to full cognitive system
//  Features: Redundancy reduction, idea evolution, hybrid memory linking
//

import Foundation
import CoreLocation
import Combine

/// Manager for conceptual memories with redundancy reduction and evolution tracking
/// THREAD-SAFE: All operations run on MainActor
@MainActor
class ConceptualMemoryManager: ObservableObject {

    // MARK: - Storage

    /// In-memory storage for fast access
    private var thoughts: [UUID: ThoughtMemory] = [:]
    private var conversations: [UUID: ConversationMemory] = [:]
    private var ideas: [UUID: IdeaMemory] = [:]
    private var notes: [UUID: NoteMemory] = [:]
    private var plans: [UUID: PlanMemory] = [:]
    private var hybridMemories: [UUID: HybridMemory] = [:]

    /// Vector database for semantic search
    private let vectorDatabase: VectorDatabaseProtocol

    /// Embedding generator for text
    private let embeddingGenerator: EmbeddingGenerator

    /// Similarity threshold for redundancy detection
    private let similarityThreshold: Float = 0.88  // Slightly lower than 0.92 for conversations

    /// Conversation similarity threshold (stricter)
    private let conversationSimilarityThreshold: Float = 0.85

    /// Published properties for UI updates
    @Published private(set) var recentThoughts: [ThoughtMemory] = []
    @Published private(set) var recentIdeas: [IdeaMemory] = []
    @Published private(set) var upcomingPlans: [PlanMemory] = []

    // MARK: - Initialization

    init(vectorDatabase: VectorDatabaseProtocol, embeddingGenerator: EmbeddingGenerator) {
        self.vectorDatabase = vectorDatabase
        self.embeddingGenerator = embeddingGenerator
        print("✅ ConceptualMemoryManager initialized")
    }

    // MARK: - Thought Memory

    /// Add a thought with automatic redundancy reduction
    func addThought(
        content: String,
        category: ThoughtMemory.ThoughtCategory,
        importance: Float = 0.5,
        linkedLocation: CLLocationCoordinate2D? = nil,
        linkedObjects: [UUID] = [],
        linkedScene: String? = nil,
        emotionalTone: ThoughtMemory.EmotionalTone? = nil
    ) async throws {
        // Generate text embedding
        let embedding = try await embeddingGenerator.generateEmbedding(from: content)

        // Check for similar thoughts (redundancy reduction)
        if let similar = try await findSimilarThought(embedding: embedding) {
            // Merge with existing thought
            var merged = similar
            merged.content = content  // Update with new content
            merged.lastModified = Date()
            merged.accessCount += 1
            merged.lastAccessed = Date()

            // Update importance (average)
            merged.importance = (merged.importance + importance) / 2.0

            thoughts[merged.id] = merged
            print("📊 Merged thought: \(content.prefix(50))...")
            updateRecentThoughts()
            return
        }

        // Create new thought
        let thought = ThoughtMemory(
            content: content,
            linkedLocation: linkedLocation,
            linkedObjects: linkedObjects,
            linkedScene: linkedScene,
            embedding: embedding,
            category: category,
            importance: importance,
            emotionalTone: emotionalTone
        )

        thoughts[thought.id] = thought

        // Store embedding in vector database
        let metadata = MemoryMetadata(
            objectType: "thought",
            description: content,
            confidence: importance,
            tags: [category.rawValue],
            spatialData: nil,
            timestamp: thought.timestamp,
            location: linkedLocation
        )

        let entry = VectorEntry(
            id: thought.id,
            embedding: embedding,
            metadata: metadata,
            memoryLayer: .episodic  // Thoughts go to episodic layer
        )

        try await vectorDatabase.insert(entry)

        print("💭 Added thought: \(content.prefix(50))... (importance: \(String(format: "%.2f", importance)))")
        updateRecentThoughts()
    }

    /// Find similar thought for redundancy reduction
    private func findSimilarThought(embedding: [Float]) async throws -> ThoughtMemory? {
        // Search recent thoughts (last 20)
        let recentThoughtsList = Array(thoughts.values.sorted { $0.timestamp > $1.timestamp }.prefix(20))

        for thought in recentThoughtsList {
            let similarity = cosineSimilarity(embedding, thought.embedding)
            if similarity >= similarityThreshold {
                return thought
            }
        }

        return nil
    }

    /// Search thoughts by content
    func searchThoughts(query: String, limit: Int = 10) async throws -> [ThoughtMemory] {
        let embedding = try await embeddingGenerator.generateEmbedding(from: query)
        let results = try await vectorDatabase.search(query: embedding, k: limit)

        // Filter for thought entries only
        let thoughtIds = results
            .filter { $0.metadata.objectType == "thought" }
            .map { $0.id }

        return thoughtIds.compactMap { thoughts[$0] }
    }

    // MARK: - Conversation Memory

    /// Add conversation with redundancy reduction (merging similar conversations)
    func addConversation(
        participants: [String],
        messages: [ConversationMemory.Message],
        summary: String,
        keyTopics: [String],
        keyInsights: [String],
        location: CLLocationCoordinate2D? = nil,
        context: String? = nil,
        importance: Float = 0.5
    ) async throws {
        // Generate embedding from summary
        let embedding = try await embeddingGenerator.generateEmbedding(from:summary)

        // Check for similar conversations (CRITICAL for redundancy reduction)
        let similarConversations = try await findSimilarConversations(
            embedding: embedding,
            topics: keyTopics
        )

        if let mostSimilar = similarConversations.first {
            // MERGE conversations instead of creating duplicate
            var merged = mostSimilar

            // Append new messages
            merged.messages.append(contentsOf: messages)
            merged.duration += messages.last!.timestamp.timeIntervalSince(messages.first!.timestamp)

            // Update summary (combine both)
            merged.summary = "\(merged.summary); \(summary)"

            // Merge topics (unique)
            merged.keyTopics = Array(Set(merged.keyTopics + keyTopics))

            // Merge insights (unique)
            merged.keyInsights = Array(Set(merged.keyInsights + keyInsights))

            // Average embeddings
            merged.embedding = zip(merged.embedding, embedding).map { ($0 + $1) / 2.0 }

            // Increment occurrence count
            merged.occurrences += 1

            // Update importance (weighted average)
            merged.importance = (merged.importance * Float(merged.occurrences - 1) + importance) / Float(merged.occurrences)

            // Track merge
            if merged.mergedFrom == nil {
                merged.mergedFrom = []
            }
            merged.mergedFrom?.append(UUID())  // Track that we merged

            merged.accessCount += 1
            merged.lastAccessed = Date()

            conversations[merged.id] = merged

            print("📊 Merged conversation: \(keyTopics.joined(separator: ", ")) (occurrence #\(merged.occurrences))")
            return
        }

        // Create new conversation
        let conversation = ConversationMemory(
            participants: participants,
            messages: messages,
            duration: messages.last!.timestamp.timeIntervalSince(messages.first!.timestamp),
            location: location,
            context: context,
            summary: summary,
            keyTopics: keyTopics,
            keyInsights: keyInsights,
            embedding: embedding,
            relatedConversations: similarConversations.map { $0.id },
            importance: importance
        )

        conversations[conversation.id] = conversation

        // Store in vector database
        let metadata = MemoryMetadata(
            objectType: "conversation",
            description: summary,
            confidence: importance,
            tags: keyTopics,
            spatialData: nil,
            timestamp: conversation.timestamp,
            location: location
        )

        let entry = VectorEntry(
            id: conversation.id,
            embedding: embedding,
            metadata: metadata,
            memoryLayer: .episodic
        )

        try await vectorDatabase.insert(entry)

        print("💬 Added conversation: \(keyTopics.joined(separator: ", "))")
    }

    /// Find similar conversations for redundancy reduction
    private func findSimilarConversations(
        embedding: [Float],
        topics: [String]
    ) async throws -> [ConversationMemory] {
        var similar: [ConversationMemory] = []

        // Check recent conversations (last 50)
        let recentConvs = Array(conversations.values.sorted { $0.timestamp > $1.timestamp }.prefix(50))

        for conv in recentConvs {
            let similarity = cosineSimilarity(embedding, conv.embedding)

            // Check both embedding similarity AND topic overlap
            let topicOverlap = Set(topics).intersection(Set(conv.keyTopics)).count

            if similarity >= conversationSimilarityThreshold && topicOverlap > 0 {
                similar.append(conv)
            }
        }

        // Sort by similarity descending
        return similar.sorted {
            cosineSimilarity(embedding, $0.embedding) > cosineSimilarity(embedding, $1.embedding)
        }
    }

    /// Search conversations by topic or content
    func searchConversations(query: String, limit: Int = 10) async throws -> [ConversationMemory] {
        let embedding = try await embeddingGenerator.generateEmbedding(from:query)
        let results = try await vectorDatabase.search(query: embedding, k: limit)

        let convIds = results
            .filter { $0.metadata.objectType == "conversation" }
            .map { $0.id }

        return convIds.compactMap { conversations[$0] }
    }

    // MARK: - Idea Memory

    /// Add idea with evolution tracking
    func addIdea(
        title: String,
        description: String,
        tags: [String],
        importance: Float = 0.6,
        relatedIdeas: [UUID] = [],
        spawnedFrom: UUID? = nil,
        linkedPhysical: [UUID]? = nil
    ) async throws {
        // Generate embedding
        let embedding = try await embeddingGenerator.generateEmbedding(from:"\(title): \(description)")

        // Check if this is evolution of existing idea
        if let existingIdea = try await findRelatedIdea(embedding: embedding, title: title) {
            // EVOLVE existing idea (add version)
            var evolved = existingIdea

            let newVersion = IdeaMemory.IdeaVersion(
                version: evolved.versions.count + 1,
                content: description,
                changes: "Evolution: \(description.prefix(100))"
            )

            evolved.versions.append(newVersion)
            evolved.description = description
            evolved.lastModified = Date()
            evolved.status = .refined
            evolved.accessCount += 1
            evolved.lastAccessed = Date()

            // Update embedding (average)
            evolved.embedding = zip(evolved.embedding, embedding).map { ($0 + $1) / 2.0 }

            ideas[evolved.id] = evolved

            print("💡 Evolved idea: \(title) (version \(newVersion.version))")
            updateRecentIdeas()
            return
        }

        // Create new idea
        let idea = IdeaMemory(
            title: title,
            description: description,
            relatedIdeas: relatedIdeas,
            spawnedFrom: spawnedFrom,
            linkedPhysical: linkedPhysical,
            embedding: embedding,
            tags: tags,
            importance: importance
        )

        ideas[idea.id] = idea

        // Store in vector database (semantic layer for long-term)
        let metadata = MemoryMetadata(
            objectType: "idea",
            description: description,
            confidence: importance,
            tags: tags,
            spatialData: nil,
            timestamp: idea.timestamp,
            location: nil
        )

        let entry = VectorEntry(
            id: idea.id,
            embedding: embedding,
            metadata: metadata,
            memoryLayer: .semantic  // Ideas go to semantic layer
        )

        try await vectorDatabase.insert(entry)

        print("💡 Added idea: \(title)")
        updateRecentIdeas()
    }

    /// Find related idea for evolution tracking
    private func findRelatedIdea(embedding: [Float], title: String) async throws -> IdeaMemory? {
        // Search recent ideas
        let recentIdeasList = Array(ideas.values.sorted { $0.timestamp > $1.timestamp }.prefix(20))

        for idea in recentIdeasList {
            let similarity = cosineSimilarity(embedding, idea.embedding)

            // Also check title similarity (case-insensitive)
            let titleSimilar = idea.title.lowercased().contains(title.lowercased()) ||
                              title.lowercased().contains(idea.title.lowercased())

            if similarity >= 0.90 || titleSimilar {
                return idea
            }
        }

        return nil
    }

    /// Mark idea as implemented
    func markIdeaImplemented(_ ideaId: UUID, implementationDate: Date = Date()) {
        guard var idea = ideas[ideaId] else { return }

        idea.status = .implemented
        idea.implementationDate = implementationDate
        idea.lastModified = Date()

        ideas[ideaId] = idea

        print("✅ Marked idea implemented: \(idea.title)")
        updateRecentIdeas()
    }

    /// Search ideas by content or tags
    func searchIdeas(query: String, limit: Int = 10) async throws -> [IdeaMemory] {
        let embedding = try await embeddingGenerator.generateEmbedding(from:query)
        let results = try await vectorDatabase.search(query: embedding, k: limit)

        let ideaIds = results
            .filter { $0.metadata.objectType == "idea" }
            .map { $0.id }

        return ideaIds.compactMap { ideas[$0] }
    }

    // MARK: - Note Memory

    /// Add simple note or reminder
    func addNote(
        title: String,
        content: String,
        tags: [String] = [],
        importance: Float = 0.5,
        isReminder: Bool = false,
        reminderDate: Date? = nil,
        linkedLocation: CLLocationCoordinate2D? = nil,
        linkedObjects: [UUID] = []
    ) async throws {
        let embedding = try await embeddingGenerator.generateEmbedding(from:"\(title): \(content)")

        let note = NoteMemory(
            title: title,
            content: content,
            linkedLocation: linkedLocation,
            linkedObjects: linkedObjects,
            tags: tags,
            embedding: embedding,
            importance: importance,
            isReminder: isReminder,
            reminderDate: reminderDate
        )

        notes[note.id] = note

        // Store in episodic layer
        let metadata = MemoryMetadata(
            objectType: "note",
            description: content,
            confidence: importance,
            tags: tags,
            spatialData: nil,
            timestamp: note.timestamp,
            location: linkedLocation
        )

        let entry = VectorEntry(
            id: note.id,
            embedding: embedding,
            metadata: metadata,
            memoryLayer: .episodic
        )

        try await vectorDatabase.insert(entry)

        print("📝 Added note: \(title)")
    }

    // MARK: - Plan Memory

    /// Add future plan or appointment
    func addPlan(
        title: String,
        description: String,
        scheduledDate: Date,
        location: CLLocationCoordinate2D? = nil,
        participants: [String]? = nil,
        tags: [String] = [],
        importance: Float = 0.7,
        reminderOffsets: [TimeInterval] = [-3600]  // 1 hour before
    ) async throws {
        let embedding = try await embeddingGenerator.generateEmbedding(from:"\(title): \(description)")

        let plan = PlanMemory(
            title: title,
            description: description,
            scheduledDate: scheduledDate,
            location: location,
            participants: participants,
            embedding: embedding,
            tags: tags,
            importance: importance,
            reminderOffsets: reminderOffsets
        )

        plans[plan.id] = plan

        // Store in episodic layer
        let metadata = MemoryMetadata(
            objectType: "plan",
            description: description,
            confidence: importance,
            tags: tags,
            spatialData: nil,
            timestamp: plan.timestamp,
            location: location
        )

        let entry = VectorEntry(
            id: plan.id,
            embedding: embedding,
            metadata: metadata,
            memoryLayer: .episodic
        )

        try await vectorDatabase.insert(entry)

        print("📅 Added plan: \(title) (scheduled: \(scheduledDate))")
        updateUpcomingPlans()
    }

    /// Mark plan as completed
    func markPlanCompleted(_ planId: UUID, completedDate: Date = Date()) {
        guard var plan = plans[planId] else { return }

        plan.isCompleted = true
        plan.completedDate = completedDate
        plan.lastModified = Date()

        plans[planId] = plan

        print("✅ Marked plan completed: \(plan.title)")
        updateUpcomingPlans()
    }

    // MARK: - Hybrid Memory

    /// Create hybrid memory linking physical and conceptual
    func createHybridMemory(
        physicalMemories: [UUID],
        location: CLLocationCoordinate2D?,
        thoughts: [UUID] = [],
        conversations: [UUID] = [],
        ideas: [UUID] = [],
        notes: [UUID] = [],
        plans: [UUID] = [],
        synthesizedMeaning: String
    ) async throws {
        // Generate embedding from synthesized meaning
        let embedding = try await embeddingGenerator.generateEmbedding(from:synthesizedMeaning)

        let hybrid = HybridMemory(
            physicalMemories: physicalMemories,
            location: location,
            thoughts: thoughts,
            conversations: conversations,
            ideas: ideas,
            notes: notes,
            plans: plans,
            synthesizedMeaning: synthesizedMeaning,
            embedding: embedding,
            importance: 0.8  // Hybrid memories are important
        )

        hybridMemories[hybrid.id] = hybrid

        // Store in semantic layer (long-term)
        let metadata = MemoryMetadata(
            objectType: "hybrid",
            description: synthesizedMeaning,
            confidence: 0.8,
            tags: ["hybrid", "synthesis"],
            spatialData: nil,
            timestamp: hybrid.timestamp,
            location: location
        )

        let entry = VectorEntry(
            id: hybrid.id,
            embedding: embedding,
            metadata: metadata,
            memoryLayer: .semantic
        )

        try await vectorDatabase.insert(entry)

        print("🔗 Created hybrid memory: \(synthesizedMeaning.prefix(50))...")
    }

    // MARK: - UI Update Helpers

    private func updateRecentThoughts() {
        recentThoughts = Array(thoughts.values.sorted { $0.timestamp > $1.timestamp }.prefix(10))
    }

    private func updateRecentIdeas() {
        recentIdeas = Array(ideas.values.sorted { $0.timestamp > $1.timestamp }.prefix(10))
    }

    private func updateUpcomingPlans() {
        upcomingPlans = Array(plans.values
            .filter { !$0.isCompleted && $0.scheduledDate > Date() }
            .sorted { $0.scheduledDate < $1.scheduledDate }
            .prefix(10))
    }

    // MARK: - Statistics

    func getStatistics() -> ConceptualMemoryStatistics {
        let totalMemories = thoughts.count + conversations.count + ideas.count + notes.count + plans.count
        let totalMerged = conversations.values.filter { ($0.mergedFrom?.count ?? 0) > 0 }.count
        let implementedIdeas = ideas.values.filter { $0.status == .implemented }.count

        return ConceptualMemoryStatistics(
            totalThoughts: thoughts.count,
            totalConversations: conversations.count,
            totalIdeas: ideas.count,
            totalNotes: notes.count,
            totalPlans: plans.count,
            totalHybrid: hybridMemories.count,
            totalMemories: totalMemories,
            mergedConversations: totalMerged,
            implementedIdeas: implementedIdeas,
            redundancyRate: totalMerged > 0 ? Float(totalMerged) / Float(conversations.count) : 0.0
        )
    }
}

// MARK: - Statistics Structure

struct ConceptualMemoryStatistics {
    let totalThoughts: Int
    let totalConversations: Int
    let totalIdeas: Int
    let totalNotes: Int
    let totalPlans: Int
    let totalHybrid: Int
    let totalMemories: Int
    let mergedConversations: Int
    let implementedIdeas: Int
    let redundancyRate: Float
}

// MARK: - Usage Example

/*
 // In TrinityCoordinator:

 private let conceptualMemoryManager: ConceptualMemoryManager

 // Initialize
 self.conceptualMemoryManager = ConceptualMemoryManager(
     vectorDatabase: vectorDB,
     embeddingGenerator: embeddingGenerator
 )

 // Add thought
 try await conceptualMemoryManager.addThought(
     content: "Ich muss Milch kaufen",
     category: .reminder,
     importance: 0.7,
     linkedLocation: currentLocation
 )

 // Add conversation
 let messages = [
     ConversationMemory.Message(
         speaker: "User",
         content: "Was ist das beste Café hier?",
         embedding: embedding1
     ),
     ConversationMemory.Message(
         speaker: "Friend",
         content: "Café Central ist super!",
         embedding: embedding2
     )
 ]

 try await conceptualMemoryManager.addConversation(
     participants: ["User", "Friend"],
     messages: messages,
     summary: "Diskussion über beste Cafés in der Nähe",
     keyTopics: ["café", "empfehlung"],
     keyInsights: ["Café Central empfohlen"],
     location: currentLocation,
     importance: 0.6
 )

 // Add idea
 try await conceptualMemoryManager.addIdea(
     title: "Voice-first navigation app",
     description: "App that uses only voice for blind users",
     tags: ["accessibility", "voice", "innovation"],
     importance: 0.8
 )

 // Search
 let results = try await conceptualMemoryManager.searchThoughts(query: "Milch kaufen")

 // Get statistics
 let stats = conceptualMemoryManager.getStatistics()
 print("Total memories: \(stats.totalMemories)")
 print("Redundancy rate: \(String(format: "%.1f%%", stats.redundancyRate * 100))")
 */
