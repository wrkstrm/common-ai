import Foundation

public enum CAIRole: String, Sendable, Codable {
  case user
  case model
  case system
}

public enum CAIPart: Sendable, Equatable, Codable {
  case text(String)
}

public struct CAIContent: Sendable, Equatable, Codable {
  public let role: CAIRole
  public let parts: [CAIPart]

  public init(role: CAIRole, parts: [CAIPart]) {
    self.role = role
    self.parts = parts
  }

  public static func user(_ text: String) -> CAIContent { .init(role: .user, parts: [.text(text)]) }
  public static func model(_ text: String) -> CAIContent {
    .init(role: .model, parts: [.text(text)])
  }

  public static func system(_ text: String) -> CAIContent {
    .init(role: .system, parts: [.text(text)])
  }
}

public struct CAIMessage: Sendable, Equatable, Codable {
  public let role: CAIRole
  public let text: String
  public init(role: CAIRole, text: String) {
    self.role = role
    self.text = text
  }
}

public struct CAIChoice: Sendable, Equatable, Codable {
  public let index: Int
  public let message: CAIMessage
  public let finishReason: String?
  public init(index: Int, message: CAIMessage, finishReason: String?) {
    self.index = index
    self.message = message
    self.finishReason = finishReason
  }
}

public struct CAIUsage: Sendable, Equatable, Codable {
  public let promptTokens: Int?
  public let completionTokens: Int?
  public let totalTokens: Int?
  public init(promptTokens: Int?, completionTokens: Int?, totalTokens: Int?) {
    self.promptTokens = promptTokens
    self.completionTokens = completionTokens
    self.totalTokens = totalTokens
  }
}

public struct CAICompletion: Sendable, Equatable, Codable {
  public let id: String
  public let object: String
  public let created: Int
  public let model: String
  public let choices: [CAIChoice]
  public let usage: CAIUsage?
  public let metadata: [String: String]?

  public init(
    id: String,
    object: String = "chat.completion",
    created: Int,
    model: String,
    choices: [CAIChoice],
    usage: CAIUsage? = nil,
    metadata: [String: String]? = nil
  ) {
    self.id = id
    self.object = object
    self.created = created
    self.model = model
    self.choices = choices
    self.usage = usage
    self.metadata = metadata
  }

  public var primaryMessage: CAIMessage {
    choices.first?.message ?? CAIMessage(role: .model, text: "")
  }
}

public struct CAIModelInfo: Sendable, Equatable, Codable, Identifiable {
  public var id: String { name }
  public let name: String
  public let displayName: String?
  public let description: String?
  public let inputTokenLimit: Int?
  public let outputTokenLimit: Int?
  public init(
    name: String,
    displayName: String? = nil,
    description: String? = nil,
    inputTokenLimit: Int? = nil,
    outputTokenLimit: Int? = nil,
  ) {
    self.name = name
    self.displayName = displayName
    self.description = description
    self.inputTokenLimit = inputTokenLimit
    self.outputTokenLimit = outputTokenLimit
  }
}

public protocol CommonAIModel: Sendable {
  var name: String { get }
  func complete(_ content: [CAIContent]) async throws -> CAICompletion
  @MainActor func startChat(history: [CAIContent]) -> any CommonAIChat
}

extension CommonAIModel {
  public func complete(text: String) async throws -> CAICompletion {
    try await complete([.user(text)])
  }

  public func generate(_ content: [CAIContent]) async throws -> CAIMessage {
    try await complete(content).primaryMessage
  }

  public func generateText(_ text: String) async throws -> CAIMessage {
    try await complete(text: text).primaryMessage
  }
}

@MainActor
public protocol CommonAIChat: Sendable {
  var history: [CAIContent] { get }
  func send(_ content: [CAIContent]) async throws -> CAIMessage
  #if canImport(Darwin)
  @available(macOS 12.0, *)
  func sendStream(_ content: [CAIContent]) -> AsyncThrowingStream<CAIMessage, Error>
  #endif
}

public protocol CommonAIService: Sendable {
  var providerName: String { get }
  func model(named: String) -> any CommonAIModel
  func listModels(pageSize: Int?) async throws -> [CAIModelInfo]
}
