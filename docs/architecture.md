# Terraform 아키텍처

## 리전과 state

Fresh Canvas 계정은 Advanced 기능을 활성화했다. 운영 워크로드 provider는 서울(`ap-northeast-2`)을
사용한다. 기존 시드니(`ap-southeast-2`) S3 bucket은 이미 생성된 Terraform state 저장소로만 남기고,
production state key는 `seoul/production/terraform.tfstate`로 분리한다. state bucket의 리전과
워크로드 리전은 독립적이므로, 이를 위해 서비스 리소스를 시드니에 만들지는 않는다.

## 모듈별 책임

| 경로 | 생성 대상 | 설계 이유 |
| --- | --- | --- |
| `bootstrap/` | versioning/encryption/public-block이 적용된 state S3 bucket | application state보다 먼저 1회 적용한다. `prevent_destroy`로 우발 삭제를 막는다. |
| `modules/network` | VPC, 2개 public subnet, IGW, route table, task security group | Tunnel은 task에서 Cloudflare로 나가는 outbound 연결이므로 NAT/ALB/inbound rule이 필요 없다. |
| `modules/registry` | immutable ECR, scan on push, 종류별 10개 보존 규칙 preview | 자동 삭제 기본 off. 실행/롤백 digest 보호 절차 검증 후에만 활성화한다. |
| `modules/secrets` | Secrets Manager secret **컨테이너** 7개 | 기존 5개 + Tunnel/metrics 인증 token. 값은 별도 주입한다. |
| `modules/iam` | task execution/task/GitHub OIDC roles | runtime·CI 권한을 분리하고 장기 access key를 만들지 않는다. |
| `modules/ecs` | CloudWatch log group, ECS cluster, ARM64 Fargate Spot task/service | Next.js, Alloy, cloudflared가 한 task에서 localhost 통신한다. 평상시 Spot 1개, rolling 100/200(배포 중 최대 2개), rollback circuit breaker를 사용한다. |
| `modules/delivery` | private S3 static bucket, CloudFront OAC/distribution | 기존 static CloudFront와 병렬 검증한 뒤 `static` DNS만 전환한다. |

## IAM 경계

### ECS execution role

AWS 관리형 `AmazonECSTaskExecutionRolePolicy`로 ECR image pull과 CloudWatch Logs 전송을 허용한다.
추가 inline policy는 이 환경의 7개 Secrets Manager ARN에 대해서만 `GetSecretValue`를 허용한다.

### ECS task role

애플리케이션 프로세스에는 현재 AWS API 권한이 필요 없으므로 trust policy만 둔다. 앱이 AWS API를
직접 호출해야 할 때에만 해당 리소스의 최소 권한을 별도 정책으로 추가한다.

### GitHub Actions role

OIDC trust는 `YAPP-Github/28th-Web-Team-4-FE`의 `main` 브랜치 subject와 `sts.amazonaws.com`
audience만 허용한다. 권한은 ECR image push, S3 static object sync, ECS task definition 등록/service
update, 그리고 두 ECS role에 대한 `iam:PassRole`로 한정한다. service update는 이 서비스 ARN으로,
PassRole은 `ecs-tasks.amazonaws.com`으로 제한한다. access key는 사용하지 않는다.

콘솔은 현재 프로젝트 소유자의 Builder ID를 사용한다. 이 가입 방식은 IAM 사용자 콘솔 로그인을 지원하지
않는다. 로컬 Terraform용 임시 자격 증명 프로필은 별도로 확인한다. 실제 계정의 AWS 관리형 정책과
resource policy까지 조사하기 전에는 task role의 실효 권한이 없다고 단정하지 않는다.

## 배포 소유권

Terraform은 cluster/service/network/roles와 initial task definition을 만든다. 앱 저장소 CD가 새
immutable image tag로 task definition revision을 등록해 service를 업데이트한다. ECS service의
`task_definition` 변경은 Terraform lifecycle ignore로 지정해 인프라 apply가 앱 배포를 되돌리지 않는다.

## 초기 적용 순서

1. bootstrap apply → state bucket 생성
2. production backend 설정 후 `desired_count = 0`으로 apply
3. Secrets Manager 7개 값 주입 → task 수 0 확인 → 수동 `cd-seoul`로 이미지 push 및 revision 연결
4. `desired_count = 1` apply → 임시 hostname Tunnel 검증
5. Cloudflare DNS 전환 후 48시간 관찰

Container Insights는 비용 절감을 위해 off. Alloy는 기존 메모리 상한/재시작 정책을 유지한다.
Spot 클러스터 연결·로그 그룹·IAM 정책이 준비된 뒤에 서비스가 생성된다.
세부 승인 지점과 남은 실제 검증은 [실행 순서](preflight-runbook.md)를 따른다.

운영 task 목표는 1개지만 배치 후보 public subnet은 2개를 유지한다. 평상시 공인 IPv4는 1개이며
배포 중에는 새 task의 IP가 일시적으로 추가된다. 롤링 배포는 새 task를 먼저 시작하므로 계획된
중단은 필수가 아니다. 다만 현재 ECS health check는 Tunnel 연결을 확인하지 않으며, 실제 무중단은
외부 요청으로 검증해야 한다. Spot 회수/장애 시에는 대체 task와 Tunnel이 준비될 때까지 중단될 수
있고, Spot 용량 부족이 지속되면 중단 시간도 길어질 수 있다.
