//
//  WebViewModel.swift
//  GeminiDesktop
//
//  Created by alexcding on 2025-12-15.
//

import WebKit
import Combine
import AppKit

/// Handles console.log messages from JavaScript
class ConsoleLogHandler: NSObject, WKScriptMessageHandler {
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        if let body = message.body as? String {
            print("[WebView Console] \(body)")
        }
    }
}

/// Observable wrapper around WKWebView with X-specific functionality
class WebViewModel: NSObject, ObservableObject, WKNavigationDelegate, WKUIDelegate {

    // MARK: - Constants

    static let xURL = URL(string: "https://x.com/home")!

    private static let xHost = "x.com"
    private static let userAgent: String = UserAgent.chrome
    private static let sharedProcessPool = WKProcessPool()

    // MARK: - Public Properties

    let wkWebView: WKWebView
    @Published private(set) var canGoBack: Bool = false
    @Published private(set) var canGoForward: Bool = false
    @Published private(set) var isAtHome: Bool = true
    @Published private(set) var isLoading: Bool = true

    // MARK: - Private Properties

    private var backObserver: NSKeyValueObservation?
    private var forwardObserver: NSKeyValueObservation?
    private var urlObserver: NSKeyValueObservation?
    private var loadingObserver: NSKeyValueObservation?
    private var titleObserver: NSKeyValueObservation?
    private let consoleLogHandler = ConsoleLogHandler()
    private var popupWindow: NSWindow?
    private var popupURLObserver: NSKeyValueObservation?
    private var popupWindowCloseObserver: NSObjectProtocol?
    private var isCleanedUp = false
    private var memoryPressureSource: DispatchSourceMemoryPressure?
    private var resignActiveObserver: NSObjectProtocol?
    private var becomeActiveObserver: NSObjectProtocol?
    private var backgroundSuspendTimer: Timer?

    // MARK: - Initialization

    override init() {
        self.wkWebView = Self.createWebView(consoleLogHandler: consoleLogHandler)
        super.init()
        wkWebView.navigationDelegate = self
        wkWebView.uiDelegate = self
        setupObservers()
        setupMemoryPressureHandling()
        setupBackgroundHandling()
        loadHome()
    }

    deinit {
        cleanup()
    }

    // MARK: - Navigation

    func loadHome() {
        isAtHome = true
        canGoBack = false
        #if DEBUG
        print("[WebView] Loading: \(Self.xURL)")
        #endif
        wkWebView.load(URLRequest(url: Self.xURL))
    }

    func goBack() {
        isAtHome = false
        wkWebView.goBack()
    }

    func goForward() {
        wkWebView.goForward()
    }

    func reload() {
        wkWebView.reload()
    }

