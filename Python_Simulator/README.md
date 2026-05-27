# EV-Pulse BMW Playback Simulator

전처리 완료 BMW CSV를 실시간 차량 데이터처럼 Azure IoT Hub로 재생하는 Playback Simulator.

## 폴더 구조

```
Python_Simulator/
  ├── TripAB_all_processed_sampled_60000_window_combined.csv   ← CSV 파일 여기에 배치
  ├── simulator.py        메인 재생기
  ├── config.py           설정값 (IoT Hub 연결, 임계값, 증강 파라미터)
  ├── requirements.txt
  └── README.md
```

## 설치

```bash
pip install -r requirements.txt
```

## 실행

```bash
# CSV가 스크립트와 같은 폴더에 있을 때 (기본값 — 경로 생략 가능)
python3 simulator.py --dry-run

# CSV 경로 직접 지정
python3 simulator.py --csv TripAB_all_processed_sampled_60000_window_combined.csv --dry-run

# IoT Hub 실제 전송 (config.py에 연결 문자열 설정 필요)
python3 simulator.py

# 전송 속도 조정 (0.5초마다 전송)
python3 simulator.py --interval 0.5

# rows-per-send 조정 (CSV cursor를 5행씩 건너뜀 → 더 촘촘한 재생)
python3 simulator.py --rows-per-send 5
```

> **`--rows-per-send`** 는 "메시지 N개 전송"이 아니라, 각 차량의 CSV cursor를 N행씩 건너뛰는 값입니다.
> 기본값 10은 "0.1s 샘플링 데이터를 1s 단위로 압축"을 의미합니다.
> 1초당 전송 메시지 수는 항상 **차량 수(100개)** 입니다.

## IoT Hub 연결 설정

`config.py`의 `IOT_HUB_CONNECTION_STRING`을 Azure Portal에서 복사한 Device 연결 문자열로 교체:

```
Azure Portal > IoT Hub > Devices > {device} > Primary Connection String
```

## 데이터 흐름

```
전처리 CSV (200,000행, 70 실차량)
  + 가우시안 증강 15대 생성 (VIN-071~085)
  + 열화 차량   15대 생성 (VIN-086~100)
  ──────────────────────────────────────
  총 100대 → VIN 매핑 → 1초 간격 전송

  각 차량 전송 시:
    1. CSV 현재 행 읽기 (cursor를 rows_per_send=10 행 전진)
    2. 1% 확률 이상 주입 (전압↓ / 온도↑ / 전류↑)
    3. CRITICAL 3회 연속 확정 로직 적용
       - 비정상(WARNING 이상) 누적 < 3회  →  WARNING (is_anomaly=0)
       - 비정상 누적 ≥ 3회               →  CRITICAL 확정 (is_anomaly=1)
       - 정상 수신 시 streak 초기화
    4. Alert_Log 컬럼 포함 JSON 빌드
    5. IoT Hub 전송

  IoT Hub → Stream Analytics → Azure SQL → Power BI
```

## VIN 매핑

| 원본 vehicle_id       | VIN         | 설명                         |
|----------------------|-------------|------------------------------|
| VehicleA_001~032     | VIN-001~032 | 여름 차량 32대               |
| VehicleB_001~038     | VIN-033~070 | 겨울 차량 38대               |
| VehicleGaussian_001~015 | VIN-071~085 | 가우시안 증강 차량 15대      |
| VehicleDeg_001~015   | VIN-086~100 | 열화 시뮬레이션 차량 15대    |

### 이상 차량 5대 (Power BI 맵 강남/서초 클러스터링)

실제 위험(bsi_label=2) 비율 상위 5개 차량:

| VIN     | 원본 차량      | 위험 비율 |
|---------|---------------|---------|
| VIN-027 | VehicleA_027  | 6.21%   |
| VIN-022 | VehicleA_022  | 6.19%   |
| VIN-064 | VehicleB_032  | 6.19%   |
| VIN-024 | VehicleA_024  | 6.17%   |
| VIN-060 | VehicleB_028  | 6.17%   |

## JSON 페이로드 → SQL 테이블 매핑

| JSON 키                | SQL 테이블.컬럼                                      |
|------------------------|-----------------------------------------------------|
| vehicle_id             | Vehicle.vehicle_id                                  |
| model_name             | VehicleModel.model_name                             |
| received_at            | Battery_Telemetry.received_at / BSI_Feature_Log.received_at |
| battery_voltage        | Battery_Telemetry.battery_voltage                   |
| battery_current        | Battery_Telemetry.battery_current                   |
| temperature            | Battery_Telemetry.temperature                       |
| bsi                    | Battery_Telemetry.bsi / BSI_Feature_Log.bsi         |
| status                 | Battery_Telemetry.status / Vehicle_Current_Status.status |
| latitude / longitude   | Battery_Telemetry / Vehicle_Current_Status          |
| delta_v / delta_i      | BSI_Feature_Log.delta_v / delta_i                   |
| thermal_stress         | BSI_Feature_Log.thermal_stress                      |
| z_delta_i/v/thermal    | BSI_Feature_Log.z_delta_i / z_delta_v / z_thermal_stress |
| current_bsi            | Vehicle_Current_Status.current_bsi                  |
| last_received_at       | Vehicle_Current_Status.last_received_at             |
| is_active              | Vehicle_Current_Status.is_active                    |
| current_region_id      | Vehicle_Current_Status.current_region_id            |
| is_anomaly=1           | Alert_Log INSERT 트리거 (Stream Analytics)          |
| alert_time             | Alert_Log.alert_time                                |
| alert_type             | Alert_Log.alert_type                                |
| alert_level            | Alert_Log.alert_level                               |
| message                | Alert_Log.message                                   |
| is_sent_teams          | Alert_Log.is_sent_teams                             |

> **Vehicle_Current_Status 주의**: Stream Analytics SQL output은 INSERT 전용입니다.
> `staging_current_status`에 append 후 SQL MERGE 트리거로 upsert 처리를 권장합니다.

> **Vehicle.model_id / region_id / vehicle_number**: simulator payload에 없는 FK 컬럼은
> SQL seed 테이블에서 사전 등록하거나 Stream Analytics에서 JOIN으로 결합합니다.
