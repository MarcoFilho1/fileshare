import Foundation
import Testing
@testable import FileShareCore

struct PartCompressionTests {
    /// Mesmo vetor do WireTest.java, feito por outra ferramenta (zlib do Python, DEFLATE cru):
    /// garante que Mac e Android falam o mesmo formato.
    static let sharedVector = "edc8b109c0201000c0c1beb7b3ca041f79306015dc1fc7b0b92baf7dab9e997f45cf113bdf553b9a94524a29a594524a29a594524a29a594524a29e5bd3c"
    static let sharedOriginal = Data(String(repeating: "FileShare;Mac;tablet;", count: 400).utf8)

    static func hex(_ s: String) -> Data {
        var d = Data()
        var i = s.startIndex
        while i < s.endIndex {
            let j = s.index(i, offsetBy: 2)
            d.append(UInt8(s[i..<j], radix: 16)!)
            i = j
        }
        return d
    }

    @Test func decodesSharedVector() throws {
        #expect(try PartCompression.decompress(Self.hex(Self.sharedVector)) == Self.sharedOriginal)
    }

    /// Texto repetitivo (como um CSV) encolhe muito e volta idêntico.
    @Test func textShrinksAndComesBackIdentical() throws {
        let csv = Data((1...20_000).map { "\($0);Fulano de Tal;2026-10-28;R$ \($0 % 97),00\n" }.joined().utf8.prefix(Wire.partSize))
        let small = try #require(PartCompression.compress(csv))
        #expect(small.count < csv.count / 3)
        #expect(try PartCompression.decompress(small) == csv)
    }

    /// Dados aleatórios (como um vídeo) não encolhem: vão como estão.
    @Test func randomDataIsNotCompressed() {
        var random = Data(count: Wire.partSize)
        random.withUnsafeMutableBytes { _ = SecRandomCopyBytes(kSecRandomDefault, $0.count, $0.baseAddress!) }
        #expect(PartCompression.compress(random) == nil)
    }

    /// Um pedaço que se expandiria além de 512 KB é recusado (proteção contra "bombas").
    @Test func refusesDecompressionBomb() throws {
        let huge = Data(count: Wire.partSize * 4) // zeros: comprime muitíssimo
        let bomb = try #require(PartCompression.compress(huge))
        #expect(throws: PartCompression.Failure.tooLarge) { try PartCompression.decompress(bomb) }
        #expect(throws: PartCompression.Failure.self) { try PartCompression.decompress(Data([0xFF, 0x00, 0x13])) }
    }

    @Test func skipsTypesThatAreAlreadyCompressed() {
        #expect(PartCompression.worthTrying(name: "dados.csv", mime: "text/csv"))
        #expect(PartCompression.worthTrying(name: "relatório.pdf", mime: "application/pdf"))
        #expect(PartCompression.worthTrying(name: "scan.bmp", mime: "image/bmp"))
        #expect(!PartCompression.worthTrying(name: "aula.mp4", mime: "video/mp4"))
        #expect(!PartCompression.worthTrying(name: "foto.jpg", mime: "image/jpeg"))
        #expect(!PartCompression.worthTrying(name: "planilha.xlsx", mime: "application/octet-stream"))
        #expect(!PartCompression.worthTrying(name: "Aulas", mime: Wire.folderMime))
    }

    /// Mesmo texto do WireTest.java.
    @Test func partZMatchesAndroidFormat() throws {
        let bytes = Wire.messageBytes(.partZ(id: 7, data: Data([1, 2, 3])))
        #expect(bytes == Data("PARZ 7\n".utf8) + Data([1, 2, 3]))
        #expect(try Wire.decodeMessage(bytes) == .partZ(id: 7, data: Data([1, 2, 3])))
    }
}
