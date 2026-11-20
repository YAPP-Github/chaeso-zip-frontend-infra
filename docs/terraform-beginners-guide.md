# 처음 보는 사람을 위한 Terraform 안내서

이 문서는 이 저장소의 Terraform 코드를 **처음부터 읽는 사람**을 위한 설명서다. 아직 `apply`하지
않았으므로 AWS에 이 설계의 자원이 만들어진 상태는 아니다.

## 1. Terraform을 한 문장으로

Terraform은 “AWS에 이런 상태가 있어야 한다”는 선언형 코드다. `terraform plan`은 현재 AWS와 코드의
차이를 **미리 보여 주고**, `terraform apply`는 검토한 차이만 실제 AWS에 반영한다.

```text
*.tf 코드 ── terraform plan ──> 변경 미리보기 ── 승인 ── terraform apply ──> AWS 자원
                    │                                                     │
                    └────────────── state 파일 ────────────────────────────┘
                           “Terraform이 이미 만든 것”의 기록
```

여기서 중요한 단어는 네 가지다.

| 단어 | 뜻 | 이 저장소의 예 |
| --- | --- | --- |
| resource | 실제로 만드는 AWS 자원 | `aws_ecs_service`, `aws_vpc`, `aws_ecr_repository` |
| variable | 환경마다 바꿀 수 있는 입력값 | 계정 ID, 컨테이너 이미지, task 수 |
| module | 관련 resource를 한 폴더로 묶은 재사용 단위 | `modules/ecs`, `modules/iam` |
| output | apply 후 다른 사람이/모듈이 쓸 결과값 | ECR URL, GitHub 배포 role ARN |

## 2. 이 설계가 만들 운영 경로

ALB와 NAT Gateway/Instance를 두지 않고, ECS 안의 `cloudflared`가 Cloudflare에 **밖으로 연결을
먼저 만드는** 구조다. 그래서 AWS 인터넷에서 ECS로 들어오는 포트는 없다.

```text
방문자 브라우저
     │ HTTPS
     ▼
Cloudflare DNS / Proxy
     │ Cloudflare 네트워크 안의 named Tunnel
     │ (공개 원본 주소 없음)
     ▼
cloudflared 컨테이너 ───── localhost:3000 ─────> Next.js 컨테이너
        ▲                                                   │
        │ outbound TCP/UDP 7844                              ├── CloudWatch Logs
        │                                                     └── Alloy → Grafana
        │
Fargate Spot task (동일 task 안에 컨테이너 3개)
```

초기 기본값은 `desired_count = 0`이다. 준비 후 승인받아 `1`로 바꾸면 위 task가 **1개** 실행된다.
두 AZ의 subnet은 배치 후보로 유지하며, 평상시 task는 그중 한 곳에 배치된다. 컨테이너는
Next.js·Alloy·cloudflared가 각각 1개씩, 총 3개다. 롤링 배포 중에는 task가 최대 2개가 된다. `cloudflared`는 ECS가 자동 제공하는 기능이
아니다. task definition에 명시적으로 넣은 일반 컨테이너이며, Secrets Manager에서 Tunnel token을 읽어
실행된다.

## 3. 폴더 지도

```text
chaeso-zip-frontend-infra/
├── bootstrap/                         # state 보관용 S3를 한 번 먼저 만든다
├── environments/production/           # “서울 운영”을 조립하는 곳
│   ├── main.tf                         # module들을 연결한다
│   ├── variables.tf                    # 바꿀 수 있는 입력과 기본값
│   └── terraform.tfvars.example        # 실제 tfvars의 안전한 견본
├── modules/                            # 각 AWS 영역의 부품
│   ├── network/ registry/ secrets/
│   ├── iam/ ecs/ delivery/
├── .github/workflows/terraform.yml     # PR마다 문법/구성 검증
└── docs/
```

`modules/`는 단독으로 실행하지 않는다. `environments/production/main.tf`가 필요한 값을 각 모듈에
전달해 하나의 환경을 만든다. 즉, 실무에서 직접 실행할 위치는 `bootstrap/` 또는
`environments/production/`이다.

## 4. 두 번에 나누어 만드는 이유: bootstrap과 production

Terraform은 무엇을 이미 만들었는지 **state**로 기억한다. state에는 자원 ID와 민감한 메타데이터가
들어갈 수 있으므로, 개인 PC가 아닌 암호화된 비공개 S3에 둔다.

