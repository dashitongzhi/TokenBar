import Foundation

struct ProbeTemplateLoader {
    static func builtInTemplates() -> [ProbeTemplate] {
        [
            ProbeTemplate(platform: "openai", displayName: "OpenAI", category: "AI & API", symbolName: "brain.head.profile", unit: "tokens"),
            ProbeTemplate(platform: "anthropic", displayName: "Anthropic", category: "AI & API", symbolName: "sparkles", unit: "tokens"),
            ProbeTemplate(platform: "stripe", displayName: "Stripe", category: "Payments", symbolName: "creditcard.fill", unit: "events"),
            ProbeTemplate(platform: "github", displayName: "GitHub Copilot", category: "Developer Tool", symbolName: "chevron.left.forwardslash.chevron.right", unit: "requests"),
            ProbeTemplate(platform: "cursor", displayName: "Cursor", category: "AI Tool", symbolName: "cursorarrow.motionlines", unit: "requests"),
            ProbeTemplate(platform: "codex", displayName: "OpenAI Codex", category: "AI Tool", symbolName: "terminal.fill", unit: "requests"),
            ProbeTemplate(platform: "gemini", displayName: "Gemini", category: "AI & API", symbolName: "diamond.fill", unit: "tokens"),
            ProbeTemplate(platform: "openrouter", displayName: "OpenRouter", category: "AI & API", symbolName: "point.3.connected.trianglepath.dotted", unit: "credits"),
            ProbeTemplate(platform: "deepseek", displayName: "DeepSeek", category: "AI & API", symbolName: "magnifyingglass", unit: "tokens"),
            ProbeTemplate(platform: "mistral", displayName: "Mistral", category: "AI & API", symbolName: "wind", unit: "tokens"),
            ProbeTemplate(platform: "vercel", displayName: "Vercel", category: "Cloud", symbolName: "triangle.fill", unit: "requests"),
            ProbeTemplate(platform: "railway", displayName: "Railway", category: "Cloud", symbolName: "tram.fill", unit: "requests"),
            ProbeTemplate(platform: "render", displayName: "Render", category: "Cloud", symbolName: "shippingbox.fill", unit: "requests"),
            ProbeTemplate(platform: "fly", displayName: "Fly.io", category: "Cloud", symbolName: "paperplane.fill", unit: "requests"),
            ProbeTemplate(platform: "netlify", displayName: "Netlify", category: "Cloud", symbolName: "network", unit: "requests"),
            ProbeTemplate(platform: "supabase", displayName: "Supabase", category: "Database", symbolName: "cylinder.split.1x2.fill", unit: "requests"),
            ProbeTemplate(platform: "planetscale", displayName: "PlanetScale", category: "Database", symbolName: "globe", unit: "queries"),
            ProbeTemplate(platform: "aws", displayName: "AWS", category: "Cloud", symbolName: "server.rack", unit: "USD"),
            ProbeTemplate(platform: "google-cloud", displayName: "Google Cloud", category: "Cloud", symbolName: "cloud.fill", unit: "USD"),
            ProbeTemplate(platform: "azure", displayName: "Azure", category: "Cloud", symbolName: "cloud.bolt.fill", unit: "USD"),
            ProbeTemplate(platform: "cloudflare", displayName: "Cloudflare", category: "CDN", symbolName: "cloud.fill", unit: "requests"),
            ProbeTemplate(platform: "sentry", displayName: "Sentry", category: "Monitoring", symbolName: "exclamationmark.bubble.fill", unit: "events")
            ,ProbeTemplate(platform: "datadog", displayName: "Datadog", category: "Monitoring", symbolName: "waveform.path.ecg", unit: "events")
            ,ProbeTemplate(platform: "sendgrid", displayName: "SendGrid", category: "Communication", symbolName: "envelope.fill", unit: "emails")
            ,ProbeTemplate(platform: "twilio", displayName: "Twilio", category: "Communication", symbolName: "phone.bubble.fill", unit: "messages")
            ,ProbeTemplate(platform: "algolia", displayName: "Algolia", category: "Search", symbolName: "magnifyingglass.circle.fill", unit: "operations")
            ,ProbeTemplate(platform: "mapbox", displayName: "Mapbox", category: "Maps", symbolName: "map.fill", unit: "requests")
        ]
    }
}
