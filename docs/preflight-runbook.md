# 서울 적용 전 점검 및 실행 순서

2026-11-20 기준 bootstrap 버킷 생성과 S3 state 이전을 완료했다. production backend 연결 및
plan은 완료했지만 production apply는 하지 않았다. 아직 실제 image/secret/Tunnel/DNS 검증은 미완료다.
아래 명령은 실행 예시이며 apply, 배포와 DNS 변경은 각 단계 리뷰 뒤에 실행한다.

**현재 production plan은 적용 보류다.** 2026-11-20에 Paid Plan과 Advanced 기능 활성화는 완료했다.
Advanced 전환 전에는 프로젝트 SCP가 `iam:*Provider*`를 차단해 GitHub OIDC provider 생성을 막았다.
이제 새 CLI 세션을 발급하고 서울 리전에서 OIDC provider 조회와 production plan을 다시 검증한다.
생성 가능성을 시험하려고 이 plan을 apply하지 않는다.

- [프로젝트 조직 정책: Free/Paid의 DenyIAMRestrictedActions](https://docs.aws.amazon.com/accounts/latest/reference/scps-and-rcps-for-projects.html)
- [Advanced 기능 활성화: 사전 업그레이드 필요, 활성화는 되돌릴 수 없음](https://docs.aws.amazon.com/accounts/latest/reference/activate-advanced-features.html)

## 1. 사람이 로그인하는 방법

Fresh Canvas 프로젝트형 계정은 기존 Builder ID로 콘솔에 로그인한다. 별도 root 사용자나 IAM 콘솔
사용자를 만드는 절차를 따르지 않는다. IAM role은 ECS와 GitHub 자동화용이다.
로컬 CLI에는 서울용 `chaeso-seoul` 브라우저 기반 임시 인증을 연결한다. 세션이 만료되면 다시 로그인한다.

```sh
aws login --profile chaeso-seoul --region ap-northeast-2
aws sts get-caller-identity --profile chaeso-seoul --region ap-northeast-2
```

이때 브라우저에서 실제 Fresh Canvas 프로젝트를 선택한다. 계정 ID를 확인한 뒤 Terraform의
`aws_account_id` 및 backend의 `allowed_account_ids`에 같은 값을 넣는다. AWS provider가 임시 인증을
읽는지도 bootstrap plan에서 확인한다. 세션 토큰과 액세스 키는 Git·문서·채팅에 남기지 않는다.
기존 IAM 사용자의 연결 정책과 키 유무는 읽기 전용으로 점검하고, 불필요한 사용자를 자동 삭제하지 않는다.

## 2. state 준비 (plan → 리뷰 → apply)

bootstrap에는 account/region을 넣은 로컬 `terraform.tfvars`와 기존 버킷을 가리키는
`backend.hcl`을 준비한다. secret 값은 넣지 않는다. 현재 환경의 연결·점검 명령은 다음과 같다.

```sh
export AWS_PROFILE=chaeso-seoul
terraform -chdir=bootstrap init -backend-config=backend.hcl -lockfile=readonly
terraform -chdir=bootstrap plan
terraform -chdir=bootstrap output state_bucket_name
```

현재 `bootstrap/backend.tf`는 S3 backend를 사용한다. 기존 환경을 새로 체크아웃할 때는
계정별 `backend.hcl`과 `terraform.tfvars`를 준비해 `init -backend-config=backend.hcl`로 연결한다.
이미 생성한 버킷을 다시 bootstrap하거나 빈 로컬 state를 원격으로 이전하지 않는다.

`bootstrap/terraform.tfvars.example`을 복사한 뒤, 서울 리전과 이미 생성한 state bucket 이름을
명시한다. state bucket은 전역적으로 이름이 유일해야 하므로 `bucket_prefix`로 자동 생성하지 않는다.

아래는 이번에 완료한 최초 이전 절차의 기록이다. 첫 bootstrap은 로컬 state를 사용한다. 버킷 생성 후 `bootstrap/terraform.tfstate`를 안전한 위치에
백업하고, `bootstrap/backend.tf.example`을 `bootstrap/backend.tf`로 복사한다. production의
`backend.hcl.example` 형식을 사용하되 key는 반드시 `seoul/bootstrap/terraform.tfstate`로 바꾼다.
bucket/profile/account/region은 같은 새 서울 계정 값으로 설정한다.

```sh
terraform -chdir=bootstrap init -migrate-state -backend-config=backend.hcl
```

원격 state migration 완료를 확인하기 전에는 로컬 state/백업을 지우지 않는다. 암호화는 유지하고
bootstrap과 production의 key를 절대로 공유하지 않는다. `prevent_destroy`는 Terraform 내 안전장치이며
콘솔 삭제나 코드에서 lifecycle을 제거하는 것까지 막지는 않는다.

production에는 S3 backend 블록이 이미 있다. `environments/production/backend.hcl.example`을 참고해
실제 `backend.hcl`을 준비하고 연결한다. `use_lockfile=true`이므로 실행 주체에는 state object의
Get/Put 및 `.tflock` object의 Get/Put/Delete 권한이 필요하다. GitHub 앱 배포 role에 state 권한은 주지 않는다.

```sh
terraform -chdir=environments/production init -backend-config=backend.hcl -lockfile=readonly
terraform -chdir=environments/production plan -out=production.tfplan
```

이 단계는 `desired_count=0`, `enable_image_expiration=false`를 유지한다. task definition의 이미지 URL은
형식에 맞는 초기 자리표시자를 사용할 수 있지만 task를 실행하기 전에는 실제 image가 필요하다.
CloudFront custom domain/certificate는 null로 시작해 기본 distribution hostname으로 검증한다.
프로젝트 리전 제한하에서 us-east-1 ACM 사용자 도메인 인증서 사용 가능 여부는 별도 검증 대상이다.

## 3. secret·image·Tunnel 준비

- 7개 secret 값은 Doppler를 원본으로 별도 주입한다. `OBSERVABILITY_METRICS_ENABLED`는 `true`이며
  새 `OBSERVABILITY_METRICS_BEARER_TOKEN`은 비어 있지 않은 강한 난수다. Next.js와 Alloy에 동일 값이 들어간다.
- Tunnel은 임시 hostname → `http://localhost:3000`으로 연결하고 token을 secret에 저장한다.
  cloudflared image는 검증한 ARM64 tag/digest로 고정한다. egress에는 TCP/UDP 7844가 필요하다.
- secret 주입/동기화 주체 권한은 앱 CD의 배포 role과 별도로 관리한다.
- 컨테이너에 secret이 주입되는 것은 시작 시점이다. 값을 회전하면 task 재배포가 필요하다.

앱 저장소의 새 `.github/workflows/cd-seoul.yml`은 수동 실행 전용이며, `main` +
`SEOUL_DEPLOY_ENABLED=true`에서만 실행된다. 기존 `cd.yml`은 유지한다.
별도 준비/배포 모드 없이 기존 CD처럼 빌드 → S3/ECR 업로드 → render/deploy Actions로 진행한다.
아래 GitHub repository variables를 **실제 Terraform 출력 확인 후** 설정한다.

| 변수 | 값의 출처 |
| --- | --- |
| `SEOUL_DEPLOY_ENABLED` | 검토 전 미설정/false; 배포 준비 승인 뒤 true |
| `SEOUL_AWS_ACCOUNT_ID` | 확인한 새 프로젝트 ID |
| `SEOUL_AWS_ROLE_ARN` | `github_actions_role_arn` |
| `SEOUL_STATIC_BUCKET` | `static_bucket_name` |
| `SEOUL_CDN_BASE_URL` | `https://` + `static_distribution_domain` |

기존 Doppler 빌드 token은 GitHub secret을 사용한다. workflow는 현재 서비스의 task definition을 읽고
Next.js/Alloy 이미지 두 개만 바꾸므로 Tunnel 설정과 역할/secret ARN을 보존한다. task 수는 변경하지 않는다.
최초 실행 전 task 수 0을 운영자가 확인한다. 같은 workflow로 이미지를 올리고 service revision을 연결한 뒤
Terraform으로 task 수를 1로 변경한다. CD는 task 수를 바꾸지 않는다.
Terraform이 만든 초기 revision은 `ignore_changes`로 덮어쓰지 않는다.
나중에 task 크기/secret/컨테이너 정의를 Terraform에서 바꾸면 새로운 initial_task_definition_arn을 검토해
서비스로 전달하는 절차가 별도로 필요하다. ignore_changes 때문에 apply만으로 배포되지 않는다.

Alloy는 기존 `docker/Dockerfile.alloy`와 `deploy/config.alloy` 하나를 양쪽 환경에서 공유한다.
설정에 메트릭 인증 헤더만 추가했다. token 미설정 상태에서도 설정이 유효하며, 서울에서는
Next.js/Alloy 양쪽에 같은 비어 있지 않은 token을 주입한다. 기존 Next.js의 선택적 인증 동작은 변경하지 않는다.

## 4. 검증 후 공개 전환

`desired_count=1` plan을 검토한 뒤 apply한다. 이후 동일 workflow로 롤링 배포한다.
운영 목표는 평상시 task 1개다. rolling 100/200 설정으로 기존 1개를 유지하면서 새 1개를 먼저
시작할 수 있으므로 계획된 중단은 필수가 아니다. 배포 중 최대 task 2개와 공인 IP 2개가 사용된다.
새 task의 ECS health와 Cloudflare Tunnel 준비 시점은 다를 수 있으므로 무중단을 보장하지 않으며,
실제 외부 요청으로 배포 전환을 검증한다.
deploy Action은 서비스 안정화를 기다린다. 롤백된 이전 revision도 stable로 판단될 수 있으므로
이전 검증 시 ECS 콘솔에서 원하는 revision이 실제 실행 중인지 직접 확인한다.
첫 배포에는 이전 성공 revision이 없어 자동 롤백 대상을 기대하면 안 된다.

이전 체크리스트로 아래 항목을 직접 확인한다. 별도 외부 검사 스크립트나 CI 테스트는 두지 않는다.

- Tunnel 외부 `/api/internal/health`: 204.
- 인증 없는 외부 `/api/metrics`: 401 (404나 200은 이 검증에서 실패).
- 별도로 Grafana에서 Alloy의 `up=1`과 각 task 지표를 확인한다. HTTP 검사만으로 수집 성공을 입증하지 못한다.
- 로그인/BFF/API/정적 JS·CSS·폰트가 정상인지 확인한다.
- task 중단 실험은 유일한 운영 task를 멈추므로 별도 승인 후 실행해 복구 시간·교체·Tunnel 재연결을 확인한다.
  Spot 회수/장애 시에는 대체 task가 준비될 때까지 서비스가 중단될 수 있다. Spot 용량 부족 시에는
  재시작이 지연되며 자동으로 On-Demand로 전환되지 않는다. 중단이 항상 짧다고 보장할 수 없다.
- Tunnel 연결은 ECS 내부 health check에 포함되지 않는다. 외부 연결은 직접 확인하고,
  실패 시 배포 전 기록한 이전 revision으로 복구할지 리뷰한다. 내부 health endpoint와 ECS 검사는 유지한다.

모든 검증 후 root/www DNS 전환을 별도 승인한다. static 사용자 도메인은 ACM/CloudFront 확인 후 전환한다.
48시간 관찰 및 원복 경로 확인 후에만 이전 인프라 종료를 검토한다.

## 5. 이미지와 비용

`app-`/`alloy-` 각 10개 규칙은 preview용이다. 실제 자동 삭제는 **기본 off**다. 개수만으로는 현재 실행,
재시작 예정, 롤백 대상 digest를 구분할 수 없다. 단발 preview만 확인한 뒤 계속 켜 두는 것도 충분하지 않다.
운영 이미지 보호/정리 절차를 따로 검토하기 전에는 false를 유지한다. 따라서 현재 20개 상한을 강제하지 않는다.
공인 IPv4, Fargate, Secrets Manager 7개, CloudWatch 로그, ECR/S3 저장·전송 비용은 남는다.
Container Insights는 off로 바꾸었고 Alloy 메모리 상한/재시작 정책을 복원했다.

## 6. 블로그 스크린샷 시점

사진은 앱 workspace `.context/aws-migration/screenshots/`에 저장한다. 값 주입 화면은 촬영하지 않는다.

| 시점 | 촬영 대상 |
| --- | --- |
| 인증 확인 | 프로젝트 이름·서울 리전 (이메일/계정 ID는 게시 전 가림) |
| bootstrap plan 리뷰 | S3 관련 생성 목록, 삭제 0개 |
| production plan 리뷰 | ALB/NAT 없이 생성할 모듈과 task 수 0 |
| task 기동 후 | ECS task 1개·컨테이너 3개, 배포 상태 |
| 롤링 배포 검증 | 기존/신규 task가 일시적으로 2개가 된 뒤 1개로 복귀, Tunnel·외부 응답 |
| Tunnel 검증 | token이 보이지 않는 connector 상태 |
| 외부 검사 | health 204·metrics 401·Grafana up=1 |
| DNS 전환 후 | 공개 서비스와 비용 변화 (식별정보 가림) |

## 참고

- [프로젝트 계정의 로그인·권한 구조](https://docs.aws.amazon.com/accounts/latest/reference/sign-up-for-aws.html)
- [임시 CLI 로그인](https://docs.aws.amazon.com/cli/latest/userguide/cli-configure-sign-in.html)
- [S3 backend와 lockfile](https://developer.hashicorp.com/terraform/language/backend/s3)
- [ECR lifecycle 평가 규칙](https://docs.aws.amazon.com/AmazonECR/latest/userguide/LifecyclePolicies.html)
