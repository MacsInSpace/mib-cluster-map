# NavActiveIgnore.jar, Audi build (AU57x)

Unmodified file from
[M.I.B. - More Incredible Bash](https://github.com/Mr-MIBonk/M.I.B._More-Incredible-Bash)
(`mod/java/navignore_audi.jar`, added by harman-f in commit `562c0c3`,
"updated jars for navignore: individual solutions for AUDI/Porsche/Bentley
and VW/Skoda/Seat"), GPL-2.0 (see `LICENSE` beside it). M.I.B. installs it
on Audi units as `NavActiveIgnore.jar`.

SHA-256 `c962834de249459209f7c1aa4210f6b4179e563bad84e39e1312e4848278fd46`,
2645 bytes. It replaces two classes, both with the same members as the stock
ones in `MHI2_ER_AU57x_K3663` (MU1425) and class version 46:

- `de.audi.app.terminalmode.smartphone.androidauto2.nav.AndroidAuto2NavHandler`
- `org.dsi.ifc.carplay.AppState`

The toolbox's `NavActiveIgnore.jar` beside it (`thirdparty/mib2-toolbox`)
patches VW classes (`de.vw.mib.asl.*`), most of which the AU57x interface
does not have, so on `*_AU57x_*` the installer copies this one instead,
under the same name on the unit (`/eso/hmi/lsd/jars/NavActiveIgnore.jar`),
where M.I.B. and the status check look for it.

To update: copy the file again and change the hash and commit above.
