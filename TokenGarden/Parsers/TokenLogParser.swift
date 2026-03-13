import Foundation

protocol TokenLogParser: Sendable {
    var name: String { get }
    var watchPaths: [String] { get }
    func parse(logLine: String) -> TokenEvent?
}
