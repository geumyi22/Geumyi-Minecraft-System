package main

// GSCReleaseChannel is read-only operator guidance for signed update
// channel selection. It does not publish/promote a release or grant
// permission to install, restart, or alter any Minecraft server.
type GSCReleaseChannel struct {
 ID               string `json:"id"`
 Label            string `json:"label"`
 Purpose          string `json:"purpose"`
 Audience         string `json:"audience"`
 Risk             string `json:"risk"`
 Recommended      bool   `json:"recommended"`
 RequiresOptIn    bool   `json:"requires_opt_in"`
 SignedManifest   string `json:"signed_manifest"`
 PromotionGate    string `json:"promotion_gate"`
}

func gscReleaseChannelCatalog() []GSCReleaseChannel {
 return []GSCReleaseChannel{
  {
   ID: "stable", Label: "Stable · 안정 운영", Purpose: "검증·승인을 끝낸 정식 운영 버전",
   Audience: "메인 서버 PC와 일반 관리 PC", Risk: "lowest", Recommended: true,
   RequiresOptIn: false, SignedManifest: "deployment-stable.json",
   PromotionGate: "CI·보안·서명·회귀·대표 실기기 테스트·복구 검증·운영 승인",
  },
  {
   ID: "beta", Label: "Beta · 사전 시험", Purpose: "정식 출시 전 기능·호환성 검증",
   Audience: "보조 PC와 선택적 테스터", Risk: "medium", Recommended: false,
   RequiresOptIn: true, SignedManifest: "deployment-beta.json",
   PromotionGate: "CI·핵심 기능 테스트·알려진 문제 및 롤백 계획·시험 배포 승인",
  },
  {
   ID: "canary", Label: "Canary · 개발 실험", Purpose: "최신 변경 사항의 조기 오류 발견",
   Audience: "격리 개발/테스트 환경", Risk: "high", Recommended: false,
   RequiresOptIn: true, SignedManifest: "deployment-canary.json",
   PromotionGate: "기본 빌드·정적/보안 검사·합성 테스트·추적 가능한 후보",
  },
 }
}