```text
첫 번째 apply                                  두 번째 apply
bootstrap/                                      environments/production/
┌────────────────────┐                          ┌──────────────────────────┐
│ state S3 bucket    │ ── backend로 사용 ─────> │ VPC, ECR, ECS, IAM,       │
│ - 암호화           │                          │ Secrets 컨테이너,         │
│ - 버전 보관        │                          │ S3, CloudFront            │
│ - 퍼블릭 차단      │                          └──────────────────────────┘
│ - 삭제 방지        │
└────────────────────┘
```

`bootstrap/main.tf`의 핵심은 다음이다.

| 코드 | 효과 | 필요한 이유 |
| --- | --- | --- |
| `aws_s3_bucket` | state를 담는 S3 생성 | 협업/CI에서 같은 상태를 공유 |
| `prevent_destroy = true` | Terraform이 버킷 삭제를 거절 | state를 실수로 잃지 않음 |
| `aws_s3_bucket_versioning` | 과거 state 버전 보존 | 잘못 apply했을 때 복구 단서 |
| `server_side_encryption` | S3 안 state를 AES-256으로 암호화 | state 보호 |
| `public_access_block` | public 공개 차단 | state 외부 노출 방지 |

> production에는 암호화와 `use_lockfile = true`가 설정된 S3 backend 블록을 준비했다. 실제 bucket과
> 계정은 아직 연결하지 않았다. bootstrap state는 처음에는 로컬에 생기므로 안전하게 백업하고,
> 생성한 S3의 별도 `sydney/bootstrap/terraform.tfstate` key로 옮기는 절차를 실행 순서에 명시했다. 이 버킷은 state 전용이며, 운영 워크로드는 서울 리전에 생성한다.

## 5. production은 모듈을 어떻게 연결하는가

`environments/production/main.tf`가 조립 도면이다.

```text
network ──────────────┐
                       ├──> ecs (subnet, security group)
registry ──────────────┤
                       ├──> iam (ECR/S3/secret ARN 권한 범위)
secrets ───────────────┤
delivery ──────────────┤
iam ───────────────────┘──> ecs (execution role, task role)
```

Terraform은 이 참조를 보고 자동으로 순서를 정한다. 예를 들어 ECS는 `module.iam.execution_role_arn`을
받으므로 IAM role이 먼저 만들어진다. 사람이 따로 순서를 맞출 필요가 없다.

모든 자원은 다음 공통 태그를 받는다.

```hcl
Application = "chaeso-zip-frontend"
Environment = "production"
ManagedBy   = "terraform"
```

AWS 콘솔에서 비용/자원을 찾거나 나중에 정리할 때 기준이 된다.

## 6. 모듈별 상세 설명

### 6.1 network: VPC와 통신 길

파일: `modules/network/main.tf`

```text
VPC 10.42.0.0/16
│
├── public subnet (ap-northeast-2a)
│     └── 운영 task 배치 후보: public IP 있음, inbound 없음
└── public subnet (ap-northeast-2b)
      └── 운영 task 배치 후보: public IP 있음, inbound 없음

평상시 두 subnet 중 한 곳에 task 1개; 롤링 배포 중에는 최대 2개
두 subnet → route table → Internet Gateway → 인터넷
```

- `10.42.0.0/16`은 이 서비스 전용 사설 네트워크 범위다.
- `cidrsubnet`은 이 범위를 AZ별 subnet으로 자동 분할한다.
- task에는 public IP가 붙지만 security group에 **ingress 규칙이 0개**다. 따라서 인터넷이 task로 직접
  접속할 수 없다.
- egress는 현재 모두 허용한다. Cloudflare Tunnel 연결, ECR image pull, Secrets Manager, CloudWatch
  Logs에는 HTTPS/DNS가 필요하며, Tunnel에는 TCP/UDP 7844가 필요하다.
- NAT를 쓰지 않는 이유는 task가 public subnet에서 outbound 연결을 하기 때문이다. ALB를 쓰지 않는
  이유는 Cloudflare Tunnel이 public-origin 진입 경로를 대체하기 때문이다.

### 6.2 registry: 컨테이너 이미지 창고(ECR)

파일: `modules/registry/main.tf`

```text
GitHub Actions ── push ──> ECR: chaeso-zip-frontend
                                  ├── git SHA image
                                  ├── Alloy image
                                  └── app-/alloy- 각각 10개 규칙 (자동 삭제 OFF)
                                         ↓
                                     ECS가 pull
```

