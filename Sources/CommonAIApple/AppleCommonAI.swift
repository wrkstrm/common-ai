#if canImport(FoundationModels)
import CommonAI
import Foundation
import FoundationModels

@available(iOS 26.0, macOS 26.0, *)
public struct AppleCommonAIService: CommonAIService {
  public let providerName = "Apple Intelligence"
  private let guardrails: SystemLanguageModel.Guardrails

  public init(guardrails: SystemLanguageModel.Guardrails = .default) {
    self.guardrails = guardrails
  }

  public func model(named name: String) -> any CommonAIModel {
    let catalog = AppleModelCatalog.lookup(name: name)
    return AppleCommonAIModel(
      name: catalog.name,
      useCase: catalog.useCase,
      guardrails: guardrails,
    )
  }

  public func listModels(pageSize: Int? = nil) async throws -> [CAIModelInfo] {
    let entries = AppleModelCatalog.allCases
    let limited = pageSize.map { Array(entries.prefix($0)) } ?? entries
    return limited.map { catalog in
      CAIModelInfo(
        name: catalog.name,
        displayName: catalog.displayName,
        description: catalog.description,
        inputTokenLimit: nil,
        outputTokenLimit: nil,
      )
    }
  }
}

@available(iOS 26.0, macOS 26.0, *)
private enum AppleModelCatalog: CaseIterable {
  case general
  case contentTagging

  var name: String {
    switch self {
    case .general: "apple.system.general"
    case .contentTagging: "apple.system.content-tagging"
    }
  }

  var displayName: String {
    switch self {
    case .general: "Apple Intelligence (General)"
    case .contentTagging: "Apple Intelligence (Content Tagging)"
    }
  }

  var description: String {
    switch self {
    case .general:
      "Base on-device language model optimized for open-ended text generation."

    case .contentTagging:
      "Specialized variant tuned for structured content tagging responses."
    }
  }

  var useCase: SystemLanguageModel.UseCase? {
    switch self {
    case .general: .general
    case .contentTagging: .contentTagging
    }
  }

  static func lookup(name: String) -> AppleModelCatalog {
    allCases.first(where: { $0.name == name }) ?? .general
  }
}

@available(iOS 26.0, macOS 26.0, *)
public enum AppleCommonAIError: Error, LocalizedError {
  case modelUnavailable(SystemLanguageModel.Availability)
  case missingUserPrompt

  public var errorDescription: String? {
    switch self {
    case .modelUnavailable(let availability):
      switch availability {
      case .available:
        "Model reported available, but availability check failed."

      case .unavailable(let reason):
        "Apple Intelligence model unavailable: \(reason)."
      }

    case .missingUserPrompt:
      "No user message found to generate a response."
    }
  }
}

@available(iOS 26.0, macOS 26.0, *)
public final class AppleCommonAIModel: @unchecked Sendable, CommonAIModel {
  public let name: String
  private let systemLanguageModel: SystemLanguageModel
  init(
    name: String,
    useCase: SystemLanguageModel.UseCase?,
    guardrails: SystemLanguageModel.Guardrails,
  ) {
    self.name = name
    let resolvedUseCase = useCase ?? .general
    systemLanguageModel = SystemLanguageModel(
      useCase: resolvedUseCase,
      guardrails: guardrails,
    )
  }

  public func complete(_ content: [CAIContent]) async throws -> CAICompletion {
    try ensureAvailability()
    let context = try ApplePromptBuilder.makeContext(from: content)
    let session = LanguageModelSession(
      model: systemLanguageModel,
      transcript: context.transcript,
    )
    let response = try await session.respond(to: context.prompt)
    let message = CAIMessage(role: .model, text: response.content)
    let choice = CAIChoice(index: 0, message: message, finishReason: nil)
    return CAICompletion(
      id: "cai-" + UUID().uuidString.lowercased(),
      created: Int(Date().timeIntervalSince1970),
      model: name,
      choices: [choice],
      usage: nil,
      metadata: ["provider": "apple-intelligence"]
    )
  }

  @MainActor
  public func startChat(history: [CAIContent]) -> any CommonAIChat {
    AppleCommonAIChat(model: self, seedHistory: history)
  }

  private func ensureAvailability() throws {
    let availability = systemLanguageModel.availability
    guard case .available = availability else {
      throw AppleCommonAIError.modelUnavailable(availability)
    }
  }

  #if canImport(Darwin)
  @available(iOS 26.0, macOS 26.0, *)
  fileprivate func makeStreamingResponse(
    for content: [CAIContent],
  ) throws -> LanguageModelSession.ResponseStream<String> {
    try ensureAvailability()
    let context = try ApplePromptBuilder.makeContext(from: content)
    let session = LanguageModelSession(
      model: systemLanguageModel,
      transcript: context.transcript,
    )
    return session.streamResponse(to: context.prompt)
  }
  #endif
}

@available(iOS 26.0, macOS 26.0, *)
@MainActor
public final class AppleCommonAIChat: CommonAIChat {
  private let model: AppleCommonAIModel
  public private(set) var history: [CAIContent]

  init(model: AppleCommonAIModel, seedHistory: [CAIContent]) {
    self.model = model
    history = seedHistory
  }

