package kr.geumyi.discordstatus;

import java.util.ArrayList;
import java.util.List;
import java.util.concurrent.atomic.AtomicLong;

final class EventBuffer {
    private final int capacity;
    private final EventRecord[] ring;
    private final AtomicLong sequence = new AtomicLong();
    private int size;
    private int next;

    EventBuffer(int capacity) {
        this.capacity = Math.max(32, capacity);
        this.ring = new EventRecord[this.capacity];
    }

    synchronized EventRecord add(long timestamp, String type, String title, String message, String mode) {
        long seq = sequence.incrementAndGet();
        EventRecord record = new EventRecord(seq, timestamp, type, title, message, mode);
        ring[next] = record;
        next = (next + 1) % capacity;
        if (size < capacity) size++;
        return record;
    }

    synchronized List<EventRecord> since(long seqExclusive) {
        List<EventRecord> out = new ArrayList<>();
        int start = (next - size + capacity) % capacity;
        for (int i = 0; i < size; i++) {
            EventRecord r = ring[(start + i) % capacity];
            if (r != null && r.sequence() > seqExclusive) out.add(r);
        }
        return out;
    }

    long latestSequence() {
        return sequence.get();
    }
}
