import AsyncHTTPClient
import CommonAI
import Foundation
import OpenAIKit
@preconcurrency import OpenAIStreamingCompletions

public struct OpenAICommonAIService: CommonAIService {
  public let providerName = "OpenAI"
  private let apiKey: String
  private let organization: String?
  public init(apiKey: String, organization: String? = nil) {
    self.apiKey = apiKey
    self.organization = organization
  }

  public func model(named name: String) -> any CommonAIModel {
    OpenAICommonAIModel(name: name, apiKey: apiKey, organization: organization)
  }

  public func listModels(pageSize _: Int? = nil) async throws -> [CAIModelInfo] {
    struct Models: Decodable { let data: [Model] }
    struct Model: Decodable { let id: String }
    var req = HTTPClientRequest(url: "https://api.openai.com/v1/models")
    req.method = .GET
    req.headers.add(name: "Authorization", value: "Bearer \(apiKey)")
    if let org = organization { req.headers.add(name: "OpenAI-Organization", value: org) }
    let client = HTTPClient(eventLoopGroupProvider: .singleton)
    let res = try await client.execute(req, timeout: .seconds(10))
    var buf = try await res.body.collect(upTo: 1 << 22)
    let data = buf.readData(length: buf.readableBytes) ?? Data()
    let models = try JSONDecoder().decode(Models.self, from: data)
    return models.data.map { .init(name: $0.id) }
  }
}

public final class OpenAICommonAIModel: @unchecked Sendable, CommonAIModel {
  public let name: String
  private let client: Client
  fileprivate let streamer: OpenAIAPI
  public init(name: String, apiKey: String, organization: String? = nil) {
    self.name = name
    let cfg = OpenAIKit.Configuration(apiKey: apiKey, organization: organization)
    let http = HTTPClient(eventLoopGroupProvider: .singleton)
    client = Client(httpClient: http, configuration: cfg)
    streamer = OpenAIAPI(apiKey: apiKey, orgId: organization)
  }

  public func complete(_ content: [CAIContent]) async throws -> CAICompletion {
    let msgs = Self.makeOpenAIKitMessages(content)
    let chat = try await client.chats.create(model: name, messages: msgs)
    let text = chat.choices.first?.message.content ?? ""
    let choice = CAIChoice(index: 0, message: .init(role: .model, text: text), finishReason: nil)
    let metadata = ["provider": "openai"]
    return CAICompletion(
      id: "cai-" + UUID().uuidString.lowercased(),
      created: Int(Date().timeIntervalSince1970),
      model: name,
      choices: [choice],
      usage: nil,
      metadata: metadata
    )
  }

  @MainActor public func startChat(history: [CAIContent]) -> any CommonAIChat {
    OpenAICommonAIChat(model: self, history: history)
  }

  static func makeOpenAIKitMessages(_ content: [CAIContent]) -> [Chat.Message] {
    content.flatMap { c -> [Chat.Message] in
      let text = c.parts.compactMap {
        guard case .text(let t) = $0 else { return nil }
        return t
      }.joined()
      switch c.role {
      case .user: return [.user(content: text)]
      case .system: return [.system(content: text)]
      case .model: return [.assistant(content: text)]
      }
    }
  }
}

@MainActor public final class OpenAICommonAIChat: CommonAIChat {
  private let model: OpenAICommonAIModel
  public private(set) var history: [CAIContent]
  init(model: OpenAICommonAIModel, history: [CAIContent]) {
    self.model = model
    self.history = history
  }

  public func send(_ content: [CAIContent]) async throws -> CAIMessage {
    let msg = try await model.generate(content)
    history.append(contentsOf: content)
    history.append(.model(msg.text))
    return msg
  }

  #if canImport(Darwin)
  @available(macOS 12.0, *)
  public func sendStream(_ content: [CAIContent]) -> AsyncThrowingStream<CAIMessage, Error> {
    let messages: [OpenAIAPI.Message] = {
      var out: [OpenAIAPI.Message] = []
      for c in content {
        let t = c.parts.compactMap {
          guard case .text(let s) = $0 else { return nil }
          return s
        }.joined()
        let role: OpenAIAPI.Message.Role =
          (c.role == .user ? .user : c.role == .system ? .system : .assistant)
        out.append(.init(role: role, content: t))
      }
      return out
    }()
    let req = OpenAIAPI.ChatCompletionRequest(messages: messages, model: model.name)
    guard let base = try? model.streamer.completeChatStreaming(req) else {
      return AsyncThrowingStream { $0.finish(throwing: NSError(domain: "openai", code: -1)) }
    }
    var it = base.makeAsyncIterator()
    return AsyncThrowingStream {
      guard let m = await it.next() else { return nil }
      return .init(role: .model, text: m.content)
    }
  }
  #endif
}
