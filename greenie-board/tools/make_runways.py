#!/usr/bin/env python3
"""Build runways.json for the Greenie Board from the OurAirports public-domain data.

Usage: python3 make_runways.py airports.csv runways.csv > ../runways.json
Get the two CSV files from https://ourairports.com/data/

Keeps open US runways at least 1,500 ft long that have coordinates for both ends.
Each row: [airport, low end name, high end name, low lat, low lon, high lat, high lon,
           width ft, low displaced threshold ft, high displaced threshold ft]
"""
import csv, json, sys

airports_csv, runways_csv = sys.argv[1], sys.argv[2]
us = {}
with open(airports_csv, newline='', encoding='utf-8') as f:
    for a in csv.DictReader(f):
        if a['iso_country'] == 'US' and a['type'] in ('small_airport', 'medium_airport', 'large_airport'):
            us[a['ident']] = a.get('gps_code') or a.get('local_code') or a['ident']

def num(s):
    try:
        return float(s)
    except ValueError:
        return None

rows = []
with open(runways_csv, newline='', encoding='utf-8') as f:
    for r in csv.DictReader(f):
        if r['airport_ident'] not in us or r['closed'] == '1':
            continue
        c = [num(r[k]) for k in ('le_latitude_deg', 'le_longitude_deg', 'he_latitude_deg', 'he_longitude_deg')]
        length = num(r['length_ft'])
        if None in c or not length or length < 1500:
            continue
        if not r['le_ident'] or not r['he_ident'] or r['le_ident'].startswith('H'):
            continue
        rows.append([us[r['airport_ident']], r['le_ident'], r['he_ident'],
                     round(c[0], 6), round(c[1], 6), round(c[2], 6), round(c[3], 6),
                     int(num(r['width_ft']) or 0),
                     int(num(r['le_displaced_threshold_ft']) or 0),
                     int(num(r['he_displaced_threshold_ft']) or 0)])
rows.sort()
json.dump(rows, sys.stdout, separators=(',', ':'))
