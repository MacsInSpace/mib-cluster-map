import java.io.ByteArrayInputStream;
import java.io.DataInputStream;
import java.io.File;
import java.io.IOException;
import java.io.InputStream;
import java.lang.reflect.Modifier;
import java.net.URL;
import java.net.URLClassLoader;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.TreeSet;
import java.util.zip.ZipEntry;
import java.util.zip.ZipFile;

/**
 * Checks ClusterMapWheelZoom.jar against a unit's converted stock lsd.jar
 * before it goes anywhere near a car: a class that does not fit the stock
 * code that calls it stops the centre screen's navigation.
 *
 *   java -Xverify:all --add-exports java.base/jdk.internal.org.objectweb.asm=ALL-UNNAMED \
 *       tools/WheelZoomCheck.java build/ClusterMapWheelZoom.jar <lsd.jar>
 *
 * (tests/wheelzoom_check.sh runs it.)
 *
 * 1. The replacement timer has the stock class's access flags, superclass,
 *    interfaces, and every stock constructor and method (name, descriptor,
 *    static), each at least as accessible as the stock one; anything extra
 *    is private.
 * 2. Every class, method and field the jar's classes use exists in the stock
 *    jar or the JDK, with the right kind (class or interface method), and is
 *    public, so the jar does not depend on J9 counting its classes as part
 *    of lsd.jxe's package.
 * 3. Both classes load and pass HotSpot's bytecode verifier.
 *
 * Stock classes are read from their class files, never linked: the converted
 * jar (jxe2jar) leaves bytes HotSpot's verifier refuses but J9 never sees --
 * code on abstract interface methods, max_locals of 0, padding after return.
 * For step 3 the loader drops that code and recomputes the sizes of the stock
 * classes it has to load, and nothing else.
 */
public final class WheelZoomCheck {
    static final String TIMER = "de/audi/tghu/navi/app/map/CtxShown$ZoomUpdateDelayTimer";
    static final String BRIDGE = "local/clustermap/WheelZoom";
    static final int ACC_PUBLIC = 0x1, ACC_PRIVATE = 0x2, ACC_PROTECTED = 0x4, ACC_STATIC = 0x8,
        ACC_FINAL = 0x10, ACC_NATIVE = 0x100, ACC_INTERFACE = 0x200, ACC_ABSTRACT = 0x400;
    static int failures;

    /* What a class file says about itself, and its member references. */
    static final class Info {
        String name, superName, source = "jdk";
        List<String> classRefs = new ArrayList<>();
        int access, major;
        List<String> interfaces = new ArrayList<>();
        Map<String, Integer> methods = new HashMap<>(), fields = new HashMap<>();
        List<String[]> refs = new ArrayList<>();  // {kind, owner, name, descriptor}
    }

    static final Map<String, Info> cache = new HashMap<>();
    static ZipFile oursJar, stockJar;

    public static void main(String[] args) throws Exception {
        if (args.length != 2) {
            System.err.println("usage: java -Xverify:all tools/WheelZoomCheck.java <ClusterMapWheelZoom.jar> <stock lsd.jar>");
            System.exit(2);
        }
        oursJar = new ZipFile(args[0]);
        stockJar = new ZipFile(args[1]);

        Info stockTimer = read(stockJar, TIMER), ourTimer = read(oursJar, TIMER);
        if (stockTimer == null) { fail("the stock jar has no " + TIMER + ": not this HMI build"); finish(); }
        if (ourTimer == null) { fail("the wheel-zoom jar has no " + TIMER); finish(); }
        compare(stockTimer, ourTimer);
        for (String c : new String[] {TIMER, BRIDGE}) {
            Info i = read(oursJar, c);
            if (i == null) { fail("the wheel-zoom jar has no " + c); continue; }
            i.source = "ours";
            if (i.major != 46) fail(c + ": class version " + i.major + "; the AU57x unit's other patches use 46");
            else ok(c + ": class version 46");
            checkRefs(i);
        }
        verify(args[0], args[1]);
        finish();
    }

