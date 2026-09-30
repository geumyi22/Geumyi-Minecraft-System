package main

import (
	"fmt"
	"os"
	"path/filepath"
	"strings"
)

func day10SelfTestRequested() bool {
	for _, arg := range os.Args[1:] {
		if arg == "--day10-selftest" {
			return true
		}
	}
	return false
}

func day10NewServerRoot(name string) (string, error) {
	root, err := os.MkdirTemp("", "Geumyi-Day10-"+name+"-*")
	if err != nil {
		return "", err
	}
	if err := os.WriteFile(filepath.Join(root, "server.properties"), []byte("server-port=65534\n"), 0644); err != nil {
		_ = os.RemoveAll(root)
		return "", err
	}
	return root, nil
}

func day10PreparePair(root string) ([]updatePlanItem, map[string]string, error) {
	oldTech := filepath.Join(root, "plugins", "GeumyiTechnology-0.1.3.jar")
	oldChem := filepath.Join(root, "plugins", "GeumyiChemistry-0.4.1.jar")
	if err := day9SelfTestJar(oldTech, "GeumyiTechnology", "0.1.3"); err != nil {
		return nil, nil, err
	}
	if err := day9SelfTestJar(oldChem, "GeumyiChemistry", "0.4.1"); err != nil {
		return nil, nil, err
	}

	cacheDir := filepath.Join(root, "day10-cache")
	newTech := filepath.Join(cacheDir, "GeumyiTechnology-0.1.4.jar")
	newChem := filepath.Join(cacheDir, "GeumyiChemistry-0.4.2.jar")
	if err := day9SelfTestJar(newTech, "GeumyiTechnology", "0.1.4"); err != nil {
		return nil, nil, err
	}
	if err := day9SelfTestJar(newChem, "GeumyiChemistry", "0.4.2"); err != nil {
		return nil, nil, err
	}
	techComp, err := day9SelfTestComponent(newTech, "GeumyiTechnology", "0.1.4")
	if err != nil {
		return nil, nil, err
	}
	chemComp, err := day9SelfTestComponent(newChem, "GeumyiChemistry", "0.4.2")
	if err != nil {
		return nil, nil, err
	}
	techComp.Targets = []string{"wild"}
	techComp.ReleaseGroup = "server-core"
	chemComp.Targets = []string{"wild"}
	chemComp.ReleaseGroup = "server-core"
	chemComp.Requires = map[string]string{"technology": ">=0.1.4"}

	plan := []updatePlanItem{
		day9SelfTestPlanItem("technology", "GeumyiTechnology", "0.1.3", oldTech, techComp),
		day9SelfTestPlanItem("chemistry", "GeumyiChemistry", "0.4.1", oldChem, chemComp),
	}
	return plan, map[string]string{"technology": newTech, "chemistry": newChem}, nil
}

func day10AssertVersion(root, file, plugin, version string) error {
	return day9AssertPlugin(filepath.Join(root, "plugins", file), plugin, version)
}

func day10TestHealthyCommit() error {
	root, err := day10NewServerRoot("Healthy")
	if err != nil {
		return err
	}
	defer os.RemoveAll(root)

	plan, cache, err := day10PreparePair(root)
	if err != nil {
		return err
	}
	s := ServerConfig{ID: "wild", Path: root, JavaPort: 65534}
	tx, err := applyUpdateTransaction(s, plan, cache, "canary", "day10-healthy", "day10-healthy-manifest")
	if err != nil {
		return fmt.Errorf("healthy transaction apply failed: %w", err)
	}
	if tx.Phase != "applied_pending_health" || !hasPendingUpdate(s) {
		return fmt.Errorf("healthy transaction did not enter pending health")
	}
	if _, err := markPendingUpdateHealthy(s); err != nil {
		return fmt.Errorf("healthy transaction commit failed: %w", err)
	}
	if hasPendingUpdate(s) {
		return fmt.Errorf("healthy commit left pending transaction")
	}
	if err := day10AssertVersion(root, "GeumyiTechnology-0.1.4.jar", "GeumyiTechnology", "0.1.4"); err != nil {
		return err
	}
	if err := day10AssertVersion(root, "GeumyiChemistry-0.4.2.jar", "GeumyiChemistry", "0.4.2"); err != nil {
		return err
	}
	if _, err := os.Stat(filepath.Join(root, "plugins", "GeumyiTechnology-0.1.3.jar")); !os.IsNotExist(err) {
		return fmt.Errorf("healthy commit left old Technology enabled: %v", err)
	}
	return nil
}

