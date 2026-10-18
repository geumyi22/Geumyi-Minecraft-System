package kr.geumyi.velocitybridge;

import static org.junit.jupiter.api.Assertions.*;

import java.io.ByteArrayInputStream;
import java.io.ByteArrayOutputStream;
import java.io.DataInputStream;
import java.io.DataOutputStream;
import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.time.Instant;
import java.util.Arrays;
import org.junit.jupiter.api.Test;

/** Offline fixtures only: no runtime transport, task or Velocity events. */
final class StatusOnlyWireTest {
    private static final Instant NOW = Instant.ofEpochSecond(1792267200);
    private static final String GEN = "parent-100-child-101";
    private static byte[] key() {
        byte[] key = new byte[32];
        for (int i=0; i<key.length; i++) key[i]=(byte)i;
        return key;
    }

    private static String valid() {
        return "{\"target\":\"wild\",\"operation\":\"status\","
            + "\"generation\":\"" + GEN + "\","
            + "\"nonce\":\"" + "A".repeat(32) + "\","
            + "\"issued_unix\":1792267200,\"expires_unix\":1792267220}";
    }

    private static byte[] frame(String body) throws IOException {
        ByteArrayOutputStream buffer = new ByteArrayOutputStream();
        try (DataOutputStream writer = new DataOutputStream(buffer)) {
            byte[] raw = body.getBytes(StandardCharsets.US_ASCII);
            writer.writeInt(raw.length);
            writer.write(raw);
        }
        return buffer.toByteArray();
    }

    private static String respond(byte[] request, String target, String gen,
                                  Instant now) throws IOException {
        var input = new DataInputStream(new ByteArrayInputStream(request));
        var output = new ByteArrayOutputStream();
        var writer = new DataOutputStream(output);
        StatusOnlyWire.respond(input,writer,key(),target,gen,now);
        var reader = new DataInputStream(new ByteArrayInputStream(output.toByteArray()));
        int length = reader.readInt();
        assertTrue(length > 0 && length <= 2048);
        byte[] body = new byte[length];
        reader.readFully(body);
        assertEquals(-1,reader.read());
        return new String(body,StandardCharsets.US_ASCII);
    }

    @Test
    void goOrderedChallengeProducesGoCompatibleStatusOnlyEnvelope() throws Exception {
        String response = respond(frame(valid()),"wild",GEN,NOW);
        assertEquals(
            "{\"version\":1,\"target\":\"wild\",\"operation\":\"status\","
            + "\"generation\":\"parent-100-child-101\","
            + "\"nonce\":\"" + "A".repeat(32) + "\","
            + "\"issued_unix\":1792267200,\"expires_unix\":1792267220,"
            + "\"mac\":\"1488217fd43660a2e0810dc60caf3f93d89d4ba4bb9b4920967f42d31fff70c5\"}",
            response);
    }

    @Test
    void noOtherOperationOrForgedJsonCanBeAnswered() {
        String original = valid();
        String[] rejected = {
            original.replace("\"status\"", "\"prepare_shutdown\""),
            original.replace("\"status\"", "\"confirm_shutdown\""),
            original.replace("\"issued_unix\":1792267200", "\"issued_unix\":0"),
            original.replace("\"expires_unix\":1792267220", "\"expires_unix\":1792267221"),
            original.replace("\"expires_unix\":1792267220", "\"expires_unix\":1792267200"),
            original.replace("\"nonce\":\"", "\"nonce\":\"!"),
            original.replace("\"nonce\":\"", "\"nonce\":\"AA\" , \"nonce\":\""),
            original.replace("}", ",\"command\":\"shutdown\"}"),
            original+"{}",
            original.replace("\"target\":\"wild\",",""),
            original.replace("\"target\"", "\"other_key\""),
            original.replace("\"target\":\"wild\"","\"target\":\"wi\\u006cd\""),
            original.replace("\"target\":\"wild\",", "\"operation\":\"status\",\"target\":\"wild\","),
            original.replace("\"issued_unix\":1792267200", "\"issued_unix\":1792267300"),
            original.replace("\"expires_unix\":1792267220", "\"expires_unix\":1792267199"),
        };
        for (String body : rejected) {
            assertThrows(IOException.class,
                () -> StatusOnlyWire.parseChallenge(
                    body.getBytes(StandardCharsets.US_ASCII),NOW),
                "bad challenge accepted: "+body);
        }
    }

    @Test
    void mismatchedProxyOrGenerationNeverProducesSignedResponse() throws Exception {
        assertThrows(IOException.class,
            ()->respond(frame(valid()),"other",GEN,NOW));
        assertThrows(IOException.class,
            ()->respond(frame(valid()),"wild","other-generation-1",NOW));
        assertThrows(IOException.class,
            ()->respond(frame(valid()),"wild",GEN,NOW.plusSeconds(21)));
    }

    @Test
    void boundedFramesAndBrokenInputAreRejected() throws Exception {
        byte[] good=frame(valid());
        byte[] tooBig=new byte[]{0,0,8,1}; // 2049
        byte[] zero=new byte[]{0,0,0,0};
        byte[] truncated=Arrays.copyOf(good,good.length-2);
        for(byte[] bad : new byte[][]{tooBig,zero,truncated,new byte[]{0,0,0}}){
            assertThrows(IOException.class,
                ()->respond(bad,"wild",GEN,NOW));
        }
        assertThrows(IOException.class,
            ()->StatusOnlyWire.parseChallenge(
                new byte[2049],NOW));
        byte[] nonASCII=valid().getBytes(StandardCharsets.US_ASCII);
        nonASCII[5]=(byte)0xff;
        assertThrows(IOException.class,
            ()->StatusOnlyWire.parseChallenge(nonASCII,NOW));
    }

    @Test
    void malformedCredentialsAndNullStreamFailClosed() throws Exception {
        byte[] request=frame(valid());
        assertThrows(IOException.class,
            ()->StatusOnlyWire.respond(
                new DataInputStream(new ByteArrayInputStream(request)),
                new DataOutputStream(new ByteArrayOutputStream()),new byte[8],
                "wild",GEN,NOW));
        assertThrows(IOException.class,
            ()->StatusOnlyWire.respond(null,
                new DataOutputStream(new ByteArrayOutputStream()),key(),
                "wild",GEN,NOW));
        assertThrows(IOException.class,
            ()->StatusOnlyWire.respond(
                new DataInputStream(new ByteArrayInputStream(request)),null,key(),
                "wild",GEN,NOW));
    }
}
