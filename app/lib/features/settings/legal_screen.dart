import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/theme.dart';

// ── 개인정보처리방침 ──────────────────────────────────────

class PrivacyPolicyScreen extends StatelessWidget {
  const PrivacyPolicyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return _LegalScreen(
      title: '개인정보처리방침',
      lastUpdated: '2026년 3월 27일',
      sections: const [
        _Section(
          title: '1. 개인정보 수집 항목 및 수집 방법',
          body: '얼마였지?(이하 "서비스")는 다음과 같은 정보를 수집합니다.\n\n'
              '【필수 수집 항목】\n'
              '• 기기 고유 식별자(UUID): 앱 최초 실행 시 기기 내 자동 생성\n'
              '• 운영체제 종류(iOS/Android), 앱 버전: 서비스 환경 파악\n'
              '• 바코드 스캔 이력(바코드 번호, 스캔 일시): 가격 비교 서비스 제공\n'
              '• 온라인 가격 조회 결과: 스캔 시 자동 수집\n\n'
              '【선택 수집 항목】\n'
              '• 오프라인 가격 입력값, 장소명, 메모: 이용자가 직접 입력\n'
              '• 게시글 내용(제목, 본문, 가격, 첨부 이미지): 이용자가 직접 작성\n'
              '• 찜 목록(관심 바코드): 이용자가 직접 등록\n'
              '• FCM 푸시 알림 토큰: 알림 수신 동의 시 수집\n'
              '• 소셜 로그인 정보(이름, 이메일): 구글·카카오·네이버 로그인 선택 시 수집\n\n'
              '수집 방법: 앱 내 이용자 직접 입력, 서비스 이용 과정에서 자동 수집\n\n'
              '※ 서비스는 GPS 등 기기 위치 정보를 수집하지 않습니다.',
        ),
        _Section(
          title: '2. 개인정보 수집·이용 목적',
          body: '• 바코드 스캔 기반 가격 비교 서비스 제공\n'
              '• 개인별 스캔 이력 및 가격 변동 추적 서비스 제공\n'
              '• 오프라인 가격 및 장소 기록 (이용자 직접 입력 시)\n'
              '• 공유 게시판 서비스 운영\n'
              '• 소셜 로그인을 통한 기기 교체 시 데이터 연속성 제공\n'
              '• 서비스 개선 및 오류 분석\n'
              '• 불법·부적절한 콘텐츠 신고 처리',
        ),
        _Section(
          title: '3. 개인정보 보유 및 이용 기간',
          body: '수집된 개인정보는 서비스 이용 목적이 달성된 후 즉시 파기합니다.\n\n'
              '• 스캔 이력, 가격 정보, 찜 목록: 이용자가 직접 삭제하거나 서비스 탈퇴 요청 시까지\n'
              '• 게시글·댓글: 게시 삭제 요청 시까지\n'
              '• 기기 정보(UUID, OS): 마지막 앱 사용일로부터 1년\n'
              '• FCM 토큰: 알림 수신 철회 또는 서비스 탈퇴 시까지\n\n'
              '단, 관련 법령에 의해 보존이 필요한 경우 해당 기간 동안 보관합니다.',
        ),
        _Section(
          title: '4. 개인정보의 제3자 제공',
          body: '서비스는 이용자의 개인정보를 원칙적으로 외부에 제공하지 않습니다.\n\n'
              '다음의 경우에는 예외적으로 제공할 수 있습니다.\n'
              '• 이용자가 사전에 동의한 경우\n'
              '• 법령의 규정에 의거하거나 수사기관의 적법한 요청이 있는 경우',
        ),
        _Section(
          title: '5. 개인정보 처리 위탁 및 국외 이전',
          body: '서비스는 서비스 운영을 위해 아래와 같이 개인정보 처리 업무를 위탁하며, '
              '일부 업무는 국외에서 처리될 수 있습니다.\n\n'
              '【국외 이전】\n'
              '• 이전받는 자: Google LLC\n'
              '  이전 국가: 미국 (및 Google 데이터 센터 소재 국가)\n'
              '  이전 항목: 기기 UUID, FCM 토큰, 앱 이용 데이터\n'
              '  이전 목적: 푸시 알림 발송(Firebase Cloud Messaging), 앱 안정성 분석\n'
              '  보유 기간: 서비스 이용 종료 시까지\n'
              '  연락처: https://policies.google.com/privacy\n\n'
              '• 이전받는 자: Apple Inc.\n'
              '  이전 국가: 미국\n'
              '  이전 항목: 앱 배포 관련 정보\n'
              '  이전 목적: App Store를 통한 앱 배포 및 업데이트\n'
              '  보유 기간: 서비스 이용 종료 시까지\n'
              '  연락처: https://www.apple.com/legal/privacy\n\n'
              '【국내 위탁】\n'
              '위탁 업체들은 서비스 제공 목적 이외의 용도로 개인정보를 사용하지 않습니다.',
        ),
        _Section(
          title: '6. 이용자의 권리 및 행사 방법',
          body: '이용자는 언제든지 다음과 같은 개인정보 보호 권리를 행사할 수 있습니다.\n\n'
              '• 개인정보 조회: 앱 내 스캔 기록 화면에서 직접 확인\n'
              '• 개인정보 삭제: 설정 > 스캔 기록 전체 삭제 기능 이용\n'
              '• 게시글 삭제: 게시판 내 본인 게시글 직접 삭제\n'
              '• 푸시 알림 수신 거부: 기기 설정에서 알림 비허용\n\n'
              '위 방법으로 해결되지 않는 경우 아래 연락처로 문의해주세요.',
        ),
        _Section(
          title: '7. 개인정보 파기',
          body: '수집된 개인정보는 보유 기간 종료 또는 이용자의 삭제 요청 시 다음 방법으로 파기합니다.\n\n'
              '• 전자적 파일 형태: 복구 불가능한 방법으로 영구 삭제\n'
              '• 게시 이미지 파일: 서버 파일 시스템에서 영구 삭제',
        ),
        _Section(
          title: '8. 만 14세 미만 아동의 개인정보',
          body: '서비스는 만 14세 미만 아동의 개인정보를 수집하지 않습니다.\n'
              '만 14세 미만 아동의 경우 서비스 이용을 제한합니다.',
        ),
        _Section(
          title: '9. 개인정보 보호책임자',
          body: '개인정보 처리에 관한 문의, 불만, 피해구제는 아래로 연락해주세요.\n\n'
              '• 이메일: eolmaeossjeo@gmail.com\n'
              '• 처리 기간: 접수 후 7영업일 이내 회신\n\n'
              '또한 개인정보 침해 관련 신고 및 상담은 아래 기관에 문의하실 수 있습니다.\n'
              '• 개인정보보호위원회: privacy.go.kr / 국번없이 182\n'
              '• 한국인터넷진흥원 개인정보침해신고센터: privacy.kisa.or.kr / 국번없이 118',
        ),
        _Section(
          title: '10. 개인정보처리방침 변경',
          body: '본 방침은 법령·정책 변경이나 서비스 변경에 따라 수정될 수 있습니다.\n'
              '변경 시 앱 내 공지 또는 업데이트를 통해 사전 고지합니다.\n\n'
              '시행일: 2026년 3월 27일',
        ),
      ],
    );
  }
}

