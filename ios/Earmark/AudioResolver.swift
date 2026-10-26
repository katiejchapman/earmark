import Foundation

struct ResolvedAudio {
    var source: URL?
    var title: String
    var show = ""
    var episodes: [ResolvedEpisode] = []
}
struct ResolvedEpisode {
    var source: URL
    var title: String
    var show: String
    var page: URL?
}

struct AudioResolver {
    enum Failure: LocalizedError {
        case unavailable, noAudio
        var errorDescription: String? {
            switch self {
            case .unavailable: return "The source is unavailable. Your link is saved; try loading it again."
            case .noAudio: return "Link saved. No playable audio found. Try a direct audio link or the podcast’s RSS feed."
            }
        }
    }
    private let extensions = ["mp3", "m4a", "aac", "wav", "flac", "ogg", "mp4"]
    func resolve(_ url: URL) async throws -> ResolvedAudio {
        let archive = url.host == "archive.org" || (url.host?.hasSuffix(".archive.org") ?? false)
        if extensions.contains(url.pathExtension.lowercased()) {
            if archive, let normalized = Self.archiveDownload(url) {
                return ResolvedAudio(source: normalized, title: url.deletingPathExtension().lastPathComponent)
            }
            return ResolvedAudio(source: url, title: url.deletingPathExtension().lastPathComponent)
        }
        if archive { return try await resolveArchive(url) }
        let bytes = try await fetch(url)
        if let feed = RSSReader.read(bytes, base: url), !feed.episodes.isEmpty { return feed }
        guard let html = String(data: bytes, encoding: .utf8) else { throw Failure.noAudio }
        // Podcast publishers commonly expose PodcastEpisode in JSON-LD.
        for script in captures("<script[^>]*type=[\"']application/ld\\+json[\"'][^>]*>([\\s\\S]*?)</script>", in: html) {
            guard let data = script.data(using: .utf8), let json = try? JSONSerialization.jsonObject(with: data),
                  let episode = podcastEpisode(json) else { continue }
            let media = episode["associatedMedia"] ?? episode["audio"] ?? [:]
            let candidates = (media as? [[String: Any]]) ?? [(media as? [String: Any]) ?? [:]]
            let source = candidates.compactMap { webURL(($0["contentUrl"] ?? $0["url"]) as? String, base: url) }.first
            let series = (episode["partOfSeries"] ?? episode["isPartOf"]) as? [String: Any]
            if let source { return ResolvedAudio(source: source, title: episode["name"] as? String ?? "Episode", show: series?["name"] as? String ?? "") }
        }
        let tags = captures("(<(?:meta|audio|source|link)\\b[^>]*>)", in: html)
        var source: URL?
        var title = "Audio"
        var feedURL: URL?
        for tag in tags {
            let a = attributes(tag)
            if ["og:audio", "og:audio:url"].contains(a["property"] ?? "") { source = webURL(a["content"], base: url) ?? source }
            if tag.lowercased().hasPrefix("<audio") || tag.lowercased().hasPrefix("<source") { source = webURL(a["src"], base: url) ?? source }
            if a["property"] == "og:title" { title = a["content"] ?? title }
            if a["type"] == "application/rss+xml" { feedURL = webURL(a["href"], base: url) }
        }
        if let feedURL, let feedBytes = try? await fetch(feedURL), let feed = RSSReader.read(feedBytes, base: feedURL),
           let match = feed.episodes.first(where: { $0.page == url || (source != nil && $0.source == source) }) {
            return ResolvedAudio(source: match.source, title: match.title, show: match.show)
        }
        if let source { return ResolvedAudio(source: source, title: title) }
        throw Failure.noAudio
    }

    static func archiveDownload(_ url: URL) -> URL? {
        let parts = url.pathComponents
        guard let index = parts.firstIndex(where: { $0 == "items" || $0 == "download" }), parts.count > index + 2 else { return nil }
        return parts[(index + 1)...].reduce(URL(string: "https://archive.org/download")!) { $0.appendingPathComponent($1) }
    }

