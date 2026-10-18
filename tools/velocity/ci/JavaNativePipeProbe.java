import java.io.IOException;
import java.io.RandomAccessFile;

/**
 * Dedicated CI-only Java 25 Windows named-pipe feasibility probe.
 * NOT a Velocity plugin, not packaged in an operator release and never
 * connects to Minecraft. The CI script creates one random test-local pipe.
 */
public final class JavaNativePipeProbe {
    private JavaNativePipeProbe() { }

    public static void main(String[] args) throws IOException {
        if (args.length != 1 || !args[0].matches("GSC452-CI-PIPE-[0-9a-f]{24}")) {
            throw new IllegalArgumentException("CI pipe name must be random and explicitly scoped");
        }
        String endpoint = "\\\\.\\pipe\\" + args[0];
        try (RandomAccessFile pipe = new RandomAccessFile(endpoint, "rw")) {
            int received = pipe.readUnsignedByte();
            if (received != 0x41) {
                throw new IOException("unexpected fixture server challenge");
            }
            pipe.writeByte(0x42);
        }
        System.out.println("GSC452_WINDOWS_JAVA_NATIVE_PIPE_BYTE_EXCHANGE_PASS");
    }
}
