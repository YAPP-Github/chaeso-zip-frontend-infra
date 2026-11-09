# chaeso-zip-frontend-infra

채소ZIP 프론트엔드 운영 인프라를 Terraform으로 관리하는 저장소입니다.

이 저장소는 네트워크, ECR, ECS, IAM/OIDC, CloudWatch, S3·CloudFront와 ECS 서비스 기반을
관리합니다. 애플리케이션 소스와 컨테이너 이미지 빌드·배포는
`28th-Web-Team-4-FE` 저장소가 담당합니다.

시크릿 값과 Cloudflare Tunnel 토큰은 Terraform 변수나 state에 저장하지 않습니다.
