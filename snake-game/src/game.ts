/**
 * Snake Game - TypeScript
 * 一个基于 Canvas 的经典贪吃蛇游戏
 *
 * 功能：
 *  - 键盘方向控制（方向键 / WASD）
 *  - 蛇吃食物增长、计分
 *  - 最高分本地持久化（localStorage）
 *  - 暂停 / 继续 / 重新开始
 *  - 三档速度可选
 */

// ---------- 类型定义 ----------

/** 方向枚举 */
enum Direction {
  Up = 'Up',
  Down = 'Down',
  Left = 'Left',
  Right = 'Right',
}

/** 一个网格坐标点 */
interface Point {
  x: number;
  y: number;
}

/** 游戏状态 */
type GameState = 'idle' | 'running' | 'paused' | 'over';

/** 速度档位 */
type SpeedLevel = 'slow' | 'normal' | 'fast';

// ---------- 常量 ----------

const GRID_SIZE = 20; // 网格行列数
const CELL_SIZE = 24; // 每个格子像素大小
const DEFAULT_SPEED_MS = 150; // 普通档每步毫秒数
const SPEED_CONFIG: Record<SpeedLevel, number> = {
  slow: 220,
  normal: 150,
  fast: 90,
};

const HIGH_SCORE_KEY = 'snake-game-high-score';

/** 与按键对应的方向 */
const KEY_TO_DIRECTION: Record<string, Direction> = {
  ArrowUp: Direction.Up,
  ArrowDown: Direction.Down,
  ArrowLeft: Direction.Left,
  ArrowRight: Direction.Right,
  w: Direction.Up,
  s: Direction.Down,
  a: Direction.Left,
  d: Direction.Right,
  W: Direction.Up,
  S: Direction.Down,
  A: Direction.Left,
  D: Direction.Right,
};

/** 相反方向映射，用于禁止蛇原地掉头 */
const OPPOSITE: Record<Direction, Direction> = {
  [Direction.Up]: Direction.Down,
  [Direction.Down]: Direction.Up,
  [Direction.Left]: Direction.Right,
  [Direction.Right]: Direction.Left,
};

// ---------- 工具函数 ----------

/** 两个点是否相等 */
function isSamePoint(a: Point, b: Point): boolean {
  return a.x === b.x && a.y === b.y;
}

/** 生成 [min, max) 区间内的随机整数 */
function randomInt(min: number, max: number): number {
  return Math.floor(Math.random() * (max - min)) + min;
}

// ---------- 游戏主类 ----------

class SnakeGame {
  private canvas: HTMLCanvasElement;
  private ctx: CanvasRenderingContext2D;

  private snake: Point[] = [];
  private food: Point | null = null;
  private direction: Direction = Direction.Right;
  private nextDirection: Direction = Direction.Right;

  private state: GameState = 'idle';
  private speedLevel: SpeedLevel = 'normal';
  private speedMs = DEFAULT_SPEED_MS;

  private score = 0;
  private highScore = 0;

  private timer: number | null = null;

  // DOM 引用
  private scoreEl: HTMLElement;
  private highScoreEl: HTMLElement;
  private statusEl: HTMLElement;
  private startBtn: HTMLButtonElement;
  private pauseBtn: HTMLButtonElement;
  private speedSelect: HTMLSelectElement;

  constructor() {
    const canvas = document.getElementById('game-canvas');
    if (!(canvas instanceof HTMLCanvasElement)) {
      throw new Error('未找到 #game-canvas 画布元素');
    }
    this.canvas = canvas;

    const ctx = this.canvas.getContext('2d');
    if (!ctx) {
      throw new Error('无法获取 2D 绘图上下文');
    }
    this.ctx = ctx;

    // 设置画布尺寸 = 网格数 x 格子大小
    this.canvas.width = GRID_SIZE * CELL_SIZE;
    this.canvas.height = GRID_SIZE * CELL_SIZE;

    this.scoreEl = this.mustGet<HTMLElement>('score');
    this.highScoreEl = this.mustGet<HTMLElement>('high-score');
    this.statusEl = this.mustGet<HTMLElement>('status');
    this.startBtn = this.mustGet<HTMLButtonElement>('btn-start');
    this.pauseBtn = this.mustGet<HTMLButtonElement>('btn-pause');
    this.speedSelect = this.mustGet<HTMLSelectElement>('speed-select');

    this.highScore = Number(localStorage.getItem(HIGH_SCORE_KEY) ?? 0);
    this.highScoreEl.textContent = String(this.highScore);

    this.bindEvents();
    this.resetGame();
  }

  /** 便捷获取 DOM 元素并做类型断言 */
  private mustGet<T extends HTMLElement>(id: string): T {
    const el = document.getElementById(id);
    if (!el) {
      throw new Error(`未找到 #${id} 元素`);
    }
    return el as T;
  }

