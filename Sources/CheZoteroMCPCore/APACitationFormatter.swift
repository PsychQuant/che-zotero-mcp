// APACitationFormatter.swift — Zotero items → APA 7th Edition formatted text
// Reference: APA Publication Manual 7th Edition, Chapters 8-11
import Foundation
import BiblatexAPA

public struct APACitationFormatter {

    // MARK: - Public API

    /// Format a single item as an APA 7 reference list entry.
    public static func formatReference(_ item: ZoteroItem) -> String {
        let authors = formatAuthors(item.creatorDetails, itemType: item.itemType)
        let date = formatDate(item.date)
        let body = formatBody(item)
        let source = formatSource(item)

        var parts: [String] = []
        if !authors.isEmpty { parts.append(authors) }
        parts.append("(\(date)).")
        if !body.isEmpty { parts.append(body) }
        if !source.isEmpty { parts.append(source) }

        var result = parts.joined(separator: " ")
        // Ensure ends with period (unless ends with URL/DOI)
        if !result.hasSuffix(".") && !result.contains("https://") {
            result += "."
        }
        return result
    }

    /// Format a single item as an APA 7 in-text citation.
    /// Returns parenthetical form: (Author, Year)
    public static func formatCitation(_ item: ZoteroItem) -> String {
        let authors = formatCitationAuthors(item.creatorDetails, itemType: item.itemType)
        let year = extractYear(item.date)
        return "(\(authors), \(year))"
    }

    /// Format a single item as an APA 7 narrative citation.
    /// Returns: Author (Year)
    public static func formatNarrativeCitation(_ item: ZoteroItem) -> String {
        let authors = formatCitationAuthors(item.creatorDetails, itemType: item.itemType)
        let year = extractYear(item.date)
        return "\(authors) (\(year))"
    }

    /// Format multiple items as a reference list (sorted alphabetically).
    public static func formatReferenceList(_ items: [ZoteroItem]) -> String {
        let formatted = items.map { (item: $0, ref: formatReference($0)) }
        let sorted = formatted.sorted { $0.ref.lowercased() < $1.ref.lowercased() }
        return sorted.map(\.ref).joined(separator: "\n\n")
    }

    // MARK: - Author Formatting (Reference List)

    /// APA 7 author format for reference list:
    /// 1 author: Last, F. M.
    /// 2 authors: Last, F. M., & Last, F. M.
    /// 3-20 authors: Last, F. M., Last, F. M., ... & Last, F. M.
    /// 21+ authors: First 19, ... Last
    static func formatAuthors(_ creators: [ZoteroCreator], itemType: String) -> String {
        // Determine primary creator type
        let primaryType: String
        switch itemType {
        case "film", "videoRecording": primaryType = "director"
        default: primaryType = "author"
        }

        var primary = creators.filter { $0.creatorType == primaryType }
        // Fallback: if no primary, try editors for edited volumes
        if primary.isEmpty {
            primary = creators.filter { $0.creatorType == "editor" }
            if !primary.isEmpty {
                let names = formatAuthorNames(primary)
                let edLabel = primary.count == 1 ? "Ed." : "Eds."
                return "\(names) (\(edLabel))."
            }
        }
        if primary.isEmpty { return "" }

        return formatAuthorNames(primary) + "."
    }

    static func formatAuthorNames(_ creators: [ZoteroCreator]) -> String {
        let names = creators.map { formatSingleAuthor($0) }
        let count = names.count

        switch count {
        case 0: return ""
        case 1: return names[0]
        case 2: return "\(names[0]), & \(names[1])"
        case 3...20:
            let allButLast = names.dropLast().joined(separator: ", ")
            return "\(allButLast), & \(names.last!)"
        default:
            // 21+: first 19, ..., last
            let first19 = names.prefix(19).joined(separator: ", ")
            return "\(first19), . . . \(names.last!)"
        }
    }

    /// Format a single author: Last, F. M.
    static func formatSingleAuthor(_ creator: ZoteroCreator) -> String {
        if creator.firstName.isEmpty {
            // Corporate/institutional author
            return creator.lastName
        }
        let initials = formatInitials(creator.firstName)
        return "\(creator.lastName), \(initials)"
    }

