# Data Source Credibility Hierarchy

> v1.3.3 — 2026-03-05

## Overview

che-zotero-mcp queries multiple external data sources. Each has different levels of authority, coverage, and known issues. This document defines the credibility hierarchy used throughout the codebase to determine source priority.

## Credibility Ranking

```
Tier 1 (Self-curated)
  ORCID ──────────── Researcher maintains their own publication list

Tier 2 (Publisher-submitted)
  doi.org ─────────── Content negotiation returns CSL-JSON from the
                      DOI Registration Agency (Crossref, DataCite, mEDRA, etc.)
                      Metadata is submitted directly by publishers

Tier 3 (Curated registries)
  Crossref ────────── Publisher-submitted DOI metadata (subset of doi.org)
  DataCite ────────── Dataset/preprint DOI metadata (subset of doi.org)

Tier 4 (Aggregators)
  OpenAlex ────────── 250M+ works, aggregated from MAG, Crossref, PubMed,
                      ORCID, and publisher websites. Rich supplementary data
                      (citation counts, OA status) but applies algorithmic
                      disambiguation that can introduce errors.

Tier 5 (Regional)
  Airiti DOI ──────── Taiwan academic publications (via airiti.com)
```

## Source Characteristics

### ORCID (Tier 1)

| Attribute | Detail |
|-----------|--------|
| Maintainer | Individual researcher |
| Coverage | Only what the researcher adds (may be incomplete) |
| Accuracy | Highest — zero disambiguation errors |
| Data format | Title, year, DOI, journal, type |
| Limitation | Not all researchers have ORCID; profile may be incomplete |
| API | Public, no auth required |

### doi.org Content Negotiation (Tier 2)

| Attribute | Detail |
|-----------|--------|
| Maintainer | DOI Registration Agencies (12 worldwide) |
| Coverage | Any DOI registered with any RA globally |
| Accuracy | Very high — publisher-submitted metadata |
| Data format | CSL-JSON (title, authors, date, journal, volume, pages, etc.) |
| Limitation | No citation counts, no OA status, no abstracts (varies by RA) |
| API | `Accept: application/vnd.citationstyles.csl+json` header to `https://doi.org/{doi}` |

### DOI Registration Agencies

| RA | Region | Coverage |
|----|--------|----------|
| Crossref | Global | Journals, conferences, books |
| DataCite | Global | Datasets, preprints, software |
| mEDRA | Europe | Italian/European publishers |
| JaLC | Japan | Japanese publications |
| KISTI | Korea | Korean publications |
| Airiti | Taiwan | Taiwanese academic works |
| ISTIC | China | Chinese publications |
| CNKI | China | Chinese academic databases |
| OP | International | Select publishers |
| BSI | Standards | British Standards |
| EIDR | Entertainment | Film/TV identifiers |
| OPOCE | EU | EU official publications |

### OpenAlex (Tier 4)

| Attribute | Detail |
|-----------|--------|
| Maintainer | OurResearch (automated aggregation) |
| Coverage | 250M+ works globally |
| Accuracy | Good for metadata, but author disambiguation has known errors |
| Data format | Rich: title, authors, citations, OA status, abstracts, affiliations, OpenAlex ID |
| Limitation | Author disambiguation merges different people with similar names |
| API | Free, polite pool with `mailto` parameter |

#### Known OpenAlex Disambiguation Issues

OpenAlex uses algorithmic author disambiguation that can:
- **Merge different authors** with similar names into one entity (false merge)
- **Split one author** across multiple entities (false split)

Example: Searching for Author ID `A5073079707` (Che Cheng, psychometrics researcher at NTU) returns papers from unrelated researchers in petroleum engineering and education technology, because OpenAlex merged them into the same entity.

**Implication**: Even using `author.id` (the most precise OpenAlex filter), results may include misattributed papers. Always cross-reference with ORCID when available.

### Airiti DOI (Tier 5)

| Attribute | Detail |
|-----------|--------|
| Maintainer | Airiti Inc. (Taiwan) |
| Coverage | Taiwanese academic journals, theses |
| Accuracy | High for Taiwan-specific content |
| Data format | Basic: title, authors, journal |
| Limitation | Limited to Taiwan publications |
| API | HTML scraping (no structured API) |

## Application in Code

### DOI Resolution Cascade (`DOIResolver.swift`)

```
doi.org (Tier 2) → OpenAlex (Tier 4) → Airiti (Tier 5)
```

Used by: `academic_lookup_doi`, `zotero_add_item_by_doi`

Core metadata (title, authors, date) comes from the most authoritative source that has the DOI. OpenAlex is used for supplementary enrichment (citation count, OA status).

### Author Search Cascade (`academic_search_author`)

```
ORCID filter (Tier 1) → OpenAlex author.id (Tier 4) → Name search (Tier 4, degraded)
```

Priority is determined by which identifier is provided:
1. `orcid` parameter → `author.orcid` filter (precise, curated)
2. `openalex_author_id` parameter → `author.id` filter (precise but entity may be polluted)
3. `name` parameter → `raw_author_name.search` (fuzzy, high false positive rate)

### Data Quality Trade-offs

| Scenario | Recommended source | Why |
|----------|-------------------|-----|
| "Is this DOI correct?" | doi.org | Publisher-submitted, canonical |
| "How many citations?" | OpenAlex | Only source with citation data |
| "All my publications?" | ORCID | Self-curated, no disambiguation errors |
| "Explore author's work" | OpenAlex with author.id | Broad coverage, but verify with ORCID |
| "Taiwan thesis DOI" | Airiti | Only source for some Taiwan DOIs |
