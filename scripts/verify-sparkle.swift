import Foundation
import CryptoKit

enum VerificationError: Error { case failed(String) }

func require(_ condition: Bool, _ message: String) throws {
    if !condition { throw VerificationError.failed(message) }
}

final class Enclosure: NSObject, XMLParserDelegate {
    var signature: String?
    func parser(_ parser: XMLParser, didStartElement element: String,
                namespaceURI: String?, qualifiedName: String?, attributes: [String: String]) {
        if element == "enclosure" && signature == nil { signature = attributes["sparkle:edSignature"] }
    }
}

func verify() throws {
    let args = Array(CommandLine.arguments.dropFirst())
    try require(args.count == 3,
                "Usage: verify-sparkle.swift --check-key PRIVATE_KEY_FILE INFO_PLIST | INFO_PLIST APPCAST_XML DMG")
    let checkKey = args[0] == "--check-key"
    let plistPath = checkKey ? args[2] : args[0]
    let plist = try PropertyListSerialization.propertyList(
        from: Data(contentsOf: URL(fileURLWithPath: plistPath)), format: nil) as? [String: Any]
    guard let text = plist?["SUPublicEDKey"] as? String, let expected = Data(base64Encoded: text) else {
        throw VerificationError.failed("Missing Sparkle public key in Info.plist")
    }
    if checkKey {
        let seedText = try String(contentsOfFile: args[1], encoding: .utf8)
            .components(separatedBy: .whitespacesAndNewlines).joined()
        guard let seed = Data(base64Encoded: seedText) else {
            throw VerificationError.failed("Invalid Sparkle private-key encoding")
        }
        let privateKey = try Curve25519.Signing.PrivateKey(rawRepresentation: seed)
        try require(privateKey.publicKey.rawRepresentation == expected,
                    "Sparkle private key does not match Info.plist; restore the existing key")
        print("Sparkle signing key matches Info.plist.")
        return
    }

    let publicKey = try Curve25519.Signing.PublicKey(rawRepresentation: expected)
    let feed = try Data(contentsOf: URL(fileURLWithPath: args[1]))
    let archive = try Data(contentsOf: URL(fileURLWithPath: args[2]))
    let enclosure = Enclosure()
    let parser = XMLParser(data: feed)
    parser.delegate = enclosure
    try require(parser.parse(), "Invalid appcast XML")
    guard let signatureText = enclosure.signature, let signature = Data(base64Encoded: signatureText) else {
        throw VerificationError.failed("Missing DMG update signature")
    }
    try require(publicKey.isValidSignature(signature, for: archive), "DMG update signature is invalid")
    guard let feedText = String(data: feed, encoding: .utf8),
          let footer = feedText.range(of: "<!-- sparkle-signatures:", options: .backwards) else {
        throw VerificationError.failed("Missing signed appcast footer")
    }
    let trailer = String(feedText[footer.lowerBound...]) as NSString
    let regex = try NSRegularExpression(pattern: "edSignature: (\\S+)\\s+length: (\\d+)")
    guard let match = regex.firstMatch(in: trailer as String, range: NSRange(location: 0, length: trailer.length)),
          let feedSignature = Data(base64Encoded: trailer.substring(with: match.range(at: 1))),
          let length = Int(trailer.substring(with: match.range(at: 2))),
          length == feedText[..<footer.lowerBound].utf8.count else {
        throw VerificationError.failed("Invalid signed appcast footer")
    }
    try require(publicKey.isValidSignature(feedSignature, for: Data(feed.prefix(length))),
                "Appcast update signature is invalid")
    print("DMG and appcast signatures match the app's Sparkle public key.")
}

do { try verify() }
catch VerificationError.failed(let message) { fputs("\(message)\n", stderr); exit(1) }
catch { fputs("Sparkle verification failed: \(error.localizedDescription)\n", stderr); exit(1) }
