#!/usr/bin/env python3
"""
EV-Pulse Playback Simulator  v2
────────────────────────────────────────────────────────────────
역할: 원본 센서값 + 파생변수 실시간 계산 → Azure IoT Hub 전송

파이프라인:
  Simulator (raw + derived)
    → IoT Hub
    → Stream Analytics  (컬럼 라우팅 / 이상 원인 기준)
    → Azure ML          (Z-score · BSI 계산 · 정상/위험 판별)
    → Azure SQL         (ML 결과 + 위치/차량정보 저장)
    → HTML 대시보드

시뮬레이터가 계산하는 파생변수 (BSI 문서 기준):
  Delta_I              = I(t) − I(t−1)           [전류 변화량]
  Delta_V              = V(t) − V(t−1)           [전압 변화량]
  Joule_Heating_Stress = I(t)² × T(t)            [줄 발열 스트레스]

시뮬레이터가 계산하지 않는 것 (Azure ML 담당):
  Z_Delta_I / Z_Delta_V / Z_Thermal_Stress
  Z_Battery_Current / Z_Battery_Voltage / Z_BSI
  BSI / status (Normal · Warning · Critical)
────────────────────────────────────────────────────────────────
"""

import argparse
import json
import random
import time
from datetime import datetime, timezone
from pathlib import Path

import numpy as np
import pandas as pd

import config

# ── IoT Hub SDK ────────────────────────────────────────────────
try:
    from azure.iot.device import IoTHubDeviceClient, Message
    _SDK_AVAILABLE = True
except ImportError:
    _SDK_AVAILABLE = False


# ─────────────────────────────────────────────────────────────
#  VIN 매핑
# ─────────────────────────────────────────────────────────────

def build_vin_map(vehicle_ids: list[str]) -> dict[str, str]:
    """
    VehicleA_001~032 → VIN-001~032
    VehicleB_001~038 → VIN-033~070
    VehicleGaussian   → VIN-071~085
    VehicleDeg        → VIN-086~100
    """
    vin_map: dict[str, str] = {}
    a_ids = sorted(v for v in vehicle_ids if v.startswith("VehicleA_"))
    b_ids = sorted(v for v in vehicle_ids if v.startswith("VehicleB_"))

    for i, vid in enumerate(a_ids, start=1):
        vin_map[vid] = f"VIN-{i:03d}"
    offset = len(a_ids)
    for i, vid in enumerate(b_ids, start=1):
        vin_map[vid] = f"VIN-{offset + i:03d}"

    syn_start = offset + len(b_ids) + 1
    for i in range(1, config.GAUSSIAN_COUNT + 1):
        vin_map[f"VehicleGaussian_{i:03d}"] = f"VIN-{syn_start + i - 1:03d}"

    deg_start = syn_start + config.GAUSSIAN_COUNT
    for i in range(1, config.DEGRADATION_COUNT + 1):
        vin_map[f"VehicleDeg_{i:03d}"] = f"VIN-{deg_start + i - 1:03d}"

    return vin_map


# ─────────────────────────────────────────────────────────────
#  차량 메타 (모델명 / 위치)
# ─────────────────────────────────────────────────────────────

def build_vehicle_meta(vin_map: dict[str, str]) -> dict[str, dict]:
    rng = random.Random(42)
    meta: dict[str, dict] = {}
    for orig_id, vin in vin_map.items():
        is_anomaly = vin in config.ANOMALY_VEHICLE_VINS
        loc = config.LOCATION_ANOMALY if is_anomaly else config.LOCATION_NORMAL
        meta[vin] = {
            "model_name":        rng.choice(config.BMW_MODELS),
            "base_lat":          rng.uniform(loc["lat_min"], loc["lat_max"]),
            "base_lon":          rng.uniform(loc["lon_min"], loc["lon_max"]),
            "is_anomaly_vehicle": is_anomaly,
        }
    return meta