// ── 이용약관 ──────────────────────────────────────────────

class TermsScreen extends StatelessWidget {
  const TermsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return _LegalScreen(
      title: '이용약관',
      lastUpdated: '2026년 3월 27일',
      sections: const [
        _Section(
          title: '제1조 (목적)',
          body: '본 약관은 얼마였지?(이하 "서비스")의 이용 조건 및 절차, 이용자와 운영자의 권리·의무 및 책임 사항을 규정함을 목적으로 합니다.',
        ),
        _Section(
          title: '제2조 (서비스 내용)',
          body: '서비스는 다음의 기능을 제공합니다.\n\n'
              '• 바코드 스캔을 통한 온라인 쇼핑몰 가격 비교\n'
              '• 개인 스캔 이력 및 가격 변동 추적\n'
              '• 오프라인 가격 직접 입력 및 온·오프라인 가격 비교\n'
              '• 찜 기능(관심 상품 저장)\n'
              '• 커뮤니티 가격 공유 게시판',
        ),
        _Section(
          title: '제3조 (서비스 이용)',
          body: '① 서비스는 별도의 회원가입 없이 이용할 수 있습니다. '
              '기기 고유 식별자(UUID)를 통해 이용자를 구분합니다.\n\n'
              '② 이용자는 구글·카카오·네이버 소셜 로그인을 통해 계정을 연결할 수 있습니다. '
              '소셜 로그인은 기기 교체 시 데이터 연속성을 위한 선택적 기능이며, '
              '연결하지 않아도 모든 서비스를 이용할 수 있습니다.\n\n'
              '③ 이용자는 서비스 이용 시 본 약관에 동의한 것으로 간주합니다.\n\n'
              '④ 서비스는 만 14세 이상의 이용자를 대상으로 합니다.',
        ),
        _Section(
          title: '제4조 (이용자의 의무)',
          body: '이용자는 다음 행위를 해서는 안 됩니다.\n\n'
              '• 허위 가격 정보 게시 또는 다른 이용자를 오도하는 행위\n'
              '• 타인의 명예를 훼손하거나 불쾌감을 주는 콘텐츠 게시\n'
              '• 음란물, 폭력적 콘텐츠, 불법 정보 게시\n'
              '• 저작권 등 타인의 지적재산권 침해\n'
              '• 서비스 운영을 방해하거나 서버에 과도한 부하를 주는 행위\n'
              '• 자동화 도구를 이용한 비정상적인 서비스 이용',
        ),
        _Section(
          title: '제5조 (게시물 정책)',
          body: '① 게시판에 작성된 게시글, 댓글, 이미지(이하 "게시물")의 저작권은 작성자에게 있습니다.\n\n'
              '② 이용자는 게시물을 작성함으로써 서비스가 해당 게시물을 서비스 운영 목적에 한하여 표시·전송할 수 있는 권리를 부여합니다.\n\n'
              '③ 서비스는 다음에 해당하는 게시물을 사전 통보 없이 삭제하거나 숨길 수 있습니다.\n'
              '  - 타인의 권리를 침해하는 게시물\n'
              '  - 허위 정보 또는 스팸성 게시물\n'
              '  - 불법 콘텐츠 또는 커뮤니티 기준 위반 게시물\n'
              '  - 다른 이용자로부터 반복 신고된 게시물\n\n'
              '④ 이용자는 본인이 작성한 게시물을 언제든지 삭제할 수 있습니다.',
        ),
        _Section(
          title: '제6조 (가격 정보의 정확성)',
          body: '① 서비스가 제공하는 온라인 가격 정보는 각 쇼핑몰이 공개한 데이터 및 '
              '검색 API를 통해 수집되며, 실제 판매 가격과 차이가 있을 수 있습니다.\n\n'
              '② 이용자가 직접 입력한 오프라인 가격 정보의 정확성은 해당 이용자에게 책임이 있습니다.\n\n'
              '③ 서비스는 가격 정보의 오류로 인해 발생한 손해에 대해 책임을 지지 않습니다. '
              '중요한 구매 결정은 반드시 실제 매장이나 쇼핑몰에서 최종 가격을 확인하시기 바랍니다.',
        ),
        _Section(
          title: '제7조 (서비스 변경 및 중단)',
          body: '① 서비스는 운영상 필요에 따라 서비스 내용을 변경하거나 중단할 수 있습니다.\n\n'
              '② 서비스 중단 시에는 앱 내 공지를 통해 사전에 고지합니다. '
              '단, 긴급한 기술적 사유로 인한 일시 중단은 사후 고지할 수 있습니다.\n\n'
              '③ 서비스 변경 또는 중단으로 인해 발생한 손해에 대해서는 관련 법령이 허용하는 범위 내에서 책임을 지지 않습니다.',
        ),
        _Section(
          title: '제8조 (면책 조항)',
          body: '① 서비스는 이용자 간의 거래 또는 분쟁에 개입하지 않으며, 이로 인한 손해에 대해 책임지지 않습니다.\n\n'
              '② 서비스는 천재지변, 해킹, 통신장애 등 불가항력적 사유로 인한 서비스 중단에 대해 책임지지 않습니다.\n\n'
              '③ 이용자가 본 약관을 위반하여 발생한 손해는 해당 이용자가 책임을 집니다.',
        ),
        _Section(
          title: '제9조 (준거법 및 관할 법원)',
          body: '본 약관은 대한민국 법령에 따라 해석되며, 서비스 이용으로 발생한 분쟁은 대한민국 법원을 관할 법원으로 합니다.',
        ),
        _Section(
          title: '제10조 (문의)',
          body: '본 약관에 관한 문의는 아래 연락처로 해주세요.\n\n'
              '• 이메일: eolmaeossjeo@gmail.com\n\n'
              '시행일: 2026년 3월 27일',
        ),
      ],
    );
  }
}

