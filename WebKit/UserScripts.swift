//
//  UserScripts.swift
//  GeminiDesktop
//
//  Created by alexcding on 2025-12-15.
//

import WebKit

/// Collection of user scripts injected into WKWebView
enum UserScripts {

    /// Message handler name for console log bridging
    static let consoleLogHandler = "consoleLog"

    /// Creates all user scripts to be injected into the WebView
    static func createAllScripts() -> [WKUserScript] {
        var scripts: [WKUserScript] = [
            createErrorCatchScript(),
            createCSSOptimizationScript(),
            createPromotedTweetHiderScript(),
            createVideoPauseScript(),
            createIMEFixScript(),
            createImageLazyLoadScript()
        ]

        #if DEBUG
        scripts.insert(createConsoleLogBridgeScript(), at: 0)
        #endif

        return scripts
    }

    /// Creates a script that bridges console.log to native Swift
    private static func createConsoleLogBridgeScript() -> WKUserScript {
        WKUserScript(
            source: consoleLogBridgeSource,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: false
        )
    }

    /// Creates the IME fix script that resolves the double-enter issue
    /// when using input method editors (e.g., Chinese, Japanese, Korean input)
    private static func createIMEFixScript() -> WKUserScript {
        WKUserScript(
            source: imeFixSource,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: true
        )
    }

    /// Creates a script that captures all JS errors and logs them
    private static func createErrorCatchScript() -> WKUserScript {
        WKUserScript(
            source: errorCatchSource,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: false
        )
    }

    // MARK: - Script Sources

    /// JavaScript to capture errors
    private static let errorCatchSource = """
    (function() {
        window.onerror = function(msg, url, line, col, error) {
            console.log('[JS ERROR] ' + msg + ' at ' + url + ':' + line + ':' + col);
        };
        window.addEventListener('unhandledrejection', function(e) {
            console.log('[JS PROMISE] ' + e.reason);
        });
    })();
    """

    /// JavaScript to bridge console.log to native Swift via WKScriptMessageHandler
    private static let consoleLogBridgeSource = """
    (function() {
        const originalLog = console.log;
        console.log = function(...args) {
            originalLog.apply(console, args);
            try {
                const message = args.map(arg => {
                    if (typeof arg === 'object') {
                        return JSON.stringify(arg, null, 2);
                    }
                    return String(arg);
                }).join(' ');
                window.webkit.messageHandlers.\(consoleLogHandler).postMessage(message);
            } catch (e) {}
        };
    })();
    """

    /// CSS to hide heavy DOM elements on x.com for better performance
    private static let cssOptimizationSource = """
    (function() {
        var style = document.createElement('style');
        style.textContent = [
            '/* Hide footer */',
            '[role="contentinfo"] { display: none !important; }',
            '',
            '/* Hide cookie/banner toasts */',
            '[data-testid="toast"] { display: none !important; }'
        ].join('\\n');
        document.documentElement.appendChild(style);
    })();
    """

    /// JavaScript MutationObserver to hide promoted tweets from timeline.
    /// Uses WeakSet to track checked articles and only processes addedNodes,
    /// avoiding expensive full-scan on every DOM mutation.
    private static let promotedTweetHiderSource = """
    (function() {
        'use strict';

        var checked = new WeakSet();

        function checkArticle(article) {
            if (checked.has(article)) return;
            checked.add(article);
            var spans = article.querySelectorAll('span');
            for (var j = 0; j < spans.length; j++) {
                var text = spans[j].textContent;
                if (text === 'Promoted' || text === 'Ad' || text === '\\u5e7f\\u544a') {
                    article.style.display = 'none';
                    break;
                }
            }
        }

        function checkNode(node) {
            if (!node || node.nodeType !== Node.ELEMENT_NODE) return;
            if (node.matches && node.matches('article[data-testid="tweet"]')) {
                checkArticle(node);
            }
            if (node.querySelectorAll) {
                var articles = node.querySelectorAll('article[data-testid="tweet"]');
                for (var k = 0; k < articles.length; k++) {
                    checkArticle(articles[k]);
                }
            }
        }

        function startObserver() {
            var main = document.querySelector('[data-testid="primaryColumn"]');
            if (!main) return;
            var observer = new MutationObserver(function(mutations) {
                for (var i = 0; i < mutations.length; i++) {
                    var added = mutations[i].addedNodes;
                    for (var j = 0; j < added.length; j++) {
                        checkNode(added[j]);
                    }
                }
            });
            observer.observe(main, { childList: true, subtree: true });
            var existing = main.querySelectorAll('article[data-testid="tweet"]');
            for (var i = 0; i < existing.length; i++) {
                checkArticle(existing[i]);
            }
        }

        if (document.querySelector('[data-testid="primaryColumn"]')) {
            startObserver();
        } else {
            var bodyObs = new MutationObserver(function() {
                if (document.querySelector('[data-testid="primaryColumn"]')) {
                    bodyObs.disconnect();
                    startObserver();
                }
            });
            bodyObs.observe(document.body, { childList: true, subtree: true });
        }
    })();
    """

