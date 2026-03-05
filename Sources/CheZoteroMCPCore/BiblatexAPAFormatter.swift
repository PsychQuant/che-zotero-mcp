// BiblatexAPAFormatter.swift — Zotero items → biblatex-apa format (.bib)
// Conforms to: https://ctan.org/pkg/biblatex-apa
import Foundation

public struct BiblatexAPAFormatter {

    // MARK: - Public API

    /// Format a single ZoteroItem as a biblatex-apa entry.
    public static func format(_ item: ZoteroItem) -> String {
        let entryType = mapEntryType(item)
        let citeKey = generateCiteKey(item)
        var fields: [(key: String, value: String)] = []

        addCreatorFields(item, &fields)
        addTitleFields(item, entryType, &fields)
        addSourceFields(item, entryType, &fields)
        addDateFields(item, &fields)
        addIdentifierFields(item, &fields)
        addExtraFields(item, entryType, &fields)

        return buildEntry(entryType, citeKey, fields)
    }

    /// Format multiple items as a complete .bib file.
    public static func formatAll(_ items: [ZoteroItem]) -> String {
        items.map { format($0) }.joined(separator: "\n\n")
    }

    // MARK: - Entry Type Mapping

    static func mapEntryType(_ item: ZoteroItem) -> String {
        switch item.itemType {
        case "journalArticle":
            return "ARTICLE"
        case "book":
            // Check if it has editors but no authors → edited volume
            let hasAuthor = item.creatorDetails.contains { $0.creatorType == "author" }
            let hasEditor = item.creatorDetails.contains { $0.creatorType == "editor" }
            if !hasAuthor && hasEditor { return "COLLECTION" }
            return "BOOK"
        case "bookSection":
            return "INCOLLECTION"
        case "thesis":
            let thesisType = (item.allFields["thesisType"] ?? "").lowercased()
            if thesisType.contains("master") { return "MASTERSTHESIS" }
            return "PHDTHESIS"
        case "report":
            return "REPORT"
        case "webpage":
            return "ONLINE"
        case "conferencePaper":
            return "INPROCEEDINGS"
        case "presentation":
            return "UNPUBLISHED"
        case "encyclopediaArticle":
            return "INREFERENCE"
        case "newspaperArticle":
            return "ARTICLE"
        case "magazineArticle":
            return "ARTICLE"
        case "film", "videoRecording":
            return "VIDEO"
        case "audioRecording", "podcast":
            return "AUDIO"
        case "computerProgram":
            return "SOFTWARE"
        case "dataset":
            return "DATASET"
        case "preprint":
            return "ONLINE"
        case "blogPost":
            return "ONLINE"
        case "dictionaryEntry":
            return "INREFERENCE"
        default:
            return "MISC"
        }
    }

    // MARK: - Creator Fields

    static func addCreatorFields(_ item: ZoteroItem, _ fields: inout [(key: String, value: String)]) {
        let authors = item.creatorDetails.filter { $0.creatorType == "author" }
        let editors = item.creatorDetails.filter { $0.creatorType == "editor" }
        let translators = item.creatorDetails.filter { $0.creatorType == "translator" }
        let directors = item.creatorDetails.filter { $0.creatorType == "director" }
        let hosts = item.creatorDetails.filter { $0.creatorType == "host" || $0.creatorType == "podcaster" }

        // For films/videos, director is the primary creator
        if !directors.isEmpty {
            fields.append(("AUTHOR", formatBibAuthors(directors)))
            fields.append(("AUTHOR+an:role", directors.enumerated().map { "\($0.offset + 1)=director" }.joined(separator: ";")))
        } else if !hosts.isEmpty && authors.isEmpty {
            fields.append(("AUTHOR", formatBibAuthors(hosts)))
            fields.append(("AUTHOR+an:role", hosts.enumerated().map { "\($0.offset + 1)=host" }.joined(separator: ";")))
        } else if !authors.isEmpty {
            fields.append(("AUTHOR", formatBibAuthors(authors)))
        }

        if !editors.isEmpty {
            fields.append(("EDITOR", formatBibAuthors(editors)))
        }

        if !translators.isEmpty {
            fields.append(("TRANSLATOR", formatBibAuthors(translators)))
        }
    }

