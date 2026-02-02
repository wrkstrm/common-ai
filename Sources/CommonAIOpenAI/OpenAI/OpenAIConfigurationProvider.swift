import Foundation
import OpenAIKit

public protocol OpenAIConfigurationProvider {
  static var aiConfiguration: OpenAIKit.Configuration { get }
  static func load(apiKeyFlag: String?, orgFlag: String?) -> (apiKey: String, org: String?)?
}

public struct DefaultOpenAIConfigurationProvider: OpenAIConfigurationProvider {
  // Keychain integration intentionally disabled in the basic SPM build.
  public static func aiKeyFromKeychain() -> String? { nil }

  public static func load(apiKeyFlag: String?, orgFlag: String?) -> (apiKey: String, org: String?)?
  {
    // 1) Explicit flag takes precedence
    if let flag = apiKeyFlag, !flag.isEmpty { return (flag, orgFlag) }
    // 2) Keychain (disabled in basic build)
    // 3) Environment variables
    let env = ProcessInfo.processInfo.environment
    let apiKey = env["OPENAI_API_KEY"] ?? env["OPENAI_KEY"] ?? env["OPENAI_APIKEY"]
    if let apiKey, !apiKey.isEmpty {
      let org =
        orgFlag
        ?? env["OPENAI_ORG_ID"]
        ?? env["OPENAI_ORG"]
        ?? env["OPENAI_ORGANIZATION"]
      return (apiKey, org)
    }
    // Nothing found
    return nil
  }

  public static var aiConfiguration: OpenAIKit.Configuration {
    let tuple = load(apiKeyFlag: nil, orgFlag: nil)
    return .init(apiKey: tuple?.apiKey ?? "", organization: tuple?.org)
  }
}
