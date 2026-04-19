import Foundation

class SVGButtonExtractor: NSObject, XMLParserDelegate {
    var paths: [String: String] = [:]
    var idStack: [String?] = []

    static func extract(url: URL) -> [String: String] {
        guard let parser = XMLParser(contentsOf: url) else {
            fatalError("Failed to create XMLParser for SVG: \(url.path)")
        }
        let delegate = SVGButtonExtractor()
        parser.delegate = delegate
        guard parser.parse() else {
            let message = parser.parserError?.localizedDescription ?? "Unknown parse error"
            fatalError("Failed to parse SVG: \(url.path) (\(message))")
        }
        return delegate.paths
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String : String] = [:]) {
        let id = attributeDict["id"]
        idStack.append(id)

        if elementName == "path", let d = attributeDict["d"] {
            // Find the closest active ID
            if let activeID = idStack.reversed().compactMap({ $0 }).first {
                paths[activeID] = d
            }
        }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        idStack.removeLast()
    }
}