    /// Convert first name to initials: "Sarah Michelle" → "S. M."
    static func formatInitials(_ firstName: String) -> String {
        let parts = firstName.components(separatedBy: " ")
            .filter { !$0.isEmpty }

        return parts.map { part in
            // If already an initial (e.g., "S." or "S"), just ensure period
            if part.count <= 2 && part.first?.isUppercase == true {
                return part.hasSuffix(".") ? part : "\(part)."
            }
            // If it's a hyphenated name like "Jean-Pierre"
            if part.contains("-") {
                let sub = part.components(separatedBy: "-")
                return sub.map { s in
                    guard let first = s.first else { return "" }
                    return "\(first.uppercased())."
                }.joined(separator: "-")
            }
            // Normal name
            guard let first = part.first else { return "" }
            return "\(first.uppercased())."
        }.joined(separator: " ")
    }

    // MARK: - Author Formatting (In-Text Citation)

    /// APA 7 citation author format:
    /// 1 author: Last
    /// 2 authors: Last & Last
    /// 3+ authors: Last et al.
    static func formatCitationAuthors(_ creators: [ZoteroCreator], itemType: String) -> String {
        let primaryType = itemType == "film" || itemType == "videoRecording" ? "director" : "author"
        var primary = creators.filter { $0.creatorType == primaryType }
        if primary.isEmpty {
            primary = creators.filter { $0.creatorType == "editor" }
        }
        if primary.isEmpty { return "Unknown" }

        switch primary.count {
        case 1:
            return primary[0].firstName.isEmpty ? primary[0].lastName : primary[0].lastName
        case 2:
            return "\(primary[0].lastName) & \(primary[1].lastName)"
        default:
            return "\(primary[0].lastName) et al."
        }
    }

    // MARK: - Date Formatting

    /// Format date for reference list: (2019) or (2019, March) or (2019, March 15)
    static func formatDate(_ date: String?) -> String {
        guard let date = date, !date.isEmpty else { return "n.d." }

        let normalized = APAUtilities.normalizeDate(date)
        let parts = normalized.components(separatedBy: "-")

        guard let year = parts.first, !year.isEmpty else { return "n.d." }

        if parts.count >= 3, let month = Int(parts[1]), month > 0, let day = Int(parts[2]), day > 0 {
            let monthName = Self.monthNames[month - 1]
            return "\(year), \(monthName) \(day)"
        }
        if parts.count >= 2, let month = Int(parts[1]), month > 0 {
            let monthName = Self.monthNames[month - 1]
            return "\(year), \(monthName)"
        }
        return year
    }

    static func extractYear(_ date: String?) -> String {
        guard let date = date, !date.isEmpty else { return "n.d." }
        let normalized = APAUtilities.normalizeDate(date)
        return String(normalized.prefix(4))
    }

    private static let monthNames = [
        "January", "February", "March", "April", "May", "June",
        "July", "August", "September", "October", "November", "December"
    ]

    // MARK: - Body (Title) Formatting

