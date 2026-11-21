// Oui.swift: MAC prefix -> maker. The full table (oui.tsv, prefix TAB short name) is made in CI by tools/make_oui.py from
// the IEEE list and sits in the app's Resources. This file holds a small committed fallback of well-known prefixes for
// when that download failed (the build does not fail then). A MAC with the locally-administered bit is "Private address"
// and never gets a maker; an unknown prefix gives an empty string, never a guess.
import Foundation

enum OUI {
    static let fallbackText = """
    286FB9 Nokia Shanghai Bell
    90ECE3 Nokia
    B851A9 Nokia
    5C76D5 Nokia
    E80AB9 Cisco Systems
    9CE330 Cisco Meraki
    B4DF91 Cisco Meraki
    481BA4 Cisco Systems
    E00630 HUAWEI
    D8DAF1 HUAWEI
    54443B HUAWEI
    5C7075 HUAWEI
    644ED7 HP
    7C4D8F HP
    5C60BA HP
    508140 HP
    E4C767 Intel Corporate
    A002A5 Intel Corporate
    444988 Intel Corporate
    102E00 Intel Corporate
    D48AFC Espressif
    E465B8 Espressif
    B48A0A Espressif
    94E686 Espressif
    601AC7 Nintendo
    BC9EBB Nintendo
    CC5B31 Nintendo
    1C4586 Nintendo
    CCEB5E Xiaomi Communications
    B8EA98 Xiaomi Communications
    F41A9C Xiaomi Communications
    DC6AE7 Xiaomi Communications
    7478A6 Fortinet
    84398F Fortinet
    7818EC Fortinet
    5C63B0 Fortinet
    50FE0C AzureWave
    505A65 AzureWave
    B48C9D AzureWave
    90E868 AzureWave
    F0EE7A Apple
    58AD12 Apple
    60FDA6 Apple
    80A997 Apple
    40F3B0 Texas Instruments
    149CEF Texas Instruments
    80C41B Texas Instruments
    3468B5 Texas Instruments
    ACC048 OnePlus Technology (Shenzhen
    5C17CF OnePlus Technology (Shenzhen
    A091A2 OnePlus Electronics (Shenzhe
    7CF0E5 OnePlus Technology (Shenzhen
    842859 Amazon
    2873F6 Amazon
    E0CB1D Amazon
    FCD749 Amazon
    5016F4 Motorola Mobility LLC a Leno
    C4A052 Motorola Mobility LLC a Leno
    C85895 Motorola Mobility LLC a Leno
    00047D Motorola Solutions
    641B2F Samsung Electronics
    9C73B1 Samsung Electronics
    388A06 Samsung Electronics
    48BCE1 Samsung Electronics
    B0D888 Panasonic Automotive Systems
    B8208E Panasonic Connect
    001BD3 Panasonic Corporation AVC Ne
    CC7EE7 Panasonic Corporation AVC Ne
    FC84A7 Murata Manufacturing
    2CD1C6 Murata Manufacturing
    5026EF Murata Manufacturing
    A0CDF3 Murata Manufacturing
    D0431E Dell
    00C04F Dell
    00B0D0 Dell
    0019B9 Dell
    F80DA9 Zyxel Communications
    88ACC0 Zyxel Communications
    0023F8 Zyxel Communications
    0019CB Zyxel Communications
    581031 Hon Hai Precision IND.CO.
    843095 Hon Hai Precision IND.CO.
    A4AE11 Hon Hai Precision Industry
    9C305B Hon Hai Precision Ind.
    F09FC2 Ubiquiti
    802AA8 Ubiquiti
    788A20 Ubiquiti
    7483C2 Ubiquiti
    AC800A Sony
    F46412 Sony Interactive Entertainme
    2C9E00 Sony Interactive Entertainme
    143FA6 Sony Home Entertainment&Soun
    64EC65 vivo Mobile Communication
    6CD199 vivo Mobile Communication
    28BE43 vivo Mobile Communication
    9431CB vivo Mobile Communication
    D83ADD Raspberry Pi Trading
    DCA632 Raspberry Pi Trading
    E45F01 Raspberry Pi Trading
    88A29E Raspberry Pi (Trading)
    70F8AE Microsoft
    201642 Microsoft
    C461C7 Microsoft
    D8E2DF Microsoft
    08C3B3 TCL King Electrical Applianc
    C07982 TCL King Electrical Applianc
    3C591E TCL King Electrical Applianc
    0000DD TCL INCORPORATED
    D03957 Liteon
    E82A44 Liteon
    30D16B Liteon
    646E69 Liteon
    48C35A LENOVO(BEIJING)CO.
    10C595 Lenovo
    A41194 Lenovo
    E02CB2 Lenovo Mobile Communication 
    60706C Google
    C82ADD Google
    242934 Google
    08B4B1 Google
    1C90FF Tuya Smart
    FC3CD7 Tuya Smart
    E4AEE4 Tuya Smart
    FC671F Tuya Smart
    8C5219 SHARP
    6879ED SHARP
    145051 SHARP
    345A06 SHARP
    045747 GoPro
    2474F7 GoPro
    D43260 GoPro
    F4DD9E GoPro
    AC5AF0 LG Electronics
    B03795 LG Electronics
    58FDB1 LG Electronics
    A04F85 LG Electronics (Mobile Commu
    C83A1B Toshiba TEC
    0015B7 Toshiba
    E89D87 Toshiba
    78D6B2 Toshiba
    D4BD4F Ruckus Wireless
    5CDF89 Ruckus Wireless
    38453B Ruckus Wireless
    60D02C Ruckus Wireless
    B4F267 Compal Broadband Networks
    BCECA0 COMPAL INFORMATION (KUNSHAN)
    E4A8DF COMPAL INFORMATION (KUNSHAN)
    089798 COMPAL INFORMATION (KUNSHAN)
    00620B Broadcom
    5C6F69 Broadcom
    BC97E1 Broadcom
    001BE9 Broadcom
    E06D18 PIONEERCORPORATION
    745E1C PIONEER
    00E036 PIONEER
    94B2CC PIONEER
    BC2228 D-Link International
    A0A3F0 D-Link International
    BC0F9A D-Link International
    74DADA D-Link International
    D03F27 Wyze Labs
    F0C88B Wyze Labs
    80482C Wyze Labs
    7C78B2 Wyze Labs
    E43BC9 HISENSE VISUAL
    B84DEE Hisense broadband multimedia
    A88200 Hisense Electric
    001A95 Hisense Mobile Communication
    34FE9E Fujitsu
    68847E FUJITSU
    A8B2DA FUJITSU
    B0ACFA FUJITSU
    C87B23 Bose
    2C41A1 Bose
    08DF1F Bose
    0050B7 BOSER
    002618 ASUSTek COMPUTER
    049226 ASUSTek COMPUTER
    1831BF ASUSTek COMPUTER
    88D7F6 ASUSTek COMPUTER
    34F716 TP-LINK
    54A703 TP-LINK
    B0BE76 TP-LINK
    34E894 TP-LINK
    B4C26A Garmin International
    104E89 Garmin International
    E04824 Garmin International
    00054F Garmin International
    C45444 Quanta Computer
    001B24 Quanta Computer
    00C09F Quanta Computer
    C80AA9 Quanta Computer
    D49234 NEC
    8CDF9D NEC
    F46E24 NEC Personal Computers
    000862 NEC Eluminant
    6869CA Hitachi
    A497BB Hitachi Industrial Equipment
    0021BF Hitachi High-Tech Control Sy
    000E66 Hitachi Industry & Control S
    B8A44F Axis Communications
    00408C Axis Communications
    E82725 Axis Communications
    ACCC8E Axis Communications
    54E019 Ring
    00254A RingCube
    B009DA Ring Solutions
    0025C2 RingBell
    9C7BEF Hewlett Packard
    10E7C6 Hewlett Packard
    B8AF67 Hewlett Packard
    80CE62 Hewlett Packard
    00203D Honeywell Environmental & Co
    004084 Honeywell
    144146 Honeywell (China)
    001F55 Honeywell Security (China)
    002421 MICRO-STAR INT'L
    D8CB8A Micro-Star INTL
    448A5B Micro-Star INT'L
    D43D7E Micro-Star Int'l
    482AE3 Wistron InfoComm(Kunshan)Co.
    70E284 Wistron Infocomm (Zhongshan)
    446752 Wistron INFOCOMM (Zhongshan)
    5CFF35 Wistron
    D45DDF PEGATRON
    202564 PEGATRON
    0C54A5 PEGATRON
    54BEF7 PEGATRON
    00C0FF Seagate Cloud Systems
    001862 Seagate
    000C50 Seagate
    0014C3 Seagate
    BC0543 AVM
    0024FE AVM
    C02506 AVM
    3431C4 AVM
    24C42F Philips Lifeline
    E8C1D7 Philips
    7C94B2 Philips Healthcare PCCI
    00054E Philips
    D8EC5E Belkin International
    E89F80 Belkin International
    58EF68 Belkin International
    6038E0 Belkin International
    88124E Qualcomm
    A0BD71 QUALCOMM Incorporated
    00A0C6 Qualcomm
    649C81 Qualcomm
    006B9E Vizio
    CC95D7 Vizio
    3C9BD6 Vizio
    A06A44 Vizio
    AC44F2 YAMAHA
    00A0DE YAMAHA
    0004C6 YAMAHA MOTOR
    F4D580 YAMAHA
    84BA3B CANON
    60128B CANON
    000220 CANON FINETECH
    5C625A CANON
    008077 Brother industries
    B07C8E Brother Industries
    001BA9 Brother industries
    3C2AF4 Brother Industries
    D04D2C Roku
    B0A737 Roku
    B0EE7B Roku
    D83134 Roku
    405D82 NETGEAR
    DCEF09 NETGEAR
    100C6B NETGEAR
    3894ED NETGEAR
    0021F6 Oracle
    000017 Oracle
    A8698C Oracle
    00104F Oracle
    00130E Focusrite Audio Engineering
    00043C SONOS
    7828CA Sonos
    542A1B Sonos
    F0F6C1 Sonos
    00E04C REALTEK SEMICONDUCTOR
    FC934E REALTEK SEMICONDUCTOR
    0000C0 WESTERN DIGITAL
    0090A9 WESTERN DIGITAL
    0014EE Western Digital
    08000A NESTAR SYSTEMS INCORPORATED
    BC0866 Nestle Purina PetCare
    000A17 NESTAR COMMUNICATIONS
    641666 Nest Labs
    4471B3 Logitech Far East
    38F0C8 Logitech
    F47335 Logitech Far East
    C0288D Logitech
    8400EC Shelly Europe
    8CCBDF FOXCONN INTERCONNECT
    98E79A Foxconn(NanJing) Communicati
    EC01E2 FOXCONN INTERCONNECT
    001558 FOXCONN
    245EBE QNAP Systems
    E843B6 QNAP Systems
    7C2E0D Blackmagic Design
    0022DE OPPO Digital
    001C42 Parallels
    001694 Sennheiser Communications A/
    001B66 Sennheiser electronic GmbH &
    D834EE SHURE INCORPORATED
    000EDD SHURE INCORPORATED
    001C14 VMware
    005056 VMware
    000C29 VMware
    000569 VMware
    2C301A Technicolor CH USA Inc for T
    1CE4DD Technicolor (China)
    F01628 Technicolor (China)
    38F18F Technicolor (China)
    342B70 Arris
    000C43 MediaTek
    000CE7 MediaTek
    0017A5 MediaTek
    000A00 MediaTek
    9009D0 Synology Incorporated
    001132 Synology Incorporated
    EC71DB Reolink Innovation
    001564 BEHRINGER Spezielle Studiote
    """

