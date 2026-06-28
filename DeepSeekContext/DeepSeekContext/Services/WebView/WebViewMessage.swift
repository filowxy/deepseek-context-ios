import Foundation

/// Messages sent from JavaScript to native.
enum IncomingWebViewMessage: Equatable {
    case finalReply(text: String)
    case sendStarted
    case domHealth(healthy: Bool, missingSelector: String?)
    case log(level: String, message: String)
    case error(String)
}

/// Commands sent from native to JavaScript.
enum OutgoingWebViewCommand: Equatable {
    case setInput(text: String)
    case appendInput(text: String)
    case injectSystem(text: String)
    case clickSend
    case getInput
    case getOutput
}
