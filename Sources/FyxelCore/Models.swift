import Foundation

// Typed read-only views over the router's JSON. Each keeps `raw` so writes can round-trip
// the original object and the UI can show the full record.

public struct SystemStatus: Sendable {
    public var model, firmware, serial, hostName, lastRebootCause, firstUse: String
    public var uptime: TimeInterval
    public var rebootCount: Int
    public var cpu: Int
    public var memTotalKB, memFreeKB: Int
    public var firewallEnabled: Bool
    public var firewallLevel: String
    public var wan: [WanInterface]
    public var lanPorts: [EthernetPort]
    public var wifi: [SSIDSummary]
    public var raw: JSONValue

    public init(_ j: JSONValue) {
        let d = j["DeviceInfo"], s = j["SystemInfo"], f = j["FirewallInfo"]
        model = d["ModelName"].str
        firmware = d["SoftwareVersion"].str
        serial = d["SerialNumber"].str
        lastRebootCause = d["X_ZYXEL_LastRebootCause"].str
        firstUse = d["FirstUseDate"].str
        uptime = TimeInterval(d["UpTime"].int ?? 0)
        rebootCount = d["X_ZYXEL_RebootCount"].int ?? 0
        hostName = s["HostName"].str
        cpu = s["CPUUsage"].int ?? 0
        memTotalKB = s["Total"].int ?? 0
        memFreeKB = s["Free"].int ?? 0
        firewallEnabled = f["Enable"].bool
        firewallLevel = f["X_ZYXEL_DefaultConfig"].str
        wan = j["WanLanInfo"].array.map(WanInterface.init).filter { $0.type == "WAN" }
        lanPorts = j["LanPortInfo"].array.map(EthernetPort.init)
        wifi = j["WiFiInfo"].array.map(SSIDSummary.init)
        raw = j
    }

    public var activeWan: WanInterface? { wan.first { $0.isUp && $0.defaultGateway } ?? wan.first { $0.isUp } }
}

public struct WanInterface: Sendable, Identifiable {
    public var id: String { ipIfacePath }
    public var ipIfacePath, name, serviceName, type, encapsulation, linkType, status, ifName, mac: String
    public var ipv4, mask, gateway: String
    public var dns: [String]
    public var ipv6: [String]
    public var uptime: TimeInterval
    public var defaultGateway: Bool
    public var isUp: Bool { status == "Up" }

    public init(_ j: JSONValue) {
        ipIfacePath = j["IpIfacePath"].str
        name = j["Name"].str
        serviceName = j["X_ZYXEL_SrvName"].str
        type = j["X_ZYXEL_Type"].str
        encapsulation = j["Encapsulation"].str
        linkType = j["LinkType"].str
        status = j["Status"].string ?? j["pppConnectionStatus"].str
        ifName = j["X_ZYXEL_IfName"].str
        mac = j["MACAddress"].str
        let a = j["IPv4Address"][0]
        ipv4 = a["IPAddress"].str
        mask = a["SubnetMask"].str
        gateway = j["v4Gateway"].str
        dns = j["dnsv4Server"].array.flatMap { $0["DNSServer"].str.split(separator: ",").map(String.init) }
        ipv6 = j["IPv6Address"].array.compactMap { $0["IPAddress"].string }
        uptime = TimeInterval(j["ipoeConnectionUpTime"].int ?? j["pppoeConnectionUpTime"].int ?? 0)
        defaultGateway = j["X_ZYXEL_DefaultGatewayIface"].bool
    }
}

public struct EthernetPort: Sendable, Identifiable {
    public var id: String { name }
    public var name, label, status, duplex, mac: String
    public var bitRate: Int
    public var isUp: Bool { status == "Up" }

    public init(_ j: JSONValue) {
        name = j["Name"].str
        label = j["X_ZYXEL_LanPort"].string ?? j["Name"].str
        status = j["Status"].str
        duplex = j["DuplexMode"].str
        mac = j["MACAddress"].str
        bitRate = j["CurrentBitRate"].int ?? 0
    }
}

public struct SSIDSummary: Sendable, Identifiable {
    public var id: String { path }
    public var path, ssid, band, bandwidth, standards, rate, security: String
    public var channel: Int
    public var enabled, main, hidden, autoChannel: Bool

    public init(_ j: JSONValue) {
        path = j["IntfPath"].str
        ssid = j["SSID"].str
        band = j["OperatingFrequencyBand"].str
        bandwidth = j["OperatingChannelBandwidth"].str
        standards = j["OperatingStandards"].str
        rate = j["X_ZYXEL_Rate"].str
        security = j["ModeEnabled"].str
        channel = j["Channel"].int ?? 0
        enabled = j["Enable"].bool
        main = j["X_ZYXEL_MainSSID"].bool
        hidden = j["wlHideEnable"].bool
        autoChannel = j["AutoChannelEnable"].bool
    }
}

