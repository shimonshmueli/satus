import Foundation

extension String {
    /// Checks if the search text is a fuzzy match for the current string.
    /// A fuzzy match means all characters in the search text appear in the current string in the same relative order, case-insensitive.
    func isFuzzyMatch(with searchText: String) -> Bool {
        let text = self.lowercased()
        let search = searchText.lowercased()
        
        guard !search.isEmpty else { return true }
        guard search.count <= text.count else { return false }
        
        var searchIndex = search.startIndex
        for char in text {
            if char == search[searchIndex] {
                searchIndex = search.index(after: searchIndex)
                if searchIndex == search.endIndex {
                    return true
                }
            }
        }
        return false
    }
    
    /// Provides a rudimentary score for how well the search text matches the current string.
    /// Higher score is better.
    /// - Returns: 100 for exact match, 75 for prefix match, 50 for substring match, 10 for loose fuzzy match, 0 for no match.
    func fuzzyMatchScore(with searchText: String) -> Int {
        let text = self.lowercased()
        let search = searchText.lowercased()
        
        if text == search { return 100 }
        if text.hasPrefix(search) { return 75 }
        if text.contains(search) { return 50 }
        if isFuzzyMatch(with: searchText) { return 10 }
        return 0
    }
}
