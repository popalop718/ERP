import UIKit
import ImageIO

struct GIFItem {
    let id: String
    let previewURL: URL
    let fullURL: URL
    let aspect: CGFloat   // width / height
}

enum GIFError: LocalizedError {
    case noKey, noAccess, badResponse(String)
    var errorDescription: String? {
        switch self {
        case .noKey: return "Add a Tenor or GIPHY API key in the Duo Keyboard app to use GIFs."
        case .noAccess: return "Turn on Allow Full Access for Duo Keyboard to load GIFs."
        case .badResponse(let s): return s
        }
    }
}

/// Searches Tenor (Google) or GIPHY. Both need a free developer API key, entered
/// in the container app. Network access requires "Allow Full Access".
final class GIFService {
    private let session: URLSession = {
        let cfg = URLSessionConfiguration.default
        cfg.urlCache = URLCache(memoryCapacity: 8 << 20, diskCapacity: 40 << 20)
        cfg.timeoutIntervalForRequest = 12
        return URLSession(configuration: cfg)
    }()
    private let imageCache = NSCache<NSURL, UIImage>()
    private var currentTask: URLSessionDataTask?

    init() { imageCache.totalCostLimit = 18 << 20 }

    func search(_ query: String?, provider: GIFProvider, apiKey: String, language: KeyboardLanguage,
                completion: @escaping (Result<[GIFItem], Error>) -> Void) {
        guard !apiKey.isEmpty else { return completion(.failure(GIFError.noKey)) }
        var comps: URLComponents
        let q = query?.trimmingCharacters(in: .whitespaces) ?? ""
        switch provider {
        case .tenor:
            comps = URLComponents(string: q.isEmpty ? "https://tenor.googleapis.com/v2/featured" : "https://tenor.googleapis.com/v2/search")!
            comps.queryItems = [URLQueryItem(name: "key", value: apiKey), URLQueryItem(name: "client_key", value: "duo_keyboard"),
                                URLQueryItem(name: "limit", value: "30"), URLQueryItem(name: "media_filter", value: "tinygif,gif"),
                                URLQueryItem(name: "contentfilter", value: "medium"),
                                URLQueryItem(name: "locale", value: language.checkerCandidates[0])]
            if !q.isEmpty { comps.queryItems?.append(URLQueryItem(name: "q", value: q)) }
        case .giphy:
            comps = URLComponents(string: q.isEmpty ? "https://api.giphy.com/v1/gifs/trending" : "https://api.giphy.com/v1/gifs/search")!
            comps.queryItems = [URLQueryItem(name: "api_key", value: apiKey), URLQueryItem(name: "limit", value: "30"),
                                URLQueryItem(name: "rating", value: "pg-13"), URLQueryItem(name: "lang", value: language.rawValue)]
            if !q.isEmpty { comps.queryItems?.append(URLQueryItem(name: "q", value: q)) }
        }
        guard let url = comps.url else { return }
        currentTask?.cancel()
        let task = session.dataTask(with: url) { data, response, error in
            let result: Result<[GIFItem], Error>
            if let error { result = .failure(error) }
            else if let data, let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                let items = provider == .tenor ? Self.parseTenor(json) : Self.parseGiphy(json)
                if items.isEmpty, (response as? HTTPURLResponse)?.statusCode ?? 200 >= 400 {
                    result = .failure(GIFError.badResponse("The GIF service rejected the request — check your API key."))
                } else {
                    result = .success(items)
                }
            } else {
                result = .failure(GIFError.badResponse("Couldn't read the GIF service response."))
            }
            DispatchQueue.main.async { completion(result) }
        }
        currentTask = task
        task.resume()
    }

    private static func parseTenor(_ json: [String: Any]) -> [GIFItem] {
        (json["results"] as? [[String: Any]] ?? []).compactMap { r in
            guard let id = r["id"] as? String, let media = r["media_formats"] as? [String: Any],
                  let tiny = media["tinygif"] as? [String: Any], let gif = media["gif"] as? [String: Any],
                  let p = (tiny["url"] as? String).flatMap(URL.init(string:)),
                  let f = (gif["url"] as? String).flatMap(URL.init(string:)) else { return nil }
            let dims = tiny["dims"] as? [Double] ?? [1, 1]
            return GIFItem(id: id, previewURL: p, fullURL: f, aspect: CGFloat(dims[0] / max(dims.count > 1 ? dims[1] : 1, 1)))
        }
    }

    private static func parseGiphy(_ json: [String: Any]) -> [GIFItem] {
        (json["data"] as? [[String: Any]] ?? []).compactMap { r in
            guard let id = r["id"] as? String, let images = r["images"] as? [String: Any],
                  let small = images["fixed_height_small"] as? [String: Any],
                  let full = (images["downsized"] as? [String: Any]) ?? (images["original"] as? [String: Any]),
                  let p = (small["url"] as? String).flatMap(URL.init(string:)),
                  let f = (full["url"] as? String).flatMap(URL.init(string:)) else { return nil }
            let w = Double(small["width"] as? String ?? "1") ?? 1, h = Double(small["height"] as? String ?? "1") ?? 1
            return GIFItem(id: id, previewURL: p, fullURL: f, aspect: CGFloat(w / max(h, 1)))
        }
    }

    func preview(_ url: URL, completion: @escaping (UIImage?) -> Void) {
        if let img = imageCache.object(forKey: url as NSURL) { return completion(img) }
        session.dataTask(with: url) { [weak self] data, _, _ in
            let img = data.flatMap { Self.animatedImage(from: $0, maxPixel: 220) }
            if let img { self?.imageCache.setObject(img, forKey: url as NSURL, cost: data?.count ?? 0) }
            DispatchQueue.main.async { completion(img) }
        }.resume()
    }

    /// Downloads the full GIF and puts it on the pasteboard so it can be pasted
    /// into Messages, WhatsApp, Mail, etc. (keyboards can't insert images directly).
    func copyToPasteboard(_ item: GIFItem, completion: @escaping (Bool) -> Void) {
        session.dataTask(with: item.fullURL) { data, _, _ in
            DispatchQueue.main.async {
                guard let data, !data.isEmpty else { return completion(false) }
                UIPasteboard.general.setData(data, forPasteboardType: "com.compuserve.gif")
                completion(true)
            }
        }.resume()
    }

    static func animatedImage(from data: Data, maxPixel: Int) -> UIImage? {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let count = CGImageSourceGetCount(src)
        let opts: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true,
                                     kCGImageSourceThumbnailMaxPixelSize: maxPixel,
                                     kCGImageSourceCreateThumbnailWithTransform: true]
        var frames: [UIImage] = []
        var duration = 0.0
        let step = max(1, count / 40)   // cap memory: at most ~40 frames per preview
        var i = 0
        while i < count {
            if let cg = CGImageSourceCreateThumbnailAtIndex(src, i, opts as CFDictionary) {
                frames.append(UIImage(cgImage: cg))
                let props = CGImageSourceCopyPropertiesAtIndex(src, i, nil) as? [CFString: Any]
                let gif = props?[kCGImagePropertyGIFDictionary] as? [CFString: Any]
                let d = (gif?[kCGImagePropertyGIFUnclampedDelayTime] as? Double) ?? (gif?[kCGImagePropertyGIFDelayTime] as? Double) ?? 0.1
                duration += max(d, 0.02) * Double(step)
            }
            i += step
        }
        guard !frames.isEmpty else { return nil }
        return frames.count == 1 ? frames[0] : UIImage.animatedImage(with: frames, duration: duration)
    }
}
