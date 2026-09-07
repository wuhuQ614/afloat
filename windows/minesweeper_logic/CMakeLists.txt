cmake_minimum_required(VERSION 3.14)
project(minesweeper_logic LANGUAGES CXX)

# 跨平台 C++ 扫雷逻辑库（dart:ffi 调用）
add_library(minesweeper_logic SHARED
  "${CMAKE_CURRENT_SOURCE_DIR}/../../native/minesweeper_logic/minesweeper_logic.cpp"
)

target_compile_definitions(minesweeper_logic PRIVATE NOMINMAX)
target_compile_options(minesweeper_logic PRIVATE /W3 /EHsc /utf-8)
# 符号导出由 minesweeper_logic.h 中的 __declspec(dllexport) 宏完成

# 构建后拷贝到 runner 输出目录（与 afloat.exe 同目录，供 dart:ffi 加载）
add_custom_command(TARGET minesweeper_logic POST_BUILD
  COMMAND ${CMAKE_COMMAND} -E copy_if_different
    $<TARGET_FILE:minesweeper_logic>
    "${CMAKE_BINARY_DIR}/runner/$<CONFIG>/"
)
