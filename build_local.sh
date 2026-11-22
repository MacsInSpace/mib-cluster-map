#!/bin/bash
# Local build with the open QNX 6.5 ARMv7 toolchain image (luka-dev/qnx65-armv7-toolchain,
# tag 8.5).
#
#   ./build_local.sh            build everything and assemble dist/sdcard
#   ./build_local.sh hook       only libgal_hook.so + libdmdt_flush.so
#   ./build_local.sh player     only stream-player (builds ffmpeg-mini on first use)
#   ./build_local.sh java       only the steering-wheel zoom jars (host JDK 8 or newer)
#   ./build_local.sh wireless-bench  TEST ONLY: the package with the wireless bench
#                               hook (experiments/wireless_bench), as a separate zip
#
# Output: dist/sdcard/ (copy its CONTENTS to the SD card root) and a release zip in dist/.
set -euo pipefail
IMG=${QNX_IMAGE:-qnx65-armv7-toolchain:8.5}
ROOT="$(cd "$(dirname "$0")" && pwd)"
WHAT=${1:-all}
# RELEASE_VERSION first: a release build is usually made before its tag
# exists, and beta17 shipped a hook that called itself beta16-dirty.
BUILD_ID=${RELEASE_VERSION:-$(git -C "$ROOT" describe --always --dirty 2>/dev/null || echo local)}
# Packaging needs no compiler, so only the build steps require the image. Docker
# Desktop's inspect call has failed transiently here while the image was present,
# so fall back to the image list before giving up.
need_image() {
  # Saved to, or loaded from, the shared image folder (tools/docker_image.sh),
  # so another Mac account does not rebuild it.
  sh "$ROOT/tools/docker_image.sh" "$IMG" && return 0
  echo "ERROR: docker image $IMG not found; build it first (qnx-run.sh build 8.5)"; exit 1
}
run() { docker run --rm --platform=linux/amd64 -v "$ROOT":/work -w /work -e BUILD_ID="$BUILD_ID" "$IMG" bash -c "$1"; }
ENVSETUP='export PATH=/opt/qnx650/host/linux/x86/usr/bin:$PATH QNX_HOST=/opt/qnx650/host/linux/x86 QNX_TARGET=/opt/qnx650/target/qnx6; P=arm-unknown-nto-qnx6.5.0eabi'
mkdir -p "$ROOT/build"

