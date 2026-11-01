import Foundation
import FyxelCore

// A fictional home network. Everything here is made up: IPs come from the documentation
// ranges (203.0.113.0/24, 2001:db8::/32), MACs use locally-administered prefixes, and names
// are invented. Used by `MockRouter` for demos, tests and README screenshots.

struct MockDevice {
    var name: String
    var vendor: String
    var mac: String
    var ip: String
    var link: Link
    var icon: String
    var os: String = ""
    var active = true
    var reserved = false
    var uptime: Int = 3600 * 5
    /// Typical throughput in bytes/s (down, up); the mock varies it over time.
    var rate: (down: Double, up: Double) = (2_000, 500)

    enum Link { case wired(port: Int), wifi(ssidIndex: Int, rssi: Int, phy: Int, std: String) }
}

enum Fixtures {
    static let routerIP = "192.168.1.1"
    static let publicIP = "203.0.113.42"
    static let gateway = "203.0.113.1"

    static let devices: [MockDevice] = [
        .init(name: "Studio MacBook Pro", vendor: "Apple", mac: "a2:4f:01:10:22:31", ip: "192.168.1.23",
              link: .wifi(ssidIndex: 5, rssi: -47, phy: 2401, std: "ax"), icon: "ipc", os: "macOS", rate: (900_000, 120_000)),
        .init(name: "Office iMac", vendor: "Apple", mac: "a2:4f:01:10:22:9c", ip: "192.168.1.24",
              link: .wired(port: 1), icon: "ipc", os: "macOS", rate: (250_000, 40_000)),
        .init(name: "NAS", vendor: "Synology", mac: "02:11:32:aa:01:07", ip: "192.168.1.10",
              link: .wired(port: 2), icon: "iserver", os: "Linux", reserved: true, uptime: 86400 * 41, rate: (60_000, 1_400_000)),
        .init(name: "Home Server", vendor: "ASRock", mac: "02:7a:c3:00:41:20", ip: "192.168.1.20",
              link: .wired(port: 3), icon: "iserver", os: "Linux", reserved: true, uptime: 86400 * 41, rate: (180_000, 310_000)),
        .init(name: "Pi-hole", vendor: "Raspberry Pi", mac: "02:d8:3a:5b:00:05", ip: "192.168.1.5",
              link: .wired(port: 3), icon: "iserver", os: "Linux", reserved: true, uptime: 86400 * 41, rate: (8_000, 6_000)),
        .init(name: "Living Room TV", vendor: "LG Electronics", mac: "02:64:95:7e:10:aa", ip: "192.168.1.41",
              link: .wired(port: 4), icon: "itv", rate: (2_600_000, 30_000)),
        .init(name: "PlayStation 5", vendor: "Sony", mac: "02:5c:f3:21:9a:0b", ip: "192.168.1.42",
              link: .wired(port: 4), icon: "igame", active: false, uptime: 0),
        .init(name: "Alex's iPhone", vendor: "Apple", mac: "a2:4f:01:7d:3e:58", ip: "192.168.1.61",
              link: .wifi(ssidIndex: 5, rssi: -58, phy: 1200, std: "ax"), icon: "iphone", os: "iOS", rate: (35_000, 9_000)),
        .init(name: "Sam's Pixel", vendor: "Google", mac: "02:3e:e1:c4:91:11", ip: "192.168.1.62",
              link: .wifi(ssidIndex: 5, rssi: -63, phy: 866, std: "ax"), icon: "iphone", os: "Android", rate: (120_000, 15_000)),
        .init(name: "iPad", vendor: "Apple", mac: "a2:4f:01:66:aa:0e", ip: "192.168.1.63",
              link: .wifi(ssidIndex: 5, rssi: -71, phy: 433, std: "ac"), icon: "itablet", os: "iPadOS", active: false, uptime: 0),
        .init(name: "Work Laptop", vendor: "Dell", mac: "02:e4:b9:12:6f:30", ip: "192.168.1.64",
              link: .wifi(ssidIndex: 5, rssi: -55, phy: 1201, std: "ax"), icon: "ipc", os: "Windows", rate: (420_000, 260_000)),
        .init(name: "Kindle", vendor: "Amazon", mac: "02:fc:65:0a:bb:21", ip: "192.168.1.65",
              link: .wifi(ssidIndex: 1, rssi: -66, phy: 72, std: "n"), icon: "itablet", active: false, uptime: 0),
        .init(name: "Printer", vendor: "HP", mac: "02:9c:b6:54:1d:80", ip: "192.168.1.30",
              link: .wifi(ssidIndex: 3, rssi: -61, phy: 72, std: "n"), icon: "iprinter", reserved: true, rate: (200, 100)),
        .init(name: "Thermostat", vendor: "Nest Labs", mac: "02:18:b4:30:72:5e", ip: "192.168.1.71",
              link: .wifi(ssidIndex: 3, rssi: -69, phy: 65, std: "n"), icon: "iiot", rate: (400, 300)),
        .init(name: "Hue Bridge", vendor: "Signify", mac: "02:17:88:6a:01:fe", ip: "192.168.1.72",
              link: .wired(port: 2), icon: "iiot", rate: (600, 500)),
        .init(name: "Doorbell", vendor: "Ring", mac: "02:b0:09:da:44:12", ip: "192.168.1.73",
              link: .wifi(ssidIndex: 3, rssi: -74, phy: 58, std: "n"), icon: "icamera", rate: (3_000, 95_000)),
        .init(name: "Robot Vacuum", vendor: "Roborock", mac: "02:50:ec:50:8f:99", ip: "192.168.1.74",
              link: .wifi(ssidIndex: 3, rssi: -67, phy: 65, std: "n"), icon: "iiot", rate: (300, 200)),
        .init(name: "Kitchen Speaker", vendor: "Sonos", mac: "02:5a:a8:61:20:0c", ip: "192.168.1.75",
              link: .wifi(ssidIndex: 1, rssi: -59, phy: 144, std: "n"), icon: "ispeaker", rate: (40_000, 1_000)),
        .init(name: "Visitor's Phone", vendor: "Samsung", mac: "02:a8:7b:91:5c:33", ip: "192.168.1.150",
              link: .wifi(ssidIndex: 6, rssi: -64, phy: 573, std: "ax"), icon: "iphone", os: "Android", rate: (60_000, 8_000)),
    ]

