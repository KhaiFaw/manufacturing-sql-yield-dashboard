"""Generate a deterministic, intentionally imperfect manufacturing test dataset.

Only Python is used to create source CSVs. All cleanup and analysis happens in PostgreSQL.
"""

from __future__ import annotations

import csv
import math
import random
from datetime import date, datetime, time, timedelta
from pathlib import Path


SEED = 20260813
ROW_COUNT = 8_000
START_DATE = date(2026, 1, 1)
DAYS = 90
ROOT = Path(__file__).resolve().parents[1]
DATA = ROOT / "data"


def write_csv(name: str, fieldnames: list[str], rows: list[dict]) -> None:
    DATA.mkdir(parents=True, exist_ok=True)
    with (DATA / name).open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(rows)


def weighted_choice(rng: random.Random, pairs: list[tuple[str, float]]) -> str:
    return rng.choices([value for value, _ in pairs], [weight for _, weight in pairs], k=1)[0]


def main() -> None:
    rng = random.Random(SEED)

    plants = [
        {"plant_code": "KUL", "plant_name": "Kuala Lumpur Assembly", "country": "Malaysia", "timezone_name": "Asia/Kuala_Lumpur"},
        {"plant_code": "PNG", "plant_name": "Penang Electronics", "country": "Malaysia", "timezone_name": "Asia/Kuala_Lumpur"},
    ]
    lines = [
        {"line_code": "KUL-L1", "plant_code": "KUL", "line_name": "KUL SMT Line 1"},
        {"line_code": "KUL-L2", "plant_code": "KUL", "line_name": "KUL SMT Line 2"},
        {"line_code": "PNG-L1", "plant_code": "PNG", "line_name": "PNG Final Assembly 1"},
        {"line_code": "PNG-L2", "plant_code": "PNG", "line_name": "PNG Final Assembly 2"},
    ]
    products = [
        {"product_code": "CTRL-A100", "product_name": "Industrial Controller A100", "product_family": "Controls", "target_cycle_seconds": 44.0},
        {"product_code": "SENS-B200", "product_name": "Smart Sensor B200", "product_family": "Sensors", "target_cycle_seconds": 36.0},
        {"product_code": "GW-C300", "product_name": "Edge Gateway C300", "product_family": "Gateways", "target_cycle_seconds": 58.0},
    ]
    stations = [
        {"station_code": "AOI-1", "station_name": "Automated Optical Inspection 1", "test_type": "AOI"},
        {"station_code": "AOI-2", "station_name": "Automated Optical Inspection 2", "test_type": "AOI"},
        {"station_code": "ICT-1", "station_name": "In-Circuit Test 1", "test_type": "ICT"},
        {"station_code": "ICT-2", "station_name": "In-Circuit Test 2", "test_type": "ICT"},
        {"station_code": "FCT-1", "station_name": "Functional Test 1", "test_type": "FCT"},
        {"station_code": "FCT-2", "station_name": "Functional Test 2", "test_type": "FCT"},
    ]
    failure_modes = [
        {"failure_code": "FM-SOLDER", "failure_category": "Assembly", "failure_description": "Solder bridge"},
        {"failure_code": "FM-OPEN", "failure_category": "Assembly", "failure_description": "Open circuit"},
        {"failure_code": "FM-COMP", "failure_category": "Material", "failure_description": "Component out of tolerance"},
        {"failure_code": "FM-FW", "failure_category": "Firmware", "failure_description": "Firmware load failure"},
        {"failure_code": "FM-CAL", "failure_category": "Calibration", "failure_description": "Calibration drift"},
        {"failure_code": "FM-COSMETIC", "failure_category": "Cosmetic", "failure_description": "Cosmetic defect"},
    ]

    # Lots span the whole analysis period and create stable joins to line/product dimensions.
    lots: list[dict] = []
    lot_lookup: dict[tuple[str, str, int], str] = {}
    for day_bucket in range(0, DAYS, 3):
        for line in lines:
            product = products[(day_bucket // 3 + len(line["line_code"])) % len(products)]
            code = f"LOT-{line['line_code'].replace('-', '')}-{day_bucket + 1:03d}"
            lot_lookup[(line["line_code"], product["product_code"], day_bucket // 3)] = code
            lots.append(
                {
                    "lot_code": code,
                    "line_code": line["line_code"],
                    "product_code": product["product_code"],
                    "planned_start_date": (START_DATE + timedelta(days=day_bucket)).isoformat(),
                }
            )

    raw_rows: list[dict] = []
    outcome_variants = {"PASS": ["PASS", "Pass", " pass ", "OK"], "FAIL": ["FAIL", "Fail", " fail ", "NG"]}
    for row_num in range(1, ROW_COUNT + 1):
        day_offset = rng.randrange(DAYS)
        tested_date = START_DATE + timedelta(days=day_offset)
        line = rng.choice(lines)
        bucket = day_offset // 3
        # Use the product assigned to that line's active 3-day lot.
        active_candidates = [key for key in lot_lookup if key[0] == line["line_code"] and key[2] == bucket]
        if not active_candidates:
            active_candidates = [key for key in lot_lookup if key[0] == line["line_code"]]
        _, product_code, lot_bucket = rng.choice(active_candidates)
        product = next(p for p in products if p["product_code"] == product_code)
        lot_code = lot_lookup[(line["line_code"], product_code, lot_bucket)]
        station = rng.choice(stations)
        shift = weighted_choice(rng, [("Day", 0.46), ("Evening", 0.34), ("Night", 0.20)])

        base_fail = 0.037
        if line["line_code"] == "KUL-L2":
            base_fail += 0.026
        if shift == "Night":
            base_fail += 0.014
        if product_code == "GW-C300":
            base_fail += 0.011
        if station["station_code"] == "AOI-2" and day_offset >= 55:
            base_fail += 0.045 + 0.0008 * (day_offset - 55)
        wave = 0.009 * math.sin(day_offset / 8.0)
        failed = rng.random() < max(0.01, base_fail + wave)

        failure_code = ""
        if failed:
            weights = [
                ("FM-SOLDER", 0.25),
                ("FM-OPEN", 0.20),
                ("FM-COMP", 0.17),
                ("FM-FW", 0.14),
                ("FM-CAL", 0.13),
                ("FM-COSMETIC", 0.11),
            ]
            if line["line_code"] == "KUL-L2" and day_offset >= 45:
                weights = [(code, weight * (2.5 if code == "FM-SOLDER" else 1.0)) for code, weight in weights]
            if station["station_code"] == "AOI-2" and day_offset >= 55:
                weights = [(code, weight * (3.2 if code == "FM-CAL" else 1.0)) for code, weight in weights]
            failure_code = weighted_choice(rng, weights)

        hour_range = {"Day": (7, 15), "Evening": (15, 23), "Night": (0, 7)}[shift]
        tested_at = datetime.combine(tested_date, time(rng.randrange(*hour_range), rng.randrange(60), rng.randrange(60)))
        target = float(product["target_cycle_seconds"])
        cycle = max(18.0, rng.gauss(target + (4.5 if failed else 0.0), 5.5))
        measurement = rng.gauss(5.0, 0.16 + (0.22 if failure_code == "FM-CAL" else 0.0))

        raw_rows.append(
            {
                "source_row_number": row_num,
                "serial_number": f"SN{tested_date:%y%m%d}{row_num:06d}",
                "lot_code": lot_code,
                "line_code": f" {line['line_code']} " if row_num % 31 == 0 else line["line_code"],
                "product_code": product_code.lower() if row_num % 37 == 0 else product_code,
                "station_code": f" {station['station_code']}" if row_num % 41 == 0 else station["station_code"],
                "shift_name": shift.lower() if row_num % 29 == 0 else shift,
                "tested_at_text": tested_at.strftime("%Y-%m-%d %H:%M:%S"),
                "outcome_text": rng.choice(outcome_variants["FAIL" if failed else "PASS"]),
                "failure_code": failure_code.lower() if failure_code and row_num % 43 == 0 else failure_code,
                "cycle_time_seconds_text": f" {cycle:.2f} " if row_num % 47 == 0 else f"{cycle:.2f}",
                "measurement_value_text": f"{measurement:.4f}",
                "lower_spec_limit_text": "4.5000",
                "upper_spec_limit_text": "5.5000",
                "operator_code": f"OP-{rng.randrange(1, 25):03d}",
            }
        )

    write_csv("plants.csv", list(plants[0]), plants)
    write_csv("lines.csv", list(lines[0]), lines)
    write_csv("products.csv", list(products[0]), products)
    write_csv("stations.csv", list(stations[0]), stations)
    write_csv("failure_modes.csv", list(failure_modes[0]), failure_modes)
    write_csv("production_lots.csv", list(lots[0]), lots)
    write_csv("raw_test_results.csv", list(raw_rows[0]), raw_rows)
    print(f"Generated {len(raw_rows):,} test records and {len(lots):,} production lots in {DATA}")


if __name__ == "__main__":
    main()