    /// JavaScript to pause videos when they leave the viewport.
    /// Simple strategy: videos don't auto-play (controlled by WebKit),
    /// and we pause them when they scroll out of view to save resources.
    private static let videoPauseSource = """
    (function() {
        'use strict';

        function isInViewport(el) {
            if (!el || !el.parentElement) return false;
            var rect = el.getBoundingClientRect();
            var h = window.innerHeight || 800;
            return rect.bottom > 0 && rect.top < h;
        }

        function checkVideo(video) {
            if (!isInViewport(video)) {
                if (!video.paused) {
                    video.pause();
                }
            }
        }

        function register(video) {
            if (video._registered) return;
            video._registered = true;
            video.pause();
        }

        function scan() {
            var videos = document.querySelectorAll('video');
            for (var i = 0; i < videos.length; i++) {
                register(videos[i]);
                checkVideo(videos[i]);
            }
        }

        var observer = new MutationObserver(function() {
            scan();
        });

        window.addEventListener('scroll', function() {
            scan();
        }, true);

        setInterval(scan, 1000);

        function init() {
            if (document.body) {
                observer.observe(document.body, { childList: true, subtree: true });
                scan();
            }
        }

        if (document.body) {
            init();
        } else {
            var wait = new MutationObserver(function() {
                if (document.body) {
                    wait.disconnect();
                    init();
                }
            });
            wait.observe(document.documentElement, { childList: true });
        }
    })();
    """

    /// Creates the video pause script
    private static func createVideoPauseScript() -> WKUserScript {
        WKUserScript(
            source: videoPauseSource,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: true
        )
    }

    /// JavaScript to fix IME Enter issue
    /// When using IME (e.g., Chinese/Japanese input), pressing Enter to confirm
    /// the IME composition should NOT send the message. This script intercepts
    /// Enter keydown events during and immediately after IME composition,
    /// preventing them from reaching the send handler.
    private static let imeFixSource = """
    (function() {
        'use strict';

        let imeActive = false;
        let imeEverUsed = false;
        let compositionEndTime = 0;
        const BUFFER_TIME = 300;

        function isInIMEWindow() {
            return imeActive || (Date.now() - compositionEndTime < BUFFER_TIME);
        }

        document.addEventListener('compositionstart', function() {
            imeActive = true;
            imeEverUsed = true;
        }, true);

        document.addEventListener('compositionend', function() {
            imeActive = false;
            compositionEndTime = Date.now();
        }, true);

        document.addEventListener('keydown', function(e) {
            if (!imeEverUsed) return;
            if (e.key !== 'Enter' || e.shiftKey || e.ctrlKey || e.altKey) return;

            if (isInIMEWindow() || e.isComposing || e.keyCode === 229) {
                e.stopImmediatePropagation();
                e.preventDefault();
            }
        }, true);

        document.addEventListener('beforeinput', function(e) {
            if (!imeEverUsed) return;
            if (e.inputType !== 'insertParagraph' && e.inputType !== 'insertLineBreak') return;

            if (isInIMEWindow()) {
                e.stopImmediatePropagation();
                e.preventDefault();
            }
        }, true);
    })();
    """