  /** 绑定键盘与按钮事件 */
  private bindEvents(): void {
    window.addEventListener('keydown', (e: KeyboardEvent) => {
      const dir = KEY_TO_DIRECTION[e.key];
      if (dir) {
        // 不允许原地掉头
        if (dir !== OPPOSITE[this.direction]) {
          this.nextDirection = dir;
        }
        // 阻止方向键滚动页面
        e.preventDefault();
      }

      // 空格：暂停 / 继续
      if (e.key === ' ') {
        e.preventDefault();
        this.togglePause();
      }

      // 回车：开始 / 重新开始
      if (e.key === 'Enter') {
        e.preventDefault();
        this.start();
      }
    });

    this.startBtn.addEventListener('click', () => this.start());
    this.pauseBtn.addEventListener('click', () => this.togglePause());

    this.speedSelect.addEventListener('change', () => {
      const value = this.speedSelect.value as SpeedLevel;
      if (value in SPEED_CONFIG) {
        this.speedLevel = value;
        this.speedMs = SPEED_CONFIG[value];
        // 若正在运行则立即应用新速度
        if (this.state === 'running') {
          this.scheduleNextStep();
        }
      }
    });
  }

  /** 初始化 / 重置游戏数据 */
  private resetGame(): void {
    const mid = Math.floor(GRID_SIZE / 2);
    this.snake = [
      { x: mid, y: mid },
      { x: mid - 1, y: mid },
      { x: mid - 2, y: mid },
    ];
    this.direction = Direction.Right;
    this.nextDirection = Direction.Right;
    this.score = 0;
    this.food = this.spawnFood();
    this.scoreEl.textContent = '0';
    this.setState('idle');
  }

  /** 设置游戏状态并同步界面 */
  private setState(state: GameState): void {
    this.state = state;
    this.statusEl.textContent = this.statusText(state);

    // 按钮可用性
    this.pauseBtn.disabled = state !== 'running';
    this.startBtn.textContent = state === 'running' || state === 'paused' ? '重新开始' : '开始游戏';
    this.render();
  }

  /** 状态对应的提示文案 */
  private statusText(state: GameState): string {
    switch (state) {
      case 'idle':
        return '按 方向键/WASD 移动，吃到食物得 10 分';
      case 'running':
        return '游戏中…（空格暂停）';
      case 'paused':
        return '已暂停（空格继续）';
      case 'over':
        return '游戏结束，按回车重新开始';
    }
  }

  /** 开始（含重新开始） */
  public start(): void {
    if (this.state === 'over') {
      this.resetGame();
    }
    if (this.state !== 'idle' && this.state !== 'paused') {
      return;
    }
    if (this.state === 'paused') {
      // 从暂停恢复
      this.setState('running');
      this.scheduleNextStep();
      return;
    }
    this.setState('running');
    this.scheduleNextStep();
  }

  /** 暂停 / 恢复 */
  private togglePause(): void {
    if (this.state === 'running') {
      this.clearTimer();
      this.setState('paused');
    } else if (this.state === 'paused') {
      this.setState('running');
      this.scheduleNextStep();
    }
  }

  /** 清除定时器 */
  private clearTimer(): void {
    if (this.timer !== null) {
      window.clearTimeout(this.timer);
      this.timer = null;
    }
  }

  /** 以当前速度安排下一步 */
  private scheduleNextStep(): void {
    this.clearTimer();
    this.timer = window.setTimeout(() => {
      this.step();
    }, this.speedMs);
  }

  /** 推进一帧游戏逻辑 */
  private step(): void {
    if (this.state !== 'running') {
      return;
    }

    // 应用下一次方向
    this.direction = this.nextDirection;

    const head = this.snake[0];
    const offset = this.offsetOf(this.direction);
    const newHead: Point = { x: head.x + offset.x, y: head.y + offset.y };

    // 碰撞检测：撞墙
    if (
      newHead.x < 0 ||
      newHead.x >= GRID_SIZE ||
      newHead.y < 0 ||
      newHead.y >= GRID_SIZE
    ) {
      this.gameOver('撞到墙了！');
      return;
    }

    // 碰撞检测：撞到自己（注意尾巴即将移动，通常不计入，这里简化：撞到除尾巴外的身体都算）
    const bodyToCheck = this.snake.slice(0, this.foodEaten() ? this.snake.length : this.snake.length - 1);
    if (bodyToCheck.some((seg) => isSamePoint(seg, newHead))) {
      this.gameOver('撞到自己了！');
      return;
    }

    // 蛇前进
    this.snake.unshift(newHead);

    // 判断是否吃到食物
    if (this.food && isSamePoint(newHead, this.food)) {
      this.score += 10;
      this.scoreEl.textContent = String(this.score);
      this.food = this.spawnFood();
      // 吃到了，不删除尾巴 → 身体变长
    } else {
      this.snake.pop();
    }

    this.render();
    this.scheduleNextStep();
  }

  /** 判断本帧是否吃到食物（用于碰撞检测时判断尾巴是否移动） */
  private foodEaten(): boolean {
    const head = this.snake[0];
    return this.food !== null && isSamePoint(head, this.food);
  }

