#if canImport(FoundationModels)
import CommonAI
@testable import CommonAIApple
import Foundation
import FoundationModels
import Testing

struct ApplePromptBuilderTests {
  @Test
  func makeContextBuildsTranscriptHistory() throws {
    guard #available(iOS 26.0, macOS 26.0, *) else { return }
    let contents: [CAIContent] = [
      .system("Follow the user's lead."),
      .user("Hello."),
      .model("Hi there!"),
      .user("Share three bullet points about Apple Intelligence."),
    ]

    let context = try ApplePromptBuilder.makeContext(from: contents)
    let entries = Array(context.transcript)

    #expect(entries.count == 3)

    if case .instructions(let instructions) = entries.first {
      let instructionText = instructions.segments.compactMap { segment -> String? in
        guard case .text(let segmentText) = segment else { return nil }
        return segmentText.content
      }.joined(separator: "\n")
      #expect(instructionText.contains("Follow the user's lead."))
    } else {
      Issue.record("Expected instructions entry at transcript start.")
    }

    if case .prompt(let prompt) = entries.dropFirst().first {
      let promptText = prompt.segments.compactMap { segment -> String? in
        guard case .text(let segmentText) = segment else { return nil }
        return segmentText.content
      }.joined(separator: "\n")
      #expect(promptText == "Hello.")
    } else {
      Issue.record("Expected prompt entry for first user message.")
    }

    if case .response(let response) = entries.last {
      let responseText = response.segments.compactMap { segment -> String? in
        guard case .text(let segmentText) = segment else { return nil }
        return segmentText.content
      }.joined(separator: "\n")
      #expect(responseText == "Hi there!")
    } else {
      Issue.record("Expected response entry for assistant message.")
    }
  }

  @Test
  func makeContextRequiresTrailingUserMessage() {
    guard #available(iOS 26.0, macOS 26.0, *) else { return }
    let contents: [CAIContent] = [
      .user("Explain the weather."),
      .model("It is sunny today."),
    ]

    do {
      _ = try ApplePromptBuilder.makeContext(from: contents)
      Issue.record("Expected missingUserPrompt error to be thrown.")
    } catch AppleCommonAIError.missingUserPrompt {
      // Expected path.
    } catch {
      Issue.record("Unexpected error: \(error)")
    }
  }
}
#endif
