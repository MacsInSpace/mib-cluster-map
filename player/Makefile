# Makefile for building stream-player for Harman MHI2 (QNX 6.5.0 / Tegra 3 ARMv7)
# Requires Docker and the MIB SDK image; ffmpeg-mini is cross-compiled
# automatically by build_ffmpeg.sh the first time it's needed.

DOCKER_IMAGE  := registry.gitlab.com/andrewleech/mibsdk:latest
PWD           := $(shell pwd)
DEFAULT_FFMPEG_PATH := $(PWD)/build/ffmpeg-mini
FFMPEG_PATH   ?= $(DEFAULT_FFMPEG_PATH)
# player/ is mounted into the container as /work and the FFmpeg build tree
# as /ffmpeg, so FFMPEG_PATH may point anywhere on the host -- including an
# existing ffmpeg-mini outside this repository.
FFMPEG_DIR    := $(abspath $(FFMPEG_PATH))
FFMPEG_LIBS   := $(FFMPEG_DIR)/libavformat/libavformat.a \
                  $(FFMPEG_DIR)/libavcodec/libavcodec.a \
                  $(FFMPEG_DIR)/libavutil/libavutil.a

.PHONY: all ffmpeg clean ffmpeg-clean

all: stream-player

ifeq ($(FFMPEG_DIR),$(DEFAULT_FFMPEG_PATH))
# ffmpeg-mini is expensive to build, so it's cached under build/ and only
# rebuilt when missing; `make ffmpeg-clean` forces a rebuild. All three
# libraries come out of one build_ffmpeg.sh run, so they're gated behind
# a single stamp file, which stream-player depends on directly. The stamp
# is written inside the container: with Docker on Linux, build/ is created
# as root and a host-side touch is refused.
FFMPEG_DEPS   := $(FFMPEG_DIR)/.built

ffmpeg: $(FFMPEG_DEPS)

$(FFMPEG_DEPS):
	@echo "==> ffmpeg-mini not found, cross-compiling it inside Docker SDK..."
	docker run --rm -v $(PWD):/work -v $(FFMPEG_DIR):/ffmpeg -w /work $(DOCKER_IMAGE) sh -c '\
		. /etc/qnx/env && \
		FFMPEG_PATH=/ffmpeg BUILD_DIR=/work/build ./build_ffmpeg.sh && \
		touch /ffmpeg/.built'
else
# A FFMPEG_PATH chosen by the caller must already hold a built ffmpeg-mini.
# It is mounted read-only: never built into, stamped or cleaned.
FFMPEG_DEPS   := $(FFMPEG_LIBS)

ffmpeg:
	@echo "==> Using prebuilt ffmpeg-mini at $(FFMPEG_DIR)"

$(FFMPEG_LIBS):
	$(error $@ not found; FFMPEG_PATH must point at a built ffmpeg-mini)
endif

stream-player: opengl_gpu.cc $(FFMPEG_DEPS)
	@echo "==> Building stream-player inside Docker SDK..."
	docker run --rm -v $(PWD):/work -v $(FFMPEG_DIR):/ffmpeg:ro -w /work $(DOCKER_IMAGE) sh -c '\
		. /etc/qnx/env && \
		qcc -Vgcc_ntoarmv7 -c -O2 -Wc,-Wall -I/ffmpeg -DNDEBUG \
			-I. -I/usr/qnx650/target/qnx6/usr/include \
			-EL -DVARIANT_le -DVARIANT_v7 -DBUILDENV_qss \
			opengl_gpu.cc -o opengl_gpu.o && \
		qcc -V4.4.2,gcc_ntoarmv7le opengl_gpu.o \
			-L/usr/qnx650/target/qnx6/armle-v7/lib -L/usr/qnx650/target/qnx6/armle-v7/usr/lib \
			-Wl,--start-group \
			/ffmpeg/libavformat/libavformat.a \
			/ffmpeg/libavcodec/libavcodec.a \
			/ffmpeg/libavutil/libavutil.a \
			-Bstatic -lbz2 -lz -lcpp -Bdynamic \
			-Wl,--end-group \
			-lEGL -lGLESv2 -lsocket -lm -lc \
			-o stream-player && \
		ntoarmv7-strip -s stream-player'
	@echo "==> Build successful: player/stream-player"

clean:
	rm -f opengl_gpu.o stream-player

# build/ is created by the container as root, so remove it from inside one.
ffmpeg-clean:
	docker run --rm -v $(PWD):/work $(DOCKER_IMAGE) rm -rf /work/build
