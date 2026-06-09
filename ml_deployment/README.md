# Azure ML Deployment & Inference Pipeline

본 폴더는 Azure Stream Analytics에서 전달받은 차량 센서 데이터를 Azure ML Online Endpoint에서 처리하기 위한 배포 및 추론 코드를 포함합니다.

## 주요 처리 흐름

1. Azure Stream Analytics로부터 차량 텔레메트리 데이터 수신
2. 모델 입력 및 BSI 계산에 필요한 파생변수 생성
3. 팀에서 정의한 BSI 공식에 따라 BSI 산출
4. 학습된 LightGBM 모델로 배터리 상태 예측
5. 원본 데이터, BSI, 예측 결과, 대시보드용 파생컬럼을 함께 반환
6. 반환 결과는 이후 Azure SQL DB 저장 및 대시보드 시각화에 활용