    // MARK: Wi-Fi

    struct SSID { var index: Int; var name: String; var enabled: Bool; var main: Bool; var guest: Bool; var psk: String }
    static let ssids: [SSID] = [
        .init(index: 1, name: "Northwind", enabled: true, main: true, guest: false, psk: "orbit-lantern-quiet-42"),
        .init(index: 2, name: "Northwind Guest", enabled: true, main: false, guest: true, psk: "welcome-guest-2024"),
        .init(index: 3, name: "Northwind IoT", enabled: true, main: false, guest: false, psk: "iot-devices-only-77"),
        .init(index: 4, name: "Zyxel_4", enabled: false, main: false, guest: false, psk: "unused-ssid-four"),
        .init(index: 5, name: "Northwind", enabled: true, main: true, guest: false, psk: "orbit-lantern-quiet-42"),
        .init(index: 6, name: "Northwind Guest", enabled: true, main: false, guest: true, psk: "welcome-guest-2024"),
        .init(index: 7, name: "Zyxel_7", enabled: false, main: false, guest: false, psk: "unused-ssid-seven"),
        .init(index: 8, name: "Zyxel_8", enabled: false, main: false, guest: false, psk: "unused-ssid-eight"),
        .init(index: 9, name: "Zyxel_9", enabled: false, main: false, guest: false, psk: "unused-ssid-nine"),
        .init(index: 10, name: "Zyxel_10", enabled: false, main: false, guest: false, psk: "unused-ssid-ten"),
    ]

    static func bssid(_ i: Int) -> String { String(format: "02:00:5e:10:%02x:%02x", i <= 4 ? 0x24 : 0x50, i) }

    static func wlan() -> [JSONValue] {
        ssids.map { s in
            let is24 = s.index <= 4
            return [
                "Index": .int(Int64(s.index)), "SSID": .string(s.name), "wlEnable": .bool(s.enabled),
                "MainSSID": .bool(s.main), "wlHide": false, "band": is24 ? "2.4GHz" : "5GHz",
                "radioenable": true, "SecurityMode": "WPA3-Personal-Transition", "ModesSupported": "None,WPA2-Personal,WPA3-Personal,WPA3-Personal-Transition",
                "AutoGenPSK": false, "AutoGenPSKValue": "", "PskDisplay": .string(s.psk),
                "X_ZYXEL_BssIdIsolation": .bool(s.guest), "IsolationEnable": .bool(s.guest),
                "BSSID": .string(s.enabled ? bssid(s.index) : "00:00:00:00:00:00"),
                "AutoChannelEnable": .bool(!is24), "channel": is24 ? 6 : 44,
                "bandwidth": is24 ? "20MHz" : "80MHz", "extcha": 0, "X_ZYXEL_OBSS_coex": .bool(is24),
                "PossibleChannels": is24 ? "1,2,3,4,5,6,7,8,9,10,11,12,13" : "36,40,44,48,52,56,60,64,100,104,108,112,116,120,124,128,132,136,140",
                "OperatingStandards": is24 ? "b,g,n,ax" : "a,n,ac,ax", "SupportedStandards": is24 ? "b,g,n,ax" : "a,n,ac,ax",
                "oneSsidEnable": false, "oneSsidEnable_ori": false, "MaxAssociatedDevices": 32,
                "upRate": 0, "downRate": 0, "X_ZYXEL_Multicast_Fwd": true, "wlpmf": "capable", "encryp": "aes",
                "RekeyingInterval": 3600, "X_ZYXEL_Preauth": false, "X_ZYXEL_ReauthInterval": 0,
                "RadiusServerIPAddr": "", "RadiusServerPort": 1812, "RadiusSecret": "", "RadiusAccountingPort": 1813,
                "X_ZYXEL_SSIDSuffix": "", "X_ZYXEL_Attribute": 0,
            ]
        }
    }