// ── 마케팅 정보 수신 ──────────────────────────────────────

class MarketingInfoScreen extends StatelessWidget {
  const MarketingInfoScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return _LegalScreen(
      title: '마케팅 정보 수신',
      lastUpdated: '2026년 3월 27일',
      sections: const [
        _Section(
          title: '수신 동의 목적',
          body: '마케팅 정보 수신에 동의하시면 아래와 같은 혜택 정보를 받아보실 수 있습니다.\n\n'
              '• 얼마였지? 신규 기능 및 업데이트 안내\n'
              '• 시즌별 특가·핫딜 상품 정보\n'
              '• 가격 하락 트렌드 리포트\n'
              '• 이벤트 및 프로모션 안내',
        ),
        _Section(
          title: '수신 채널',
          body: '• 앱 푸시 알림\n\n'
              '마케팅 알림은 서비스 필수 알림과 별개로 운영됩니다.',
        ),
        _Section(
          title: '수신 거부 방법',
          body: '마케팅 정보 수신 동의는 선택 사항이며, 동의하지 않아도 서비스를 정상적으로 이용할 수 있습니다.\n\n'
              '수신 거부 방법:\n'
              '• 기기 설정 > 알림 > 얼마였지? > 마케팅 알림 끄기\n\n'
              '수신 거부 시에도 서비스 관련 필수 알림은 계속 수신됩니다.',
        ),
        _Section(
          title: '개인정보 처리',
          body: '마케팅 목적으로 수집된 정보는 마케팅 발송 목적 외에 사용되지 않으며, '
              '수신 동의 철회 시 즉시 발송이 중단됩니다.\n\n'
              '자세한 사항은 개인정보처리방침을 참고해주세요.',
        ),
      ],
    );
  }
}