    static func formatBibAuthors(_ creators: [ZoteroCreator]) -> String {
        creators.map { creator in
            if creator.firstName.isEmpty {
                // Likely corporate/institutional author
                if creator.lastName.contains(" ") || creator.lastName.contains(",") {
                    return "{\(creator.lastName)}"
                }
                return creator.lastName
            }
            return "\(creator.firstName) \(creator.lastName)"
        }.joined(separator: " and ")
    }

    // MARK: - Title Fields

    static func addTitleFields(_ item: ZoteroItem, _ entryType: String, _ fields: inout [(key: String, value: String)]) {
        let (mainTitle, subtitle) = splitTitle(item.title)
        fields.append(("TITLE", protectProperNouns(mainTitle)))
        if let sub = subtitle {
            fields.append(("SUBTITLE", protectProperNouns(sub)))
        }

        // Book title for chapters
        if let bookTitle = item.allFields["bookTitle"], !bookTitle.isEmpty {
            let (bookMain, bookSub) = splitTitle(bookTitle)
            fields.append(("BOOKTITLE", protectProperNouns(bookMain)))
            if let bs = bookSub {
                fields.append(("BOOKSUBTITLE", protectProperNouns(bs)))
            }
        }

        // Encyclopedia title
        if let encTitle = item.allFields["encyclopediaTitle"], !encTitle.isEmpty {
            let (encMain, encSub) = splitTitle(encTitle)
            fields.append(("BOOKTITLE", protectProperNouns(encMain)))
            if let es = encSub {
                fields.append(("BOOKSUBTITLE", protectProperNouns(es)))
            }
        }

        // Short title
        if let shortTitle = item.allFields["shortTitle"], !shortTitle.isEmpty {
            fields.append(("SHORTTITLE", shortTitle))
        }
    }

    /// Split title at ": " into main title and subtitle.
    static func splitTitle(_ title: String) -> (String, String?) {
        // Look for ": " (colon + space) not at the very beginning
        guard title.count > 5 else { return (title, nil) }

        // Find the last ": " that makes sense as a title/subtitle split
        if let range = title.range(of: ": ",
                                    range: title.index(title.startIndex, offsetBy: 3)..<title.endIndex) {
            let main = String(title[..<range.lowerBound])
            let sub = String(title[range.upperBound...]).trimmingCharacters(in: .whitespaces)
            if !sub.isEmpty {
                return (main, sub)
            }
        }

        // Also try " — " (em-dash with spaces)
        if let range = title.range(of: " — ",
                                    range: title.index(title.startIndex, offsetBy: 3)..<title.endIndex) {
            let main = String(title[..<range.lowerBound])
            let sub = String(title[range.upperBound...]).trimmingCharacters(in: .whitespaces)
            if !sub.isEmpty {
                return (main, sub)
            }
        }

        return (title, nil)
    }

    /// Protect proper nouns and acronyms with braces for biblatex.
    static func protectProperNouns(_ text: String) -> String {
        // Protect sequences of 2+ uppercase letters (acronyms like ADHD, LGBTQ, USA)
        var result = text
        let acronymPattern = try! NSRegularExpression(pattern: "\\b([A-Z]{2,})\\b")
        let matches = acronymPattern.matches(in: result, range: NSRange(result.startIndex..., in: result))
        // Replace in reverse to preserve indices
        for match in matches.reversed() {
            if let range = Range(match.range(at: 1), in: result) {
                let acronym = String(result[range])
                result.replaceSubrange(range, with: "{\(acronym)}")
            }
        }
        return result
    }

    // MARK: - Source Fields

