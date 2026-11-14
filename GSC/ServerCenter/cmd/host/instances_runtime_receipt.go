package main

import (
	"crypto/rand"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"time"
)

type instanceProcessReceipt struct {
	Schema         int    `json:"schema"`
	ID             string `json:"id"`
	Directory      string `json:"directory"`
	Nonce          string `json:"nonce"`
	State          string `json:"state"`
	PID            int    `json:"pid"`
	ProcessCreated string `json:"process_created"`
	RequestedAt    string `json:"requested_at"`
}

func instanceReceiptPath(p ManagedInstance) string {
	return filepath.Join(filepath.Dir(configPath), "instances-runtime", p.ID+".json")
}

func readInstanceReceipt(p ManagedInstance) (instanceProcessReceipt, error) {
	var receipt instanceProcessReceipt
	if !instanceIDPattern.MatchString(p.ID) {
		return receipt, errors.New("잘못된 서버 ID입니다")
	}
	b, err := os.ReadFile(instanceReceiptPath(p))
	if err != nil {
		return receipt, err
	}
	if len(b) > 16<<10 {
		return receipt, errors.New("실행 확인 기록이 너무 큽니다")
	}
	if err = json.Unmarshal(b, &receipt); err != nil {
		return receipt, err
	}
	if receipt.Schema != 1 || receipt.ID != p.ID || receipt.Directory != p.Dir || receipt.Nonce == "" {
		return receipt, errors.New("실행 확인 기록이 현재 서버와 일치하지 않습니다")
	}
	return receipt, nil
}

func writeInstanceReceipt(p ManagedInstance, r instanceProcessReceipt) error {
	path := instanceReceiptPath(p)
	if err := os.MkdirAll(filepath.Dir(path), 0700); err != nil {
		return err
	}
	b, err := json.Marshal(r)
	if err != nil {
		return err
	}
	f, err := os.CreateTemp(filepath.Dir(path), "receipt-*.tmp")
	if err != nil {
		return err
	}
	tmp := f.Name()
	defer os.Remove(tmp)
	if err = f.Chmod(0600); err == nil {
		_, err = f.Write(b)
	}
	if err == nil {
		err = f.Sync()
	}
	closeErr := f.Close()
	if err == nil {
		err = closeErr
	}
	if err != nil {
		return err
	}
	return os.Rename(tmp, path)
}

func prepareInstanceReceipt(p ManagedInstance) (instanceProcessReceipt, error) {
	var nonce [16]byte
	if _, err := rand.Read(nonce[:]); err != nil {
		return instanceProcessReceipt{}, err
	}
	r := instanceProcessReceipt{Schema: 1, ID: p.ID, Directory: p.Dir, Nonce: hex.EncodeToString(nonce[:]), State: "pending", RequestedAt: time.Now().UTC().Format(time.RFC3339Nano)}
	return r, writeInstanceReceipt(p, r)
}

func clearInstanceReceipt(p ManagedInstance, r instanceProcessReceipt) {
	current, err := readInstanceReceipt(p)
	if err != nil || current.Nonce != r.Nonce {
		return
	}
	_ = os.Remove(instanceReceiptPath(p))
}

// Receipts are evidence to refuse an unsafe second launch, never authority to
// terminate or adopt another PID. A stale/reused or inaccessible PID fails closed.
func instanceReceiptBlocks(p ManagedInstance) (bool, string) {
	if isScheduledProxy(p) {
		return false, ""
	}
	r, err := readInstanceReceipt(p)
	if os.IsNotExist(err) {
		return false, ""
	}
	if err != nil {
		return true, "이전 실행 기록을 확인하지 못했습니다. 중복 시작을 차단했습니다: " + err.Error()
	}
	if r.State != "running" || r.PID <= 0 {
		return true, "이전 시작 요청의 완료 여부를 확인할 수 없습니다. 기존 프로세스를 확인해 주세요"
	}
	alive, created, err := instanceProcessIdentity(r.PID)
	if err != nil {
		return true, "이전 서버 프로세스 확인 실패 · 중복 시작 차단"
	}
	if !alive {
		clearInstanceReceipt(p, r)
		return false, ""
	}
	if r.ProcessCreated != "" && created != "" && r.ProcessCreated != created {
		return true, fmt.Sprintf("이전 실행 PID %d가 재사용되었습니다. 실행 기록 확인이 필요합니다", r.PID)
	}
	return true, fmt.Sprintf("이전 Host가 실행한 프로세스(PID %d)가 남아 있습니다. 기존 콘솔에서 종료한 뒤 다시 시작하세요", r.PID)
}
