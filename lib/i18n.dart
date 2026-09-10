/// 轻量国际化：7 语言词表 + 全局语言状态 + agent 可调用的切换入口
///
/// 设计取舍：
/// - **不引入 flutter gen-l10n / intl 的 ARB 流程**。项目是单一语言起步、文案散落在
///   各页面的字面量里，gen-l10n 需要先把所有文案抽成 ARB 才能编译，迁移成本过高。
///   这里用「key → 语言代码 → 文案」的常量表，缺 key 时回落 zh-Hans、再回落 key 本身，
///   可以**逐页增量迁移**：改一页是一页，未迁移的页面继续显示原文，不会编译失败。
/// - 读取不需要 BuildContext（`I18n.tr('nav.study')`），换语言靠根节点的
///   `ValueListenableBuilder` 整体重建 —— 一处接线，全树生效。
/// - 持久化走 `Storage`，与项目其它偏好一致。
library;

import 'package:flutter/foundation.dart';

import 'services/storage.dart';

/// 支持的语言
enum AppLang { zhHans, zhHant, en, ja, ko, id, ru }

/// 语言元信息：BCP-47 代码 + 自称 + 英文名
extension AppLangMeta on AppLang {
  String get code => switch (this) {
        AppLang.zhHans => 'zh-Hans',
        AppLang.zhHant => 'zh-Hant',
        AppLang.en => 'en',
        AppLang.ja => 'ja',
        AppLang.ko => 'ko',
        AppLang.id => 'id',
        AppLang.ru => 'ru',
      };

  /// 语言自称（下拉/提示里展示给用户看，用母语写）
  String get native => switch (this) {
        AppLang.zhHans => '简体中文',
        AppLang.zhHant => '繁體中文',
        AppLang.en => 'English',
        AppLang.ja => '日本語',
        AppLang.ko => '한국어',
        AppLang.id => 'Bahasa Indonesia',
        AppLang.ru => 'Русский',
      };

  static AppLang? fromCode(String? raw) {
    if (raw == null) return null;
    final s = raw.trim().toLowerCase().replaceAll('_', '-');
    for (final l in AppLang.values) {
      if (l.code.toLowerCase() == s) return l;
    }
    // 宽容匹配：zh / zh-cn / zh-hans-cn / en-us / ja-jp …
    if (s.startsWith('zh')) {
      final t = s.replaceAll('-', '');
      if (t.contains('hant') || t.contains('tw') || t.contains('hk') || t.contains('mo')) {
        return AppLang.zhHant;
      }
      return AppLang.zhHans;
    }
    if (s.startsWith('en')) return AppLang.en;
    if (s.startsWith('ja')) return AppLang.ja;
    if (s.startsWith('ko')) return AppLang.ko;
    if (s.startsWith('id') || s.startsWith('in')) return AppLang.id;
    if (s.startsWith('ru')) return AppLang.ru;
    return null;
  }
}

