import Foundation

enum ProbeTemplateLoader {
    static func builtInTemplates(bundle: Bundle = .main) -> [ProbeTemplate] {
        let decoder = JSONDecoder()
        return (bundle.urls(forResourcesWithExtension: "json", subdirectory: nil) ?? [])
            .compactMap { url -> ProbeTemplate? in
                guard let data = try? Data(contentsOf: url),
                      let template = try? decoder.decode(ProbeTemplate.self, from: data)
                else {
                    return nil
                }
                return template
            }
            .sorted {
                if $0.category != $1.category {
                    return $0.category.localizedCaseInsensitiveCompare($1.category) == .orderedAscending
                }
                return $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
            }
    }
}
