import java.nio.file.Files;
import java.nio.file.Path;

/**
 * Rewrites one class file as a Java 1.2 one (version 46) with no
 * StackMapTable attributes, which javac 9+ always writes and the AU57x J9
 * did not take (java/wheelzoom/build.sh). Bytecode is unchanged; only the
 * frames go and the version changes.
 *
 *   java --add-exports java.base/jdk.internal.org.objectweb.asm=ALL-UNNAMED tools/StripFrames.java <file.class>
 */
public final class StripFrames {
    public static void main(String[] args) throws Exception {
        Path p = Path.of(args[0]);
        jdk.internal.org.objectweb.asm.ClassReader r = new jdk.internal.org.objectweb.asm.ClassReader(Files.readAllBytes(p));
        jdk.internal.org.objectweb.asm.ClassWriter w = new jdk.internal.org.objectweb.asm.ClassWriter(0);
        r.accept(new jdk.internal.org.objectweb.asm.ClassVisitor(jdk.internal.org.objectweb.asm.Opcodes.ASM9, w) {
            @Override
            public void visit(int version, int access, String name, String sig, String sup, String[] ifs) {
                super.visit(jdk.internal.org.objectweb.asm.Opcodes.V1_2, access, name, sig, sup, ifs);
            }
        }, jdk.internal.org.objectweb.asm.ClassReader.SKIP_FRAMES);
        Files.write(p, w.toByteArray());
    }
}
