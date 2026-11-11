Compile-time stand-ins for the stock classes the wheel-zoom jar calls, with
only the members it uses and no stock code. They are never packaged: on the
unit the real classes in lsd.jxe are used. `tools/WheelZoomCheck.java` checks
every call against a converted stock lsd.jar.
