// ============================================================
// 扫雷游戏逻辑实现 —— 详见 minesweeper_logic.h
// ============================================================
#include "minesweeper_logic.h"

#include <algorithm>
#include <random>
#include <vector>

struct MSGame {
    int rows;
    int cols;
    int mines;
    int seconds;
    int revealedCount;
    int boom;            // 踩中的雷索引，-1 无
    bool started;        // 首次点击后为 true（布雷完成）
    bool over;
    bool won;
    std::vector<int> mine;   // 0/1
    std::vector<int> adj;    // 周围雷数
    std::vector<int> state;  // 0 hidden 1 revealed 2 flagged 3 question

    MSGame(int r, int c, int m)
        : rows(r), cols(c), mines(m), seconds(0), revealedCount(0),
          boom(-1), started(false), over(false), won(false),
          mine(static_cast<size_t>(r) * c, 0),
          adj(static_cast<size_t>(r) * c, 0),
          state(static_cast<size_t>(r) * c, 0) {}

    int total() const { return rows * cols; }
    bool inBoard(int r, int c) const { return r >= 0 && r < rows && c >= 0 && c < cols; }

    // 收集 8 邻域索引
    void neighbors(int idx, std::vector<int>& out) const {
        out.clear();
        const int r = idx / cols;
        const int c = idx % cols;
        for (int dr = -1; dr <= 1; dr++) {
            for (int dc = -1; dc <= 1; dc++) {
                if (dr == 0 && dc == 0) continue;
                const int nr = r + dr;
                const int nc = c + dc;
                if (inBoard(nr, nc)) out.push_back(nr * cols + nc);
            }
        }
    }
};

static void msComputeAdj(MSGame* g) {
    std::vector<int> ns;
    for (int i = 0; i < g->total(); i++) {
        g->neighbors(i, ns);
        int count = 0;
        for (int n : ns) {
            if (g->mine[static_cast<size_t>(n)] != 0) count++;
        }
        g->adj[static_cast<size_t>(i)] = count;
    }
}

static void msPlaceMines(MSGame* g, int safeIdx) {
    // 首击格及其 8 邻域不布雷（保证首击展开空白区）
    std::vector<int> safe;
    g->neighbors(safeIdx, safe);
    safe.push_back(safeIdx);

    std::vector<int> candidates;
    candidates.reserve(static_cast<size_t>(g->total()));
    for (int i = 0; i < g->total(); i++) {
        if (std::find(safe.begin(), safe.end(), i) == safe.end()) {
            candidates.push_back(i);
        }
    }
    if (static_cast<int>(candidates.size()) < g->mines) {
        // 极端情况（雷数过多）：回退为仅排除首击格
        candidates.clear();
        for (int i = 0; i < g->total(); i++) {
            if (i != safeIdx) candidates.push_back(i);
        }
    }

    std::random_device rd;
    std::mt19937 gen(rd());
    std::shuffle(candidates.begin(), candidates.end(), gen);

    const int limit = std::min(g->mines, static_cast<int>(candidates.size()));
    for (int k = 0; k < limit; k++) {
        g->mine[static_cast<size_t>(candidates[static_cast<size_t>(k)])] = 1;
    }
    msComputeAdj(g);
}

static void msFloodReveal(MSGame* g, int start) {
    std::vector<int> stack;
    stack.push_back(start);
    std::vector<char> seen(static_cast<size_t>(g->total()), 0);
    while (!stack.empty()) {
        const int i = stack.back();
        stack.pop_back();
        if (seen[static_cast<size_t>(i)] != 0) continue;
        seen[static_cast<size_t>(i)] = 1;
        // 仅展开未标记的格子：旗与问号格保留（与 Windows 一致）
        const int st = g->state[static_cast<size_t>(i)];
        if (st == 1 || st == 2 || st == 3) continue;
        g->state[static_cast<size_t>(i)] = 1;
        g->revealedCount++;
        if (g->adj[static_cast<size_t>(i)] == 0) {
            std::vector<int> ns;
            g->neighbors(i, ns);
            for (int n : ns) {
                if (g->state[static_cast<size_t>(n)] == 0 &&
                    g->mine[static_cast<size_t>(n)] == 0) {
                    stack.push_back(n);
                }
            }
        }
    }
}

