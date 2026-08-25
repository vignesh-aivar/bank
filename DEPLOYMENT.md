# Convogent - Client EKS Deployment Guide

## Prerequisites

- EKS cluster with `kubectl` and `helm` access
- AWS CLI configured with appropriate permissions
- `jq` installed on the machine

---

## 1. Create Namespace

```bash
kubectl create ns convogent
```

---

## 2. Create Node Groups

### App Node Group (frontend, backend, chat, eval, pca)

```bash
aws eks create-nodegroup \
  --cluster-name <CLUSTER_NAME> \
  --nodegroup-name convogent-app \
  --node-role arn:aws:iam::273354645607:role/<NODE_ROLE_NAME> \
  --instance-types c6a.2xlarge \
  --scaling-config minSize=1,maxSize=3,desiredSize=2 \
  --ami-type AL2023_x86_64_STANDARD \
  --capacity-type ON_DEMAND \
  --disk-size 50 \
  --subnets <SUBNET_1> <SUBNET_2> <SUBNET_3> \
  --labels NodeGroupType=app \
  --taints "key=workload,value=app,effect=NO_SCHEDULE" \
  --tags Environment=production,Service=convogent,NodeGroup=app
```

### Voice Node Group (voice only — CPU-heavy)

```bash
aws eks create-nodegroup \
  --cluster-name <CLUSTER_NAME> \
  --nodegroup-name convogent-agent-voice \
  --node-role arn:aws:iam::273354645607:role/<NODE_ROLE_NAME> \
  --instance-types c6a.2xlarge \
  --scaling-config minSize=1,maxSize=10,desiredSize=1 \
  --ami-type AL2023_x86_64_STANDARD \
  --capacity-type ON_DEMAND \
  --disk-size 50 \
  --subnets <SUBNET_1> <SUBNET_2> <SUBNET_3> \
  --labels NodeGroupType=agent-voice \
  --taints "key=workload,value=agent-voice,effect=NO_SCHEDULE" \
  --tags Environment=production,Service=convogent,NodeGroup=agent-voice
```

### LiveKit Server Node Group

```bash
aws eks create-nodegroup \
  --cluster-name <CLUSTER_NAME> \
  --nodegroup-name convogent-livekit-server \
  --node-role arn:aws:iam::273354645607:role/<NODE_ROLE_NAME> \
  --instance-types c6a.2xlarge \
  --scaling-config minSize=1,maxSize=10,desiredSize=1 \
  --ami-type AL2023_x86_64_STANDARD \
  --capacity-type ON_DEMAND \
  --disk-size 50 \
  --subnets <SUBNET_1> <SUBNET_2> <SUBNET_3> \
  --labels workload=livekit-server \
  --taints "key=workload,value=livekit-server,effect=NO_SCHEDULE" \
  --tags Environment=production,Service=convogent,NodeGroup=livekit-server
```

### LiveKit Egress Node Group

```bash
aws eks create-nodegroup \
  --cluster-name <CLUSTER_NAME> \
  --nodegroup-name convogent-livekit-egress \
  --node-role arn:aws:iam::273354645607:role/<NODE_ROLE_NAME> \
  --instance-types c6a.2xlarge \
  --scaling-config minSize=1,maxSize=10,desiredSize=1 \
  --ami-type AL2023_x86_64_STANDARD \
  --capacity-type ON_DEMAND \
  --disk-size 50 \
  --subnets <SUBNET_1> <SUBNET_2> <SUBNET_3> \
  --labels workload=livekit-egress \
  --taints "key=workload,value=livekit-egress,effect=NO_SCHEDULE" \
  --tags Environment=production,Service=convogent,NodeGroup=livekit-egress
```

### LiveKit SIP Node Group

```bash
aws eks create-nodegroup \
  --cluster-name <CLUSTER_NAME> \
  --nodegroup-name convogent-livekit-sip \
  --node-role arn:aws:iam::273354645607:role/<NODE_ROLE_NAME> \
  --instance-types c6a.2xlarge \
  --scaling-config minSize=1,maxSize=10,desiredSize=1 \
  --ami-type AL2023_x86_64_STANDARD \
  --capacity-type ON_DEMAND \
  --disk-size 50 \
  --subnets <SUBNET_1> <SUBNET_2> <SUBNET_3> \
  --labels workload=livekit-sip \
  --taints "key=workload,value=livekit-sip,effect=NO_SCHEDULE" \
  --tags Environment=production,Service=convogent,NodeGroup=livekit-sip
```

---

## 3. Install EKS Pod Identity Agent

```bash
aws eks create-addon \
  --cluster-name <CLUSTER_NAME> \
  --addon-name eks-pod-identity-agent
```

---

## 4. Create Pod Identity Associations

