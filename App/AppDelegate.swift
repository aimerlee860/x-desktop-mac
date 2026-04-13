//
//  AppDelegate.swift
//  GeminiDesktop
//

import AppKit
import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate {
    var coordinator = AppCoordinator()
    var mainWindow: NSWindow?
    var settingsWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSLog("[XDesktop] applicationDidFinishLaunching called")

        // Main window
        let mainWindowView = MainWindowView(coordinator: coordinator)
        let hostingView = NSHostingView(rootView: mainWindowView)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1000, height: 700),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = AppCoordinator.Constants.mainWindowTitle
        window.titlebarAppearsTransparent = true
        window.styleMask.insert(.fullSizeContentView)
        window.titleVisibility = .hidden
        if #available(macOS 11.0, *) {
            window.titlebarSeparatorStyle = .none
        }
        window.contentView = hostingView
        window.minSize = NSSize(width: 1250, height: 750)
        window.delegate = self
        window.center()
        window.setFrameAutosaveName("MainWindow")
        NSLog("[XDesktop] Window created, frame: \(window.frame)")
        window.makeKeyAndOrderFront(nil)
        NSLog("[XDesktop] Window visible: \(window.isVisible)")
        mainWindow = window

        setupMenu()

        // 窗口最小化 → 立即暂停媒体，恢复时 → 恢复播放
        NotificationCenter.default.addObserver(
            forName: NSWindow.didMiniaturizeNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            self?.coordinator.webViewModel.suspendForBackground()
        }

        NotificationCenter.default.addObserver(
            forName: NSWindow.didDeminiaturizeNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            self?.coordinator.webViewModel.resumeFromBackground()
        }

        // Observe open main window notification
        NotificationCenter.default.addObserver(
            forName: .openMainWindow,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.openMainWindow()
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        NotificationCenter.default.post(name: .openMainWindow, object: nil)
        return true
    }

    // MARK: - Menu

    private func setupMenu() {
        let mainMenu = NSMenu()

        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu(title: "X")
        appMenu.addItem(withTitle: "About X", action: #selector(showAboutPanel), keyEquivalent: "")
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(withTitle: "Quit X", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)

        NSApplication.shared.mainMenu = mainMenu
    }

    @objc private func showAboutPanel() {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
        NSApp.orderFrontStandardAboutPanel(options: [
            .applicationName: "X",
            .applicationVersion: "Version \(version)"
        ])
    }

    // MARK: - Windows

    func applicationWillTerminate(_ notification: Notification) {
        coordinator.webViewModel.cleanup()
        NotificationCenter.default.removeObserver(self)
    }

    func openMainWindow() {
        mainWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func openSettings() {
        if let window = settingsWindow {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let settingsView = SettingsView(coordinator: coordinator)
        let hostingView = NSHostingView(rootView: settingsView)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 700, height: 600),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Settings"
        window.contentView = hostingView
        window.center()
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.makeKeyAndOrderFront(nil)
        settingsWindow = window
        NSApp.activate(ignoringOtherApps: true)
    }
}

// MARK: - NSWindowDelegate for settings

extension AppDelegate: NSWindowDelegate {
    func windowWillResize(_ sender: NSWindow, to frameSize: NSSize) -> NSSize {
        let minSize = NSSize(width: 1250, height: 750)
        return NSSize(
            width: max(frameSize.width, minSize.width),
            height: max(frameSize.height, minSize.height)
        )
    }

    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        if window == settingsWindow {
            settingsWindow = nil
        }
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        if sender == mainWindow {
            NSApp.terminate(nil)
            return false
        }
        return true
    }
}
