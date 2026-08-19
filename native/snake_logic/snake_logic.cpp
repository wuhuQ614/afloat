// ============================================================
// 贪吃蛇游戏逻辑实现（C++，纯逻辑，无渲染）
// 含：方向队列缓冲、碰撞检测、食物生成、得分、变速
// ============================================================
#include "snake_logic.h"

#include <algorithm>
#include <cstdint>
#include <cstdlib>
#include <cstring>
#include <vector>

namespace {

struct Vec {
  int x, y;
};

struct SnakeStateImpl {
  std::vector<Vec> snake;
  Vec food{8, 8};
  Vec dir{1, 0};
  std::vector<Vec> dirQueue;
  bool playing = false;
  bool paused = false;
  bool over = false;
  int score = 0;
  int highScore = 0;
  double tickMs = 180.0;
  double logicElapsed = 0.0;
  double moveProgress = 1.0;
  uint32_t rngState = 12345;

  // 供渲染插值的坐标数组（头在 index 0，长度 = snakeLen）
  int curX[SNAKE_MAX_LEN];
  int curY[SNAKE_MAX_LEN];
  int prevX[SNAKE_MAX_LEN];
  int prevY[SNAKE_MAX_LEN];
  int snakeLen = 0;

  void syncRenderArrays() {
    snakeLen = (int)snake.size();
    for (int i = 0; i < snakeLen; i++) {
      curX[i] = snake[i].x;
      curY[i] = snake[i].y;
    }
  }

  void syncPrevArrays(const std::vector<Vec>& prev) {
    size_t n = prev.size();
    for (size_t i = 0; i < n; i++) {
      prevX[i] = prev[i].x;
      prevY[i] = prev[i].y;
    }
    if (n < (size_t)snakeLen) {
      // 蛇变长时新段无 prev，用 cur 兜底（不移动）
      for (size_t i = n; i < (size_t)snakeLen; i++) {
        prevX[i] = curX[i];
        prevY[i] = curY[i];
      }
    }
  }

  uint32_t rngNext() {
    rngState ^= rngState << 13;
    rngState ^= rngState >> 17;
    rngState ^= rngState << 5;
    return rngState;
  }

  Vec randomFreeCell() {
    std::vector<Vec> free;
    for (int x = 0; x < SNAKE_COLS; x++)
      for (int y = 0; y < SNAKE_ROWS; y++) {
        bool occ = false;
        for (auto& s : snake)
          if (s.x == x && s.y == y) { occ = true; break; }
        if (!occ) free.push_back({x, y});
      }
    if (free.empty()) return {0, 0};
    return free[rngNext() % free.size()];
  }

  void reset() {
    snake.clear();
    snake.push_back({10, 10});
    snake.push_back({9, 10});
    snake.push_back({8, 10});
    dir = {1, 0};
    dirQueue.clear();
    score = 0;
    tickMs = 180.0;
    food = randomFreeCell();
    over = false;
    paused = false;
    moveProgress = 1.0;
    logicElapsed = 0.0;
    syncRenderArrays();
    syncPrevArrays(snake);  // prev = cur（首帧不移动）
  }

  void gameOver() {
    playing = false;
    over = true;
    if (score > highScore) highScore = score;
  }

  void step() {
    std::vector<Vec> prev = snake;
    if (!dirQueue.empty()) {
      dir = dirQueue.front();
      dirQueue.erase(dirQueue.begin());
    }
    Vec head = {snake[0].x + dir.x, snake[0].y + dir.y};
    if (head.x < 0 || head.x >= SNAKE_COLS || head.y < 0 || head.y >= SNAKE_ROWS) {
      gameOver();
      return;
    }
    bool willMove = !(head.x == snake.back().x && head.y == snake.back().y);
    if (willMove) {
      for (size_t i = 0; i + 1 < snake.size(); i++)
        if (snake[i].x == head.x && snake[i].y == head.y) {
          gameOver();
          return;
        }
    }
    snake.insert(snake.begin(), head);
    if (head.x == food.x && head.y == food.y) {
      score += 10;
      if (score % 50 == 0 && tickMs > 90.0) {
        tickMs = std::max(90.0, 180.0 - (score / 10) * 6.0);
      }
      food = randomFreeCell();
    } else {
      snake.pop_back();
    }
    syncRenderArrays();
    syncPrevArrays(prev);
  }

  void advance(double dtMs) {
    if (!playing || paused || over) return;
    logicElapsed += dtMs;
    while (logicElapsed >= tickMs) {
      logicElapsed -= tickMs;
      step();
      if (over) break;
    }
    moveProgress = std::min(1.0, logicElapsed / tickMs);
  }
};

}  // namespace

extern "C" {

SnakeState* snake_create(int high_score) {
  auto* s = new SnakeStateImpl();
  s->highScore = high_score;
  s->reset();
  return reinterpret_cast<SnakeState*>(s);
}

void snake_destroy(SnakeState* s) {
  delete reinterpret_cast<SnakeStateImpl*>(s);
}

void snake_start(SnakeState* s) {
  auto* impl = reinterpret_cast<SnakeStateImpl*>(s);
  impl->reset();
  impl->playing = true;
}

void snake_toggle_pause(SnakeState* s) {
  auto* impl = reinterpret_cast<SnakeStateImpl*>(s);
  if (!impl->playing || impl->over) return;
  impl->paused = !impl->paused;
}

void snake_turn(SnakeState* s, int dx, int dy) {
  auto* impl = reinterpret_cast<SnakeStateImpl*>(s);
  if (!impl->playing || impl->paused || impl->over) return;
  if (impl->dirQueue.size() >= 2) return;
  Vec last = impl->dirQueue.empty() ? impl->dir : impl->dirQueue.back();
  if (dx == -last.x && dy == -last.y) return;
  if (dx == last.x && dy == last.y) return;
  impl->dirQueue.push_back({dx, dy});
}

void snake_advance(SnakeState* s, double dt_ms) {
  reinterpret_cast<SnakeStateImpl*>(s)->advance(dt_ms);
}

void snake_snapshot(SnakeState* s, SnakeSnapshot* out) {
  auto* impl = reinterpret_cast<SnakeStateImpl*>(s);
  out->score = impl->score;
  out->high_score = impl->highScore;
  out->playing = impl->playing ? 1 : 0;
  out->paused = impl->paused ? 1 : 0;
  out->over = impl->over ? 1 : 0;
  out->snake_len = impl->snakeLen;
  out->dir_x = impl->dir.x;
  out->dir_y = impl->dir.y;
  out->food_x = impl->food.x;
  out->food_y = impl->food.y;
  out->move_progress = (float)impl->moveProgress;
  out->tick_ms = impl->tickMs;
}

const int* snake_snake_cur_x(SnakeState* s) {
  return reinterpret_cast<SnakeStateImpl*>(s)->curX;
}

const int* snake_snake_cur_y(SnakeState* s) {
  return reinterpret_cast<SnakeStateImpl*>(s)->curY;
}

const int* snake_snake_prev_x(SnakeState* s) {
  return reinterpret_cast<SnakeStateImpl*>(s)->prevX;
}

const int* snake_snake_prev_y(SnakeState* s) {
  return reinterpret_cast<SnakeStateImpl*>(s)->prevY;
}

void snake_set_high_score(SnakeState* s, int hs) {
  reinterpret_cast<SnakeStateImpl*>(s)->highScore = hs;
}

}  // extern "C"