static void msCheckWin(MSGame* g) {
    if (g->revealedCount != g->total() - g->mines) return;
    g->over = true;
    g->won = true;
    // 胜利：剩余雷自动插旗
    for (size_t i = 0; i < g->mine.size(); i++) {
        if (g->mine[i] != 0 && g->state[i] != 1) g->state[i] = 2;
    }
}

extern "C" {

MS_API MSGame* ms_create(int rows, int cols, int mines) {
    return new MSGame(rows, cols, mines);
}

MS_API void ms_destroy(MSGame* g) {
    delete g;
}

MS_API void ms_reset(MSGame* g) {
    const size_t n = static_cast<size_t>(g->total());
    g->seconds = 0;
    g->revealedCount = 0;
    g->boom = -1;
    g->started = false;
    g->over = false;
    g->won = false;
    std::fill(g->mine.begin(), g->mine.end(), 0);
    std::fill(g->adj.begin(), g->adj.end(), 0);
    std::fill(g->state.begin(), g->state.end(), 0);
    (void)n;
}

MS_API void ms_resize(MSGame* g, int rows, int cols, int mines) {
    g->rows = rows;
    g->cols = cols;
    g->mines = mines;
    ms_reset(g);
    g->mine.assign(static_cast<size_t>(rows) * cols, 0);
    g->adj.assign(static_cast<size_t>(rows) * cols, 0);
    g->state.assign(static_cast<size_t>(rows) * cols, 0);
}

MS_API void ms_reveal(MSGame* g, int idx) {
    if (g->over) return;
    if (idx < 0 || idx >= g->total()) return;
    const int st = g->state[static_cast<size_t>(idx)];
    if (st == 1 || st == 2) return; // 已翻开或已插旗：无效
    if (!g->started) {
        msPlaceMines(g, idx);
        g->started = true;
    }
    if (g->mine[static_cast<size_t>(idx)] != 0) {
        g->boom = idx;
        g->over = true;
        g->won = false;
        return;
    }
    msFloodReveal(g, idx);
    msCheckWin(g);
}

MS_API void ms_toggle_mark(MSGame* g, int idx) {
    if (g->over) return;
    if (idx < 0 || idx >= g->total()) return;
    int& st = g->state[static_cast<size_t>(idx)];
    if (st == 1) return; // 已翻开：无效
    if (st == 0) st = 2;
    else if (st == 2) st = 3; // 问号
    else st = 0;
}

MS_API void ms_chord(MSGame* g, int idx) {
    if (g->over) return;
    if (idx < 0 || idx >= g->total()) return;
    if (g->state[static_cast<size_t>(idx)] != 1) return;
    if (g->adj[static_cast<size_t>(idx)] == 0) return;
    std::vector<int> ns;
    g->neighbors(idx, ns);
    int flags = 0;
    for (int n : ns) {
        if (g->state[static_cast<size_t>(n)] == 2) flags++;
    }
    if (flags != g->adj[static_cast<size_t>(idx)]) return;
    for (int n : ns) {
        const int st = g->state[static_cast<size_t>(n)];
        if (st == 0 || st == 3) {
            ms_reveal(g, n);
            if (g->over) return;
        }
    }
}

MS_API void ms_tick(MSGame* g) {
    if (g->started && !g->over && g->seconds < 999) g->seconds++;
}

MS_API int ms_rows(MSGame* g) { return g->rows; }
MS_API int ms_cols(MSGame* g) { return g->cols; }
MS_API int ms_mines(MSGame* g) { return g->mines; }
MS_API int ms_seconds(MSGame* g) { return g->seconds; }

MS_API int ms_remain(MSGame* g) {
    int flags = 0;
    for (int st : g->state) {
        if (st == 2) flags++;
    }
    return g->mines - flags;
}

MS_API int ms_over(MSGame* g) { return g->over ? 1 : 0; }
MS_API int ms_won(MSGame* g) { return g->won ? 1 : 0; }
MS_API int ms_started(MSGame* g) { return g->started ? 1 : 0; }
MS_API int ms_boom(MSGame* g) { return g->boom; }

MS_API void ms_copy_state(MSGame* g, int* out) {
    for (size_t i = 0; i < g->state.size(); i++) out[i] = g->state[i];
}

MS_API void ms_copy_adj(MSGame* g, int* out) {
    for (size_t i = 0; i < g->adj.size(); i++) out[i] = g->adj[i];
}

MS_API void ms_copy_mine(MSGame* g, int* out) {
    for (size_t i = 0; i < g->mine.size(); i++) out[i] = g->mine[i];
}

} // extern "C"
