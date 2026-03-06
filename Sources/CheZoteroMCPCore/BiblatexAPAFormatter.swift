// BiblatexAPAFormatter.swift — Zotero items → biblatex-apa format (.bib)
// Conforms to: https://ctan.org/pkg/biblatex-apa
import Foundation
import BiblatexAPA

public struct BiblatexAPAFormatter {

    // MARK: - Public API

    public static func format(_ item: ZoteroItem) -> String {
        let entryType = mapEntryType(item)
        let citeKey = generateCiteKey(item)
        var fields: [(key: String, value: String)] = []

        addCreatorFields(item, entryType, &fields)
        addTitleFields(item, entryType, &fields)
        addSourceFields(item, entryType, &fields)
        addDateFields(item, entryType, &fields)
        addIdentifierFields(item, entryType, &fields)
        addMetadataFields(item, entryType, &fields)

        // Build BibEntry and serialize via shared module
        var orderedFields = OrderedDict()
        for (key, value) in fields {
            orderedFields[key] = value
        }
        let entry = BibEntry(
            entryType: entryType,
            key: citeKey,
            fields: orderedFields,
            rawText: "",
            lineNumber: 0
        )
        return BibWriter.serialize(entry)
    }

    public static func formatAll(_ items: [ZoteroItem]) -> String {
        items.map { format($0) }.joined(separator: "\n\n")
    }

    // MARK: - Entry Type Mapping

