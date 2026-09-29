package main

import (
	"archive/zip"
	"fmt"
	"os"
	"path/filepath"
	"strings"
)

func day9SelfTestRequested() bool {
	for _, arg := range os.Args[1:] {
		if arg == "--day9-selftest" {
			return true
		}
	}
	return false
}

func day9SelfTestJar(path, name, version string) error {
	if err := os.MkdirAll(filepath.Dir(path), 0755); err != nil {
		return err
	}
	f, err := os.Create(path)
	if err != nil {
		return err
	}
	z := zip.NewWriter(f)
	w, err := z.Create("plugin.yml")
	if err != nil {
		_ = f.Close()
		return err
	}
	if _, err := w.Write([]byte("name: " + name + "\nversion: " + version + "\n")); err != nil {
		_ = z.Close()
		_ = f.Close()
		return err
	}
	if err := z.Close(); err != nil {
		_ = f.Close()
		return err
	}
	return f.Close()
}

func day9SelfTestComponent(path, name, version string) (DeploymentComponent, error) {
	st, err := os.Stat(path)
	if err != nil {
		return DeploymentComponent{}, err
	}
	hash, err := day9FileSHA256(path)
	if err != nil {
		return DeploymentComponent{}, err
	}
	return DeploymentComponent{
		Version: version, Kind: "plugin", PluginName: name,
		File: filepath.Base(path), URL: "https://example.invalid/" + filepath.Base(path),
		SHA256: hash, Size: st.Size(), Targets: []string{"day9-selftest"},
	}, nil
}

func day9SelfTestPlanItem(key, plugin, fromVersion, oldPath string, comp DeploymentComponent) updatePlanItem {
	return updatePlanItem{
		Key: key,
		Component: comp,
		Installed: PluginInventory{
			File: filepath.Base(oldPath), Name: plugin, Version: fromVersion,
			Enabled: true, Managed: true,
		},
	}
}

func day9AssertPlugin(path, wantName, wantVersion string) error {
	name, version := jarPluginInfo(path)
	if name != wantName || version != wantVersion {
		return fmt.Errorf("%s metadata=%q %q want=%q %q", filepath.Base(path), name, version, wantName, wantVersion)
	}
	return nil
}

func runDay9SelfTest() error {
	root, err := os.MkdirTemp("", "Geumyi-Day9-SelfTest-*")
	if err != nil {
		return err
	}
	defer os.RemoveAll(root)
	if err := os.WriteFile(filepath.Join(root, "server.properties"), []byte("server-port=65534\n"), 0644); err != nil {
		return err
	}
	oldTech := filepath.Join(root, "plugins", "GeumyiTechnology-0.1.3.jar")
	oldChem := filepath.Join(root, "plugins", "GeumyiChemistry-0.4.1.jar")
	if err := day9SelfTestJar(oldTech, "GeumyiTechnology", "0.1.3"); err != nil { return err }
	if err := day9SelfTestJar(oldChem, "GeumyiChemistry", "0.4.1"); err != nil { return err }

	cacheDir := filepath.Join(root, "cache")
	newTech := filepath.Join(cacheDir, "GeumyiTechnology-0.1.4.jar")
	newChem := filepath.Join(cacheDir, "GeumyiChemistry-0.4.2.jar")
	if err := day9SelfTestJar(newTech, "GeumyiTechnology", "0.1.4"); err != nil { return err }
	if err := day9SelfTestJar(newChem, "GeumyiChemistry", "0.4.2"); err != nil { return err }
	techComp, err := day9SelfTestComponent(newTech, "GeumyiTechnology", "0.1.4")
	if err != nil { return err }
	chemComp, err := day9SelfTestComponent(newChem, "GeumyiChemistry", "0.4.2")
	if err != nil { return err }

	s := ServerConfig{ID: "day9-selftest", Path: root, JavaPort: 65534}
	plan := []updatePlanItem{
		day9SelfTestPlanItem("technology", "GeumyiTechnology", "0.1.3", oldTech, techComp),
		day9SelfTestPlanItem("chemistry", "GeumyiChemistry", "0.4.1", oldChem, chemComp),
	}
	cache := map[string]string{"technology": newTech, "chemistry": newChem}

	day9UpdateFaultHook = func(point string) error {
		if strings.HasPrefix(point, "after_activate:0:") {
			return fmt.Errorf("day9 self-test injected failure")
		}
		return nil
	}
	_, applyErr := applyUpdateTransaction(s, plan, cache, "canary", "selftest-failure", "selftest")
	day9UpdateFaultHook = nil
	if applyErr == nil {
		return fmt.Errorf("failure injection unexpectedly succeeded")
	}
	if hasPendingUpdate(s) {
		return fmt.Errorf("failure rollback left a pending transaction")
	}
	if err := day9AssertPlugin(oldTech, "GeumyiTechnology", "0.1.3"); err != nil { return err }
	if err := day9AssertPlugin(oldChem, "GeumyiChemistry", "0.4.1"); err != nil { return err }
	if _, err := os.Stat(filepath.Join(root, "plugins", filepath.Base(newTech))); !os.IsNotExist(err) {
		return fmt.Errorf("failed transaction left new Technology enabled: %v", err)
	}
	if _, err := os.Stat(filepath.Join(root, "plugins", filepath.Base(newChem))); !os.IsNotExist(err) {
		return fmt.Errorf("failed transaction left new Chemistry enabled: %v", err)
	}

	tx, err := applyUpdateTransaction(s, plan, cache, "canary", "selftest-pending", "selftest")
	if err != nil {
		return fmt.Errorf("successful transaction setup failed: %w", err)
	}
	if tx.Phase != "applied_pending_health" || !hasPendingUpdate(s) {
		return fmt.Errorf("successful transaction did not enter pending-health state")
	}
	if err := day9AssertPlugin(filepath.Join(root, "plugins", filepath.Base(newTech)), "GeumyiTechnology", "0.1.4"); err != nil { return err }
	if err := day9AssertPlugin(filepath.Join(root, "plugins", filepath.Base(newChem)), "GeumyiChemistry", "0.4.2"); err != nil { return err }

	recovered, err := recoverInterruptedUpdate(s)
	if err != nil {
		return fmt.Errorf("interrupted transaction recovery failed: %w", err)
	}
	if !recovered || hasPendingUpdate(s) {
		return fmt.Errorf("interrupted transaction recovery did not clear pending state")
	}
	if err := day9AssertPlugin(oldTech, "GeumyiTechnology", "0.1.3"); err != nil { return err }
	if err := day9AssertPlugin(oldChem, "GeumyiChemistry", "0.4.1"); err != nil { return err }
	if rejected, _ := rejectedUpdateForRelease(s, "selftest-pending"); !rejected {
		return fmt.Errorf("interrupted applied release was not rejected")
	}

	fmt.Println("DAY9 SELFTEST PASS")
	return nil
}