    static void finish() {
        System.out.println(failures == 0 ? "WHEELZOOM_CHECK_OK" : "WHEELZOOM_CHECK_FAILED (" + failures + ")");
        System.exit(failures == 0 ? 0 : 1);
    }

    static void ok(String s) { System.out.println("ok    " + s); }
    static void fail(String s) { System.out.println("FAIL  " + s); failures++; }

    /* ---- class files -------------------------------------------------- */

    static Info read(ZipFile jar, String name) throws IOException {
        ZipEntry e = jar.getEntry(name + ".class");
        if (e == null) return null;
        try (InputStream in = jar.getInputStream(e)) { return parse(in.readAllBytes()); }
    }

    /* Ours first, then the stock jar, then the JDK: the unit's lookup order. */
    static Info lookup(String name) throws IOException {
        if (cache.containsKey(name)) return cache.get(name);
        Info i = read(oursJar, name);
        if (i != null) i.source = "ours";
        if (i == null && (i = read(stockJar, name)) != null) i.source = "stock";
        if (i == null) {
            try (InputStream in = ClassLoader.getSystemResourceAsStream(name + ".class")) {
                if (in != null) i = parse(in.readAllBytes());
            }
        }
        cache.put(name, i);
        return i;
    }

    static Info parse(byte[] b) throws IOException {
        DataInputStream in = new DataInputStream(new ByteArrayInputStream(b));
        Info info = new Info();
        in.readInt();
        in.readUnsignedShort();
        info.major = in.readUnsignedShort();
        int n = in.readUnsignedShort();
        Object[] pool = new Object[n];
        int[] tags = new int[n];
        for (int i = 1; i < n; i++) {
            int tag = in.readUnsignedByte();
            tags[i] = tag;
            switch (tag) {
                case 1: pool[i] = in.readUTF(); break;
                case 3: case 4: in.readInt(); break;
                case 5: case 6: in.readLong(); i++; break;
                case 7: case 8: case 16: case 19: case 20: pool[i] = new int[] {in.readUnsignedShort()}; break;
                case 9: case 10: case 11: case 12: case 17: case 18:
                    pool[i] = new int[] {in.readUnsignedShort(), in.readUnsignedShort()}; break;
                case 15: in.readUnsignedByte(); in.readUnsignedShort(); break;
                default: throw new IOException("constant tag " + tag);
            }
        }
        info.access = in.readUnsignedShort();
        info.name = className(pool, in.readUnsignedShort());
        int sup = in.readUnsignedShort();
        info.superName = sup == 0 ? null : className(pool, sup);
        for (int k = in.readUnsignedShort(); k > 0; k--) info.interfaces.add(className(pool, in.readUnsignedShort()));
        for (int pass = 0; pass < 2; pass++) {
            for (int k = in.readUnsignedShort(); k > 0; k--) {
                int acc = in.readUnsignedShort();
                String nm = (String) pool[in.readUnsignedShort()], desc = (String) pool[in.readUnsignedShort()];
                (pass == 0 ? info.fields : info.methods).put(nm + ":" + desc, acc);
                for (int a = in.readUnsignedShort(); a > 0; a--) { in.readUnsignedShort(); in.skipBytes(in.readInt()); }
            }
        }
        for (int i = 1; i < n; i++) {
            if (tags[i] == 15 || tags[i] == 16 || tags[i] == 17 || tags[i] == 18)
                fail(info.name + ": a Java 7+ constant (tag " + tags[i] + ") the unit cannot run");
            if (tags[i] == 7) info.classRefs.add(className(pool, i));
            if (tags[i] != 9 && tags[i] != 10 && tags[i] != 11) continue;
            int[] r = (int[]) pool[i], nt = (int[]) pool[r[1]];
            info.refs.add(new String[] {tags[i] == 9 ? "field" : tags[i] == 10 ? "method" : "interface method",
                className(pool, r[0]), (String) pool[nt[0]], (String) pool[nt[1]]});
        }
        return info;
    }

    static String className(Object[] pool, int index) { return (String) pool[((int[]) pool[index])[0]]; }

    /* ---- 1: the same shape as the stock class ------------------------- */