func day10TestCorruptArtifactRejected() error {
	root, err := day10NewServerRoot("Corrupt")
	if err != nil {
		return err
	}
	defer os.RemoveAll(root)

	plan, cache, err := day10PreparePair(root)
	if err != nil {
		return err
	}
	if err := os.WriteFile(cache["technology"], []byte("corrupt-day10-artifact"), 0644); err != nil {
		return err
	}
	s := ServerConfig{ID: "wild", Path: root, JavaPort: 65534}
	if _, err := applyUpdateTransaction(s, plan, cache, "canary", "day10-corrupt", "day10-corrupt-manifest"); err == nil {
		return fmt.Errorf("corrupt artifact unexpectedly applied")
	}
	if hasPendingUpdate(s) {
		return fmt.Errorf("corrupt artifact left pending transaction")
	}
	if err := day10AssertVersion(root, "GeumyiTechnology-0.1.3.jar", "GeumyiTechnology", "0.1.3"); err != nil {
		return err
	}
	if err := day10AssertVersion(root, "GeumyiChemistry-0.4.1.jar", "GeumyiChemistry", "0.4.1"); err != nil {
		return err
	}
	return nil
}

func day10TestCommitFailureRollback() error {
	root, err := day10NewServerRoot("CommitFailure")
	if err != nil {
		return err
	}
	defer os.RemoveAll(root)

	plan, cache, err := day10PreparePair(root)
	if err != nil {
		return err
	}
	s := ServerConfig{ID: "wild", Path: root, JavaPort: 65534}
	day9UpdateFaultHook = func(point string) error {
		if strings.HasPrefix(point, "after_activate:0:") {
			return fmt.Errorf("day10 injected activation failure")
		}
		return nil
	}
	_, applyErr := applyUpdateTransaction(s, plan, cache, "canary", "day10-injected-failure", "day10-failure-manifest")
	day9UpdateFaultHook = nil
	if applyErr == nil {
		return fmt.Errorf("injected activation failure unexpectedly succeeded")
	}
	if hasPendingUpdate(s) {
		return fmt.Errorf("activation rollback left pending transaction")
	}
	if err := day10AssertVersion(root, "GeumyiTechnology-0.1.3.jar", "GeumyiTechnology", "0.1.3"); err != nil {
		return err
	}
	if err := day10AssertVersion(root, "GeumyiChemistry-0.4.1.jar", "GeumyiChemistry", "0.4.1"); err != nil {
		return err
	}
	return nil
}

func day10TestInterruptedRecovery() error {
	root, err := day10NewServerRoot("Interrupted")
	if err != nil {
		return err
	}
	defer os.RemoveAll(root)

	plan, cache, err := day10PreparePair(root)
	if err != nil {
		return err
	}
	s := ServerConfig{ID: "wild", Path: root, JavaPort: 65534}
	if _, err := applyUpdateTransaction(s, plan, cache, "canary", "day10-interrupted", "day10-interrupted-manifest"); err != nil {
		return err
	}
	recovered, err := recoverInterruptedUpdate(s)
	if err != nil {
		return fmt.Errorf("interrupted recovery failed: %w", err)
	}
	if !recovered || hasPendingUpdate(s) {
		return fmt.Errorf("interrupted recovery did not clear pending state")
	}
	if rejected, reason := rejectedUpdateForRelease(s, "day10-interrupted"); !rejected || reason == "" {
		return fmt.Errorf("interrupted release was not rejected")
	}
	if err := day10AssertVersion(root, "GeumyiTechnology-0.1.3.jar", "GeumyiTechnology", "0.1.3"); err != nil {
		return err
	}
	return nil
}