    static func addSourceFields(_ item: ZoteroItem, _ entryType: String, _ fields: inout [(key: String, value: String)]) {
        switch item.itemType {
        case "journalArticle", "newspaperArticle", "magazineArticle":
            if let journal = item.publicationTitle, !journal.isEmpty {
                fields.append(("JOURNALTITLE", journal))
            }
            if let abbr = item.allFields["journalAbbreviation"], !abbr.isEmpty {
                fields.append(("SHORTJOURNAL", abbr))
            }
            if let vol = item.allFields["volume"], !vol.isEmpty {
                fields.append(("VOLUME", vol))
            }
            if let issue = item.allFields["issue"], !issue.isEmpty {
                fields.append(("NUMBER", issue))
            }
            if let pages = item.allFields["pages"], !pages.isEmpty {
                fields.append(("PAGES", normalizePages(pages)))
            }

        case "book":
            if let pub = item.allFields["publisher"], !pub.isEmpty {
                fields.append(("PUBLISHER", pub))
            }
            if let edition = item.allFields["edition"], !edition.isEmpty {
                fields.append(("EDITION", edition))
            }
            if let vol = item.allFields["volume"], !vol.isEmpty {
                fields.append(("VOLUME", vol))
            }
            if let series = item.allFields["series"], !series.isEmpty {
                fields.append(("SERIES", series))
            }
            if let isbn = item.allFields["ISBN"], !isbn.isEmpty {
                fields.append(("ISBN", isbn))
            }

        case "bookSection", "encyclopediaArticle", "dictionaryEntry":
            if let pub = item.allFields["publisher"], !pub.isEmpty {
                fields.append(("PUBLISHER", pub))
            }
            if let edition = item.allFields["edition"], !edition.isEmpty {
                fields.append(("EDITION", edition))
            }
            if let vol = item.allFields["volume"], !vol.isEmpty {
                fields.append(("VOLUME", vol))
            }
            if let pages = item.allFields["pages"], !pages.isEmpty {
                fields.append(("PAGES", normalizePages(pages)))
            }

        case "thesis":
            if let uni = item.allFields["university"], !uni.isEmpty {
                fields.append(("INSTITUTION", uni))
            }
            if let thesisType = item.allFields["thesisType"], !thesisType.isEmpty {
                fields.append(("TYPE", thesisType))
            }

        case "report":
            if let inst = item.allFields["institution"], !inst.isEmpty {
                fields.append(("INSTITUTION", inst))
            }
            if let pub = item.allFields["publisher"], !pub.isEmpty && item.allFields["institution"]?.isEmpty != false {
                fields.append(("PUBLISHER", pub))
            }
            if let reportNum = item.allFields["reportNumber"], !reportNum.isEmpty {
                fields.append(("NUMBER", reportNum))
            }
            if let reportType = item.allFields["reportType"], !reportType.isEmpty {
                fields.append(("TITLEADDON", reportType))
            }
            if let series = item.allFields["seriesTitle"], !series.isEmpty {
                fields.append(("SERIES", series))
            }
            if let pages = item.allFields["pages"], !pages.isEmpty {
                fields.append(("PAGES", normalizePages(pages)))
            }

        case "conferencePaper":
            if let proc = item.allFields["proceedingsTitle"] ?? item.allFields["conferenceName"], !proc.isEmpty {
                fields.append(("BOOKTITLE", proc))
            }
            if let pub = item.allFields["publisher"], !pub.isEmpty {
                fields.append(("PUBLISHER", pub))
            }
            if let pages = item.allFields["pages"], !pages.isEmpty {
                fields.append(("PAGES", normalizePages(pages)))
            }
            if let place = item.allFields["place"], !place.isEmpty {
                fields.append(("LOCATION", place))
            }

        case "webpage", "blogPost":
            if let site = item.allFields["websiteTitle"], !site.isEmpty {
                fields.append(("EPRINT", site))
            }

        case "presentation":
            if let meeting = item.allFields["meetingName"], !meeting.isEmpty {
                fields.append(("EVENTTITLE", meeting))
            }
            if let place = item.allFields["place"], !place.isEmpty {
                fields.append(("VENUE", place))
            }
            if let presType = item.allFields["presentationType"], !presType.isEmpty {
                fields.append(("TITLEADDON", presType))
            }

        default:
            // Generic: publisher, place, pages if present
            if let pub = item.allFields["publisher"], !pub.isEmpty {
                fields.append(("PUBLISHER", pub))
            }
            if let pages = item.allFields["pages"], !pages.isEmpty {
                fields.append(("PAGES", normalizePages(pages)))
            }
        }
    }

