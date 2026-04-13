//
//  ContentBlocker.swift
//  GeminiDesktop
//
//  Created by alexcding on 2025-12-16.
//

import WebKit

/// Manages WKContentRuleList for blocking ads, trackers, and telemetry on x.com
enum ContentBlocker {

    private static let identifier = "XContentBlocker"

    /// Domains where rules apply (x.com and twitter.com)
    private static let targetDomains = ["x.com", "*x.com", "twitter.com", "*twitter.com"]

    /// Compiles and registers content blocking rules onto the given content controller.
    /// Must be called BEFORE the WKWebView is instantiated.
    static func compile(into controller: WKUserContentController) {
        WKContentRuleListStore.default().compileContentRuleList(
            forIdentifier: identifier,
            encodedContentRuleList: ruleListJSON,
            completionHandler: { ruleList, error in
            if let error = error {
                print("[ContentBlocker] Compile error: \(error)")
                return
            }
            guard let ruleList = ruleList else { return }
            controller.add(ruleList)
            print("[ContentBlocker] Rules registered")
        })
    }

    /// Removes stored rule list on cleanup
    static func remove() {
        WKContentRuleListStore.default().removeContentRuleList(forIdentifier: identifier) { error in
            if let error = error {
                print("[ContentBlocker] Remove error: \(error)")
            }
        }
    }

    // MARK: - Rule List JSON

    private static let ruleListJSON: String = {
        let domains = targetDomains
        var rules: [[String: Any]] = []

        // Helper: create a block rule
        func block(_ urlFilter: String, resourceTypes: [String]? = nil) {
            var trigger: [String: Any] = [
                "url-filter": urlFilter,
                "if-domain": domains
            ]
            if let types = resourceTypes {
                trigger["resource-type"] = types
            }
            rules.append([
                "trigger": trigger,
                "action": ["type": "block"]
            ])
        }

        // Resource types for scripts/images/XHR
        let scriptImageXHR = ["script", "image", "xmlhttprequest"]
        let allTypes: [String] = ["document", "script", "image", "style-sheet", "raw", "subdocument", "xmlhttprequest", "media", "font", "other"]

        // MARK: Advertising
        block("doubleclick\\.net", resourceTypes: allTypes)
        block("googleadservices\\.com", resourceTypes: allTypes)
        block("googlesyndication\\.com", resourceTypes: allTypes)
        block("amazon-adsystem\\.com", resourceTypes: allTypes)
        block("adnxs\\.com", resourceTypes: allTypes)
        block("adsrvr\\.org", resourceTypes: allTypes)
        block("criteo\\.com", resourceTypes: allTypes)
        block("moatads\\.com", resourceTypes: allTypes)
        block("adsafetyproject\\.com", resourceTypes: allTypes)
        block("ad\\.twitter\\.com", resourceTypes: allTypes)
        block("ads\\.x\\.com", resourceTypes: allTypes)

        // MARK: Analytics & Tracking
        block("google-analytics\\.com", resourceTypes: scriptImageXHR)
        block("googletagmanager\\.com", resourceTypes: scriptImageXHR)
        block("scorecardresearch\\.com", resourceTypes: scriptImageXHR)
        block("hotjar\\.com", resourceTypes: scriptImageXHR)
        block("fullstory\\.com", resourceTypes: scriptImageXHR)
        block("chartbeat\\.com", resourceTypes: scriptImageXHR)
        block("quantserve\\.com", resourceTypes: scriptImageXHR)

        // MARK: X/Twitter Telemetry
        block("scribe\\.twitter\\.com", resourceTypes: ["xmlhttprequest", "image"])
        block("scribe\\.x\\.com", resourceTypes: ["xmlhttprequest", "image"])

        // MARK: Social Widgets (not core X functionality)
        block("platform\\.twitter\\.com", resourceTypes: ["script", "xmlhttprequest"])
        block("platform\\.x\\.com", resourceTypes: ["script", "xmlhttprequest"])
        block("syndication\\.twitter\\.com", resourceTypes: allTypes)

        // MARK: Third-party social plugins
        block("facebook\\.net", resourceTypes: ["script", "image", "xmlhttprequest"])
        block("fbcdn\\.net", resourceTypes: ["script", "image"])
        block("connect\\.facebook\\.net", resourceTypes: ["script", "image", "xmlhttprequest"])

        // MARK: Additional tracking & attribution
        block("branch\\.io", resourceTypes: allTypes)
        block("impactradius\\-go\\.com", resourceTypes: allTypes)
        block("impactradius\\-ad\\.com", resourceTypes: allTypes)

        // MARK: Content recommendation / ad networks
        block("taboola\\.com", resourceTypes: allTypes)
        block("outbrain\\.com", resourceTypes: allTypes)
        block("mgid\\.com", resourceTypes: allTypes)

        // MARK: Additional telemetry pixels
        block("p\\.twitter\\.com", resourceTypes: ["image", "xmlhttprequest"])
        block("p\\.x\\.com", resourceTypes: ["image", "xmlhttprequest"])

        // MARK: Video tracking & analytics
        block("video\\.twimg\\.com.*\\.json", resourceTypes: ["xmlhttprequest"])
        block("video\\.x\\.com.*\\.json", resourceTypes: ["xmlhttprequest"])

        // MARK: Image CDN tracking requests
        block("pbs\\.twimg\\.com.*profile_images", resourceTypes: ["xmlhttprequest"])
        block("pbs\\.twimg\\.com.*\\/img\\/.*\\?format=.*", resourceTypes: ["xmlhttprequest"])

        // MARK: Preload/prefetch resources (减少不必要的预加载)
        block("syndication\\.twimg\\.com", resourceTypes: ["raw", "xmlhttprequest"])
        block("abs\\.twimg\\.com", resourceTypes: ["raw"])

        // MARK: Additional third-party tracking
        block("bluekai\\.com", resourceTypes: allTypes)
        block("krxd\\.net", resourceTypes: allTypes)
        block("pingchartbeat\\.net", resourceTypes: ["image", "xmlhttprequest"])
        block("newrelic\\.com", resourceTypes: ["script", "xmlhttprequest"])
        block("nr-data\\.net", resourceTypes: ["xmlhttprequest"])

        // MARK: Push notification & notification related
        block("push\\.twitter\\.com", resourceTypes: ["xmlhttprequest"])
        block("push\\.x\\.com", resourceTypes: ["xmlhttprequest"])

        // MARK: CDN analytics (减少 CDN 层面的追踪)
        block("cdn\\.syndication\\.twimg\\.com", resourceTypes: ["xmlhttprequest"])
        block("ton\\.twimg\\.com.*\\/analytics", resourceTypes: ["xmlhttprequest"])

        // MARK: Embed widgets (外挂件，通常非核心功能)
        block("widgets\\.twitter\\.com", resourceTypes: ["script", "xmlhttprequest"])
        block("widgets\\.x\\.com", resourceTypes: ["script", "xmlhttprequest"])

        // MARK: Localization analytics (本地化追踪)
        block("loc\\.twimg\\.com", resourceTypes: ["xmlhttprequest"])

        guard let data = try? JSONSerialization.data(withJSONObject: rules, options: [.prettyPrinted, .sortedKeys]),
              let json = String(data: data, encoding: .utf8) else {
            return "[]"
        }
        return json
    }()
}
