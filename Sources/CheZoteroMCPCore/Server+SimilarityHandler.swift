// Server+SimilarityHandler.swift — Paper similarity comparison handler
import Foundation
import MCP

extension CheZoteroMCPServer {

    func handleComparePapers(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        let paperA = params.arguments?["paper_a"]?.stringValue ?? ""
        let paperB = params.arguments?["paper_b"]?.stringValue ?? ""

        guard !paperA.isEmpty, !paperB.isEmpty else {
            return CallTool.Result(content: [.text("Both paper_a and paper_b are required.")], isError: true)
        }

        // Step 1: Resolve both inputs to DOI
        let resolvedA = resolveToDOI(paperA)
        let resolvedB = resolveToDOI(paperB)

        guard let doiA = resolvedA.doi else {
            return CallTool.Result(content: [.text("Cannot resolve paper_a '\(paperA)' to DOI. \(resolvedA.reason ?? "")")], isError: true)
        }
        guard let doiB = resolvedB.doi else {
            return CallTool.Result(content: [.text("Cannot resolve paper_b '\(paperB)' to DOI. \(resolvedB.reason ?? "")")], isError: true)
        }

        if doiA.lowercased() == doiB.lowercased() {
            return CallTool.Result(content: [.text("Both inputs resolve to the same DOI: \(doiA). Cannot compare a paper to itself.")], isError: true)
        }

        // Step 2: Fetch OpenAlex works for both
        let workA = try? await academic.getWork(doi: doiA)
        let workB = try? await academic.getWork(doi: doiB)

        // Pre-compute reference sets for graph metrics
        let refsA = Set(workA?.referenced_works ?? [])
        let refsB = Set(workB?.referenced_works ?? [])
        let sharedRefs = refsA.intersection(refsB)

        var dimensions: [(name: String, value: String, detail: String)] = []

        // --- Content ---
        dimensions.append(computeSemantic(resolvedA: resolvedA, resolvedB: resolvedB))

        // --- Citation Structure (Bibliographic Coupling family) ---
        dimensions.append(computeBibCoupling(refsA: refsA, refsB: refsB, shared: sharedRefs))

        let (aaResult, raResult) = await computeWeightedBibCoupling(sharedRefs: sharedRefs)
        dimensions.append(aaResult)
        dimensions.append(raResult)

        dimensions.append(computeHPI(refsA: refsA, refsB: refsB, shared: sharedRefs))
        dimensions.append(computeHDI(refsA: refsA, refsB: refsB, shared: sharedRefs))

        // --- Co-citation ---
        let coCitationResult = await computeCoCitation(workA: workA, workB: workB)
        dimensions.append(coCitationResult)

        // --- Metadata ---
        dimensions.append(computeAuthorOverlap(workA: workA, workB: workB))
        dimensions.append(computeVenue(workA: workA, workB: workB))
        dimensions.append(computeTagOverlap(resolvedA: resolvedA, resolvedB: resolvedB))

        // --- Graph Distance ---
        dimensions.append(computeShortestPath(workA: workA, workB: workB, sharedRefs: sharedRefs, coCitValue: coCitationResult.value))

        // Step 3: Format output
        let titleA = workA?.display_name ?? workA?.title ?? doiA
        let titleB = workB?.display_name ?? workB?.title ?? doiB

        var lines: [String] = []
        lines.append("Paper A: \(titleA)")
        lines.append("  DOI: \(doiA)\(resolvedA.zoteroKey != nil ? " [Zotero: \(resolvedA.zoteroKey!)]" : "")")
        lines.append("Paper B: \(titleB)")
        lines.append("  DOI: \(doiB)\(resolvedB.zoteroKey != nil ? " [Zotero: \(resolvedB.zoteroKey!)]" : "")")
        lines.append("")
        lines.append("Similarity Vector:")
        lines.append(String(repeating: "-", count: 60))

        for dim in dimensions {
            lines.append("  \(dim.name): \(dim.value)")
            if !dim.detail.isEmpty {
                lines.append("    \(dim.detail)")
            }
        }

        lines.append(String(repeating: "-", count: 60))
        lines.append("Methods: Salton |A∩B|/√(|A|·|B|), Adamic-Adar Σ1/log(cited_by), RA Σ1/cited_by, HPI/HDI min/max norm")

        return CallTool.Result(content: [.text(lines.joined(separator: "\n"))], isError: false)
    }