- `IMMUTABLE`은 같은 tag를 나중에 다른 이미지로 덮어쓰지 못하게 한다. 배포 재현성과 롤백에 중요하다.
- `scan_on_push = true`는 push한 이미지의 알려진 취약점을 검사한다.
- `app-`, `alloy-` 각각 최신 10개를 남기는 규칙을 준비했다. **자동 삭제는 기본 비활성화**다.
  개수 규칙은 실행 중인 이미지도 지울 수 있다. 실행/롤백 digest 보호 절차를 먼저 검증해야 한다.
  현재 보존 개수가 20개로 강제되는 것은 아니며, 비활성 기간에는 이미지가 계속 쌓일 수 있다.

### 6.3 secrets: 값이 아니라 “금고 자리”만 생성

파일: `modules/secrets/main.tf`

Terraform은 다음 7개 **Secrets Manager secret 컨테이너**만 만든다.

| 이름 | 사용하는 컨테이너 | 용도 |
| --- | --- | --- |
| `SESSION_ENCRYPTION_KEY` | Next.js | 세션 암호화 |
| `OBSERVABILITY_METRICS_ENABLED` | Next.js | 메트릭 활성화 여부 |
| `OBSERVABILITY_METRICS_BEARER_TOKEN` | Next.js + Alloy | 메트릭 요청 인증; 빈 값 금지 |
| `GRAFANA_PROM_URL` | Alloy | Grafana Prometheus endpoint |
| `GRAFANA_PROM_USER` | Alloy | Grafana 사용자 |
| `GRAFANA_TOKEN` | Alloy | Grafana 인증 token |
| `CLOUDFLARE_TUNNEL_TOKEN` | cloudflared | named Tunnel 인증 token |

```text
Terraform apply: 빈 Secrets Manager 항목 7개 생성
                         │
운영자 콘솔/안전한 CLI: 실제 값 주입     ← 값은 .tf, tfvars, state에 없음
                         │
ECS task 시작: execution role이 필요한 ARN에서 GetSecretValue
```

`recovery_window_in_days = 7`은 삭제 요청 뒤 7일 동안 복구할 수 있게 한다. secret 값을 Terraform으로
관리하지 않는 이유는 plan 로그, Git 기록, Terraform state에 비밀값이 남는 사고를 막기 위해서다.

### 6.4 iam: “누가 무엇을 해도 되는가”

파일: `modules/iam/main.tf`

IAM은 사용자 계정이 아니라 **역할(role)** 에 권한을 주는 방식이다. 장기 AWS access key는 만들지 않는다.

```text
ECS가 task 시작 ── AssumeRole ──> execution role
                                      ├── ECR image pull
                                      ├── CloudWatch Logs write
                                      └── 7개 secret 읽기

Next.js / Alloy / cloudflared ─────> task role
                                      └── 현재 AWS API 권한 없음

GitHub Actions(main) ─ OIDC token ─> GitHub Actions role
                                      ├── ECR image push
                                      ├── static S3 upload/delete
                                      ├── ECS definition/service update
                                      └── 두 ECS role만 PassRole
```

| role | 신뢰하는 주체 | 할 수 있는 일 | 하지 못하는 일 |
| --- | --- | --- | --- |
| execution role | `ecs-tasks.amazonaws.com` | ECR pull, Logs, 7개 secret 읽기 | 앱 코드에 이 role의 자격 증명 제공 |
| task role | `ecs-tasks.amazonaws.com` | 현재 없음 | S3, secret, ECS 등 모든 AWS API |
| GitHub Actions role | 지정 GitHub repo의 `main` OIDC token | deploy에 필요한 ECR/S3/ECS/PassRole | 다른 repo/branch의 role assume, IAM 관리자 작업 |

사람은 이 프로젝트의 기존 Builder ID로 콘솔에 로그인한다. 이 계정 유형에서는 IAM 사용자 콘솔 로그인은
지원되지 않는다. task role에는 이 코드가 추가하는 AWS API 정책이 없지만, 계정의 관리형 정책과
resource policy를 포함한 실효 권한은 실제 계정에서 별도로 확인한다.

GitHub role의 trust policy가 특히 중요하다. 다음 조건을 **둘 다** 확인한다.

```text
aud = sts.amazonaws.com
sub = repo:YAPP-Github/28th-Web-Team-4-FE:ref:refs/heads/main
```

