import Foundation
import FyxelCore

// Settings objects for the extra pages. Shapes follow what the firmware returns; values are invented.

extension Fixtures {
    static let fx_wps: [JSONValue] = [
            ["Band": "2.4GHz", "Enable": false, "ModeEnabled": "WPA3-Personal-Transition", "X_ZYXEL_WPS_Configured": true,
             "X_ZYXEL_WPS_EnablePBC": true, "X_ZYXEL_WPS_EnableStaPin": false, "X_ZYXEL_WPS_EnableAPPin": false, "X_ZYXEL_WPS_V2": true, "X_ZYXEL_WlMode": "ap"],
            ["Band": "5GHz", "Enable": false, "ModeEnabled": "WPA3-Personal-Transition", "X_ZYXEL_WPS_Configured": true,
             "X_ZYXEL_WPS_EnablePBC": true, "X_ZYXEL_WPS_EnableStaPin": false, "X_ZYXEL_WPS_EnableAPPin": false, "X_ZYXEL_WPS_V2": true, "X_ZYXEL_WlMode": "ap"],
        ]
    static let fx_wifi_macfilter: [JSONValue] = ssids.map { s -> JSONValue in
            let iot = s.index == 3
            let list = iot ? "02-18-b4-30-72-5e,02-b0-09-da-44-12,02-50-ec-50-8f-99,02-9c-b6-54-1d-80" : ""
            return ["ssid": .string(s.name), "mode": .int(iot ? 2 : 0), "list": .string(list)]
        }
    static let fx_wifi_others: [JSONValue] = [1, 5].map { i -> JSONValue in
            let b24 = i == 1
            let mode = b24 ? "b,g,n,ax" : "a,n,ac,ax"
            return ["Index": .int(Int64(i)), "Band": .string(b24 ? "2.4GHz" : "5GHz"), "wlRtsThrshld": 2347, "wlFrgThrshld": 2346, "wlTxPwrPcnt": 100,
             "wlBcnIntvl": 100, "wlDtmIntvl": 1, "wlMode": .string(mode), "wlProtect": "auto", "wlPreamble": "long",
             "InActiveChan": "", "atf": false, "acs_fcs_mode": 0, "X_ZYXEL_BF_Enable": true, "X_ZYXEL_IEEE80211R_Enable": false,
             "SupportedStandards": .string(mode)]
        }
    static let fx_wlan_scheduler: [JSONValue] = [
            ["Index": 1, "Enable": true, "Name": "IoT quiet hours", "Description": "", "SSID": "Northwind IoT", "Interface": 99,
             "Days": "Mon,Tue,Wed,Thu,Fri,Sat,Sun", "TimeStartHour": 1, "TimeStartMin": 0, "TimeStopHour": 6, "TimeStopMin": 0],
        ]
    static let fx_ddns: [JSONValue] = [[
            "Enable": true, "ServiceProvider": "dynu", "HostName": "northwind.example.net", "UserName": "northwind",
            "Password": "not-a-real-password", "Wildcard": false, "Offline": false, "UseIPv6": false, "UpdateURL": "", "UpdateURLv6": "",
            "ConnectionType": "HTTP", "AuthenticationResult": "Success", "UpdatedTime": "2026-10-31 18:02:11", "DynamicIP": .string(publicIP), "DynamicIPv6": "",
        ]]
    static let fx_ipalias: [JSONValue] = [[
            "GroupName": "Default", "ipAlias_Enable": false, "ipAlias_IPAddress": "", "ipAlias_SubnetMask": "", "ipAlias_Subnet_Ref": "",
            "PubLan_Enable": false, "PubLan_IP": "", "PubLan_SubnetMask": "", "PubLan_DHCP": false, "PubLan_ARP": false,
        ]]
    static let fx_firewall_acl: [JSONValue] = [
            ["Index": 1, "Order": 1, "Enable": 1, "Name": "No IoT to NAS", "IPVersion": "IPv4", "SourceIP": "192.168.1.70", "SourceMask": 28,
             "DestIP": "192.168.1.10", "DestMask": 32, "MACAddress": "AnyMACAddress", "Target": "Drop", "X_ZYXEL_ServiceIndex": 0,
             "Protocol": "ALL", "DestPort": -1, "DestPortRangeMax": -1, "Direction": "LAN_TO_WAN", "Log": true],
        ]
    static let fx_firewall_proto: [JSONValue] = [
            ["Index": 1, "Name": "Plex", "Description": "Media server", "Protocol": 6, "SourcePort": -1, "SourcePortEnd": -1,
             "DestPort": 32400, "DestPortEnd": -1, "ICMPType": -1, "ICMPTypeCode": -1],
        ]
    static let fx_macfilter: [JSONValue] = [["MAC": ["Filter_Enable": false, "Restrict": true], "whitelist": [
            ["List_Enable": true, "HostName": "Old laptop", "MACAddress": "02:44:10:9A:BC:01"],
        ]]]
    static let fx_paren_ctl: [JSONValue] = [
            ["PrentalCtlEnable": true, "ForceThirdParty": false, "MaxLenPrentalCtlPrf": 12],
            ["Index": 1, "pcpEnable": true, "pcpName": "School nights", "MACAddressList": "a2:4f:01:66:aa:0e,02:fc:65:0a:bb:21",
             "Days": "Sun,Mon,Tue,Wed,Thu", "TimeRangeList": "21:30-23:59", "TimeType": "Normal", "TimeEnable": "1",
             "ServicePolicy": "Block", "UrlPolicy": "Block", "WebRedirect": 0, "URLFilter": "", "NetworkServiceList": ""],
        ]
    static let fx_URL_BlackList: [JSONValue] = [["Index": 1, "Enable": true, "Name": "UserDefined", "BlackList": "ads.example.com", "FilterIndex": "X_ZYXEL_URLfilter.1"]]
    static let fx_URL_WhiteList: [JSONValue] = []
    static let fx_nat_trigger: [JSONValue] = [
            ["idx": 1, "Index": 1, "Enable": true, "Description": "Video chat", "Interface": "", "X_ZYXEL_AutoDetectWanStatus": true,
             "TriggerPort": 6970, "TriggerPortEndRange": 6970, "TriggerProtocol": "UDP", "OpenPort": 7000, "OpenPortEndRange": 7010, "Protocol": "UDP"],
        ]
    static let fx_nat_addr_map: [JSONValue] = []
    static let fx_static_route: [JSONValue] = [
            ["Index": 1, "Enable": true, "Name": "Lab", "ipver": "IPv4", "DestIPAddress": "10.42.0.0", "DestSubnetMask": "255.255.0.0",
             "GatewayIPAddress": "192.168.1.20", "Interface": "IP.Interface.1", "DestIPPrefix": "", "NextHop": ""],
        ]
    static let fx_policy_route: [JSONValue] = []
    static let fx_dns_route: [JSONValue] = []
    static let fx_qos: [JSONValue] = [["Enable": false, "UpRate": 100_000, "MinUpRate": 0, "MaxUpRate": 1_000_000, "AutoMapType": "None", "DownRate": 0]]
    static let fx_qos_queue: [JSONValue] = [["idx": 1, "Index": 1, "Enable": true, "Name": "default", "Priority": "8", "Weight": "1", "RateLimit": -1]]
    static let fx_qos_shaper: [JSONValue] = []
    static let fx_user_account: [JSONValue] = [[
            "Index": 2, "Username": "admin", "Enabled": true, "group": "Administrator", "AccountIdleTime": 300,
            "AccountLockTime": 300, "AccountRetryTime": 3, "RemoteAccessPrivilege": "LAN,WAN",
        ]]
    static let fx_trust_domain: [JSONValue] = []
    static let fx_time: [JSONValue] = [[
            "Date": "2026-11-01", "Time": "10:24:51", "X_ZYXEL_TimeZone": "CET-1CEST,M3.5.0,M10.5.0/3",
            "NTPServer1": "pool.ntp.org", "NTPServer2": "time.cloudflare.com", "NTPServer3": "None", "NTPServer4": "None",
            "NTPServer5": "None", "DaylightSavings": true,
        ]]
    static let fx_logset: [JSONValue] = [[
            "Enable": true, "LogMode": "Local", "LogServer": "0.0.0.0", "UDPPort": 514, "EnableSyslogOverTLS": false, "MutualAuthLocalCert": "",
            "Interval": 60, "MailEnable": false, "System": true, "Firewall": true, "Attack": true, "Account": true, "Wireless": true,
            "DHCP Server": true, "WAN-DHCP": false, "UPNP": false, "MAC Filter": false, "EasyMesh": false, "Voice": false, "TR-069": false,
        ]]
    static let fx_phone: [JSONValue] = [
            ["Index": 1, "PhoneID": "PHONE1", "InterNum": "**11", "DialEnable": true, "LineSelect": "", "phoneBoundingList": "", "NumberList": "", "LineList": ""],
            ["Index": 2, "PhoneID": "PHONE2", "InterNum": "**12", "DialEnable": true, "LineSelect": "", "phoneBoundingList": "", "NumberList": "", "LineList": ""],
        ]
    static let fx_region: [JSONValue] = [["Region": "NL", "Service_Mode": "Europe_Type", "FxsCIDMode": "Default", "FxsCIDSigProtocol": "Default"]]
    static let fx_sip_account: [JSONValue] = []
    static let fx_media_server: [JSONValue] = [["Enable": true, "Interface": "IP.Interface.1", "MediaRelativePath": "/mnt/usb1_sda1/Media/"]]
    static let fx_usb_filesharing: [JSONValue] = [[
            "Service Conf": ["File Sharing Services": true],
            "Usb Info": [["Volume": "usb1_sda1", "Capacity": 476_940, "Used Space": 198_211]],
            "Samba": [["Index": 1, "Share Name": "Media", "Share Path": "/mnt/usb1_sda1/Media", "Share Description": "Films and music",
                       "Hostname": "usb1_sda1", "Status": true, "Public": true]],
            "Account": [["Username": "admin", "Status": true]],
        ]]
    static let fx_cellular: [JSONValue] = [[
            "Enable_3G": false, "APN": "", "Username": "", "Password": "", "ConnectionTrigger": "AlwaysOn",
            "Backup_Interval": 60, "Recovery_Interval": 300,
        ]]
    static let fx_PINGTEST: [JSONValue] = [["DiagnosticsState": "None"]]

