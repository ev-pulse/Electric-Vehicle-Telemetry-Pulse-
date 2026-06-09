"""
EV-Pulse Azure ML Deployment · register_and_deploy_model.py

역할
┌─ Model Artifact ───────────────────────────┐
│  model.pkl + feature schema + threshold 저장 │
└────────────────────────────────────────────┘
        ↓ Register
┌─ Azure ML Workspace ───────────────────────┐
│  모델 아티팩트 등록 및 버전 관리              │
└────────────────────────────────────────────┘
        ↓ Deploy
┌─ Managed Online Endpoint ──────────────────┐
│  score.py 기반 실시간 추론 API 배포          │
└────────────────────────────────────────────┘

주요 작업
1. 학습된 LightGBM 모델 및 추론 메타데이터 저장
2. Azure ML Workspace에 모델 아티팩트 등록
3. Managed Online Endpoint 생성
4. conda.yaml과 score.py를 사용한 배포 환경 구성
5. Endpoint 트래픽 연결
6. 샘플 Payload를 통한 추론 테스트

보안 처리
- 실제 Azure 구독 ID, Workspace, Endpoint URI, Key 값은 placeholder로 대체
- model.pkl 및 outputs/ 폴더는 GitHub에 업로드하지 않음
"""

# ====================================
# [1] 모델 저장
# ====================================
from pathlib import Path
import os, json, joblib

MODEL_DIR = Path("outputs/ev_lgbm_inference_artifact")
MODEL_DIR.mkdir(parents=True, exist_ok=True)

FEATURE_COLS = X_train_final.columns.tolist()
ID_COLS = ["vehicle_id", "received_at"]
TARGET_COL = "bsi_label"

joblib.dump(final_model, MODEL_DIR / "model.pkl")

with open(MODEL_DIR / "feature_columns.json", "w", encoding="utf-8") as f:
    json.dump(FEATURE_COLS, f, ensure_ascii=False, indent=2)

with open(MODEL_DIR / "id_columns.json", "w", encoding="utf-8") as f:
    json.dump(ID_COLS, f, ensure_ascii=False, indent=2)

with open(MODEL_DIR / "target_info.json", "w", encoding="utf-8") as f:
    json.dump({"target_col": TARGET_COL}, f, ensure_ascii=False, indent=2)

with open(MODEL_DIR / "class_info.json", "w", encoding="utf-8") as f:
    json.dump({"classes": final_model.classes_.tolist()}, f, ensure_ascii=False, indent=2)

with open(MODEL_DIR / "threshold.json", "w", encoding="utf-8") as f:
    json.dump({"danger_label": 2, "danger_threshold": 0.15}, f, ensure_ascii=False, indent=2)




# ====================================
# [2] 모델 등록
# ====================================
from azure.identity import DefaultAzureCredential
from azure.ai.ml import MLClient
from azure.ai.ml.entities import Model
from azure.ai.ml.constants import AssetTypes
from pathlib import Path

subscription_id = "YOUR_SUBSCRIPTION_ID"
resource_group = "YOUR_RESOURCE_GROUP"
workspace_name = "YOUR_WORKSPACE_NAME"

ml_client = MLClient(DefaultAzureCredential(), subscription_id, resource_group, workspace_name)

# 모델 아티팩트 경로 (노트북 환경의 실제 경로)
model_artifact_path = "./outputs/ev_lgbm_inference_artifact" 

model_asset = Model(
    path=str(Path(model_artifact_path).resolve()),
    name="ev-lgbm-inference-artifact",
    type=AssetTypes.CUSTOM_MODEL,
    description="EV LGBM model + feature schema + threshold",
    tags={"team": "dt4team1", "task": "ev-anomaly"}
)

registered_model = ml_client.models.create_or_update(model_asset)


# ====================================
# [3] online endpoint 생성
# ====================================
import uuid
from azure.ai.ml.entities import ManagedOnlineEndpoint

# 엔드포인트 이름 생성
endpoint_name = f"ev-anomaly-endpoint-{uuid.uuid4().hex[:8]}" 

