//
//  GeminiWebView.swift
//  GeminiDesktop
//
//  Created by alexcding on 2025-12-13.
//

import SwiftUI
import WebKit

struct GeminiWebView: NSViewRepresentable {
    let webView: WKWebView

    func makeNSView(context: Context) -> WebViewContainer {
        WebViewContainer(webView: webView)
    }

    func updateNSView(_ container: WebViewContainer, context: Context) {}
}

class WebViewContainer: NSView {
    let webView: WKWebView
    private var windowObserver: NSObjectProtocol?
    private let titlebarDragView = TitlebarDragView()
    private var preZoomFrame: NSRect?
    private var eventMonitor: Any?

    /// When true, hitTest skips the titlebar drag view so click events reach the WKWebView
    fileprivate var passThroughClick = false

    init(webView: WKWebView) {
        self.webView = webView
        super.init(frame: .zero)
        autoresizesSubviews = true
        wantsLayer = true
        layer?.drawsAsynchronously = true
        setupWindowObserver()
        setupDoubleClickMonitor()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        webView.removeFromSuperview()
        if let observer = windowObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
        }
    }

    private func setupWindowObserver() {
        windowObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didBecomeKeyNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self = self,
                  let keyWindow = notification.object as? NSWindow,
                  self.window === keyWindow else { return }
            self.attachWebView()
        }
    }

    private func setupDoubleClickMonitor() {
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
            guard let self = self, let window = self.window else { return event }
            guard event.window === window else { return event }
            guard event.clickCount >= 2 else { return event }

            let locationInView = self.convert(event.locationInWindow, from: nil)
            let titlebarHeight: CGFloat = 28
            guard locationInView.y >= self.bounds.height - titlebarHeight else { return event }

            self.handleTitlebarZoom()
            return nil // consume the event
        }
    }

    private func handleTitlebarZoom() {
        guard let window = window else { return }
        let targetFrame: NSRect
        if let saved = preZoomFrame {
            preZoomFrame = nil
            targetFrame = saved
        } else {
            guard let screen = window.screen else { return }
            preZoomFrame = window.frame
            targetFrame = screen.visibleFrame
        }
        window.setFrame(targetFrame, display: true, animate: true)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil && window?.isKeyWindow == true {
            attachWebView()
        }
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.modifierFlags.contains(.command) {
            let char = event.charactersIgnoringModifiers?.lowercased()
            let selector: Selector?
            switch char {
            case "v": selector = NSSelectorFromString("paste:")
            case "c": selector = NSSelectorFromString("copy:")
            case "x": selector = NSSelectorFromString("cut:")
            case "a": selector = NSSelectorFromString("selectAll:")
            default: selector = nil
            }
            if let selector = selector, webView.responds(to: selector) {
                webView.perform(selector, with: nil)
                return true
            }
        }
        return super.performKeyEquivalent(with: event)
    }

    override func layout() {
        super.layout()
        if webView.superview === self {
            webView.frame = bounds
        }
        let titlebarHeight: CGFloat = 28
        titlebarDragView.frame = NSRect(
            x: 0,
            y: bounds.height - titlebarHeight,
            width: bounds.width,
            height: titlebarHeight
        )
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let titlebarHeight: CGFloat = 28
        if point.y >= bounds.height - titlebarHeight {
            if passThroughClick {
                let converted = convert(point, to: webView)
                return webView.hitTest(converted)
            }
            return titlebarDragView
        }
        return super.hitTest(point)
    }

    private func attachWebView() {
        guard webView.superview !== self else { return }
        webView.removeFromSuperview()
        webView.frame = bounds
        webView.autoresizingMask = [.width, .height]
        // Do NOT set delegates here — WebViewModel owns them
        addSubview(webView)
        // Ensure titlebarDragView is on top
        titlebarDragView.removeFromSuperview()
        addSubview(titlebarDragView)
    }
}

private final class TitlebarDragView: NSView {

    override func mouseDown(with event: NSEvent) {
        guard let window = window else { return }

        // Track drag vs click
        let startMouse = NSEvent.mouseLocation
        let startOrigin = window.frame.origin
        let dragThreshold: CGFloat = 3.0
        var hasDragged = false

        while true {
            guard let next = window.nextEvent(
                matching: [.leftMouseDragged, .leftMouseUp],
                until: Date.distantFuture,
                inMode: .eventTracking,
                dequeue: true
            ) else { break }

            if next.type == .leftMouseDragged {
                let current = NSEvent.mouseLocation
                if !hasDragged {
                    if abs(current.x - startMouse.x) > dragThreshold ||
                       abs(current.y - startMouse.y) > dragThreshold {
                        hasDragged = true
                    }
                }
                if hasDragged {
                    window.setFrameOrigin(NSPoint(
                        x: startOrigin.x + current.x - startMouse.x,
                        y: startOrigin.y + current.y - startMouse.y
                    ))
                }
            } else if next.type == .leftMouseUp {
                if !hasDragged {
                    // Single click without drag — forward to the WKWebView underneath
                    forwardClick(downEvent: event, upEvent: next)
                }
                break
            }
        }
    }

    private func forwardClick(downEvent: NSEvent, upEvent: NSEvent) {
        guard let container = superview as? WebViewContainer,
              let window = window else { return }

        // Synthesize clean mouseDown + mouseUp pair
        guard let newDown = NSEvent.mouseEvent(
            with: .leftMouseDown,
            location: downEvent.locationInWindow,
            modifierFlags: downEvent.modifierFlags,
            timestamp: downEvent.timestamp,
            windowNumber: window.windowNumber,
            context: nil,
            eventNumber: downEvent.eventNumber,
            clickCount: downEvent.clickCount,
            pressure: 1.0
        ), let newUp = NSEvent.mouseEvent(
            with: .leftMouseUp,
            location: upEvent.locationInWindow,
            modifierFlags: upEvent.modifierFlags,
            timestamp: upEvent.timestamp,
            windowNumber: window.windowNumber,
            context: nil,
            eventNumber: upEvent.eventNumber,
            clickCount: upEvent.clickCount,
            pressure: 0.0
        ) else { return }

        // Enable passthrough so hitTest routes to WKWebView instead of us
        container.passThroughClick = true
        // postEvent(atStart: true) inserts at the FRONT of the queue.
        // To ensure newDown is processed before newUp, post newUp first,
        // then newDown — so the final queue order is [newDown, newUp, ...].
        // Wrong ordering causes WKWebView.mouseDown to enter a tracking loop
        // waiting for a mouseUp that was already consumed → deadlock / freeze.
        window.postEvent(newUp, atStart: true)
        window.postEvent(newDown, atStart: true)
        // Reset flag after events are processed (use asyncAfter for safety margin)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            container.passThroughClick = false
        }
    }
}
