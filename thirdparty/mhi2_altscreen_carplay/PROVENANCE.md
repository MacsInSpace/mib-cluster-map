# harman-f/mhi2_altscreen_carplay: CarPlay cluster-stream hook

Unmodified copy of `src/native/altscreen111-gen2/` from
https://github.com/harman-f/mhi2_altscreen_carplay at commit `47b1dcc30d25c01bd32b7f35a03380803aeea64e`
(GPL-3.0, see LICENSE). `build_local.sh` builds it, together with
`carplay/carplay_launcher.c`, into `libcarplay_cluster.so`.

It is preloaded into `dio_manager` and targets the CarPlay library
`libairplay.so` with SHA-256
`193a4fd9101ec2aa05e7159cfa307b96500810d379ca74a194f172adc13a46b5`
(Skoda MU1440; byte-identical on VW MU1367). It checks the stock function
prologues before hooking and leaves CarPlay stock on a mismatch.

This is harman-f's development source, which is newer than their
vehicle-tested binary of 2026-09-27 (SHA-256 `094e3f1a…`); the source of
that exact binary is not published.

This project uses only its cluster-stream output (H.264 on 127.0.0.1:19820),
not harman-f's direct MOST bridge. To update: copy the directory again and
change the commit above.
