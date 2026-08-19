cmake_minimum_required(VERSION 3.18.1)

project("snake_logic")

add_library(
        snake_logic
        SHARED
        "${CMAKE_CURRENT_SOURCE_DIR}/../../../../../native/snake_logic/snake_logic.cpp"
)

target_link_libraries(
        snake_logic
        android
        log
)
