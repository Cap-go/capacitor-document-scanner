/**
 Allows throwing runtime errors with a custom message.
 */
enum RuntimeError: Error {
    case message(String)
}