/// 语言表。key 采用「域.对象.属性」三段式，便于按页增量补充。
/// 缺某个语言时回落 zh-Hans。
const Map<String, Map<String, String>> _kTable = {
  // ========== 侧栏主导航 ==========
  'nav.study': {
    'zh-Hans': '学习', 'zh-Hant': '學習', 'en': 'Study', 'ja': '学習',
    'ko': '학습', 'id': 'Belajar', 'ru': 'Учёба',
  },
  'nav.quiz': {
    'zh-Hans': '答题', 'zh-Hant': '答題', 'en': 'Quiz', 'ja': '問題演習',
    'ko': '문제 풀이', 'id': 'Kuis', 'ru': 'Тесты',
  },
  'nav.report': {
    'zh-Hans': '学习报告', 'zh-Hant': '學習報告', 'en': 'Report', 'ja': '学習レポート',
    'ko': '학습 리포트', 'id': 'Laporan', 'ru': 'Отчёт',
  },
  'nav.lookup': {
    'zh-Hans': '查询', 'zh-Hant': '查詢', 'en': 'Lookup', 'ja': '検索',
    'ko': '조회', 'id': 'Pencarian', 'ru': 'Поиск',
  },
  'nav.more': {
    'zh-Hans': '更多功能', 'zh-Hant': '更多功能', 'en': 'More', 'ja': 'その他の機能',
    'ko': '더 보기', 'id': 'Lainnya', 'ru': 'Ещё',
  },
  'nav.settings': {
    'zh-Hans': '设置', 'zh-Hant': '設定', 'en': 'Settings', 'ja': '設定',
    'ko': '설정', 'id': 'Pengaturan', 'ru': 'Настройки',
  },

  // ========== 更多功能入口（标题 / 副标题）==========
  'more.lookup.t': {
    'zh-Hans': '查词', 'zh-Hant': '查詞', 'en': 'Lookup', 'ja': '辞書',
    'ko': '사전', 'id': 'Kamus', 'ru': 'Словарь',
  },
  'more.lookup.s': {
    'zh-Hans': '查单词/翻译', 'zh-Hant': '查單詞/翻譯', 'en': 'Words & translation',
    'ja': '単語検索・翻訳', 'ko': '단어 검색/번역', 'id': 'Cari kata/terjemah',
    'ru': 'Слова и перевод',
  },
  'more.bank.t': {
    'zh-Hans': '题库', 'zh-Hant': '題庫', 'en': 'Question bank', 'ja': '問題バンク',
    'ko': '문제 은행', 'id': 'Bank soal', 'ru': 'Банк заданий',
  },
  'more.bank.s': {
    'zh-Hans': '管理题目集', 'zh-Hant': '管理題目集', 'en': 'Manage question sets',
    'ja': '問題集の管理', 'ko': '문제집 관리', 'id': 'Kelola kumpulan soal',
    'ru': 'Управление наборами заданий',
  },
  'more.wrong.t': {
    'zh-Hans': '错题本', 'zh-Hant': '錯題本', 'en': 'Mistakes', 'ja': '間違いノート',
    'ko': '오답 노트', 'id': 'Buku kesalahan', 'ru': 'Тетрадь ошибок',
  },
  'more.wrong.s': {
    'zh-Hans': '复习做错的题', 'zh-Hant': '複習做錯的題', 'en': 'Review missed questions',
    'ja': '間違えた問題を復習', 'ko': '틀린 문제 복습', 'id': 'Ulas soal yang salah',
    'ru': 'Повторить ошибки',
  },
  'more.star.t': {
    'zh-Hans': '生词本', 'zh-Hant': '生詞本', 'en': 'Wordbook', 'ja': '単語帳',
    'ko': '단어장', 'id': 'Buku kosakata', 'ru': 'Словарь',
  },
  'more.star.s': {
    'zh-Hans': '收藏的生词', 'zh-Hant': '收藏的生詞', 'en': 'Saved words',
    'ja': '保存した単語', 'ko': '저장한 단어', 'id': 'Kata tersimpan',
    'ru': 'Сохранённые слова',
  },
  'more.record.t': {
    'zh-Hans': '答题记录', 'zh-Hant': '答題記錄', 'en': 'Answer history', 'ja': '解答履歴',
    'ko': '풀이 기록', 'id': 'Riwayat jawaban', 'ru': 'История ответов',
  },
  'more.record.s': {
    'zh-Hans': '记录已答单词', 'zh-Hant': '記錄已答單詞', 'en': 'Words you have answered',
    'ja': '解答済み単語の記録', 'ko': '푼 단어 기록', 'id': 'Kata yang sudah dijawab',
    'ru': 'Отвеченные слова',
  },
  'more.dictation.t': {
    'zh-Hans': '默写', 'zh-Hant': '默寫', 'en': 'Dictation', 'ja': 'ディクテーション',
    'ko': '받아쓰기', 'id': 'Dikte', 'ru': 'Диктант',
  },
  'more.dictation.s': {
    'zh-Hans': '单词默写练习', 'zh-Hant': '單詞默寫練習', 'en': 'Spelling practice',
    'ja': '単語の書き取り練習', 'ko': '단어 받아쓰기 연습', 'id': 'Latihan ejaan',
    'ru': 'Тренировка письма',
  },
  'more.maimemo.t': {
    'zh-Hans': '墨墨', 'zh-Hant': '墨墨', 'en': 'Maimemo', 'ja': '墨墨',
    'ko': '墨墨', 'id': 'Maimemo', 'ru': 'Maimemo',
  },
  'more.maimemo.s': {
    'zh-Hans': '同步墨墨词库', 'zh-Hant': '同步墨墨詞庫', 'en': 'Sync Maimemo wordbook',
    'ja': '墨墨単語帳を同期', 'ko': '墨墨 단어장 동기화',
    'id': 'Sinkronkan kosakata Maimemo', 'ru': 'Синхронизация Maimemo',
  },
  'more.grammar.t': {
    'zh-Hans': '语法学习', 'zh-Hant': '文法學習', 'en': 'Grammar', 'ja': '文法',
    'ko': '문법', 'id': 'Tata bahasa', 'ru': 'Грамматика',
  },
  'more.grammar.s': {
    'zh-Hans': '从零学会专升本语法', 'zh-Hant': '從零學會專升本語法',
    'en': 'Grammar from scratch', 'ja': '基礎から学ぶ文法',
    'ko': '기초부터 배우는 문법', 'id': 'Tata bahasa dari nol',
    'ru': 'Грамматика с нуля',
  },
  'more.browser.t': {
    'zh-Hans': '浏览器', 'zh-Hant': '瀏覽器', 'en': 'Browser', 'ja': 'ブラウザ',
    'ko': '브라우저', 'id': 'Peramban', 'ru': 'Браузер',
  },
  'more.browser.s': {
    'zh-Hans': '轻量网页浏览', 'zh-Hant': '輕量網頁瀏覽', 'en': 'Lightweight browsing',
    'ja': '軽量ブラウザ', 'ko': '경량 브라우저', 'id': 'Peramban ringan',
    'ru': 'Лёгкий браузер',
  },
  'more.snake.t': {
    'zh-Hans': '贪吃蛇', 'zh-Hant': '貪食蛇', 'en': 'Snake', 'ja': 'スネーク',
    'ko': '스네이크', 'id': 'Ular', 'ru': 'Змейка',
  },
  'more.snake.s': {
    'zh-Hans': '经典小游戏放松', 'zh-Hant': '經典小遊戲放鬆', 'en': 'Classic mini game',
    'ja': '定番ミニゲーム', 'ko': '클래식 미니게임', 'id': 'Gim klasik',
    'ru': 'Классическая игра',
  },
  'more.gomoku.t': {
    'zh-Hans': '五子棋', 'zh-Hant': '五子棋', 'en': 'Gomoku', 'ja': '五目並べ',
    'ko': '오목', 'id': 'Gomoku', 'ru': 'Гомоку',
  },
  'more.gomoku.s': {
    'zh-Hans': '双人对战五子连珠', 'zh-Hant': '雙人對戰五子連珠',
    'en': 'Two-player gomoku', 'ja': '二人対戦の五目並べ',
    'ko': '2인 오목 대전', 'id': 'Gomoku dua pemain', 'ru': 'Гомоку на двоих',
  },
  'more.mine.t': {
    'zh-Hans': '扫雷', 'zh-Hant': '踩地雷', 'en': 'Minesweeper', 'ja': 'マインスイーパ',
    'ko': '지뢰찾기', 'id': 'Minesweeper', 'ru': 'Сапёр',
  },
  'more.mine.s': {
    'zh-Hans': '微软经典玩法复刻', 'zh-Hant': '微軟經典玩法復刻',
    'en': 'Classic Minesweeper', 'ja': '定番マインスイーパ',
    'ko': '고전 지뢰찾기', 'id': 'Minesweeper klasik', 'ru': 'Классический сапёр',
  },
  'more.debate.t': {
    'zh-Hans': '辩论模式', 'zh-Hant': '辯論模式', 'en': 'Debate', 'ja': 'ディベート',
    'ko': '토론', 'id': 'Debat', 'ru': 'Дебаты',
  },
  'more.debate.s': {
    'zh-Hans': '两个模型正反方对辩', 'zh-Hant': '兩個模型正反方對辯',
    'en': 'Two models debate', 'ja': '2つのモデルが討論',
    'ko': '두 모델의 토론', 'id': 'Dua model berdebat', 'ru': 'Дебаты двух моделей',
  },
  'more.expert.t': {
    'zh-Hans': '多专家团', 'zh-Hant': '多專家團', 'en': 'Expert team',
    'ja': 'エキスパートチーム', 'ko': '전문가 팀', 'id': 'Tim ahli',
    'ru': 'Команда экспертов',
  },
  'more.expert.s': {
    'zh-Hans': '解析·执行·验证协作', 'zh-Hant': '解析·執行·驗證協作',
    'en': 'Analyse · execute · verify', 'ja': '分析・実行・検証',
    'ko': '분석·실행·검증', 'id': 'Analisis · eksekusi · verifikasi',
    'ru': 'Анализ · выполнение · проверка',
  },
  'more.mail.t': {
    'zh-Hans': '邮箱', 'zh-Hant': '信箱', 'en': 'Mail', 'ja': 'メール',
    'ko': '메일', 'id': 'Surel', 'ru': 'Почта',
  },
  'more.mail.s': {
    'zh-Hans': '收发邮件/写信', 'zh-Hant': '收發郵件/寫信', 'en': 'Read and send mail',
    'ja': 'メールの送受信', 'ko': '메일 송수신', 'id': 'Baca dan kirim surel',
    'ru': 'Чтение и отправка почты',
  },

  // ========== Agent 对话面板 ==========
  'agent.greet.t': {
    'zh-Hans': 'Hi! 我是你的 AI 备考助手', 'zh-Hant': 'Hi! 我是你的 AI 備考助手',
    'en': "Hi! I'm your AI study assistant",
    'ja': 'こんにちは！AI 学習アシスタントです',
    'ko': '안녕하세요! AI 학습 도우미입니다',
    'id': 'Hai! Saya asisten belajar AI Anda',
    'ru': 'Привет! Я ваш ИИ-помощник по учёбе',
  },
  'agent.greet.s': {
    'zh-Hans': '已自动关联题目，有问题可以随时问我',
    'zh-Hant': '已自動關聯題目，有問題可以隨時問我',
    'en': 'Questions are linked automatically — ask me anything.',
    'ja': '問題は自動で連携されています。いつでも聞いてください。',
    'ko': '문제가 자동으로 연결되어 있습니다. 언제든 물어보세요.',
    'id': 'Soal sudah tertaut otomatis — tanyakan apa saja.',
    'ru': 'Вопросы подключаются автоматически — спрашивайте.',
  },
  'agent.focus.on': {
    'zh-Hans': '专注全屏', 'zh-Hant': '專注全螢幕', 'en': 'Focus mode',
    'ja': '集中全画面', 'ko': '집중 전체화면', 'id': 'Mode fokus',
    'ru': 'Режим фокуса',
  },
  'agent.focus.off': {
    'zh-Hans': '退出专注全屏', 'zh-Hant': '退出專注全螢幕', 'en': 'Exit focus mode',
    'ja': '集中全画面を終了', 'ko': '집중 전체화면 종료', 'id': 'Keluar mode fokus',
    'ru': 'Выйти из режима фокуса',
  },
  'agent.history': {
    'zh-Hans': '历史对话', 'zh-Hant': '歷史對話', 'en': 'Chat history', 'ja': '履歴',
    'ko': '대화 기록', 'id': 'Riwayat obrolan', 'ru': 'История чата',
  },
  'agent.history.empty': {
    'zh-Hans': '还没有历史对话', 'zh-Hant': '還沒有歷史對話', 'en': 'No chat history yet',
    'ja': '履歴はまだありません', 'ko': '대화 기록이 없습니다',
    'id': 'Belum ada riwayat obrolan', 'ru': 'Истории чата пока нет',
  },
  'agent.clear': {
    'zh-Hans': '清空对话', 'zh-Hant': '清空對話', 'en': 'Clear chat', 'ja': 'チャットを消去',
    'ko': '대화 지우기', 'id': 'Bersihkan obrolan', 'ru': 'Очистить чат',
  },
  'agent.browser.open': {
    'zh-Hans': '打开侧边浏览器', 'zh-Hant': '開啟側邊瀏覽器', 'en': 'Open side browser',
    'ja': 'サイドブラウザを開く', 'ko': '사이드 브라우저 열기',
    'id': 'Buka peramban samping', 'ru': 'Открыть боковой браузер',
  },
  'agent.browser.close': {
    'zh-Hans': '关闭侧边浏览器', 'zh-Hant': '關閉側邊瀏覽器', 'en': 'Close side browser',
    'ja': 'サイドブラウザを閉じる', 'ko': '사이드 브라우저 닫기',
    'id': 'Tutup peramban samping', 'ru': 'Закрыть боковой браузер',
  },
  'agent.perm.t': {
    'zh-Hans': '权限设置', 'zh-Hant': '權限設定', 'en': 'Permissions', 'ja': '権限設定',
    'ko': '권한 설정', 'id': 'Izin', 'ru': 'Разрешения',
  },
  'agent.perm.full': {
    'zh-Hans': '允许完全访问', 'zh-Hant': '允許完全存取', 'en': 'Allow full access',
    'ja': '完全アクセスを許可', 'ko': '전체 접근 허용', 'id': 'Izinkan akses penuh',
    'ru': 'Разрешить полный доступ',
  },
  'agent.perm.desc': {
    'zh-Hans': '当前为默认权限，所有操作都会在安全沙箱约束内进行，超出范围会请求你的允许。',
    'zh-Hant': '目前為預設權限，所有操作都會在安全沙箱限制內進行，超出範圍會請求你的允許。',
    'en': 'Default permissions are active. Everything runs inside the sandbox; '
        'anything beyond it will ask for your approval.',
    'ja': '現在は既定の権限です。すべての操作はサンドボックス内で行われ、'
        '範囲外の操作は許可を求めます。',
    'ko': '현재 기본 권한입니다. 모든 작업은 샌드박스 안에서 실행되며, '
        '범위를 벗어나면 승인을 요청합니다.',
    'id': 'Izin bawaan aktif. Semua tindakan dibatasi sandbox; '
        'di luar itu akan meminta persetujuan Anda.',
    'ru': 'Действуют права по умолчанию. Всё выполняется в песочнице; '
        'выход за её пределы потребует вашего разрешения.',
  },
  'agent.composer.hint': {
    'zh-Hans': '今天帮你做些什么？@ 引用文件',
    'zh-Hant': '今天幫你做些什麼？@ 引用檔案',
    'en': 'What can I do for you today?  @ to reference a file',
    'ja': '今日は何をお手伝いしましょう？@ でファイルを参照',
    'ko': '오늘 무엇을 도와드릴까요? @ 로 파일 참조',
    'id': 'Ada yang bisa saya bantu hari ini?  @ untuk merujuk berkas',
    'ru': 'Чем помочь сегодня?  @ — сослаться на файл',
  },
  'agent.composer.fullAccess': {
    'zh-Hans': '完全访问', 'zh-Hant': '完全存取', 'en': 'Full access',
    'ja': '完全アクセス', 'ko': '전체 접근', 'id': 'Akses penuh',
    'ru': 'Полный доступ',
  },
  'agent.composer.defaultPerm': {
    'zh-Hans': '默认权限', 'zh-Hant': '預設權限', 'en': 'Default permissions',
    'ja': '既定の権限', 'ko': '기본 권한', 'id': 'Izin bawaan',
    'ru': 'Права по умолчанию',
  },
  'agent.composer.tools': {
    'zh-Hans': '工具', 'zh-Hant': '工具', 'en': 'Tools', 'ja': 'ツール',
    'ko': '도구', 'id': 'Alat', 'ru': 'Инструменты',
  },
  'agent.model.independent': {
    'zh-Hans': '·独立', 'zh-Hant': '·獨立', 'en': ' · Standalone',
    'ja': ' · 独立', 'ko': ' · 독립', 'id': ' · Mandiri', 'ru': ' · Отдельно',
  },

  // ========== 语言名（用母语书写）==========
  'lang.zhHans': {
    'zh-Hans': '简体中文', 'zh-Hant': '簡體中文', 'en': 'Simplified Chinese',
    'ja': '簡体字中国語', 'ko': '중국어 간체', 'id': 'Tionghoa Sederhana',
    'ru': 'Китайский (упрощённый)',
  },
  'lang.zhHant': {
    'zh-Hans': '繁体中文', 'zh-Hant': '繁體中文', 'en': 'Traditional Chinese',
    'ja': '繁体字中国語', 'ko': '중국어 번체', 'id': 'Tionghoa Tradisional',
    'ru': 'Китайский (традиционный)',
  },
  'lang.en': {
    'zh-Hans': '英语', 'zh-Hant': '英語', 'en': 'English', 'ja': '英語',
    'ko': '영어', 'id': 'Inggris', 'ru': 'Английский',
  },
  'lang.ja': {
    'zh-Hans': '日语', 'zh-Hant': '日語', 'en': 'Japanese', 'ja': '日本語',
    'ko': '일본어', 'id': 'Jepang', 'ru': 'Японский',
  },
  'lang.ko': {
    'zh-Hans': '韩语', 'zh-Hant': '韓語', 'en': 'Korean', 'ja': '韓国語',
    'ko': '한국어', 'id': 'Korea', 'ru': 'Корейский',
  },
  'lang.id': {
    'zh-Hans': '印尼语', 'zh-Hant': '印尼語', 'en': 'Indonesian',
    'ja': 'インドネシア語', 'ko': '인도네시아어', 'id': 'Indonesia',
    'ru': 'Индонезийский',
  },
  'lang.ru': {
    'zh-Hans': '俄语', 'zh-Hant': '俄語', 'en': 'Russian', 'ja': 'ロシア語',
    'ko': '러시아어', 'id': 'Rusia', 'ru': 'Русский',
  },

  // ========== set_language 工具回执 ==========
  'tool.lang.ok': {
    'zh-Hans': '界面语言已切换为 {lang}',
    'zh-Hant': '介面語言已切換為 {lang}',
    'en': 'UI language switched to {lang}',
    'ja': '表示言語を {lang} に切り替えました',
    'ko': '인터페이스 언어를 {lang}(으)로 전환했습니다',
    'id': 'Bahasa antarmuka diubah ke {lang}',
    'ru': 'Язык интерфейса переключён на {lang}',
  },
  'tool.lang.bad': {
    'zh-Hans': '不支持的语言「{lang}」。可选：zh-Hans / zh-Hant / en / ja / ko / id / ru',
    'zh-Hant': '不支援的語言「{lang}」。可選：zh-Hans / zh-Hant / en / ja / ko / id / ru',
    'en': 'Unsupported language "{lang}". Supported: zh-Hans / zh-Hant / en / ja / ko / id / ru',
    'ja': '未対応の言語「{lang}」です。対応：zh-Hans / zh-Hant / en / ja / ko / id / ru',
    'ko': '지원하지 않는 언어 "{lang}"입니다. 지원: zh-Hans / zh-Hant / en / ja / ko / id / ru',
    'id': 'Bahasa "{lang}" tidak didukung. Didukung: zh-Hans / zh-Hant / en / ja / ko / id / ru',
    'ru': 'Язык «{lang}» не поддерживается. Доступно: zh-Hans / zh-Hant / en / ja / ko / id / ru',
  },
  'tool.lang.unsupported': {
    'zh-Hans': '暂不支持的语言，已回落到简体中文：{lang}',
    'zh-Hant': '暫不支援的語言，已回落到簡體中文：{lang}',
    'en': 'Unsupported language, fell back to Simplified Chinese: {lang}',
    'ja': '未対応の言語のため簡体字中国語に戻しました：{lang}',
    'ko': '지원하지 않는 언어라 중국어 간체로 되돌렸습니다: {lang}',
    'id': 'Bahasa tidak didukung, kembali ke Tionghoa Sederhana: {lang}',
    'ru': 'Язык не поддерживается, возврат к китайскому (упрощённому): {lang}',
  },
};

