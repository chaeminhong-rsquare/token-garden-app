import Testing
@testable import TokenGarden

@Test func formatSmallNumbers() {
    #expect(TokenFormatter.format(0) == "0")
    #expect(TokenFormatter.format(999) == "999")
}

@Test func formatThousands() {
    #expect(TokenFormatter.format(1000) == "1K")
    #expect(TokenFormatter.format(1500) == "1.5K")
    #expect(TokenFormatter.format(23400) == "23.4K")
    #expect(TokenFormatter.format(142000) == "142K")
}

@Test func formatMillions() {
    #expect(TokenFormatter.format(1_000_000) == "1M")
    #expect(TokenFormatter.format(1_200_000) == "1.2M")
}