    static String flags(int a) {
        return ((a & ACC_STATIC) != 0 ? "static " : "")
            + ((a & ACC_PUBLIC) != 0 ? "public" : (a & ACC_PROTECTED) != 0 ? "protected" : (a & ACC_PRIVATE) != 0 ? "private" : "package");
    }

    static void compare(Info stock, Info ours) {
        int mask = ACC_PUBLIC | ACC_FINAL | ACC_INTERFACE | ACC_ABSTRACT;
        if ((stock.access & mask) != (ours.access & mask))
            fail("class flags: stock 0x" + Integer.toHexString(stock.access & mask) + ", ours 0x" + Integer.toHexString(ours.access & mask));
        else ok("class flags " + Modifier.toString(ours.access & mask));
        if (!String.valueOf(stock.superName).equals(String.valueOf(ours.superName)))
            fail("superclass: stock " + stock.superName + ", ours " + ours.superName);
        else ok("superclass " + ours.superName);
        if (!new TreeSet<>(stock.interfaces).equals(new TreeSet<>(ours.interfaces)))
            fail("interfaces: stock " + stock.interfaces + ", ours " + ours.interfaces);
        else ok("interfaces " + ours.interfaces);
        int good = 0;
        for (Map.Entry<String, Integer> m : stock.methods.entrySet()) {
            Integer a = ours.methods.get(m.getKey());
            int sa = m.getValue();
            if (a == null) { fail("stock method missing: " + m.getKey() + " " + flags(sa)); continue; }
            if ((a & ACC_STATIC) != (sa & ACC_STATIC)) { fail("static differs: " + m.getKey()); continue; }
            if (rank(a) < rank(sa)) { fail("less accessible than stock: " + m.getKey() + " " + flags(a) + " < " + flags(sa)); continue; }
            good++;
        }
        for (Map.Entry<String, Integer> m : ours.methods.entrySet())
            if (!stock.methods.containsKey(m.getKey()) && !m.getKey().startsWith("<clinit>") && (m.getValue() & ACC_PRIVATE) == 0)
                fail("extra method that is not private: " + m.getKey());
        if (good == stock.methods.size()) ok("all " + good + " stock constructors and methods present, none less accessible");
    }

    static int rank(int a) {
        return (a & ACC_PUBLIC) != 0 ? 3 : (a & ACC_PROTECTED) != 0 ? 2 : (a & ACC_PRIVATE) != 0 ? 0 : 1;
    }

    /* ---- 2: every reference resolves ---------------------------------- */

    static void checkRefs(Info self) throws IOException {
        int good = 0;
        for (String cn : self.classRefs) {
            String base = cn.replaceAll("^\\[+L?|;$", "");
            if (base.length() <= 1 || cn.matches("^\\[+[ZBCSIJFD]$")) continue;
            Info c = lookup(base);
            if (c == null) fail(self.name + " -> class " + base + ": not found");
            else if (!c.source.equals("ours") && (c.access & ACC_PUBLIC) == 0) fail(self.name + " -> class " + base + ": not public");
        }
        for (String[] r : self.refs) {
            String kind = r[0], owner = r[1], what = owner + "." + r[2] + r[3];
            Info c = lookup(owner);
            if (c == null) { fail(self.name + " -> " + what + ": class not found"); continue; }
            boolean iface = (c.access & ACC_INTERFACE) != 0;
            if (kind.equals("method") && iface) { fail(what + ": called as a class method, but " + owner + " is an interface"); continue; }
            if (kind.equals("interface method") && !iface) { fail(what + ": called as an interface method, but " + owner + " is a class"); continue; }
            Object[] found = kind.equals("field") ? findField(c, r[2] + ":" + r[3]) : findMethod(c, r[2] + ":" + r[3], r[2].equals("<init>"));
            if (found == null) { fail(self.name + " -> " + what + ": not in " + owner + " or its supertypes"); continue; }
            String why = access(self, (Info) found[0], (Integer) found[1]);
            if (why != null) { fail(self.name + " -> " + what + ": " + why); continue; }
            good++;
        }
        ok(self.name + ": all " + good + " references resolve in the stock jar or the JDK");
    }