endpoint = ManagedOnlineEndpoint(
    name=endpoint_name,
    description="EV anomaly real-time inference endpoint for dt4team1",
    auth_mode="key"
)

ep_poller = ml_client.online_endpoints.begin_create_or_update(endpoint)
ep_result = ep_poller.result()


# ====================================
# [4] 배포
# ====================================
from azure.ai.ml.entities import ManagedOnlineDeployment, Environment, CodeConfiguration

# 환경 등록 (conda.yaml을 사용)
deployment_code_path = "./deployment_dt4team1" 
env = Environment(
    name="ev-lgbm-inference-env",
    description="Inference environment for EV LGBM",
    image="mcr.microsoft.com/azureml/openmpi4.1.0-ubuntu22.04:latest",
    conda_file=str(Path(deployment_code_path) / "conda.yaml")
)

env = ml_client.environments.create_or_update(env)
print("Environment ready:", env.name, env.version)

# 배포 정의
deployment = ManagedOnlineDeployment(
    name="purple2",
    endpoint_name=endpoint_name,
    model=f"azureml:{registered_model.name}:{registered_model.version}",
    environment=f"azureml:{env.name}:{env.version}",
    code_configuration=CodeConfiguration(
        code=deployment_code_path,
        scoring_script="score.py"
    ),
    instance_type="Standard_DS3_v2",
    instance_count=1
)

dep_poller = ml_client.online_deployments.begin_create_or_update(deployment)
dep_result = dep_poller.result()


# ====================================
# [5] 트래픽 연결
# ====================================
endpoint = ml_client.online_endpoints.get(endpoint_name)
endpoint.traffic = {"purple2": 100}
ml_client.online_endpoints.begin_create_or_update(endpoint).result()
print("Traffic set: purple2=100 on endpoint", endpoint_name)


# ====================================
# [6] 샘플 테스트
# ====================================
import json
import requests

scoring_uri = "YOUR_SCORING_URI"

# 기본키 입력
key = "YOUR_PRIMARY_KEY"

# 샘플 payload 데이터 3개
sample_payload = {
    "Inputs": {
        "WebServiceInput0": [
            {
                "vehicle_id": "EV001",
                "model_name": "IONIQ5",
                "received_at": "2026-05-27T10:00:00Z",
                "battery_voltage": 350.0,
                "battery_current": 20.0,
                "temperature": 28.0,
                "ambient_temp": 22.0,
                "delta_i": 0.2,
                "delta_v": 0.5,
                "joule_heating_stress": 0.3,
                "latitude": 35.1796,
                "longitude": 129.0756,
                "current_region_id": 101,
                "region_name": "Busan",
                "is_active": 1,
                "alert_type": "NONE"
            },
            {
                "vehicle_id": "EV002",
                "model_name": "IONIQ5",
                "received_at": "2026-05-27T10:00:01Z",
                "battery_voltage": 357.0,
                "battery_current": 24.0,
                "temperature": 24.0,
                "ambient_temp": 21.0,
                "delta_i": 0.5,
                "delta_v": 0.6,
                "joule_heating_stress": 0.3,
                "latitude": 35.1796,
                "longitude": 129.0756,
                "current_region_id": 101,
                "region_name": "Seoul",
                "is_active": 1,
                "alert_type": "NONE"
            },
            {
                "vehicle_id": "EV003",
                "model_name": "IONIQ3",
                "received_at": "2026-05-27T10:00:03Z",
                "battery_voltage": 350.0,
                "battery_current": 20.0,
                "temperature": 28.0,
                "ambient_temp": 22.0,
                "delta_i": 0.2,
                "delta_v": 0.5,
                "joule_heating_stress": 0.3,
                "latitude": 35.1796,
                "longitude": 129.0756,
                "current_region_id": 101,
                "region_name": "Daejeon",
                "is_active": 1,
                "alert_type": "NONE"
            }
        ]
    }
}

# 요청 헤더
headers = {
    "Content-Type": "application/json",
    "Authorization": f"Bearer {key}"
}


response = requests.post(
    scoring_uri,
    json=sample_payload,
    headers=headers,
    timeout=60
)

print("status code:", response.status_code)
print(response.text)
