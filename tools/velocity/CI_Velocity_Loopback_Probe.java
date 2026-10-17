// CI-ONLY disposable TCP/RakNet endpoint probe. No login, player actions,
// credentials, config edits, remote addresses or production server access.
// Must run INSIDE the network-namespace of the ephemeral no-network Docker
// Velocity container. Only loopback destinations with fixed ports are allowed.
import java.io.DataInputStream;
import java.io.DataOutputStream;
import java.net.DatagramPacket;
import java.net.DatagramSocket;
import java.net.InetAddress;
import java.net.InetSocketAddress;
import java.net.Socket;
import java.nio.ByteBuffer;
import java.nio.ByteOrder;
import java.nio.charset.StandardCharsets;
import java.security.SecureRandom;

public final class CI_Velocity_Loopback_Probe {
    private static final byte[] MAGIC = new byte[]{
        0x00, (byte)0xff, (byte)0xff, 0x00, (byte)0xfe, (byte)0xfe,
        (byte)0xfe, (byte)0xfe, (byte)0xfd, (byte)0xfd,
        (byte)0xfd, (byte)0xfd, 0x12, 0x34, 0x56, 0x78
    };
    private static final int JAVA_PORT = 25577; // isolated stock Velocity default
    private static final int BEDROCK_PORT = 19132; // isolated Geyser default

    private CI_Velocity_Loopback_Probe() {}

    private static void writeVarInt(DataOutputStream out, int value) throws Exception {
        while ((value & 0xffffff80) != 0) {
            out.writeByte((value & 0x7f) | 0x80);
            value >>>= 7;
        }
        out.writeByte(value);
    }

    private static int readVarInt(DataInputStream in) throws Exception {
        int value = 0;
        for (int i = 0; i < 5; i++) {
            int b = in.readUnsignedByte();
            value |= (b & 0x7f) << (i * 7);
            if ((b & 0x80) == 0) return value;
        }
        throw new IllegalStateException("malformed Java status VarInt");
    }

    private static void javaStatus(InetAddress local) throws Exception {
        try (Socket socket = new Socket()) {
            socket.connect(new InetSocketAddress(local, JAVA_PORT), 2000);
            socket.setSoTimeout(2500);
            DataOutputStream out = new DataOutputStream(socket.getOutputStream());
            // Minecraft Java HANDSHAKING -> STATUS, no LOGIN packet.
            // Handshake: packet id 0, protocol 767, host 127.0.0.1,
            // default isolated proxy port 25577, next state=1 (STATUS).
            byte[] host = "127.0.0.1".getBytes(StandardCharsets.US_ASCII);
            java.io.ByteArrayOutputStream packetBytes = new java.io.ByteArrayOutputStream();
            DataOutputStream packet = new DataOutputStream(packetBytes);
            writeVarInt(packet, 0);    // packet ID
            writeVarInt(packet, 767);  // protocol used only for status query
            writeVarInt(packet, host.length);
            packet.write(host);
            packet.writeShort(JAVA_PORT);
            writeVarInt(packet, 1);    // STATUS
            packet.flush();
            byte[] encoded = packetBytes.toByteArray();
            writeVarInt(out, encoded.length);
            out.write(encoded);
            // Java status request (packet id 0).
            writeVarInt(out, 1);
            writeVarInt(out, 0);
            out.flush();
            DataInputStream in = new DataInputStream(socket.getInputStream());
            int frameLen = readVarInt(in);
            if (frameLen < 3 || frameLen > 16384) throw new IllegalStateException("invalid status frame length");
            if (readVarInt(in) != 0) throw new IllegalStateException("not a Java status response");
            int jsonLen = readVarInt(in);
            if (jsonLen < 2 || jsonLen > 15000) throw new IllegalStateException("unexpected Java status body length");
            byte[] reply = new byte[jsonLen];
            in.readFully(reply);
            String text = new String(reply, StandardCharsets.UTF_8);
            if (!text.startsWith("{") || !text.contains("\"version\"")) {
                throw new IllegalStateException("Java status JSON missing version field");
            }
        }
    }

    private static void bedrockRaknetPong(InetAddress local) throws Exception {
        // Offline unconnected ping only (0x01). Never initiate Bedrock login.
        long sent = System.currentTimeMillis();
        ByteBuffer buf = ByteBuffer.allocate(33).order(ByteOrder.BIG_ENDIAN);
        buf.put((byte) 0x01);
        buf.putLong(sent);
        buf.put(MAGIC);
        buf.putLong(new SecureRandom().nextLong());
        byte[] ping = buf.array();
        try (DatagramSocket socket = new DatagramSocket(new InetSocketAddress(local, 0))) {
            socket.setSoTimeout(3000);
            socket.send(new DatagramPacket(ping, ping.length, local, BEDROCK_PORT));
            byte[] response = new byte[2048];
            DatagramPacket received = new DatagramPacket(response, response.length);
            socket.receive(received);
            if (received.getLength() < 35 || response[0] != 0x1c) {
                throw new IllegalStateException("not a RakNet unconnected pong");
            }
            long echo = ByteBuffer.wrap(response, 1, 8).order(ByteOrder.BIG_ENDIAN).getLong();
            if (echo != sent) throw new IllegalStateException("RakNet ping nonce not echoed");
            for (int i=0;i<MAGIC.length;i++) {
                // 0x1c + echo time (8) + server GUID (8) = magic starts at 17.
                if (response[17+i] != MAGIC[i]) {
                    throw new IllegalStateException("RakNet magic mismatch");
                }
            }
        }
    }

    public static void main(String[] args) throws Exception {
        if (args.length != 0) throw new IllegalArgumentException("No override arguments permitted");
        InetAddress loopback = InetAddress.getByName("127.0.0.1");
        javaStatus(loopback);
        System.out.println("DISPOSABLE_JAVA_STATUS_RESPONSE=PASS");
        bedrockRaknetPong(loopback);
        System.out.println("DISPOSABLE_BEDROCK_RAKNET_PONG=PASS");
        System.out.println("NO_CLIENT_LOGIN_OR_LOBBY_TRANSFER_VERIFIED");
    }
}
