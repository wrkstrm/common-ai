// swift-tools-version:6.1
import Foundation
import PackageDescription

let useLocalDeps: Bool = {
  // Default to local monorepo deps unless explicitly disabled.
  guard let raw = ProcessInfo.processInfo.environment["SPM_USE_LOCAL_DEPS"] else { return true }
  let v = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
  return !(v == "0" || v == "false" || v == "no")
}()

func localOrRemote(name: String, path: String, url: String, from version: Version) -> Package.Dependency {
  if useLocalDeps { return .package(name: name, path: path) }
  return .package(url: url, from: version)
}

let package = Package(
  name: "CommonAI",
  platforms: [
    .iOS(.v17),
    .macOS(.v15),
    .tvOS(.v16),
    .watchOS(.v9),
  ],
  products: [
    .library(name: "CommonAI", targets: ["CommonAI"]),
    .library(name: "CommonAIGoogle", targets: ["CommonAIGoogle"]),
    .library(name: "CommonAIOpenAI", targets: ["CommonAIOpenAI"]),
    .library(name: "CommonAIApple", targets: ["CommonAIApple"]),
  ],
  dependencies: [
    // Local monorepo dependencies
    localOrRemote(
      name: "wrkstrm-foundation",
      path: "../../../../../../../wrkstrm/public/spm/universal/domain/system/wrkstrm-foundation",
      url: "https://github.com/wrkstrm/wrkstrm-foundation.git",
      from: "3.0.0"),
    localOrRemote(
      name: "wrkstrm-networking",
      path: "../../../../../../../wrkstrm/public/spm/universal/domain/system/wrkstrm-networking",
      url: "https://github.com/wrkstrm/wrkstrm-networking.git",
      from: "3.0.0"),
    localOrRemote(
      name: "common-log",
      path: "../../../../../../../swift-universal/public/spm/universal/domain/system/common-log",
      url: "https://github.com/swift-universal/common-log.git",
      from: "3.0.0"),
    localOrRemote(
      name: "google-ai-swift",
      path: "../../../../../../../wrkstrm/public/spm/universal/domain/ai/google-ai-swift",
      url: "https://github.com/wrkstrm/google-ai-swift.git",
      from: "1.0.0"),
    // External dependencies
    .package(
      url: "https://github.com/dylanshine/openai-kit.git",
      from: "1.0.0",
    ),
    .package(
      url: "https://github.com/nate-parrott/openai-streaming-completions-swift.git",
      from: "1.0.1",
    ),
    .package(
      url: "https://github.com/swift-server/async-http-client.git",
      from: "1.9.0",
    ),
  ],
  targets: [
    // Core protocols and types
    .target(
      name: "CommonAI",
      dependencies: [],
    ),
    // Google Generative AI adapters
    .target(
      name: "CommonAIGoogle",
      dependencies: [
        "CommonAI",
        .product(name: "GoogleGenerativeAI", package: "google-ai-swift"),
        .product(name: "WrkstrmFoundation", package: "wrkstrm-foundation"),
        .product(name: "CommonLog", package: "common-log"),
        .product(name: "WrkstrmNetworking", package: "wrkstrm-networking"),
      ],
    ),
    // OpenAI adapters
    .target(
      name: "CommonAIOpenAI",
      dependencies: [
        "CommonAI",
        .product(name: "OpenAIKit", package: "openai-kit"),
        .product(
          name: "OpenAIStreamingCompletions",
          package: "openai-streaming-completions-swift",
        ),
        .product(name: "AsyncHTTPClient", package: "async-http-client"),
      ],
      path: "Sources/CommonAIOpenAI",
    ),
    .target(
      name: "CommonAIApple",
      dependencies: ["CommonAI"],
      path: "Sources/CommonAIApple",
    ),
    .testTarget(
      name: "CommonAIAppleTests",
      dependencies: [
        "CommonAIApple"
      ],
    ),
  ],
)