    static var settings: [String: [JSONValue]] {
        var d: [String: [JSONValue]] = [:]
        d["wps"] = fx_wps
        d["wifi_macfilter"] = fx_wifi_macfilter
        d["wifi_others"] = fx_wifi_others
        d["wlan_scheduler"] = fx_wlan_scheduler
        d["ddns"] = fx_ddns
        d["ipalias"] = fx_ipalias
        d["firewall_acl"] = fx_firewall_acl
        d["firewall_proto"] = fx_firewall_proto
        d["macfilter"] = fx_macfilter
        d["paren_ctl"] = fx_paren_ctl
        d["URL_BlackList"] = fx_URL_BlackList
        d["URL_WhiteList"] = fx_URL_WhiteList
        d["nat_trigger"] = fx_nat_trigger
        d["nat_addr_map"] = fx_nat_addr_map
        d["static_route"] = fx_static_route
        d["policy_route"] = fx_policy_route
        d["dns_route"] = fx_dns_route
        d["qos"] = fx_qos
        d["qos_queue"] = fx_qos_queue
        d["qos_shaper"] = fx_qos_shaper
        d["user_account"] = fx_user_account
        d["trust_domain"] = fx_trust_domain
        d["time"] = fx_time
        d["logset"] = fx_logset
        d["phone"] = fx_phone
        d["region"] = fx_region
        d["sip_account"] = fx_sip_account
        d["media_server"] = fx_media_server
        d["usb_filesharing"] = fx_usb_filesharing
        d["cellular"] = fx_cellular
        d["PINGTEST"] = fx_PINGTEST
        return d
    }

