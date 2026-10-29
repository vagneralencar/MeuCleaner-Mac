import Foundation
import AppKit
import Darwin
import IOKit.ps

public struct RunningAppMemoryItem: Identifiable, Sendable {
    public let id: pid_t
    public let name: String
    public let bundleIdentifier: String?
    public let memoryBytes: Int64
    public let icon: NSImage?
}

@MainActor
public final class SystemMonitorService: ObservableObject {
    @Published public var cpuUsagePercent: Double = 12.0
    @Published public var memoryUsedBytes: Int64 = 0
    @Published public var memoryTotalBytes: Int64 = Int64(ProcessInfo.processInfo.physicalMemory)
    @Published public var diskFreeBytes: Int64 = 0
    @Published public var diskTotalBytes: Int64 = 0
    @Published public var batteryPercent: Int = 100
    @Published public var isCharging: Bool = false
    @Published public var networkDownBytesPerSec: Int64 = 0
    @Published public var networkUpBytesPerSec: Int64 = 0
    @Published public var topMemoryApps: [RunningAppMemoryItem] = []

    private var timer: Timer?
    private var prevNetInBytes: UInt64 = 0
    private var prevNetOutBytes: UInt64 = 0
    private var prevTimestamp: TimeInterval = Date().timeIntervalSince1970
    private var prevCPUInfo: processor_info_array_t?
    private var prevCPUInfoCount: mach_msg_type_number_t = 0

    public init() {
        refreshAll()
        startMonitoring()
    }

