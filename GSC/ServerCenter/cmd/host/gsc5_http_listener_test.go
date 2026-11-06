package main

import "testing"

// Keep remote-enabled mobile compatibility while ensuring a disabled
// mobile gate cannot expose an otherwise unnecessary wildcard listener.
func TestGSC5HostHTTPListenAddressRespectsMobileGate(t *testing.T) {
	cases := []struct {
		name string
		config Config
		want string
	}{
		{
			name: "remote-disabled-default-bind",
			config: Config{Port: 18787, Bind: "127.0.0.1", MobileEnabled: false},
			want: "127.0.0.1:18787",
		},
		{
			name: "remote-disabled-even-with-legacy-wildcard",
			config: Config{Port: 18787, Bind: "0.0.0.0", MobileEnabled: false},
			want: "127.0.0.1:18787",
		},
		{
			name: "remote-enabled-legacy-GSCM-compatible",
			config: Config{Port: 8787, Bind: "127.0.0.1", MobileEnabled: true},
			want: "0.0.0.0:8787",
		},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			if got := gsc5HostHTTPListenAddress(tc.config); got != tc.want {
				t.Fatalf("listen address=%q, want %q", got, tc.want)
			}
		})
	}
}