    // MARK: - Date Fields

    static func addDateFields(_ item: ZoteroItem, _ fields: inout [(key: String, value: String)]) {
        if let date = item.date, !date.isEmpty {
            fields.append(("DATE", normalizeDate(date)))
        }
        if let origDate = item.allFields["originalDate"], !origDate.isEmpty {
            fields.append(("ORIGDATE", normalizeDate(origDate)))
        }
        if let accessDate = item.allFields["accessDate"], !accessDate.isEmpty {
            // Only include for online sources where it matters
            if item.itemType == "webpage" || item.itemType == "blogPost" {
                let normalized = normalizeDate(accessDate)
                if !normalized.isEmpty {
                    fields.append(("URLDATE", normalized))
                }
            }
        }
    }

    /// Normalize Zotero's date format to ISO for biblatex.
    /// Zotero stores: "2019-02-00 2/2019", "2019", "2019-03-15", "2019-02-00 February 2019"
    static func normalizeDate(_ dateStr: String) -> String {
        let trimmed = dateStr.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return "" }

        // Take the first space-separated token (the ISO part)
        let isoCandidate = trimmed.components(separatedBy: " ").first ?? trimmed

        // Check if it looks like an ISO date
        if isoCandidate.contains("-") || (isoCandidate.count == 4 && Int(isoCandidate) != nil) {
            // Remove trailing -00 (Zotero's "unknown" marker)
            var result = isoCandidate
            while result.hasSuffix("-00") {
                result = String(result.dropLast(3))
            }
            return result
        }