# ─────────────────────────────────────────────────────────────
#  가우시안 증강 차량 (VIN-071~085, 15대)
# ─────────────────────────────────────────────────────────────

def generate_gaussian_vehicles(
    real_data: dict[str, pd.DataFrame],
    rng: np.random.Generator,
) -> dict[str, pd.DataFrame]:
    """
    실제 차량 원본 센서 4개에 가우시안 노이즈 추가.
    파생변수(ΔI, ΔV, JHS)는 전송 시 실시간 계산하므로 여기서 수정 불필요.
    """
    all_df = pd.concat(real_data.values(), ignore_index=True)
    col_std = {
        col: float(all_df[col].std())
        for col in config.GAUSSIAN_NOISE_COLS
        if col in all_df.columns
    }

    base_ids = list(real_data.keys())
    syn: dict[str, pd.DataFrame] = {}

    for i in range(1, config.GAUSSIAN_COUNT + 1):
        syn_id  = f"VehicleGaussian_{i:03d}"
        base_id = base_ids[rng.integers(0, len(base_ids))]
        df = real_data[base_id].copy()

        for col, std in col_std.items():
            noise   = rng.normal(0.0, std * config.GAUSSIAN_NOISE_SCALE, size=len(df))
            df[col] = df[col] + noise

        # 물리적 클리핑
        df["voltage"]      = df["voltage"].clip(lower=280.0, upper=420.0)
        df["battery_temp"] = df["battery_temp"].clip(lower=-5.0, upper=50.0)

        df["vehicle_id"] = syn_id
        syn[syn_id] = df.reset_index(drop=True)

    print(f"[AUGMENT] 가우시안 증강 {len(syn)}대 생성 완료")
    return syn


# ─────────────────────────────────────────────────────────────
#  열화 차량 (VIN-086~100, 15대)
# ─────────────────────────────────────────────────────────────

def generate_degradation_vehicles(
    real_data: dict[str, pd.DataFrame],
    rng: np.random.Generator,
) -> dict[str, pd.DataFrame]:
    """
    원본 센서값(전압·온도)만 진행도(0→1)에 따라 열화 적용.
    ΔI / ΔV / JHS 는 열화된 센서값에서 전송 시 자동 재계산.
    BSI·status 판별은 Azure ML 담당.
    """
    base_pool = [v for v in config.DEGRADATION_BASE_VEHICLES if v in real_data]
    if not base_pool:
        base_pool = list(real_data.keys())

    syn: dict[str, pd.DataFrame] = {}

    for i in range(1, config.DEGRADATION_COUNT + 1):
        syn_id  = f"VehicleDeg_{i:03d}"
        base_id = base_pool[rng.integers(0, len(base_pool))]
        df = real_data[base_id].copy()
        n  = len(df)

        progress = np.linspace(0.0, 1.0, n)

        # 전압 하락 (배터리 노화 → 용량 감소)
        df["voltage"] = (
            df["voltage"] - config.DEGRADATION_VOLTAGE_DROP_MAX * progress
        ).clip(lower=250.0)

        # 온도 상승 (내부 저항 증가 → 발열 증가)
        df["battery_temp"] = (
            df["battery_temp"] + config.DEGRADATION_TEMP_RISE_MAX * progress
        ).clip(upper=60.0)

        # 결과: Joule_Heating_Stress = I² × T 가 후반부로 갈수록 자연 증가
        # → Azure ML에서 Z-score 계산 시 이상 탐지됨

        df["vehicle_id"] = syn_id
        syn[syn_id] = df.reset_index(drop=True)

    print(f"[AUGMENT] 열화 차량 {len(syn)}대 생성 완료")
    return syn


# ─────────────────────────────────────────────────────────────
#  CSV 로드
# ─────────────────────────────────────────────────────────────