  /** 方向对应的坐标偏移 */
  private offsetOf(dir: Direction): Point {
    switch (dir) {
      case Direction.Up:
        return { x: 0, y: -1 };
      case Direction.Down:
        return { x: 0, y: 1 };
      case Direction.Left:
        return { x: -1, y: 0 };
      case Direction.Right:
        return { x: 1, y: 0 };
    }
  }

  /** 在空白格子上生成食物，若无处可放则视为胜利 */
  private spawnFood(): Point | null {
    const freeCells: Point[] = [];
    for (let y = 0; y < GRID_SIZE; y++) {
      for (let x = 0; x < GRID_SIZE; x++) {
        if (!this.snake.some((seg) => isSamePoint(seg, { x, y }))) {
          freeCells.push({ x, y });
        }
      }
    }
    if (freeCells.length === 0) {
      return null; // 蛇填满整个棋盘 → 胜利
    }
    return freeCells[randomInt(0, freeCells.length)];
  }

  /** 游戏结束 */
  private gameOver(reason: string): void {
    this.clearTimer();
    this.updateHighScore();
    this.setState('over');
    this.statusEl.textContent = `${reason} 得分 ${this.score}，按回车重新开始`;
  }

  /** 更新最高分并持久化 */
  private updateHighScore(): void {
    if (this.score > this.highScore) {
      this.highScore = this.score;
      this.highScoreEl.textContent = String(this.highScore);
      localStorage.setItem(HIGH_SCORE_KEY, String(this.highScore));
    }
  }

  /** 渲染整个画面 */
  private render(): void {
    const { ctx } = this;
    // 背景
    ctx.fillStyle = '#1a2332';
    ctx.fillRect(0, 0, this.canvas.width, this.canvas.height);

    // 绘制网格线
    ctx.strokeStyle = 'rgba(255,255,255,0.06)';
    ctx.lineWidth = 1;
    for (let i = 1; i < GRID_SIZE; i++) {
      ctx.beginPath();
      ctx.moveTo(i * CELL_SIZE, 0);
      ctx.lineTo(i * CELL_SIZE, this.canvas.height);
      ctx.stroke();
      ctx.beginPath();
      ctx.moveTo(0, i * CELL_SIZE);
      ctx.lineTo(this.canvas.width, i * CELL_SIZE);
      ctx.stroke();
    }

    // 绘制食物
    if (this.food) {
      const fx = this.food.x * CELL_SIZE;
      const fy = this.food.y * CELL_SIZE;
      ctx.fillStyle = '#ff4757';
      ctx.beginPath();
      ctx.arc(
        fx + CELL_SIZE / 2,
        fy + CELL_SIZE / 2,
        CELL_SIZE * 0.38,
        0,
        Math.PI * 2
      );
      ctx.fill();
    }

    // 绘制蛇
    this.snake.forEach((seg, index) => {
      const x = seg.x * CELL_SIZE;
      const y = seg.y * CELL_SIZE;
      // 头部亮一些，身体逐渐变暗
      const isHead = index === 0;
      ctx.fillStyle = isHead ? '#2ed573' : `rgb(${70 - index * 2}, ${190 - index * 3}, ${110})`;
      ctx.fillRect(x + 1, y + 1, CELL_SIZE - 2, CELL_SIZE - 2);

      // 头部眼睛
      if (isHead) {
        ctx.fillStyle = '#ffffff';
        const eyeOffset = 5;
        const half = CELL_SIZE / 2;
        if (this.direction === Direction.Left || this.direction === Direction.Right) {
          const dy = 6;
          ctx.beginPath();
          ctx.arc(x + half + (this.direction === Direction.Right ? 4 : -4), y + half - dy, 3, 0, Math.PI * 2);
          ctx.arc(x + half + (this.direction === Direction.Right ? 4 : -4), y + half + dy, 3, 0, Math.PI * 2);
          ctx.fill();
        } else {
          const dx = 6;
          ctx.beginPath();
          ctx.arc(x + half - dx, y + half + (this.direction === Direction.Down ? 4 : -4), 3, 0, Math.PI * 2);
          ctx.arc(x + half + dx, y + half + (this.direction === Direction.Down ? 4 : -4), 3, 0, Math.PI * 2);
          ctx.fill();
        }
        void eyeOffset;
      }
    });

    // 结束遮罩
    if (this.state === 'over') {
      ctx.fillStyle = 'rgba(0,0,0,0.55)';
      ctx.fillRect(0, 0, this.canvas.width, this.canvas.height);
      ctx.fillStyle = '#ffffff';
      ctx.font = 'bold 28px sans-serif';
      ctx.textAlign = 'center';
      ctx.fillText('游戏结束', this.canvas.width / 2, this.canvas.height / 2 - 10);
      ctx.font = '16px sans-serif';
      ctx.fillText(`得分 ${this.score}`, this.canvas.width / 2, this.canvas.height / 2 + 24);
    }
  }
}

// ---------- 启动 ----------

document.addEventListener('DOMContentLoaded', () => {
  new SnakeGame();
});
