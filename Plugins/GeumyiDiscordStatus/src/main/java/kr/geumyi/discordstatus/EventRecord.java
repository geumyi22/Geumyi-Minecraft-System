package kr.geumyi.discordstatus;

record EventRecord(long sequence, long timestamp, String type, String title, String message, String mode) {}