    // MARK: Hosts

    static func ssidName(_ i: Int) -> String { ssids.first { $0.index == i }?.name ?? "" }

    static func lanhost(_ d: MockDevice, uptimeOffset: Int) -> JSONValue {
        var o: JSONValue = [
            "PhysAddress": .string(d.mac), "IPAddress": .string(d.active ? d.ip : ""), "IPAddress6": "",
            "HostName": .string(d.name.replacingOccurrences(of: " ", with: "-").replacingOccurrences(of: "'", with: "")),
            "DeviceName": .string(d.name), "curHostName": .string(d.name), "X_ZYXEL_InterfaceBrand": .string(d.vendor),
            "X_ZYXEL_OperatingSystem": .string(d.os), "icon": .string(d.icon), "DeviceIcon": .string(d.icon),
            "Active": .bool(d.active), "Internet_Blocking_Enable": false, "AddressSource": "DHCP",
            "dhcp4StaticAddrExist": .bool(d.reserved), "dhcp4StaticAddr": .string(d.reserved ? d.ip : ""),
            "X_ZYXEL_UpTime": .int(Int64(d.active ? d.uptime + uptimeOffset : 0)),
            "LeaseTimeRemaining": .int(Int64(d.active ? 86400 - (d.uptime + uptimeOffset) % 86400 : 0)),
            "X_ZYXEL_BytesSent": 0, "X_ZYXEL_BytesReceived": 0,
        ]
        switch d.link {
        case .wired(let port):
            o["InterfaceType"] = "Ethernet"
            o["X_ZYXEL_ConnectionType"] = .string("LAN\(port)")
            o["Layer1Interface"] = .string("Device.Ethernet.Interface.\(port)")
            o["X_ZYXEL_WiFiStatus"] = false
            o["X_ZYXEL_PhyRate"] = 1000
        case .wifi(let idx, let rssi, let phy, let std):
            o["InterfaceType"] = "Wi-Fi"
            o["X_ZYXEL_ConnectionType"] = .string(idx <= 4 ? "802.11 2.4GHz" : "802.11 5GHz")
            o["Layer1Interface"] = .string("Device.WiFi.SSID.\(idx)")
            o["WiFiname"] = .string(ssidName(idx))
            o["X_ZYXEL_WiFiStatus"] = .bool(d.active)
            o["X_ZYXEL_RSSI"] = .int(Int64(rssi))
            o["X_ZYXEL_SNR"] = .int(Int64(rssi + 95))
            o["X_ZYXEL_PhyRate"] = .int(Int64(phy))
            o["X_ZYXEL_OperatingStandard"] = .string(std)
            o["X_ZYXEL_ConnectedAP"] = "Router"
        }
        return o
    }

    // MARK: Status