func day10TestHealthFailureRollback() error {
	root, err := day10NewServerRoot("HealthFailure")
	if err != nil {
		return err
	}
	defer os.RemoveAll(root)

	plan, cache, err := day10PreparePair(root)
	if err != nil {
		return err
	}
	s := ServerConfig{ID: "wild", Path: root, JavaPort: 65534}
	if _, err := applyUpdateTransaction(s, plan, cache, "canary", "day10-health-failure", "day10-health-manifest"); err != nil {
		return err
	}
	if _, err := rollbackPendingUpdate(s, "synthetic post-start health failure", true); err != nil {
		return fmt.Errorf("health failure rollback failed: %w", err)
	}
	if hasPendingUpdate(s) {
		return fmt.Errorf("health rollback left pending transaction")
	}
	if rejected, _ := rejectedUpdateForRelease(s, "day10-health-failure"); !rejected {
		return fmt.Errorf("health-failed release was not rejected")
	}
	if err := day10AssertVersion(root, "GeumyiTechnology-0.1.3.jar", "GeumyiTechnology", "0.1.3"); err != nil {
		return err
	}
	if err := day10AssertVersion(root, "GeumyiChemistry-0.4.1.jar", "GeumyiChemistry", "0.4.1"); err != nil {
		return err
	}
	return nil
}

func day10TestTargetIsolation() error {
	root, err := day10NewServerRoot("TargetIsolation")
	if err != nil {
		return err
	}
	defer os.RemoveAll(root)

	oldTech := filepath.Join(root, "plugins", "GeumyiTechnology-0.1.3.jar")
	if err := day9SelfTestJar(oldTech, "GeumyiTechnology", "0.1.3"); err != nil {
		return err
	}
	m := DeploymentManifest{
		Schema: 1,
		Channel: "canary",
		Release: "day10-targets",
		Repository: "geumyi22/Geumyi-Minecraft-System",
		Components: map[string]DeploymentComponent{
			"technology": {
				Version: "0.1.4",
				Kind: "plugin",
				PluginName: "GeumyiTechnology",
				File: "GeumyiTechnology-0.1.4.jar",
				URL: "https://example.invalid/GeumyiTechnology-0.1.4.jar",
				SHA256: strings.Repeat("a", 64),
				Size: 1,
				Targets: []string{"wild"},
			},
		},
	}
	plan, err := buildUpdatePlan(ServerConfig{ID: "playground", Path: root}, m)
	if err != nil {
		return err
	}
	if len(plan) != 0 {
		return fmt.Errorf("Wild-only component leaked into Playground update plan")
	}
	return nil
}

func day10TestUpdateFailureIsFailOpen() error {
	root, err := day10NewServerRoot("FailOpen")
	if err != nil {
		return err
	}
	defer os.RemoveAll(root)

	oldTech := filepath.Join(root, "plugins", "GeumyiTechnology-0.1.3.jar")
	if err := day9SelfTestJar(oldTech, "GeumyiTechnology", "0.1.3"); err != nil {
		return err
	}
	s := ServerConfig{ID: "wild", Path: root, JavaPort: 65534}

	configMu.Lock()
	saved := cfg
	cfg.Update = UpdateConfig{
		Enabled: true,
		Repository: "geumyi22/Geumyi-Minecraft-System",
		Channel: "canary",
		PublicKeyPath: filepath.Join(root, "missing-public-key.pem"),
		TimeoutSeconds: 3,
	}
	configMu.Unlock()
	defer func() {
		configMu.Lock()
		cfg = saved
		configMu.Unlock()
	}()

	st := runPreStartUpdater(s)
	if st.Phase != "error" {
		return fmt.Errorf("verification failure should produce error phase, got %s", st.Phase)
	}
	if st.BlockStart {
		return fmt.Errorf("verification/discovery failure must remain fail-open")
	}
	if err := day10AssertVersion(root, "GeumyiTechnology-0.1.3.jar", "GeumyiTechnology", "0.1.3"); err != nil {
		return err
	}
	return nil
}

func runDay10SelfTest() error {
	tests := []struct {
		name string
		run func() error
	}{
		{"healthy-commit", day10TestHealthyCommit},
		{"corrupt-artifact", day10TestCorruptArtifactRejected},
		{"commit-failure-rollback", day10TestCommitFailureRollback},
		{"interrupted-recovery", day10TestInterruptedRecovery},
		{"health-failure-rollback", day10TestHealthFailureRollback},
		{"target-isolation", day10TestTargetIsolation},
		{"update-failure-fail-open", day10TestUpdateFailureIsFailOpen},
	}
	for _, tc := range tests {
		fmt.Printf("DAY10 SELFTEST %s ... ", tc.name)
		if err := tc.run(); err != nil {
			fmt.Println("FAIL")
			return fmt.Errorf("%s: %w", tc.name, err)
		}
		fmt.Println("PASS")
	}
	fmt.Println("DAY10 SELFTEST PASS")
	return nil
}
