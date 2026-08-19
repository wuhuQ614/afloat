// ============================================================
// 贪吃蛇游戏逻辑 —— 纯 C 接口（跨平台：Android .so / Windows .dll）
// 由 dart:ffi 调用。本库只负责逻辑，不包含任何渲染/UI 代码。
// ============================================================
#ifndef SNAKE_LOGIC_H
#define SNAKE_LOGIC_H

#ifdef __cplusplus
extern "C" {
#endif

// Windows DLL 需显式导出符号，Dart FFI 才能 lookupFunction 找到
#ifdef _WIN32
#define SNAKE_API __declspec(dllexport)
#else
#define SNAKE_API
#endif

#define SNAKE_COLS 20
#define SNAKE_ROWS 20
#define SNAKE_MAX_LEN (SNAKE_COLS * SNAKE_ROWS)

typedef struct SnakeState SnakeState;

// 状态快照（字段顺序与 Dart 侧 FFI 结构体保持一致）
typedef struct SnakeSnapshot {
  int score;
  int high_score;
  int playing;
  int paused;
  int over;
  int snake_len;
  int dir_x;
  int dir_y;
  int food_x;
  int food_y;
  float move_progress;
  double tick_ms;
} SnakeSnapshot;

// 创建/销毁
SNAKE_API SnakeState* snake_create(int high_score);
SNAKE_API void snake_destroy(SnakeState* s);

// 重新开始（重置并进入进行中）
SNAKE_API void snake_start(SnakeState* s);

// 暂停/继续
SNAKE_API void snake_toggle_pause(SnakeState* s);

// 转向（内部做反向检测与 2 步方向队列缓冲）
SNAKE_API void snake_turn(SnakeState* s, int dx, int dy);

// 前进逻辑时间（毫秒）。内部累积步进、处理碰撞/得分/速度。
// 同时更新 move_progress 供插值渲染。
SNAKE_API void snake_advance(SnakeState* s, double dt_ms);

// 填充状态快照
SNAKE_API void snake_snapshot(SnakeState* s, SnakeSnapshot* out);

// 返回内部蛇坐标数组指针（长度为 snake_len；头在 index 0）。
// 提供当前格坐标与上一逻辑步坐标，供 Dart 做平滑插值。
SNAKE_API const int* snake_snake_cur_x(SnakeState* s);
SNAKE_API const int* snake_snake_cur_y(SnakeState* s);
SNAKE_API const int* snake_snake_prev_x(SnakeState* s);
SNAKE_API const int* snake_snake_prev_y(SnakeState* s);

// 回写最高分（Dart 持久化后调用）
SNAKE_API void snake_set_high_score(SnakeState* s, int hs);

#ifdef __cplusplus
}
#endif

#endif  // SNAKE_LOGIC_H
