import Foundation
import Testing
@testable import KukitCore

@Suite("CSV")
struct CSVTests {
    @Test func plainFieldsAreLeftAlone() {
        #expect(CSV.escape("Calculus II") == "Calculus II")
        #expect(CSV.escape("") == "")
        #expect(CSV.escape("미적분학") == "미적분학")
    }

    @Test func specialCharactersAreQuoted() {
        #expect(CSV.escape("a,b") == "\"a,b\"")
        #expect(CSV.escape("say \"hi\"") == "\"say \"\"hi\"\"\"")
        #expect(CSV.escape("two\nlines") == "\"two\nlines\"")
        #expect(CSV.escape("cr\rlf") == "\"cr\rlf\"")
    }

    @Test func rowsAndDocuments() {
        #expect(CSV.row(["a", "b,c", ""]) == "a,\"b,c\",")
        let doc = CSV.document(header: ["Course", "Minutes"], rows: [["Math", "25"], ["Art, history", "50"]])
        #expect(doc == "\u{FEFF}Course,Minutes\r\nMath,25\r\n\"Art, history\",50\r\n")
        #expect(CSV.document(header: ["x"], rows: []) == "\u{FEFF}x\r\n")
    }
}