```bash
aws eks create-pod-identity-association \
  --cluster-name <CLUSTER_NAME> \
  --namespace convogent \
  --service-account convogent-backend-sa \
  --role-arn arn:aws:iam::273354645607:role/ConvogentBackendRole

aws eks create-pod-identity-association \
  --cluster-name <CLUSTER_NAME> \
  --namespace convogent \
  --service-account convogent-chat-sa \
  --role-arn arn:aws:iam::273354645607:role/ConvogentChatRole

aws eks create-pod-identity-association \
  --cluster-name <CLUSTER_NAME> \
  --namespace convogent \
  --service-account convogent-eval-sa \
  --role-arn arn:aws:iam::273354645607:role/ConvogentEvalRole

aws eks create-pod-identity-association \
  --cluster-name <CLUSTER_NAME> \
  --namespace convogent \
  --service-account convogent-pca-sa \
  --role-arn arn:aws:iam::273354645607:role/ConvogentPcaRole

aws eks create-pod-identity-association \
  --cluster-name <CLUSTER_NAME> \
  --namespace convogent \
  --service-account convogent-voice-sa \
  --role-arn arn:aws:iam::273354645607:role/ConvogentVoiceRole
```

---

## 5. Create Secrets in AWS Secrets Manager

```bash
aws secretsmanager create-secret \
  --name convogent/dev/backend \
  --region ap-south-1 \
  --secret-string '{
    "PORT": "8000",
    "ENV": "production",
    "LOG_LEVEL": "info",
    "MONGODB_DB_NAME": "",
    "MONGO_DB_URI": "",
    "MONGO_MASTER_KEY": "",
    "KEY_ALT_NAME": "API_ENCRYPTION_DEK_KEY",
    "KEY_VAULT_NAMESPACE": "",
    "KEY_VAULT_COLL": "__keyVault",
    "KMS_ENCRYPTION_ENABLED": "0",
    "MONGO_ENCRYPT_ALGORITHM": "AEAD_AES_256_CBC_HMAC_SHA_512-Deterministic",
    "S3_BUCKET_ARN": "",
    "AGENT_BACKEND_URL": "http://convogent-voice.convogent.svc.cluster.local:9000/voice_service",
    "COGNITO_ENABLED": "true",
    "COGNITO_USER_POOL_ID": "",
    "COGNITO_CLIENT_ID": "",
    "COGNITO_CLIENT_SECRET": "",
    "COGNITO_DOMAIN": "",
    "COGNITO_REDIRECT_URI": "",
    "COGNITO_SCOPES": "openid profile email",
    "CONVOGENT_UI_LOGIN_URL": "",
    "CONVOGENT_UI_URL": "",
    "CONVOGENT_UI_LOGOUT_URI": "",
    "COOKIE_SIGNING_MASTER_KEY": "",
    "JWT_SECRET": "",
    "PROCESS_ENV": "production",
    "AWS_REGION": "ap-south-1",
    "ALLOWED_ORIGIN": "",
    "METRICS_STALE_HOURS": "1",
    "KAFKA_ENABLED": "true",
    "KAFKA_SECURITY_PROTOCOL": "SASL_SSL",
    "KAFKA_SASL_MECHANISM": "AWS_MSK_IAM",
    "KAFKA_BOOTSTRAP_SERVERS": "",
    "KAFKA_EVAL_REQUESTS_TOPIC": "eval-requests",
    "KAFKA_CALL_CAMPAIGN_TOPIC": "call-requests",
    "KAFKA_EVAL_PUBLISH_TOPIC": "publish-eval-requests",
    "MSK_ROLE_ARN": "",
    "ENABLE_TRACING": "true",
    "OTEL_EXPORTER_OTLP_ENDPOINT": "",
    "OTEL_SERVICE_NAME": "convogent-backend",
    "METADATA_PROMPT_NEW": ", then generate :"
  }'

aws secretsmanager create-secret \
  --name convogent/dev/chat \
  --region ap-south-1 \
  --secret-string '{
    "AWS_REGION": "ap-south-1",
    "S3_BUCKET": "",
    "WEBSOCKET_URL": "",
    "FLOW_SERVICE_URL": "http://convogent-backend.convogent.svc.cluster.local:8000",
    "FLOW_AGENT_CONFIG_SOURCE": "draft",
    "FLOW_AGENT_CONFIG_VERSION_ID": "",
    "BACKEND_AUTH_TOKEN": "",
    "BEDROCK_MODEL": "us.anthropic.claude-sonnet-4-5-20250929-v1:0",
    "LOG_LEVEL": "INFO",
    "MCP_ENABLED": "false",
    "MCP_BASE_URL": ""
  }'

aws secretsmanager create-secret \
  --name convogent/dev/eval \
  --region ap-south-1 \
  --secret-string '{
    "LOG_LEVEL": "INFO",
    "AWS_REGION": "ap-south-1",
    "S3_BUCKET": "",
    "EVAL_SIMULATION_MODEL": "us.anthropic.claude-3-5-sonnet-20240620-v1:0",
    "EVAL_JUDGE_MODEL": "us.anthropic.claude-3-5-sonnet-20240620-v1:0",
    "CHAT_SERVICE_URL": "ws://convogent-chat.convogent.svc.cluster.local:9001",
    "FLOW_SERVICE_URL": "http://convogent-backend.convogent.svc.cluster.local:8000",
    "FLOW_AGENT_CONFIG_SOURCE": "draft",
    "FLOW_AGENT_CONFIG_VERSION_ID": "",
    "BACKEND_AUTH_TOKEN": "",
    "KAFKA_ENABLED": "true",
    "KAFKA_SECURITY_PROTOCOL": "SASL_SSL",
    "KAFKA_SASL_MECHANISM": "AWS_MSK_IAM",
    "KAFKA_EVAL_REQUESTS_TOPIC": "eval-requests",
    "KAFKA_CONSUMER_GROUP_ID": "eval-consumer-group",
    "KAFKA_BOOTSTRAP_SERVERS": "",
    "MSK_ROLE_ARN": ""
  }'

aws secretsmanager create-secret \
  --name convogent/dev/pca \
  --region ap-south-1 \
  --secret-string '{
    "AWS_REGION": "ap-south-1",
    "S3_BUCKET": "",
    "KAFKA_ENABLED": "true",
    "KAFKA_SECURITY_PROTOCOL": "SASL_SSL",
    "KAFKA_SASL_MECHANISM": "AWS_MSK_IAM",
    "KAFKA_CALL_COMPLETED_TOPIC": "call-completed",
    "KAFKA_CONSUMER_GROUP_ID": "pca-consumer-group",
    "KAFKA_BOOTSTRAP_SERVERS": "",
    "MSK_ROLE_ARN": "",
    "PCA_AUTH_TOKEN": "",
    "FLOW_SERVICE_URL": "http://convogent-backend.convogent.svc.cluster.local:8000",
    "FLOW_AGENT_CONFIG_SOURCE": "draft",
    "FLOW_AGENT_CONFIG_VERSION_ID": "",
    "BACKEND_AUTH_TOKEN": "",
    "PCA_BEDROCK_MODEL": "us.anthropic.claude-sonnet-4-20250514-v1:0",
    "LOG_LEVEL": "INFO"
  }'

aws secretsmanager create-secret \
  --name convogent/dev/voice-service \
  --region ap-south-1 \
  --secret-string '{
    "S3_BUCKET": "",
    "AWS_DEFAULT_REGION": "ap-south-1",
    "AWS_REGION": "ap-south-1",
    "HOST": "0.0.0.0",
    "LOG_LEVEL": "INFO",
    "RECORDINGS_DIR": "sip_call_recordings",
    "RECORDING_ENABLED": "True",
    "LOCAL_AUDIO_RECORDING_ENABLED": "True",
    "BEDROCK_GUARDRAIL_VERSION": "",
    "BEDROCK_GUARDRAILS_ENABLED": "true",
    "RAG_EMBEDDING_MODEL": "amazon.titan-embed-text-v2:0",
    "RAG_EMBEDDING_DIMENSION": "512",
    "RAG_EMBEDDING_NORMALIZE": "true",
    "BACKGROUND_AUDIO_PATH": "data/output_16k_mono.wav",
    "FLOW_SERVICE_URL": "http://convogent-backend.convogent.svc.cluster.local:8000",
    "BACKEND_AUTH_TOKEN": "",
    "LIVEKIT_URL": "",
    "LIVEKIT_API_KEY": "",
    "LIVEKIT_API_SECRET": "",
    "REDIS_URL": "",
    "WEBSOCKET_URL": "ws://localhost:9000",
    "OTEL_EXPORTER_OTLP_ENDPOINT": "",
    "OTEL_SERVICE_NAME": "convogent-voice",
    "KAFKA_ENABLED": "true",
    "KAFKA_SECURITY_PROTOCOL": "SASL_SSL",
    "KAFKA_SASL_MECHANISM": "AWS_MSK_IAM",
    "KAFKA_CALL_REQUESTS_TOPIC": "call-requests",
    "KAFKA_CALL_COMPLETED_TOPIC": "call-completed",
    "KAFKA_CONSUMER_GROUP_ID": "voice-agent-consumer-group",
    "KAFKA_BOOTSTRAP_SERVERS": "",
    "MSK_ROLE_ARN": "",
    "FLOW_AGENT_CONFIG_SOURCE": "draft",
    "FLOW_AGENT_CONFIG_VERSION_ID": "",
    "CHAT_SESSION_TTL": "3600",
    "CHAT_HISTORY_MAX_MESSAGES": "100",
    "EVAL_DEBUG": "false"
  }'
```