    // MARK: - Resolve Input to DOI

    private struct ResolvedPaper {
        let doi: String?
        let zoteroKey: String?
        let reason: String?
    }

    private func resolveToDOI(_ input: String) -> ResolvedPaper {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)

        // Check if it looks like a DOI
        let doiPatterns = ["10.", "doi.org/"]
        let looksLikeDOI = doiPatterns.contains { trimmed.lowercased().contains($0) }

        if looksLikeDOI {
            let cleanDOI = trimmed
                .replacingOccurrences(of: "https://doi.org/", with: "")
                .replacingOccurrences(of: "http://doi.org/", with: "")

            // Try to find matching Zotero item
            let zoteroKey = (try? reader.searchByDOI(doi: cleanDOI))?.key
            return ResolvedPaper(doi: cleanDOI, zoteroKey: zoteroKey, reason: nil)
        }

        // Assume it's a Zotero item key
        if let item = try? reader.getItem(key: trimmed) {
            if let doi = item.DOI, !doi.isEmpty {
                let cleanDOI = doi
                    .replacingOccurrences(of: "https://doi.org/", with: "")
                    .replacingOccurrences(of: "http://doi.org/", with: "")
                return ResolvedPaper(doi: cleanDOI, zoteroKey: trimmed, reason: nil)
            } else {
                return ResolvedPaper(doi: nil, zoteroKey: trimmed, reason: "Zotero item '\(trimmed)' has no DOI.")
            }
        }

