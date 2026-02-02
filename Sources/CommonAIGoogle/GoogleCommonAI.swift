import CommonAI
import Foundation
import GoogleGenerativeAI
import WrkstrmFoundation
import CommonLog
import WrkstrmNetworking

public struct GoogleCommonAIService: CommonAIService {
  public let providerName = "Google Generative AI"
  private let apiKey: String
  public init(apiKey: String) { self.apiKey = apiKey }

  public func model(named name: String) -> any CommonAIModel {
    GoogleCommonAIModel(name: name, apiKey: apiKey)
  }

  public func listModels(pageSize: Int? = nil) async throws -> [CAIModelInfo] {
    let env = AI.GoogleGenAI.Environment.betaEnv(with: apiKey)
    let client = HTTP.CodableClient(
      environment: env,
      json: (.commonDateFormatting, .commonDateParsing),
    )
    let response = try await client.send(
      ListModels.Request(options: .init(), pageSize: pageSize),
    )
    return response.models.map { m in
      CAIModelInfo(
        name: m.name,
        displayName: m.displayName,
        description: m.description,
        inputTokenLimit: m.inputTokenLimit,
        outputTokenLimit: m.outputTokenLimit,
      )
    }
  }
}

public final class GoogleCommonAIModel: @unchecked Sendable, CommonAIModel {
  public let name: String
  private let model: GenerativeModel
  public init(name: String, apiKey: String) {
    self.name = name
    model = .init(name: name, apiKey: apiKey)
  }

  public func complete(_ content: [CAIContent]) async throws -> CAICompletion {
    let mc = try content.map(Self.toModelContent(_:))
    let response = try await model.generateContent(mc)
    let choices: [CAIChoice] = response.candidates.enumerated().map { index, candidate in
      let text = candidate.content.parts.compactMap { part -> String? in
        if case .text(let value) = part { return value }
        return nil
      }.joined(separator: "\n")
      return CAIChoice(
        index: index,
        message: .init(role: .model, text: text),
        finishReason: candidate.finishReason?.rawValue
      )
    }
    let usage = response.usageMetadata.map { metadata in
      CAIUsage(
        promptTokens: metadata.promptTokenCount,
        completionTokens: metadata.candidatesTokenCount,
        totalTokens: metadata.totalTokenCount
      )
    }
    let finalChoices =
      choices.isEmpty
      ? [
        CAIChoice(
          index: 0, message: .init(role: .model, text: response.text ?? ""), finishReason: nil)
      ]
      : choices
    return CAICompletion(
      id: "cai-" + UUID().uuidString.lowercased(),
      created: Int(Date().timeIntervalSince1970),
      model: name,
      choices: finalChoices,
      usage: usage,
      metadata: ["provider": "google-genai"]
    )
  }

  @MainActor public func startChat(history: [CAIContent]) -> any CommonAIChat {
    let h = (try? history.map(Self.toModelContent(_:))) ?? []
    return GoogleCommonAIChat(chat: model.startChat(history: h))
  }

  fileprivate static func toModelContent(_ c: CAIContent) throws -> ModelContent {
    let role =
      switch c.role {
      case .user: "user"
      case .model: "model"
      case .system: "system"
      }
    let parts: [ModelContent.Part] = c.parts.map { part in
      guard case .text(let t) = part else { return ModelContent.Part.text("") }
      return ModelContent.Part.text(t)
    }
    return ModelContent(role: role, parts: parts)
  }
}

@MainActor public final class GoogleCommonAIChat: CommonAIChat {
  private let chat: Chat
  public private(set) var history: [CAIContent]
  init(chat: Chat) {
    self.chat = chat
    history = []
  }

  public func send(_ content: [CAIContent]) async throws -> CAIMessage {
    let mc = try content.map(GoogleCommonAIModel.toModelContent(_:))
    let r = try await chat.sendMessage(mc)
    let text = r.text ?? ""
    history.append(contentsOf: content)
    history.append(CAIContent.model(text))
    return .init(role: .model, text: text)
  }

  #if canImport(Darwin)
  @available(macOS 12.0, *)
  public func sendStream(_ content: [CAIContent]) -> AsyncThrowingStream<
    CAIMessage, Error
  > {
    let mc = (try? content.map(GoogleCommonAIModel.toModelContent(_:))) ?? []
    var it = chat.sendMessageStream(mc).makeAsyncIterator()
    return AsyncThrowingStream {
      guard let r = try await it.next() else { return nil }
      return .init(role: .model, text: r.text ?? "")
    }
  }
  #endif
}