/// 便捷取词。页面里直接 `tr('nav.study')`，不必写 `I18n.tr(...)`。
String tr(String key, [Map<String, String>? args]) => I18n.tr(key, args);

/// 当前语言与查询入口
class I18n {  I18n._();

  /// 语言变化通知：根节点监听它整体重建
  static final ValueNotifier<AppLang> lang = ValueNotifier(AppLang.zhHans);

  static AppLang get current => lang.value;

  /// 取文案。缺 key 时回落 zh-Hans，再回落 key 本身（便于发现漏配）。
  /// [args] 支持 `{name}` 占位替换。
  static String tr(String key, [Map<String, String>? args]) {
    final row = _kTable[key];
    var s = row == null
        ? key
        : (row[lang.value.code] ?? row['zh-Hans'] ?? key);
    if (args != null && args.isNotEmpty) {
      for (final e in args.entries) {
        s = s.replaceAll('{${e.key}}', e.value);
      }
    }
    return s;
  }

  /// 语言自称（母语书写），如 日本語 / Русский
  static String nativeName(AppLang l) => switch (l) {
        AppLang.zhHans => '简体中文',
        AppLang.zhHant => '繁體中文',
        AppLang.en => 'English',
        AppLang.ja => '日本語',
        AppLang.ko => '한국어',
        AppLang.id => 'Bahasa Indonesia',
        AppLang.ru => 'Русский',
      };

  /// 该语言在当前界面语言下的称呼（如当前是日文界面，简体中文显示为「簡体字中国語」）
  static String displayName(AppLang l) => tr(switch (l) {
        AppLang.zhHans => 'lang.zhHans',
        AppLang.zhHant => 'lang.zhHant',
        AppLang.en => 'lang.en',
        AppLang.ja => 'lang.ja',
        AppLang.ko => 'lang.ko',
        AppLang.id => 'lang.id',
        AppLang.ru => 'lang.ru',
      });

  /// 启动时载入（AppState 初始化里调用）
  static void load() {
    final saved = AppLangMeta.fromCode(Storage.loadLanguage());
    if (saved != null) lang.value = saved;
  }

  /// 切换语言（agent 的 set_language 工具与设置页共用）
  static Future<void> set(AppLang l) async {
    if (lang.value == l) return;
    lang.value = l;
    Storage.saveLanguage(l.code);
  }
}