    static func formatBody(_ item: ZoteroItem) -> String {
        switch item.itemType {
        case "journalArticle", "newspaperArticle", "magazineArticle":
            // Article title in sentence case, no italics
            return toSentenceCase(item.title) + "."

        case "book":
            // Book title in sentence case, italics (markdown)
            let edition = formatEdition(item.allFields["edition"])
            let vol = item.allFields["volume"]
            var parenthetical: [String] = []
            if let ed = edition { parenthetical.append(ed) }
            if let v = vol, !v.isEmpty { parenthetical.append("Vol. \(v)") }
            let paren = parenthetical.isEmpty ? "" : " (\(parenthetical.joined(separator: ", ")))"
            return "*\(toSentenceCase(item.title))*\(paren)."

        case "bookSection", "encyclopediaArticle", "dictionaryEntry":
            // Chapter title (no italics), then "In Editor (Ed.), Book title"
            let chapterTitle = toSentenceCase(item.title) + "."
            let editors = item.creatorDetails.filter { $0.creatorType == "editor" }
            let bookTitle = item.allFields["bookTitle"] ?? item.allFields["encyclopediaTitle"] ?? ""
            let edition = formatEdition(item.allFields["edition"])
            let vol = item.allFields["volume"]
            let pages = item.allFields["pages"]

            var inPart = "In "
            if !editors.isEmpty {
                let edNames = editors.map { formatEditorForIn($0) }.joined(separator: ", ")
                let edLabel = editors.count == 1 ? "Ed." : "Eds."
                inPart += "\(edNames) (\(edLabel)), "
            }
            inPart += "*\(toSentenceCase(bookTitle))*"

            var parenthetical: [String] = []
            if let ed = edition { parenthetical.append(ed) }
            if let v = vol, !v.isEmpty { parenthetical.append("Vol. \(v)") }
            if let p = pages, !p.isEmpty { parenthetical.append("pp. \(normalizeAPAPages(p))") }
            if !parenthetical.isEmpty {
                inPart += " (\(parenthetical.joined(separator: ", ")))"
            }
            inPart += "."

            return "\(chapterTitle) \(inPart)"

        case "thesis":
            let thesisType = item.allFields["thesisType"] ?? "Doctoral dissertation"
            let university = item.allFields["university"] ?? ""
            return "*\(toSentenceCase(item.title))* [\(thesisType), \(university)]."

        case "report":
            let reportNum = item.allFields["reportNumber"]
            let reportType = item.allFields["reportType"]
            var titlePart = "*\(toSentenceCase(item.title))*"
            var parenthetical: [String] = []
            if let rt = reportType, !rt.isEmpty { parenthetical.append(rt) }
            if let rn = reportNum, !rn.isEmpty { parenthetical.append("No. \(rn)") }
            if !parenthetical.isEmpty {
                titlePart += " (\(parenthetical.joined(separator: " ")))"
            }
            return titlePart + "."

        case "webpage", "blogPost":
            // Webpage title in italics
            return "*\(toSentenceCase(item.title))*."

        case "presentation":
            let presType = item.allFields["presentationType"] ?? "Conference presentation"
            return "*\(toSentenceCase(item.title))* [\(presType)]."

        case "conferencePaper":
            return toSentenceCase(item.title) + "."

        case "film", "videoRecording":
            return "*\(toSentenceCase(item.title))* [Film]."

        case "audioRecording", "podcast":
            return "*\(toSentenceCase(item.title))* [Podcast]."

        default:
            return toSentenceCase(item.title) + "."
        }
    }

    /// Format editor name for "In" clause: F. M. Last
    static func formatEditorForIn(_ creator: ZoteroCreator) -> String {
        if creator.firstName.isEmpty {
            return creator.lastName
        }
        let initials = formatInitials(creator.firstName)
        return "\(initials) \(creator.lastName)"
    }

    // MARK: - Source Formatting

    static func formatSource(_ item: ZoteroItem) -> String {
        var parts: [String] = []

        switch item.itemType {
        case "journalArticle":
            if let journal = item.publicationTitle, !journal.isEmpty {
                var journalPart = "*\(journal)*"
                if let vol = item.allFields["volume"], !vol.isEmpty {
                    journalPart += ", *\(vol)*"
                    if let issue = item.allFields["issue"], !issue.isEmpty {
                        journalPart += "(\(issue))"
                    }
                }
                if let pages = item.allFields["pages"], !pages.isEmpty {
                    journalPart += ", \(normalizeAPAPages(pages))"
                }
                journalPart += "."
                parts.append(journalPart)
            }

        case "newspaperArticle", "magazineArticle":
            if let pub = item.publicationTitle, !pub.isEmpty {
                var pubPart = "*\(pub)*"
                if let pages = item.allFields["pages"], !pages.isEmpty {
                    pubPart += ", \(normalizeAPAPages(pages))"
                }
                pubPart += "."
                parts.append(pubPart)
            }

        case "book":
            if let pub = item.allFields["publisher"], !pub.isEmpty {
                parts.append("\(pub).")
            }

        case "bookSection", "encyclopediaArticle", "dictionaryEntry":
            if let pub = item.allFields["publisher"], !pub.isEmpty {
                parts.append("\(pub).")
            }

        case "report":
            if let inst = item.allFields["institution"], !inst.isEmpty {
                parts.append("\(inst).")
            } else if let pub = item.allFields["publisher"], !pub.isEmpty {
                parts.append("\(pub).")
            }

        case "webpage", "blogPost":
            if let site = item.allFields["websiteTitle"], !site.isEmpty {
                parts.append("\(site).")
            }

        case "presentation":
            if let meeting = item.allFields["meetingName"], !meeting.isEmpty {
                var meetingPart = meeting
                if let place = item.allFields["place"], !place.isEmpty {
                    meetingPart += ", \(place)"
                }
                meetingPart += "."
                parts.append(meetingPart)
            }

        case "conferencePaper":
            if let conf = item.allFields["conferenceName"] ?? item.allFields["proceedingsTitle"], !conf.isEmpty {
                parts.append("\(conf).")
            }

        default:
            if let pub = item.allFields["publisher"], !pub.isEmpty {
                parts.append("\(pub).")
            }
        }

        // DOI or URL
        if let doi = item.DOI, !doi.isEmpty {
            let doiURL = doi.hasPrefix("http") ? doi : "https://doi.org/\(doi)"
            parts.append(doiURL)
        } else if let url = item.url, !url.isEmpty {
            parts.append(url)
        }

        return parts.joined(separator: " ")
    }