---

## 6. Create Kubernetes Secrets from AWS Secrets Manager

```bash
for svc in backend chat eval pca voice-service; do
  K8S_NAME="convogent-${svc%-service}-secrets"

  SECRET_JSON=$(aws secretsmanager get-secret-value \
    --secret-id "convogent/dev/$svc" \
    --region ap-south-1 \
    --query SecretString --output text)

  kubectl create secret generic "$K8S_NAME" \
    -n convogent \
    --from-env-file=<(echo "$SECRET_JSON" | jq -r 'to_entries[] | "\(.key)=\(.value)"')
done
```

---

## 7. Deploy Charts

### Extract charts

```bash
cd charts
tar -xzf convogent-backend-0.1.0.tgz
tar -xzf convogent-frontend-0.1.0.tgz
tar -xzf convogent-chat-service-0.1.0.tgz
tar -xzf convogent-eval-service-0.1.0.tgz
tar -xzf convogent-pca-service-0.1.0.tgz
tar -xzf convogent-voice-service-0.1.0.tgz
```

### Install all services

```bash
helm upgrade --install convogent-backend ./convogent-backend \
  -f environments/client/values.yaml -n convogent

helm upgrade --install convogent-frontend ./convogent-frontend \
  -f environments/client/values.yaml -n convogent

helm upgrade --install convogent-chat ./convogent-chat-service \
  -f environments/client/values.yaml -n convogent

helm upgrade --install convogent-eval ./convogent-eval-service \
  -f environments/client/values.yaml -n convogent

helm upgrade --install convogent-pca ./convogent-pca-service \
  -f environments/client/values.yaml -n convogent

helm upgrade --install convogent-voice ./convogent-voice-service \
  -f environments/client/values.yaml -n convogent
```