        // Fallback: try to extract a year
        let yearPattern = try! NSRegularExpression(pattern: "(\\d{4})")
        if let match = yearPattern.firstMatch(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed)),
           let range = Range(match.range(at: 1), in: trimmed) {
            return String(trimmed[range])
        }

        return trimmed
    }

    // MARK: - Identifier Fields

    static func addIdentifierFields(_ item: ZoteroItem, _ fields: inout [(key: String, value: String)]) {
        if let doi = item.DOI, !doi.isEmpty {
            fields.append(("DOI", doi))
        }
        // URL only if no DOI (APA 7 preference)
        if let url = item.url, !url.isEmpty, (item.DOI ?? "").isEmpty {
            fields.append(("URL", url))
        }
        // Always include URL for online-primary types even with DOI
        if let url = item.url, !url.isEmpty,
           ["webpage", "blogPost", "presentation"].contains(item.itemType) {
            if !fields.contains(where: { $0.key == "URL" }) {
                fields.append(("URL", url))
            }
        }
        if let issn = item.allFields["ISSN"], !issn.isEmpty {
            fields.append(("ISSN", issn))
        }
    }

    // MARK: - Extra Fields

    static func addExtraFields(_ item: ZoteroItem, _ entryType: String, _ fields: inout [(key: String, value: String)]) {
        if let lang = item.allFields["language"], !lang.isEmpty {
            fields.append(("LANGID", mapLanguageToLangID(lang)))
        }

        // Parse Zotero's extra field for additional biblatex data
        if let extra = item.allFields["extra"], !extra.isEmpty {
            let extraFields = parseExtraField(extra)
            if let pmid = extraFields["PMID"] {
                fields.append(("NOTE", "PMID: \(pmid)"))
            }
        }

        // Number of volumes for books
        if let numVol = item.allFields["numberOfVolumes"], !numVol.isEmpty {
            fields.append(("VOLUMES", numVol))
        }
    }

    /// Map language name to biblatex LANGID.
    static func mapLanguageToLangID(_ lang: String) -> String {
        let lower = lang.lowercased()
        if lower.hasPrefix("en") { return "english" }
        if lower.hasPrefix("zh") || lower.contains("chinese") { return "chinese" }
        if lower.hasPrefix("ja") || lower.contains("japanese") { return "japanese" }
        if lower.hasPrefix("ko") || lower.contains("korean") { return "korean" }
        if lower.hasPrefix("fr") || lower.contains("french") { return "french" }
        if lower.hasPrefix("de") || lower.contains("german") { return "german" }
        if lower.hasPrefix("es") || lower.contains("spanish") { return "spanish" }
        if lower.hasPrefix("pt") || lower.contains("portuguese") { return "portuguese" }
        if lower.hasPrefix("it") || lower.contains("italian") { return "italian" }
        return lower
    }

    /// Parse Zotero's extra field (key: value pairs, one per line).
    static func parseExtraField(_ extra: String) -> [String: String] {
        var result: [String: String] = [:]
        for line in extra.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if let colonRange = trimmed.range(of: ": ") {
                let key = String(trimmed[..<colonRange.lowerBound]).trimmingCharacters(in: .whitespaces)
                let value = String(trimmed[colonRange.upperBound...]).trimmingCharacters(in: .whitespaces)
                result[key] = value
            }
        }
        return result
    }

    // MARK: - Utility

    /// Convert page ranges: single hyphen → double hyphen (biblatex en-dash).
    static func normalizePages(_ pages: String) -> String {
        var result = pages
        // Normalize all dash types to single hyphen first
        result = result.replacingOccurrences(of: "–", with: "-")  // en-dash
        result = result.replacingOccurrences(of: "—", with: "-")  // em-dash
        result = result.replacingOccurrences(of: "--", with: "-")  // already doubled
        // Then convert to biblatex double-hyphen
        result = result.replacingOccurrences(of: "-", with: "--")
        return result
    }

    /// Generate a citation key from author + year.
    static func generateCiteKey(_ item: ZoteroItem) -> String {
        // Check for existing citation key
        if let ck = item.allFields["citationKey"], !ck.isEmpty {
            return ck
        }

        // Parse extra field for "Citation Key: xxx"
        if let extra = item.allFields["extra"], !extra.isEmpty {
            let extraFields = parseExtraField(extra)
            if let ck = extraFields["Citation Key"], !ck.isEmpty { return ck }
        }

        // Generate: firstAuthorLastName + year
        let lastName: String
        if let firstCreator = item.creatorDetails.first {
            lastName = firstCreator.lastName
                .components(separatedBy: " ").last ?? firstCreator.lastName
        } else {
            lastName = "unknown"
        }

        let year = normalizeDate(item.date ?? "").prefix(4)
        let cleanName = lastName.lowercased()
            .replacingOccurrences(of: " ", with: "")
            .filter { $0.isLetter }

        return "\(cleanName)\(year)"
    }

    /// Build a formatted biblatex entry string.
    static func buildEntry(_ entryType: String, _ citeKey: String, _ fields: [(key: String, value: String)]) -> String {
        var lines: [String] = []
        lines.append("@\(entryType){\(citeKey),")
        for (i, field) in fields.enumerated() {
            let comma = i < fields.count - 1 ? "," : ""
            let padding = String(repeating: " ", count: max(1, 17 - field.key.count))
            lines.append("  \(field.key)\(padding)= {\(field.value)}\(comma)")
        }
        lines.append("}")
        return lines.joined(separator: "\n")
    }
}