즉 올바른 GitHub OpenID Connect 발급자여야 하고, 정확히 이 repository의 `main` 실행이어야만 AWS role을
빌릴 수 있다. 나중에 preview 배포 브랜치를 허용하고 싶으면 이 조건을 별도로 설계·리뷰해야 한다.

`iam:PassRole`은 GitHub Actions가 task definition을 등록할 때 ECS에 execution/task role을 전달하기
위해 필요한 권한이다. 두 role ARN으로만 제한돼 있어 임의 role을 전달할 수 없다.

### 6.5 ecs: 실제 서버(task) 실행

파일: `modules/ecs/main.tf`

```text
ECS cluster: chaeso-zip-frontend
└── ECS service (desired_count = 1, FARGATE_SPOT)
    └── task #1 (ARM64, 0.25 vCPU / 1 GiB)
        ├── nextjs       CPU 160 / memory reservation 384 MiB, :3000
        ├── alloy        CPU 48  / memory reservation 128 MiB
        └── cloudflared  CPU 48  / memory reservation 128 MiB
```

task definition은 세 컨테이너가 같은 task network namespace에서 실행되게 한다. 그래서 cloudflared와
Alloy는 Next.js를 `127.0.0.1:3000`으로 부를 수 있다. 외부 DNS나 ALB가 필요 없다.

| 코드 설정 | 의미 | 운영상 효과 |
| --- | --- | --- |
| `cpu = 256`, `memory = 1024` | task 전체 크기 | Fargate의 0.25 vCPU / 1 GiB 조합 |
| `ARM64` | Graviton 아키텍처 | 기존 운영 구성과 일치, image도 ARM64여야 함 |
| `FARGATE_SPOT` | 남는 Fargate 용량을 할인받아 사용 | 비용 절감, 중단 가능성 대비가 필요 |
| `desired_count = 1` | 평상시 task 한 개 유지 | 비용 절감, Spot 회수/장애 시 대체 task 준비까지 중단 가능 |
| `minimum_healthy = 100`, `maximum = 200` | 롤링 배포 중 기존 1개 유지, 최대 2개까지 | 새 task를 먼저 시작, Tunnel 준비는 별도 검증 필요 |
| circuit breaker + rollback | 새 task가 시작 실패하면 | ECS가 실패 배포를 되돌림 |
| `ignore_changes = [task_definition]` | 앱 CD가 올린 revision을 Terraform이 무시 | 다음 infra apply가 배포 이미지를 옛것으로 되돌리지 않음 |

컨테이너 시작 순서도 고정해 두었다.

```text
Next.js 시작 → /api/internal/health가 healthy
                          ├── Alloy 시작
                          └── cloudflared 시작 → Tunnel 연결
```

health check는 30초마다 내부 endpoint를 호출한다. 3번 연속 실패해야 unhealthy로 판정하며, 시작 후
처음 30초는 준비 시간으로 준다. 이 endpoint는 app 저장소에 추가되어 있으나 아직 해당 앱 변경은 배포되지
않았다.

### 6.6 delivery: 정적 파일은 CloudFront로

파일: `modules/delivery/main.tf`

Next.js 요청 경로와 별도로 static 파일은 private S3 + CloudFront 구조로 둔다.

```text
브라우저 ── HTTPS ──> CloudFront ── OAC 서명 요청 ──> private S3 bucket
                         │                                  ▲
                         └──── S3 public access: 차단 ──────┘
```

- S3는 public이 아니며, CloudFront의 Origin Access Control(OAC)만 `s3:GetObject`를 받는다.
- `static_domain`과 `static_acm_certificate_arn`은 인증서 검증 전에는 `null`이다. 나중에 정적 도메인을
  전환할 때만 입력한다.
- CloudFront custom domain certificate는 AWS 제약상 `us-east-1`에서 발급한 ACM 인증서 ARN이어야 한다.
- `force_destroy = false`이므로 bucket이 비어 있지 않으면 Terraform이 삭제하지 않는다.

## 7. 입력값은 어디에 두는가

`environments/production/variables.tf`는 **변수의 형식·기본값·설명**이고,
`terraform.tfvars`는 **이 운영 환경의 실제 값**이다. 실제 `terraform.tfvars`는 gitignore 대상이다.