    public func startMonitoring() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refreshAll()
            }
        }
    }

    public func refreshAll() {
        updateDiskUsage()
        updateMemoryUsage()
        updateCPUUsage()
        updateBatteryStatus()
        updateNetworkThroughput()
        updateTopMemoryApps()
    }

    public var memoryPressurePercent: Double {
        guard memoryTotalBytes > 0 else { return 0 }
        return min(100, max(0, (Double(memoryUsedBytes) / Double(memoryTotalBytes)) * 100.0))
    }

    public var diskUsedBytes: Int64 {
        max(0, diskTotalBytes - diskFreeBytes)
    }

    public var diskUsedPercent: Double {
        guard diskTotalBytes > 0 else { return 0 }
        return min(100, max(0, (Double(diskUsedBytes) / Double(diskTotalBytes)) * 100.0))
    }

    private func updateDiskUsage() {
        let homeURL = FileManager.default.homeDirectoryForCurrentUser
        do {
            let values = try homeURL.resourceValues(forKeys: [
                .volumeTotalCapacityKey,
                .volumeAvailableCapacityForImportantUsageKey,
                .volumeAvailableCapacityKey
            ])
            if let total = values.volumeTotalCapacity {
                diskTotalBytes = Int64(total)
            }
            if let availImportant = values.volumeAvailableCapacityForImportantUsage {
                diskFreeBytes = availImportant
            } else if let avail = values.volumeAvailableCapacity {
                diskFreeBytes = Int64(avail)
            }
        } catch {
            // Keep existing values if reading fails
        }
    }

    private func updateMemoryUsage() {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
        let hostPort = mach_host_self()
        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(hostPort, HOST_VM_INFO64, $0, &count)
            }
        }
        if result == KERN_SUCCESS {
            let pageSize = Int64(vm_kernel_page_size)
            let active = Int64(stats.active_count) * pageSize
            let wired = Int64(stats.wire_count) * pageSize
            let compressed = Int64(stats.compressor_page_count) * pageSize
            memoryUsedBytes = active + wired + compressed
        }
    }

    private func updateCPUUsage() {
        var numCPUsU: natural_t = 0
        var cpuInfo: processor_info_array_t?
        var numCPUInfo: mach_msg_type_number_t = 0

        let result = host_processor_info(
            mach_host_self(),
            PROCESSOR_CPU_LOAD_INFO,
            &numCPUsU,
            &cpuInfo,
            &numCPUInfo
        )
        guard result == KERN_SUCCESS, let info = cpuInfo else { return }

        var totalUser: Int64 = 0
        var totalSystem: Int64 = 0
        var totalIdle: Int64 = 0
        var totalNice: Int64 = 0

        for i in 0..<Int(numCPUsU) {
            let offset = Int(CPU_STATE_MAX) * i
            if let prev = prevCPUInfo {
                totalUser += Int64(info[offset + Int(CPU_STATE_USER)] - prev[offset + Int(CPU_STATE_USER)])
                totalSystem += Int64(info[offset + Int(CPU_STATE_SYSTEM)] - prev[offset + Int(CPU_STATE_SYSTEM)])
                totalIdle += Int64(info[offset + Int(CPU_STATE_IDLE)] - prev[offset + Int(CPU_STATE_IDLE)])
                totalNice += Int64(info[offset + Int(CPU_STATE_NICE)] - prev[offset + Int(CPU_STATE_NICE)])
            } else {
                totalUser += Int64(info[offset + Int(CPU_STATE_USER)])
                totalSystem += Int64(info[offset + Int(CPU_STATE_SYSTEM)])
                totalIdle += Int64(info[offset + Int(CPU_STATE_IDLE)])
                totalNice += Int64(info[offset + Int(CPU_STATE_NICE)])
            }
        }

        if let prev = prevCPUInfo {
            let prevSize = vm_size_t(prevCPUInfoCount) * vm_size_t(MemoryLayout<integer_t>.stride)
            vm_deallocate(mach_task_self_, vm_address_t(bitPattern: prev), prevSize)
        }

        prevCPUInfo = info
        prevCPUInfoCount = numCPUInfo

        let totalTicks = totalUser + totalSystem + totalIdle + totalNice
        if totalTicks > 0 {
            let busy = Double(totalUser + totalSystem + totalNice)
            cpuUsagePercent = min(100.0, max(0.0, (busy / Double(totalTicks)) * 100.0))
        }
    }

    private func updateBatteryStatus() {
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [CFTypeRef],
              let first = sources.first,
              let desc = IOPSGetPowerSourceDescription(snapshot, first)?.takeUnretainedValue() as? [String: Any] else {
            return
        }
        if let capacity = desc[kIOPSCurrentCapacityKey as String] as? Int {
            batteryPercent = capacity
        }
        if let state = desc[kIOPSPowerSourceStateKey as String] as? String {
            isCharging = (state == kIOPSACPowerValue)
        }
    }

    private func updateNetworkThroughput() {
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let firstAddr = ifaddr else { return }
        defer { freeifaddrs(ifaddr) }

        var totalIn: UInt64 = 0
        var totalOut: UInt64 = 0

        var ptr: UnsafeMutablePointer<ifaddrs>? = firstAddr
        while let current = ptr {
            let name = String(cString: current.pointee.ifa_name)
            if name.hasPrefix("en"),
               let addr = current.pointee.ifa_addr,
               addr.pointee.sa_family == UInt8(AF_LINK),
               let data = current.pointee.ifa_data?.assumingMemoryBound(to: if_data.self) {
                totalIn += UInt64(data.pointee.ifi_ibytes)
                totalOut += UInt64(data.pointee.ifi_obytes)
            }
            ptr = current.pointee.ifa_next
        }

        let now = Date().timeIntervalSince1970
        let elapsed = max(0.5, now - prevTimestamp)
        if prevNetInBytes > 0 && totalIn >= prevNetInBytes {
            networkDownBytesPerSec = Int64(Double(totalIn - prevNetInBytes) / elapsed)
        }
        if prevNetOutBytes > 0 && totalOut >= prevNetOutBytes {
            networkUpBytesPerSec = Int64(Double(totalOut - prevNetOutBytes) / elapsed)
        }
        prevNetInBytes = totalIn
        prevNetOutBytes = totalOut
        prevTimestamp = now
    }

    /// Bundle IDs that should never be offered as quittable memory hogs (matching CleanerCore.MemoryHogs.protectedBundleIDs)
    public static let protectedBundleIDs: Set<String> = [
        "com.apple.finder",
        "com.apple.dock",
        "com.apple.loginwindow",
        "com.apple.systemuiserver",
        "com.apple.controlcenter",
        "com.apple.WindowManager",
        "com.apple.notificationcenterui",
        "dev.vagner.MeuCleaner"
    ]

    private func updateTopMemoryApps() {
        let ownPID = ProcessInfo.processInfo.processIdentifier
        let workspaceApps = NSWorkspace.shared.runningApplications.filter { app in
            guard app.activationPolicy == .regular,
                  app.processIdentifier > 0,
                  app.processIdentifier != ownPID else {
                return false
            }
            if let bid = app.bundleIdentifier, Self.protectedBundleIDs.contains(bid) {
                return false
            }
            return true
        }

        var items: [RunningAppMemoryItem] = []
        for app in workspaceApps {
            let pid = app.processIdentifier
            var usage = rusage_info_v4()
            let res = withUnsafeMutablePointer(to: &usage) { usagePtr in
                usagePtr.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { reboundPtr in
                    proc_pid_rusage(pid, RUSAGE_INFO_V4, reboundPtr)
                }
            }
            let footprint: Int64
            if res == 0 {
                footprint = Int64(usage.ri_phys_footprint)
            } else {
                footprint = 0
            }
            if footprint > 0 {
                items.append(
                    RunningAppMemoryItem(
                        id: pid,
                        name: app.localizedName ?? "App",
                        bundleIdentifier: app.bundleIdentifier,
                        memoryBytes: footprint,
                        icon: app.icon
                    )
                )
            }
        }
        topMemoryApps = items.sorted { $0.memoryBytes > $1.memoryBytes }.prefix(6).map { $0 }
    }

    public func terminateApp(pid: pid_t) {
        if let app = NSWorkspace.shared.runningApplications.first(where: { $0.processIdentifier == pid }) {
            app.terminate()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
                self?.updateTopMemoryApps()
            }
        }
    }
}
