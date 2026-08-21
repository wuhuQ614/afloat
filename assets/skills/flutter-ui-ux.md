---
name: flutter-ui-ux
description: 使用现代设计模式和最佳实践创建美观、响应式、带动画的 Flutter 应用。当用户要求构建 Flutter 界面、优化 Flutter UI/UX、实现响应式布局或动画时使用。
category: 前端开发
source: ajianaz/flutter-ui-ux
---

# Flutter UI/UX Development

Create beautiful, responsive, and animated Flutter applications with modern design patterns and best practices.

## Core Philosophy

**"Mobile-first, animation-enhanced, accessible design"** - Focus on:

| Priority | Area               | Purpose                                               |
| -------- | ------------------ | ----------------------------------------------------- |
| 1        | Widget Composition | Reusable, maintainable UI components                  |
| 2        | Responsive Design  | Adaptive layouts for all screen sizes                 |
| 3        | Animations         | Smooth, purposeful transitions and micro-interactions |
| 4        | Custom Themes      | Consistent, branded visual identity                   |
| 5        | Performance        | 60fps rendering and optimal resource usage            |

## Development Workflow

Execute phases sequentially. Complete each before proceeding.

### Phase 1: Analyze Requirements

1. **Understand app structure** - Identify existing widgets, screens, and navigation
2. **Design system review** - Check existing themes, colors, and typography
3. **Platform considerations** - Note iOS/Android specific requirements
4. **Performance constraints** - Identify animation complexity and rendering needs

Output: UI requirements analysis with component breakdown.

### Phase 2: Design Widget Architecture

1. **Widget hierarchy planning** - Design composition tree
2. **State management strategy** - Choose StatefulWidget vs StatelessWidget
3. **Custom widget identification** - Plan reusable components
4. **Theme integration** - Define color schemes and typography

Output: Widget architecture diagram and component specifications.

### Phase 3: Implement Core UI

1. **Create base widgets** - Build foundational components
2. **Implement responsive layouts** - Use MediaQuery, LayoutBuilder, Flex/Expanded
3. **Add custom themes** - ThemeData, ColorScheme, TextThemes
4. **Integrate navigation** - Implement routing and transitions

**Widget Composition Patterns:**

```dart
// ✅ DO: Compose small, reusable widgets
class CustomCard extends StatelessWidget {
  final Widget child;
  final EdgeInsets padding;

  const CustomCard({required this.child, this.padding = EdgeInsets.all(16)});

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 4,
      child: Padding(padding: padding, child: child),
    );
  }
}

// ✅ DO: Use const constructors where possible
const Icon(Icons.add) // Better than Icon(Icons.add)
```

### Phase 4: Add Animations

1. **Implicit animations** - AnimatedContainer, AnimatedOpacity
2. **Explicit animations** - AnimationController with Tween
3. **Hero animations** - Screen transitions with Hero widgets
4. **Micro-interactions** - Button presses, hover effects, loading states

**Animation Performance Rules:**

```dart
// ✅ DO: Use performance-optimized animations
AnimatedBuilder(
  animation: controller,
  builder: (context, child) => Transform.rotate(
    angle: controller.value * 2 * math.pi,
    child: child, // Pass child to avoid rebuilding
  ),
  child: const Icon(Icons.refresh),
)

// ❌ DON'T: Animate expensive operations
// Avoid animating complex layouts or heavy widgets
```

### Phase 5: Optimize and Test

1. **Performance profiling** - Use Flutter DevTools
2. **Accessibility testing** - Screen readers, contrast ratios
3. **Responsive testing** - Multiple screen sizes and orientations
4. **Animation smoothness** - 60fps validation

## Quick Reference

### Responsive Design Patterns

| Technique         | Use Case          | Implementation                                        |
| ----------------- | ----------------- | ----------------------------------------------------- |
| LayoutBuilder     | Responsive layouts | LayoutBuilder(builder: (context, constraints) => ...) |
| MediaQuery        | Screen info        | MediaQuery.of(context).size.width                     |
| Flexible/Expanded | Flex layouts       | Flexible(child: ...) or Expanded(child: ...)          |
| AspectRatio       | Fixed ratios       | AspectRatio(aspectRatio: 16/9, child: ...)            |

### Animation Types

| Type     | Widget             | Duration    | Use Case           |
| -------- | ------------------ | ----------- | ------------------ |
| Fade     | AnimatedOpacity    | 200-300ms   | Show/hide content  |
| Slide    | SlideTransition    | 250-350ms   | Screen transitions |
| Scale    | AnimatedScale      | 150-250ms   | Button presses     |
| Rotation | RotationTransition | 1000-2000ms | Loading indicators |

## Technical Stack

* **Core Widgets**: StatelessWidget, StatefulWidget, InheritedWidget
* **Layout**: Row, Column, Stack, GridView, ListView
* **Animation**: AnimationController, Tween, AnimatedWidget
* **Themes**: ThemeData, ColorScheme, TextTheme
* **Navigation**: Navigator, MaterialPageRoute, Hero

## Accessibility (Required)

Always implement:

```dart
// Semantic labels for screen readers
Semantics(
  label: 'Add item to cart',
  button: true,
  child: IconButton(icon: Icon(Icons.add_cart), onPressed: () {}),
)

// Font scaling
MediaQuery.of(context).accessibleNavigation
```

## Performance Guidelines

* Use `const` widgets where possible
* Prefer `ListView.builder` for long lists
* Avoid unnecessary rebuilds with `const` keys
* Use `RepaintBoundary` for complex animations
* Profile with Flutter DevTools regularly

---

This Flutter UI/UX skill transforms mobile app development into a systematic process that ensures beautiful, responsive, and performant applications with exceptional user experiences.
