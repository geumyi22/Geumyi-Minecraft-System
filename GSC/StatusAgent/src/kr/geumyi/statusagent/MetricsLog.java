package kr.geumyi.statusagent;

import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.*;
import java.time.*;
import java.util.ArrayList;
import java.util.List;
import java.util.Locale;

final class MetricsLog {
    private final Path dir;
    private final ZoneId zone;
    MetricsLog(Path dir, ZoneId zone) { this.dir = dir; this.zone = zone; }

    synchronized void append(ServerState s) {
        try {
            Files.createDirectories(dir);
            Path file = dir.resolve("metrics-" + LocalDate.now(zone) + ".csv");
            if (!Files.exists(file)) {
                Files.writeString(file, "timestamp,server,state,online,max,tps,mspt,memory,java,bedrock\n", StandardCharsets.UTF_8,
                        StandardOpenOption.CREATE, StandardOpenOption.APPEND);
            }
            String line = System.currentTimeMillis() + "," + csv(s.id) + "," + csv(s.derivedState) + "," + s.online + "," + s.maxPlayers + ","
                    + fmt(s.tps) + "," + fmt(s.mspt) + "," + fmt(s.memory) + "," + s.javaPlayers + "," + s.bedrockPlayers + "\n";
            Files.writeString(file, line, StandardCharsets.UTF_8, StandardOpenOption.CREATE, StandardOpenOption.APPEND);
        } catch (IOException e) { System.err.println("[Agent] metrics 기록 실패: " + e.getMessage()); }
    }

    Summary summarize(LocalDate date, String serverId) {
        Path file = dir.resolve("metrics-" + date + ".csv");
        if (!Files.isRegularFile(file)) return new Summary(0,0,0,0);
        long total = 0, up = 0;
        int peak = 0;
        double tpsSum = 0; int tpsN = 0;
        try {
            List<String> lines = Files.readAllLines(file, StandardCharsets.UTF_8);
            for (int i=1;i<lines.size();i++) {
                String[] p = lines.get(i).split(",", -1);
                if (p.length < 10 || !p[1].equals(serverId)) continue;
                total++;
                String st = p[2];
                boolean online = st.equals("ONLINE") || st.equals("DEGRADED") || st.equals("MAINTENANCE") || st.equals("RESTARTING") || st.equals("PLUGIN_UNREACHABLE");
                if (online) up++;
                try { peak = Math.max(peak, Integer.parseInt(p[3])); } catch (Exception ignored) {}
                try { double t = Double.parseDouble(p[5]); if (online && t > 0) { tpsSum += t; tpsN++; } } catch (Exception ignored) {}
            }
        } catch (IOException ignored) { }
        double uptime = total == 0 ? 0 : (up * 100.0 / total);
        double avg = tpsN == 0 ? 0 : tpsSum / tpsN;
        return new Summary(total, uptime, peak, avg);
    }

    record Summary(long samples, double uptimePercent, int peakPlayers, double avgTps) {}
    private static String csv(String s) { return s == null ? "" : s.replace(",", " ").replace("\n"," "); }
    private static String fmt(double d) { return String.format(Locale.ROOT, "%.2f", d); }
}