    static func status(uptime: Int, cpu: Int, freeKB: Int, wanUptime: Int) -> JSONValue {
        let lanPorts: [JSONValue] = (1...4).map { p in
            let up = p != 4 || true
            return ["Name": .string("eth0.\(p)"), "X_ZYXEL_LanPort": .string("LAN\(p)"), "Status": up ? "Up" : "NoLink",
                    "DuplexMode": "Full", "MACAddress": "02:00:5e:00:00:01", "CurrentBitRate": p == 2 ? 2500 : 1000]
        }
        let wifi: [JSONValue] = ssids.filter { $0.index == 1 || $0.index == 5 || $0.enabled }.map { s in
            let is24 = s.index <= 4
            return ["IntfPath": .string("WiFi.SSID.\(s.index)"), "SSID": .string(s.name),
                    "OperatingFrequencyBand": is24 ? "2.4GHz" : "5GHz", "OperatingChannelBandwidth": is24 ? "20MHz" : "80MHz",
                    "OperatingStandards": is24 ? "b,g,n,ax" : "a,n,ac,ax", "X_ZYXEL_Rate": is24 ? "574Mbps" : "4804Mbps",
                    "ModeEnabled": "WPA3-Personal-Transition", "Channel": is24 ? 6 : 44, "Enable": .bool(s.enabled),
                    "X_ZYXEL_MainSSID": .bool(s.main), "wlHideEnable": false, "AutoChannelEnable": .bool(!is24)]
        }
        let wan: [JSONValue] = [
            ["IpIfacePath": "IP.Interface.4", "Name": "WAN", "X_ZYXEL_SrvName": "ETH_Internet", "X_ZYXEL_Type": "WAN",
             "Encapsulation": "IPoE", "LinkType": "ETH", "Status": "Up", "X_ZYXEL_IfName": "eth1.3",
             "MACAddress": "02:00:5e:00:00:02", "IPv4Address": [["IPAddress": .string(publicIP), "SubnetMask": "255.255.255.0"]],
             "v4Gateway": .string(gateway), "dnsv4Server": [["DNSServer": "9.9.9.9,149.112.112.112"]],
             "IPv6Address": [["IPAddress": "2001:db8:4a1c::1"]], "ipoeConnectionUpTime": .int(Int64(wanUptime)),
             "X_ZYXEL_DefaultGatewayIface": true],
            ["IpIfacePath": "IP.Interface.2", "Name": "WAN", "X_ZYXEL_SrvName": "IPTV", "X_ZYXEL_Type": "WAN",
             "Encapsulation": "IPoE", "LinkType": "ETH", "Status": "Up", "X_ZYXEL_IfName": "eth1.4",
             "IPv4Address": [["IPAddress": "10.20.30.40", "SubnetMask": "255.255.240.0"]], "v4Gateway": "10.20.16.1",
             "X_ZYXEL_DefaultGatewayIface": false],
            ["IpIfacePath": "IP.Interface.3", "Name": "WWAN", "X_ZYXEL_SrvName": "WWAN", "X_ZYXEL_Type": "WAN",
             "Encapsulation": "IPoE", "LinkType": "USB", "Status": "Down", "X_ZYXEL_DefaultGatewayIface": false],
        ]
        return [
            "DeviceInfo": ["ModelName": "EX5601-T1", "SoftwareVersion": "V5.70(ACEA.0)T56C", "SerialNumber": "S000Z00000042",
                           "X_ZYXEL_LastRebootCause": "Firmware upgrade", "FirstUseDate": "2024-03-02",
                           "UpTime": .int(Int64(uptime)), "X_ZYXEL_RebootCount": 7],
            "SystemInfo": ["HostName": "EX5601-T1", "CPUUsage": .int(Int64(cpu)), "Total": 1_016_420, "Free": .int(Int64(freeKB))],
            "FirewallInfo": ["Enable": true, "X_ZYXEL_DefaultConfig": "Medium"],
            "WanLanInfo": .array(wan), "LanPortInfo": .array(lanPorts), "WiFiInfo": .array(wifi),
        ]
    }

    // MARK: Config tables

    static let reservations: [JSONValue] = devices.filter(\.reserved).enumerated().map { i, d in
        ["Index": .int(Int64(i + 1)), "BrWan": "Default", "Enable": true, "MACAddr": .string(d.mac), "IPAddr": .string(d.ip)]
    }

    static func natRule(_ i: Int, _ desc: String, _ proto: String, _ ext: Int, _ host: String, _ int: Int, on: Bool = true) -> JSONValue {
        ["Index": .int(Int64(i)), "Enable": .bool(on), "Description": .string(desc), "Protocol": .string(proto),
         "ExternalPortStart": .int(Int64(ext)), "ExternalPortEnd": .int(Int64(ext)),
         "InternalPortStart": .int(Int64(int)), "InternalPortEnd": .int(Int64(int)), "InternalClient": .string(host),
         "Interface": "", "SetRemoteIP": false, "RemoteHost": "", "RemoteHostEndRange": "255.255.255.255",
         "WANIP": "", "X_ZYXEL_AutoDetectWanStatus": true, "DefaultPort": "", "referenceIndex": -1]
    }