    // MARK: - WKNavigationDelegate

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        #if DEBUG
        print("[WebView] Started provisional nav: \(webView.url?.absoluteString ?? "nil")")
        #endif
    }

    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        #if DEBUG
        print("[WebView] Committed: \(webView.url?.absoluteString ?? "nil")")
        #endif
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        #if DEBUG
        print("[WebView] Finished: \(webView.url?.absoluteString ?? "nil")")
        #endif
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        print("[WebView] Nav failed: \(error.localizedDescription)")
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        print("[WebView] Provisional nav failed: \(error.localizedDescription)")
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = navigationAction.request.url else {
            decisionHandler(.allow)
            return
        }

        let host = url.host ?? ""
        let isMainFrame = navigationAction.targetFrame?.isMainFrame == true

        #if DEBUG
        print("[WebView] Policy: \(isMainFrame ? "main" : "sub") \(url.absoluteString.prefix(120))")
        #endif

        // Intercept Google OAuth in main frame of the MAIN webview only
        if webView === wkWebView && isMainFrame && host.hasSuffix("accounts.google.com") {
            let currentHost = webView.url?.host ?? ""
            if currentHost == Self.xHost || currentHost == "www.\(Self.xHost)" {
                #if DEBUG
                print("[WebView] Intercepting Google OAuth → popup")
                #endif
                let popupWebView = createOAuthPopup()
                popupWebView.load(URLRequest(url: url))
                decisionHandler(.cancel)
                return
            }
        }

        decisionHandler(.allow)
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse, decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
        if navigationResponse.canShowMIMEType {
            decisionHandler(.allow)
        } else {
            print("[WebView] Blocked non-renderable content: \(navigationResponse.response.mimeType ?? "unknown")")
            decisionHandler(.cancel)
        }
    }

    // MARK: - WKUIDelegate

    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        #if DEBUG
        print("[WebView] window.open: \(navigationAction.request.url?.absoluteString.prefix(100) ?? "nil")")
        #endif
        if let url = navigationAction.request.url {
            let host = url.host ?? ""
            if host.hasSuffix("google.com") || host.hasSuffix("googleapis.com") {
                // Return a real WKWebView so WebKit preserves window.opener relationship
                return createOAuthPopup(using: configuration)
            } else if isExternalURL(url) {
                NSWorkspace.shared.open(url)
            } else {
                webView.load(URLRequest(url: url))
            }
        }
        return nil
    }

    func webViewDidClose(_ webView: WKWebView) {
        popupWindow?.close()
    }

    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) {
        let alert = NSAlert()
        alert.messageText = message
        alert.addButton(withTitle: "OK")
        alert.runModal()
        completionHandler()
    }

    func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (Bool) -> Void) {
        let alert = NSAlert()
        alert.messageText = message
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")
        completionHandler(alert.runModal() == .alertFirstButtonReturn)
    }

    func webView(_ webView: WKWebView, runJavaScriptTextInputPanelWithPrompt prompt: String, defaultText: String?, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (String?) -> Void) {
        let alert = NSAlert()
        alert.messageText = prompt
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")

        let textField = NSTextField(frame: NSRect(x: 0, y: 0, width: 200, height: 24))
        textField.stringValue = defaultText ?? ""
        alert.accessoryView = textField

        completionHandler(alert.runModal() == .alertFirstButtonReturn ? textField.stringValue : nil)
    }

    func webView(_ webView: WKWebView, requestMediaCapturePermissionFor origin: WKSecurityOrigin, initiatedByFrame frame: WKFrameInfo, type: WKMediaCaptureType, decisionHandler: @escaping (WKPermissionDecision) -> Void) {
        decisionHandler(origin.host.contains("x.com") ? .grant : .prompt)
    }

    func webView(_ webView: WKWebView, runOpenPanelWith parameters: WKOpenPanelParameters, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping ([URL]?) -> Void) {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = parameters.allowsMultipleSelection
        panel.canChooseDirectories = parameters.allowsDirectories
        panel.canChooseFiles = true
        NSApp.activate(ignoringOtherApps: true)
        panel.begin { response in
            completionHandler(response == .OK ? panel.urls : nil)
        }
    }

    // MARK: - OAuth Popup

    /// Creates a popup WKWebView for OAuth flows.
    /// - Parameter configuration: Optional configuration from `createWebViewWith`. If nil, a default one is created.
    /// - Returns: The popup WKWebView. When called from `createWebViewWith`, WebKit will load the URL automatically.
    private func createOAuthPopup(using configuration: WKWebViewConfiguration? = nil) -> WKWebView {
        // Clean up previous popup observers
        cleanupPopupObservers()
        popupWindow?.close()

        let config = configuration ?? WKWebViewConfiguration()
        // Share cookie store and process pool with main webView
        config.websiteDataStore = wkWebView.configuration.websiteDataStore
        config.processPool = wkWebView.configuration.processPool
        config.defaultWebpagePreferences.allowsContentJavaScript = true

        let popupWebView = WKWebView(frame: .zero, configuration: config)
        popupWebView.customUserAgent = Self.userAgent
        popupWebView.navigationDelegate = self
        popupWebView.uiDelegate = self

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 640),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Sign In"
        window.contentView = popupWebView
        window.center()
        window.makeKeyAndOrderFront(nil)
        popupWindow = window

        popupURLObserver = popupWebView.observe(\.url, options: .new) { [weak self] pv, _ in
            guard let popupURL = pv.url else { return }
            let host = popupURL.host ?? ""
            #if DEBUG
            print("[Popup] URL: \(popupURL.absoluteString.prefix(120))")
            #endif

            if (host == Self.xHost || host == "www.\(Self.xHost)")
                && !popupURL.path.hasPrefix("/i/flow/login") {
                #if DEBUG
                print("[Popup] Auth complete → reloading main")
                #endif
                DispatchQueue.main.async {
                    window.close()
                    self?.popupWindow = nil
                    self?.wkWebView.load(URLRequest(url: Self.xURL))
                }
            }
        }

        popupWindowCloseObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            self?.cleanupPopupObservers()
            if self?.popupWindow === window {
                self?.popupWindow = nil
            }
        }

        return popupWebView
    }

    // MARK: - Helpers

    private func isExternalURL(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        let internalHosts = ["x.com", "www.x.com", "twimg.com", "t.co",
                             "google.com", "www.google.com", "accounts.google.com",
                             "gstatic.com", "googleapis.com", "googleusercontent.com"]
        for item in internalHosts {
            if host == item || host.hasSuffix(".\(item)") { return false }
        }
        return true
    }

    // MARK: - Private Setup

    private static func createWebView(consoleLogHandler: ConsoleLogHandler) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        configuration.processPool = sharedProcessPool
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        // 禁用所有媒体自动播放，需要用户点击才能播放
        configuration.mediaTypesRequiringUserActionForPlayback = .all

        let preferences = WKPreferences()
        if #available(macOS 12.3, *) {
            preferences.isElementFullscreenEnabled = true
        }
        configuration.preferences = preferences

        for script in UserScripts.createAllScripts() {
            configuration.userContentController.addUserScript(script)
        }

        #if DEBUG
        configuration.userContentController.add(consoleLogHandler, name: UserScripts.consoleLogHandler)
        #endif

        // Compile content blocking rules before WKWebView is created
        ContentBlocker.compile(into: configuration.userContentController)

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.allowsBackForwardNavigationGestures = true
        webView.allowsLinkPreview = true
        webView.customUserAgent = userAgent

        return webView
    }

    private func setupObservers() {
        backObserver = wkWebView.observe(\.canGoBack, options: [.new, .initial]) { [weak self] webView, _ in
            guard let self = self else { return }
            self.canGoBack = !self.isAtHome && webView.canGoBack
        }

        forwardObserver = wkWebView.observe(\.canGoForward, options: [.new, .initial]) { [weak self] webView, _ in
            guard let self = self else { return }
            self.canGoForward = webView.canGoForward
        }

        loadingObserver = wkWebView.observe(\.isLoading, options: [.new, .initial]) { [weak self] webView, _ in
            self?.isLoading = webView.isLoading
        }

        urlObserver = wkWebView.observe(\.url, options: .new) { [weak self] webView, _ in
            guard let self = self else { return }
            guard let currentURL = webView.url else { return }

            #if DEBUG
            print("[WebView] URL changed: \(currentURL)")
            #endif

            let isXApp = currentURL.host == Self.xHost ||
                         currentURL.host == "www.\(Self.xHost)"

            if isXApp {
                self.isAtHome = true
                self.canGoBack = false
            } else {
                self.isAtHome = false
                self.canGoBack = webView.canGoBack
            }
        }

        titleObserver = wkWebView.observe(\.title, options: .new) { webView, _ in
            #if DEBUG
            if let title = webView.title, !title.isEmpty {
                print("[WebView] Title: \(title)")
            }
            #endif
        }
    }

    // MARK: - Cleanup

    func cleanup() {
        guard !isCleanedUp else { return }
        isCleanedUp = true

        // 1. 停止摄像头和麦克风捕获（立即释放硬件设备）
        if #available(macOS 12.0, *) {
            if wkWebView.cameraCaptureState != .none {
                wkWebView.setCameraCaptureState(.none) { }
            }
            if wkWebView.microphoneCaptureState != .none {
                wkWebView.setMicrophoneCaptureState(.none) { }
            }
        }

        // 2. 关闭所有媒体展示（画中画、全屏视频等）
        if #available(macOS 11.3, *) {
            wkWebView.closeAllMediaPresentations { }
        }

        // 3. 注入 JS 停止所有媒体轨道和 WebRTC 连接
        let stopMediaJS = """
        (function() {
            try {
                document.querySelectorAll('video, audio').forEach(function(el) {
                    el.pause();
                    if (el.srcObject && el.srcObject.getTracks) {
                        el.srcObject.getTracks().forEach(function(t) { t.stop(); });
                    }
                    el.removeAttribute('src');
                    el.srcObject = null;
                    el.load();
                });
            } catch(e) {}
        })();
        """
        wkWebView.evaluateJavaScript(stopMediaJS)

        // 4. 关闭 OAuth popup 窗口
        cleanupPopupObservers()
        popupWindow?.close()
        popupWindow = nil

        // 5. 停止加载并清空页面
        wkWebView.stopLoading()
        wkWebView.loadHTMLString("", baseURL: nil)

        // 6. 移除代理，防止回调到已释放的对象
        wkWebView.navigationDelegate = nil
        wkWebView.uiDelegate = nil

        // 7. 移除 script message handler（仅在 DEBUG 下注册了）
        #if DEBUG
        wkWebView.configuration.userContentController.removeScriptMessageHandler(forName: UserScripts.consoleLogHandler)
        #endif

        // 8. 清理 KVO observers
        backObserver?.invalidate(); backObserver = nil
        forwardObserver?.invalidate(); forwardObserver = nil
        urlObserver?.invalidate(); urlObserver = nil
        loadingObserver?.invalidate(); loadingObserver = nil
        titleObserver?.invalidate(); titleObserver = nil

        // 9. 停止内存压力监听和定时器
        memoryPressureSource?.cancel(); memoryPressureSource = nil
        backgroundSuspendTimer?.invalidate(); backgroundSuspendTimer = nil

        // 10. 移除后台节流观察者
        if let obs = resignActiveObserver {
            NotificationCenter.default.removeObserver(obs)
            resignActiveObserver = nil
        }
        if let obs = becomeActiveObserver {
            NotificationCenter.default.removeObserver(obs)
            becomeActiveObserver = nil
        }

        // 11. 移除内容拦截规则
        ContentBlocker.remove()

        // 12. 从视图层级中移除，释放 GPU 渲染资源
        wkWebView.removeFromSuperview()
    }

    // MARK: - Memory Management

    private func setupMemoryPressureHandling() {
        memoryPressureSource = DispatchSource.makeMemoryPressureSource(
            eventMask: [.warning, .critical],
            queue: .main
        )
        memoryPressureSource?.setEventHandler { [weak self] in
            self?.handleMemoryPressure()
        }
        memoryPressureSource?.resume()
    }

    private func handleMemoryPressure() {
        print("[WebView] Memory pressure detected, clearing caches")
        let types: Set<String> = [
            WKWebsiteDataTypeDiskCache,
            WKWebsiteDataTypeMemoryCache,
            WKWebsiteDataTypeOfflineWebApplicationCache
        ]
        WKWebsiteDataStore.default().removeData(
            ofTypes: types,
            modifiedSince: Date.distantPast,
            completionHandler: {}
        )
        URLCache.shared.removeAllCachedResponses()
    }

    // MARK: - Background Handling

    private func setupBackgroundHandling() {
        resignActiveObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            // 立即暂停，不需要延迟
            self?.backgroundSuspendTimer?.invalidate()
            self?.suspendForBackground()
        }

        becomeActiveObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.backgroundSuspendTimer?.invalidate()
            self?.backgroundSuspendTimer = nil
            self?.resumeFromBackground()
        }
    }

    func suspendForBackground() {
        guard !isCleanedUp else { return }

        // 关闭画中画、全屏视频等媒体展示
        if #available(macOS 11.3, *) {
            wkWebView.closeAllMediaPresentations { }
        }

        // 通过 JS 暂停所有媒体（视频和 GIF）
        // 使用与 singleMediaPlaybackSource 相同的暂停逻辑
        let js = """
        (function() {
            // 暂停所有视频
            var videos = document.querySelectorAll('video');
            for (var i = 0; i < videos.length; i++) {
                if (!videos[i].paused) {
                    videos[i].pause();
                    videos[i].dataset._bgPaused = '1';
                }
            }
            // 暂停所有 GIF（替换为静态图）
            var imgs = document.querySelectorAll('img');
            for (var i = 0; i < imgs.length; i++) {
                var img = imgs[i];
                if (img.src && (img.src.indexOf('format=gif') !== -1 || img.src.match(/\\.gif($|\\?)/i))) {
                    if (!img.dataset._gifSrc) {
                        img.dataset._gifSrc = img.src;
                        img.dataset._bgPaused = '1';
                        img.src = img.src.replace('format=gif', 'format=jpg');
                    }
                }
            }
        })();
        """
        wkWebView.evaluateJavaScript(js)
    }

    func resumeFromBackground() {
        guard !isCleanedUp else { return }

        // 恢复因后台挂起而暂停的媒体
        // 注意：恢复后需要等待新的检测周期来决定是否播放
        let js = """
        (function() {
            // 清除后台暂停标记，让脚本重新检测
            var videos = document.querySelectorAll('video');
            for (var i = 0; i < videos.length; i++) {
                delete videos[i].dataset._bgPaused;
            }
            var imgs = document.querySelectorAll('img');
            for (var i = 0; i < imgs.length; i++) {
                delete imgs[i].dataset._bgPaused;
            }
            // 不立即恢复播放，让 singleMediaPlayback 脚本的检测周期来决定
            // 该脚本会在 500ms 后检查中央区域并决定是否播放
        })();
        """
        wkWebView.evaluateJavaScript(js)
    }

    private func cleanupPopupObservers() {
        popupURLObserver?.invalidate()
        popupURLObserver = nil
        if let obs = popupWindowCloseObserver {
            NotificationCenter.default.removeObserver(obs)
            popupWindowCloseObserver = nil
        }
    }
}
