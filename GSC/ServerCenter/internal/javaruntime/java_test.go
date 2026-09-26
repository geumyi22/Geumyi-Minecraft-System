package javaruntime

import (
	"strings"
	"testing"
)

func TestJavaHomeComesFromRuntimeNotShimDirectory(t *testing.T) {
	out := "Property settings:\r\n    java.home = C:\\Program Files\\Java\\jdk-26.0.2\r\n    java.version = 26.0.2\r\n"
	r, e := parseProperties(out)
	if e != nil {
		t.Fatal(e)
	}
	if r.Home != `C:\Program Files\Java\jdk-26.0.2` || r.Version != "26.0.2" || strings.Contains(r.Home, "javapath") {
		t.Fatalf("invalid Java home: %+v", r)
	}
	if _, e = parseProperties("java version without settings"); e == nil {
		t.Fatal("missing java.home accepted")
	}
}