# 시뮬레이터가 읽는 컬럼: 원본 센서 4개만
REQUIRED_COLS = [
    "vehicle_id",
    "voltage",        # Battery Voltage [V]
    "current",        # Battery Current [A]
    "battery_temp",   # Battery Temperature [°C]
    "ambient_temp",   # Ambient Temperature [°C]
]

def load_csv(csv_path: str) -> dict[str, pd.DataFrame]:
    print(f"[LOAD] {csv_path}")
    df = pd.read_csv(csv_path, low_memory=False)

    missing = [c for c in REQUIRED_COLS if c not in df.columns]
    if missing:
        raise ValueError(f"CSV에 필수 컬럼 없음: {missing}")

    split: dict[str, pd.DataFrame] = {}
    for vid, grp in df.groupby("vehicle_id"):
        split[str(vid)] = grp.reset_index(drop=True)

    print(f"[LOAD] {len(split)} 차량, 총 {len(df):,} 행 로드 완료")
    return split


# ─────────────────────────────────────────────────────────────
#  위치 헬퍼
# ─────────────────────────────────────────────────────────────

def _jitter_location(base_lat: float, base_lon: float) -> tuple[float, float]:
    return (
        round(base_lat + random.uniform(-0.001, 0.001), 6),
        round(base_lon + random.uniform(-0.001, 0.001), 6),
    )


# 서울 구별 경계 (lat_min, lat_max, lon_min, lon_max, region_id, region_name)
_SEOUL_DISTRICTS: list[tuple[float, float, float, float, int, str]] = [
    (37.488, 37.537, 127.018, 127.095, 101, "서울시 강남구"),
    (37.463, 37.493, 126.992, 127.052, 102, "서울시 서초구"),
    (37.496, 37.537, 127.083, 127.148, 103, "서울시 송파구"),
    (37.536, 37.556, 127.083, 127.148, 104, "서울시 강동구"),
    (37.514, 37.546, 126.872, 126.938, 105, "서울시 영등포구"),
    (37.450, 37.480, 126.870, 126.912, 106, "서울시 구로구"),
    (37.453, 37.470, 126.870, 126.905, 107, "서울시 금천구"),
    (37.460, 37.520, 126.850, 126.878, 108, "서울시 양천구"),
    (37.470, 37.500, 126.908, 126.958, 109, "서울시 관악구"),
    (37.498, 37.518, 126.930, 126.962, 110, "서울시 동작구"),
    (37.516, 37.556, 126.960, 127.018, 111, "서울시 용산구"),
    (37.548, 37.578, 126.958, 127.018, 112, "서울시 중구"),
    (37.562, 37.600, 126.938, 126.998, 113, "서울시 종로구"),
    (37.556, 37.582, 127.018, 127.072, 114, "서울시 성동구"),
    (37.528, 37.556, 127.072, 127.098, 115, "서울시 광진구"),
    (37.572, 37.608, 127.018, 127.058, 116, "서울시 동대문구"),
    (37.580, 37.630, 127.000, 127.050, 117, "서울시 성북구"),
    (37.630, 37.660, 127.040, 127.108, 118, "서울시 노원구"),
    (37.650, 37.680, 127.020, 127.070, 119, "서울시 도봉구"),
    (37.536, 37.582, 126.872, 126.938, 120, "서울시 마포구"),
    (37.572, 37.608, 126.920, 126.970, 121, "서울시 서대문구"),
    (37.598, 37.660, 126.878, 126.945, 122, "서울시 은평구"),
    (37.582, 37.630, 126.940, 126.998, 123, "서울시 강북구"),
]


def _region_from_latlon(lat: float, lon: float) -> tuple[int, str]:
    for lat_min, lat_max, lon_min, lon_max, rid, rname in _SEOUL_DISTRICTS:
        if lat_min <= lat <= lat_max and lon_min <= lon <= lon_max:
            return rid, rname
    return 1, "서울시"


# ─────────────────────────────────────────────────────────────
#  JSON 페이로드 빌드
# ─────────────────────────────────────────────────────────────

