import Foundation

public enum DeepSeekConfiguration {
    public static let defaultModel = "deepseek-flash"

    public static func resolvedModel(_ model: String, baseURL: String) -> String {
        let value = model.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.isEmpty { return defaultModel }
        if URL(string: baseURL)?.host?.lowercased() == "api.deepseek.com", value == "deepseek-chat" {
            return defaultModel
        }
        return value
    }
}

public enum DeepSeekServiceError: LocalizedError {
    case httpStatus(Int)
    case invalidResponse

    public var errorDescription: String? {
        switch self {
        case .invalidResponse: return "DeepSeek 没有返回有效的词条 JSON，请重试。"
        case .httpStatus(let code):
            let reason: String
            switch code {
            case 400, 422: reason = "模型名称或请求参数无效；官方服务请使用 deepseek-flash。"
            case 401: reason = "API Key 鉴权失败，请在配置中心更新 DeepSeek Key。"
            case 402: reason = "API 账户余额不足，请检查 DeepSeek 开放平台余额。"
            case 403: reason = "当前 Key 没有访问权限，请检查账户与服务权限。"
            case 404: reason = "接口或模型不存在；请检查服务地址和模型名称。"
            case 408, 504: reason = "请求超时，请稍后重试。"
            case 429: reason = "请求过于频繁，请稍后重试。"
            case 500...599: reason = "服务暂时不可用，请稍后重试。"
            default: reason = "请求未成功，请检查供应商配置。"
            }
            // Provider response bodies can echo credentials or source text; never forward them to a web page.
            return "DeepSeek HTTP \(code)：\(reason)"
        }
    }
}