    // MARK: - Utility

    /// Convert to APA sentence case: capitalize first word, first word after colon, and proper nouns.
    /// This is a best-effort heuristic — proper nouns are hard to detect automatically.
    static func toSentenceCase(_ title: String) -> String {
        // If title is already mostly lowercase, it's likely already sentence case
        // If it's Title Case or ALL CAPS, convert
        let words = title.components(separatedBy: " ")
        guard !words.isEmpty else { return title }

        var result: [String] = []
        var afterColon = false

        for (i, word) in words.enumerated() {
            if word.isEmpty { result.append(word); continue }

            // Keep acronyms (2+ uppercase letters) as-is
            if word.count >= 2 && word == word.uppercased() && word.rangeOfCharacter(from: .lowercaseLetters) == nil {
                result.append(word)
                afterColon = false
                continue
            }

            // First word or first word after colon: capitalize
            if i == 0 || afterColon {
                result.append(capitalizeFirst(word))
                afterColon = false
                continue
            }

            // Check if word ends with colon
            if word.hasSuffix(":") || word.hasSuffix(":") {
                result.append(word.lowercased())
                afterColon = true
                continue
            }

            // Keep proper nouns (words starting with uppercase in original)
            // Heuristic: if the word starts uppercase and isn't the first word, keep it
            // This preserves proper nouns but may over-preserve in Title Case titles
            if let first = word.first, first.isUppercase {
                // If the original title appears to be Title Case (most words capitalized),
                // lowercase non-proper nouns
                let capitalizedCount = words.filter { $0.first?.isUppercase == true }.count
                let isLikelyTitleCase = Double(capitalizedCount) / Double(words.count) > 0.6

                if isLikelyTitleCase {
                    result.append(word.lowercased())
                } else {
                    result.append(word) // Keep as-is (likely proper noun)
                }
            } else {
                result.append(word)
            }

            afterColon = false
        }

        return result.joined(separator: " ")
    }

    static func capitalizeFirst(_ word: String) -> String {
        guard let first = word.first else { return word }
        return first.uppercased() + word.dropFirst()
    }

    /// Format edition number: "2" → "2nd ed.", "3" → "3rd ed."
    static func formatEdition(_ edition: String?) -> String? {
        guard let ed = edition, !ed.isEmpty else { return nil }
        // If already formatted (e.g., "2nd ed."), return as-is
        if ed.contains("ed") { return ed }
        guard let num = Int(ed), num > 1 else { return nil }
        let suffix: String
        switch num {
        case 2: suffix = "nd"
        case 3: suffix = "rd"
        default: suffix = "th"
        }
        return "\(num)\(suffix) ed."
    }

    /// Normalize pages for APA: use en-dash (–) between page numbers.
    static func normalizeAPAPages(_ pages: String) -> String {
        var result = pages
        result = result.replacingOccurrences(of: "--", with: "–")  // biblatex double-hyphen
        result = result.replacingOccurrences(of: "—", with: "–")   // em-dash
        // Convert remaining single hyphens between numbers to en-dash
        let pattern = try! NSRegularExpression(pattern: "(\\d)-(\\d)")
        result = pattern.stringByReplacingMatches(in: result,
                                                   range: NSRange(result.startIndex..., in: result),
                                                   withTemplate: "$1–$2")
        return result
    }
}
