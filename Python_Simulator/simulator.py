#!/usr/bin/env python3
"""
EV-Pulse Playback Simulator
전처리 완료 BMW CSV → VIN 부여 → JSON → Azure IoT Hub
증강: 가우시안 15대 (VIN-071~085) + 열화 15대 (VIN-086~100)
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

# ── IoT Hub SDK (dry-run이면 import 불필요) ────────────────────────────────
try:
    from azure.iot.device import IoTHubDeviceClient, Message
    _SDK_AVAILABLE = True
except ImportError:
    _SDK_AVAILABLE = False


# ─────────────────────────────────────────────────────────────────────────────
#  VIN 매핑 빌드
# ─────────────────────────────────────────────────────────────────────────────

def build_vin_map(vehicle_ids: list[str]) -> dict[str, str]:
    """
    VehicleA_001~032 → VIN-001~032
    VehicleB_001~038 → VIN-033~070
    A_syn / B_syn    → VIN-071~100 (CSV에 없으면 합성 차량으로만 존재)
    """
    vin_map: dict[str, str] = {}
    a_ids = sorted(v for v in vehicle_ids if v.startswith("VehicleA_"))
    b_ids = sorted(v for v in vehicle_ids if v.startswith("VehicleB_"))

    for i, vid in enumerate(a_ids, start=1):
        vin_map[vid] = f"VIN-{i:03d}"
    offset = len(a_ids)
    for i, vid in enumerate(b_ids, start=1):
        vin_map[vid] = f"VIN-{offset + i:03d}"

    # 가우시안 증강 차량 VIN-071~085
    syn_start = offset + len(b_ids) + 1
    for i in range(1, config.GAUSSIAN_COUNT + 1):
        vin_map[f"VehicleGaussian_{i:03d}"] = f"VIN-{syn_start + i - 1:03d}"

    # 열화 차량 VIN-086~100
    deg_start = syn_start + config.GAUSSIAN_COUNT
    for i in range(1, config.DEGRADATION_COUNT + 1):
        vin_map[f"VehicleDeg_{i:03d}"] = f"VIN-{deg_start + i - 1:03d}"

    return vin_map


# ─────────────────────────────────────────────────────────────────────────────
#  모델명 / 위치 랜덤 부여 (VIN당 고정)
# ─────────────────────────────────────────────────────────────────────────────

def build_vehicle_meta(vin_map: dict[str, str]) -> dict[str, dict]:
    """각 VIN에 BMW 모델명 + 기본 위치를 고정 배정한다."""
    rng = random.Random(42)
    meta: dict[str, dict] = {}
    for orig_id, vin in vin_map.items():
        is_anomaly_vehicle = vin in config.ANOMALY_VEHICLE_VINS
        loc = config.LOCATION_ANOMALY if is_anomaly_vehicle else config.LOCATION_NORMAL
        meta[vin] = {
            "model_name": rng.choice(config.BMW_MODELS),
            "base_lat":   rng.uniform(loc["lat_min"], loc["lat_max"]),
            "base_lon":   rng.uniform(loc["lon_min"], loc["lon_max"]),
            "is_anomaly_vehicle": is_anomaly_vehicle,
        }
    return meta


# ─────────────────────────────────────────────────────────────────────────────
#  CSV 로드 및 vehicle_id별 분리
# ─────────────────────────────────────────────────────────────────────────────

# ─────────────────────────────────────────────────────────────────────────────
#  가우시안 증강 차량 생성
# ─────────────────────────────────────────────────────────────────────────────

def generate_gaussian_vehicles(
    real_data: dict[str, pd.DataFrame],
    rng: np.random.Generator,
) -> dict[str, pd.DataFrame]:
    """
    실제 차량 데이터를 기반으로 가우시안 노이즈를 더해 15대 합성 차량을 생성한다.
    각 컬럼의 전체 std × GAUSSIAN_NOISE_SCALE 을 σ로 사용한다.
    """
    # 전체 데이터 합쳐서 컬럼별 std 계산
    all_df = pd.concat(real_data.values(), ignore_index=True)
    col_std: dict[str, float] = {
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
            noise = rng.normal(0.0, std * config.GAUSSIAN_NOISE_SCALE, size=len(df))
            df[col] = df[col] + noise

        # 물리적으로 불가능한 값 클리핑
        if "voltage" in df.columns:
            df["voltage"] = df["voltage"].clip(lower=280.0, upper=420.0)
        if "battery_temp" in df.columns:
            df["battery_temp"] = df["battery_temp"].clip(lower=-5.0, upper=50.0)
        if "BSI" in df.columns:
            df["BSI"] = df["BSI"].clip(lower=0.0)

        df["vehicle_id"] = syn_id
        syn[syn_id] = df.reset_index(drop=True)

    print(f"[AUGMENT] 가우시안 증강 {len(syn)}대 생성 완료")
    return syn


# ─────────────────────────────────────────────────────────────────────────────
#  열화 차량 생성
# ─────────────────────────────────────────────────────────────────────────────

def generate_degradation_vehicles(
    real_data: dict[str, pd.DataFrame],
    rng: np.random.Generator,
) -> dict[str, pd.DataFrame]:
    """
    위험 비율 높은 차량을 기반으로 진행도(progress 0→1)에 따라
    전압 하락 / BSI 증폭 / 온도 상승을 적용해 15대 열화 차량을 생성한다.
    status 라벨은 degraded BSI 기준으로 재판정한다.
    """
    # 기반 차량 풀 (config에 없으면 전체 real_data에서 랜덤)
    base_pool = [v for v in config.DEGRADATION_BASE_VEHICLES if v in real_data]
    if not base_pool:
        base_pool = list(real_data.keys())

    syn: dict[str, pd.DataFrame] = {}

    for i in range(1, config.DEGRADATION_COUNT + 1):
        syn_id  = f"VehicleDeg_{i:03d}"
        base_id = base_pool[rng.integers(0, len(base_pool))]
        df = real_data[base_id].copy()
        n   = len(df)

        # 진행도 배열 (0.0 → 1.0)
        progress = np.linspace(0.0, 1.0, n)

        # 전압 하락: 최대 DEGRADATION_VOLTAGE_DROP_MAX V 감소
        v_drop = config.DEGRADATION_VOLTAGE_DROP_MAX * progress
        df["voltage"] = (df["voltage"] - v_drop).clip(lower=250.0)

        # 온도 상승: 최대 DEGRADATION_TEMP_RISE_MAX °C 증가
        t_rise = config.DEGRADATION_TEMP_RISE_MAX * progress
        df["battery_temp"] = (df["battery_temp"] + t_rise).clip(upper=60.0)

        # BSI 증폭: 배율(×) + 가산(+) 조합 → 기저값 무관하게 후반 CRITICAL 보장
        bsi_mult = 1.0 + (config.DEGRADATION_BSI_AMPLIFY_MAX - 1.0) * progress
        bsi_add  = config.DEGRADATION_BSI_ADD_MAX * progress
        df["BSI"]   = (df["BSI"] * bsi_mult + bsi_add).clip(lower=0.0)
        df["Z_BSI"] = (df["Z_BSI"] * bsi_mult + bsi_add)

        # thermal_stress 증가
        stress_rise = config.DEGRADATION_STRESS_RISE_MAX * progress
        df["thermal_stress"]   = df["thermal_stress"]  + stress_rise
        df["Z_Thermal_Stress"] = df["Z_Thermal_Stress"] + stress_rise

        # degraded BSI 기준으로 status 라벨 재판정
        def _relabel(bsi_val: float) -> float:
            if bsi_val > config.DEGRADATION_CRITICAL_BSI:
                return 2.0
            if bsi_val > config.DEGRADATION_WARNING_BSI:
                return 1.0
            return 0.0

        df["current_status_label"] = df["BSI"].apply(_relabel)

        df["vehicle_id"] = syn_id
        syn[syn_id] = df.reset_index(drop=True)

    print(f"[AUGMENT] 열화 차량 {len(syn)}대 생성 완료")
    return syn


REQUIRED_COLS = [
    "vehicle_id",
    "voltage", "current", "battery_temp", "ambient_temp",
    "delta_v", "delta_i",
    "joule_heating_stress", "thermal_temperature_70min",
    "thermal_stress",
    "Z_Delta_I", "Z_Delta_V",
    "Z_Battery_Current", "Z_Battery_Voltage",
    "Z_Thermal_Stress", "Z_Joule_Heating_Stress",
    "BSI", "Z_BSI",
    "current_status_label",
]

def load_csv(csv_path: str) -> dict[str, pd.DataFrame]:
    """CSV를 읽어 vehicle_id별 DataFrame dict로 반환한다."""
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


# ─────────────────────────────────────────────────────────────────────────────
#  JSON 페이로드 빌드
# ─────────────────────────────────────────────────────────────────────────────

def _jitter_location(base_lat: float, base_lon: float) -> tuple[float, float]:
    """실제 이동처럼 위치에 미세 지터를 준다 (±0.001°)."""
    return (
        round(base_lat + random.uniform(-0.001, 0.001), 6),
        round(base_lon + random.uniform(-0.001, 0.001), 6),
    )


def _region_from_latlon(lat: float, lon: float) -> int:
    """위경도 → Region.region_id 변환. SQL Region 테이블 예시 데이터 기준."""
    if 37.490 <= lat <= 37.530 and 127.020 <= lon <= 127.090:
        return 101  # 강남구
    if 37.540 <= lat <= 37.580 and 126.880 <= lon <= 126.930:
        return 102  # 마포구
    return 1        # 서울 (기본)


def build_payload(
    row: pd.Series,
    vin: str,
    meta: dict,
    rows_per_send: int,
    anomaly_prob: float,
) -> dict:
    """
    CSV 한 행 + 메타 → IoT Hub 전송용 JSON dict.
    status / is_anomaly는 run() 루프의 streak 로직에서 최종 확정된다.
    """

    now_iso = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")

    # ── 센서 값 읽기 ──────────────────────────────
    voltage     = float(row["voltage"])
    current_a   = float(row["current"])
    temperature = float(row["battery_temp"])
    ambient     = float(row["ambient_temp"])
    bsi         = float(row["BSI"])
    z_bsi       = float(row["Z_BSI"])
    label       = float(row["current_status_label"])
    status      = config.STATUS_MAP.get(label, "NORMAL")

    delta_v          = float(row["delta_v"])
    delta_i          = float(row["delta_i"])
    thermal_stress   = float(row["thermal_stress"])
    joule_stress     = float(row["joule_heating_stress"])
    thermal_70min    = float(row["thermal_temperature_70min"])
    z_delta_i        = float(row["Z_Delta_I"])
    z_delta_v        = float(row["Z_Delta_V"])
    z_thermal_stress = float(row["Z_Thermal_Stress"])

    # ── 이상 주입 (1% 확률) ───────────────────────
    alert_type = "BATTERY_STRESS"
    is_anomaly = 0
    if random.random() < anomaly_prob:
        voltage     -= random.uniform(*config.ANOMALY_VOLTAGE_DROP)
        temperature += random.uniform(*config.ANOMALY_TEMP_RISE)
        current_a   -= random.uniform(*config.ANOMALY_CURRENT_EXTRA)
        status       = "CRITICAL"
        alert_type   = "RANDOM_INJECTION"

    # bsi_label=2(Danger) → 위반으로 표시 (streak 판정은 run()에서)
    if label == 2.0:
        is_anomaly = 1

    lat, lon = _jitter_location(meta["base_lat"], meta["base_lon"])
    region_id = _region_from_latlon(lat, lon)

    return {
        # Vehicle / VehicleModel
        "vehicle_id":   vin,
        "model_name":   meta["model_name"],

        # 공통 타임스탬프
        "received_at":  now_iso,

        # Battery_Telemetry
        "battery_voltage":  round(voltage,     4),
        "battery_current":  round(current_a,   4),
        "temperature":      round(temperature, 4),
        "bsi":              round(bsi,          6),
        "status":           status,
        "latitude":         lat,
        "longitude":        lon,

        # BSI_Feature_Log
        "delta_v":           round(delta_v,          6),
        "delta_i":           round(delta_i,          6),
        "thermal_stress":    round(thermal_stress,    6),
        "z_delta_i":         round(z_delta_i,         6),
        "z_delta_v":         round(z_delta_v,         6),
        "z_thermal_stress":  round(z_thermal_stress,  6),

        # Vehicle_Current_Status
        "current_bsi":        round(bsi, 6),
        "last_received_at":   now_iso,
        "is_active":          1,
        "current_region_id":  region_id,

        # Alert_Log (is_anomaly=1일 때 Stream Analytics가 INSERT 트리거)
        "is_anomaly":    is_anomaly,
        "alert_time":    now_iso,
        "alert_type":    alert_type,
        "alert_level":   status,
        "message":       f"{vin} battery status: {status}",
        "is_sent_teams": 0,

        # 파이프라인 디버깅용 (SQL 테이블 없음)
        "ambient_temp":           round(ambient,      4),
        "joule_heating_stress":   round(joule_stress, 4),
        "thermal_temp_70min":     round(thermal_70min, 4),
        "z_bsi":                  round(z_bsi,         6),
    }


# ─────────────────────────────────────────────────────────────────────────────
#  메인 재생 루프
# ─────────────────────────────────────────────────────────────────────────────

def run(csv_path: str, dry_run: bool, interval: float, rows_per_send: int):
    # CSV 로드
    vehicle_data = load_csv(csv_path)

    # 합성 차량 생성 (고정 시드로 재현 가능)
    rng = np.random.default_rng(seed=42)
    vehicle_data.update(generate_gaussian_vehicles(vehicle_data, rng))
    vehicle_data.update(generate_degradation_vehicles(vehicle_data, rng))

    # VIN 매핑 / 메타 (합성 차량 포함)
    vin_map   = build_vin_map(list(vehicle_data.keys()))
    vin_meta  = build_vehicle_meta(vin_map)

    # 차량별 현재 행 인덱스 / CRITICAL 연속 횟수
    cursors: dict[str, int] = {vid: 0 for vid in vehicle_data}
    streaks: dict[str, int] = {vid: 0 for vid in vehicle_data}

    # IoT Hub 클라이언트 초기화
    client = None
    if not dry_run:
        if not _SDK_AVAILABLE:
            raise RuntimeError(
                "azure-iot-device 패키지가 없습니다. pip install -r requirements.txt"
            )
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

                payload = build_payload(
                    row, vin, meta,
                    rows_per_send=rows_per_send,
                    anomaly_prob=config.ANOMALY_PROB,
                )

                # ── CRITICAL 3회 연속 확정 로직 ──────────────
                tentative_status = payload["status"]
                if tentative_status != "NORMAL":
                    streaks[vid] += 1
                else:
                    streaks[vid] = 0

                streak = streaks[vid]
                if streak >= config.CRITICAL_STREAK_THRESHOLD:
                    # 3회 연속 위반 → CRITICAL 확정
                    payload["status"]      = "CRITICAL"
                    payload["is_anomaly"]  = 1
                    payload["alert_level"] = "CRITICAL"
                    payload["message"]     = (
                        f"{vin} CRITICAL confirmed "
                        f"({streak} consecutive violations)"
                    )
                elif tentative_status != "NORMAL" and streak < config.CRITICAL_STREAK_THRESHOLD:
                    # 연속 미달 → WARNING 유지 (아직 CRITICAL 미확정)
                    payload["status"]      = "WARNING"
                    payload["is_anomaly"]  = 0
                    payload["alert_level"] = "WARNING"
                    payload["message"]     = (
                        f"{vin} WARNING (streak {streak}/"
                        f"{config.CRITICAL_STREAK_THRESHOLD})"
                    )
                # ────────────────────────────────────────────

                if dry_run:
                    print(json.dumps(payload, ensure_ascii=False))
                else:
                    msg = Message(json.dumps(payload))
                    msg.content_type     = "application/json"
                    msg.content_encoding = "utf-8"
                    client.send_message(msg)

                sent_total += 1

                # rows_per_send 행 건너뜀, 끝나면 처음부터
                cursors[vid] = (idx + rows_per_send) % len(df)

            # 전송 주기 유지
            elapsed = time.time() - tick_start
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


# ─────────────────────────────────────────────────────────────────────────────
#  CLI 진입점
# ─────────────────────────────────────────────────────────────────────────────

def main():
    parser = argparse.ArgumentParser(description="EV-Pulse BMW Playback Simulator")
    parser.add_argument(
        "--csv",
        default="TripAB_all_processed_sampled_60000_window_combined.csv",
        help="전처리 완료 CSV 경로 (기본값: 스크립트와 같은 폴더)",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="IoT Hub 전송 없이 JSON을 콘솔에 출력",
    )
    parser.add_argument(
        "--interval",
        type=float,
        default=config.SEND_INTERVAL_SEC,
        help="전송 간격(초), 기본값=1.0",
    )
    parser.add_argument(
        "--rows-per-send",
        type=int,
        default=config.ROWS_PER_SEND,
        help="1회 전송 시 CSV 건너뛸 행 수, 기본값=10",
    )
    args = parser.parse_args()

    csv_path = Path(args.csv)
    if not csv_path.exists():
        # 시뮬레이터 디렉토리 루트에 있는 경우 자동 탐색
        alt = Path(__file__).parent / args.csv
        if alt.exists():
            csv_path = alt
        else:
            raise FileNotFoundError(f"CSV 파일을 찾을 수 없음: {args.csv}")

    run(
        csv_path   = str(csv_path),
        dry_run    = args.dry_run,
        interval   = args.interval,
        rows_per_send = args.rows_per_send,
    )


if __name__ == "__main__":
    main()