        return ResolvedPaper(doi: nil, zoteroKey: nil, reason: "'\(trimmed)' is not a valid DOI or Zotero item key.")
    }

    // MARK: - Dimension Computations

    private func computeSemantic(resolvedA: ResolvedPaper, resolvedB: ResolvedPaper) -> (name: String, value: String, detail: String) {
        guard let keyA = resolvedA.zoteroKey, let keyB = resolvedB.zoteroKey else {
            let missing = [
                resolvedA.zoteroKey == nil ? "paper_a" : nil,
                resolvedB.zoteroKey == nil ? "paper_b" : nil,
            ].compactMap { $0 }.joined(separator: ", ")
            return ("semantic", "null", "\(missing) not in Zotero library")
        }

        guard let sim = embeddings.cosineSimilarity(keyA: keyA, keyB: keyB) else {
            let missing = [
                !embeddings.hasEmbedding(for: keyA) ? "paper_a" : nil,
                !embeddings.hasEmbedding(for: keyB) ? "paper_b" : nil,
            ].compactMap { $0 }.joined(separator: ", ")
            return ("semantic", "null", "\(missing) not in embedding index (run zotero_build_index)")
        }

        return ("semantic", String(format: "%.4f", sim), "cosine similarity of bge-m3 embeddings (title+abstract+authors+tags)")
    }

    private func computeBibCoupling(refsA: Set<String>, refsB: Set<String>, shared: Set<String>) -> (name: String, value: String, detail: String) {
        if refsA.isEmpty && refsB.isEmpty {
            return ("bibliographic_coupling", "null", "No reference data in OpenAlex")
        }

        let denominator = sqrt(Double(refsA.count) * Double(refsB.count))
        if denominator == 0 {
            return ("bibliographic_coupling", "0.0000", "|A|=\(refsA.count), |B|=\(refsB.count), shared=0")
        }

        let score = Double(shared.count) / denominator
        return ("bibliographic_coupling", String(format: "%.4f", score), "|A|=\(refsA.count), |B|=\(refsB.count), shared=\(shared.count)")
    }

    // MARK: - Adamic-Adar & Resource Allocation

    private func computeWeightedBibCoupling(sharedRefs: Set<String>) async -> ((name: String, value: String, detail: String), (name: String, value: String, detail: String)) {
        guard !sharedRefs.isEmpty else {
            return (
                ("adamic_adar", "0.0000", "No shared references"),
                ("resource_allocation", "0.0000", "No shared references")
            )
        }

        do {
            let counts = try await academic.getCitedByCounts(openAlexIDs: sharedRefs)

            var aaScore = 0.0
            var raScore = 0.0

            for ref in sharedRefs {
                let count = counts[ref] ?? 0
                if count > 1 {
                    aaScore += 1.0 / log(Double(count))
                    raScore += 1.0 / Double(count)
                } else if count <= 1 {
                    // log(1)=0 → cap contribution at 1.0 (maximally informative)
                    aaScore += 1.0
                    raScore += 1.0
                }
            }

            // Show a few example shared refs with their citation counts
            let examples = sharedRefs.prefix(3).compactMap { ref -> String? in
                let c = counts[ref] ?? 0
                let short = ref.replacingOccurrences(of: "https://openalex.org/", with: "")
                return "\(short)(cited:\(c))"
            }.joined(separator: ", ")

            return (
                ("adamic_adar", String(format: "%.4f", aaScore), "\(sharedRefs.count) shared refs; e.g. \(examples)"),
                ("resource_allocation", String(format: "%.4f", raScore), "Σ1/cited_by for \(sharedRefs.count) shared refs")
            )
        } catch {
            return (
                ("adamic_adar", "null", "API error: \(error.localizedDescription)"),
                ("resource_allocation", "null", "API error: \(error.localizedDescription)")
            )
        }
    }

    // MARK: - Hub Promoted Index

    private func computeHPI(refsA: Set<String>, refsB: Set<String>, shared: Set<String>) -> (name: String, value: String, detail: String) {
        let minSize = min(refsA.count, refsB.count)
        guard minSize > 0 else {
            return ("hub_promoted_index", "null", "No reference data")
        }

        let score = Double(shared.count) / Double(minSize)
        return ("hub_promoted_index", String(format: "%.4f", score), "|shared|/min(|A|,|B|) = \(shared.count)/\(minSize)")
    }

    // MARK: - Hub Depressed Index

    private func computeHDI(refsA: Set<String>, refsB: Set<String>, shared: Set<String>) -> (name: String, value: String, detail: String) {
        let maxSize = max(refsA.count, refsB.count)
        guard maxSize > 0 else {
            return ("hub_depressed_index", "null", "No reference data")
        }

        let score = Double(shared.count) / Double(maxSize)
        return ("hub_depressed_index", String(format: "%.4f", score), "|shared|/max(|A|,|B|) = \(shared.count)/\(maxSize)")
    }

    private func computeCoCitation(workA: OpenAlexWork?, workB: OpenAlexWork?) async -> (name: String, value: String, detail: String) {
        guard let idA = workA?.openAlexID, let idB = workB?.openAlexID else {
            return ("co_citation", "null", "OpenAlex ID not available")
        }

        do {
            async let fetchA = academic.getCitingWorkDOIs(openAlexID: idA)
            async let fetchB = academic.getCitingWorkDOIs(openAlexID: idB)
            let (resultA, resultB) = try await (fetchA, fetchB)

            let intersection = resultA.dois.intersection(resultB.dois).count
            let denominator = sqrt(Double(resultA.dois.count) * Double(resultB.dois.count))

            var detail = "|A|=\(resultA.dois.count), |B|=\(resultB.dois.count), shared=\(intersection)"

            // Annotate if truncated
            if resultA.totalCount > 200 || resultB.totalCount > 200 {
                let noteA = resultA.totalCount > 200 ? "A:\(resultA.totalCount) total" : nil
                let noteB = resultB.totalCount > 200 ? "B:\(resultB.totalCount) total" : nil
                let truncated = [noteA, noteB].compactMap { $0 }.joined(separator: ", ")
                detail += " (based on max 200 citing works; \(truncated))"
            }

            if denominator == 0 {
                return ("co_citation", "0.0000", detail)
            }

            let score = Double(intersection) / denominator
            return ("co_citation", String(format: "%.4f", score), detail)
        } catch {
            return ("co_citation", "null", "API error: \(error.localizedDescription)")
        }
    }

    private func computeAuthorOverlap(workA: OpenAlexWork?, workB: OpenAlexWork?) -> (name: String, value: String, detail: String) {
        let authorsA = workA?.authorList ?? []
        let authorsB = workB?.authorList ?? []

        guard !authorsA.isEmpty, !authorsB.isEmpty else {
            return ("author_overlap", "null", "Author data not available")
        }

        // Normalize: lowercased for comparison
        let setA = Set(authorsA.map { $0.lowercased() })
        let setB = Set(authorsB.map { $0.lowercased() })
        let intersection = setA.intersection(setB).count
        let denominator = sqrt(Double(setA.count) * Double(setB.count))

        if denominator == 0 {
            return ("author_overlap", "0.0000", "|A|=\(setA.count), |B|=\(setB.count), shared=0")
        }

        let score = Double(intersection) / denominator
        let sharedNames = setA.intersection(setB).joined(separator: ", ")
        let detail = "|A|=\(setA.count), |B|=\(setB.count), shared=\(intersection)" + (intersection > 0 ? " (\(sharedNames))" : "")
        return ("author_overlap", String(format: "%.4f", score), detail)
    }

    private func computeVenue(workA: OpenAlexWork?, workB: OpenAlexWork?) -> (name: String, value: String, detail: String) {
        let venueA = workA?.primary_location?.source?.display_name
        let venueB = workB?.primary_location?.source?.display_name

        guard let vA = venueA, let vB = venueB, !vA.isEmpty, !vB.isEmpty else {
            return ("venue", "null", "Venue data not available")
        }

        let same = vA.lowercased() == vB.lowercased()
        return ("venue", same ? "1" : "0", same ? "Same: \(vA)" : "A: \(vA) | B: \(vB)")
    }

    private func computeTagOverlap(resolvedA: ResolvedPaper, resolvedB: ResolvedPaper) -> (name: String, value: String, detail: String) {
        guard let keyA = resolvedA.zoteroKey, let keyB = resolvedB.zoteroKey else {
            let missing = [
                resolvedA.zoteroKey == nil ? "paper_a" : nil,
                resolvedB.zoteroKey == nil ? "paper_b" : nil,
            ].compactMap { $0 }.joined(separator: ", ")
            return ("tag_overlap", "null", "\(missing) not in Zotero library")
        }

        let tagsA = (try? reader.getItem(key: keyA))?.tags ?? []
        let tagsB = (try? reader.getItem(key: keyB))?.tags ?? []

        if tagsA.isEmpty && tagsB.isEmpty {
            return ("tag_overlap", "null", "Neither item has tags")
        }
        if tagsA.isEmpty || tagsB.isEmpty {
            return ("tag_overlap", "0.0000", "|A|=\(tagsA.count), |B|=\(tagsB.count), shared=0")
        }

        let setA = Set(tagsA.map { $0.lowercased() })
        let setB = Set(tagsB.map { $0.lowercased() })
        let intersection = setA.intersection(setB).count
        let denominator = sqrt(Double(setA.count) * Double(setB.count))

        if denominator == 0 {
            return ("tag_overlap", "0.0000", "|A|=\(setA.count), |B|=\(setB.count), shared=0")
        }

        let score = Double(intersection) / denominator
        let sharedTags = setA.intersection(setB).joined(separator: ", ")
        let detail = "|A|=\(setA.count), |B|=\(setB.count), shared=\(intersection)" + (intersection > 0 ? " (\(sharedTags))" : "")
        return ("tag_overlap", String(format: "%.4f", score), detail)
    }

    // MARK: - Shortest Path in Citation Graph

    private func computeShortestPath(workA: OpenAlexWork?, workB: OpenAlexWork?, sharedRefs: Set<String>, coCitValue: String) -> (name: String, value: String, detail: String) {
        guard let idA = workA?.id, let idB = workB?.id else {
            return ("shortest_path", "null", "OpenAlex ID not available")
        }

        let refsA = Set(workA?.referenced_works ?? [])
        let refsB = Set(workB?.referenced_works ?? [])

        // Distance 1: direct citation
        if refsA.contains(idB) {
            return ("shortest_path", "1", "A cites B (direct citation)")
        }
        if refsB.contains(idA) {
            return ("shortest_path", "1", "B cites A (direct citation)")
        }

        // Distance 2: connected via shared references or shared citing papers
        if !sharedRefs.isEmpty {
            return ("shortest_path", "2", "Via \(sharedRefs.count) shared reference(s)")
        }

        let hasCoCit = coCitValue != "0.0000" && coCitValue != "null"
        if hasCoCit {
            return ("shortest_path", "2", "Via shared citing paper(s)")
        }

        return ("shortest_path", ">2", "No connection within 2 hops")
    }
}