---

## 8. Verify Deployment

```bash
kubectl get pods -n convogent
kubectl get svc -n convogent
kubectl get hpa -n convogent
kubectl get sa -n convogent
```

---

## 9. Refresh Secrets (when values change in AWS SM)

```bash
for svc in backend chat eval pca voice-service; do
  K8S_NAME="convogent-${svc%-service}-secrets"

  SECRET_JSON=$(aws secretsmanager get-secret-value \
    --secret-id "convogent/dev/$svc" \
    --region ap-south-1 \
    --query SecretString --output text)

  kubectl delete secret "$K8S_NAME" -n convogent --ignore-not-found
  kubectl create secret generic "$K8S_NAME" \
    -n convogent \
    --from-env-file=<(echo "$SECRET_JSON" | jq -r 'to_entries[] | "\(.key)=\(.value)"')
done

# Restart pods to pick up new env vars
kubectl rollout restart deployment -n convogent
```

---

## 10. Uninstall (if needed)

```bash
helm uninstall convogent-backend -n convogent
helm uninstall convogent-frontend -n convogent
helm uninstall convogent-chat -n convogent
helm uninstall convogent-eval -n convogent
helm uninstall convogent-pca -n convogent
helm uninstall convogent-voice -n convogent

kubectl delete ns convogent
```

---

## Service Endpoints (internal)

| Service | Endpoint |
|---------|----------|
| backend | `http://convogent-backend.convogent.svc.cluster.local:8000` |
| voice | `http://convogent-voice.convogent.svc.cluster.local:9000` |
| chat | `http://convogent-chat.convogent.svc.cluster.local:9001` |
| eval | `http://convogent-eval.convogent.svc.cluster.local:9002` |
| pca | `http://convogent-pca.convogent.svc.cluster.local:9003` |
| frontend | `http://convogent-frontend.convogent.svc.cluster.local:8080` |

---

## Image Registry

All images pulled from: `273354645607.dkr.ecr.ap-south-1.amazonaws.com`

| Service | Image |
|---------|-------|
| backend | `273354645607.dkr.ecr.ap-south-1.amazonaws.com/convogent-backend:latest` |
| frontend | `273354645607.dkr.ecr.ap-south-1.amazonaws.com/convogent-frontend:latest` |
| chat | `273354645607.dkr.ecr.ap-south-1.amazonaws.com/convogent-chat:latest` |
| eval | `273354645607.dkr.ecr.ap-south-1.amazonaws.com/convogent-eval:latest` |
| pca | `273354645607.dkr.ecr.ap-south-1.amazonaws.com/convogent-pca:latest` |
| voice | `273354645607.dkr.ecr.ap-south-1.amazonaws.com/convogent-voice:latest` |
