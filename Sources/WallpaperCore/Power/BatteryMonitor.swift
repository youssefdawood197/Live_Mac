import Foundation
import CoreFoundation
import IOKit.ps

// MARK: - Power Source State

/// State of the primary power source powering the macOS host.
public enum PowerSourceState: String, Sendable, Equatable, CustomStringConvertible {
    case acPower = "AC Power"
    case batteryPower = "Battery Power"
    case unknown = "Unknown"

    public var description: String { rawValue }
}

// MARK: - Power Snapshot

/// Immutable telemetry snapshot representing battery hardware status and power profile.
public struct PowerSnapshot: Equatable, Sendable {
    public let powerSourceState: PowerSourceState
    public let isOnBattery: Bool
    public let isLowPowerMode: Bool
    public let currentCapacity: Int?
    public let maxCapacity: Int?
    public let isCharging: Bool?
    public let timeToEmptyMinutes: Int?

    public init(
        powerSourceState: PowerSourceState = .acPower,
        isOnBattery: Bool = false,
        isLowPowerMode: Bool = false,
        currentCapacity: Int? = nil,
        maxCapacity: Int? = nil,
        isCharging: Bool? = nil,
        timeToEmptyMinutes: Int? = nil
    ) {
        self.powerSourceState = powerSourceState
        self.isOnBattery = isOnBattery
        self.isLowPowerMode = isLowPowerMode
        self.currentCapacity = currentCapacity
        self.maxCapacity = maxCapacity
        self.isCharging = isCharging
        self.timeToEmptyMinutes = timeToEmptyMinutes
    }
}

// MARK: - Power Source Provider Protocol

/// Abstract hardware provider protocol supplying power state to `BatteryMonitor`.
@MainActor
public protocol PowerSourceProviderProtocol: AnyObject, Sendable {
    var isOnBattery: Bool { get }
    var isLowPowerMode: Bool { get }
    var currentState: PowerSourceState { get }
    var currentSnapshot: PowerSnapshot { get }

    func startMonitoring(onChange: @escaping @MainActor () -> Void)
    func stopMonitoring()
}

// MARK: - System Power Source Provider (IOKit & ProcessInfo)

/// Production hardware power provider querying Apple IOKit IOPowerSources and Foundation ProcessInfo.
/// Handles desktop Macs and CI VMs gracefully (empty power source list = AC Power).
@MainActor
public final class SystemPowerSourceProvider: PowerSourceProviderProtocol, @unchecked Sendable {
    private var runLoopSource: CFRunLoopSource?
    private var lowPowerObserver: (any NSObjectProtocol)?
    private var onChange: (@MainActor () -> Void)?

    public init() {}

    public var isOnBattery: Bool {
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue() else {
            return false
        }
        if let sourceType = IOPSGetProvidingPowerSourceType(snapshot)?.takeRetainedValue() as String?,
           sourceType == (kIOPSBatteryPowerValue as String) {
            return true
        }
        guard let sourcesList = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [CFTypeRef] else {
            return false
        }
        for ps in sourcesList {
            guard let desc = IOPSGetPowerSourceDescription(snapshot, ps)?.takeUnretainedValue() as? [String: Any] else {
                continue
            }
            if let state = desc[kIOPSPowerSourceStateKey as String] as? String,
               state == (kIOPSBatteryPowerValue as String) {
                return true
            }
        }
        return false
    }

    public var isLowPowerMode: Bool {
        ProcessInfo.processInfo.isLowPowerModeEnabled
    }

    public var currentState: PowerSourceState {
        isOnBattery ? .batteryPower : .acPower
    }

