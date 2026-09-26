package kr.geumyi.discordstatus;

import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.StandardOpenOption;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.ThreadFactory;

final class AsyncFileLog implements AutoCloseable {
    private final GeumyiDiscordStatus plugin;
    private final ExecutorService io;

    AsyncFileLog(GeumyiDiscordStatus plugin) {
        this.plugin = plugin;
        ThreadFactory tf = r -> {
            Thread t = new Thread(r, "GDS-IO");
            t.setDaemon(true);
            return t;
        };
        this.io = Executors.newSingleThreadExecutor(tf);
    }

    void append(Path file, String text) {
        if (text == null || text.isEmpty()) return;
        io.execute(() -> {
            try {
                Path parent = file.getParent();
                if (parent != null) Files.createDirectories(parent);
                Files.writeString(file, text, StandardCharsets.UTF_8,
                        StandardOpenOption.CREATE, StandardOpenOption.APPEND);
            } catch (IOException e) {
                plugin.debug("file log failed: " + e.getMessage());
            }
        });
    }

    void appendWithHeader(Path file, String header, String text) {
        if ((header == null || header.isEmpty()) && (text == null || text.isEmpty())) return;
        io.execute(() -> {
            try {
                Path parent = file.getParent();
                if (parent != null) Files.createDirectories(parent);
                boolean needsHeader = !Files.exists(file) || Files.size(file) == 0L;
                StringBuilder data = new StringBuilder();
                if (needsHeader && header != null) data.append(header);
                if (text != null) data.append(text);
                if (!data.isEmpty()) Files.writeString(file, data.toString(), StandardCharsets.UTF_8,
                        StandardOpenOption.CREATE, StandardOpenOption.APPEND);
            } catch (IOException e) {
                plugin.debug("file log failed: " + e.getMessage());
            }
        });
    }

    @Override public void close() { io.shutdown(); }
}
