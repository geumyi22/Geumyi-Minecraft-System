package main

import "testing"

func TestDay11GitHubReleaseSortingUsesPublishTime(t *testing.T) {
	releases := []githubRelease{
		{
			TagName:     "system-2026.10.06-day11-canary",
			CreatedAt:   "2026-10-05T16:54:09Z",
			PublishedAt: "2026-10-05T17:07:00Z",
		},
		{
			TagName:     "system-2026.10.06-day11-431-canary",
			CreatedAt:   "2026-10-05T17:19:00Z",
			PublishedAt: "2026-10-05T17:27:35Z",
		},
	}
	sortGitHubReleasesNewestFirst(releases)
	if got := releases[0].TagName; got != "system-2026.10.06-day11-431-canary" {
		t.Fatalf("newest signed release not selected first: %s", got)
	}
}

func TestDay11GitHubReleaseSortingFallsBackToCreatedTime(t *testing.T) {
	releases := []githubRelease{
		{TagName: "old", CreatedAt: "2026-10-05T16:00:00Z"},
		{TagName: "new", CreatedAt: "2026-10-05T17:00:00Z"},
	}
	sortGitHubReleasesNewestFirst(releases)
	if got := releases[0].TagName; got != "new" {
		t.Fatalf("created_at fallback ordering failed: %s", got)
	}
}
