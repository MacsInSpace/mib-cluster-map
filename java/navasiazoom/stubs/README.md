Compile-time stand-ins for the stock classes of the Chinese AU57x interface
(MHI2_CN, Asia navigation) that ClusterMapNavAsiaZoom.jar calls or implements,
with only the members it uses and no stock code. They are never packaged: on
the unit the real classes in lsd.jxe are used. `tests/navasiazoom_check.sh`
checks every call, and the replaced class's shape and bytecode, against a
converted stock lsd.jar.