    static let logCategories: [String: [String]] = [
        "syslog": ["dhcpd", "httpd", "wireless", "system", "upnp"],
        "securitylog": ["account", "attack", "firewall"],
    ]

    /// Fake log lines in the router's format, oldest first.
    static func logLines(_ kind: String) -> [String] {
        let now = Date()
        func ts(_ ago: TimeInterval) -> String {
            let f = DateFormatter()
            f.locale = Locale(identifier: "en_US_POSIX")
            f.dateFormat = "MMM dd HH:mm:ss"
            return f.string(from: now.addingTimeInterval(-ago))
        }
        let sys: [(String, String, String)] = [
            ("system", "user.notice", "System booted, firmware V5.70(ACEA.0)T56C"),
            ("wireless", "user.info", "WiFi 5GHz: channel 44 selected by ACS (80MHz)"),
            ("dhcpd", "user.info", "DHCPACK(br0) 192.168.1.23 a2:4f:01:10:22:31 Studio-MacBook-Pro"),
            ("dhcpd", "user.info", "DHCPACK(br0) 192.168.1.61 a2:4f:01:7d:3e:58 Alexs-iPhone"),
            ("upnp", "user.info", "add port mapping UDP 41641 -> 192.168.1.23:41641 (tailscale)"),
            ("httpd", "user.notice", "Account admin logged in from 192.168.1.23"),
            ("wireless", "user.warning", "WiFi 2.4GHz: STA 02:b0:09:da:44:12 deauthenticated (reason 4)"),
            ("dhcpd", "user.info", "DHCPACK(br0) 192.168.1.150 02:a8:7b:91:5c:33 Galaxy-S24"),
            ("system", "user.err", "NTP: time.cloudflare.com unreachable, using pool.ntp.org"),
            ("wireless", "user.info", "WiFi 5GHz: STA a2:4f:01:7d:3e:58 associated (WPA3-SAE)"),
        ]
        let sec: [(String, String, String)] = [
            ("account", "authpriv.notice", "Account admin logged in from 192.168.1.23 via HTTPS"),
            ("firewall", "kern.warning", "Blocked TCP 198.51.100.77:51544 -> 203.0.113.42:23"),
            ("attack", "kern.alert", "SYN flood from 198.51.100.12 dropped"),
            ("firewall", "kern.warning", "Blocked UDP 192.0.2.80:5060 -> 203.0.113.42:5060"),
            ("account", "authpriv.warning", "Login failed for admin from 192.168.1.64"),
        ]
        let src = kind == "syslog" ? sys : sec
        return (0..<36).map { i in
            let e = src[i % src.count]
            return "[\(e.0)] \(ts(Double(36 - i) * 431)) \(e.1) \(e.2)"
        }
    }