public struct LanHost: Sendable, Identifiable, Hashable {
    public var id: String { mac }
    public var mac, ip, ipv6, hostName, deviceName, vendor, connection, interfaceType, ap, ssid, addressSource, os, icon: String
    public var reservedIP: String
    public var active, blocked: Bool
    public var rssi, snr, phyRateMbps: Int?
    public var standard: String
    public var uptime, leaseRemaining: TimeInterval
    public var bytesSent, bytesReceived: Int64
    public var raw: JSONValue

    public init(_ j: JSONValue) {
        mac = j["PhysAddress"].str.lowercased()
        ip = j["IPAddress"].str
        ipv6 = j["IPAddress6"].str
        hostName = j["HostName"].str
        deviceName = j["DeviceName"].str
        vendor = j["X_ZYXEL_InterfaceBrand"].str.trimmingCharacters(in: .whitespacesAndNewlines)
        connection = j["X_ZYXEL_ConnectionType"].str
        interfaceType = j["InterfaceType"].str
        ap = j["X_ZYXEL_ConnectedAP"].str
        ssid = j["WiFiname"].str
        addressSource = j["AddressSource"].str
        os = j["X_ZYXEL_OperatingSystem"].str
        icon = j["icon"].str
        reservedIP = j["dhcp4StaticAddrExist"].bool ? j["dhcp4StaticAddr"].str : ""
        active = j["Active"].bool
        blocked = j["Internet_Blocking_Enable"].bool
        let isWifi = interfaceType == "Wi-Fi" || j["X_ZYXEL_WiFiStatus"].bool
        rssi = isWifi ? j["X_ZYXEL_RSSI"].int : nil
        snr = isWifi ? j["X_ZYXEL_SNR"].int : nil
        phyRateMbps = j["X_ZYXEL_PhyRate"].int.flatMap { $0 > 0 ? $0 : nil }
        standard = j["X_ZYXEL_OperatingStandard"].str
        uptime = TimeInterval(j["X_ZYXEL_UpTime"].int ?? 0)
        leaseRemaining = TimeInterval(j["LeaseTimeRemaining"].int ?? 0)
        bytesSent = j["X_ZYXEL_BytesSent"].int64 ?? 0
        bytesReceived = j["X_ZYXEL_BytesReceived"].int64 ?? 0
        raw = j
    }

    /// Best human name: user-set name, then DHCP hostname, then vendor.
    public var displayName: String {
        for n in [deviceName, hostName] where !n.isEmpty && n != "Unknown" { return n }
        return vendor.isEmpty ? mac : vendor
    }
    public var isWifi: Bool { rssi != nil }
}

public struct DHCPReservation: Sendable, Identifiable, Hashable {
    public var id: Int { index }
    public var index: Int
    public var mac, ip, brWan: String
    public var enabled: Bool
    public var raw: JSONValue

    public init(_ j: JSONValue) {
        index = j["Index"].int ?? 0
        mac = j["MACAddr"].str.lowercased()
        ip = j["IPAddr"].str
        brWan = j["BrWan"].str
        enabled = j["Enable"].bool
        raw = j
    }
}

public struct UPnPMapping: Sendable, Identifiable, Hashable {
    public var id: String { "\(proto)/\(externalPort)/\(destination)" }
    public var proto, destination, description: String
    public var externalPort, internalPort: Int
    public var enabled: Bool

    public init(_ j: JSONValue) {
        proto = j["Protocol"].str
        destination = j["Destination"].str
        description = j["Description"].str
        externalPort = j["ExternalPort"].int ?? 0
        internalPort = j["InternalPort"].int ?? 0
        enabled = j["Enable"].bool
    }
}

public struct InterfaceCounters: Sendable {
    public var name, ifName, status: String
    public var defaultGateway: Bool
    public var bytesSent, bytesReceived: Int64
}

public struct TrafficSnapshot: Sendable {
    public var at: Date
    public var interfaces: [InterfaceCounters]
    public var hostBytes: [String: (sent: Int64, received: Int64)]
    public var customNames: [String: String]   // mac -> user-set name

    public init(_ j: JSONValue, at: Date = Date()) {
        self.at = at
        let ifs = j["ipIface"].array, st = j["ipIfaceSt"].array
        interfaces = zip(ifs, st).map { i, s in
            InterfaceCounters(name: i["Name"].str, ifName: i["X_ZYXEL_IfName"].str, status: i["Status"].str,
                              defaultGateway: i["X_ZYXEL_DefaultGatewayIface"].bool,
                              bytesSent: s["BytesSent"].int64 ?? 0, bytesReceived: s["BytesReceived"].int64 ?? 0)
        }
        var hb: [String: (Int64, Int64)] = [:]
        for h in j["hosts"].array {
            hb[h["PhysAddress"].str.lowercased()] = (h["X_ZYXEL_BytesSent"].int64 ?? 0, h["X_ZYXEL_BytesReceived"].int64 ?? 0)
        }
        hostBytes = hb
        var names: [String: String] = [:]
        for c in j["changeIconName"].array where !c["HostName"].str.isEmpty {
            names[c["MacAddress"].str.lowercased()] = c["HostName"].str
        }
        customNames = names
    }

    public var wan: InterfaceCounters? {
        interfaces.first { $0.defaultGateway && $0.status == "Up" }
    }
}