// ── 공통 레이아웃 ─────────────────────────────────────────

class _LegalScreen extends StatelessWidget {
  final String title;
  final String lastUpdated;
  final List<_Section> sections;

  const _LegalScreen({
    required this.title,
    required this.lastUpdated,
    required this.sections,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBackground,
      appBar: AppBar(
        backgroundColor: kSurface,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, size: 18, color: kOnSurface),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          title,
          style: GoogleFonts.notoSansKr(
            fontSize: 17,
            fontWeight: FontWeight.w700,
            color: kOnSurface,
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 48),
        children: [
          // 시행일 배지
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: kPrimary.withValues(alpha: 0.07),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                const Icon(Icons.calendar_today_outlined, size: 14, color: kPrimary),
                const SizedBox(width: 8),
                Text(
                  '최종 업데이트: $lastUpdated',
                  style: GoogleFonts.notoSansKr(
                    fontSize: 12,
                    color: kPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          ...sections.map((s) => _SectionWidget(section: s)),
        ],
      ),
    );
  }
}

class _Section {
  final String title;
  final String body;
  const _Section({required this.title, required this.body});
}

class _SectionWidget extends StatelessWidget {
  final _Section section;
  const _SectionWidget({required this.section});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            section.title,
            style: GoogleFonts.notoSansKr(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: kOnSurface,
            ),
          ),
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: kSurface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.grey.shade100),
            ),
            child: SelectableText(
              section.body,
              style: GoogleFonts.notoSansKr(
                fontSize: 13,
                color: kOnSurfaceVariant,
                height: 1.8,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
