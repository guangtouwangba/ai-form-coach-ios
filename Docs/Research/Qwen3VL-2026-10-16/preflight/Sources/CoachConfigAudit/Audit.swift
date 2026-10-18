import Foundation
import CoachQwenPreflight
import Tokenizers

@main
struct CoachConfigAudit {
    static func main() async throws {
        guard CommandLine.arguments.count == 2 else {
            fatalError("Usage: CoachConfigAudit <local tokenizer/config folder; no weights required>")
        }
        let folder = URL(fileURLWithPath: CommandLine.arguments[1])
        let config = try CoachQwenPreflight.decode(
            config: Data(contentsOf: folder.appendingPathComponent("config.json")),
            processor: Data(contentsOf: folder.appendingPathComponent("preprocessor_config.json")))
        let tokenizer = try await AutoTokenizer.from(modelFolder: folder)
        let chinese = "请根据这六张连续画面判断徒手深蹲，只引用已有证据；看不清请说明。"
        let tokens = tokenizer.encode(text: chinese)
        guard tokenizer.decode(tokens: tokens) == chinese else {
            fatalError("Chinese round-trip differs")
        }
        let imageMessages: [Message] = [[
            "role": "user",
            "content": [
                ["type": "image"], ["type": "image"], ["type": "image"],
                ["type": "image"], ["type": "image"], ["type": "image"],
                ["type": "text", "text": chinese]
            ]
        ]]
        let imagePrompt = try tokenizer.applyChatTemplate(messages: imageMessages)
        let videoPrompt = try tokenizer.applyChatTemplate(messages: [[
            "role": "user", "content": [["type":"video"],["type":"text","text":"描述这个片段"]]
        ]])
        let imageMarkers = imagePrompt.filter { $0 == 151655 }.count
        let videoMarkers = videoPrompt.filter { $0 == 151656 }.count
        guard imageMarkers == 6, videoMarkers == 1 else { fatalError("Vision marker mismatch") }
        let result: [String: Any] = [
            "config": config, "chineseRoundTrip": true, "chineseTextTokens": tokens.count,
            "sixImageTemplateMarkers": imageMarkers, "videoTemplateMarkers": videoMarkers,
            "templateTokensBeforeVisualExpansion": imagePrompt.count,
            "eos151645": tokenizer.decode(tokens: [151645]),
            "scope": "configuration, CPU tokenization and template only; no MLXArray evaluation or weights"
        ]
        let data = try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted,.sortedKeys])
        print(String(decoding: data,as:UTF8.self))
    }
}