    public var currentSnapshot: PowerSnapshot {
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue() else {
            return PowerSnapshot(
                powerSourceState: .acPower,
                isOnBattery: false,
                isLowPowerMode: isLowPowerMode
            )
        }

        var sourceState: PowerSourceState = .acPower
        if let typeStr = IOPSGetProvidingPowerSourceType(snapshot)?.takeRetainedValue() as String? {
            if typeStr == (kIOPSBatteryPowerValue as String) {
                sourceState = .batteryPower
            }
        }

        var currentCap: Int?
        var maxCap: Int?
        var isCharging: Bool?
        var timeToEmpty: Int?

        if let sourcesList = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [CFTypeRef],
           let firstPS = sourcesList.first,
           let desc = IOPSGetPowerSourceDescription(snapshot, firstPS)?.takeUnretainedValue() as? [String: Any] {
            if let psState = desc[kIOPSPowerSourceStateKey as String] as? String {
                if psState == (kIOPSBatteryPowerValue as String) {
                    sourceState = .batteryPower
                } else if psState == (kIOPSACPowerValue as String) {
                    sourceState = .acPower
                }
            }
            currentCap = desc[kIOPSCurrentCapacityKey as String] as? Int
            maxCap = desc[kIOPSMaxCapacityKey as String] as? Int
            isCharging = desc[kIOPSIsChargingKey as String] as? Bool
            timeToEmpty = desc[kIOPSTimeToEmptyKey as String] as? Int
        }

        return PowerSnapshot(
            powerSourceState: sourceState,
            isOnBattery: sourceState == .batteryPower,
            isLowPowerMode: isLowPowerMode,
            currentCapacity: currentCap,
            maxCapacity: maxCap,
            isCharging: isCharging,
            timeToEmptyMinutes: timeToEmpty
        )
    }

    public func startMonitoring(onChange: @escaping @MainActor () -> Void) {
        self.onChange = onChange

        // 1. IOKit RunLoop source for battery and charger plug/unplug events
        let callback: IOPowerSourceCallbackType = { context in
            guard let context = context else { return }
            let provider = Unmanaged<SystemPowerSourceProvider>.fromOpaque(context).takeUnretainedValue()
            if Thread.isMainThread {
                MainActor.assumeIsolated { provider.notifyChange() }
            } else {
                Task { @MainActor in provider.notifyChange() }
            }
        }

        let context = Unmanaged.passUnretained(self).toOpaque()
        if let source = IOPSNotificationCreateRunLoopSource(callback, context)?.takeRetainedValue() {
            self.runLoopSource = source
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        }

        // 2. Low power mode observer
        lowPowerObserver = NotificationCenter.default.addObserver(
            forName: .NSProcessInfoPowerStateDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.notifyChange()
            }
        }
    }

    public func stopMonitoring() {
        if let source = runLoopSource {
            CFRunLoopSourceInvalidate(source)
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
            self.runLoopSource = nil
        }
        if let observer = lowPowerObserver {
            NotificationCenter.default.removeObserver(observer)
            lowPowerObserver = nil
        }
        self.onChange = nil
    }

    private func notifyChange() {
        onChange?()
    }

    isolated deinit {
        stopMonitoring()
    }
}

// MARK: - Mock Power Source Provider

/// Mock power provider enabling deterministic state injection in headless CI test suites.
@MainActor
public final class MockPowerSourceProvider: PowerSourceProviderProtocol, @unchecked Sendable {
    public var isOnBattery: Bool
    public var isLowPowerMode: Bool
    public var currentState: PowerSourceState {
        isOnBattery ? .batteryPower : .acPower
    }
    public var mockCapacity: Int? = 85
    public var mockMaxCapacity: Int? = 100
    public var mockIsCharging: Bool? = false
    public var mockTimeToEmpty: Int? = 180

    public private(set) var isMonitoring: Bool = false
    private var onChange: (@MainActor () -> Void)?

    public var currentSnapshot: PowerSnapshot {
        PowerSnapshot(
            powerSourceState: currentState,
            isOnBattery: isOnBattery,
            isLowPowerMode: isLowPowerMode,
            currentCapacity: mockCapacity,
            maxCapacity: mockMaxCapacity,
            isCharging: mockIsCharging,
            timeToEmptyMinutes: mockTimeToEmpty
        )
    }

    public init(isOnBattery: Bool = false, isLowPowerMode: Bool = false) {
        self.isOnBattery = isOnBattery
        self.isLowPowerMode = isLowPowerMode
    }

    public func startMonitoring(onChange: @escaping @MainActor () -> Void) {
        self.isMonitoring = true
        self.onChange = onChange
    }

    public func stopMonitoring() {
        self.isMonitoring = false
        self.onChange = nil
    }

