# ─────────────────────────────────────────────
#  EV-Pulse Simulator v2  ·  config.py
#
#  역할 분담
#  ┌─ 시뮬레이터 ──────────────────────────────┐
#  │  원본 센서값 + 파생변수(ΔI, ΔV, JHS) 생성  │
#  └───────────────────────────────────────────┘
#        ↓ IoT Hub → Stream Analytics
#  ┌─ Azure ML ────────────────────────────────┐
#  │  Z-score 정규화 → BSI 계산 → 상태 판별     │
#  └───────────────────────────────────────────┘
# ─────────────────────────────────────────────

# ── Azure IoT Hub 연결 문자열 ──────────────────
# 실제 값은 Python_Simulator/.env 파일에 저장 (gitignore 처리됨)
# 로컬 실행 전 .env 파일에 아래 형식으로 입력:
#   IOT_HUB_CONNECTION_STRING=HostName=...;DeviceId=...;SharedAccessKey=...
import os
from dotenv import load_dotenv

load_dotenv(dotenv_path=os.path.join(os.path.dirname(__file__), '.env'))
IOT_HUB_CONNECTION_STRING = os.environ.get('IOT_HUB_CONNECTION_STRING', '')

# ── 전송 설정 ──────────────────────────────────
SEND_INTERVAL_SEC  = 1.0     # IoT Hub 전송 주기 (초)
ROWS_PER_SEND      = 10      # CSV cursor 건너뛸 행 수 (0.1s 샘플 → 1s 압축)
ANOMALY_PROB       = 0.01    # 이상 센서값 주입 확률 (1%) — 파이프라인 테스트용

# ── 차량 설정 ──────────────────────────────────
NUM_REAL_VEHICLES  = 70
NUM_SYN_VEHICLES   = 30
NUM_VEHICLES       = NUM_REAL_VEHICLES + NUM_SYN_VEHICLES  # 100

# 이상 차량 VIN (Power BI 맵 강남/서초 클러스터링 — 위험 비율 실제 상위 5개)
ANOMALY_VEHICLE_VINS = ["VIN-027", "VIN-022", "VIN-064", "VIN-024", "VIN-060"]

# ── 서울 위치 범위 ─────────────────────────────
LOCATION_NORMAL = {
    "lat_min": 37.47, "lat_max": 37.62,
    "lon_min": 126.88, "lon_max": 127.12,
}
LOCATION_ANOMALY = {
    "lat_min": 37.490, "lat_max": 37.510,
    "lon_min": 127.020, "lon_max": 127.055,
}

# ── BMW 모델명 ─────────────────────────────────
BMW_MODELS = [
    "BMW i4 eDrive40",
    "BMW iX1 xDrive30",
    "BMW i7 xDrive60",
    "BMW i5 eDrive40",
    "BMW iX xDrive50",
]

# ── 이상 센서값 주입 범위 (파이프라인 테스트용) ──
# BSI/status 주입 없음 — Azure ML이 판별
ANOMALY_VOLTAGE_DROP  = (10.0, 30.0)   # 전압 하락 [V]
ANOMALY_TEMP_RISE     = (5.0,  12.0)   # 온도 상승 [°C]
ANOMALY_CURRENT_EXTRA = (3.0,  8.0)    # 방전 전류 가중 [A]

# ── 가우시안 증강 (VIN-071~085, 15대) ─────────
GAUSSIAN_COUNT       = 15
GAUSSIAN_NOISE_SCALE = 0.08   # 각 컬럼 std 대비 노이즈 비율 (8%)
# 원본 센서 4개만 노이즈 추가 (파생변수는 노이즈 적용 후 실시간 재계산)
GAUSSIAN_NOISE_COLS  = ["voltage", "current", "battery_temp", "ambient_temp"]

# ── 열화 차량 (VIN-086~100, 15대) ────────────
DEGRADATION_COUNT   = 15
# 위험 비율 상위 기반 차량 풀
DEGRADATION_BASE_VEHICLES = [
    "VehicleA_027", "VehicleA_022", "VehicleB_032",
    "VehicleA_024", "VehicleB_028", "VehicleB_022",
    "VehicleA_014", "VehicleA_002", "VehicleA_001",
    "VehicleA_025",
]
# 열화 최대값 (progress=1.0 기준) — 원본 센서값만 열화
DEGRADATION_VOLTAGE_DROP_MAX = 25.0   # 전압 최대 하락 [V]
DEGRADATION_TEMP_RISE_MAX    = 10.0   # 온도 최대 상승 [°C]
# 파생변수(ΔI, ΔV, JHS)는 열화된 센서값에서 자동 계산 → BSI는 Azure ML 담당