    static let fallback: [String: String] = {
        var t: [String: String] = [:]
        for line in fallbackText.split(separator: "\n") {
            let s = line.trimmingCharacters(in: .whitespaces)
            guard let sp = s.firstIndex(of: " ") else { continue }
            let key = String(s[..<sp])
            let rest = String(s[s.index(after: sp)...]).trimmingCharacters(in: .whitespaces)
            if key.count == 6 { t[key.uppercased()] = rest }
        }
        return t
    }()

    /// The CI table, loaded once from Resources/oui.tsv (absent when the download failed).
    static let table: [String: String] = {
        var t: [String: String] = [:]
        guard let p = Bundle.main.path(forResource: "oui", ofType: "tsv"),
              let s = try? String(contentsOfFile: p, encoding: .utf8) else { return t }
        for line in s.split(separator: "\n") {
            let f = line.split(separator: "\t", maxSplits: 1)
            if f.count == 2 { t[String(f[0])] = String(f[1]) }
        }
        return t
    }()

    static func lookup(mac: String) -> String {
        if MAC.isPrivate(mac) { return "Private address" }
        let k = MAC.prefix6(mac)
        return table[k] ?? fallback[k] ?? ""
    }

    /// "Apple, Inc." -> "Apple", "TP-LINK TECHNOLOGIES CO.,LTD." -> "TP-LINK".
    static func shortName(_ full: String) -> String {
        var s = full.replacingOccurrences(of: ",", with: " ")
        let drop: Set<String> = ["inc", "inc.", "ltd", "ltd.", "co", "co.", "corp", "corp.", "corporation", "gmbh", "llc", "limited",
                                 "technologies", "technology", "company", "s.a.", "ag", "b.v.", "plc", "co.,ltd.", "co.ltd."]
        var words = s.split(separator: " ").map(String.init)
        while let last = words.last, drop.contains(last.lowercased()) || drop.contains(last.lowercased().replacingOccurrences(of: ".", with: "")) {
            words.removeLast()
        }
        s = words.joined(separator: " ")
        return s.isEmpty ? full : String(s.prefix(28))
    }
}
