import OpenAIKit

extension String: ModelID {
  public var id: String {
    self
  }
}
