import Foundation

enum ClaudeProviderError: LocalizedError {
    case invalidURL
    case missingCredential
    case unauthorized
    case forbidden
    case rateLimited
    case httpStatus(Int)
    case invalidResponse
    case decoding(Error)
    case network(URLError)
    case localParsing(Error)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Claude usage endpoint URL is invalid."
        case .missingCredential:
            return "Claude authentication is required."
        case .unauthorized:
            return "Claude token is invalid or expired."
        case .forbidden:
            return "This account cannot access usage limit information."
        case .rateLimited:
            return "Claude usage API is rate limited. Try again later."
        case .httpStatus(let code):
            return "Claude usage API returned HTTP \(code)."
        case .invalidResponse:
            return "Claude usage API returned an unexpected response format."
        case .decoding(let err):
            return "Claude usage response format changed: \(err.localizedDescription)"
        case .network(let err):
            return "Network error: \(err.localizedDescription)"
        case .localParsing(let err):
            return "Could not read local Claude logs: \(err.localizedDescription)"
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .missingCredential:
            return "Connect Claude in Perch settings."
        case .unauthorized:
            return "Re-authenticate Claude in Perch settings."
        case .rateLimited:
            return "Wait a few minutes before refreshing."
        case .decoding:
            return "Update Perch to the latest version."
        default:
            return nil
        }
    }
}