```text
variables.tf                 terraform.tfvars (로컬/CI 안전한 주입)
---------------              -----------------------------------------
"계정 ID는 string"    +     aws_account_id = "실제 12자리 ID"
"이미지는 반드시 입력" +     app_image = "...:<git-sha>"
"처음에는 0"          +     desired_count = 0
```

Fresh Canvas 계정에서 Advanced 기능을 활성화했으므로, 운영 provider는 한국 사용자 지연 시간을 줄이기
위해 서울(`ap-northeast-2`)을 사용한다. 기존 시드니 state bucket은 Terraform 메타데이터 전용이다.
state bucket의 리전이 워크로드 리전을 정하지 않으므로, 같은 bucket 안에서도 서울용 production key를
분리해 사용할 수 있다.

## 8. GitHub Actions는 무엇을 검사하는가

파일: `.github/workflows/terraform.yml`

```text
PR 생성 또는 main push
       │
       ├── bootstrap/ 검증
       └── environments/production/ 검증
              │
              ├── terraform fmt -check -recursive
              ├── terraform init -backend=false
              └── terraform validate
```

이 workflow는 **AWS에 apply하지 않는다.** `init -backend=false`는 실제 production state S3에 연결하지
않고 provider/module 문법만 준비한다. `validate`도 계정 자원을 만들지 않는다.

현재 전용 infra 저장소에서는 `paths` 필터를 두지 않는다. Terraform 디렉터리 밖의 변경이라도 workflow,
문서와 운영 절차에 영향을 주는지 PR에서 확인하는 편이 초기 저장소에는 안전하기 때문이다. 추후 PR 수가
많아져 비용/대기 시간이 문제일 때만, 실제 구조가 안정된 뒤에 선택적으로 추가한다.

CI와 코드 모두 Terraform `1.17` 계열로 고정했다. 포맷 검사는 저장소 루트에서 수행해 `modules/`도 포함한다.

```hcl
required_version = "~> 1.17.0"  # 1.17.0 이상, 1.18.0 미만
```

GitHub Actions는 검증한 패치 버전인 `1.17.1`을 설치한다. 같은 minor 계열로 묶어 개발자와 CI의 plan 결과가
불필요하게 달라지는 것을 줄인다.

## 9. 실제 최초 적용의 안전한 순서

아래 단계는 아직 실행하지 않았다. 각 단계의 `plan`을 먼저 보고 승인받은 뒤에만 `apply`한다.

```text
1. bootstrap plan/apply
       ↓
2. production backend 설정 + desired_count=0 plan/apply
       ↓
3. Doppler 원본을 기준으로 secret 값 7개 주입 (빈 token 금지)
       ↓
4. 수동 cd-seoul로 ARM64 image push 및 service revision 연결 (task 수 0 확인 후 실행)
       ↓
5. Cloudflare named Tunnel 생성, token을 secret에 주입
       ↓
6. desired_count=1 plan/apply
       ↓
7. 임시 hostname으로 health/Tunnel/로그 검증
       ↓
8. Cloudflare DNS를 새 Tunnel/CloudFront로 전환
       ↓
9. 48시간 관찰 후 이전 인프라 종료 검토
```

## 10. 처음에는 이렇게 읽으면 된다

1. `environments/production/main.tf`에서 어떤 module이 조립되는지 본다.
2. 궁금한 영역의 `modules/<이름>/main.tf`를 읽는다.
3. 변경 가능한 값은 같은 module의 `variables.tf`, 결과값은 `outputs.tf`에서 찾는다.
4. 실제 변경 전에는 반드시 `terraform plan` 결과의 `+ create`, `~ update`, `- destroy`를 읽는다.
5. `- destroy`가 하나라도 보이면 apply 전에 멈추고 대상이 맞는지 검토한다.

이 저장소에서 Terraform이 맡지 않는 것도 분명히 구분한다.

| Terraform이 관리 | Terraform이 관리하지 않음 |
| --- | --- |
| AWS 네트워크/ECR/ECS/IAM/CloudFront/secret 컨테이너 | secret의 실제 값 |
| ECS service의 기반 구성 | Next.js 소스·Docker build |
| GitHub가 AWS에 접근할 OIDC role | Cloudflare Tunnel 생성과 DNS 전환 |
| 첫 task definition | 이후 이미지 revision을 올리는 앱 저장소 CD |

이 경계를 유지해야 비밀값이 state에 남지 않고, 인프라 배포가 앱 배포를 덮어쓰지 않는다.