    private func resolveArchive(_ url: URL) async throws -> ResolvedAudio {
        let parts = url.pathComponents
        guard let i = parts.firstIndex(where: { ["details", "download", "embed"].contains($0) }), parts.count > i + 1 else { throw Failure.noAudio }
        let id = parts[i + 1]
        let bytes = try await fetch(URL(string: "https://archive.org/metadata")!.appendingPathComponent(id))
        guard let json = try JSONSerialization.jsonObject(with: bytes) as? [String: Any], let files = json["files"] as? [[String: Any]] else { throw Failure.noAudio }
        let supported = files.filter { extensions.contains((($0["name"] as? String) ?? "").components(separatedBy: ".").last?.lowercased() ?? "") }
        let file = supported.first { ($0["name"] as? String)?.lowercased().hasSuffix(".mp3") == true } ?? supported.first
        guard let file, let name = file["name"] as? String else { throw Failure.noAudio }
        let meta = json["metadata"] as? [String: Any] ?? [:]
        let src = URL(string: "https://archive.org/download")!.appendingPathComponent(id).appendingPathComponent(name)
        return ResolvedAudio(source: src, title: text(file["title"]) ?? text(meta["title"]) ?? name,
                             show: text(file["album"]) ?? text(meta["series"]) ?? text(meta["podcast_title"]) ?? "")
    }
    private func text(_ value: Any?) -> String? { (value as? String) ?? (value as? [String])?.first }
    private func fetch(_ url: URL) async throws -> Data {
        var request = URLRequest(url: url); request.timeoutInterval = 20
        let (bytes, response) = try await URLSession.shared.data(for: request)
        guard let response = response as? HTTPURLResponse, (200..<300).contains(response.statusCode), bytes.count <= 15_000_000 else { throw Failure.unavailable }
        return bytes
    }
    private func webURL(_ text: String?, base: URL) -> URL? {
        guard let text, let url = URL(string: text.replacingOccurrences(of: "&amp;", with: "&"), relativeTo: base)?.absoluteURL else { return nil }
        return LibraryURL.validate(url)
    }
    private func podcastEpisode(_ value: Any) -> [String: Any]? {
        if let list = value as? [Any] { return list.compactMap(podcastEpisode).first }
        guard let dict = value as? [String: Any] else { return nil }
        let types = (dict["@type"] as? [String]) ?? [dict["@type"] as? String ?? ""]
        if types.contains(where: { $0.hasSuffix("PodcastEpisode") }) { return dict }
        if let graph = dict["@graph"], let result = podcastEpisode(graph) { return result }
        if let entity = dict["mainEntity"] { return podcastEpisode(entity) }
        return nil
    }
    private func captures(_ pattern: String, in string: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return [] }
        return regex.matches(in: string, range: NSRange(string.startIndex..., in: string)).compactMap { Range($0.range(at: 1), in: string).map { String(string[$0]) } }
    }
    private func attributes(_ tag: String) -> [String: String] {
        let pattern = "([a-zA-Z:-]+)\\s*=\\s*[\"']([^\"']*)[\"']"
        guard let re = try? NSRegularExpression(pattern: pattern) else { return [:] }
        var result: [String: String] = [:]
        for match in re.matches(in: tag, range: NSRange(tag.startIndex..., in: tag)) {
            if let k = Range(match.range(at: 1), in: tag), let v = Range(match.range(at: 2), in: tag) { result[String(tag[k]).lowercased()] = String(tag[v]) }
        }
        return result
    }
}

private enum LibraryURL {
    static func validate(_ url: URL) -> URL? { ["https", "http"].contains(url.scheme ?? "") && url.host != nil ? url : nil }
}

final class RSSReader: NSObject, XMLParserDelegate {
    private var base: URL
    private var stack: [String] = []
    private var buffer = ""
    private var show = ""
    private var title = ""
    private var link: URL?
    private var source: URL?
    private var inItem = false
    private var episodes: [ResolvedEpisode] = []
    init(base: URL) { self.base = base }
    static func read(_ data: Data, base: URL) -> ResolvedAudio? {
        let reader = RSSReader(base: base)
        let parser = XMLParser(data: data); parser.delegate = reader
        parser.shouldResolveExternalEntities = false
        guard parser.parse(), !reader.episodes.isEmpty else { return nil }
        return ResolvedAudio(title: reader.show, show: reader.show, episodes: reader.episodes.map {
            var e = $0; e.show = reader.show; return e
        })
    }
    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String]) {
        stack.append(name); buffer = ""
        if name == "item" { inItem = true; title = ""; source = nil; link = nil }
        if inItem && name == "enclosure", let value = attributes["url"],
           let url = URL(string: value, relativeTo: base)?.absoluteURL,
           attributes["type"] == nil || attributes["type"]!.hasPrefix("audio/") { source = LibraryURL.validate(url) }
    }
    func parser(_ parser: XMLParser, foundCharacters string: String) { buffer += string }
    func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) { buffer += String(data: CDATABlock, encoding: .utf8) ?? "" }
    func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
        let value = buffer.trimmingCharacters(in: .whitespacesAndNewlines)
        let parent = stack.dropLast().last
        if name == "title" && parent == "channel" { show = value }
        if name == "title" && parent == "item" { title = value }
        if name == "link" && parent == "item" { link = URL(string: value, relativeTo: base)?.absoluteURL }
        if name == "item" {
            if let source { episodes.append(ResolvedEpisode(source: source, title: title.isEmpty ? "Episode" : title, show: show, page: link)) }
            inItem = false
        }
        _ = stack.popLast(); buffer = ""
    }
}
