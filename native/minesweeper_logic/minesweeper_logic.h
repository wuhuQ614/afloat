// ============================================================
// 扫雷游戏逻辑 —— 纯 C 接口（跨平台：Windows .dll / Android .so）
// 由 dart:ffi 调用。本库只负责逻辑（布雷/翻开/标记/和弦/胜负/计时），
// 不包含任何渲染/UI 代码。规则与微软经典扫雷一致：
//   - 首次点击永不踩雷（首击格及其 8 邻域不布雷，保证开局展开空白）
//   - 左键翻开；右键 旗→问号→空 循环（问号可关闭）
//   - 空白格自动展开（flood fill，旗/问号格不会被展开）
//   - 和弦：数字格周围旗数 == 数字时展开其余未标记邻格
//   - 踩雷：记录爆炸格，游戏结束；胜利：剩余雷自动插旗
// ============================================================
#ifndef MINESWEEPER_LOGIC_H
#define MINESWEEPER_LOGIC_H

#ifdef __cplusplus
extern "C" {
#endif

// Windows DLL 需显式导出符号，Dart FFI 才能 lookupFunction 找到
#ifdef _WIN32
#define MS_API __declspec(dllexport)
#else
#define MS_API
#endif

typedef struct MSGame MSGame;

MS_API MSGame* ms_create(int rows, int cols, int mines);
MS_API void ms_destroy(MSGame* g);

// 重置为同尺寸新局
MS_API void ms_reset(MSGame* g);
// 改尺寸并重开
MS_API void ms_resize(MSGame* g, int rows, int cols, int mines);

// 交互
MS_API void ms_reveal(MSGame* g, int idx);       // 左键翻开
MS_API void ms_toggle_mark(MSGame* g, int idx);  // 右键 旗→问号→空
MS_API void ms_chord(MSGame* g, int idx);        // 和弦
MS_API void ms_tick(MSGame* g);                  // 计时 +1s（Dart 每秒调）

// 状态查询
MS_API int ms_rows(MSGame* g);
MS_API int ms_cols(MSGame* g);
MS_API int ms_mines(MSGame* g);
MS_API int ms_seconds(MSGame* g);
MS_API int ms_remain(MSGame* g);   // 剩余雷数 = 雷数 - 已插旗数（可为负）
MS_API int ms_over(MSGame* g);
MS_API int ms_won(MSGame* g);
MS_API int ms_started(MSGame* g);
MS_API int ms_boom(MSGame* g);     // 踩中的雷索引，-1 表示无

// 批量拷贝（out 需由调用方分配 rows*cols 个 int）
// state: 0=hidden 1=revealed 2=flagged 3=question
MS_API void ms_copy_state(MSGame* g, int* out);
MS_API void ms_copy_adj(MSGame* g, int* out);
MS_API void ms_copy_mine(MSGame* g, int* out);

#ifdef __cplusplus
}
#endif

#endif // MINESWEEPER_LOGIC_H