  public func send(_ content: [CAIContent]) async throws -> CAIMessage {
    let pendingHistory = history + content
    let message = try await model.generate(pendingHistory)
    history.append(contentsOf: content)
    history.append(.model(message.text))
    return message
  }

  #if canImport(Darwin)
  @available(iOS 26.0, macOS 26.0, *)
  public func sendStream(_ content: [CAIContent]) -> AsyncThrowingStream<CAIMessage, Error> {
    let combinedHistory = history + content
    let stream: LanguageModelSession.ResponseStream<String>
    do {
      stream = try model.makeStreamingResponse(for: combinedHistory)
    } catch {
      return AsyncThrowingStream { continuation in
        continuation.finish(throwing: error)
      }
    }

    return AsyncThrowingStream { continuation in
      Task {
        var latestText = ""
        do {
          for try await snapshot in stream {
            latestText = snapshot.content
            continuation.yield(CAIMessage(role: .model, text: latestText))
          }
          continuation.finish()
          if !latestText.isEmpty {
            await MainActor.run {
              self.history.append(contentsOf: content)
              self.history.append(.model(latestText))
            }
          }
        } catch {
          continuation.finish(throwing: error)
        }
      }
    }
  }
  #endif
}

@available(iOS 26.0, macOS 26.0, *)
enum ApplePromptBuilder {
  static func makeContext(from contents: [CAIContent]) throws -> (
    transcript: Transcript, prompt: Prompt
  ) {
    let messages = contents
    let systemMessages = messages.filter { $0.role == .system }
    let nonSystemMessages = messages.filter { $0.role != .system }

    var entries: [Transcript.Entry] = []

    if let instructionsEntry = makeInstructionsEntry(from: systemMessages) {
      entries.append(instructionsEntry)
    }

    var pendingPrompt: CAIContent?
    var encounteredConversationEntries: [Transcript.Entry] = []

    for message in nonSystemMessages {
      switch message.role {
      case .user:
        if let carriedPrompt = pendingPrompt {
          // Two user messages in a row: treat prior prompt as part of history.
          encounteredConversationEntries.append(.prompt(makePromptEntry(from: carriedPrompt)))
        }
        pendingPrompt = message

      case .model:
        if let carriedPrompt = pendingPrompt {
          encounteredConversationEntries.append(.prompt(makePromptEntry(from: carriedPrompt)))
          pendingPrompt = nil
        }
        encounteredConversationEntries.append(.response(makeResponseEntry(from: message)))

      case .system:
        // Already handled
        break
      }
    }

    guard let currentPromptContent = pendingPrompt else {
      throw AppleCommonAIError.missingUserPrompt
    }

    entries.append(contentsOf: encounteredConversationEntries)

    let transcript = Transcript(entries: entries)
    let prompt = Prompt(currentPromptContent.makePromptText())
    return (transcript, prompt)
  }

  private static func makeInstructionsEntry(from contents: [CAIContent]) -> Transcript.Entry? {
    let text =
      contents
      .map { $0.joinedText() }
      .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
      .joined(separator: "\n")

    guard !text.isEmpty else { return nil }

    let segments = [Transcript.Segment.text(.init(content: text))]
    let instructions = Transcript.Instructions(segments: segments, toolDefinitions: [])
    return .instructions(instructions)
  }

  private static func makePromptEntry(from content: CAIContent) -> Transcript.Prompt {
    let segments = [Transcript.Segment.text(.init(content: content.joinedText()))]
    return Transcript.Prompt(segments: segments)
  }

  private static func makeResponseEntry(from content: CAIContent) -> Transcript.Response {
    let segments = [Transcript.Segment.text(.init(content: content.joinedText()))]
    return Transcript.Response(assetIDs: [], segments: segments)
  }
}

@available(iOS 26.0, macOS 26.0, *)
extension CAIContent {
  fileprivate func joinedText() -> String {
    parts.compactMap { part in
      if case .text(let value) = part { return value }
      return nil
    }.joined()
  }

  fileprivate func makePromptText() -> String {
    joinedText()
  }
}
#else
import CommonAI
import Foundation

public struct AppleCommonAIService: CommonAIService {
  public let providerName = "Apple Intelligence"

  public init() {}

  public func model(named name: String) -> any CommonAIModel {
    UnavailableAppleCommonAIModel(name: name)
  }

  public func listModels(pageSize _: Int? = nil) async throws -> [CAIModelInfo] {
    []
  }
}

struct UnavailableAppleCommonAIModel: CommonAIModel {
  let name: String

  func complete(_: [CAIContent]) async throws -> CAICompletion {
    throw UnavailableError()
  }

  @MainActor func startChat(history _: [CAIContent]) -> any CommonAIChat {
    UnavailableAppleCommonAIChat()
  }

  struct UnavailableError: Error {}
}

@MainActor
final class UnavailableAppleCommonAIChat: CommonAIChat {
  var history: [CAIContent] { [] }

  func send(_: [CAIContent]) async throws -> CAIMessage {
    throw UnavailableAppleCommonAIModel.UnavailableError()
  }

  #if canImport(Darwin)
  @available(iOS 26.0, macOS 26.0, *)
  func sendStream(_: [CAIContent]) -> AsyncThrowingStream<CAIMessage, Error> {
    AsyncThrowingStream { continuation in
      continuation.finish(throwing: UnavailableAppleCommonAIModel.UnavailableError())
    }
  }
  #endif
}
#endif
