package kr.geumyi.statusagent;

import java.io.*;
import java.net.InetSocketAddress;
import java.net.Socket;
import java.nio.charset.StandardCharsets;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

final class MinecraftPing {
    private static final Pattern ONLINE = Pattern.compile("\\\"online\\\"\\s*:\\s*(\\d+)");
    private static final Pattern MAX = Pattern.compile("\\\"max\\\"\\s*:\\s*(\\d+)");
    private static final Pattern VERSION = Pattern.compile("\\\"version\\\"\\s*:\\s*\\{[^}]*\\\"name\\\"\\s*:\\s*\\\"([^\\\"]*)\\\"");

    record Result(boolean reachable, int online, int max, String version, long latencyMs) {}

    static Result ping(String host, int port, int timeoutMs) {
        if (port <= 0) return new Result(false, 0, 0, "", -1);
        long start = System.nanoTime();
        try (Socket socket = new Socket()) {
            socket.connect(new InetSocketAddress(host, port), timeoutMs);
            socket.setSoTimeout(timeoutMs);
            DataInputStream in = new DataInputStream(new BufferedInputStream(socket.getInputStream()));
            OutputStream rawOut = socket.getOutputStream();

            ByteArrayOutputStream handshake = new ByteArrayOutputStream();
            writeVarInt(handshake, 0x00);
            writeVarInt(handshake, 0);
            writeString(handshake, host);
            handshake.write((port >>> 8) & 0xFF);
            handshake.write(port & 0xFF);
            writeVarInt(handshake, 1);
            writePacket(rawOut, handshake.toByteArray());

            writePacket(rawOut, new byte[]{0x00});
            readVarInt(in);
            int packetId = readVarInt(in);
            if (packetId != 0x00) throw new IOException("unexpected packet id " + packetId);
            int len = readVarInt(in);
            if (len < 0 || len > 1_000_000) throw new IOException("invalid json length");
            byte[] bytes = in.readNBytes(len);
            if (bytes.length != len) throw new EOFException();
            String json = new String(bytes, StandardCharsets.UTF_8);
            int online = matchInt(ONLINE, json);
            int max = matchInt(MAX, json);
            String ver = match(VERSION, json);
            long latency = (System.nanoTime() - start) / 1_000_000L;
            return new Result(true, online, max, ver, latency);
        } catch (Throwable t) {
            return new Result(false, 0, 0, "", -1);
        }
    }

    private static int matchInt(Pattern p, String s) {
        Matcher m = p.matcher(s); return m.find() ? Integer.parseInt(m.group(1)) : 0;
    }
    private static String match(Pattern p, String s) {
        Matcher m = p.matcher(s); return m.find() ? m.group(1) : "";
    }

    private static void writePacket(OutputStream out, byte[] payload) throws IOException {
        ByteArrayOutputStream frame = new ByteArrayOutputStream();
        writeVarInt(frame, payload.length);
        frame.write(payload);
        out.write(frame.toByteArray());
        out.flush();
    }

    private static void writeString(OutputStream out, String s) throws IOException {
        byte[] b = s.getBytes(StandardCharsets.UTF_8);
        writeVarInt(out, b.length); out.write(b);
    }

    private static void writeVarInt(OutputStream out, int value) throws IOException {
        do {
            int temp = value & 0b01111111;
            value >>>= 7;
            if (value != 0) temp |= 0b10000000;
            out.write(temp);
        } while (value != 0);
    }

    private static int readVarInt(InputStream in) throws IOException {
        int numRead = 0, result = 0, read;
        do {
            read = in.read();
            if (read == -1) throw new EOFException();
            int value = read & 0b01111111;
            result |= value << (7 * numRead);
            if (++numRead > 5) throw new IOException("VarInt too big");
        } while ((read & 0b10000000) != 0);
        return result;
    }
}