    static func pingOutput(_ kind: Int, host: String, step: Int) -> String {
        switch kind {
        case 1:
            let hops = ["192.168.1.1", "203.0.113.1", "198.51.100.9", "198.51.100.65", host]
            return (["traceroute to \(host), 30 hops max, 38 byte packets"] + hops.prefix(step).enumerated().map { i, h in
                String(format: " %d  %@  %.3f ms  %.3f ms  %.3f ms", i + 1, h, 0.4 + Double(i) * 2.1, 0.5 + Double(i) * 2.0, 0.4 + Double(i) * 2.2)
            }).joined(separator: "\n")
        case 2:
            return step < 1 ? "" : "Server:    127.0.0.1\nAddress 1: 127.0.0.1 localhost\n\nName:      \(host)\nAddress 1: 93.184.215.14\nAddress 2: 2606:2800:21f:cb07:6820:80da:af6b:8b2c"
        default:
            var lines = ["PING \(host) (\(host)): 56 data bytes"]
            for i in 0..<min(step, 4) { lines.append(String(format: "64 bytes from %@: seq=%d ttl=57 time=%.3f ms", host, i, 9.8 + Double(i % 3) * 0.7)) }
            if step >= 5 {
                lines += ["", "--- \(host) ping statistics ---", "4 packets transmitted, 4 packets received, 0% packet loss",
                          "round-trip min/avg/max = 9.812/10.390/11.203 ms"]
            }
            return lines.joined(separator: "\n")
        }
    }
}
