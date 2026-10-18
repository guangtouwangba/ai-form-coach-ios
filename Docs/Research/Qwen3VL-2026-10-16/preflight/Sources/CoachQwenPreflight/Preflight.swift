import Foundation
import MLXVLM
import MLXLMCommon
import Tokenizers

/// Explicit protocol adapter avoids requiring Xcode macro trust for this audit.
private struct LocalTokenizerLoader: MLXLMCommon.TokenizerLoader {
    func load(from directory: URL) async throws -> any MLXLMCommon.Tokenizer {
        let tokenizer = try await AutoTokenizer.from(modelFolder: directory)
        return LocalTokenizer(upstream: tokenizer)
    }
}

private struct LocalTokenizer: MLXLMCommon.Tokenizer {
    let upstream: any Tokenizers.Tokenizer
    func encode(text: String, addSpecialTokens: Bool) -> [Int] {
        upstream.encode(text: text, addSpecialTokens: addSpecialTokens)
    }
    func decode(tokenIds: [Int], skipSpecialTokens: Bool) -> String {
        upstream.decode(tokens: tokenIds, skipSpecialTokens: skipSpecialTokens)
    }
    func convertTokenToId(_ token: String) -> Int? { upstream.convertTokenToId(token) }
    func convertIdToToken(_ id: Int) -> String? { upstream.convertIdToToken(id) }
    var bosToken: String? { upstream.bosToken }
    var eosToken: String? { upstream.eosToken }
    var unknownToken: String? { upstream.unknownToken }
    func applyChatTemplate(messages: [[String: any Sendable]],
                           tools: [[String: any Sendable]]?,
                           additionalContext: [String: any Sendable]?) throws -> [Int] {
        do {
            return try upstream.applyChatTemplate(messages: messages, tools: tools,
                                                   additionalContext: additionalContext)
        } catch Tokenizers.TokenizerError.missingChatTemplate {
            throw MLXLMCommon.TokenizerError.missingChatTemplate
        }
    }
}

/// Shared local loader and configuration helpers for isolated Mac experiments.
public enum CoachQwenPreflight {
    public static func decode(config: Data, processor: Data) throws -> [String: Int] {
        let model = try JSONDecoder().decode(Qwen3VLConfiguration.self, from: config)
        let image = try JSONDecoder().decode(Qwen3VLProcessorConfiguration.self, from: processor)
        return [
            "layers": model.textConfiguration.numHiddenLayers,
            "kvHeads": model.textConfiguration.numKeyValueHeads,
            "headDim": model.textConfiguration.headDim,
            "patchSize": image.patchSize,
            "mergeSize": image.mergeSize,
            "minPixels": image.minPixels,
            "maxPixels": image.maxPixels,
        ]
    }
    public static func boundedProcessing() -> UserInput.Processing {
        var value = UserInput.Processing()
        value.minPixels = 65_536
        value.maxPixels = 262_144
        return value
    }

    /// The configuration-only executable never calls this. The separately
    /// authorized Mac video benchmark loads and evaluates real local weights.
    public static func loadLocalWeights(at directory: URL) async throws -> ModelContainer {
        try await loadModelContainer(from: directory, using: LocalTokenizerLoader())
    }
}
