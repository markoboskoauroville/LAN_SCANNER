#!/usr/bin/env python3
"""Downloads the IEEE OUI list and writes build/oui.tsv (6-hex prefix TAB short maker name).
Never fails the build: on any problem it prints a line and exits 0 (the app then uses its small fallback table)."""
import csv, io, os, re, sys, urllib.request

URLS = ["https://standards-oui.ieee.org/oui/oui.csv", "https://standards.ieee.org/develop/regauth/oui/oui.csv"]
DROP = {"inc", "ltd", "co", "corp", "corporation", "gmbh", "llc", "limited", "technologies", "technology", "company",
        "ag", "plc", "sa", "bv", "oy", "ab", "srl", "spa"}

def short(name):
    words = re.sub(r"[,]", " ", name).split()
    while words and re.sub(r"[.]", "", words[-1]).lower() in DROP:
        words.pop()
    s = " ".join(words) or name
    return s[:28]

def main():
    for url in URLS:
        try:
            req = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0 (LAN Scanner build)"})
            raw = urllib.request.urlopen(req, timeout=60).read().decode("utf-8", "replace")
            rows = list(csv.reader(io.StringIO(raw)))
            out = []
            for r in rows[1:]:
                if len(r) >= 3 and re.fullmatch(r"[0-9A-Fa-f]{6}", r[1]):
                    out.append("%s\t%s" % (r[1].upper(), short(r[2])))
            if len(out) > 1000:
                os.makedirs("build", exist_ok=True)
                open("build/oui.tsv", "w").write("\n".join(out) + "\n")
                print("oui.tsv: %d prefixes" % len(out))
                return
        except Exception as e:
            print("oui download failed (%s): %s" % (url, e))
    print("no oui.tsv written; the fallback table will be used")

main()
sys.exit(0)
