# ─────────────────────────────────────────────
#  EV-Pulse Simulator  ·  config.py
# ─────────────────────────────────────────────

# ── Azure IoT Hub 연결 문자열 ──────────────────
# Azure Portal > IoT Hub > Devices > 해당 Device > Connection string 복사
IOT_HUB_CONNECTION_STRING = "HostName=<YOUR_IOT_HUB>.azure-devices.net;DeviceId=<DEVICE_ID>;SharedAccessKey=<KEY>"

# ── 전송 설정 ──────────────────────────────────
SEND_INTERVAL_SEC  = 1.0     # IoT Hub 전송 주기 (초)
ROWS_PER_SEND      = 10      # 1회 전송 시 CSV에서 건너뛸 행 수 (0.1s 샘플 → 1s 압축)
ANOMALY_PROB       = 0.01    # 이상 주입 확률 (1%)

# ── 차량 설정 ──────────────────────────────────
NUM_REAL_VEHICLES  = 70      # CSV 실제 차량 수 (A:32 + B:38)
NUM_SYN_VEHICLES   = 30      # 증강 차량 수 (A_syn:15 + B_syn:15)
NUM_VEHICLES       = NUM_REAL_VEHICLES + NUM_SYN_VEHICLES  # 100

# 이상 차량 VIN 목록 (Power BI 맵 클러스터링용, 강남/서초 고정)
# 실제 위험 비율 상위 5개: A_027(6.21%)→VIN-027, A_022(6.19%)→VIN-022,
# B_032(6.19%)→VIN-064, A_024(6.17%)→VIN-024, B_028(6.17%)→VIN-060
ANOMALY_VEHICLE_VINS = ["VIN-027", "VIN-022", "VIN-064", "VIN-024", "VIN-060"]

# CRITICAL 확정 연속 횟수 (3회 연속 위반 시 CRITICAL 확정)
CRITICAL_STREAK_THRESHOLD = 3

# ── 서울 위치 범위 ─────────────────────────────
LOCATION_NORMAL = {
    "lat_min": 37.45, "lat_max": 37.65,
    "lon_min": 126.85, "lon_max": 127.15,
}
LOCATION_ANOMALY = {
    "lat_min": 37.490, "lat_max": 37.510,   # 강남/서초 집중
    "lon_min": 127.020, "lon_max": 127.055,
}

# ── BMW 모델명 ─────────────────────────────────
BMW_MODELS = [
    "BMW i3 (60Ah)",
    "BMW i3 (94Ah)",
    "BMW i3s (94Ah)",
    "BMW i3 (120Ah)",
    "BMW i3s (120Ah)",
]

# ── bsi_label → status 변환 ───────────────────
STATUS_MAP = {
    0.0: "NORMAL",
    1.0: "WARNING",
    2.0: "CRITICAL",
    # status_name 문자열 대응
    "Normal":   "NORMAL",
    "Warning":  "WARNING",
    "Danger":   "CRITICAL",
}

# ── 이상 주입 수치 범위 ───────────────────────
ANOMALY_VOLTAGE_DROP  = (10.0, 30.0)   # 전압 하락 범위 [V]
ANOMALY_TEMP_RISE     = (5.0,  12.0)   # 온도 상승 범위 [°C]
ANOMALY_CURRENT_EXTRA = (3.0,  8.0)    # 전류 방전 가중 범위 [A]

# ── 가우시안 증강 (VIN-071~085, 15대) ─────────
GAUSSIAN_COUNT      = 15
# 각 컬럼 std 대비 노이즈 스케일 (8%)
GAUSSIAN_NOISE_SCALE = 0.08
# 노이즈를 추가할 수치 컬럼 목록
GAUSSIAN_NOISE_COLS = [
    "voltage", "current", "battery_temp", "ambient_temp",
    "delta_v", "delta_i",
    "joule_heating_stress", "thermal_temperature_70min",
    "thermal_stress",
    "Z_Delta_I", "Z_Delta_V", "Z_Thermal_Stress",
    "BSI", "Z_BSI",
]

# ── 열화 차량 (VIN-086~100, 15대) ────────────
DEGRADATION_COUNT   = 15
# 열화 기반으로 삼을 차량 (위험 비율 상위)
DEGRADATION_BASE_VEHICLES = [
    "VehicleA_027", "VehicleA_022", "VehicleB_032",
    "VehicleA_024", "VehicleB_028", "VehicleB_022",
    "VehicleA_014", "VehicleA_002", "VehicleA_001",
    "VehicleA_025",
]
# 열화 최대값 (trip 끝 기준 progress=1.0일 때)
DEGRADATION_VOLTAGE_DROP_MAX  = 25.0   # 전압 최대 하락 [V]
DEGRADATION_TEMP_RISE_MAX     = 10.0   # 온도 최대 상승 [°C]
DEGRADATION_BSI_AMPLIFY_MAX   = 4.0    # BSI 최대 배율 (1.0 → 4.0배)
DEGRADATION_BSI_ADD_MAX       = 3.0    # BSI 최대 가산값 (progress=1.0 시점에 +3.0)
DEGRADATION_STRESS_RISE_MAX   = 8.0    # thermal_stress 최대 증가
# 열화 차량 status 재판정 BSI 임계값
DEGRADATION_WARNING_BSI  = 1.2         # BSI > 이 값 → WARNING
DEGRADATION_CRITICAL_BSI = 3.0         # BSI > 이 값 → CRITICAL
