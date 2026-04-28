cmake_minimum_required(VERSION 3.20.0)
find_package(Zephyr REQUIRED HINTS $ENV{ZEPHYR_BASE})
project(traffic_light_zephyr)

# Pick the compiler matching the Alire cross crate (gnat_arm_elf).
find_program(ADA_COMPILER arm-eabi-gcc REQUIRED)
find_program(ADA_GPRBUILD gprbuild     REQUIRED)
find_program(ADA_GNATBIND NAMES arm-eabi-gnatbind gnatbind REQUIRED)

get_filename_component(ADA_BIN_DIR       "${ADA_COMPILER}" DIRECTORY)
get_filename_component(ADA_TOOLCHAIN_DIR "${ADA_BIN_DIR}"  DIRECTORY)

# Derive tool prefix from the compiler name (arm-eabi-gcc → arm-eabi-).
get_filename_component(_stem "${ADA_COMPILER}" NAME_WE)
string(REGEX REPLACE "-gcc$" "" ADA_TARGET "${_stem}")
set(ADA_TOOL_PREFIX "${ADA_TARGET}-")

# Parse the RTS name out of the GPR so it stays a single source of truth.
file(READ "${CMAKE_CURRENT_SOURCE_DIR}/traffic_light_zephyr.gpr" _gpr)
string(REGEX MATCH "for Runtime \\(\"Ada\"\\) use \"([^\"]+)\"" _ "${_gpr}")
set(ADA_RTS "${CMAKE_MATCH_1}")

# libgnat.a lives inside the RTS — needed for elaboration/runtime support.
# gnatbind needs the absolute RTS dir (--RTS=<name> works for gprbuild but
# fails for gnatbind with "missing adainclude").
set(ADA_RTS_DIR "${ADA_TOOLCHAIN_DIR}/${ADA_TARGET}/lib/gnat/${ADA_RTS}")
find_file(ADA_LIBGNAT "libgnat.a"
  PATHS "${ADA_RTS_DIR}/adalib"
  NO_DEFAULT_PATH REQUIRED)

set(ADA_OBJ_DIR "${CMAKE_CURRENT_BINARY_DIR}/ada_obj")
set(ADA_LIB     "${ADA_OBJ_DIR}/lib/libada_app.a")
file(MAKE_DIRECTORY "${ADA_OBJ_DIR}")

file(GLOB_RECURSE ADA_SOURCES CONFIGURE_DEPENDS
  "src/core/*.ads" "src/core/*.adb"
  "src/app/*.ads"  "src/app/*.adb"
  "src/hal/zephyr/*.ads" "src/hal/zephyr/*.adb")

if(WIN32)
  set(_psep ";")
else()
  set(_psep ":")
endif()

# ── Compile Ada → static archive ────────────────────────────────────────
add_custom_command(
  OUTPUT "${ADA_LIB}"
  COMMAND ${CMAKE_COMMAND} -E env
    "PATH=${ADA_BIN_DIR}${_psep}$ENV{PATH}"
    "GPR_TOOL_PREFIX=${ADA_TOOL_PREFIX}"
    "${ADA_GPRBUILD}"
      -P "${CMAKE_CURRENT_SOURCE_DIR}/traffic_light_zephyr.gpr"
      -j0 --target=${ADA_TARGET}
      -XADA_OBJ_DIR="${ADA_OBJ_DIR}"
  DEPENDS ${ADA_SOURCES} "${CMAKE_CURRENT_SOURCE_DIR}/traffic_light_zephyr.gpr"
  WORKING_DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}"
  COMMENT "Compiling Ada for ${ADA_TARGET} (${ADA_RTS})")
add_custom_target(ada_lib ALL DEPENDS "${ADA_LIB}")

# ── Bind the Ada main ───────────────────────────────────────────────────
# gprbuild with Library_Kind=static does NOT run the binder. Run gnatbind -n
# on main.ali to emit ada_bind.adb (defines adainit/adafinal); the C
# trampoline in src/hal/zephyr/ada_main.c calls adainit() then _ada_main().
#
# IMPORTANT: -mcpu / -mthumb / -mfpu / -mfloat-abi MUST match the GPR's
# Compiler.Default_Switches exactly. Cortex-M33F here.
set(ADA_BINDER_OBJ "${ADA_OBJ_DIR}/ada_bind.o")
add_custom_command(
  OUTPUT "${ADA_BINDER_OBJ}"
  COMMAND ${CMAKE_COMMAND} -E env
    "PATH=${ADA_BIN_DIR}${_psep}$ENV{PATH}"
    "${ADA_GNATBIND}" -n --RTS=${ADA_RTS_DIR} -o ada_bind.adb main.ali
  COMMAND ${CMAKE_COMMAND} -E env
    "PATH=${ADA_BIN_DIR}${_psep}$ENV{PATH}"
    "${ADA_COMPILER}" -c --RTS=${ADA_RTS_DIR}
      -mcpu=cortex-m33 -mthumb -mfpu=fpv5-sp-d16 -mfloat-abi=hard
      -o ada_bind.o ada_bind.adb
  WORKING_DIRECTORY "${ADA_OBJ_DIR}"
  DEPENDS "${ADA_LIB}"
  COMMENT "Binding Ada main → ada_bind.o (adainit/adafinal)")
add_custom_target(ada_binder ALL DEPENDS "${ADA_BINDER_OBJ}")

# ── C sources Zephyr compiles ───────────────────────────────────────────
target_sources(app PRIVATE
  src/hal/zephyr/ada_main.c       # trampoline → adainit() → _ada_main()
  src/hal/zephyr/hal_zephyr.c     # Zephyr API shims callable from Ada
)

# ── Link ────────────────────────────────────────────────────────────────
add_dependencies(app ada_lib ada_binder)
target_link_libraries(app PRIVATE
  "${ADA_BINDER_OBJ}"
  "${ADA_LIB}"
  "${ADA_LIBGNAT}")

# Zephyr libc and the Ada RTS both define `abort`; let the linker keep one.
zephyr_ld_options("-Wl,--allow-multiple-definition")

# Ada's light runtime s-memory.adb references __heap_start / __heap_end.
# This is a no-heap configuration — any Ada allocation raises Storage_Error.
# Replace with a bump-heap or libc bridge if/when allocation is needed
# (see zephyr.md "Allocator options").
zephyr_ld_options(
  "-Wl,--defsym=__heap_start=0"
  "-Wl,--defsym=__heap_end=0")