build_hook() {
  need_image
  run "$ENVSETUP"'
    set -e
    # --exclude-libs,ALL keeps libgcc helpers (_Unwind_*, __aeabi_*) out of the dynamic
    # symbol table: a preloaded library must not interpose those over gal'"'"'s own.
    $P-gcc -O2 -Wall -Wextra -shared -fPIC -I./src -DGAL_HOOK_BUILD="\"$BUILD_ID\"" \
        ./src/*.c -Wl,--exclude-libs,ALL -lsocket -o build/libgal_hook.so
    $P-gcc -O2 -Wall -shared -fPIC dmdt_flush/dmdt_flush.c -Wl,--exclude-libs,ALL -o build/libdmdt_flush.so
    $P-strip --strip-debug build/libgal_hook.so build/libdmdt_flush.so
    echo "--- exported symbols that are not ours (must be empty):"
    bad=$($P-nm -D --defined-only build/libgal_hook.so | awk "{print \$3}" | \
          grep -Ev "^(_ZN|gal_hook_|fc_|vc_|hook_fix_enabled|_init|_fini|__bss|_edata|_end|__end__|_bss_end__|__bss_start__|__bss_end__|__data_start|__exidx_start|__exidx_end|_btext|_stack)" || true)
    echo "$bad"
    [ -z "$bad" ] || { echo "REJECTED: unexpected exports"; exit 1; }
    n=$($P-nm build/libgal_hook.so | grep -ci emutls || true)
    [ "$n" = "0" ] || { echo "REJECTED: emutls symbols present"; exit 1; }
    $P-readelf -d build/libgal_hook.so | grep NEEDED
    # CarPlay: one library for dio_manager'"'"'s single LD_PRELOAD entry --
    # harman-f'"'"'s cluster-stream hook, unmodified and with its own build flags,
    # plus the launcher that starts carplay_cluster.sh.
    A=thirdparty/mhi2_altscreen_carplay
    $P-gcc -shared -fPIC -mfloat-abi=softfp -O2 -std=gnu99 -Wall -Wextra -I$A/include \
        $A/libaltscreen111_gen2.c $A/src/alt111_profile.c $A/src/alt111_control.c \
        $A/src/alt111_video.c $A/src/alt111_resync.c carplay/carplay_launcher.c \
        -Wl,-soname,libcarplay_cluster.so -lsocket -o build/libcarplay_cluster.so
    $P-strip --strip-debug build/libcarplay_cluster.so
    $P-gcc -O2 -Wall -Wextra -I./src tools/profile_check.c src/profile_table.c -o build/profile_check
    $P-strip -s build/profile_check
    # The hardware decoder check (green menu, ClusterMapSupport).
    $P-gcc -O1 -Wall -Wextra tools/nvprobe/nvprobe.c -o build/nvprobe
    $P-strip -s build/nvprobe
  '
}

# The wireless bench hook (experiments/wireless_bench/README.md): its own
# output folder, so a normal package never picks it up.
build_hook_bench() {
  need_image
  run "$ENVSETUP"'
    set -e
    mkdir -p build/bench
    $P-gcc -O2 -Wall -Wextra -shared -fPIC -I./src -I./experiments/wireless_bench -DWIRELESS_BENCH \
        -DGAL_HOOK_BUILD="\"$BUILD_ID-wireless-bench\"" \
        ./src/*.c -Wl,--exclude-libs,ALL -lsocket -o build/bench/libgal_hook.so
    $P-strip --strip-debug build/bench/libgal_hook.so
    bad=$($P-nm -D --defined-only build/bench/libgal_hook.so | awk "{print \$3}" | \
          grep -Ev "^(_ZN|gal_hook_|fc_|vc_|hook_fix_enabled|_init|_fini|__bss|_edata|_end|__end__|_bss_end__|__bss_start__|__bss_end__|__data_start|__exidx_start|__exidx_end|_btext|_stack)" || true)
    [ -z "$bad" ] || { echo "REJECTED: unexpected exports: $bad"; exit 1; }
  '
}

# A normal package, then the bench hook and its scripts swapped in, zipped
# under its own name. GAL_WIRELESS_BENCH=1 is in this card's settings only.
package_bench() {
  local D="$ROOT/dist/sdcard/ClusterMap" B="$ROOT/experiments/wireless_bench"
  local VER=${RELEASE_VERSION:-$BUILD_ID}
  cp "$ROOT/build/bench/libgal_hook.so" "$D/libgal_hook.so"
  cp "$B/bench_firewall.sh" "$D/"
  printf '\n# Wireless bench test (experiments/wireless_bench): TEST BUILD ONLY.\nGAL_WIRELESS_BENCH=1\n' >> "$D/gal_dualscreen.conf"
  printf '\n# Wireless bench test (experiments/wireless_bench): TEST BUILD ONLY.\nGAL_WIRELESS_BENCH=1\n' >> "$D/scripts/gal_dualscreen.default.conf"
  printf '%s\n' "$VER-wireless-bench" > "$D/scripts/package_version.txt"
  python3 "$ROOT/tools/unit_shell_lint.py" "$D" || { echo "REJECTED: lint"; exit 1; }
  python3 "$ROOT/tools/unit_tool_options.py" "$D" || { echo "REJECTED: tool options"; exit 1; }
  (cd "$D" && shasum -a 256 libgal_hook.so stream-player profile_check hwcheck/nvprobe hwcheck/clip_800x480.h264 profiles.conf lib/libdmdt_flush.so carplay/libcarplay_cluster.so carplay/ClusterMapWheelZoom.jar carplay/ClusterMapNavAsiaZoom.jar carplay/ClusterMapGfxKeep.jar > SHA256SUMS.txt)
  python3 "$ROOT/tools/make_metainfo.py" "$ROOT/dist/sdcard" "$VER-wireless-bench"
  local Z="$ROOT/dist/mib-cluster-map_$VER-wireless-bench.zip"
  rm -f "$ROOT"/dist/*.zip "$ROOT"/dist/*.sha256
  (cd "$ROOT/dist/sdcard" && zip -qr -X "$Z" ClusterMap Custom metainfo2.txt Swdlautorun.txt -x '*.DS_Store' -x '._*')
  echo "TEST BUILD (not for release): $Z"
}

build_player() {
  need_image
  run "$ENVSETUP"'
    set -e
    FF=/work/build/ffmpeg-mini; V=6.1.5
    SHA=b8c8e926b948c14df1264cd0beac1c773df9170ac9cac97bdf1275cd3d385902
    # FFmpeg with its hand-written NEON routines for the Tegra 3 (Cortex-A9).
    # The QNX kernel of these units stops a NEON load or store of 16, 32 or 64
    # bits at an address that is not a multiple of its size (v1.2.2 crashed in
    # the h264 horizontal loop filter). So:
    #   tools/ffmpeg_qnx_aligned.sh leaves out the routines that do that,
    #   tools/qnx_cc.sh gives NEON to the assembly files only (C stays VFPv3),
    #   FFmpeg and the compiler make no misaligned access in C either,
    #   tools/neon_audit.py checks every NEON load and store in the result.
    # Found and car-tested by the Skoda fork of AMDFX60. The stamp makes a
    # cached build with other settings be made again from the same source.
    FFCONF=neon-asm-aligned-2
    if [ ! -f $FF/libavcodec/libavcodec.a ] || [ "$(cat $FF/.mibcm-ffconf 2>/dev/null)" != "$FFCONF" ]; then
      if [ ! -f $FF/configure ]; then
        cd /work/build
        [ -f ffmpeg-$V.tar.gz ] || curl -fL --retry 3 -o ffmpeg-$V.tar.gz https://ffmpeg.org/releases/ffmpeg-$V.tar.gz
        echo "$SHA  ffmpeg-$V.tar.gz" | sha256sum -c -
        mkdir -p $FF && tar xf ffmpeg-$V.tar.gz -C $FF --strip-components=1
      else
        (cd $FF && make distclean >/dev/null 2>&1 || true)
      fi
      cd $FF
      cp /work/tools/qnx_cc.sh $FF/qnx_cc.sh && chmod 755 $FF/qnx_cc.sh
      sh /work/tools/ffmpeg_qnx_aligned.sh $FF
      ./configure --cc=$FF/qnx_cc.sh --as=$FF/qnx_cc.sh --ar=$P-ar --ld=$P-gcc --nm=$P-nm --ranlib=$P-ranlib --strip=$P-strip \
        --arch=arm --cpu=cortex-a9 --target-os=qnx --enable-neon --disable-fast-unaligned --disable-debug --enable-cross-compile \
        --extra-cflags="-D_QNX_SOURCE -mfloat-abi=softfp -mfpu=vfpv3-d16 -mno-unaligned-access" \
        --extra-libs=-lsocket --disable-doc --disable-programs --disable-avdevice --disable-swresample \
        --disable-swscale --disable-postproc --disable-avfilter --disable-everything \
        --enable-decoder=h264 --enable-parser=h264
      grep -q "HAVE_NEON 1" config.h || { echo "REJECTED: FFmpeg configured without NEON"; exit 1; }
      grep -q "HAVE_FAST_UNALIGNED 0" config.h || { echo "REJECTED: FFmpeg configured with fast unaligned access"; exit 1; }
      make -j"$(nproc)"
      echo "$FFCONF" > $FF/.mibcm-ffconf
    fi
    # No object may refer to a NEON routine that was left out.
    LEFT="ff_h264_h_loop_filter_luma_neon|ff_h264_h_loop_filter_chroma_neon|ff_h264_h_loop_filter_chroma422_neon|h_loop_filter_chroma420|ff_put_h264_chroma_mc[24]_neon|ff_avg_h264_chroma_mc[24]_neon|ff_pred8x8_plane_neon"
    refs=$(find $FF/libavcodec $FF/libavutil $FF/libavformat -name "*.o" | while read o; do $P-objdump -r $o 2>/dev/null | grep -E "$LEFT" | sed "s|^|$o: |"; done)
    [ -z "$refs" ] || { echo "REJECTED: a misaligned NEON routine is still referenced:"; echo "$refs"; exit 1; }
    # The same search must find a routine that is kept, or it proves nothing.
    kept=$($P-objdump -r $FF/libavcodec/arm/h264dsp_init_arm.o | grep -c ff_h264_v_loop_filter_luma_neon || true)
    [ "$kept" -gt 0 ] || { echo "REJECTED: the NEON reference check finds no kept routine either"; exit 1; }
    cd /work/player
    $P-g++ -O2 -Wall -DNDEBUG -I$FF -I. opengl_gpu.cc -c -o /work/build/opengl_gpu.o
    $P-g++ /work/build/opengl_gpu.o \
        -Wl,--start-group $FF/libavformat/libavformat.a $FF/libavcodec/libavcodec.a $FF/libavutil/libavutil.a -Wl,--end-group \
        -static-libstdc++ -static-libgcc -lEGL -lGLESv2 -lsocket -lm -o /work/build/stream-player
    $P-objdump -d /work/build/stream-player > /work/build/stream-player.dis
    $P-strip -s /work/build/stream-player
    $P-readelf -d /work/build/stream-player | grep NEEDED
  '
  # Every NEON load and store in the linked player, checked on this machine.
  if ! python3 "$ROOT/tools/neon_audit.py" "$ROOT/build/stream-player.dis" "$ROOT/tools/neon_audit.allow" > "$ROOT/build/neon_audit.txt"; then
    cat "$ROOT/build/neon_audit.txt"
    echo "REJECTED: a NEON access that was not checked (list above)"; exit 1
  fi
  tail -1 "$ROOT/build/neon_audit.txt"
}

build_java() {
  # The AU57x steering-wheel zoom for the CarPlay map: a Java patch, built on
  # the host (no QNX tools involved). tests/wheelzoom_check.sh checks it
  # against a converted stock lsd.jar, which is not in the repository;
  # tests/navasiazoom_check.sh the Chinese K1006_2's.
  "$ROOT/java/wheelzoom/build.sh" "$ROOT/build"
  "$ROOT/java/navasiazoom/build.sh" "$ROOT/build"
  # The AU57x cockpit map view for the CarPlay map (java/gfxkeep):
  # tests/gfxkeep_logic_test.sh runs it against stand-ins of the stock classes.
  "$ROOT/java/gfxkeep/build.sh" "$ROOT/build"
  "$ROOT/tests/gfxkeep_logic_test.sh" "$ROOT/build/ClusterMapGfxKeep.jar" >/dev/null ||
    { echo "REJECTED: tests/gfxkeep_logic_test.sh failed"; exit 1; }
}

package() {
  # SD card layout. Everything of ours sits in one folder; the green menu screen
  # goes where the MQB Coding MIB2 Toolbox looks for custom screens.
  #   ClusterMap/                 scripts, binaries, settings, docs
  #   Custom/GreenMenu/*.esd        menu screen (copied to the unit by the toolbox)
  S="$ROOT/dist/sdcard"; D="$S/ClusterMap"
  rm -rf "$S"; mkdir -p "$D/scripts" "$D/lib" "$D/GEM" "$D/docs" "$S/Custom/GreenMenu"
  cp "$ROOT/build/libgal_hook.so" "$ROOT/build/stream-player" "$ROOT/build/profile_check" "$D/"
  cp "$ROOT/build/libdmdt_flush.so" "$D/lib/"
  mkdir -p "$D/hwcheck"
  cp "$ROOT/build/nvprobe" "$ROOT/tools/nvprobe/clip_800x480.h264" "$ROOT/tools/nvprobe/clip_800x480.expect" "$D/hwcheck/"
  mkdir -p "$D/carplay"
  cp "$ROOT/build/libcarplay_cluster.so" "$ROOT/carplay/carplay_cluster.sh" "$D/carplay/"
  cp "$ROOT/build/ClusterMapWheelZoom.jar" "$ROOT/build/ClusterMapNavAsiaZoom.jar" "$ROOT/build/ClusterMapGfxKeep.jar" "$D/carplay/"
  cp "$ROOT/thirdparty/mhi2_altscreen_carplay/LICENSE" "$D/carplay/mhi2_altscreen_carplay.LICENSE"
  # The install scripts treat their own folder as the package root.
  cp "$ROOT"/scripts/enable_hook.sh "$ROOT"/scripts/disable_hook.sh "$ROOT"/scripts/collect_logs.sh \
     "$ROOT"/scripts/turn_by_turn.sh "$ROOT"/scripts/lsd_jar.sh "$D/"
  mkdir -p "$D/thirdparty" && cp "$ROOT"/thirdparty/mib2-android-auto-vc/VCAndroidAuto.jar "$ROOT"/thirdparty/mib2-android-auto-vc/VCAndroidAutoMusic.jar "$ROOT"/thirdparty/mib2-android-auto-vc/VCAndroidAutoMusic_K3342.jar "$ROOT"/thirdparty/mib2-android-auto-vc/VCAndroidAutoTurns.jar "$ROOT"/thirdparty/mib2-android-auto-vc/VCAndroidAutoTurns_K3342.jar "$D/thirdparty/" && \
     cp "$ROOT"/thirdparty/mib2-android-auto-vc/LICENSE "$D/thirdparty/VCAndroidAuto.LICENSE"
  cp "$ROOT"/thirdparty/mib2-toolbox/NavActiveIgnore.jar "$D/thirdparty/" && cp "$ROOT"/thirdparty/mib2-toolbox/LICENSE "$D/thirdparty/NavActiveIgnore.LICENSE"
  # The Audi build, for AU57x (thirdparty/navactiveignore-audi/README.md).
  cp "$ROOT"/thirdparty/navactiveignore-audi/NavActiveIgnore.jar "$D/thirdparty/NavActiveIgnore_Audi.jar" && \
     cp "$ROOT"/thirdparty/navactiveignore-audi/LICENSE "$D/thirdparty/NavActiveIgnore_Audi.LICENSE"
  cp "$ROOT/scripts/lib_app_mount.sh" "$ROOT/scripts/hook_status.sh" "$ROOT/scripts/lib_resolve_hook_log.sh" \
     "$ROOT/scripts/lib_unit.sh" "$ROOT/scripts/window_fix.sh" \
     "$ROOT/scripts/lib_cluster_frame.sh" "$ROOT/scripts/full_frame.sh" "$ROOT/scripts/menu_switch.sh" \
     "$ROOT/scripts/lib_keep_settings.sh" "$ROOT/scripts/unit_probe.sh" "$ROOT/scripts/wireless_probe.sh" "$D/scripts/"
  cp "$ROOT"/greenmenu/GEM/*.sh "$D/GEM/"
  cp "$ROOT/greenmenu/cluster-map.esd" "$S/Custom/GreenMenu/"
  # Software-update route: the same screen, copied to the unit by the update
  # itself, plus the final script that runs the installer.
  cp "$ROOT/greenmenu/cluster-map.esd" "$D/GEM/"
  mkdir -p "$D/final" && cp "$ROOT/swdl/finalScript.sh" "$ROOT/swdl/update_run.sh" "$D/final/"
  # A ready-made marker, so nobody has to create a file by hand.
  mkdir -p "$D/to uninstall, move this file up one folder"
  printf 'While a file whose name starts with UNINSTALL is in the ClusterMap folder,\r\nrunning the update from this card REMOVES the cluster map and restores the\r\noriginal state. Move this file back here (or delete it) to install again.\r\n' > "$D/to uninstall, move this file up one folder/UNINSTALL.txt"
  mkdir -p "$D/to only check compatibility, move this file up one folder"
  printf 'While a file whose name starts with COLLECT is in the ClusterMap folder,\r\nrunning the update from this card INSTALLS NOTHING. It writes a compatibility\r\ncheck to update_result.txt and copies the files a port needs to porting_<train>/.\r\nOnly the menu screen file is copied to the unit. Move this file back here to install.\r\n' > "$D/to only check compatibility, move this file up one folder/COLLECT.txt"
  # Empty, as in M.I.B.: with this name the unit starts the update by itself
  # when the card goes in (no service menu). On by default; update_run.sh
  # renames it to _Swdlautorun.txt when the install finishes, so the update
  # does not start again with the card still in. Rename it back to
  # _Swdlautorun.txt to switch autorun off.
  : > "$S/Swdlautorun.txt"
  cp "$ROOT/config/gal_dualscreen.conf" "$D/gal_dualscreen.conf"
  # The shipped settings, untouched: the installer compares the card's copy
  # with it to find the owner's own lines (scripts/lib_keep_settings.sh).
  cp "$ROOT/config/gal_dualscreen.conf" "$D/scripts/gal_dualscreen.default.conf"
  # Which package this card is: the installer keeps the owner's lines only
  # when the card is a different package from the last install's.
  printf '%s\n' "${RELEASE_VERSION:-$BUILD_ID}" > "$D/scripts/package_version.txt"
  cp "$ROOT/config/profiles.conf" "$D/profiles.conf"
  cp "$ROOT/README.md" "$ROOT/docs/Install.md" "$D/docs/"
  cp "$ROOT/LICENSE" "$D/LICENSE"
  # The unit's shell needs LF line endings and plain ASCII in everything it runs.
  python3 "$ROOT/tools/check_scripts.py" "$D" || { echo "REJECTED: scripts use something units lack"; exit 1; }
  # What the unit's shell does differently from this machine's (docs/Unit-shell.md).
  python3 "$ROOT/tools/unit_shell_lint.py" "$D" || { echo "REJECTED: a script has a shape the unit's shell treats differently"; exit 1; }
  # Options the unit's own tools list in their help (copies off owners' units, kept privately; skipped without them).
  python3 "$ROOT/tools/unit_tool_options.py" "$D" || { echo "REJECTED: a script gives a unit tool an option it lacks"; exit 1; }
  sh "$ROOT/tests/unit_shell_lint_test.sh" >/dev/null || { echo "REJECTED: tests/unit_shell_lint_test.sh failed"; exit 1; }
  # Faults that reached a release once must not come back (docs/Development.md, "Settled parts").
  sh "$ROOT/tests/regression_guards.sh" || { echo "REJECTED: a regression guard failed"; exit 1; }
  sh "$ROOT/tests/profile_check_test.sh" >/dev/null || { echo "REJECTED: tests/profile_check_test.sh failed"; exit 1; }
  sh "$ROOT/tests/cluster_frame_test.sh" >/dev/null || { echo "REJECTED: tests/cluster_frame_test.sh failed"; exit 1; }
  cc -O1 -I "$ROOT/src" "$ROOT/tests/hd_frame_insets_test.c" -o "$ROOT/build/hd_frame_insets_test" &&
     "$ROOT/build/hd_frame_insets_test" >/dev/null || { echo "REJECTED: tests/hd_frame_insets_test.c failed"; exit 1; }
  bad=$(perl -ne 'if (/\r|[^\x00-\x7F]/) { print "$ARGV\n"; close ARGV }' "$D"/*.sh "$D"/scripts/*.sh "$D"/GEM/*.sh "$D"/final/*.sh "$D"/carplay/*.sh "$S"/Custom/GreenMenu/*.esd "$D"/gal_dualscreen.conf | sort -u)
  [ -z "$bad" ] || { echo "REJECTED: CR or non-ASCII in: $bad"; exit 1; }
  (cd "$D" && shasum -a 256 libgal_hook.so stream-player profile_check hwcheck/nvprobe hwcheck/clip_800x480.h264 profiles.conf lib/libdmdt_flush.so carplay/libcarplay_cluster.so carplay/ClusterMapWheelZoom.jar carplay/ClusterMapNavAsiaZoom.jar carplay/ClusterMapGfxKeep.jar > SHA256SUMS.txt)
  python3 "$ROOT/tools/make_metainfo.py" "$S" "${RELEASE_VERSION:-$BUILD_ID}"
  VER=${RELEASE_VERSION:-$BUILD_ID}
  Z="$ROOT/dist/mib-cluster-map_$VER.zip"
  rm -f "$ROOT"/dist/*.zip "$ROOT"/dist/*.sha256
  (cd "$S" && zip -qr -X "$Z" ClusterMap Custom metainfo2.txt Swdlautorun.txt -x '*.DS_Store' -x '._*')
  (cd "$ROOT/dist" && shasum -a 256 "$(basename "$Z")" > "$(basename "$Z").sha256")
  echo "Packaged: $S"; echo "Archive:  $Z"
  (cd "$S" && find . -type f | sort)
}

case "$WHAT" in
  hook) build_hook ;;
  player) build_player ;;
  java) build_java ;;
  all) build_hook; build_player; build_java; package ;;
  package) package ;;
  wireless-bench) build_hook; build_hook_bench; build_player; build_java; package; package_bench ;;
  simtest) sh "$ROOT/tests/unit_sim/run.sh" "$ROOT/dist/sdcard" ;;
  *) echo "usage: $0 [all|hook|player|java|package|simtest|wireless-bench]"; exit 2 ;;
esac
