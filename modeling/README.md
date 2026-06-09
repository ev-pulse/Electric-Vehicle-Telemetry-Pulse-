# Battery Anomaly Detection Modeling

본 폴더는 BMW EV 배터리 주행 데이터를 기반으로 배터리 상태를 NORMAL, WARNING, CRITICAL로 분류하는 LightGBM 모델 학습 코드를 포함합니다.

## 주요 작업
- BSI 기반 라벨을 활용한 다중분류 모델 학습
- 데이터 불균형을 고려한 평가 지표 선정
- Macro F1 Score 및 Danger Recall 중심 평가
- LightGBM 모델 학습 및 성능 확인
- 교차 검증 시도