    static Object[] findMethod(Info c, String key, boolean constructor) throws IOException {
        for (Info k = c; k != null; k = k.superName == null ? null : lookup(k.superName)) {
            Integer a = k.methods.get(key);
            if (a != null) return new Object[] {k, a};
            if (constructor) return null;
            for (String i : k.interfaces) {
                Info ii = lookup(i);
                Object[] r = ii == null ? null : findMethod(ii, key, false);
                if (r != null) return r;
            }
        }
        return null;
    }

    static Object[] findField(Info c, String key) throws IOException {
        for (Info k = c; k != null; k = k.superName == null ? null : lookup(k.superName)) {
            Integer a = k.fields.get(key);
            if (a != null) return new Object[] {k, a};
        }
        return null;
    }

    static String pkg(String name) { int i = name.lastIndexOf('/'); return i < 0 ? "" : name.substring(0, i); }

    static String access(Info caller, Info owner, int acc) {
        if (caller.name.equals(owner.name)) return null;
        // Same package only within one jar: see 2. above.
        boolean samePackage = pkg(caller.name).equals(pkg(owner.name)) && caller.source.equals(owner.source);
        if ((owner.access & ACC_PUBLIC) == 0 && !samePackage) return owner.name + " is not public";
        if ((acc & ACC_PRIVATE) != 0) return "private in " + owner.name;
        if ((acc & ACC_PUBLIC) != 0 || samePackage) return null;
        return ((acc & ACC_PROTECTED) != 0 ? "protected" : "package-private") + " in another package";
    }

    /* ---- 3: our classes verify ---------------------------------------- */

    static void verify(String ours, String stock) throws Exception {
        ClassLoader loader = new RepairingLoader(new URL[] {new File(ours).toURI().toURL(), new File(stock).toURI().toURL()},
            ClassLoader.getPlatformClassLoader());
        for (String c : new String[] {TIMER, BRIDGE}) {
            String name = c.replace('/', '.');
            try {
                // Initialising links the class, which runs the verifier on it.
                // Neither class has a static initialiser that does anything.
                Class.forName(name, true, loader);
                ok(name + " loads and passes verification");
            } catch (Throwable t) {
                fail(name + " does not load or verify: " + t);
            }
        }
    }

    static final class RepairingLoader extends URLClassLoader {
        RepairingLoader(URL[] urls, ClassLoader parent) { super(urls, parent); }

        @Override
        protected Class<?> findClass(String name) throws ClassNotFoundException {
            String path = name.replace('.', '/');
            URL u = findResource(path + ".class");
            if (u == null) throw new ClassNotFoundException(name);
            byte[] b;
            try (InputStream in = u.openStream()) { b = in.readAllBytes(); }
            catch (IOException e) { throw new ClassNotFoundException(name, e); }
            if (!path.equals(TIMER) && !path.equals(BRIDGE)) b = repair(b);
            return defineClass(name, b, 0, b.length);
        }
    }

    /* A stock class as HotSpot will load it: no code on abstract or native
     * methods, stack and locals sizes recomputed. Only types our classes
     * refer to are loaded, and none of them is run. */
    static byte[] repair(byte[] b) {
        jdk.internal.org.objectweb.asm.ClassReader r = new jdk.internal.org.objectweb.asm.ClassReader(b);
        jdk.internal.org.objectweb.asm.ClassWriter w =
            new jdk.internal.org.objectweb.asm.ClassWriter(jdk.internal.org.objectweb.asm.ClassWriter.COMPUTE_MAXS);
        r.accept(new jdk.internal.org.objectweb.asm.ClassVisitor(jdk.internal.org.objectweb.asm.Opcodes.ASM9, w) {
            @Override
            public jdk.internal.org.objectweb.asm.MethodVisitor visitMethod(int acc, String n, String d, String sig, String[] ex) {
                jdk.internal.org.objectweb.asm.MethodVisitor mv = super.visitMethod(acc, n, d, sig, ex);
                if ((acc & (ACC_ABSTRACT | ACC_NATIVE)) != 0) { mv.visitEnd(); return null; }
                return mv;
            }
        }, 0);
        return w.toByteArray();
    }
}
