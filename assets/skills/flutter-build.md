---
name: flutter-build
description: 构建 Flutter 应用的 Windows EXE 与 Android APK（含 Inno Setup 安装包）。当用户要求构建、打包、生成 exe/apk/安装包时使用。使用前必须先弹问卷询问用户 Flutter SDK 位置，用户给出后才开始构建。
category: 开发工具
source: custom
---

# Flutter 构建技能（EXE / APK / 安装包）

## 关键规则（Agent 必须遵守）

**在运行任何构建命令之前，必须先弹出问卷（AskUserQuestion）询问用户 Flutter SDK 的安装位置（如 `C:\flutter`、`D:\flutter`、`E:\flutter`）。用户给出 SDK 路径后才允许开始构建。切勿在未确认 SDK 位置前直接执行构建命令。**

## 构建前

1. 弹问卷询问 Flutter SDK 位置，用户给出后才继续。
2. 用 SDK 下的 flutter 确认环境：`<SDK>\bin\flutter --version`。
3. 确认当前工作目录是 Flutter 项目根（含 pubspec.yaml 的目录），构建前建议先 `flutter pub get`（必要时 `flutter clean`）。

## 一、构建 Windows EXE

```
flutter build windows --release
```

- 产物目录：`build/windows/x64/runner/Release/`
  - `afloat.exe`：原生壳（约 0.2MB），Dart 业务代码在 `data\app.so`（约 14.7MB）
  - `data\`：`app.so`、`icudtl.dat`、`flutter_assets\`（资源）
  - 根目录与 `data\` 下全部 DLL：插件原生库（如 win32、inappwebview、flutter_tts 等），数量需逐一核对
- 部署：把 Release 目录内容同步到部署目录，必须覆盖全部 DLL、app.so、icudtl.dat、flutter_assets
- 部署后校验（必做）：
  1. DLL 数量与哈希逐一比对
  2. `app.so` / `icudtl.dat` 哈希比对
  3. `flutter_assets` 用 `Compare-Object` 比文件清单
  4. 启动 `afloat.exe` 冒烟测试：存活 8 秒且无 `crash_trace.txt`

## 二、构建 Android APK

```
flutter build apk --release
```

- 产物：`build/app/outputs/flutter-apk/app-release.apk`（约 82MB，debug key 签名），复制为 `afloat.apk` 交付
- 本机注意：Gradle/Kotlin daemon 写 C 盘临时文件会被沙箱拦截导致 BUILD FAILED。已在 `android/gradle.properties` 配置 `kotlin.daemon.dir` 与 `java.io.tmpdir` 重定向到项目 `dev-cache/` 目录规避。【注意 properties 中路径必须用正斜杠，否则反斜杠被转义吞掉】。APK 构建失败时先检查这两项配置。

## 三、Inno Setup 安装包（可选）

- 脚本：`installer/afloat_setup.iss`
- 编译：`iscc installer/afloat_setup.iss`
- 要点：
  - 向导图片必须是 **BMP** 格式（JPG 报 'Bitmap image is not valid'）
  - 版本号需与 [pubspec.yaml] 的 version 同步更新
  - 安装包须完整覆盖全部 DLL（新插件会引入新 DLL）与 `data\` 资源
- 产物：`afloat-setup.exe`（约 18MB）

## 四、常见坑

| 问题 | 处理 |
|---|---|
| 插件符号链接创建失败（PathNotFoundException） | 手动用 `New-Item -ItemType Junction` 补齐 `windows/flutter/ephemeral/.plugin_symlinks`（清单见 `.flutter-plugins-dependencies` 的 windows 段） |
| LNK1104 无法写入 afloat.exe | 旧版 afloat.exe 正在运行占用文件，先终止进程再构建 |
| Gradle BUILD FAILED | 检查 `kotlin.daemon.dir`/`java.io.tmpdir` 重定向配置是否还在 |
| Windows 插件导致的 Android 构建问题 | Android 平台避免使用 Windows 专属插件（如 window_manager） |

## 交付物核对清单

- Windows EXE：`afloat.exe` + 全部 DLL + `data\` 资源已部署并校验
- Android APK：`afloat.apk`
- 安装包：`afloat-setup.exe`
- 构建完成时向用户汇报产物路径与大小