# CMake file for QuickJS static library placeholder compilation
project(qjs LANGUAGES C)

add_library(qjs STATIC
    quickjs_dummy.c
)
