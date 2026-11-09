# chaeso-zip-frontend-infra

채소ZIP 프론트엔드 운영 인프라를 Terraform으로 관리하는 저장소입니다. 최초 환경은
시드니(`ap-southeast-2`)이며, 서울 이전 시에는 같은 모듈을 별도 state로 적용합니다.

이 저장소는 네트워크, ECR, ECS, IAM/OIDC, CloudWatch, S3·CloudFront와 ECS 서비스 기반을
관리합니다. 애플리케이션 소스와 컨테이너 이미지 빌드·배포는
`28th-Web-Team-4-FE` 저장소가 담당합니다.

시크릿 값과 Cloudflare Tunnel 토큰은 Terraform 변수나 state에 저장하지 않습니다.

## 소유 경계

| 저장소 | 소유 대상 |
| --- | --- |
| 이 저장소 | VPC, ECR, ECS service/role/log, Secrets Manager 컨테이너, S3·CloudFront |
| `28th-Web-Team-4-FE` | Next.js·Docker 이미지, task-definition revision, GitHub Actions 배포 |

ECS service는 인프라 bootstrap 뒤 app 저장소의 task definition revision을 허용하도록
`task_definition` drift를 무시합니다. 인프라 apply가 배포된 이미지를 되돌리지 않습니다.

## 순서

1. `bootstrap/`을 적용해 encrypted/versioned Terraform state bucket을 만든다.
2. 생성된 버킷을 `environments/production` S3 backend로 설정하고 state lockfile을 활성화한다.
3. production apply는 `desired_count = 0`으로 시작한다.
4. 출력된 6개 Secrets Manager 컨테이너에 기존 런타임 시크릿 5개와 Cloudflare Tunnel token을 주입한다.
5. app 저장소 CI로 새 ECR에 Next.js·Alloy 이미지를 push하고, task definition을 등록한다.
6. `desired_count = 2`로 변경해 Spot 태스크 2개를 기동한다.
7. 임시 hostname 검증 뒤에만 Cloudflare DNS를 전환한다.

`terraform.tfvars`와 state 파일은 커밋하지 않습니다. Cloudflare Tunnel과 DNS는 Terraform이 아닌
Cloudflare Dashboard에서 별도 검증·승인 흐름으로 관리합니다.