    public func updatePowerState(
        isOnBattery: Bool? = nil,
        isLowPowerMode: Bool? = nil,
        isCharging: Bool? = nil
    ) {
        if let b = isOnBattery { self.isOnBattery = b }
        if let l = isLowPowerMode { self.isLowPowerMode = l }
        if let c = isCharging { self.mockIsCharging = c }
        onChange?()
    }
}

// MARK: - Battery Monitor Delegate & Protocol

@MainActor
public protocol BatteryMonitorDelegate: AnyObject {
    func batteryMonitorDidChangePowerState(_ monitor: BatteryMonitorProtocol)
}

@MainActor
public protocol BatteryMonitorProtocol: AnyObject {
    var delegate: BatteryMonitorDelegate? { get set }
    var isOnBattery: Bool { get }
    var isLowPowerMode: Bool { get }
    var isBatteryActive: Bool { get }
    var currentState: PowerSourceState { get }
    var currentSnapshot: PowerSnapshot { get }
    var isMonitoring: Bool { get }
    var onPowerStateChanged: (@MainActor (BatteryMonitorProtocol) -> Void)? { get set }

    func startMonitoring()
    func stopMonitoring()
}

// MARK: - BatteryMonitor

/// Manages observation of system battery and power source states.
@MainActor
public final class BatteryMonitor: BatteryMonitorProtocol {
    public weak var delegate: BatteryMonitorDelegate?
    public let provider: PowerSourceProviderProtocol

    public var isOnBattery: Bool { provider.isOnBattery }
    public var isLowPowerMode: Bool { provider.isLowPowerMode }
    public var isBatteryActive: Bool { provider.isOnBattery || provider.isLowPowerMode }
    public var currentState: PowerSourceState { provider.currentState }
    public var currentSnapshot: PowerSnapshot { provider.currentSnapshot }
    public private(set) var isMonitoring: Bool = false
    public var onPowerStateChanged: (@MainActor (BatteryMonitorProtocol) -> Void)?

    public init(provider: PowerSourceProviderProtocol = SystemPowerSourceProvider()) {
        self.provider = provider
    }

    public func startMonitoring() {
        guard !isMonitoring else { return }
        isMonitoring = true
        provider.startMonitoring { [weak self] in
            guard let self = self else { return }
            self.delegate?.batteryMonitorDidChangePowerState(self)
            self.onPowerStateChanged?(self)
        }
    }

    public func stopMonitoring() {
        guard isMonitoring else { return }
        isMonitoring = false
        provider.stopMonitoring()
    }

    isolated deinit {
        stopMonitoring()
    }
}

// MARK: - Mock Battery Monitor

/// Mock battery monitor for testing PowerManager in isolation.
@MainActor
public final class MockBatteryMonitor: BatteryMonitorProtocol {
    public weak var delegate: BatteryMonitorDelegate?
    public var isOnBattery: Bool = false
    public var isLowPowerMode: Bool = false
    public var isBatteryActive: Bool { isOnBattery || isLowPowerMode }
    public var currentState: PowerSourceState { isOnBattery ? .batteryPower : .acPower }
    public var currentSnapshot: PowerSnapshot {
        PowerSnapshot(
            powerSourceState: currentState,
            isOnBattery: isOnBattery,
            isLowPowerMode: isLowPowerMode,
            currentCapacity: 80,
            maxCapacity: 100,
            isCharging: false,
            timeToEmptyMinutes: 120
        )
    }
    public private(set) var isMonitoring: Bool = false
    public var onPowerStateChanged: (@MainActor (BatteryMonitorProtocol) -> Void)?

    public init(isOnBattery: Bool = false, isLowPowerMode: Bool = false) {
        self.isOnBattery = isOnBattery
        self.isLowPowerMode = isLowPowerMode
    }

    public func startMonitoring() {
        isMonitoring = true
    }

    public func stopMonitoring() {
        isMonitoring = false
    }

    public func setBatteryActive(_ active: Bool) {
        self.isOnBattery = active
        delegate?.batteryMonitorDidChangePowerState(self)
        onPowerStateChanged?(self)
    }

    public func setLowPowerMode(_ active: Bool) {
        self.isLowPowerMode = active
        delegate?.batteryMonitorDidChangePowerState(self)
        onPowerStateChanged?(self)
    }
}