    static func mapEntryType(_ item: ZoteroItem) -> String {
        switch item.itemType {
        case "journalArticle":
            return "ARTICLE"
        case "book":
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
        case "newspaperArticle", "magazineArticle":
            // C3: Online-only (no vol/issue/pages) → @ONLINE; print → @ARTICLE
            let hasVol = !(item.allFields["volume"] ?? "").isEmpty
            let hasIssue = !(item.allFields["issue"] ?? "").isEmpty
            let hasPages = !(item.allFields["pages"] ?? "").isEmpty
            if !hasVol && !hasIssue && !hasPages {
                return "ONLINE"
            }
            return "ARTICLE"
        case "film", "videoRecording":
            return "VIDEO"
        case "audioRecording":
            return "AUDIO"
        case "podcast":
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

    static func addCreatorFields(_ item: ZoteroItem, _ entryType: String, _ fields: inout [(key: String, value: String)]) {
        let authors = item.creatorDetails.filter { $0.creatorType == "author" }
        let editors = item.creatorDetails.filter { $0.creatorType == "editor" }
        let translators = item.creatorDetails.filter { $0.creatorType == "translator" }
        let directors = item.creatorDetails.filter { $0.creatorType == "director" }
        let hosts = item.creatorDetails.filter { $0.creatorType == "host" || $0.creatorType == "podcaster" }

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

        // Parse extra field for creator-related metadata
        if let extra = item.allFields["extra"], !extra.isEmpty {
            let parsed = APAUtilities.parseExtraField(extra)

            // H6: AUTHOR+an:username (social media handles)
            if let username = parsed["Username"] ?? parsed["username"] {
                let handle = username.hasPrefix("@") ? username : "@\(username)"
                fields.append(("AUTHOR+an:username", "1=\"\(handle)\""))
            }

            // M4: SHORTAUTHOR (corporate abbreviations like APA, WHO)
            if let shortAuthor = parsed["Short Author"] ?? parsed["shortAuthor"] ?? parsed["SHORTAUTHOR"] {
                fields.append(("SHORTAUTHOR", "{{\(shortAuthor)}}"))
            }
        }
    }

    /// Format authors for biblatex.
    /// C1: Compound surnames (multi-word) → brace-protected.
    /// C2: Corporate/institutional authors → double braces {{}}.
    static func formatBibAuthors(_ creators: [ZoteroCreator]) -> String {
        creators.map { creator in
            if creator.firstName.isEmpty {
                // C2: Corporate/institutional author → double braces
                return "{{\(creator.lastName)}}"
            }
            // C1: Multi-word last names → brace-protect to prevent biber mis-parsing
            if creator.lastName.contains(" ") {
                return "\(creator.firstName) {\(creator.lastName)}"
            }
            return "\(creator.firstName) \(creator.lastName)"
        }.joined(separator: " and ")
    }

    // MARK: - Title Fields

    static func addTitleFields(_ item: ZoteroItem, _ entryType: String, _ fields: inout [(key: String, value: String)]) {
        let (mainTitle, subtitle) = APAUtilities.splitTitle(item.title)
        fields.append(("TITLE", APAUtilities.protectProperNouns(mainTitle)))
        if let sub = subtitle {
            fields.append(("SUBTITLE", APAUtilities.protectProperNouns(sub)))
        }

        if let bookTitle = item.allFields["bookTitle"], !bookTitle.isEmpty {
            let (bookMain, bookSub) = APAUtilities.splitTitle(bookTitle)
            fields.append(("BOOKTITLE", APAUtilities.protectProperNouns(bookMain)))
            if let bs = bookSub {
                fields.append(("BOOKSUBTITLE", APAUtilities.protectProperNouns(bs)))
            }
        }

        if let encTitle = item.allFields["encyclopediaTitle"], !encTitle.isEmpty {
            let (encMain, encSub) = APAUtilities.splitTitle(encTitle)
            fields.append(("BOOKTITLE", APAUtilities.protectProperNouns(encMain)))
            if let es = encSub {
                fields.append(("BOOKSUBTITLE", APAUtilities.protectProperNouns(es)))
            }
        }

        if let shortTitle = item.allFields["shortTitle"], !shortTitle.isEmpty {
            fields.append(("SHORTTITLE", shortTitle))
        }
    }

    // MARK: - Source Fields

    static func addSourceFields(_ item: ZoteroItem, _ entryType: String, _ fields: inout [(key: String, value: String)]) {
        switch item.itemType {
        case "journalArticle":
            // H2: Apply protectProperNouns to journal title for acronym protection
            if let journal = item.publicationTitle, !journal.isEmpty {
                fields.append(("JOURNALTITLE", APAUtilities.protectProperNouns(journal)))
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
                fields.append(("PAGES", APAUtilities.normalizePages(pages)))
            }

        case "newspaperArticle", "magazineArticle":
            if entryType == "ONLINE" {
                // C3: Online-only → EPRINT for container/site name
                if let pub = item.publicationTitle, !pub.isEmpty {
                    fields.append(("EPRINT", pub))
                }
            } else {
                if let journal = item.publicationTitle, !journal.isEmpty {
                    fields.append(("JOURNALTITLE", APAUtilities.protectProperNouns(journal)))
                }
                if let vol = item.allFields["volume"], !vol.isEmpty {
                    fields.append(("VOLUME", vol))
                }
                if let issue = item.allFields["issue"], !issue.isEmpty {
                    fields.append(("NUMBER", issue))
                }
                if let pages = item.allFields["pages"], !pages.isEmpty {
                    fields.append(("PAGES", APAUtilities.normalizePages(pages)))
                }
            }

        case "book":
            if let pub = item.allFields["publisher"], !pub.isEmpty {
                // H7: If publisher matches corporate author → use "Author"
                let corpAuthor = item.creatorDetails.first(where: { $0.firstName.isEmpty })?.lastName ?? ""
                if !corpAuthor.isEmpty && pub.lowercased() == corpAuthor.lowercased() {
                    fields.append(("PUBLISHER", "Author"))
                } else {
                    fields.append(("PUBLISHER", pub))
                }
            }
            if let edition = item.allFields["edition"], !edition.isEmpty {
                fields.append(("EDITION", APAUtilities.normalizeEdition(edition)))
            }
            if let vol = item.allFields["volume"], !vol.isEmpty {
                fields.append(("VOLUME", vol))
            }
            if let series = item.allFields["series"], !series.isEmpty {
                fields.append(("SERIES", series))
            }

        case "bookSection", "encyclopediaArticle", "dictionaryEntry":
            if let pub = item.allFields["publisher"], !pub.isEmpty {
                fields.append(("PUBLISHER", pub))
            }
            if let edition = item.allFields["edition"], !edition.isEmpty {
                fields.append(("EDITION", APAUtilities.normalizeEdition(edition)))
            }
            if let vol = item.allFields["volume"], !vol.isEmpty {
                fields.append(("VOLUME", vol))
            }
            if let pages = item.allFields["pages"], !pages.isEmpty {
                fields.append(("PAGES", APAUtilities.normalizePages(pages)))
            }

        case "thesis":
            if let uni = item.allFields["university"], !uni.isEmpty {
                fields.append(("INSTITUTION", uni))
            }
            if let thesisType = item.allFields["thesisType"], !thesisType.isEmpty {
                fields.append(("TYPE", thesisType))
            }

        case "report":
            // H7: Institution/Publisher with "Author" convention for self-publishing orgs
            let corpAuthor = item.creatorDetails.first(where: { $0.firstName.isEmpty })?.lastName ?? ""
            if let inst = item.allFields["institution"], !inst.isEmpty {
                if !corpAuthor.isEmpty && inst.lowercased() == corpAuthor.lowercased() {
                    fields.append(("INSTITUTION", "Author"))
                } else {
                    fields.append(("INSTITUTION", inst))
                }
            } else if let pub = item.allFields["publisher"], !pub.isEmpty {
                if !corpAuthor.isEmpty && pub.lowercased() == corpAuthor.lowercased() {
                    fields.append(("PUBLISHER", "Author"))
                } else {
                    fields.append(("PUBLISHER", pub))
                }
            }
            if let reportNum = item.allFields["reportNumber"], !reportNum.isEmpty {
                fields.append(("NUMBER", reportNum))
            }
            if let reportType = item.allFields["reportType"], !reportType.isEmpty {
                fields.append(("TITLEADDON", reportType))
            }
            if let series = item.allFields["seriesTitle"] ?? item.allFields["series"], !series.isEmpty {
                fields.append(("SERIES", series))
            }
            if let pages = item.allFields["pages"], !pages.isEmpty {
                fields.append(("PAGES", APAUtilities.normalizePages(pages)))
            }
            // M2: LOCATION for reports (international/government docs)
            if let place = item.allFields["place"], !place.isEmpty {
                fields.append(("LOCATION", place))
            }

        case "conferencePaper":
            if let proc = item.allFields["proceedingsTitle"] ?? item.allFields["conferenceName"], !proc.isEmpty {
                fields.append(("BOOKTITLE", proc))
            }
            if let pub = item.allFields["publisher"], !pub.isEmpty {
                fields.append(("PUBLISHER", pub))
            }
            if let pages = item.allFields["pages"], !pages.isEmpty {
                fields.append(("PAGES", APAUtilities.normalizePages(pages)))
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

        // M3: Audio/Video/Podcast proper field handling
        case "podcast":
            if let series = item.allFields["seriesTitle"] ?? item.publicationTitle, !series.isEmpty {
                fields.append(("TITLEADDON", series))
            }
            if let episodeNum = item.allFields["episodeNumber"] ?? item.allFields["number"], !episodeNum.isEmpty {
                fields.append(("NUMBER", episodeNum))
            }
            if let pub = item.allFields["publisher"], !pub.isEmpty {
                fields.append(("PUBLISHER", pub))
            }

        case "audioRecording":
            if let pub = item.allFields["label"] ?? item.allFields["publisher"], !pub.isEmpty {
                fields.append(("PUBLISHER", pub))
            }
            if let vol = item.allFields["volume"], !vol.isEmpty {
                fields.append(("VOLUME", vol))
            }

        case "film", "videoRecording":
            if let pub = item.allFields["studio"] ?? item.allFields["distributor"] ?? item.allFields["publisher"], !pub.isEmpty {
                fields.append(("PUBLISHER", pub))
            }

        default:
            if let pub = item.allFields["publisher"], !pub.isEmpty {
                fields.append(("PUBLISHER", pub))
            }
            if let pages = item.allFields["pages"], !pages.isEmpty {
                fields.append(("PAGES", APAUtilities.normalizePages(pages)))
            }
        }
    }

    // MARK: - Date Fields

    static func addDateFields(_ item: ZoteroItem, _ entryType: String, _ fields: inout [(key: String, value: String)]) {
        if let date = item.date, !date.isEmpty {
            fields.append(("DATE", APAUtilities.normalizeDate(date)))
        }
        if let origDate = item.allFields["originalDate"], !origDate.isEmpty {
            fields.append(("ORIGDATE", APAUtilities.normalizeDate(origDate)))
        }
        // URLDATE for sources where content may change (wikis, social media, webpages)
        if let accessDate = item.allFields["accessDate"], !accessDate.isEmpty {
            let urlDateTypes: Set<String> = ["webpage", "blogPost", "encyclopediaArticle", "dictionaryEntry"]
            if urlDateTypes.contains(item.itemType) || entryType == "ONLINE" {
                let normalized = APAUtilities.normalizeDate(accessDate)
                if !normalized.isEmpty {
                    fields.append(("URLDATE", normalized))
                }
            }
        }
    }

    // MARK: - Identifier Fields

    static func addIdentifierFields(_ item: ZoteroItem, _ entryType: String, _ fields: inout [(key: String, value: String)]) {
        if let doi = item.DOI, !doi.isEmpty {
            fields.append(("DOI", doi))
        }

        // URL: only if no DOI (APA 7), except for online-primary types
        let onlinePrimaryTypes: Set<String> = ["webpage", "blogPost", "presentation"]
        if let url = item.url, !url.isEmpty {
            if (item.DOI ?? "").isEmpty {
                fields.append(("URL", url))
            } else if onlinePrimaryTypes.contains(item.itemType) || entryType == "ONLINE" {
                fields.append(("URL", url))
            }
        }
    }

    // MARK: - Metadata Fields (H3, H4, H5, M5)

    static func addMetadataFields(_ item: ZoteroItem, _ entryType: String, _ fields: inout [(key: String, value: String)]) {
        if let lang = item.allFields["language"], !lang.isEmpty {
            fields.append(("LANGID", APAUtilities.mapLanguageToLangID(lang)))
        }

        // H3: ENTRYSUBTYPE for social media, podcasts, etc.
        addEntrySubtype(item, entryType, &fields)

        // H4: TITLEADDON for media descriptors (broader usage)
        addTitleAddon(item, entryType, &fields)

        // Parse extra field for additional metadata
        if let extra = item.allFields["extra"], !extra.isEmpty {
            let parsed = APAUtilities.parseExtraField(extra)

            // H5: ADDENDUM for retracted articles
            if let retracted = parsed["Retracted"] ?? parsed["Retraction Date"] ?? parsed["retracted"] {
                fields.append(("ADDENDUM", "Retracted \(retracted)"))
            }

            // PMID
            if let pmid = parsed["PMID"] {
                fields.append(("NOTE", "PMID: \(pmid)"))
            }

            // M5: PUBSTATE for in-press works
            if let pubstate = parsed["Publication Status"] ?? parsed["pubstate"] ?? parsed["PUBSTATE"] {
                fields.append(("PUBSTATE", pubstate.lowercased()))
            } else if extra.lowercased().contains("in press") {
                fields.append(("PUBSTATE", "inpress"))
            }
        }

        if let numVol = item.allFields["numberOfVolumes"], !numVol.isEmpty {
            fields.append(("VOLUMES", numVol))
        }
    }

    /// H3: Determine ENTRYSUBTYPE from item metadata.
    static func addEntrySubtype(_ item: ZoteroItem, _ entryType: String, _ fields: inout [(key: String, value: String)]) {
        if item.itemType == "webpage" || item.itemType == "blogPost" {
            if let site = item.allFields["websiteTitle"]?.lowercased() {
                let subtypeMap: [(contains: String, subtype: String)] = [
                    ("twitter", "Tweet"), ("x.com", "Tweet"),
                    ("facebook", "Facebook post"),
                    ("instagram", "Instagram photo"),
                    ("tiktok", "TikTok video"),
                    ("linkedin", "LinkedIn post"),
                    ("reddit", "Reddit post"),
                    ("youtube", "Video"),
                    ("wikipedia", "Wikipedia entry"),
                ]
                for (keyword, subtype) in subtypeMap {
                    if site.contains(keyword) {
                        fields.append(("ENTRYSUBTYPE", subtype))
                        return
                    }
                }
            }
        }

        if item.itemType == "podcast" {
            let hasEpisode = !(item.allFields["episodeNumber"] ?? item.allFields["number"] ?? "").isEmpty
            fields.append(("ENTRYSUBTYPE", hasEpisode ? "podcast episode" : "podcast"))
        }
    }

    /// H4: Add TITLEADDON for media descriptors beyond reports/presentations.
    static func addTitleAddon(_ item: ZoteroItem, _ entryType: String, _ fields: inout [(key: String, value: String)]) {
        // Skip if already set (e.g., by addSourceFields for reports/presentations/podcasts)
        if fields.contains(where: { $0.key == "TITLEADDON" }) { return }

        // Check extra field for explicit format/medium
        if let extra = item.allFields["extra"], !extra.isEmpty {
            let parsed = APAUtilities.parseExtraField(extra)
            if let format = parsed["Format"] ?? parsed["Medium"] ?? parsed["medium"] {
                fields.append(("TITLEADDON", format))
                return
            }
        }

        // Books: detect e-book, audiobook from extra
        if item.itemType == "book" {
            if let extra = item.allFields["extra"]?.lowercased() {
                if extra.contains("e-book") || extra.contains("ebook") || extra.contains("kindle") {
                    fields.append(("TITLEADDON", "E-book"))
                } else if extra.contains("audiobook") {
                    fields.append(("TITLEADDON", "Audiobook"))
                }
            }
        }
    }

    // MARK: - Cite Key Generation

    static func generateCiteKey(_ item: ZoteroItem) -> String {
        if let ck = item.allFields["citationKey"], !ck.isEmpty {
            return ck
        }

        if let extra = item.allFields["extra"], !extra.isEmpty {
            let extraFields = APAUtilities.parseExtraField(extra)
            if let ck = extraFields["Citation Key"], !ck.isEmpty { return ck }
        }

        let lastName: String
        if let firstCreator = item.creatorDetails.first {
            lastName = firstCreator.lastName
                .components(separatedBy: " ").last ?? firstCreator.lastName
        } else {
            lastName = "unknown"
        }

        let year = APAUtilities.normalizeSingleDate(item.date ?? "").prefix(4)
        let cleanName = lastName.lowercased()
            .replacingOccurrences(of: " ", with: "")
            .filter { $0.isLetter }

        return "\(cleanName)\(year)"
    }
}