    static let nat: [JSONValue] = [
        natRule(1, "Home Server HTTPS", "TCP", 443, "192.168.1.20", 443),
        natRule(2, "Home Server HTTP", "TCP", 80, "192.168.1.20", 80),
        natRule(3, "WireGuard", "UDP", 51820, "192.168.1.20", 51820),
        natRule(4, "Media server", "TCP", 32400, "192.168.1.10", 32400),
        natRule(5, "Game server", "ALL", 25565, "192.168.1.24", 25565, on: false),
    ]

    static let lan: JSONValue = [
        "Name": "Default", "IPAddress": .string(routerIP), "SubnetMask": "255.255.255.0", "EnableDHCP": true,
        "DHCPType": "DHCPServer", "DHCP_MinAddress": "192.168.1.2", "DHCP_MaxAddress": "192.168.1.254",
        "DHCP_LeaseTime": 86400, "DHCP_AutoReserveLanIp": false, "DNS_Type": "DNSProxy",
        "IGMPSnoopingMode": "Blocking", "IPv6_LanEnable": true,
    ]

    static let lanadv: [JSONValue] = [
        ["UPnPEnable": true, "NATTEnable": true, "TFTPServerName": "", "STBVendorID1": "", "STBVendorID2": "",
         "STBVendorID3": "", "STBVendorID4": "", "STBVendorID5": ""],
        [
            ["Protocol": "UDP", "ExternalPort": 3074, "InternalPort": 3074, "Destination": "192.168.1.42", "Description": "PS Remote Play", "Enable": true],
            ["Protocol": "UDP", "ExternalPort": 41641, "InternalPort": 41641, "Destination": "192.168.1.23", "Description": "tailscale", "Enable": true],
            ["Protocol": "TCP", "ExternalPort": 5353, "InternalPort": 5353, "Destination": "192.168.1.10", "Description": "NAS DDNS helper", "Enable": true],
        ],
    ]

    static let natConf: JSONValue = [
        "DMZHost": "0.0.0.0", "NAT_ALG": true, "SIP_ALG": false, "RTSP_ALG": true, "PPTP_ALG": true, "IPSEC_ALG": true,
        "MaxSessionPerHost": 2048, "subnetInfo": [],
    ]

    static let routes: JSONValue = [[
        "result": [
            ["network": "0.0.0.0", "mask": "0.0.0.0", "gateway": .string(gateway), "flags": "UG", "metric": 0, "intf": "eth1.3"],
            ["network": "10.20.16.0", "mask": "255.255.240.0", "gateway": "0.0.0.0", "flags": "U", "metric": 0, "intf": "eth1.4"],
            ["network": "192.168.1.0", "mask": "255.255.255.0", "gateway": "0.0.0.0", "flags": "U", "metric": 0, "intf": "br0"],
            ["network": "203.0.113.0", "mask": "255.255.255.0", "gateway": "0.0.0.0", "flags": "U", "metric": 0, "intf": "eth1.3"],
        ],
    ]]

    /// Simple config objects copied from the shapes the real firmware returns, with neutral values.
    static let misc: [String: [JSONValue]] = [
        "firewall": [["Enable": true, "IPv4_Enable": true, "IPv6_Enable": true, "Level_GUI": "Low", "enableDos": true]],
        "macfilter": [["MAC": ["Filter_Enable": false, "Restrict": false], "whitelist": []]],
        "mgmt_srv": [
            ["Index": 1, "Name": "HTTP", "Enable": true, "Mode": "LAN_ONLY", "Port": 80, "BoundInterfaceList": "", "RedirectHttps": true],
            ["Index": 2, "Name": "HTTPS", "Enable": true, "Mode": "LAN_ONLY", "Port": 443, "BoundInterfaceList": "", "RedirectHttps": false],
            ["Index": 3, "Name": "SSH", "Enable": false, "Mode": "LAN_ONLY", "Port": 22, "BoundInterfaceList": "", "RedirectHttps": false],
            ["Index": 4, "Name": "PING", "Enable": true, "Mode": "LAN_WAN", "Port": 0, "BoundInterfaceList": "", "RedirectHttps": false],
        ],
        "paren_ctl": [["PrentalCtlEnable": false, "ForceThirdParty": false, "MaxLenPrentalCtlPrf": 12]],
        "wifi_easy_mesh": [["EasyMeshEnable": true, "BandSteeringEnable": true, "Controller_mode": 1, "CurRole": 1, "EasyMeshTsEnable": false]],
        "nat_trigger": [], "nat_addr_map": [], "firewall_acl": [], "URL_BlackList": [], "URL_WhiteList": [],
        "dns": [
            ["Index": 1, "HostName": "nas.home", "IPv4Address": "192.168.1.10"],
            ["Index": 2, "HostName": "server.home", "IPv4Address": "192.168.1.20"],
        ],
    ]
}
