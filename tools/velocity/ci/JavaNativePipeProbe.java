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
            // The exact 4-byte big-endian length prefix used by the Go
            // velocitybridge/frame.go transport, WITHOUT live JSON commands.
            final byte[] expected = "GSC452-CI-BOUND-FRAME-V1"
                .getBytes(java.nio.charset.StandardCharsets.US_ASCII);
            final int length = pipe.readInt();
            if (length != expected.length || length <= 0 || length > 2048) {
                throw new IOException("CI native pipe request length was out of bounds");
            }
            byte[] frame = new byte[length];
            pipe.readFully(frame);
            if (!java.security.MessageDigest.isEqual(frame, expected)) {
                throw new IOException("CI native pipe payload mismatch");
            }
            byte[] response = "GSC452-CI-JAVA-FRAME-PASS"
                .getBytes(java.nio.charset.StandardCharsets.US_ASCII);
            pipe.writeInt(response.length);
            pipe.write(response);
        }
        System.out.println("GSC452_WINDOWS_JAVA_NATIVE_PIPE_BYTE_EXCHANGE_PASS");
    }
}