def build_payload(
    row:        pd.Series,
    vin:        str,
    meta:       dict,
    prev:       dict | None,   # 직전 전송값 {voltage, current}
    inject_anomaly: bool = False,
) -> dict:
    """
    원본 센서값 읽기 + 파생변수 실시간 계산 → IoT Hub 전송 payload

    파생변수 계산식 (BSI 문서 기준):
      Delta_I              = I(t) − I(t−1)      [A]
      Delta_V              = V(t) − V(t−1)      [V]
      Joule_Heating_Stress = I(t)² × T(t)       [A²·°C]

    주의: Z-score · BSI · status 는 Azure ML 담당 → 여기서 계산 안 함
    """
    now_iso = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")

    # ── 원본 센서값 읽기 ──────────────────────────
    voltage      = float(row["voltage"])
    current      = float(row["current"])
    battery_temp = float(row["battery_temp"])
    ambient_temp = float(row["ambient_temp"])

    # ── 파이프라인 테스트용 이상 센서값 주입 ────────
    # (실제 배포 시 제거 가능 — Azure ML이 자체적으로 탐지)
    if inject_anomaly:
        voltage      -= random.uniform(*config.ANOMALY_VOLTAGE_DROP)
        battery_temp += random.uniform(*config.ANOMALY_TEMP_RISE)
        current      -= random.uniform(*config.ANOMALY_CURRENT_EXTRA)

    # ── 파생변수 실시간 계산 ─────────────────────
    # prev 없음 (첫 전송) → 0.0 처리
    if prev is not None:
        delta_i = round(current      - prev["current"], 6)   # ΔI [A]
        delta_v = round(voltage      - prev["voltage"], 6)   # ΔV [V]
    else:
        delta_i = 0.0
        delta_v = 0.0

    # Joule_Heating_Stress = I² × T  (줄 발열 법칙 Q = I²RT 기반)
    joule_heating_stress = round((current ** 2) * battery_temp, 4)

    # ── 위치 ────────────────────────────────────
    lat, lon = _jitter_location(meta["base_lat"], meta["base_lon"])
    region_id, region_name = _region_from_latlon(lat, lon)

    return {
        # ── 차량 식별 ───────────────────────────
        "vehicle_id":   vin,
        "model_name":   meta["model_name"],
        "received_at":  now_iso,

        # ── 원본 센서값 (Raw Sensors) ───────────
        # Battery_Telemetry 테이블 대응
        "battery_voltage":  round(voltage,      4),
        "battery_current":  round(current,      4),
        "temperature":      round(battery_temp, 4),
        "ambient_temp":     round(ambient_temp, 4),

        # ── 파생변수 (Derived Variables) ────────
        # BSI 문서: ΔI(0.4830) · ΔV(0.2218) · JHS(0.1027) 주요 피처
        # Stream Analytics → Azure ML 입력값
        "delta_i":              delta_i,
        "delta_v":              delta_v,
        "joule_heating_stress": joule_heating_stress,

        # ── 위치 정보 ────────────────────────────
        "latitude":           lat,
        "longitude":          lon,
        "current_region_id":  region_id,
        "region_name":        region_name,

        # ── 운영 상태 ────────────────────────────
        "is_active":          1,
        "last_received_at":   now_iso,
    }


# ─────────────────────────────────────────────────────────────
#  메인 재생 루프
# ─────────────────────────────────────────────────────────────