    /// JavaScript to lazy load images outside viewport.
    /// Uses IntersectionObserver to delay loading images until they enter viewport.
    /// Excludes small images (likely avatars/icons) and critical UI elements.
    private static let imageLazyLoadSource = """
    (function() {
        'use strict';

        // 延迟启动，避免 SPA 导航时过早处理
        var ready = false;
        setTimeout(function() { ready = true; }, 1500);

        // 透明 placeholder (1x1 pixel)
        var placeholder = 'data:image/gif;base64,R0lGODlhAQABAIAAAAAAAP///yH5BAEAAAAALAAAAAABAAEAAAIBRAA7';

        // 最小图片尺寸阈值（小于此尺寸的可能是头像/图标，不延迟加载）
        var MIN_SIZE = 50;

        var observer = new IntersectionObserver(function(entries) {
            for (var i = 0; i < entries.length; i++) {
                var entry = entries[i];
                var img = entry.target;
                if (entry.isIntersecting && img.dataset._lazySrc) {
                    img.src = img.dataset._lazySrc;
                    delete img.dataset._lazySrc;
                    img.dataset._lazyLoaded = '1';
                    observer.unobserve(img);
                }
            }
        }, { rootMargin: '100px 0px', threshold: 0.01 });

        function shouldLazyLoad(img) {
            // 已加载或已有 data-src 则跳过
            if (img.dataset._lazyLoaded || img.dataset._lazySrc) return false;
            // 空 src 或 placeholder 跳过
            if (!img.src || img.src === placeholder) return false;
            // 小图片（头像/图标）不延迟
            var rect = img.getBoundingClientRect();
            if (rect.width < MIN_SIZE || rect.height < MIN_SIZE) return false;
            // 排除 profile 图片（通常是头像）
            if (img.alt && img.alt.toLowerCase().indexOf('profile') !== -1) return false;
            // 排除 SVG 和非 twimg 域名的图片
            if (img.src.indexOf('.svg') !== -1) return false;
            if (img.src.indexOf('twimg.com') === -1 && img.src.indexOf('pbs.') === -1) return false;
            return true;
        }

        function processImage(img) {
            if (!shouldLazyLoad(img)) return;
            img.dataset._lazySrc = img.src;
            img.src = placeholder;
            observer.observe(img);
        }

        function processNode(node) {
            if (!node || node.nodeType !== Node.ELEMENT_NODE) return;
            if (node.tagName === 'IMG') processImage(node);
            var imgs = node.querySelectorAll ? node.querySelectorAll('img') : [];
            for (var i = 0; i < imgs.length; i++) {
                processImage(imgs[i]);
            }
        }

        var domObserver = new MutationObserver(function(mutations) {
            if (!ready) return;
            for (var i = 0; i < mutations.length; i++) {
                var added = mutations[i].addedNodes;
                for (var j = 0; j < added.length; j++) {
                    processNode(added[j]);
                }
            }
        });

        domObserver.observe(document.body, { childList: true, subtree: true });

        // 延迟处理已存在的图片
        setTimeout(function() {
            if (!ready) return;
            var imgs = document.querySelectorAll('img');
            for (var i = 0; i < imgs.length; i++) {
                processImage(imgs[i]);
            }
        }, 2000);
    })();
    """

    /// Creates the CSS optimization script injected at document start
    private static func createCSSOptimizationScript() -> WKUserScript {
        WKUserScript(
            source: cssOptimizationSource,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true
        )
    }

    /// Creates the promoted tweet hider script injected at document end
    private static func createPromotedTweetHiderScript() -> WKUserScript {
        WKUserScript(
            source: promotedTweetHiderSource,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: true
        )
    }

    /// Creates the image lazy load script injected at document end
    private static func createImageLazyLoadScript() -> WKUserScript {
        WKUserScript(
            source: imageLazyLoadSource,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: true
        )
    }
}