def run(csv_path: str, dry_run: bool, interval: float, rows_per_send: int):
    # CSV 로드
    vehicle_data = load_csv(csv_path)

    # 합성 차량 생성 (고정 seed=42)
    rng = np.random.default_rng(seed=42)
    vehicle_data.update(generate_gaussian_vehicles(vehicle_data, rng))
    vehicle_data.update(generate_degradation_vehicles(vehicle_data, rng))

    # VIN 매핑 / 메타
    vin_map  = build_vin_map(list(vehicle_data.keys()))
    vin_meta = build_vehicle_meta(vin_map)

    # 차량별 상태
    cursors:     dict[str, int]  = {vid: 0    for vid in vehicle_data}
    prev_values: dict[str, dict] = {}   # {vid: {"voltage": ..., "current": ...}}

    # IoT Hub 클라이언트
    client = None
    if not dry_run:
        if not _SDK_AVAILABLE:
            raise RuntimeError("azure-iot-device 없음. pip install -r requirements.txt")
        client = IoTHubDeviceClient.create_from_connection_string(
            config.IOT_HUB_CONNECTION_STRING
        )
        client.connect()
        print("[IOT] IoT Hub 연결 완료")

    print(f"[START] 차량 {len(vehicle_data)}대 / 전송 간격 {interval}s / rows_per_send={rows_per_send}")
    print("[START] Ctrl+C 로 종료\n")

    sent_total = 0
    try:
        while True:
            tick_start = time.time()

            for vid, df in vehicle_data.items():
                vin  = vin_map.get(vid, vid)
                meta = vin_meta.get(vin, {
                    "model_name": "BMW i3 (120Ah)",
                    "base_lat": 37.55, "base_lon": 127.00,
                    "is_anomaly_vehicle": False,
                })

                idx = cursors[vid]
                row = df.iloc[idx]

                # 이상 센서값 주입 여부 (파이프라인 테스트용)
                inject = random.random() < config.ANOMALY_PROB

                payload = build_payload(
                    row  = row,
                    vin  = vin,
                    meta = meta,
                    prev = prev_values.get(vid),
                    inject_anomaly = inject,
                )

                # 직전 전송값 저장 (다음 tick의 ΔI, ΔV 계산용)
                prev_values[vid] = {
                    "voltage": float(row["voltage"]),
                    "current": float(row["current"]),
                }

                if dry_run:
                    print(json.dumps(payload, ensure_ascii=False))
                else:
                    msg = Message(json.dumps(payload))
                    msg.content_type     = "application/json"
                    msg.content_encoding = "utf-8"
                    client.send_message(msg)

                sent_total += 1
                cursors[vid] = (idx + rows_per_send) % len(df)

            elapsed   = time.time() - tick_start
            sleep_sec = max(0.0, interval - elapsed)
            if sleep_sec > 0:
                time.sleep(sleep_sec)

            if sent_total % (len(vehicle_data) * 10) == 0:
                print(f"[INFO] 누적 전송 {sent_total:,} 건")

    except KeyboardInterrupt:
        print(f"\n[STOP] 종료 — 총 전송 {sent_total:,} 건")
    finally:
        if client:
            client.disconnect()


# ─────────────────────────────────────────────────────────────
#  CLI
# ─────────────────────────────────────────────────────────────

def main():
    parser = argparse.ArgumentParser(description="EV-Pulse BMW Playback Simulator v2")
    parser.add_argument(
        "--csv",
        default="TripAB_all_processed_sampled_60000_window_combined.csv",
        help="원본 CSV 경로 (기본값: 스크립트와 같은 폴더)",
    )
    parser.add_argument("--dry-run",      action="store_true", help="콘솔 출력만 (IoT Hub 미전송)")
    parser.add_argument("--interval",     type=float, default=config.SEND_INTERVAL_SEC)
    parser.add_argument("--rows-per-send",type=int,   default=config.ROWS_PER_SEND)
    args = parser.parse_args()

    csv_path = Path(args.csv)
    if not csv_path.exists():
        alt = Path(__file__).parent / args.csv
        if alt.exists():
            csv_path = alt
        else:
            raise FileNotFoundError(f"CSV 없음: {args.csv}")

    run(
        csv_path      = str(csv_path),
        dry_run       = args.dry_run,
        interval      = args.interval,
        rows_per_send = args.rows_per_send,
    )


if __name__ == "__main__":
    main()
